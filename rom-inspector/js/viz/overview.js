function render_overview(main) {
  const decoded = OPCODES.filter(o => o.status === "decoded").length;
  const dflt = OPCODES.filter(o => o.status === "default").length;
  const hard = OPCODES.filter(o => o.status === "known-hard").length;
  const undecoded = OPCODES.filter(o => o.status === "undecoded").length;
  const cleanPct = Math.round(100 * SCAN_RESULTS.clean / SCAN_RESULTS.totalScripts);

  main.innerHTML = `
    <h1 class="page-title">Mystic Quest &mdash; ROM Inspector</h1>
    <p class="page-lede">
      Eine interaktive Referenz für die reale, per Reverse Engineering erschlossene
      Struktur der ROM von <em>Mystic Quest</em> (Game Boy, EU-Fassung von
      <em>Final Fantasy Adventure</em> / <em>Seiken Densetsu 1</em>): Speicherlayout,
      Skript-Interpreter, Opcode-Tabelle, Raum-System und Text-Encoding &mdash; mit
      klickbaren Visualisierungen statt reinem Fließtext. Alle Daten stammen entweder
      aus einem echten Lauf gegen die ROM-Datei oder sind explizit als kuratiert markiert
      (siehe Fußzeile jeder Seite).
    </p>

    <h2 class="section-title">ROM-Eckdaten</h2>
    <div class="stat-grid">
      <div class="stat-card"><div class="value small">${ROM_BASICS.displayName}</div><div class="label">Erkannte Revision</div></div>
      <div class="stat-card"><div class="value">${ROM_BASICS.bankCount}</div><div class="label">ROM-Banks à ${ROM_BASICS.bankSize / 1024} KiB</div></div>
      <div class="stat-card"><div class="value">${(ROM_BASICS.sizeBytes / 1024).toFixed(0)} KiB</div><div class="label">Gesamtgröße</div></div>
      <div class="stat-card"><div class="value small">${ROM_BASICS.cartridgeType}</div><div class="label">Mapper</div></div>
      <div class="stat-card"><div class="value small mono">${ROM_BASICS.sha1.slice(0, 12)}&hellip;</div><div class="label">SHA-1</div></div>
    </div>

    <h2 class="section-title">Skript-Opcode-Abdeckung <a href="#opcodes" style="font-size:11px;">&rarr; Explorer</a></h2>
    <div class="stat-grid">
      <div class="stat-card ok"><div class="value">${decoded}</div><div class="label">dekodiert &amp; implementiert</div></div>
      <div class="stat-card"><div class="value">${dflt}</div><div class="label">bestätigtes No-Op</div></div>
      <div class="stat-card warn"><div class="value">${hard}</div><div class="label">bekannt schwer / bewusst offen</div></div>
      <div class="stat-card error"><div class="value">${undecoded}</div><div class="label">noch undekodiert</div></div>
    </div>

    <h2 class="section-title">Whole-Corpus-Skript-Scan <a href="#scan" style="font-size:11px;">&rarr; Details</a></h2>
    <p style="color:var(--text-dim); font-size:13px; max-width:700px;">
      Alle ${SCAN_RESULTS.totalScripts} echten Einträge der Skript-Zeigertabelle wurden mit der
      aktuellen Interpreter-Abdeckung tatsächlich ausgeführt (Budget: ${SCAN_RESULTS.stepBudget} Schritte).
      <strong>${cleanPct}%</strong> laufen sauber durch.
    </p>
    <div class="stat-grid">
      <div class="stat-card ok"><div class="value">${SCAN_RESULTS.clean}</div><div class="label">clean</div></div>
      <div class="stat-card error"><div class="value">${SCAN_RESULTS.haltUndecoded}</div><div class="label">halt: undekodierter Opcode</div></div>
      <div class="stat-card warn"><div class="value">${SCAN_RESULTS.errorOther}</div><div class="label">sonstiger Laufzeitfehler</div></div>
    </div>

    <h2 class="section-title">Raum-Katalog <a href="#map" style="font-size:11px;">&rarr; Map-Viewer</a></h2>
    <p style="color:var(--text-dim); font-size:13px; max-width:700px;">
      Alle ${ROOM_CATALOG.length} echten Bank-5/Bank-6-Einträge (256 + 64) dekodieren strukturell
      sauber (echte, nicht-verrauschte GB-Kacheln) -- über den <strong>Map-Viewer</strong> einzeln
      durchblätterbar. Nur ${ROOM_CATALOG.filter(r => r.confirmed).length} davon (unknownRoomA) haben
      eine unabhängig bestätigte Metatile-Tabelle -- <strong>bei allen anderen ist die gezeigte
      Kachel-Zuordnung ein unverifizierter Platzhalter und sehr wahrscheinlich falsch</strong>
      (direkter Nutzerbefund 2026-08-14, siehe rom-map.md).
    </p>
    <div class="stat-grid">
      <div class="stat-card"><div class="value">${ROOM_CATALOG.length}</div><div class="label">strukturell dekodierte Katalog-Einträge</div></div>
      <div class="stat-card ok"><div class="value">${ROOM_CATALOG.filter(r => r.confirmed).length}</div><div class="label">mit bestätigter Kachel-Zuordnung</div></div>
      <div class="stat-card"><div class="value">${ROOMS.length}</div><div class="label">real verbundene Räume (Gameplay)</div></div>
    </div>

    <h2 class="section-title">Bereiche</h2>
    <div class="card-grid">
      ${SECTIONS.filter(s => s.id !== "overview").map(s => `
        <div class="card" style="cursor:pointer" onclick="location.hash='#${s.id}'">
          <h3>${s.icon} ${s.label}</h3>
          <div class="desc">${sectionBlurb(s.id)}</div>
        </div>`).join("")}
    </div>
  `;
}

function sectionBlurb(id) {
  return {
    memory: "ROM-Bank-Layout und bekannte WRAM-Zellen &mdash; klickbar.",
    entity: "Der 20-Slot-Entity-Struct: Slot-Index verschieben, Felder live sehen.",
    tables: "Jede bekannte, verifizierte ROM-Tabelle mit Bank/Offset/Status.",
    opcodes: "Alle 256 Skript-Opcodes als durchsuchbares Raster.",
    scan: "Live-Lauf aller 1357 echten Skripte gegen die aktuelle Abdeckung.",
    rooms: "Der bekannte Raum-Graph mit echten Übergangsmechanismen.",
    map: "Echte Raum-Tilemaps live zusammengesetzt -- die 8 verbundenen Räume plus alle 320 Katalog-Einträge (Kachel-Zuordnung nur für 6 davon bestätigt).",
    tiles: "Einzelne 8×8-Kacheln aus jeder bekannten Tileset-Adresse ansehen.",
    text: "Die Text-Encoding-Tabellen &mdash; live an echten ROM-Bytes ausprobieren.",
    questions: "Was diese Untersuchung (noch) nicht beantworten kann.",
  }[id] || "";
}
