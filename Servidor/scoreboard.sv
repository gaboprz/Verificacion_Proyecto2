/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el scoreboard
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`include "mesh_defines.svh"

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

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
  endfunction

  // DRIVER → SCB
  function void write_ingress(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; e.target_row = tr.target_row; e.target_col = tr.target_col; e.mode = tr.mode; e.t_submit = $time;
    by_key[key].push_back(e);
    `uvm_info("SCB_IN",
      $sformatf("Esperado: payload=0x%0h -> r=%0d c=%0d m=%0b (pend=%0d)",
                tr.payload, e.target_row, e.target_col, e.mode, by_key[key].size()), UVM_LOW)
  endfunction

  // MONITOR → SCB
  function void write_egress(mesh_pkt pkt);
    string key = $sformatf("%0h", pkt.payload);

    if (!by_key.exists(key) || by_key[key].size()==0) begin
      `uvm_error("SCB_OUT", $sformatf("Salida inesperada: payload=0x%0h (cola vacía)", pkt.payload))
      return;
    end

    exp_t exp;
    exp = by_key[key].pop_front();

    // Comparar header
    if (exp.target_row != pkt.target_row || exp.target_col != pkt.target_col || exp.mode != pkt.mode) begin
      `uvm_error("SCB_HDR",
        $sformatf("Header mismatch payload=0x%0h exp[r=%0d c=%0d m=%0b] act[r=%0d c=%0d m=%0b]",
                  pkt.payload, exp.target_row, exp.target_col, exp.mode,
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
endclass
