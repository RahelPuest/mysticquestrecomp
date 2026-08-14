// Hand-curated (not auto-generated): for every ROM bank that has NO
// entry in ROM_TABLES (rom-tables.js), a short, honest note on what
// this project's own reverse-engineering docs actually know about that
// bank -- distinct from "has a named, structured record table."
//
// WHY THIS EXISTS (2026-08-14, direct user question: "laut der website
// ist der Inhalt der meisten ROM-Bänke noch nicht kartiert. ist das
// so"): the bank-grid view's own "Inhalt nicht kartiert" tag used to
// fire for EVERY bank without a ROM_TABLES entry (11 of 16 banks) --
// technically about "no named table," but read, unqualified, as "we
// know nothing here," which a real grep across rom-map.md/events.md/
// combat.md immediately disproved for most of those 11: real,
// individually disassembled routines, VERIFIED tile-graphics regions,
// and confirmed dispatch tables exist in several of them, just never
// packaged as a ROM_TABLES-shaped record array. Only bank 10 turned up
// ZERO real mentions anywhere in this project's own docs -- genuinely
// unexplored, unlike the rest.
//
// `tier`: "explored" (real, specific, cited findings exist -- possibly
// incomplete, but not blank) or "unexplored" (no real finding cited
// anywhere in this project's own docs -- an honest gap, not "coming
// soon").
const BANK_NOTES = {
  1: {
    tier: "explored",
    note: "Extensively disassembled: the real scroll/tile-paint routine (loops over $051D, \"paint a tile strip\"), the $1ED7 cross-bank selector dispatcher's own bank-1 target, and a real \"every function start in bank 1\" jump table (file 0x21445+) have all been traced to specific, confirmed addresses. Not exhaustively mapped byte-for-byte, but far from blank."
  },
  3: {
    tier: "explored",
    note: "Home of the real \"actor flag/state\" primitive family this project's own combat/entity code depends on: the $C5A0 8-slot WRAM table search ($4B4F), the enemy-placement loops (a fixed-position walk and a randomized-placement loop that calls the noise-table PRNG), and the $1F35 selector dispatcher's own bank-3 targets are all confirmed, cited routines."
  },
  6: {
    tier: "explored",
    note: "Its first 16 words decode as a real dispatch-table structure. Also holds one of the general room-decode pipeline's own verified 64-record lookup tables (task #63, \"decode ANY room\") -- confirmed real, not a coincidental byte pattern, by rendering and cross-checking every one of its 64 records."
  },
  7: {
    tier: "explored",
    note: "Identified as holding a genuinely DIFFERENT room-data compression scheme (\"Templated\" rooms) from every other bank's format -- confirmed to exist and differ, but the format itself is not yet cracked (see the 'open questions' section). Known and flagged, not silently skipped."
  },
  9: {
    tier: "explored",
    note: "Reached via the $1F35-style selector dispatcher family ($1F93->bank 9) and holds part of the real creature-sprite graphics region (cross-checked against bank 8's own data during sprite-source disambiguation). Several confirmed real reference points, not a full map."
  },
  10: {
    tier: "unexplored",
    note: "Genuinely open: zero real, cited findings anywhere in this project's own reverse-engineering docs. The one bank where \"content not mapped\" is accurate as stated, not just \"no named table.\""
  },
  11: {
    tier: "explored",
    note: "Item/weapon icon graphics -- PARTIALLY VERIFIED directly in rom-map.md (its bottom rows render as small, distinct iconographic sprites matching the known item/weapon set)."
  },
  12: {
    tier: "explored",
    note: "VERIFIED environment tileset -- the real source of most room wall/floor/decoration graphics this project's own room renderer uses (willyRoom/secondRoom/thirdRoom/fourthRoom/fifthRoom/sixthRoom's own tileOffsets all point here, file range roughly 0x30000-0x34000). One of the most solidly understood banks in the whole ROM -- it just isn't a RECORD table, so it never got a ROM_TABLES entry."
  },
  13: {
    tier: "explored",
    note: "Confirmed (live, via direct MBC bank-register reads) to hold the boss-defeat story script's REAL runtime content -- BossSequenceInterpreter runs cleanly through its own start and a real mid-script bank-13->14 CHAIN jump."
  },
  14: {
    tier: "explored",
    note: "The boss-defeat sequence's real CHAIN target after bank 13 (confirmed live, 2000+ further real interpreter ticks with zero undecoded opcodes). Also holds real room-transition table records at specific cited file offsets (e.g. fourthRoom->fifthRoom at file 0x38C87)."
  },
  15: {
    tier: "explored",
    note: "ALL 830 real sound-register writes observed in this project's own live tracing came from bank 15 -- confirmed as the audio-data bank. The actual music-sequence FORMAT within it is still unknown (see the 'Audio format' open question) -- location confirmed, content format is not."
  },
};
