/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el scoreboard
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // Ingreso desde el driver (confirmado por pop==1)
  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;
  // Egreso desde el monitor (mesh_pkt con egress_id)
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // Esperados por payload (cola FIFO por clave)
  typedef struct {
    int  target_row;
    int  target_col;
    bit  mode;
    longint t_submit;
  } exp_t;
  typedef exp_t exp_q[$];
  exp_q by_key[string];

  // ========== NUEVO: Buffer para paquetes del monitor que llegan antes ==========
  mesh_pkt monitor_buffer[$];
  bit processing_monitor_buffer = 0;

  // (opcional) validar puerto exacto
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int]; // [row][col] -> dev_id esperado

  // ========== MODIFICADO: Sincronización basada en paquetes QUE SALEN ==========
  // Contadores para sincronización
  int total_packets_received_by_monitor = 0;  // Paquetes que SALIERON del DUT
  int total_packets_received_by_driver = 0;   // ========== NUEVO: Paquetes que ENTRARON al DUT ==========
  int expected_total_packets = 0;
  
  // --- Estadísticas de latencia por terminal ---
  longint sum_latency_per_dev[`NUM_DEVS];
  int     count_per_dev[`NUM_DEVS];
  
  // Evento para notificar al test
  uvm_event test_completion_event;

  int i;

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  // ========== MODIFICADO: Método para que test configure expectativas ==========
  function void set_expected_packet_count(int expected_count);
    expected_total_packets = expected_count;
    total_packets_received_by_monitor = 0;
    total_packets_received_by_driver = 0;  // ========== NUEVO: Reset contador driver ==========
    `uvm_info("SCB_SYNC", $sformatf("Expecting %0d total packets to EXIT the mesh", expected_total_packets), UVM_LOW)
  endfunction

  // ========== NUEVO: Método para consultar progreso actual ==========
  function int get_current_progress();
    return total_packets_received_by_monitor;
  endfunction

  // ========== NUEVO: Método para consultar paquetes recibidos por driver ==========
  function int get_driver_received_count();
    return total_packets_received_by_driver;
  endfunction

  // ========== NUEVO: Método para forzar finalización ==========
  function void force_completion();
    `uvm_info("SCB_SYNC", "Forzando finalización por timeout", UVM_LOW)
    test_completion_event.trigger();
  endfunction

  // ========== MODIFICADO: Método para que test espere completación ==========
  task wait_for_completion();
    `uvm_info("SCB_SYNC", $sformatf("Waiting for completion: %0d/%0d packets EXITED mesh", 
              total_packets_received_by_monitor, expected_total_packets), UVM_LOW)
    
    // Esperar hasta que TODOS los paquetes hayan SALIDO de la malla
    while (total_packets_received_by_monitor < expected_total_packets) begin
      test_completion_event.wait_trigger();
      // Romper el loop si ya alcanzamos el total
      if (total_packets_received_by_monitor >= expected_total_packets) break;
    end
    
    `uvm_info("SCB_SYNC", "All expected packets have EXITED the mesh", UVM_LOW)
  endtask

  // DRIVER → SCB - Registra paquetes esperados y procesa buffer
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; 
    e.target_row = tr.target_row; 
    e.target_col = tr.target_col; 
    e.mode = tr.mode; 
    e.t_submit = $time;
    by_key[key].push_back(e);
    
    // ========== NUEVO: Contar paquete recibido por driver ==========
    total_packets_received_by_driver++;
    
    `uvm_info("SCB_IN",
      $sformatf("Paquete ENTRÓ a la malla: payload=0x%0h -> r=%0d c=%0d m=%0b (cola_size=%0d, driver_total=%0d)",
                tr.payload, e.target_row, e.target_col, e.mode, by_key[key].size(), total_packets_received_by_driver), UVM_LOW)
    
    // ========== NUEVO: Procesar buffer de monitor después de registrar paquete ==========
    process_monitor_buffer();
  endfunction

  // MONITOR → SCB - MODIFICADO: Bufferizar paquetes si llegan antes
  function void write_egress(mesh_pkt pkt);
    // ========== NUEVO: Bufferizar paquete en lugar de procesar inmediatamente ==========
    monitor_buffer.push_back(pkt);
    `uvm_info("SCB_BUFFER", 
      $sformatf("Paquete bufferizado del monitor: payload=0x%0h (buffer_size=%0d)",
                pkt.payload, monitor_buffer.size()), UVM_HIGH)
    
    // Intentar procesar el buffer
    process_monitor_buffer();
  endfunction

  // ========== NUEVA FUNCIÓN: Procesar buffer de paquetes del monitor ==========
  function void process_monitor_buffer();
    if (processing_monitor_buffer) return; // Evitar recursión
    
    processing_monitor_buffer = 1;
    
    // Procesar todos los paquetes en el buffer que puedan ser matcheados
    i = 0;
    while (i < monitor_buffer.size()) begin
      mesh_pkt pkt = monitor_buffer[i];
      string key = $sformatf("%0h", pkt.payload);
      
      // Si el paquete del monitor tiene match en el driver, procesarlo
      if (by_key.exists(key) && by_key[key].size() > 0) begin
        exp_t expected;
        longint latency;

        expected = by_key[key].pop_front();
        monitor_buffer.delete(i); // Remover del buffer

        // Comparar header
        if (expected.target_row != pkt.target_row || expected.target_col != pkt.target_col || expected.mode != pkt.mode) begin
          `uvm_error("SCB_HDR",
            $sformatf("Header mismatch payload=0x%0h exp[r=%0d c=%0d m=%0b] act[r=%0d c=%0d m=%0b]",
                      pkt.payload, expected.target_row, expected.target_col, expected.mode,
                      pkt.target_row, pkt.target_col, pkt.mode))
        end else begin
          `uvm_info("SCB_OK",
            $sformatf("OK payload=0x%0h r=%0d c=%0d m=%0b (egress_id=%0d)",
                      pkt.payload, pkt.target_row, pkt.target_col, pkt.mode, pkt.egress_id),
            UVM_LOW)
        end

        // (opcional) puerto exacto
        if (check_port_exact) begin
          if (!(exp_port_from_rc.exists(pkt.target_row) &&
                exp_port_from_rc[pkt.target_row].exists(pkt.target_col)))
            `uvm_warning("SCB_PORT", $sformatf("Sin mapping para r=%0d c=%0d; omito check.",
                                               pkt.target_row, pkt.target_col))
          else begin
            int exp_dev = exp_port_from_rc[pkt.target_row][pkt.target_col];
            if (pkt.egress_id != exp_dev)
              `uvm_error("SCB_PORT",
                $sformatf("Puerto incorrecto payload=0x%0h: exp_dev=%0d act_dev=%0d (r=%0d c=%0d)",
                          pkt.payload, exp_dev, pkt.egress_id, pkt.target_row, pkt.target_col))
          end
        end

        // Calcular latencia
        latency = $time - expected.t_submit;

        // acumular por terminal
        sum_latency_per_dev[pkt.egress_id] += latency;
        count_per_dev[pkt.egress_id]++;

        // imprimir latencia individual
        `uvm_info("LAT",
          $sformatf("Latency dev[%0d] = %0d ns (payload=0x%0h)",
                    pkt.egress_id, latency, pkt.payload),
          UVM_LOW)

        // Contar paquete cuando SALE del DUT
        total_packets_received_by_monitor++;
        `uvm_info("SCB_SYNC", 
          $sformatf("Paquete SALIÓ de la malla: %0d/%0d completados", 
                    total_packets_received_by_monitor, expected_total_packets), UVM_MEDIUM)
        
        // Notificar al test cuando TODOS los paquetes hayan SALIDO
        if (total_packets_received_by_monitor >= expected_total_packets && expected_total_packets > 0) begin
          `uvm_info("SCB_SYNC", "¡TODOS los paquetes han salido de la malla! Disparando evento...", UVM_LOW)
          test_completion_event.trigger();
        end
      end else begin
        // No hay match todavía, mantener en buffer
        i++;
        `uvm_info("SCB_BUFFER", 
          $sformatf("Esperando paquete del driver para payload=0x%0h", pkt.payload), UVM_HIGH)
      end
    end
    
    processing_monitor_buffer = 0;
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // ========== NUEVO: Estadísticas completas de paquetes ==========
    `uvm_info("SCB_STATS", "===== PACKET STATISTICS =====", UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes ENTRADOS al DUT (driver): %0d", total_packets_received_by_driver), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes SALIDOS del DUT (monitor): %0d", total_packets_received_by_monitor), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes PERDIDOS en la malla: %0d", 
              total_packets_received_by_driver - total_packets_received_by_monitor), UVM_NONE)

    // Verificar paquetes pendientes en by_key
    foreach (by_key[key]) begin
      if (by_key[key].size() != 0) begin
        `uvm_error("SCB_PENDING",
          $sformatf("Quedaron %0d paquetes pendientes para payload=%s",
                    by_key[key].size(), key));
      end
    end

    // Verificar paquetes pendientes en el buffer del monitor
    if (monitor_buffer.size() > 0) begin
      `uvm_error("SCB_BUFFER_PENDING",
        $sformatf("Quedaron %0d paquetes en el buffer del monitor sin procesar", 
                  monitor_buffer.size()))
    end
    
    // --- Reporte de latencias promedio ---
    `uvm_info("LAT_SUMMARY", "===== LATENCY REPORT =====", UVM_NONE)

    for (int d = 0; d < `NUM_DEVS; d++) begin
      if (count_per_dev[d] > 0) begin
        longint avg = sum_latency_per_dev[d] / count_per_dev[d];
        `uvm_info("LAT_SUMMARY",
          $sformatf("Terminal %0d -> Avg latency = %0d ns (samples=%0d)",
                    d, avg, count_per_dev[d]),
          UVM_NONE)
      end
      else begin
        `uvm_info("LAT_SUMMARY",
          $sformatf("Terminal %0d -> Sin paquetes recibidos", d),
          UVM_NONE)
      end
    end
  endfunction
endclass