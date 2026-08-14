function render_tables(main) {
  main.innerHTML = `
    <h1 class="page-title">ROM-Tabellen</h1>
    <p class="page-lede">
      Jede benannte, (teilweise) verifizierte Datentabelle, die dieses Projekt in der ROM
      lokalisiert hat &mdash; direkt aus <code>rom_profiles.lua</code> gelesen, nicht von Hand
      abgeschrieben.
    </p>
    <div class="card-grid" id="tableCards"></div>
  `;
  const host = document.getElementById("tableCards");
  for (const t of ROM_TABLES) {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${escapeHtml(t.name)}</h3>
      <span class="badge ${badgeClassForStatus(t.status)}">${escapeHtml((t.status || "").split(" ")[0] || "?")}</span>
      <div class="desc" style="margin-top:8px;">${escapeHtml(t.status || "")}</div>
      <div class="meta">
        Bank ${t.bank !== undefined ? t.bank : "?"} &middot; file ${t.fileOffset !== undefined ? hex(t.fileOffset, 5) : "?"}
        ${t.recordCount ? " &middot; " + t.recordCount + " Einträge" : ""}
      </div>
    `;
    host.appendChild(card);
  }
}
