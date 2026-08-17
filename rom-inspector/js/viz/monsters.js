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
//
// Defined here (this module loads before npcs.js/graphics.js in
// index.html) and reused as a plain global by both -- js/viz/npcs.js's
// own NPC portraits and js/viz/graphics.js's own graphics-candidate
// cards all draw through this exact same function, so a palette
// switch (GBPalette, js/rombytes.js) or a GB-decode fix only needs to
// happen in one place.
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
  const bosses = MONSTERS.bosses || [];
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
      anderen 10 sind ehrlich als "Grafik unbekannt" markiert. Weitere,
      noch nicht einer Spezies zugeordnete Grafik-Funde stehen jetzt auf
      der eigenen <a href="#graphics">Grafiken</a>-Seite.
    </p>
    <div id="monsterRomBanner"></div>
    ${ks ? `
    <div class="card" style="max-width:260px;">
      <h3>Bekanntes Sprite (Spezies 4)</h3>
      <div class="meta">${ks.cols}&times;${ks.rows} Kacheln &middot; echtes Hardware-X-Flip = 2. Pose</div>
      <canvas id="monsterSpriteCanvas" width="10" height="10" style="margin-top:8px; image-rendering: pixelated;" role="img" aria-label="Echtes Monster-Sprite (Spezies 4), ${ks.cols}×${ks.rows} Kacheln, direkt aus der geladenen ROM gerendert"></canvas>
      <div class="toolbar" style="margin-top:8px;">
        <div class="pill-tabs" id="monsterPoseTabs">
          <div class="pill-tab active" data-flip="0">Pose A</div>
          ${ks.flipXTogglesPerStep ? '<div class="pill-tab" data-flip="1">Pose B (gespiegelt)</div>' : ""}
        </div>
      </div>
    </div>` : ""}
    ${bosses.length ? `
    <h2 class="page-title" style="font-size:1.3em; margin-top:28px;">Bosse (echte Story-Bosse)</h2>
    <p class="page-lede">
      21 echte, namentlich bekannte Bosse aus einer eigenen, separaten
      ROM-Tabelle (<code>EnemyStatTable</code>, Datei <code>0x10739</code>,
      24 Bytes/Zeile) &mdash; Namen aus der öffentlichen US-Disassembly
      ("Final Fantasy Adventure"), <strong>byte-genau</strong> gegen diese
      EU-ROM abgeglichen (speed/hpBase/xp/gold stimmen für alle 21
      exakt überein). <code>hpBase</code> ist kein fester Start-HP-Wert,
      sondern der Multiplikator in einer echten, live bestätigten
      Zufallsformel. <code>speciesByte</code>/<code>defeatBehaviorId</code>/
      <code>numObjects</code> sind echte Bytes, aber gegen diese EU-ROM
      noch nicht unabhängig bestätigt.
    </p>
    <div class="card-grid" id="bossCards" style="margin-top:16px;"></div>
    ` : ""}
    <h2 class="page-title" style="font-size:1.3em; margin-top:28px;">Reguläre Spezies</h2>
    <div class="card-grid" id="monsterCards" style="margin-top:16px;"></div>
  `;

  updateRomBanner(document.getElementById("monsterRomBanner"));
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("monsterRomBanner"));
    if (ks) drawSpriteGrid(document.getElementById("monsterSpriteCanvas"), ks.tileOffsets, ks.cols, ks.rows, 4, false);
    bossSpriteDraws.forEach(fn => fn());
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

  const bossHost = document.getElementById("bossCards");
  const bossSpriteDraws = [];
  if (bossHost) {
    for (const b of bosses) {
      const hasSprite = b.spriteTileOffsets && b.spriteTileOffsets.length;
      // 2026-08-17, direct instruction "die müssen nicht verified sein,
      // bau auch die grafiken in die website ein" -- show every boss's
      // own real sprite tiles regardless of arrangement-confirmation
      // status. Direct follow-up "versuche daraus die tatsächlichen
      // monster mit den animationsphasen zu rekonstruieren wie du es
      // bei spezies 4 gemacht hast": `spriteChunksReordered`/
      // `spriteChunksTotal` (see export_data.lua's own doc comment)
      // tell us how many of THIS boss's own real 16-tile animation-
      // phase chunks got a confident real arrangement -- render at
      // cols=4 (the real creature-pose width) whenever at least one
      // chunk was reconstructed, since even a partial reconstruction
      // is more readable at the real width than a generic 8-wide strip.
      const anyReordered = b.spriteChunksReordered > 0;
      const cols = hasSprite ? (anyReordered ? 4 : 8) : 4;
      const rows = hasSprite ? Math.ceil(b.spriteTileOffsets.length / cols) : 4;
      // 2026-08-17, same day, direct follow-up "wenn die posen
      // rekonstruiert sind dann bitte auch so einbauen wie bei spezies
      // 4": when EVERY real chunk is confidently reconstructed
      // (`spritePoses`, see export_data.lua's own doc comment), show
      // the SAME UI species 4's own card already uses -- one 4x4
      // canvas + switchable "Pose N" tabs -- instead of one tall
      // concatenated strip. Species 4 itself (Jackal, index 16) also
      // gets this treatment here now, for the same real reason its own
      // top card already has it: readability, one real pose at a time.
      const hasPoseTabs = !!b.spritePoses;
      let spriteBadge = "";
      if (hasSprite) {
        if (b.spriteArrangementConfirmed) {
          spriteBadge = `<span class="badge verified">Sprite-Anordnung bestätigt</span>`;
        } else if (b.spriteChunksReordered === b.spriteChunksTotal && b.spriteChunksTotal > 0) {
          spriteBadge = `<span class="badge partial" title="Jede echte 16-Kachel-Pose stimmt strukturell exakt mit dem einen live bestätigten Referenz-Monster (Jackal) überein -- real, aber nicht einzeln live geprüft.">Alle Posen rekonstruiert (${b.spriteChunksReordered}/${b.spriteChunksTotal})</span>`;
        } else if (b.spriteChunksReordered > 0) {
          spriteBadge = `<span class="badge partial" title="Nur ein Teil der echten 16-Kachel-Posen stimmt strukturell mit dem Referenz-Monster überein -- der Rest bleibt in roher Kopierreihenfolge.">Teilweise rekonstruiert (${b.spriteChunksReordered}/${b.spriteChunksTotal})</span>`;
        } else {
          spriteBadge = `<span class="badge unknown-b" title="Echte ROM-Pixel, aber keine der echten 16-Kachel-Posen stimmt strukturell mit dem Referenz-Monster überein -- rohe Kopierreihenfolge.">Anordnung unbekannt</span>`;
        }
      }
      const card = document.createElement("div");
      card.className = "card";
      card.innerHTML = `
        <h3>${b.name || ("Boss " + b.index)}</h3>
        <span class="badge verified">Stats byte-genau bestätigt</span>
        ${spriteBadge}
        <table class="data-table" style="margin-top:10px;">
          <tr><th>Speed</th><td class="num">${b.speed}</td></tr>
          <tr><th>hpBase</th><td class="num">${b.hpBase}</td><td class="desc">Formel-Eingabe, kein fester HP-Wert</td></tr>
          <tr><th>XP</th><td class="num">${b.xp}</td></tr>
          <tr><th>Gold</th><td class="num">${b.gold}</td></tr>
          <tr><th>speciesByte</th><td class="num">${b.speciesByte}</td><td class="desc">nicht eindeutig pro Boss</td></tr>
          <tr><th>defeatBehaviorId</th><td class="num">${hex(b.defeatBehaviorId, 4)}</td><td class="desc">unbestätigt</td></tr>
        </table>
        ${hasSprite ? `<canvas id="bossSprite${b.index}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated; max-width:100%;" role="img" aria-label="Echtes Sprite von ${escapeHtml(b.name || ("Boss " + b.index))}, Bank ${b.spriteBank}, ${b.spriteTileOffsets.length} Kacheln, direkt aus der geladenen ROM gerendert (${b.spriteChunksReordered}/${b.spriteChunksTotal} echte Posen rekonstruiert)"></canvas>` : ""}
        ${hasPoseTabs ? `
        <div class="toolbar" style="margin-top:8px;">
          <div class="pill-tabs" id="bossPoseTabs${b.index}">
            ${b.spritePoses.map((_, p) => `<div class="pill-tab ${p === 0 ? "active" : ""}" data-pose="${p}">Pose ${p + 1}</div>`).join("")}
          </div>
        </div>` : ""}
        <div class="meta" style="margin-top:8px;">
          raw: ${b.rawBytes.map(x => hex(x, 2)).join(" ")}
        </div>
      `;
      bossHost.appendChild(card);
      if (hasSprite) {
        const canvas = document.getElementById(`bossSprite${b.index}`);
        const state = { pose: 0 };
        const draw = () => {
          if (!canvas) return;
          if (hasPoseTabs) {
            drawSpriteGrid(canvas, b.spritePoses[state.pose], 4, 4, 4, false);
          } else {
            drawSpriteGrid(canvas, b.spriteTileOffsets, cols, rows, 3, false);
          }
        };
        bossSpriteDraws.push(draw);
        draw();
        if (hasPoseTabs) {
          document.querySelectorAll(`#bossPoseTabs${b.index} .pill-tab`).forEach(tab => {
            tab.addEventListener("click", () => {
              document.querySelectorAll(`#bossPoseTabs${b.index} .pill-tab`).forEach(t => t.classList.remove("active"));
              tab.classList.add("active");
              state.pose = parseInt(tab.dataset.pose, 10);
              draw();
            });
          });
        }
      }
    }
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
}
