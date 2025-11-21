/////////////////////////////////////////////////////////////////////////////////////////////////////////
// TOP del ambiente. Es el testbench
/////////////////////////////////////////////////////////////////////////////////////////////////////////

//`timescale 1ns/1ps

// Incluir UVM
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
`include "Router_library.sv"

module tb;

  // Señales globales
  logic clk;
  logic reset;

  // Señales para el DUT - arrays para `NUM_DEVS
  logic                      pndng[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out[`NUM_DEVS];
  logic                      popin[`NUM_DEVS];
  logic                      pop[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out_i_in[`NUM_DEVS];
  logic                      pndng_i_in[`NUM_DEVS];

  // Generación de reloj (100 MHz)
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // período 10 ns
  end

  // Reset
  initial begin
    reset = 1'b1;
    #100 reset = 1'b0;
  end

  // Instanciación del DUT
  mesh_gnrtr #(
    .ROWS       (`ROWS),
    .COLUMS     (`COLUMNS),   // ← nombre del parámetro tal como está en el DUT
    .pckg_sz    (`PKG_SZ),
    .fifo_depth (`FIFO_DEPTH),
    .bdcst      (`BROADCAST)
  ) dut (
    .pndng        (pndng),
    .data_out     (data_out),
    .popin        (popin),
    .pop          (pop),
    .data_out_i_in(data_out_i_in),
    .pndng_i_in   (pndng_i_in),
    .clk          (clk),
    .reset        (reset)
  );

  // Interfaces virtuales para cada dispositivo
  router_external_if ext_if[`NUM_DEVS](clk, reset);

  // Conexión de interfaces al DUT
  generate
    for (genvar i = 0; i < `NUM_DEVS; i++) begin : connect_interfaces
      // TB -> DUT (entradas del DUT)
      assign data_out_i_in[i] = ext_if[i].data_out_i_in;
      assign pndng_i_in[i]    = ext_if[i].pndng_i_in;
      assign pop[i]           = ext_if[i].pop;

      // DUT -> TB (salidas del DUT)
      assign ext_if[i].data_out = data_out[i];
      assign ext_if[i].pndng    = pndng[i];
      assign ext_if[i].popin    = popin[i];
    end
  endgenerate

  // SINK simple para salida (el “consumidor” acepta cuando hay dato)
  generate
    for (genvar i = 0; i < `NUM_DEVS; i++) begin : auto_pop_sink
      always_ff @(posedge clk or posedge reset) begin
        if (reset) ext_if[i].pop <= 1'b0;
        else       ext_if[i].pop <= ext_if[i].pndng; // ready=1 cuando hay dato
      end
    end
  endgenerate

  generate
    for (genvar idx = 0; idx < `NUM_DEVS; idx++) begin : register_interfaces
      string if_name = $sformatf("ext_if[%0d]", idx);
      initial begin
        uvm_config_db#(virtual router_external_if)::set(
          null, "uvm_test_top.env.*", if_name, ext_if[idx]
        );
      end
    end
  endgenerate

  // <<< AÑADIR ESTO >>>
  initial begin
    run_test("test");   // nombre de tu clase de test
  end

  // Timeout
  initial begin
    #5000;
    `uvm_info("TB", "Timeout - finalizando simulación", UVM_LOW)
    $finish;
  end

  // Dump de waveforms (opcional)
  initial begin
    if ($test$plusargs("wave")) begin
      $dumpfile("mesh_waves.vcd");
      $dumpvars(0, tb);
    end
  end

endmodule
