class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)

  // Puerto de análisis para enviar paquetes observados al scoreboard
  uvm_analysis_port #(mesh_pkt) mon_ap;

  virtual router_external_if vif;

  int device_id;

  // Bandera para no capturar el mismo paquete varias veces
  bit captured_this_packet;

  function new(string name="monitor", uvm_component parent=null);
    super.new(name, parent);
  endfunction
    
  virtual function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);

    // Buscar la interfaz virtual para este device_id en la config_db
    key = $sformatf("ext_if[%0d]", device_id);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("MON", $sformatf("No se pudo obtener vif con clave %s", key))
    
    // Crear el puerto de análisis
    mon_ap = new("mon_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    captured_this_packet = 1'b0;
    `uvm_info("MON", $sformatf("Monitor iniciado para dispositivo %0d", device_id), UVM_MEDIUM)
    
    forever begin
      @(posedge vif.clk);

      if (vif.rst) begin
        captured_this_packet = 1'b0;
        continue;
      end
        
      // Cuando hay dato válido (pndng=1) y el entorno hace pop,
      // se toma el paquete una sola vez
      if (vif.pndng && !captured_this_packet && vif.pop) begin
        mesh_pkt pkt = mesh_pkt::type_id::create("egress_pkt");
            
        // Decodificar el paquete de salida desde el vector de 40 bits
        pkt.raw_pkt    = vif.data_out;
        pkt.nxt_jump   = vif.data_out[`PKG_SZ-1  -: 8];
        pkt.target_row = vif.data_out[`PKG_SZ-9  -: 4];
        pkt.target_col = vif.data_out[`PKG_SZ-13 -: 4];
        pkt.mode       = vif.data_out[`PKG_SZ-17];
        pkt.payload    = vif.data_out[`PKG_SZ-18 -: `PAYLOAD_W];
            
        // Guardar por qué puerto salió el paquete
        pkt.egress_id = device_id;
            
        // Enviar el paquete observado al scoreboard
        mon_ap.write(pkt);
        captured_this_packet = 1'b1;
            
        `uvm_info("MON",
                  $sformatf("Dev[%0d] Paquete salió: %s",
                            device_id, pkt.convert2str()),
                  UVM_MEDIUM)
      end

      // Cuando ya no hay dato pendiente se habilita la captura del siguiente
      if (!vif.pndng) begin
        captured_this_packet = 1'b0;
      end
    end
  endtask

endclass
