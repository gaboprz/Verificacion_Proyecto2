class mesh_driver extends uvm_driver #(mesh_pkt);
  `uvm_component_utils(mesh_driver)

  // Interfaz física que conecta este driver con el DUT
  virtual router_external_if vif;

  // Identificador del terminal al que pertenece este driver
  int device_id;

  // Número de ciclos de espera antes de mandar el paquete
  int unsigned n;

  // Puerto de análisis para avisar al scoreboard qué paquetes se inyectaron
  uvm_analysis_port #(mesh_pkt) drv_ap;

  function new(string name="mesh_driver", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);

    // La clave se arma con el device_id para escoger la interfaz correcta
    key = $sformatf("ext_if[%0d]", device_id);

    // Se trae la interfaz de la config_db, si no está, se detiene la simulación
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("DRV", $sformatf("No se encontró vif con clave %s", key))

    // Puerto que se usa para reportar al scoreboard los paquetes aceptados
    drv_ap = new("drv_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.pndng_i_in    <= 1'b0;
    vif.data_out_i_in <= '0;

    // Esperar a que se libere el reset
    if (vif.rst === 1'b1) @(negedge vif.rst);
    @(posedge vif.clk);

    forever begin
      mesh_pkt m_item;

      // Pedir el siguiente item al sequencer
      seq_item_port.get_next_item(m_item);

      // Esperar los ciclos de idle indicados en el item
      n = m_item.idle_cycles;
      repeat (n) @(posedge vif.clk);

      // Presentar el paquete al DUT
      @(posedge vif.clk);
      vif.data_out_i_in <= m_item.raw_pkt;
      vif.pndng_i_in    <= 1'b1;
      `uvm_info("DRV", $sformatf("Enviando: %s", m_item.convert2str()), UVM_LOW)

      // Esperar a que el DUT consuma la entrada (popin = 1)
      do @(posedge vif.clk); while (vif.popin !== 1'b1);

      // Avisar al scoreboard que este paquete fue aceptado
      drv_ap.write(m_item);

      @(posedge vif.clk);
      vif.pndng_i_in    <= 1'b0;
      vif.data_out_i_in <= '0;

      seq_item_port.item_done();
    end
  endtask

endclass