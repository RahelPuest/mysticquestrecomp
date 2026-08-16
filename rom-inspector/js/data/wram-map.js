// Hand-curated (not auto-generated): a reference list of every WRAM
// cell this project's own reverse-engineering docs have identified so
// far, condensed from docs/reverse-engineering/*.md and this project's
// own source doc comments (EntityStructLayout.lua, ScriptOpcodeTable.lua,
// StandardScriptHandlers.lua, ScriptRuntime.lua). `status` mirrors this
// project's own VERIFIED / PARTIALLY VERIFIED / HYPOTHESIS / UNKNOWN
// labeling discipline -- see docs/reverse-engineering/rom-map.md for the
// full trace behind any entry marked VERIFIED.
const WRAM_MAP = [
  {
    address: "$C200-$C33F",
    name: "Entity slot struct array",
    status: "VERIFIED",
    description: "20 slots x 16 bytes (BASE=$C200, STRIDE=16). Fields: +0 ALIVE (0xFF=dead sentinel), +1 TYPE, +2 PARAM2, +3 PARAM3, +4 POSITION_Y, +5 POSITION_X, +6 PARAM6, +7 PARAM7, +8/+9 OAM_SHADOW_PTR. Confirmed via the real DESPAWN ($0AE3) and ALLOCATE ($0A74) routines, which both compute this exact address formula."
  },
  {
    address: "$C244/$C245",
    name: "Player POSITION_Y / POSITION_X",
    status: "VERIFIED",
    description: "Slot 4 of the entity struct (the confirmed player slot) -- live-traced via a real 'cut' room transition's own landing-position commit chain passing the literal value 4 as the entity slot index."
  },
  {
    address: "$C240",
    name: "Player ALIVE/state byte -- low nibble is a real facing bitmask",
    status: "VERIFIED",
    description: "Slot 4's FIELD.ALIVE byte (offset 0). CRACKED 2026-08-14: this is exactly what the long-standing 'known-hard' opcode 0x80 (and its $02AB leaf) reads. Low nibble is a one-hot facing direction (1=right, 2=left, 4=up, 8=down) -- live-traced across idle/movement/attack, decisively confirmed by idle=0x04 matching Player.DEFAULT_FACING='up'. Upper nibble varies with movement/attack sub-state but is masked away by every real reader (AND 0x0F)."
  },
  {
    address: "$C3F0 / $C3FE / $C3FF",
    name: "Cross-actor dispatch record",
    status: "UNKNOWN",
    description: "A real WRAM record read by a shared dispatcher ($31AD, 15 independent real call sites) that resolves which script a given actor/context should run. General schema (per-room? per-actor?) still open -- see 'open questions'."
  },
  {
    address: "$C3F1",
    name: "Generic WRAM bit flags (bit 0)",
    status: "VERIFIED",
    description: "Set/cleared by real opcodes 0xB8/0xB9. A different cell from $D874's own bit 1 used by 0xDC/0xDD."
  },
  {
    address: "$C4E0",
    name: "Third actor/object array",
    status: "PARTIALLY VERIFIED",
    description: "24-byte stride, distinct from the $C200 struct -- found tracing the bank-3 $1F35 trampoline family (opcodes 0x10-0x7B)."
  },
  {
    address: "$C5A0",
    name: "8-slot known/active ID list",
    status: "PARTIALLY VERIFIED",
    description: "A shared linear-search utility ($4B62) walks this list -- part of the same 0x10-0x7B 'mark actor/flag N as reached state V' family."
  },
  {
    address: "$C8E0 / $CEE8",
    name: "Dual trigger-event gate -- $C8E0 CRACKED 2026-08-16 (task #160)",
    status: "VERIFIED ($C8E0's own real meaning); $CEE8 still PARTIALLY VERIFIED",
    description: "Both cells checked together by opcodes 0xFC/0xFD (one-shot), 0xE8/0xE9 (repeating leaf), and $1ED7 selector 0x10's phases 1/3. $C8E0 is now fully understood, found via live mGBA read-watchpoints during real combat: it's the real queue depth of a ROM-to-VRAM tile-streaming DMA system (see the new '$C5E0 tile-transfer queue' entry below and rom-map.md's own 'the real graphics-loading mechanism' section for the full disassembly) -- these opcodes are literally waiting for pending graphics transfers to finish, not an opaque flag. $CEE8's own real meaning (a separate, still-unconfirmed cell) remains untraced."
  },
  {
    address: "$C5E0+",
    name: "Real ROM->VRAM tile-transfer work queue",
    status: "VERIFIED",
    description: "FOUND 2026-08-16 (task #160, live mGBA read-watchpoints + full disassembly of bank 0 $2D57-$2E31). 6 bytes/entry: {bankByte, pad, destAddrLo, destAddrHi, srcAddrLo, srcAddrHi}. Producer entries $2DF5 (append) and $2E45 (insert-at-front, found but genuinely never called anywhere in the ROM -- real dead code) take HL=source ROM address, DE=destination VRAM address, A=bank number. Consumer entry $2D57 (called every real VBlank, the ONLY static caller found, at $71) drains up to a real scanline-time-budgeted number of 16-byte tiles per call, switching the MBC2 bank per queue entry via the real $2100 convention before each unrolled copy loop. $C8E0 (see above) is this queue's own real depth counter."
  },
  {
    address: "$C8E1",
    name: "Tile-transfer-queue reentrancy guard",
    status: "VERIFIED",
    description: "FOUND 2026-08-16 (task #160), same disassembly as $C5E0 above. A transient busy flag (0=free, briefly 1=busy) guarding both the enqueue ($2DF5/$2E45) and dequeue ($2D57) entry points against real re-entrant calls -- distinct from $C8E0 (the queue depth) and from $CEE8 (a separate, unrelated cell the script-level gate opcodes also check)."
  },
  {
    address: "$D3A0",
    name: "Palette-fade mode flag",
    status: "PARTIALLY VERIFIED",
    description: "Opcode 0xBD ($1046) branches on whether this equals 0x7E to decide between writing its result to the pending-palette cell or to $D3A3."
  },
  {
    address: "$D3A3",
    name: "Alternate palette-fade write target",
    status: "PARTIALLY VERIFIED",
    description: "See $D3A0 above -- real target of opcode 0xBD's own write when the mode flag isn't 0x7E."
  },
  {
    address: "$D499",
    name: "Shared 'phase/step counter' scratch byte",
    status: "VERIFIED (mechanism); shared across multiple unrelated real consumers",
    description: "Reused by several genuinely different, non-concurrent mechanisms: the $413C cut-sequence table's own step index, opcode 0xFB's wave-offset oscillator (mod 64), and the 0xBC/0xBD/0xBF palette-fade family (paired with $D49A)."
  },
  {
    address: "$D49A",
    name: "Fade-family secondary byte",
    status: "PARTIALLY VERIFIED",
    description: "Paired with $D499 in the palette-fade index formula (opcode 0xBD); bit 0 also feeds that same index."
  },
  {
    address: "$D49B / $D4A3",
    name: "Sound/timing parameter cache",
    status: "PARTIALLY VERIFIED",
    description: "Written by real opcode 0xF8 alongside HRAM $FF90 -- reads as a real sound/timing parameter, exact meaning not decoded."
  },
  {
    address: "$D613 / $D623 / $D633",
    name: "3-member two-byte-command family",
    status: "PARTIALLY VERIFIED",
    description: "Stride 0x10, written by real opcodes 0xC9/0xCA's own twoByteCommand handlers."
  },
  {
    address: "$D6C5 (16B) / $D6DD (12B) / $D6E9 (6B)",
    name: "Fixed WRAM arrays for opcode 0x09/0x0A",
    status: "VERIFIED (mechanism)",
    description: "Incremented/decremented by fixed amounts (0x41/0x41/0x08), skipping any byte already at the 0x80 'maxed out' sentinel or already 0 -- see StandardScriptHandlers.timerListSearch's doc comment."
  },
  {
    address: "$D7C6",
    name: "Bit-field lookup for opcode 0x08's loop condition",
    status: "PARTIALLY VERIFIED",
    description: "Read by a shared helper ($35EF) that decides whether opcode 0x08's real conditional loop repeats or falls through. Exact plain-language trigger condition not pinned down."
  },
  {
    address: "$D85A",
    name: "Current opcode byte",
    status: "VERIFIED",
    description: "The primary interpreter's own 'what opcode is currently dispatched' register -- written by the general fetch primitive ($3727) on every real tick, and directly overwritten by a few opcodes' own exhaustion paths as a 'force the next opcode' convention."
  },
  {
    address: "$D86B",
    name: "Current sub-opcode byte",
    status: "VERIFIED",
    description: "A separate register for the real 0xFF sub-dispatch table (11 records, file $3BAC)."
  },
  {
    address: "$D79D / $D7A2",
    name: "Name-insertion string source slots",
    status: "PARTIALLY VERIFIED",
    description: "2026-08-15: two distinct real WRAM string-pointer slots, each cached into $D8AA/$D8AB by control bytes 0x14/0x15 respectively (opcode 0x04's own $38F6 control-code table), then bridged via $3C74 into the 0xFF sub-table's sub-opcode 1 -- very likely the real mechanism behind the long-flagged, never-decoded '[0x14]'-style speaker/name tag seen in the boss-defeat script's own text. The link from these two slots back to NameEntry.lua's own real save-format bytes has not yet been traced."
  },
  {
    address: "$D853",
    name: "Control-code pacing-active flag (bit 7)",
    status: "VERIFIED",
    description: "2026-08-15, live mGBA write-watchpoint trace: bit 7 is SET one real frame after opcode 0x04's classifier enters a real control-code byte (confirmed for byte 0x11), stays SET for a real, fixed 9-frame pacing window, then CLEARS on exactly the same real frame the persistent cursor ($D8B6/$D8B7) advances past that control byte. Control byte 0x11's own real handler ($34F4) checks this bit directly (RET NZ = still pacing, halt; bit clear = fall through to the real $36D0 'consume one more byte, re-enter classifier' bridge). Confirmed as a real, live-observed pacing signal, not a guess -- now implemented byte-exact in StandardScriptHandlers.tick's ctx.onControlCode contract."
  },
  {
    address: "$D86F",
    name: "Fade-active gate bit 1",
    status: "PARTIALLY VERIFIED",
    description: "Gates real opcodes 0xD4/0xD6/0xD8 -- the bit-SET path isn't modeled (never observed live), only bit-clear (\"never active\")."
  },
  {
    address: "$D870 / $D871 / $D873",
    name: "List-search bound / match byte / gate bit 7",
    status: "PARTIALLY VERIFIED",
    description: "$D870 is opcode 0x09's real fixed loop bound (7). $D871/$D873 are the real external match byte and gate cell for opcodes 0x0B/0x0C's runListSearch -- this project has no live simulation to supply real values for either."
  },
  {
    address: "$D874",
    name: "Multi-bit flag byte",
    status: "VERIFIED",
    description: "Bit 0 gates opcode 0x00's own conditional halt; bit 1 is set/cleared by opcodes 0xDC/0xDD."
  },
  {
    address: "$D8B6 / $D8B7",
    name: "Persistent cross-call script cursor cache",
    status: "VERIFIED",
    description: "The real ROM's own mirror of the interpreter's HL cursor between ticks -- this project's own ScriptRuntime just threads the cursor explicitly instead of storing it in WRAM. UPDATE 2026-08-16 (task #160 follow-up): CHAIN's own real handler ($32FE) writes its new target here, then immediately calls $2A0A (see the bank call-stack entries below) before releasing -- real, previously-unknown detail about CHAIN's own execution, part of the still-open cross-bank CHAIN investigation (task #81)."
  },
  {
    address: "HRAM $FF8A",
    name: "Bank call-stack index",
    status: "VERIFIED",
    description: "FOUND 2026-08-16 (task #160 follow-up, tracing CHAIN's own real bank-switch behavior). A real, general-purpose stack pointer (HRAM, not WRAM) into the $C000+ bank-number array below -- incremented by the real push routine ($29FB), decremented by the real pop routine ($2A0A). ~35 real call sites across bank 0 use this pair -- a previously-undocumented, project-wide 'remember which bank to return to' primitive, not specific to graphics or to CHAIN."
  },
  {
    address: "$C000+ (indexed by HRAM $FF8A)",
    name: "Bank call-stack array",
    status: "VERIFIED",
    description: "FOUND 2026-08-16 (task #160 follow-up). Each slot holds one real MBC2 bank number, pushed by $29FB (argument in A: push the bank, write it here, switch to it via the real $2100 convention) and consumed by $2A0A (pop: switch to whatever is now on top -- 'return to the previous bank') or $2A17 (peek, no switch -- the SAME routine the $C5E0 tile-transfer queue's own consumer calls to restore its bank after a transfer, see above). CHAIN's own handler calls the pop variant; whether this is what correctly resolves the real 7 cross-bank CHAIN targets (task #81) is not yet proven."
  },
  {
    address: "$D8B8-$D8BB",
    name: "BC/DE snapshot, gated on $D84A==6",
    status: "UNKNOWN",
    description: "A real save/restore mechanism ($3736/$374D) found adjacent to the $D499 wrap-skip primitive -- only lightly traced, real purpose not determined."
  },
];
