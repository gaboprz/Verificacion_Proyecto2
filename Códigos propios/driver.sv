class mesh_driver extends uvm_driver #(mesh_pkt);
  `uvm_component_utils(mesh_driver)

  virtual router_external_if vif;

  function new(string name = "mesh_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", "router_ext_vif", vif))
      `uvm_fatal("DRV", "No se pudo obtener 'router_external_if' (router_ext_vif)")
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    //  Estado inicial
    vif.pndng_i_in    <= 1'b0;
    vif.data_out_i_in <= '0;

    //  liberación de reset
    if (vif.rst === 1'b1) @(negedge vif.rst);
    @(posedge vif.clk);

    forever begin
      mesh_pkt m_item;
      `uvm_info("DRV", "Esperando item del sequencer", UVM_LOW)
      seq_item_port.get_next_item(m_item);

      // Presentar paquete y marcar pendiente
      @(posedge vif.clk);
      // Si justo hay reset, espera a que se libere y continúa
      if (vif.rst === 1'b1) begin
        // limpiar mientras dura el reset
        vif.pndng_i_in    <= 1'b0;
        vif.data_out_i_in <= '0;
        @(negedge vif.rst);
        @(posedge vif.clk);
      end

      vif.data_out_i_in <= m_item.raw_pkt;
      vif.pndng_i_in    <= 1'b1;
      `uvm_info("DRV", $sformatf("Enviando paquete: %s", m_item.convert2str()), UVM_LOW)

      // Esperar a que el DUT consuma el paquete (pop=1)
      do begin
        @(posedge vif.clk);
        if (vif.rst === 1'b1) begin
          // Si entra reset: baja bandera, limpia, espera liberar y re-presenta el mismo item
          vif.pndng_i_in    <= 1'b0;
          vif.data_out_i_in <= '0;
          @(negedge vif.rst);
          @(posedge vif.clk);
          vif.data_out_i_in <= m_item.raw_pkt;
          vif.pndng_i_in    <= 1'b1;
        end
      end while (vif.pop !== 1'b1);

      @(posedge vif.clk);
      vif.pndng_i_in    <= 1'b0;
      vif.data_out_i_in <= '0;

      `uvm_info("DRV", "Paquete aceptado por el DUT (pop=1)", UVM_LOW)
      seq_item_port.item_done();
    end
  endtask
endclass
