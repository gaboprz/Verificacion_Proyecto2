class mesh_pkt extends uvm_sequence_item;
  `uvm_object_utils(mesh_pkt)

  // Campos principales del paquete
  rand bit [7:0]            nxt_jump;      // control del paquete 
  rand bit [3:0]            target_row;    // fila de destino
  rand bit [3:0]            target_col;    // columna de destino
  rand bit                  mode;          // 0: Row-First, 1: Column-First
  rand bit [`PAYLOAD_W-1:0] payload;       // datos que se quieren enviar

  // Espera en ciclos antes de inyectar este paquete
  rand int unsigned         idle_cycles;

  // Versión empaquetada para ir directo al puerto del DUT
  bit [`PKG_SZ-1:0]         raw_pkt;

  // Marca si el destino es un terminal válido o no
  rand bit                  dest_valid;

  // Lado de salida por donde se observó el paquete (lo rellena el monitor)
  int unsigned              egress_id;


  // No usar el valor reservado para broadcast en nxt_jump
  constraint c_nxt_no_bcast { nxt_jump != 8'hFF; }

  // Limitar filas y columnas 
  constraint c_rc_range {
    target_row inside {[0:5]};
    target_col inside {[0:5]};
  }

  // Si dest_valid=1, el destino debe estar en el borde
  // Si dest_valid=0, el destino cae fuera de esas coordenadas
  constraint c_dest {
    if (dest_valid)
      (
        (target_row == 0 && target_col inside {1,2,3,4}) ||
        (target_col == 0 && target_row inside {1,2,3,4}) ||
        (target_row == 5 && target_col inside {1,2,3,4}) ||
        (target_col == 5 && target_row inside {1,2,3,4})
      );
    else
      !(
        (target_row == 0 && target_col inside {1,2,3,4}) ||
        (target_col == 0 && target_row inside {1,2,3,4}) ||
        (target_row == 5 && target_col inside {1,2,3,4}) ||
        (target_col == 5 && target_row inside {1,2,3,4})
      );
  }

  // Pequeño rango de espera entre paquetes
  constraint c_idle { idle_cycles inside {[0:20]}; }

  function new(string name="mesh_pkt");
    super.new(name);
  endfunction

  // Empaqueta los campos del encabezado/payload en raw_pkt
  function void pack_bits();
    raw_pkt = '0;
    raw_pkt[`PKG_SZ-1   -: 8]  = nxt_jump;
    raw_pkt[`PKG_SZ-9   -: 4]  = target_row;
    raw_pkt[`PKG_SZ-13  -: 4]  = target_col;
    raw_pkt[`PKG_SZ-17]        = mode;
    if (`PAYLOAD_W > 0)
      raw_pkt[`PKG_SZ-18 -: `PAYLOAD_W] = payload;
  endfunction

  // Cada vez que se randomiza el objeto, se vuelve a construir raw_pkt
  function void post_randomize(); 
    pack_bits(); 
  endfunction

  function string convert2str();
    return $sformatf("to[%0d,%0d] mode=%0b payload=0x%0h idle=%0dcy egress_id=%0d",
                     target_row, target_col, mode, payload, idle_cycles, egress_id);
  endfunction

endclass