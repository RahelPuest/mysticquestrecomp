// Dedicated "Grafiken" section for every GRAPHICS_CANDIDATES entry
// (js/data/graphics-candidates.js, generated from src/import/
// GraphicsCandidates.lua) -- real, visually-confirmed ROM art that is
// NOT tied to any confirmed species/room/NPC identity yet, honestly
// kept apart from the confirmed catalogs (Monster/NPCs pages) that
// only show identity-confirmed content.
//
// MOVED HERE (2026-08-16, direct user request: "pack diese grafik
// funde bitte in einen eignen tab" -- put these graphics finds into
// their own tab) -- previously embedded as a second section at the
// bottom of the Monster page, which mixed confirmed species data with
// unconfirmed candidate art in one place. Filterable by `kind`
// (monster/npc/fragment/tileset) via the same pill-tab pattern
// js/viz/opcodes.js and others already use.
//
// Rendering reuses `drawSpriteGrid` (defined in js/viz/monsters.js,
// which loads before this module) and `updateRomBanner` (js/viz/
// tiles.js) -- the exact same real-pixel canvas renderer every other
// tile-art section on this site already uses, so a palette switch
// (GBPalette, js/rombytes.js) or a GB-decode fix applies here too with
// zero extra wiring.

const GRAPHICS_KIND_LABEL = {
  monster: "Monster-Kandidat",
  npc: "NPC-Kandidat",
  fragment: "Icon-/Fragment-Sammlung",
  tileset: "Map-/Umgebungs-Kachelset",
};
const GRAPHICS_KIND_ORDER = ["monster", "npc", "tileset", "fragment"];

