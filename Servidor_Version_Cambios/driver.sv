/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el driver
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class mesh_driver extends uvm_driver #(mesh_pkt);
  `uvm_component_utils(mesh_driver)

  virtual router_external_if vif;
  int device_id;
  int unsigned n;
  //puerto de análisis hacia el scoreboard 
  uvm_analysis_port #(mesh_pkt) drv_ap;

  function new(string name="mesh_driver", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);
    key = $sformatf("ext_if[%0d]", device_id);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("DRV", $sformatf("No vif con clave %s", key))
    drv_ap = new("drv_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Idle + release reset
    vif.pndng_i_in    <= 1'b0;
    vif.data_out_i_in <= '0;
    if (vif.rst === 1'b1) @(negedge vif.rst);
    @(posedge vif.clk);

    forever begin
      mesh_pkt m_item;
      seq_item_port.get_next_item(m_item);

      // >>> NUEVO: espera aleatoria por item (en ciclos de clk)
      //     (el valor viene aleatorio desde el sequence_item)
      n = m_item.idle_cycles;
      repeat (n) @(posedge vif.clk);

      // Presentar paquete al DUT
      @(posedge vif.clk);
      vif.data_out_i_in <= m_item.raw_pkt;
      vif.pndng_i_in    <= 1'b1;
      `uvm_info("DRV", $sformatf("Enviando: %s", m_item.convert2str()), UVM_LOW)

      // Esperar a que el DUT consuma la entrada (popin = 1)
      do @(posedge vif.clk); while (vif.popin !== 1'b1);

      // Avisar al scoreboard que ESTE paquete ya fue aceptado
      drv_ap.write(m_item);

      // Limpiar
      @(posedge vif.clk);
      vif.pndng_i_in    <= 1'b0;
      vif.data_out_i_in <= '0;

      seq_item_port.item_done();
    end
  endtask

endclass