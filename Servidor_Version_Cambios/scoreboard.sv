`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // Puertos de análisis
  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // Estructura básica de paquete esperado
  typedef struct {
    int  target_row;
    int  target_col;
    bit  mode;
    longint t_submit;
    int driver_id;
  } exp_t;
  typedef exp_t exp_q[$];

  // Cola de esperados por clave
  exp_q by_key[string];

  // Buffer de paquetes que llegan primero desde el monitor
  mesh_pkt monitor_buffer[$];
  bit processing_monitor_buffer = 0;

  // Chequeo de puerto exacto
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int];

  // Contadores
  int total_packets_received_by_monitor = 0;  // paquetes que SALEN del DUT
  int expected_total_packets = 0;
  
  // Acumuladores de latencia por terminal
  longint sum_latency_per_dev[`NUM_DEVS];
  int     count_per_dev[`NUM_DEVS];
  
  // Evento para sincronizar con el test
  uvm_event test_completion_event;

  int     last_progress_count = 0;
  longint last_progress_time  = 0;
  bit     force_completion    = 0;
  int     packets_from_driver = 0;
  
  typedef struct {
    mesh_pkt pkt;
    int      driver_id;
    longint  send_time;
    longint  reception_time;
    longint  latency;
    bit      received;
    int      egress_id;
  } packet_tracking_t;
  
  packet_tracking_t packet_tracking[string];
  string packet_keys[$];

  int lost_packets;
  int received_packets;
  int i;

  // Manejo de archivo CSV
  string csv_filename = "scoreboard_report.csv";
  int    csv_file;

  // Para tracking simple de driver_id
  int current_driver_id = -1;

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp          = new("ingress_imp", this);
    egress_imp           = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  function void create_csv_file();
    csv_file = $fopen(csv_filename, "w");
    if (csv_file == 0) begin
      `uvm_error("SCB_CSV", $sformatf("No se pudo crear el archivo CSV: %s", csv_filename))
      return;
    end
    $fwrite(csv_file,
      "PacketID,Payload,SourceAgent,TargetRow,TargetCol,Mode,SendTime,ReceptionTime,Latency,DestinationAgent,Status\n");
    `uvm_info("SCB_CSV", $sformatf("Archivo CSV creado: %s", csv_filename), UVM_LOW)
  endfunction

  // Escribe una fila de paquete en el CSV
  function void write_packet_to_csv(string key, packet_tracking_t tracking);
    string  status;
    longint reception_time;
    longint latency;
    int     destination_agent;
    
    if (tracking.received) begin
      status           = "RECEIVED";
      reception_time   = tracking.reception_time;
      latency          = tracking.latency;
      destination_agent = tracking.egress_id;
    end else begin
      status           = "LOST";
      reception_time   = 0;
      latency          = 0;
      destination_agent = -1;
    end
    
    $fwrite(csv_file, "%s,0x%0h,%0d,%0d,%0d,%0d,%0t,%0t,%0t,%0d,%s\n",
            key,
            tracking.pkt.payload,
            tracking.driver_id,
            tracking.pkt.target_row,
            tracking.pkt.target_col,
            tracking.pkt.mode,
            tracking.send_time,
            reception_time,
            latency,
            destination_agent,
            status);
  endfunction

  // Escribe resumen global en el CSV
  function void write_summary_to_csv();
    $fwrite(csv_file, "\n\n=== SUMMARY ===\n");
    $fwrite(csv_file, "Metric,Value\n");
    $fwrite(csv_file, "TotalPacketsFromDrivers,%0d\n", packets_from_driver);
    $fwrite(csv_file, "TotalPacketsReceived,%0d\n", received_packets);
    $fwrite(csv_file, "TotalPacketsLost,%0d\n", lost_packets);
    $fwrite(csv_file, "SuccessRate,%.2f%%\n",
            (received_packets * 100.0) / packets_from_driver);
    
    $fwrite(csv_file, "\n=== AVERAGE LATENCY PER TERMINAL ===\n");
    $fwrite(csv_file, "Terminal,AvgLatency,ReceivedPackets\n");
    for (int d = 0; d < `NUM_DEVS; d++) begin
      if (count_per_dev[d] > 0) begin
        longint avg = sum_latency_per_dev[d] / count_per_dev[d];
        $fwrite(csv_file, "Terminal_%0d,%0t,%0d\n", d, avg, count_per_dev[d]);
      end else begin
        $fwrite(csv_file, "Terminal_%0d,No packets,0\n", d);
      end
    end
    
    $fwrite(csv_file, "\n=== TEST INFORMATION ===\n");
    $fwrite(csv_file, "ExpectedPackets,%0d\n", expected_total_packets);
    $fwrite(csv_file, "ActualReceived,%0d\n", total_packets_received_by_monitor);
    $fwrite(csv_file, "CompletionStatus,%s\n",
            force_completion ? "FORCED" : "NORMAL");
  endfunction


  function void close_csv_file();
    if (csv_file != 0) begin
      $fclose(csv_file);
      `uvm_info("SCB_CSV", $sformatf("Archivo CSV cerrado: %s", csv_filename), UVM_LOW)
    end
  endfunction

  function int get_current_progress();
    return total_packets_received_by_monitor;
  endfunction

  function int get_expected_total();
    return expected_total_packets;
  endfunction

  function int get_packets_from_driver();
    return packets_from_driver;
  endfunction

  // Fuerza el fin de la prueba
  function void force_test_completion();
    force_completion = 1;
    test_completion_event.trigger();
    `uvm_info("SCB_SYNC", "Test completion forced by test", UVM_LOW)
  endfunction

  // Indica si no hay progreso desde hace tiempo
  function bit is_stalled(longint current_time, longint stall_threshold);
    if (last_progress_time == 0) return 0;
    return ((current_time - last_progress_time) > stall_threshold) && 
           (total_packets_received_by_monitor == last_progress_count);
  endfunction

  // Se llama desde el test para indicar cuántos paquetes esperamos
  function void set_expected_packet_count(int expected_count);
    expected_total_packets             = expected_count;
    total_packets_received_by_monitor  = 0;
    packets_from_driver                = 0;
    last_progress_count                = 0;
    last_progress_time                 = 0;
    force_completion                   = 0;
    
    create_csv_file();
    
    `uvm_info("SCB_SYNC",
      $sformatf("Expecting %0d total packets to EXIT the mesh", expected_total_packets),
      UVM_LOW)
  endfunction

  // El test espera aquí hasta que terminen los paquetes o se fuerce fin
  task wait_for_completion(longint stall_threshold = 1000000);
    longint start_time = $time;
    `uvm_info("SCB_SYNC",
      $sformatf("Waiting for completion: %0d/%0d packets EXITED mesh",
                total_packets_received_by_monitor, expected_total_packets),
      UVM_LOW)
    
    while (total_packets_received_by_monitor < expected_total_packets &&
           !force_completion) begin
      test_completion_event.wait_trigger();
      
      if (is_stalled($time, stall_threshold) && !force_completion) begin
        `uvm_warning("SCB_STALL", 
          $sformatf("Progress stalled for %0t units. Current: %0d/%0d. Waiting for test decision...",
                    $time - last_progress_time,
                    total_packets_received_by_monitor,
                    expected_total_packets))
      end
      
      if (total_packets_received_by_monitor >= expected_total_packets) break;
    end
    
    if (force_completion)
      `uvm_info("SCB_SYNC", "Test completed by force", UVM_LOW)
    else
      `uvm_info("SCB_SYNC", "All expected packets have EXITED the mesh", UVM_LOW)
  endtask

  function string generate_unique_key(mesh_pkt pkt);
    return $sformatf("%0h_%0d_%0d_%0d",
                     pkt.payload, pkt.target_row, pkt.target_col, pkt.mode);
  endfunction

  // DRIVERal scoreboard: registra entrada a la malla
  function void write_ingress(mesh_pkt tr);
    string key = generate_unique_key(tr);
    exp_t  e; 
    e.target_row = tr.target_row; 
    e.target_col = tr.target_col; 
    e.mode       = tr.mode; 
    e.t_submit   = $time;
    
    // Driver “lógico” que envió el paquete
    e.driver_id = get_driver_id_from_context();
    
    packets_from_driver++;
    
    packet_tracking[key] = '{
      pkt:           tr,
      driver_id:     e.driver_id,
      send_time:     $time,
      reception_time: 0,
      latency:       0,
      received:      0,
      egress_id:     -1
    };
    packet_keys.push_back(key);
    
    by_key[key].push_back(e);

    `uvm_info("SCB_IN",
      $sformatf("Paquete ENTRÓ desde driver[%0d]: payload=0x%0h -> r=%0d c=%0d m=%0b (cola_size=%0d, total_driver=%0d)",
                e.driver_id, tr.payload, e.target_row, e.target_col, e.mode,
                by_key[key].size(), packets_from_driver),
      UVM_LOW)
    
    process_monitor_buffer();
  endfunction

  function int get_driver_id_from_context();
    static int driver_counter = 0;
    int driver_id = driver_counter;
    driver_counter = (driver_counter + 1) % `NUM_DEVS;
    return driver_id;
  endfunction

  // MONITOR al scoreboard: se guarda en buffer y luego se intenta empatar
  function void write_egress(mesh_pkt pkt);
    monitor_buffer.push_back(pkt);
    `uvm_info("SCB_BUFFER", 
      $sformatf("Paquete bufferizado del monitor: payload=0x%0h (buffer_size=%0d)",
                pkt.payload, monitor_buffer.size()),
      UVM_HIGH)
    
    last_progress_count = total_packets_received_by_monitor;
    last_progress_time  = $time;
    
    process_monitor_buffer();
  endfunction

  // Intenta emparejar paquetes del monitor con los esperados
  function void process_monitor_buffer();
    if (processing_monitor_buffer) return;
    
    processing_monitor_buffer = 1;
    
    i = 0;
    while (i < monitor_buffer.size()) begin
      mesh_pkt pkt = monitor_buffer[i];
      string  key = generate_unique_key(pkt);
      
      if (by_key.exists(key) && by_key[key].size() > 0) begin
        exp_t   expected;
        longint latency;

        expected = by_key[key].pop_front();
        monitor_buffer.delete(i);

        if (packet_tracking.exists(key)) begin
          packet_tracking[key].received       = 1;
          packet_tracking[key].reception_time = $time;
          packet_tracking[key].latency       = $time - expected.t_submit;
          packet_tracking[key].egress_id     = pkt.egress_id;
        end

        // Comparar encabezado básico
        if (expected.target_row != pkt.target_row ||
            expected.target_col != pkt.target_col ||
            expected.mode       != pkt.mode) begin
          `uvm_error("SCB_HDR",
            $sformatf("Header mismatch payload=0x%0h exp[r=%0d c=%0d m=%0b] act[r=%0d c=%0d m=%0b]",
                      pkt.payload,
                      expected.target_row, expected.target_col, expected.mode,
                      pkt.target_row, pkt.target_col, pkt.mode))
        end else begin
          `uvm_info("SCB_OK",
            $sformatf("OK payload=0x%0h r=%0d c=%0d m=%0b (egress_id=%0d)",
                      pkt.payload, pkt.target_row, pkt.target_col, pkt.mode, pkt.egress_id),
            UVM_LOW)
        end

        if (check_port_exact) begin
          if (!(exp_port_from_rc.exists(pkt.target_row) &&
                exp_port_from_rc[pkt.target_row].exists(pkt.target_col)))
            `uvm_warning("SCB_PORT",
              $sformatf("Sin mapping para r=%0d c=%0d; omito check.",
                        pkt.target_row, pkt.target_col))
          else begin
            int exp_dev = exp_port_from_rc[pkt.target_row][pkt.target_col];
            if (pkt.egress_id != exp_dev)
              `uvm_error("SCB_PORT",
                $sformatf("Puerto incorrecto payload=0x%0h: exp_dev=%0d act_dev=%0d (r=%0d c=%0d)",
                          pkt.payload, exp_dev, pkt.egress_id,
                          pkt.target_row, pkt.target_col))
          end
        end

        // Latencia por paquete
        latency = $time - expected.t_submit;

        sum_latency_per_dev[pkt.egress_id] += latency;
        count_per_dev[pkt.egress_id]++;

        `uvm_info("LAT",
          $sformatf("Latency dev[%0d] = %0d ns (payload=0x%0h)",
                    pkt.egress_id, latency, pkt.payload),
          UVM_LOW)

        // Contar paquete que SALIÓ del DUT
        total_packets_received_by_monitor++;
        
        last_progress_count = total_packets_received_by_monitor;
        last_progress_time  = $time;
        
        `uvm_info("SCB_SYNC", 
          $sformatf("Paquete SALIÓ de la malla: %0d/%0d completados",
                    total_packets_received_by_monitor, expected_total_packets),
          UVM_MEDIUM)
        
        test_completion_event.trigger();
        
        if (total_packets_received_by_monitor >= expected_total_packets &&
            expected_total_packets > 0) begin
          `uvm_info("SCB_SYNC",
                    "¡TODOS los paquetes han salido de la malla! Disparando evento...",
                    UVM_LOW)
          test_completion_event.trigger();
        end
      end else begin
        i++;
        `uvm_info("SCB_BUFFER", 
          $sformatf("Esperando paquete del driver para payload=0x%0h", pkt.payload),
          UVM_HIGH)
      end
    end
    
    processing_monitor_buffer = 0;
  endfunction

  // Genera reporte CSV completo
  function void generate_csv_report();
    `uvm_info("SCB_CSV", "Generando reporte CSV completo...", UVM_LOW)
    foreach (packet_keys[i]) begin
      string key = packet_keys[i];
      if (packet_tracking.exists(key))
        write_packet_to_csv(key, packet_tracking[key]);
    end
    write_summary_to_csv();
    `uvm_info("SCB_CSV", "Reporte CSV generado exitosamente", UVM_LOW)
  endfunction

  // Reporte detallado en el log (perdidos/recibidos)
  function void generate_detailed_report();
    lost_packets     = 0;
    received_packets = 0;
    
    `uvm_info("SCB_REPORT", "===== DETALLED PACKET REPORT =====", UVM_NONE)
    `uvm_info("SCB_REPORT",
              $sformatf("Packets from drivers: %0d", packets_from_driver), UVM_NONE)
    `uvm_info("SCB_REPORT",
              $sformatf("Packets received from monitors: %0d",
                        total_packets_received_by_monitor),
              UVM_NONE)
    
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
    
    `uvm_info("SCB_REPORT",
              $sformatf("Packets successfully received: %0d", received_packets), UVM_NONE)
    `uvm_info("SCB_REPORT",
              $sformatf("Packets lost: %0d", lost_packets), UVM_NONE)
    
    if (lost_packets > 0)
      `uvm_error("SCB_REPORT",
                 $sformatf("TEST FAILED: %0d packets were lost", lost_packets))
    else
      `uvm_info("SCB_REPORT",
                "TEST PASSED: All packets successfully received", UVM_NONE)
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    generate_detailed_report();
    generate_csv_report();
    close_csv_file();

    // Revisar si quedaron esperados sin emparejar
    foreach (by_key[key]) begin
      if (by_key[key].size() != 0) begin
        `uvm_error("SCB_PENDING",
          $sformatf("Quedaron %0d paquetes pendientes para payload=%s",
                    by_key[key].size(), key));
      end
    end

    // Revisar si quedaron paquetes sin procesar en el buffer
    if (monitor_buffer.size() > 0) begin
      `uvm_error("SCB_BUFFER_PENDING",
        $sformatf("Quedaron %0d paquetes en el buffer del monitor sin procesar",
                  monitor_buffer.size()))
    end
    
    // Resumen de latencias por terminal
    `uvm_info("LAT_SUMMARY", "===== LATENCY REPORT =====", UVM_NONE)

    for (int d = 0; d < `NUM_DEVS; d++) begin
      if (count_per_dev[d] > 0) begin
        longint avg = sum_latency_per_dev[d] / count_per_dev[d];
        `uvm_info("LAT_SUMMARY",
          $sformatf("Terminal %0d -> Avg latency = %0d ns (samples=%0d)",
                    d, avg, count_per_dev[d]),
          UVM_NONE)
      end else begin
        `uvm_info("LAT_SUMMARY",
          $sformatf("Terminal %0d -> Sin paquetes recibidos", d),
          UVM_NONE)
      end
    end
  endfunction
endclass
