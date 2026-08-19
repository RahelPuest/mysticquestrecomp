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
    <p class="page-lede" style="margin-top:8px;">
      <strong>Preis</strong> (gefunden 2026-08-18): Bytes 13-14 jedes
      Datensatzes (16-Bit little-endian) -- 8 von 8 gegen einen echten,
      extern gefundenen Preis-Guide exakt abgeglichen (Lebe=40G, S-Lebe=160G,
      Magi=320G, S-Magi=640G, Salbe=30G, Auge=60G, Bewege=90G, Spruch=120G --
      die letzten vier zusaetzlich eine saubere +30G-Reihe, unabhaengig vom
      externen Fund). Das sind die Records 8-19, der echte Shop-Katalog fuer
      Erholungs-/Statusheilitems.
    </p>
    <p class="page-lede" style="margin-top:8px;">
      <strong>MP-Kosten</strong> (gefunden 2026-08-19): die Records 0-7 sind
      die echten 8 wirkbaren Magie-Menue-Zauber (Lebe=Cure, Salb=Heal,
      Blok=Mute, Ruhe=Sleep, Flam=Fire, Eis=Ice, Bliz=Lightning, Bomb=Nuke --
      Sleep/Mute per echtem Code-Beleg korrigiert, siehe unten) --
      NICHT "Wurf-/Kampfitems" wie fruehere Doku hier annahm. Live per
      mGBA-Disassemblierung der echten ROM-Abzugsroutine gefunden (Bank 2,
      <code>$718F-$71AB</code>): <code>categoryByte AND 0x1F</code> ist der
      echte MP-Kosten-Wert, 8 von 8 exakt gegen denselben externen Guide
      abgeglichen (Cure=2, Heal=1, Sleep=1, Mute=1, Fire=1, Ice=2,
      Lightning=2, Nuke=3).
    </p>
    <p class="page-lede" style="margin-top:8px;">
      <strong>Effekt-Dispatch, VOLLSTÄNDIGE Kette</strong> (gefunden
      2026-08-19, selber Tag): der echte Einstiegspunkt (Bank 2,
      <code>$6FBE</code>) läuft nach dem MP-Abzug eine echte Kette von
      8 Effekt-Kategorie-Tabellen ab (<code>$7B29→$7B31→$7B38→$7B46→
      $7B3D→$7B40→$7B43→$7B48</code>, geprüft über <code>CALL
      $7155</code>) -- jede Tabelle ist eine echte, nullterminierte
      Liste 1-basierter Item-/Zauber-Indizes, direkt aus dem ROM
      gelesen. Cure (Index 1) berechnet die Heilmenge über den bereits
      bekannten Kampf-PRNG plus dieselben Level-Wachstumstabellen-
      Routinen (<code>$2B7B</code>/<code>$2B8B</code>), die auch der
      Level-Aufstieg benutzt. Heal (Index 2) stellt sich als
      Status-Heilung heraus, nicht als zweiter LP-Zauber. Entscheidender
      Design-Befund: Items UND Zauber teilen sich EIN Effektsystem --
      der Cure-Zauber und die Shop-Tränke Lebe/S-Lebe/Magi/S-Magi/
      Elixier laufen durch exakt denselben LP-Wiederherstellungs-Code.
      Selbst korrigiert: Sleep/Mute waren anfangs nach externer
      Guide-Reihenfolge geraten (beide Kosten 1 MP) -- die echte
      Tabellen-Zugehörigkeit klärt es andersherum (Blok gruppiert mit
      Shop-Item "Stille" → Mute; Ruhe mit "Schlaf" → Sleep). Die
      Tabellen $7B38/$7B43/$7B46 (Edelsteine/Kristal) sind ein echter,
      allgemeiner 16-Slot-Inventar-Sammelmechanismus (WRAM
      <code>$D7E1</code>) -- strukturell unabhängig von Kampfmagie.
    </p>
    <p class="page-lede" style="margin-top:8px;">
      <strong>Eis-Anomalie AUFGEKLÄRT</strong> (gefunden 2026-08-19,
      selber Tag): der komplette Einstieg in diese Kette (Bank 2,
      <code>$6FBE</code>) läuft über eine Menü-/Feld-Aktions-Tabelle
      (<code>$404E</code>) -- nicht aus dem Kampf. Die
      Kampf-Kontext-Variante der MP-Abzugsroutine (<code>$6660</code>)
      führt NICHT in dieselbe Kette: ihre echte Fortsetzung
      (<code>$71AC</code>) kehrt für JEDEN Zauber-Index sofort zurück,
      bevor sie überhaupt in die Nähe von <code>$7B29</code> kommt.
      Diese ganze Kette ist also FELD-/MENÜ-Kontext -- nicht etwas, das
      ein im Kampf gewirkter Zauber durchläuft. Eis' Kampfeffekt (und
      möglicherweise auch Feuers/Blitz'/Nukes echter Kampfschaden)
      liegt daher in einem eigenen, noch nicht gefundenen Code-Pfad,
      nicht in dieser Kette.
    </p>
    <div class="toolbar">
      <div class="pill-tabs" id="itemTabs">
        <div class="pill-tab active" data-tab="items">Items &amp; Zauber</div>
        <div class="pill-tab" data-tab="weapons">Waffen &amp; Rüstung</div>
        ${ITEMS.weaponStats && ITEMS.weaponStats.length ? '<div class="pill-tab" data-tab="weaponStats">Waffen-Stats (echte Power/Preise)</div>' : ""}
      </div>
    </div>
    ${ITEMS.weaponStats && ITEMS.weaponStats.length ? `
    <p class="page-lede" id="weaponStatsLede" style="display:none; margin-top:8px;">
      Eine echte, SEPARATE Tabelle (<code>WeaponStatTable.lua</code>, Datei
      <code>0xA1FD</code>, 16 Bytes/Zeile) &mdash; Power und Preis
      <strong>byte-genau</strong> gegen die öffentliche US-Disassembly
      abgeglichen (alle 16 Waffen), und Power/mehrere Preise zusätzlich
      unabhängig gegen einen echten Walkthrough-Fund bestätigt. Bewusst
      NICHT mit der Namenstabelle oben verschmolzen &mdash; die
      Reihenfolge-Zuordnung zwischen beiden Tabellen ist nicht bestätigt.
    </p>` : ""}
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
    if (state.tab === "weaponStats") {
      categoryToolbar.innerHTML = "";
      return;
    }
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
    const lede = document.getElementById("weaponStatsLede");
    if (lede) lede.style.display = state.tab === "weaponStats" ? "" : "none";
    if (categoryToolbar) categoryToolbar.style.display = state.tab === "weaponStats" ? "none" : "";

    if (state.tab === "weaponStats") {
      host.innerHTML = `
        <table class="data-table">
          <thead><tr><th>#</th><th>Name</th><th>Power</th><th>Preis</th><th>Rohbytes</th></tr></thead>
          <tbody>
            ${(ITEMS.weaponStats || []).map(r => `
              <tr>
                <td class="num">${r.index}</td>
                <td>${r.name ? escapeHtml(r.name) : '<span class="desc">(unbenannt)</span>'}</td>
                <td class="num">${r.power}</td>
                <td class="num">${r.price}</td>
                <td class="num">${r.rawBytes.map(b => hex(b, 2)).join(" ")}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      `;
      return;
    }

    if (state.tab === "items") {
      host.innerHTML = `
        <table class="data-table">
          <thead><tr><th>#</th><th>Name</th><th>Kategorie</th><th>ID</th><th>Typ</th><th>Preis</th><th>MP-Kosten</th></tr></thead>
          <tbody>
            ${filteredRecords().map(r => `
              <tr>
                <td class="num">${r.index}</td>
                <td>${r.name ? escapeHtml(r.name) : '<span class="desc">(unaufgelöst)</span>'}</td>
                <td class="num">${r.categoryByte}</td>
                <td class="num">${r.id}</td>
                <td>${r.isSpell ? "Zauber" : "Item"}</td>
                <td class="num">${r.price ? r.price + " G" : '<span class="desc">(nicht verkauft)</span>'}</td>
                <td class="num">${r.isSpell ? r.mpCost + " MP" : '<span class="desc">-</span>'}</td>
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
