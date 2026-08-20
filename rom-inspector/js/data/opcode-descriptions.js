// Hand-curated (not auto-generated): human-readable descriptions for
// every real opcode FAMILY this project has decoded, keyed by the
// BASE constant name pattern from ScriptOpcodeTable.lua (the trailing
// `_XX` opcode-byte suffix, if any, is stripped before lookup -- see
// `lookupOpcodeDescription()` below). Condensed from this project's
// own StandardScriptHandlers.lua doc comments and ScriptRuntime.lua's
// own `ctx.*` field documentation -- every claim here has a real
// disassembly behind it in the main codebase, this is just the
// human-readable summary.
//
// TWO LEVELS ON PURPOSE (added 2026-08-15, direct user feedback: "die
// optcodes seite... ist sehr kryptisch. vor allem die beschreibnbenden
// texte"): `summary` is ONE plain-language sentence -- what the opcode
// DOES in the game, no hex addresses, no jargon, readable without any
// Game Boy reverse-engineering background. `text` is the original,
// full technical writeup (real addresses, WRAM cells, byte-exact
// evidence) -- kept in full, not trimmed, just moved to a secondary,
// visually de-emphasized spot in the UI (see js/viz/opcodes.js's own
// `showOpcodeDetail`) so a casual reader gets the plain sentence first
// and the deep evidence stays one click away for anyone who wants it.
// Every `summary` is a genuine, honest simplification of the SAME real
// facts `text` documents -- never a guess beyond what `text` already
// establishes.
const OPCODE_DESCRIPTIONS = {
  DEFAULT_HANDLER_ADDRESS: {
    title: "No-Op",
    summary: "Tut nichts -- ein Platzhalter-Opcode, der sofort übersprungen wird.",
    text: "Bestätigter echter Leerlauf-Opcode: liest keine Operanden, macht keinen Seiteneffekt, läuft sofort weiter.",
  },
  QUEUE_GATE_HANDLER_ADDRESS: {
    title: "Queue-Gate (0x00)",
    summary: "Pausiert das Skript, bis eine interne Warteliste etwas zu erledigen hat.",
    text: "Hält an, solange die reale Skript-Fortsetzungs-Queue (ein WRAM-FIFO) leer ist, ODER solange ein reales Flag-Bit ($D874 Bit 0) gesetzt ist. Ein Eintrag aus CHAIN (0x02) oder dem Typewriter-Kommando (0x03) gibt frei -- entweder mit Sprung zur gemerkten Position oder als reiner Weiterlauf. UPDATE 2026-08-14 (Task #86, live mGBA-Trace): der reale ~1,7-Sekunden-Boss-Defeat-Block, der früher diesem Bit-0-Gate zugeschrieben wurde, ist tatsächlich ein KOMPLETT ANDERER Mechanismus -- ein periodischer Flanken-Detektor ($1F35 Selector 0x13 -> $4BE0, gecacht bei $C5AF), der erst feuert, sobald der Actor-Slot des besiegten Gegners wirklich fertig despawnt ist, und dann direkt den persistenten Skript-Cursor überschreibt ($24A7 -> $31AD, Task #85) -- nicht über dieses Gate. Bit 0 selbst ist real, gattert aber vermutlich etwas anderes.",
  },
  SKIP_HANDLER_ADDRESS: {
    title: "Relativer Sprung (0x01)",
    summary: "Springt im Skript ein paar Bytes nach vorne, wie ein „goto“.",
    text: "Liest ein Operand-Byte und addiert es auf den Cursor -- ein echtes „springe N Bytes vorwärts“, die einfachste reale Flusskontrolle in diesem Format.",
  },
  CHAIN_HANDLER_ADDRESS: {
    title: "CHAIN (0x02)",
    summary: "Springt zu einer ANDEREN Stelle im Skript, z. B. zur nächsten Dialogseite.",
    text: "Liest einen 16-Bit-Zeiger aus dem Stream und springt den Cursor dorthin -- z.B. „nächste Seite dieser Nachricht“. Reale Bank-übergreifende Ziele sind nicht aus einer Formel ableitbar, nur aus konkret bekannten Szenen.",
  },
  TICK_HANDLER_ADDRESS: {
    title: "Text-/Steuercode-Klassifizierer (0x04)",
    summary: "Steuert den Schreibmaschinen-Effekt: zeigt Dialogtext Buchstabe für Buchstabe an und erkennt dabei eingebettete Sonderbefehle (Zeilenumbruch, Pause, Name einfügen).",
    text: "UPDATE 2026-08-15 (voller Disassembly-Nachweis, echter Codewechsel): kein einfacher parameterloser Tick, sondern ein echter PRO-BYTE-KLASSIFIZIERER ($333D) -- liest das Byte an der aktuellen Cursor-Position und verzweigt: reales Terminator-Byte 0x00 (Textlauf zu Ende, sofortiger Weiterlauf), echter Steuercode 0x10-0x1F (Dispatch über eine reale Sprungtabelle bei $38F6 -- siehe „0xFF-Subtabelle” unten, dieselbe Maschine), oder ein echtes druckbares Textzeichen (getaktet mit der real gemessenen 5-Frame-Kadenz, der Typewriter-Reveal). Steuercode 0x11 pausiert dabei zusätzlich 9 echte Frames lang (WRAM $D853 Bit 7, live mGBA-Trace bestätigt) und springt danach über eine reale $36D0-Brücke ein Byte weiter, bevor der Klassifizierer erneut einsteigt. Dieser volle Mechanismus ist inzwischen in StandardScriptHandlers.tick als echter, bytegenauer Nachbau implementiert (nicht nur dokumentiert) und im Boss-Defeat-Shadow-Run live bestätigt: der Cursor folgt dem echten ROM bytegenau bis 0x61d8 (echtes HEAL_LP). UPDATE 2026-08-15, weiter: die Palette-Fade-Familie (0xBC/0xBD/0xBE, siehe eigener Eintrag) ist inzwischen ebenfalls verdrahtet -- der Cursor kommt jetzt noch weiter (dispatcht 0xBD alle echten 66 Male, erreicht Opcode 0xF3), stößt dort aber auf eine NEUE, echte Lücke (0xF3's eigener, nicht nachgebildeter $1ED7-Selector-0x10-Seiteneffekt) und landet wieder beim altbekannten 0x4798.",
  },
  MESSAGE_HANDLER_ADDRESS: {
    title: "Nachricht anzeigen (0xFE)",
    summary: "Zeigt eine bestimmte, fest vorgegebene Dialog-/Textbox an.",
    text: "Liest ein messageID-Byte, löst die reale Dialogadresse auf (siehe messageTextPointer) und zeigt den echten Text an.",
  },
  HEAL_LP_HANDLER_ADDRESS: {
    title: "LP auf Maximum heilen",
    summary: "Füllt die Lebenspunkte (LP) des Spielers vollständig auf.",
    text: "Setzt die aktuellen Lebenspunkte auf ihr Maximum.",
  },
  HEAL_MP_HANDLER_ADDRESS: {
    title: "MP auf Maximum heilen",
    summary: "Füllt die Magiepunkte (MP) des Spielers vollständig auf.",
    text: "Setzt die aktuellen Magiepunkte auf ihr Maximum.",
  },
  FLAG_SET_HANDLER_ADDRESS: {
    title: "Flag-Bit setzen (0xDC)",
    summary: "Setzt einen internen Merker (\"Schalter\"), z. B. \"dieses Ereignis ist schon passiert\".",
    text: "SET 1,(WRAM $D874) -- setzt Bit 1 eines echten Mehrzweck-Flag-Bytes.",
  },
  FLAG_CLEAR_HANDLER_ADDRESS: {
    title: "Flag-Bit löschen (0xDD)",
    summary: "Löscht denselben Merker wieder, den FLAG_SET setzt.",
    text: "RES 1,(WRAM $D874) -- löscht dasselbe Bit, das FLAG_SET setzt.",
  },
  TYPEWRITER_COMMAND_HANDLER_ADDRESS: {
    title: "Typewriter-Cursor-Kommando (0x03)",
    summary: "Ein Steuerbefehl innerhalb der Schreibmaschinen-Textanzeige (genaue Wirkung noch nicht vollständig geklärt).",
    text: "2 Operand-Bytes: das erste ist ein echter Kommandowert (Bedeutung nicht abschließend dekodiert), das zweite wird real gelesen, aber vom ROM selbst nie ausgewertet.",
  },
  START_TEXTBOX_WAIT_HANDLER_ADDRESS: {
    title: "Textbox-Wait starten",
    summary: "Lässt das Skript warten, bis eine Textbox fertig angezeigt wurde, bevor es weitergeht.",
    text: "Startet das reale Warten auf das Ende einer Textbox-Anzeige (Gate für 0xF0/0xFF).",
  },
  SUBTABLE_DISPATCH_HANDLER_ADDRESS: {
    title: "0xFF-Subtabelle",
    summary: "Ein zweites, eigenständiges Befehlssystem speziell für Formatierungs-Codes MITTEN im Text (Zeilenumbruch, Namen einfügen, Text-Cursor bewegen).",
    text: "Zweite, eigenständige Dispatch-Tabelle (11 Einträge, Bank 0, $3BAC), indiziert über ein eigenes WRAM-Register ($D86B) statt des primären „aktueller Opcode“-Bytes. UPDATE 2026-08-15: dieselbe Maschine wie die reale $38F6-Steuercode-Tabelle, die Opcode 0x04's Klassifizierer für Bytes 0x10-0x1F anspringt (siehe „Text-/Steuercode-Klassifizierer” oben) -- beide wurden unabhängig voneinander in verschiedenen Sessions disassembliert und erst nachträglich als EIN reales System erkannt (der „multi-line textbox driver”). Bytes 0x14/0x15 sind der reale Namens-Einfügemechanismus (zwei WRAM-Stringpointer, $D79D/$D7A2) -- sehr wahrscheinlich der lange gesuchte „[0x14]”-Sprecher-Tag. Bytes 0x1C-0x1F sind der bereits dokumentierte Cursor-Delta-Dispatcher (Text-Cursor hoch/runter/links/rechts). Byte 0x1A deckt sich exakt mit TextDecoder.lua's unabhängig hergeleitetem NEWLINE_BYTE=0x1A.",
  },
  ACTOR_ACTION_HANDLER_ADDRESS: {
    title: "Actor-Action-Familie",
    summary: "Lässt eine Spielfigur (NPC oder Gegner) eine vorprogrammierte Aktion ausführen, z. B. sich bewegen.",
    text: "14 reale Opcodes, jeder mit einer FESTEN, in die Handler-Adresse eingebackenen „Aktionsgruppe“, die in einen gemeinsamen Dispatcher ($2879) einläuft. Wartet ggf. bis der Akteur bereit ist (echtes $C5A0-Gate).",
  },
  QUEUED_ACTION_HANDLER_ADDRESS: {
    title: "Queued-Action-Familie",
    summary: "Wie Actor-Action, reiht die Aktion aber erst in eine Warteliste ein statt sie sofort auszuführen.",
    text: "6 reale Opcodes (0x18/28/38/48/58/78) -- reiht eine Aktion ein, gleiches Bereitschafts-Gate wie die Actor-Action-Familie.",
  },
  ACTOR_SLOT_POSITION_HANDLER_ADDRESS: {
    title: "Actor-Slot-Position setzen",
    summary: "Versetzt eine Spielfigur direkt an eine bestimmte X/Y-Position im Raum, ohne Animation.",
    text: "5 reale Opcodes (0x19/29/39/49/59), alle über denselben realen $123E-Mechanismus -- setzt die Position eines Akteur-Slots aus 2 rohen Operand-Bytes.",
  },
  TRIGGER_EVENT_HANDLER_ADDRESS: {
    title: "Trigger-Event-Familie",
    summary: "Löst ein internes Spielereignis aus (z. B. eine Szene, einen Kampf oder einen Effekt).",
    text: "Eine große, generisch registrierte Familie realer „löse System-Event N aus“-Opcodes, ohne Operand-Byte -- feuert sofort. 0xFC/0xFD gehören strukturell zu dieser Dispatch-Familie, haben aber eine eigene, konkret entschlüsselte Bedeutung -- siehe deren eigene Einträge.",
  },
  TRIGGER_EVENT_HANDLER_ADDRESS_FC: {
    title: "sSET_NPC_TYPES -- NPC/Monster-Zeile auswählen",
    summary: "Wählt eine Zeile in der echten NPC-/Monster-Spawn-Tabelle aus (109 Zeilen, je 3 Spalten) -- der erste von zwei Schritten, um eine Kreatur ins Spiel zu setzen.",
    text: "GEFUNDEN 2026-08-20 (externe FFA-Disassembly gezielt nach Encounter-/Spawn-Code durchsucht, nicht nur nach Boss-Werten): dieser Opcode ist das reale <code>sSET_NPC_TYPES &lt;row&gt;</code> -- er staged eine Zeilen-Nummer (0-108) in echtem WRAM ($C5AE), gelesen aus der echten <code>NPCSpawnPointers</code>-Tabelle (Bank 3, CPU $7142, byte-identisch zur US-Cartridge -- siehe src/import/NpcSpawnTable.lua). Reales Dual-WRAM-Gate ($C8E0/$CEE8, ROM->VRAM-DMA-Warteschlangentiefe) wie die restliche Trigger-Event-Familie. LIVE BESTÄTIGT: ein 2-Byte-ROM-Patch, der einen bereits real feuernden 0xFC/0xFD-Trigger umlenkte, brachte eine zweite, sichtbare, kämpfbare Kreatur ins laufende Spiel (Willy-Zimmer -&gt; Goblin) -- siehe docs/reverse-engineering/events.md, 2026-08-20 „SOLVED&quot;-Eintrag.",
  },
  TRIGGER_EVENT_HANDLER_ADDRESS_FD: {
    title: "sSPAWN_NPC -- Spalte spawnen",
    summary: "Erzeugt tatsächlich eine Kreatur aus der zuvor per sSET_NPC_TYPES gewählten Zeile -- welche der 3 Spalten, sagt das Operand-Byte.",
    text: "Das reale <code>sSPAWN_NPC &lt;col&gt;</code>, Gegenstück zu 0xFC. Löst die reale Spawn-Kette aus: NPCSpawnPointers[row][col] -&gt; echte Zufallsauswahl (Kampf-PRNG $2B1E + 8x8-&gt;16-Multiplikation $2B7B, dieselbe Routine wie EnemyStatTable's HP-Formel) einer von 4 Kandidaten-IDs -&gt; echte Positions-/Zufallspositions-Liste -&gt; echte Entity-Alloc-Primitive $0A74 (dieselbe, die auch der bekannte Story-Boss benutzt). Eine rohe Ganz-ROM-Suche nach <code>CALL $0A74</code> fand genau 7 reale direkte Aufrufer -- diese Kette ist vollständig geschlossen nachgewiesen, nicht nur strukturell vermutet.",
  },
  SOUND_PARAM_HANDLER_ADDRESS: {
    title: "Sound-/Timing-Parameter",
    summary: "Setzt einen Parameter für die Musik-/Soundhardware -- welcher genau, ist musikalisch noch nicht entschlüsselt.",
    text: "1 Operand-Byte, geschrieben in echte Sound-/Timing-Hardwareregister (u.a. HRAM $FF90/$FF92) -- exakte musikalische Bedeutung nicht dekodiert.",
  },
  SOUND_PARAM_1_HANDLER_ADDRESS: {
    title: "Sound-Parameter 1",
    summary: "Derselben Familie wie Sound-/Timing-Parameter, ein zweiter, eigener Opcode dafür.",
    text: "Wie SOUND_PARAM, ein weiterer realer Handler derselben Familie.",
  },
  SOUND_PARAM_2_HANDLER_ADDRESS: {
    title: "Sound-Parameter 2",
    summary: "Derselben Familie wie Sound-/Timing-Parameter, ein dritter, eigener Opcode dafür.",
    text: "Wie SOUND_PARAM, ein weiterer realer Handler derselben Familie.",
  },
  WORD_COMMAND_HANDLER_ADDRESS: {
    title: "16-Bit-Wort-Kommando",
    summary: "Liest eine zusammengesetzte Zahl aus dem Skript und übergibt sie an eine interne Funktion.",
    text: "2 Operand-Bytes, little-endian zu einem 16-Bit-Wert kombiniert, ein Callback erhält den kombinierten Wert.",
  },
  BYTE_WORD_COMMAND_HANDLER_ADDRESS: {
    title: "Byte+Wort-Kommando (0xB0)",
    summary: "Wie das 16-Bit-Wort-Kommando, zusätzlich mit einem einzelnen Extra-Byte davor.",
    text: "1 einzelnes Byte gefolgt von einem 16-Bit-Wort -- beide an einen Callback übergeben.",
  },
  TWO_BYTE_COMMAND_HANDLER_ADDRESS: {
    title: "Zwei-Byte-Kommando",
    summary: "Liest zwei einzelne Werte aus dem Skript und übergibt sie unverändert an eine interne Funktion.",
    text: "2 Operand-Bytes, EINZELN (nicht zu 16 Bit kombiniert) an einen opaken Leaf-Callback übergeben -- verschiedene reale ROM-Ziele je nach konkretem Opcode, gleiche Form.",
  },
  GATED_BYTE_LEAF_HANDLER_ADDRESS: {
    title: "Gegatetes Byte-Leaf (0xD4/D6/D8)",
    summary: "Erhöht einen internen Zähler, aber nur wenn eine (noch nicht geklärte) Bedingung erfüllt ist.",
    text: "1 Operand-Byte (real inkrementiert), gegatet über Bit 1 von WRAM $D86F -- der Bit-GESETZT-Pfad ist nie live beobachtet und daher nicht modelliert.",
  },
  BYTE_LEAF_HANDLER_ADDRESS: {
    title: "Ungegatetes Byte-Leaf (0xD5/D7/D9)",
    summary: "Wie das gegatete Geschwister-Kommando, aber ohne Bedingung -- läuft immer sofort durch.",
    text: "Exakt dieselbe Form wie das gegatete Geschwister-Leaf, aber ohne das $D86F-Gate -- läuft immer sofort weiter.",
  },
  PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS: {
    title: "2-Byte-Peek-Gate (0xF3/0xF4)",
    summary: "Wartet auf eine Bedingung, OHNE dabei schon Skript-Daten zu verbrauchen -- ein ungewöhnlicher Sonderfall unter den Opcodes.",
    text: "Ein genuin ungewöhnlicher Opcode: „peekt“ 2 Bytes OHNE sie zu konsumieren, wartet auf ein WRAM-Gate ($D499==0), liest danach dieselben 2 Bytes erneut als nächsten echten Opcode. 0xF4 übergibt so die Kontrolle an die $413C-Cut-Sequenz-Maschine.",
  },
  WRAM_BIT_COMMAND_HANDLER_ADDRESS: {
    title: "WRAM-Bit setzen/löschen (0xB8/0xB9)",
    summary: "Setzt oder löscht einen einzelnen internen Schalter.",
    text: "Setzt bzw. löscht Bit 0 von WRAM $C3F1, feuert danach einen opaken Leaf-Callback, keine Operand-Bytes.",
  },
  DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS: {
    title: "Dual-Gate-Leaf (0xE8/0xE9)",
    summary: "Wartet auf dieselbe Bedingung wie die Trigger-Event-Familie, aktualisiert danach wiederholt Grafikkacheln.",
    text: "Hält an, solange dasselbe reale $C8E0/$CEE8-Dual-Gate wie 0xFC/0xFD geschlossen ist. Einmal offen: feuert bei JEDEM Aufruf einen echten VRAM-Tile-Pattern-Update-Leaf (nicht nur einmalig).",
  },
  TIMER_LIST_SEARCH_HANDLER_ADDRESS: {
    title: "Timer-Array + Listensuche (0x09/0x0A)",
    summary: "Verändert interne Zähler-Listen und durchsucht danach eine Liste nach einem bestimmten Wert.",
    text: "Inkrementiert/dekrementiert feste WRAM-Arrays ($D6E9/$D6DD/$D6C5) um feste Beträge (überspringt bereits „volle“ 0x80-Sentinel-Bytes), dann eine nullterminierte Byteliste gegen ein reales Ziel-Array durchsuchen.",
  },
  RUN_LIST_SEARCH_HANDLER_ADDRESS: {
    title: "Inline-Listensuche (0x0B/0x0C)",
    summary: "Durchsucht eine Liste, die direkt im Skript selbst steht (nicht separat im Speicher), nach einem bestimmten Wert.",
    text: "Durchsucht eine FLACHE Byteliste, die direkt IM Skript-Stream selbst liegt (nicht in WRAM), gegen ein externes WRAM-Byte ($D871), gegatet über Bit 7 von $D873 mit entgegengesetzter Polarität zwischen den beiden Opcodes.",
  },
  WAVE_OFFSET_EFFECT_HANDLER_ADDRESS: {
    title: "Wellen-Offset-Oszillator (0xFB)",
    summary: "Ein kosmetischer Wackel-Effekt (Sprite bewegt sich leicht wellenförmig) -- in diesem Projekt bisher nicht sichtbar umgesetzt.",
    text: "Bewegt WRAM $C0A6 bei jedem Aufruf um ±2 entlang einer echten Dreieckswelle (Periode 8) -- ein kosmetischer Sprite-Wobble-Effekt ohne Renderer-Anbindung in diesem Projekt.",
  },
  COLOR_PULSE_EFFECT_HANDLER_ADDRESS: {
    title: "2-Farben-Puls (0xBF)",
    summary: "Ein Blink-/Puls-Effekt, der zwischen zwei Farbwerten hin und her wechselt.",
    text: "Schreibt 5 Aufrufe lang ein „dunkles“ WRAM-Triple, dann 5 Aufrufe lang ein „helles“ -- ein klassischer Flash/Blink-Effekt, Teil der Palette-Fade-Familie.",
  },
  PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS: {
    title: "Spieler-Entity-TYPE schreiben (0x88/0x89)",
    summary: "Setzt einen internen Typ-Wert für die Spielfigur -- wofür dieser Wert genau gebraucht wird, ist noch offen.",
    text: "Schreibt einen festen Wert (2 bzw. 1) in das TYPE-Feld ($C241) des Spieler-Entity-Slots -- reale ROM-Bedeutung des Feldes selbst nicht weiter dekodiert.",
  },
  ACTOR_FLAG_LIST_HANDLER_ADDRESS: {
    title: "Nullterminierte Flag-Liste (0x08)",
    summary: "Prüft eine Liste von Bedingungen der Reihe nach durch -- wie eine echte Schleife innerhalb des Skripts.",
    text: "Eine echte bedingte Schleife: holt, testet, wiederholt oder fällt durch (gemeinsamer Helfer $35EF). Exakte reale Bedingung nicht vollständig dekodiert.",
  },
  PALETTE_FADE_HANDLER_ADDRESS: {
    title: "Palette-Fade-Familie (0xBC/0xBD/0xBE)",
    summary: "Steuert eine Farbüberblendung (Fade-Effekt) mit exakt bekanntem Timing -- WELCHE Farben dabei genau verwendet werden, ist noch offen.",
    text: "WIRED 2026-08-15 (kehrt die frühere „genuinely known-hard\"-Einschätzung vom 2026-08-14 um): alle drei Opcodes rufen denselben, jetzt vollständig disassemblierten Leaf $1142 auf -- ein echter, deterministischer 6x11=66-Tick-Pacing-Zähler auf WRAM $D499/$D49A, strukturell wie das bereits nachgebaute Steuercode-0x11-Pacing. Alle drei lesen NULL Operand-Bytes aus dem Skript-Stream. Die eigentliche Fade-FARBE (4 reale Lookup-Tabellen, $101A/$1030/$107B/$1091) bleibt wie bei 0xFB/0xBF ein optionaler, unverdrahteter Callback -- kein Rendering nötig, nur für den Cursor-Fortschritt reicht das Pacing. Live-Test: der Interpreter dispatcht 0xBD jetzt alle echten 66 Male und erreicht danach Opcode 0xF3 -- dort stößt er aber auf eine NEUE, echte Lücke (0xF3's eigener, unmodellierter $1ED7-Selector-0x10-Seiteneffekt) und landet wieder beim altbekannten Cursor 0x4798.",
  },
};

