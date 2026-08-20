// NPC/monster spawn table (js/data/npc-spawn-table.js, NpcSpawnTable.lua)
// -- the real mechanism behind every placed creature in this game,
// found 2026-08-20. Reuses `drawSpriteGrid` (js/viz/monsters.js) for
// real sprite previews resolved via ActorDefinitionTable's own ID
// space -- see that data file's own header comment for the full
// cross-link story.

function npcSpawnCols(count) {
  // Real tileOffsets counts seen so far are either 4 (a 16x16 NPC
  // portrait, ActorDefinitionTable's "humanoid4pose" family) or 16 (a
  // 32x32 monster block, the same shape MonsterDefinitionTable's own
  // bosses use) -- pick a sane grid width for either, and fall back to
  // a generic 4-wide strip for anything else rather than guessing a
  // single "the" width.
  if (count === 4) return 2;
  if (count === 16) return 4;
  return 4;
}

function render_npcspawn(main) {
  const data = (typeof NPC_SPAWN_TABLE !== "undefined") ? NPC_SPAWN_TABLE : null;
  if (!data) {
    main.innerHTML = "<p>Keine Daten geladen.</p>";
    return;
  }

  main.innerHTML = `
    <h1 class="page-title">NPC-/Monster-Spawn-Tabelle</h1>
    <p class="page-lede" style="font-size:15px;">
      Der reale Mechanismus hinter JEDER platzierten Kreatur in diesem Spiel
      &mdash; gefunden 2026-08-20 beim gezielten Durchsuchen der externen
      FFA-Disassembly nach ihrem Encounter-/Spawn-Code (nicht nur nach
      Boss-Werten, wie zuvor). Zwei echte Skript-Opcodes steuern sie: der
      erste (<a href="#opcodes?focus=252">0xFC</a>, <code>sSET_NPC_TYPES</code>)
      wählt eine der ${data.rowCount} Zeilen, der zweite
      (<a href="#opcodes?focus=253">0xFD</a>, <code>sSPAWN_NPC</code>) erzeugt
      eine Kreatur aus einer der ${data.colsPerRow} Spalten dieser Zeile.
    </p>
    <p class="page-lede">
      Bank 3, CPU $7142, byte-identisch zur US-Cartridge (externe
      FFA-Disassembly, <code>NPCSpawnPointers</code>). Jede Spalte trägt 4
      Kandidaten-IDs (real eine per Zufall gewählt, meist alle 4 identisch),
      eine Min/Max-Spawnanzahl, und entweder echte Positionen oder
      „zufällige Position" ($80,$80-Terminator). Die Sprite-Vorschauen
      kommen &mdash; wo auflösbar &mdash; von der bereits unabhängig
      gefundenen <a href="#actors">Akteur-Tabelle</a> (ActorDefinitionTable):
      derselbe reale ID-Raum, aus zwei komplett getrennten
      Untersuchungssitzungen gefunden.
    </p>
    <p class="page-lede" style="color:var(--text-dim); font-size:13px;">
      Namen sind eine externe, quellenbelegte Referenz (FFA-Disassembly) &mdash;
      nur für 4 IDs live bestätigt (siehe unten), nicht für alle 191
      einzeln nachgeprüft. Diese Seite unterscheidet NICHT zwischen
      feindlichen Kreaturen, freundlichen NPCs und Story-Bossen &mdash;
      dafür gibt es kein dekodiertes ROM-Merkmal (nur echte Tür-/
      Kisten-Auslöser, siehe „Umgebungs-Trigger" unten, sind sicher
      keine platzierte Figur). Ein Name wie „Willy" oder „Goblin" ist
      genau das: ein Name, keine Klassifizierung.
    </p>
    <div id="npcSpawnRomBanner"></div>

    <h2 class="page-title" style="font-size:1.3em; margin-top:24px;">Live bestätigte Beispiele</h2>
    <p class="page-lede">
      3 feuern natürlich im unveränderten ROM (willyRoom/secondRoom); der
      Goblin wurde nur über einen 2-Byte-ROM-Patch erreicht, der einen
      bereits real feuernden Trigger umlenkte &mdash; siehe
      docs/reverse-engineering/events.md, 2026-08-20 „SOLVED"-Eintrag.
    </p>
    <div class="card-grid" id="npcSpawnVerified" style="margin-top:12px;"></div>

    <h2 class="page-title" style="font-size:1.3em; margin-top:28px;">Alle ${data.rowCount} Zeilen</h2>
    <div class="toolbar" style="margin:12px 0; gap:10px; flex-wrap:wrap;">
      <input type="text" id="npcSpawnSearch" placeholder="Suche nach Name oder ID…" style="flex:1; min-width:200px;">
      <div class="pill-tabs" id="npcSpawnFilterTabs">
        <div class="pill-tab active" data-filter="all">Alle</div>
        <div class="pill-tab" data-filter="creature">Ohne Umgebungs-Trigger</div>
      </div>
    </div>
    <div id="npcSpawnRowCount" style="font-size:12.5px; color:var(--text-dim); margin-bottom:10px;"></div>
    <div id="npcSpawnRows"></div>
  `;

  updateRomBanner(document.getElementById("npcSpawnRomBanner"));
  const pendingDraws = [];
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("npcSpawnRomBanner"));
    pendingDraws.forEach(fn => fn());
  }));

  function colCard(col, compact) {
    const name = col.candidateNames[0] || `unbekannt (${col.candidateIds[0]})`;
    const allSame = col.candidateIds.every(id => id === col.candidateIds[0]);
    const idsLabel = allSame ? `ID ${col.candidateIds[0]}` :
      `IDs ${[...new Set(col.candidateIds)].join("/")} (zufällig)`;
    const posLabel = col.isRandomPosition ? "zufällige Position" :
      `${col.positions.length} feste Position${col.positions.length === 1 ? "" : "en"}`;
    const wrap = document.createElement("div");
    wrap.style.cssText = "display:flex; flex-direction:column; align-items:center; gap:4px; min-width:76px;";
    // Real, individually-selectable animation poses (2026-08-20, direct
    // follow-up "versuche mal die monster animationen... raus zu
    // extrahieren") -- every resolvable candidate ID here turns out to
    // belong to ActorDefinitionTable's own already-known "humanoid4pose"
    // family (4-tile pose groups, same real down/up/left-frame1/left-
    // frame2 shape the Story/NPC page's own characterA/characterB cards
    // show) -- click the sprite to cycle through them, same real frames
    // this creature's own animation actually uses, not separate images.
    const poses = (col.spritePoses && col.spritePoses.length > 1) ? col.spritePoses : null;
    const poseLabel = poses ? `<div class="mono" style="font-size:9px; color:var(--accent2); cursor:pointer;" data-pose-label>Pose 1/${poses.length} &#8635;</div>` : "";
    wrap.innerHTML = `
      <canvas width="10" height="10" style="image-rendering: pixelated; background:#1a1e14; ${poses ? "cursor:pointer;" : ""}" role="img" aria-label="${escapeHtml(name)}" tabindex="${poses ? "0" : "-1"}"></canvas>
      ${poseLabel}
      <div style="font-size:11px; text-align:center; max-width:96px; line-height:1.3;">${escapeHtml(name)}</div>
      ${!compact ? `<div style="font-size:10px; color:var(--text-dim); text-align:center;">${escapeHtml(idsLabel)}<br>${col.minSpawn}-${col.maxSpawn}x &middot; ${escapeHtml(posLabel)}</div>` : ""}
      ${col.isEnvironmentalTrigger ? '<span class="badge default" style="font-size:9px; padding:1px 5px;" title="Echter, dekodierter Tür-/Kisten-Auslöser -- keine platzierte Figur.">Umgebungs-Trigger</span>' : ""}
    `;
    const canvas = wrap.querySelector("canvas");
    if (poses) {
      let poseIndex = 0;
      const labelEl = wrap.querySelector("[data-pose-label]");
      const draw = () => drawSpriteGrid(canvas, poses[poseIndex], 2, 2, 2, false);
      const cycle = () => {
        poseIndex = (poseIndex + 1) % poses.length;
        labelEl.textContent = `Pose ${poseIndex + 1}/${poses.length} ↻`;
        draw();
      };
      draw();
      pendingDraws.push(draw);
      canvas.addEventListener("click", cycle);
      labelEl.addEventListener("click", cycle);
      canvas.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); cycle(); } });
    } else if (col.spriteTileOffsets && col.spriteTileOffsets.length) {
      const cols = npcSpawnCols(col.spriteTileOffsets.length);
      const draw = () => drawSpriteGrid(canvas, col.spriteTileOffsets, cols, Math.ceil(col.spriteTileOffsets.length / cols), 2, false);
      draw();
      pendingDraws.push(draw);
    } else {
      canvas.width = 32; canvas.height = 32;
      const ctx2d = canvas.getContext("2d");
      ctx2d.strokeStyle = "#3a4a2a";
      ctx2d.strokeRect(0.5, 0.5, 31, 31);
    }
    return wrap;
  }

  const verifiedHost = document.getElementById("npcSpawnVerified");
  for (const ex of data.verifiedExamples || []) {
    const col = data.rows[ex.row].cols[ex.col];
    const card = document.createElement("div");
    card.className = "card";
    card.style.maxWidth = "220px";
    const header = document.createElement("div");
    header.innerHTML = `<h3 style="margin:0 0 6px 0; font-size:14px;">Zeile ${ex.row} / Spalte ${ex.col}</h3>
      <div class="meta" style="margin-bottom:8px;">${ex.observedLive
        ? '<span class="badge verified">Live bestätigt (unverändertes ROM)</span>'
        : '<span class="badge partial" title="' + escapeHtml(ex.note || "") + '">Nur via ROM-Patch erreicht</span>'}</div>`;
    card.appendChild(header);
    card.appendChild(colCard(col, false));
    verifiedHost.appendChild(card);
  }

  const rowsHost = document.getElementById("npcSpawnRows");
  const rowCountEl = document.getElementById("npcSpawnRowCount");
  let activeFilter = "all";
  let activeQuery = "";

  function rowMatches(row) {
    const anyRealCreature = row.cols.some(c => !c.isEnvironmentalTrigger);
    if (activeFilter === "creature" && !anyRealCreature) return false;
    if (!activeQuery) return true;
    const hay = row.cols.map(c => c.candidateNames.join(" ") + " " + c.candidateIds.join(" ")).join(" ").toLowerCase();
    return hay.includes(activeQuery) || String(row.row).includes(activeQuery);
  }

  function renderRows() {
    rowsHost.innerHTML = "";
    const visible = data.rows.filter(rowMatches);
    rowCountEl.textContent = `${visible.length} von ${data.rows.length} Zeilen`;
    for (const row of visible) {
      const rowEl = document.createElement("div");
      rowEl.className = "card";
      rowEl.style.cssText = "display:flex; align-items:flex-start; gap:16px; margin-bottom:10px; padding:10px 14px;";
      const label = document.createElement("div");
      label.style.cssText = "font-size:12px; color:var(--text-dim); min-width:52px; padding-top:4px;";
      label.textContent = "Zeile " + row.row;
      rowEl.appendChild(label);
      const colsWrap = document.createElement("div");
      colsWrap.style.cssText = "display:flex; gap:18px; flex-wrap:wrap;";
      for (const col of row.cols) colsWrap.appendChild(colCard(col, true));
      rowEl.appendChild(colsWrap);
      rowsHost.appendChild(rowEl);
    }
  }
  renderRows();

  document.getElementById("npcSpawnSearch").addEventListener("input", (e) => {
    activeQuery = e.target.value.trim().toLowerCase();
    renderRows();
  });
  document.querySelectorAll("#npcSpawnFilterTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#npcSpawnFilterTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      activeFilter = tab.dataset.filter;
      renderRows();
    });
  });
}
