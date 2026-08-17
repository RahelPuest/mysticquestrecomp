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
// Recomputed on EVERY call (not cached at module load) so a palette
// switch (GBPalette.set(), see js/rombytes.js) is picked up immediately
// -- GB_SHADES is a `let` that can change after this module first
// loads, and freezing the RGB conversion once here would silently keep
// showing the old preset's colors on this one section.
function gbShadesRgb() {
  return GB_SHADES.map(hex => {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
  });
}
function tileToOffscreenCanvas(decoded) {
  const c = document.createElement("canvas");
  c.width = 8;
  c.height = 8;
  const cctx = c.getContext("2d");
  const img = cctx.createImageData(8, 8);
  const shadesRgb = gbShadesRgb();
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      const [r, g, b] = shadesRgb[decoded[y][x]];
      const o = (y * 8 + x) * 4;
      img.data[o] = r; img.data[o + 1] = g; img.data[o + 2] = b; img.data[o + 3] = 255;
    }
  }
  cctx.putImageData(img, 0, 0);
  return c;
}

// Google-Maps-style pan/zoom (2026-08-15, direct user request: "eine
// map naviagation wie bei google maps"). Replaces the old discrete
// zoom-slider + native-scrollbar approach: the whole map is rendered
// ONCE, at a fixed, generously-high pixel-per-tile resolution (so
// zooming in stays reasonably crisp), into the canvas -- actual pan/
// zoom is then a pure CSS `transform: translate(...) scale(...)` on
// that already-rendered canvas, applied every pointer-move/wheel tick
// with zero redraw cost (the expensive part -- decoding hundreds of
// real ROM tiles into pixels -- happens exactly once per source
// switch, same as before). `transform-origin: 0 0` keeps the pan/zoom
// math simple (world-space (0,0) is always the map's own top-left
// corner, matching `tx`/`ty` directly). Mouse (drag + wheel, zoom
// anchored under the cursor, matching Google Maps' own feel) and
// touch (single-finger drag, two-finger pinch-to-zoom) are unified via
// the Pointer Events API rather than separate mouse/touch listeners.
const WorldmapView = { scale: 1, tx: 0, ty: 0, minScale: 0.15, maxScale: 8 };

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
      <select id="worldmapSource" aria-label="Kartenquelle auswählen">
        <option value="bank5">${WORLDMAP_SOURCES.bank5.label}</option>
        <option value="bank6">${WORLDMAP_SOURCES.bank6.label}</option>
      </select>
      <button id="worldmapFit" type="button">Ansicht zurücksetzen</button>
      <label style="font-size:12px; color:var(--text-dim);">
        <input type="checkbox" id="worldmapGrid" checked> Raum-Grenzen einzeichnen
      </label>
      <label style="font-size:12px; color:var(--text-dim);">
        <input type="checkbox" id="worldmapCoords" checked> Koordinaten anzeigen
      </label>
      <label style="font-size:12px; color:var(--text-dim);">Actor-Action-Overlay
        <select id="worldmapOverlayMode">
          <option value="off">aus</option>
          <option value="pair">an (Gruppe+Aktion)</option>
          <option value="group">an (nur Gruppe -- sauberere Zonen)</option>
        </select>
      </label>
      <span style="font-size:12px; color:var(--text-dim);">Ziehen zum Verschieben, Mausrad/Pinch zum Zoomen, Klick für Rauminfo.</span>
    </div>

    <div id="worldmapNote" style="font-size:12px; color:var(--text-dim); margin:4px 0; max-width:900px;"></div>
    <div id="worldmapViewport" style="position:relative; overflow:hidden; width:100%; height:75vh;
        border:1px solid var(--border, #333); cursor:grab; touch-action:none; background:#1a1e14;">
      <canvas id="worldmapCanvas" width="10" height="10"
        style="position:absolute; top:0; left:0; transform-origin:0 0; image-rendering:pixelated;"
        role="img" aria-label="Rekonstruierte Weltkarte (16×16- und 8×8-Rastergruppen), direkt aus der geladenen ROM gerendert. Schwenkbar und zoombar per Maus; Details einzelner Räume per Mausklick."></canvas>
    </div>
    <div id="worldmapHoverInfo" style="font-size:12px; margin-top:6px;"></div>
  `;

  updateRomBanner(document.getElementById("worldmapRomBanner"));
  const sourceSelect = document.getElementById("worldmapSource");
  sourceSelect.addEventListener("change", () => { drawWorld(); fitToViewport(); });
  document.getElementById("worldmapFit").addEventListener("click", fitToViewport);
  document.getElementById("worldmapGrid").addEventListener("change", drawWorld);
  document.getElementById("worldmapCoords").addEventListener("change", drawWorld);
  document.getElementById("worldmapOverlayMode").addEventListener("change", drawWorld);
  wirePanZoom();
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
    // Fixed, generously-high base resolution -- see this file's own
    // "Google-Maps-style pan/zoom" doc comment above: actual zoom is a
    // CSS transform on the already-rendered canvas, not a redraw, so
    // this only needs to be high enough to stay reasonably crisp at
    // the max CSS scale (`WorldmapView.maxScale`).
    const tilePx = 16;
    // Coordinate rulers (2026-08-17, direct user request: "bau mal
    // mitte noch die koordinaten an weltkarten dran damit ich dir
    // besser koordinaten komunizieren kann") -- a real, always-visible
    // row/column axis (like a spreadsheet), so the user can just READ
    // OFF a "Zeile X, Spalte Y" coordinate by looking, instead of
    // having to click every room individually. `MARGIN` reserves real
    // canvas space (not an HTML overlay -- stays correctly positioned
    // through the same CSS pan/zoom transform as everything else).
    const showCoords = document.getElementById("worldmapCoords").checked;
    const MARGIN = showCoords ? 2 * tilePx : 0;
    const canvas = document.getElementById("worldmapCanvas");
    canvas.width = MARGIN + stride * roomW * tilePx;
    canvas.height = MARGIN + gridRows * roomH * tilePx;
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
      const baseX = MARGIN + roomCol * roomW * tilePx;
      const baseY = MARGIN + roomRow * roomH * tilePx;
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
      if (showCoords) {
        // Real per-room "row,col" coordinate, small text over a
        // semi-transparent backing box (readable against any real
        // tile art underneath) in each room's own top-left corner --
        // the SAME (roomRow,roomCol) pair the click-to-inspect info
        // box below already reports, just always visible now.
        const label = `${roomRow},${roomCol}`;
        ctx2d.font = "bold 11px monospace";
        const textW = ctx2d.measureText(label).width;
        ctx2d.fillStyle = "rgba(10,12,7,.72)";
        ctx2d.fillRect(baseX + 1, baseY + 1, textW + 4, 13);
        ctx2d.fillStyle = "#e8d33a";
        ctx2d.textBaseline = "top";
        ctx2d.fillText(label, baseX + 3, baseY + 1);
      }
    }

    if (showCoords) {
      // Axis rulers in the reserved margin -- column indices along the
      // top, row indices down the left, one label per real room
      // column/row (not per pixel), each centered over/beside its own
      // real room band.
      ctx2d.fillStyle = "#171b10";
      ctx2d.fillRect(0, 0, canvas.width, MARGIN);
      ctx2d.fillRect(0, 0, MARGIN, canvas.height);
      ctx2d.strokeStyle = "rgba(232,211,58,.4)";
      ctx2d.strokeRect(0.5, 0.5, canvas.width - 1, MARGIN - 1);
      ctx2d.strokeRect(0.5, 0.5, MARGIN - 1, canvas.height - 1);
      ctx2d.font = "bold 12px monospace";
      ctx2d.fillStyle = "#e8d33a";
      ctx2d.textAlign = "center";
      ctx2d.textBaseline = "middle";
      for (let c = 0; c < stride; c++) {
        ctx2d.fillText(String(c), MARGIN + c * roomW * tilePx + (roomW * tilePx) / 2, MARGIN / 2);
      }
      ctx2d.textAlign = "right";
      for (let r = 0; r < gridRows; r++) {
        ctx2d.fillText(String(r), MARGIN - 4, MARGIN + r * roomH * tilePx + (roomH * tilePx) / 2);
      }
      ctx2d.textAlign = "left";
      ctx2d.textBaseline = "alphabetic";
    }

    const info = document.getElementById("worldmapHoverInfo");
    if (!RomBytes.isLoaded()) {
      info.textContent = "Keine ROM geladen -- oben rechts „ROM laden…“, um echte Pixel zu sehen (Grid-Struktur ist trotzdem sichtbar).";
    } else {
      info.textContent = "Auf einen Raum klicken/tippen für seinen Record-Index + Gitter-Position -- oder direkt die Koordinaten am Rand/auf der Kachel ablesen.";
    }
    // CLICK (not hover -- see this file's own "Google-Maps-style pan/
    // zoom" doc comment: hover doesn't exist on touch, and a click is
    // also what `wirePanZoom`'s own drag-vs-click distinction already
    // produces for free) shows the room info, persistent until the
    // next click, instead of vanishing the moment the mouse leaves.
    canvas.onWorldmapClick = (clientX, clientY) => {
      const rect = canvas.getBoundingClientRect();
      const px = (clientX - rect.left) * (canvas.width / rect.width) - MARGIN;
      const py = (clientY - rect.top) * (canvas.height / rect.height) - MARGIN;
      const roomCol = Math.floor(px / (roomW * tilePx));
      const roomRow = Math.floor(py / (roomH * tilePx));
      if (roomRow < 0 || roomCol < 0 || roomCol >= stride || roomRow >= gridRows) return;
      const i = roomRow * stride + roomCol;
      if (i < 0 || i >= rooms.length) return;
      const aa = rooms[i].actorAction;
      const aaLabel = aa ? ` &middot; Actor-Action group=${aa.group} action=0x${aa.action.toString(16).padStart(2, "0")}` : "";
      info.innerHTML = `<strong>${key}-record-${String(i).padStart(3, "0")}</strong> &middot; Gitter-Position (Zeile ${roomRow}, Spalte ${roomCol})${aaLabel}`;
    };
  }

  drawWorld();
  fitToViewport();
}

//// Pan/zoom mechanics -- pure view-state math, no ROM/room knowledge. ////

function applyTransform() {
  const canvas = document.getElementById("worldmapCanvas");
  if (!canvas) return;
  canvas.style.transform = `translate(${WorldmapView.tx}px, ${WorldmapView.ty}px) scale(${WorldmapView.scale})`;
}

// Real "zoom to fit" -- centers the whole map in the viewport at
// whatever scale makes it fit entirely (capped at 1:1 so a small
// bank6 map doesn't get blown up blurry on first load), matching
// Google Maps' own "reset view" affordance.
function fitToViewport() {
  const viewport = document.getElementById("worldmapViewport");
  const canvas = document.getElementById("worldmapCanvas");
  if (!viewport || !canvas || !canvas.width || !canvas.height) return;
  const vw = viewport.clientWidth, vh = viewport.clientHeight;
  const scale = Math.min(vw / canvas.width, vh / canvas.height, 1);
  WorldmapView.scale = Math.max(WorldmapView.minScale, scale);
  WorldmapView.tx = (vw - canvas.width * WorldmapView.scale) / 2;
  WorldmapView.ty = (vh - canvas.height * WorldmapView.scale) / 2;
  applyTransform();
}

// Zoom by `factor`, keeping the world-space point currently under
// (`anchorX`,`anchorY`) -- viewport-relative pixel coords -- fixed on
// screen, exactly like Google Maps' own scroll-to-zoom / pinch feel.
function zoomAt(factor, anchorX, anchorY) {
  const v = WorldmapView;
  const newScale = Math.min(v.maxScale, Math.max(v.minScale, v.scale * factor));
  const worldX = (anchorX - v.tx) / v.scale;
  const worldY = (anchorY - v.ty) / v.scale;
  v.tx = anchorX - worldX * newScale;
  v.ty = anchorY - worldY * newScale;
  v.scale = newScale;
  applyTransform();
}

// Pointer Events unify mouse + touch: a single active pointer drags
// (pan); a second simultaneous pointer switches to pinch-zoom (scale
// from the change in inter-pointer distance, anchored at their
// midpoint) -- real two-finger pinch, not just single-finger pan on
// touch devices. A pointer that moved less than a few px total between
// down and up counts as a real "click" (room info), not a drag --
// otherwise every intentional room click would also nudge the pan by a
// stray sub-pixel amount and never register as a click at all.
function wirePanZoom() {
  const viewport = document.getElementById("worldmapViewport");
  const canvas = document.getElementById("worldmapCanvas");
  if (!viewport || !canvas) return;
  const pointers = new Map(); // pointerId -> {x, y}
  let dragMoved = 0;
  let pinchStartDist = null;
  let pinchStartScale = null;

  function midpoint() {
    const pts = [...pointers.values()];
    return { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
  }
  function dist() {
    const pts = [...pointers.values()];
    return Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
  }

  viewport.addEventListener("pointerdown", (ev) => {
    viewport.setPointerCapture(ev.pointerId);
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    dragMoved = 0;
    if (pointers.size === 2) {
      pinchStartDist = dist();
      pinchStartScale = WorldmapView.scale;
    }
    viewport.style.cursor = "grabbing";
  });

  viewport.addEventListener("pointermove", (ev) => {
    if (!pointers.has(ev.pointerId)) return;
    const prev = pointers.get(ev.pointerId);
    const dx = ev.clientX - prev.x, dy = ev.clientY - prev.y;
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    dragMoved += Math.abs(dx) + Math.abs(dy);

    if (pointers.size === 2 && pinchStartDist) {
      const d = dist();
      const rect = viewport.getBoundingClientRect();
      const mid = midpoint();
      const factor = (d / pinchStartDist) * (pinchStartScale / WorldmapView.scale);
      zoomAt(factor, mid.x - rect.left, mid.y - rect.top);
    } else if (pointers.size === 1) {
      WorldmapView.tx += dx;
      WorldmapView.ty += dy;
      applyTransform();
    }
  });

  function endPointer(ev) {
    if (!pointers.has(ev.pointerId)) return;
    const wasSingleClick = pointers.size === 1 && dragMoved < 6;
    pointers.delete(ev.pointerId);
    pinchStartDist = null;
    viewport.style.cursor = "grab";
    if (wasSingleClick && canvas.onWorldmapClick) {
      canvas.onWorldmapClick(ev.clientX, ev.clientY);
    }
  }
  viewport.addEventListener("pointerup", endPointer);
  viewport.addEventListener("pointercancel", endPointer);

  // Scroll-wheel zoom, anchored under the cursor -- the desktop
  // equivalent of pinch, same `zoomAt` helper either way.
  viewport.addEventListener("wheel", (ev) => {
    ev.preventDefault();
    const rect = viewport.getBoundingClientRect();
    const factor = ev.deltaY < 0 ? 1.15 : 1 / 1.15;
    zoomAt(factor, ev.clientX - rect.left, ev.clientY - rect.top);
  }, { passive: false });

  // Keep the current view sane (re-fit) if the browser window itself
  // is resized -- otherwise a fit computed for the old viewport size
  // can leave the map oddly off-center.
  window.addEventListener("resize", () => {
    if (document.getElementById("worldmapViewport")) fitToViewport();
  });
}
