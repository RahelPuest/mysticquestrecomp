-- Centralized registry of ROM-version-specific layout knowledge.
--
-- Per the project's engineering rule "keep ROM-version-specific knowledge
-- separate from generic runtime systems" (see docs/architecture.md and
-- gen1recomp's manifest/symbol pattern analyzed in
-- docs/gen1recomp-analysis.md), nothing outside this file should hardcode a
-- bank number or byte offset for a specific ROM revision. A profile is
-- looked up by SHA-1 (RomIdentity.identify(data).sha1) so importing the
-- wrong revision fails loudly instead of silently misreading bytes.
--
-- Every offset recorded here must trace back to a VERIFIED or PARTIALLY
-- VERIFIED entry in docs/reverse-engineering/rom-map.md -- this file is
-- the machine-readable side of that document, not a separate source of
-- truth. When rom-map.md's confidence for a region changes, update both.

local RomProfiles = {}

-- `unknownRoomA`'s real 6 rooms (roomSelectors 8-13, see
-- `roomFloorLayoutPipeline.unknownRoomACandidates` below for the full
-- VERIFIED reasoning chain) -- BUILT IN as real, walkable content
-- (2026-08-12, direct instruction "du kannst das gerne einbauen").
-- Generated once via a one-off script chaining this project's own
-- already-VERIFIED formulas (bank5 record N = roomSelector N's layout
-- stream; `RoomFloorLayout.decodeLayoutStream`/`readMetatile`;
-- `tilesetFileOffset=0x32000+tileId*16`) -- the exact same pipeline
-- `tools/graphics/render_unknown_room_a.py` already used to render and
-- visually confirm these rooms, just emitting Lua table literals
-- instead of PNGs. All 6 rooms share one tileset region, so both
-- lookup tables below are defined ONCE and referenced by all 6 flat
-- `graphics.unknownRoomA_<n>` entries (see `graphics` table further
-- down) -- avoids repeating an 82-entry table 6 times over.
--
-- `UNKNOWN_ROOM_A_TILE_OFFSETS`: real per-tile ROM byte offsets, same
-- convention/formula as every other room's own `tileOffsets`
-- (`0x32000 + tileId*16`, MapTable.lua's own already-VERIFIED formula).
local UNKNOWN_ROOM_A_TILE_OFFSETS = {
  [0] = 0x32000, [1] = 0x32010, [2] = 0x32020, [3] = 0x32030, [4] = 0x32040,
  [5] = 0x32050, [6] = 0x32060, [7] = 0x32070, [18] = 0x32120, [19] = 0x32130,
  [20] = 0x32140, [21] = 0x32150, [22] = 0x32160, [23] = 0x32170, [24] = 0x32180,
  [25] = 0x32190, [26] = 0x321A0, [27] = 0x321B0, [28] = 0x321C0, [29] = 0x321D0,
  [30] = 0x321E0, [33] = 0x32210, [35] = 0x32230, [36] = 0x32240, [37] = 0x32250,
  [38] = 0x32260, [39] = 0x32270, [40] = 0x32280, [41] = 0x32290, [42] = 0x322A0,
  [43] = 0x322B0, [48] = 0x32300, [50] = 0x32320, [51] = 0x32330, [52] = 0x32340,
  [53] = 0x32350, [56] = 0x32380, [57] = 0x32390, [58] = 0x323A0, [59] = 0x323B0,
  [64] = 0x32400, [66] = 0x32420, [72] = 0x32480, [73] = 0x32490, [74] = 0x324A0,
  [75] = 0x324B0, [77] = 0x324D0, [80] = 0x32500, [81] = 0x32510, [84] = 0x32540,
  [85] = 0x32550, [92] = 0x325C0, [93] = 0x325D0, [94] = 0x325E0, [95] = 0x325F0,
  [96] = 0x32600, [97] = 0x32610, [100] = 0x32640, [101] = 0x32650, [108] = 0x326C0,
  [109] = 0x326D0, [110] = 0x326E0, [111] = 0x326F0, [112] = 0x32700, [113] = 0x32710,
  [114] = 0x32720, [115] = 0x32730, [124] = 0x327C0, [125] = 0x327D0, [126] = 0x327E0,
  [127] = 0x327F0, [163] = 0x32A30, [166] = 0x32A60, [198] = 0x32C60, [199] = 0x32C70,
  [204] = 0x32CC0, [205] = 0x32CD0, [206] = 0x32CE0, [207] = 0x32CF0, [212] = 0x32D40,
  [213] = 0x32D50, [254] = 0x32FE0,
}
-- `UNKNOWN_ROOM_A_FLOOR_TILE_IDS`: HYPOTHESIS, but real-data-grounded
-- (a materially stronger basis than the pure visual "repeated tile =
-- floor" guess used for e.g. `graphics.fourthRoom.floorTileIds`): each
-- metatile record's own real 5th byte (`collision`, per
-- `RoomFloorLayout.readMetatile`'s already-VERIFIED 6-byte-record
-- shape) was read for every one of this tile ID's real usages across
-- all 6 rooms. Real observed values: 0x00, 0x08, 0x30, 0x31 -- read as
-- a bitmask, these cluster cleanly: 0x30/0x31 (upper nibble non-zero)
-- fall exactly on the room's own border-wall tiles (23-26) and solid
-- feature/decoration blocks (torches, pillars) -- consistent with bits
-- 4-7 being a real N/E/S/W-style directional block mask (0x10/0x20/
-- 0x40/0x80 per edge, 0x30 = two edges blocked, matching a corner/
-- border piece exactly, the FFA-Disassembly documented format's own
-- "$10/$20/$30/$40/$80/$C0" values). 0x00 and 0x08 (upper nibble ZERO
-- in both) fall on the room's own large open floor-mesh areas -- treated
-- as the SAME "not blocked" class; bit 3 (0x08) is presumably a
-- separate, non-blocking flag (material/texture variant or an unrelated
-- trigger bit), not decoded further here. Rule: floor iff EVERY
-- observed collision byte for this tile ID has upper nibble 0x00.
-- Genuinely mixed tiles (27-30: both 0x08 and 0x30 observed across
-- different metatile usages) are treated conservatively as NOT floor --
-- never risk making a real wall walkable. Cross-checked directly
-- against `fourthRoom`'s own real, LIVE-MOVEMENT-VERIFIED case (held UP
-- in-game, watched the player walk freely through tiles this exact rule
-- calls "floor") -- that check passed.
--
-- CORRECTED (2026-08-12, same day, direct follow-up while generalizing
-- this same rule to OTHER rooms -- see `RoomFloorLayout.lua`'s own
-- `COLLISION_WALL_MASK` doc comment for the full story): this bitmask
-- rule does NOT hold universally across the whole ROM -- running it
-- against willyRoom's own real metatile stream (a THIRD, independent
-- room, with its own live-verified real floor) finds willyRoom's own
-- checkerboard floor (tiles 151-154, extensively gameplay-tested
-- throughout this whole project) has collision `0x30` everywhere it
-- appears -- the OPPOSITE of what this rule would predict. So this
-- entry's own bit-level interpretation is confirmed ONLY for
-- fourthRoom's own live-tested case, extrapolated here to a genuinely
-- DIFFERENT, independent metatile table (unknownRoomA's own, at
-- `0x20938`, not fourthRoom's) with no live-movement check possible (no
-- live gameplay trigger exists into this area) -- a real, concrete
-- reason this stays HYPOTHESIS rather than VERIFIED, not a formality.
-- Most likely explanation: the collision byte's bit meanings are set
-- per metatile TABLE, not fixed ROM-wide (ordinary for a hand-authored,
-- per-map collision scheme) -- unknownRoomA's own table could
-- plausibly follow either convention, and this project has no way to
-- tell which without a live trigger that doesn't exist.
local UNKNOWN_ROOM_A_FLOOR_TILE_IDS = {
  [18] = true, [33] = true, [35] = true, [36] = true, [37] = true, [38] = true,
  [39] = true, [40] = true, [41] = true, [42] = true, [43] = true, [48] = true,
  [50] = true, [51] = true, [52] = true, [53] = true, [56] = true, [57] = true,
  [58] = true, [59] = true, [64] = true, [66] = true, [72] = true, [73] = true,
  [74] = true, [75] = true, [77] = true, [80] = true, [81] = true, [84] = true,
  [85] = true, [92] = true, [93] = true, [94] = true, [95] = true, [96] = true,
  [97] = true, [100] = true, [101] = true, [108] = true, [109] = true,
  [110] = true, [111] = true, [163] = true, [166] = true,
}
-- Real, per-room 16x20 pixel-tile grids (row-major, matching every
-- other room's own `graphics.<room>.grid` shape) -- each decoded from
-- bank 5's own record N (N = roomSelector), through unknownRoomA's own
-- real metatile table (bank 8, file 0x20938), exactly like
-- `render_unknown_room_a.py`'s own `render_room()`.
local UNKNOWN_ROOM_A_GRIDS = {
  [8] = {
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {92,93,92,93,92,93,92,93,92,93,92,93,92,93,23,24,23,24,23,24},
    {108,109,108,109,108,109,108,109,108,109,108,109,108,109,25,26,25,26,25,26},
    {33,36,33,36,33,36,27,28,48,75,27,28,48,75,42,43,23,24,23,24},
    {51,52,51,52,51,52,58,59,74,37,58,59,74,37,29,30,25,26,25,26},
    {33,36,33,36,33,36,48,53,112,113,112,113,112,113,48,75,72,37,23,24},
    {51,52,51,52,51,52,39,35,114,115,114,115,114,115,74,37,48,73,25,26},
    {33,36,33,36,33,36,33,36,33,36,48,53,112,113,112,113,42,43,23,24},
    {51,52,51,52,51,52,51,52,51,52,39,35,114,115,114,115,29,30,25,26},
    {33,36,33,36,198,198,198,198,33,36,27,28,112,113,112,113,48,75,72,37},
    {51,52,51,52,199,199,199,199,51,52,58,59,114,115,114,115,74,37,48,73},
    {33,36,33,36,33,36,33,36,33,36,48,53,50,64,50,64,112,113,94,95},
    {51,52,51,52,51,52,51,52,51,52,39,35,66,35,66,35,114,115,110,111},
    {198,198,33,36,33,36,33,36,33,36,33,36,33,36,198,198,48,53,112,113},
    {199,199,51,52,51,52,51,52,51,52,51,52,51,52,199,199,39,35,114,115},
  },
  [9] = {
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,23,24,254,254,254,254,254,254,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,254,254,254,254,254,254,25,26,25,26},
    {23,24,23,24,23,24,40,41,40,41,204,205,163,163,204,205,27,28,27,28},
    {25,26,25,26,25,26,29,30,29,30,206,207,166,166,206,207,56,57,56,57},
    {23,24,23,24,23,24,40,41,40,41,40,41,40,41,40,41,40,41,40,41},
    {25,26,25,26,25,26,29,30,29,30,29,30,29,30,29,30,29,30,29,30},
    {23,24,23,24,23,24,4,5,40,41,40,41,40,41,40,41,40,41,40,41},
    {25,26,25,26,25,26,6,7,29,30,29,30,29,30,29,30,29,30,29,30},
    {94,95,23,24,23,24,84,85,4,5,40,41,40,41,40,41,40,41,27,28},
    {110,111,25,26,25,26,100,101,6,7,29,30,29,30,29,30,29,30,56,57},
    {112,113,23,24,23,24,84,85,84,85,4,5,4,5,4,5,4,5,4,5},
    {114,115,25,26,25,26,100,101,100,101,6,7,6,7,6,7,6,7,6,7},
  },
  [10] = {
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,0,1,40,41,40,41,40,41,40,41,40,41},
    {25,26,25,26,25,26,25,26,2,3,29,30,29,30,29,30,29,30,29,30},
    {27,28,27,28,40,41,40,41,40,41,40,41,18,18,40,41,40,41,40,41},
    {56,57,56,57,29,30,29,30,29,30,29,30,18,18,29,30,29,30,29,30},
    {40,41,40,41,40,41,40,41,18,18,40,41,40,41,40,41,40,41,40,41},
    {29,30,29,30,29,30,29,30,18,18,29,30,29,30,29,30,29,30,29,30},
    {40,41,40,41,40,41,40,41,40,41,40,41,40,41,198,198,40,41,40,41},
    {29,30,29,30,29,30,29,30,29,30,29,30,29,30,212,213,29,30,29,30},
    {27,28,27,28,27,28,40,41,40,41,40,41,40,41,40,41,40,41,27,28},
    {56,57,56,57,56,57,29,30,29,30,29,30,29,30,29,30,29,30,56,57},
    {4,5,4,5,27,28,27,28,40,41,40,41,40,41,40,41,27,28,27,28},
    {6,7,6,7,56,57,56,57,29,30,29,30,29,30,29,30,56,57,56,57},
  },
  [11] = {
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {40,41,40,41,40,41,40,41,40,41,40,41,40,41,198,198,40,41,40,41},
    {29,30,29,30,29,30,29,30,29,30,29,30,29,30,212,213,29,30,29,30},
    {40,41,40,41,40,41,18,18,40,41,40,41,40,41,40,41,40,41,40,41},
    {29,30,29,30,29,30,18,18,29,30,29,30,29,30,29,30,29,30,29,30},
    {40,41,40,41,18,18,40,41,40,41,40,41,40,41,40,41,40,41,40,41},
    {29,30,29,30,18,18,29,30,29,30,29,30,29,30,29,30,29,30,29,30},
    {40,41,40,41,40,41,40,41,40,41,198,198,40,41,40,41,40,41,40,41},
    {29,30,29,30,29,30,29,30,29,30,212,213,29,30,29,30,29,30,29,30},
    {27,28,40,41,40,41,40,41,40,41,40,41,40,41,40,41,27,28,94,95},
    {56,57,29,30,29,30,29,30,29,30,29,30,29,30,29,30,58,59,110,111},
    {27,28,27,28,27,28,27,28,40,41,40,41,27,28,94,95,112,113,112,113},
    {56,57,56,57,56,57,56,57,29,30,29,30,58,59,110,111,114,115,114,115},
  },
  [12] = {
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {40,41,40,41,40,41,42,43,23,24,23,24,23,24,23,24,23,24,23,24},
    {29,30,29,30,29,30,29,30,25,26,25,26,25,26,25,26,25,26,25,26},
    {40,41,40,41,40,41,40,41,42,43,23,24,23,24,23,24,23,24,23,24},
    {29,30,29,30,29,30,29,30,29,30,25,26,25,26,25,26,25,26,25,26},
    {40,41,40,41,18,18,40,41,40,41,40,41,40,41,42,43,23,24,23,24},
    {29,30,29,30,18,18,29,30,29,30,29,30,29,30,29,30,25,26,25,26},
    {40,41,40,41,40,41,40,41,198,198,40,41,40,41,40,41,42,43,23,24},
    {29,30,29,30,29,30,29,30,212,213,29,30,29,30,29,30,29,30,25,26},
    {48,75,40,41,40,41,40,41,40,41,40,41,40,41,40,41,27,28,48,75},
    {74,37,29,30,29,30,29,30,29,30,29,30,29,30,29,30,58,59,74,37},
    {112,113,48,75,27,28,48,75,27,28,48,75,40,41,40,41,112,113,112,113},
    {114,115,74,37,58,59,74,37,58,59,74,37,29,30,29,30,114,115,114,115},
  },
  [13] = {
    {23,24,23,24,23,24,23,24,27,28,27,28,27,28,27,28,27,28,48,53},
    {25,26,25,26,25,26,25,26,29,30,29,30,29,30,29,30,29,30,39,35},
    {23,24,23,24,23,24,23,24,27,28,27,28,27,28,27,28,27,28,27,28},
    {25,26,25,26,25,26,25,26,29,30,29,30,29,30,29,30,29,30,29,30},
    {23,24,23,24,23,24,23,24,124,125,27,28,27,28,56,57,27,28,27,28},
    {25,26,25,26,25,26,25,26,126,127,29,30,29,30,38,77,29,30,29,30},
    {23,24,23,24,23,24,80,81,48,53,124,125,27,28,27,28,27,28,27,28},
    {25,26,25,26,25,26,96,97,39,35,126,127,29,30,29,30,29,30,29,30},
    {23,24,23,24,23,24,23,24,19,20,48,53,4,5,4,5,4,5,4,5},
    {25,26,25,26,25,26,25,26,21,22,39,35,6,7,6,7,6,7,6,7},
    {23,24,23,24,23,24,23,24,23,24,198,198,198,198,198,198,198,198,198,198},
    {25,26,25,26,25,26,25,26,25,26,199,199,199,199,199,199,199,199,199,199},
    {27,28,48,75,42,43,23,24,23,24,23,24,23,24,23,24,23,24,23,24},
    {58,59,74,37,29,30,25,26,25,26,25,26,25,26,25,26,25,26,25,26},
    {112,113,112,113,48,75,27,28,48,75,42,43,23,24,23,24,23,24,23,24},
    {114,115,114,115,74,37,58,59,74,37,29,30,25,26,25,26,25,26,25,26},
  },
}

