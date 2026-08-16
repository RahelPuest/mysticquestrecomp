function render_transitions(main) {
  main.innerHTML = `
    <h1 class="page-title">Raum-Übergänge</h1>
    <p class="page-lede">
      Eine echte, generelle ROM-Struktur (Bank 14, ${TRANSITIONS.rawRecordCount} rohe
      Datensätze &rarr; ${TRANSITIONS.distinct.length} tatsächlich distinkte reale Übergänge),
      die sowohl den Ziel-<code>roomSelector</code> als auch die reale Landeposition für jeden
      "Wipe-Style"-Raumübergang kodiert &mdash; gefunden 2026-08-16 über einen echten
      Hardware-Watchpoint auf WRAM <code>$C244</code>/<code>$C245</code> (der reale Schreibzugriff
      ist INDIREKT, <code>LD (HL),D</code>/<code>LD (HL),E</code>, genau die blinde Stelle, die
      6+ frühere rein-statische Durchgänge nie abdecken konnten), dann generalisiert per
      statischer Byte-Muster-Suche. Voller Herleitungsweg:
      <code>docs/reverse-engineering/rom-map.md</code>, Abschnitt "Consolidated reference" (4).
    </p>
    <p class="page-lede">
      <strong>Ehrlicher Umfang:</strong> nur <span class="badge verified">2</span> der
      ${TRANSITIONS.distinct.length} distinkten Übergänge sind aktuell live-verifiziert UND
      tatsächlich im Spiel verdrahtet (siehe unten). Der Rest sind reale, ROM-dekodierte Daten,
      deren echter In-Game-Auslöser (welcher Story-/Dialog-Moment ihn tatsächlich abruft) ehrlich
      noch unbekannt ist &mdash; eine zeitlich begrenzte Live-Suche über jede Wand jedes aktuell
      erreichbaren Raums fand nichts Neues. Besonders bemerkenswert:
      <span class="badge partial">unknownRoomA</span>-Einträge (roomSelector 8&ndash;13) sind
      der erste reale ROM-Beleg, dass diese seit Langem mysteriöse Raumfamilie (nie in einer
      früheren Session live erreicht) echter beabsichtigter Content ist, kein toter Datenmüll.
    </p>

    <h2>Live-verifizierte, im Spiel verdrahtete Übergänge</h2>
    <div class="card-grid" id="knownLiveHost"></div>

    <h2 style="margin-top:24px;">Alle ${TRANSITIONS.distinct.length} distinkten Übergänge</h2>
    <div class="toolbar" id="familyToolbar"></div>
    <table class="data-table">
      <thead>
        <tr>
          <th>roomSelector</th>
          <th>Ziel-Familie</th>
          <th>Landeposition (Tile)</th>
          <th>Landeposition (Pixel)</th>
          <th>Vorkommen im Skript-Korpus</th>
          <th>Beispiel-ROM-Offset</th>
        </tr>
      </thead>
      <tbody id="transitionsHost"></tbody>
    </table>

    <h2 style="margin-top:24px;">Verwandter, noch unentschlüsselter Record-Typ</h2>
    <p class="page-lede">
      Ein zweiter, strukturell ähnlicher Record (<code>00 08 C5 idx F4 a b 09 0C EC 00 0B</code>,
      ${TRANSITIONS.selectorRecords.length} echte Treffer, ebenfalls exklusiv in Bank 14) wurde
      ursprünglich als der reale Connectivity-Schlüssel vermutet &mdash; das stellte sich als
      Zufall heraus (die echte Antwort liegt direkt im <code>roomSelector</code>-Feld der
      Übergangs-Tabelle oben). Die eigene reale Bedeutung dieses Record-Typs bleibt offen, hier
      als echter, verifizierter struktureller Fund dokumentiert statt gelöscht.
    </p>
  `;

  const knownHost = document.getElementById("knownLiveHost");
  TRANSITIONS.knownLive.forEach(k => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>roomSelector ${k.roomSelector}</h3>
      <span class="badge verified">Pixel (${k.pixelX}, ${k.pixelY})</span>
      <div class="desc" style="margin-top:8px;">${escapeHtml(k.label)}</div>
    `;
    knownHost.appendChild(card);
  });

  const FAMILY_BADGE = {
    "startRoom/fourthRoom": "partial",
    "willyRoom/secondRoom/thirdRoom/fifthRoom": "partial",
    "unknownRoomA": "unknown-b",
    "unknownRoomB (schwarzer Wipe-Hintergrund)": "default",
    "pre-transition placeholder (kein echter Raum)": "default",
    "unbekannt (kein bereits bekannter Raum)": "undecoded",
  };
  function badgeFor(family) {
    return FAMILY_BADGE[family] || "unknown-b";
  }

  const families = Array.from(new Set(TRANSITIONS.distinct.map(d => d.targetFamily)));
  const toolbar = document.getElementById("familyToolbar");
  const tbody = document.getElementById("transitionsHost");
  const state = { family: "all" };

  function renderPills() {
    toolbar.innerHTML = `
      <div class="pill-tabs" id="familyPills">
        <div class="pill-tab ${state.family === "all" ? "active" : ""}" data-family="all">
          Alle (${TRANSITIONS.distinct.length})
        </div>
        ${families.map(f => `
          <div class="pill-tab ${state.family === f ? "active" : ""}" data-family="${escapeHtml(f)}">
            ${escapeHtml(f)} (${TRANSITIONS.distinct.filter(d => d.targetFamily === f).length})
          </div>
        `).join("")}
      </div>
    `;
    document.getElementById("familyPills").querySelectorAll(".pill-tab").forEach(el => {
      el.addEventListener("click", () => {
        state.family = el.dataset.family;
        renderPills();
        renderTable();
      });
    });
  }

  function renderTable() {
    const rows = state.family === "all"
      ? TRANSITIONS.distinct
      : TRANSITIONS.distinct.filter(d => d.targetFamily === state.family);
    tbody.innerHTML = "";
    rows.forEach(d => {
      const row = document.createElement("tr");
      row.innerHTML = `
        <td class="num">${d.roomSelector}</td>
        <td><span class="badge ${badgeFor(d.targetFamily)}">${escapeHtml(d.targetFamily)}</span></td>
        <td class="num">(${d.tileCol}, ${d.tileRow})</td>
        <td class="num">(${d.pixelX}, ${d.pixelY})</td>
        <td class="num">${d.occurrences}</td>
        <td><code>${hex(d.exampleFileOffset, 6)}</code></td>
      `;
      tbody.appendChild(row);
    });
  }

  renderPills();
  renderTable();
}
