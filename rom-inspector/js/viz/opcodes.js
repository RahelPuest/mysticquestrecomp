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
        übersprungen oder ausgeführt. Beide Beispiele sind echte Event-Skripte aus dem 384-Raum-
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
        effect = escapeHtml(s.desc.summary);
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

// Real control-code sub-system opcode 0x04's own classifier dispatches
// through (byte values 0x10-0x1F read directly off the live script
// cursor, NOT separate top-level opcodes -- see CONTROL_CODES's own
// header comment in js/data/control-codes.js / export_data.lua for the
// full real evidence trail). Found + fixed 2026-08-15 (tasks #141-147)
// via live mgba tracing + static disassembly of the real ROM. Shown
// as its own panel because these bytes are invisible to the primary
// 256-opcode grid above -- opcode 0x04 alone "owns" them.
function render_control_codes(container) {
  const statusColor = {
    "generalisiert, sicher": "rgba(107,207,127,.4)",
    "live-confirmed (pacing only)": "rgba(240,192,90,.4)",
  };
  function swatchFor(status) {
    return statusColor[status] || "rgba(120,150,240,.4)"; // occurrence-specific default
  }
  container.innerHTML = `
    <h2 class="section-title">Control-Code-Subsystem von Opcode 0x04 (Pinning)</h2>
    <p style="color:var(--text-dim); font-size:13px; max-width:760px; line-height:1.6;">
      Opcode <code>0x04</code> ist real ein eigener Klassifikator: er liest laufend weitere,
      selbst gewählte Bytes direkt vom Skript-Cursor (<code>0x10</code>-<code>0x1F</code>), OHNE
      dass die reale ROM den normalen Opcode-Fetch (<code>$3727</code>) erneut aufruft. Die reale
      ROM „pinnt" dafür ihr eigenes WRAM-Register „aktueller Opcode" ($D85A) über viele echte
      Ticks auf <code>0x04</code>, indem <code>$36D0</code> (die Control-Code-/Text-Freigabe-
      Routine) den Cursor weiterschiebt UND <code>$D85A=0x04</code> direkt neu setzt &mdash;
      ohne je wieder <code>$3727</code> aufzurufen. Diese Website-Software hatte diese Struktur
      lange nicht nachgebildet: jeder Tick las <code>stream[cursor]</code> als frischen Top-
      Level-Opcode neu ein, was echte Textbytes gelegentlich rein numerisch mit unabhängigen
      Opcodes kollidieren ließ. Die Lösung: <code>ScriptInterpreter:step()</code> akzeptiert jetzt
      einen optionalen <code>pinnedOpcode</code>-Parameter, und jeder Handler kann per zweitem
      Rückgabewert <code>pin</code> verlangen, dass der NÄCHSTE Tick denselben Opcode direkt
      erneut aufruft, statt den Cursor-Inhalt als neuen Opcode zu interpretieren.
    </p>
    <p style="color:var(--text-dim); font-size:13px; max-width:760px; line-height:1.6;">
      Mit allen unten bestätigten Control-Codes verdrahtet läuft dieses Projekts eigener
      <code>BossSequenceInterpreter</code> jetzt das GESAMTE verbleibende reale Boss-Defeat-Skript
      sauber durch und erreicht den echten Opcode-<code>0x00</code>-Queue-Gate &mdash; denselben
      Fund, mit dem diese gesamte Untersuchung an diesem Tag begann (siehe
      <code>docs/reverse-engineering/events.md</code>).
    </p>
    <div class="opcode-grid" style="grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));">
      ${CONTROL_CODES.map(c => `
        <div class="panel" style="padding:10px 14px;">
          <div class="mono" style="font-size:13px;">
            Byte 0x${c.byte.toString(16).toUpperCase().padStart(2, "0")}
            <span style="margin-left:6px; font-size:11px; padding:2px 6px; border-radius:4px; background:${swatchFor(c.status)};">${escapeHtml(c.status)}</span>
          </div>
          <div style="font-size:13px; font-weight:600; margin-top:4px;">${escapeHtml(c.title)}</div>
          <div class="mono" style="color:var(--accent2); font-size:12px; margin-top:2px;">Handler: ${escapeHtml(c.handler)}</div>
          <div style="font-size:12.5px; margin-top:6px; line-height:1.55; color:var(--text-dim);">${escapeHtml(c.note)}</div>
        </div>
      `).join("")}
    </div>
  `;
}

