// ---------------------------
// mesh_scoreboard.sv (corregido)
// ---------------------------

`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // Puertos de análisis:
  //  - ingress_imp: recibe lo que el DRIVER confirmó como aceptado (popin==1)
  //  - egress_imp : recibe lo que el MONITOR observó a la salida del DUT
  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // Esperados por payload (FIFO por clave):
  typedef struct {
    int      target_row;
    int      target_col;
    bit      mode;
    longint  t_submit;   // timestamp de ingreso (opcional, útil para latencia)
  } exp_t;
  typedef exp_t exp_q[$];
  exp_q by_key[string];

  // (Opcional) Validación de puerto exacto (row,col)->dev_id
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int];

  // ---- Sincronización y métricas ----
  int ingress_cnt = 0;                 // paquetes que entraron (driver→scb)
  int egress_cnt  = 0;                 // paquetes que salieron (monitor→scb)
  int expected_total_packets = 0;      // meta configurada por el test
  uvm_event test_completion_event;     // se dispara cuando egresos == esperados

  // -----------------------------------
  // Constructor
  // -----------------------------------
  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
    test_completion_event = new("test_completion_event");
  endfunction

  // -----------------------------------
  // Configurar expectativa desde el test
  // -----------------------------------
  function void set_expected_packet_count(int expected_count);
    expected_total_packets = expected_count;
    ingress_cnt = 0;
    egress_cnt  = 0;
    by_key.delete();
    `uvm_info("SCB_SYNC",
      $sformatf("Expecting %0d packets (reset counters)", expected_total_packets),
      UVM_LOW)
  endfunction

  // -----------------------------------
  // DRIVER → SCB (ingreso): encola esperado
  //  * No disparamos el evento aquí.
  // -----------------------------------
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; 
    e.target_row = tr.target_row;
    e.target_col = tr.target_col;
    e.mode       = tr.mode;
    e.t_submit   = $time;
    by_key[key].push_back(e);

    ingress_cnt++;

    `uvm_info("SCB_IN",
      $sformatf("Ingresado: payload=0x%0h -> r=%0d c=%0d m=%0b (ing=%0d/exp=%0d)",
                tr.payload, e.target_row, e.target_col, e.mode,
                ingress_cnt, expected_total_packets),
      UVM_LOW)
  endfunction

  // -----------------------------------
  // MONITOR → SCB (egreso): hace match y dispara evento al completar
  // -----------------------------------
  function void write_egress(mesh_pkt pkt);
    string key = $sformatf("%0h", pkt.payload);

    if (!by_key.exists(key) || by_key[key].size() == 0) begin
      `uvm_error("SCB_OUT",
        $sformatf("Salida inesperada: payload=0x%0h (cola vacía)", pkt.payload))
      return;
    end

    exp_t expected = by_key[key].pop_front();

    // Comparar header del paquete
    if (expected.target_row != pkt.target_row ||
        expected.target_col != pkt.target_col ||
        expected.mode       != pkt.mode) begin
      `uvm_error("SCB_HDR",
        $sformatf("Header mismatch payload=0x%0h exp[r=%0d c=%0d m=%0b] act[r=%0d c=%0d m=%0b]",
                  pkt.payload,
                  expected.target_row, expected.target_col, expected.mode,
                  pkt.target_row,  pkt.target_col,  pkt.mode))
    end else begin
      `uvm_info("SCB_OK",
        $sformatf("OK payload=0x%0h r=%0d c=%0d m=%0b (egress_id=%0d)",
                  pkt.payload, pkt.target_row, pkt.target_col, pkt.mode, pkt.egress_id),
        UVM_LOW)
    end

    // (Opcional) Verificar puerto exacto (mapping row/col → dev_id)
    if (check_port_exact) begin
      if (!(exp_port_from_rc.exists(pkt.target_row) &&
            exp_port_from_rc[pkt.target_row].exists(pkt.target_col))) begin
        `uvm_warning("SCB_PORT",
          $sformatf("Sin mapping para r=%0d c=%0d; omito check.", pkt.target_row, pkt.target_col))
      end
      else begin
        int exp_dev = exp_port_from_rc[pkt.target_row][pkt.target_col];
        if (pkt.egress_id != exp_dev)
          `uvm_error("SCB_PORT",
            $sformatf("Puerto incorrecto payload=0x%0h: exp_dev=%0d act_dev=%0d (r=%0d c=%0d)",
                      pkt.payload, exp_dev, pkt.egress_id, pkt.target_row, pkt.target_col))
      end
    end

    // Contar egreso y notificar completado cuando corresponda
    egress_cnt++;

    `uvm_info("SCB_SYNC",
      $sformatf("Egreso %0d/%0d (payload=0x%0h)",
                egress_cnt, expected_total_packets, pkt.payload),
      UVM_LOW)

    if (egress_cnt >= expected_total_packets && expected_total_packets > 0)
      test_completion_event.trigger();
  endfunction

  // -----------------------------------
  // Bloqueo para que el test espere al SCB
  // -----------------------------------
  task wait_for_completion();
    if (egress_cnt < expected_total_packets) begin
      `uvm_info("SCB_SYNC",
        $sformatf("Waiting for completion: %0d/%0d packets",
                  egress_cnt, expected_total_packets),
        UVM_LOW)
      test_completion_event.wait_trigger();
    end
    `uvm_info("SCB_SYNC", "All expected packets processed by scoreboard", UVM_LOW)
  endtask

  // -----------------------------------
  // check_phase: no deben quedar pendientes
  // -----------------------------------
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    if (ingress_cnt != egress_cnt) begin
      `uvm_error("SCB_MISMATCH",
        $sformatf("Ingresos=%0d vs Egresos=%0d", ingress_cnt, egress_cnt))
    end

    foreach (by_key[key]) begin
      if (by_key[key].size() != 0) begin
        `uvm_error("SCB_PENDING",
          $sformatf("Quedaron %0d paquetes pendientes para payload=%s",
                    by_key[key].size(), key))
      end
    end
  endfunction

endclass
