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
  { id: "transitions", icon: "🚪", label: "Raum-Übergänge", group: "Welt" },
  { id: "tiles", icon: "◱", label: "Tile-Viewer", group: "Welt" },
  { id: "text", icon: "“”", label: "Text-Encoding", group: "Welt" },
  { id: "music", icon: "♪", label: "Musik & Sound", group: "Welt" },
  { id: "monsters", icon: "👾", label: "Monster", group: "Katalog" },
  { id: "items", icon: "🗡", label: "Items & Waffen", group: "Katalog" },
  { id: "npcs", icon: "🧑", label: "NPCs", group: "Katalog" },
  { id: "actors", icon: "🎲", label: "Akteur-Tabelle", group: "Katalog" },
  { id: "story", icon: "📖", label: "Story & Charaktere", group: "Katalog" },
  { id: "graphics", icon: "🖼", label: "Grafiken", group: "Katalog" },
  { id: "questions", icon: "?", label: "Offene Fragen", group: "Status" },
];

function countFor(id) {
  try {
    if (id === "opcodes") return OPCODES.filter(o => o.status === "undecoded").length + " offen";
    if (id === "questions") return String(OPEN_QUESTIONS.length);
    if (id === "rooms") return String(ROOMS.length);
    if (id === "map") return String(ROOM_MAPS.length + ROOM_CATALOG.length);
    if (id === "worldmap") return "16×16 / 8×8";
    if (id === "transitions") return String(TRANSITIONS.distinct.length);
    if (id === "monsters") return String(MONSTERS.species.length);
    if (id === "items") return String(ITEMS.items.length + ITEMS.weapons.length);
    if (id === "npcs") return String(NPCS.length);
    if (id === "actors") return String(ACTORS.tableCount);
    if (id === "story") return String(STORY.bossDefeats.length + STORY.namedCharacters.length);
    if (id === "music") return String(MUSIC.songCount);
    if (id === "graphics") return String(GRAPHICS_CANDIDATES.length);
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
    // A real <a href="#id">, not a <div> + click listener (2026-08-16
    // accessibility audit): natively keyboard-focusable and operable
    // (Enter activates it, no custom keydown handling needed), gets a
    // real accessible name from its own text content, and
    // `aria-current="page"` tells assistive tech which section is
    // active -- none of that was true for the old plain <div>.
    const item = document.createElement("a");
    item.href = "#" + s.id;
    item.className = "navitem" + (s.id === activeId ? " active" : "");
    if (s.id === activeId) item.setAttribute("aria-current", "page");
    const cnt = countFor(s.id);
    item.innerHTML = `<span class="icon" aria-hidden="true">${s.icon}</span><span>${s.label}</span>` +
      (cnt ? `<span class="count">${cnt}</span>` : "");
    // Navigation itself happens via the real href/hashchange; this
    // only closes the mobile drawer (a no-op on desktop, see
    // setupMobileNav's own closeMobileNav definition).
    item.addEventListener("click", closeMobileNav);
    nav.appendChild(item);
  }
}

// Retrofits keyboard operability onto this site's own custom
// click-driven controls (.pill-tab, .bank-cell, .opcode-cell,
// .hbar-row) -- 2026-08-16 audit finding: none of these ever had
// `tabindex`/`role`/a keyboard handler, so keyboard-only and screen-
// reader users could not reach or activate ANY of them (filters,
// memory-bank cells, the whole opcode grid, scan-result rows). Runs
// once per render, AFTER a section's own render_*() has already
// attached its real `click` listeners -- forwarding Enter/Space to a
// real `.click()` call means every one of those existing listeners
// keeps working completely unchanged; this only adds the missing
// keyboard entry point. Elements can opt out by already carrying
// their own explicit tabindex (none currently do).
function enhanceKeyboardAccessibility(container) {
  container.querySelectorAll(".pill-tab, .bank-cell, .opcode-cell, .hbar-row").forEach(el => {
    if (el.hasAttribute("tabindex")) return;
    // .hbar-row (scan.js) is only genuinely clickable for entries with
    // a real matching opcode (see that file's own guard) -- checking
    // the actually-applied cursor style, not a fragile string match on
    // the raw `style` attribute, is what tells the two kinds apart.
    if (el.classList.contains("hbar-row") && getComputedStyle(el).cursor !== "pointer") return;
    el.setAttribute("tabindex", "0");
    if (!el.hasAttribute("role")) el.setAttribute("role", "button");
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        el.click();
      }
    });
  });
}

