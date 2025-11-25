import uvm_pkg::*;
`include "uvm_macros.svh"

// Definiciones del proyecto
`include "mesh_defines.svh"

// Interface
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

  // Señales para el DUT
  logic                      pndng[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out[`NUM_DEVS];
  logic                      popin[`NUM_DEVS];
  logic                      pop[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out_i_in[`NUM_DEVS];
  logic                      pndng_i_in[`NUM_DEVS];

  // Clock
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Reset
  initial begin
    reset = 1'b1;
    #100 reset = 1'b0;
  end

  // DUT
  mesh_gnrtr #(
    .ROWS       (`ROWS),
    .COLUMS     (`COLUMNS),  
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

  // Interface
  router_external_if ext_if[`NUM_DEVS](clk, reset);

  // Se generan las 16 interfaces y se conectan con su respectivo dispositivo
  generate
    for (genvar i = 0; i < `NUM_DEVS; i++) begin : connect_interfaces
      assign data_out_i_in[i] = ext_if[i].data_out_i_in;
      assign pndng_i_in[i]    = ext_if[i].pndng_i_in;
      assign pop[i]           = ext_if[i].pop;

      assign ext_if[i].data_out = data_out[i];
      assign ext_if[i].pndng    = pndng[i];
      assign ext_if[i].popin    = popin[i];
    end
  endgenerate

  // El monitor acepta el dato siempre que el DUT se lo ofrezca
  generate
    for (genvar i = 0; i < `NUM_DEVS; i++) begin : auto_pop_sink
      always_ff @(posedge clk or posedge reset) begin
        if (reset) ext_if[i].pop <= 1'b0;
        else       ext_if[i].pop <= ext_if[i].pndng;
      end
    end
  endgenerate
  // Registra las interfaces
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

  // Comando para correr el test
  initial begin
    run_test("test");
  end

  // Waveforms
  initial begin
    if ($test$plusargs("wave")) begin
      $dumpfile("mesh_waves.vcd");
      $dumpvars(0, tb);
    end
  end

endmodule