class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    mesh_env env;
    gen_mesh_seq seq;
    
    function new(string name = "base_test", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("TEST", "Build phase started", UVM_LOW)
        
        env = mesh_env::type_id::create("env", this);
        
        // Configurar el número de dispositivos
        uvm_config_db#(int unsigned)::set(this, "env", "NUM_DEVS", `NUM_DEVS);
        
        `uvm_info("TEST", "Build phase completed", UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        `uvm_info("TEST", "UVM Topology:", UVM_LOW)
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Run phase started", UVM_LOW)
        
        // Esperar a que el reset termine
        #150; // Un poco después del reset a los 100ns
        
        `uvm_info("TEST", "Starting sequence", UVM_LOW)
        
        seq = gen_mesh_seq::type_id::create("seq");
        seq.num = 3;
        
        if (!seq.randomize()) 
            `uvm_error("TEST", "Failed to randomize sequence")
        else
            `uvm_info("TEST", $sformatf("Sequence randomized with %0d packets", seq.num), UVM_LOW)
        
        `uvm_info("TEST", "Starting sequence on agent 0", UVM_LOW)
        seq.start(env.agents[0].s0);
        
        `uvm_info("TEST", "Sequence completed, waiting for packets to propagate", UVM_LOW)
        #500; // Dar más tiempo para la propagación
        
        `uvm_info("TEST", "Test completed - dropping objection", UVM_LOW)
        phase.drop_objection(this);
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("TEST", "Test report phase completed", UVM_LOW)
    endfunction
endclass