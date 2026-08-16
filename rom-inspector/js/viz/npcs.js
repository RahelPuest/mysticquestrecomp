const NPC_DIRECTIONS = ["down", "up", "left", "right"];

function render_npcs(main) {
  main.innerHTML = `
    <h1 class="page-title">NPCs</h1>
    <p class="page-lede">
      Anders als Monster/Items gibt es in dieser ROM KEINE statische Platzierungs-Tabelle
      für NPCs &mdash; eine frühere, eigenständige Untersuchung hat das bereits live und
      erschöpfend festgestellt. Jeder Eintrag unten wurde einzeln per Live-OAM-Tracing +
      Raum-für-Raum-Dialogtest gefunden. "Vollständig" heißt hier "alle bisher gefundenen",
      nicht "alle, die im Spiel existieren" &mdash; weitere NPCs zu finden würde bedeuten,
      weitere Räume live zu erkunden (siehe roadmap.md, "World scope / content pipeline"),
      nicht eine Tabelle mechanisch weiterzulesen.
    </p>
    <div id="npcRomBanner"></div>
    <div class="card-grid" id="npcCards"></div>
  `;

  updateRomBanner(document.getElementById("npcRomBanner"));
  const redraws = [];
  onSectionUnload(RomBytes.onChange(() => {
    updateRomBanner(document.getElementById("npcRomBanner"));
    redraws.forEach(fn => fn());
  }));

  const host = document.getElementById("npcCards");
  NPCS.forEach((n, idx) => {
    const card = document.createElement("div");
    card.className = "card";
    const hasAnim = n.animation && NPC_DIRECTIONS.some(d => n.animation[d]);
    card.innerHTML = `
      <h3>${escapeHtml(n.name)}</h3>
      <span class="badge verified">${escapeHtml(n.room)}</span>
      <div class="meta">
        screen (${n.screenX}, ${n.screenY})
        ${n.palette ? " &middot; Palette " + escapeHtml(n.palette) : ""}
      </div>
      <canvas id="npcCanvas${idx}" width="10" height="10" style="margin-top:8px; image-rendering: pixelated;" role="img" aria-label="Echtes NPC-Sprite von ${escapeHtml(n.name)}, direkt aus der geladenen ROM gerendert"></canvas>
      ${hasAnim ? `
      <div class="toolbar" style="margin-top:8px;">
        <div class="pill-tabs" id="npcDirTabs${idx}">
          ${NPC_DIRECTIONS.filter(d => n.animation[d]).map((d, i) =>
            `<div class="pill-tab ${i === 0 ? "active" : ""}" data-dir="${d}">${d}</div>`).join("")}
        </div>
        <div class="pill-tabs" id="npcPhaseTabs${idx}">
          <div class="pill-tab active" data-phase="0">Phase 1</div>
          <div class="pill-tab" data-phase="1">Phase 2</div>
        </div>
      </div>
      <div class="meta" style="margin-top:4px;">${n.framesPerPhase ? n.framesPerPhase + " reale Frames/Phase" : ""}</div>
      ` : `<div class="desc" style="margin-top:8px;">Keine echten Animationsphasen bekannt (nur diese Ruhepose).</div>`}
      ${n.dialogue ? `<div class="desc" style="margin-top:8px; white-space:pre-line;">${n.dialogue.map(escapeHtml).join("\n---\n")}</div>` : ""}
    `;
    host.appendChild(card);

    const canvas = card.querySelector(`#npcCanvas${idx}`);
    const state = { dir: NPC_DIRECTIONS.find(d => n.animation && n.animation[d]) || null, phase: 0 };

    function currentTileOffsets() {
      if (state.dir && n.animation && n.animation[state.dir] && n.animation[state.dir][state.phase]) {
        const f = n.animation[state.dir][state.phase];
        // CORRECTED (2026-08-15, direct user report "die npc sprites a
        // und b jeweils 16x16 gross sind"): each pose is a real 4-tile
        // row-major 2x2 block (`f.tileOffsets`), not a 2-tile top/
        // bottom column -- see rom_profiles.lua's own doc comment for
        // the live OAM re-trace that found this. Real per-axis OAM
        // flip bits still apply on top of the whole assembled 16x16
        // image (down/up's phase-2 frame reuses phase-1's tiles with a
        // real `flipY`, NOT `flipX`) -- both must be read, not just one.
        return { offsets: f.tileOffsets, cols: 2, rows: 2, flip: { x: !!f.flip, y: !!f.flipY } };
      }
      if (n.tileOffsets) {
        // Willy's own static 2x2 pose, or a fallback when no animation
        // frame is selected -- always a real 4-tile 2x2 block now (see
        // rom_profiles.lua's own 2026-08-15 shape fix for secondRoom's
        // own NPCs; Willy's own tileOffsets was always this shape).
        return { offsets: n.tileOffsets, cols: 2, rows: 2, flip: { x: false, y: false } };
      }
      return null;
    }

    function redraw() {
      const data = currentTileOffsets();
      if (!data) return;
      drawSpriteGrid(canvas, data.offsets, data.cols, data.rows, 4, data.flip);
    }
    redraws.push(redraw);
    redraw();

    const dirTabs = card.querySelector(`#npcDirTabs${idx}`);
    if (dirTabs) {
      dirTabs.querySelectorAll(".pill-tab").forEach(tab => {
        tab.addEventListener("click", () => {
          dirTabs.querySelectorAll(".pill-tab").forEach(t => t.classList.remove("active"));
          tab.classList.add("active");
          state.dir = tab.dataset.dir;
          redraw();
        });
      });
    }
    const phaseTabs = card.querySelector(`#npcPhaseTabs${idx}`);
    if (phaseTabs) {
      phaseTabs.querySelectorAll(".pill-tab").forEach(tab => {
        tab.addEventListener("click", () => {
          phaseTabs.querySelectorAll(".pill-tab").forEach(t => t.classList.remove("active"));
          tab.classList.add("active");
          state.phase = parseInt(tab.dataset.phase, 10);
          redraw();
        });
      });
    }
  });
}
