// Pan/zoom (2026-08-17, direct user request: "mach den grafen noch
// scroll und zoombar") -- reuses the exact same Google-Maps-style
// convention worldmap.js already established for the Weltkarte page
// (see that file's own "Google-Maps-style pan/zoom" doc comment):
// `overflow:hidden` host + one absolutely-positioned child carrying a
// pure `translate(...) scale(...)` transform, Pointer Events unifying
// mouse drag + touch drag/pinch, wheel-zoom anchored under the cursor.
// Unlike worldmap.js (one canvas), the transformed child here wraps
// TWO siblings (the HTML `.room-node-card` thumbnails + the SVG arrow
// overlay) so both pan/zoom together as one rigid graph.
//
// Real trigger-zone -> landing-point arrows (same request, second
// half): every edge below now anchors at the REAL, empirically-
// bracketed `zone` rectangle (screen-space trigger area, exported
// as-is from rom_profiles.lua's own `exits[].zone`) in the source
// room's thumbnail, and the REAL `landingX`/`landingY` point in the
// target room's thumbnail -- not a generic node-edge midpoint. Room
// thumbnails in this dataset are always exactly one real GB screen's
// worth of tiles (20x16 = 160x128px, matches every `ROOM_MAPS` entry
// currently exported), so `zone`/`landingX/Y` (already real screen-
// space pixel coordinates, see rom_profiles.lua's own schema doc
// comment) map directly onto the thumbnail canvas via one linear scale
// factor -- no separate scroll-offset bookkeeping needed for THIS
// dataset. An exit missing `zone`/landing data (shouldn't currently
// happen -- all 8 live-wired exits have both) falls back to the old
// node-edge-midpoint anchor rather than crashing.
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
      (<span style="color:var(--accent3)">gestrichelt</span>). Jeder Pfeil beginnt exakt an der
      echten, empirisch eingegrenzten <span style="color:#e0a030;">Trigger-Zone</span> (gelbes
      Rechteck) im Quellraum und endet am echten <span style="color:#40c0ff;">Landepunkt</span>
      (blauer Punkt) im Zielraum &mdash; beides reale <code>zone</code>/<code>landingX</code>/
      <code>landingY</code>-Werte, keine geschätzten Kantenmitten.
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
    <p class="page-lede">
      <span style="color:#e0a030;">&#9888; <code>startRoom</code></span> (amber gestrichelter
      Rahmen unten): ein echter, VERIFIED Raum &mdash; hostet den echten ersten Bosskampf
      (<code>BattleIntro.lua</code>s reale „Kaempfe!“-Sequenz, das Startbild von
      <code>Field.lua</code>) &mdash; aber OHNE live gefundene Verbindung zur
      <code>willyRoom</code>-Kette (die nur über den separaten VictorySequence/RoomExplorer-
      Debug-Walker erreichbar ist, nicht über den normalen Spielfluss). Ehrlich als
      eigenständiger, unverbundener Knoten gezeigt statt weggelassen.
    </p>
    <p class="page-lede">
      <span style="color:#9d6fe0;">&equiv; <code>fifthRoom</code></span> (violetter Rahmen unten):
      <strong>kein eigenständiger ROM-Raum</strong> &mdash; direkte Bestätigung eines Nutzer-Hinweises
      (2026-08-17: "ich bin mir sehr sicher das der übergang von fourth in den fith room einfach
      nur ein übergang zurück in den third room ist"). Live geprüft: die echten
      Raum-Identitätsregister (<code>$D392</code>/<code>$D393</code> Tile-Source-Pointer,
      <code>$C3F0</code> dynamicBank, <code>$C3F5</code> roomSelector) sind byte-identisch mit
      <code>willyRoom</code>/<code>secondRoom</code>/<code>thirdRoom</code>. Nuance: visuell/im
      Kachel-Grid nicht dasselbe bereits erfasste Bild wie <code>thirdRoom</code> (nur 17,5&nbsp;%
      Zellen-Übereinstimmung, gegen 82&ndash;89&nbsp;% zwischen je zwei der anderen drei) &mdash;
      vermutlich ein anderer, per Cut erreichter Scroll-Ausschnitt derselben großen Leinwand, aber
      real ROM-seitig derselbe Raum, kein unabhängiger. Details im Tooltip am Knoten.
    </p>
    <p class="page-lede">
      <span style="color:#e05a5a;">&#9888; <code>seventhRoom</code>/<code>eighthRoom</code>/
      <code>ninthRoom</code></span> (rot gestrichelter Rahmen unten): direkter, glaubwürdiger
      Nutzer-Hinweis (2026-08-17, echtes ROM-Wissen: "raum 7 8 und 9 haben die falschen tilesets") --
      gründlich nachgeprüft (externe FFA-Disassembly-Doku direkt abgerufen, Bank-5-Struktur auf eine
      versteckte zweite Karte geprüft, jeder bekannte alternative Tileset-Pointer ausprobiert), aber
      <strong>nicht gelöst</strong>. Diese 3 Räume waren schon vorher als "IMPLEMENTATION CHOICE,
      nicht ROM-bestätigt" markiert (kein Live-Gameplay erreicht sie je) -- dieser Hinweis geht
      darüber hinaus: konkret als wahrscheinlich falsch gemeldet, nicht nur unbestätigt. Details im
      Tooltip am jeweiligen Knoten.
    </p>
    <div id="roomGraphRomBanner"></div>
    <div class="toolbar" id="roomGraphToolbar" style="margin-bottom:8px; align-items:center; gap:8px;">
      <button class="btn small" id="roomZoomOut" type="button" title="Verkleinern">&minus;</button>
      <span id="roomZoomLabel" class="meta" style="min-width:44px; text-align:center;">100%</span>
      <button class="btn small" id="roomZoomIn" type="button" title="Vergrößern">+</button>
      <button class="btn small" id="roomZoomReset" type="button" title="Ganzen Graphen einpassen">Einpassen</button>
      <span class="meta" style="margin-left:8px;">Ziehen zum Verschieben, Mausrad/Pinch zum Zoomen (wie bei der Weltkarte).</span>
    </div>
    <div id="roomGraphHost" style="position:relative; overflow:hidden; border:1px solid var(--border); border-radius:8px; background:#10130c; height:70vh; min-height:420px; cursor:grab; touch-action:none; user-select:none;">
      <div id="roomGraphScaled" style="position:absolute; top:0; left:0; transform-origin:0 0;">
        <div id="roomGraphNodes" style="position:relative;"></div>
        <svg id="roomGraphSvg" style="position:absolute; top:0; left:0; pointer-events:none;"></svg>
      </div>
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
  let contentHeight = 20;
  for (let lvl = 0; lvl <= maxLevel; lvl++) {
    const names = (byLevel[lvl] || []).slice().sort();
    let y = 20;
    for (const n of names) {
      const sz = nodeSize(n);
      pos[n] = { x: colX[lvl], y, w: sz.w, h: sz.h };
      y += sz.h + ROW_GAP;
    }
    contentHeight = Math.max(contentHeight, y);
  }
  const contentWidth = x;

  const svg = document.getElementById("roomGraphSvg");
  const nodesHost = document.getElementById("roomGraphNodes");
  nodesHost.style.width = svg.style.width = contentWidth + "px";
  nodesHost.style.height = svg.style.height = contentHeight + "px";
  svg.setAttribute("width", contentWidth);
  svg.setAttribute("height", contentHeight);
  svg.setAttribute("viewBox", `0 0 ${contentWidth} ${contentHeight}`);

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
    // A real, VERIFIED room with a `note` (currently: startRoom, the
    // real first-boss-fight room -- see export_data.lua's own
    // ISOLATED_BUT_REAL_ROOMS comment) that has no live-traced exits
    // AND nothing else points to it -- shown as its own honestly-
    // disconnected node (distinct amber dashed border + a small
    // "isoliert" badge + the real reason as a hover tooltip) instead
    // of looking like an ordinary, silently-unconnected leaf.
    const roomEntry = roomByName[n];
    const isIsolated = !!(roomEntry && roomEntry.note);
    // A room whose real, live-confirmed WRAM room-identity registers
    // are byte-identical to another already-named room (currently:
    // fifthRoom = willyRoom/secondRoom/thirdRoom -- see
    // rom_profiles.lua's own `sameRomIdentityAs`/`sameRomIdentityNote`
    // doc comment, 2026-08-17 direct user claim "ich bin mir sehr
    // sicher das er übergang von fourth in den fith room einfach nur
    // ein übergang zurück in den third room ist") -- shown with a
    // distinct solid violet border + a "= <rooms>" badge + the real
    // evidence as a hover tooltip, visually different from the amber
    // dashed "isoliert" styling above (a different real finding: this
    // one IS connected, it's just not an independent room).
    const sameAs = roomEntry && roomEntry.sameRomIdentityAs;
    // A room flagged with a direct, credible user report that its own
    // catalog-derived tileset is wrong (currently: seventhRoom/
    // eighthRoom/ninthRoom -- see rom_profiles.lua's own
    // `tilesetDisputed`/`tilesetDisputedNote` doc comment, 2026-08-17
    // "raum 7 8 und 9 haben die falschen tilesets") -- thoroughly
    // re-investigated (external FFA-Disassembly doc, bank-5 structure,
    // every known alternate tileset pointer tried) but NOT resolved.
    // Distinct red dashed border + its own badge, takes priority over
    // the other real-but-different findings above (a credible dispute
    // is a stronger flag than "not independently confirmed" alone).
    const disputed = !!(roomEntry && roomEntry.tilesetDisputed);
    const borderStyle = disputed ? "2px dashed #e05a5a" : (isIsolated ? "2px dashed #e0a030" : (sameAs ? "2px solid #9d6fe0" : "1px solid var(--border)"));
    const tooltip = disputed ? roomEntry.tilesetDisputedNote : (isIsolated ? roomEntry.note : (sameAs ? roomEntry.sameRomIdentityNote : ""));
    nodesHtml += `
      <div class="room-node-card${isLeaf ? " leaf" : ""}" data-room="${escapeHtml(n)}"
           ${tooltip ? `title="${escapeHtml(tooltip)}"` : ""}
           style="position:absolute; left:${p.x}px; top:${p.y}px; width:${p.w}px; height:${p.h}px;
                  box-sizing:border-box; border:${borderStyle}; border-radius:8px;
                  background:var(--bg-card,#171b10); padding:${NODE_PAD}px; text-align:center;">
        <canvas class="room-thumb-canvas" width="10" height="10"
                style="image-rendering:pixelated; max-width:100%; border:1px solid var(--border-faint,#2a331b); border-radius:4px;"
                role="img" aria-label="Echte Raum-Kachelkarte für ${escapeHtml(n)}"></canvas>
        <div style="font-size:11px; margin-top:4px; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${escapeHtml(n)}</div>
        <div style="font-size:9px; color:var(--text-faint);">${m ? m.cols + "&times;" + m.rows + " Tiles" : (roomByName[n] ? "kein Kartenraster" : "kein eigener Exit-Eintrag")}</div>
        ${disputed ? `<div style="font-size:9px; color:#e05a5a; margin-top:2px;" title="${escapeHtml(roomEntry.tilesetDisputedNote)}">&#9888; Tileset umstritten</div>` : ""}
        ${isIsolated ? `<div style="font-size:9px; color:#e0a030; margin-top:2px;" title="${escapeHtml(roomEntry.note)}">&#9888; isoliert &mdash; 1. Bosskampf</div>` : ""}
        ${sameAs ? `<div style="font-size:9px; color:#9d6fe0; margin-top:2px;" title="${escapeHtml(roomEntry.sameRomIdentityNote)}">&equiv; ${escapeHtml(sameAs.join("/"))}</div>` : ""}
      </div>`;
  }
  nodesHost.innerHTML = nodesHtml;

  // Real thumbnail-space anchor for an exit's own trigger `zone`
  // (center of the real bracketed rectangle, missing bounds treated
  // as "unbounded to that room edge" per rom_profiles.lua's own exits
  // schema doc comment) or landing point, converted from real GB
  // screen-pixel space (0..160 x, 0..128/144 y) into this node's own
  // thumbnail pixel space via one linear scale factor. Returns null
  // if this node has no real ROOM_MAPS entry to scale against.
  const SCREEN_W = 160, SCREEN_H = 128; // matches every current 20x16 ROOM_MAPS entry
  function anchorAbs(name, screenX, screenY) {
    const p = pos[name], m = mapByName[name];
    if (!p || !m) return null;
    const t = thumbSize(name);
    const sx = t.w / SCREEN_W, sy = t.h / SCREEN_H;
    return {
      x: p.x + NODE_PAD + Math.max(0, Math.min(SCREEN_W, screenX)) * sx,
      y: p.y + NODE_PAD + Math.max(0, Math.min(SCREEN_H, screenY)) * sy,
    };
  }
  function zoneRectAbs(name, zone) {
    const p = pos[name], m = mapByName[name];
    if (!p || !m || !zone) return null;
    const t = thumbSize(name);
    const sx = t.w / SCREEN_W, sy = t.h / SCREEN_H;
    const xMin = zone.xMin != null ? zone.xMin : 0;
    const xMax = zone.xMax != null ? zone.xMax : SCREEN_W;
    const yMin = zone.yMin != null ? zone.yMin : 0;
    const yMax = zone.yMax != null ? zone.yMax : SCREEN_H;
    return {
      x: p.x + NODE_PAD + xMin * sx,
      y: p.y + NODE_PAD + yMin * sy,
      w: (xMax - xMin) * sx,
      h: (yMax - yMin) * sy,
      cx: p.x + NODE_PAD + ((xMin + xMax) / 2) * sx,
      cy: p.y + NODE_PAD + ((yMin + yMax) / 2) * sy,
    };
  }

  // Edges: real trigger-zone -> real landing-point anchors where the
  // exit carries that data (all 8 currently do); falls back to the
  // old node-edge-midpoint anchor otherwise, rather than guessing
  // coordinates that don't exist.
  let markerDefs = `<defs>
    <marker id="arrow-scroll" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent2)"></path></marker>
    <marker id="arrow-cut" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent3)"></path></marker>
  </defs>`;
  let edgesSvg = "";
  let overlaySvg = "";
  for (const e of edges) {
    const a = pos[e.from], b = pos[e.to];
    if (!a || !b) continue;
    const zoneRect = e.zone ? zoneRectAbs(e.from, e.zone) : null;
    const landing = (e.landingX != null && e.landingY != null) ? anchorAbs(e.to, e.landingX, e.landingY) : null;
    let x1, y1, x2, y2;
    if (zoneRect) {
      x1 = zoneRect.cx; y1 = zoneRect.cy;
      overlaySvg += `<rect class="zone-rect" x="${zoneRect.x}" y="${zoneRect.y}" width="${Math.max(2, zoneRect.w)}" height="${Math.max(2, zoneRect.h)}"></rect>`;
    } else {
      x1 = a.x + a.w; y1 = a.y + a.h / 2;
    }
    if (landing) {
      x2 = landing.x; y2 = landing.y;
      overlaySvg += `<circle class="landing-point" cx="${landing.x}" cy="${landing.y}" r="4"></circle>`;
    } else {
      x2 = b.x; y2 = b.y + b.h / 2;
    }
    const midX = (x1 + x2) / 2;
    const cls = e.transitionType === "scroll" ? "edge-scroll" : "edge-cut";
    const marker = e.transitionType === "scroll" ? "arrow-scroll" : "arrow-cut";
    edgesSvg += `<path class="${cls}" marker-end="url(#${marker})" d="M${x1},${y1} C${midX},${y1} ${midX},${y2} ${x2},${y2}"></path>`;
    const label = e.transitionType === "scroll" ? `scroll (${e.axis}, ${e.totalPixels}px)` : "cut";
    edgesSvg += `<text class="edge-label" x="${midX}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle">${label}</text>`;
  }
  svg.innerHTML = markerDefs + overlaySvg + edgesSvg;

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

  wireRoomGraphPanZoom(contentWidth, contentHeight);

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

// Google-Maps-style pan/zoom for the room graph -- see this file's own
// top-of-file doc comment. `contentWidth`/`contentHeight` are the
// graph's own real, unscaled pixel size (computed fresh in
// render_rooms every visit, since the graph's real layout can change
// as more exits get decoded); the view state itself is intentionally
// a plain local (re-created per visit, not persisted module-wide like
// worldmap.js's `WorldmapView`) -- this graph is small enough that
// "start fresh, fitted, on every visit" is the more useful default.
function wireRoomGraphPanZoom(contentWidth, contentHeight) {
  const host = document.getElementById("roomGraphHost");
  const scaled = document.getElementById("roomGraphScaled");
  if (!host || !scaled) return;
  const view = { scale: 1, tx: 0, ty: 0, minScale: 0.2, maxScale: 3 };
  const zoomLabel = document.getElementById("roomZoomLabel");

  function applyTransform() {
    scaled.style.transform = `translate(${view.tx}px, ${view.ty}px) scale(${view.scale})`;
    if (zoomLabel) zoomLabel.textContent = Math.round(view.scale * 100) + "%";
  }

  function fitToViewport() {
    const vw = host.clientWidth, vh = host.clientHeight;
    if (!vw || !vh || !contentWidth || !contentHeight) return;
    const s = Math.min(vw / contentWidth, vh / contentHeight, 1);
    view.scale = Math.max(view.minScale, s);
    view.tx = (vw - contentWidth * view.scale) / 2;
    view.ty = (vh - contentHeight * view.scale) / 2;
    applyTransform();
  }

  function zoomAt(factor, anchorX, anchorY) {
    const newScale = Math.min(view.maxScale, Math.max(view.minScale, view.scale * factor));
    const worldX = (anchorX - view.tx) / view.scale;
    const worldY = (anchorY - view.ty) / view.scale;
    view.tx = anchorX - worldX * newScale;
    view.ty = anchorY - worldY * newScale;
    view.scale = newScale;
    applyTransform();
  }

  document.getElementById("roomZoomIn").addEventListener("click", () => {
    zoomAt(1.25, host.clientWidth / 2, host.clientHeight / 2);
  });
  document.getElementById("roomZoomOut").addEventListener("click", () => {
    zoomAt(1 / 1.25, host.clientWidth / 2, host.clientHeight / 2);
  });
  document.getElementById("roomZoomReset").addEventListener("click", fitToViewport);

  // Pointer Events unify mouse + touch, same convention as
  // worldmap.js's own `wirePanZoom` (see that file for the fuller
  // doc comment on the click-vs-drag / pinch-vs-pan disambiguation).
  const pointers = new Map();
  let pinchStartDist = null, pinchStartScale = null;
  function dist() {
    const pts = [...pointers.values()];
    return Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
  }
  function midpoint() {
    const pts = [...pointers.values()];
    return { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
  }

  host.addEventListener("pointerdown", (ev) => {
    host.setPointerCapture(ev.pointerId);
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (pointers.size === 2) {
      pinchStartDist = dist();
      pinchStartScale = view.scale;
    }
    host.style.cursor = "grabbing";
  });
  host.addEventListener("pointermove", (ev) => {
    if (!pointers.has(ev.pointerId)) return;
    const prev = pointers.get(ev.pointerId);
    const dx = ev.clientX - prev.x, dy = ev.clientY - prev.y;
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (pointers.size === 2 && pinchStartDist) {
      const d = dist();
      const rect = host.getBoundingClientRect();
      const mid = midpoint();
      const factor = (d / pinchStartDist) * (pinchStartScale / view.scale);
      zoomAt(factor, mid.x - rect.left, mid.y - rect.top);
    } else if (pointers.size === 1) {
      view.tx += dx;
      view.ty += dy;
      applyTransform();
    }
  });
  function endPointer(ev) {
    if (!pointers.has(ev.pointerId)) return;
    pointers.delete(ev.pointerId);
    pinchStartDist = null;
    host.style.cursor = "grab";
  }
  host.addEventListener("pointerup", endPointer);
  host.addEventListener("pointercancel", endPointer);

  host.addEventListener("wheel", (ev) => {
    ev.preventDefault();
    const rect = host.getBoundingClientRect();
    const factor = ev.deltaY < 0 ? 1.15 : 1 / 1.15;
    zoomAt(factor, ev.clientX - rect.left, ev.clientY - rect.top);
  }, { passive: false });

  function onResize() {
    if (document.getElementById("roomGraphHost") === host) fitToViewport();
  }
  window.addEventListener("resize", onResize);
  onSectionUnload(() => window.removeEventListener("resize", onResize));

  fitToViewport();
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
