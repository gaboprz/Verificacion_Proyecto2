/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se definen los paquetes necesarios para las transacciones
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// Clase de transacción, paquete de entrada y salida de routers exteriores
// --- Transacción que publica el MONITOR (egreso) ---
class main_pck extends uvm_sequence_item;
  // Entrada (solo para snapshot/debug)
  rand logic [39:0] data_out_i_in;
  rand bit          pndng_i_in;
  rand bit          pop;

  // Salida observada del DUT
  logic [39:0]      data_out;
  bit               pndng;
  bit               popin;

  // Desde qué puerto/terminal salió.
  int unsigned      dev_id;

  `uvm_object_utils_begin(main_pck)
    `uvm_field_int(data_out_i_in, UVM_ALL_ON)
    `uvm_field_int(pndng_i_in   , UVM_ALL_ON)
    `uvm_field_int(pop          , UVM_ALL_ON)
    `uvm_field_int(data_out     , UVM_ALL_ON)
    `uvm_field_int(pndng        , UVM_ALL_ON)
    `uvm_field_int(popin        , UVM_ALL_ON)
    `uvm_field_int(dev_id       , UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name="main_pck"); super.new(name); endfunction
endclass
