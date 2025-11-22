/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el sequence item
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class main_pck extends uvm_object;
  // Snapshot de ENTRADA (solo debug)
  logic [39:0] data_out_i_in;
  bit          pndng_i_in;
  bit          pop;

  // SALIDA observada del DUT
  logic [39:0] data_out;
  bit          pndng;
  bit          popin;

  // Puerto/terminal por donde el monitor vio la salida
  int unsigned dev_id;

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
