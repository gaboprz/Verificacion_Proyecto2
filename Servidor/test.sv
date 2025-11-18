

//`include "mesh_defines.svh"
//`include "uvm_macros.svh"
//import uvm_pkg::*;

class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    mesh_env env;
    
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
        
        `uvm_info("TEST", "Iniciando test básico", UVM_LOW)
        
        // Crear UNA secuencia y ejecutarla en UN sequencer (agente 0)
        // Esto es suficiente para probar que todo funciona
        gen_mesh_seq seq = gen_mesh_seq::type_id::create("seq");
        seq.num = 3; // Solo 3 paquetes para prueba básica
        
        // Ejecutar en el primer agente solamente
        seq.start(env.agents[0].s0);
        
        // Esperar un poco para que los paquetes se propaguen
        #200;
        
        `uvm_info("TEST", "Test completado", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass