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
      Jeder Knoten ist die echte, live aus der ROM gerenderte Raum-Kachelkarte; jeder Pfeil ein
      echter, live bestätigter Übergang (<span style="color:var(--accent2)">durchgezogen</span>
      = Hardware-Scroll, <span style="color:var(--accent3)">gestrichelt</span> = „Cut“-Szenenwechsel),
      von der echten <span style="color:#e0a030;">Trigger-Zone</span> zum echten
      <span style="color:#40c0ff;">Landepunkt</span>. Nur tatsächlich im Spiel verdrahtete
      Übergänge &mdash; die vollständige rohe ROM-Tabelle (82 Einträge) steht unter
      <a href="#transitions">Raum-Übergänge</a>.
    </p>
    <p class="page-lede">
      Mehrere Verbindungsversuche für weitere Räume (<code>worldMapRoom_131</code>/<code>132</code>,
      <code>unknownRoomA_8</code>&ndash;<code>13</code>, <code>eighthRoom</code>/<code>ninthRoom</code>)
      wurden 2026-08-19/20 gebaut und wieder zurückgezogen, nachdem sie sich als nicht belastbar
      erwiesen (fehlerhafte Kollisionsdaten bzw. fehlender räumlicher Bezug). Diese Räume sind
      entweder gar nicht mehr vorhanden oder haben aktuell keine Verbindung. Voller Verlauf:
      <details style="display:inline;">
        <summary style="display:inline; cursor:pointer; color:var(--accent2);">Details</summary>
        <div style="margin-top:8px; font-size:13px; color:var(--text-dim); line-height:1.6;">
          <code>seventhRoom</code>&rarr;<code>worldMapRoom_131</code> beruhte auf keinem echten
          räumlichen Bezug (zwei unterschiedliche Katalog-Raster) und wurde nach direkter
          Nutzer-Korrektur entfernt. <code>unknownRoomA_8</code>&ndash;<code>13</code> hatten
          zunächst kaputte Bodendaten (2026-08-19), später einen technisch korrekten, aber vom
          Nutzer als falsch verworfenen Verbindungsversuch (2026-08-20). <code>eighthRoom</code>/
          <code>ninthRoom</code> wurden komplett gelöscht, da ihre Identifikation als falsch
          erkannt wurde. Vollständiger, datierter Bericht: <code>docs/reverse-engineering/events.md</code>.
        </div>
      </details>
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
  //
  // MERGE, 2026-08-18 (direct, repeated, frustrated user report: "DER
  // FITH ROOM IST DOCH IMMERNOCH IM RAUMSYSTEM UND DER STARTRAUM IST
  // IMMERNOCH NOICHT IDENTISCH MIT DEM 6. ROOM" -- the violet "same
  // identity" badge alone never actually removed the duplicate box, it
  // only decorated it; both `r.name` below and every `ex.targetRoom`
  // reference still created/kept a genuinely separate node). `mergeInto`
  // (rom_profiles.lua, see fifthRoom/sixthRoom's own doc comments) names
  // the room a mergeable room's own real identity resolves to --
  // `resolveMerge` follows it (a short bounded loop, not just one hop,
  // in case a future merge target is itself later merged again) so a
  // mergeable room NEVER becomes its own node and every edge that would
  // have pointed at it points at its real canonical room instead.
  const roomByNameRaw = {};
  for (const r of ROOMS) roomByNameRaw[r.name] = r;
  function resolveMerge(name) {
    const seen = new Set();
    while (roomByNameRaw[name] && roomByNameRaw[name].mergeInto && !seen.has(name)) {
      seen.add(name);
      name = roomByNameRaw[name].mergeInto;
    }
    return name;
  }
  // Collect, per canonical room, which mergeable rooms resolved into it
  // -- shown on the canonical node itself so the real identity info
  // isn't lost, just no longer a separate box.
  const aliasesOf = {};
  for (const r of ROOMS) {
    if (r.mergeInto) {
      const canonical = resolveMerge(r.name);
      (aliasesOf[canonical] = aliasesOf[canonical] || []).push(r.name);
    }
  }

  const nodeNames = new Set();
  const roomByName = {};
  for (const r of ROOMS) {
    if (r.mergeInto) continue; // merged away -- never its own node, see resolveMerge above
    nodeNames.add(r.name);
    roomByName[r.name] = r;
  }
  let edges = [];
  for (const r of ROOMS) {
    if (r.mergeInto) continue; // a merged room's own listed exits (if any) are not rendered separately
    for (const ex of r.exits) {
      const target = resolveMerge(ex.targetRoom);
      nodeNames.add(target);
      edges.push({ from: r.name, to: target, redirected: target !== ex.targetRoom, ...ex });
    }
  }
  // BUG FIX, 2026-08-18 (direct user report "die website hängt beim
  // laden" -- a real regression from the `mergeInto` redirect above,
  // not a pre-existing issue): redirecting an alias's own edge can turn
  // an already-real edge into a direct 2-cycle -- concretely,
  // thirdRoom->fourthRoom already existed, and fourthRoom's own real
  // north exit (originally ->fifthRoom) now resolves to ->thirdRoom,
  // the exact reverse. The BFS leveling loop below has no cycle guard
  // (`level[e.to] < l + 1` stays true forever around a cycle, since
  // both directions keep pushing each other's level higher without
  // bound) -- a genuine infinite loop, not just a slow one, which is
  // exactly why the page hung rather than just rendering wrong.
  //
  // Fixed generically, not special-cased to this one pair: for any
  // reverse-direction pair, keep the edge that was NOT itself a merge
  // redirect (the real, original transition) and drop the redirected
  // one -- its semantic info isn't lost, it's already stated in the
  // source room's own `bridgeNote` tooltip (see fourthRoom's own doc
  // comment). If somehow both sides of a pair were redirected, fall
  // back to a deterministic name-order tie-break so exactly one survives
  // either way -- never both, never neither.
  const pairSet = new Set(edges.map(e => e.from + "→" + e.to));
  edges = edges.filter(e => {
    if (!pairSet.has(e.to + "→" + e.from)) return true; // no reverse edge at all, always keep
    const reverse = edges.find(o => o.from === e.to && o.to === e.from);
    if (e.redirected && !reverse.redirected) return false; // drop the redirected side
    if (!e.redirected && reverse.redirected) return true; // keep the original side
    return e.from < e.to; // both/neither redirected -- deterministic tie-break
  });
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

  // Scroll-chain grouping (2026-08-18, direct user request "wenn es die
  // selbe fortlaufende leinwand ist dann sollte es auch so dargestellt
  // werden" -- a plain arrow between two rooms connected by a real
  // hardware SCROLL, not a cut, otherwise reads exactly like a discrete
  // cut transition; the edge's own dashed/solid line style hints at the
  // difference but doesn't make "these are ONE continuous space, not
  // several separate rooms" immediately visible). Real ROM basis: only
  // willyRoom<->secondRoom<->thirdRoom are connected exclusively by
  // `transitionType==="scroll"` edges (see rom_profiles.lua's own
  // exits data) -- a real, empirically-measured SCX/SCY hardware
  // scroll, not a guess. Drawn as one shared, labeled background behind
  // the group's own room cards (still individually shown, each with its
  // own real captured content -- grouping is a visual framing, not a
  // data merge like `mergeInto` above).
  const scrollAdj = {};
  for (const e of edges) {
    if (e.transitionType !== "scroll") continue;
    (scrollAdj[e.from] = scrollAdj[e.from] || new Set()).add(e.to);
    (scrollAdj[e.to] = scrollAdj[e.to] || new Set()).add(e.from);
  }
  const groupVisited = new Set();
  const scrollGroups = [];
  for (const n of nodeNames) {
    if (groupVisited.has(n) || !scrollAdj[n]) continue;
    const group = [];
    const queue = [n];
    groupVisited.add(n);
    while (queue.length) {
      const cur = queue.shift();
      group.push(cur);
      for (const nb of scrollAdj[cur] || []) {
        if (!groupVisited.has(nb)) { groupVisited.add(nb); queue.push(nb); }
      }
    }
    if (group.length > 1) scrollGroups.push(group);
  }
  const GROUP_PAD = 14;
  let groupsHtml = "";
  for (const group of scrollGroups) {
    const ps = group.map(g => pos[g]).filter(Boolean);
    if (!ps.length) continue;
    const minX = Math.min(...ps.map(p => p.x)) - GROUP_PAD;
    const minY = Math.min(...ps.map(p => p.y)) - GROUP_PAD;
    const maxX = Math.max(...ps.map(p => p.x + p.w)) + GROUP_PAD;
    const maxY = Math.max(...ps.map(p => p.y + p.h)) + GROUP_PAD;
    groupsHtml += `
      <div style="position:absolute; left:${minX}px; top:${minY}px; width:${maxX - minX}px; height:${maxY - minY}px;
                  border:2px dashed var(--accent2); border-radius:14px;
                  background:rgba(80,200,180,0.08); box-sizing:border-box; pointer-events:none;"
           title="${escapeHtml(group.join(" ↔ "))}: echte Hardware-Scroll-Kette (SCX/SCY-Bewegung, kein Cut) -- eine durchgehende Leinwand, keine separaten Räume.">
        <div style="position:absolute; top:-11px; left:12px; background:var(--bg-page,#0d100a); padding:0 6px; font-size:10px; color:var(--accent2); font-weight:600; white-space:nowrap;">
          &#8644; eine durchgehende Leinwand (Scroll, kein Cut)
        </div>
      </div>`;
  }

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
    // Priority REORDERED (2026-08-17, direct user instruction "der
    // startraum muss im raumsystem auch anders dargestellt werden"):
    // `sameAs` now outranks `isIsolated`. Real reason: startRoom now
    // carries BOTH flags at once (its own graph node has no traced
    // exit -- isIsolated -- but it's the exact same real ROM room as
    // sixthRoom, which IS connected -- sameAs). The OLD order showed
    // amber "isoliert" for that case, which reads as "this room is not
    // really connected to anything" -- misleading once the real
    // same-identity link is known. `sameAs` is the stronger, more
    // specific real finding (a live-confirmed WRAM identity match, not
    // just "no traced exit yet") so it wins the border/tooltip slot;
    // the isolated badge text below still renders alongside it as
    // secondary context, just no longer the PRIMARY framing.
    const borderStyle = disputed ? "2px dashed #e05a5a" : (sameAs ? "2px solid #9d6fe0" : (isIsolated ? "2px dashed #e0a030" : "1px solid var(--border)"));
    const tooltip = disputed ? roomEntry.tilesetDisputedNote : (sameAs ? roomEntry.sameRomIdentityNote : (isIsolated ? roomEntry.note : ""));
    // Real, live-confirmed presence in the bank6 8x8 world-map catalog
    // (currently: startRoom at (7,4), fourthRoom at (7,5) -- see
    // rom_profiles.lua's own `worldMapCatalogRecord` doc comment,
    // 2026-08-17 direct user report "Der Bossraum sowie der Raum vorm
    // Boss sind jeweils auf der Weltmap"). Additive, not a border-style
    // priority slot: this can and does co-occur with the amber
    // "isoliert" badge above (startRoom has no live play-flow
    // connection AND is a real catalog entry -- both true at once, not
    // contradictory).
    const worldMapRec = roomEntry && roomEntry.worldMapCatalogRecord;
    // A room whose own exits BOTH terminate back inside already-known
    // territory (currently: fourthRoom -- see rom_profiles.lua's own
    // `bridgeNote` doc comment, 2026-08-18 direct user framing "das ist
    // quasi der Rückweg"). Additive, same convention as `worldMapRec`
    // above (co-occurs with any border-priority flag, not exclusive) --
    // this is a real, separate finding about the room's own ROLE in the
    // map graph, not about its identity or tileset.
    const bridgeNote = roomEntry && roomEntry.bridgeNote;
    // Rooms that MERGED into this one (see resolveMerge above) -- shown
    // right on the canonical node so the real identity match stays
    // visible even though the alias itself no longer gets its own box.
    const aliases = aliasesOf[n];
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
        ${worldMapRec ? `<div style="font-size:9px; color:#5ac0a0; margin-top:2px;" title="Echter Eintrag im 8x8-Weltkarten-Katalog (${escapeHtml(worldMapRec.table)}, Record ${worldMapRec.recordIndex}) -- live per Zell-fuer-Zell-Vergleich bestaetigt.">&#128506; Weltkarte (${worldMapRec.row},${worldMapRec.col})</div>` : ""}
        ${bridgeNote ? `<div style="font-size:9px; color:#e0c05a; margin-top:2px;" title="${escapeHtml(bridgeNote)}">&#128279; Brücke &mdash; führt zurück in bekanntes Gebiet</div>` : ""}
        ${aliases ? `<div style="font-size:9px; color:#9d6fe0; margin-top:2px;" title="Diese Räume sind laut live bestätigten ROM-Identitätsregistern derselbe reale Raum wie ${escapeHtml(n)} -- als eigener Knoten zusammengeführt, nicht separat gezeigt.">&equiv; auch: ${escapeHtml(aliases.join(", "))}</div>` : ""}
      </div>`;
  }
  nodesHost.innerHTML = groupsHtml + nodesHtml;

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
