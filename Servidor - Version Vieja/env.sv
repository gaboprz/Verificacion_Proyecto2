/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Se define el ambiente
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// =======================================================
// ENV: crea N agentes, crea el scoreboard y conecta:
//   driver.drv_ap      -> scb.ingress_imp
//   monitor.mon_ap     -> scb.egress_imp
// Usa config_db("NUM_DEVS") para fijar cuántos agentes.
// =======================================================
class mesh_env extends uvm_env;
  `uvm_component_utils(mesh_env)

  // Número de puertos/agentes externos (por defecto 1)
  int unsigned NUM_DEVS = `NUM_DEVS;

  // Arreglo de agentes
  external_agent   agents[];

  // Scoreboard
  mesh_scoreboard  scb;

  function new(string name="mesh_env", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  // -----------------------------
  // BUILD
  // -----------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Permitir override por config_db
    void'(uvm_config_db#(int unsigned)::get(this, "", "NUM_DEVS", NUM_DEVS));
    if (NUM_DEVS == 0)
      `uvm_fatal("ENV_CFG", "NUM_DEVS debe ser >= 1")

    // Crear scoreboard
    scb = mesh_scoreboard::type_id::create("scb", this);

    // Crear agentes y asignar device_id
    agents = new[NUM_DEVS];
    foreach (agents[i]) begin
      string aname = $sformatf("agent_%0d", i);
      agents[i] = external_agent::type_id::create(aname, this);
      agents[i].device_id = i;
      
      `uvm_info("ENV", $sformatf("Agente %0d creado", i), UVM_MEDIUM)
    end

    `uvm_info("ENV", $sformatf("=== %0d agentes y 1 scoreboard creados ===", NUM_DEVS), UVM_LOW)
  endfunction

  // -----------------------------
  // CONNECT
  // -----------------------------
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    `uvm_info("ENV", "=== Conectando componentes ===", UVM_LOW)

    foreach (agents[i]) begin
      // DRIVER → SCOREBOARD (ingreso confirmado tras pop==1)
      agents[i].d0.drv_ap.connect(scb.ingress_imp);

      // MONITOR → SCOREBOARD (egreso observado, mesh_pkt)
      agents[i].m0.mon_ap.connect(scb.egress_imp);
    end
  endfunction
endclass
