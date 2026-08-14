function render_map(main) {
  // Combined room list: the 8 real, gameplay-connected rooms
  // (ROOM_MAPS) plus the room CATALOG (2026-08-14, "andere räume, so
  // viele wie möglich, raumdaten reicht") -- ALL 320 individually-
  // decodable bank-5/bank-6 records, exported from the exact same
  // pipeline RoomExplorer.lua's dev-only F8 browser already drives
  // live in the LÖVE app. Kept as two <optgroup>s, not silently
  // merged, so the honest distinction stays visible: only the 6
  // `confirmed=true` catalog entries are proven to be a SPECIFIC real
  // dungeon room (unknownRoomA); the rest are real ROM art with no
  // known live gameplay trigger (see room-catalog.js's own header
  // comment for the full scope note).
  const combined = [
    ...ROOM_MAPS.map(r => ({ room: r, group: "connected" })),
    ...ROOM_CATALOG.map(r => ({ room: r, group: "catalog" })),
  ];

  main.innerHTML = `
    <h1 class="page-title">Map-Viewer</h1>
    <p class="page-lede">
      Setzt eine echte Raum-Tilemap (Grid aus Tile-IDs + Tile-ID&rarr;ROM-Offset-Lookup, direkt
      aus <code>rom_profiles.lua</code> bzw. dem Bank-5/Bank-6-Raum-Katalog) zu einem vollständigen
      Bild zusammen &mdash; live aus einer lokal geladenen ROM-Datei dekodiert.
    </p>
    <div id="mapRomBanner"></div>

    <div class="toolbar">
      <select id="mapRoomSelect" style="min-width:280px;">
        <optgroup label="Echte, verbundene Räume (${ROOM_MAPS.length})">
          ${ROOM_MAPS.map((r, i) => `<option value="${i}">${escapeHtml(r.name)} (${r.cols}&times;${r.rows})</option>`).join("")}
        </optgroup>
        <optgroup label="Raum-Katalog -- alle ${ROOM_CATALOG.length} Bank-5/6-Einträge (nur ${ROOM_CATALOG.filter(r => r.confirmed).length} als konkreter Raum bestätigt)">
          ${ROOM_CATALOG.map((r, i) => `<option value="${ROOM_MAPS.length + i}">${r.confirmed ? "✓ " : ""}${escapeHtml(r.name)} (${r.cols}&times;${r.rows})</option>`).join("")}
        </optgroup>
      </select>
      <label style="font-size:12px; color:var(--text-dim);">Zoom
        <input type="range" id="mapZoom" min="1" max="5" value="3" style="vertical-align:middle;">
      </label>
      <label style="font-size:12px; color:var(--text-dim);">
        <input type="checkbox" id="mapFloorOverlay"> Floor-Tiles hervorheben
      </label>
    </div>

    <div id="mapCatalogNote" style="font-size:12px; color:var(--text-dim); margin:4px 0;"></div>
    <div id="mapCanvasHost"><canvas id="mapCanvas" width="10" height="10"></canvas></div>
    <div id="mapHoverInfo"></div>
  `;

  updateRomBanner(document.getElementById("mapRomBanner"));
  const select = document.getElementById("mapRoomSelect");
  select.addEventListener("change", drawMap);
  document.getElementById("mapZoom").addEventListener("input", drawMap);
  document.getElementById("mapFloorOverlay").addEventListener("change", drawMap);
  onSectionUnload(RomBytes.onChange(() => { updateRomBanner(document.getElementById("mapRomBanner")); drawMap(); }));

  function drawMap() {
    const selectedEntry = combined[parseInt(select.value, 10)];
    const room = selectedEntry.room;
    const note = document.getElementById("mapCatalogNote");
    if (selectedEntry.group === "catalog") {
      note.textContent = room.confirmed
        ? "Bestätigt: dieser Katalog-Eintrag ist unknownRoomA's eigener, konkreter Dungeon-Raum (roomSelector " + room.recordIndex + ")."
        : "Katalog-Eintrag, nicht als konkreter erreichbarer Raum bestätigt -- echte ROM-Kunst (tile_entropy-geprüft), aber ohne bekannten Live-Gameplay-Trigger.";
    } else {
      note.textContent = "";
    }
    const zoom = parseInt(document.getElementById("mapZoom").value, 10) || 3;
    const showFloor = document.getElementById("mapFloorOverlay").checked;
    const canvas = document.getElementById("mapCanvas");
    const tilePx = 8 * zoom;
    canvas.width = room.cols * tilePx;
    canvas.height = room.rows * tilePx;
    const ctx2d = canvas.getContext("2d");
    ctx2d.fillStyle = "#1a1e14";
    ctx2d.fillRect(0, 0, canvas.width, canvas.height);

    const tileCache = {};
    for (let row = 0; row < room.rows; row++) {
      for (let col = 0; col < room.cols; col++) {
        const tileId = room.grid[row][col];
        let decoded = tileCache[tileId];
        if (decoded === undefined) {
          const entry = room.tileOffsets[String(tileId)];
          const bytes = entry !== undefined ? resolveTileBytes(entry) : null;
          decoded = bytes ? gbDecodeTile(bytes) : null;
          tileCache[tileId] = decoded;
        }
        const dx = col * tilePx, dy = row * tilePx;
        if (decoded) {
          gbDrawTile(ctx2d, decoded, dx, dy, zoom);
        } else {
          ctx2d.strokeStyle = "#3a4a2a";
          ctx2d.strokeRect(dx + 0.5, dy + 0.5, tilePx - 1, tilePx - 1);
        }
        if (showFloor && room.floorTileIds && room.floorTileIds[String(tileId)]) {
          ctx2d.fillStyle = "rgba(95,196,232,.28)";
          ctx2d.fillRect(dx, dy, tilePx, tilePx);
        }
      }
    }

    const info = document.getElementById("mapHoverInfo");
    if (!RomBytes.isLoaded()) {
      info.textContent = "Keine ROM geladen -- oben rechts „ROM laden…“, um echte Pixel zu sehen (Grid-Struktur ist trotzdem sichtbar).";
    } else {
      info.textContent = "Kachel mit der Maus berühren für Tile-ID + Offset.";
    }

    canvas.onmousemove = (ev) => {
      const rect = canvas.getBoundingClientRect();
      const col = Math.floor((ev.clientX - rect.left) / tilePx);
      const row = Math.floor((ev.clientY - rect.top) / tilePx);
      if (row < 0 || row >= room.rows || col < 0 || col >= room.cols) return;
      const tileId = room.grid[row][col];
      const entry = room.tileOffsets[String(tileId)];
      const offsetLabel = entry === undefined ? "kein bekannter Offset" : (entry.literal ? "literales Muster" : hex(entry, 5));
      info.innerHTML = `Zeile ${row}, Spalte ${col} &middot; Tile-ID ${tileId} ($${tileId.toString(16).toUpperCase()}) &middot; ${offsetLabel}`;
    };
  }

  drawMap();
}
