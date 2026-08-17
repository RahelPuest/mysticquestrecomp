function render_rooms(main) {
  main.innerHTML = `
    <h1 class="page-title">Raum-System</h1>
    <p class="page-lede">
      Jeder Knoten zeigt die echte, live aus der geladenen ROM gerenderte Raum-Kachelkarte
      (dieselben Kachel-Grafik-Primitiven wie der <a href="#map">Map-Viewer</a>), jeder Pfeil
      ein echter, empirisch gefundener Übergang (Trigger-Zone + Übergangsmechanismus +
      Zielraum), direkt aus <code>rom_profiles.lua</code>s <code>graphics.&lt;room&gt;.exits</code>
      gelesen. Zwei reale Mechanismen kommen vor: ein echter Hardware-Scroll
      (<span style="color:var(--accent2)">durchgezogen</span>) und ein echter „Cut“ &mdash;
      ein sofortiger Szenenwechsel über die relozierbare Zeiger-Pipeline
      (<span style="color:var(--accent3)">gestrichelt</span>).
    </p>
    <p class="page-lede">
      <strong>Nur die tatsächlich im Spiel verdrahteten Übergänge</strong> &mdash; nicht
      die volle rohe ROM-Tabelle. Diese ${ROOMS.reduce((n, r) => n + r.exits.length, 0)}
      Kanten sind eine kleine, live bestätigte Teilmenge der
      <a href="#transitions">${TRANSITIONS.distinct.length} echten, distinkten Übergänge</a>,
      die 2026-08-16 direkt aus dem ROM dekodiert wurden (Bank 14, Ziel-<code>roomSelector</code>
      + reale Landeposition in einem Record). Der Grund für den Unterschied ist ehrlich: nur
      2 dieser 82 Einträge haben einen bekannten echten In-Game-Auslöser und sind deshalb hier
      als spielbare Kante verdrahtet &mdash; die anderen 80 (darunter 36 zur lange mysteriösen
      <code>unknownRoomA</code>-Familie) sind reale ROM-Daten ohne bekannten Trigger. Siehe den
      <a href="#transitions">Raum-Übergänge</a>-Tab für die vollständige Tabelle.
    </p>
    <div id="roomGraphRomBanner"></div>
    <div id="roomGraphHost" style="position:relative; overflow:auto; border:1px solid var(--border); border-radius:8px; background:#10130c;">
      <div id="roomGraphNodes" style="position:relative;"></div>
      <svg id="roomGraphSvg" style="position:absolute; top:0; left:0; pointer-events:none;"></svg>
    </div>
    <div class="card-grid" id="roomCards" style="margin-top:20px;"></div>
  `;

  updateRomBanner(document.getElementById("roomGraphRomBanner"));
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("roomGraphRomBanner"));
    drawThumbnails();
  }));

  // Cross-reference ROOMS (graph/exit data) against ROOM_MAPS (full
  // tile grid + tileOffsets, the same data the Map-Viewer already
  // renders from) by room name -- both are exported from the SAME
  // `profile.graphics` table (see export_data.lua's own "6"/"6b"
  // sections), so every graph node with real exits also has a real
  // map entry to render a thumbnail from.
  const mapByName = {};
  for (const m of ROOM_MAPS) mapByName[m.name] = m;

  // Build node/edge set.
  const nodeNames = new Set();
  const roomByName = {};
  for (const r of ROOMS) { nodeNames.add(r.name); roomByName[r.name] = r; }
  const edges = [];
  for (const r of ROOMS) {
    for (const ex of r.exits) {
      nodeNames.add(ex.targetRoom);
      edges.push({ from: r.name, to: ex.targetRoom, ...ex });
    }
  }
  const incoming = new Set(edges.map(e => e.to));
  const roots = [...nodeNames].filter(n => !incoming.has(n));

  // BFS leveling (multi-root) -- unchanged from before.
  const level = {};
  const queue = roots.map(r => ({ n: r, l: 0 }));
  roots.forEach(r => level[r] = 0);
  while (queue.length) {
    const { n, l } = queue.shift();
    for (const e of edges.filter(e => e.from === n)) {
      if (level[e.to] === undefined || level[e.to] < l + 1) {
        level[e.to] = l + 1;
        queue.push({ n: e.to, l: l + 1 });
      }
    }
  }
  for (const n of nodeNames) if (level[n] === undefined) level[n] = 0;

  const byLevel = {};
  for (const n of nodeNames) {
    (byLevel[level[n]] = byLevel[level[n]] || []).push(n);
  }

  // Real per-room thumbnail size: fixed width, real aspect ratio from
  // that room's own actual cols/rows (most rooms are 20x16, but this
  // must not assume that -- some real rooms differ).
  const THUMB_W = 130;
  const LABEL_H = 34; // name + tile-size caption below the thumbnail
  const NODE_PAD = 10;
  const COL_GAP = 100, ROW_GAP = 28;

  function thumbSize(n) {
    const m = mapByName[n];
    if (!m || !m.cols || !m.rows) return { w: THUMB_W, h: Math.round(THUMB_W * 0.8) };
    return { w: THUMB_W, h: Math.round(THUMB_W * (m.rows / m.cols)) };
  }
  function nodeSize(n) {
    const t = thumbSize(n);
    return { w: t.w + NODE_PAD * 2, h: t.h + LABEL_H + NODE_PAD * 2 };
  }

  const pos = {};
  const maxLevel = Math.max(...Object.keys(byLevel).map(Number));
  let x = 20;
  const colX = {};
  for (let lvl = 0; lvl <= maxLevel; lvl++) {
    colX[lvl] = x;
    const names = (byLevel[lvl] || []).slice().sort();
    let colWidth = 0;
    for (const n of names) colWidth = Math.max(colWidth, nodeSize(n).w);
    x += colWidth + COL_GAP;
  }
  let height = 20;
  for (let lvl = 0; lvl <= maxLevel; lvl++) {
    const names = (byLevel[lvl] || []).slice().sort();
    let y = 20;
    for (const n of names) {
      const sz = nodeSize(n);
      pos[n] = { x: colX[lvl], y, w: sz.w, h: sz.h };
      y += sz.h + ROW_GAP;
    }
    height = Math.max(height, y);
  }
  const width = x;

  const svg = document.getElementById("roomGraphSvg");
  const nodesHost = document.getElementById("roomGraphNodes");
  document.getElementById("roomGraphHost").style.width = "100%";
  document.getElementById("roomGraphHost").style.height = Math.min(height + 20, 640) + "px";
  nodesHost.style.width = svg.style.width = width + "px";
  nodesHost.style.height = svg.style.height = height + "px";
  svg.setAttribute("width", width);
  svg.setAttribute("height", height);
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);

  // Node DOM: a small card per room, thumbnail canvas + label, real
  // pixel content filled in by drawThumbnails() below (needs a
  // loaded ROM; the grid/box outline shows even without one, same
  // "structure visible, pixels need a ROM" convention as the
  // Map-Viewer/Tile-Viewer).
  let nodesHtml = "";
  for (const n of nodeNames) {
    const p = pos[n];
    const m = mapByName[n];
    const isLeaf = !roomByName[n];
    nodesHtml += `
      <div class="room-node-card${isLeaf ? " leaf" : ""}" data-room="${escapeHtml(n)}"
           style="position:absolute; left:${p.x}px; top:${p.y}px; width:${p.w}px; height:${p.h}px;
                  box-sizing:border-box; border:1px solid var(--border); border-radius:8px;
                  background:var(--bg-card,#171b10); padding:${NODE_PAD}px; text-align:center;">
        <canvas class="room-thumb-canvas" width="10" height="10"
                style="image-rendering:pixelated; max-width:100%; border:1px solid var(--border-faint,#2a331b); border-radius:4px;"
                role="img" aria-label="Echte Raum-Kachelkarte für ${escapeHtml(n)}"></canvas>
        <div style="font-size:11px; margin-top:4px; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${escapeHtml(n)}</div>
        <div style="font-size:9px; color:var(--text-faint);">${m ? m.cols + "&times;" + m.rows + " Tiles" : (roomByName[n] ? "kein Kartenraster" : "kein eigener Exit-Eintrag")}</div>
      </div>`;
  }
  nodesHost.innerHTML = nodesHtml;

  // Edges: connect the real right-edge/left-edge midpoints of the
  // rendered node CARDS (not a fixed guess) -- same curved-path +
  // arrowhead-marker convention as before, recomputed for the new,
  // per-room-sized node boxes.
  let markerDefs = `<defs>
    <marker id="arrow-scroll" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent2)"></path></marker>
    <marker id="arrow-cut" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent3)"></path></marker>
  </defs>`;
  let edgesSvg = "";
  for (const e of edges) {
    const a = pos[e.from], b = pos[e.to];
    if (!a || !b) continue;
    const x1 = a.x + a.w, y1 = a.y + a.h / 2;
    const x2 = b.x, y2 = b.y + b.h / 2;
    const midX = (x1 + x2) / 2;
    const cls = e.transitionType === "scroll" ? "edge-scroll" : "edge-cut";
    const marker = e.transitionType === "scroll" ? "arrow-scroll" : "arrow-cut";
    edgesSvg += `<path class="${cls}" marker-end="url(#${marker})" d="M${x1},${y1} C${midX},${y1} ${midX},${y2} ${x2 - 6},${y2}"></path>`;
    const label = e.transitionType === "scroll" ? `scroll (${e.axis}, ${e.totalPixels}px)` : "cut";
    edgesSvg += `<text class="edge-label" x="${midX}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle">${label}</text>`;
  }
  svg.innerHTML = markerDefs + edgesSvg;

  function drawThumbnails() {
    document.querySelectorAll(".room-thumb-canvas").forEach(canvas => {
      const name = canvas.closest(".room-node-card").dataset.room;
      const m = mapByName[name];
      if (!m) {
        canvas.width = 10; canvas.height = 10;
        return;
      }
      const t = thumbSize(name);
      const tilePx = t.w / m.cols;
      canvas.width = t.w;
      canvas.height = Math.round(m.rows * tilePx);
      const ctx2d = canvas.getContext("2d");
      ctx2d.fillStyle = "#1a1e14";
      ctx2d.fillRect(0, 0, canvas.width, canvas.height);
      const tileCache = {};
      for (let row = 0; row < m.rows; row++) {
        for (let col = 0; col < m.cols; col++) {
          const tileId = m.grid[row][col];
          let decoded = tileCache[tileId];
          if (decoded === undefined) {
            const entry = m.tileOffsets[String(tileId)];
            const bytes = entry !== undefined ? resolveTileBytes(entry) : null;
            decoded = bytes ? gbDecodeTile(bytes) : null;
            tileCache[tileId] = decoded;
          }
          const dx = col * tilePx, dy = row * tilePx;
          if (decoded) {
            gbDrawTileScaled(ctx2d, decoded, dx, dy, tilePx);
          } else {
            ctx2d.strokeStyle = "#3a4a2a";
            ctx2d.strokeRect(dx + 0.5, dy + 0.5, tilePx - 1, tilePx - 1);
          }
        }
      }
    });
  }
  drawThumbnails();

  // Cards with the raw exit facts underneath the diagram (unchanged).
  const cardsHost = document.getElementById("roomCards");
  for (const r of ROOMS) {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `<h3>${escapeHtml(r.name)}</h3>
      <div class="desc">${r.widthTiles}&times;${r.heightTiles} Tiles &middot; ${r.exits.length} Exit(s)</div>
      ${r.exits.map(ex => `<div class="meta">&rarr; ${escapeHtml(ex.targetRoom)}: ${escapeHtml(ex.transitionType)}${ex.axis ? ", Achse " + ex.axis : ""}${ex.totalPixels ? ", " + ex.totalPixels + "px" : ""}${ex.reverse ? ", reverse" : ""} <span class="badge ${badgeClassForStatus(ex.status)}" style="margin-left:4px;">${ex.status || "?"}</span></div>`).join("")}
    `;
    cardsHost.appendChild(card);
  }
}

// `gbDrawTile` (js/rombytes.js) always draws at an INTEGER `scale`
// multiple of 8px (it loops pixel-by-pixel). Room thumbnails need an
// arbitrary, possibly-fractional per-tile pixel size (THUMB_W spread
// across each real room's own, varying `cols`) -- draw each decoded
// 8x8 tile to a tiny offscreen canvas at 1x once, then let the browser
// scale that onto the thumbnail, instead of teaching the shared
// primitive a fractional-scale pixel loop it doesn't need anywhere
// else on the site.
const _tinyTileCanvas = document.createElement("canvas");
_tinyTileCanvas.width = 8;
_tinyTileCanvas.height = 8;
const _tinyTileCtx = _tinyTileCanvas.getContext("2d");
function gbDrawTileScaled(ctx2d, tile, dx, dy, sizePx) {
  _tinyTileCtx.clearRect(0, 0, 8, 8);
  gbDrawTile(_tinyTileCtx, tile, 0, 0, 1);
  const prevSmoothing = ctx2d.imageSmoothingEnabled;
  ctx2d.imageSmoothingEnabled = false;
  ctx2d.drawImage(_tinyTileCanvas, 0, 0, 8, 8, dx, dy, sizePx, sizePx);
  ctx2d.imageSmoothingEnabled = prevSmoothing;
}
