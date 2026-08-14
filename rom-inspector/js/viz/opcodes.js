// Interactive script step-tracer (2026-08-14, direct user request:
// "kannst du mal den ganzen script mechanismus mal in app... intuitiver
// darstellen. vielleicht mit einem beispielscript so das man verfolgen
// kann was passiert"). Walks one of `SCRIPT_EXAMPLES` (real ROM file
// offsets, see export_data.lua's own doc comment) opcode-by-opcode,
// live from the user's own locally loaded ROM -- one real interpreter
// STEP per click (matches `ScriptInterpreter:step()`'s own real
// semantics: one opcode byte consumed per step, whether it resolves
// to a no-op, a decoded handler, or an undecoded one).
//
// The ACTOR_ACTION pattern-match below is a direct, intentional 1:1
// port of `MapTable.lua`'s own `matchActorActionHandler` (same 3
// fixed byte sequences, same field positions) -- kept in sync
// manually since this is client-side JS with no access to the real
// Lua module; if that Lua function's own pattern ever changes, this
// copy needs the same edit (flagged here so it isn't missed).
function matchActorActionPattern(bytes, handlerAddr) {
  if (handlerAddr >= 0x4000 || !bytes) return null;
  const b = bytes.subarray(handlerAddr, handlerAddr + 11);
  if (b.length < 11) return null;
  if (!(b[0] === 0xCD && b[1] === 0xC2 && b[2] === 0x28)) return null; // CALL $28C2
  if (b[3] !== 0xC6) return null; // ADD A,n
  const group = b[4];
  if (!(b[5] === 0x4F && b[6] === 0x3E)) return null; // LD C,A / LD A,n
  const action = b[7];
  if (!(b[8] === 0xCD && b[9] === 0x79 && b[10] === 0x28)) return null; // CALL $2879
  return { group, action };
}

function render_script_tracer(container) {
  let cursor = null;
  let steps = [];
  let exampleIndex = 0;

  function resetToExample(idx) {
    exampleIndex = idx;
    cursor = SCRIPT_EXAMPLES[idx].scriptFileOffset;
    steps = [];
    renderTracer();
  }

  function stepOnce() {
    if (!RomBytes.isLoaded()) return;
    const bytes = RomBytes.bytes;
    const opcode = bytes[cursor];
    const entry = OPCODES.find(o => o.opcode === opcode);
    const desc = entry ? lookupOpcodeDescription(entry.names) : null;
    const actorAction = entry ? matchActorActionPattern(bytes, entry.handler) : null;
    steps.push({ cursor, opcode, entry, desc, actorAction });
    cursor += 1;
    renderTracer();
  }

  function renderTracer() {
    const stopped = steps.length && steps[steps.length - 1].entry &&
      steps[steps.length - 1].entry.status === "undecoded";
    container.innerHTML = `
      <h2 class="section-title">So funktioniert ein echtes Skript (Beispiel)</h2>
      <p style="color:var(--text-dim); font-size:13px; max-width:760px;">
        Ein echtes, ROM-gestütztes Beispiel-Skript wird hier Byte für Byte durchlaufen -- ein Klick
        auf „Schritt &rarr;“ entspricht genau EINEM echten Interpreter-Schritt
        (<code>ScriptInterpreter:step()</code>): ein Opcode-Byte wird gelesen, in der echten
        <code>scriptOpcodeTable</code> nachgeschlagen, und je nach Status entweder als No-Op
        übersprungen oder ausgeführt. Beide Beispiele sind echte Event-Skripte aus dem 320-Raum-
        Katalog (Bank 5) -- siehe <a href="#worldmap">Weltkarte</a>.
      </p>
      <div class="toolbar">
        <select id="scriptExampleSelect">
          ${SCRIPT_EXAMPLES.map((ex, i) => `<option value="${i}" ${i === exampleIndex ? "selected" : ""}>${escapeHtml(ex.title)}</option>`).join("")}
        </select>
        <button class="btn small" id="scriptStepBtn" ${stopped ? "disabled" : ""}>Schritt &rarr;</button>
        <button class="btn small" id="scriptResetBtn">Zurücksetzen</button>
      </div>
      <div id="scriptTraceLog" style="margin-top:8px;"></div>
    `;
    const select = document.getElementById("scriptExampleSelect");
    select.addEventListener("change", () => resetToExample(parseInt(select.value, 10)));
    document.getElementById("scriptStepBtn").addEventListener("click", stepOnce);
    document.getElementById("scriptResetBtn").addEventListener("click", () => resetToExample(exampleIndex));

    const log = document.getElementById("scriptTraceLog");
    if (!RomBytes.isLoaded()) {
      log.innerHTML = `<p style="color:var(--text-dim); font-size:13px;">Keine ROM geladen -- oben rechts „ROM laden…“, um das Beispiel live zu verfolgen.</p>`;
      return;
    }
    if (!steps.length) {
      log.innerHTML = `<p style="color:var(--text-dim); font-size:13px;">Startadresse: ${hex(cursor, 5)}. Klicke „Schritt &rarr;“ für den ersten echten Opcode.</p>`;
      return;
    }
    log.innerHTML = steps.map((s, i) => {
      const opHex = "0x" + s.opcode.toString(16).toUpperCase().padStart(2, "0");
      const name = s.entry && s.entry.names ? s.entry.names[0] : null;
      const status = s.entry ? s.entry.status : "unbekannt";
      let effect;
      if (s.actorAction) {
        effect = `<strong>Echter Effekt (direkt aus den Handler-Bytes disassembliert):</strong> reiht ` +
          `(group=${s.actorAction.group}, action=0x${s.actorAction.action.toString(16).padStart(2, "0")}) ` +
          `in die reale Actor-Command-Queue ein (WRAM $C4E0/$C5A0) -- siehe <a href="#worldmap">Weltkarte</a>-Overlay.`;
      } else if (s.desc) {
        effect = escapeHtml(s.desc.text);
      } else if (status === "default") {
        effect = "Echter, ROM-bestätigter No-Op -- der Interpreter geht direkt zum nächsten Byte über.";
      } else if (status === "undecoded") {
        effect = "Noch keine registrierte Lua-Implementierung für diesen Opcode -- der Interpreter würde hier real anhalten (siehe eigener „undecoded“-Status). Verfolgung endet ehrlich hier.";
      } else {
        effect = "";
      }
      return `
        <div class="panel" style="margin-bottom:6px; padding:10px 14px;">
          <div class="mono" style="font-size:13px;">
            Schritt ${i + 1} &middot; Adresse ${hex(s.cursor, 5)} &middot; Byte ${opHex}
            <span class="badge ${status}" style="margin-left:6px;">${status}</span>
          </div>
          ${name ? `<div class="mono" style="color:var(--accent2); font-size:12.5px; margin-top:2px;">${escapeHtml(name)} &rarr; Handler ${hex(s.entry.handler)}</div>` : ""}
          ${effect ? `<div style="font-size:13px; margin-top:4px; max-width:700px; line-height:1.5;">${effect}</div>` : ""}
        </div>`;
    }).join("");
  }

  resetToExample(0);
  onSectionUnload(RomBytes.onChange(renderTracer));
}

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

    <div id="scriptTracerHost"></div>

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

  render_script_tracer(document.getElementById("scriptTracerHost"));

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
