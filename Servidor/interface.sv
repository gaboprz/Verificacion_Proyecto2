/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define la interfaz que permite comunicar los dispositivos externos con el DUT
/////////////////////////////////////////////////////////////////////////////////////////////////////////

interface router_external_if (input clk, input rst);
    logic [39:0] data_out_i_in;  
    logic        pndng_i_in;            
    logic        pop;                   

    logic [39:0] data_out;      
    logic        pndng;                 
    logic        popin;      

        // ================================
    // ASERCIONES PARA SEÑALES DE ENTRADA
    // ================================
    
    // 1. Aserción: pndng_i_in nunca debe activarse durante reset
    property no_pndng_i_in_during_reset;
        @(posedge clk) rst |-> !pndng_i_in;
    endproperty
    ASSERT_NO_PNDNG_DURING_RESET: assert property (no_pndng_i_in_during_reset) 
        else `uvm_error("ASSERT", "pndng_i_in activo durante reset")
    
    // 2. Aserción: data_out_i_in debe ser estable cuando pndng_i_in está activo y popin está inactivo
    property stable_data_when_pending;
        @(posedge clk) disable iff (rst)
        (pndng_i_in && !popin) |=> $stable(data_out_i_in);
    endproperty
    ASSERT_STABLE_DATA_PENDING: assert property (stable_data_when_pending)
        else `uvm_error("ASSERT", "data_out_i_in cambió mientras pndng_i_in estaba activo y popin inactivo")
    
    // 3. Aserción: popin solo puede activarse cuando pndng_i_in está activo
    property popin_only_when_pndng_i_in;
        @(posedge clk) disable iff (rst)
        popin |-> pndng_i_in;
    endproperty
    ASSERT_POPIN_REQUIRES_PNDNG: assert property (popin_only_when_pndng_i_in)
        else `uvm_error("ASSERT", "popin activo sin pndng_i_in")
    
    // 4. Aserción: Protocolo handshake - pndng_i_in debe desactivarse después de popin
    property handshake_protocol_input;
        @(posedge clk) disable iff (rst)
        (pndng_i_in && popin) |=> !pndng_i_in;
    endproperty
    ASSERT_HANDSHAKE_INPUT: assert property (handshake_protocol_input)
        else `uvm_error("ASSERT", "pndng_i_in no se desactivó después de popin")
    
    // ================================
    // ASERCIONES PARA SEÑALES DE SALIDA
    // ================================
    
    // 5. Aserción: pndng nunca debe activarse durante reset
    property no_pndng_during_reset;
        @(posedge clk) rst |-> !pndng;
    endproperty
    ASSERT_NO_PNDNG_OUT_DURING_RESET: assert property (no_pndng_during_reset)
        else `uvm_error("ASSERT", "pndng activo durante reset")
    
    // 6. Aserción: data_out debe ser estable cuando pndng está activo y pop está inactivo
    property stable_data_out_when_pending;
        @(posedge clk) disable iff (rst)
        (pndng && !pop) |=> $stable(data_out);
    endproperty
    ASSERT_STABLE_DATA_OUT: assert property (stable_data_out_when_pending)
        else `uvm_error("ASSERT", "data_out cambió mientras pndng estaba activo y pop inactivo")
    
    // 7. Aserción: Protocolo handshake - pndng debe desactivarse después de pop
    property handshake_protocol_output;
        @(posedge clk) disable iff (rst)
        (pndng && pop) |=> !pndng;
    endproperty
    ASSERT_HANDSHAKE_OUTPUT: assert property (handshake_protocol_output)
        else `uvm_error("ASSERT", "pndng no se desactivó después de pop")
    
    // ================================
    // ASERCIONES DE CORRELACIÓN ENTRE SEÑALES
    // ================================
    
    // 8. Aserción: No puede haber popin y pop activos simultáneamente en el mismo ciclo
    property no_simultaneous_pop;
        @(posedge clk) disable iff (rst)
        !(popin && pop);
    endproperty
    ASSERT_NO_SIMULTANEOUS_POP: assert property (no_simultaneous_pop)
        else `uvm_error("ASSERT", "popin y pop activos simultáneamente")
                   
endinterface