/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se definen los paquetes necesarios para las transacciones
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// Clase de transacción, paquete de entrada y salida de routers exteriores
class main_pck extends uvm_sequence_item;
    // Datos de entrada al DUT
    rand logic [39:0] data_out_i_in;
    rand bit          pndng_i_in; 
    rand bit          pop;
    // Datos de salida del DUT
    bit               popin;
    bit               pndng;
    logic      [39:0] data_out;

    `uvm_object_utils_begin(main_pck)
        `uvm_field_int(data_out_i_in, UVM_ALL_ON)
        `uvm_field_int(pndng_i_in, UVM_ALL_ON)
        `uvm_field_int(pop, UVM_ALL_ON)
        `uvm_field_int(popin, UVM_ALL_ON)
        `uvm_field_int(pndng, UVM_ALL_ON)
        `uvm_field_int(data_out, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "main_pck");
        super.new(name);
    endfunction 
endclass 