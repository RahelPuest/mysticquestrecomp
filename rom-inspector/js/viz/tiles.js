function render_tiles(main) {
  const roomOptions = ROOM_MAPS.map(r => {
    const ids = Object.keys(r.tileOffsets).map(Number).sort((a, b) => a - b);
    return { label: `${r.name} (${ids.length} Tiles)`, tiles: ids.map(id => ({ id, entry: r.tileOffsets[String(id)] })) };
  });

  main.innerHTML = `
    <h1 class="page-title">Tile-Viewer</h1>
    <p class="page-lede">
      Dekodiert echte 8&times;8-Game-Boy-2bpp-Kacheln direkt aus einer lokal geladenen ROM-Datei
      (nichts wird hochgeladen &mdash; reines <code>FileReader</code> im Browser). Voreinstellungen
      nutzen die echten, bereits verifizierten Tile-Adressen aus <code>rom_profiles.lua</code>;
      der freie Adressbereich unten funktioniert für jede beliebige Stelle der ROM.
    </p>
    <div id="tileRomBanner"></div>

    <div class="toolbar">
      <select id="tilePreset" style="min-width:220px;">
        <option value="font">Font-Tileset (${FONT_TILESET.tileCount} Tiles, $${FONT_TILESET.fileOffset.toString(16).toUpperCase()})</option>
        ${roomOptions.map((r, i) => `<option value="room:${i}">${escapeHtml(r.label)}</option>`).join("")}
        <option value="custom">Freier Adressbereich&hellip;</option>
      </select>
      <span id="customRange" style="display:none; gap:8px; align-items:center;">
        <input type="text" id="customOffset" placeholder="Offset, z.B. 0x22B00" style="width:150px;">
        <input type="text" id="customCount" placeholder="Anzahl" value="64" style="width:70px;">
      </span>
      <label style="font-size:12px; color:var(--text-dim);">Spalten
        <input type="text" id="tileCols" value="16" style="width:44px; margin-left:4px;">
      </label>
      <label style="font-size:12px; color:var(--text-dim);">Zoom
        <input type="range" id="tileZoom" min="1" max="6" value="3" style="vertical-align:middle;">
      </label>
      <button class="btn primary small" id="renderTilesBtn">Anzeigen</button>
    </div>

    <div id="tileCanvasHost"><canvas id="tileCanvas" width="10" height="10" role="img" aria-label="Ausgewähltes Kachel-Set, direkt aus der geladenen ROM gerendert. Einzelne Kacheln per Mausklick inspizierbar."></canvas></div>
    <div class="tile-info-strip" id="tileInfo">Kachel anklicken für Details.</div>
  `;

  updateRomBanner(document.getElementById("tileRomBanner"));

  const presetSel = document.getElementById("tilePreset");
  const customRange = document.getElementById("customRange");
  presetSel.addEventListener("change", () => {
    customRange.style.display = presetSel.value === "custom" ? "inline-flex" : "none";
  });
  document.getElementById("renderTilesBtn").addEventListener("click", () => drawSelected());
  document.getElementById("tileZoom").addEventListener("input", () => drawSelected());
  onSectionUnload(RomBytes.onChange(() => { updateRomBanner(document.getElementById("tileRomBanner")); drawSelected(); }));

  function currentTileList() {
    const val = presetSel.value;
    if (val === "font") {
      const list = [];
      for (let i = 0; i < FONT_TILESET.tileCount; i++) {
        list.push({ id: i, entry: FONT_TILESET.fileOffset + i * 16 });
      }
      return list;
    }
    if (val.startsWith("room:")) {
      return roomOptions[parseInt(val.split(":")[1], 10)].tiles;
    }
    // custom
    const offset = parseInt(document.getElementById("customOffset").value.replace(/^0x/i, ""), 16) || 0;
    const count = parseInt(document.getElementById("customCount").value, 10) || 1;
    const list = [];
    for (let i = 0; i < count; i++) list.push({ id: null, entry: offset + i * 16 });
    return list;
  }

  function drawSelected() {
    const tiles = currentTileList();
    const cols = Math.max(1, parseInt(document.getElementById("tileCols").value, 10) || 16);
    const zoom = parseInt(document.getElementById("tileZoom").value, 10) || 3;
    const scale = zoom * 1; // pixel scale per GB pixel
    const rows = Math.ceil(tiles.length / cols);
    const canvas = document.getElementById("tileCanvas");
    canvas.width = cols * 8 * scale;
    canvas.height = Math.max(1, rows) * 8 * scale;
    const ctx2d = canvas.getContext("2d");
    ctx2d.fillStyle = "#1a1e14";
    ctx2d.fillRect(0, 0, canvas.width, canvas.height);

    const info = document.getElementById("tileInfo");
    if (!RomBytes.isLoaded() && !tiles.some(t => t.entry && t.entry.literal)) {
      info.textContent = "Keine ROM geladen -- oben rechts „ROM laden…“, um echte Pixel zu sehen.";
    }

    tiles.forEach((t, i) => {
      const bytes = resolveTileBytes(t.entry);
      const tx = (i % cols) * 8 * scale, ty = Math.floor(i / cols) * 8 * scale;
      if (bytes) {
        gbDrawTile(ctx2d, gbDecodeTile(bytes), tx, ty, scale);
      } else {
        ctx2d.strokeStyle = "#3a4a2a";
        ctx2d.strokeRect(tx + 0.5, ty + 0.5, 8 * scale - 1, 8 * scale - 1);
      }
    });

    canvas.onclick = (ev) => {
      const rect = canvas.getBoundingClientRect();
      const cx = Math.floor((ev.clientX - rect.left) / (8 * scale));
      const cy = Math.floor((ev.clientY - rect.top) / (8 * scale));
      const idx = cy * cols + cx;
      const t = tiles[idx];
      if (!t) return;
      const offsetLabel = (t.entry && t.entry.literal) ? "literales Muster (kein ROM-Offset)" : hex(t.entry, 5);
      info.innerHTML = `Index ${idx}${t.id !== null ? `, Tile-ID ${t.id} ($${t.id.toString(16).toUpperCase()})` : ""} &middot; ${offsetLabel}`;
    };
  }

  drawSelected();
}

function updateRomBanner(host) {
  if (!host) return; // section no longer mounted -- see onSectionUnload
  if (RomBytes.isLoaded()) {
    host.innerHTML = "";
    return;
  }
  host.innerHTML = `<div class="rom-needed-banner">
    <strong>Keine ROM geladen.</strong> Lade oben rechts deine eigene, legal erworbene
    <code>.gb</code>-Datei &mdash; sie verlässt deinen Browser nie (kein Upload, reines
    <code>FileReader</code>). Ohne ROM werden nur Kachel-Umrisse angezeigt.
  </div>`;
}
