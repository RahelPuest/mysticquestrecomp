function render_items(main) {
  main.innerHTML = `
    <h1 class="page-title">Items &amp; Waffen</h1>
    <p class="page-lede">
      Die echte Item-/Zauber-Tabelle (<code>ItemTable.lua</code>, ${ITEMS.items.length}
      Einträge) und die echte Waffen-/Rüstungstabelle (<code>WeaponTable.lua</code>,
      ${ITEMS.weapons.length} Einträge) &mdash; beide Tabellengrenzen 2026-08-15 deutlich
      erweitert. Namen dekodieren für die meisten Einträge sauber; Einträge mit leerem
      Namen dekodieren an keinem der beiden bekannten Offsets &mdash; ehrlich als
      unaufgelöste Lücke gezeigt, nicht geraten.
    </p>
    <div class="toolbar">
      <div class="pill-tabs" id="itemTabs">
        <div class="pill-tab active" data-tab="items">Items &amp; Zauber</div>
        <div class="pill-tab" data-tab="weapons">Waffen &amp; Rüstung</div>
      </div>
    </div>
    <p class="page-lede" style="margin-top:8px;">
      <strong>Kategorie-Bytes</strong> (2026-08-15, Katalog-Plan Phase 2): jeder echte
      Datensatz trägt ein reales <code>categoryByte</code>. Gruppen mit &ge;5 Einträgen
      (<span class="badge partial">Gruppe</span>) zeigen bei Waffen oft eine klare Material-/
      Elementar-Tier-Reihe (z.&nbsp;B. Bronze&rarr;Eisen&rarr;Silber&rarr;Gold&rarr;...) &mdash;
      welcher reale Ausrüstungs-Slot (Waffe/Rüstung/Helm?) dahintersteckt, ist NICHT
      bestätigt. Kleinere Gruppen (<span class="badge default">Einzelstück</span>) sind meist
      individuell benannte Gegenstände. Die Einteilung selbst ist real (aus dem ROM
      gruppiert); die Namen der Kategorien sind es nicht &mdash; nur die Byte-Werte.
    </p>
    <div class="toolbar" id="itemCategoryToolbar"></div>
    <div id="itemHost"></div>
  `;
  const host = document.getElementById("itemHost");
  const categoryToolbar = document.getElementById("itemCategoryToolbar");

  const state = { tab: "items", category: "all" };

  function categoriesFor(tab) {
    return tab === "items" ? ITEMS.itemCategories : ITEMS.weaponCategories;
  }
  function recordsFor(tab) {
    return tab === "items" ? ITEMS.items : ITEMS.weapons;
  }

  function renderCategoryPills() {
    const cats = categoriesFor(state.tab);
    categoryToolbar.innerHTML = `
      <div class="pill-tabs" id="itemCatPills">
        <div class="pill-tab ${state.category === "all" ? "active" : ""}" data-cat="all">
          Alle (${recordsFor(state.tab).length})
        </div>
        ${cats.map(c => `
          <div class="pill-tab ${state.category === c.categoryByte ? "active" : ""}" data-cat="${c.categoryByte}">
            #${c.categoryByte} (${c.count})${c.sizeClass === "group" ? " &bull;" : ""}
          </div>
        `).join("")}
      </div>
    `;
    categoryToolbar.querySelectorAll(".pill-tab").forEach(tab => {
      tab.addEventListener("click", () => {
        const v = tab.dataset.cat;
        state.category = v === "all" ? "all" : Number(v);
        renderCategoryPills();
        renderTable();
      });
    });
  }

  function filteredRecords() {
    const records = recordsFor(state.tab);
    if (state.category === "all") return records;
    return records.filter(r => r.categoryByte === state.category);
  }

  function renderTable() {
    if (state.tab === "items") {
      host.innerHTML = `
        <table class="data-table">
          <thead><tr><th>#</th><th>Name</th><th>Kategorie</th><th>ID</th><th>Typ</th></tr></thead>
          <tbody>
            ${filteredRecords().map(r => `
              <tr>
                <td class="num">${r.index}</td>
                <td>${r.name ? escapeHtml(r.name) : '<span class="desc">(unaufgelöst)</span>'}</td>
                <td class="num">${r.categoryByte}</td>
                <td class="num">${r.id}</td>
                <td>${r.isSpell ? "Zauber" : "Item"}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    } else {
      host.innerHTML = `
        <table class="data-table">
          <thead><tr><th>#</th><th>Name</th><th>Kategorie-Byte</th><th>Stat-Bytes (roh)</th></tr></thead>
          <tbody>
            ${filteredRecords().map(r => `
              <tr>
                <td class="num">${r.index}</td>
                <td>${r.name ? escapeHtml(r.name) : '<span class="desc">(unaufgelöst)</span>'}</td>
                <td class="num">${r.categoryByte}</td>
                <td class="num">${r.statBytes.map(b => hex(b, 2)).join(" ")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
    }
  }

  document.querySelectorAll("#itemTabs .pill-tab").forEach(tab => {
    tab.addEventListener("click", () => {
      document.querySelectorAll("#itemTabs .pill-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      state.tab = tab.dataset.tab;
      state.category = "all";
      renderCategoryPills();
      renderTable();
    });
  });

  renderCategoryPills();
  renderTable();
}
