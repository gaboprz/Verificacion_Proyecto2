class mesh_pkt extends uvm_sequence_item;
  `uvm_object_utils(mesh_pkt)

  // Header/payload
  rand bit [7:0]            nxt_jump;
  rand bit [3:0]            target_row;
  rand bit [3:0]            target_col;
  rand bit                  mode;
  rand bit [`PAYLOAD_W-1:0] payload;

  // >>> NUEVO: jitter entre envíos (en ciclos de clk)
  rand int unsigned         idle_cycles;

  // Vector listo para el DUT
  bit [`PKG_SZ-1:0]         raw_pkt;

  // Observación (monitor)
  int unsigned              egress_id;

  // Constraints
  constraint c_nxt_no_bcast { nxt_jump != 8'hFF; }

  constraint c_external_device {
    ( (target_row == 0 && target_col inside {1,2,3,4}) ||
      (target_col == 0 && target_row inside {1,2,3,4}) ||
      (target_row == 5 && target_col inside {1,2,3,4}) ||
      (target_col == 5 && target_row inside {1,2,3,4})
    );
  }

  // >>> Rango simple y seguro para la holgura entre envíos
  //     (ajústalo a gusto o déjalo así)
  constraint c_idle { idle_cycles inside {[0:20]}; }

  function new(string name="mesh_pkt"); super.new(name); endfunction

  function void pack_bits();
    raw_pkt = '0;
    raw_pkt[`PKG_SZ-1   -: 8]  = nxt_jump;
    raw_pkt[`PKG_SZ-9   -: 4]  = target_row;
    raw_pkt[`PKG_SZ-13  -: 4]  = target_col;
    raw_pkt[`PKG_SZ-17]        = mode;
    if (`PAYLOAD_W > 0)
      raw_pkt[`PKG_SZ-18 -: `PAYLOAD_W] = payload;
  endfunction

  function void post_randomize(); 
    pack_bits(); 
  endfunction

  function string convert2str();
    return $sformatf("to[%0d,%0d] mode=%0b payload=0x%0h idle=%0dcy egress_id=%0d",
                     target_row, target_col, mode, payload, idle_cycles, egress_id);
  endfunction
endclass
