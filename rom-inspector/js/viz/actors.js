function render_actors(main) {
  main.innerHTML = `
    <h1 class="page-title">Akteur-Tabelle</h1>
    <p class="page-lede">
      Eine echte, live-nachverfolgte ROM-Tabelle (Bank 3, CPU <code>$5f5a</code>, 24-Byte-
      Stride, <strong>${ACTORS.tableCount} Einträge</strong>, Indizes 0&ndash;${ACTORS.tableCount - 1})
      &mdash; gefunden 2026-08-16 beim Live-Tracing der beiden secondRoom-NPCs (Amanda,
      characterA). Der reale Mechanismus: eine Näherungsprüfung ruft den bereits bekannten
      Kampf-PRNG (<code>$2B1E</code>) auf, um einen Index in diese Tabelle zu berechnen; jeder
      Datensatz verweist über einen echten, eingebetteten Pointer (Bytes 8&ndash;9) auf einen
      ZWEITEN 24-Byte-Datensatz kleiner, Tile-ID-artiger Werte, bevor der bereits bekannte
      Entity-Allokator (<code>$0A74</code>) aufgerufen wird. Voller Herleitungsweg:
      <code>src/import/ActorDefinitionTable.lua</code>.
    </p>
    <p class="page-lede">
      <strong>Entscheidende Bestätigung:</strong> die beiden live erfassten Indizes
      (${ACTORS.liveConfirmed.map(l => l.index).join(", ")}) haben Sprite-Unter-Datensätze,
      die sich auf JEDEM abweichenden Byte um exakt <code>+0x20</code> unterscheiden &mdash;
      ein byte-exakter Treffer, über eine völlig unabhängige Methode (Live-OAM-Tile-ID-Capture),
      auf die bereits bestätigte Tatsache "characterB's Tile-IDs sind characterA's eigene
      <code>+0x20</code>" (siehe <a href="#npcs">NPCs</a>-Tab).
    </p>
    <p class="page-lede">
      <strong>Ehrlicher Umfang:</strong> das ist KEINE statische Pro-Raum-Platzierungstabelle
      &mdash; der Index wird zur LAUFZEIT berechnet (PRNG-beeinflusst), weshalb reine
      statische Suche nie eine "NPC-Platzierungstabelle" gefunden hat. Nur die
      <span class="badge verified">${ACTORS.liveConfirmed.length}</span> Einträge unten mit
      grünem Badge haben einen bestätigten Live-Spawn dahinter &mdash; der Rest ist reale,
      strukturierte ROM-Daten ohne bekannten In-Game-Auslöser.
      <span class="badge unknown-b">5</span> Einträge (Index 0 sowie ein Cluster bei 12&ndash;15)
      sind zusätzlich als "anomal" markiert: ihr eingebetteter Pointer zeigt in den festen
      Bank-0-Bereich statt in das übliche Bank-3-Fenster &mdash; vermutlich eine kleine
      reservierte Gruppe, nicht live bestätigt.
    </p>

    <h2>Live-bestätigte Einträge</h2>
    <div class="card-grid" id="actorLiveHost"></div>

    <h2 style="margin-top:24px;">Alle ${ACTORS.tableCount} Einträge</h2>
    <div class="toolbar" id="actorFilterToolbar"></div>
    <table class="data-table">
      <thead>
        <tr>
          <th>Index</th>
          <th>Status</th>
          <th>allocParam</th>
          <th>spritePointer</th>
          <th>ROM-Offset</th>
          <th>Sub-Record ROM-Offset</th>
        </tr>
      </thead>
      <tbody id="actorHost"></tbody>
    </table>
  `;

  const liveHost = document.getElementById("actorLiveHost");
  ACTORS.liveConfirmed.forEach(l => {
    const record = ACTORS.records.find(r => r.index === l.index);
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>Index ${l.index}</h3>
      <span class="badge verified">Live-Spawn bestätigt</span>
      <div class="desc" style="margin-top:8px;">${escapeHtml(l.plausibleCharacter)}</div>
      <div class="meta" style="margin-top:6px;">
        allocParam ${record ? record.allocParam : "?"} &middot;
        spritePointer <code>${record ? hex(record.spritePointer, 4) : "?"}</code>
      </div>
      <div class="meta" style="word-break:break-all;">
        raw: <code>${record ? escapeHtml(record.rawHex) : "?"}</code>
      </div>
      ${record && record.spriteSubRecord ? `<div class="meta" style="word-break:break-all;">
        sub-record: <code>${escapeHtml(record.spriteSubRecord.rawHex)}</code>
      </div>` : ""}
    `;
    liveHost.appendChild(card);
  });

  const FILTERS = {
    all: () => true,
    live: r => ACTORS.liveConfirmed.some(l => l.index === r.index),
    anomalous: r => r.anomalous,
  };
  const FILTER_LABELS = { all: "Alle", live: "Live-bestätigt", anomalous: "Anomal" };
  const toolbar = document.getElementById("actorFilterToolbar");
  const tbody = document.getElementById("actorHost");
  const state = { filter: "all" };

  function renderPills() {
    toolbar.innerHTML = `
      <div class="pill-tabs" id="actorFilterPills">
        ${Object.keys(FILTERS).map(f => `
          <div class="pill-tab ${state.filter === f ? "active" : ""}" data-filter="${f}">
            ${FILTER_LABELS[f]} (${ACTORS.records.filter(FILTERS[f]).length})
          </div>
        `).join("")}
      </div>
    `;
    document.getElementById("actorFilterPills").querySelectorAll(".pill-tab").forEach(el => {
      el.addEventListener("click", () => {
        state.filter = el.dataset.filter;
        renderPills();
        renderTable();
      });
    });
  }

  function renderTable() {
    const rows = ACTORS.records.filter(FILTERS[state.filter]);
    tbody.innerHTML = "";
    rows.forEach(r => {
      const isLive = ACTORS.liveConfirmed.some(l => l.index === r.index);
      const row = document.createElement("tr");
      row.innerHTML = `
        <td class="num">${r.index}</td>
        <td>${isLive
          ? `<span class="badge verified">Live-bestätigt</span>`
          : r.anomalous
            ? `<span class="badge unknown-b">Anomal</span>`
            : `<span class="badge undecoded">Trigger unbekannt</span>`}</td>
        <td class="num">${r.allocParam}</td>
        <td><code>${hex(r.spritePointer, 4)}</code></td>
        <td><code>${hex(r.fileOffset, 6)}</code></td>
        <td>${r.spriteSubRecord ? `<code>${hex(r.spriteSubRecord.fileOffset, 6)}</code>` : "&mdash;"}</td>
      `;
      tbody.appendChild(row);
    });
  }

  renderPills();
  renderTable();
}
