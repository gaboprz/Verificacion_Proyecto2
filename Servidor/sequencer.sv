class mesh_sequencer extends uvm_sequencer#(mesh_pkt);
  `uvm_component_utils(mesh_sequencer)
  virtual router_external_if vif;
  int device_id;

  function new(string name="mesh_sequencer", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    string key = $sformatf("ext_if[%0d]", device_id);
    if (!uvm_config_db#(virtual router_external_if)::get(this, "", key, vif))
      `uvm_fatal("SEQ", $sformatf("No se obtuvo vif con clave %s", key))
  endfunction
endclass
