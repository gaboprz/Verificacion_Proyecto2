/////////////////////////////////////////////////////////////////////////////////////////////////////////
// TOP del ambiente. Es el testbench
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

// Incluir macros UVM
import uvm_pkg::*;
`include "uvm_macros.svh"

// Definiciones del proyecto
`include "mesh_defines.svh"

// Interfaces
`include "interface.sv"

// Componentes UVM
`include "sequence_item.sv"
`include "sequencer.sv" 
`include "driver.sv"
`include "monitor.sv"
`include "agent.sv"
`include "scoreboard.sv"
`include "env.sv"
`include "test.sv"

// DUT
`include "fifo.sv"
`include "Library.sv"
`include "Router_library.sv"

module tb;
    // Señales globales
    logic clk;
    logic reset;

    // Señales para el DUT - arrays para 16 dispositivos
    logic pndng[`NUM_DEVS];
    logic [`PKG_SZ-1:0] data_out[`NUM_DEVS];
    logic popin[`NUM_DEVS];
    logic pop[`NUM_DEVS];
    logic [`PKG_SZ-1:0] data_out_i_in[`NUM_DEVS];
    logic pndng_i_in[`NUM_DEVS];

    // Generación de reloj (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period = 100MHz
    end

    // Generación de reset
    initial begin
        reset = 1'b1;
        #100 reset = 1'b0; // Reset por 100ns
    end

    // Instanciación del DUT
    mesh_gnrtr #(
        .ROWS(`ROWS),
        .COLUMS(`COLUMNS), 
        .pckg_sz(`PKG_SZ),
        .fifo_depth(`FIFO_DEPTH),
        .bdcst(`BROADCAST)
    ) dut (
        .pndng(pndng),
        .data_out(data_out),
        .popin(popin),
        .pop(pop),
        .data_out_i_in(data_out_i_in),
        .pndng_i_in(pndng_i_in),
        .clk(clk),
        .reset(reset)
    );

    // Interfaces virtuales para cada dispositivo
    router_external_if ext_if[`NUM_DEVS](clk, reset);

    // Conexión de interfaces al DUT
    generate
        for (genvar i = 0; i < `NUM_DEVS; i++) begin : connect_interfaces
            // Conexiones desde TB hacia DUT (entradas del DUT)
            assign data_out_i_in[i] = ext_if[i].data_out_i_in;
            assign pndng_i_in[i]    = ext_if[i].pndng_i_in;
            assign pop[i]           = ext_if[i].pop;
            
            // Conexiones desde DUT hacia TB (salidas del DUT)  
            assign ext_if[i].data_out = data_out[i];
            assign ext_if[i].pndng    = pndng[i];
            assign ext_if[i].popin    = popin[i];
        end
    endgenerate

    // Configuración UVM - registrar interfaces
    initial begin
        // Registrar cada interfaz en la config DB
        for (int i = 0; i < `NUM_DEVS; i++) begin
            string if_name = $sformatf("ext_if[%0d]", i);
            uvm_config_db#(virtual router_external_if)::set(null, "uvm_test_top.env.*", if_name, ext_if[i]);
        end
        
        `uvm_info("TB", "Interfaces registradas en config_db", UVM_LOW)
    end

    // Iniciar test UVM
    initial begin
        `uvm_info("TB", "Iniciando test UVM", UVM_LOW)
        run_test("base_test");
    end

    // Finalización de simulación
    initial begin
        #5000; // 5us máximo de simulación
        `uvm_info("TB", "Timeout - finalizando simulación", UVM_LOW)
        $finish;
    end

    // Dump de waveforms para debug
    initial begin
        if ($test$plusargs("wave")) begin
            $dumpfile("mesh_waves.vcd");
            $dumpvars(0, tb);
        end
    end

endmodule