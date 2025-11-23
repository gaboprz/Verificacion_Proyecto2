class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)

  rand int num;  
  constraint c1 { num inside {[2:50]}; }

  // 0 = sólo destinos válidos
  // 1 = sólo destinos inválidos
  int unsigned dest_mode = 0;

  function new(string name="gen_mesh_seq"); 
    super.new(name); 
  endfunction

  virtual task body();
    for (int i = 0; i < num; i++) begin
      mesh_pkt m_item = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      start_item(m_item);

      case (dest_mode)
        0: void'( m_item.randomize() with { dest_valid == 1; } );
        1: void'( m_item.randomize() with { dest_valid == 0; } );
        2: void'( m_item.randomize() with { dest_valid = (i % 2 == 0); } );
        default: void'( m_item.randomize() ); // mezcla
      endcase

      `uvm_info("SEQ", $sformatf("Generate: %s", m_item.convert2str()), UVM_LOW)
      finish_item(m_item);
    end
  endtask
endclass
