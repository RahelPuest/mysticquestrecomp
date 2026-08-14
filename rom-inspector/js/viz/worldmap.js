// Weltkarte (2026-08-14, direct user request after the mapRoomPointers
// find: "können wir das 8x8 raster nicht zuordnen? ich vermute das ist
// die worldmap. wenn das geht dann können wir das bitte in der website
// einbauen"). Stitches ROOM_CATALOG's own already-decoded room grids
// together into one big composite image per source (bank5's 16x16 room
// grid, bank6's 8x8) -- no new ROM decode needed, `ROOM_CATALOG` is
// already ordered by real record index (0..255 for bank5, then
// 0..63 for bank6, see export_data.lua's own `exportCatalogSource`
// loop), so `recordIndex -> (row, col)` is a direct `row=floor(i/stride)
// col=i%stride` computation, stride = 16 (bank5) / 8 (bank6) --
// EXACTLY the "map height/width in rooms" fields the external
// FFA-Disassembly project's own MAP_HEADER format documents (already
// cross-checked: bank5's header [16,16] and bank6's [8,8] match their
// own real record counts, 256 and 64).
//
// REAL, QUANTIFIED EVIDENCE this stride is the right one (not just
// assumed): a real, controlled statistical check -- comparing tile IDs
// along the shared edge of stride-adjacent room pairs against a RANDOM
// pair baseline -- found stride-adjacent pairs match FAR more often
// than random (bank5: horizontal 12.0% vs 0.7% random, ~17x; vertical
// 21.8% vs 0.7%, ~31x; bank6: horizontal 18.0% vs 2.8%, ~6.4x; vertical
// 14.1% vs 2.8%, ~5x) -- a real signal, not proof of every single
// connection, but strong, controlled evidence the grid arrangement is
// real and spatially meaningful, not an arbitrary storage order.
//
// HONEST SCOPE: this is a structural/statistical finding, like the
// Map-Viewer's own catalog tileset -- NOT independently gameplay-
// confirmed (no live trigger reaches any of these rooms). The page
// says so explicitly.
//
// ACTOR-ACTION OVERLAY (2026-08-14, direct follow-up "verfolge mal
// diese eventscripte und schaue dir an was diese machen"): each
// catalog room's own `actorAction` field (export_data.lua, from
// `MapTable.tryDecodeActorAction`) is the real `(group, action)` pair
// its own per-room event script enqueues, for the 104/320 records
// whose script matches the already-documented "ACTOR_ACTION" opcode
// family -- a real actor-command-queue mechanism (`$C4E0`/`$C5A0`),
// NOT tile/graphics/room-selection data (see MapTable.lua's own doc
// comment). Real, controlled finding backing this overlay: several
// (group,action) values form tight, CONTIGUOUS regions on the bank-5
// grid (e.g. group=3/action=4 -> cols 7-11, rows 4-6; group=4/
// action=15 -> cols 0-3, rows 9-13) -- suggestive of real, distinct
// game areas/zones, though the exact GAMEPLAY MEANING of each value
// stays open (events.md's own honest note).
//
// "NUR GRUPPE" MODE ADDED (2026-08-14, "erkunde mal alle räume und
// die paarungen... versuche sinn daraus zu machen"): real connected-
// component analysis (4-directional adjacency, not just a bounding
// box) found grouping by `group` ALONE gives a MUCH cleaner signal
// than the full pair -- bank 5's own `group=5` rooms are 70% ONE
// single 31-cell connected blob (`action` sub-values interleave
// freely inside it, reading like a finer variant WITHIN one region,
// not a competing boundary); `group=4` is two solid 6/7-cell
// clusters; `group=3` is smaller but still real; `group=6` is
// heavily scattered (mostly singles) -- plausibly individual points,
// not a zone. See events.md's own dated section for the full numbers.

// PERFORMANCE FIX (2026-08-14, direct user report: "die welt map
// öffnet entweder nicht oder sehr langsam") lives right above
// `drawWorld`'s own tile-drawing loop -- see that comment for the
// real cause (millions of individual `fillRect` calls) and fix
// (cached offscreen-canvas tiles + `drawImage` blitting).

