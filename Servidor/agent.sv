class external_agent extends uvm_agent;
  `uvm_component_utils(external_agent)

  mesh_driver  d0;
  monitor      m0;
  mesh_sequencer s0; // << antes: uvm_sequencer#(mesh_pkt)

  int device_id;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    s0 = mesh_sequencer::type_id::create($sformatf("s0_%0d", device_id), this);
    d0 = mesh_driver   ::type_id::create($sformatf("d0_%0d", device_id), this);
    m0 = monitor       ::type_id::create($sformatf("m0_%0d", device_id), this);
    s0.device_id = device_id; // << importante
    d0.device_id = device_id;
    m0.device_id = device_id;
  endfunction
endclass
