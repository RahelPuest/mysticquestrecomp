function render_opcodes(main) {
  const params = new URLSearchParams(location.hash.split("?")[1] || "");
  const focusOpcode = params.has("focus") ? parseInt(params.get("focus"), 10) : null;

  main.innerHTML = `
    <h1 class="page-title">Skript-Opcode-Explorer</h1>
    <p class="page-lede">
      Alle 256 Einträge der primären Opcode-Tabelle (Bank 2, $8576, 2 Bytes/Eintrag,
      indiziert über das reale WRAM-Register „aktueller Opcode“ $D85A). Status wird nicht
      von Hand vergeben, sondern durch tatsächliches Bauen eines <code>ScriptRuntime</code>
      ermittelt: <em>decoded</em> heißt, es existiert eine echte registrierte Lua-Implementierung
      für die reale ROM-Handler-Adresse.
    </p>

    <div class="legend">
      <span><span class="sw" style="background:rgba(107,207,127,.4)"></span>decoded (${OPCODES.filter(o=>o.status==="decoded").length})</span>
      <span><span class="sw" style="background:rgba(138,148,166,.4)"></span>default/No-Op (${OPCODES.filter(o=>o.status==="default").length})</span>
      <span><span class="sw" style="background:rgba(240,192,90,.4)"></span>known-hard (${OPCODES.filter(o=>o.status==="known-hard").length})</span>
      <span><span class="sw" style="background:rgba(240,113,90,.4)"></span>undecoded (${OPCODES.filter(o=>o.status==="undecoded").length})</span>
    </div>

    <div class="toolbar">
      <div class="pill-tabs" id="statusTabs">
        ${["all", "decoded", "default", "known-hard", "undecoded"].map(s =>
          `<div class="pill-tab${s === "all" ? " active" : ""}" data-status="${s}">${s}</div>`).join("")}
      </div>
      <input type="text" id="opcodeSearch" placeholder="Name oder Handler-Adresse&hellip;" style="width:240px;">
    </div>

    <div class="opcode-grid" id="opcodeGrid"></div>
    <div id="opcodeDetail" class="panel"></div>
  `;

  const grid = document.getElementById("opcodeGrid");
  const cells = {};
  for (const o of OPCODES) {
    const cell = document.createElement("div");
    cell.className = "opcode-cell " + o.status;
    cell.textContent = o.opcode.toString(16).toUpperCase().padStart(2, "0");
    const desc = lookupOpcodeDescription(o.names);
    cell.title = `Opcode 0x${cell.textContent}${desc ? " — " + desc.title : ""} -> handler ${hex(o.handler)}`;
    cell.addEventListener("click", () => showOpcodeDetail(o));
    grid.appendChild(cell);
    cells[o.opcode] = cell;
  }

  let activeStatus = "all";
  let activeQuery = "";
  function applyFilter() {
    for (const o of OPCODES) {
      const cell = cells[o.opcode];
      let visible = true;
      if (activeStatus !== "all" && o.status !== activeStatus) visible = false;
      if (activeQuery) {
        const desc = lookupOpcodeDescription(o.names);
        const hay = (o.names ? o.names.join(" ") : "") + " " + hex(o.handler) + " " + o.opcode.toString(16) + " " + (desc ? desc.title + " " + desc.text : "");
        if (!hay.toLowerCase().includes(activeQuery)) visible = false;
      }
      cell.classList.toggle("dim", !visible);
    }
  }
  document.querySelectorAll("#statusTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#statusTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      activeStatus = tab.dataset.status;
      applyFilter();
    });
  });
  document.getElementById("opcodeSearch").addEventListener("input", (e) => {
    activeQuery = e.target.value.toLowerCase();
    applyFilter();
  });

  function showOpcodeDetail(o) {
    document.querySelectorAll(".opcode-cell").forEach(c => c.style.outline = "");
    cells[o.opcode].style.outline = "2px solid var(--accent)";
    const detail = document.getElementById("opcodeDetail");
    const desc = lookupOpcodeDescription(o.names);
    detail.innerHTML = `
      <h3 style="margin-top:0;">Opcode 0x${o.opcode.toString(16).toUpperCase().padStart(2, "0")}${desc ? " — " + escapeHtml(desc.title) : ""} <span class="badge ${o.status}">${o.status}</span></h3>
      <div class="mono" style="color:var(--accent2); font-size:14px; margin-bottom:8px;">Handler: ${hex(o.handler)}</div>
      ${desc ? `<p style="color:var(--text); font-size:13.5px; max-width:680px; line-height:1.6;">${escapeHtml(desc.text)}</p>` : ""}
      ${o.names ? `<div style="margin-bottom:8px;">${o.names.map(n => `<span class="badge default" style="margin-right:6px;">${escapeHtml(n)}</span>`).join("")}</div>` : ""}
      ${o.note ? `<p style="color:var(--warn); font-size:13px; max-width:640px;">${escapeHtml(o.note)}</p>` : ""}
      ${(!o.names && o.status === "undecoded") ? `<p style="color:var(--text-dim); font-size:13px;">Kein registrierter Handler, keine bekannte Konstante &mdash; dieser Opcode ist bisher gar nicht untersucht oder nur teilweise disassembliert.</p>` : ""}
      ${(!desc && o.names && o.status === "decoded") ? `<p style="color:var(--text-faint); font-size:12px;">(Noch keine kuratierte Beschreibung für diese Konstante in <code>opcode-descriptions.js</code> &mdash; siehe Konstantennamen oben.)</p>` : ""}
    `;
  }

  if (focusOpcode !== null) {
    const found = OPCODES.find(o => o.opcode === focusOpcode);
    if (found) {
      showOpcodeDetail(found);
      cells[focusOpcode].scrollIntoView({ block: "center" });
    }
  } else {
    document.getElementById("opcodeDetail").innerHTML = `<p style="color:var(--text-dim);">Klicke eine Zelle für Details.</p>`;
  }
}
