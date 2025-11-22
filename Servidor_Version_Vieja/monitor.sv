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

    // Bit que se usa para asegurar correcta política para aceptar datos del DUT
    bit captured_this_packet;

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

        captured_this_packet = 1'b0;
        
        `uvm_info("MON", $sformatf("Monitor iniciado para dispositivo %0d", device_id), UVM_MEDIUM)
        
        forever begin
            @(posedge vif.clk);

            if (vif.rst) begin 
              captured_this_packet = 1'b0;
              continue; 
            end
            
            // Esperar a que el DUT tenga un paquete listo (pndng=1)
            // Y que el dispositivo externo lo acepte (pop=1)
            if (vif.pndng && !captured_this_packet) begin
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
                captured_this_packet = 1'b1;
                
                `uvm_info("MON", $sformatf("Dev[%0d] Paquete salió: %s", 
                          device_id, pkt.convert2str()), UVM_MEDIUM)
            end

            // Resetear cuando pndng baja
            if (!vif.pndng) begin
                captured_this_packet = 1'b0;
            end
        end
    endtask
endclass