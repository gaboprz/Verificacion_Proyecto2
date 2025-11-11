/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define le monitor
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class monitor extends uvm_monitor;
    `uvm_component_utils(monitor)

    uvm_analysis_port #(main_pck) mon_analysis_port;

    virtual router_external_if vif;
    int device_id;  // ID del dispositivo (0-15)

    function new(string name="monitor", uvm_component parent=null);
        super.new(name, parent);
    endfunction
    
    // BUILD PHASE
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Obtener la interfaz específica para este dispositivo
        if (!uvm_config_db#(virtual router_external_if)::get(this, "", $sformatf("ext_if[%0d]", device_id), vif))
            `uvm_fatal("MON", $sformatf("Could not get vif for device %0d", device_id))
        
        mon_analysis_port = new("mon_analysis_port", this);
    endfunction

    
    
    // RUN PHASE - CAPTURA SIMULTÁNEA
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("MON", $sformatf("Iniciando monitor para dispositivo %0d", device_id), UVM_LOW)
        
        forever begin
            // ESPERAR el disparador PRINCIPAL: DUT tiene datos de SALIDA listos
            // pndng=1 (DUT tiene dato) Y pop=1 (dispositivo solicitando dato)
            @(posedge vif.clk iff (vif.pndng === 1'b1 && vif.pop === 1'b1));

            main_pck transaction = main_pck::type_id::create("transaction");

            transaction.data_out_i_in = vif.data_out_i_in;  // Dato enviado al DUT
            transaction.pndng_i_in    = vif.pndng_i_in;     // Indicador de dato pendiente de entrada
            transaction.pop           = vif.pop;            // Señal para sacar dato de FIFO de entrada

            transaction.data_out = vif.data_out;            // Dato recibido del DUT
            transaction.pndng    = vif.pndng;               // Indicador de dato pendiente de salida
            transaction.popin    = vif.popin;               // Confirmación de consumo de dato de entrada
            
            `uvm_info("MON_CAPTURE", $sformatf(
                "Dispositivo %0d | SALIDA: Data=0x%0h | ENTRADA: Data=0x%0h", 
                device_id,
                transaction.data_out,      // Dato que el DUT está enviando
                transaction.data_out_i_in  // Dato que el dispositivo está enviando al DUT
            ), UVM_MEDIUM)
            
            // Enviar transacción al scoreboard
            mon_analysis_port.write(transaction);
        end
    endtask

    
    
endclass

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
