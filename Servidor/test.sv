/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el test
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class test extends uvm_test;
    `uvm_component_utils(test)

    mesh_env env;
    
    // Estructura para configurar cada prueba
    typedef struct {
        string name;
        int num_packets_per_agent[`NUM_DEVS];
    } test_config_t;
    
    // Lista de pruebas a ejecutar
    test_config_t test_list[$];
    
    function new(string name = "test", uvm_component parent=null);
        super.new(name, parent);
        
        // INICIALIZAR LA LISTA DE PRUEBAS VACÍA
        // Las pruebas se añadirán en build_phase o run_phase
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mesh_env::type_id::create("env", this);
        uvm_config_db#(int unsigned)::set(this, "env", "NUM_DEVS", `NUM_DEVS);
        
        // CONFIGURAR LAS PRUEBAS QUE QUEREMOS EJECUTAR
        setup_test_scenarios();
    endfunction

    // FUNCIÓN PARA CONFIGURAR DIFERENTES ESCENARIOS DE PRUEBA
    virtual function void setup_test_scenarios();
        test_config_t prueba;
        
        // ===========================================================================
        // PRUEBA 1: 
        // ===========================================================================
        prueba.name = "Prueba 1 - Transacciones Legales";
        // Configurar diferentes cantidades por agente
        prueba.num_packets_per_agent = '{
            0: 1,  1: 0,  2: 0,  3: 0,  4: 0,  5: 0,  6: 0,  7: 0,
            8: 0,  9: 0,  10: 0, 11: 0, 12: 0, 13: 0, 14: 0, 15: 0
        };
            
        test_list.push_back(prueba);
        /*
        // ===========================================================================
        // PRUEBA 2: 
        // ===========================================================================
        prueba.name = "Prueba 2 - Mixto Legal/Ilegal";
        // Configurar cantidades
        prueba.num_packets_per_agent = '{
            0: 4,  1: 4,  2: 4,  3: 4,  4: 4,  5: 4,  6: 4,  7: 4,
            8: 3,  9: 3,  10: 3, 11: 3, 12: 3, 13: 3, 14: 3, 15: 3
        };
            
        test_list.push_back(prueba);
        
        // ===========================================================================
        // PRUEBA 3: 
        // ===========================================================================
        prueba.name = "Prueba 3 - Targets Específicos";
        // Menos paquetes pero con targets controlados
        prueba.num_packets_per_agent = '{
            0: 2,  1: 2,  2: 2,  3: 2,  4: 2,  5: 2,  6: 2,  7: 2,
            8: 2,  9: 2,  10: 2, 11: 2, 12: 2, 13: 2, 14: 2, 15: 2
        };
            
        test_list.push_back(prueba);
        */
        `uvm_info("TEST_SETUP", $sformatf("Configuradas %0d pruebas", test_list.size()), UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // TAREA PRINCIPAL - EJECUCIÓN SECUENCIAL DE PRUEBAS
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Iniciando suite de pruebas avanzadas", UVM_LOW)
        
        // EJECUTAR CADA PRUEBA EN SECUENCIA
        foreach (test_list[i]) begin
            `uvm_info("TEST", $sformatf("=== INICIANDO %s ===", test_list[i].name), UVM_LOW)
            run_single_test(test_list[i]);
            `uvm_info("TEST", $sformatf("=== COMPLETADA %s ===", test_list[i].name), UVM_LOW)
            
            // Pequeña pausa entre pruebas
            #500;
        end
        
        `uvm_info("TEST", "Todas las pruebas completadas exitosamente", UVM_LOW)
        phase.drop_objection(this);
    endtask

    // TAREA PARA EJECUTAR UNA PRUEBA INDIVIDUAL
    virtual task run_single_test(test_config_t configuration);
        fork
            for (int agent_id = 0; agent_id < `NUM_DEVS; agent_id++) begin
                automatic int agent = agent_id;
                if (configuration.num_packets_per_agent[agent] > 0) begin
                    begin
                        gen_mesh_seq seq = gen_mesh_seq::type_id::create($sformatf("seq_%0d", agent));
                        // Configurar la secuencia según la prueba
                        seq.num = configuration.num_packets_per_agent[agent];
                        
                        seq.start(env.agents[agent].s0);
                        
                       `uvm_info("TEST", $sformatf("Agente %0d completado: %0d paquetes", agent, seq.num), UVM_MEDIUM)
                    end
                end else begin
                    `uvm_info("TEST", $sformatf("Agente %0d: 0 paquetes - omitido", agent), UVM_HIGH)
                end
            end
        join // Espera a que TODOS los agentes de esta prueba terminen
        
        // Esperar a que los paquetes se propaguen completamente
        #1000;
    endtask
endclass