function render_graphics(main) {
  const candidates = (typeof GRAPHICS_CANDIDATES !== "undefined") ? GRAPHICS_CANDIDATES : [];
  const totalTiles = candidates.reduce((sum, c) => sum + c.tileCount, 0);
  const counts = {};
  for (const c of candidates) counts[c.kind] = (counts[c.kind] || 0) + 1;

  const mapCatalog = (typeof MAP_TILE_CATALOG !== "undefined") ? MAP_TILE_CATALOG : { entries: [], byBank: {}, roomCount: 0 };
  const mapBanks = Object.keys(mapCatalog.byBank).map(Number).sort((a, b) => a - b);

  const spriteCatalog = (typeof SPRITE_CATALOG !== "undefined") ? SPRITE_CATALOG : { npcs: [], monsters: [] };
  const spriteNpcs = spriteCatalog.npcs;
  const spriteMonsters = spriteCatalog.monsters;
  const spriteConfirmedCount = spriteNpcs.filter(e => e.arrangementConfirmed).length
    + spriteMonsters.filter(e => e.arrangementConfirmed).length;
  const spriteFamilyCount = spriteNpcs.filter(e => e.arrangementFamily === "humanoid4pose").length;
  const spriteFamilyDistinct = new Set(
    spriteNpcs.filter(e => e.arrangementFamily === "humanoid4pose").map(e => e.kindByte)
  ).size;

  main.innerHTML = `
    <h1 class="page-title">Grafiken</h1>
    <p class="page-lede">
      Zwei ehrlich getrennte Sammlungen echter ROM-Grafik: unten
      <strong>bereits bestätigte</strong> Map-Kacheln (aus vollständig
      kartierten, live-verifizierten Räumen) und oben
      <strong>unbestätigte Kandidaten</strong> (Kreaturen, NPC-Portraits,
      Icon-Sammlungen, weitere Map-Kacheln) &mdash; gefunden durch ein
      vollständiges Rendern JEDER ROM-Bank (0&ndash;15) und manuelle
      Durchsicht, nicht nur einzelne Treffer eines heuristischen Scans.
      KEIN Kandidat ist einer bestätigten Spezies, einem Raum, NPC oder
      einem echten Spawn-/Verwendungs-Nachweis zugeordnet &mdash; das sind
      echte ROM-Pixel (direkt aus deiner geladenen ROM gerendert), aber
      die Identität/Verwendung ist ehrlich unbestätigt.
    </p>
    <div id="graphicsRomBanner"></div>

    <h2 class="section-title">Bekannte, bereits kartierte Map-Kacheln</h2>
    <p class="page-lede">
      Jede echte Kachel, die dieses Projekt bereits über einen vollständig
      dekodierten, VERIFIED Raum bestätigt hat &mdash; dedupliziert über alle
      ${mapCatalog.roomCount} kartierten Räume hinweg
      (<a href="#tiles">Tile-Viewer</a> zeigt dieselben Daten pro Raum
      einzeln an). Verteilt auf ${mapBanks.length} echte Banks, NICHT nur
      Bank 12, wie eine ältere Notiz in <code>rom_profiles.lua</code>
      nahelegte. Jede Kachel unten stammt aus mindestens einem echten,
      live-verifizierten Raum &mdash; kein Kandidat, kein Scan-Treffer.
    </p>
    <div class="stat-grid">
      <div class="stat-card"><div class="value">${mapCatalog.entries.length}</div><div class="label">bestätigte Map-Kacheln (~${Math.round(mapCatalog.entries.length * 16 / 1024)} KB)</div></div>
      <div class="stat-card"><div class="value">${mapCatalog.roomCount}</div><div class="label">vollständig kartierte Räume</div></div>
      ${mapBanks.map(b => `<div class="stat-card"><div class="value">${mapCatalog.byBank[b]}</div><div class="label">Kacheln in Bank ${b}</div></div>`).join("")}
    </div>
    <div class="card-grid" id="mapTileBankCards" style="margin-top:16px;"></div>
    <div class="tile-info-strip" id="mapTileHoverInfo">Kachel anklicken für Details (welche Räume sie nutzen).</div>

    <h2 class="section-title" style="margin-top:36px;">Grafik-Kandidaten (unbestätigt)</h2>
    <div class="stat-grid">
      <div class="stat-card"><div class="value">${candidates.length}</div><div class="label">Grafik-Kandidaten gesamt</div></div>
      <div class="stat-card"><div class="value">${totalTiles}</div><div class="label">Kacheln gesamt (~${Math.round(totalTiles * 16 / 1024)} KB)</div></div>
      <div class="stat-card"><div class="value">${counts.monster || 0}</div><div class="label">Monster-Kandidaten</div></div>
      <div class="stat-card"><div class="value">${counts.npc || 0}</div><div class="label">NPC-Kandidaten</div></div>
      <div class="stat-card"><div class="value">${counts.tileset || 0}</div><div class="label">Map-/Kachelset-Kandidaten</div></div>
    </div>

    <div class="toolbar" style="margin-top:18px;">
      <div class="pill-tabs" id="graphicsKindTabs">
        <div class="pill-tab active" data-kind="all">Alle (${candidates.length})</div>
        ${GRAPHICS_KIND_ORDER.filter(k => counts[k]).map(k =>
          `<div class="pill-tab" data-kind="${k}">${GRAPHICS_KIND_LABEL[k]} (${counts[k]})</div>`
        ).join("")}
      </div>
    </div>

    <div class="card-grid" id="graphicsCandidateCards" style="margin-top:16px;"></div>

    <h2 class="section-title" style="margin-top:36px;">Sprite-Katalog: NPC/Monster/Boss-Pixelquelle (2026-08-17)</h2>
    <p class="page-lede">
      Die reale ROM-&gt;VRAM-Sprite-Kachel-PIXELQUELLE für jeden NPC
      (<code>ActorDefinitionTable</code>, ${spriteNpcs.length} Einträge)
      und jedes Monster/jeden Boss (<code>MonsterDefinitionTable</code>,
      ${spriteMonsters.length} Einträge) &mdash; über denselben Hebel wie
      die Kachel-Pipeline gefunden: eine reale, disassemblierte
      ROM-&gt;VRAM-DMA-Formel, live an 3 unabhängigen, bereits bekannten
      echten Sprites exakt bestätigt (siehe <code>SpriteTileFormula.lua</code>
      für die volle Herleitung). Direkter Nutzer-Auftrag "du sollst mehr
      npcs suchen" führte zu einem zweiten Fund: ${spriteFamilyCount}
      weitere NPC-Einträge (${spriteFamilyDistinct} davon mit
      unterschiedlichem <code>kindByte</code>, also wirklich
      unterschiedliche NPC-Designs) teilen exakt dieselbe reale
      Kopierreihenfolge wie characterA/characterB &mdash; ihre Kacheln
      werden automatisch in die echte, logische Pose-Reihenfolge
      umsortiert (nicht mehr die rohe DMA-Reihenfolge).
      <strong>Ehrlicher Umfang, 3 Vertrauensstufen:</strong> die
      gezeigten Kacheln sind für JEDEN Eintrag echte, einzeln korrekte
      ROM-Pixel. Die Bildschirm-ANORDNUNG ist für
      ${spriteConfirmedCount} Einträge mit
      <span class="badge verified">Anordnung bestätigt</span> individuell
      live verifiziert; für ${spriteFamilyCount} Einträge mit
      <span class="badge partial">Anordnung wahrscheinlich (Familie)</span>
      per Familien-Zugehörigkeit übernommen (echt, aber nicht einzeln
      live geprüft); alle anderen zeigen
      <span class="badge unknown-b">Anordnung unbekannt</span> in roher
      ROM-Kopierreihenfolge, kein geratenes Raster.
    </p>
    <div class="stat-grid">
      <div class="stat-card"><div class="value">${spriteNpcs.length}</div><div class="label">NPC-Einträge</div></div>
      <div class="stat-card"><div class="value">${spriteMonsters.length}</div><div class="label">Monster/Boss-Einträge</div></div>
      <div class="stat-card"><div class="value">${spriteConfirmedCount}</div><div class="label">Anordnung individuell bestätigt</div></div>
      <div class="stat-card"><div class="value">${spriteFamilyCount} (${spriteFamilyDistinct} Designs)</div><div class="label">Anordnung wahrscheinlich (Familie)</div></div>
    </div>
    <div class="toolbar" style="margin-top:18px;">
      <div class="pill-tabs" id="spriteCatalogTabs">
        <div class="pill-tab active" data-kind="npcs">NPCs (${spriteNpcs.length})</div>
        <div class="pill-tab" data-kind="monsters">Monster/Bosse (${spriteMonsters.length})</div>
      </div>
    </div>
    <div class="card-grid" id="spriteCatalogCards" style="margin-top:16px;"></div>
  `;

  updateRomBanner(document.getElementById("graphicsRomBanner"));
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("graphicsRomBanner"));
    redrawGraphicsCandidates();
    redrawMapTileBanks();
    redrawSpriteCatalog();
  }));

  // --- known/confirmed map tiles, one mosaic canvas per real bank ---
  const bankTileLists = {}; // bank -> sorted offset array (for click lookup)
  const bankHost = document.getElementById("mapTileBankCards");
  for (const b of mapBanks) {
    const offsets = mapCatalog.entries.filter(e => e.bank === b).map(e => e.fileOffset).sort((a, b2) => a - b2);
    bankTileLists[b] = offsets;
    const cols = 16;
    const rows = Math.ceil(offsets.length / cols);
    const card = document.createElement("div");
    card.className = "card";
    card.style.maxWidth = "none";
    card.innerHTML = `
      <h3>Bank ${b}</h3>
      <span class="badge verified">${offsets.length} bestätigte Kacheln</span>
      <div class="meta">${cols}&times;${rows} Raster</div>
      <canvas id="mtc_bank${b}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated; max-width:100%; cursor:pointer;" role="img" aria-label="Mosaik aller ${offsets.length} bestätigten Map-Kacheln in Bank ${b}, direkt aus der geladenen ROM gerendert. Einzelne Kacheln per Mausklick inspizierbar (welche Räume sie nutzen); diese Detailansicht ist derzeit nur per Maus erreichbar."></canvas>
    `;
    bankHost.appendChild(card);
  }

  function redrawMapTileBanks() {
    for (const b of mapBanks) {
      const canvas = document.getElementById(`mtc_bank${b}`);
      if (!canvas) continue;
      const offsets = bankTileLists[b];
      drawSpriteGrid(canvas, offsets, 16, Math.ceil(offsets.length / 16), 3, false);
      canvas.onclick = (ev) => {
        const rect = canvas.getBoundingClientRect();
        // Multiplies back by canvas.width/rect.width to account for any CSS
        // max-width downscale (the canvas can render wider than its own CSS
        // box on narrow viewports) before dividing into 8x8@3x tile cells.
        const cx = Math.floor((ev.clientX - rect.left) * (canvas.width / rect.width) / (8 * 3));
        const cy = Math.floor((ev.clientY - rect.top) * (canvas.height / rect.height) / (8 * 3));
        const idx = cy * 16 + cx;
        const off = offsets[idx];
        const info = document.getElementById("mapTileHoverInfo");
        if (off === undefined || !info) return;
        const entry = mapCatalog.entries.find(e => e.fileOffset === off);
        info.innerHTML = `Bank ${b}, Datei-Offset ${hex(off, 6)} &middot; verwendet von: ${entry ? entry.rooms.join(", ") : "?"}`;
      };
    }
  }

  const host = document.getElementById("graphicsCandidateCards");
  let activeKind = "all";

  function renderCards() {
    host.innerHTML = "";
    for (const c of candidates) {
      if (activeKind !== "all" && c.kind !== activeKind) continue;
      const card = document.createElement("div");
      card.className = "card";
      card.innerHTML = `
        <h3>${c.id}</h3>
        <span class="badge unknown-b">${GRAPHICS_KIND_LABEL[c.kind] || "unbestätigt"}</span>
        <div class="meta">
          Bank ${c.bank} &middot; Datei-Offset ${hex(c.fileOffset, 6)} &middot;
          ${c.tileCount} Kacheln
        </div>
        <canvas id="gc_${c.id}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated; max-width:100%;" role="img" aria-label="Grafik-Kandidat ${c.id}: ${c.tileCount} Kacheln aus Bank ${c.bank}, direkt aus der geladenen ROM gerendert"></canvas>
        <div class="meta" style="margin-top:8px;">${c.note}</div>
      `;
      host.appendChild(card);
    }
    redrawGraphicsCandidates();
  }

  function redrawGraphicsCandidates() {
    for (const c of candidates) {
      const canvas = document.getElementById(`gc_${c.id}`);
      if (canvas) drawSpriteGrid(canvas, c.tileOffsets, c.cols, c.rows, 3, false);
    }
  }

  document.querySelectorAll("#graphicsKindTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#graphicsKindTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      activeKind = tab.dataset.kind;
      renderCards();
    });
  });

  // --- sprite catalog (NPCs / monsters+bosses, 2026-08-17) ---
  const spriteHost = document.getElementById("spriteCatalogCards");
  let activeSpriteKind = "npcs";

  function spriteCols(entry) {
    // The 3 individually-confirmed entries AND the 172 humanoid4pose
    // family members (2026-08-17, "du sollst mehr npcs suchen") use
    // their own real, known shape (4 wide, tileOffsets already
    // reordered into real logical pose order by resolveSpriteTileOffsets
    // -- see that function's own doc comment). Every other entry has an
    // honestly unknown arrangement, so a neutral 8-wide strip is used
    // purely for compact display -- NOT a claimed layout (see this
    // section's own page-lede text).
    return (entry.arrangementConfirmed || entry.arrangementFamily === "humanoid4pose") ? 4 : 8;
  }

  function renderSpriteCards() {
    spriteHost.innerHTML = "";
    const list = activeSpriteKind === "npcs" ? spriteNpcs : spriteMonsters;
    const label = activeSpriteKind === "npcs" ? "NPC" : "Monster/Boss";
    for (const entry of list) {
      const cols = spriteCols(entry);
      const rows = Math.ceil(entry.tileOffsets.length / cols);
      const card = document.createElement("div");
      card.className = "card";
      let badge, ariaLayout;
      if (entry.arrangementConfirmed) {
        badge = `<span class="badge verified">Anordnung bestätigt</span>`;
        ariaLayout = "Bildschirm-Anordnung individuell live bestätigt";
      } else if (entry.arrangementFamily === "humanoid4pose") {
        badge = `<span class="badge partial" title="Teilt characterA/characterBs eigene, live bestätigte Kopierreihenfolge -- dieselbe Vertrauensstufe wie andere Familien-Funde dieses Projekts, keine individuelle Live-Verifikation.">Anordnung wahrscheinlich (Familie)</span>`;
        ariaLayout = "Bildschirm-Anordnung wahrscheinlich, per Familien-Zugehörigkeit zu characterA/characterB übernommen";
      } else {
        badge = `<span class="badge unknown-b">Anordnung unbekannt</span>`;
        ariaLayout = "Bildschirm-Anordnung unbekannt";
      }
      card.innerHTML = `
        <h3>${label} #${entry.index}</h3>
        ${badge}
        <div class="meta">
          Bank ${entry.bank} &middot; ${entry.tileOffsets.length} Kacheln &middot;
          kindByte=0x${entry.kindByte.toString(16).padStart(2, "0")}, C=0x${entry.cByte.toString(16).padStart(2, "0")}
        </div>
        <canvas id="sc_${activeSpriteKind}_${entry.index}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated; max-width:100%;" role="img" aria-label="${label} #${entry.index}: ${entry.tileOffsets.length} echte Sprite-Kacheln, direkt aus der geladenen ROM gerendert (${ariaLayout})"></canvas>
      `;
      spriteHost.appendChild(card);
    }
    redrawSpriteCatalog();
  }

  function redrawSpriteCatalog() {
    const list = activeSpriteKind === "npcs" ? spriteNpcs : spriteMonsters;
    for (const entry of list) {
      const canvas = document.getElementById(`sc_${activeSpriteKind}_${entry.index}`);
      if (canvas) drawSpriteGrid(canvas, entry.tileOffsets, spriteCols(entry), Math.ceil(entry.tileOffsets.length / spriteCols(entry)), 3, false);
    }
  }

  document.querySelectorAll("#spriteCatalogTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#spriteCatalogTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      activeSpriteKind = tab.dataset.kind;
      renderSpriteCards();
    });
  });

  redrawMapTileBanks();
  renderCards();
  renderSpriteCards();
}
