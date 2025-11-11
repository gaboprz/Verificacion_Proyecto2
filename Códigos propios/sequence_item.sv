`include "uvm_macros.svh"
import uvm_pkg::*;

// --- Parámetros---
`define PKG_SZ      40
`define ROWS        4
`define COLUMNS     4
`define PAYLOAD_W  (`PKG_SZ - 17)

// =========================
// Sequence item
// =========================
class mesh_pkt extends uvm_sequence_item;


  `uvm_object_utils(mesh_pkt)
  // Campos del paquete
  rand bit [7:0]            nxt_jump;
  rand bit [3:0]            target_row;
  rand bit [3:0]            target_col;
  rand bit                  mode;
  rand bit [`PAYLOAD_W-1:0] payload;

  // Vector listo para el DUT
  bit [`PKG_SZ-1:0]         raw_pkt;

  function new(string name="mesh_pkt");
    super.new(name);
  endfunction

  // Empaquetar para el DUT
  function void pack_bits();
    raw_pkt = '0;
    // [X-1 : X-8]   = nxt_jump
    raw_pkt[`PKG_SZ-1   -: 8]  = nxt_jump;
    // [X-9 : X-12]  = target_row
    raw_pkt[`PKG_SZ-9   -: 4]  = target_row;
    // [X-13: X-16]  = target_col
    raw_pkt[`PKG_SZ-13  -: 4]  = target_col;
    // [X-17]        = mode
    raw_pkt[`PKG_SZ-17]        = mode;
    // [X-18:0]      = payload
    if (`PAYLOAD_W > 0)
      raw_pkt[`PKG_SZ-18 -: `PAYLOAD_W] = payload;
  endfunction

  function void post_randomize();
    pack_bits();
  endfunction

  function string convert2str();
    return $sformatf("to[%0d,%0d] mode=%0b payload=0x%0h",
                     target_row, target_col, mode, payload);
  endfunction
endclass
