/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el sequencer
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)

  // 0 = solo destinos válidos
  // 1 = solo destinos inválidos
  // 2 = mezcla (válidos e inválidos)
  int dest_mode;

  rand int num;  
  constraint c1 { num inside {[2:50]}; }

  function new(string name="gen_mesh_seq"); 
    super.new(name); 
    dest_mode = 0; // por defecto: solo válidos
  endfunction

  virtual task body();
    for (int i = 0; i < num; i++) begin
      mesh_pkt m_item = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      start_item(m_item);

      case (dest_mode)
        0: begin
          // Solo destinos válidos
          void'(m_item.randomize() with { dest_valid == 1; });
        end
        1: begin
          // Solo destinos inválidos
          void'(m_item.randomize() with { dest_valid == 0; });
        end
        default: begin
          // Mezcla (dest_valid queda random)
          void'(m_item.randomize());
        end
      endcase

      `uvm_info("SEQ", $sformatf("Generate: %s", m_item.convert2str()), UVM_LOW)
      finish_item(m_item);
    end
  endtask
endclass
