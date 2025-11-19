// -----------------------------------------------------------------------------
// TOP del ambiente (tb.sv)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

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
`include "Router_library.sv"   // (y agrega Library.sv/fifo.sv si tu Router los requiere)

module tb;
  // Señales globales
  logic clk;
  logic reset;

  // Buses del DUT
  logic                      pndng[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out[`NUM_DEVS];
  logic                      popin[`NUM_DEVS];
  logic                      pop[`NUM_DEVS];
  logic [`PKG_SZ-1:0]        data_out_i_in[`NUM_DEVS];
  logic                      pndng_i_in[`NUM_DEVS];

  // Reloj 100 MHz
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
    .COLUMS     (`COLUMNS),     // nombre de parámetro tal cual en tu RTL
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

  // Conectar TB <-> DUT
  genvar i;
  generate
    for (i = 0; i < `NUM_DEVS; i++) begin : CONNECT
      // TB -> DUT
      assign data_out_i_in[i] = ext_if[i].data_out_i_in;
      assign pndng_i_in[i]    = ext_if[i].pndng_i_in;
      assign pop[i]           = ext_if[i].pop;

      // DUT -> TB
      assign ext_if[i].data_out = data_out[i];
      assign ext_if[i].pndng    = pndng[i];
      assign ext_if[i].popin    = popin[i];
    end
  endgenerate

  // SINK simple para la salida del DUT: consumir cuando haya dato
  generate
    for (genvar j = 0; j < `NUM_DEVS; j++) begin : AUTO_POP_SINK
      always_ff @(posedge clk or posedge reset) begin
        if (reset) ext_if[j].pop <= 1'b0;
        else       ext_if[j].pop <= ext_if[j].pndng;
      end
    end
  endgenerate

  // -------- Registro de VIFs + arranque UVM (¡FUERA de generate!) --------
  initial begin
    // Registrar cada interfaz con la MISMA llave que pide tu driver/monitor
    // (driver/monitor hacen get(..., "", $sformatf("ext_if[%0d]", device_id), vif))
    for (int k = 0; k < `NUM_DEVS; k++) begin
      string if_name = $sformatf("ext_if[%0d]", k);
      uvm_config_db#(virtual router_external_if)::set(
        null, "uvm_test_top.env.*", if_name, ext_if[k]);
    end

    // (opcional) forzar número de agentes en el env
    uvm_config_db#(int unsigned)::set(null, "uvm_test_top.env", "NUM_DEVS", `NUM_DEVS);

    `uvm_info("TB", "Interfaces registradas en config_db; arrancando UVM...", UVM_LOW)

    // Opción A: fija el test aquí
    run_test("base_test");

    // Opción B: deja vacío y pasa +UVM_TESTNAME=base_test desde la línea de comandos
    // run_test();
  end

  // Timeout de seguridad
  initial begin
    #5000;
    `uvm_info("TB", "Timeout - finalizando simulación", UVM_LOW)
    $finish;
  end

  // Waves
  initial begin
    if ($test$plusargs("wave")) begin
      $dumpfile("mesh_waves.vcd");
      $dumpvars(0, tb);
    end
  end

endmodule
