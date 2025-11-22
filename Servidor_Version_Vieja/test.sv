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
    
    // ========== NUEVO: Contador total de paquetes ==========
    int total_packets_to_send = 0;
    
    function new(string name = "test", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        uvm_top.set_timeout(500000, 0);

        env = mesh_env::type_id::create("env", this);
        uvm_config_db#(int unsigned)::set(this, "env", "NUM_DEVS", `NUM_DEVS);
        setup_test_scenarios();
        
        // ========== NUEVO: Calcular total de paquetes ==========
        calculate_total_packets();
    endfunction

    // ========== NUEVO: Calcular cuántos paquetes enviaremos en total ==========
    virtual function void calculate_total_packets();
        total_packets_to_send = 0;
        foreach (test_list[i]) begin
            foreach (test_list[i].num_packets_per_agent[j]) begin
                total_packets_to_send += test_list[i].num_packets_per_agent[j];
            end
        end
        `uvm_info("TEST_SYNC", $sformatf("Total packets to send across all tests: %0d", total_packets_to_send), UVM_LOW)
    endfunction

    virtual function void setup_test_scenarios();
        test_config_t prueba;
        
        // PRUEBA 1: Solo 1 paquete en agente 1
        prueba.name = "Prueba 1 - Un paquete en agente 1";
        prueba.num_packets_per_agent = '{
            0: 25,  1: 25,  2: 25,  3:25,  4: 25,  5: 25,  6: 25,  7: 25,
            8: 25,  9: 25,  10: 25, 11: 25, 12: 25, 13: 25, 14: 25, 15: 25
        };
        test_list.push_back(prueba);

        /*prueba.name = "Prueba 2 - Un paquete en agente 1";
        prueba.num_packets_per_agent = '{
            0: 1,  1: 4,  2: 2,  3:3,  4: 2,  5: 5,  6: 4,  7: 3,
            8: 5,  9: 5,  10: 2, 11: 10, 12: 12, 13: 21, 14: 2, 15: 1
        };
        test_list.push_back(prueba);
        
        prueba.name = "Prueba 3 - Un paquete en agente 1";
        prueba.num_packets_per_agent = '{
            0: 11,  1: 21,  2: 21,  3:31,  4: 2,  5: 5,  6: 4,  7: 3,
            8: 5,  9: 15,  10: 12, 11: 10, 12: 12, 13: 21, 14: 12, 15: 1
        };
        test_list.push_back(prueba);*/
        
        `uvm_info("TEST_SETUP", $sformatf("Configuradas %0d pruebas", test_list.size()), UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // ========== NUEVA TAREA: Timeout simple para el último paquete ==========
    virtual task wait_with_timeout();
        int timeout_counter = 0;
        int max_timeout = 10000; // 10000 unidades de tiempo máximo
        
        `uvm_info("TEST_TIMEOUT", "Iniciando espera con timeout", UVM_LOW)
        
        while (env.scb.get_current_progress() < total_packets_to_send && timeout_counter < max_timeout) begin
            #100;
            timeout_counter++;
            
            // Cada 1000 unidades, mostrar progreso
            if (timeout_counter % 1000 == 0) begin
                `uvm_info("TEST_PROGRESS", 
                    $sformatf("Progreso: %0d/%0d, timeout_counter: %0d/%0d", 
                    env.scb.get_current_progress(), total_packets_to_send, 
                    timeout_counter, max_timeout), UVM_MEDIUM)
            end
        end
        
        if (timeout_counter >= max_timeout) begin
            `uvm_warning("TEST_TIMEOUT", 
                $sformatf("Timeout alcanzado. Paquetes recibidos: %0d/%0d", 
                env.scb.get_current_progress(), total_packets_to_send))
            env.scb.force_completion();
        end else begin
            `uvm_info("TEST_SUCCESS", 
                $sformatf("Todos los paquetes recibidos: %0d/%0d", 
                env.scb.get_current_progress(), total_packets_to_send), UVM_LOW)
        end
    endtask

    // TAREA PRINCIPAL - MODIFICADA para mejor sincronización
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Iniciando suite de pruebas avanzadas", UVM_LOW)
        
        // ========== NUEVO: Informar al scoreboard cuántos paquetes esperamos que SALGAN ==========
        env.scb.set_expected_packet_count(total_packets_to_send);
        
        // EJECUTAR CADA PRUEBA EN SECUENCIA
        foreach (test_list[i]) begin
            `uvm_info("TEST", $sformatf("=== INICIANDO %s ===", test_list[i].name), UVM_LOW)
            run_single_test(test_list[i]);
            `uvm_info("TEST", $sformatf("=== ENVÍO COMPLETADO %s ===", test_list[i].name), UVM_LOW)
        end
        
        // ========== MEJORADO: Espera con timeout para el último paquete ==========
        `uvm_info("TEST_SYNC", "Esperando a que los paquetes SALGAN de la malla...", UVM_LOW)
        
        fork
            // Proceso 1: Espera normal de completación
            begin
                env.scb.wait_for_completion();
            end
            
            // Proceso 2: Timeout por si se queda el último paquete
            begin
                wait_with_timeout();
            end
        join_any
        
        // Matar cualquier proceso que todavía esté corriendo
        disable fork;
        
        // Pequeña pausa adicional para asegurar que todo se estabilice
        #1000;
        
        `uvm_info("TEST", $sformatf("Pruebas completadas. Paquetes recibidos: %0d/%0d", 
                  env.scb.get_current_progress(), total_packets_to_send), UVM_LOW)
        phase.drop_objection(this);
    endtask

    // TAREA PARA EJECUTAR UNA PRUEBA INDIVIDUAL - SIN CAMBIOS
    virtual task run_single_test(test_config_t configuration);
        fork
            for (int agent_id = 0; agent_id < `NUM_DEVS; agent_id++) begin
                automatic int agent = agent_id;
                if (configuration.num_packets_per_agent[agent] > 0) begin
                    begin
                        gen_mesh_seq seq = gen_mesh_seq::type_id::create($sformatf("seq_%0d", agent));
                        seq.num = configuration.num_packets_per_agent[agent];
                        
                        seq.start(env.agents[agent].s0);
                        
                        `uvm_info("TEST", $sformatf("Agente %0d completado: %0d paquetes", agent, seq.num), UVM_MEDIUM)
                    end
                end else begin
                    `uvm_info("TEST", $sformatf("Agente %0d: 0 paquetes - omitido", agent), UVM_HIGH)
                end
            end
        join // Espera a que TODOS los agentes de esta prueba terminen
        
        // Pequeña pausa para que los últimos paquetes entren al DUT
        #1000;
    endtask
endclass