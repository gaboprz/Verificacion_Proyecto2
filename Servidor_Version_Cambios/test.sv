
class test extends uvm_test;
    `uvm_component_utils(test)

    mesh_env env;
    
    // Struct para describir una prueba:
    // name: nombre identificador
    // num_packets_per_agent: cuántos paquetes envía cada agente en esa prueba
    typedef struct {
        string name;
        int num_packets_per_agent[`NUM_DEVS];
    } test_config_t;
    
    // Lista de pruebas que se van a correr en secuencia
    test_config_t test_list[$];
    
    //  Variables para monitoreo de progreso 
    // total_packets_to_send: suma de todos los paquetes de todas las pruebas
    // progress_check_interval: cada cuánto se revisa el avance
    // stall_threshold: cuánto tiempo sin progreso se considera “stall”
    // max_test_time: tiempo máximo total del test
    int     total_packets_to_send      = 0;
    longint progress_check_interval    = 10000;  // 10us entre revisiones
    longint stall_threshold            = 20000;  // 100us sin progreso = stall
    longint max_test_time              = 100000; // 1ms tiempo máximo total
    bit     test_completed_normally    = 0;

    int last_count;
    int current_count;
    int stall_count;
    
    // Evento UVM para coordinar
    uvm_event progress_monitor_event;

    function new(string name = "test", uvm_component parent=null);
        super.new(name, parent);
        progress_monitor_event = new("progress_monitor_event");
    endfunction


    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Timeout global de la simulación
        uvm_top.set_timeout(50000000, 0);

        // Crear environment y pasar número de dispositivos
        env = mesh_env::type_id::create("env", this);
        uvm_config_db#(int unsigned)::set(this, "env", "NUM_DEVS", `NUM_DEVS);

        // Definir los escenarios de prueba
        setup_test_scenarios();
        
        // Calcular la cantidad total de paquetes que se espera que salgan
        calculate_total_packets();
    endfunction

    // Recorre la lista de pruebas y suma todos los paquetes de todos los agentes
    virtual function void calculate_total_packets();
        total_packets_to_send = 0;
        foreach (test_list[i]) begin
            foreach (test_list[i].num_packets_per_agent[j]) begin
                total_packets_to_send += test_list[i].num_packets_per_agent[j];
            end
        end
        `uvm_info("TEST_SYNC", 
                  $sformatf("Total packets to send across all tests: %0d", 
                            total_packets_to_send), 
                  UVM_LOW)
    endfunction

    // Aquí se definen las pruebas
    virtual function void setup_test_scenarios();
        test_config_t prueba;
        
        // PRUEBA 1
        prueba.name = "Prueba 1";
        prueba.num_packets_per_agent = '{
            0: 80,  1: 80,  2: 70,  3: 80,  4: 70,  5: 70,  6: 70,  7: 80,
            8: 100, 9: 80, 10: 90, 11: 90, 12: 80, 13: 80, 14: 60, 15: 80
        };
        test_list.push_back(prueba);

        // PRUEBA 2
        prueba.name = "Prueba 2";
        prueba.num_packets_per_agent = '{
            0: 80,  1: 80,  2: 70,  3: 80,  4: 70,  5: 70,  6: 70,  7: 80,
            8: 100, 9: 80, 10: 90, 11: 90, 12: 80, 13: 80, 14: 60, 15: 80
        };
        test_list.push_back(prueba);

        // PRUEBA 3
        prueba.name = "Prueba 3";
        prueba.num_packets_per_agent = '{
            0: 50,  1: 40,  2: 20,  3: 20,  4: 30,  5: 50,  6: 30,  7: 30,
            8: 25,  9: 60, 10: 30, 11: 30, 12: 50, 13: 50, 14: 20, 15: 50
        };
        test_list.push_back(prueba);
        
        `uvm_info("TEST_SETUP", 
                  $sformatf("Configuradas %0d pruebas", test_list.size()), 
                  UVM_LOW)
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

    virtual task monitor_progress();
        longint start_time         = $time;
        longint last_progress_time = $time;
        int     last_count         = 0;
        int     current_count;
        int     stall_count        = 0;
        
        `uvm_info("TEST_MONITOR", "Iniciando monitoreo de progreso...", UVM_LOW)
        
        // Se mantiene revisando hasta que:
        // - se alcance max_test_time, o
        // - se completen tods los paquetes
        while ($time - start_time < max_test_time) begin
            #(progress_check_interval);
            
            // Pregunta al scoreboard cuántos paquetes de salida lleva
            current_count = env.scb.get_current_progress();
            
            // Si hubo avance, se reporta y se resetea el conteo de stalls
            if (current_count != last_count) begin
                `uvm_info("TEST_PROGRESS", 
                    $sformatf("Progreso: %0d/%0d paquetes recibidos (%.1f%%) en tiempo %0t",
                             current_count, total_packets_to_send,
                             (current_count * 100.0) / total_packets_to_send,
                             $time), 
                    UVM_MEDIUM)
                last_count         = current_count;
                last_progress_time = $time;
                stall_count        = 0;
            end else begin
                // Si no hubo avance, se revisa si ya pasó el umbral de stall
                if ($time - last_progress_time > stall_threshold) begin
                    stall_count++;
                    `uvm_warning("TEST_STALL", 
                        $sformatf("STALL DETECTADO: Sin progreso por %0t unidades. Ciclo de stall: %0d",
                                  $time - last_progress_time, stall_count))
                    
                    // Si se acumulan varios stalls seguidos, se fuerza el cierre del test
                    if (stall_count >= 3) begin
                        `uvm_error("TEST_STALL", 
                            $sformatf("STALL CRÍTICO: %0d stalls consecutivos. Forzando finalización del test.",
                                      stall_count))
                        env.scb.force_test_completion();
                        break;
                    end
                end
            end
            
            // Si ya llegamos al total esperado, marcamos como completado normal
            if (current_count >= total_packets_to_send) begin
                test_completed_normally = 1;
                `uvm_info("TEST_PROGRESS", "¡Todos los paquetes recibidos!", UVM_LOW)
                break;
            end
        end
        
        // Si se acabó el tiempo total y no se terminó, marcamos timeout
        if ($time - start_time >= max_test_time) begin
            `uvm_error("TEST_TIMEOUT", 
                $sformatf("Timeout total alcanzado (%0t). Paquetes recibidos: %0d/%0d",
                         max_test_time, current_count, total_packets_to_send))
            env.scb.force_test_completion();
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info("TEST", "Iniciando suite de pruebas avanzadas", UVM_LOW)
        
        // Se le dice al scoreboard cuántos paquetes se espera que SALGAN en total
        env.scb.set_expected_packet_count(total_packets_to_send);
        
        fork
            monitor_progress();
        join_none
        
        // Ejecutar cada prueba de la lista, una después de la otra
        foreach (test_list[i]) begin
            `uvm_info("TEST", 
                      $sformatf("=== INICIANDO %s ===", test_list[i].name), 
                      UVM_LOW)
            run_single_test(test_list[i]);
            `uvm_info("TEST", 
                      $sformatf("=== ENVÍO COMPLETADO %s ===", test_list[i].name), 
                      UVM_LOW)
        end
        
        `uvm_info("TEST_SYNC", "Esperando a que el scoreboard complete...", UVM_LOW)
        
        // Espera a que el scoreboard declare que ya terminó
        env.scb.wait_for_completion(stall_threshold * 3);
    
        #1000;
        
        if (test_completed_normally) begin
            `uvm_info("TEST", 
                      "Todas las pruebas completadas exitosamente - TODOS los paquetes salieron", 
                      UVM_LOW)
        end else begin
            `uvm_warning("TEST", 
                         "Prueba completada de forma forzada - Revisar reporte del scoreboard")
        end
        
        phase.drop_objection(this);
    endtask

    virtual task run_single_test(test_config_t configuration);
        // Cada agente arranca su propia secuencia en paralelo
        fork
            for (int agent_id = 0; agent_id < `NUM_DEVS; agent_id++) begin
                automatic int agent = agent_id;
                if (configuration.num_packets_per_agent[agent] > 0) begin
                    begin
                        gen_mesh_seq seq;
                        seq = gen_mesh_seq::type_id::create(
                                $sformatf("seq_%0d_%s", agent, configuration.name));
                        seq.num = configuration.num_packets_per_agent[agent];

                        // Selección del tipo de destino según el nombre de la prueba
                        if (configuration.name == "Prueba 1") begin
                            seq.dest_mode = 0; // destinos válidos
                        end
                        else if (configuration.name == "Prueba 2") begin
                            seq.dest_mode = 0; // destinos válidos
                        end
                        else if (configuration.name == "Prueba 3") begin
                            seq.dest_mode = 0; 
                        end

                        seq.start(env.agents[agent].s0);

                        `uvm_info("TEST",
                            $sformatf("Agente %0d completado: %0d paquetes (dest_mode=%0d)",
                                      agent, seq.num, seq.dest_mode),
                            UVM_MEDIUM)
                    end
                end
                else begin
                    `uvm_info("TEST", 
                              $sformatf("Agente %0d: 0 paquetes - omitido", agent), 
                              UVM_HIGH)
                end
            end
        join

        #100;
    endtask

endclass