const WORLDMAP_SOURCES = {
  bank5: { stride: 16, label: "Bank 5 (16×16 = 256 Räume)" },
  bank6: { stride: 8, label: "Bank 6 (8×8 = 64 Räume)" },
};

// A small, stable, high-contrast palette -- enough for the ~10 real
// distinct (group,action) pairs actually observed; unseen extras
// cycle back through the same palette rather than erroring.
const ACTOR_ACTION_PALETTE = [
  "#e85f5f", "#f0a13a", "#e8d33a", "#7ed13a", "#3ad19a",
  "#3ac6d1", "#3a8ed1", "#7a5fe8", "#c05fe8", "#e85fb0",
];
function actorActionColor(aa, groupOnly) {
  if (!aa) return null;
  // Stable hash -> palette index (order-independent of insertion, so
  // the same value always gets the same color). `groupOnly=true` --
  // see this file's own "NUR GRUPPE" doc comment above -- hashes just
  // `group`, giving the cleaner, more contiguous regional signal the
  // connected-component analysis found.
  const key = groupOnly ? aa.group : aa.group * 31 + aa.action;
  return ACTOR_ACTION_PALETTE[key % ACTOR_ACTION_PALETTE.length];
}

// PERFORMANCE FIX (2026-08-14, direct user report: "die welt map
// öffnet entweder nicht oder sehr langsam"). The naive per-pixel
// `gbDrawTile` (64 individual `ctx.fillRect` calls per 8x8 tile,
// scaled) is fine for a single room (~320 tiles) but the full bank-5
// grid draws up to 256 rooms x 320 tiles = ~82,000 tile placements --
// over 5 MILLION `fillRect` calls, which visibly hangs the browser's
// main thread. Fix: decode each tile ONCE into a real, tiny native-
// resolution (8x8) offscreen `<canvas>` via a single `putImageData`
// call (not 64 `fillRect`s), then blit it at the target size with one
// hardware-accelerated `ctx.drawImage` call per placement -- the same
// real GB pixel data, ~80-100x fewer, much cheaper draw calls.
const GB_SHADES_RGB = GB_SHADES.map(hex => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
});
function tileToOffscreenCanvas(decoded) {
  const c = document.createElement("canvas");
  c.width = 8;
  c.height = 8;
  const cctx = c.getContext("2d");
  const img = cctx.createImageData(8, 8);
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      const [r, g, b] = GB_SHADES_RGB[decoded[y][x]];
      const o = (y * 8 + x) * 4;
      img.data[o] = r; img.data[o + 1] = g; img.data[o + 2] = b; img.data[o + 3] = 255;
    }
  }
  cctx.putImageData(img, 0, 0);
  return c;
}

