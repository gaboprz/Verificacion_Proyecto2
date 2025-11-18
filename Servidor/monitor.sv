/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define le monitor
/////////////////////////////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Monitor: Observa paquetes que SALEN del DUT hacia los dispositivos externos
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class monitor extends uvm_monitor;
    `uvm_component_utils(monitor)

    // Analysis port para enviar transacciones al scoreboard
    uvm_analysis_port #(mesh_pkt) mon_ap;

    virtual router_external_if vif;
    int device_id;  // ID del dispositivo externo (0-15)

    function new(string name="monitor", uvm_component parent=null);
        super.new(name, parent);
    endfunction
    
    // BUILD PHASE
    virtual function void build_phase(uvm_phase phase);
        string key;
        super.build_phase(phase);
        // Obtener la interfaz virtual para este dispositivo
        key = $sformatf("ext_if[%0d]", device_id);
        if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
            `uvm_fatal("MON", $sformatf("No se pudo obtener vif con clave %s", key))
        
        mon_ap = new("mon_ap", this);
    endfunction

    // RUN PHASE - Monitorea salidas del DUT
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        
        `uvm_info("MON", $sformatf("Monitor iniciado para dispositivo %0d", device_id), UVM_MEDIUM)
        
        forever begin
            @(posedge vif.clk);
            
            // Esperar a que el DUT tenga un paquete listo (pndng=1)
            // Y que el dispositivo externo lo acepte (pop=1)
            if (vif.pndng === 1'b1 && vif.pop === 1'b1) begin
                mesh_pkt pkt = mesh_pkt::type_id::create("egress_pkt");
                
                // Decodificar el paquete de salida
                pkt.raw_pkt    = vif.data_out;
                pkt.nxt_jump   = vif.data_out[`PKG_SZ-1 -: 8];
                pkt.target_row = vif.data_out[`PKG_SZ-9 -: 4];
                pkt.target_col = vif.data_out[`PKG_SZ-13 -: 4];
                pkt.mode       = vif.data_out[`PKG_SZ-17];
                pkt.payload    = vif.data_out[`PKG_SZ-18 -: `PAYLOAD_W];
                
                // Guardar por qué puerto salió (para verificación)
                pkt.egress_id = device_id;
                
                // Enviar al scoreboard
                mon_ap.write(pkt);
                
                `uvm_info("MON", $sformatf("Dev[%0d] Paquete salió: %s", 
                          device_id, pkt.convert2str()), UVM_MEDIUM)
            end
        end
    endtask
endclass

/*
//Problema: pop es el ACK de entrada (TB→DUT). Para observar la salida (DUT→TB) debes mirar pndng
// (y, si tienes un consumidor que acepte la salida, usarías su popin). Un monitor pasivo no debe depender de pop.
class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)

  // Antes: uvm_analysis_port #(main_pck) mon_analysis_port;
  uvm_analysis_port #(mesh_pkt) mon_ap;

  virtual router_external_if vif;
  int device_id;

  function new(string name="monitor", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    string key = $sformatf("ext_if[%0d]", device_id);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("MON", $sformatf("No vif con clave %s", key))
    mon_ap = new("mon_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit prev_pndng = 1'b0;
    forever begin
      @(posedge vif.clk);
      if (vif.rst) begin prev_pndng = 1'b0; continue; end

      // Flanco de subida de pndng (hay dato listo en la salida del DUT)
      if (vif.pndng && !prev_pndng) begin
        mesh_pkt tr = mesh_pkt::type_id::create("egress_tr");

        // Decodificar data_out en los campos del mesh_pkt
        logic [39:0] bits = vif.data_out;
        tr.nxt_jump   = bits[`PKG_SZ-1   -: 8];
        tr.target_row = bits[`PKG_SZ-9   -: 4];
        tr.target_col = bits[`PKG_SZ-13  -: 4];
        tr.mode       = bits[`PKG_SZ-17];
        if (`PAYLOAD_W > 0)
          tr.payload = bits[`PKG_SZ-18 -: `PAYLOAD_W];
        tr.raw_pkt = bits; // por si quieres loguear el vector completo

        mon_ap.write(tr);

        `uvm_info("MON_EGRESS",
          $sformatf("Dev %0d | OUT %s", device_id, tr.convert2str()),
          UVM_MEDIUM)
      end
      prev_pndng = vif.pndng;
    end
  endtask
endclass
*/

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Monitor: Observa paquetes que SALEN del DUT hacia los dispositivos externos
/////////////////////////////////////////////////////////////////////////////////////////////////////////