// A short, collapsible glossary for the recurring technical jargon in
// this page's own opcode descriptions (js/data/opcode-descriptions.js's
// own OPCODE_GLOSSARY -- added 2026-08-15, direct user feedback: "die
// optcodes seite... ist sehr kryptisch. vor allem die beschreibnbenden
// texte"). Collapsed by default (a reader who already knows the terms
// shouldn't have to scroll past it) but easy to find right above the
// opcode grid.
function render_glossary(container) {
  const terms = (typeof OPCODE_GLOSSARY !== "undefined") ? OPCODE_GLOSSARY : [];
  if (!terms.length) { container.innerHTML = ""; return; }
  container.innerHTML = `
    <details class="panel" style="margin:12px 0; padding:10px 14px;">
      <summary style="cursor:pointer; font-size:13px; font-weight:600;">
        Begriffs-Glossar (${terms.length} Fachbegriffe erklärt)
      </summary>
      <div style="margin-top:10px; display:grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap:10px;">
        ${terms.map(t => `
          <div>
            <div class="mono" style="color:var(--accent2); font-size:12.5px; font-weight:600;">${escapeHtml(t.term)}</div>
            <div style="font-size:12.5px; color:var(--text-dim); line-height:1.5; margin-top:2px;">${escapeHtml(t.def)}</div>
          </div>
        `).join("")}
      </div>
    </details>
  `;
}

function render_opcodes(main) {
  const params = new URLSearchParams(location.hash.split("?")[1] || "");
  const focusOpcode = params.has("focus") ? parseInt(params.get("focus"), 10) : null;

  main.innerHTML = `
    <h1 class="page-title">Skript-Opcode-Explorer</h1>
    <p class="page-lede" style="font-size:15px;">
      Dieses ROM enthält eine eigene kleine „Skriptsprache“ &mdash; eine Folge von
      Steuer-Bytes (<strong>Opcodes</strong>), die Dialoge, Kämpfe, Ereignisse und
      NPC-Verhalten steuert. Diese Seite zeigt alle 256 möglichen Opcode-Werte
      und was dieses Projekt über jeden einzelnen real herausgefunden hat &mdash;
      per echtem Reverse Engineering der ROM, nicht geraten. Klicke unten auf
      eine Kachel für Details, oder probiere zuerst das Beispiel-Skript.
    </p>
    <p class="page-lede">
      Technisch: alle 256 Einträge der primären Opcode-Tabelle (Bank 2, $8576, 2
      Bytes/Eintrag, indiziert über das reale WRAM-Register „aktueller Opcode“
      $D85A). Status wird nicht von Hand vergeben, sondern durch tatsächliches
      Bauen eines <code>ScriptRuntime</code> ermittelt: <em>decoded</em> heißt,
      es existiert eine echte registrierte Lua-Implementierung für die reale
      ROM-Handler-Adresse.
    </p>

    <div id="scriptTracerHost"></div>

    <div class="legend">
      <span><span class="sw" style="background:rgba(107,207,127,.4)"></span>decoded (${OPCODES.filter(o=>o.status==="decoded").length})</span>
      <span><span class="sw" style="background:rgba(138,148,166,.4)"></span>default/No-Op (${OPCODES.filter(o=>o.status==="default").length})</span>
      <span><span class="sw" style="background:rgba(240,192,90,.4)"></span>known-hard (${OPCODES.filter(o=>o.status==="known-hard").length})</span>
      <span><span class="sw" style="background:rgba(240,113,90,.4)"></span>undecoded (${OPCODES.filter(o=>o.status==="undecoded").length})</span>
    </div>

    <div id="glossaryHost"></div>

    <div class="toolbar">
      <div class="pill-tabs" id="statusTabs">
        ${["all", "decoded", "default", "known-hard", "undecoded"].map(s =>
          `<div class="pill-tab${s === "all" ? " active" : ""}" data-status="${s}">${s}</div>`).join("")}
      </div>
      <input type="text" id="opcodeSearch" placeholder="Name oder Handler-Adresse&hellip;" style="width:240px;">
    </div>

    <div class="opcode-grid" id="opcodeGrid"></div>
    <div id="opcodeDetail" class="panel"></div>

    <div id="controlCodesHost" style="margin-top:28px;"></div>
  `;

  render_script_tracer(document.getElementById("scriptTracerHost"));
  render_control_codes(document.getElementById("controlCodesHost"));
  render_glossary(document.getElementById("glossaryHost"));

  const grid = document.getElementById("opcodeGrid");
  const cells = {};
  for (const o of OPCODES) {
    const cell = document.createElement("div");
    cell.className = "opcode-cell " + o.status;
    cell.textContent = o.opcode.toString(16).toUpperCase().padStart(2, "0");
    const desc = lookupOpcodeDescription(o.names);
    cell.title = `Opcode 0x${cell.textContent}${desc ? " — " + desc.title + ": " + desc.summary : ""}`;
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
        const hay = (o.names ? o.names.join(" ") : "") + " " + hex(o.handler) + " " + o.opcode.toString(16) + " " + (desc ? desc.title + " " + desc.summary + " " + desc.text : "");
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
    const detailId = "opcodeTechDetail_" + o.opcode;
    detail.innerHTML = `
      <h3 style="margin-top:0;">Opcode 0x${o.opcode.toString(16).toUpperCase().padStart(2, "0")}${desc ? " — " + escapeHtml(desc.title) : ""} <span class="badge ${o.status}">${o.status}</span></h3>
      <div class="mono" style="color:var(--accent2); font-size:14px; margin-bottom:8px;">Handler: ${hex(o.handler)}</div>
      ${desc ? `<p style="color:var(--text); font-size:15px; max-width:680px; line-height:1.6; font-weight:500;">${escapeHtml(desc.summary)}</p>` : ""}
      ${o.names ? `<div style="margin-bottom:8px;">${o.names.map(n => `<span class="badge default" style="margin-right:6px;">${escapeHtml(n)}</span>`).join("")}</div>` : ""}
      ${o.note ? `<p style="color:var(--warn); font-size:13px; max-width:640px;">${escapeHtml(o.note)}</p>` : ""}
      ${(!o.names && o.status === "undecoded") ? `<p style="color:var(--text-dim); font-size:13px;">Kein registrierter Handler, keine bekannte Konstante &mdash; dieser Opcode ist bisher gar nicht untersucht oder nur teilweise disassembliert.</p>` : ""}
      ${(!desc && o.names && o.status === "decoded") ? `<p style="color:var(--text-faint); font-size:12px;">(Noch keine kuratierte Beschreibung für diese Konstante in <code>opcode-descriptions.js</code> &mdash; siehe Konstantennamen oben.)</p>` : ""}
      ${desc ? `
        <details style="margin-top:10px;">
          <summary style="cursor:pointer; color:var(--text-dim); font-size:12.5px;">Technische Details (echte ROM-Adressen &amp; Nachweis)</summary>
          <p id="${detailId}" style="color:var(--text-dim); font-size:12.5px; max-width:680px; line-height:1.6; margin-top:8px;"></p>
        </details>` : ""}
    `;
    if (desc) {
      // Set via textContent + a small glossary-hover pass, not raw innerHTML,
      // so the real technical text (containing real hex addresses, WRAM
      // cells, etc.) can't accidentally be parsed as markup.
      document.getElementById(detailId).innerHTML = glossarize(desc.text);
    }
  }

  // Wraps the FIRST occurrence of each glossary term (js/data/
  // opcode-descriptions.js's own OPCODE_GLOSSARY) in a real HTML
  // `<abbr>` with the plain-language definition as a native browser
  // tooltip -- so a reader hitting unfamiliar jargon INSIDE a
  // technical-detail paragraph can hover it right there instead of
  // needing to separately consult the glossary box above.
  function glossarize(text) {
    let html = escapeHtml(text);
    if (typeof OPCODE_GLOSSARY === "undefined") return html;
    for (const { term, def } of OPCODE_GLOSSARY) {
      // Multi-word/compound display terms (e.g. "Pin / Pinning",
      // "Dispatch(er)") match on their own FIRST plain word only --
      // the glossary box above still shows the full term+definition,
      // this inline hover is a convenience, not the source of truth.
      const matchWord = term.split(/[\s/(]/)[0];
      if (!matchWord) continue;
      const re = new RegExp("\\b(" + matchWord.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\w*)\\b");
      html = html.replace(re, `<abbr title="${escapeHtml(def)}" style="text-decoration-style:dotted; cursor:help;">$1</abbr>`);
    }
    return html;
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
