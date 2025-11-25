// Interfaz que conecta un terminal externo con el DUT
interface router_external_if (input clk, input rst);

  // Señales hacia el DUT (entrada)
  logic [39:0] data_out_i_in;  // Paquete de 40 bits que se quiere inyectar
  logic        pndng_i_in;     // Indica que data_out_i_in es válido
  logic        pop;            // Señal del entorno para "consumir" el dato de salida


  // Señales desde el DUT (salida)
  logic [39:0] data_out;       // Paquete de 40 bits que entrega el DUT
  logic        pndng;          // Indica que hay un dato válido en data_out
  logic        popin;          // Señal del DUT para confirmar que consumió la entrada


  // pndng_i_in no debe ir alto durante reset
  property no_pndng_i_in_during_reset;
    @(posedge clk) rst |-> !pndng_i_in;
  endproperty
  ASSERT_NO_PNDNG_DURING_RESET: assert property (no_pndng_i_in_during_reset)
    else `uvm_error("ASSERT", "pndng_i_in activo durante reset");

  // popin solo puede ir alto si pndng_i_in está activo
  property popin_only_when_pndng_i_in;
    @(posedge clk) disable iff (rst)
      popin |-> pndng_i_in;
  endproperty
  ASSERT_POPIN_REQUIRES_PNDNG: assert property (popin_only_when_pndng_i_in)
    else `uvm_error("ASSERT", "popin activo sin pndng_i_in");


  // pndng no debe ir alto durante reset
  property no_pndng_during_reset;
    @(posedge clk) rst |-> !pndng;
  endproperty
  ASSERT_NO_PNDNG_OUT_DURING_RESET: assert property (no_pndng_during_reset)
    else `uvm_error("ASSERT", "pndng activo durante reset");

  // data_out debe quedarse estable mientras pndng=1 y aún no se hace pop
  property stable_data_out_when_pending;
    @(posedge clk) disable iff (rst)
      (pndng && !pop) |=> $stable(data_out);
  endproperty
  ASSERT_STABLE_DATA_OUT: assert property (stable_data_out_when_pending)
    else `uvm_error("ASSERT", "data_out cambió mientras pndng estaba activo y pop inactivo");

  // Después de hacer pop, pndng debe bajar
  property handshake_protocol_output;
    @(posedge clk) disable iff (rst)
      (pndng && pop) |=> !pndng;
  endproperty
  ASSERT_HANDSHAKE_OUTPUT: assert property (handshake_protocol_output)
    else `uvm_error("ASSERT", "pndng no se desactivó después de pop");


  // No deberían estar activos popin y pop al mismo tiempo
  property no_simultaneous_pop;
    @(posedge clk) disable iff (rst)
      !(popin && pop);
  endproperty
  ASSERT_NO_SIMULTANEOUS_POP: assert property (no_simultaneous_pop)
    else `uvm_error("ASSERT", "popin y pop activos simultáneamente");

endinterface
