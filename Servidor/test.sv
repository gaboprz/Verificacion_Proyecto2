/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el test
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    mesh_env env;
    gen_mesh_seq seq;
    
    function new(string name = "base_test", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mesh_env::type_id::create("env", this);
        
        // Configurar el número de dispositivos
        uvm_config_db#(int unsigned)::set(this, "env", "NUM_DEVS", `NUM_DEVS);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Iniciando test CONCURRENTE con 16 agentes", UVM_LOW)
        
        // EJECUCIÓN CONCURRENTE DE TODOS LOS AGENTES
        fork
            begin : agent_0
                gen_mesh_seq seq0 = gen_mesh_seq::type_id::create("seq0");
                seq0.num = 3;
                seq0.start(env.agents[0].s0);
                `uvm_info("TEST", $sformatf("Agente 0 completado: %0d paquetes", seq0.num), UVM_MEDIUM)
            end
            
            begin : agent_1
                gen_mesh_seq seq1 = gen_mesh_seq::type_id::create("seq1");
                seq1.num = 5;
                seq1.start(env.agents[1].s0);
                `uvm_info("TEST", $sformatf("Agente 1 completado: %0d paquetes", seq1.num), UVM_MEDIUM)
            end
            
            begin : agent_2
                gen_mesh_seq seq2 = gen_mesh_seq::type_id::create("seq2");
                seq2.num = 4;
                seq2.start(env.agents[2].s0);
                `uvm_info("TEST", $sformatf("Agente 2 completado: %0d paquetes", seq2.num), UVM_MEDIUM)
            end
            
            begin : agent_3
                gen_mesh_seq seq3 = gen_mesh_seq::type_id::create("seq3");
                seq3.num = 4;
                seq3.start(env.agents[3].s0);
                `uvm_info("TEST", $sformatf("Agente 3 completado: %0d paquetes", seq3.num), UVM_MEDIUM)
            end
            
            begin : agent_4
                gen_mesh_seq seq4 = gen_mesh_seq::type_id::create("seq4");
                seq4.num = 4;
                seq4.start(env.agents[4].s0);
                `uvm_info("TEST", $sformatf("Agente 4 completado: %0d paquetes", seq4.num), UVM_MEDIUM)
            end
            
            begin : agent_5
                gen_mesh_seq seq5 = gen_mesh_seq::type_id::create("seq5");
                seq5.num = 4;
                seq5.start(env.agents[5].s0);
                `uvm_info("TEST", $sformatf("Agente 5 completado: %0d paquetes", seq5.num), UVM_MEDIUM)
            end
            
            begin : agent_6
                gen_mesh_seq seq6 = gen_mesh_seq::type_id::create("seq6");
                seq6.num = 4;
                seq6.start(env.agents[6].s0);
                `uvm_info("TEST", $sformatf("Agente 6 completado: %0d paquetes", seq6.num), UVM_MEDIUM)
            end
            
            begin : agent_7
                gen_mesh_seq seq7 = gen_mesh_seq::type_id::create("seq7");
                seq7.num = 4;
                seq7.start(env.agents[7].s0);
                `uvm_info("TEST", $sformatf("Agente 7 completado: %0d paquetes", seq7.num), UVM_MEDIUM)
            end
            
            begin : agent_8
                gen_mesh_seq seq8 = gen_mesh_seq::type_id::create("seq8");
                seq8.num = 4;
                seq8.start(env.agents[8].s0);
                `uvm_info("TEST", $sformatf("Agente 8 completado: %0d paquetes", seq8.num), UVM_MEDIUM)
            end
            
            begin : agent_9
                gen_mesh_seq seq9 = gen_mesh_seq::type_id::create("seq9");
                seq9.num = 4;
                seq9.start(env.agents[9].s0);
                `uvm_info("TEST", $sformatf("Agente 9 completado: %0d paquetes", seq9.num), UVM_MEDIUM)
            end
            
            begin : agent_10
                gen_mesh_seq seq10 = gen_mesh_seq::type_id::create("seq10");
                seq10.num = 4;
                seq10.start(env.agents[10].s0);
                `uvm_info("TEST", $sformatf("Agente 10 completado: %0d paquetes", seq10.num), UVM_MEDIUM)
            end
            
            begin : agent_11
                gen_mesh_seq seq11 = gen_mesh_seq::type_id::create("seq11");
                seq11.num = 4;
                seq11.start(env.agents[11].s0);
                `uvm_info("TEST", $sformatf("Agente 11 completado: %0d paquetes", seq11.num), UVM_MEDIUM)
            end
            
            begin : agent_12
                gen_mesh_seq seq12 = gen_mesh_seq::type_id::create("seq12");
                seq12.num = 4;
                seq12.start(env.agents[12].s0);
                `uvm_info("TEST", $sformatf("Agente 12 completado: %0d paquetes", seq12.num), UVM_MEDIUM)
            end
            
            begin : agent_13
                gen_mesh_seq seq13 = gen_mesh_seq::type_id::create("seq13");
                seq13.num = 4;
                seq13.start(env.agents[13].s0);
                `uvm_info("TEST", $sformatf("Agente 13 completado: %0d paquetes", seq13.num), UVM_MEDIUM)
            end
            
            begin : agent_14
                gen_mesh_seq seq14 = gen_mesh_seq::type_id::create("seq14");
                seq14.num = 4;
                seq14.start(env.agents[14].s0);
                `uvm_info("TEST", $sformatf("Agente 14 completado: %0d paquetes", seq14.num), UVM_MEDIUM)
            end
            
            begin : agent_15
                gen_mesh_seq seq15 = gen_mesh_seq::type_id::create("seq15");
                seq15.num = 4;
                seq15.start(env.agents[15].s0);
                `uvm_info("TEST", $sformatf("Agente 15 completado: %0d paquetes", seq15.num), UVM_MEDIUM)
            end
        join // Espera a que TODOS los agentes terminen

        // Esperar un poco más para que los últimos paquetes se propaguen
        #1000;
        
        `uvm_info("TEST", "Test concurrente completado - TODOS los agentes terminaron", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass