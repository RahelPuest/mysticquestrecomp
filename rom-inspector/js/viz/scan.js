function render_scan(main) {
  const total = SCAN_RESULTS.totalScripts;
  const cleanPct = 100 * SCAN_RESULTS.clean / total;
  const haltPct = 100 * SCAN_RESULTS.haltUndecoded / total;
  const errPct = 100 * SCAN_RESULTS.errorOther / total;
  const maxCount = Math.max(...SCAN_RESULTS.topBlockers.map(b => b.count));

  main.innerHTML = `
    <h1 class="page-title">Whole-Corpus-Skript-Scan</h1>
    <p class="page-lede">
      Ein echter Lauf: alle ${total} Einträge der Skript-Zeigertabelle werden mit der
      aktuellen Interpreter-Abdeckung tatsächlich ausgeführt (nicht simuliert) &mdash;
      Budget ${SCAN_RESULTS.stepBudget} Schritte pro Skript, generischer Stub-Kontext
      (siehe <code>scripts/scan_all_scripts.lua</code> im Hauptprojekt für die exakte Methode
      inkl. ehrlicher Grenzen).
    </p>

    <div class="stack-bar" title="clean / halt (undekodiert) / sonstiger Fehler">
      <div style="width:${cleanPct}%; background:var(--ok);">${cleanPct >= 8 ? Math.round(cleanPct) + "%" : ""}</div>
      <div style="width:${haltPct}%; background:var(--error);">${haltPct >= 8 ? Math.round(haltPct) + "%" : ""}</div>
      <div style="width:${errPct}%; background:var(--warn); color:#241a00;">${errPct >= 8 ? Math.round(errPct) + "%" : ""}</div>
    </div>
    <div class="legend" style="margin-top:10px;">
      <span><span class="sw" style="background:var(--ok)"></span>clean (${SCAN_RESULTS.clean})</span>
      <span><span class="sw" style="background:var(--error)"></span>halt: undekodierter Opcode (${SCAN_RESULTS.haltUndecoded})</span>
      <span><span class="sw" style="background:var(--warn)"></span>sonstiger Laufzeitfehler (${SCAN_RESULTS.errorOther})</span>
    </div>

    <h2 class="section-title">Top-Blocker (Handler-Adressen, die die meisten Skripte aufhalten)</h2>
    <div id="blockerList"></div>
  `;

  const list = document.getElementById("blockerList");
  for (const b of SCAN_RESULTS.topBlockers) {
    const row = document.createElement("div");
    row.className = "hbar-row";
    const pct = 100 * b.count / maxCount;
    const label = b.names ? b.names[0] : (b.note ? "known-hard" : "");
    row.innerHTML = `
      <div class="addr">${escapeHtml(b.address)}</div>
      <div class="hbar-track"><div class="hbar-fill" style="width:${pct}%;"></div></div>
      <div class="count">${b.count}</div>
    `;
    row.title = (label ? label + " — " : "") + (b.note || "");
    row.style.cursor = "pointer";
    row.addEventListener("click", () => {
      const opcodeNum = parseInt(b.address, 16);
      const match = OPCODES.find(o => o.handler === opcodeNum);
      if (match) location.hash = "#opcodes?focus=" + match.opcode;
    });
    list.appendChild(row);
    if (b.note) {
      const note = document.createElement("div");
      note.style.cssText = "font-size:11.5px; color:var(--text-faint); margin: -2px 0 8px 100px;";
      note.textContent = b.note;
      list.appendChild(note);
    }
  }
}
