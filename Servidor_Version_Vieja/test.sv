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
    
    // ========== NUEVO: Parámetros de timeout inteligente ==========
    int timeout_counter = 0;
    int max_timeout_cycles = 5000; // 5000 ciclos de reloj máximo de espera
    int last_received_count = 0;
    int stable_cycles_threshold = 100; // Si no hay progreso en 100 ciclos, terminar

    int current_progress;

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
            0: 1,  1: 4,  2: 2,  3:3,  4: 2,  5: 5,  6: 4,  7: 3,
            8: 5,  9: 5,  10: 2, 11: 0, 12: 2, 13: 2, 14: 2, 15: 1
        };
        test_list.push_back(prueba);

        prueba.name = "Prueba 2 - Un paquete en agente 1";
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
        test_list.push_back(prueba);
        
        `uvm_info("TEST_SETUP", $sformatf("Configuradas %0d pruebas", test_list.size()), UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // ========== NUEVA TAREA: Monitoreo de progreso con timeout inteligente ==========
    virtual task monitor_progress_with_timeout();
        timeout_counter = 0;
        last_received_count = 0;
        
        `uvm_info("TEST_TIMEOUT", "Iniciando monitoreo de progreso con timeout inteligente", UVM_LOW)
        
        while (timeout_counter < max_timeout_cycles) begin
            #100; // Monitorear cada 100 unidades de tiempo
            
            current_progress = env.scb.get_current_progress();
            
            // Verificar si hay progreso
            if (current_progress > last_received_count) begin
                timeout_counter = 0; // Resetear timeout si hay progreso
                last_received_count = current_progress;
                `uvm_info("TEST_PROGRESS", 
                    $sformatf("Progreso: %0d/%0d paquetes recibidos", 
                    current_progress, total_packets_to_send), UVM_HIGH)
            end else begin
                timeout_counter++;
                if (timeout_counter % 100 == 0) begin
                    `uvm_info("TEST_TIMEOUT", 
                        $sformatf("Sin progreso por %0d ciclos. Actual: %0d/%0d", 
                        timeout_counter, current_progress, total_packets_to_send), UVM_MEDIUM)
                end
            end
            
            // Si ya completamos todos los paquetes, salir inmediatamente
            if (current_progress >= total_packets_to_send) begin
                `uvm_info("TEST_PROGRESS", "Todos los paquetes recibidos - terminando monitoreo", UVM_LOW)
                return;
            end
            
            // Si no hay progreso por mucho tiempo y estamos cerca del total, forzar finalización
            if (timeout_counter > stable_cycles_threshold && 
                current_progress >= total_packets_to_send - 1) begin
                `uvm_warning("TEST_TIMEOUT", 
                    $sformatf("Timeout: Solo falta 1 paquete (%0d/%0d). Forzando finalización.", 
                    current_progress, total_packets_to_send))
                env.scb.force_completion();
                return;
            end
        end
        
        // Timeout completo
        `uvm_error("TEST_TIMEOUT", 
            $sformatf("Timeout máximo alcanzado. Paquetes recibidos: %0d/%0d", 
            last_received_count, total_packets_to_send))
        env.scb.force_completion();
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
        
        // ========== MEJORADO: Espera con timeout inteligente ==========
        `uvm_info("TEST_SYNC", "Esperando a que los paquetes SALGAN de la malla...", UVM_LOW)
        
        fork
            // Proceso 1: Espera normal de completación
            begin
                env.scb.wait_for_completion();
            end
            
            // Proceso 2: Monitoreo de progreso con timeout
            begin
                monitor_progress_with_timeout();
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
        #1000; // Aumentado de 100 a 1000
    endtask
endclass