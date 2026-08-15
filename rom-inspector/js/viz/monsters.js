// Draws a multi-tile sprite (row-major `tileOffsets`, `cols`x`rows`)
// onto a canvas, real pixels straight from a locally-loaded ROM (see
// js/rombytes.js's own `RomBytes`/`resolveTileBytes`/`gbDecodeTile`/
// `gbDrawTile` -- the SAME primitives js/viz/tiles.js already uses).
// `flip`, mirrors the WHOLE assembled sprite as one unit -- matching
// `src/rendering/CreatureSprite.lua`'s own real `:draw(x,y,flipX,
// flipY)` implementation (real hardware OAM flip bits, not a per-tile
// operation): a plain boolean means X-flip only (the monster's own
// `flipXTogglesPerStep`, see rom_profiles.lua's own doc comment);
// `{x=,y=}` selects each axis independently -- secondRoom's NPCs use a
// REAL `flipY` for their down/up phase-2 frame (see rom_profiles.lua's
// `secondRoom.scene.characterA.animation` doc comment for the live
// capture + a same-day bug fix that first mis-modeled this as X-flip).
function drawSpriteGrid(canvas, tileOffsets, cols, rows, scale, flip) {
  const f = (typeof flip === "object" && flip !== null) ? flip : { x: !!flip, y: false };
  canvas.width = cols * 8 * scale;
  canvas.height = rows * 8 * scale;
  const ctx2d = canvas.getContext("2d");
  ctx2d.fillStyle = "#1a1e14";
  ctx2d.fillRect(0, 0, canvas.width, canvas.height);
  ctx2d.save();
  if (f.x || f.y) {
    ctx2d.translate(f.x ? canvas.width : 0, f.y ? canvas.height : 0);
    ctx2d.scale(f.x ? -1 : 1, f.y ? -1 : 1);
  }
  tileOffsets.forEach((off, i) => {
    const bytes = resolveTileBytes(off);
    const tx = (i % cols) * 8 * scale, ty = Math.floor(i / cols) * 8 * scale;
    if (bytes) {
      gbDrawTile(ctx2d, gbDecodeTile(bytes), tx, ty, scale);
    } else {
      ctx2d.strokeStyle = "#3a4a2a";
      ctx2d.strokeRect(tx + 0.5, ty + 0.5, 8 * scale - 1, 8 * scale - 1);
    }
  });
  ctx2d.restore();
}

