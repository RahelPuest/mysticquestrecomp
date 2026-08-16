// I18n -- toggleable German/English UI chrome for this site.
//
// 2026-08-16, direct user instruction ("mach die website zweisprachig
// (umschaltbar zwischen deutsch und englisch)"), scoped per the user's
// own explicit choice ("nur UI-Hülle übersetzen"): this translates
// STRUCTURAL chrome only -- nav labels, page/section headings, table
// column headers, buttons, tabs, form labels/placeholders, and a
// handful of site-wide boilerplate sentences (the footer note, the
// "no ROM loaded" status). It deliberately does NOT translate:
//   - the page-lede / section-explainer prose in js/viz/*.js (the
//     longer paragraphs describing methodology and findings), or
//   - any research content from js/data/*.js (opcode descriptions,
//     open questions, room/actor/story notes, etc.).
// Those are real, verified reverse-engineering findings; translating
// thousands of them by hand/model risks silently shifting a technical
// claim's meaning, which this project treats as a correctness bug, not
// a cosmetic one (see the project's own "nothing is guessed" rule).
// They stay German-only, with an honest note in the language switcher
// itself -- not silently passed through as if reviewed.
//
// Mechanism: an exact-string dictionary (German phrase -> English
// phrase) plus a DOM pass that walks text nodes and a fixed set of
// translatable attributes (placeholder/aria-label/title/alt), matching
// only EXACT, trimmed content. A string not in DICT is left exactly as
// rendered (German) -- there is no machine translation step and no
// partial/fuzzy matching, so this can never mistranslate a fragment of
// real ROM data that happens to sit next to translated chrome. Each
// touched node/attribute remembers its own original (German, as
// authored in the *.js source) the first time it's visited, so
// switching language is symmetric and re-render-safe: dynamically
// rebuilt sections (main content, re-rendered on every route()) just
// re-capture fresh German source text each time, while the static
// topbar (parsed once from index.html) keeps its captured original
// across every toggle.

