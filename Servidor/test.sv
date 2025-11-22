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
        bit use_valid_destinations;
    } test_config_t;
    
    // Lista de pruebas a ejecutar
    test_config_t test_list[$];
    
    // ========== NUEVO: Contador total de paquetes ==========
    int total_packets_to_send = 0;
    
    // ========== NUEVO: Parámetros de timeout ==========
    int timeout_checks = 20;           // Número de checks sin progreso antes de timeout
    int check_interval = 1000;         // Intervalo entre checks (unidades de tiempo)
    int current_timeout_count = 0;     // Contador actual de timeout
    int last_progress_count = 0;       // Último conteo de progreso
    
    function new(string name = "test", uvm_component parent=null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        uvm_top.set_timeout(100000, 0);

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
        prueba.name = "Prueba 1";
        prueba.num_packets_per_agent = '{
            0: 1,  1: 4,  2: 10,  3:20,  4: 0,  5: 10,  6: 0,  7: 0,
            8: 0,  9: 10,  10: 10, 11: 0, 12: 10, 13: 10, 14: 0, 15: 0
        };
        prueba.use_valid_destinations = 1;
        test_list.push_back(prueba);

        prueba.name = "Prueba 2";
        prueba.num_packets_per_agent = '{
            0: 1,  1: 4,  2: 10,  3:20,  4: 0,  5: 10,  6: 7,  7: 5,
            8: 10,  9: 10,  10: 10, 11: 10, 12: 10, 13: 10, 14: 10, 15: 12
        };
        prueba.use_valid_destinations = 1;
        test_list.push_back(prueba);
        
        `uvm_info("TEST_SETUP", $sformatf("Configuradas %0d pruebas", test_list.size()), UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    // ========== NUEVA TAREA: Monitorear progreso y manejar timeout ==========
    virtual task monitor_progress_with_timeout();
        int current_progress;
        int driver_packets;
        
        `uvm_info("TEST_TIMEOUT", "Iniciando monitoreo de progreso con timeout", UVM_LOW)
        
        // Inicializar contadores
        last_progress_count = env.scb.get_current_progress();
        current_timeout_count = 0;
        
        while (current_timeout_count < timeout_checks) begin
            #check_interval; // Esperar intervalo entre checks
            
            current_progress = env.scb.get_current_progress();
            driver_packets = env.scb.get_driver_received_count();
            
            `uvm_info("TEST_PROGRESS", 
                $sformatf("Progreso: %0d/%0d paquetes salieron, %0d paquetes entraron al DUT (timeout_count=%0d/%0d)",
                current_progress, total_packets_to_send, driver_packets, 
                current_timeout_count, timeout_checks), UVM_MEDIUM)
            
            // Verificar si hay progreso
            if (current_progress > last_progress_count) begin
                // Hay progreso, resetear contador de timeout
                current_timeout_count = 0;
                last_progress_count = current_progress;
                `uvm_info("TEST_PROGRESS", "Progreso detectado - reset timeout counter", UVM_HIGH)
            end else begin
                // No hay progreso, incrementar contador de timeout
                current_timeout_count++;
                `uvm_info("TEST_TIMEOUT", 
                    $sformatf("Sin progreso - timeout_count incrementado a %0d", current_timeout_count), UVM_MEDIUM)
            end
            
            // Si ya completamos todos los paquetes, salir
            if (current_progress >= total_packets_to_send) begin
                `uvm_info("TEST_PROGRESS", "Todos los paquetes han salido - terminando monitoreo", UVM_LOW)
                break;
            end
        end
        
        // Si salimos por timeout, forzar finalización
        if (current_timeout_count >= timeout_checks) begin
            `uvm_warning("TEST_TIMEOUT", 
                $sformatf("Timeout alcanzado después de %0d checks sin progreso. Forzando finalización.", timeout_checks))
            env.scb.force_completion();
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
        
        // ========== NUEVO: Iniciar monitoreo de progreso en paralelo ==========
        fork
            // Proceso 1: Esperar a que scoreboard confirme que TODOS los paquetes SALIERON
            begin
                `uvm_info("TEST_SYNC", "Esperando a que TODOS los paquetes SALGAN de la malla...", UVM_LOW)
                env.scb.wait_for_completion();
            end
            
            // Proceso 2: Monitorear progreso y manejar timeout
            begin
                monitor_progress_with_timeout();
            end
        join_any // Cualquiera de los dos procesos puede terminar la espera
        
        // Matar el otro proceso si todavía está corriendo
        disable fork;
        
        // Pequeña pausa adicional para asegurar que todo se estabilice
        #1000;
        
        `uvm_info("TEST", "Todas las pruebas completadas - algunos paquetes pueden haberse perdido en la malla", UVM_LOW)
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
        #100;
    endtask
endclass