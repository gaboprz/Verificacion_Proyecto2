/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el agente
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class external_agent extends uvm_agent;
    `uvm_component_utils(external_agent)

    external_driver      d0;        // Driver handle
    external_monitor     m0;        // Monitor handle  
    router_sequencer     s0;        // Sequencer handle

    int device_id;  // ID del dispositivo (0-15)

    function new(string name="external_agent", uvm_component parent=null);
        super.new(name, parent);
    endfunction
    
    // BUILD PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Crear los componentes con nombres únicos basados en device_id
        s0 = router_sequencer::type_id::create($sformatf("s0_%0d", device_id), this);
        d0 = external_driver::type_id::create($sformatf("d0_%0d", device_id), this);
        m0 = external_monitor::type_id::create($sformatf("m0_%0d", device_id), this);
        
        // Pasar el device_id a los componentes
        d0.device_id = device_id;
        m0.device_id = device_id;
    endfunction

    // CONNECT PHASE
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Conectar el driver al sequencer
        d0.seq_item_port.connect(s0.seq_item_export);
    endfunction

endclass