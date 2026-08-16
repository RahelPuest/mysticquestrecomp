function render_entity(main) {
  main.innerHTML = `
    <h1 class="page-title">Entity-Struktur</h1>
    <p class="page-lede">
      Der reale, generische WRAM-Slot-Struct, den Spieler, Gegner und NPCs gleichermaßen
      benutzen: ${ENTITY_STRUCT.slotCount} Slots à ${ENTITY_STRUCT.stride} Bytes ab
      ${hex(ENTITY_STRUCT.base)}. Verifiziert über zwei unabhängige reale Routinen
      (DESPAWN ${hex(ENTITY_STRUCT.despawnRoutine)} und ALLOCATE ${hex(ENTITY_STRUCT.allocateRoutine)}),
      die beide exakt dieselbe Adressformel berechnen.
    </p>

    <div class="panel entity-row">
      <div class="entity-controls">
        <label for="slotSlider" style="font-size:12px; color:var(--text-dim);">Slot-Index (0-${ENTITY_STRUCT.slotCount - 1})</label><br>
        <input type="range" id="slotSlider" min="0" max="${ENTITY_STRUCT.slotCount - 1}" value="${ENTITY_STRUCT.playerSlotIndex}">
        <div style="margin-top:10px; font-family:var(--mono);">
          Slot <span id="slotNum" style="color:var(--accent-bright);"></span>
          &rarr; Basis-Adresse <span id="slotAddr" style="color:var(--accent-bright);"></span>
        </div>
        <div id="playerNote" style="margin-top:8px; font-size:12px; color:var(--accent); display:none;">
          &#9733; Dies ist der bestätigte Spieler-Slot (live-getraced über die reale
          Landeposition-Übergabe eines Cut-Übergangs).
        </div>
      </div>
      <div style="flex:1; min-width:280px;">
        <div class="byte-strip" id="byteStrip"></div>
      </div>
    </div>

    <h2 class="section-title">Felder</h2>
    <table class="data-table">
      <thead><tr><th style="width:80px;">Offset</th><th>Feld</th><th style="width:150px;">Getter/Setter</th><th>Bedeutung</th></tr></thead>
      <tbody>
        ${ENTITY_STRUCT.fields.map(f => `<tr><td class="num">+${f.offset}</td><td class="mono">${escapeHtml(f.name)}</td><td class="mono" style="font-size:12px; color:var(--text-dim);">${accessorCell(f)}</td><td class="desc" style="color:var(--text-dim); font-size:13px;">${escapeHtml(f.note) || fieldMeaning(f.name)}</td></tr>`).join("")}
      </tbody>
    </table>
    ${ENTITY_STRUCT.pairedSetterAddress !== undefined ? `
    <p class="page-lede" style="margin-top:14px; font-size:13px;">
      Zusätzlich: <span class="mono">${hex(ENTITY_STRUCT.pairedSetterAddress)}</span> ist ein realer,
      GEGUARDETER Setter, der +6/+7 als EINEN gepaarten 16-Bit-Wert behandelt (nicht als zwei
      unabhängige Bytes) &mdash; übersprungen, sobald der Slot tot ist (ALIVE == 0xFF).
    </p>` : ""}
  `;

  const slider = document.getElementById("slotSlider");
  function update() {
    const slot = parseInt(slider.value, 10);
    const base = ENTITY_STRUCT.base + slot * ENTITY_STRUCT.stride;
    document.getElementById("slotNum").textContent = slot;
    document.getElementById("slotAddr").textContent = hex(base);
    document.getElementById("playerNote").style.display = (slot === ENTITY_STRUCT.playerSlotIndex) ? "block" : "none";

    const strip = document.getElementById("byteStrip");
    strip.innerHTML = "";
    for (let off = 0; off < ENTITY_STRUCT.stride; off++) {
      const field = ENTITY_STRUCT.fields.find(f => f.offset === off);
      const box = document.createElement("div");
      box.className = "byte-box" + (field ? " highlight" : "");
      box.innerHTML = `<div class="off">${hex(base + off)}</div><div>+${off}</div>` +
        (field ? `<div class="fname">${abbrev(field.name)}</div>` : "");
      box.title = field ? field.name : "ungenutzt/unbekannt";
      strip.appendChild(box);
    }
  }
  slider.addEventListener("input", update);
  update();
}

function abbrev(name) {
  const map = { ALIVE: "ALIVE", TYPE: "TYPE", PARAM2: "P2", PARAM3: "P3", POSITION_Y: "Y", POSITION_X: "X", PARAM6: "P6", PARAM7: "P7", OAM_SHADOW_PTR: "OAM*", UNKNOWN_10: "?10", UNKNOWN_11: "?11" };
  return map[name] || name;
}

function accessorCell(f) {
  if (f.accessorGet === undefined && f.accessorSet === undefined) return "&mdash;";
  const g = f.accessorGet !== undefined ? `get ${hex(f.accessorGet)}` : "";
  const s = f.accessorSet !== undefined ? `set ${hex(f.accessorSet)}` : "";
  return [g, s].filter(Boolean).join("<br>");
}

// Fallback only -- ENTITY_STRUCT.fields[].note (from export_data.lua's
// own curated FIELD_NOTES, 2026-08-14) is preferred when present; this
// map exists so the table still shows something sensible if a field
// has no server-provided note.
function fieldMeaning(name) {
  const map = {
    ALIVE: "Alive/State-Byte: 0xFF = tot/leer (Sentinel), 0x08 beim echten Allocate.",
    TYPE: "Vom Aufrufer übergebener „Typ“-Parameter &mdash; reale ROM-Bedeutung nicht weiter dekodiert. Auch das Ziel der Opcodes 0x88/0x89 (schreiben feste Werte 2/1).",
    PARAM2: "Vom Aufrufer übergebener Parameter.",
    PARAM3: "Real 0 beim Allocate.",
    POSITION_Y: "Echte Y-Position, Pixel-Raum. Für Slot 4 (Spieler) = $C244.",
    POSITION_X: "Echte X-Position, Pixel-Raum. Für Slot 4 (Spieler) = $C245.",
    PARAM6: "Vom Aufrufer übergebener Parameter.",
    PARAM7: "Vom Aufrufer übergebener Parameter.",
    OAM_SHADOW_PTR: "Echter 16-Bit-LE-Zeiger auf den 8-Byte-OAM-Schatten-Block dieses Slots.",
    UNKNOWN_10: "Feld jenseits des bisher dokumentierten Bereichs 0-8, real aber unbenannt.",
    UNKNOWN_11: "Feld jenseits des bisher dokumentierten Bereichs 0-8, real aber unbenannt.",
  };
  return map[name] || "";
}
