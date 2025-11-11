// Mantén estas declaraciones arriba:
`uvm_analysis_imp_decl(_ingress)
`uvm_analysis_imp_decl(_egress)

class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // Ingreso desde el driver (confirmado con pop==1)
  uvm_analysis_imp_ingress #(mesh_pkt, mesh_scoreboard) ingress_imp;

  // Egreso desde el monitor (ahora también mesh_pkt)
  uvm_analysis_imp_egress  #(mesh_pkt, mesh_scoreboard) egress_imp;

  // Estado esperado por payload
  typedef struct packed {
    int  target_row;
    int  target_col;
    bit  mode;
    longint t_submit;
  } exp_t;
  typedef exp_t exp_q[$];
  exp_q by_key[string];

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
  endfunction

  // DRIVER → SCB (ingreso)
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; e.target_row = tr.target_row; e.target_col = tr.target_col; e.mode = tr.mode; e.t_submit = $time;
    by_key[key].push_back(e);
    `uvm_info("SCB_IN",
      $sformatf("Esperado: payload=0x%0h -> r=%0d c=%0d mode=%0b", tr.payload, e.target_row, e.target_col, e.mode),
      UVM_LOW)
  endfunction

  // MONITOR → SCB (egreso)  // <<— ahora recibe mesh_pkt
  function void write_egress(mesh_pkt pkt);
    string key = $sformatf("%0h", pkt.payload);

    if (!by_key.exists(key) || by_key[key].size()==0) begin
      `uvm_error("SCB_OUT", $sformatf("Salida inesperada: payload=0x%0h", pkt.payload))
      return;
    end

    exp_t exp = by_key[key].pop_front();

    if (exp.target_row != pkt.target_row || exp.target_col != pkt.target_col || exp.mode != pkt.mode) begin
      `uvm_error("SCB_HDR",
        $sformatf("Header mismatch payload=0x%0h exp[r=%0d c=%0d m=%0b] act[r=%0d c=%0d m=%0b]",
                  pkt.payload, exp.target_row, exp.target_col, exp.mode,
                  pkt.target_row, pkt.target_col, pkt.mode))
    end else begin
      `uvm_info("SCB_OK",
        $sformatf("OK payload=0x%0h r=%0d c=%0d mode=%0b", pkt.payload, pkt.target_row, pkt.target_col, pkt.mode),
        UVM_LOW)
    end
  endfunction
endclass
