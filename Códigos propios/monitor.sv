/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define le monitor
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class monitor extends uvm_monitor;
    `uvm_component_utils(monitor)

    uvm_analysis_port #(main_pck) mon_analysis_port;

    virtual router_external_if vif;
    int device_id;  // ID del dispositivo (0-15)

    function new(string name="monitor", uvm_component parent=null);
        super.new(name, parent);
    endfunction
    
    // BUILD PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Obtener la interfaz específica para este dispositivo
        if (!uvm_config_db#(virtual router_external_if)::get(this, "", $sformatf("ext_if[%0d]", device_id), vif))
            `uvm_fatal("MON", $sformatf("Could not get vif for device %0d", device_id))
        
        mon_analysis_port = new("mon_analysis_port", this);
    endfunction
    
    // RUN PHASE - CAPTURA SIMULTÁNEA
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("MON", $sformatf("Iniciando monitor para dispositivo %0d", device_id), UVM_LOW)
        
        forever begin
            // ESPERAR el disparador PRINCIPAL: DUT tiene datos de SALIDA listos
            // pndng=1 (DUT tiene dato) Y pop=1 (dispositivo solicitando dato)
            @(posedge vif.clk iff (vif.pndng === 1'b1 && vif.pop === 1'b1));

            main_pck transaction = main_pck::type_id::create("transaction");

            transaction.data_out_i_in = vif.data_out_i_in;  // Dato enviado al DUT
            transaction.pndng_i_in    = vif.pndng_i_in;     // Indicador de dato pendiente de entrada
            transaction.pop           = vif.pop;            // Señal para sacar dato de FIFO de entrada

            transaction.data_out = vif.data_out;            // Dato recibido del DUT
            transaction.pndng    = vif.pndng;               // Indicador de dato pendiente de salida
            transaction.popin    = vif.popin;               // Confirmación de consumo de dato de entrada
            
            `uvm_info("MON_CAPTURE", $sformatf(
                "Dispositivo %0d | SALIDA: Data=0x%0h | ENTRADA: Data=0x%0h", 
                device_id,
                transaction.data_out,      // Dato que el DUT está enviando
                transaction.data_out_i_in  // Dato que el dispositivo está enviando al DUT
            ), UVM_MEDIUM)
            
            // Enviar transacción al scoreboard
            mon_analysis_port.write(transaction);
        end
    endtask
    
endclass