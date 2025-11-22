/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el sequencer
/////////////////////////////////////////////////////////////////////////////////////////////////////////

class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)
  rand int num;
  constraint c1 { num inside {[2:50]}; }

  function new(string name="gen_mesh_seq"); 
    super.new(name); 
  endfunction

  virtual task body();
    // castear el p_sequencer para acceder a la vif y su clk
    mesh_sequencer seqr;
    if (!$cast(seqr, p_sequencer)) `uvm_fatal("SEQ", "No pude castear p_sequencer a mesh_sequencer");

    for (int i = 0; i < num; i++) begin
      mesh_pkt tr = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      start_item(tr);
      assert(tr.randomize());
      tr.t_created = $time;

      // <<< AQUÍ está el jitter de envío >>>
      repeat (tr.send_gap_cycles) @(posedge seqr.vif.clk);

      tr.t_ready = $time;
      `uvm_info("SEQ", $sformatf("Item %0d: gap=%0d ciclos (%0t→%0t) %s",
                 i, tr.send_gap_cycles, tr.t_created, tr.t_ready, tr.convert2str()), UVM_LOW)

      finish_item(tr);
    end
  endtask
endclass