// A short glossary for the recurring technical jargon in the `text`
// fields above (added 2026-08-15, same user feedback as `summary`) --
// plain-language definitions for terms a reader without Game Boy
// reverse-engineering background won't know. Rendered as a collapsible
// box on the opcode page (see js/viz/opcodes.js's own `render_glossary`)
// and, for the SAME terms when they appear inside a `text` field, as an
// inline glow/hover -- see `glossarize()` below.
const OPCODE_GLOSSARY = [
  { term: "Opcode", def: "Ein einzelnes Byte im Skript, das sagt, WAS als nächstes passieren soll -- vergleichbar mit einem Befehlswort in einer Programmiersprache." },
  { term: "Handler", def: "Der Stück-Code (in der echten ROM UND in diesem Projekt), der für einen bestimmten Opcode tatsächlich zuständig ist und ihn ausführt." },
  { term: "WRAM", def: "\"Work RAM\" -- der Arbeitsspeicher des Game Boy, in dem das Spiel seinen aktuellen Zustand hält (Lebenspunkte, Position, Flags, ...). Adressen darin beginnen in diesem Projekt immer mit $C oder $D." },
  { term: "Operand-Byte", def: "Ein zusätzliches Datenbyte direkt NACH einem Opcode im Skript -- ein Parameter für den Befehl, z. B. \"welche Nachricht\" oder \"wie weit springen\"." },
  { term: "Cursor", def: "Die aktuelle Leseposition im Skript -- die Adresse des Bytes, das als Nächstes gelesen wird. Rückt normalerweise nach jedem Opcode weiter." },
  { term: "Bank", def: "Der Game Boy kann nur einen kleinen Speicherausschnitt gleichzeitig \"sehen\"; größere ROMs sind deshalb in umschaltbare 16-KB-Blöcke (\"Bänke\") aufgeteilt." },
  { term: "Gate", def: "Eine Bedingung, die ein Skript-Befehl abwartet, bevor er weiterläuft -- z. B. \"warte, bis eine Warteschlange leer ist\"." },
  { term: "Dispatch(er)", def: "Der Mechanismus, der anhand eines Wertes (z. B. des Opcode-Bytes) entscheidet, welcher konkrete Code-Abschnitt ausgeführt wird -- wie eine Weiche." },
  { term: "Callback", def: "Eine Funktion, die dieses Projekt von außen \"einhängen\" kann, um auf einen echten ROM-Seiteneffekt zu reagieren, dessen genaue Wirkung (noch) nicht nachgebaut ist." },
  { term: "Leaf", def: "Ein \"Blatt\"-Aufruf am Ende einer Befehlskette -- ein konkreter, oft noch nicht vollständig verstandener Seiteneffekt-Code in der echten ROM." },
  { term: "Sentinel-Byte", def: "Ein spezieller, reservierter Wert (z. B. 0x80 oder 0xFF), der NICHT als normale Daten gilt, sondern eine besondere Bedeutung hat, z. B. \"Liste zu Ende\"." },
  { term: "Pin / Pinning", def: "Ein Mechanismus, bei dem der Interpreter denselben Opcode über mehrere Durchläufe hinweg festhält (\"anpinnt\"), statt bei jedem Schritt neu zu entscheiden, welcher Opcode als Nächstes drankommt." },
];

// Match a constant name against the dictionary by stripping a trailing
// `_XX` opcode-byte suffix if the remaining prefix is a known key.
function lookupOpcodeDescription(names) {
  if (!names) return null;
  for (const name of names) {
    if (OPCODE_DESCRIPTIONS[name]) return OPCODE_DESCRIPTIONS[name];
    const stripped = name.replace(/_[0-9A-F]{1,2}$/, "");
    if (stripped !== name && OPCODE_DESCRIPTIONS[stripped]) return OPCODE_DESCRIPTIONS[stripped];
  }
  return null;
}
