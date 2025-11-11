/////////////////////////////////////////////////////////////////////////////////////////////////////////
// TOP del ambiente. Es el testbench
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// Se importan los códigos del ambiente

`include "test.sv"
`include "env.sv"
`include "interface.sv"
`include "transaction.sv"
`include "sequencer.sv"
`include "sequence_item.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"

// Se importan los códigos del DUT
`include "fifo.sv"
`include "Library.sv"
`include "Router_library.sv"