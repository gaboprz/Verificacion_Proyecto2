class gen_mesh_seq extends uvm_sequence #(mesh_pkt);
  `uvm_object_utils(gen_mesh_seq)
  `uvm_declare_p_sequencer(mesh_sequencer) // << ahora podemos ver p_sequencer.vif.clk

  // “knobs” configurables (puedes tunearlos por config_db o plusargs)
  rand int unsigned pre_gap_cyc;   // ciclos aleatorios ANTES de cada envío
  rand int unsigned post_gap_cyc;  // (opcional) ciclos después del envío

  // rangos (por defecto)
  int unsigned pre_gap_min  = 0;
  int unsigned pre_gap_max  = 20;
  int unsigned post_gap_min = 0;
  int unsigned post_gap_max = 3;

  // constraints
  constraint c_pre_gap  { pre_gap_cyc  inside {[pre_gap_min :  pre_gap_max]}; }
  constraint c_post_gap { post_gap_cyc inside {[post_gap_min : post_gap_max]}; }

  // cantidad de mensajes
  rand int num;
  constraint c1 { num inside {[2:50]}; }

  function new(string name="gen_mesh_seq"); super.new(name); endfunction

  // (opcional) tomar plusargs para no recompilar
  function void pre_start();
    void'($value$plusargs("PRE_GAP_MAX=%d", pre_gap_max));
    void'($value$plusargs("POST_GAP_MAX=%d", post_gap_max));
  endfunction

  virtual task body();
    for (int i = 0; i < num; i++) begin
      // 1) Espera aleatoria ANTES de crear/enviar el paquete
      assert(std::randomize(pre_gap_cyc));
      repeat (pre_gap_cyc) @(posedge p_sequencer.vif.clk);

      // 2) Crear y enviar el item
      mesh_pkt m_item = mesh_pkt::type_id::create($sformatf("m_item_%0d", i));
      start_item(m_item);
      void'(m_item.randomize());
      `uvm_info("SEQ",
        $sformatf("Agt%0d: pkt%0d pre_gap=%0d cyc -> %s",
          p_sequencer.device_id, i, pre_gap_cyc, m_item.convert2str()),
        UVM_LOW)
      finish_item(m_item);

      // 3) (opcional) espera aleatoria DESPUÉS de enviarlo
      assert(std::randomize(post_gap_cyc));
      repeat (post_gap_cyc) @(posedge p_sequencer.vif.clk);
    end
  endtask
endclass