// --- mobile navigation drawer (2026-08-16 audit: replaces the old
// "#sidebar{display:none} below 860px, no alternative" dead end) ---
function isMobileNavOpen() {
  return document.getElementById("sidebar").classList.contains("open");
}
function openMobileNav() {
  document.getElementById("sidebar").classList.add("open");
  document.getElementById("sidebarBackdrop").classList.add("open");
  document.getElementById("sidebarToggle").setAttribute("aria-expanded", "true");
}
function closeMobileNav() {
  if (!isMobileNavOpen()) return; // no-op on desktop (class never gets added) and when already closed
  document.getElementById("sidebar").classList.remove("open");
  document.getElementById("sidebarBackdrop").classList.remove("open");
  document.getElementById("sidebarToggle").setAttribute("aria-expanded", "false");
}
function setupMobileNav() {
  const toggle = document.getElementById("sidebarToggle");
  const backdrop = document.getElementById("sidebarBackdrop");
  toggle.addEventListener("click", () => {
    if (isMobileNavOpen()) closeMobileNav(); else openMobileNav();
  });
  backdrop.addEventListener("click", closeMobileNav);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isMobileNavOpen()) {
      closeMobileNav();
      toggle.focus(); // return focus to the control that opened it, standard dialog/drawer convention
    }
  });
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
  enhanceKeyboardAccessibility(main);
}

// hashchange-only wrapper around route(): scrolls to the top and moves
// focus to #main (a real, expected SPA convention -- without it, a
// keyboard/screen-reader user who navigates from the bottom of a long
// page lands on the new page still scrolled to where they were, and
// nothing announces that the content even changed). Deliberately NOT
// baked into route() itself, since route() also runs for non-
// navigation refreshes (initial load, a palette switch) where
// grabbing focus/scrolling away would be a real regression, not a fix
// -- e.g. picking a new color palette from the top bar must not yank
// focus and the viewport down to the page body.
function navigate() {
  route();
  closeMobileNav();
  window.scrollTo(0, 0);
  document.getElementById("main").focus();
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

function setupPaletteControl() {
  GBPalette.init(); // restore a previously-picked preset, if any
  const select = document.getElementById("paletteSelect");
  select.innerHTML = Object.entries(GBPalette.PRESETS)
    .map(([id, p]) => `<option value="${id}">${escapeHtml(p.label)}</option>`)
    .join("");
  select.value = GBPalette.current;
  select.addEventListener("change", () => GBPalette.set(select.value));
  // Every currently-mounted tile canvas was drawn with the OLD colors
  // -- re-running the current section's own render is the simplest way
  // to get every one of them (Tile-Viewer, Map-Viewer, Weltkarte,
  // Monster/NPC/Grafiken cards, ...) to redraw with the new preset
  // without wiring a bespoke redraw callback into each of those
  // modules individually.
  GBPalette.onChange(() => route());
}

window.addEventListener("hashchange", navigate);
window.addEventListener("DOMContentLoaded", () => {
  setupPaletteControl();
  setupMobileNav();
  route();
  const search = document.getElementById("globalSearch");
  search.addEventListener("keydown", (e) => {
    if (e.key === "Enter") runGlobalSearch(search.value);
  });

  const romInput = document.getElementById("romFileInput");
  const romLabel = document.getElementById("romLoadLabel");
  romInput.addEventListener("change", () => {
    if (romInput.files[0]) RomBytes.loadFile(romInput.files[0]);
  });
  // The real input is visually-hidden (its own <label> is the visible
  // "button"); mirror ITS focus state onto the label so a keyboard
  // user tabbing to the real, now-reachable input still sees a focus
  // ring on the control they can actually see (2026-08-16 audit fix).
  romInput.addEventListener("focus", () => romLabel.classList.add("focus-ring"));
  romInput.addEventListener("blur", () => romLabel.classList.remove("focus-ring"));
  RomBytes.onChange(updateRomLoadStatus);
  updateRomLoadStatus();
});
