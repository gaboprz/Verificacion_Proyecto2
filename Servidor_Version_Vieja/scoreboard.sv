/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el scoreboard - VERSIÓN MEJORADA
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // ========== NUEVO: Estructura mejorada para tracking ==========
  typedef struct {
    int  target_row;
    int  target_col;
    bit  mode;
    longint t_submit;
    int  sequence_id;
    int  instance_id;
    bit  processed;
  } exp_t;
  
  exp_t expected_packets[$]; // ========== NUEVO: Cola en lugar de diccionario ==========
  mesh_pkt monitor_buffer[$];

  // Contadores
  int total_packets_received_by_monitor = 0;
  int total_packets_received_by_driver = 0;
  int expected_total_packets = 0;
  
  // Estadísticas
  longint sum_latency_per_dev[`NUM_DEVS];
  int     count_per_dev[`NUM_DEVS];
  
  // Evento para notificar al test
  uvm_event test_completion_event;

  // ========== NUEVO: Contadores de matching ==========
  int packets_matched = 0;
  int packets_in_buffer = 0;
  int packets_waiting_for_driver = 0;

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  function void set_expected_packet_count(int expected_count);
    expected_total_packets = expected_count;
    total_packets_received_by_monitor = 0;
    total_packets_received_by_driver = 0;
    packets_matched = 0;
    `uvm_info("SCB_SYNC", $sformatf("Expecting %0d total packets", expected_total_packets), UVM_LOW)
  endfunction

  function int get_current_progress();
    return total_packets_received_by_monitor;
  endfunction

  function int get_driver_received_count();
    return total_packets_received_by_driver;
  endfunction

  function void force_completion();
    `uvm_info("SCB_SYNC", "Forzando finalización por timeout", UVM_LOW)
    test_completion_event.trigger();
  endfunction

  task wait_for_completion();
    `uvm_info("SCB_SYNC", $sformatf("Waiting for completion: %0d/%0d packets", 
              total_packets_received_by_monitor, expected_total_packets), UVM_LOW)
    
    while (total_packets_received_by_monitor < expected_total_packets) begin
      test_completion_event.wait_trigger();
      if (total_packets_received_by_monitor >= expected_total_packets) break;
    end
    
    `uvm_info("SCB_SYNC", "All expected packets have EXITED the mesh", UVM_LOW)
  endtask

  // DRIVER → SCB - Versión mejorada
  function void write_ingress(mesh_pkt tr);
    exp_t e;
    e.target_row = tr.target_row;
    e.target_col = tr.target_col; 
    e.mode = tr.mode;
    e.t_submit = $time;
    e.sequence_id = tr.sequence_id;
    e.instance_id = tr.instance_id;
    e.processed = 0;
    
    expected_packets.push_back(e);
    total_packets_received_by_driver++;
    
    `uvm_info("SCB_IN",
      $sformatf("DRIVER: %s (total_driver=%0d, total_expected=%0d)",
                tr.convert2str(), total_packets_received_by_driver, expected_packets.size()), UVM_MEDIUM)
    
    // Intentar matching inmediato
    process_monitor_buffer();
  endfunction

  // MONITOR → SCB - Versión mejorada
  function void write_egress(mesh_pkt pkt);
    monitor_buffer.push_back(pkt);
    packets_in_buffer = monitor_buffer.size();
    
    `uvm_info("SCB_MON", 
      $sformatf("MONITOR: %s (buffer_size=%0d)", 
                pkt.convert2str(), monitor_buffer.size()), UVM_MEDIUM)
    
    // Intentar matching inmediato
    process_monitor_buffer();
  endfunction

  // ========== NUEVO: Procesamiento de buffer mejorado ==========
  function void process_monitor_buffer();
    int i = 0;
    int matches_found = 0;
    
    // Procesar todo el buffer
    while (i < monitor_buffer.size()) begin
      mesh_pkt pkt = monitor_buffer[i];
      int match_index = -1;
      
      // Buscar match en los paquetes esperados
      for (int j = 0; j < expected_packets.size(); j++) begin
        if (!expected_packets[j].processed &&
            expected_packets[j].target_row == pkt.target_row &&
            expected_packets[j].target_col == pkt.target_col &&
            expected_packets[j].mode == pkt.mode &&
            expected_packets[j].sequence_id == pkt.sequence_id) begin
          match_index = j;
          break;
        end
      end
      
      if (match_index != -1) begin
        // MATCH ENCONTRADO - Procesar paquete
        exp_t expected = expected_packets[match_index];
        longint latency = $time - expected.t_submit;
        
        `uvm_info("SCB_MATCH",
          $sformatf("MATCH: Monitor[seq=%0d inst=%0d] -> Driver[seq=%0d inst=%0d] Latency=%0d",
                    pkt.sequence_id, pkt.instance_id, expected.sequence_id, expected.instance_id, latency), UVM_LOW)

        // Marcar como procesado
        expected_packets[match_index].processed = 1;
        
        // Estadísticas
        sum_latency_per_dev[pkt.egress_id] += latency;
        count_per_dev[pkt.egress_id]++;
        total_packets_received_by_monitor++;
        packets_matched++;
        
        // Remover del buffer
        monitor_buffer.delete(i);
        matches_found++;
        
        `uvm_info("SCB_SYNC", 
          $sformatf("Progreso: %0d/%0d (matched=%0d)", 
                    total_packets_received_by_monitor, expected_total_packets, packets_matched), UVM_MEDIUM)
        
        // Notificar si completamos
        if (total_packets_received_by_monitor >= expected_total_packets && expected_total_packets > 0) begin
          `uvm_info("SCB_SYNC", "¡TODOS los paquetes procesados!", UVM_LOW)
          test_completion_event.trigger();
        end
      end else begin
        // No hay match, mantener en buffer
        i++;
      end
    end
    
    if (matches_found > 0) begin
      `uvm_info("SCB_BUFFER", 
        $sformatf("Procesados %0d paquetes del buffer. Buffer restante: %0d", 
                  matches_found, monitor_buffer.size()), UVM_HIGH)
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // ========== NUEVO: Reporte detallado ==========
    `uvm_info("SCB_STATS", "===== DETAILED PACKET STATISTICS =====", UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes ENTRADOS al DUT (driver): %0d", total_packets_received_by_driver), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes SALIDOS del DUT (monitor): %0d", total_packets_received_by_monitor), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes MATCHED: %0d", packets_matched), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes PERDIDOS: %0d", total_packets_received_by_driver - total_packets_received_by_monitor), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes en BUFFER: %0d", monitor_buffer.size()), UVM_NONE)
    `uvm_info("SCB_STATS", $sformatf("Paquetes esperados NO PROCESADOS: %0d", count_unprocessed_expected()), UVM_NONE)

    // Reportar paquetes no procesados
    report_unprocessed_packets();
    
    // Verificar consistencia
    if (total_packets_received_by_driver != total_packets_received_by_monitor) begin
      `uvm_error("SCB_MISMATCH", 
        $sformatf("DISCREPANCIA: Driver=%0d, Monitor=%0d, Diferencia=%0d",
                  total_packets_received_by_driver, total_packets_received_by_monitor,
                  total_packets_received_by_driver - total_packets_received_by_monitor))
    end

    if (monitor_buffer.size() > 0) begin
      `uvm_error("SCB_BUFFER_PENDING",
        $sformatf("Quedaron %0d paquetes en el buffer sin procesar", monitor_buffer.size()))
    end
    
    // Reporte de latencias
    `uvm_info("LAT_SUMMARY", "===== LATENCY REPORT =====", UVM_NONE)
    for (int d = 0; d < `NUM_DEVS; d++) begin
      if (count_per_dev[d] > 0) begin
        longint avg = sum_latency_per_dev[d] / count_per_dev[d];
        `uvm_info("LAT_SUMMARY",
          $sformatf("Terminal %0d -> Avg latency = %0d ns (samples=%0d)", d, avg, count_per_dev[d]), UVM_NONE)
      end else begin
        `uvm_info("LAT_SUMMARY", $sformatf("Terminal %0d -> Sin paquetes", d), UVM_NONE)
      end
    end
  endfunction

  // ========== NUEVO: Funciones auxiliares ==========
  function int count_unprocessed_expected();
    int count = 0;
    foreach (expected_packets[i]) begin
      if (!expected_packets[i].processed) count++;
    end
    return count;
  endfunction

  function void report_unprocessed_packets();
    int unprocessed = 0;
    foreach (expected_packets[i]) begin
      if (!expected_packets[i].processed) begin
        unprocessed++;
        `uvm_info("SCB_UNPROCESSED",
          $sformatf("Paquete no procesado: seq=%0d inst=%0d to[%0d,%0d] mode=%0b",
                    expected_packets[i].sequence_id, expected_packets[i].instance_id,
                    expected_packets[i].target_row, expected_packets[i].target_col, expected_packets[i].mode), UVM_NONE)
      end
    end
    if (unprocessed > 0) begin
      `uvm_error("SCB_UNPROCESSED", $sformatf("%0d paquetes del driver no fueron procesados", unprocessed))
    end
  endfunction
endclass