/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el scoreboard MEJORADO
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // Ingreso desde el driver (confirmado por pop==1)
  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;
  // Egreso desde el monitor (mesh_pkt con egress_id)
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // ========== MEJORADO: Estructura para tracking completo ==========
  typedef struct {
    int  target_row;
    int  target_col;
    bit  mode;
    bit [`PAYLOAD_W-1:0] payload;
    longint t_submit;
    longint t_received;    // Cuando llegó del monitor
    bit received;          // Si ya fue recibido por monitor
    int expected_egress;   // Puerto esperado de salida
    int actual_egress;     // Puerto real de salida
    bit matched;           // Si coincidió la verificación
  } packet_tracking_t;
  
  // Almacenamiento por payload (clave única)
  packet_tracking_t packet_db[string];
  
  // Colas para manejo temporal
  packet_tracking_t ingress_queue[$];
  packet_tracking_t egress_queue[$];

  // ========== MEJORADO: Contadores separados ==========
  int packets_ingressed = 0;    // Paquetes del driver
  int packets_egressed = 0;     // Paquetes del monitor  
  int packets_verified = 0;     // Paquetes verificados correctamente
  int packets_mismatched = 0;   // Paquetes con errores
  int expected_total_packets = 0;
  
  // Evento para notificar al test
  uvm_event test_completion_event;

  // ========== NUEVO: Mapeo de puertos esperados ==========
  int exp_port_from_rc[int][int]; // [row][col] -> dev_id esperado

  // Comparación en función egress match
  bit header_match;
  bit port_match;

  // Check Fase
  int pending_packets;

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
    
    // ========== NUEVO: Inicializar mapeo de puertos ==========
    initialize_expected_ports();
  endfunction

  // ========== NUEVO: Inicializar puertos esperados ==========
  function void initialize_expected_ports();
    // Para un mesh 4x4, los puertos se asignan así:
    // Filas 0-3, Columnas 0-3
    // Puerto = (fila * 4) + columna para los primeros 16
    for (int row = 0; row < `ROWS; row++) begin
      for (int col = 0; col < `COLUMNS; col++) begin
        exp_port_from_rc[row][col] = (row * `COLUMNS) + col;
      end
    end
    `uvm_info("SCB_INIT", "Mapeo de puertos esperados inicializado", UVM_LOW)
  endfunction

  // ========== MEJORADO: Método para que test configure expectativas ==========
  function void set_expected_packet_count(int expected_count);
    expected_total_packets = expected_count;
    packets_ingressed = 0;
    packets_egressed = 0;
    packets_verified = 0;
    packets_mismatched = 0;
    packet_db.delete();
    ingress_queue.delete();
    egress_queue.delete();
    `uvm_info("SCB_SYNC", $sformatf("Expecting %0d total packets from test", expected_total_packets), UVM_LOW)
  endfunction

  // ========== MEJORADO: Método para que test espere completación ==========
  task wait_for_completion();
    `uvm_info("SCB_SYNC", 
      $sformatf("Waiting for completion: ingress=%0d/%0d, egress=%0d, verified=%0d", 
                packets_ingressed, expected_total_packets, packets_egressed, packets_verified), 
      UVM_LOW)
    
    // Esperar hasta que se hayan procesado TODOS los paquetes
    while (packets_ingressed < expected_total_packets || 
           packets_egressed < packets_ingressed || 
           packets_verified < packets_ingressed) begin
      #100; // Pequeña espera para evitar busy waiting
      `uvm_info("SCB_WAIT", 
        $sformatf("Progress: ingress=%0d/%0d, egress=%0d, verified=%0d", 
                  packets_ingressed, expected_total_packets, packets_egressed, packets_verified), 
        UVM_HIGH)
    end
    
    `uvm_info("SCB_SYNC", 
      $sformatf("All packets processed: ingress=%0d, egress=%0d, verified=%0d, errors=%0d", 
                packets_ingressed, packets_egressed, packets_verified, packets_mismatched), 
      UVM_LOW)
    
    // Notificar al test que YA terminamos
    test_completion_event.trigger();
  endtask

  // ========== MEJORADO: DRIVER → SCB ==========
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    packet_tracking_t pkt_track;
    
    // Verificar que no sea un duplicado
    if (packet_db.exists(key)) begin
      `uvm_error("SCB_DUP", $sformatf("Paquete duplicado: payload=0x%0h", tr.payload))
      return;
    end
    
    // Llenar estructura de tracking
    pkt_track.target_row = tr.target_row;
    pkt_track.target_col = tr.target_col;
    pkt_track.mode = tr.mode;
    pkt_track.payload = tr.payload;
    pkt_track.t_submit = $time;
    pkt_track.received = 0;
    pkt_track.matched = 0;
    
    // Calcular puerto esperado de salida
    if (exp_port_from_rc.exists(tr.target_row) && 
        exp_port_from_rc[tr.target_row].exists(tr.target_col)) begin
      pkt_track.expected_egress = exp_port_from_rc[tr.target_row][tr.target_col];
    end else begin
      pkt_track.expected_egress = -1; // No se pudo determinar
      `uvm_warning("SCB_PORT", $sformatf("No se pudo determinar puerto esperado para [%0d,%0d]", 
                                         tr.target_row, tr.target_col))
    end
    
    // Guardar en base de datos
    packet_db[key] = pkt_track;
    packets_ingressed++;
    
    `uvm_info("SCB_IN",
      $sformatf("INGRESS: payload=0x%0h -> to[%0d,%0d] mode=%0b (exp_port=%0d) [%0d/%0d]",
                tr.payload, tr.target_row, tr.target_col, tr.mode, 
                pkt_track.expected_egress, packets_ingressed, expected_total_packets), 
      UVM_MEDIUM)
  endfunction

  // ========== MEJORADO: MONITOR → SCB ==========
  function void write_egress(mesh_pkt pkt);
    string key = $sformatf("%0h", pkt.payload);
    packet_tracking_t expected;
    
    // Verificar que el paquete fue enviado (existe en DB)
    if (!packet_db.exists(key)) begin
      `uvm_error("SCB_UNEXP", 
        $sformatf("Paquete inesperado: payload=0x%0h to[%0d,%0d] mode=%0b from port=%0d",
                  pkt.payload, pkt.target_row, pkt.target_col, pkt.mode, pkt.egress_id))
      packets_mismatched++;
      return;
    end
    
    // Obtener datos esperados
    expected = packet_db[key];
    
    // Verificar que no sea un duplicado
    if (expected.received) begin
      `uvm_error("SCB_DUP_EGRESS", 
        $sformatf("Paquete ya recibido: payload=0x%0h", pkt.payload))
      return;
    end
    
    // ========== COMPARACIÓN COMPLETA ==========
    header_match = 1;
    port_match = 1;
    
    // Verificar headers
    if (expected.target_row != pkt.target_row) begin
      `uvm_error("SCB_ROW", 
        $sformatf("Mismatch ROW: payload=0x%0h exp=%0d act=%0d", 
                  pkt.payload, expected.target_row, pkt.target_row))
      header_match = 0;
    end
    
    if (expected.target_col != pkt.target_col) begin
      `uvm_error("SCB_COL", 
        $sformatf("Mismatch COL: payload=0x%0h exp=%0d act=%0d", 
                  pkt.payload, expected.target_col, pkt.target_col))
      header_match = 0;
    end
    
    if (expected.mode != pkt.mode) begin
      `uvm_error("SCB_MODE", 
        $sformatf("Mismatch MODE: payload=0x%0h exp=%0d act=%0d", 
                  pkt.payload, expected.mode, pkt.mode))
      header_match = 0;
    end
    
    // Verificar puerto de salida
    if (expected.expected_egress != -1 && expected.expected_egress != pkt.egress_id) begin
      `uvm_error("SCB_PORT_MISMATCH", 
        $sformatf("Puerto incorrecto: payload=0x%0h exp_port=%0d act_port=%0d", 
                  pkt.payload, expected.expected_egress, pkt.egress_id))
      port_match = 0;
    end
    
    // Actualizar tracking
    packet_db[key].t_received = $time;
    packet_db[key].received = 1;
    packet_db[key].actual_egress = pkt.egress_id;
    packet_db[key].matched = header_match && port_match;
    
    packets_egressed++;
    
    if (header_match && port_match) begin
      packets_verified++;
      `uvm_info("SCB_OK",
        $sformatf("✓ VERIFIED: payload=0x%0h to[%0d,%0d] mode=%0b port=%0d [latency=%0t]",
                  pkt.payload, pkt.target_row, pkt.target_col, pkt.mode, pkt.egress_id,
                  $time - packet_db[key].t_submit),
        UVM_MEDIUM)
    end else begin
      packets_mismatched++;
      `uvm_error("SCB_MISMATCH",
        $sformatf("✗ MISMATCH: payload=0x%0h headers_ok=%0d port_ok=%0d", 
                  pkt.payload, header_match, port_match))
    end
    
    // Log intermedio
    `uvm_info("SCB_PROGRESS",
      $sformatf("Progress: ingress=%0d/%0d, egress=%0d, verified=%0d, errors=%0d",
                packets_ingressed, expected_total_packets, packets_egressed, 
                packets_verified, packets_mismatched),
      UVM_LOW)
  endfunction

  // ========== NUEVO: Reporte final detallado ==========
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    
    `uvm_info("SCB_REPORT", "=== SCOREBOARD FINAL REPORT ===", UVM_LOW)
    `uvm_info("SCB_REPORT", 
      $sformatf("Packets Ingressed:  %0d / %0d", packets_ingressed, expected_total_packets), 
      UVM_LOW)
    `uvm_info("SCB_REPORT", 
      $sformatf("Packets Egressed:   %0d", packets_egressed), 
      UVM_LOW)
    `uvm_info("SCB_REPORT", 
      $sformatf("Packets Verified:   %0d", packets_verified), 
      UVM_LOW)
    `uvm_info("SCB_REPORT", 
      $sformatf("Packets Mismatched: %0d", packets_mismatched), 
      UVM_LOW)
    
    if (packets_verified == expected_total_packets && packets_mismatched == 0) begin
      `uvm_info("SCB_REPORT", "*** ALL PACKETS VERIFIED SUCCESSFULLY ***", UVM_LOW)
    end else begin
      `uvm_error("SCB_REPORT", "*** VERIFICATION FAILURES DETECTED ***")
    end
    
    // Reporte de paquetes perdidos
    if (packets_egressed < packets_ingressed) begin
      `uvm_warning("SCB_REPORT", 
        $sformatf("Missing packets: %0d ingress but only %0d egress", 
                  packets_ingressed, packets_egressed))
    end
  endfunction
  
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // Verificar paquetes pendientes
    pending_packets = 0;
    foreach (packet_db[key]) begin
      if (!packet_db[key].received) begin
        pending_packets++;
        `uvm_error("SCB_PENDING",
          $sformatf("Paquete pendiente: payload=0x%0h to[%0d,%0d] mode=%0b (never received)",
                    packet_db[key].payload, packet_db[key].target_row, 
                    packet_db[key].target_col, packet_db[key].mode))
      end
    end
    
    if (pending_packets > 0) begin
      `uvm_error("SCB_PENDING", $sformatf("%0d packets never received by monitor", pending_packets))
    end
  endfunction
endclass