RomProfiles.PROFILES = {
  -- Mystic Quest (Europe) -- see docs/rom-identification.md.
  ["7cb65cb314e3f26b92549ddc7f4fc275186c6170"] = {
    id = "mystic_quest_eu",
    displayName = "Mystic Quest (Europe)",
    sha1 = "7cb65cb314e3f26b92549ddc7f4fc275186c6170",
    sizeBytes = 262144,
    cartridgeType = "MBC2+BATTERY", -- header byte 0x06, verified (rom-identification.md)
    bankSize = 0x4000,
    bankCount = 16,

    -- Graphics regions verified by decoding + visual inspection --
    -- see docs/reverse-engineering/rom-map.md "Graphics" section for the
    -- method and confidence notes. Offsets are flat file offsets into the
    -- 262144-byte ROM.
    graphics = {
      -- VERIFIED (2026-08-09) by live ground truth, same session: read
      -- the real DMG hardware palette registers directly (mGBA
      -- `core.memory.u8[0xFF47/48/49]`, Pan Docs "LCD Monochrome
      -- Palettes") at the real starting room. `BGP=$E4` decodes to the
      -- identity mapping [0,1,2,3] (raw pixel index N -> grey shade N)
      -- -- confirms this project's existing `TileImage.DEFAULT_PALETTE`
      -- grey-ramp assumption was already correct for backgrounds/UI.
      -- `OBP0`/`OBP1` both `$D0`, decoding to **[0,0,1,3]** -- raw pixel
      -- index 1 renders as shade 0 (WHITE, same as index 0/background),
      -- not a mid-grey -- i.e. real sprites render mostly as outlines
      -- against a white background, not solid grey-filled blocks. This
      -- was the exact, visible difference between this project's sprite
      -- rendering and a live ground-truth screenshot before this fix
      -- (see docs/progress.md). General DMG hardware fact for THIS game
      -- state (both OBP0 and OBP1 agree, so it doesn't matter which an
      -- OAM entry's attribute byte selects) -- not proven immutable
      -- across every future screen this project hasn't captured yet.
      spritePalette = {
        status = "VERIFIED",
        registerValue = 0xD0,
        -- raw pixel index (0-3) -> DMG grey-shade index (0=white..3=black)
        shadeIndices = { 0, 0, 1, 3 },
      },
      font = {
        status = "VERIFIED",
        -- Digit/letter charmap: 16 glyphs per row, starting at '0'.
        fileOffset = 0x22B00,
        bank = 8,
        cpuAddress = 0x6B00,
        tileCount = 80, -- 5 rows x 16: 0-9/A-F, G-V, W-Z+a-l, m-z+',, ., !?:
        -- Row layout, 16 tiles each, in ROM order starting at fileOffset:
        rowGlyphs = {
          "0123456789ABCDEF",
          "GHIJKLMNOPQRSTUV",
          "WXYZabcdefghijkl",
          "mnopqrstuvwxyz',",
        },
        notes = "Preceded by German umlaut glyphs (AeOeUe/aeoeuess) and " ..
          "UI icon tiles around 0x22900-0x22B00; byte-value-to-tile-index " ..
          "encoding used by actual dialogue text is still UNKNOWN.",
        -- VERIFIED (2026-08-09) real period/hyphen glyph tiles -- direct
        -- fix for a real gap (user report: "es fehlen die satzzeichen im
        -- scroll text, zb die punkte"): Font.lua only ever built quads
        -- for `TextDecoder.MAIN_GLYPHS`'s 64 characters, so `.`/`-`
        -- (real, VERIFIED `TextDecoder` bytes `0xF0`/`0xF2` -- see
        -- text.md) silently had no quad to draw and were skipped, even
        -- though `TextDecoder.decodeString` itself decoded them
        -- correctly the whole time -- a rendering gap, not a decode
        -- gap. Offsets found via the same linear relationship this
        -- pass established for the name-entry keyboard (`0x22900 +
        -- (tileId-0x10)*16`, cross-checked against this exact font
        -- block's own already-VERIFIED fileOffset) and confirmed
        -- visually (decoded pixel grids: tile 0x70 is a small period
        -- dot, tile 0x72 a horizontal hyphen bar).
        extraGlyphs = {
          ["."] = 0x22F00, -- tile 0x70, TextDecoder.PERIOD_BYTE (0xF0)
          ["-"] = 0x22F20, -- tile 0x72, TextDecoder.HYPHEN_BYTE (0xF2)
          -- Found decoding the real "Kaempfe!" battle-intro textbox (see
          -- `battleIntro` below) -- same linear formula, same visual
          -- confirmation method (decoded pixel grid is a clean "!").
          ["!"] = 0x22F30, -- tile 0x73, TextDecoder.EXCLAMATION_BYTE (0xF3)
          -- VERIFIED (2026-08-12, quick win "fehlende Font-Glyphen ?
          -- und : ergänzen"): `TextDecoder.lua`'s own `QUESTION_BYTE`
          -- (0xF4) and `COLON_BYTE` (0xF5) were already VERIFIED as
          -- real decoded characters since 2026-08-10 -- `decodeByte`
          -- has returned literal "?"/":" for them the whole time -- but
          -- neither ever got a `font.extraGlyphs` entry, so `Font:print`
          -- silently SKIPPED both everywhere they appeared (advancing
          -- the cursor with nothing drawn, same class of gap the
          -- period/hyphen/exclamation entries above already fixed once
          -- each). Caught live during quick win #3's own screenshot
          -- verification (2026-08-12): the "Willy:" speaker prefix
          -- rendered as "Willy" with a blank gap where the colon should
          -- be.
          --
          -- Found via the exact SAME linear formula already established
          -- for `.`/`-`/`!` above (`fileOffset = fontInfo.fileOffset +
          -- tileId*16`) -- those three already fix `tileId = 64 + (byte
          -- - 0xF0)`: PERIOD (0xF0) -> tile 64 (0x40), HYPHEN (0xF2) ->
          -- tile 66 (0x42), EXCLAMATION (0xF3) -> tile 67 (0x43). Same
          -- formula predicts QUESTION_BYTE (0xF4) -> tile 68 (0x44) and
          -- COLON_BYTE (0xF5) -> tile 69 (0x45) -- confirmed by directly
          -- decoding both raw 16-byte tiles (`tools/graphics/gbtile.py`)
          -- and eyeballing the resulting 8x8 pixel grid, same method as
          -- every other glyph in this table:
          --   tile 0x44 (file 0x22F40):        tile 0x45 (file 0x22F50):
          --     ..####..                         ........
          --     .##..##.                         .##.....
          --     .##..##.                         .##.....
          --     ....##..                         ........
          --     ...##...                         ........
          --     ...##...                         .##.....
          --     ........                         .##.....
          --     ...##...                         ........
          -- -- an unambiguous "?" (hook + dot) and ":" (two stacked
          -- dots), locked in as an exact-pixel-grid test (see
          -- `tests/import/rom_profiles_test.lua`).
          --
          -- Bonus, NOT resolved here: decoding the immediately-preceding
          -- gap tile (0x41/file 0x22F10, sitting between PERIOD and
          -- HYPHEN, corresponding to the never-assigned byte 0xF1) shows
          -- TWO side-by-side dots (`..##..##` on two rows) -- plausibly
          -- a double-quote/apostrophe-pair glyph, but no real ROM text
          -- byte has been confirmed to map to 0xF1 yet, so it stays
          -- unmapped rather than guessed into `extraGlyphs` on shape
          -- alone (this project's own "don't fabricate" rule -- a
          -- genuinely open lead for a future pass, not silently
          -- dropped). Tile 0x46 (file 0x22F60, the already-flagged
          -- `0xF6` "numeric value insertion" HYPOTHESIS above) was also
          -- checked as a negative control: it decodes to a plain
          -- diagonal line, NOT a punctuation glyph -- consistent with,
          -- not contradicting, that byte's existing "control code, not
          -- a printable character" status.
          ["?"] = 0x22F40, -- tile 0x74, TextDecoder.QUESTION_BYTE (0xF4)
          [":"] = 0x22F50, -- tile 0x75, TextDecoder.COLON_BYTE (0xF5)
          -- Real umlaut/eszett glyphs (2026-08-10, direct user report:
          -- "es gibt ein problem mit umlauten") -- same linear formula,
          -- tiles 0x19-0x1F (25-31), immediately preceding the main
          -- font block. Decoded pixel grids directly confirm the real
          -- shapes (dots over the letter for each umlaut, the real
          -- double-loop eszett for ß) -- see TextDecoder.lua's
          -- UMLAUT_PARTIAL doc comment for the full live cross-check
          -- (tile 0x1c/28 independently confirmed in "wächst"/"Kräfte",
          -- tile 0x1e/30 in "berührt"/"überirdi-", both real, decoded
          -- ROM text, two unrelated words each). Keyed by the same
          -- UTF-8 byte-escape strings TextDecoder.lua now emits (kept
          -- as `\ddd` escapes, not raw UTF-8 bytes, so this source
          -- file's own bytes stay plain ASCII).
          ["\195\132"] = 0x22990, -- Ä, tile 0x19 (25)
          ["\195\150"] = 0x229A0, -- Ö, tile 0x1a (26)
          ["\195\156"] = 0x229B0, -- Ü, tile 0x1b (27)
          ["\195\164"] = 0x229C0, -- ä, tile 0x1c (28)
          ["\195\182"] = 0x229D0, -- ö, tile 0x1d (29)
          ["\195\188"] = 0x229E0, -- ü, tile 0x1e (30)
          ["\195\159"] = 0x229F0, -- ß, tile 0x1f (31)
        },
      },
      -- VERIFIED (2026-08-09) real HUD decoration -- direct fix for a
      -- named gap (user report: "Poweranzeige fehlt im HUD"). Found by
      -- finally checking the WINDOW layer, not just the background map:
      -- live `LCDC` at the real room is `$E5` -- bit 6 set means the
      -- window uses its OWN separate tilemap (`$9C00`, not the
      -- background's `$9800`), which this project had never dumped
      -- before (every prior HUD/room capture only ever read the
      -- background map). Real `WY`/`WX` = `128`/`7` -- the window starts
      -- exactly at the HUD strip (screen Y=128, matching this project's
      -- own `HUD_H`/`PLAY_H` split in Field.lua) and covers full screen
      -- width. Window tilemap row 1 (screen row 17, the strip below the
      -- `LP`/`MP`/`G` text row) is `0xF8` once, `0xFA` x16, `0xFE` once,
      -- then blank -- a start-cap + repeating line-segment + end-cap
      -- forming a static horizontal rule with an arrowhead, confirmed by
      -- direct visual comparison against a live mGBA screenshot (a solid
      -- black line spanning the HUD, arrow pointing right). **Always the
      -- same 16 segments in every capture taken so far** -- no evidence
      -- of this being a fillable "gauge" that grows/shrinks with a real
      -- game value (this project explicitly tested holding the attack
      -- button for 180 real frames looking for exactly that kind of
      -- indicator and found nothing -- see attackSwing's doc comment /
      -- combat.md's "Power gauge" note) -- treated as a static HUD
      -- decoration, not a meter, unless a future capture shows otherwise.
      -- HONEST LIMIT: window row 0 (the actual `LP`/`MP`/`G` text row)
      -- uses a DIFFERENT, not-yet-decoded tile set from the regular
      -- dialogue font this project's `Font.lua` currently reuses to draw
      -- readable-but-not-literal HUD text -- real icon/label tiles
      -- (rom-map.md's "HPMSGLE/" note) remain unimplemented; only this
      -- bar (row 1) is added here.
      hudBar = {
        status = "VERIFIED",
        tileOffsets = { startCap = 0x22780, segment = 0x227A0, endCap = 0x227E0 },
        segmentCount = 16,
        screenX = 0,
        screenY = 136, -- window row 1: WY(128) + 8
      },
      -- CORRECTED (2026-08-09, same day): an earlier capture this same
      -- session, using tools/rom/reach_room.py's exact button sequence,
      -- was NOT the real starting room -- it was a later screen (an
      -- empty bordered box) that this project mistook for gameplay.
      -- Direct user pushback ("kann es sein das du das main menü nimmst
      -- und nicht die erste szene... da wo man den boss bekämpft?") led
      -- to re-verifying instead of trusting the first capture: (1) the
      -- "player" sprite in that capture jumped 72px in a single frame
      -- when a direction was held, instead of the independently-VERIFIED
      -- 1px/frame walk speed (Player.lua) -- a real, decisive tell that
      -- it wasn't the field-movement entity; (2) a fresh, from-boot scan
      -- screenshotting at regular intervals (not reusing reach_room.py's
      -- assumed press counts) found the real room appears EARLIER, right
      -- after the intro dialogue, and reach_room.py's extra name-entry
      -- `START` presses were firing *after* gameplay had already begun --
      -- almost certainly opening the in-game pause menu (see Menu.lua),
      -- which is the empty box that was wrongly captured as "the room."
      -- The real room (screenshot: real ROM art, a barred gate, textured
      -- floor, and a real 4x2-tile enemy creature above a real 2-tile
      -- player) was re-captured and is what `startRoom`/`playerSprite`/
      -- `enemySprite` below now describe. `reach_room.py` itself was
      -- also fixed (see its own updated comment) so this doesn't
      -- silently regress for the next investigation.
      --
      -- VERIFIED (2026-08-09) real title screen -- captured the same way
      -- as `startRoom` below (live VRAM tilemap + per-tile ROM offset
      -- search against the ROM file, cross-checking multiple matches for
      -- consistency rather than trusting the first hit -- some simple/
      -- sparse tile patterns matched dozens of places; every one here
      -- was resolved to a real offset inside bank 11 (the "MYSTIC QUEST"
      -- logo art -- confirms this bank's own doc comment: "title-logo
      -- art plus real small creature-sprite fragments") or bank 8 (the
      -- font block's own unlabeled tail, a stylized title-specific menu
      -- font distinct from the regular 64-glyph dialogue font). `grid`
      -- is 18 rows x 20 cols (the FULL screen -- no HUD split like
      -- `startRoom`, since this isn't a gameplay room). Real BGP at
      -- capture: `$E4` (identity ramp, same as the room -- confirms this
      -- project's rendering already uses the right palette here).
      titleScreen = {
        status = "VERIFIED",
        tileOffsets = {
          [49] = 0x22B10, [51] = 0x22B30, [57] = 0x22B90, [58] = 0x22BA0,
          [60] = 0x22BC0, [61] = 0x22BD0, [62] = 0x22BE0, [66] = 0x22C20,
          [69] = 0x22C50, [71] = 0x22C70, [72] = 0x22B00, [74] = 0x22CA0,
          [75] = 0x22CB0, [76] = 0x22CC0, [77] = 0x22CD0, [78] = 0x22CE0,
          [80] = 0x22D00, [88] = 0x22D80, [92] = 0x22DC0, [95] = 0x22DF0,
          [97] = 0x22E10, [99] = 0x22E30, [101] = 0x22E50, [102] = 0x22E60,
          [103] = 0x22E70, [104] = 0x22E80,
          [129] = 0x2C600, [130] = 0x2C610, [131] = 0x2C700, [132] = 0x2C710,
          [133] = 0x2C620, [134] = 0x2C630, [135] = 0x2C720, [136] = 0x2C730,
          [137] = 0x2C640, [138] = 0x2C650, [139] = 0x2C740, [140] = 0x2C750,
          [141] = 0x2C660, [142] = 0x2C670, [143] = 0x2C760, [144] = 0x2C770,
          [145] = 0x2C680, [146] = 0x2C690, [148] = 0x2C790, [149] = 0x2C6A0,
          [150] = 0x2C6B0, [151] = 0x2C7A0, [153] = 0x2C800, [154] = 0x2C810,
          [155] = 0x2C900, [156] = 0x2C910, [157] = 0x2C820, [158] = 0x2C830,
          [159] = 0x2C920, [160] = 0x2C930, [162] = 0x2C850, [164] = 0x2C950,
          [165] = 0x2C860, [166] = 0x2C870, [168] = 0x2C970, [170] = 0x2C890,
          [172] = 0x2C990, [173] = 0x2C8A0, [174] = 0x2C8B0, [175] = 0x2C9A0,
          [176] = 0x2C9B0, [177] = 0x2C5A0, [178] = 0x2C6C0, [179] = 0x2C6D0,
          [180] = 0x2C7C0, [182] = 0x2C6E0, [183] = 0x2C6F0, [184] = 0x2C7E0,
          [185] = 0x2C7F0, [186] = 0x2CA00, [187] = 0x2CA10, [188] = 0x2CB00,
          [189] = 0x2CA10, [190] = 0x2CA20, [191] = 0x2CA30, [192] = 0x2CB20,
          [193] = 0x2CB30, [194] = 0x2CA40, [195] = 0x2CA50, [196] = 0x2CB40,
          [197] = 0x2CB50, [198] = 0x2CA60, [199] = 0x2CA70, [200] = 0x2CAE0,
          [201] = 0x2CB70, [202] = 0x2C5C0, [203] = 0x2C5B0, [204] = 0x2C8C0,
          [206] = 0x2C9C0, [207] = 0x2C9D0, [208] = 0x2C8E0, [209] = 0x2C8F0,
          [210] = 0x2C9E0, [211] = 0x2C9F0, [212] = 0x2CA80, [213] = 0x2CA10,
          [214] = 0x2CB80, [215] = 0x2CB90, [216] = 0x2CAA0, [217] = 0x2CAB0,
          [218] = 0x2CBA0, [219] = 0x2CBB0, [221] = 0x2CAD0, [222] = 0x2CBC0,
          [223] = 0x2CBD0, [224] = 0x2CAE0, [225] = 0x2CAF0, [227] = 0x2CBF0,
          [255] = 0x227F0,
          -- [128] (0x80) deliberately absent -- confirmed blank (all-
          -- zero pattern, the screen's own background fill), rendered as
          -- empty space, not a real offset. [200] and [224] share one
          -- real ROM offset (0x2CAE0) -- both live VRAM patterns matched
          -- that single bank-11 location exactly, not a coincidence
          -- (unlike the two bank-1 stragglers this same search initially
          -- turned up for them, discarded for being outside every other
          -- confirmed title-screen tile's bank-8/bank-11 pattern).
        },
        -- 18 rows x 20 cols, the full LCD (no HUD split -- this isn't a
        -- gameplay room). Row-major, values are the VRAM tile IDs used
        -- as keys into `tileOffsets` above.
        grid = {
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,129,130,133,134,137,138,141,142,145,146,149,150,128,128,128,128},
          {128,128,128,128,131,132,135,136,139,140,143,144,147,148,151,152,128,128,128,128},
          {128,128,128,128,153,154,157,158,161,162,165,166,169,170,173,174,128,128,128,128},
          {128,128,128,128,155,156,159,160,163,164,167,168,171,172,175,176,128,128,128,128},
          {128,128,128,128,178,179,182,183,186,187,190,191,194,195,198,199,202,128,128,128},
          {128,128,128,177,180,181,184,185,188,189,192,193,196,197,200,201,128,128,128,128},
          {128,128,128,203,204,205,208,209,212,213,216,217,220,221,224,225,128,128,128,128},
          {128,128,128,128,206,207,210,211,214,215,218,219,222,223,226,227,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,127,127,127,128,128,128},
          {128,128,128,71,88,104,88,102,127,76,99,92,88,95,127,127,127,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,127,128,128,128},
          {128,128,128,80,88,92,103,88,101,102,99,92,88,95,88,97,127,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {69,66,60,62,71,76,62,61,127,77,72,127,71,66,71,77,62,71,61,72},
          {127,255,127,49,57,57,49,127,49,57,57,51,127,76,74,78,58,75,62,127},
        },
        -- Real menu cursor: OAM sprite, NOT part of the static tilemap
        -- above (confirmed via live OAM dump at the title screen, not
        -- guessed). 8x16 mode (same LCDC as everywhere else in this
        -- profile) so each of the cursor's 2 side-by-side OAM entries is
        -- itself 2 stacked tiles (top real tile + its N+1 partner); the
        -- partner tile offsets were found the same way as every other
        -- 8x16 sprite pair in this project (exact byte search for the
        -- live pattern, not arithmetic -- these are not evenly strided).
        -- Same shape/ordering convention as `playerSprite`/`enemySprite`
        -- below (plain array, row-major top-left/top-right/bottom-left/
        -- bottom-right -- see CreatureSprite.fromOffsets), not a
        -- tile-ID-keyed map like `tileOffsets` above. Reuses tile IDs
        -- 0x12/0x13/0x14/0x15 -- the SAME IDs this project's very first
        -- (mistaken) ground-truth pass had misidentified as "the player
        -- sprite" before the real player (tiles 0x00/0x02) was found;
        -- harmless coincidence, real here.
        cursorSprite = {
          cols = 2,
          rows = 2,
          tileOffsets = { 0x21F60, 0x21F70, 0x21F80, 0x21F90 },
        },
        -- Captured OAM: slot 2 (y=120,x=16,tile=0x12) + slot 3
        -- (y=120,x=24,tile=0x14) -> screen position (8,104), aligned
        -- with the "Weiterspielen" row in this captured frame. The menu
        -- has two rows ("Neues Spiel" row 11, "Weiterspielen" row 13 in
        -- `grid` above, 8px apart) -- `rowY` gives both real on-screen Y
        -- positions the cursor sprite occupies (index 1 = "Neues Spiel",
        -- index 2 = "Weiterspielen").
        cursor = {
          screenX = 8,
          rowY = { 88, 104 },
        },
      },
      -- VERIFIED (2026-08-09) real intro-text scroll -- direct
      -- implementation of a detailed user-supplied reference description
      -- of the real boot flow ("Neues Spiel" -> intro scroll -> name
      -- entry -> first battle -> ... -> Willy). Confirmed live: pressing
      -- UP then A from the title screen (real default is "Weiterspielen"
      -- -- see TitleScreen.lua's corrected doc comment) makes the
      -- background scroll continuously upward (`SCY` increases ~1 unit
      -- every ~5.2 real frames, `SCX` stays 0) while `BGP` shifts to a
      -- lighter ramp (`$40`) for the duration, reverting to the normal
      -- `$E4` identity ramp once the scroll ends -- a real, deliberate
      -- palette effect, not this project's invention, though its exact
      -- per-row flicker timing is simplified here to "light throughout,
      -- normal after" rather than replicated frame-for-frame.
      --
      -- The scrolled content is the SAME background tilemap the title
      -- screen uses, extended: the logo/menu (rows 0-17, unchanged)
      -- followed by the intro story text, written row-by-row into a
      -- circular tilemap buffer just ahead of the scroll (a real VRAM
      -- technique, not replicated bit-for-bit here -- this project lays
      -- the same real text out as one tall virtual image instead, same
      -- visual result via a much simpler implementation).
      --
      -- `text`: the ACTUAL literal ROM bytes at file offset `0xBED8`,
      -- decoded through `TextDecoder.decodeString` at runtime (real
      -- `\n` = the newly-found `TextDecoder.NEWLINE_BYTE`, `0x1A`) --
      -- NOT a hardcoded Lua string. Found by decoding the real live
      -- tilemap scroll first (VRAM tile IDs -> the font's own known
      -- glyph order, tileId+0x80 into the existing dialogue-byte space),
      -- then searching the ROM file for that exact byte sequence as a
      -- cross-check -- found verbatim on the first attempt, meaning
      -- (unlike the still-unsolved "Willy" dialogue elsewhere) THIS
      -- text is stored as plain literal bytes, not the general dual-
      -- table compression scheme text.md flags as unsolved.
      introText = {
        status = "VERIFIED",
        fileOffset = 0xBED8,
        -- `totalUnits` re-measured more precisely (2026-08-09, second
        -- pass): cumulative SCY delta from scroll-trigger to the frame
        -- LCDC's window-enable bit actually reverts (494 units over
        -- 2503 real frames), not the original short-sample
        -- extrapolation (475). Intro.lua itself clamps the EFFECTIVE
        -- scroll shorter than this real measured value -- see its own
        -- doc comment: the real hardware keeps scrolling ~14 more
        -- real seconds of blank padding after the last real sentence
        -- clears the screen, which reads as a stuck/broken screen to a
        -- player (direct user report) -- this field stays the real,
        -- fully-measured value; the shortening is Intro.lua's own,
        -- clearly-documented UX choice, not a correction to this data.
        scy = { unitsPerFrame = 494 / 2503, totalUnits = 494 },
      },
      -- VERIFIED (2026-08-09) real hero/heroine name-entry screens,
      -- captured live right after the intro scroll: a top window box
      -- reading "Held" (hero) or "Frau" (heroine, confirmed by the box
      -- literally changing to that word after confirming the hero name)
      -- above a bigger bordered box holding an on-screen character-
      -- selection keyboard, exactly matching the user-supplied reference
      -- description. Real mechanics confirmed live: the OAM cursor
      -- (reuses the EXACT SAME sprite as the title screen's menu cursor
      -- -- same tile IDs 0x12-0x15, same real ROM offsets, see
      -- `titleScreen.cursorSprite` -- a real, deliberate asset reuse,
      -- not a coincidence) selects one grid cell per A press, appending
      -- its glyph after the label text (with a real 2-tile blank gap,
      -- e.g. "Held  A" -> "Held  AB" -> ...); START confirms and
      -- advances ONLY once at least one character has been entered
      -- (confirmed: pressing START on a still-empty name does nothing).
      -- The long-standing "AAAA" default name this project observed
      -- elsewhere (rom-map.md, WILLY_DIALOGUE) is now understood, not
      -- just reported: it is NOT an auto-fill-on-empty default -- it is
      -- what results from selecting the grid's first cell ('A', where
      -- the cursor already starts) four times in a row, byte-for-byte
      -- confirmed by reading WRAM `$D79D-$D7A0` = `0xBA` x4 after doing
      -- exactly that (0xBA = the same dialogue-byte encoding as regular
      -- text, `0xB0 + glyphIndex('A')`).
      --
      -- `tileset`: ALL tiles this screen needs (letters, digits,
      -- umlauts, punctuation, AND the window border/corner tiles) live
      -- in one real, contiguous ROM block -- confirmed by finding the
      -- border tiles (0x77-0x7E) via live-VRAM-pattern byte search and
      -- discovering their offsets fall exactly on the same linear
      -- `0x22900 + (tileId-0x10)*16` relationship the font's own
      -- already-VERIFIED `fileOffset`/tile-order independently implies
      -- (cross-checked: tile 0x3A/'A' via this formula lands exactly on
      -- `font.fileOffset`'s own 'A' glyph offset) -- not a second,
      -- independently-guessed offset table, the SAME real font block
      -- this project already uses, just referenced by raw tile ID here
      -- instead of by character (since several grid cells, like the
      -- punctuation row, aren't part of `font.rowGlyphs`).
      --
      -- `grid`: the real, live-captured keyboard layout (VRAM tile IDs,
      -- row-major, 9 columns -- the last 2 rows are 8 wide, real, not a
      -- truncation bug: 26 letters and 10 digits don't fill a 9-wide
      -- row evenly). Rows 0-2 = uppercase A-Z, rows 3-5 = lowercase a-z,
      -- row 6 = punctuation (apostrophe/comma/period confirmed by
      -- position matching `font.rowGlyphs`; the remaining 5 cells are
      -- real UI tiles this project hasn't individually named -- rendered
      -- from their real tile art regardless, not skipped), row 7 =
      -- digits 0-4 then uppercase AE/OE/UE umlauts, row 8 = digits 5-9
      -- then lowercase ae/ue/ss umlauts (8 wide) -- this exact grouping
      -- is what let this project pin down the 3 new uppercase umlaut
      -- byte values (see TextDecoder.lua's `UMLAUT_PARTIAL`).
      nameEntry = {
        status = "VERIFIED",
        tileset = { fileOffset = 0x22900, tileBase = 0x10, count = 112 },
        labels = { hero = "Held", heroine = "Frau" },
        grid = {
          { 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42 },
          { 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b },
          { 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53 },
          { 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c },
          { 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65 },
          { 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d },
          { 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76 },
          { 0x30, 0x31, 0x32, 0x33, 0x34, 0x19, 0x1a, 0x1b, 0x1c },
          { 0x35, 0x36, 0x37, 0x38, 0x39, 0x1d, 0x1e, 0x1f },
        },
        -- Real box border tile IDs, same tileset (see above).
        border = { topLeft = 0x77, top = 0x78, topRight = 0x79,
          left = 0x7a, right = 0x7b,
          bottomLeft = 0x7c, bottom = 0x7d, bottomRight = 0x7e },
        -- VERIFIED live: tried selecting 6 letters in a row (A-F); only
        -- the first 4 (A,B,C,D) were accepted, the 5th/6th A-presses
        -- were silent no-ops -- not inferred from the HUD's display
        -- width, directly confirmed.
        maxNameLength = 4,
      },
      -- VERIFIED (2026-08-09) real first-battle intro sequence -- traced
      -- against the actual ROM CODE (not just observed behavior), per
      -- direct user request: "suche die entsprechenden stellen im rom
      -- code anstatt das ganze evidenzbasiert zu machen." Used
      -- `tools/rom/watcher.py` (real SM83 watchpoints) + `disasm.py`
      -- (a real disassembler) to find and read the actual routines, not
      -- just infer them from OAM/tilemap side effects.
      --
      -- **Real walk-in**: right after the heroine name is confirmed, the
      -- player is hidden for ~68 real frames, then appears already at
      -- the entrance and walks from screen X=152 to X=72 (Y fixed at 80,
      -- the same real spawn position `playerSprite` already uses) over
      -- 80 real frames -- exactly 1px/frame, the SAME speed this
      -- project already independently VERIFIED for ordinary player
      -- movement (`Player.PIXELS_PER_STEP`), not a separate cutscene
      -- speed. Confirmed at the CODE level, not just from OAM: ROM
      -- `$0659`/`$065B` (ram addresses `$C244`=Y/`$C245`=X) initialize
      -- the entrance position, then every single per-frame decrement is
      -- executed by ROM `$09A6`, a store instruction INSIDE the same
      -- generic "position += velocity, collision-check, write back"
      -- entity-update routine at `$0961-$09BE` this project had already
      -- found and documented (rom-map.md "Breakthrough") driving
      -- ordinary player/enemy movement -- i.e. the real ROM does not
      -- special-case this cutscene walk with separate code, it just
      -- feeds the normal movement system a synthetic leftward input,
      -- which is exactly how this entry is implemented (see
      -- BattleIntro.lua: drives the real `Player:update` with a
      -- synthetic held-left input, not custom position math).
      --
      -- **Real "Kaempfe!" textbox**: a real bordered box (same border
      -- tile IDs as `nameEntry.border` above -- confirmed shared UI
      -- chrome) appears on the BACKGROUND layer (not the window -- a
      -- real, deliberate difference from name-entry's own box) at the
      -- top of the screen, ~208 real frames after the heroine name is
      -- confirmed, then types its text one real letter every exactly 5
      -- real frames (confirmed: 6 consecutive letter-reveal writes, all
      -- exactly 5 frames apart). Real text (NOT "Kampf" as informally
      -- guessed from an early low-resolution screenshot -- see
      -- text.md): "Kaempfe!" (German imperative "Fight!"), found the
      -- same two-independent-ways method as the intro text -- decoded
      -- live from the real reveal, then found verbatim as literal ROM
      -- bytes at file offset `0x346D4`. Box closes ~324 frames after
      -- heroine-confirm (visible ~116 frames total).
      --
      -- **Real enemy appearance**: the enemy's OAM stays fully hidden
      -- (parked off-screen, same convention as the attack-swing sprite
      -- when idle) until ~468 real frames after heroine-confirm, then
      -- appears already in motion, settling into the SAME real captured
      -- movement cycle this project already implemented
      -- (`Enemy.MOVEMENT_CYCLE`) by ~frame 513 -- no distinct "entrance"
      -- animation found; it simply becomes visible mid-cycle.
      battleIntro = {
        status = "VERIFIED",
        hiddenFrames = 68,
        walkFrames = 80, -- matches Player.PIXELS_PER_STEP (1px/frame)
        walkStartScreenX = 152,
        walkEndScreenX = 72, -- == playerSprite.screenX
        settleFrames = 58, -- pause after walk-in, before the textbox
        textbox = {
          fileOffset = 0x346D4,
          -- Real border tiles -- same tileset/IDs as `nameEntry.border`.
          border = { topLeft = 0x77, top = 0x78, topRight = 0x79,
            left = 0x7a, right = 0x7b,
            bottomLeft = 0x7c, bottom = 0x7d, bottomRight = 0x7e },
          preDelayFrames = 10, -- border visible before typing starts
          framesPerLetter = 5,
          holdFrames = 71, -- fully-typed, before the box closes
        },
        postBoxFrames = 144, -- pause after the box closes, before the enemy appears
        -- VERIFIED (2026-08-09, task P4 continued -- direct follow-up to
        -- the "real THIRD use of the tile-patch pipeline" trace in
        -- rom-map.md's "Answered" entry): the real barred-gate open/
        -- close animation's exact position, tile IDs, and frame timing,
        -- re-confirmed fresh this pass with a per-frame VRAM sweep
        -- (not just the tilemap-ID diff the original trace used) --
        -- `openTileId` below's own live VRAM *pattern* bytes (not just
        -- its tilemap ID) were captured and cross-checked against the
        -- ALREADY-known-correct `startRoom.tileOffsets[133]`/`[137]`
        -- addressing formula (same live-vs-ROM byte match) before being
        -- trusted -- both matched exactly, ruling out an addressing bug
        -- as the explanation for `openTileId`'s own surprising content.
        --
        -- `openTileId`'s real live VRAM pattern is 16 bytes of `0xFF`
        -- (2bpp palette index 3, i.e. a SOLID dark tile, not a blank/
        -- transparent one -- 0x00 would be blank; 0xFF is a real solid
        -- fill). No single ROM *offset* is recorded for it (unlike every
        -- other tile in `startRoom.tileOffsets`): the small tile-patch
        -- blob already found driving this exact animation (ROM file
        -- offset `0x200B0`, bank 8 -- see rom-map.md) only needs to
        -- REPOINT tilemap cells to an already-VRAM-resident tile slot to
        -- produce this effect, not load new pixel data -- so there may
        -- be no dedicated "source location" to find, only the already-
        -- resolved live content, which is what's recorded here.
        gate = {
          status = "VERIFIED",
          bgRow = 0, bgCol = 8, rows = 4, cols = 4, -- BG tilemap rows0-3, cols8-11
          openFrame = 396, closeFrame = 461, -- same battleIntro `self.frame` counter as phaseBounds()
          openTileId = 149,
          openTilePattern = string.rep("\255", 16), -- real live-captured 2bpp bytes, solid color-index-3
        },
        -- ADDED (2026-08-12, direct user report after playing the real
        -- app: "es gibt ein offenen tile in der rechten wand durch der
        -- der player einläuft das sich danach verschließt" -- exactly
        -- this): a SECOND, independent real tile-patch mechanic, at the
        -- courtyard's own RIGHT wall -- the exact spot the player walks
        -- in through during the walk-in sequence (`walkStartScreenX
        -- =152`, `playerSprite.screenY=80` -> BG tilemap row 10,
        -- straddling cols 18-19). This project's own `startRoom.grid`
        -- had always modeled that spot as permanently solid wall (real
        -- tiles 128/129/130), so the player visually walked straight
        -- through it (sprites draw over BG regardless of collision, so
        -- nothing crashed, it just looked wrong) -- the real ROM
        -- actually patches in a genuine 2x2 floor-tile opening there
        -- for the walk-in, then seals it back to the normal wall tiles
        -- once the player has arrived. Live-captured (mgba, real full
        -- boot -> title -> name entry -> battle intro, sampling the
        -- exact BG tilemap cells every real frame): the open state is
        -- {141,142,142,141} (TL,TR,BL,BR -- both already-real
        -- `startRoom` floor tiles, same convention as their own real
        -- interior checkerboard use elsewhere in this room), the closed
        -- state is {128,129,130,130} (the room's own real border-wall
        -- tiles). Frame numbers calibrated RELATIVE to this project's
        -- own already-VERIFIED `hiddenFrames=68` landmark (captured in
        -- the SAME live run, not assumed): the opening appears 2 real
        -- frames before the player sprite itself becomes visible
        -- (hiddenFrames-2), and seals again 117 real frames later
        -- (hiddenFrames+117) -- comfortably inside the existing
        -- `settleFrames` pause, well before the "Kaempfe!" textbox
        -- appears. Slightly less precise than `gate`'s own frame
        -- numbers (those came from a direct CallTracer/watchpoint trace
        -- against ROM code; these came from a live BG-tilemap sample
        -- every frame, cross-calibrated against the `hiddenFrames`
        -- landmark) but real, live-measured data, not invented.
        entranceSeal = {
          status = "VERIFIED",
          bgRow = 10, bgCol = 18, rows = 2, cols = 2, -- BG tilemap row10-11, col18-19
          openFrame = 66, closeFrame = 185, -- hiddenFrames-2, hiddenFrames+117
          openGrid = { { 141, 142 }, { 142, 141 } },
          closedGrid = { { 128, 129 }, { 130, 130 } },
        },
      },
      -- Real post-victory scene, traced via direct ROM code tracing per
      -- explicit user instruction (2026-08-09: "mach mal die scene
      -- transition... auf basis des codes und moeglichst allgemein"),
      -- not inferred from visuals -- see docs/reverse-engineering/
      -- combat.md's "Real post-victory scene transition" entry for the
      -- full instruction-level trace (ROM addresses, WRAM fields).
      --
      -- The real ROM implements this via a general VRAM-write job queue
      -- (WRAM `$C8E8` array / `$CEE8` count, drained once/frame during
      -- active display) and a general cursor-relative tile-blit helper
      -- (`$045D`) -- NOT a hardware palette fade (BGP/OBP/LCDC/WY/WX were
      -- all watched live across the whole sequence and never changed).
      -- The "black screen" is a real full tilemap overwrite with the
      -- blank tile below, applied through that same general queue -- the
      -- identical mechanism the ROM would use to load any room's tiles,
      -- not a bespoke fade effect. This project's own renderer doesn't
      -- need to copy the queue's frame-by-frame timing-safety (a real
      -- GB PPU-race concern that doesn't apply to a modern Love2D
      -- redraw) to reproduce the same real on-screen *result* -- see
      -- `src/app/states/VictorySequence.lua`.
      victorySequence = {
        status = "PARTIALLY VERIFIED",
        -- VERIFIED (2026-08-09): the real blank/background tile the ROM
        -- fills the tilemap with for the black screen (ROM data table,
        -- copied via the general VRAM queue to `$9800`, confirmed by a
        -- live watchpoint: `DE=$8080` written repeatedly -- i.e. tile
        -- `$80` twice per call).
        wipeBlankTileId = 0x80,
        textbox = {
          border = { topLeft = 0x77, top = 0x78, topRight = 0x79,
            left = 0x7a, right = 0x7b,
            bottomLeft = 0x7c, bottom = 0x7d, bottomRight = 0x7e },
          framesPerLetter = 5, -- same real cadence as battleIntro's box
        },
        -- Real text content below is NOT decoded live from a located ROM
        -- offset -- general dialogue is still real-but-COMPRESSED (see
        -- docs/reverse-engineering/text.md; same open problem as
        -- DialogueBox.lua's existing "Willy" lines). Transcribed instead
        -- from this project's own live VRAM/screenshot capture
        -- (2026-08-09, `tools/rom/` scratch scripts, see combat.md).
        -- `%s` = the real player-entered name (see NameEntry.lua).
        -- Line breaks here are this project's OWN safe re-wrap (kept
        -- under this box's ~18-char line width for a name up to the
        -- real VERIFIED `nameEntry.maxNameLength=4`), NOT a literal
        -- reproduction of the real ROM's own wrap points -- the real
        -- ROM box also does real mid-word hyphenation (using the
        -- already-VERIFIED HYPHEN_BYTE, see TextDecoder.lua) which this
        -- project doesn't reproduce automatically yet (no general word-
        -- wrap/hyphenation is implemented -- see TextBox.lua's doc
        -- comment); wrapping at word boundaries instead is an honest,
        -- readable substitute, not a claim of pixel-exact real wrapping.
        -- CORRECTED (2026-08-10, direct user report: "die gesammte start
        -- boss sequence ist noch nicht komplett... der willy dialog ist
        -- nicht vollstaendig"): a fresh, careful live re-trace (real ROM
        -- under mgba, NOT this project's own replay -- starting from
        -- `pre_kaempfe_box.state`, defeating the real boss for real, then
        -- pacing single real `A` taps with generous typewriter-reveal
        -- waits between each to avoid the over/under-mashing trap this
        -- project's own rom-map.md already documented) found the REAL
        -- first box after the black wipe is directly `storyPages[1]`
        -- below ("...und viele andere wurden gezwungen...") -- this
        -- `victoryLine` never appeared at that point. It's real ROM text
        -- (rom-map.md's own "mashing A... re-triggers a real status
        -- bubble once the player is actually free" finding independently
        -- names this exact sentence as something that fires LATER, once
        -- free-roaming, seemingly from a generic status/flex check, not
        -- as this cutscene's fixed first page) -- kept here as a real,
        -- confirmed STRING for whenever that separate trigger gets
        -- found/wired, but VictorySequence.lua no longer inserts it into
        -- the fixed intro page list (a real, confirmed-wrong assumption
        -- corrected, not just "improved").
        victoryLine = "%s ist ein\ntapferer Kaempfer.",
        -- REAL ROM SOURCE FOUND (task "komplett autark interpretiert"):
        -- `tools/rom/dump_strings.py --gaps` found the real byte header
        -- `04 10 14` (bank 14, file `0x03a1bb`) immediately before this
        -- exact sentence -- `0x14` is the already-VERIFIED hero-name
        -- substitution token (see Milestone 6's own doc comment), and
        -- the text tail decodes CLEANLY (zero digraph exceptions) from
        -- `0x03a1be` to the real terminator at `0x03a1d1`, byte-exact
        -- match to the string above
        -- (with the real umlaut "Kämpfer", not the old ASCII
        -- "Kaempfer" fallback). `%HERO_NAME%` below is a marker, not a
        -- real ROM byte -- the caller substitutes the real player-
        -- entered name for it (same real substitution `0x14` itself
        -- performs in the ROM's own text engine). HONEST SCOPE: this is
        -- FORMULA-PROVEN and regression-tested
        -- (`tests/import/dialogue_text_resolver_test.lua`), not yet
        -- wired into any live UI trigger -- see this table's own doc
        -- comment above: no real trigger for showing `victoryLine`
        -- itself has been found/wired yet, only the formula for
        -- resolving its real text once one is.
        victoryLineSegments = {
          { literal = "%HERO_NAME%" },
          { fromOffset = 0x03a1be, toOffsetExclusive = 0x03a1d1 }, -- real terminator (0x00) sits at 0x03a1d1
        },
        -- Re-traced live (see `victoryLine`'s own doc comment above for
        -- the full method). Found TWO real issues with the previous
        -- single-page version below: (1) it silently stopped the
        -- sentence early, at "...jeden Tag zu kaempfen." -- the real
        -- ROM's own box continues onto A SECOND box with "zur
        -- Unterhaltung des Dark Lord, zu kaempfen." (i.e. the full real
        -- sentence names WHO the fighting is for, entirely missing
        -- before); (2) the previously-honest "at least one more lore
        -- page, cut off by this project's own capture window" gap is now
        -- closed -- that page reads in full "Viele liessen dabei
        -- unnoetig ihr Leben." (a plain single-page sentence, not a
        -- longer cut-off block as the old capture's ellipsis implied).
        -- SUPERSEDED (2026-08-12, "ja bitte alles in dieser reinfolge",
        -- direct continuation of the Willy-exchange live-decoding work):
        -- the hand-transcribed `storyPages` table that used to live here
        -- is gone -- `VictorySequence.lua` now live-decodes all 3 pages
        -- directly from their real ROM offsets (`STORY_PAGE_OFFSETS`,
        -- file `0x3A1E5`/`0x3A208`/`0x3A234`, same bank-14 dialogue
        -- block the Willy exchange lives in, immediately before it) via
        -- `TextDecoder.decodeString`, matching the Willy-exchange lines'
        -- own established convention of keeping a ROM offset directly in
        -- app code rather than a second, parallel data table here that
        -- could drift out of sync with it. See VictorySequence.lua's own
        -- doc comment for the exact offsets, the real (not re-wrapped)
        -- line breaks/hyphenation this uncovered, and the one real,
        -- honest content difference found (page 3 has no real trailing
        -- period). This comment intentionally stays -- the RESEARCH
        -- HISTORY above (`victoryLine`'s own doc comment) is still real
        -- and still explains how these 3 pages were originally found.
        --
        -- Real room transition (2026-08-09, traced and implemented --
        -- see `graphics.willyRoom` below and `docs/reverse-engineering/
        -- rom-map.md`'s "Real room-tile decompression pipeline, found"
        -- entry): a genuinely different room loads before the Willy
        -- dialogue plays. Real code path, bank 0: `$04E8` reads the
        -- source pointer at WRAM `$D392`/`$D393` (resolves live to ROM
        -- bank 8, file offset `0x206B0`), and for each raw source byte
        -- looks it up through a real 256-entry tile-ID remap table
        -- staged at WRAM `$D070-$D16F` before drawing 2x2 real tile
        -- blocks via the same general cursor-relative blit (`$045D`/
        -- `$048C`) and VRAM job-queue (`$1E9F`) this session already
        -- found for the black-screen wipe -- i.e. this is the SAME
        -- general drawing machinery, just fed a different (non-blank)
        -- tile source. This is a real, newly-found room-decompression
        -- pipeline, distinct from both the starting courtyard's own
        -- hardcoded capture (`startRoom` below) and the still-not-
        -- understood bank-5 RLE table (see rom-map.md's "Maps"
        -- section) -- neither superseded nor explained by this finding,
        -- just a third, now-real data point.
      },
      -- The real second room (traced per the `victorySequence` doc
      -- comment above) -- captured the same way `startRoom` was: a live
      -- VRAM tilemap read (20x16, no scroll, same convention as every
      -- other confirmed room this project has found), NOT reconstructed
      -- from the raw compressed source bytes (that pipeline is
      -- documented but not re-implemented here -- this project renders
      -- the known-correct decoded RESULT, same honesty level as
      -- `startRoom`).
      --
      -- CORRECTED (2026-08-09, same day): this entry originally assumed
      -- these tile IDs (0x80-0xAB) were indices into the general
      -- environment tileset at a flat `tilesetFileOffset + id*16` stride
      -- (`mapTable.tilesetFileOffset`) -- WRONG, caught by direct user
      -- report ("der neue raum ist noch falsch") after the room rendered
      -- with a checkerboard pattern where the real screenshot shows
      -- solid brick walls. Re-verified by reading the LIVE VRAM tile
      -- *pattern* data directly (not the tilemap indices) for each used
      -- ID and rendering THAT -- it matched the real screenshot exactly
      -- (brick walls + a decorative arch at top-center, previously
      -- invisible because the wrong graphics were being read for those
      -- IDs). Then found each tile's real, individual ROM source offset
      -- by an exact 16-byte search (same method as `startRoom.tileOffsets`
      -- below) -- confirms these tiles live scattered across
      -- `0x321B0-0x32630` (same general ROM region as the environment
      -- tileset, but NOT at the simple `id*16` stride from that
      -- tileset's own base -- a separate, room-specific tile graphics
      -- set assembled into contiguous VRAM slots `0x80-0xAB`, indexed
      -- explicitly below, same shape as `startRoom.tileOffsets`).
      willyRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $46B0, shared by roomSelectors 2-6
        -- in `roomSelectorTable` above (the willyRoom/secondRoom/
        -- thirdRoom family).
        --
        -- The "which SPECIFIC selector is willyRoom's own" caveat this
        -- comment used to carry is now RESOLVED (2026-08-12, quick win
        -- #3 "parity-check gegen echte Live-VRAM-Daten"): live-traced
        -- real WRAM `$C3F5` ("the room-selector byte", see rom-map.md's
        -- own `$026DC` writeup) through the whole real post-boss
        -- sequence -- `0x0f` (the already-known "unknownRoomB"
        -- placeholder, fired during the black-wipe transition) right
        -- after `post_black_wipe()`, then a clean, STABLE `0x04` from
        -- the moment the Willy dialogue begins through the entire real
        -- free-roam session (`willy_room_free()`) -- confirmed real,
        -- reproducible, not a one-off read. **willyRoom's own real
        -- roomSelectorTable index is 4.**
        --
        -- HONEST NEGATIVE RESULT, same investigation: this did NOT
        -- confirm a matching bank-5/6 `mapTable` record the way it did
        -- for `unknownRoomA`'s own family (selectors 8-13, see
        -- `RoomFloorLayout.buildRoomFromMapTableRecord`'s own doc
        -- comment) -- decoding bank-5 record 4 (the "roomSelector N =
        -- mapTable record N" rule, applied here) and comparing it
        -- cell-by-cell against THIS room's own real, independently
        -- live-VRAM-captured grid below found only 96/320 real tile
        -- matches (not the 288-320/320 a correct identification would
        -- need) -- and no other bank-5/6 record (0-7 checked on both
        -- tables) does meaningfully better (best: bank-5 record 3,
        -- 124/320, still nowhere near a real match, plausibly just
        -- incidental shared-floor-tile overlap). Conclusion: the
        -- `roomSelector N = mapTable record N` identity is CONFIRMED
        -- ONLY for the unknownRoomA family (selectors 8-13) that
        -- originally established it -- it does NOT generalize to the
        -- willyRoom family (selectors 2-6), which real evidence (this
        -- room's own separate `$46B0` tile-source pointer, a DIFFERENT
        -- real mechanism, see this comment's first paragraph) already
        -- suggested was a distinct pipeline, now positively confirmed
        -- rather than just suspected. This room's real content stays
        -- exactly as before (the live-captured grid below) -- this
        -- finding only narrows what the general "320 decodable rooms"
        -- claim (rom-map.md "World scope, round 5") means: 320 real
        -- records decode as real, coherent ROM ART (entropy + visual
        -- confirmed), but only unknownRoomA's original 6 are also
        -- confirmed to correspond to a specific, real, in-game room
        -- IDENTITY -- the other 314 records' real in-game (if any)
        -- placement remains genuinely unknown. See rom-map.md's "World
        -- scope, round 6" for the full trace.
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        romRoomSelectorConfirmed = 4, -- live-traced via WRAM $C3F5, see doc comment above
        -- Confirmed 2026-08-12, same day: `$C3F5` stays exactly `4`
        -- through the ENTIRE willyRoom -> secondRoom -> thirdRoom real
        -- checkpoint chain (`door_ready()`/`second_room_free()`/
        -- `third_room_free()`) -- consistent with (and now positively
        -- confirming) `third_room_free()`'s own doc comment that these
        -- 3 rooms are one continuous real room space, scrolled via
        -- hardware SCX/SCY, not 3 separate roomSelector dispatches.
        cols = 20,
        rows = 16,
        tileOffsets = {
          [0x80] = 0x32200, [0x81] = 0x32210, [0x82] = 0x32300, [0x83] = 0x32310, [0x84] = 0x32440,
          [0x85] = 0x32220, [0x86] = 0x32460, [0x87] = 0x32500, [0x88] = 0x32510, [0x89] = 0x32600,
          [0x8a] = 0x32610, [0x8b] = 0x32520, [0x8c] = 0x32530, [0x8d] = 0x32620, [0x8e] = 0x32630,
          [0x8f] = 0x32450, [0x90] = 0x32470, [0x91] = 0x32240, [0x92] = 0x32330, [0x93] = 0x32340,
          [0x94] = 0x32480, [0x95] = 0x32250, [0x96] = 0x32490, [0x97] = 0x321b0, [0x98] = 0x321c0,
          [0x99] = 0x321d0, [0x9a] = 0x321e0, [0x9b] = 0x32260, [0x9c] = 0x324f0, [0x9d] = 0x324e0,
          [0x9e] = 0x324b0, [0x9f] = 0x324a0, [0xa0] = 0x324c0, [0xa1] = 0x324d0, [0xa2] = 0x32350,
          [0xa3] = 0x32270, [0xa4] = 0x32230, [0xa5] = 0x32320, [0xa6] = 0x32400, [0xa7] = 0x32420,
          [0xa8] = 0x32410, [0xa9] = 0x32430, [0xaa] = 0x32360, [0xab] = 0x32370,
        },
        -- HYPOTHESIS, same status/method as `startRoom.floorTileIds`
        -- below (this project's own classification of the real tile IDs
        -- into floor vs. wall/border, not a decoded ROM collision
        -- table): only the checkerboard floor pattern tiles are open --
        -- live-verified (2026-08-09) by actually holding UP after the
        -- Willy dialogue ends: the real player sprite moves a real 72px
        -- north (1px/frame, same VERIFIED speed as the courtyard) then
        -- stops dead at the wall/arch boundary, never entering row 0-1.
        floorTileIds = { [151] = true, [152] = true, [153] = true, [154] = true },
        grid = {
          {128,129,132,129,132,129,132,129,135,136,139,140,129,143,129,143,129,143,129,145},
          {130,131,133,134,133,134,133,134,137,138,141,142,144,133,144,133,144,133,146,147},
          {148,149,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {130,150,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {148,149,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {130,150,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {148,149,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {130,150,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {130,158,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,158,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,158,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,162,165,166,165,166,165,166,165,166,168,165,168,165,168,165,168,165,170,147},
          {163,164,167,164,167,164,167,164,167,164,164,169,164,169,164,169,164,169,164,171},
        },
        -- VERIFIED (2026-08-09): the real north door (the arch-shaped
        -- structure at BG row0-1, cols8-11). Direct user correction
        -- after this project's own live testing repeatedly failed to
        -- open it ("die tuer oeffnet einfach wenn man mittig dagegen
        -- laeuft! ich habs gerade im rom verifiziert") -- the earlier
        -- failures all approached off-center (this project's own test
        -- harness had drifted the player to real screen X 88, outside
        -- the door's real working range, purely a test-methodology
        -- artifact). Re-tested centered: opens on the very first
        -- approach, deterministically (exact input-sequence
        -- reproduction gave identical results twice). `triggerXMin`/
        -- `triggerXMax` are an empirically-bracketed real working range
        -- (X 75/76/79/83 all opened it; X 88 confirmed did not) --
        -- NOT a proven exact pixel/tile boundary, see rom-map.md
        -- "ANSWERED: the real Willy-room north door DOES open".
        door = {
          status = "VERIFIED",
          bgRow = 0, bgCol = 8, rows = 2, cols = 4, -- BG tilemap row0-1, cols8-11
          closedGrid = { {135,136,139,140}, {137,138,141,142} },
          openGrid = { {172,152,151,174}, {173,154,153,175} },
        },
        -- GENERAL room-exit schema (2026-08-09, introduced once a 2nd
        -- and 3rd real transition made "one bespoke phase per room"
        -- clearly not scalable -- see rom-map.md "Yes, it keeps going"
        -- and RoomChain.lua's own doc comment for the engine this
        -- drives). Each entry: `zone` (a real, empirically-bracketed
        -- screen-space rectangle the player must be inside -- any of
        -- xMin/xMax/yMin/yMax may be omitted, meaning "unbounded on
        -- that side"), `transition` (`{type="scroll",axis="x"|"y",
        -- totalPixels=,pixelsPerFrame=}` for a real hardware-scroll
        -- pan, or `{type="cut"}` for a real instant room change via the
        -- `$D392`/`$D393` pipeline), `targetRoom` (a key into this same
        -- `graphics` table), `landingX`/`landingY` (where the player
        -- appears in the target room), and optional `dialoguePages`/
        -- `holdInput` (see RoomChain.lua). This one shape covers every
        -- real transition mechanism found so far (VERIFIED: the
        -- vertical scroll below, the horizontal scroll on `secondRoom`,
        -- the instant cut on `thirdRoom`) without needing a new code
        -- path for the next one, as long as it's also a scroll or a
        -- cut -- a real, load-bearing generality claim, not aspirational.
        --
        -- `totalPixels` UPGRADED from empirical to CODE-VERIFIED
        -- (2026-08-09/10, see rom-map.md "The real scroll/transition
        -- engine" and "BREAKTHROUGH: the real room table, found"): the
        -- real ROM scroll-completion routine (`$46C4`, bank 1) computes
        -- its own threshold as `roomHeightTiles * 8` for a vertical
        -- scroll (`$C340`, live-confirmed `0x10`=16 for `willyRoom`,
        -- `16*8=128` exactly) but as a plain HARDCODED `160` (one
        -- screen width) for a horizontal scroll -- i.e. `secondRoom`'s
        -- own `160` below isn't a per-room field read from anywhere,
        -- it's the same fixed constant the ROM itself always uses for
        -- every horizontal room-scroll. `pixelsPerFrame=4` matches the
        -- real per-frame delta this same routine applies (confirmed via
        -- the already-VERIFIED live SCY/SCX register watches). These are
        -- no longer "bracketed by testing many values" the way `zone`
        -- still is -- they're the literal formula/constant the real
        -- code uses.
        exits = {
          {
            status = "VERIFIED",
            -- Real player left-edge screen X range (bracketed, not an
            -- exact proven pixel boundary -- X 75/76/79/83 all opened
            -- it live, X 88 confirmed did not) and the real screen Y
            -- reached when blocked against the closed door.
            zone = { xMin = 72, xMax = 86, yMax = 24 },
            -- totalPixels = roomHeightTiles(16) * 8, CODE-VERIFIED, see
            -- schema comment above.
            --
            -- CORRECTED (2026-08-12, direct user report from actual
            -- play: "der wipe vom willy raum ist von unten nach oben
            -- anstatt anders herrum"): `VictorySequence:draw()`'s own
            -- scroll-pan code hardcodes "the current room slides toward
            -- the NEGATIVE axis side, the target room enters from the
            -- POSITIVE side" for every exit, with no per-exit direction
            -- data to say otherwise -- correct for `secondRoom`'s own
            -- EAST exit below (walking further east really should
            -- reveal new area sliding in from positive X), but this
            -- exit is a real NORTH door (the player walks UP through
            -- it) -- walking north should reveal new area ABOVE
            -- (negative Y), sliding DOWN into place, the OPPOSITE sign.
            -- `reverse=true` tells the draw code to flip which side
            -- each room slides toward for this specific exit, instead
            -- of guessing a single global convention that can only ever
            -- be right for one of the two real directions on an axis.
            transition = { type = "scroll", axis = "y", totalPixels = 128, pixelsPerFrame = 4, reverse = true },
            targetRoom = "secondRoom",
            -- CORRECTED AGAIN (2026-08-10, direct user report: "beim
            -- betreten des raums nach willy bin ich halb in der wand
            -- gespawned"): the (80,136) value directly below (this
            -- project's own prior pass) turned out to be the RAW WRAM
            -- `$C244`/`$C245` bytes at the scroll's settle instant, used
            -- as-is -- but every OTHER position in this file (playerSprite
            -- /enemySprite/willyScene/etc) documents that raw OAM/WRAM
            -- position pair as needing the standard Pan Docs hardware
            -- offset subtracted (`Y-16`/`X-8`) before it's a real local
            -- screen coordinate; this one entry skipped that step. A
            -- naive `-16` alone (136-16=120) still isn't right either --
            -- 136 is a WORLD-space Y that kept accumulating THROUGH the
            -- 128px scroll (confirmed live: it rose in lockstep with SCY
            -- falling, exactly matching this file's own `exits.
            -- transition` doc comment's "world position advances in
            -- lockstep with the scroll" note), not a simple per-room
            -- local value. Re-derived the real local landing spot
            -- directly instead of theorizing further: took a real
            -- screenshot at the exact settled instant, overlaid a real
            -- pixel grid on it, and cross-CALIBRATED that same grid
            -- method against an ALREADY-VERIFIED position (`playerSprite`
            -- .screenX/screenY` above) in an unrelated screenshot first,
            -- to confirm the measurement technique itself was trustworthy
            -- before trusting its result here. Real measured position:
            -- (72,96) -- lands on the room's own real checkerboard floor
            -- (cross-checked against `TileWalkability.build` using this
            -- room's own `floorTileIds` below: `canMoveTo(72,96)` is
            -- real open floor, `canMoveTo(80,136)` and even
            -- `canMoveTo(72,120)` are not), matching the live screenshot
            -- exactly (player standing normally, not clipped).
            landingX = 72, landingY = 96,
            -- REMOVED (2026-08-10, same investigation): the 3-line
            -- "Amanda! Das mit Willy tut mir leid...." dialogue
            -- previously fired here, tied to completing THIS transition
            -- (matching this project's own general `exits.dialoguePages`
            -- room-entry mechanism) -- direct user report ("der dialog
            -- wird beim betreten des raums getriggert") questioned this,
            -- and a fresh live re-trace disproves it outright: idling
            -- 900 real frames with ZERO input immediately after landing
            -- in `secondRoom` produced no dialogue box at all. The real
            -- trigger is per-NPC proximity instead (see `secondRoom
            -- .scene.characterA.dialogue` below) -- a structurally
            -- different mechanism, not a timing tweak, so this field is
            -- removed rather than re-populated with a guess; no text
            -- resembling "Amanda"/these exact lines appeared anywhere in
            -- this fresh re-trace, so it is not re-attached to the NPCs
            -- either -- an honest gap, not a silent carry-over.
          },
        },
      },
      -- VERIFIED (2026-08-09): the real second room revealed beyond the
      -- Willy-room's own north door -- NOT reached via the already-
      -- documented `$D392`/`$D393` room-load pipeline: watched live,
      -- this room's content was already sitting in VRAM (tilemap rows
      -- 16-31, off-screen) before the door ever opened, and the real
      -- transition is a pure hardware background-scroll animation (see
      -- `doorScroll` below) -- `$D392`/`$D393` never change. Real grid
      -- + tile offsets captured the same way as every other room here
      -- (live VRAM tile pattern -> exact ROM byte search); reuses most
      -- of `willyRoom`'s own tileset (same bank 8 region) plus 12 real,
      -- new tile IDs (`176`-`187`) found the same way. See rom-map.md
      -- "ANSWERED: the real Willy-room north door DOES open" for the
      -- full trace.
      secondRoom = {
        status = "VERIFIED",
        -- Same real tile-source pointer/family as `willyRoom` above
        -- ($46B0, roomSelectors 2-6) -- this is the SAME continuous
        -- scrollable source, not a separately-selected room (see
        -- roomSelectorTable's own note and rom-map.md's "scroll
        -- transitions don't pick a different room" conclusion).
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        cols = 20,
        rows = 16,
        tileOffsets = {
          [128]=0x32200,[129]=0x32210,[130]=0x32300,[131]=0x32310,[132]=0x32440,
          [133]=0x32220,[134]=0x32460,[135]=0x32500,[136]=0x32510,[137]=0x32600,
          [138]=0x32610,[139]=0x32520,[140]=0x32530,[141]=0x32620,[142]=0x32630,
          [143]=0x32450,[144]=0x32470,[145]=0x32240,[146]=0x32330,[147]=0x32340,
          [148]=0x32480,[149]=0x32250,[150]=0x32490,[151]=0x321b0,[152]=0x321c0,
          [153]=0x321d0,[154]=0x321e0,[155]=0x32260,[156]=0x324f0,[157]=0x324e0,
          [158]=0x324b0,[159]=0x324a0,[160]=0x324c0,[161]=0x324d0,[162]=0x32350,
          [163]=0x32270,[164]=0x32230,[165]=0x32320,[166]=0x32400,[167]=0x32420,
          [168]=0x32410,[169]=0x32430,[170]=0x32360,[171]=0x32370,
          -- Real, NEW tile IDs (2026-08-09), found the same way, not
          -- part of `willyRoom.tileOffsets`:
          [176]=0x32ec0,[177]=0x32ed0,[178]=0x32ee0,[179]=0x32ef0,
          [180]=0x32280,[181]=0x32290,[182]=0x32380,[183]=0x32390,
          [184]=0x322c0,[185]=0x323c0,[186]=0x322d0,[187]=0x323d0,
        },
        -- HYPOTHESIS (same status/method as every other room's own
        -- floorTileIds here): only the checkerboard floor tiles are
        -- open, matching `willyRoom`'s own convention -- not
        -- independently re-verified against real collision this pass
        -- (real player movement in all 4 directions was confirmed
        -- working after the transition, but the exact walkable/wall
        -- boundary tiles were not individually tested).
        floorTileIds = { [151] = true, [152] = true, [153] = true, [154] = true },
        grid = {
          {128,129,132,129,132,129,132,129,132,129,129,143,129,143,129,143,129,143,129,145},
          {130,131,133,134,133,134,133,134,133,134,144,133,144,133,144,133,144,133,146,147},
          {148,149,176,177,176,177,151,152,151,152,151,152,151,152,176,177,176,177,155,156},
          {130,150,178,179,178,179,153,154,153,154,153,154,153,154,178,179,178,179,157,147},
          {148,149,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {130,150,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {148,149,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,180,181},
          {130,150,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154},
          {130,158,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152},
          {159,149,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,182,183},
          {130,158,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,158,176,177,176,177,151,152,151,152,151,152,151,152,176,177,176,177,160,147},
          {159,149,178,179,178,179,153,154,153,154,153,154,153,154,178,179,178,179,155,161},
          {130,162,165,166,165,166,165,166,184,152,151,186,168,165,168,165,168,165,170,147},
          {163,164,167,164,167,164,167,164,185,154,153,187,164,169,164,169,164,169,164,171},
        },
        -- VERIFIED (2026-08-09): the real two new characters found
        -- standing in this room -- neither matches the already-known
        -- Willy sprite (tiles 96/98, palette attr 0x10). Identity
        -- UNKNOWN (the room's own dialogue names a character "Amanda"
        -- but does not visually tag which sprite -- if either -- is
        -- her; not guessed here).
        --
        -- CORRECTED (2026-08-10): `screenX`/`screenY` below are NOT a
        -- stable, ROM-authored fixed position -- live-traced (write-
        -- watchpoint + CallTracer, see rom-map.md "P5: the secondRoom
        -- NPCs are NOT placed via a fixed table") to a real, general
        -- spawn primitive (`$42BD`, bank 3) fed by a genuinely
        -- procedural placement loop. The values below are one real,
        -- live-captured sample -- used as each character's own starting
        -- point for the real wander movement below, not a fixed resting
        -- spot.
        --
        -- `dialogue` (2026-08-10, direct user report: "die beiden npcs
        -- ... der dialog wird beim betreten des raums getriggert"): a
        -- fresh live re-trace found the real trigger is per-NPC
        -- PROXIMITY, not room entry (see willyRoom's own north-door
        -- `exits` entry above, whose now-removed `dialoguePages` this
        -- replaces) -- confirmed by walking the player up to each
        -- OAM-tracked NPC individually under mgba and watching a real
        -- dialogue box appear the instant of overlap, with NO button
        -- press needed. Real, confirmed text for the NPC approached
        -- first (moving toward the higher-X side, i.e. `characterA`
        -- here): "Der Monsterein-gang fuehrt nach drausen." (a room-
        -- function hint, using the real ROM's own hyphenated word-wrap
        -- this time, not this project's usual word-boundary substitute).
        --
        -- FOUND (2026-08-12, "ja bitte alles in dieser reinfolge",
        -- direct continuation of the same session's Willy-exchange
        -- offset-hunting work): `characterB`'s own real line, previously
        -- an honest, unfilled gap. Located the SAME way the Willy-
        -- exchange offsets were -- a full-ROM `dump_strings.py` scan for
        -- "Monster"/"drau" keywords turned up `characterA`'s own line at
        -- real file offset `0x378AA` (bank 13) FIRST, decoding cleanly
        -- end to end via `TextDecoder.decodeString` (confirms the
        -- existing hand-transcription byte-for-byte, including finding
        -- a genuinely new digraph along the way -- see `TextDecoder.lua`
        -- own `DIGRAPH_PARTIAL[0x84]="ac"` doc comment: this exact line
        -- needed it to complete "nach", and 5+ other independent real
        -- sentences confirmed the same fill). Right after that box's own
        -- real `[0x12][0x11]` close marker (file `0x378C6` onward, past
        -- a short `[0x04][0x10]` control sequence -- same
        -- un-reverse-engineered family as the Willy exchange's own
        -- inter-box control bytes, not decoded further here) sits a
        -- SECOND clean box at file `0x378CC`: `"Hallo!Willkommen\nin
        -- Toppel!"` -- a real NPC greeting, real ROM room name
        -- ("Toppel"), immediately following the first NPC's own line in
        -- the same real ROM data stream -- exactly where a second NPC's
        -- own dialogue would sit for a two-NPC scene like this one.
        -- Stored here as a plain string (same shape as `characterA`'s
        -- own `dialogue` field below, matching `NpcProximity.lua`'s
        -- existing static-table convention) rather than live-decoded in
        -- app code -- unlike `storyPages`/the Willy exchange, this
        -- dialogue is dispatched through `NpcProximity.lua`'s own
        -- proximity-trigger mechanism, which expects a plain string
        -- array already in `rom_profiles.lua`, not a decode call at
        -- render time; restructuring that mechanism to decode live is
        -- real, separate, non-trivial scope beyond this quick win. The
        -- STRING itself is real, ROM-confirmed content either way, not
        -- a guess.
        --
        -- FOUND AND FIXED (2026-08-10, direct user reports: "die beiden
        -- npcs ... haben immer noch keine grafik" then, after the first
        -- fix pass, "die grafiken der npcs ... sind noch nicht [richtig].
        -- ausserdem haben diese animationen und bewegungspattern"):
        -- THREE real, confirmed problems, all from one extended live
        -- mgba re-trace (900 real frames, OAM-tracked every single
        -- frame, from `settled_secondroom.state`):
        -- (1) the `tileOffsets` this project had were simply WRONG --
        --     real, readable ROM bytes, but from this profile's own font
        --     region, not a creature sprite (confirmed by a live
        --     screenshot showing garbled glyph-shaped marks).
        -- (2) the SHAPE was wrong too: this project modeled these as
        --     2x2-tile (4-tile, 16x16px) sprites like Willy/the player --
        --     but the real OAM only ever uses TWO sprite slots per
        --     character (one column, 8x16 OBJ mode, top+bottom), not
        --     four. A correct 2-tile read through the WRONG 2x2 shape
        --     would still have come out visually wrong/doubled even with
        --     the right bytes.
        -- (3) both characters really do animate AND move -- confirmed
        --     directly: each one's OAM tile ID cycles through a real
        --     4-direction, 2-phase walk cycle as it wanders, tracked the
        --     entire 900-frame window with no obvious short fixed loop
        --     (reads as a real, continuous random walk, consistent with
        --     these same NPCs' already-VERIFIED PRNG-driven spawn
        --     placement above -- plausibly the same generator still
        --     driving them post-spawn, not independently confirmed).
        -- All 16 real tile IDs used (8 per character, a clean `+0x20`
        -- shift between the two -- `characterA` here, `characterB`
        -- `+0x20`) were found via this project's own "exact 16-byte ROM
        -- search" method (every one matched exactly ONE location in the
        -- whole 256KB ROM -- high-confidence, not a guess) and are wired
        -- below as `animation` (see `src/rendering/NpcSprite.lua`).
        -- HONESTY NOTE: the real MOVEMENT algorithm itself (exact step
        -- timing/direction-change rule) was not decoded -- `wander`
        -- below is this project's own reasonable random-walk
        -- approximation (same "not independently verified" status as
        -- KnockbackFlicker.lua's own direction extrapolation), not a
        -- reproduction of the real PRNG sequence. The animation TILES
        -- and their direction/phase/flip pairing, by contrast, ARE the
        -- real, directly-observed data.
        scene = {
          characterA = {
            screenX = 128, screenY = 58,
            dialogue = { "Der Monsterein-\ngang f\195\188hrt nach\ndrau\195\159en." },
            -- REAL ROM SOURCE FOUND (task "komplett autark
            -- interpretiert", direct follow-up): `dialogue` above was
            -- hand-transcribed from a live VRAM capture with no static
            -- ROM offset ever pinned down -- this project's own
            -- `tools/rom/dump_strings.py "$ROM" --min-len 8` scan found
            -- it decodes CLEANLY (zero digraph exceptions) at bank 13,
            -- file `0x0378aa`-`0x0378c6` (stops at the real terminator
            -- control byte `0x12`), byte-exact match to the string
            -- above -- see `tests/import/dialogue_text_resolver_test
            -- .lua`. `VictorySequence.lua` now resolves this live via
            -- `DialogueTextResolver` when `romData` is available,
            -- falling back to the hand-transcribed string above only
            -- when it isn't (e.g. `NpcCatalog.build`, which has no
            -- `romData` -- see that module's own doc comment).
            dialogueSegments = {
              { { fromOffset = 0x0378aa, toOffsetExclusive = 0x0378c6 } },
            },
            -- CORRECTED FOR REAL (2026-08-15, direct user report from
            -- actual play: "die npc sprites a und b jeweils 16x16 gross
            -- sind"): this whole `animation` table (and the 2026-08-12
            -- "CORRECTED" comment that used to sit here) was built on a
            -- WRONG model -- "a single 8x16-OBJ-mode column, 2 real OAM
            -- entries stacked top+bottom" (see the superseded 2026-08-10
            -- progress.md entry). A fresh live OAM re-trace this pass
            -- (`second_room_free()` checkpoint, `core.memory.oam`
            -- dumped directly) found the REAL shape: 2 OAM entries at
            -- the SAME Y, X exactly 8px apart -- a real LEFT+RIGHT pair,
            -- each already 8x16 in hardware (8x16 OBJ mode IS real and
            -- confirmed -- tile IDs always even, per Pan Docs' own
            -- LSB-forced-to-0 rule), so the TRUE on-screen character is
            -- a 16x16 block using 4 real tiles, not 2.
            --
            -- SECOND CORRECTION, same day (direct user report "die
            -- linke und rechte haelfte der npc sprites a und b sind
            -- vertauscht"): a first attempt at this fix reordered the 4
            -- tiles by their OWN live-captured OAM screen X position
            -- (`{ T+0x10, T, T+0x30, T+0x20 }`) -- WRONG, confirmed by
            -- directly decoding the 4 real captured tile byte blocks and
            -- rendering both candidate orderings pixel-for-pixel: that
            -- "OAM-position" ordering produces 2 visibly DISCONNECTED
            -- blobs (not a character), while the plain, UNREORDERED
            -- sequential order -- `{ T, T+0x10, T+0x20, T+0x30 }` -- (T
            -- = the pre-existing `top` field's own file offset) renders
            -- a single, coherent, correctly-proportioned 16x16 humanoid,
            -- confirmed independently for BOTH characterA's own "left"
            -- capture AND characterB's own "up" capture. I.e. the ROM
            -- simply stores each pose's 4 tiles consecutively in real
            -- row-major file order already -- no OAM-position-based
            -- reordering was ever needed; that extra step was the bug.
            -- `flip`/`flipY` booleans are UNCHANGED from before this fix
            -- (only the TILE ORDER was wrong) -- but HONESTLY FLAGGED:
            -- the exact left-vs-right facing/flip semantics were NOT
            -- independently re-verified this pass (a live capture
            -- matched by VALUE to this "left" entry showed real hardware
            -- X-flip SET, which doesn't obviously square with
            -- `flip=false` here) -- a real, still-open follow-up (see
            -- roadmap.md), not silently claimed correct.
            animation = {
              framesPerPhase = 10, -- real captured runs varied 6-21f; a reasonable single cadence, not individually reproduced per-run
              down  = { { tileOffsets = { 0x25100, 0x25110, 0x25120, 0x25130 }, flip = false },
                        { tileOffsets = { 0x25100, 0x25110, 0x25120, 0x25130 }, flipY = true } },
              up    = { { tileOffsets = { 0x25140, 0x25150, 0x25160, 0x25170 }, flip = false },
                        { tileOffsets = { 0x25140, 0x25150, 0x25160, 0x25170 }, flipY = true } },
              left  = { { tileOffsets = { 0x25180, 0x25190, 0x251a0, 0x251b0 }, flip = false },
                        { tileOffsets = { 0x251c0, 0x251d0, 0x251e0, 0x251f0 }, flip = false } },
              right = { { tileOffsets = { 0x25180, 0x25190, 0x251a0, 0x251b0 }, flip = true },
                        { tileOffsets = { 0x251c0, 0x251d0, 0x251e0, 0x251f0 }, flip = true } },
            },
          },
          characterB = {
            screenX = 80, screenY = 58,
            -- RESOLVED (2026-08-15, direct user report "die npc sprites
            -- a und b jeweils 16x16..." then a direct follow-up "der
            -- dialog von b ist falsch. das ist amanda die hat einen
            -- ganz anderen dialog ueber ihren bruder"): the PREVIOUS
            -- text here (`"Hallo!Willkommen\nin Toppel!"`, file offset
            -- 0x378CC) was found via simple ROM-adjacency to
            -- characterA's own box on 2026-08-10 -- WRONG, confirmed
            -- both by 3 failed live re-verification attempts (blind
            -- walk, closed-loop OAM-seek, static loiter+A-press, none
            -- ever reproduced the box) AND, decisively, by the user
            -- directly naming the real character and topic. Found the
            -- REAL line via a targeted `dump_strings.py --gaps` scan
            -- for "Bruder"/"Amanda" (NOT a live capture -- this text is
            -- read directly from ROM data, no emulator needed once the
            -- byte-decode formula is known): real file offset
            -- `0x03783e` (bank 13), a genuine first-person 3-page
            -- Amanda monologue that explicitly mentions Willy (matching
            -- this exact story beat, right after the Willy scene) and
            -- her own little brother -- unmistakably the right line,
            -- not a guess. Decoded via `TextDecoder`'s own byte-exact
            -- formula EXCEPT two bytes, `0x82` and `0x5B`, both
            -- resolved LOCALLY by hand for "meinem"/"meinen"/"raus"
            -- here (NOT added to the shared global digraph table --
            -- checked first in both cases).
            --
            -- SECOND CORRECTION, same day (direct user report "raa!
            -- müsste wir müssen hier raus heißen", then, once shown the
            -- byte-count math looked airtight, "du hast einfach das
            -- literal falsch abgespeichert es muss ja ganz klar
            -- ausrüstung heißen" -- pointing straight at a fresh
            -- cross-check that had turned up "Aarüstung" as PART of
            -- confirming this): a first pass left "raa!" as an "honest,
            -- unresolved oddity", reasoning that its 2 bytes (`0x8E`
            -- ="ra", `0x5B`="a" at the time, both independently well-
            -- confirmed elsewhere) mathematically can't spell "raus!"
            -- (4 decoded symbols vs. 5 needed). That reasoning was
            -- right about the MATH but wrong to stop there -- searching
            -- the WHOLE ROM for every other occurrence of the exact
            -- byte pair `8E 5B` (only 4 total) found `0x5B` is ALSO
            -- genuinely contradictory against the OLD "a" reading (same
            -- shape as `0x82`, just never previously flagged):
            -- "Ausrüstung" (equipment, `A[5B]r...`, no `0x8E` even
            -- involved), "Daraus mache" (from that I make), "grausamer
            -- als" (crueler than -- ALSO independently reconfirms
            -- `0x82`="me"), "grausam!" (terrible!) all needed "us", not
            -- "a". At the time, `0x5B` stayed "a" in the SHARED global
            -- table (the byte was also assumed to spell "Julia") with a
            -- LOCAL override to "us" just for this hand-transcribed
            -- string. RESOLVED, 2026-08-17: the real ROM digraph table
            -- (found by disassembly) proved `0x5B="us"` universally --
            -- these 4 words were right all along, and "Julia" was
            -- itself a mis-read (really "Julius", see
            -- `namedCharacters` above and TextDecoder.lua's own `0x5B`
            -- note). The shared global table now reads "us" directly,
            -- so this string no longer needs (or has) a local override.
            realName = "Amanda", -- her name is unmistakable and appears
            -- 15+ times throughout this ROM's own real story text (see
            -- dump_strings.py's own scan output) -- confident enough to
            -- surface as a real name, unlike `characterA`'s own still-
            -- undetermined one.
            dialogue = {
              "Amanda:Das mit\nWilly tut mir\nleid.", -- CORRECTED (task
              -- "komplett autark interpretiert"): no space after the
              -- speaker colon (`SPEAKER_COLON_BYTE`, `0x2c`) -- the real
              -- ROM byte stream never inserts one; this project already
              -- established the SAME "no added space" convention for
              -- Julius's own line ("Julius:Nun er-\nfahre..."), this
              -- was just never applied here yet.
              "Wir müssen hier\nraus!", -- 0x5B reads "us" here via the shared table directly (see doc comment above)
              "Ich möchte nach\nHause zu meinem\nkleinen Bruder.",
            },
            -- REAL ROM SOURCE FOUND (task "komplett autark
            -- interpretiert", direct follow-up to the doc comment
            -- above's own already-cited `0x03783e`): a full byte-exact
            -- trace via `tools/rom/dump_strings.py --gaps` found the
            -- precise real ranges for all 3 pages, bank 13 -- page 1
            -- decodes CLEANLY end to end (`0x037840`-`0x037859`); pages
            -- 2 and 3 each need exactly the ONE already-documented
            -- per-occurrence digraph override from this table's own doc
            -- comment above (`0x5B`->"us" at file `0x037867`; `0x82`
            -- ->"me" at file `0x03787b`) spliced in between two real,
            -- cleanly-decoding ranges -- everything else here is real
            -- ROM bytes, not a guess. Byte-exact regression:
            -- `tests/import/dialogue_text_resolver_test.lua`.
            -- `VictorySequence.lua` now resolves this live via
            -- `DialogueTextResolver` when `romData` is available (same
            -- fallback story as `characterA.dialogueSegments` above).
            dialogueSegments = {
              { { fromOffset = 0x037840, toOffsetExclusive = 0x037859 } },
              {
                { fromOffset = 0x03785b, toOffsetExclusive = 0x037867 },
                { literal = "us" }, -- real byte 0x5B at file 0x037867, documented local override (see doc comment above)
                { fromOffset = 0x037868, toOffsetExclusive = 0x037869 },
              },
              {
                { fromOffset = 0x03786b, toOffsetExclusive = 0x03787b },
                { literal = "me" }, -- real byte 0x82 at file 0x03787b, documented local override (see doc comment above)
                { fromOffset = 0x03787c, toOffsetExclusive = 0x037889 },
              },
            },
            -- Real tile set is `characterA`'s own `+0x20` (see this
            -- table's own doc comment) -- confirmed independently from
            -- this NPC's own live OAM capture, not assumed from the
            -- shift alone.
            -- SAME real shape fix as `characterA`'s own doc comment
            -- above (2026-08-15, twice-corrected same day): real 4-tile
            -- `tileOffsets`, plain sequential file order `{T,T+0x10,
            -- T+0x20,T+0x30}` (NOT an OAM-position-reordered variant --
            -- that first attempt was the bug the 2nd correction fixed).
            -- This character's own "up" pose (T=0x25540) is the SECOND
            -- of the 2 fresh live captures that cross-validated this
            -- exact tile SET (real measured tiles: right-top=0x25540,
            -- left-top=0x25550, right-bottom=0x25560, left-
            -- bottom=0x25570 -- exact match to `{T,T+0x10,T+0x20,
            -- T+0x30}`, zero discrepancy) -- and independently re-
            -- confirmed the correct ORDER by direct pixel rendering:
            -- decoding these 4 real tiles and assembling them in this
            -- sequential order (not OAM-position order) produces a
            -- single, coherent 16x16 humanoid silhouette.
            animation = {
              framesPerPhase = 10,
              down  = { { tileOffsets = { 0x25500, 0x25510, 0x25520, 0x25530 }, flip = false },
                        { tileOffsets = { 0x25500, 0x25510, 0x25520, 0x25530 }, flipY = true } },
              up    = { { tileOffsets = { 0x25540, 0x25550, 0x25560, 0x25570 }, flip = false },
                        { tileOffsets = { 0x25540, 0x25550, 0x25560, 0x25570 }, flipY = true } },
              left  = { { tileOffsets = { 0x25580, 0x25590, 0x255a0, 0x255b0 }, flip = false },
                        { tileOffsets = { 0x255c0, 0x255d0, 0x255e0, 0x255f0 }, flip = false } },
              right = { { tileOffsets = { 0x25580, 0x25590, 0x255a0, 0x255b0 }, flip = true },
                        { tileOffsets = { 0x255c0, 0x255d0, 0x255e0, 0x255f0 }, flip = true } },
            },
          },
        },
        -- VERIFIED (2026-08-09): the real east exit -- a real, DIFFERENT
        -- transition axis from `willyRoom`'s own door (horizontal, not
        -- vertical) -- see rom-map.md "Yes, it keeps going". Real
        -- working trigger window bracketed narrower than the north
        -- door's: screen Y ~64-65 confirmed working; 16/32/48/80/96/112
        -- all confirmed NOT to (a real, live position sweep, not a
        -- guess) -- `zone` below uses a small margin around the one
        -- confirmed-working value rather than the wider untested range.
        exits = {
          {
            status = "VERIFIED",
            -- CORRECTED (2026-08-10, found while re-verifying the
            -- willyRoom exit above for the same user report): `zone` had
            -- no `xMin`/`xMax` at all, so ANY x position satisfied it as
            -- soon as y fell in 60-68 -- harmless by accident while this
            -- project's own landingY for the north-door exit happened to
            -- be far outside that band (the old, wrong 136), but exposed
            -- the instant that was corrected to a real, in-range value
            -- (96): simply walking straight UP from the door now crossed
            -- y=60-68 near the WEST wall and immediately (wrongly)
            -- fired this EAST exit -- live-reproduced via a scripted
            -- UP-only hold that reached `thirdRoom` without ever
            -- pressing RIGHT.
            --
            -- CORRECTED AGAIN (2026-08-10, direct user report: "ich kann
            -- jetzt nicht mehr vom npc in den treppen raum laufen"): the
            -- first fix's `xMin=136` broke the exit entirely instead --
            -- checked directly against this room's own
            -- `TileWalkability`/`floorTileIds` and x>=129 is WALL for
            -- the whole y=60-68 band (a decorative pillar), i.e. the
            -- player can never physically stand at x=136 there at all.
            -- `xMin=110` instead: real open floor the whole way from
            -- there to the room's own reachable maximum (128, confirmed
            -- via the same `TileWalkability` check) at this y band, and
            -- still comfortably clear of the door's own landing spot
            -- (x=72, see willyRoom's own exit above) so a straight walk
            -- up from the door no longer false-triggers this exit.
            zone = { xMin = 110, yMin = 60, yMax = 68 },
            -- totalPixels=160: CODE-VERIFIED as the ROM's own hardcoded
            -- horizontal-scroll constant (one full screen width, not a
            -- per-room field), see the schema comment on willyRoom's
            -- own exits above.
            transition = { type = "scroll", axis = "x", totalPixels = 160, pixelsPerFrame = 4 },
            targetRoom = "thirdRoom",
            -- CORRECTED AGAIN (2026-08-17, direct user report: "die end
            -- position im third room ist falsch. das sollte nicht die
            -- mitte des raums sein sondern in dem türdurchgang"): the
            -- (80,64) below (this project's own prior pass, dated
            -- 2026-08-10) turned out to be a real methodology bug, not a
            -- ROM fact -- it was captured by `checkpoints.third_room_
            -- free()`, which deliberately holds RIGHT for 200 frames
            -- AFTER the scroll settles, to walk the player clear of the
            -- landing spot for later, unrelated investigation
            -- convenience. That extra ~160px of self-inflicted walking
            -- (well past the scroll's own 40-frame/160px duration) got
            -- mistakenly recorded as if it were the landing position
            -- itself, instead of stopping measurement the instant
            -- control genuinely returns to the player.
            --
            -- Re-measured properly this pass: released RIGHT on the
            -- EXACT frame the real SCX shadow (`$C0A6`) reaches its
            -- settled 160 (same signal used before, just not walked
            -- past this time), then confirmed via 40 further real
            -- frames with ZERO input that the real position (`$C245`=X,
            -- `$C244`=Y) does NOT drift -- a genuine stable settle, not
            -- a mid-transition reading. Real result: (0,64), not
            -- (80,64) -- Y=64 was already correct both times; only X
            -- was wrong. X=0 is thirdRoom's own real west edge (the
            -- door threshold this room is entered through, scrolling in
            -- from `secondRoom`), landing cleanly on real, already-
            -- verified floor tile 151 (see this room's own `grid`/
            -- `floorTileIds` below) -- exactly matching the user's own
            -- description, not a coincidence.
            landingX = 0, landingY = 64,
          },
        },
      },
      -- VERIFIED (2026-08-09): the real third room, reached through
      -- `secondRoom`'s own east exit -- see rom-map.md "Yes, it keeps
      -- going". Reuses most of `secondRoom`'s own tileset (same bank 8
      -- region) plus 8 real, new tile IDs (`188`-`195`) found the same
      -- live-VRAM-pattern -> exact-ROM-byte-search way as every other
      -- tileset here. `188`/`189`/`190`/`191` (real screen cols 16-17,
      -- rows 2-3 -- this room's own real top-right) are the user-
      -- reported staircase ("dort befindet sich oben rechts eine
      -- treppe"). No dialogue or new sprites found in this room (live
      -- OAM capture showed only the player).
      thirdRoom = {
        status = "VERIFIED",
        -- Same real tile-source pointer/family as `willyRoom`/
        -- `secondRoom` above ($46B0, roomSelectors 2-6) -- see those
        -- rooms' own doc comments.
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        cols = 20,
        rows = 16,
        tileOffsets = {
          [128]=0x32200,[129]=0x32210,[130]=0x32300,[131]=0x32310,[132]=0x32440,
          [133]=0x32220,[134]=0x32460,[143]=0x32450,[144]=0x32470,[145]=0x32240,
          [146]=0x32330,[147]=0x32340,[148]=0x32480,[149]=0x32250,[150]=0x32490,
          [151]=0x321b0,[152]=0x321c0,[153]=0x321d0,[154]=0x321e0,[155]=0x32260,
          [156]=0x324f0,[157]=0x324e0,[158]=0x324b0,[159]=0x324a0,[160]=0x324c0,
          [161]=0x324d0,[162]=0x32350,[163]=0x32270,[164]=0x32230,[165]=0x32320,
          [166]=0x32400,[167]=0x32420,[168]=0x32410,[169]=0x32430,[170]=0x32360,
          [171]=0x32370,[176]=0x32ec0,[177]=0x32ed0,[178]=0x32ee0,[179]=0x32ef0,
          -- Real, NEW tile IDs (2026-08-09), not part of `secondRoom`'s
          -- own set. 188-191 had 2-3 ambiguous byte-identical ROM
          -- matches each (ROM offsets `0x31f80-0x31fb0` vs.
          -- `0x32170-0x321a0`, both real contiguous 4-tile blocks) --
          -- picked `0x32170-0x321a0` as the more consistent match:
          -- it's immediately adjacent to 192-195's own unambiguous
          -- matches (`0x322a0-0x323b0`), the same real "this room's own
          -- new-tile neighborhood," rather than the more distant
          -- alternative -- a real disambiguation, not the first hit.
          [188]=0x32170,[189]=0x32180,[190]=0x32190,[191]=0x321a0,
          [192]=0x322a0,[193]=0x322b0,[194]=0x323a0,[195]=0x323b0,
        },
        -- HYPOTHESIS, same status/method as every other room's own
        -- floorTileIds here. `188`-`191` (the staircase itself) are
        -- included as walkable -- found live, correcting an initial
        -- implementation gap this pass: without it the player can
        -- never physically reach the staircase's own exit `zone` at
        -- all (real live testing did stand ON it, so it must be
        -- walkable).
        floorTileIds = { [151] = true, [152] = true, [153] = true, [154] = true,
          [188] = true, [189] = true, [190] = true, [191] = true },
        grid = {
          {128,129,132,129,132,129,132,129,132,129,129,143,129,143,129,143,129,143,129,145},
          {130,131,133,134,133,134,133,134,133,134,144,133,144,133,144,133,144,133,146,147},
          {148,149,176,177,151,152,151,152,151,152,151,152,151,152,151,152,188,189,155,156},
          {130,150,178,179,153,154,153,154,153,154,153,154,153,154,153,154,190,191,157,147},
          {148,149,176,177,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {130,150,178,179,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {192,193,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,155,156},
          {153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,157,147},
          {151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {194,195,153,154,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,158,176,177,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,178,179,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,158,176,177,151,152,151,152,151,152,151,152,151,152,151,152,151,152,160,147},
          {159,149,178,179,153,154,153,154,153,154,153,154,153,154,153,154,153,154,155,161},
          {130,162,165,166,165,166,165,166,165,166,168,165,168,165,168,165,168,165,170,147},
          {163,164,167,164,167,164,167,164,167,164,164,169,164,169,164,169,164,169,164,171},
        },
        -- VERIFIED (2026-08-09): the real staircase -- a real, FOURTH,
        -- DIFFERENT transition mechanism: not a scroll. `$D392`/`$D393`
        -- actually change here (live-read `$B0`/`$46` -> `$B0`/`$40`, a
        -- real different source pointer) and `SCX`/`SCY` both snap
        -- straight to 0 -- an instant cut via the ORIGINAL relocatable-
        -- pointer pipeline this project found first (the courtyard ->
        -- willyRoom transition), now confirmed for a real third use.
        -- `zone` is the staircase's own real screen position (cols
        -- 16-17/rows 2-3 -> pixel 128-143/16-31); the exact trigger
        -- boundary within that zone was not swept as precisely as the
        -- other two exits' (found via a coarser live walk-and-watch,
        -- not a position sweep) -- the whole visible staircase tile
        -- block is used as the trigger zone, a reasonable superset.
        --
        -- CODE-TRACED (2026-08-10, see rom-map.md "BREAKTHROUGH: the
        -- real room table, found"): this `cut` is real, general, DATA-
        -- DRIVEN infrastructure, not a one-off. The ROM's own "commit
        -- new room" routine (`$01AF3`, bank 0) is fed by a genuine
        -- table lookup (`$026DC`, bank 1): a real 11-byte-stride record
        -- table at bank 8 file offset `0x20000`, indexed by a literal
        -- `roomSelector` byte baked into a tiny bytecode instruction
        -- (this specific staircase uses `roomSelector=1`; its real,
        -- static record -- confirmed live -- is
        -- `00 00 00 b0 40 80 06 00 40 0e 11`, whose bytes 3-4 (`b0 40`)
        -- are exactly this room's `$D392`/`$D393` target). This
        -- project's engine does not read that table at runtime (it's a
        -- reimplementation, not a ROM interpreter) -- recorded here so
        -- `targetRoom`/the underlying `$D392`/`$D393` pointer for this
        -- exit is understood as real, table-verified ROM data, not an
        -- empirical guess, same upgrade as `totalPixels` above.
        exits = {
          {
            status = "VERIFIED",
            zone = { xMin = 128, xMax = 143, yMin = 16, yMax = 31 },
            transition = { type = "cut" },
            targetRoom = "fourthRoom",
            -- CORRECTED (2026-08-10, same user report as the two exits
            -- above): the old (72,96) was an explicitly-flagged
            -- placeholder guess. Live-traced from `staircase_ready
            -- .state`: held UP until the real instant-cut fired
            -- ($D392/$D393 changing from the thirdRoom to the fourthRoom
            -- pointer), released input at that EXACT frame (the cut
            -- itself lands the player 9 real frames later -- position
            -- stays at the old room's coordinates in between, a real
            -- sequencing detail, not a bug), then confirmed the position
            -- stabilized at exactly (120,112) for 60+ further frames
            -- with zero input.
            --
            -- REAL HARDWARE OFFSET FOUND, 2026-08-15 (direct user
            -- report: "der charakter spwned ein tile zu südlich und ein
            -- halbes tile nach rechts verschoben") -- see Player.lua's
            -- own `RENDER_OFFSET_X`/`RENDER_OFFSET_Y` doc comment for
            -- the full real-hardware OAM trace. Direct, blunt user
            -- pushback (twice) against BOTH ways this was tried so far:
            -- editing this value directly (breaks the general "landingX/
            -- landingY is always the real raw WRAM value, collision-
            -- space, same convention in every room" invariant every
            -- other room in this file relies on), and applying the real
            -- offset as a general per-draw-call render correction
            -- (regressed `startRoom`'s own rendering, cause not yet
            -- root-caused -- see Player.lua's own doc comment for
            -- exactly where that investigation currently stands). This
            -- value is deliberately back to the real, raw, ROM-verified
            -- WRAM value (120,112) -- collision-space, untouched,
            -- consistent with every other room's own `landingX`/
            -- `landingY` -- while the render-side fix is properly
            -- finished (see Player.lua).
            landingX = 120, landingY = 112,
            -- ROM-TABLE-VERIFIED (2026-08-16, task "komplett autark
            -- interpretiert"/blocker resolution): this pair is not
            -- just an empirical WRAM capture anymore -- it's the real,
            -- decoded tile coordinate (14,12) at ROM file `0x382f3`
            -- (bank 14), part of a real, general 186-record landing
            -- table this session found and decoded (see
            -- `src/import/CutTransitionTable.lua`'s own doc comment
            -- for the full derivation). `(14+1)*8=120`,
            -- `(12+2)*8=112` -- exact match, confirming this project's
            -- own real tile-to-pixel formula (`TileLandingPosition
            -- .lua`) end to end.
            --
            -- INTERPRETER-DRIVEN, real ROM bytecode (2026-08-16, direct
            -- user instruction "es soll alles komplett über den
            -- interpreter laufen"): a live single-step trace (native
            -- mGBA, PC watchpoint on `$11B7`, opcode `0xF4`'s real
            -- handler) found this transition's own real entry point --
            -- bank 14, CPU `$42F6` (file `0x382F6`, the `0xF4` byte
            -- itself, immediately before the already-known landing
            -- record's own `A1`/`A2` bytes at file `0x382F7`) -- reached
            -- via genuine TOP-LEVEL script dispatch (74 real hits across
            -- the transition, all bank 14). `roomSelector`/
            -- `subIndexByte` (below) are now LIVE-CAPTURED by
            -- `CutTransitionInterpreter` at this exact real ROM address,
            -- not just read from the static table -- see that module's
            -- own doc comment for the full trace and the honest limit
            -- (only this ONE peek is reached via top-level dispatch; the
            -- landing-tile peek is reached via the real `$413C` step
            -- automaton's own internal jump, NOT top-level dispatch, so
            -- `landingX`/`landingY` above stay the pre-baked, already
            -- ROM-table-verified constants -- not yet interpreter-
            -- captured).
            scriptEntry = {
              bank = 14,
              cpuAddress = 0x42F6,
              transitionKey = "thirdRoomToFourthRoom",
            },
            romRoomSelector = 1, -- live-captured cross-check target, see VictorySequence.lua's own switchToTargetRoom
          },
        },
      },
      -- VERIFIED (2026-08-09): the real fourth room, reached through
      -- `thirdRoom`'s own staircase -- see rom-map.md "Yes, it keeps
      -- going". Visually and structurally different from the whole
      -- willyRoom/secondRoom/thirdRoom chain: a simple, repetitive
      -- 8-tile set. 6 of its 8 tile IDs matched the ALREADY-KNOWN
      -- `startRoom`/environment tileset (bank 12) byte-for-byte (a
      -- real cross-confirmation, not a coincidence) -- reused directly
      -- below rather than re-searched. Its dominant tile (`128`, fills
      -- the whole top of the room) is a real, solid all-`0xFF` pattern
      -- -- the SAME real "solid tile" signature already found for the
      -- courtyard gate's open state (see `startRoom.door` /
      -- GateAnimation.lua) -- confirmed here via a genuinely different
      -- room, reinforcing it as a deliberate ROM convention. It had 11
      -- real, ambiguous byte-identical ROM matches (ordinary for a
      -- common solid-fill pattern) -- used as a literal tile pattern
      -- (see `TileImage.sheetFromOffsets`'s own doc comment) rather
      -- than picking one arbitrarily. Reads, structurally, like the
      -- real entrance to a much bigger open/outdoor area (the
      -- overworld) rather than another contained interior room -- a
      -- plausible, NOT yet confirmed, interpretation.
      --
      -- CORRECTED (2026-08-12, "fourthRoom systematisch flutfüllen"):
      -- this room DOES have a further real exit -- an earlier, wrong
      -- "no exits, dead end" conclusion from a straight-line-only probe
      -- was retracted after a proper systematic exploration (see
      -- `fifthRoom`'s own doc comment below and events.md's "Correction
      -- and a real find" section for the complete live-trace evidence).
      fourthRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $40B0, roomSelectors 0-1 in
        -- `roomSelectorTable` above -- LIVE-CONFIRMED (via $C3F5, in
        -- two separate `CallTracer` traces) to be the EXACT SAME
        -- pointer as `startRoom`'s own real pre-combat state. This
        -- room's own captured tiles only partially overlap `startRoom`
        -- 's (6/8 exact matches) -- plausibly the same underlying
        -- source rendered through a different per-byte `$D070` remap
        -- at each use, not literally identical output; NOT merged into
        -- one definition since the two captures genuinely differ
        -- visually. See rom-map.md's cross-check section for the full
        -- reasoning -- an honest, unreconciled structural note, not
        -- silently resolved either way.
        romRoomSelectors = { 0, 1 },
        -- RESOLVED (2026-08-16, task "komplett autark
        -- interpretiert"/blocker resolution): live-traced the real
        -- thirdRoom->fourthRoom transition's own `$4395` (`CALL
        -- $026DC`) call site directly -- `A=0x1` at that exact real
        -- moment, and `$026DC`'s own `A` argument IS the real target
        -- `roomSelectorTable` index, unmodified (see
        -- `CutTransitionTable.lua`'s own doc comment for the full
        -- derivation). **fourthRoom's own real roomSelector is `1`**,
        -- not `0` -- resolving the "0 or 1" ambiguity above for good
        -- (plausibly meaning `startRoom` below, sharing the same
        -- `{0,1}` candidate pair, is `0` -- a reasonable inference,
        -- NOT itself separately live-confirmed, so left as `{0,1}`
        -- there rather than asserted).
        romRoomSelectorConfirmed = 1,
        cols = 20,
        rows = 16,
        tileOffsets = {
          [128] = string.rep("\255", 16), -- real solid tile, literal pattern (see doc comment above)
          [129] = 0x30300, [130] = 0x30310, [131] = 0x30D10, [132] = 0x30D20,
          [133] = 0x302E0, [134] = 0x302F0,
          [135] = 0x307F0, -- disambiguated the same way as thirdRoom's 188-191: picked the match inside the same environment-tileset bank12 neighborhood as this room's other real offsets, over a more distant bank8 alternative
          -- Real, NEW tile IDs (2026-08-14, task #75 "reconcile live zone
          -- coords with static grid" -- see this room's `exits` doc
          -- comment below for the full live-trace evidence). Found via
          -- the same live-VRAM-pattern -> exact-ROM-byte-search method
          -- as every other room's tileOffsets here: these are the
          -- corridor's real wall/border decoration tiles that only
          -- scroll into the visible screen once SCX genuinely moves
          -- away from 0 (i.e. NOT visible at the original landing-spot
          -- capture, which is why this room's own original 8-tile set
          -- never had them). 136-140/143/144/147 each had exactly ONE
          -- real ROM match, all clustered immediately next to this
          -- room's own already-known 131/132 offsets (0x30D10/0x30D20)
          -- -- high-confidence, same-neighborhood matches, not
          -- coincidental. 145/146 had 2 candidate matches each (same
          -- ambiguity shape as 135 above) -- picked the closer
          -- same-neighborhood match over the more distant one.
          [136] = 0x30D70, [137] = 0x30DC0, [138] = 0x30E50, [139] = 0x30DB0,
          [140] = 0x30D40, [143] = 0x30D90, [144] = 0x30DA0, [145] = 0x30B20,
          [146] = 0x30B30, [147] = 0x30D30,
        },
        -- CORRECTED (2026-08-12, direct user report: "vor allem nach der
        -- treppe spawned der player in der wand"): 129/130 (the "border
        -- pattern" trim between the solid wall and the open floor) used
        -- to be excluded here on a pure, never-tested visual guess --
        -- and the staircase exit's own real, live-verified landing spot
        -- (`thirdRoom.exits[1].landingX/Y` = 120,112) puts the TOP HALF
        -- of the player's own 16x16 real footprint exactly on top of
        -- 130/129 (confirmed both statically against this grid and live
        -- against real VRAM at the settled position -- BG tiles under
        -- the player's own top-left/top-right corners read back as
        -- 130/129 exactly). With 129/130 excluded, this project's own
        -- `TileWalkability`/`canMoveTo` blocked the player from moving
        -- away from that overlap at all, which combined with 129/130's
        -- own dark trim art reads exactly like "stuck inside the wall"
        -- -- the reported symptom.
        --
        -- LIVE RE-VERIFIED (mgba, held UP from the real settled landing
        -- spot): real screen Y walked 112 -> 102 -> 95 -> 88 over 30
        -- real frames with ZERO hesitation crossing the 129/130 trim
        -- row -- the real ROM does not treat it as a wall at all. Only
        -- genuinely open floor behaves like that; a real wall would have
        -- stopped movement dead on first contact, the way it does at
        -- the real boundary found beyond Y=88 (not further characterized
        -- this pass -- this room's own exits, if any exist past that
        -- point, are still unexplored; not needed to fix the reported
        -- landing-spot bug). 129/130 promoted from "not floor" to
        -- VERIFIED real floor/decoration.
        --
        -- CLOSED (2026-08-14, direct user report: "der spawn ist immer
        -- noch off / der übergang geht nicht" for this exact room):
        -- 135 promoted from HYPOTHESIS to VERIFIED real floor. Root
        -- cause, found via a new `MYSTICQUEST_VICTORY_START_ROOM` debug
        -- hook (VictorySequence.lua) that jumps straight to a room at
        -- its own real landing spot: `TileWalkability.build`'s footprint
        -- check at the real landing spot (120,112) touches tile 135
        -- (the 2x2 feature block at native rows 12-13, cols 14-15 --
        -- pixel range x=112-127, y=96-111) the INSTANT the player moves
        -- even 1px in EITHER vertical direction (up OR down), because
        -- the 16px-tall footprint's own row window shifts the moment Y
        -- leaves its exact spawn-time multiple-of-8 alignment. With 135
        -- excluded from `floorTileIds`, this made the player's own
        -- vertical movement completely frozen from the instant of
        -- landing -- confirmed live (`MYSTICQUEST_SCRIPT=up@3-60`, 60
        -- real frames, Y never changed) -- explaining BOTH halves of the
        -- user's report at once (spawn "feels" wrong because the player
        -- can never leave it, and the fifthRoom exit "doesn't work"
        -- because it's unreachable if you can't move vertically at
        -- all). Directly contradicted by THIS SAME room's own already-
        -- recorded live evidence just above ("real screen Y walked 112
        -- -> 102 -> 95 -> 88 over 30 real frames with ZERO hesitation")
        -- -- that trace already proved this exact path is real, open
        -- floor in the actual ROM; 135 was simply never added to
        -- `floorTileIds` to match it, an oversight now corrected.
        floorTileIds = { [129] = true, [130] = true, [131] = true, [132] = true,
          [133] = true, [134] = true, [135] = true },
        grid = {
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128,128},
          {129,130,129,130,129,130,129,130,129,130,129,130,129,130,129,130,129,130,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,129,130,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,129,130,128,128},
          {132,132,132,132,132,132,132,132,132,132,132,132,132,132,132,132,131,131,128,128},
          {133,134,133,134,133,134,133,134,133,134,133,134,133,134,133,134,129,130,128,128},
          {133,134,133,134,133,134,133,134,133,134,133,134,133,134,133,134,131,131,128,128},
          {129,130,129,130,129,130,129,130,129,130,129,130,129,130,135,135,129,130,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,135,135,131,131,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,129,130,129,130,129,130,128,128},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,131,128,128},
        },
        -- ADDED (2026-08-15, direct user demand: "die kollision mit den
        -- wänden im fourthroom [ist kaputt]... suche einfach einen
        -- allgemeinen kollisions mechanismus!!!"). A dedicated real
        -- metatile-source hunt for this room came back a genuine,
        -- decisive NEGATIVE first (single-stepped the ENTIRE real
        -- thirdRoom->fourthRoom staircase cut, 6M+ real instructions,
        -- watching for PC==0x242B -- the same real RLE-decompressor
        -- entry point willyRoom/unknownRoomB's own metatile tables were
        -- found through -- zero hits; this room's real load genuinely
        -- does not go through that pipeline, matching `rom-map.md`'s
        -- own earlier "fourthRoom has no known metatile source" note).
        --
        -- Fell back to the SAME rigor willyRoom's own collision got
        -- (real, live-movement-verified ground truth), but via direct
        -- probing instead of a decoded table: `mgba`, real held-button
        -- input from the real landing spot, `save_raw_state`/
        -- `load_raw_state` to reset between probes (NOT position
        -- teleporting -- a raw $C244/$C245 WRAM poke was tried FIRST
        -- and found unreliable, real movement silently no-ops for 100+
        -- frames afterward in this environment; a real, reproducible
        -- mgba-python-bindings limitation, not a ROM fact, so every
        -- number below comes from a genuinely WALKED real path).
        --
        -- Real, decisive, twice-reproduced finding: holding LEFT from
        -- the real landing spot (row 14, the bottom-most row) OR from
        -- row 13 (one row up) moves the player NOT AT ALL for 100+ real
        -- frames -- a real wall, west of column 14 specifically. The
        -- EXACT SAME LEFT input from row 12 (one row further from the
        -- stairs) moves freely all the way to the real west wall
        -- (column 0). A companion probe (UP from row 12 at a smaller X,
        -- reached via a real detour) found DOWN is ALSO blocked at that
        -- same column range, re-entering rows 13-14 -- consistent with
        -- one coherent real structure, not two unrelated glitches: the
        -- staircase landing is a real, narrow ALCOVE (columns ~14-19
        -- only, matching this room's own real `135` feature-block
        -- columns), not full-width open floor the way the identical-
        -- looking `131`/`129`/`130` tiles read everywhere else in this
        -- room. `floorTileIds` above cannot express this (same tile IDs
        -- appear both inside and outside the real alcove) -- exactly
        -- the class of bug `TileWalkability.build`'s new, general
        -- `blockedRects` escape hatch exists for (see that module's own
        -- doc comment). Columns 14-19 are deliberately NOT listed here
        -- (already correctly handled: 14-17 read real floor per the
        -- existing tile IDs, 18-19 are the room's own already-known
        -- solid `128` wall) -- only the real, newly-discovered west
        -- alcove wall (columns 0-13, rows 13-15 -- row 15 included for
        -- footprint-math consistency with row 14's own anchor checks,
        -- even though no player anchor can independently rest there)
        -- needs an explicit override.
        -- CORRECTED (2026-08-15, same pass, direct live re-check after
        -- the first live screenshot verification): `colMax` was
        -- initially 13 -- off by one. The real evidence is "holding
        -- LEFT from the landing spot (column 15) moves NOT AT ALL",
        -- but a 2-wide player footprint moving from column 15 to 14
        -- only touches columns 14-15 -- with `colMax=13`, column 14
        -- stayed real floor, so the footprint check still passed and
        -- the player took one real, wrong 8px step before stopping
        -- (caught live: `MYSTICQUEST_SCRIPT=left@10-120` landed at
        -- x=112, not the real ROM's own x=120). `colMax=14` blocks
        -- that first step too, matching the real, live-observed "zero
        -- movement, 100+ frames" result exactly.
        blockedRects = {
          { rowMin = 13, rowMax = 15, colMin = 0, colMax = 14 },
        },
        -- Real, LIVE-TRACED exit (2026-08-12, "fourthRoom systematisch
        -- flutfüllen") -- see `fifthRoom`'s own doc comment for the
        -- full evidence trail.
        --
        -- RESOLVED (2026-08-14, task #75 "reconcile live zone coords
        -- with static grid"): the previously-flagged "HONEST LIMIT"
        -- (below, kept for the record) is now fully understood, not
        -- just narrowed. A dedicated live mgba session (loading the
        -- `third_room_free` checkpoint, replaying the real staircase
        -- cut, then walking the corridor while logging `$C244`/`$C245`
        -- (Y/X), the real SCX/SCY scroll shadows (`$C0A6`/`$C0A7`), and
        -- the FULL 32x32 VRAM tilemap every step) found:
        --   1. The zone below (raw WRAM Y/X) IS correct and needs no
        --      change -- `VictorySequence.player.x/y` already use this
        --      project's own local coordinate convention, which is
        --      literally the same raw WRAM values these zones were
        --      built from (`switchToTargetRoom` sets `player.x/y`
        --      straight from `exit.landingX/Y`), so "raw WRAM" and
        --      "this project's own coordinate space" were never two
        --      different things here -- there is no transform to apply.
        --   2. The real, general reconciliation formula for turning a
        --      live WRAM Y/X + SCX/SCY sample into the exact real BG
        --      tile underfoot IS simply `bgRow = (Y+SCY)//8 mod 32`,
        --      `bgCol = (X+SCX)//8 mod 32` (no OAM +16/+8 sprite-offset
        --      correction -- that convention applies to the real
        --      hardware sprite/OAM position, confirmed a DIFFERENT,
        --      non-offset thing here since this ROM's own real
        --      `$C244`/`$C245`->OAM-copy writes the WRAM value into OAM
        --      directly unshifted, live-confirmed via direct `$FE00`
        --      OAM reads matching WRAM exactly). Cross-verified against
        --      the ALREADY-established ground truth (the 2026-08-12
        --      130/129 landing-spot fix below) and against this
        --      formula predicting known floor tiles correctly at every
        --      sampled position along both real corridor paths.
        --   3. Using that formula with `SCX` restricted to its real,
        --      currently-scrolled value (not assumed 0) DOES turn up
        --      real, previously-uncaptured tile content -- 10 new tile
        --      IDs (136-140/143-147, see `tileOffsets` above) that only
        --      scroll into the visible 20-column window once the
        --      corridor's own real SCX genuinely moves away from 0 --
        --      confirming the original investigator's "discrepancy" was
        --      real, not a false alarm. BUT: every one of these newly-
        --      found tiles is a WALL/BORDER decoration near the TOP of
        --      the screen (native BG row 0-1), never anywhere the
        --      player's own feet are -- the floor the player actually
        --      stands on (and the exit trigger zones below) stayed
        --      ordinary, already-known floor (131/133/134) at every
        --      sampled position on both paths. So the zones below never
        --      needed correcting either way.
        --   4. Genuinely NOT fixable further within this room's own
        --      static single-screen `grid`: `TileGridBackground`/
        --      `Field.lua` have no camera-scroll implementation at all
        --      (confirmed -- `Field.lua`'s own doc comment: "no camera
        --      scroll") -- this project's "cut" transition (matching
        --      the real ROM's own transition TYPE for both these exits)
        --      never needs to render the scrolled-past corridor
        --      content, so extending `grid`/`cols` to include the new
        --      136-140/143-147 tiles wouldn't currently be drawn
        --      anywhere without ALSO building real scroll-camera
        --      support -- a genuinely separate, much larger feature,
        --      out of this task's own scope. The new tile IDs are kept
        --      in `tileOffsets` above purely as real, decoded
        --      documentation for that future work, not wired into
        --      `grid` (which stays the original, still-accurate,
        --      landing-spot capture).
        --
        -- Original 2026-08-12 "HONEST LIMIT" text, kept for the record:
        -- the zone below uses the REAL WRAM `$C244`/`$C245` (Y/X)
        -- values directly observed at the live trigger point, NOT
        -- values re-derived from this room's own already-decoded static
        -- `grid` -- a real, live-confirmed discrepancy was found
        -- between the two (the same screen Y/X the corridor's own real
        -- screenshot was captured at reads back as an ordinary already-
        -- decoded floor tile in this room's own static grid, not the
        -- real brick-corridor content actually shown -- most likely a
        -- real hardware SCROLL offset this project hasn't reconciled
        -- against the static grid's own coordinate origin.
        --
        -- CLOSED (2026-08-13, "fourthRoom->fifthRoom-Lücken schließen"):
        -- the second real, honest gap -- the actual ROM trigger needs
        -- the player held against a real wall for ~64 real frames
        -- before it fires (confirmed live, frame-by-frame) -- is now
        -- reproduced. `holdFrames=64`/`holdDirection="down"` (see
        -- events.md's "fourthRoom systematisch flutfüllen" section:
        -- "holding DOWN there for ~64 real frames against what looks
        -- like a wall") are read by `VictorySequence:matchedExit`'s own
        -- extended logic (`HoldTrigger.lua`) -- the exit no longer
        -- fires the instant the zone is entered, matching the real ROM
        -- delay instead of this project's own previous, faster,
        -- unverified-against-the-real-ROM default.
        exits = {
          {
            -- CORRECTED (2026-08-14, direct user report: "der übergang
            -- zum nächsten raum geht nicht" for this exact room, two
            -- real bugs found together): the zone's own `yMin`/`yMax`
            -- (100-108) never actually overlapped a real wall --
            -- `TileWalkability` reports open floor continuously from
            -- y=32 down to y=112 (the landing spot), so a player
            -- holding UP from the landing spot walks straight through
            -- 100-108 without stopping, and this project's own
            -- `ZoneMatch` only checks CURRENT position (not collision)
            -- -- holding DOWN once past the zone fails the check again
            -- before `HoldTrigger`'s 64-frame counter can ever
            -- accumulate. The exit could never fire.
            --
            -- Live-verified where the player ACTUALLY stops walking up
            -- (`MYSTICQUEST_VICTORY_START_ROOM=fourthRoom
            -- MYSTICQUEST_SCRIPT=up@3-120`): settles at EXACTLY y=32 --
            -- the real wall sits between y=30 (blocked) and y=32
            -- (open), and 32 is ALSO this exit's own already-correct
            -- `landingY` for fifthRoom, a real, decisive cross-check
            -- this is the right spot to be standing at.
            --
            -- BUT (the second real bug, found live-testing the first
            -- fix): a naive small zone right at y=32 still never
            -- fires, because holding the required `down` direction
            -- there is NOT blocked (`canMoveTo(120,33)` etc. are all
            -- real open floor too, confirmed by the exact same sweep)
            -- -- the player just walks back down and out of a small
            -- zone within ~8 frames, nowhere near the 64 needed. This
            -- project's own `HoldTrigger`/`ZoneMatch` pair has no
            -- concept of "blocked while held" (see their own doc
            -- comments) -- only "currently inside the zone, this
            -- frame, while the button is down." Rather than inventing
            -- unverified additional wall tiles this room's own real,
            -- captured static data doesn't contain (this room's own
            -- doc history already flags the REAL ROM's own exact wall
            -- position "beyond Y=88" as honestly uncharacterized, see
            -- the older text below), the zone is sized tall enough
            -- (64px, `yMax = yMin + holdFrames`, one real game pixel
            -- per real held frame at this project's own verified 1px/
            -- frame vertical speed) that a continuous 64-frame down-
            -- hold starting at the real y=32 stopping point stays
            -- inside it for the entire hold, by construction -- a
            -- deliberate, documented engineering choice (not a claimed
            -- ROM fact) to make the ALREADY-real, ALREADY-verified
            -- `holdFrames=64`/`holdDirection="down"` finding actually
            -- reachable in this project's own current model, honestly
            -- flagged as such rather than silently left broken.
            zone = { xMin = 112, xMax = 128, yMin = 32, yMax = 96 },
            transition = { type = "cut" },
            targetRoom = "fifthRoom",
            landingX = 136, landingY = 32,
            -- ROM-TABLE-VERIFIED (2026-08-16, same pass as
            -- thirdRoom->fourthRoom's own citation above): real,
            -- decoded tile coordinate (16,2) at ROM file `0x38c82`
            -- (bank 14) or its sibling record at `0x38c8c` (both
            -- resolve to the identical real pixel pair) -- see
            -- `src/import/CutTransitionTable.lua`'s own doc comment.
            -- `(16+1)*8=136`, `(2+2)*8=32` -- exact match.
            -- LIVE ENTRY POINT FOUND (2026-08-16, same live single-step
            -- methodology as thirdRoom->fourthRoom's own `scriptEntry`
            -- below -- see `CutTransitionInterpreter.lua`'s own
            -- `ENTRY_POINTS.fourthRoomToFifthRoom` doc comment for the
            -- full trace): real opcode `0xF4` at bank 14, file `0x38c84`
            -- -- `VictorySequence.lua`'s own `switchToTargetRoom` now
            -- live-captures and cross-checks this exit's roomSelector
            -- too, same as thirdRoom->fourthRoom.
            scriptEntry = {
              bank = 14,
              cpuAddress = 0x4C84,
              transitionKey = "fourthRoomToFifthRoom",
            },
            romRoomSelector = 4, -- live-captured cross-check target, matches fifthRoom's own romRoomSelectorConfirmed above
            holdFrames = 64, holdDirection = "down",
          },
          {
          -- RE-ADDED (2026-08-15, direct user bug report: "dann sollte
          -- wenn der spieler dem weg nach westen folgt eun neuer raum
          -- da sein... bau das ein" -- build it in). History: this exit
          -- was RETRACTED on 2026-08-14 (see the evidence trail kept
          -- below) after live re-tracing found the real ROM corridor
          -- keeps scrolling as ONE continuous `fourthRoom` canvas rather
          -- than cutting to a genuinely separate room -- that structural
          -- finding still stands, unchanged. What's different now: this
          -- project's own renderer has NO camera-scroll implementation
          -- (`Field.lua`'s own doc comment, unchanged this pass -- a
          -- real, separate, much bigger feature) and, independently,
          -- the user directly confirmed (three separate, insistent
          -- corrections, live-walked together) that walking west from
          -- here in THIS APP is expected to lead somewhere, not dead-
          -- end at x=0. Rather than leave `sixthRoom`'s own real,
          -- already-captured tile grid (see its own doc comment) sitting
          -- unused, this exit exposes it as a static "cut" screen --
          -- exactly the same pragmatic choice this project already made
          -- for willyRoom/secondRoom/thirdRoom (also literally one
          -- scrolling ROM canvas, also exposed here as separate static
          -- rooms joined by cuts). HONEST STATUS: the ROM itself never
          -- "cuts" here -- this is a deliberate ENGINEERING CHOICE to
          -- make real, already-decoded ROM tile content reachable
          -- within this project's own no-scroll engine, not a claimed
          -- ROM transition fact (contrast with the `down` exit above,
          -- which IS a live-confirmed real cut). `holdFrames=220`
          -- reuses the original real-measured value from BEFORE the
          -- 2026-08-14 retraction (the corridor genuinely does pause
          -- around there, see finding 1 below -- a real, measured
          -- number, just not a "cut" trigger in the actual ROM). The
          -- zone deliberately excludes the extreme top/bottom of the
          -- room (`yMin=40`, short of the north exit's own `yMin=32`;
          -- direct match to the user's own live-tested correction "ja
          -- aber auch noch nicht ganz nach oben", yes but also not all
          -- the way at the top).
          --
          -- CORRECTED (2026-08-15, same pass as this room's own new
          -- `blockedRects` collision fix): `yMax` used to be 110 --
          -- REQUIRED to shrink to 96 now that real, live-verified
          -- collision blocks LEFT entirely below row 12 (y>=104, see
          -- `blockedRects`'s own doc comment above) -- the old zone
          -- silently relied on a west edge (y=104-110) the corrected,
          -- real collision no longer lets the player reach by holding
          -- LEFT at all, which would have made this exit unreachable
          -- from part of its own declared trigger zone.
          zone = { xMin = 0, xMax = 16, yMin = 40, yMax = 96 },
          transition = { type = "cut" },
          targetRoom = "sixthRoom",
          landingX = 144, landingY = 80,
          holdFrames = 220, holdDirection = "left",
          },
          -- RETRACTED-THEN-RECONSIDERED (2026-08-14 investigation, kept
          -- verbatim for the record -- still an accurate account of what
          -- the real ROM itself does, just no longer read as "so don't
          -- build this"): a dedicated re-investigation found THREE
          -- independent, converging real pieces of evidence that this
          -- was never a real "cut" transition in the ROM:
          --   1. Live re-tested the documented holdFrames=220 trigger
          --      with much longer, more careful holds (up to 3000+
          --      frames, continuous AND intermittent-tapped) -- it never
          --      fires. The real corridor is bigger than originally
          --      captured (a second real wall exists further west, at
          --      WRAM X=24, with further real walkable space beyond
          --      that too) -- the original "settles at X=80" claim was
          --      a real, understandable false read of a TEMPORARY pause
          --      (~260 frames), not the room's own true boundary.
          --   2. The original "confirmation" evidence (`dynamicBank`
          --      `$C3F0`=6, "matches the willyRoom/secondRoom/thirdRoom
          --      family") turned out to be non-discriminating: `$C3F0`
          --      already reads 6 the instant `fourthRoom` itself is
          --      entered via the staircase (roomSelector 1's own real
          --      dynamicBank value) -- observing 6 anywhere in the
          --      corridor is equally consistent with STILL being in
          --      fourthRoom.
          --   3. DECISIVE: live-captured the real `$1E9F`/`$1EB6` scroll-
          --      time VRAM-write-queue calls during the corridor walk --
          --      the EXACT SAME real mechanism (same ROM address,
          --      `$1EB6`) already proven for `secondRoom`'s own real
          --      continuation of `willyRoom`'s single continuous room
          --      space. Captured 160 real tile-ID pairs (a full 16-row
          --      x 20-col real strip) whose values are the literal same
          --      tile vocabulary `fourthRoom` already uses (129-134 plus
          --      the 145/146 corridor-decoration tiles). A completely
          --      independent, pre-existing doc comment (see
          --      `StandardScriptHandlers.lua`'s own `peekTwoByteGate`
          --      doc comment) had ALSO already flagged, from an entirely
          --      different investigation (the real cut-sequence landing-
          --      tile-source table), that no real table entry for
          --      fourthRoom->sixthRoom was ever found, unlike the real,
          --      confirmed thirdRoom->fourthRoom and fourthRoom->
          --      fifthRoom entries -- a fourth, independent corroboration.
          --
          -- Conclusion, still true: "sixthRoom" is real further columns
          -- of `fourthRoom`'s own single continuous room space (the same
          -- "one room, several screens" pattern as `willyRoom`/
          -- `secondRoom`), not a genuinely separate room in the ROM's
          -- own terms. The 160 real captured tile-pairs from that pass's
          -- own full-corridor scan remain a real, concrete foundation
          -- for properly extending `fourthRoom.grid` itself westward
          -- with genuine scroll support, whenever that larger feature
          -- gets built -- this exit is the smaller, honestly-labeled
          -- stand-in until then.
        },
      },
      -- Real room found LIVE (2026-08-12, "fourthRoom systematisch
      -- flutfüllen" -- a direct user instruction to systematically
      -- probe fourthRoom for further real exits, after an EARLIER,
      -- wrong "fourthRoom is a dead end" conclusion this same pass
      -- had to retract -- see events.md's own "Correction and a real
      -- find" section for the complete disassembly-free, pure live-
      -- ROM-tracing evidence trail). Reached by walking north from
      -- fourthRoom's own landing spot into a real, previously-
      -- uncaptured corridor (still `fourthRoom`'s own tile source,
      -- `$40B0` -- a real continuous-scroll extension, same "one
      -- underlying room, several named screens" pattern already
      -- established for willyRoom/secondRoom/thirdRoom), then holding
      -- `DOWN` there for ~64 real frames against what looks like a
      -- wall -- which fires a genuine, live-confirmed "cut" transition
      -- (a real, sudden, non-gradual position jump, not ordinary
      -- walking) into THIS room.
      --
      -- Real tile-source pointer `$46B0`, dynamicBank 7 -- confirmed
      -- LIVE (read directly from WRAM `$D392`/`$D393`/`$C3F0` at the
      -- landed position) to be the EXACT SAME source as the willyRoom/
      -- secondRoom/thirdRoom family (`roomSelectorTable`'s own
      -- selectors 2-6) -- this is a real, different SCREEN/LAYOUT of
      -- that same shared underlying tileset, not a new ROM tile
      -- region. 44 of this room's own 48 distinct real tile IDs
      -- already had a real, verified ROM offset from `willyRoom`'s own
      -- `tileOffsets` (reused directly, unchanged); the remaining 4
      -- (`172`-`175`) were found this pass via the SAME live exact-
      -- byte VRAM-pattern ROM search this project's other rooms all
      -- used, each with exactly one real match.
      fifthRoom = {
        status = "VERIFIED",
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        -- RESOLVED (2026-08-16, same live methodology as fourthRoom's
        -- own `romRoomSelectorConfirmed` above, applied to the
        -- fourthRoom->fifthRoom transition itself this time): a live
        -- PC watch on the shared `$026DC` roomSelector-argument
        -- subroutine, during the real RIGHT/UP/DOWN trigger sequence
        -- (`fifth_room_free()`'s own documented recipe), caught it once
        -- with `A=4` -- resolving the `{2,3,4,5,6}` candidate set above
        -- down to the real, confirmed `4`. Independently cross-checked
        -- by the SAME trace's own `$11B7` peek (opcode `0xF4`, the real
        -- entry point now wired in `CutTransitionInterpreter.lua`'s own
        -- `ENTRY_POINTS.fourthRoomToFifthRoom`): its captured
        -- `(B,C)=(4,80)` reads B=4 too, byte-exact agreement between
        -- two completely independent live-execution angles.
        romRoomSelectorConfirmed = 4,
        cols = 20,
        rows = 16,
        tileOffsets = {
          [128] = 0x32200, [129] = 0x32210, [130] = 0x32300, [131] = 0x32310,
          [132] = 0x32440, [133] = 0x32220, [134] = 0x32460, [135] = 0x32500,
          [136] = 0x32510, [137] = 0x32600, [138] = 0x32610, [139] = 0x32520,
          [140] = 0x32530, [141] = 0x32620, [142] = 0x32630, [143] = 0x32450,
          [144] = 0x32470, [145] = 0x32240, [146] = 0x32330, [147] = 0x32340,
          [148] = 0x32480, [149] = 0x32250, [150] = 0x32490, [151] = 0x321b0,
          [152] = 0x321c0, [153] = 0x321d0, [154] = 0x321e0, [155] = 0x32260,
          [156] = 0x324f0, [157] = 0x324e0, [158] = 0x324b0, [159] = 0x324a0,
          [160] = 0x324c0, [161] = 0x324d0, [162] = 0x32350, [163] = 0x32270,
          [164] = 0x32230, [165] = 0x32320, [166] = 0x32400, [167] = 0x32420,
          [168] = 0x32410, [169] = 0x32430, [170] = 0x32360, [171] = 0x32370,
          [172] = 0x32410, -- NEW, found this pass (real VRAM pattern search,
          [173] = 0x32430, --   exactly 1 match each, see doc comment above)
          [174] = 0x32360,
          [175] = 0x32370,
        },
        -- Real, LIVE-CONFIRMED floor tiles (2026-08-12): the real
        -- landing spot walked freely left (57px) and down (57px) --
        -- both directions stayed entirely within the checkered `147`-
        -- `150` tile pattern that dominates this room's own interior
        -- -- while `RIGHT`/`UP` were blocked almost immediately (the
        -- real bordering wall/decoration tiles, `128`-`146`/`155`-
        -- `175`, are NOT marked floor here -- HYPOTHESIS, not
        -- individually live-tested, matching this project's own
        -- honest-default-to-wall convention for untested border tiles).
        floorTileIds = { [147] = true, [148] = true, [149] = true, [150] = true },
        -- Real VRAM tilemap capture at the settled landing position
        -- (mgba, background map 0, rows 0-15/cols 0-19 -- the same
        -- real 20x16 playfield convention every other room here uses).
        grid = {
          {128,129,132,129,132,129,132,129,132,129,129,135,129,135,129,135,129,135,129,137},
          {130,131,133,134,133,134,133,134,133,134,136,133,136,133,136,133,136,133,138,139},
          {140,141,143,144,147,148,147,148,147,148,147,148,147,148,147,148,151,152,155,156},
          {130,142,145,146,149,150,149,150,149,150,149,150,149,150,149,150,153,154,157,139},
          {140,141,143,144,147,148,147,148,147,148,147,148,147,148,147,148,147,148,155,156},
          {130,142,145,146,149,150,149,150,149,150,149,150,149,150,149,150,149,150,157,139},
          {158,159,147,148,147,148,147,148,147,148,147,148,147,148,147,148,147,148,155,156},
          {149,150,149,150,149,150,149,150,149,150,149,150,149,150,149,150,149,150,157,139},
          {147,148,147,148,147,148,147,148,147,148,147,148,147,148,147,148,147,148,162,139},
          {160,161,149,150,149,150,149,150,149,150,149,150,149,150,149,150,149,150,155,163},
          {130,164,143,144,147,148,147,148,147,148,147,148,147,148,147,148,147,148,162,139},
          {165,141,145,146,149,150,149,150,149,150,149,150,149,150,149,150,149,150,155,163},
          {130,164,143,144,147,148,147,148,147,148,147,148,147,148,147,148,147,148,162,139},
          {165,141,145,146,149,150,149,150,149,150,149,150,149,150,149,150,149,150,155,163},
          {130,166,169,170,169,170,169,170,169,170,172,169,172,169,172,169,172,169,174,139},
          {167,168,171,168,171,168,171,168,171,168,168,173,168,173,168,173,168,173,168,175},
        },
        -- RETRACTED (2026-08-15, direct user report: "das ist doch
        -- immernoch der falsche raum!!! es ist im raum der so ausseiht
        -- wie der start raum wo auch der erste bossfight statt
        -- findet!!!", then, after live back-and-forth confirmed this
        -- was reached by walking WEST out of `fourthRoom`'s own
        -- corridor (normal live play, this LÖVE app, not the debug
        -- room browser): a `secondBoss` entry USED to live here. Moved
        -- to `sixthRoom` -- see that room's own doc comment for the
        -- full history (both the original species-byte evidence trail
        -- and this correction) -- since the room the user kept
        -- describing is reached going west, not north. `fifthRoom`
        -- itself is real (the north exit is a genuine, live-traced ROM
        -- transition) but apparently is NOT where this encounter lives.
      },
      -- Real room found LIVE (2026-08-13, direct user bug report: "im
      -- raum nach der treppe müsste ich nach westen weiter gehen
      -- können... der raum sollte weiter scrollen"). This project's
      -- own earlier "flood-fill" of fourthRoom (see fifthRoom's own
      -- doc comment) DID try LEFT from the staircase landing spot and
      -- found an immediate wall there -- but its own `walk()` helper
      -- gave up after only 10 real stall frames, well short of the
      -- ~64-frame real hold delay already known for the NORTH exit
      -- (fourthRoom -> fifthRoom) -- a real, caught false negative.
      -- Re-tested with a real, long (200+ frame) hold from the
      -- corridor's own real waypoint (reached by UP then LEFT from the
      -- staircase landing spot, the SAME corridor the fifthRoom exit
      -- uses) -- the real SCX shadow (`$C0A6`) genuinely moves (0 ->
      -- 184 -> settles at 96), confirming an actual hardware scroll,
      -- not a stationary wall -- revealing this real, previously-
      -- uncaptured screen. Real tile-source pointer `$46B0`,
      -- dynamicBank 6 -- confirmed LIVE (`$D392`/`$D393`/`$C3F0` at the
      -- settled position) to be the SAME `willyRoom`/`secondRoom`/
      -- `thirdRoom`/`fifthRoom` family (`roomSelectorTable`'s own
      -- selectors 2-6), matching `fourthRoom`'s own selector-1
      -- `dynamicBank` exactly -- this is real, further content of that
      -- SAME already-explored screen, not a new tile region or a
      -- different `roomSelector` state.
      -- CORRECTED (2026-08-14, "gamemap absolute prio"): the paragraph
      -- above already had the real answer, three separate real
      -- confirmations later just made it decisive -- see `fourthRoom
      -- .exits`'s own "RETRACTED" doc comment above for the full
      -- evidence trail (the documented cut-trigger never fires even
      -- after 3000+ frames; the `$C3F0`=6 "confirmation" was non-
      -- discriminating; the real `$1E9F`/`$1EB6` scroll-reveal
      -- mechanism -- the exact one that proved `secondRoom` is part of
      -- `willyRoom` -- fires here too, with real captured tile data
      -- matching `fourthRoom`'s own vocabulary). This table's own real,
      -- independently-verified `tileOffsets` are KEPT (genuine,
      -- cross-validated ROM data, still useful) -- the ROM's own
      -- structure genuinely never cuts here.
      --
      -- RE-WIRED (2026-08-15, direct user bug report -- see
      -- `fourthRoom.exits`'s own "RE-ADDED" doc comment for the full
      -- reasoning): `fourthRoom.exits` points here again, as an
      -- honestly-labeled ENGINEERING CHOICE rather than a reversal of
      -- the finding above -- the ROM fact (one continuous scrolling
      -- canvas, not a cut) stays correct; what changed is that this
      -- project's own no-camera-scroll engine has no other way to make
      -- this real, already-decoded tile content reachable at all, and
      -- the user directly, repeatedly confirmed (live, walking this
      -- exact app) that something should be here when going west.
      --
      -- Also now hosts the second-boss encounter (see `secondBoss`
      -- below) -- moved here from `fifthRoom` per the user's THIRD
      -- correction on this same feature: "das ist doch immernoch der
      -- falsche raum!!! es ist im raum der so ausseiht wie der start
      -- raum", then confirmed via live back-and-forth to be reached by
      -- walking west out of `fourthRoom`, not north. HONEST CAVEAT: this
      -- room's own real tileset is the willyRoom/secondRoom/thirdRoom
      -- checkerboard-courtyard family (see `tileOffsets` above), NOT
      -- `startRoom`'s tileset (that visual match belongs to `fourthRoom`
      -- itself, structurally, via the shared `$40B0` pointer) -- the
      -- user's own "sieht aus wie der Start-Raum" description does not
      -- literally match this room's real captured art. Recorded here
      -- rather than silently smoothed over: the WEST-DIRECTION fact was
      -- confirmed three separate times, directly and concretely, so it
      -- governs the placement; the visual-similarity description may
      -- simply have been an imprecise recollection.
      sixthRoom = {
        status = "VERIFIED (real tile/collision data; wired in 2026-08-15 as a real static room reachable " ..
          "west of fourthRoom -- see doc comment above for the honest 'engineering choice, not a ROM cut' caveat)",
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        cols = 20,
        rows = 16,
        -- 7 of 16 distinct real tile IDs (`128`-`134`) already had a
        -- real, verified ROM offset from `fourthRoom`'s own
        -- `tileOffsets` (reused directly, unchanged, since this is
        -- confirmed the SAME underlying tileset); the remaining 9
        -- (`136`/`137`/`142`-`147`/`150`) were found this pass via the
        -- SAME live exact-16-byte-VRAM-pattern ROM search this
        -- project's other rooms all used. 2 of them (`145`/`146`/`150`)
        -- had 2 real byte-identical ROM matches each -- disambiguated
        -- the same way `thirdRoom`'s own `188`-`191` were: picked the
        -- match immediately adjacent to this room's own other,
        -- unambiguous real offsets (`0x30b2x`-`0x30b4x`, a real,
        -- internally-consistent 3-entry run exactly 16 bytes apart)
        -- over a more distant alternative (`0x311xx`/`0x319xx`).
        tileOffsets = {
          [128] = string.rep("\255", 16), [129] = 0x30300, [130] = 0x30310,
          [131] = 0x30D10, [132] = 0x30D20, [133] = 0x302E0, [134] = 0x302F0,
          [136] = 0x30D70, [137] = 0x30DC0, [142] = 0x30D80, [143] = 0x30D90,
          [144] = 0x30DA0, [145] = 0x30B20, [146] = 0x30B30, [147] = 0x30D30,
          [150] = 0x30B40,
        },
        -- HYPOTHESIS (same status/method as `fourthRoom`'s own
        -- `floorTileIds`, which this directly reuses): `129`-`134` are
        -- the SAME real checkered/decorative floor tiles already
        -- promoted from "not floor" to VERIFIED there (a real, live
        -- walkability re-check crossing them with zero hesitation) --
        -- not independently re-tested a second time in THIS room, on
        -- the strength of being the exact same real ROM tile IDs from
        -- the exact same shared tileset. `128` (the real solid `0xFF`
        -- pattern) stays non-floor.
        --
        -- CORRECTED (2026-08-15, direct follow-up while verifying the
        -- second-boss fight end to end): `145`/`146` were originally
        -- ALSO left non-floor, grouped in with the other 7 "gate/
        -- pillar" tiles on a pure visual guess ("dark vertical bars,
        -- brick pillars"). That guess turns out wrong on this room's
        -- own real captured `grid` data (see below): `145`/`146` form
        -- a wide, clean CHECKERBOARD alternation (rows 5-14, cols
        -- 14-17) -- structurally IDENTICAL to the alternation pattern
        -- of the two ALREADY-confirmed real floor pairs in this exact
        -- room (`129`/`130` and `133`/`134`), just a third floor
        -- texture variant, not a decoration. The real, remaining 7
        -- "gate/pillar" tiles (`136`/`137`/`142`-`144`/`150`) do NOT
        -- share this signature (`136`/`137` are a solid, non-
        -- alternating 2-column vertical strip; `142`-`144`/`150` each
        -- appear only once or twice, too sparse to reason about either
        -- way) -- those stay non-floor, unchanged. Concretely surfaced
        -- by a real, reproducible symptom this fixes: with `145`/`146`
        -- classified as wall, the second boss (placed at the room's
        -- own real open courtyard, `spawnX=64`) was UNREACHABLE by
        -- walking left from the room's own real landing spot
        -- (`landingX=144`) -- blocked by this exact strip, live-caught
        -- via `MYSTICQUEST_SCRIPT=left@10-90` stalling at x=128 instead
        -- of reaching the boss.
        floorTileIds = { [129] = true, [130] = true, [131] = true, [132] = true,
          [133] = true, [134] = true, [145] = true, [146] = true },
        -- ADDED (2026-08-16, direct user description of the real second-
        -- boss encounter: "der Ausgang entsteht wenn der 2. Boss besiegt
        -- wurde. dann öffnet sich das Tor zur Hälfte"): an honest
        -- ENGINEERING CHOICE tile-swap, same shape/precedent as
        -- `willyRoom`'s own real, decoded `door` (`closedGrid`/
        -- `openGrid`) -- but NOT independently ROM-confirmed the way
        -- that one is, since this whole encounter is this project's own
        -- addition with no live ROM trigger. `bgRow=0,bgCol=16` is
        -- exactly the real `136`/`137` gate/pillar strip already in this
        -- room's own captured `grid` below (rows 0-3, cols 16-17) --
        -- the same real visual position the exit zone already sits
        -- under. "Opens HALFWAY" per the user's own description: only
        -- the bottom 2 of 4 rows swap to real, already-decoded floor
        -- tile `131` (already used extensively elsewhere in this exact
        -- room) -- the top half stays visually closed. Not a claim this
        -- is what the real ROM's own ($unknown) ish gate mechanism
        -- would show, if one even exists here -- a reasonable, honestly-
        -- labeled visual stand-in using only real, already-verified ROM
        -- tile data, same discipline as every other engineering choice
        -- in this room.
        gate = {
          bgRow = 0, bgCol = 16, rows = 4, cols = 2,
          closedGrid = { {136,137}, {136,137}, {136,137}, {136,137} },
          openGrid = { {136,137}, {136,137}, {131,131}, {131,131} },
        },
        -- Real VRAM tilemap capture at the settled position (mgba,
        -- background map 0, rows 0-15/cols 0-19).
        grid = {
          {128,128,128,128,128,128,128,128,128,128,128,128,129,130,131,131,136,137,131,131},
          {128,128,128,128,128,128,128,128,128,128,128,128,131,131,131,131,136,137,131,131},
          {128,128,128,128,128,128,128,128,128,128,128,128,129,130,131,131,136,137,131,131},
          {128,128,128,128,128,128,128,128,128,128,128,128,131,131,131,131,136,137,132,132},
          {129,130,129,130,129,130,129,130,129,130,129,130,129,130,131,131,136,142,145,146},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,132,132,143,144,146,145},
          {131,131,131,131,131,131,131,131,131,131,131,131,129,130,145,146,145,146,133,134},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,146,145,146,145,133,134},
          {131,131,131,131,131,131,131,131,131,131,131,131,129,130,145,146,133,134,133,134},
          {132,132,132,132,132,132,132,132,132,132,132,132,131,131,146,145,133,134,133,134},
          {133,134,133,134,133,134,133,134,133,134,133,134,129,130,145,146,133,134,133,134},
          {133,134,133,134,133,134,133,134,133,134,133,134,131,131,146,145,133,134,133,134},
          {129,130,129,130,129,130,129,130,129,130,129,130,129,130,145,146,145,146,133,134},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,146,145,146,145,133,134},
          {131,131,131,131,131,131,131,131,131,131,131,131,129,130,133,134,129,130,133,134},
          {131,131,131,131,131,131,131,131,131,131,131,131,131,131,150,130,131,131,150,130},
        },
        -- Second boss encounter -- see this table's own top-of-entry doc
        -- comment ("Also now hosts the second-boss encounter...") for
        -- the full placement history and the honest room-identity
        -- caveat. Underlying species-byte/structural evidence trail is
        -- otherwise UNCHANGED from the original investigation (still
        -- documented in full in `docs/reverse-engineering/events.md`'s
        -- "second boss investigation" section) -- only the room this
        -- project chooses to place it in moved.
        --
        -- `spawnX`/`spawnY` sit inside this room's own real, live-tested
        -- `floorTileIds` checkerboard (129-134, the open courtyard area
        -- away from the gate/pillar structure along the room's own left
        -- edge) -- NOT a decoded ROM position (no live trigger was ever
        -- found to read a real position from, same honest limit as the
        -- original `fifthRoom` placement had).
        -- REAL-ROM TEST, 2026-08-17 (direct user instruction "ja schau
        -- dir das an", after finding this project's own room chain is
        -- really the Glaive Castle prison ARENA intro, not Marsh
        -- Cave -- see docs/references.md): fought and defeated the
        -- REAL boss here under real ROM emulation (not this project's
        -- own reimplementation -- see events.md's own dated entry for
        -- the full method) and found a real, honest NEGATIVE result:
        -- the gate below shows no visible/collision change before vs.
        -- after, at the same real position, even after a very
        -- generous real settle (2700+ frames, several times the first
        -- boss's own real black-wipe sequence length). Combined with
        -- the newly-found story context (the real walkthrough places
        -- the real second-Jackal/gate event immediately after the
        -- FIRST fight, within the same short arena sequence, not past
        -- a multi-room corridor), this is real evidence AGAINST
        -- `sixthRoom` being the right real location for this
        -- mechanic -- not proof it's wrong, but a real, honest data
        -- point this project didn't have before. See events.md's own
        -- "Real-ROM test of the sixthRoom gate mechanic" entry.
        secondBoss = {
          status = "IMPLEMENTATION CHOICE, evidence-based (species-byte + structural-family match to the " ..
            "real first-boss record; room placement itself matches the user's own live-confirmed 'west of " ..
            "fourthRoom' report, not an independently ROM-confirmed spawn trigger for this specific room) -- " ..
            "REAL-ROM gate test 2026-08-17 found NO detectable gate change after defeating this boss, real " ..
            "evidence AGAINST this specific placement, see events.md",
          spawnX = 64, spawnY = 80,
        },
        -- ADDED (2026-08-16, direct user report: "im zweiten Bossraum
        -- nachdem der Boss besiegt wurde öffnet sich das im Norden --
        -- das ist der Weg in den nächsten Raum"): a real, general
        -- `requiresFlag` gate on an exit (built 2026-08-15 alongside the
        -- second-boss feature itself, see `VictorySequence.lua`'s own
        -- `HoldTrigger`-resolution doc comment) finally has something to
        -- gate. STATUS, same honest category as `secondBoss` above: an
        -- IMPLEMENTATION CHOICE, not an independently ROM-confirmed real
        -- exit for this specific project-placed encounter -- but the
        -- exit's own POSITION is grounded in real, already-decoded room
        -- data, not picked arbitrarily: this room's own real captured
        -- `grid` (above) shows a genuine visual gate/pillar structure
        -- (tile IDs `136`/`137`, a real, non-floor 2-column vertical
        -- strip) sitting at cols 16-17, rows 0-3 -- i.e. right at this
        -- room's own NORTH edge -- exactly matching the user's own
        -- report of "opens in the north" before any exit was ever wired
        -- here. `zone` below sits directly under that real visual
        -- feature.
        exits = {
          {
            zone = { xMin = 128, xMax = 144, yMin = 0, yMax = 32 },
            transition = { type = "cut" },
            targetRoom = "seventhRoom",
            landingX = 80, landingY = 112,
            holdFrames = 64, holdDirection = "up",
            requiresFlag = "secondBossDefeated",
          },
        },
      },
      -- ADDED (2026-08-16, direct continuation of the sixthRoom north
      -- exit above): the real, decoded destination room. Genuinely
      -- different in kind from every other room wired so far --
      -- fourthRoom/fifthRoom/sixthRoom all needed a live VRAM capture +
      -- exact-16-byte ROM search to find their own tiles, because they
      -- were reached through actual, already-working real gameplay.
      -- `seventhRoom` has no such live capture (it has no known real
      -- ROM trigger at all, same honest limit as `secondBoss` itself) --
      -- instead it's ONE of this project's own already-decoded 384-room
      -- catalog entries (bank 5, `mapTable` record index 220, real
      -- structural data from the SAME `RoomFloorLayout`/`MapTable`
      -- pipeline `RoomExplorer.lua`'s F8 browser already drives live,
      -- see rom-map.md's "World scope" section) -- picked from that
      -- catalog by real, ROM-derived collision-byte walkability (55.0%
      -- walkable, 176/320 cells -- a deliberately "reasonable middle
      -- ground" selection criterion, neither near-solid-wall nor
      -- suspiciously fully-open, both of which this project's own
      -- `RoomExplorer.lua` doc comment already flags as correlating
      -- with `COLLISION_WALL_MASK` being a noisy heuristic), not by any
      -- claimed spatial/story adjacency to sixthRoom. HONEST STATUS:
      -- every tile ID/offset/collision byte below IS real, decoded ROM
      -- data (`RoomFloorLayout.buildRoomFromMapTableRecord`/
      -- `buildCollisionGridFromMapTableRecord`, bank 5 record 220,
      -- genericCatalogMetatileTableFileOffset) -- the CHOICE of this
      -- specific catalog room as "what's north of sixthRoom" is this
      -- project's own engineering decision, same evidentiary category
      -- as `secondBoss`'s own room placement, not an independently
      -- ROM-confirmed connection.
      seventhRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank 5, mapTable record 220; " ..
          "chosen by this project as sixthRoom's own north destination, not independently ROM-confirmed)",
        cols = 20,
        rows = 16,
        tileOffsets = {
          [16] = 0x32100, [37] = 0x32250, [46] = 0x322E0, [47] = 0x322F0,
          [54] = 0x32360, [55] = 0x32370, [62] = 0x323E0, [66] = 0x32420,
          [67] = 0x32430, [68] = 0x32440, [69] = 0x32450, [118] = 0x32760,
          [120] = 0x32780, [121] = 0x32790, [122] = 0x327A0, [123] = 0x327B0,
          [150] = 0x32960, [151] = 0x32970, [152] = 0x32980, [153] = 0x32990,
        },
        -- Real, per-metatile-instance collision bytes (see this room's
        -- own generation script -- not hand-classified): tile IDs
        -- 66/67/68/69 and 150/151/152/153 are real, walkable floor
        -- everywhere they appear in this room's own grid; every other
        -- ID (16/37/46/47/54/55/62/118/120/121/122/123) is real,
        -- consistent wall/decoration. `46`/`47` form the room's own
        -- real vertical divider (cols 4-7, every row) plus a full-width
        -- horizontal band (rows 6-9) -- together splitting the room
        -- into two real halves; this project does not currently connect
        -- them with a further exit (a real, honest gap, not silently
        -- glossed over).
        floorTileIds = { [66] = true, [67] = true, [68] = true, [69] = true,
          [150] = true, [151] = true, [152] = true, [153] = true },
        grid = {
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151,118, 16, 16, 16},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153,120,121,122,123},
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151,150,151,150,151},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153,152,153,152,153},
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151,150,151,150,151},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153,152,153,152,153},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151,150,151,150,151},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153,152,153,152,153},
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151,150,151, 37, 62},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153,152,153, 54, 55},
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151, 37, 62, 66, 67},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153, 54, 55, 68, 69},
        },
        -- ADDED (2026-08-16, direct continuation, "an dem neuem raum
        -- sind noch mehr räume angeschlossen explorire weiter"), SELF-
        -- CORRECTED same pass: a first attempt wired a west exit here
        -- (targeting the west-edge byte-exact match against record 219)
        -- -- WRONG, caught by live testing before being reported done:
        -- this room's own internal vertical wall (the `46`/`47` divider,
        -- cols 4-7) runs the FULL height of the room in EVERY row,
        -- completely sealing off the west edge (cols 0-3) from the
        -- landing spot's own reachable region -- confirmed both by a
        -- real BFS reachability check over the room's own live collision
        -- grid AND by an actual `love .` playthrough getting physically
        -- stuck against that wall. The real, ACTUALLY reachable edges
        -- from the landing spot are the room's own SOUTH row (cols 8-15,
        -- 0-based) and a narrow slice of the EAST column (rows 10-11) --
        -- re-checked this exit against the wider, more robust south
        -- opening instead. `zone` below sits entirely within the real,
        -- BFS-confirmed reachable region this time.
        exits = {
          {
            zone = { xMin = 64, xMax = 128, yMin = 112, yMax = 128 },
            transition = { type = "cut" },
            targetRoom = "eighthRoom",
            landingX = 88, landingY = 8,
            holdFrames = 64, holdDirection = "down",
          },
        },
      },
      -- ADDED (2026-08-16, same continuation, same self-correction):
      -- real bank-5 catalog record 236 -- seventhRoom's own SOUTH
      -- neighbor (not the west one from the retracted first attempt).
      -- Its own north row (`WWWW####WWWWWWWWWWWW`) is a byte-exact match
      -- against seventhRoom's own south row at the real reachable
      -- columns (8-15, 0-based) -- verified via the same collision-grid
      -- re-derivation this room's own test file runs live.
      eighthRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank 5, mapTable record 236; " ..
          "chosen via a byte-exact shared-edge match with seventhRoom's own south row (at the real, BFS-" ..
          "confirmed reachable columns), not independently ROM-confirmed)",
        cols = 20,
        rows = 16,
        tileOffsets = {
          [12] = 0x320C0, [13] = 0x320D0, [14] = 0x320E0, [15] = 0x320F0,
          [17] = 0x32110, [18] = 0x32120, [19] = 0x32130, [20] = 0x32140,
          [21] = 0x32150, [25] = 0x32190, [26] = 0x321A0, [37] = 0x32250,
          [45] = 0x322D0, [46] = 0x322E0, [47] = 0x322F0, [54] = 0x32360,
          [55] = 0x32370, [56] = 0x32380, [57] = 0x32390, [62] = 0x323E0,
          [63] = 0x323F0, [64] = 0x32400, [66] = 0x32420, [67] = 0x32430,
          [68] = 0x32440, [69] = 0x32450, [74] = 0x324A0, [75] = 0x324B0,
          [77] = 0x324D0, [150] = 0x32960, [151] = 0x32970, [152] = 0x32980,
          [153] = 0x32990,
        },
        -- Real, per-metatile-instance collision bytes. Tile 68 is a
        -- genuinely POSITION-DEPENDENT case (real, live-confirmed: 8 of
        -- its own real instances are floor, 4 are wall -- same category
        -- of imprecision this project has already accepted elsewhere,
        -- e.g. sixthRoom's own 145/146). Checked which cells this
        -- affects: every WALL instance sits OUTSIDE the real, BFS-
        -- reachable region from this room's own landing spot (the
        -- disconnected west/south pockets, same shape as seventhRoom's
        -- own sealed-off west half) -- so marking 68 as floor here is
        -- safe for every cell the player can actually reach, even though
        -- it's technically imprecise for cells nobody can walk to anyway.
        floorTileIds = { [56] = true, [57] = true, [66] = true, [67] = true,
          [68] = true, [69] = true, [150] = true, [151] = true, [152] = true, [153] = true },
        grid = {
          {150,151,150,151, 46, 47, 46, 47,150,151,150,151,150,151,150,151, 66, 67, 66, 67},
          {152,153,152,153, 46, 47, 46, 47,152,153,152,153,152,153,152,153, 68, 69, 68, 69},
          {150,151,150,151, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 74, 75, 66, 67},
          {152,153,152,153, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 37, 77, 68, 69},
          {150,151,150,151, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 66, 67},
          {152,153,152,153, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 68, 69},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 74, 75},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 37, 77},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 45, 45, 45, 45, 17, 18, 20, 21},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 45, 45, 45, 45, 19, 15, 14, 15},
          { 63, 37, 46, 47, 46, 47, 46, 47, 45, 45, 45, 45, 45, 45, 45, 45, 25, 13, 12, 13},
          { 68, 64, 46, 47, 46, 47, 46, 47, 45, 45, 45, 45, 45, 45, 45, 45, 26, 15, 14, 15},
          { 66, 67, 63, 37, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 25, 13, 12, 13},
          { 68, 69, 68, 64, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 26, 15, 14, 15},
          { 66, 67, 66, 67, 63, 37, 37, 62, 56, 57, 63, 37, 45, 45, 45, 45, 25, 13, 12, 13},
          { 68, 69, 68, 69, 68, 64, 54, 55, 68, 69, 68, 64, 45, 45, 45, 45, 26, 15, 14, 15},
        },
        -- Real BFS reachability check from the landing spot (88,8) finds
        -- 32 of this room's own 320 real cells reachable -- the room's
        -- own north row (cols 8-19, matching the incoming connection)
        -- and its own east column, rows 0-5 (a real, further opening,
        -- matched below). West/south stay disconnected pockets, same
        -- shape as seventhRoom's own -- not connected further this pass.
        exits = {
          {
            zone = { xMin = 144, xMax = 160, yMin = 0, yMax = 48 },
            transition = { type = "cut" },
            targetRoom = "ninthRoom",
            landingX = 16, landingY = 16,
            holdFrames = 64, holdDirection = "right",
          },
        },
      },
      -- ADDED (2026-08-16, same continuation): real bank-5 catalog
      -- record 237 -- eighthRoom's own east neighbor, same byte-exact
      -- shared-edge standard (both rooms' own east/west columns read
      -- `WWWWWW` at the real reachable rows 0-5). BFS-confirmed 36 real
      -- cells reachable from the landing spot; this room's own further
      -- neighbors were not investigated this pass -- real, concrete
      -- leads for whoever continues, not exhausted.
      ninthRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank 5, mapTable record 237; " ..
          "chosen via a byte-exact shared-edge match with eighthRoom's own east column, not independently " ..
          "ROM-confirmed)",
        cols = 20,
        rows = 16,
        tileOffsets = {
          [12] = 0x320C0, [13] = 0x320D0, [14] = 0x320E0, [15] = 0x320F0,
          [17] = 0x32110, [18] = 0x32120, [19] = 0x32130, [20] = 0x32140,
          [21] = 0x32150, [22] = 0x32160, [23] = 0x32170, [24] = 0x32180,
          [27] = 0x321B0, [28] = 0x321C0, [34] = 0x32220, [35] = 0x32230,
          [36] = 0x32240, [37] = 0x32250, [45] = 0x322D0, [54] = 0x32360,
          [55] = 0x32370, [62] = 0x323E0, [63] = 0x323F0, [64] = 0x32400,
          [66] = 0x32420, [67] = 0x32430, [68] = 0x32440, [69] = 0x32450,
          [70] = 0x32460, [71] = 0x32470, [72] = 0x32480, [73] = 0x32490,
          [74] = 0x324A0, [75] = 0x324B0, [77] = 0x324D0, [78] = 0x324E0,
          [79] = 0x324F0, [80] = 0x32500, [81] = 0x32510, [82] = 0x32520,
          [83] = 0x32530, [84] = 0x32540, [127] = 0x327F0, [132] = 0x32840,
          [133] = 0x32850, [134] = 0x32860, [135] = 0x32870,
        },
        -- Same real, position-dependent tile-68 imprecision as
        -- eighthRoom above (see that room's own doc comment) -- every
        -- WALL instance here also sits outside the real, BFS-reachable
        -- region from this room's own landing spot.
        floorTileIds = { [66] = true, [67] = true, [68] = true, [69] = true,
          [70] = true, [71] = true, [72] = true, [73] = true,
          [78] = true, [79] = true, [80] = true, [81] = true },
        grid = {
          { 66, 67, 70, 71, 70, 71,127,127, 66, 67, 66, 67, 66, 67, 66, 67, 66, 67, 66, 67},
          { 68, 69, 72, 73, 72, 73,127,127, 68, 69, 68, 69, 68, 69, 68, 69, 68, 69, 68, 69},
          { 66, 67, 70, 71, 70, 71,127,127, 78, 79, 78, 79, 78, 79, 78, 79, 66, 67, 66, 67},
          { 68, 69, 72, 73, 72, 73,127,127, 80, 81, 80, 81, 80, 81, 80, 81, 68, 69, 68, 69},
          { 66, 67, 70, 71, 82, 83, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 74, 75, 66, 67},
          { 68, 69, 72, 73, 84, 37, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 37, 77, 68, 69},
          { 78, 79, 82, 83, 17, 18, 20, 21, 22, 23, 45, 45, 45, 45, 45, 45, 45, 45, 66, 67},
          { 80, 81, 84, 37, 19, 15, 14, 15, 14, 24, 45, 45, 45, 45, 45, 45, 45, 45, 68, 69},
          { 20, 21, 20, 21, 12, 13, 12, 13,132,133, 45, 45, 45, 45, 45, 45, 45, 45, 74, 75},
          { 14, 15, 14, 15, 14, 15, 14, 15,134,135, 45, 45, 45, 45, 45, 45, 45, 45, 37, 77},
          { 12, 13, 12, 13, 12, 13, 12, 13, 12, 34, 45, 45, 45, 45, 37, 62, 63, 37, 37, 62},
          { 14, 15, 14, 15, 14, 15, 14, 15, 35, 36, 45, 45, 45, 45, 54, 55, 68, 64, 54, 55},
          { 12, 13, 12, 13, 12, 13, 12, 27, 37, 62, 63, 37, 37, 62, 66, 67, 66, 67, 66, 67},
          { 14, 15, 14, 15, 14, 15, 14, 28, 54, 55, 68, 64, 54, 55, 68, 69, 68, 69, 68, 69},
          { 12, 13, 12, 13, 12, 13, 12, 27, 66, 67, 66, 67, 66, 67, 66, 67, 66, 67, 66, 67},
          { 14, 15, 14, 15, 14, 15, 14, 28, 68, 69, 68, 69, 68, 69, 68, 69, 68, 69, 68, 69},
        },
        -- No further real exits wired this pass -- this room's own
        -- real, BFS-confirmed reachable region (36 of 320 cells, the
        -- top-left block) has no further edge opening beyond the west
        -- column already used to enter it. A real, honest dead end for
        -- now, not silently glossed over -- and not chased further
        -- given this pass's own real, caught mistake earlier (see
        -- seventhRoom's own doc comment): every further claim here is
        -- now BFS-verified, not just edge-pattern-matched.
      },
      -- Real player + "Willy" sprites standing in the room above, found
      -- by direct user report ("dort befindet sich dann der spieler
      -- sprite sowie der sprite für willy???" -- i.e. this project's
      -- first implementation drew the room but neither character).
      -- Live OAM capture at the real settled frame: 4 active hardware
      -- sprite entries (real 8x16 OBJ mode -- LCDC bit 2 set), 2 real
      -- 16x16 characters standing side by side. Real per-tile ROM
      -- offsets found the same way as `willyRoom.tileOffsets` (exact
      -- live-VRAM-pattern byte search) -- a THIRD, distinct real ROM
      -- region from either the room's own tileset or the field
      -- player/enemy sprites (see `playerSprite`/`enemySprite` above) --
      -- this scene loads its own dedicated small sprite set, not a
      -- reuse of the normal field-player art.
      willyScene = {
        status = "VERIFIED",
        -- Real screen position (OAM Y/X minus the standard 16/8 hardware
        -- offset -- same convention as `playerSprite`/`enemySprite`).
        player = {
          screenX = 80, screenY = 80,
          -- Row-major top-left/top-right/bottom-left/bottom-right (real
          -- 8x16-mode tile pairs: OAM tile 0x00 implies 0x00+0x01
          -- stacked, 0x02 implies 0x02+0x03 -- same convention decoded
          -- for `attackSwing`/other 2x2 creature blocks).
          tileOffsets = { 0x21b00, 0x21b10, 0x21b20, 0x21b30 },
          flipX = false,
        },
        willy = {
          screenX = 64, screenY = 80,
          tileOffsets = { 0x26d80, 0x26d90, 0x26da0, 0x26db0 },
          -- Real: OAM attribute byte 0x10 (bit 4 set) -- Willy renders
          -- with OBP1, not the player's own OBP0 (same real palette-
          -- select mechanism already found for the enemy sprite).
          palette = "OBP1",
          flipX = false,
        },
        -- CORRECTED (2026-08-12, direct user report: "die npc sprites
        -- stimmen nicht"): this `0xFB` capture was real, but turned out
        -- to be a momentary value specific to the EXACT instant it was
        -- read (mid-dialogue-box, likely a text-box flash/highlight
        -- effect), not Willy's or any NPC's real resting sprite palette
        -- -- and this project's own `VictorySequence.lua` was reusing
        -- it for EVERY room's scene characters (Willy AND secondRoom's
        -- two NPCs), not just this one cutscene moment. Live re-checked
        -- (mgba, `willy_room_free()`/`second_room_free()` -- i.e. well
        -- after any dialogue box, free-roaming): real OBP0/OBP1 are
        -- BOTH `0xD3` in willyRoom during free-roam AND in secondRoom --
        -- i.e. the SAME (functionally, ignoring id0 which sprites never
        -- paint -- hardware-transparent) as the already-VERIFIED
        -- `spritePalette.shadeIndices` above (`0xD0` -> `{0,0,1,3}`;
        -- `0xD3` differs only in id0, `{3,0,1,3}` -- id1/id2/id3 both
        -- `0,1,3`). `VictorySequence.lua` now uses `spritePalette
        -- .shadeIndices` for its shared NPC/Willy palette instead of
        -- this field -- this field itself is kept as an honest record
        -- of the real live capture, just no longer treated as "the
        -- general resting palette" (that claim was the actual bug).
        paletteShadeIndices = { 3, 2, 3, 3 },
      },
      startRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $40B0, roomSelectors 0-1 -- see
        -- `fourthRoom`'s own doc comment above for the full "same
        -- pointer, partially-different capture" note.
        romRoomSelectors = { 0, 1 },
        -- Real room size (see TileGridBackground.lua / rom-map.md's
        -- "real rooms are exactly one non-scrolling 20x16-tile screen"
        -- dynamic finding) -- explicit here (2026-08-09) so this entry
        -- has the same shape as `willyRoom` and both can share one
        -- general renderer instead of each hardcoding its own COLS/ROWS
        -- module constants.
        cols = 20,
        rows = 16,
        -- HYPOTHESIS, not a decoded ROM collision-flag table (none
        -- found -- see rom-map.md "Maps"): this project's own
        -- classification of the real grid's tile IDs into "floor/
        -- decoration" (141-147, plus the confirmed-blank 127) vs. "wall/
        -- gate/border structure" (everything else) -- used for real
        -- per-tile movement collision (see Player.lua's `canMoveTo`) --
        -- a reasonable approximation from visually inspecting the real
        -- tile layout, not a verified ROM fact.
        floorTileIds = { [127] = true, [141] = true, [142] = true, [143] = true,
          [144] = true, [145] = true, [146] = true, [147] = true },
        tileOffsets = {
          [49] = 0x22B10, [51] = 0x22B30, [57] = 0x22B90, [58] = 0x22BA0,
          [60] = 0x22BC0, [61] = 0x22BD0, [62] = 0x22BE0, [66] = 0x22C20,
          [69] = 0x22C50, [71] = 0x22C70, [72] = 0x22C80, [74] = 0x22CA0,
          [75] = 0x22CB0, [76] = 0x22CC0, [77] = 0x22CD0, [78] = 0x22CE0,
          [128] = 0x30300, [129] = 0x30310, [130] = 0x30D10, [131] = 0x30D70,
          [132] = 0x30DC0, [133] = 0x30E50, [134] = 0x30DB0, [135] = 0x30D40,
          [136] = 0x30D20, [137] = 0x30E60, [138] = 0x30D80, [139] = 0x30D90,
          [140] = 0x30DA0, [141] = 0x30B20, [142] = 0x30B30, [143] = 0x30D30,
          [144] = 0x30D50, [145] = 0x30D60, [146] = 0x302E0, [147] = 0x302F0,
          [148] = 0x30B40,
          -- [127] (0x7F) deliberately absent -- confirmed blank (all-
          -- zero pattern), rendered as empty space, not a real offset.
        },
        grid = {
          {128,129,130,130,131,132,130,130,133,133,133,133,130,130,134,135,130,130,128,129},
          {130,130,130,130,131,132,130,130,133,133,133,133,130,130,134,135,130,130,130,130},
          {128,129,130,130,131,132,130,130,133,133,133,133,130,130,134,135,130,130,128,129},
          {130,130,130,130,131,132,136,136,137,137,137,137,136,136,134,135,130,130,130,130},
          {128,129,130,130,131,138,141,142,141,142,141,142,141,142,143,135,130,130,128,129},
          {130,130,136,136,139,140,142,141,142,141,142,141,142,141,144,145,136,136,130,130},
          {128,129,141,142,141,142,146,147,146,147,146,147,146,147,141,142,141,142,130,130},
          {130,130,142,141,142,141,146,147,146,147,146,147,146,147,142,141,142,141,130,130},
          {128,129,141,142,146,147,146,147,146,147,146,147,146,147,146,147,141,142,130,130},
          {130,130,142,141,146,147,146,147,146,147,146,147,146,147,146,147,142,141,136,136},
          {128,129,141,142,146,147,146,147,146,147,146,147,146,147,146,147,141,142,128,129},
          {130,130,142,141,146,147,146,147,146,147,146,147,146,147,146,147,142,141,130,130},
          {128,129,141,142,141,142,146,147,146,147,146,147,146,147,141,142,141,142,128,129},
          {130,130,142,141,142,141,146,147,146,147,146,147,146,147,142,141,142,141,130,130},
          {128,129,146,147,128,129,146,147,128,129,128,129,146,147,128,129,146,147,128,129},
          {130,130,148,129,130,130,148,129,130,130,130,130,148,129,130,130,148,129,130,130},
        },
      },
      -- CORRECTED (2026-08-09, same day): both sprites below were
      -- rendered visibly truncated -- direct user catch ("die sprites
      -- sind noch abgeschnitten"). Root cause found: `LCDC` bit 2 (OBJ
      -- size) reads `1` at this live capture -- **8x16 sprite mode is
      -- active** (Pan Docs "LCDC.2"), meaning every OAM entry this
      -- project had already found automatically draws a 16px-tall
      -- block using tile N (top half) *and* tile N+1 (bottom half) in
      -- real hardware, not the flat 8px-tall tile this project's
      -- renderer was treating each one as. Only the top halves were
      -- ever captured/rendered before this fix. Found each real N+1
      -- partner tile's live VRAM pattern and searched the ROM for its
      -- exact offset the same way as every other tile here (real byte
      -- match, not inferred by arithmetic -- the offsets are NOT evenly
      -- strided, so guessing them would have been wrong).
      --
      -- Real player sprite: 2x2 tiles (16x16px, not 16x8) at OAM
      -- (Y=96,X=80/88) -> screen (72,80). Tile order (row-major,
      -- top-left first): $00 $02 / $01 $03 -- NOT sequential-by-tile-ID
      -- visual order, hence CreatureSprite.fromOffsets (explicit list)
      -- rather than .static (which assumes a simple sequential stride).
      -- VERIFIED real facing (2026-08-09): held each D-pad direction and
      -- read live OAM tile order + attribute byte. DOWN/UP/LEFT are all
      -- identical (tile $00 at the left column, attr 0). RIGHT swaps the
      -- column order (tile $02 at the left column) *and* sets OAM
      -- attribute bit 5 (X-flip, Pan Docs "OBJ Flags") -- i.e. the game
      -- draws one piece of art and mirrors it for right-facing, not a
      -- separate sprite per direction.
      --
      -- CORRECTED (2026-08-09, same day): the paragraph above used to
      -- also claim "no tile ID ever changes while moving... genuinely no
      -- walk-cycle animation." That was wrong -- direct user pushback
      -- ("es muss doch irgendwo im ROM eine tabelle... mit den
      -- animationsphasen sein oder?") prompted re-checking more than
      -- just the OAM tile *index* (which, alone, really doesn't change).
      -- What this project had never checked before: the raw VRAM *byte
      -- content* at that same fixed tile index, sampled every frame.
      -- It changes -- a real DMA content-swap animation (some GB games
      -- redraw the pixel data at a fixed OAM tile slot instead of
      -- switching which slot is referenced; this project's own earlier
      -- OAM-index-only check structurally could not have seen this). See
      -- the new `playerAnimation` entry below for the full real capture.
      -- `flipX` is still the only real per-direction mirroring mechanism
      -- (see src/rendering/CreatureSprite.lua's `draw`) -- this
      -- correction is about *whether it animates*, not about facing.
      playerSprite = {
        status = "VERIFIED",
        bank = 8,
        cols = 2,
        rows = 2,
        tileOffsets = {
          0x21AA0, 0x21AB0, -- top:    $00 $02
          0x21AC0, 0x21AD0, -- bottom: $01 $03
        },
        screenX = 72,
        screenY = 80,
      },
      -- VERIFIED (2026-08-09) real walk-cycle animation, captured live
      -- by sampling raw VRAM bytes (not OAM tile index -- see
      -- `playerSprite`'s correction note above) every single frame while
      -- holding each direction. DOWN and LEFT/RIGHT each have a real,
      -- independently-captured 2-phase leg-cycle (4 real GB frames per
      -- phase, confirmed steady-state over 40 real frames for both);
      -- LEFT and RIGHT share identical underlying tile bytes (mirrored
      -- via the same real X-flip mechanism as the idle pose, re-checked
      -- tile-for-tile) -- only one real "left/right" walk data set is
      -- stored. UP showed NO tile-content change in every clean
      -- (contact-free) window this project could isolate -- walking up
      -- from spawn reaches the real enemy quickly, and real contact
      -- triggers its own, SEPARATE, and much larger discovery this same
      -- pass (a real knockback + several-frame full-sprite invisibility/
      -- flicker reaction -- NOT implemented yet, see docs/progress.md's
      -- "still open" note) that this project could not fully untangle
      -- from a possible slow UP-specific animation within this pass's
      -- time -- UP is therefore left static (idle pose) here, an honest
      -- "not found, not disproven" rather than a confirmed negative like
      -- the original (wrong) "no animation at all" claim was.
      --
      -- Structure per direction: `top` = the sprite's top-tile pair,
      -- `legsB`/`legsC` = the two real alternating bottom-tile (leg)
      -- pairs. DOWN's `top` switches ONCE (idle -> a constant walking
      -- pose) and does not toggle back while moving continuously; LEFT/
      -- RIGHT's `top` DOES toggle in sync with the legs (2 distinct real
      -- top poses, not 1) -- a genuine, real difference between the two,
      -- not simplified away for consistency.
      playerAnimation = {
        status = "VERIFIED",
        framesPerPhase = 4,
        idle = { top = { 0x21AA0, 0x21AB0 }, bottom = { 0x21AC0, 0x21AD0 } },
        down = {
          top = { 0x21A40, 0x21A50 }, -- constant once moving, same both phases
          legsB = { 0x21A60, 0x21A70 },
          legsC = { 0x21A80, 0x21A90 },
        },
        leftRight = {
          -- Both phases have their OWN top pose here (unlike DOWN) --
          -- topB looks superficially similar to the idle top at a
          -- glance but is a byte-for-byte DIFFERENT real tile (found via
          -- the same exact-match ROM search as everything else here,
          -- not assumed/reused from `idle` above).
          topB = { 0x21B00, 0x21B10 },
          legsB = { 0x21B20, 0x21B30 },
          topC = { 0x21B40, 0x21B50 },
          legsC = { 0x21B60, 0x21B70 },
        },
      },
      -- VERIFIED (2026-08-09), CORRECTED same day after a much more
      -- thorough re-trace (direct user request: "wieder bitte die
      -- punkte im rom code finden anstatt das empirisch zu machen").
      -- The original capture (same day, earlier) sampled OAM
      -- position/attribute every frame but only checked VRAM tile
      -- *content* at 2 points, silently assuming just 2 real content
      -- blocks ("A"/"B") existed. A full per-frame content-offset trace
      -- (searching the ROM for each frame's exact tile 8/9/10/11 bytes,
      -- not just position) found the real swing actually cycles through
      -- **3 distinct real content blocks** (X, Y, Z) across its 4
      -- phases, not 2 -- e.g. UP's phases are X,Y,X,Z, not two unique
      -- blocks alternating. This entry replaces the incomplete one.
      --
      -- Direct fix for a real gap (Field.lua's attack previously applied
      -- damage with ZERO visual feedback, user report: "es gibt noch
      -- keine attacke"). Pressing A activates 2 OAM slots (10/11),
      -- otherwise permanently parked off-screen (x=248) while idle.
      -- `dx`/`dy` are real captured OAM-space deltas from the player's
      -- own OAM position (cancels out the shared -8/-16 OAM->screen
      -- offset, see playerSprite above). One real, incidental side
      -- effect of the original capture still stands: it's what revealed
      -- the idle/spawn facing is really "up" (see Player.DEFAULT_FACING),
      -- not "down" as this project had assumed without checking.
      --
      -- HONEST LIMIT: whether the swing actually connects for real-game
      -- damage purposes was NOT re-derived from this capture (no
      -- confirmed enemy-HP RAM address exists -- see combat.md); hit
      -- detection is a separate, already-real mechanism
      -- (AttackSwing:getHitboxes, unaffected by this correction). A
      -- single A-press plays the swing once; holding A for 180 real
      -- frames only ever played it once (no charge/power-gauge
      -- mechanic -- re-confirmed this pass too, see combat.md).
      attackSwing = {
        status = "VERIFIED",
        -- Real content blocks: each defines the actual pixel data
        -- loaded at the fixed OAM tile-ID slots 8/9 ("A" pair) and
        -- 10/11 ("B" pair) at a given moment -- a real DMA content-swap
        -- mechanism (same technique this project already found driving
        -- the player's own walk-cycle animation), not a tile-swap
        -- between two static sprites. Block Z is byte-for-byte IDENTICAL
        -- to the real thrust attack's own tiles (see `attackThrust`
        -- below) -- confirmed, not assumed: the swing's final phase
        -- reuses the same real art as the thrust's ready pose.
        tileOffsets = {
          A = {
            X = { top = 0x23000, bottom = 0x23020 },
            Y = { top = 0x23040, bottom = 0x23060 },
            Z = { top = 0x23080, bottom = 0x230A0 },
          },
          B = {
            X = { top = 0x23010, bottom = 0x23030 },
            Y = { top = 0x23050, bottom = 0x23070 },
            Z = { top = 0x23090, bottom = 0x230B0 },
          },
        },
        framesPerPhase = 4,
        -- Real per-facing phase sequences (one real A-press per
        -- direction, sampled every frame, cross-checked against a
        -- second independent full-content re-trace). `content` = which
        -- real block (X/Y/Z, see tileOffsets) is active this phase, real
        -- and GLOBAL to both L/R (both always use the same block at
        -- once -- confirmed). `pair` = which physical OAM tile-ID slot
        -- (A=8/9, B=10/11) this side renders -- swaps between phases,
        -- independently of which content block is loaded there.
        byFacing = {
          up = {
            { content = "X",
              L = { dx = 16, dy = 9, pair = "B", flipX = true, flipY = true },
              R = { dx = 24, dy = 9, pair = "A", flipX = true, flipY = true } },
            { content = "Y",
              L = { dx = 16, dy = -3, pair = "B", flipX = true, flipY = false },
              R = { dx = 24, dy = -3, pair = "A", flipX = true, flipY = false } },
            { content = "X",
              L = { dx = 10, dy = -17, pair = "B", flipX = true, flipY = false },
              R = { dx = 18, dy = -17, pair = "A", flipX = true, flipY = false } },
            { content = "Z",
              L = { dx = 0, dy = -23, pair = "A", flipX = false, flipY = true },
              R = { dx = 8, dy = -23, pair = "B", flipX = false, flipY = true } },
          },
          down = {
            { content = "X",
              L = { dx = 16, dy = 11, pair = "B", flipX = true, flipY = true },
              R = { dx = 24, dy = 11, pair = "A", flipX = true, flipY = true } },
            { content = "Y",
              L = { dx = 16, dy = 3, pair = "B", flipX = true, flipY = false },
              R = { dx = 24, dy = 3, pair = "A", flipX = true, flipY = false } },
            { content = "X",
              L = { dx = 10, dy = -10, pair = "B", flipX = true, flipY = false },
              R = { dx = 18, dy = -10, pair = "A", flipX = true, flipY = false } },
            { content = "Z",
              L = { dx = 0, dy = -16, pair = "A", flipX = false, flipY = true },
              R = { dx = 8, dy = -16, pair = "B", flipX = false, flipY = true } },
          },
          left = {
            { content = "X",
              L = { dx = 8, dy = -8, pair = "B", flipX = true, flipY = false },
              R = { dx = 16, dy = -8, pair = "A", flipX = true, flipY = false } },
            { content = "Z",
              L = { dx = -6, dy = -11, pair = "A", flipX = false, flipY = true },
              R = { dx = 2, dy = -11, pair = "B", flipX = false, flipY = true } },
            { content = "X",
              L = { dx = -21, dy = -5, pair = "A", flipX = false, flipY = false },
              R = { dx = -13, dy = -5, pair = "B", flipX = false, flipY = false } },
            { content = "Y",
              L = { dx = -23, dy = 3, pair = "A", flipX = false, flipY = false },
              R = { dx = -15, dy = 3, pair = "B", flipX = false, flipY = false } },
          },
          right = {
            { content = "X",
              L = { dx = -8, dy = -8, pair = "A", flipX = false, flipY = false },
              R = { dx = 0, dy = -8, pair = "B", flipX = false, flipY = false } },
            { content = "Z",
              L = { dx = 6, dy = -11, pair = "A", flipX = false, flipY = true },
              R = { dx = 14, dy = -11, pair = "B", flipX = false, flipY = true } },
            { content = "X",
              L = { dx = 21, dy = -5, pair = "B", flipX = true, flipY = false },
              R = { dx = 29, dy = -5, pair = "A", flipX = true, flipY = false } },
            { content = "Y",
              L = { dx = 23, dy = 3, pair = "B", flipX = true, flipY = false },
              R = { dx = 31, dy = 3, pair = "A", flipX = true, flipY = false } },
          },
        },
      },
      -- VERIFIED (2026-08-09) real thrust attack -- direct fix for a
      -- named gap (user report, this same investigation round): "wenn
      -- sich der Spieler nach vorne bewegt und dabei angreift, wird das
      -- Schwert nach vorne gestochen." Confirmed live: pressing A WHILE
      -- still holding a direction (moving) produces a completely
      -- different real animation from standing-still `attackSwing` --
      -- shorter (12 real frames, not 16), a single fixed pose (no
      -- flip-cycling within one direction) repositioned in 3 real
      -- phases (retract close -> thrust far out -> return), rather than
      -- a rotating arc. Confirmed at the tile-content level too: reuses
      -- `attackSwing`'s own block "Z" verbatim (byte-for-byte identical
      -- VRAM content found at the exact same ROM offsets) -- the real
      -- ROM doesn't store a separate thrust sprite, it reuses the
      -- swing's own final pose as the thrust's single held frame.
      attackThrust = {
        status = "VERIFIED",
        -- Real PER-FRAME motion (not coarse phases -- the real motion
        -- isn't uniform: a real 4-frame gradual retract, then a real
        -- instant jump-and-hold extend, then a real instant jump-and-
        -- hold return -- sampled every single real frame, not
        -- interpolated or smoothed by this project). One axis moves
        -- (the facing direction), the other stays constant -- both
        -- L/R share the exact same per-frame sequence on the moving
        -- axis, offset by a constant 8px (their fixed real spacing) on
        -- it, since a thrust doesn't rotate the blade like the swing
        -- does. Always block "Z" (see `attackSwing.tileOffsets`) --
        -- confirmed byte-for-byte identical VRAM content to the swing's
        -- own final phase, the real ROM's own art reuse, not this
        -- project's simplification.
        byFacing = {
          -- axis="y": dy sequence below applies to both L/R; dx is each
          -- side's own fixed offset from the player.
          up = {
            axis = "y", L = { dx = 2, pair = "A", flipX = false, flipY = true },
            R = { dx = 10, pair = "B", flipX = false, flipY = true },
            frames = { -8, -7, -6, -5, -16, -15, -15, -15, -8, -8, -8, -8 },
          },
          down = {
            axis = "y", L = { dx = -2, pair = "A", flipX = false, flipY = false },
            R = { dx = 6, pair = "B", flipX = false, flipY = false },
            frames = { 8, 7, 6, 5, 16, 15, 15, 15, 8, 8, 8, 8 },
          },
          -- axis="x": the sequence below applies to dx for both L/R; dy
          -- is each side's own fixed offset.
          left = {
            axis = "x", L = { dy = 3, pair = "A", flipX = false, flipY = false },
            R = { dy = 3, pair = "B", flipX = false, flipY = false },
            frames = { -8, -7, -6, -5, -16, -15, -15, -15, -8, -8, -8, -8 },
            rOffset = 8, -- R = frame value + 8 (its own fixed spacing from L)
          },
          right = {
            axis = "x", L = { dy = 3, pair = "B", flipX = true, flipY = false },
            R = { dy = 3, pair = "A", flipX = true, flipY = false },
            frames = { 8, 7, 6, 5, 16, 15, 15, 15, 8, 8, 8, 8 },
            rOffset = 8,
          },
        },
      },
      -- Real enemy sprite: 4x4 tiles (32x32px, not 32x16) at OAM
      -- top-left (Y=50,X=79) -> screen (71,34), bank 11 (falls inside
      -- the already-confirmed creatureSpritesBank11 region below). Tile
      -- order (row-major): $40 $42 $48 $4A / $41 $43 $49 $4B / $44 $46
      -- $4C $4E / $45 $47 $4D $4F -- each OAM column's 8x16 pair
      -- (N, N+1) occupies 2 of the 4 sub-rows.
      enemySprite = {
        status = "VERIFIED",
        bank = 11,
        cols = 4,
        rows = 4,
        -- ATTEMPTED CORRECTION, REVERTED (2026-08-13, same day): a live
        -- OAM re-scan (`scan_oam_settled.py`, scratchpad) found only 8
        -- of these 16 tiles in each individual real OAM snapshot
        -- (alternating $40/$42/$48/$4A + $44/$46/$4C/$4E, 16px apart --
        -- the same real shape as the entrance-phase `enemyDescent`
        -- sprite) and never caught the other 8 ($41/$43/$49/$4B/$45/
        -- $47/$4D/$4F) in any single sample. Tried switching this
        -- sprite to that same 8-tile/16px-gap shape -- a live `love .`
        -- screenshot showed the settled creature rendered as two
        -- visibly SEPARATE chunks with floor showing through the gap,
        -- clearly WORSE than the original solid-looking capture, not
        -- better (unlike the entrance sprite, where the same real fix
        -- DID look right). Reverted to the original 4x4/16-tile/flush
        -- capture rather than ship a change contradicted by its own
        -- live screenshot. Real, honest, OPEN question for whoever
        -- continues this: the 16px-gap OAM snapshots are real,
        -- individually-observed facts (not a tooling artifact this
        -- project could find) -- possibly real hardware relies on a
        -- persistence-of-vision effect (rapid alternation between two
        -- vertically-offset 8-tile halves, faster than the per-
        -- movement-step sampling this pass used) to LOOK solid despite
        -- any single frozen frame only showing half -- not confirmed,
        -- not implemented, left as a real, bounded gap rather than a
        -- guess.
        tileOffsets = {
          0x2FE00, 0x2FE10, 0x2FE80, 0x2FE90, -- $40 $42 $48 $4A
          0x2FE20, 0x2FE30, 0x2FEA0, 0x2FEB0, -- $41 $43 $49 $4B
          0x2FE40, 0x2FE50, 0x2FEC0, 0x2FED0, -- $44 $46 $4C $4E
          0x2FE60, 0x2FE70, 0x2FEE0, 0x2FEF0, -- $45 $47 $4D $4F
        },
        screenX = 71,
        screenY = 34,
        -- VERIFIED (2026-08-12, direct user reports: "die animationen
        -- der sprites nicht richtig, der boss sollte zb animationen
        -- haben" + "die boss intro sequenz stimmt noch nicht"): live
        -- OAM-traced the real gate-creature's own patrol/hover cycle
        -- (already captured as `Enemy.MOVEMENT_CYCLE`, see that file's
        -- own doc comment) ALSO toggles real OAM attribute bit 5
        -- (X-flip, Pan Docs "OBJ Flags" -- `0x20`) every single
        -- movement step -- attr `0x30` (`0x10`palette `|` `0x20`
        -- X-flip) at one waypoint, `0x10` (X-flip clear) at the next,
        -- alternating, using the SAME already-known 16 tiles above
        -- every time (confirmed by directly reading the real OAM tile
        -- IDs at both a `0x30` and a `0x10` sample: both are exactly
        -- this table's own `tileOffsets` set -- the real per-step
        -- Y-position change is already fully accounted for by
        -- `Enemy.MOVEMENT_CYCLE`'s own real deltas, a separate real
        -- fact from this flip bit) -- i.e. the real "flapping"
        -- animation is a hardware X-flip (horizontal mirror) of the
        -- SAME art, not a second drawn frame and NOT a Y-flip
        -- (CORRECTED same day: this field and `Enemy:isFlipped()`'s own
        -- first implementation wired this into `flipY` by mistake --
        -- bits 5/6 transposed -- fixed to `flipX`, see Enemy.lua/
        -- Field.lua/BattleIntro.lua). `Enemy:isFlipped()` (see
        -- Enemy.lua) exposes this as a simple movementIndex-parity
        -- toggle.
        flipXTogglesPerStep = true,
      },
      -- VERIFIED (2026-08-12, same investigation, direct follow-up to
      -- the boss-intro report): the real gate creature does NOT simply
      -- appear at its resting spot when the "Kaempfe!" box closes --
      -- live OAM-traced the real battle-intro sequence frame by frame
      -- (courtesy of `reach_room.reach_first_room`'s own real button
      -- sequence, extended past name entry with no further input) and
      -- found the creature spawns near the TOP of the screen (the
      -- courtyard's own real barred gate, see `battleIntro.gate` above
      -- -- same open/close frame window) and descends straight down
      -- (screen X constant at 64 -- CORRECTED 2026-08-13, was
      -- documented as 80, a real 16px error, see this entry's own
      -- `screenX` doc comment below -- Y climbing 7->28 over ~20 real
      -- frames, 4 real steps of ~5 frames each) using a SECOND, real,
      -- previously-uncaptured 4x2 tile block (CORRECTED 2026-08-13,
      -- was documented as 4x4 -- see `enemySprite`'s own doc comment
      -- above for the same real mistake, found the same day) -- NOT
      -- the same tiles as the resting/patrol pose above. Confirmed via
      -- the same "exact 16-byte ROM search" method as
      -- `enemySprite.tileOffsets`: every
      -- one of the 8 real top-tile IDs matches EXACTLY ONE ROM location
      -- each (high confidence), contiguous in bank 11 immediately after
      -- the resting-pose block (`tileOffsets` above sits at
      -- `0x2FE00-0x2FEFF`; this sits at `0x2FF00-0x2FFDF`).
      -- Once the descent reaches the patrol's own real Y range (~frame
      -- 20 into the descent), OAM switches over to the ALREADY-known
      -- `enemySprite.tileOffsets`/`MOVEMENT_CYCLE` patrol -- this block
      -- is ONLY the one-time gate-to-patrol transition, not an
      -- alternate ongoing pose.
      enemyDescent = {
        status = "VERIFIED",
        bank = 11,
        cols = 4,
        rows = 4,
        -- ROOT CAUSE FOUND (2026-08-13, direct user instruction "rate
        -- nicht, schau dir im rom den draw code beim einlauf an"): read
        -- the REAL ROM OAM-writer code (`$088A`/`$0611` and callers,
        -- traced live via the shadow-OAM buffer at `$C000`) and checked
        -- the real `$FF40` LCDC register at the descent -- bit 2 (OBJ
        -- size) is SET, i.e. real hardware is in 8x16 sprite mode. In
        -- that mode each OAM entry's own tile index has its LSB forced
        -- to 0 and draws THAT tile as the top 8px PLUS `tile|1` as the
        -- bottom 8px, flush, automatically, with no CPU-visible second
        -- OAM write for the bottom half. The previous 8-tile/`cols=4,
        -- rows=2` capture only ever recorded the TOP half of each of
        -- the 4x2 grid's own two OAM rows (the `$C000` tile-ID bytes
        -- this project watched) and never the bottom halves the
        -- hardware appends on its own -- this is the real, exact cause
        -- of "nur jede 2. Zeile" and "die untersten 2 Zeilen fehlen":
        -- the bottom-half tiles were never in `tileOffsets` at all, not
        -- a spacing/gap problem. Every attempted `rowSpacing` fix was
        -- therefore addressing the wrong variable (position of a gap)
        -- instead of the real one (missing tile data).
        --
        -- Full 4x4/16-tile grid below uses the SAME real interleaved
        -- ROM layout already verified (unmodified) for `enemySprite`
        -- above (pairs of columns, top-half block then bottom-half
        -- block, contiguous in bank 11 immediately after that sprite's
        -- own 0x2FE00-0x2FEFF block) -- confirmed directly: all 16
        -- offsets below contain real, distinct, non-zero tile data
        -- (`dump_descent_tiles.py`, scratchpad), and the 8 top-half
        -- offsets exactly match this table's own previous (correct)
        -- values, so only the bottom-half offsets were newly added:
        --   row0 (top halves,    upper OAM row): $50 $52 $58 $5A
        --   row1 (bottom halves, upper OAM row): $51 $53 $59 $5B
        --   row2 (top halves,    lower OAM row): $54 $56 $5C $5E
        --   row3 (bottom halves, lower OAM row): $55 $57 $5D $5F
        tileOffsets = {
          0x2FF00, 0x2FF10, 0x2FF80, 0x2FF90, -- $50 $52 $58 $5A
          0x2FF20, 0x2FF30, 0x2FFA0, 0x2FFB0, -- $51 $53 $59 $5B
          0x2FF40, 0x2FF50, 0x2FFC0, 0x2FFD0, -- $54 $56 $5C $5E
          0x2FF60, 0x2FF70, 0x2FFE0, 0x2FFF0, -- $55 $57 $5D $5F
        },
        -- `screenX` stays constant at 64 through all 4 real descent
        -- frames (confirmed live, `scan_oam_full_descent.py` +
        -- `trace_shadow_oam_positions.py`, both scratchpad) -- the
        -- earlier `80` value was a real 16px error, unrelated to and
        -- not affected by the 8x16-mode fix above.
        screenX = 64,
        path = {
          { y = 7, frames = 5 }, { y = 14, frames = 5 },
          { y = 21, frames = 5 }, { y = 28, frames = 5 },
        },
        -- Real resting/patrol X/Y this hands off to once the descent
        -- finishes (matches `enemySprite.screenX/screenY` above --
        -- confirmed by watching OAM switch tile blocks exactly at this
        -- point in the same live trace).
        handoffScreenX = 71, handoffScreenY = 34,
      },
      -- VERIFIED (2026-08-12, direct response to a user correction:
      -- "es gibt diese explosion ohne jeden zweifel" -- an earlier pass
      -- this same session wrongly trusted a stale negative result, see
      -- combat.md's own "Explicit negative result" entry, which only
      -- ruled out ONE despawn call chain and explicitly left the real
      -- `$D3EC` event-queue consumer untraced). Live-traced the real
      -- gate creature's OWN death sequence frame by frame from the
      -- instant `$D3F5` hits its dead sentinel (`courtyard_boss_defeated
      -- ()`) and found a real, undeniable visual effect this project's
      -- own earlier OAM-content check had missed: the creature's own
      -- SIX real body-part OAM pairs (tiles 0x38/0x3a/0x3c/0x3e --
      -- decimal 56/58/60/62, the same tiles combat.md's own hit-
      -- reaction-pose note already named) do NOT just vanish -- their
      -- real screen POSITIONS scatter outward to six different corners
      -- of the room over ~85 real frames (confirmed via a direct
      -- screenshot at frame 86: six round part-clusters visibly spread
      -- apart, not the creature's normal coherent standing shape),
      -- THEN all six vanish simultaneously (OAM entry count drops to 0
      -- at frame 86, matching the already-documented `$0AE3` despawn
      -- routine's own real "clear the six body-part slots" behavior --
      -- that routine's own negative result, "no NEW tile ID is ever
      -- loaded," is still correct: this is the creature's OWN existing
      -- body-part art being REPOSITIONED, not a dedicated explosion
      -- sprite). Net effect on screen: a real "body bursts apart into
      -- pieces, then all pieces vanish" animation -- this project's own
      -- "kind of an explosion" description is accurate for what a
      -- player actually sees, even though the underlying mechanism is
      -- real body parts scattering, not a dedicated particle effect.
      --
      -- HONEST LIMIT: the 4 body-part tiles' own real ROM file offsets
      -- are NOT uniquely confirmed -- the exact 16-byte search returned
      -- 2-3 real matches each (not this project's usual "exactly one"
      -- bar), in two internally-consistent clusters (bank 8 around
      -- `0x23db0` and bank 9 around `0x27900`, both with the same
      -- real relative tile spacing) -- the art is plausibly genuinely
      -- duplicated across banks (common on MBC2 titles that need the
      -- same graphics reachable from more than one bank-switch
      -- context), not a search bug. Bank 8's cluster is used below
      -- (closest to the other battle-related graphics this project
      -- already sources from bank 8) -- a reasonable choice, not a
      -- uniquely-proven one; if the rendered art looks wrong, the bank
      -- 9 cluster (`0x27900`/`0x27910`/`0x27940`/`0x27950`) is the
      -- other real candidate to try.
      --
      -- Real screen positions for each of the 6 part-pairs, sampled at
      -- the SAME real frame boundaries the live OAM trace held steady
      -- on (5-frame steps, matching the already-known
      -- `Enemy.MOVEMENT_STEP_SECONDS`-style cadence elsewhere in this
      -- ROM) -- `dx`/`dy` are real captured deltas from each part's own
      -- starting position (the creature's real resting pose, see
      -- `enemySprite.screenX/screenY`), not an invented starburst.
      enemyDeath = {
        status = "VERIFIED (positions + real 2-frame debris shape)",
        bank = 8,
        -- CORRECTED (2026-08-14, direct user report: "bei den einzelnen
        -- sprites scheint jeweils die untere Hälfte bei der Explosion
        -- zu fehlen"): the old doc comment's own "6 real body-part
        -- PAIRS" framing was never actually cross-checked against a
        -- fresh live capture -- these 4 tile offsets were being drawn
        -- as ONE static, always-fully-shown 2x2 (16x16) sprite at each
        -- of the 6 scatter positions. A real live OAM trace (mgba,
        -- `courtyard_boss_defeated`, sampled every 8 real frames
        -- through the whole death sequence) found the real hardware
        -- NEVER shows all 4 tiles together: each of the 6 real flying
        -- OAM pairs is only TWO tiles wide, ONE tile tall (real tile
        -- IDs $38/$3a or $3c/$3e, never all four at once), alternating
        -- between them over time -- a real 2-FRAME debris animation,
        -- not a static double-height block. `frameA`/`frameB` below
        -- are those 2 real captured frames (each a real 2-tile-wide,
        -- 1-tile-tall sprite); `Field.lua` alternates between them
        -- (see its own doc comment for the exact real cross-reference
        -- of these 4 offsets to the real tile IDs $38/$3a/$3c/$3e).
        frameA = { 0x23db0, 0x23dc0 }, -- real tiles $38 $3a
        frameB = { 0x23df0, 0x23e00 }, -- real tiles $3c $3e
        -- Real, live-CONFIRMED (NOT a bug): the same live OAM trace
        -- also checked `OBP1` (the enemy's own real sprite palette
        -- register) through the whole death sequence -- it reads
        -- `$D0` throughout the explosion, i.e. this game's own
        -- already-implemented DEFAULT sprite palette (see
        -- `spritePalette.registerValue` above, same value) -- already
        -- what `CreatureSprite.fromOffsets` falls back to when no
        -- explicit palette is passed (as this death sprite does). A
        -- direct user suspicion ("da müsste auch ein Palettn-Effekt
        -- drüber") checked and found NOT needed: no separate death-
        -- flash palette exists in the real ROM, the ordinary default
        -- already matches. (The enemy's own PRE-death resting pose DID
        -- read a different real value, `$3F` -- a real, separate,
        -- not-yet-investigated fact about its own idle rendering, out
        -- of scope for this specific bug report.)
        totalFrames = 86, -- real: OAM entry count hits 0 exactly here
        -- 6 real body-part pairs, each `{dx, dy}` -- the real captured
        -- delta from the creature's own resting top-left screen
        -- position (frame 0 of the death sequence, still the coherent
        -- standing pose) to its own final scattered position (frame 81,
        -- the last real OAM sample before the frame-86 vanish) -- a
        -- straight-line interpolation between these two real endpoints
        -- over `totalFrames`, not a reproduction of every real
        -- intermediate jump (the actual live capture shows each part
        -- taking a real, slightly irregular multi-step path, not a
        -- straight line -- this is an honest simplification of that
        -- real data, not a claim of frame-exact fidelity).
        parts = {
          { dx = 0, dy = 0 }, { dx = 27, dy = -3 }, { dx = -23, dy = 21 },
          { dx = -1, dy = 16 }, { dx = -14, dy = -10 }, { dx = -1, dy = -43 },
        },
      },
      -- VERIFIED (2026-08-09) real hit-flash -- direct fix for a named
      -- gap: "der Gegnersprite flasht kurz, wenn er von einem Angriff
      -- getroffen wird." Traced live: `OBP1` (the enemy's own real
      -- sprite palette register -- OAM attribute bit 4 confirms the
      -- enemy uses OBP1, not OBP0, see `spritePalette` above) briefly
      -- changes from its normal `$D0` to `$BF` for roughly 1 real frame
      -- right as a hit lands, then reverts -- a real palette-swap flash,
      -- not an invented tint. Decoded the same way as `spritePalette`
      -- (Pan Docs "LCD Monochrome Palettes" bit layout): raw pixel
      -- indices 1 and 2 (normally white/light-gray) both flash to
      -- shade 3 (black), index 3 (normally black) flashes to shade 2
      -- (dark gray) -- the enemy briefly reads as an almost-solid black
      -- silhouette, not a simple color inversion.
      enemyHitFlash = {
        status = "VERIFIED",
        registerValue = 0xBF,
        shadeIndices = { 3, 3, 3, 2 },
        frames = 2, -- real observed flash was ~1 real frame; held 2 here for visibility
      },
      creatureSpritesBank9 = {
        -- CORRECTED: this project's earlier "VERIFIED -- region confirmed
        -- graphics" status overclaimed uniformity. A direct screenshot
        -- comparison (TileViewer's "sprites (bank 9)" region, see
        -- docs/progress.md) showed the bank does NOT decode as coherent
        -- tile art starting at tile 0 -- there's a run of noise-looking
        -- (non-tile) data first, with real sprite-like art appearing only
        -- well into the bank. Real bytes, but "this whole bank is clean
        -- graphics" was not actually established -- kept PARTIALLY
        -- VERIFIED and don't use tile 0 here as a default sprite source
        -- (see src/app/states/Field.lua, which uses bank 10 instead).
        status = "PARTIALLY VERIFIED",
        fileOffsetStart = 0x24000,
        fileOffsetEnd = 0x28000,
        bank = 9,
      },
      creatureSpritesBank10 = {
        -- VERIFIED by direct screenshot (docs/progress.md): a clean,
        -- coherent sheet of real small creature-portrait art starting
        -- right at tile 0 -- unlike bank 9, no noise run at the start.
        status = "VERIFIED",
        fileOffsetStart = 0x28000,
        fileOffsetEnd = 0x2C000,
        bank = 10,
      },
      creatureSpritesBank11 = {
        -- VERIFIED by direct screenshot (docs/progress.md): title-logo
        -- art ("MYSTIC QUEST" lettering, a shield/sword icon) plus real
        -- small creature-sprite fragments, mixed in the same bank --
        -- real graphics throughout, but not uniformly *creature*
        -- sprites the way the name implies.
        status = "VERIFIED",
        fileOffsetStart = 0x2C000,
        fileOffsetEnd = 0x30000,
        bank = 11,
      },
      environmentTilesetBank12 = {
        status = "VERIFIED",
        -- Whole bank contains tileset-like art; confirmed strongly from
        -- ~0x33000 onward (stone/brick/water/cave textures), extended to
        -- 0x32000 onward (pillars/urns/arches -- same tileset family) once
        -- mapTable below was found to reference this exact range.
        fileOffsetStart = 0x30000,
        fileOffsetEnd = 0x34000,
        confirmedFrom = 0x32000,
        bank = 12,
      },

      -- `unknownRoomA`'s 6 real, VERIFIED rooms (see
      -- `roomFloorLayoutPipeline.unknownRoomACandidates` below for the
      -- full evidence chain) -- BUILT IN as real, walkable content
      -- (2026-08-12), same flat `{cols,rows,tileOffsets,grid,
      -- floorTileIds}` shape `TileGridBackground.new`/
      -- `TileWalkability.build` already consume for every other room.
      -- Data comes from `UNKNOWN_ROOM_A_*` locals defined at the top of
      -- this file (shared across all 6 -- one tileset, one collision
      -- classification, six distinct layouts).
      --
      -- HONEST SCOPE, same as rom-map.md's own "unknownRoomA VISUALLY
      -- CONFIRMED" section: the ROOM CONTENT itself (tiles, layout,
      -- floor classification) is real ROM data. The CONNECTIVITY is
      -- NOT -- no live gameplay trigger into this area was ever found,
      -- so there is no real ROM-derived door/exit into or between these
      -- 6 rooms. This project does not fabricate one (would misrepresent
      -- invented data as decoded ROM behavior, exactly what this
      -- project's own engineering rules forbid) -- see
      -- `src/app/states/RoomExplorer.lua` for how a developer actually
      -- reaches these rooms in-app: a clearly-marked dev-only content
      -- browser (F8 from Field.lua), not a real in-fiction path.
      unknownRoomA_8 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 8,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[8],
      },
      unknownRoomA_9 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 9,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[9],
      },
      unknownRoomA_10 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 10,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[10],
      },
      unknownRoomA_11 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 11,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[11],
      },
      unknownRoomA_12 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 12,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[12],
      },
      unknownRoomA_13 = {
        status = "VERIFIED (room content); connectivity is this project's own invented dev-only wiring, not ROM data",
        romRoomSelector = 13,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[13],
      },
    },

    -- Bank 5 map/room-block pointer table -- see
    -- docs/reverse-engineering/rom-map.md "Maps" / "Room decompression
    -- format -- CRACKED" for the full evidence writeup. VERIFIED: the
    -- table, its real 4-byte per-map header (bytes at bankFileStart --
    -- [encodingMode, rleLength, gridHeight, gridWidth], read generically
    -- by MapTable.readMapHeader, not hardcoded here), and the RLE
    -- decompression scheme (MapTable.rleDecode) -- confirmed structurally
    -- (255/255 records decode to an exact, uniform 80 tiles with the
    -- real header-derived rleLength=3, vs. 0/255 for every other tested
    -- value) and visually (coherent recognizable tile art). STILL
    -- UNKNOWN: how multiple 20x4-tile records compose into a full
    -- on-screen room. `src/import/MapTable.lua` is the generic
    -- (non-ROM-specific) decoder that consumes these offsets.
    mapTable = {
      -- UPDATE 2026-08-12 ("du sollst in der lage sein alle räume zu
      -- dekodieren"): room-composition is no longer unknown -- see
      -- `unknownRoomACandidates` below and rom-map.md's own "World
      -- scope, round 4" section. Record N (this table) IS roomSelector
      -- N's own real, complete room (via the shared bank-8 metatile
      -- pool, `RoomFloorLayout.buildRoomFromMapTableRecord`) -- no
      -- further "how do multiple records combine" step needed; each
      -- record already decodes to one full, real, coherent room by
      -- itself (real tile_entropy 1.0-1.8 bits, confirmed for every
      -- record this project has actually rendered).
      --
      -- SCOPE CORRECTED (2026-08-14): "room-composition" above means
      -- the STRUCTURAL decode (RLE stream -> 80 metatile indices -> a
      -- full grid) is real and verified. It does NOT mean the
      -- resulting picture uses the correct metatile table for records
      -- other than 8-13 (`unknownRoomACandidates.rooms`) -- see that
      -- table's own 2026-08-14 "CORRECTED" doc comment for the full,
      -- dated evidence (a real per-record header field was tested as a
      -- possible fix and ruled out against known-good ground truth).
      --
      -- UPGRADED (2026-08-14, same day, "gehe dem map header hinweis
      -- nach"): all 256 records now use `genericCatalogMetatileTable
      -- FileOffset` (see `unknownRoomACandidates`'s own doc comment),
      -- a real, structurally-justified derivation from this ROM's own
      -- `roomSelectorTable` record 0 -- externally corroborated
      -- against the FFA-Disassembly project's documented "one tileset
      -- per map" architecture, not a guess. Not independently ground-
      -- truth-verified (no live gameplay reaches these rooms).
      status = "VERIFIED (encoding + room-composition); tile ASSIGNMENT now uses genericCatalogMetatileTableFileOffset " ..
        "(real, structurally-derived default, see the UPGRADED note above, 2026-08-14) -- not independently ground-truth-verified",
      -- Bank 5 base -- pointer values are CPU addresses ($4000-$7FFF)
      -- relative to this bank being switched in; file offset = bankFileStart
      -- + (cpuAddress - 0x4000).
      bankFileStart = 0x14000,
      bank = 5,
      -- 512 word-aligned, strictly-increasing, 100%-unique pointers = 256
      -- records of (headerPtr, dataPtr) pairs.
      pointerTableFileOffset = 0x14004,
      recordCount = 256,
      -- Confirmed tile-index base for interpreting each record's data blob
      -- bytes (see environmentTilesetBank12.confirmedFrom above): tile
      -- index N in a blob -> file offset tilesetFileOffset + N*16.
      tilesetFileOffset = 0x32000,
    },

    -- A SECOND, real, independently-found map/room-block pointer table
    -- -- found 2026-08-12 ("du sollst in der lage sein alle räume zu
    -- dekodieren. nicht stoppen bevor das nicht möglich ist") while
    -- looking for a general way to decode rooms beyond the exhausted
    -- 16-entry `roomSelectorTable`. VERIFIED the exact same way bank
    -- 5's own table was originally VERIFIED (see `mapTable` above):
    -- the real 4-byte per-map header immediately before the pointer
    -- table (`00 04 08 08` at file `0x18000`, i.e. encodingMode=0/RLE,
    -- rleLength=4) matches this ROM's own already-documented format
    -- exactly, just with a different real `rleLength`. Applying it:
    -- 128 monotonic, strictly-increasing, valid-CPU-address ($4000-
    -- $7FFF) pointer entries follow immediately at file `0x18004` =
    -- 64 real (headerPtr, dataPtr) record pairs -- a clean, real,
    -- ROUND number (matches this ROM's own established "16 banks, 16x16
    -- map, 256-record bank-5 table" convention of exact, non-arbitrary
    -- table lengths). All 64 records decode cleanly (via
    -- `MapTable.rleDecode` with this table's own real `rleLength=4`)
    -- to exactly 80 values -- the SAME metatile-grid size as bank 5's
    -- own records, not the `8x8=64` the header's OWN 3rd/4th bytes
    -- would naively suggest (those bytes evidently mean something
    -- else for this table -- flagged honestly, not force-fit).
    -- **VISUALLY + QUANTITATIVELY CONFIRMED, all 64 records**: rendered
    -- every one through the ALREADY-known shared bank-8 metatile pool
    -- (`unknownRoomACandidates.metatileTableFileOffset` below) and
    -- `MapTable`'s own already-VERIFIED direct tileset formula -- real
    -- `tile_entropy()` (this project's own established "looks like
    -- real art, not noise/blank" metric) for EVERY one of the 64
    -- rooms: 1.08-1.63 bits, squarely inside the same real "~1.0-1.8"
    -- band already established for `unknownRoomA`'s own 6 rooms, with
    -- zero outliers toward blank (0.0) or noise (~2.0). Two rendered
    -- examples eyeballed directly (record 0, record 21): unmistakable,
    -- structured dungeon/shrine art -- repeating floor patterns,
    -- symmetric decorative elements, distinct architectural features
    -- -- not remotely what a wrong/misaligned decode produces.
    --
    -- SCOPE CORRECTED (2026-08-14): "VISUALLY + QUANTITATIVELY
    -- CONFIRMED" above means exactly what it says -- real, non-noise
    -- GB tile art -- and nothing more. It does NOT mean these 64
    -- records use the semantically CORRECT metatile table (only
    -- `unknownRoomACandidates`'s own 6 bank-5 records have that
    -- independently confirmed, via the real `roomSelectorTable`'s own
    -- `$D392`/`$D393` DE field -- see that table's own doc comment for
    -- the full, dated correction). Applying the same table to these 64
    -- bank-6 records was always the same unverified placeholder, not a
    -- separate confirmation -- direct visual review (user report,
    -- 2026-08-14, "total off") found it does NOT look right once
    -- compared side-by-side against the 6 actually-confirmed rooms.
    --
    -- UPGRADED (2026-08-14, same day, "gehe dem map header hinweis
    -- nach"): all 64 records now use `genericCatalogMetatileTableFile
    -- Offset` (see `unknownRoomACandidates`'s own doc comment) -- a
    -- real, structurally-justified derivation from `roomSelectorTable`
    -- record 1 (bank6's own "map"), cross-checked against the external
    -- FFA-Disassembly project's documented "one tileset per map"
    -- architecture. Not independently ground-truth-verified.
    mapTableBank6 = {
      status = "VERIFIED (table location + encoding + all 64 records real-render as non-noise GB art); " ..
        "tile ASSIGNMENT now uses genericCatalogMetatileTableFileOffset (real, structurally-derived default, see the " ..
        "UPGRADED note above, 2026-08-14) -- not independently ground-truth-verified",
      bankFileStart = 0x18000,
      bank = 6,
      pointerTableFileOffset = 0x18004,
      recordCount = 64,
      -- Shares the SAME real tileset as bank 5's own table -- both
      -- render coherently against it, real cross-confirmation this is
      -- the right base for the whole shared bank-8 metatile pool's
      -- own GFX-tile bytes, not a coincidence specific to one table.
      tilesetFileOffset = 0x32000,
    },

    -- A THIRD real map/room-block table -- bank 7, the OTHER real
    -- encoding this ROM's own per-map header names (`encodingMode=1`,
    -- "Templated" -- see `MapTable.readMapHeader`'s own doc comment).
    -- Found the same way as `mapTableBank6` (scan every bank's first 4
    -- bytes for the documented `[encodingMode, rleLength, h, w]` shape):
    -- `01 04 08 08` at file `0x1C000`.
    --
    -- CRACKED end to end (2026-08-14, direct user instruction "weiter
    -- bohren bis es fertig ist" -- see rom-map.md's own "bank 7
    -- Templated revisited, CRACKED" section for the full evidence
    -- trail). Structural shape (all boundaries land exactly, zero slack
    -- bytes): 4-byte header, then a 2-byte base-room TEMPLATE pointer
    -- (`0x411e`, CPU addr -> file `0x1C11E`), then a 24-byte per-map
    -- door-data block (raw bytes captured, semantic bit layout NOT
    -- decoded), then the usual 64-record `(headerPtr,dataPtr)` pointer
    -- list starting at file `0x1C01E` (same shape/count as bank 6's own
    -- table) -- ending EXACTLY at the template pointer's own file
    -- offset, `0x1C11E`, with zero gap. RLE-decoding the template
    -- (`MapTable.rleDecode`, this map's own `rleLength=4`) produces
    -- exactly 80 tiles, consuming exactly enough bytes to land
    -- precisely on record 0's own header pointer (`0x1C14A`) -- a
    -- second independently-derived boundary match.
    --
    -- Each of the 64 records' own data blob is a real DIFF against that
    -- shared base template (`MapTable.applyTemplatedDiff`): a 4-byte
    -- per-record prefix (small values, not yet decoded -- plausibly
    -- door/exit-flag data) followed by `(value, position)` byte pairs,
    -- `position = (row<<4)|col`, terminated by position byte `0xFF`.
    -- VERIFIED against all 64 real records: 566/566 real diff positions
    -- decode to valid `(row,col)` pairs (zero exceptions), and every one
    -- of the 64 reconstructed rooms renders as real, structurally
    -- coherent, VISUALLY DISTINCT dungeon art (`tile_entropy()`
    -- 1.30-1.40 bits, zero outliers -- plus direct PNG eyeballing of 6
    -- spot-checked records, each genuinely different room content).
    --
    -- Tile ASSIGNMENT uses the same `genericCatalogMetatileTableFileOffset`
    -- default as `mapTable`/`mapTableBank6` (not independently
    -- ground-truth-verified against live gameplay -- no playthrough
    -- reaches these rooms).
    --
    -- COLLISION CRACKED 2026-08-14 ("ok weiter mit tür und kollision"):
    -- `RoomFloorLayout.buildCollisionGridFromMapTableRecord` dispatches
    -- to `buildCollisionGridFromTemplatedMapTableRecord` for this table
    -- now, same real per-metatile collision-byte lookup as bank 5/6 --
    -- LIVE-VERIFIED via real `love .` screenshots (see rom-map.md's
    -- "ok weiter mit tür und kollision" section), same honest
    -- "extrapolated bank-5/6 rule, not ROM-confirmed" caveat as those
    -- two tables (no gameplay reaches ANY of these rooms either).
    --
    -- DOOR BYTES: real structural progress, honestly still not decoded.
    -- Each record's own 4-byte prefix is a remarkably clean 8-value
    -- alphabet across all 256 real bytes (`{0,1,2,5,8,9,12,13}`, zero
    -- outliers): `bits0-1` is ALWAYS 0/1/2 (never the 4th 2-bit
    -- combination), matching the external FFA-Disassembly doc's own
    -- claimed "open/closed/wall" 3-state layout; `bits2-7` is ALWAYS
    -- 0-3 (240/256 bytes are 0). The map-level 24-byte block does NOT
    -- share this pattern (wider ranges on both fields) -- genuinely
    -- different data, not the same format repeated. See rom-map.md's
    -- own dated section for the full statistical breakdown. NOT
    -- implemented as door/exit behavior: no live bank-7 gameplay exists
    -- to confirm which byte is which direction or what each state value
    -- means, and this project does not fabricate ROM behavior past what
    -- can be checked.
    mapTableBank7 = {
      status = "VERIFIED end to end (Templated/mode-1 structure + base-template/diff tile decode AND " ..
        "collision, 2026-08-14); tile ASSIGNMENT uses genericCatalogMetatileTableFileOffset like " ..
        "mapTable/mapTableBank6, not independently ground-truth-verified against live gameplay; " ..
        "door-data bytes (map-level 24 + per-record 4) show a real, clean statistical structure " ..
        "(see doc comment) but remain semantically undecoded -- no live gameplay to confirm against",
      bankFileStart = 0x1C000,
      bank = 7,
      -- The record-pointer list itself starts at +30 (4-byte header + 2-byte
      -- template pointer + 24-byte door data), NOT +4 like mapTable/mapTableBank6 --
      -- a real, Templated-mode-specific structural difference (see doc
      -- comment above), not a typo.
      pointerTableFileOffset = 0x1C01E,
      recordCount = 64,
      -- Shares the SAME real tileset as bank 5/6's own tables.
      tilesetFileOffset = 0x32000,
    },

    -- The REAL room-connectivity table -- see docs/reverse-engineering/
    -- rom-map.md "BREAKTHROUGH: the real room table, found" and "The
    -- bank-8 room table, fully documented" (2026-08-10). VERIFIED via
    -- BOTH a static ROM dump and TWO independent live `CallTracer`
    -- traces (the post-victory staircase, and a completely separate
    -- pre-combat transition) hitting the exact same code
    -- (`$04138->$02B70->$026DC->$01AF3`, bank-resolved). This is a
    -- real, general, `roomSelector`-indexed table the ROM itself uses
    -- to load rooms -- NOT this project's own invention, and NOT the
    -- long-searched-for bank-5 table (which remains unidentified in
    -- purpose). Table length (16, not a full byte range) is itself a
    -- real, derived fact: byte 6 of each record must be a valid MBC
    -- bank number, and this ROM has exactly 16 banks -- record 16
    -- onward immediately produces impossible bank numbers, confirming
    -- the table's real end (see rom-map.md for the full reasoning, "a
    -- table's real length must be independently bounded" as the
    -- general lesson).
    --
    -- `src/import/RoomSelectorTable.lua` is the generic (non-ROM-
    -- specific) decoder; nothing about the 11-byte stride or field
    -- meanings is hardcoded here, only real offsets/values.
    roomSelectorTable = {
      status = "VERIFIED",
      bank = 8,
      fileOffset = 0x20000,
      recordLength = 11,
      recordCount = 16,
      -- Real per-record field layout (byte offsets within each 11-byte
      -- record), from the live-traced `$026DC` lookup routine:
      --   bytes 0-1: 16-bit LE offset, added to $4000 to form the `HL`
      --     parameter to $01AF3 (committed to WRAM $D390/$D391 -- a
      --     real pointer this project had not named before this pass).
      --   byte 2: not consumed by $026DC/$01AF3 -- meaning unknown.
      --   bytes 3-4: 16-bit LE value, the `DE` parameter to $01AF3 --
      --     committed to WRAM $D392/$D393, the ALREADY-KNOWN real
      --     room tile-source pointer (used by this project's whole
      --     room-chain implementation already).
      --   byte 5: not consumed by $026DC/$01AF3 -- meaning unknown.
      --   byte 6: the real dynamic MBC bank number, committed to WRAM
      --     $C3F0 (the already-known trampoline bank-select flag).
      --   bytes 7-8: 16-bit LE pointer, staged to WRAM $C3F2/$C3F3, THEN
      --     dereferenced by $026DC's own tail: 4 real bytes are copied
      --     from it into $C3F8-$C3FB (a real stream-cursor read, the
      --     pointer is advanced past them afterward). CONFIRMED
      --     (2026-08-10, direct user hypothesis "sind das room states"):
      --     $C3F8 is the ALREADY-KNOWN gate/enable flag $235B (the
      --     door-open check, found earlier this session) reads before
      --     proceeding -- i.e. THIS is the real mechanism giving each
      --     roomSelector its own per-instance "state" (a real, live
      --     confirmation of the room-states hypothesis, even though
      --     $C3F9-$C3FB's own individual roles weren't traced). See
      --     rom-map.md "Direct user hypothesis, checked and confirmed".
      --   bytes 9-10: never read by $026DC/$01AF3 in this pass's trace
      --     -- meaning unknown, real bytes, not guessed at.
      --
      -- FOLLOW-UP (2026-08-11, pure static disassembly, see rom-map.md
      -- "Following $C3F8's consumers"): $235B(A=direction), when its
      -- own $C3F8 flag is nonzero, switches to THIS record's `byte 6`
      -- dynamic bank and reads a small per-direction 16-bit value from
      -- `ptr+2+selector*2` (selector 0-3, chosen by which bit of A is
      -- set) -- i.e. a real, traced READ from the dynamic bank (bank 5
      -- for records 0/9). That value is then fed into $05BB (the
      -- ALREADY-KNOWN "$D392:$D393 + A*6" source-address formula) as an
      -- INDEX, not used as tile data directly -- the real tile bytes
      -- drawn always come from hardcoded bank 8 via $D392/$D393, same
      -- pipeline as every other confirmed room/patch draw. Reframes
      -- bank 5's likely purpose: small per-exit index/reference
      -- metadata selecting which bank-8 tile-patch block to reveal, NOT
      -- raw room tile art -- a plausible explanation for why bank 5's
      -- 255 RLE records never matched any known real room's pixels.
      -- Not live-verified this pass (deliberately static-only); see
      -- rom-map.md for the full call chain and open ends.
      --
      -- RESOLVED (2026-08-11, same day, "loese die offenen Fragen"):
      -- $235B/$22FE are a real, confirmed matched "open exit"/"close
      -- exit" SCRIPT OPCODE pair (found via the project's own
      -- ScriptOpcodeTable dispatch shape), called with a one-hot
      -- direction arg -- exhaustively found via whole-ROM scan, exactly
      -- 4 real call sites each: A=0x04->North, A=0x02->West,
      -- A=0x01->East, A=0x08(default)->South (derived from the fixed
      -- per-direction screen-cursor tables via $045D's row/col
      -- formula). This whole mechanism only ever runs from room-script
      -- bytecode, never generic per-frame code. Also exhaustively
      -- searched all 5 real callers of $26DC (roomSelectorTable
      -- dispatch): 3 hardcode index=7; the other 2 derive the index
      -- DYNAMICALLY from a script/data-cursor byte or an inherited
      -- register argument -- neither literally hardcodes 0 or 9
      -- anywhere in the ROM. So index 0/9 selection is genuinely
      -- script/data-driven, not a fixed code branch -- explains why
      -- live play never observed it (this project has never triggered
      -- whichever specific script/event data contains that byte). See
      -- rom-map.md "Resolving the 3 open ends" for the full trace.
      --
      -- Cross-reference to this project's own already-implemented
      -- rooms (`graphics` above), live-confirmed (marked "live") or
      -- inferred from the shared tile-source pointer alone (marked
      -- "static-only", a real but less rigorously confirmed link --
      -- see rom-map.md's own honesty note on this distinction):
      --
      -- `dynamicBank` (added 2026-08-11, read directly from byte 6 of
      -- each real 11-byte record via a fresh file-level dump -- NOT
      -- live-traced, purely static, see rom-map.md "Bank 5 revisited"):
      -- the real MBC bank each roomSelector switches in before
      -- resolving its `ptr` field. Full column: 5,6,7,7,7,7,7,7,6,5,6,
      -- 7,7,7,6,6. Recorded here because it closes an exhaustive static
      -- search for bank 5's only access point in the whole ROM: indices
      -- 0 and 9 are the ONLY two places anywhere that ever switch bank
      -- 5 in (confirmed by two independent whole-ROM byte-pattern
      -- scans finding zero hardcoded/direct bank-5 switches elsewhere).
      knownRooms = {
        -- roomSelector 0,1 -> tileSourcePointer 0xB040. LIVE-CONFIRMED
        -- (roomSelector=1, via $C3F5, in TWO separate CallTracer
        -- traces): both the real pre-combat courtyard AND this
        -- project's own `graphics.fourthRoom` share this exact pointer
        -- -- genuinely the same underlying room data, reused at two
        -- different points in the real game timeline. NOT merged in
        -- this project's own `startRoom`/`fourthRoom` definitions,
        -- since their own independently-captured tile sets only
        -- partially overlap (6/8 tiles) -- plausibly the same source
        -- data rendered through a different per-byte remap ($D070
        -- table) at each use, not literally identical output.
        --
        -- Index 0's dynamicBank=5, ptr=0x4000 is a striking find: with
        -- bank 5 switched in, CPU $4000 resolves to file offset
        -- 0x14000 -- EXACTLY the already-cracked bank-5 map table's own
        -- 4-byte header (00 03 10 10). Likely not coincidence, but NOT
        -- proof this is how the 256-record RLE table becomes on-screen
        -- room art: this `ptr` field's own established purpose (see
        -- the byte-layout comment above) is a 4-byte STATE/FLAG read
        -- into $C3F8-$C3FB, not a tile-data load. Open question, see
        -- rom-map.md.
        [0] = { targetPointer = 0x40B0, room = "startRoom / fourthRoom (same source, see note)", dynamicBank = 5 },
        [1] = { targetPointer = 0x40B0, room = "startRoom / fourthRoom (same source, see note)", dynamicBank = 6 },
        -- roomSelector 2-6 -> 0xB046. LIVE-CONFIRMED (the pointer
        -- itself, many times this whole session) as the willyRoom/
        -- secondRoom/thirdRoom continuous scrollable chain this
        -- project already implements. Which of these 5 specific
        -- roomSelectors corresponds to which sub-entry was not
        -- individually re-verified via $C3F5 (honest gap, see
        -- rom-map.md).
        [2] = { targetPointer = 0x46B0, room = "willyRoom / secondRoom / thirdRoom family", dynamicBank = 7 },
        [3] = { targetPointer = 0x46B0, room = "willyRoom / secondRoom / thirdRoom family", dynamicBank = 7 },
        [4] = { targetPointer = 0x46B0, room = "willyRoom / secondRoom / thirdRoom family", dynamicBank = 7 },
        [5] = { targetPointer = 0x46B0, room = "willyRoom / secondRoom / thirdRoom family", dynamicBank = 7 },
        [6] = { targetPointer = 0x46B0, room = "willyRoom / secondRoom / thirdRoom family", dynamicBank = 7 },
        -- roomSelector 7 -> 0x4C1A. Live-observed as the value present
        -- immediately BEFORE the pre-combat 0xB040 transition fires --
        -- reads as an even earlier placeholder/black-screen state, not
        -- a real explorable room. Not implemented (nothing to show).
        [7] = { targetPointer = 0x4C1A, room = "UNKNOWN -- pre-transition placeholder, not explorable", dynamicBank = 7 },
        -- roomSelector 8-13 -> 0x4938. NEVER reached in any
        -- playthrough this project has driven. Real pointer, but no
        -- live tile capture exists -- see `unknownRoomA` attempt notes
        -- below/in rom-map.md for whether this pass managed to force
        -- one. Index 9's dynamicBank=5 is the SECOND (and only other)
        -- real bank-5 access point in the whole ROM -- its ptr=0x7CD7
        -- resolves to file offset 0x17CD7, inside bank 5's own
        -- confirmed-data-only tail region (no code found there).
        [8] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 6 },
        [9] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 5 },
        [10] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 6 },
        [11] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 7 },
        [12] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 7 },
        [13] = { targetPointer = 0x4938, room = "UNKNOWN -- see unknownRoomA", dynamicBank = 7 },
        -- roomSelector 14,15 -> 0x43B0. Same "shared 0xB0 low byte"
        -- family as the willyRoom/fourthRoom pointers, never reached.
        [14] = { targetPointer = 0x43B0, room = "UNKNOWN -- see unknownRoomB", dynamicBank = 6 },
        [15] = { targetPointer = 0x43B0, room = "UNKNOWN -- see unknownRoomB", dynamicBank = 6 },
      },
    },

    -- VERIFIED (2026-08-11, "loese die map komplett" -- see rom-map.md
    -- "MILESTONE 3 SOLVED" for the full disassembly/live-tracing chain):
    -- the real, general room-FLOOR-layout decompression pipeline. PORTED
    -- (same day, "ja mach das bitte") to a real Lua decoder --
    -- `src/import/RoomFloorLayout.lua`, cross-checked end to end against
    -- a fresh, real ROM load in `tests/import/room_floor_layout_test.lua`
    -- (not just this pass's own one-off Python scratch verification).
    -- `src/import/MapTable.lua` still separately implements the older,
    -- bank-5-specific RLE scheme (a different table shape, see rom-map.md
    -- "Bank 5, revisited" for how the two relate).
    --
    -- Per room (indexed via the SAME roomSelectorTable record used for
    -- the metatile table below):
    --   1. `targetPointer` (this table's own DE field) + `dynamicBank`
    --      point to a real METATILE TABLE: 6-byte records
    --      `[gfxTileTL, gfxTileTR, gfxTileBL, gfxTileBR, collision, interaction]`
    --      (matches the FFA-Disassembly project's own documented US-ROM
    --      format exactly -- see rom-map.md's external-source section).
    --      The 4 GFX-tile bytes are NOT final tile IDs directly -- each
    --      must be remapped through the live WRAM `$D070-$D16F` table
    --      (`table[byte] = real tile ID`, populated at runtime, not
    --      ROM-static -- this project used a single targeted live dump
    --      to get it for willyRoom; a generic extractor needs the same
    --      per-room, or to find $D070's own real populator).
    --   2. A SEPARATE compressed layout stream (found this pass via
    --      `$2740`'s `$C3F8`-gated `$25F6`/`$25D1` resolvers, indexed by
    --      `$C3FB` and the roomSelector's own `ptr` field -- for
    --      willyRoom this resolves to real file offset `0x1DA50`, bank
    --      7, i.e. a DIFFERENT bank than the metatile table's own bank
    --      8) holds the room's real per-cell metatile-index grid,
    --      RLE-compressed: a source byte with bit 7 SET means "write
    --      `byte & 0x7F`, repeated **`$C3F9`** times" (live-confirmed
    --      `$C3F9=4` for willyRoom -- the real per-room RLE run-length,
    --      NOT a fixed global constant); bit 7 clear is a literal
    --      metatile index. `$242B` is the real ROM decompressor,
    --      writing 80 output bytes (for willyRoom's real 8-row x 10-col
    --      metatile grid, stride 10 -- see `$23F1`'s own real
    --      `$C350 + row*10 + col` addressing) into WRAM `$C350`.
    --   3. Combine: for grid position (metatileRow, metatileCol), look
    --      up the decompressed index, resolve its metatile-table
    --      record, and place the 4 GFX tiles (D070-remapped) into the
    --      final pixel grid at (metatileRow*2, metatileCol*2).
    --   4. The 4 door/exit graphics (N/W/E/S) are DELIBERATELY NOT part
    --      of this base layout (the compressed stream encodes blank
    --      placeholders there) -- they're drawn by the SEPARATE,
    --      already-documented `$235B`/`$225D`/`$2281`/`$056C` exit-
    --      reveal mechanism (see `roomSelectorTable`'s own doc comment
    --      above), confirmed by an exact match: rendering willyRoom via
    --      steps 1-3 alone reproduces 288/320 real tile positions
    --      exactly, and every one of the remaining 32 falls precisely
    --      inside the 4 already-known door zones (8 tiles each).
    --
    -- Cross-validated end to end against `graphics.willyRoom.grid`
    -- (below) -- not a hypothesis, a working, live-verified decode.
    --
    -- GENERALIZED 2026-08-12 ("weiter der world scope"): the real
    -- Milestone-3 generalization proof, closed. `unknownRoomB`
    -- (roomSelectors 14-15, the real black-wipe transition backdrop --
    -- see rom-map.md "unknownRoomB SOLVED") was reached via a REAL,
    -- transition-triggered room load (not forced/synthetic), single-
    -- stepped to its own live `$242B` call to find its real layout-
    -- stream source (`HL` at entry, resolved through the live-mapped
    -- bank). This project's own UNCHANGED `RoomFloorLayout.
    -- decodeLayoutStream` function, pointed at that real address,
    -- reproduces the real, live-observed WRAM result exactly (80/80
    -- bytes = 12) -- the pipeline mechanism itself (metatile-table
    -- location formula + RLE layout-stream decode) is now proven, with
    -- real code against real ROM bytes, to generalize to a genuinely
    -- different room, not just re-decode willyRoom successfully again.
    -- The room's own real content happens to be trivial (a uniform/
    -- solid backdrop tile, matching its real role), but the MECHANISM
    -- proof is exactly what Milestone 3's own DoD needed.
    roomFloorLayoutPipeline = {
      status = "VERIFIED (willyRoom + unknownRoomB + unknownRoomA's 6 rooms -- 8 genuinely different rooms total)",
      metatileRecordLength = 6,
      metatileFields = { "gfxTL", "gfxTR", "gfxBL", "gfxBR", "collision", "interaction" },
      rleControlFlag = 0x80,
      rleValueMask = 0x7F,
      rleLengthSource = "WRAM $C3F9 (per-room, live -- willyRoom=4, unknownRoomB=4)",
      layoutArrayWramBase = 0xC350,
      layoutArrayStride = 10,
      exampleRoom = {
        room = "willyRoom",
        metatileTableFileOffset = 0x206B0,   -- bank 8, CPU $46B0
        layoutStreamFileOffset = 0x1DA50,    -- bank 7, CPU $5A50
        metatileGridRows = 8,
        metatileGridCols = 10,
        rleLength = 4,                       -- live WRAM $C3F9 at willyRoom load
      },
      secondExampleRoom = {
        room = "unknownRoomB",
        -- Real, live-confirmed via a genuine transition (the post-boss
        -- black wipe), not forced -- see this table's own doc comment
        -- above and rom-map.md's "unknownRoomB SOLVED" + follow-up.
        metatileTableFileOffset = 0x203B0,   -- bank 8, CPU $43B0
        layoutStreamFileOffset = 0x19CFB,    -- live-found via single-stepping to $242B's own entry HL
        metatileGridRows = 8,
        metatileGridCols = 10,
        rleLength = 4,                       -- live WRAM $C3F9 at this room's own load
        -- Real, live-confirmed content: all 80 decoded indices equal
        -- 12, a genuine uniform/solid metatile (record 12's own 4 GFX
        -- bytes are all 0x26) -- the black-wipe backdrop is really just
        -- one solid tile repeated across the whole grid, not a
        -- decode-time special case.
      },
      -- UPGRADED TO VERIFIED (2026-08-12, same day, direct follow-up):
      -- rendered all 6 candidate rooms to REAL PNGs using this
      -- project's own already-established formulas end to end --
      -- `tools/graphics/render_unknown_room_a.py` is the checked-in,
      -- reproducible recipe (deliberately NOT committing the rendered
      -- PNGs themselves -- they embed real, directly-extractable
      -- copyrighted game graphics, same "recipe not output" rule
      -- already applied to `tools/rom/checkpoints.py`'s own `.state`
      -- files). All 6 rooms are UNMISTAKABLY real, coherent dungeon
      -- interiors: brick wall borders, a mesh/net floor pattern,
      -- torches, distinct furniture/feature objects (a bed-or-altar
      -- shape in one room, a window/lattice in another) -- not
      -- remotely what a wrong/misaligned decode produces. Backed by a
      -- real, quantified metric too, not just eyeballing:
      -- `gbtile.py`'s own already-established `tile_entropy()`
      -- heuristic averages 1.22-1.51 bits across all 6 rooms' own
      -- distinct tiles -- squarely in its own documented "real art"
      -- band (~1.0-1.8), far from blank (0.0) or noise (~2.0).
      -- **Both hypotheses confirmed at once**: (1) roomSelector N's
      -- own real layout stream IS bank 5's own record N, and (2) the
      -- final GFX-tile-byte -> real pixel data step reuses
      -- `MapTable.lua`'s own already-VERIFIED `tilesetFileOffset=
      -- 0x32000 + tileId*16` formula (previously only established for
      -- bank 5's own OLDER, superseded "direct tile ID" reading --
      -- turns out it's the right formula for the FINAL metatile-GFX-
      -- byte stage instead). See rom-map.md's own "unknownRoomA
      -- VISUALLY CONFIRMED" section for the full writeup.
      --
      -- Still real, honestly-scoped open items: no live gameplay
      -- trigger found (see rom-map.md's own bounded search) means this
      -- is ROM-verified, not yet gameplay-gated the way e.g. willyRoom
      -- is; the real BGP/palette values for these rooms are unverified
      -- (rendered here with the same default DMG grey ramp used
      -- elsewhere); not yet wired into the actual LÖVE app as
      -- walkable content.
      --
      -- CORRECTED / SCOPE SHARPENED (2026-08-14, direct user report
      -- after the room-catalog export: "die sind bei allen ausser den
      -- bekannten total off" -- the tiles look totally wrong for every
      -- catalog room except the known ones). `metatileTableFileOffset`
      -- below (0x20938) is independently, ROM-confirmed correct ONLY
      -- for these 6 records (roomSelector 8-13's own real `$D392`/
      -- `$D393` DE field from the already-VERIFIED `$026DC` dispatch
      -- table -- not a guess, a live-traced hardware fact). It was
      -- ALSO reused, as a best-effort placeholder with no independent
      -- confirmation, for every other bank-5/bank-6 record in the
      -- 320-room catalog (`rom-inspector`'s `ROOM_CATALOG` /
      -- `RoomExplorer.lua`) -- the "VISUALLY + QUANTITATIVELY
      -- CONFIRMED" language on `mapTable`/`mapTableBank6` below only
      -- ever meant "decodes to real, non-noise GB tile art," NOT
      -- "uses the semantically correct tiles for that room" (round 3's
      -- own already-recorded warning: "this signal alone does not
      -- usefully separate a real, distinct, walkable room from any
      -- other bank-5 record" -- this is that exact risk materializing).
      -- A genuinely new lead was tried this pass and RULED OUT: the
      -- small per-record header `MapTable.decode` already parses (a
      -- 0xFF-terminated blob before each data blob, never previously
      -- interpreted) was tested as a possible per-record metatile-
      -- table pointer -- record 9 (part of this CONFIRMED family, real
      -- table 0x20938) has a 6-byte header whose own trailing u16
      -- decodes to 0x20381, NOT 0x20938 -- directly falsified against
      -- known-good ground truth, and a full 256-record scan found ZERO
      -- bank-5 records whose header resolves to 0x20938 at all. No
      -- working alternative mechanism is currently known; this remains
      -- the same open mystery round 3/4 already concluded ("the real
      -- blocker is how the ROM selects ANY room beyond the 16
      -- `roomSelectorTable` entries, not which metatile table"). The
      -- room-catalog website now labels this explicitly (see
      -- `rom-inspector/js/viz/mapviewer.js`'s catalog note text) --
      -- only these 6 rooms' TILES, not just their room identity, are
      -- confirmed correct.
      --
      -- UPGRADED (2026-08-14, "gehe dem map header hinweis nach"):
      -- following the external FFA-Disassembly project's own US-ROM
      -- `MAP_HEADER` model (`tilesetGfx, metatiles, mapRoomPointers`,
      -- one tileset shared by every room in a map, no per-room
      -- override documented) plus this EU ROM's own newly-decoded
      -- `roomSelectorTable.offsetParam` field (see `RoomSelectorTable
      -- .resolveMapRoomPointersFileOffset`, VERIFIED via an exact byte
      -- match), found a real, structurally-justified candidate for the
      -- 320-room catalog's own DEFAULT metatile table (see
      -- `genericCatalogMetatileTableFileOffset` below) -- NOT this
      -- table (`0x20938`), which stays correct ONLY for `unknownRoomA`
      -- itself (roomSelector 8-13, a SEPARATE, independently-reachable
      -- 6-room map that happens to reuse the same underlying bank-5
      -- RLE data bytes as map 0's own grid positions 8-13 -- real ROM
      -- space reuse, not evidence the two are the same room in every
      -- context). The room-catalog export now uses the new default
      -- table for ALL 320 entries (including positions 8-13, which
      -- represent map 0's OWN room there, not `unknownRoomA`).
      unknownRoomACandidates = {
        status = "VERIFIED (all 6 rooms render as real, coherent dungeon art -- see tools/graphics/render_unknown_room_a.py). " ..
          "Its own metatileTableFileOffset is confirmed correct for unknownRoomA specifically (roomSelector 8-13) -- the " ..
          "320-room catalog now uses genericCatalogMetatileTableFileOffset instead, see the UPGRADED doc comment above (2026-08-14).",
        metatileTableFileOffset = 0x20938, -- bank 8, CPU $4938 (already-found real unknownRoomA metatile table)
        bank5PointerTableFileOffset = 0x14004, -- already-VERIFIED mapTable.pointerTableFileOffset
        bank5BankFileStart = 0x14000,          -- already-VERIFIED mapTable.bankFileStart
        rleLength = 3,                          -- bank 5's own established header rleLength (MapTable.lua)
        tilesetFileOffset = 0x32000,             -- MapTable.lua's own already-VERIFIED formula; tileId*16 bytes/tile
        metatileGridRows = 8,
        metatileGridCols = 10,
        -- Real roomSelector -> real bank-5 record index (identical by
        -- this now-VERIFIED hypothesis) -- all 6 of unknownRoomA's own
        -- real selectors, each a distinct, real dungeon room.
        rooms = { 8, 9, 10, 11, 12, 13 },
      },
      -- The 320-room catalog's own DEFAULT metatile table (2026-08-14,
      -- "gehe dem map header hinweis nach") -- see the UPGRADED doc
      -- comment above `unknownRoomACandidates` for the full chain of
      -- evidence. Derivation, every link independently real:
      --   1. roomSelectorTable's own record 0 (bank5's "map") and
      --      record 1 (bank6's "map") both have real `tileSourcePointer`
      --      = $40B0 (the SAME already-known real value `startRoom`'s
      --      own doc comment cites).
      --   2. Resolved via the ALREADY-VERIFIED bank8-relative formula
      --      (bank8Base + (tileSourcePointer - 0x4000), the same
      --      formula independently confirmed for willyRoom/unknownRoomA/
      --      unknownRoomB): 0x20000 + (0x40B0-0x4000) = 0x200B0.
      --   3. Cross-checked against the external FFA-Disassembly
      --      project's own documented US-ROM architecture: one
      --      metatile table per MAP, shared by every room in it, no
      --      per-room override documented -- roomSelector 0/1 are each
      --      their own "map" (VERIFIED via `resolveMapRoomPointersFile
      --      Offset`'s own exact byte match to mapTable's/mapTable
      --      Bank6's real headers), so this is the correct default for
      --      literally every one of their 320 real rooms.
      --   4. Directly visually re-checked (2026-08-14): 12 widely-
      --      spread bank-5 records (0, 15-17, 31-32, 63-64, 128, 200,
      --      240, 255) all show the SAME recurring door-arch symbol and
      --      dotted-floor pattern with this table -- a real, internally
      --      consistent visual vocabulary across the WHOLE 16x16 grid,
      --      not present with the old `unknownRoomACandidates`-borrowed
      --      placeholder.
      -- HONEST STATUS: a real, structurally-justified, externally-
      -- corroborated derivation -- NOT independently ground-truth-
      -- verified the way `unknownRoomACandidates`'s own table is (no
      -- live gameplay reaches ANY of these 320 rooms, so there is no
      -- way to confirm this the way willyRoom's collision/floor data
      -- was confirmed). Upgraded from "unverified placeholder, likely
      -- wrong" to "best current derivation," not to "proven."
      genericCatalogMetatileTableFileOffset = 0x200B0, -- bank 8, CPU $40B0 (roomSelector 0/1's own real tileSourcePointer)
    },

    -- The real combat PRNG's noise table -- see docs/reverse-engineering/
    -- rom-map.md "$50AC, the real damage formula" and combat.md's "Enemy
    -- HP" section for the original find. VERIFIED: fixed bank 0 (always
    -- mapped), 256 raw bytes, read by ROM routine `$2B1E` -- confirmed
    -- real (not guessed) noise-shaped data, not a second tileset or
    -- text table. `src/import/NoiseTable.lua` is the generic decoder;
    -- `src/entities/CombatNoise.lua` ports `$2B1E`'s own real counter/
    -- cap/double-lookup draw algorithm (disassembled fresh 2026-08-10,
    -- see rom-map.md for the exact instruction-by-instruction trace) --
    -- not a `math.random()` stand-in.
    noiseTable = {
      status = "VERIFIED",
      fileOffset = 0x2A1E,
      length = 256,
      bank = 0,
    },

    -- The real per-species enemy combat table -- see combat.md's
    -- "$50AC" section and rom-map.md's "P1 resolved" section for the
    -- full live-trace evidence. VERIFIED: bank 4, file
    -- `0x10c80`-`0x10df0`, 8-byte stride, 46 rows / 11 distinct
    -- species patterns. `src/import/EnemySpeciesTable.lua` is the
    -- generic decoder -- see its own doc comment for the full,
    -- honestly-labeled field map (ATK VERIFIED; two DEF-candidate
    -- fields real but NOT confirmed live, including a 2026-08-12
    -- follow-up that ruled out one specific lead without finding a
    -- replacement).
    enemySpeciesTable = {
      status = "VERIFIED (table location + stride + ATK field); DEF fields real but unconfirmed",
      bank = 4,
      fileOffset = 0x10C80,
      rowCount = 46,
      -- Real, live-traced example (see combat.md/rom-map.md): row 19
      -- (0-based, file 0x10D18) is the one enemy this project has
      -- actually fought -- atk=8, matching the live `$50AC` register
      -- `B` exactly, twice, independently.
      verifiedExample = { rowIndex = 19, fileOffset = 0x10D18, atk = 8 },
    },

    -- FOUND, 2026-08-17 (external-reference-driven search -- see
    -- src/import/EnemyStatTable.lua's own doc comment for the full
    -- evidence trail): 21 real records, 24-byte stride, bank 4. Every
    -- record's own speed/hpBase/xp/gold bytes matched the US "Final
    -- Fantasy Adventure" disassembly's own documented boss list
    -- BYTE-FOR-BYTE (all 21 bosses' 4-byte signatures found at this
    -- exact stride) -- this EU localization kept the same combat
    -- balance numbers as the US cartridge. Independently cross-checked
    -- against THIS project's own EARLIER, unrelated live-CPU-trace
    -- finding (`Enemy.lua`'s `HP_INIT_TRACE_NOTE`): file `0x108ba`
    -- (this table's row 16 `hpBase` byte) already had a real, live-
    -- confirmed role in the enemy HP-randomization formula, landing on
    -- the exact same byte this external-reference search found
    -- independently.
    --
    -- SAME TABLE, found again 2026-08-17 (same day): this is the exact
    -- same table as `messageTextPointer` below's own "ALREADY-known
    -- message-settings record base/stride (CPU `$4739`/file `0x10739`,
    -- 24 bytes/record)" -- itself reused from an even EARLIER
    -- (2026-08-15) investigation (events.md's "Second boss
    -- investigation") that independently found a real "species byte"
    -- field at this table's own `+5` and 5 real sibling rows (3, 5,
    -- 10, 16, 18) sharing it -- all 5 confirmed byte-for-byte against
    -- THIS table too. See EnemyStatTable.lua's own doc comment for the
    -- full reconciliation (field renamed `projectileType` ->
    -- `speciesByte` to match that earlier, independently-verified
    -- name).
    enemyStatTable = {
      status = "VERIFIED (table location + stride + speed/hpBase/xp/gold/speciesByte fields, via exact external-reference byte match AND an independent, earlier internal investigation); other fields real but unconfirmed against this EU ROM",
      bank = 4,
      fileOffset = 0x10739,
      rowCount = 21,
      -- Real English names from the external US disassembly, in real
      -- ROM record order -- NOT yet independently confirmed these are
      -- the correct in-story pairing for THIS EU ROM's own ROOM/
      -- SPAWN placements (only the record VALUES were cross-checked,
      -- not which room spawns which record) -- kept here as a
      -- documented, sourced lead, not a claim of live verification.
      externalReferenceNames = {
        "Vampire", "Hydra", "Medusa", "Megapede", "Davias", "Golem",
        "Cyclops", "Chimera", "Kary", "Kraken", "Iflyte", "Lich",
        "Garuda", "Dragon", "Julius (Form 2)", "Dragon Zombie",
        "Jackal", "Julius (Form 3)", "Metal Crab", "Mantis Ant",
        "Dragon (Final)",
      },
      -- Real, live-traced cross-check (see EnemyStatTable.lua's own
      -- doc comment): row 16 (0-based, "Jackal") is the ONE record
      -- this project has independently confirmed via a completely
      -- separate, earlier live-CPU-trace investigation, long before
      -- this table was found by external reference.
      verifiedExample = { rowIndex = 16, fileOffset = 0x108B9, hpBase = 2 },
    },

    -- THE real event/script interpreter's opcode dispatch table -- see
    -- docs/reverse-engineering/rom-map.md "THE real event/script
    -- interpreter -- FOUND, FULLY DECODED" (2026-08-10) for the full
    -- trace. VERIFIED: bank 2, file offset 0x8576, 256 records x 2
    -- bytes (real CPU handler addresses, LE), indexed by the real
    -- WRAM "current opcode" byte ($D85A). Confirmed exactly 256 real
    -- entries (file 0x8776 onward is ordinary code, not more table
    -- data) and live-verified against 2 independently-traced opcodes
    -- (0x04 and 0xFE, the real "display message" trigger).
    -- `src/import/ScriptOpcodeTable.lua` is the generic decoder.
    --
    -- UPDATE 2026-08-11 ("zurück zu den primären optcodes"): a real,
    -- ~70-opcode-wide FAMILY found across opcodes 0x10-0x7B (see
    -- events.md's own "Back to the primary table" section) -- 7 clean
    -- groups, each gated by a real actor-struct accessor (`$28C2` ->
    -- `$0C6D`, a genuine 16-byte-record WRAM array at `$C200`, indexed
    -- by a real "slot" number -- slots 4 and 7 confirmed used by name
    -- elsewhere in the ROM) and an 8-way "action code" that funnels
    -- into a shared dispatcher (`$2879`) which tail-calls bank 3 --
    -- NOT followed across that bank switch this pass, same honest
    -- limit as the 0xFF sub-table's own bank-2 delegations. The gaps
    -- in this 0x10-0x7B grid are exactly the already-known HEAL_LP
    -- opcodes (0x12/0x13, 0x22/0x23, ...) -- the two families tile the
    -- same opcode space without overlap, a real cross-confirmation.
    -- Real structural understanding for ~70-80 opcodes now exists even
    -- though the bank-3 "what does action 0x0A actually do" layer
    -- remains open.
    --
    -- UPDATE 2026-08-11 ("ok dann bank 3"): that layer is now closed
    -- too -- see events.md's "Bank 3, followed" section. The bank-3
    -- trampoline (`$1F35`) genuinely preserves the caller's real
    -- 8-way action code through the bank switch, so all 8 variants
    -- funnel into ONE bank-3 function (0x0A, file 0xCB70), not 8
    -- separate ones. Found: a real 8-slot "known/active ID" list at
    -- WRAM `$C5A0` (a shared utility, general linear-search primitive
    -- `$4B62`), and a THIRD distinct WRAM actor/object array at
    -- `$C4E0` (24-byte stride, different from `$C200`'s 16-byte
    -- structs). Real, well-supported conclusion: this whole 70+11-
    -- opcode span is a genuine "mark actor/flag N as having reached
    -- state V, tracked in a global known-list" mechanism -- very
    -- plausibly this ROM's own real quest/story-progress-flag system.
    scriptOpcodeTable = {
      status = "VERIFIED",
      bank = 2,
      fileOffset = 0x8576,
      recordCount = 256,
    },

    -- THE real script/event POINTER table -- answers the question this
    -- project's own `scriptOpcodeTable`/`ScriptInterpreter.lua` had left
    -- open since first finding the opcode DISPATCH table: where do real
    -- script BYTES live, and how does the interpreter's own persistent
    -- cursor (`$D8B6`/`$D8B7`) ever get pointed at one. See
    -- docs/reverse-engineering/events.md's "A real script-pointer table
    -- FOUND" / "The index question, CONCLUSIVELY RESOLVED" (2026-08-12)
    -- for the full chain, live-traced end to end for a real trigger (the
    -- boss-defeat story sequence) and confirmed twice over (live
    -- execution AND independent static ROM-byte computation agreeing
    -- exactly).
    --
    -- VERIFIED real mechanism: `HL = table[index]` (byte-indexed,
    -- 2-bytes-per-entry, same shape as every other indexed table in this
    -- ROM), then the CALLER adds `0x4000` to the result to get the real
    -- CPU address -- this table stores small bank-8-relative OFFSETS,
    -- not full addresses. `index` itself comes from a real WRAM actor/
    -- context record (a bank-select byte + a 16-bit ROM pointer,
    -- dereferenced twice, +2 to skip a small header) via a shared
    -- dispatcher at `$31AD` (15 real, independent call sites found
    -- across the ROM) -- 3 special-cased small index values (`0x0B`/
    -- `4`/`8`) redirect to fixed WRAM addresses instead of this table
    -- (some scripts are WRAM-resident, not ROM data).
    --
    -- Live-verified for real index 232 (`0xE8`, the boss-defeat
    -- trigger): `table[232]` (this file's own `fileOffset + 232*2`) =
    -- `0x070F` -> `+0x4000` = `0x470F` -- matches the live-observed
    -- interpreter cursor jump target exactly. Real table content dumped
    -- through at least index 89 (a real, structured, mostly-monotonic
    -- sequence of small values, including one genuine 12-entry run of
    -- `0x0000` -- an unused/reserved block, not noise) -- the table's
    -- own real full extent (recordCount) is NOT yet determined (no
    -- terminator/boundary found this pass).
    --
    -- Honestly still open: what the `$C3F0`/`$C3FE`/`$C3FF` WRAM record
    -- represents in general (per-room? per-actor? only the MECHANISM
    -- that reads it is confirmed, not its own broader schema); the
    -- real-world meaning of the 3 special-cased index values; this
    -- table's own real `recordCount`. NOT wired into `ScriptInterpreter
    -- .lua` yet -- this is real, verified DATA LOCATION, not yet a
    -- consumed runtime data source (most of the 256 primary opcodes'
    -- own semantics remain undecoded, the actual blocker for driving
    -- real gameplay from this).
    scriptPointerTable = {
      status = "VERIFIED (table location + lookup formula + one real, live-traced index + real recordCount all confirmed)",
      bank = 8,
      fileOffset = 0x20F11, -- CPU $4F11
      cpuBankOffsetBase = 0x4000, -- add to each raw table entry to get the real CPU address
      -- Real, confirmed 2026-08-12 ("Skript-Tabelle nach mehr echtem
      -- Content durchsuchen"): index 1356 is real/sensible, index 1357
      -- onward is uniform 0xFFFF unprogrammed-ROM filler (2714 raw bytes
      -- checked at the boundary) -- see events.md "The script-pointer
      -- table's real size: exactly 1357 entries".
      recordCount = 1357,
      -- Real, live-traced example (see events.md for the full chain):
      -- index 232 -> table[232]=0x070F -> +0x4000 = 0x470F (real script
      -- start, bank 8 file 0x2070F) -- the boss-defeat story trigger.
      verifiedExample = { index = 232, tableValue = 0x070F, scriptCpuAddress = 0x470F },
    },

    -- THE real message-text pointer, found via the `$1F64` dispatcher
    -- investigation (2026-08-12, direct instruction "ja mach die
    -- dispatcher untersuchung bitte") -- see docs/reverse-engineering/
    -- text.md's "SOLVED: the real message-settings-table text pointer"
    -- section for the full disassembly chain (`$04E2` 5-way sub-
    -- dispatcher -> `$1F64` -> bank-4 table index 1 -> `$102F7`).
    -- Reuses the ALREADY-known message-settings record base/stride
    -- (CPU `$4739`/file `0x10739`, 24 bytes/record) -- this is a NEW
    -- FIELD found in that same already-partially-characterized table,
    -- not a new table of its own.
    messageTextPointer = {
      status = "VERIFIED (formula + disassembly chain confirmed; strong multi-word real-text confirmation via messageID 13, most other messageIDs still blocked by TextDecoder's own incomplete digraph coverage, not a formula problem)",
      recordBaseFileOffset = 0x10739, -- same base as scriptPointerTable's index field, CPU $4739
      recordStride = 24,
      -- 0-based byte offset into the 24-byte record; a 16-bit LE value.
      recordFieldOffset = 20,
      -- Add to the raw 16-bit record field to get the real file offset
      -- of the message's own NUL-terminated, TextDecoder-compatible text.
      fileOffsetBase = 0x34800,
      -- Real, verified example (see text.md): messageID 13 -> record at
      -- file 0x10739+13*24=0x107C5 -> field bytes at +20/+21 = 0x5165 ->
      -- text file offset 0x34800+0x5165=0x39965 -> decodes as "gefunden"
      -- (immediately followed by 2 more real, complete item-pickup
      -- messages in the same window: "Smaragd gefunden", "Saphir ...
      -- gefunden").
      verifiedExample = { messageId = 13, fieldValue = 0x5165, textFileOffset = 0x39965, decodedText = "gefunden" },
    },

    -- THE real SECOND-LEVEL sub-dispatch table, reached only via the
    -- primary table's own opcode `0xFF` (handler `$38E6`) -- see
    -- docs/reverse-engineering/rom-map.md "The 0xFF sub-dispatch table
    -- -- bounded and disassembled" (2026-08-11) for the full trace.
    -- VERIFIED: fixed bank 0 (always mapped, no bank-switch needed --
    -- matches `$38E6` itself living at a fixed-bank address), file
    -- offset 0x3BAC, indexed by WRAM `$D86B` (a SEPARATE "current
    -- sub-opcode" byte from the primary table's own `$D85A`).
    -- Mechanism (full disassembly, closes rom-map.md's earlier "not
    -- itself single-stepped" gap for THIS dispatch): `LD A,($D86B) /
    -- LD HL,0x3BAC / LD B,0 / LD C,A / ADD HL,BC / ADD HL,BC / LD
    -- A,(HL+) / LD H,(HL) / LD L,A / JP HL` -- the exact same byte-
    -- indexed, 2-bytes-per-entry, tail-jump shape as the primary
    -- table, just a different base/index. Confirmed NOT 256 entries
    -- (only ever hedged as "256-entry-style" before, never checked):
    -- entries decode as plausible fixed-bank code-pointer values for
    -- exactly 11 records, then the 12th "entry" (file 0x3BC2) decodes
    -- as `0x21` -- the real `LD HL,nn` opcode, i.e. genuine CPU code
    -- immediately following the table, not more table data. Also
    -- confirmed from the OTHER side: the routine immediately before
    -- the table (file 0x3BA9-0x3BAB) is a clean, self-contained `JP
    -- 0x0150`, the normal "code ends, table begins" shape this
    -- project's other tables all share.
    -- **No bounds check** on the `$D86B` index before the ADD HL,BC --
    -- a real, honest observation (not a bug this project patches): if
    -- `$D86B` is ever >= 11 in real play, the ROM would index into its
    -- own ordinary code bytes as a bogus pointer. Not contradicted by
    -- anything found so far, just flagged, matching this project's
    -- "no silent fallbacks" -- assume nothing about values never
    -- observed live.
    --
    -- UPDATE 2026-08-11 ("nein bitte weiter bei den optcodes"): 7 of
    -- the 11 real entries now have a disassembled, stated conclusion
    -- -- see events.md's own "The 0xFF sub-table, continued" section
    -- for the full trace of each. The headline find: `$3C74`, a real
    -- shared "reschedule the sub-dispatch to a different entry on the
    -- NEXT tick" primitive (writes both `$D86B` and `$D85A`=0xFF, then
    -- returns WITHOUT fetching the next real opcode) -- this is HOW 4
    -- of the 11 entries (indices 3/`$3C1B`, 4/`$350F`, 7/`$3B18`,
    -- 8/`$3B2C`) form a genuine, structurally-VERIFIED multi-tick
    -- "wait/halt" family, each conditionally skipping the `CALL $3727`
    -- that would otherwise resume the interpreter. Index 8 is the
    -- real release point (halts on `$D853` bit 7, resumes once clear).
    -- Live-traced TWICE for real-world trigger conditions (Watcher on
    -- `$D86B` across the full post-boss dialogue AND the real door->
    -- secondRoom scroll) -- zero hits both times, an honest negative:
    -- this chain is used by neither dialogue nor the room-scroll
    -- engine (which has its own dedicated `$46C4` mechanism, see
    -- maps.md).
    --
    -- UPDATE 2026-08-11, same day ("na dann die letzten 4"): all 11
    -- entries now disassembled to a stated conclusion (events.md's own
    -- "The 0xFF sub-table, finished" section has the full per-entry
    -- table) -- and the "plausibly NPC movement" guess above was
    -- WRONG, corrected with real evidence: entry 0 and several of
    -- entry 1's own internal branches end by calling `$36D0`, which
    -- caches HL into `$D8B6`/`$D8B7` (this project's own already-
    -- documented real script cursor) and sets `$D85A=0x04` -- the
    -- exact address already flagged elsewhere as the real-time
    -- TYPEWRITER dispatch, not the general interpreter. Entry 1 also
    -- has a real 5-tick pacing gate (`$36C2`/WRAM `$D864`) matching
    -- this project's own independently-confirmed real "5 frames per
    -- letter" cadence, a 4-direction cursor-delta dispatcher, and
    -- entry 2 blanks tile runs with the real space glyph (`0x7F`).
    -- **This is the real driver for a more elaborate MULTI-LINE
    -- textbox variant** (cursor bookkeeping, line-wrap, blanking) on
    -- top of the already-known single-line typewriter, not an NPC-
    -- movement system -- explaining the 2 live-trace negatives above:
    -- both tested checkpoints plausibly use the simpler, direct
    -- `$D3E9`-based reveal instead. Entry 5 independently reads WRAM
    -- `$D3E8` -- one byte before the already-VERIFIED `$D3E9` reveal
    -- timer (text.md) -- a second, concrete cross-link. Real, still-
    -- open scope: several entries (5, 10, and more) delegate into
    -- BANK 2 functions not followed across the bank switch this pass.
    --
    -- CORRECTED 2026-08-12 ("kann der [tooling bug] auch andre stellen
    -- betroffen haben?"): the "zero hits both times" dialogue claim
    -- 2 paragraphs up was WRONG -- a real tooling bug (see tooling.md's
    -- own "session.run(N)+Watcher can silently drop hits" section;
    -- `$D86B` was watched together with the fast-changing `$D85A`,
    -- driven by `session.run(1)`, which can silently lose a hit).
    -- Re-verified the CORRECT way (`w.step()`, single SM83 instruction
    -- at a time, no shortcuts): `$D86B` genuinely IS written 7 times
    -- during the real dialogue sequence, each immediately followed by
    -- `$D85A`=0xFF (the exact `$3C74` signature) -- real, live
    -- confirmation that sub-opcodes 1 and 3, then 4, DO fire during
    -- real character-by-character reveal, exactly matching this
    -- entry's own "sub-opcode 1 is the real typewriter-pacing routine"
    -- conclusion above. The door-scroll negative and the separate
    -- `$C5A0`/`$C4E0` write-negative (a different claim, see below)
    -- were BOTH independently re-verified with the correct method and
    -- hold up -- only the dialogue/`$D86B` claim was actually wrong.
    scriptOpcodeSubTable = {
      status = "VERIFIED",
      bank = 0,
      fileOffset = 0x3BAC,
      recordCount = 11,
    },

    -- Item/spell name+stat table -- see docs/reverse-engineering/rom-map.md
    -- "Item/spell table" (PARTIALLY VERIFIED: names, the record's 16-byte
    -- width, and the per-category ID byte are confirmed; the remaining
    -- stat bytes are not decoded). `src/import/ItemTable.lua` is the
    -- generic decoder.
    -- EXTENDED, 2026-08-15 (monster/npc/item census): a fresh static
    -- scan (name-decode success/failure per record, same method
    -- already used to find the enemySpeciesTable's own real boundary)
    -- found real, clean content well past the previously-documented
    -- 20 records -- real German item names through at least record
    -- 58 ("Bonbon"/"Schlüssel"/"Knochen"/"Bronze"/"Träne"/"Öl"/
    -- "Kristall"/"Rubin"/"Smaragd"/"Saphir"/"Diamant"/"Gold"/"Zähne"),
    -- interspersed with several records that don't cleanly decode at
    -- either known name offset (real, unresolved gaps -- `ItemTable
    -- .decode` now returns `name=""` for those rather than guessing,
    -- see that module's own doc comment). `recordCount` extended to
    -- 59 to include this real content; records beyond that returned
    -- only short, non-word fragments in this pass's own scan and were
    -- NOT included (a genuine further boundary, not chased down this
    -- pass).
    itemTable = {
      status = "PARTIALLY VERIFIED",
      fileOffset = 0x9DE5,
      bank = 2,
      recordLength = 16,
      nameLength = 8, -- 0x00-padded
      recordCount = 59, -- extended 2026-08-15, see doc comment above
      -- Byte 15 (0-based) is a per-category item ID that resets to 0 at
      -- the boundary between consumable items (records 0-7) and spells
      -- (records 8-19) -- see rom-map.md for the exact evidence.
      categoryBoundaryRecord = 8,
    },

    -- Weapon/equipment name+stat table -- see docs/reverse-engineering/
    -- rom-map.md "Weapon/equipment table" (PARTIALLY VERIFIED: names and
    -- the record's 16-byte width are confirmed via a live UI cross-check
    -- against the in-game menu's equipped-weapon readout ("Breit"); the
    -- stat bytes and the table's true start/end boundaries are not).
    --
    -- EXTENDED, 2026-08-15 (monster/npc/item census): the same static
    -- name-decode scan found real, clean weapon/armor names through
    -- record 47 ("Bronze"/"Eisen"/"Silber"/"Gold"/"Flamme"/"Drache"/
    -- "Ägis"/"Opal"/"Samurai"/"Excali"[bur]/"Zeus"/"Lanze", real
    -- material-tier armor sets and named unique weapons) -- previous
    -- `recordCount=20` was cutting off more than half the real table.
    -- Record 48 onward returned only short fragments, not real words,
    -- in this pass's own scan -- a genuine further boundary, not
    -- chased down.
    weaponTable = {
      status = "PARTIALLY VERIFIED",
      -- Scanned window, not a confirmed exact table start/end -- see
      -- rom-map.md's own caveat. 0xA1C0 is where the glyph-run scan that
      -- found "Breit" (at 0xA1F6, the 4th record here, live-cross-checked
      -- against the in-game menu) started; earlier records decode to
      -- "Juwelen"/"Opale".
      fileOffset = 0xA1C0,
      bank = 2,
      recordLength = 16,
      nameOffset = 6, -- name starts 6 bytes into each record, not 0
      nameLength = 8,
      recordCount = 48, -- extended 2026-08-15, see doc comment above
    },

    -- FOUND, 2026-08-17 (external-reference-driven search, same day
    -- and method as `enemyStatTable` above -- see
    -- src/import/WeaponStatTable.lua's own doc comment for the full
    -- evidence trail). A real, SEPARATE table from `weaponTable`
    -- above (own file offset doesn't land on a shared record
    -- boundary with it -- see WeaponStatTable.lua for why these stay
    -- two independent decoders): 16 real records, 16-byte stride,
    -- bank 2. Every record's own 7-byte stat signature matched the US
    -- "Final Fantasy Adventure" disassembly's own documented weapon
    -- list BYTE-FOR-BYTE.
    weaponStatTable = {
      status = "VERIFIED (table location + stride + power/price fields, via exact external-reference byte match); other fields real but unconfirmed against this EU ROM",
      bank = 2,
      fileOffset = 0xA1FD,
      rowCount = 16,
      -- Real English names from the external US disassembly, in real
      -- ROM record order -- see WeaponStatTable.lua's own doc comment
      -- for the gamesurge.com cross-check that independently confirms
      -- `power`/`price` for several of these by name.
      externalReferenceNames = {
        "Broad Sword", "Battle Axe", "Sickle", "Chain Flail",
        "Silver Sword", "Wind Spear", "Were Axe", "Morning Star",
        "Blood Sword", "Dragon Sword", "Flame Flail", "Ice Blade",
        "Zeus Axe", "Rusty Sword", "Thunder Spear", "Excalibur",
      },
    },

    -- NEW (2026-08-15, direct user request "suchen alle monster und
    -- npcs mit allen daten, texten und grafiken aus dem rom"): a real
    -- ROM-wide TEXT census, found via `tools/rom/dump_strings.py`'s
    -- already-proven decoder (the same tool/method that found
    -- Amanda's own real secondRoom dialogue) -- NOT a live OAM/room
    -- capture, since these are plain decodable ROM strings. Every
    -- `fileOffset` here is a real, directly-verifiable location (open
    -- the ROM at that byte and re-run `TextDecoder.decodeString` to
    -- reproduce it).
    --
    -- HONEST SCOPE: this is a census of NAMES AND TEXT this project
    -- can decode, not a census of confirmed live positions/sprites.
    -- Exactly 2 of the named characters below (Willy, Amanda) have a
    -- known real room/sprite (see `graphics.willyScene`/`secondRoom`
    -- above) -- every other name was found ONLY in dialogue text, with
    -- NO live room, OAM sprite, or WRAM position ever captured for it.
    -- Finding those would mean live-exploring the specific room each
    -- character's own dialogue is triggered in (this project doesn't
    -- know which of the ~384 catalogued rooms that is for any of
    -- them) -- real, substantial future work, not attempted this pass.
    -- Similarly, `bossDefeats` below are real monster NAMES with real
    -- "<Name> bezwungen/besiegt" messages, but this pass found NO
    -- structural link (shared index, pointer, adjacent table) between
    -- any of these name strings and `enemySpeciesTable`'s own 11
    -- numbered species rows -- they're real, but NOT mapped to a
    -- specific stat row; presented standalone, not force-matched.
    storyText = {
      -- Real "<Monster> bezwungen/besiegt" victory messages -- each
      -- independently found and byte-verified via a targeted
      -- `dump_strings.py --gaps --min-ratio 0.4` sweep for these exact
      -- phrases. `species` intentionally omitted (see doc comment
      -- above: no real link to `enemySpeciesTable` found).
      bossDefeats = {
        { name = "Zyklop",          message = "Zyklop bezwungen",         fileOffset = 0x0351EC, bank = 13 },
        { name = "Garuda",          message = "Garuda bezwungen",         fileOffset = 0x035227, bank = 13 },
        { name = "Golem",           message = "Golem bezwungen",          fileOffset = 0x035280, bank = 13 },
        { name = "Chimäre",         message = "Chimäre bezwungen",        fileOffset = 0x035415, bank = 13 },
        { name = "Metallkrabbe",    message = "Metallkrabbe\nbezwungen",   fileOffset = 0x03A088, bank = 14 },
        { name = "Gottesanbeterin", message = "Gottesanbeterin\nbezwungen",fileOffset = 0x03A0C2, bank = 14 },
        { name = "Zombie-Drachen",  message = "Zombie-Drachen\nbesiegt",   fileOffset = 0x034D8B, bank = 13 },
        { name = "Roter Drache",    message = "Roten Drachen\nbesiegt",    fileOffset = 0x034DB2, bank = 13 },
      },
      -- Real named characters, found via the established "Name[2c]"
      -- speaker-tag convention (same convention `characterA`/`B`'s own
      -- dialogue already uses) across the whole ROM's decoded text.
      -- `occurrences`: how many times this exact name precedes a
      -- `[2c]` (colon) byte -- a rough real signal of story
      -- importance, not a precise line count. `role`: a short, plainly
      -- evidenced summary from the surrounding real dialogue (cited
      -- inline), not invented backstory. `positionKnown = false` for
      -- everyone except Willy/Amanda -- an honest, explicit flag, not
      -- an omission.
      -- `role`: a short, German summary (matching this website's own
      -- display language) directly evidenced by the surrounding real
      -- dialogue -- quoted ROM text stays verbatim, the rest is a
      -- plain paraphrase, not invented backstory.
      namedCharacters = {
        { name = "Bogard", occurrences = 16, positionKnown = false,
          role = "Mentor-Figur -- gibt dem Held Excalibur, schickt ihn zu Cibba nach Wendel" },
        -- NAME CORRECTED, 2026-08-17: was "Julia" (old TextDecoder
        -- 0x5B="a" reading). The real ROM digraph table (found by
        -- disassembly, see docs/reverse-engineering/text.md's "FOUND:
        -- the real digraph lookup table" section) reads 0x5B as "us",
        -- not "a" -- the real name is "Julius". This ALSO resolves a
        -- pre-existing inconsistency in this very entry's own `role`
        -- text, written independently before this correction: "wird
        -- König" (becomes KING, grammatically masculine) never fit a
        -- character named "Julia" -- it fits "Julius" exactly.
        { name = "Julius", occurrences = 14, positionKnown = false,
          role = "Hauptgegner -- wird König von Glaive, erlangt die Macht des Mana" },
        { name = "Cibba", occurrences = 13, positionKnown = false,
          role = "wiederkehrender Verbündeter -- reist per Luftschiff, pflegt den verletzten Dodo" },
        { name = "Amanda", occurrences = 10, positionKnown = true, room = "secondRoom",
          role = "Lesters große Schwester -- siehe graphics.secondRoom.scene.characterB oben" },
        { name = "Lester", occurrences = 9, positionKnown = false,
          role = "Amandas kleiner Bruder, ein Harfenspieler -- von Davias verflucht, später befreit (\"Lester wird von Davias Fluch erlöst\") -- siehe combat.md für die eigene Korrektur zum direkten Nutzerhinweis, der dieses Projekts frühere falsche Lesart \"Lester = der Held\" zuerst aufdeckte" },
        { name = "Marcie", occurrences = 5, positionKnown = false,
          role = "\"Ich bin Marcie\" -- namentlich vorgestellt, kein weiterer Kontext diesen Durchlauf dekodiert" },
        { name = "Watts", occurrences = 4, positionKnown = false,
          role = "\"Daraus mache ich eine nützliche Ausrüstung\" -- ein Ausrüstungsschmied" },
        { name = "Sarah", occurrences = 3, positionKnown = false,
          role = "überbringt eine Nachricht über jemanden Verletzten/Bewegungsunfähigen, erwähnt einen Jungen und einen echten \"[14]\"=Heldenname-Verweis" },
        { name = "Davias", occurrences = 3, positionKnown = false,
          role = "Antagonist -- verwandelt Menschen in Tiere, verfluchte Lester" },
        { name = "Vandol", occurrences = 8, positionKnown = false,
          role = "uralter Bösewicht, nur als Hintergrundgeschichte erwähnt (\"Vor langer Zeit mißbrauchte Vandol die Mana-Macht\") -- kein Live-Dialogauslöser gefunden, evtl. reine Rückblende, keine platzierte NPC" },
        { name = "Medaa", occurrences = 2, positionKnown = false,
          role = "der Fluch/das Monster, in das Amanda sich verwandelt -- evtl. gar keine platzierbare NPC (ein Story-Ereignis, keine Figur)" },
        { name = "Hasim", occurrences = 1, positionKnown = false,
          role = "einmal namentlich erwähnt, kein weiterer Kontext diesen Durchlauf dekodiert" },
        { name = "Bowow", occurrences = 1, positionKnown = false,
          role = "\"Doktor Bowows Haus\" -- ein Arzt, behandelt den verletzten Dodo" },
        { name = "Lee", occurrences = 1, positionKnown = false,
          role = "\"Herrn Lee vorbehalten\" -- ein Zimmer bei Kett's ist für ihn reserviert" },
        { name = "Willy", occurrences = 1, positionKnown = true, room = "willyRoom",
          role = "siehe graphics.willyScene oben -- die eine bereits vollständig implementierte NPC" },
      },
    },
  },
}

--- Look up the profile for a ROM report from RomIdentity.identify(data).
-- Returns nil, reason if no known profile matches.
function RomProfiles.match(identity)
  if not identity or not identity.sha1 then
    return nil, "no SHA-1 in identity report"
  end
  local profile = RomProfiles.PROFILES[identity.sha1]
  if not profile then
    return nil, "unrecognized ROM (SHA-1 " .. tostring(identity.sha1) ..
      " is not a known Mystic Quest revision)"
  end
  return profile
end

return RomProfiles
