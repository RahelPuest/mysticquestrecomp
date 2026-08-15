function render_story(main) {
  main.innerHTML = `
    <h1 class="page-title">Story &amp; Charaktere</h1>
    <p class="page-lede">
      Ein echter ROM-weiter Text-Fund (2026-08-15, direkte Anfrage "suchen alle monster und
      npcs mit allen daten, texten und grafiken aus dem rom"): reale
      "&lt;Monster&gt; bezwungen/besiegt"-Siegesmeldungen und benannte Story-Figuren, gefunden
      per gezieltem <code>tools/rom/dump_strings.py</code>-Scan (dieselbe Methode, die bereits
      Amandas echten secondRoom-Dialog gefunden hat) &mdash; kein Live-Capture nötig, reine
      ROM-Byte-Dekodierung. <strong>Ehrlicher Umfang:</strong> nur Willy und Amanda haben eine
      bekannte echte Position/Sprite; jeder andere Name wurde ausschließlich im Dialogtext
      gefunden, ohne je eine Live-Position zu haben &mdash; explizit so markiert, nicht
      verschwiegen. Die Monster-Namen haben KEINE bestätigte Verknüpfung zu den 11 nummerierten
      Spezies in <code>enemySpeciesTable</code> (siehe Monster-Tab) &mdash; eigenständig
      gezeigt, nicht erzwungen zugeordnet.
    </p>

    <h2>Monster-Siegesmeldungen</h2>
    <div class="card-grid" id="bossDefeatsHost"></div>

    <h2 style="margin-top:24px;">Benannte Story-Figuren</h2>
    <table class="data-table">
      <thead><tr><th>Name</th><th>Vorkommen</th><th>Position bekannt?</th><th>Rolle (aus echtem Dialog)</th></tr></thead>
      <tbody id="namedCharactersHost"></tbody>
    </table>
  `;

  const bossHost = document.getElementById("bossDefeatsHost");
  STORY.bossDefeats.forEach(b => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${escapeHtml(b.name)}</h3>
      <span class="badge verified">bank ${b.bank}, ${hex(b.fileOffset, 6)}</span>
      <div class="desc" style="margin-top:8px; white-space:pre-line;">${escapeHtml(b.message)}</div>
    `;
    bossHost.appendChild(card);
  });

  const namedHost = document.getElementById("namedCharactersHost");
  STORY.namedCharacters
    .slice()
    .sort((a, c) => c.occurrences - a.occurrences)
    .forEach(p => {
      const row = document.createElement("tr");
      row.innerHTML = `
        <td>${escapeHtml(p.name)}</td>
        <td class="num">${p.occurrences}</td>
        <td>${p.positionKnown
          ? `<span class="badge verified">${escapeHtml(p.room)}</span>`
          : '<span class="badge unknown-b">nur Text</span>'}</td>
        <td class="desc">${escapeHtml(p.role)}</td>
      `;
      namedHost.appendChild(row);
    });
}
