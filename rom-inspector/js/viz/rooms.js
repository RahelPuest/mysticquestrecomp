function render_rooms(main) {
  main.innerHTML = `
    <h1 class="page-title">Raum-System</h1>
    <p class="page-lede">
      Jeder Knoten ist ein realer Raum, jede Kante ein echter, empirisch gefundener
      Übergang (Trigger-Zone + Übergangsmechanismus + Zielraum), direkt aus
      <code>rom_profiles.lua</code>s <code>graphics.&lt;room&gt;.exits</code> gelesen.
      Zwei reale Mechanismen kommen vor: ein echter Hardware-Scroll (<span style="color:var(--accent2)">durchgezogen</span>)
      und ein echter „Cut“ &mdash; ein sofortiger Szenenwechsel über die relozierbare
      Zeiger-Pipeline (<span style="color:var(--accent3)">gestrichelt</span>).
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
    <svg id="roomGraphSvg"></svg>
    <div class="card-grid" id="roomCards" style="margin-top:20px;"></div>
  `;

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

  // BFS leveling (multi-root).
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
  // Anything unreached (shouldn't happen, but stay honest/robust).
  for (const n of nodeNames) if (level[n] === undefined) level[n] = 0;

  const byLevel = {};
  for (const n of nodeNames) {
    (byLevel[level[n]] = byLevel[level[n]] || []).push(n);
  }
  const NODE_W = 150, NODE_H = 56, COL_GAP = 90, ROW_GAP = 40;
  const pos = {};
  const maxLevel = Math.max(...Object.keys(byLevel).map(Number));
  let maxRows = 1;
  for (const lvl of Object.keys(byLevel)) {
    byLevel[lvl].sort();
    maxRows = Math.max(maxRows, byLevel[lvl].length);
    byLevel[lvl].forEach((n, i) => {
      pos[n] = {
        x: 40 + Number(lvl) * (NODE_W + COL_GAP),
        y: 40 + i * (NODE_H + ROW_GAP),
      };
    });
  }
  const width = 40 + (maxLevel + 1) * (NODE_W + COL_GAP);
  const height = 40 + maxRows * (NODE_H + ROW_GAP);

  const svg = document.getElementById("roomGraphSvg");
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.style.height = Math.min(height, 560) + "px";

  let markerDefs = `<defs>
    <marker id="arrow-scroll" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent2)"></path></marker>
    <marker id="arrow-cut" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 Z" fill="var(--accent3)"></path></marker>
  </defs>`;

  let edgesSvg = "";
  for (const e of edges) {
    const a = pos[e.from], b = pos[e.to];
    if (!a || !b) continue;
    const x1 = a.x + NODE_W, y1 = a.y + NODE_H / 2;
    const x2 = b.x, y2 = b.y + NODE_H / 2;
    const midX = (x1 + x2) / 2;
    const cls = e.transitionType === "scroll" ? "edge-scroll" : "edge-cut";
    const marker = e.transitionType === "scroll" ? "arrow-scroll" : "arrow-cut";
    edgesSvg += `<path class="${cls}" marker-end="url(#${marker})" d="M${x1},${y1} C${midX},${y1} ${midX},${y2} ${x2 - 6},${y2}"></path>`;
    const label = e.transitionType === "scroll" ? `scroll (${e.axis}, ${e.totalPixels}px)` : "cut";
    edgesSvg += `<text class="edge-label" x="${midX}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle">${label}</text>`;
  }

  let nodesSvg = "";
  for (const n of nodeNames) {
    const p = pos[n];
    const isLeaf = !roomByName[n];
    const r = roomByName[n];
    nodesSvg += `<g class="room-node${isLeaf ? " leaf" : ""}">
      <rect x="${p.x}" y="${p.y}" width="${NODE_W}" height="${NODE_H}" rx="8"></rect>
      <text x="${p.x + 12}" y="${p.y + 24}">${escapeHtml(n)}</text>
      <text x="${p.x + 12}" y="${p.y + 40}" style="fill:var(--text-faint); font-size:10px;">${r ? r.widthTiles + "x" + r.heightTiles + " Tiles" : "kein eigener Exit-Eintrag"}</text>
    </g>`;
  }
  svg.innerHTML = markerDefs + edgesSvg + nodesSvg;

  // Cards with the raw exit facts underneath the diagram.
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
