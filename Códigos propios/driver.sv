class mesh_driver extends uvm_driver #(mesh_pkt);
  `uvm_component_utils(mesh_driver)

  virtual router_external_if vif;
  int device_id;

  function new(string name = "mesh_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    string key = $sformatf("ext_if[%0d]", device_id);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("DRV", $sformatf("No se obtuvo router_external_if con clave %s", key))
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Estado inicial
    vif.pndng_i_in    <= 1'b0;
    vif.data_out_i_in <= '0;

    // Espera única a la liberación de reset (asumimos rst=1 activo)
    if (vif.rst === 1'b1) @(negedge vif.rst);
    @(posedge vif.clk);

    forever begin
      mesh_pkt m_item;
      `uvm_info("DRV", "Esperando item del sequencer", UVM_LOW)
      seq_item_port.get_next_item(m_item);


      @(posedge vif.clk);
      vif.data_out_i_in <= m_item.raw_pkt;
      vif.pndng_i_in    <= 1'b1;
      `uvm_info("DRV", $sformatf("Enviando paquete: %s", m_item.convert2str()), UVM_LOW)

      // Esperar ACK del DUT (pop=1)
      do @(posedge vif.clk); while (vif.pop !== 1'b1);

      // Limpiar un ciclo después
      @(posedge vif.clk);
      vif.pndng_i_in    <= 1'b0;
      vif.data_out_i_in <= '0;

      `uvm_info("DRV", "Paquete aceptado por el DUT (pop=1)", UVM_LOW)
      seq_item_port.item_done();
    end
  endtask
endclass