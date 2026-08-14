// Hand-curated (not auto-generated): every currently-open real question
// this reverse-engineering project has, condensed from
// docs/reverse-engineering/events.md, rom-map.md, and this project's own
// task list. Each entry links back to the concrete real ROM
// addresses/mechanisms involved, not a vague "TODO".
const OPEN_QUESTIONS = [
  {
    title: "Cross-actor dispatch mechanism ($31AD / $C3F0 / $C3FE / $C3FF)",
    area: "Script interpreter",
    description: "A shared dispatcher with 15 independent real call sites resolves which script a given actor/context should run, reading a WRAM record at $C3F0/$C3FE/$C3FF. The MECHANISM is confirmed; the record's own general schema (per-room? per-actor? something else?) is not. This is the concrete blocker for driving real NPC/story content from the interpreter instead of hand-authored cutscene code."
  },
  {
    title: "Boss-defeat sequence: real completion blocked by a queue-gate halt",
    area: "Script interpreter",
    description: "The boss-defeat story script's own opcode list is now almost fully decoded (only 0xBC/0xBD remain, both known-hard palette-fade family members). But a live headless shadow-run shows it gets stuck almost immediately on opcode 0x00 (a real conditional halt on the script continuation queue) because no CHAIN populated the queue first in a single synchronous burst -- the real release condition genuinely depends on passage of real game time this project's one-shot shadow run can't reproduce."
  },
  {
    title: "No real camera-scroll rendering (engine-wide, found via fourthRoom's corridor)",
    area: "Room system",
    description: "RESOLVED 2026-08-14 that this was never a coordinate bug: fourthRoom's real 'cut' exit (to fifthRoom) already uses the correct trigger coordinates (this project's player.x/y IS the same raw-WRAM coordinate space the ROM itself uses, no translation needed). The real, general gap found instead: Field.lua has no camera-scroll implementation at all, so a real ROM room that scrolls before its own 'cut' fires (like fourthRoom's own west corridor) never gets its scrolled-past content rendered here. CORRECTED same day: that corridor was originally misread as a second real exit into a separate room ('sixthRoom') -- re-investigated under 'gamemap absolute prio' and retracted, it's further columns of fourthRoom's own single continuous room space (see rom_profiles.lua's own doc comments and sixth_room_test.lua). 20+ real, newly-decoded wall/border tiles from that corridor sit in rom_profiles.lua's fourthRoom.tileOffsets, documented but unused, waiting on this future scroll-camera feature."
  },
  {
    title: "Collision: willyRoom closed, most other rooms still a visual heuristic, not a decoded ROM fact",
    area: "Room system",
    description: "CLOSED for willyRoom specifically (2026-08-14): its real metatile collision byte's own bit rule was re-derived from scratch (cross-tabulated against live-movement-tested ground truth, all 320 real grid cells, zero exceptions) -- collision==0x30 means floor in willyRoom's own table, the OPPOSITE polarity from fourthRoom/unknownRoomA's table (confirming collision semantics are set per metatile TABLE, not fixed ROM-wide). Wired in as willyRoom's real live collision, proven behavior-preserving both headlessly and via a live love . movement test. Still open: secondRoom/thirdRoom likely extend the SAME metatile table (2 real indices already found past willyRoom's own last entry) but aren't wired yet; fourthRoom/fifthRoom/sixthRoom/startRoom have no known metatile source of their own at all; unknownRoomA/unknownRoomB have real collision bytes but no live-movement ground truth is possible there (no gameplay ever reaches them), so their own rule stays unverified extrapolation."
  },
  {
    title: "The real cross-bank CHAIN mystery",
    area: "Script interpreter",
    description: "7 real scripts CHAIN (opcode 0x02) to a cursor address that would fall in a DIFFERENT bank than the one currently mapped -- the real bank-switch mechanism that must accompany those specific jumps hasn't been found."
  },
  {
    title: "Audio format: completely unknown",
    area: "Audio",
    description: "No format investigation has produced a working theory yet -- lowest priority of the project's own open items, but a total gap (not even a partial byte-shape hypothesis)."
  },
  {
    title: "Opcodes 0xA0/0xA1: real bank-1 targets never traced",
    area: "Script interpreter",
    description: "Both delegate through the already-mapped $1ED7 dispatcher (selectors 9 and 0x0A) to real bank-1 addresses $5136/$5156 -- confirmed live but genuinely new, un-disassembled territory. 0xA1 alone blocks 10 real scripts in the whole-corpus scan."
  },
  {
    title: "The palette-fade family's exact fade curve (0xBC / 0xBD)",
    area: "Script interpreter",
    description: "Both real handlers read two shared gradient lookup tables ($101A/$1030) indexed by the $D499/$D49A phase counter -- the mechanism is traced, but the tables' own real content hasn't been decoded into an exact per-frame fade curve, and 0xBD additionally calls a further untraced leaf ($1142)."
  },
  {
    title: "Text digraph table: ~15 more repeating low-byte codes uncross-checked",
    area: "Text decoding",
    description: "A full-ROM scan found many more repeating low-byte values (0x25, 0x28, 0x2B, 0x33, 0x44, 0x46, 0x4A, 0x53, 0x64, 0x69, 0x6A, 0x87, 0xA9, ...) that are almost certainly more digraphs, several contextually guessable, but none cross-checked against a second independent occurrence yet -- this project's own bar for calling a byte VERIFIED."
  },
  {
    title: "Control byte 0xF6: HYPOTHESIS only, not verified",
    area: "Text decoding",
    description: "Appears exactly where the known HUD text needs a numeric value inserted (\"LP [F6] MP [F6]\") -- reads as a real substitution opcode, not a printable glyph, but not independently cross-checked a second way yet."
  },
  {
    title: "scriptPointerTable's 3 special-cased index values (0x0B / 4 / 8)",
    area: "Script interpreter",
    description: "These 3 small index values redirect to fixed WRAM addresses instead of the normal ROM table lookup (some scripts are WRAM-resident, not ROM data) -- the mechanism is confirmed but their real-world meaning is not."
  },
  {
    title: "Bank 7's 'Templated' room-compression format",
    area: "Room system",
    description: "A genuinely different room-data compression scheme from every other bank's format -- not yet reverse-engineered."
  },
  {
    title: "The $413C cut-sequence table: only 2 of 30 steps decoded",
    area: "Room system",
    description: "Step 3 (room load) and step 5 (position set) are understood; the other 28 steps of this shared cut-transition state machine are not."
  },
  {
    title: "Enemy DEF formula: two candidate WRAM fields, neither confirmed live",
    area: "Combat",
    description: "The enemy species table's ATK field is VERIFIED via a live cross-check; DEF has two real candidate byte fields but neither has been confirmed against an actual live combat trace yet. Two specific leads are now ruled out (2026-08-12, and 2026-08-14's own bank-4 $4466 entity-command dispatcher trace, which turned out to be a real positioning/movement command family, not stat-reading) without a replacement found. HP's own real spawn-time roll formula (rollHP in CombatFormulas.lua) WAS found and implemented this same pass, but deliberately left unwired pending the real n=0 edge case the ROM itself branches on differently."
  },
  {
    title: "$1ED7 / $1F35 dispatcher families: remaining unmapped selectors",
    area: "Script interpreter",
    description: "UPDATED 2026-08-14: the $1F35 family's own read side is now traced end to end -- selector 0x0E ($4B4F) periodically scans the $C5A0 known-list and, via a per-entry helper ($4B19) and a real per-record tick handler ($404A), consumes what selector 0x0A/$4B70 writes (countdown/reload timers, a group-based branch, a further gated helper $4107). Selector 0x07 (previously unclassified) is now known to be its own separate small dispatcher. Still open: the exact real-world MEANING of the 8 action-code values themselves (0x04/0x05/0x0E/0x0F/0x1C/0x1D/0x1E/0x1F) -- two independent live-trace attempts at a real boss-defeat quest-flag moment both came back negative -- plus selectors 0x0B/0x0C/0x0D/0x0F's own deeper helper leaves ($0611/$0695/$08D4/$05EF/$3DCB/$24A7) and $1ED7's own selector range, neither re-visited this pass."
  },
  {
    title: "EntityStructLayout ($C200): 2 new fields found, most still unnamed by real-world meaning",
    area: "Combat / entity system",
    description: "2026-08-14: the whole $0C41-$0D1B getter/setter accessor block for this struct was found and mapped (see the Entity-Struktur page), revealing 2 fields beyond the previously-known 0-8 range (offsets +10/+11) with real getters/setters and real callers, plus evidence PARAM6/PARAM7 (+6/+7) are used as ONE paired 16-bit value by at least one real caller, not two independent bytes. PARAM2 (+2) is confirmed as the single most heavily-used accessor found anywhere in this struct (24+17 real callers, every ROM bank) and bridges directly to the $C4E0 actor-command array's own slot-scan code. A live-tested hypothesis that TYPE (+1) held a dynamic, attack-related per-frame state was RETRACTED the same day (mGBA watchpoints + a direct 600,000-step execution check both came back negative -- the 3 real static call sites exist, but the code containing them is never reached during a normal attack). Open: the real-world meaning of +10, +11, PARAM2, and TYPE's own real 3 call sites, if not attack-related."
  },
];
