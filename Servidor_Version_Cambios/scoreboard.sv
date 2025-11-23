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
    int driver_id;  // Nuevo: ID del driver que envió el paquete
  } exp_t;
  typedef exp_t exp_q[$];
  exp_q by_key[string];

  // Buffer para paquetes del monitor que llegan antes
  mesh_pkt monitor_buffer[$];
  bit processing_monitor_buffer = 0;

  // (opcional) validar puerto exacto
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int]; // [row][col] -> dev_id esperado

  // Contadores para sincronización
  int total_packets_received_by_monitor = 0;  // Paquetes que SALIERON del DUT
  int expected_total_packets = 0;
  
  // --- Estadísticas de latencia por terminal ---
  longint sum_latency_per_dev[`NUM_DEVS];
  int     count_per_dev[`NUM_DEVS];
  
  // Evento para notificar al test
  uvm_event test_completion_event;

  // ========== NUEVO: Variables para monitoreo de progreso ==========
  int last_progress_count = 0;
  longint last_progress_time = 0;
  bit force_completion = 0;
  int packets_from_driver = 0;
  
  // ========== NUEVO: Estructuras para tracking de paquetes ==========
  typedef struct {
    mesh_pkt pkt;
    int driver_id;
    longint send_time;
    bit received;
  } packet_tracking_t;
  
  packet_tracking_t packet_tracking[string]; // key -> tracking info
  string packet_keys[$]; // Para mantener orden

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  // ========== NUEVO: Métodos para comunicación con test ==========
  function int get_current_progress();
    return total_packets_received_by_monitor;
  endfunction

  function int get_expected_total();
    return expected_total_packets;
  endfunction

  function int get_packets_from_driver();
    return packets_from_driver;
  endfunction

  function void force_test_completion();
    force_completion = 1;
    test_completion_event.trigger();
    `uvm_info("SCB_SYNC", "Test completion forced by test", UVM_LOW)
  endfunction

  function bit is_stalled(longint current_time, longint stall_threshold);
    if (last_progress_time == 0) return 0;
    return ((current_time - last_progress_time) > stall_threshold) && 
           (total_packets_received_by_monitor == last_progress_count);
  endfunction

  // Método para que test configure expectativas
  function void set_expected_packet_count(int expected_count);
    expected_total_packets = expected_count;
    total_packets_received_by_monitor = 0;
    packets_from_driver = 0;
    last_progress_count = 0;
    last_progress_time = 0;
    force_completion = 0;
    `uvm_info("SCB_SYNC", $sformatf("Expecting %0d total packets to EXIT the mesh", expected_total_packets), UVM_LOW)
  endfunction

  // ========== MEJORADO: Método para que test espere completación ==========
  task wait_for_completion(longint stall_threshold = 1000000);
    longint start_time = $time;
    `uvm_info("SCB_SYNC", $sformatf("Waiting for completion: %0d/%0d packets EXITED mesh", 
              total_packets_received_by_monitor, expected_total_packets), UVM_LOW)
    
    // Esperar hasta que TODOS los paquetes hayan SALIDO de la malla o hasta timeout
    while (total_packets_received_by_monitor < expected_total_packets && !force_completion) begin
      test_completion_event.wait_trigger();
      
      // Verificar si debemos forzar completación por stall
      if (is_stalled($time, stall_threshold) && !force_completion) begin
        `uvm_warning("SCB_STALL", 
          $sformatf("Progress stalled for %0t units. Current: %0d/%0d. Waiting for test decision...",
                   $time - last_progress_time, total_packets_received_by_monitor, expected_total_packets))
        // No forzamos automáticamente, esperamos que el test decida
      end
      
      if (total_packets_received_by_monitor >= expected_total_packets) break;
    end
    
    if (force_completion) begin
      `uvm_info("SCB_SYNC", "Test completed by force", UVM_LOW)
    end else begin
      `uvm_info("SCB_SYNC", "All expected packets have EXITED the mesh", UVM_LOW)
    end
  endtask

  // Función para generar una clave única
  function string generate_unique_key(mesh_pkt pkt);
    return $sformatf("%0h_%0d_%0d_%0d", pkt.payload, pkt.target_row, pkt.target_col, pkt.mode);
  endfunction

  // DRIVER → SCB - Registra paquetes esperados y procesa buffer
  function void write_ingress(mesh_pkt tr);
    string key = generate_unique_key(tr);
    exp_t e; 
    e.target_row = tr.target_row; 
    e.target_col = tr.target_col; 
    e.mode = tr.mode; 
    e.t_submit = $time;
    e.driver_id = -1; // Se actualizará si tenemos info del driver
    
    // ========== NUEVO: Trackeo de paquetes del driver ==========
    packets_from_driver++;
    
    // Guardar información de tracking
    packet_tracking[key] = '{pkt: tr, driver_id: -1, send_time: $time, received: 0};
    packet_keys.push_back(key);
    
    by_key[key].push_back(e);

    int lost_packets;
    int received_packets;
    
    `uvm_info("SCB_IN",
      $sformatf("Paquete ENTRÓ a la malla: payload=0x%0h -> r=%0d c=%0d m=%0b (cola_size=%0d, total_driver=%0d)",
                tr.payload, e.target_row, e.target_col, e.mode, by_key[key].size(), packets_from_driver), UVM_LOW)
    
    // Procesar buffer de monitor después de registrar paquete
    process_monitor_buffer();
  endfunction

  // MONITOR → SCB - Bufferizar paquetes si llegan antes
  function void write_egress(mesh_pkt pkt);
    // Bufferizar paquete
    monitor_buffer.push_back(pkt);
    `uvm_info("SCB_BUFFER", 
      $sformatf("Paquete bufferizado del monitor: payload=0x%0h (buffer_size=%0d)",
                pkt.payload, monitor_buffer.size()), UVM_HIGH)
    
    // Actualizar progreso
    last_progress_count = total_packets_received_by_monitor;
    last_progress_time = $time;
    
    // Intentar procesar el buffer
    process_monitor_buffer();
  endfunction

  // Función para procesar buffer de paquetes del monitor
  function void process_monitor_buffer();
    if (processing_monitor_buffer) return;
    
    processing_monitor_buffer = 1;
    
    int i = 0;
    while (i < monitor_buffer.size()) begin
      mesh_pkt pkt = monitor_buffer[i];
      string key = generate_unique_key(pkt);
      
      if (by_key.exists(key) && by_key[key].size() > 0) begin
        exp_t expected;
        longint latency;

        expected = by_key[key].pop_front();
        monitor_buffer.delete(i);

        // ========== NUEVO: Actualizar tracking ==========
        if (packet_tracking.exists(key)) begin
          packet_tracking[key].received = 1;
        end

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

        `uvm_info("LAT",
          $sformatf("Latency dev[%0d] = %0d ns (payload=0x%0h)",
                    pkt.egress_id, latency, pkt.payload),
          UVM_LOW)

        // Contar paquete cuando SALE del DUT
        total_packets_received_by_monitor++;
        
        // Actualizar progreso
        last_progress_count = total_packets_received_by_monitor;
        last_progress_time = $time;
        
        `uvm_info("SCB_SYNC", 
          $sformatf("Paquete SALIÓ de la malla: %0d/%0d completados", 
                    total_packets_received_by_monitor, expected_total_packets), UVM_MEDIUM)
        
        // Notificar progreso
        test_completion_event.trigger();
        
        if (total_packets_received_by_monitor >= expected_total_packets && expected_total_packets > 0) begin
          `uvm_info("SCB_SYNC", "¡TODOS los paquetes han salido de la malla! Disparando evento...", UVM_LOW)
          test_completion_event.trigger();
        end
      end else begin
        i++;
        `uvm_info("SCB_BUFFER", 
          $sformatf("Esperando paquete del driver para payload=0x%0h", pkt.payload), UVM_HIGH)
      end
    end
    
    processing_monitor_buffer = 0;
  endfunction

  // ========== NUEVO: Función para reporte detallado ==========
  function void generate_detailed_report();
    lost_packets = 0;
    received_packets = 0;
    
    `uvm_info("SCB_REPORT", "===== DETALLED PACKET REPORT =====", UVM_NONE)
    `uvm_info("SCB_REPORT", $sformatf("Packets from drivers: %0d", packets_from_driver), UVM_NONE)
    `uvm_info("SCB_REPORT", $sformatf("Packets received from monitors: %0d", total_packets_received_by_monitor), UVM_NONE)
    
    // Reportar paquetes perdidos
    foreach (packet_keys[i]) begin
      string key = packet_keys[i];
      if (packet_tracking.exists(key) && !packet_tracking[key].received) begin
        lost_packets++;
        `uvm_error("SCB_LOST", 
          $sformatf("Paquete PERDIDO: payload=0x%0h, target=[%0d,%0d], mode=%0d, enviado en t=%0d",
                   packet_tracking[key].pkt.payload,
                   packet_tracking[key].pkt.target_row,
                   packet_tracking[key].pkt.target_col,
                   packet_tracking[key].pkt.mode,
                   packet_tracking[key].send_time))
      end else begin
        received_packets++;
      end
    end
    
    `uvm_info("SCB_REPORT", $sformatf("Packets successfully received: %0d", received_packets), UVM_NONE)
    `uvm_info("SCB_REPORT", $sformatf("Packets lost: %0d", lost_packets), UVM_NONE)
    
    if (lost_packets > 0) begin
      `uvm_error("SCB_REPORT", $sformatf("TEST FAILED: %0d packets were lost", lost_packets))
    end else begin
      `uvm_info("SCB_REPORT", "TEST PASSED: All packets successfully received", UVM_NONE)
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // Generar reporte detallado
    generate_detailed_report();

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