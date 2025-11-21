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

  // (opcional) validar puerto exacto
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int]; // [row][col] -> dev_id esperado

  // ========== NUEVO: Sincronización con test ==========
  // Contadores para sincronización
  int total_packets_received = 0;
  int expected_total_packets = 0;
  
  // Evento para notificar al test
  uvm_event test_completion_event;
  
  // Semáforo para acceso seguro a contadores
  semaphore counter_sem = new(1);

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  // ========== NUEVO: Método para que test configure expectativas ==========
  function void set_expected_packet_count(int expected_count);
    counter_sem.get(1);
    expected_total_packets = expected_count;
    total_packets_received = 0;
    `uvm_info("SCB_SYNC", $sformatf("Expecting %0d total packets from test", expected_total_packets), UVM_LOW)
    counter_sem.put(1);
  endfunction

  // ========== NUEVO: Método para que test espere completación ==========
  task wait_for_completion();
    `uvm_info("SCB_SYNC", $sformatf("Waiting for completion: %0d/%0d packets", 
              total_packets_received, expected_total_packets), UVM_LOW)
    
    // Esperar hasta que recibamos todos los paquetes esperados
    while (total_packets_received < expected_total_packets) begin
      @(posedge test_completion_event);
    end
    
    `uvm_info("SCB_SYNC", "All expected packets processed by scoreboard", UVM_LOW)
  endtask

  // DRIVER → SCB - MODIFICADO para contar paquetes
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; 
    e.target_row = tr.target_row; 
    e.target_col = tr.target_col; 
    e.mode = tr.mode; 
    e.t_submit = $time;
    by_key[key].push_back(e);
    
    // ========== NUEVO: Contar paquete recibido ==========
    counter_sem.get(1);
    total_packets_received++;
    `uvm_info("SCB_IN",
      $sformatf("Esperado: payload=0x%0h -> r=%0d c=%0d m=%0b (recibidos=%0d/esperados=%0d)",
                tr.payload, e.target_row, e.target_col, e.mode, 
                total_packets_received, expected_total_packets), UVM_LOW)
    
    // Notificar al test si hemos alcanzado el total esperado
    if (total_packets_received >= expected_total_packets && expected_total_packets > 0) begin
      test_completion_event.trigger();
    end
    counter_sem.put(1);
  endfunction

  // MONITOR → SCB
  function void write_egress(mesh_pkt pkt);
    string key = $sformatf("%0h", pkt.payload);
    exp_t expected;

    if (!by_key.exists(key) || by_key[key].size()==0) begin
      `uvm_error("SCB_OUT", $sformatf("Salida inesperada: payload=0x%0h (cola vacía)", pkt.payload))
      return;
    end

    expected = by_key[key].pop_front();

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
  endfunction
  
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    foreach (by_key[key]) begin
      if (by_key[key].size() != 0) begin
        `uvm_error("SCB_PENDING",
          $sformatf("Quedaron %0d paquetes pendientes para payload=%s",
                    by_key[key].size(), key));
      end
    end
  endfunction
endclass