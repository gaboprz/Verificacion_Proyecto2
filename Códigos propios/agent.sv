class external_agent extends uvm_agent;
  `uvm_component_utils(external_agent)

  mesh_driver               d0;
  monitor                   m0;
  uvm_sequencer #(mesh_pkt) s0;

  int device_id;

  function new(string name="external_agent", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    s0 = uvm_sequencer#(mesh_pkt)::type_id::create($sformatf("s0_%0d", device_id), this);
    d0 = mesh_driver              ::type_id::create($sformatf("d0_%0d", device_id), this);
    m0 = monitor                  ::type_id::create($sformatf("m0_%0d", device_id), this);
    d0.device_id = device_id;
    m0.device_id = device_id;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d0.seq_item_port.connect(s0.seq_item_export);
  endfunction
endclass
