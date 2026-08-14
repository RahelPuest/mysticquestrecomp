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
    const notes = (typeof BANK_NOTES !== "undefined" && BANK_NOTES[b]) || null;
    const cell = document.createElement("div");
    cell.className = "bank-cell";
    // CORRECTED 2026-08-14 (direct user question: "laut der website ist
    // der Inhalt der meisten ROM-Bänke noch nicht kartiert. ist das
    // so"): this tag used to read "Inhalt nicht kartiert" for EVERY
    // bank without a ROM_TABLES entry (11/16 banks) -- technically
    // about "no named table," but real enough content is documented
    // elsewhere (BANK_NOTES, hand-curated from rom-map.md/events.md)
    // for all but bank 10 that the old blanket tag was actively
    // misleading. Now distinguishes "known table," "explored (real
    // findings exist, just not a table)," and the one real "genuinely
    // unexplored" case.
    let tag;
    if (tables.length) {
      tag = tables.length + " bekannte Tabelle(n)";
    } else if (b === 0) {
      tag = "immer gemappt ($0000-$3FFF)";
    } else if (notes && notes.tier === "explored") {
      tag = "teilweise erkundet (keine Tabelle)";
    } else {
      tag = "Inhalt nicht kartiert";
    }
    cell.innerHTML = `<div class="n">Bank ${b}</div><div class="tag">${tag}</div>`;
    cell.addEventListener("click", () => {
      bankDetail.style.display = "block";
      let html = `<h3 style="margin-top:0;">Bank ${b}</h3>`;
      if (tables.length) {
        html += tables.map(t => `
          <div style="padding:8px 0; border-top:1px solid var(--border);">
            <strong>${t.name}</strong> &mdash; <span class="badge ${badgeClassForStatus(t.status)}">${escapeHtml((t.status || "").split(" ")[0])}</span><br>
            <span class="mono" style="color:var(--text-dim); font-size:12px;">file ${hex(t.fileOffset, 5)} &middot; ${t.recordCount || "?"} Einträge</span>
          </div>`).join("");
      }
      if (notes) {
        html += `<p class="desc" style="margin-top:${tables.length ? "12px" : "0"};">${escapeHtml(notes.note)}</p>`;
      } else if (!tables.length) {
        html += `<p class="desc">Keine hier verortete, benannte Tabelle in den aktuellen Projektdaten &mdash; das heißt nicht zwangsläufig, dass die Bank leer ist, nur dass dieses Tool nichts Benanntes darin kennt.</p>`;
      }
      bankDetail.innerHTML = html;
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