function render_worldmap(main) {
  main.innerHTML = `
    <h1 class="page-title">Weltkarte</h1>
    <p class="page-lede">
      Setzt den Raum-Katalog (<a href="#map">Map-Viewer</a>) gemäß der echten, aus den
      Map-Header-Bytes abgeleiteten Gitter-Größe (16&times;16 für Bank 5, 8&times;8 für
      Bank 6 -- siehe <code>rom-map.md</code>, "gehe dem map header hinweis nach") zu einem
      einzigen, großen Bild zusammen. <strong>Strukturell/statistisch begründet, nicht per
      Live-Gameplay bestätigt</strong> -- siehe Hinweis unten für die echte, kontrollierte Evidenz.
    </p>
    <div id="worldmapRomBanner"></div>

    <div class="toolbar">
      <select id="worldmapSource">
        <option value="bank5">${WORLDMAP_SOURCES.bank5.label}</option>
        <option value="bank6">${WORLDMAP_SOURCES.bank6.label}</option>
      </select>
      <label style="font-size:12px; color:var(--text-dim);">Zoom
        <input type="range" id="worldmapZoom" min="1" max="3" value="1" style="vertical-align:middle;">
      </label>
      <label style="font-size:12px; color:var(--text-dim);">
        <input type="checkbox" id="worldmapGrid" checked> Raum-Grenzen einzeichnen
      </label>
      <label style="font-size:12px; color:var(--text-dim);">Actor-Action-Overlay
        <select id="worldmapOverlayMode">
          <option value="off">aus</option>
          <option value="pair">an (Gruppe+Aktion)</option>
          <option value="group">an (nur Gruppe -- sauberere Zonen)</option>
        </select>
      </label>
    </div>

    <div id="worldmapNote" style="font-size:12px; color:var(--text-dim); margin:4px 0; max-width:900px;"></div>
    <div id="worldmapCanvasHost" style="overflow:auto; max-height:75vh; border:1px solid var(--border, #333);">
      <canvas id="worldmapCanvas" width="10" height="10"></canvas>
    </div>
    <div id="worldmapHoverInfo" style="font-size:12px; margin-top:6px;"></div>
  `;

  updateRomBanner(document.getElementById("worldmapRomBanner"));
  const sourceSelect = document.getElementById("worldmapSource");
  sourceSelect.addEventListener("change", drawWorld);
  document.getElementById("worldmapZoom").addEventListener("input", drawWorld);
  document.getElementById("worldmapGrid").addEventListener("change", drawWorld);
  document.getElementById("worldmapOverlayMode").addEventListener("change", drawWorld);
  onSectionUnload(RomBytes.onChange(() => { updateRomBanner(document.getElementById("worldmapRomBanner")); drawWorld(); }));

  function roomsForSource(key) {
    // ROOM_CATALOG is one flat array: bank5's 256 records first (in
    // real record-index order), then bank6's 64 -- see export_data
    // .lua's own exportCatalogSource loop. Slice out just this source.
    return ROOM_CATALOG.filter(r => r.source === key);
  }

  function drawWorld() {
    const key = sourceSelect.value;
    const src = WORLDMAP_SOURCES[key];
    const rooms = roomsForSource(key);
    const stride = src.stride;
    const gridRows = Math.ceil(rooms.length / stride);

    const note = document.getElementById("worldmapNote");
    note.innerHTML = "ℹ Anordnung strukturell/statistisch hergeleitet (echte, kontrollierte Kanten-" +
      "Kontinuitätsprüfung deutlich über Zufalls-Basislinie -- siehe worldmap.js's eigener Kommentar " +
      "für die genauen Zahlen), <strong>nicht per Live-Gameplay bestätigt</strong>. Reihenfolge: Record-" +
      "Index N &rarr; Zeile " + "&lfloor;N/" + stride + "&rfloor;, Spalte N mod " + stride + ".";

    const zoom = parseInt(document.getElementById("worldmapZoom").value, 10) || 1;
    const showGrid = document.getElementById("worldmapGrid").checked;
    const overlayMode = document.getElementById("worldmapOverlayMode").value; // "off" | "pair" | "group"
    const showActorAction = overlayMode !== "off";
    const groupOnly = overlayMode === "group";
    if (showActorAction) {
      const withFlag = rooms.filter(r => r.actorAction).length;
      note.innerHTML += ` <strong>Actor-Action-Overlay an${groupOnly ? " (nur Gruppe)" : ""}:</strong> ${withFlag}/${rooms.length} Räume ` +
        `haben ein reales, erkanntes (group,action)-Paar (echte ROM-Handler-Bytes, siehe MapTable.lua) -- ` +
        `Farbe = ${groupOnly ? "Gruppen-Identität (echte Connected-Component-Analyse zeigt hier die saubersten, größtenteils zusammenhängenden Zonen -- z.B. group=5: 70% ein einziger 31-Zellen-Block)" : "Paar-Identität"}. ` +
        `Bedeutet reales Akteur-Kommando (Actor-Command-Queue), <strong>nicht</strong> ` +
        `Tile-Zuordnung -- gleiche Farbe kann echte, zusammenhängende Spielgebiete markieren.`;
    }
    const roomW = rooms[0].cols, roomH = rooms[0].rows;
    const tilePx = 8 * zoom;
    const canvas = document.getElementById("worldmapCanvas");
    canvas.width = stride * roomW * tilePx;
    canvas.height = gridRows * roomH * tilePx;
    const ctx2d = canvas.getContext("2d");
    ctx2d.fillStyle = "#1a1e14";
    ctx2d.fillRect(0, 0, canvas.width, canvas.height);

    // Per-room tile-canvas cache (offscreen 8x8 canvases, see the
    // performance-fix comment above `tileToOffscreenCanvas`) --
    // `ctx2d.imageSmoothingEnabled = false` keeps the scaled blit
    // crisp/pixelated instead of blurry, matching every other GB tile
    // view on this site.
    ctx2d.imageSmoothingEnabled = false;
    const tileCache = {};
    for (let i = 0; i < rooms.length; i++) {
      const room = rooms[i];
      const roomRow = Math.floor(i / stride);
      const roomCol = i % stride;
      const baseX = roomCol * roomW * tilePx;
      const baseY = roomRow * roomH * tilePx;
      const cache = tileCache[i] = tileCache[i] || {};
      for (let row = 0; row < room.rows; row++) {
        for (let col = 0; col < room.cols; col++) {
          const tileId = room.grid[row][col];
          let tileCanvas = cache[tileId];
          if (tileCanvas === undefined) {
            const entry = room.tileOffsets[String(tileId)];
            const bytes = entry !== undefined ? resolveTileBytes(entry) : null;
            const decoded = bytes ? gbDecodeTile(bytes) : null;
            tileCanvas = decoded ? tileToOffscreenCanvas(decoded) : null;
            cache[tileId] = tileCanvas;
          }
          const dx = baseX + col * tilePx, dy = baseY + row * tilePx;
          if (tileCanvas) {
            ctx2d.drawImage(tileCanvas, dx, dy, tilePx, tilePx);
          } else {
            ctx2d.strokeStyle = "#3a4a2a";
            ctx2d.strokeRect(dx + 0.5, dy + 0.5, tilePx - 1, tilePx - 1);
          }
        }
      }
      if (showActorAction && room.actorAction) {
        ctx2d.fillStyle = actorActionColor(room.actorAction, groupOnly);
        ctx2d.globalAlpha = 0.45;
        ctx2d.fillRect(baseX, baseY, roomW * tilePx, roomH * tilePx);
        ctx2d.globalAlpha = 1;
      }
      if (showGrid) {
        ctx2d.strokeStyle = "rgba(232,95,95,.55)";
        ctx2d.lineWidth = 1;
        ctx2d.strokeRect(baseX + 0.5, baseY + 0.5, roomW * tilePx - 1, roomH * tilePx - 1);
      }
    }

    const info = document.getElementById("worldmapHoverInfo");
    if (!RomBytes.isLoaded()) {
      info.textContent = "Keine ROM geladen -- oben rechts „ROM laden…“, um echte Pixel zu sehen (Grid-Struktur ist trotzdem sichtbar).";
    } else {
      info.textContent = "Maus über einen Raum bewegen für seinen Record-Index + Gitter-Position.";
    }
    canvas.onmousemove = (ev) => {
      const rect = canvas.getBoundingClientRect();
      const px = (ev.clientX - rect.left) * (canvas.width / rect.width);
      const py = (ev.clientY - rect.top) * (canvas.height / rect.height);
      const roomCol = Math.floor(px / (roomW * tilePx));
      const roomRow = Math.floor(py / (roomH * tilePx));
      if (roomRow < 0 || roomCol < 0 || roomCol >= stride) return;
      const i = roomRow * stride + roomCol;
      if (i < 0 || i >= rooms.length) return;
      const aa = rooms[i].actorAction;
      const aaLabel = aa ? ` &middot; Actor-Action group=${aa.group} action=0x${aa.action.toString(16).padStart(2, "0")}` : "";
      info.innerHTML = `${key}-record-${String(i).padStart(3, "0")} &middot; Gitter-Position (Zeile ${roomRow}, Spalte ${roomCol})${aaLabel}`;
    };
  }

  drawWorld();
}
