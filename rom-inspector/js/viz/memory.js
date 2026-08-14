function render_memory(main) {
  const params = new URLSearchParams(location.hash.split("?")[1] || "");
  const focusAddr = params.get("focus");

  main.innerHTML = `
    <h1 class="page-title">Speicherkarte</h1>
    <p class="page-lede">
      Zwei reale Adressräume: die 16 umschaltbaren 16-KiB-ROM-Banks (MBC2, fest gemappt
      auf $0000-$3FFF / umschaltbar auf $4000-$7FFF) und die bekannten WRAM-Zellen, die
      der Skript-Interpreter und die Spiellogik tatsächlich lesen/schreiben.
    </p>

    <h2 class="section-title">ROM-Banks</h2>
    <div class="bank-grid" id="bankGrid"></div>
    <div id="bankDetail" class="bank-detail panel" style="display:none;"></div>

    <h2 class="section-title">Bekannte WRAM-Zellen</h2>
    <div class="toolbar">
      <input type="text" id="wramSearch" placeholder="Filtern nach Adresse/Name&hellip;" style="width:280px;">
    </div>
    <table class="data-table" id="wramTable">
      <thead><tr><th style="width:150px;">Adresse</th><th style="width:220px;">Name</th><th style="width:110px;">Status</th><th>Beschreibung</th></tr></thead>
      <tbody></tbody>
    </table>
  `;

  const bankGrid = document.getElementById("bankGrid");
  const bankDetail = document.getElementById("bankDetail");
  for (let b = 0; b < ROM_BASICS.bankCount; b++) {
    const tables = ROM_TABLES.filter(t => t.bank === b);
    const cell = document.createElement("div");
    cell.className = "bank-cell";
    cell.innerHTML = `<div class="n">Bank ${b}</div><div class="tag">${tables.length ? tables.length + " bekannte Tabelle(n)" : (b === 0 ? "immer gemappt ($0000-$3FFF)" : "Inhalt nicht kartiert")}</div>`;
    cell.addEventListener("click", () => {
      bankDetail.style.display = "block";
      if (tables.length === 0) {
        bankDetail.innerHTML = `<h3 style="margin-top:0;">Bank ${b}</h3><p class="desc">Keine hier verortete, benannte Tabelle in den aktuellen Projektdaten &mdash; das heißt nicht, dass die Bank leer ist, nur dass dieses Tool nichts Benanntes darin kennt.</p>`;
      } else {
        bankDetail.innerHTML = `<h3 style="margin-top:0;">Bank ${b}</h3>` + tables.map(t => `
          <div style="padding:8px 0; border-top:1px solid var(--border);">
            <strong>${t.name}</strong> &mdash; <span class="badge ${badgeClassForStatus(t.status)}">${escapeHtml((t.status || "").split(" ")[0])}</span><br>
            <span class="mono" style="color:var(--text-dim); font-size:12px;">file ${hex(t.fileOffset, 5)} &middot; ${t.recordCount || "?"} Einträge</span>
          </div>`).join("");
      }
    });
    bankGrid.appendChild(cell);
  }

  const tbody = document.querySelector("#wramTable tbody");
  function renderWram(filter) {
    tbody.innerHTML = "";
    const f = (filter || "").toLowerCase();
    for (const w of WRAM_MAP) {
      if (f && !w.address.toLowerCase().includes(f) && !w.name.toLowerCase().includes(f) && !w.description.toLowerCase().includes(f)) continue;
      const tr = document.createElement("tr");
      if (focusAddr && w.address === focusAddr) tr.style.background = "var(--bg-hover)";
      tr.innerHTML = `<td class="addr">${escapeHtml(w.address)}</td><td>${escapeHtml(w.name)}</td>
        <td><span class="badge ${badgeClassForStatus(w.status)}">${escapeHtml(w.status.split(" ")[0])}</span></td>
        <td class="desc" style="color:var(--text-dim); font-size:12.5px;">${escapeHtml(w.description)}</td>`;
      tbody.appendChild(tr);
    }
  }
  renderWram("");
  document.getElementById("wramSearch").addEventListener("input", (e) => renderWram(e.target.value));
}

function badgeClassForStatus(status) {
  if (!status) return "unknown-b";
  const s = status.toUpperCase();
  if (s.startsWith("VERIFIED")) return "verified";
  if (s.startsWith("PARTIALLY")) return "partial";
  if (s.startsWith("UNKNOWN")) return "unknown-b";
  return "partial";
}
