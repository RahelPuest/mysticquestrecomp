// Shell: sidebar nav + hash router + a small cross-section search.
// Each section module (js/viz/*.js) registers itself into `SECTIONS`
// and exports a `render(container)` function that fills #main.

const SECTIONS = [
  { id: "overview", icon: "▣", label: "Übersicht", group: "Start" },
  { id: "memory", icon: "▤", label: "Speicherkarte", group: "Struktur" },
  { id: "entity", icon: "⚙", label: "Entity-Struktur", group: "Struktur" },
  { id: "tables", icon: "☷", label: "ROM-Tabellen", group: "Struktur" },
  { id: "opcodes", icon: "⌘", label: "Skript-Opcodes", group: "Interpreter" },
  { id: "scan", icon: "≈", label: "Whole-Corpus-Scan", group: "Interpreter" },
  { id: "rooms", icon: "⬢", label: "Raum-System", group: "Welt" },
  { id: "map", icon: "▦", label: "Map-Viewer", group: "Welt" },
  { id: "worldmap", icon: "🗺", label: "Weltkarte", group: "Welt" },
  { id: "tiles", icon: "◱", label: "Tile-Viewer", group: "Welt" },
  { id: "text", icon: "“”", label: "Text-Encoding", group: "Welt" },
  { id: "music", icon: "♪", label: "Musik & Sound", group: "Welt" },
  { id: "monsters", icon: "👾", label: "Monster", group: "Katalog" },
  { id: "items", icon: "🗡", label: "Items & Waffen", group: "Katalog" },
  { id: "npcs", icon: "🧑", label: "NPCs", group: "Katalog" },
  { id: "story", icon: "📖", label: "Story & Charaktere", group: "Katalog" },
  { id: "questions", icon: "?", label: "Offene Fragen", group: "Status" },
];

function countFor(id) {
  try {
    if (id === "opcodes") return OPCODES.filter(o => o.status === "undecoded").length + " offen";
    if (id === "questions") return String(OPEN_QUESTIONS.length);
    if (id === "rooms") return String(ROOMS.length);
    if (id === "map") return String(ROOM_MAPS.length + ROOM_CATALOG.length);
    if (id === "worldmap") return "16×16 / 8×8";
    if (id === "monsters") return String(MONSTERS.species.length);
    if (id === "items") return String(ITEMS.items.length + ITEMS.weapons.length);
    if (id === "npcs") return String(NPCS.length);
    if (id === "story") return String(STORY.bossDefeats.length + STORY.namedCharacters.length);
    if (id === "music") return String(MUSIC.songCount);
  } catch (e) { /* data not loaded yet */ }
  return "";
}

function renderSidebar(activeId) {
  const nav = document.getElementById("sidebar");
  nav.innerHTML = "";
  let lastGroup = null;
  for (const s of SECTIONS) {
    if (s.group !== lastGroup) {
      const label = document.createElement("div");
      label.className = "group-label";
      label.textContent = s.group;
      nav.appendChild(label);
      lastGroup = s.group;
    }
    const item = document.createElement("div");
    item.className = "navitem" + (s.id === activeId ? " active" : "");
    const cnt = countFor(s.id);
    item.innerHTML = `<span class="icon">${s.icon}</span><span>${s.label}</span>` +
      (cnt ? `<span class="count">${cnt}</span>` : "");
    item.addEventListener("click", () => { location.hash = "#" + s.id; });
    nav.appendChild(item);
  }
}

function currentSectionId() {
  const h = location.hash.replace("#", "").split("?")[0];
  return SECTIONS.some(s => s.id === h) ? h : "overview";
}

// Per-section cleanup registry -- a render_*() function that
// subscribes to something long-lived (e.g. RomBytes.onChange) MUST
// call `onSectionUnload(unsubscribeFn)` so it gets torn down the
// moment the user navigates away, instead of leaking a callback that
// later fires against DOM nodes route() already removed.
let _sectionCleanups = [];
function onSectionUnload(fn) { _sectionCleanups.push(fn); }

function route() {
  for (const cleanup of _sectionCleanups) cleanup();
  _sectionCleanups = [];

  const id = currentSectionId();
  renderSidebar(id);
  const main = document.getElementById("main");
  main.innerHTML = "";
  const renderer = window["render_" + id];
  if (typeof renderer === "function") {
    renderer(main);
  } else {
    main.innerHTML = "<p>Unbekannter Bereich.</p>";
  }
  const footer = document.createElement("footer");
  footer.className = "site-footer";
  footer.innerHTML = `Alle Zahlen/Adressen auf dieser Seite stammen entweder direkt aus einem
    Lauf von <code>rom-inspector/tools/export_data.lua</code> gegen die echte ROM
    (siehe dort für Details), oder sind explizit als kuratiert gekennzeichnet.
    Quelle: <code>docs/reverse-engineering/</code> im Hauptprojekt.`;
  main.appendChild(footer);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function hex(n, digits) {
  if (n === null || n === undefined) return "?";
  digits = digits || 4;
  return "$" + n.toString(16).toUpperCase().padStart(digits, "0");
}

// --- tiny cross-section search ---
function runGlobalSearch(query) {
  query = query.trim().toLowerCase();
  if (!query) return;
  const numMatch = query.match(/^(0x)?([0-9a-f]{1,4})$/i);
  const asNum = numMatch ? parseInt(numMatch[2], 16) : null;

  // Opcode by number or handler address
  if (asNum !== null) {
    const byOpcode = OPCODES.find(o => o.opcode === asNum);
    const byHandler = OPCODES.find(o => o.handler === asNum);
    if (byHandler || (byOpcode && query.length <= 2)) {
      location.hash = "#opcodes?focus=" + (byHandler ? byHandler.opcode : byOpcode.opcode);
      return;
    }
  }
  // WRAM cell
  const wramHit = WRAM_MAP.find(w => w.address.toLowerCase().includes(query) || w.name.toLowerCase().includes(query));
  if (wramHit) { location.hash = "#memory?focus=" + encodeURIComponent(wramHit.address); return; }

  // Open question
  const qHit = OPEN_QUESTIONS.find(q => q.title.toLowerCase().includes(query) || q.description.toLowerCase().includes(query));
  if (qHit) { location.hash = "#questions"; return; }

  // Room
  const roomHit = ROOMS.find(r => r.name.toLowerCase().includes(query));
  if (roomHit) { location.hash = "#rooms"; return; }

  location.hash = "#opcodes";
}

function updateRomLoadStatus() {
  const el = document.getElementById("romLoadStatus");
  if (!el) return;
  if (RomBytes.isLoaded()) {
    el.textContent = `✓ ${RomBytes.fileName} (${(RomBytes.bytes.length / 1024).toFixed(0)} KiB)`;
    el.classList.add("loaded");
  } else {
    el.textContent = "nicht geladen";
    el.classList.remove("loaded");
  }
}

window.addEventListener("hashchange", route);
window.addEventListener("DOMContentLoaded", () => {
  route();
  const search = document.getElementById("globalSearch");
  search.addEventListener("keydown", (e) => {
    if (e.key === "Enter") runGlobalSearch(search.value);
  });

  const romInput = document.getElementById("romFileInput");
  romInput.addEventListener("change", () => {
    if (romInput.files[0]) RomBytes.loadFile(romInput.files[0]);
  });
  RomBytes.onChange(updateRomLoadStatus);
  updateRomLoadStatus();
});
