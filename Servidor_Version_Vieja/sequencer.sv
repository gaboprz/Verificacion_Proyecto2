class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)

  rand int num;  
  int agent_id;
  int sequence_id; // ========== NUEVO: ID de secuencia ==========
  static int sequence_counter = 0;
  
  constraint c1 { num inside {[2:100]}; }

  function new(string name="gen_mesh_seq"); 
    super.new(name); 
    sequence_id = sequence_counter++;
  endfunction

  virtual task body();
    `uvm_info("SEQ", $sformatf("Starting sequence %0d for agent %0d with %0d packets", 
              sequence_id, agent_id, num), UVM_LOW)
              
    for (int i = 0; i < num; i++) begin
      mesh_pkt m_item = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      m_item.sequence_id = sequence_id; // ========== NUEVO: Set sequence ID ==========
      start_item(m_item);
      void'(m_item.randomize());
      `uvm_info("SEQ", $sformatf("Generate: %s", m_item.convert2str()), UVM_LOW)
      finish_item(m_item);
    end
    
    `uvm_info("SEQ", $sformatf("Sequence %0d completed", sequence_id), UVM_LOW)
  endtask
endclass