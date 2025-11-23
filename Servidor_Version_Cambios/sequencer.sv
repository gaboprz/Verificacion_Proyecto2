/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el sequencer
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)
  typedef enum {DEST_MODE_VALID, DEST_MODE_INVALID, DEST_MODE_MIXED} dest_mode_e;


  rand int num;  
  
  constraint c1 { num inside {[2:50]}; }

  function new(string name="gen_mesh_seq"); 
    super.new(name); 
  endfunction

  virtual task body();
    for (int i = 0; i < num; i++) begin
      mesh_pkt m_item = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      start_item(m_item);

      case (dest_mode)
        DEST_MODE_VALID:   m_item.dest_valid = 1'b1;
        DEST_MODE_INVALID: m_item.dest_valid = 1'b0;
        default:           m_item.dest_valid = (i % 2 == 0); // mezcla simple
          // podrías usar también: m_item.dest_valid = $urandom_range(0,1);
      endcase

      if (!m_item.randomize()) begin
        `uvm_error("SEQ", "Randomize falló para mesh_pkt")
      end

      `uvm_info("SEQ", $sformatf("Generate: %s (dest_valid=%0b)",
                  m_item.convert2str(), m_item.dest_valid), UVM_LOW)

      finish_item(m_item);
    end
  endtask
endclass