function render_monsters(main) {
  const ks = MONSTERS.knownSprite; // top-level real sprite data (1 of 11 species)
  main.innerHTML = `
    <h1 class="page-title">Monster</h1>
    <p class="page-lede">
      Alle 11 echten Spezies aus der ROM-eigenen <code>enemySpeciesTable</code>
      (46 Zeilen, mehrere Zeilen pro Spezies) &mdash; ATK ist VERIFIED (live
      registerabgeglichen), <code>defCandidate1</code>/<code>defCandidate2</code>
      sind echte, spezies-abhängige Bytes, aber nach 4 unabhängigen
      Untersuchungen (siehe combat.md) OHNE gefundenen Konsumenten &mdash; hier
      als Rohdaten gezeigt, nicht als funktionierender DEF-Wert behauptet.
      Nur 1 der 11 Spezies hat eine bekannte echte Sprite-Grafik (per
      Live-OAM-Tracing während eines echten Kampfes gefunden) &mdash; die
      anderen 10 sind ehrlich als "Grafik unbekannt" markiert.
    </p>
    <div id="monsterRomBanner"></div>
    ${ks ? `
    <div class="card" style="max-width:260px;">
      <h3>Bekanntes Sprite (Spezies 4)</h3>
      <div class="meta">${ks.cols}&times;${ks.rows} Kacheln &middot; echtes Hardware-X-Flip = 2. Pose</div>
      <canvas id="monsterSpriteCanvas" width="10" height="10" style="margin-top:8px; image-rendering: pixelated;"></canvas>
      <div class="toolbar" style="margin-top:8px;">
        <div class="pill-tabs" id="monsterPoseTabs">
          <div class="pill-tab active" data-flip="0">Pose A</div>
          ${ks.flipXTogglesPerStep ? '<div class="pill-tab" data-flip="1">Pose B (gespiegelt)</div>' : ""}
        </div>
      </div>
    </div>` : ""}
    <div class="card-grid" id="monsterCards" style="margin-top:16px;"></div>

    <h2 class="page-title" style="margin-top:32px; font-size:1.3em;">Grafik-Kandidaten (unbestätigt)</h2>
    <p class="page-lede">
      Echte, visuell bestätigte Kreatur-/Charakter-/Icon-Grafikbereiche, gefunden
      durch ein vollständiges Rendern JEDER ROM-Bank (0&ndash;15) und manuelle
      Durchsicht &mdash; nicht nur einzelne Treffer eines heuristischen Scans.
      Banks 8, 9, 10 und 11 enthalten echte, dichte Grafik-Inhalte; alle anderen
      Banks wurden geprüft und enthalten nachweislich keine (reiner Code/Text/
      Raumdaten). KEINER dieser Bereiche ist einer bestätigten Spezies, einem
      Raum oder einem echten Spawn-Trigger zugeordnet. Das sind echte ROM-Pixel
      (du siehst sie unten direkt aus deiner geladenen ROM gerendert), aber die
      Identität ist ehrlich unbestätigt &mdash; siehe GraphicsCandidates.lua für
      die volle Methodik.
    </p>
    <div class="card-grid" id="graphicsCandidateCards" style="margin-top:16px;"></div>
  `;

  updateRomBanner(document.getElementById("monsterRomBanner"));
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("monsterRomBanner"));
    if (ks) drawSpriteGrid(document.getElementById("monsterSpriteCanvas"), ks.tileOffsets, ks.cols, ks.rows, 4, false);
    redrawGraphicsCandidates();
  }));

  if (ks) {
    const canvas = document.getElementById("monsterSpriteCanvas");
    drawSpriteGrid(canvas, ks.tileOffsets, ks.cols, ks.rows, 4, false);
    document.querySelectorAll("#monsterPoseTabs .pill-tab").forEach(tab => {
      tab.addEventListener("click", () => {
        document.querySelectorAll("#monsterPoseTabs .pill-tab").forEach(t => t.classList.remove("active"));
        tab.classList.add("active");
        drawSpriteGrid(canvas, ks.tileOffsets, ks.cols, ks.rows, 4, tab.dataset.flip === "1");
      });
    });
  }

  const host = document.getElementById("monsterCards");
  for (const m of MONSTERS.species) {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>Spezies ${m.speciesIndex}</h3>
      <span class="badge ${m.knownSprite ? "verified" : "unknown-b"}">
        ${m.knownSprite ? "Sprite bekannt" : "Sprite unbekannt"}
      </span>
      <div class="meta">
        Zeilen ${m.firstRowIndex}&ndash;${m.firstRowIndex + m.rowCount - 1} (${m.rowCount}x)
        &middot; flagVariant ${m.flagVariant}
      </div>
      <table class="data-table" style="margin-top:10px;">
        <tr><th>ATK</th><td class="num">${m.atk}</td><td class="desc">VERIFIED</td></tr>
        <tr><th>defCandidate1</th><td class="num">${m.defCandidate1}</td><td class="desc">real, kein Konsument gefunden</td></tr>
        <tr><th>defCandidate2</th><td class="num">${m.defCandidate2}</td><td class="desc">real, kein Konsument gefunden</td></tr>
      </table>
      <div class="meta" style="margin-top:8px;">
        raw: ${m.rawBytes.map(b => hex(b, 2)).join(" ")}
      </div>
    `;
    host.appendChild(card);
  }

  const gcHost = document.getElementById("graphicsCandidateCards");
  const candidates = (typeof GRAPHICS_CANDIDATES !== "undefined") ? GRAPHICS_CANDIDATES : [];
  const KIND_LABEL = { monster: "Monster-Kandidat", npc: "NPC-Kandidat", fragment: "Icon-/Fragment-Sammlung" };
  for (const c of candidates) {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${c.id}</h3>
      <span class="badge unknown-b">${KIND_LABEL[c.kind] || "unbestätigt"}</span>
      <div class="meta">
        Bank ${c.bank} &middot; Datei-Offset ${hex(c.fileOffset, 6)} &middot;
        ${c.tileCount} Kacheln
      </div>
      <canvas id="gc_${c.id}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated; max-width:100%;"></canvas>
      <div class="meta" style="margin-top:8px;">${c.note}</div>
    `;
    gcHost.appendChild(card);
  }
  redrawGraphicsCandidates();

  function redrawGraphicsCandidates() {
    for (const c of candidates) {
      const canvas = document.getElementById(`gc_${c.id}`);
      if (canvas) drawSpriteGrid(canvas, c.tileOffsets, c.cols, c.rows, 3, false);
    }
  }
}