const I18n = (() => {
  const STORAGE_KEY = "mq_rominspector_lang";
  const ATTRS = ["placeholder", "aria-label", "title", "alt"];

  // German (exact, trimmed) -> English. Chrome only -- see doc comment above.
  const DICT = {
    // --- nav (js/app.js SECTIONS) ---
    "Übersicht": "Overview",
    "Speicherkarte": "Memory map",
    "Entity-Struktur": "Entity struct",
    "ROM-Tabellen": "ROM tables",
    "Skript-Opcodes": "Script opcodes",
    "Whole-Corpus-Scan": "Whole-corpus scan",
    "Raum-System": "Room system",
    "Map-Viewer": "Map viewer",
    "Weltkarte": "World map",
    "Raum-Übergänge": "Room transitions",
    "Tile-Viewer": "Tile viewer",
    "Text-Encoding": "Text encoding",
    "Musik & Sound": "Music & sound",
    "Monster": "Monsters",
    "Items & Waffen": "Items & weapons",
    "NPCs": "NPCs",
    "Akteur-Tabelle": "Actor table",
    "Story & Charaktere": "Story & characters",
    "Grafiken": "Graphics",
    "Offene Fragen": "Open questions",
    "Start": "Start",
    "Struktur": "Structure",
    "Interpreter": "Interpreter",
    "Welt": "World",
    "Katalog": "Catalog",
    "Status": "Status",
    "offen": "open",

    // --- app shell (js/app.js, index.html) ---
    "Unbekannter Bereich.": "Unknown section.",
    "nicht geladen": "not loaded",
    "Zum Inhalt springen": "Skip to content",
    "Navigation öffnen": "Open navigation",
    "ROM Inspector": "ROM Inspector",
    "Mystic Quest (Game Boy, EU) — interaktive Reverse-Engineering-Dokumentation":
      "Mystic Quest (Game Boy, EU) — interactive reverse-engineering documentation",
    "Anzeige-Farbschema für alle Kachel-Grafiken auf dieser Seite -- eine reine Darstellungsoption, keine ROM-Daten.":
      "Display color scheme for all tile graphics on this page -- a pure display preference, not ROM data.",
    "Farbschema für Kachel-Grafiken": "Color scheme for tile graphics",
    "📂 ROM laden…": "📂 Load ROM…",
    "Suche über Opcodes, Adressen und Begriffe": "Search opcodes, addresses, and terms",
    "Suche (Opcode, Adresse, Begriff)…": "Search (opcode, address, term)…",
    "Hauptnavigation": "Main navigation",
    // NOTE: the per-page footer sentence (app.js route()'s own
    // `footer.innerHTML`) is deliberately NOT translated here -- it's
    // multi-sentence explanatory prose, not structural chrome, and sits
    // right at this scope's own boundary (see the module doc comment
    // and this project's "top-level summaries stay German for now"
    // decision). It stays German-only like the rest of the site's prose.

    // --- GBPalette presets (js/rombytes.js) ---
    "Graustufen (Standard)": "Grayscale (default)",
    "DMG-Grün (Original Game Boy)": "DMG green (original Game Boy)",
    "Game Boy Pocket (reines S/W)": "Game Boy Pocket (pure B/W)",
    "Bernstein (Game Boy Light)": "Amber (Game Boy Light)",

    // --- page titles (h1.page-title) ---
    "Mystic Quest — ROM Inspector": "Mystic Quest — ROM Inspector",
    "Skript-Opcode-Explorer": "Script opcode explorer",
    "Whole-Corpus-Skript-Scan": "Whole-corpus script scan",
    "Bekannte, bereits kartierte Map-Kacheln": "Known, already-mapped tiles",
    "Grafik-Kandidaten (unbestätigt)": "Graphics candidates (unconfirmed)",

    // --- section titles (h2) ---
    "Felder": "Fields",
    "ROM-Eckdaten": "ROM key facts",
    "Skript-Opcode-Abdeckung": "Script opcode coverage",
    "Raum-Katalog": "Room catalog",
    "Bereiche": "Sections",
    "ROM-Banks": "ROM banks",
    "Bekannte WRAM-Zellen": "Known WRAM cells",
    "So funktioniert ein echtes Skript (Beispiel)": "How a real script works (example)",
    "Control-Code-Subsystem von Opcode 0x04 (Pinning)": "Opcode 0x04's control-code subsystem (pinning)",
    "Monster-Siegesmeldungen": "Monster victory messages",
    "Benannte Story-Figuren": "Named story characters",
    "Live-verifizierte, im Spiel verdrahtete Übergänge": "Live-verified, in-game-wired transitions",
    "Verwandter, noch unentschlüsselter Record-Typ": "Related, still-undecoded record type",
    "Live-Dekodierer": "Live decoder",
    "Referenz-Tabellen": "Reference tables",
    "Top-Blocker (Handler-Adressen, die die meisten Skripte aufhalten)":
      "Top blockers (handler addresses that stop the most scripts)",
    "Live-bestätigte Einträge": "Live-confirmed entries",

    // --- inline link fragments ---
    "→ Explorer": "→ Explorer",
    "→ Details": "→ Details",
    "→ Map-Viewer": "→ Map viewer",
    "→ Weltkarte": "→ World map",

    // --- stat-card labels ---
    "Erkannte Revision": "Detected revision",
    "Gesamtgröße": "Total size",
    "Mapper": "Mapper",
    "dekodiert & implementiert": "decoded & implemented",
    "bestätigtes No-Op": "confirmed no-op",
    "bekannt schwer / bewusst offen": "known-hard / deliberately open",
    "noch undekodiert": "still undecoded",
    "clean": "clean",
    "halt: undekodierter Opcode": "halt: undecoded opcode",
    "sonstiger Laufzeitfehler": "other runtime error",
    "strukturell dekodierte Katalog-Einträge": "structurally decoded catalog entries",
    "real verbundene Räume (Gameplay)": "really-connected rooms (gameplay)",
    "vollständig kartierte Räume": "fully mapped rooms",
    "Grafik-Kandidaten gesamt": "graphics candidates, total",
    "Monster-Kandidaten": "monster candidates",
    "NPC-Kandidaten": "NPC candidates",
    "Map-/Kachelset-Kandidaten": "map/tileset candidates",

    // --- table headers (th) ---
    "Offset": "Offset",
    "Feld": "Field",
    "Getter/Setter": "Getter/setter",
    "Bedeutung": "Meaning",
    "#": "#",
    "Name": "Name",
    "Kategorie": "Category",
    "ID": "ID",
    "Typ": "Type",
    "Kategorie-Byte": "Category byte",
    "Stat-Bytes (roh)": "Stat bytes (raw)",
    "Index": "Index",
    "allocParam": "allocParam",
    "spritePointer": "spritePointer",
    "ROM-Offset": "ROM offset",
    "Sub-Record ROM-Offset": "Sub-record ROM offset",
    "Adresse": "Address",
    "Beschreibung": "Description",
    "Event": "Event",
    "Vorkommen": "Occurrence",
    "Position bekannt?": "Position known?",
    "Rolle (aus echtem Dialog)": "Role (from real dialogue)",
    "roomSelector": "roomSelector",
    "Ziel-Familie": "Target family",
    "Landeposition (Tile)": "Landing position (tile)",
    "Landeposition (Pixel)": "Landing position (pixel)",
    "Vorkommen im Skript-Korpus": "Occurrences in script corpus",
    "Beispiel-ROM-Offset": "Example ROM offset",
    "Byte": "Byte",
    "Zeichen": "Character",
    "Zeichenpaar": "Character pair",

    // --- buttons / tabs ---
    "Schritt →": "Step →",
    "Zurücksetzen": "Reset",
    "▶ Abspielen (Kanal 1+2)": "▶ Play (channel 1+2)",
    "■ Stopp": "■ Stop",
    "Leeren": "Clear",
    "Dekodieren": "Decode",
    "Anzeigen": "Show",
    "Ansicht zurücksetzen": "Reset view",
    "Items & Zauber": "Items & spells",
    "Waffen & Rüstung": "Weapons & armor",
    "Alle": "All",
    "Pose A": "Pose A",
    "Pose B (gespiegelt)": "Pose B (mirrored)",
    "Phase 1": "Phase 1",
    "Phase 2": "Phase 2",
    "Hauptalphabet": "Main alphabet",
    "Umlaute": "Umlauts",
    "Steuerbytes": "Control bytes",

    // --- form labels / placeholders / aria-labels / titles ---
    "Filtern nach Adresse/Name…": "Filter by address/name…",
    "WRAM-Zellen filtern nach Adresse oder Name": "Filter WRAM cells by address or name",
    "Name oder Handler-Adresse…": "Name or handler address…",
    "Opcodes filtern nach Name oder Handler-Adresse": "Filter opcodes by name or handler address",
    "Hex-Bytes, z.B. B6 B0 BF ... 00": "Hex bytes, e.g. B6 B0 BF ... 00",
    "Hex-Bytes zum Dekodieren eingeben": "Enter hex bytes to decode",
    "Offset, z.B. 0x22B00": "Offset, e.g. 0x22B00",
    "ROM-Offset in Hex": "ROM offset in hex",
    "Anzahl": "Count",
    "Anzahl der Tiles": "Number of tiles",
    "Raum auswählen": "Select room",
    "Song auswählen": "Select song",
    "Skript-Beispiel auswählen": "Select script example",
    "Kartenquelle auswählen": "Select map source",
    "Tile-Quelle auswählen": "Select tile source",
  };

  function readStoredLang() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }
  function storeLang(l) {
    try { localStorage.setItem(STORAGE_KEY, l); } catch (e) { /* private mode etc. -- fine, just don't persist */ }
  }

  let lang = readStoredLang() === "en" ? "en" : "de";
  const listeners = [];

  function translateOne(original) {
    const trimmed = original.trim();
    if (!trimmed) return original;
    const hit = lang === "en" ? DICT[trimmed] : null;
    if (!hit) return trimmed === original ? original : (original.match(/^\s*/)[0] + trimmed + original.match(/\s*$/)[0]);
    const lead = original.match(/^\s*/)[0];
    const trail = original.match(/\s*$/)[0];
    return lead + hit + trail;
  }

  function applyTextNode(node) {
    if (node.__i18nOriginal === undefined) node.__i18nOriginal = node.nodeValue;
    const next = translateOne(node.__i18nOriginal);
    if (node.nodeValue !== next) node.nodeValue = next;
  }

  function applyAttr(el, attr) {
    const key = "__i18nOrig_" + attr;
    if (el[key] === undefined) {
      const cur = el.getAttribute(attr);
      if (cur === null) return;
      el[key] = cur;
    }
    const next = translateOne(el[key]);
    if (el.getAttribute(attr) !== next) el.setAttribute(attr, next);
  }

  // Walks `root` (a DOM element) and translates every exact-match text
  // node and translatable attribute under it, in place. Idempotent and
  // safe to call repeatedly (re-render, language toggle, both) -- see
  // the module doc comment for why originals are always recoverable.
  function apply(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const tag = node.parentNode && node.parentNode.nodeName;
        if (tag === "SCRIPT" || tag === "STYLE") return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const textNodes = [];
    let n;
    while ((n = walker.nextNode())) textNodes.push(n);
    textNodes.forEach(applyTextNode);

    const selector = ATTRS.map(a => `[${a}]`).join(",");
    root.querySelectorAll(selector).forEach(el => {
      ATTRS.forEach(a => { if (el.hasAttribute(a)) applyAttr(el, a); });
    });
    if (root.nodeType === 1) {
      ATTRS.forEach(a => { if (root.hasAttribute && root.hasAttribute(a)) applyAttr(root, a); });
    }
  }

  function setLang(l) {
    if (l !== "de" && l !== "en") return;
    if (l === lang) return;
    lang = l;
    storeLang(lang);
    document.documentElement.lang = lang;
    listeners.forEach(fn => fn(lang));
  }

  function onChange(fn) {
    listeners.push(fn);
    return () => { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); };
  }

  return {
    get current() { return lang; },
    setLang,
    onChange,
    apply,
    t: s => (lang === "en" && DICT[s]) || s,
  };
})();
