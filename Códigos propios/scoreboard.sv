class mesh_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mesh_scoreboard)

  // TLM inputs
  uvm_analysis_imp #(mesh_pkt , mesh_scoreboard) ingress_imp; // desde driver
  uvm_analysis_imp #(main_pck , mesh_scoreboard) egress_imp;  // desde monitor

  // (Opcional) check del puerto exacto; configúralo en build si quieres
  bit check_port_exact = 0;
  int exp_port_from_rc[int][int]; // mapping [row][col] -> dev_id esperado

  // Estado: esperados por payload (cola por clave)
  typedef struct packed {
    int target_row;
    int target_col;
    bit mode;
    longint t_submit;
  } exp_t;
  typedef exp_t exp_q[$];
  exp_q by_key[string];

  function new(string name="mesh_scoreboard", uvm_component parent=null);
    super.new(name, parent);
    ingress_imp = new("ingress_imp", this);
    egress_imp  = new("egress_imp" , this);
  endfunction

  // ---------- DRIVER → SCB: paquete aceptado por DUT (ingreso) ----------
  function void write(mesh_pkt tr);
    string key = $sformatf("%0h", tr.payload);
    exp_t e; e.target_row = tr.target_row; e.target_col = tr.target_col;
    e.mode = tr.mode; e.t_submit = $time;
    by_key[key].push_back(e);
    `uvm_info("SCB_IN", $sformatf("Esperando payload=0x%0h -> row=%0d col=%0d mode=%0b",
                                  tr.payload, e.target_row, e.target_col, e.mode), UVM_LOW)
  endfunction

  // ---------- MONITOR → SCB: salida observada ----------
  function void write(main_pck pkt);
    // Desempacar header de data_out
    bit [39:0] bits = pkt.data_out;

    bit [7:0] nxt_jump   = bits[`PKG_SZ-1   -: 8];
    bit [3:0] target_row = bits[`PKG_SZ-9   -: 4];
    bit [3:0] target_col = bits[`PKG_SZ-13  -: 4];
    bit       mode       = bits[`PKG_SZ-17];

    bit [`PAYLOAD_W-1:0] payload;
    if (`PAYLOAD_W > 0) payload = bits[`PKG_SZ-18 -: `PAYLOAD_W];

    string key = $sformatf("%0h", payload);

    if (!by_key.exists(key) || by_key[key].size()==0) begin
      `uvm_error("SCB_OUT", $sformatf(
        "Salida inesperada: payload=0x%0h en dev=%0d (no hay matching en esperados)",
        payload, pkt.dev_id))
      return;
    end

    exp_t exp = by_key[key].pop_front();

    // Validar header 
    if (exp.target_row != target_row || exp.target_col != target_col || exp.mode != mode) begin
      `uvm_error("SCB_HDR", $sformatf(
        "Header mismatch payload=0x%0h exp[row=%0d col=%0d mode=%0b] act[row=%0d col=%0d mode=%0b]",
        payload, exp.target_row, exp.target_col, exp.mode,
        target_row, target_col, mode))
    end else begin
      `uvm_info("SCB_OK", $sformatf(
        "OK payload=0x%0h row=%0d col=%0d mode=%0b -> dev=%0d nxt=0x%0h",
        payload, target_row, target_col, mode, pkt.dev_id, nxt_jump), UVM_LOW)
    end

    if (check_port_exact) begin
      if (!(exp_port_from_rc.exists(target_row) && exp_port_from_rc[target_row].exists(target_col))) begin
        `uvm_warning("SCB_PORT", $sformatf(
          "Sin mapping para row=%0d col=%0d; omito check.", target_row, target_col))
      end else begin
        int exp_port = exp_port_from_rc[target_row][target_col];
        if (pkt.dev_id != exp_port) begin
          `uvm_error("SCB_PORT", $sformatf(
            "Puerto incorrecto payload=0x%0h: exp=%0d act=%0d (row=%0d col=%0d)",
            payload, exp_port, pkt.dev_id, target_row, target_col))
        end
      end
    end
  endfunction
endclass
