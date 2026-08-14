// Hand-curated (not auto-generated): human-readable descriptions for
// every real opcode FAMILY this project has decoded, keyed by the
// BASE constant name pattern from ScriptOpcodeTable.lua (the trailing
// `_XX` opcode-byte suffix, if any, is stripped before lookup -- see
// `descriptionForOpcode()` in js/viz/opcodes.js). Condensed from this
// project's own StandardScriptHandlers.lua doc comments and
// ScriptRuntime.lua's own `ctx.*` field documentation -- every claim
// here has a real disassembly behind it in the main codebase, this is
// just the human-readable summary.
const OPCODE_DESCRIPTIONS = {
  DEFAULT_HANDLER_ADDRESS: {
    title: "No-Op",
    text: "Bestätigter echter Leerlauf-Opcode: liest keine Operanden, macht keinen Seiteneffekt, läuft sofort weiter.",
  },
  QUEUE_GATE_HANDLER_ADDRESS: {
    title: "Queue-Gate (0x00)",
    text: "Hält an, solange die reale Skript-Fortsetzungs-Queue (ein WRAM-FIFO) leer ist, ODER solange ein reales Flag-Bit ($D874 Bit 0) gesetzt ist. Ein Eintrag aus CHAIN (0x02) oder dem Typewriter-Kommando (0x03) gibt frei -- entweder mit Sprung zur gemerkten Position oder als reiner Weiterlauf. UPDATE 2026-08-14 (Task #86, live mGBA-Trace): der reale ~1,7-Sekunden-Boss-Defeat-Block, der früher diesem Bit-0-Gate zugeschrieben wurde, ist tatsächlich ein KOMPLETT ANDERER Mechanismus -- ein periodischer Flanken-Detektor ($1F35 Selector 0x13 -> $4BE0, gecacht bei $C5AF), der erst feuert, sobald der Actor-Slot des besiegten Gegners wirklich fertig despawnt ist, und dann direkt den persistenten Skript-Cursor überschreibt ($24A7 -> $31AD, Task #85) -- nicht über dieses Gate. Bit 0 selbst ist real, gattert aber vermutlich etwas anderes.",
  },
  SKIP_HANDLER_ADDRESS: {
    title: "Relativer Sprung (0x01)",
    text: "Liest ein Operand-Byte und addiert es auf den Cursor -- ein echtes „springe N Bytes vorwärts“, die einfachste reale Flusskontrolle in diesem Format.",
  },
  CHAIN_HANDLER_ADDRESS: {
    title: "CHAIN (0x02)",
    text: "Liest einen 16-Bit-Zeiger aus dem Stream und springt den Cursor dorthin -- z.B. „nächste Seite dieser Nachricht“. Reale Bank-übergreifende Ziele sind nicht aus einer Formel ableitbar, nur aus konkret bekannten Szenen.",
  },
  TICK_HANDLER_ADDRESS: {
    title: "Tick (0x04)",
    text: "Pro-Tick-Pacing-Callback -- u.a. der reale Typewriter-Reveal (ein Buchstabe alle 5 GB-Frames).",
  },
  MESSAGE_HANDLER_ADDRESS: {
    title: "Nachricht anzeigen (0xFE)",
    text: "Liest ein messageID-Byte, löst die reale Dialogadresse auf (siehe messageTextPointer) und zeigt den echten Text an.",
  },
  HEAL_LP_HANDLER_ADDRESS: {
    title: "LP auf Maximum heilen",
    text: "Setzt die aktuellen Lebenspunkte auf ihr Maximum.",
  },
  HEAL_MP_HANDLER_ADDRESS: {
    title: "MP auf Maximum heilen",
    text: "Setzt die aktuellen Magiepunkte auf ihr Maximum.",
  },
  FLAG_SET_HANDLER_ADDRESS: {
    title: "Flag-Bit setzen (0xDC)",
    text: "SET 1,(WRAM $D874) -- setzt Bit 1 eines echten Mehrzweck-Flag-Bytes.",
  },
  FLAG_CLEAR_HANDLER_ADDRESS: {
    title: "Flag-Bit löschen (0xDD)",
    text: "RES 1,(WRAM $D874) -- löscht dasselbe Bit, das FLAG_SET setzt.",
  },
  TYPEWRITER_COMMAND_HANDLER_ADDRESS: {
    title: "Typewriter-Cursor-Kommando (0x03)",
    text: "2 Operand-Bytes: das erste ist ein echter Kommandowert (Bedeutung nicht abschließend dekodiert), das zweite wird real gelesen, aber vom ROM selbst nie ausgewertet.",
  },
  START_TEXTBOX_WAIT_HANDLER_ADDRESS: {
    title: "Textbox-Wait starten",
    text: "Startet das reale Warten auf das Ende einer Textbox-Anzeige (Gate für 0xF0/0xFF).",
  },
  SUBTABLE_DISPATCH_HANDLER_ADDRESS: {
    title: "0xFF-Subtabelle",
    text: "Zweite, eigenständige Dispatch-Tabelle (11 Einträge, Bank 0, $3BAC), indiziert über ein eigenes WRAM-Register ($D86B) statt des primären „aktueller Opcode“-Bytes.",
  },
  ACTOR_ACTION_HANDLER_ADDRESS: {
    title: "Actor-Action-Familie",
    text: "14 reale Opcodes, jeder mit einer FESTEN, in die Handler-Adresse eingebackenen „Aktionsgruppe“, die in einen gemeinsamen Dispatcher ($2879) einläuft. Wartet ggf. bis der Akteur bereit ist (echtes $C5A0-Gate).",
  },
  QUEUED_ACTION_HANDLER_ADDRESS: {
    title: "Queued-Action-Familie",
    text: "6 reale Opcodes (0x18/28/38/48/58/78) -- reiht eine Aktion ein, gleiches Bereitschafts-Gate wie die Actor-Action-Familie.",
  },
  ACTOR_SLOT_POSITION_HANDLER_ADDRESS: {
    title: "Actor-Slot-Position setzen",
    text: "5 reale Opcodes (0x19/29/39/49/59), alle über denselben realen $123E-Mechanismus -- setzt die Position eines Akteur-Slots aus 2 rohen Operand-Bytes.",
  },
  TRIGGER_EVENT_HANDLER_ADDRESS: {
    title: "Trigger-Event-Familie",
    text: "Eine große, generisch registrierte Familie realer „löse System-Event N aus“-Opcodes. 0xFC/0xFD sind die EINMALIGEN, Gate-gesteuerten Varianten (reales Dual-WRAM-Gate $C8E0/$CEE8); die übrigen Varianten feuern sofort.",
  },
  SOUND_PARAM_HANDLER_ADDRESS: {
    title: "Sound-/Timing-Parameter",
    text: "1 Operand-Byte, geschrieben in echte Sound-/Timing-Hardwareregister (u.a. HRAM $FF90/$FF92) -- exakte musikalische Bedeutung nicht dekodiert.",
  },
  SOUND_PARAM_1_HANDLER_ADDRESS: {
    title: "Sound-Parameter 1",
    text: "Wie SOUND_PARAM, ein weiterer realer Handler derselben Familie.",
  },
  SOUND_PARAM_2_HANDLER_ADDRESS: {
    title: "Sound-Parameter 2",
    text: "Wie SOUND_PARAM, ein weiterer realer Handler derselben Familie.",
  },
  WORD_COMMAND_HANDLER_ADDRESS: {
    title: "16-Bit-Wort-Kommando",
    text: "2 Operand-Bytes, little-endian zu einem 16-Bit-Wert kombiniert, ein Callback erhält den kombinierten Wert.",
  },
  BYTE_WORD_COMMAND_HANDLER_ADDRESS: {
    title: "Byte+Wort-Kommando (0xB0)",
    text: "1 einzelnes Byte gefolgt von einem 16-Bit-Wort -- beide an einen Callback übergeben.",
  },
  TWO_BYTE_COMMAND_HANDLER_ADDRESS: {
    title: "Zwei-Byte-Kommando",
    text: "2 Operand-Bytes, EINZELN (nicht zu 16 Bit kombiniert) an einen opaken Leaf-Callback übergeben -- verschiedene reale ROM-Ziele je nach konkretem Opcode, gleiche Form.",
  },
  GATED_BYTE_LEAF_HANDLER_ADDRESS: {
    title: "Gegatetes Byte-Leaf (0xD4/D6/D8)",
    text: "1 Operand-Byte (real inkrementiert), gegatet über Bit 1 von WRAM $D86F -- der Bit-GESETZT-Pfad ist nie live beobachtet und daher nicht modelliert.",
  },
  BYTE_LEAF_HANDLER_ADDRESS: {
    title: "Ungegatetes Byte-Leaf (0xD5/D7/D9)",
    text: "Exakt dieselbe Form wie das gegatete Geschwister-Leaf, aber ohne das $D86F-Gate -- läuft immer sofort weiter.",
  },
  PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS: {
    title: "2-Byte-Peek-Gate (0xF3/0xF4)",
    text: "Ein genuin ungewöhnlicher Opcode: „peekt“ 2 Bytes OHNE sie zu konsumieren, wartet auf ein WRAM-Gate ($D499==0), liest danach dieselben 2 Bytes erneut als nächsten echten Opcode. 0xF4 übergibt so die Kontrolle an die $413C-Cut-Sequenz-Maschine.",
  },
  WRAM_BIT_COMMAND_HANDLER_ADDRESS: {
    title: "WRAM-Bit setzen/löschen (0xB8/0xB9)",
    text: "Setzt bzw. löscht Bit 0 von WRAM $C3F1, feuert danach einen opaken Leaf-Callback, keine Operand-Bytes.",
  },
  DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS: {
    title: "Dual-Gate-Leaf (0xE8/0xE9)",
    text: "Hält an, solange dasselbe reale $C8E0/$CEE8-Dual-Gate wie 0xFC/0xFD geschlossen ist. Einmal offen: feuert bei JEDEM Aufruf einen echten VRAM-Tile-Pattern-Update-Leaf (nicht nur einmalig).",
  },
  TIMER_LIST_SEARCH_HANDLER_ADDRESS: {
    title: "Timer-Array + Listensuche (0x09/0x0A)",
    text: "Inkrementiert/dekrementiert feste WRAM-Arrays ($D6E9/$D6DD/$D6C5) um feste Beträge (überspringt bereits „volle“ 0x80-Sentinel-Bytes), dann eine nullterminierte Byteliste gegen ein reales Ziel-Array durchsuchen.",
  },
  RUN_LIST_SEARCH_HANDLER_ADDRESS: {
    title: "Inline-Listensuche (0x0B/0x0C)",
    text: "Durchsucht eine FLACHE Byteliste, die direkt IM Skript-Stream selbst liegt (nicht in WRAM), gegen ein externes WRAM-Byte ($D871), gegatet über Bit 7 von $D873 mit entgegengesetzter Polarität zwischen den beiden Opcodes.",
  },
  WAVE_OFFSET_EFFECT_HANDLER_ADDRESS: {
    title: "Wellen-Offset-Oszillator (0xFB)",
    text: "Bewegt WRAM $C0A6 bei jedem Aufruf um ±2 entlang einer echten Dreieckswelle (Periode 8) -- ein kosmetischer Sprite-Wobble-Effekt ohne Renderer-Anbindung in diesem Projekt.",
  },
  COLOR_PULSE_EFFECT_HANDLER_ADDRESS: {
    title: "2-Farben-Puls (0xBF)",
    text: "Schreibt 5 Aufrufe lang ein „dunkles“ WRAM-Triple, dann 5 Aufrufe lang ein „helles“ -- ein klassischer Flash/Blink-Effekt, Teil der Palette-Fade-Familie.",
  },
  PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS: {
    title: "Spieler-Entity-TYPE schreiben (0x88/0x89)",
    text: "Schreibt einen festen Wert (2 bzw. 1) in das TYPE-Feld ($C241) des Spieler-Entity-Slots -- reale ROM-Bedeutung des Feldes selbst nicht weiter dekodiert.",
  },
  ACTOR_FLAG_LIST_HANDLER_ADDRESS: {
    title: "Nullterminierte Flag-Liste (0x08)",
    text: "Eine echte bedingte Schleife: holt, testet, wiederholt oder fällt durch (gemeinsamer Helfer $35EF). Exakte reale Bedingung nicht vollständig dekodiert.",
  },
};

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
