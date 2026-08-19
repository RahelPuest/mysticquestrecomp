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

-- unknownRoomA's real 6 rooms (roomSelectors 8-13, see
-- `roomFloorLayoutPipeline.unknownRoomACandidates` below) -- built from
-- the already-verified pipeline (bank5 record N = roomSelector N's
-- layout stream; `RoomFloorLayout.decodeLayoutStream`/`readMetatile`;
-- `tilesetFileOffset=0x32000+tileId*16`). All 6 share one tileset, so
-- both lookup tables below are defined once and shared.
--
-- `UNKNOWN_ROOM_A_TILE_OFFSETS`: real per-tile ROM byte offsets, same
-- formula as every other room's `tileOffsets` (`0x32000 + tileId*16`).
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
-- `UNKNOWN_ROOM_A_FLOOR_TILE_IDS`: HYPOTHESIS, but data-grounded --
-- each metatile's real collision byte (`RoomFloorLayout.readMetatile`'s
-- 5th byte) was checked across all 6 rooms. Observed values 0x00/0x08
-- (upper nibble zero) cluster on open floor; 0x30/0x31 (upper nibble
-- set, an N/E/S/W block mask) cluster on walls/decoration. Rule: floor
-- iff every observed byte for that tile ID has upper nibble 0x00;
-- mixed tiles treated conservatively as NOT floor. Confirmed live
-- against fourthRoom's own tested floor, but does NOT hold for
-- willyRoom's checkerboard floor (same bit pattern reads as 0x30
-- there) -- the meaning is likely set per metatile table, not ROM-wide,
-- so this stays a hypothesis for unknownRoomA specifically.
--
-- CORRECTED 2026-08-19: the set below was rebuilt from scratch. The
-- previous hand-built set (shipped 2026-08-19 alongside the seventhRoom
-- -> unknownRoomA_8..13 engineering-choice exit chain) was audited
-- against every one of the 82 distinct tile IDs actually used across
-- these 6 rooms' own grids (see /tmp/audit_floor_ids.lua) and found to
-- MISMATCH this file's own stated rule above for 42 of those 82 tiles
-- (about half) -- e.g. tiles 198/199, the visually floor-like
-- "mesh/net" pattern rom-map.md's own human visual-confirmation
-- explicitly called real floor, both have collision byte 0x00 (upper
-- nibble zero, i.e. floor per the rule) yet were excluded. A live
-- scripted walk test (right@10-70 from the unknownRoomA_8 landing
-- spot) showed the player advancing only ~1 tile in 60 held frames,
-- consistent with hitting misclassified terrain almost immediately.
-- This confirms the direct user report that everything past seventhRoom
-- played as broken/nonsensical. The set below applies the same rule
-- mechanically and completely to all 82 used tile IDs instead of a
-- hand-picked subset, closing the gap. It does NOT resolve the deeper
-- open question of what collision bytes outside {0x00, 0x08, 0x30,
-- 0x31} (e.g. 0x02, 0x05, 0x10, 0x17, 0x59, 0x6D, seen on some of
-- these 82 tiles) actually mean -- those are still conservatively
-- treated as NOT floor, same as before.
local UNKNOWN_ROOM_A_FLOOR_TILE_IDS = {
  [1] = true, [3] = true, [4] = true, [5] = true, [7] = true, [18] = true,
  [19] = true, [20] = true, [21] = true, [22] = true, [23] = true,
  [24] = true, [26] = true, [27] = true, [28] = true, [29] = true,
  [33] = true, [36] = true, [37] = true, [38] = true, [39] = true,
  [42] = true, [48] = true, [52] = true, [53] = true, [59] = true,
  [64] = true, [66] = true, [72] = true, [74] = true, [80] = true,
  [81] = true, [84] = true, [85] = true, [92] = true, [95] = true,
  [108] = true, [109] = true, [110] = true, [111] = true, [113] = true,
  [114] = true, [115] = true, [166] = true, [198] = true, [199] = true,
  [204] = true, [205] = true, [254] = true,
}
-- `WORLD_MAP_ROOM_131_*`/`WORLD_MAP_ROOM_132_*`: real bank-5 world-map
-- catalog records 131/132 (see `mapTable` below), added 2026-08-19
-- following a direct user question ("können wir jetzt nicht alle
-- zusammenhängenden räume entschlüsseln?"). UNLIKE `unknownRoomA`'s own
-- floor set above, this pair's `floorTileIds` is derived DIRECTLY from
-- the real, POSITION-AWARE per-cell collision grid
-- (`RoomFloorLayout.buildCollisionGridFromMapTableRecord`, keyed by
-- tile ID only after confirming ZERO same-tile-ID/different-collision
-- conflicts within each room -- the exact audit that caught
-- `unknownRoomA`'s own broken set was re-run here FIRST, before
-- trusting this data, and came back clean). A systematic edge-match
-- scan of the FULL bank-5 16x16 and bank-6 8x8 world-map grids (every
-- N/N+1 and N/N+stride pair, not just the 2026-08-14 spot-check) found
-- exactly 5 bank-5 pairs and 1 bank-6 pair with a 100% tile-ID-exact
-- shared edge -- real, objective ROM evidence of genuine spatial
-- continuity (confirmed both sides use the same tileset, so a matching
-- ID at the boundary guarantees identical art AND identical collision
-- meaning there, no interpretation needed). Of those 6, records 131/132
-- (bank5, horizontal neighbors) is the ONLY pair where the ENTIRE
-- shared edge (all 16 rows) is uniformly WALKABLE on both sides under
-- `RoomFloorLayout.isWalkableCollision` AND the two rooms' own real
-- collision grids show large (59/113-cell), non-fragmented, footprint-
-- reachable regions on both sides of the door (2x2-tile/16x16px
-- footprint, the same granularity `TileWalkability.build` actually
-- uses) -- a completely different, sane rectangular-room shape from
-- unknownRoomA's broken checkerboard, not just a smaller version of the
-- same problem. Live-rendered and visually inspected (not just numbers)
-- via `MYSTICQUEST_DEBUG_STATE=roomexplorer:132`/`:133` -- both sides
-- show a plausible continuous cave-passage shape across the seam.
--
-- HONEST STATUS, still: `genericCatalogMetatileTableFileOffset`'s own
-- collision-byte MEANING (which polarity is floor vs wall) is, by this
-- pipeline's own doc comment, NOT independently ground-truth-verified
-- (no live gameplay reaches any of these 384 catalog rooms, so there is
-- no WRAM cross-check available the way fourthRoom's table has). This
-- pair was chosen specifically because it's the one candidate whose
-- OWN internal structure (zero tile-ID collision conflicts, large
-- connected footprint regions, a sane non-checkerboard room shape, real
-- visual continuity) inspires much more confidence than `unknownRoomA`'s
-- data ever did -- but "much more confidence" is not "proven." The
-- other 4 bank-5 pairs and the 1 bank-6 pair were NOT wired: their
-- shared edges are uniformly classified WALL under the same rule,
-- which -- if the polarity for this table is actually backwards, as it
-- demonstrably is for willyRoom's own table -- would mean it's actually
-- those 4 that are real doors and this one that's a real wall. Left
-- unwired pending independent verification.
local WORLD_MAP_ROOM_131_GRID = {
  {78,79,78,79,66,67,66,67,66,67,70,71,82,83,46,47,46,47,38,38},
  {80,81,80,81,68,69,68,69,68,69,72,73,84,37,46,47,46,47,38,38},
  {46,47,46,47,74,75,66,67,66,67,70,71,46,47,46,47,46,47,38,38},
  {46,47,46,47,37,77,68,69,68,69,72,73,46,47,46,47,46,47,38,38},
  {46,47,46,47,46,47,66,67,66,67,70,71,46,47,46,47,46,47,38,38},
  {46,47,46,47,46,47,68,69,68,69,72,73,46,47,46,47,46,47,38,38},
  {46,47,46,47,46,47,74,75,66,67,82,83,46,47,46,47,46,47,38,38},
  {46,47,46,47,46,47,37,77,68,69,84,37,46,47,46,47,46,47,38,38},
  {160,161,86,37,46,47,46,47,46,47,46,47,46,47,46,47,37,89,38,38},
  {68,69,87,88,46,47,46,47,46,47,46,47,46,47,46,47,90,91,38,38},
  {66,67,66,67,46,47,46,47,46,47,46,47,46,47,37,89,70,71,38,38},
  {68,69,68,69,46,47,46,47,46,47,46,47,46,47,90,91,72,73,38,38},
  {78,79,66,67,86,37,46,47,46,47,46,47,37,89,70,71,92,93,38,38},
  {80,81,68,69,87,88,46,47,46,47,46,47,90,91,72,73,94,38,38,38},
  {38,38,95,96,66,67,160,161,160,161,160,161,70,71,92,93,38,38,38,38},
  {38,38,38,97,68,69,68,69,68,69,68,69,72,73,94,38,38,38,38,38},
}
local WORLD_MAP_ROOM_131_TILE_OFFSETS = {
  [37] = 0x30250, [38] = 0x30260, [46] = 0x302E0, [47] = 0x302F0,
  [66] = 0x30420, [67] = 0x30430, [68] = 0x30440, [69] = 0x30450,
  [70] = 0x30460, [71] = 0x30470, [72] = 0x30480, [73] = 0x30490,
  [74] = 0x304A0, [75] = 0x304B0, [77] = 0x304D0, [78] = 0x304E0,
  [79] = 0x304F0, [80] = 0x30500, [81] = 0x30510, [82] = 0x30520,
  [83] = 0x30530, [84] = 0x30540, [86] = 0x30560, [87] = 0x30570,
  [88] = 0x30580, [89] = 0x30590, [90] = 0x305A0, [91] = 0x305B0,
  [92] = 0x305C0, [93] = 0x305D0, [94] = 0x305E0, [95] = 0x305F0,
  [96] = 0x30600, [97] = 0x30610, [160] = 0x30A00, [161] = 0x30A10,
}
local WORLD_MAP_ROOM_131_FLOOR_TILE_IDS = {
  [38] = true, [66] = true, [67] = true, [68] = true, [69] = true,
  [70] = true, [71] = true, [72] = true, [73] = true, [78] = true,
  [79] = true, [80] = true, [81] = true, [92] = true, [93] = true,
  [94] = true, [95] = true, [96] = true, [97] = true, [160] = true,
  [161] = true,
}
local WORLD_MAP_ROOM_132_GRID = {
  {38,38,46,47,46,47,66,67,66,67,70,71,70,71,66,67,66,67,66,67},
  {38,38,46,47,46,47,68,69,68,69,72,73,72,73,68,69,68,69,68,69},
  {38,38,46,47,46,47,66,67,66,67,70,71,82,83,46,47,46,47,46,47},
  {38,38,46,47,46,47,68,69,68,69,72,73,84,37,46,47,46,47,46,47},
  {38,38,46,47,46,47,74,75,78,79,82,83,46,47,46,47,46,47,46,47},
  {38,38,46,47,46,47,37,77,80,81,84,37,46,47,46,47,46,47,46,47},
  {38,38,46,47,46,47,46,47,46,47,46,47,46,47,46,47,37,89,43,43},
  {38,38,46,47,46,47,46,47,46,47,46,47,46,47,46,47,90,91,72,73},
  {38,38,86,37,46,47,46,47,46,47,46,47,46,47,37,89,70,71,92,93},
  {38,38,87,88,46,47,46,47,46,47,46,47,46,47,90,91,72,73,94,38},
  {38,38,66,67,160,161,160,161,160,161,160,161,160,161,70,71,92,93,38,38},
  {38,38,68,69,68,69,68,69,68,69,68,69,68,69,72,73,94,38,38,38},
  {38,38,95,96,66,67,66,67,66,67,66,67,66,67,92,93,38,38,38,38},
  {38,38,38,97,68,69,68,69,68,69,68,69,68,69,94,38,38,38,38,38},
  {38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38},
  {38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38,38},
}
local WORLD_MAP_ROOM_132_TILE_OFFSETS = {
  [37] = 0x30250, [38] = 0x30260, [43] = 0x302B0, [46] = 0x302E0,
  [47] = 0x302F0, [66] = 0x30420, [67] = 0x30430, [68] = 0x30440,
  [69] = 0x30450, [70] = 0x30460, [71] = 0x30470, [72] = 0x30480,
  [73] = 0x30490, [74] = 0x304A0, [75] = 0x304B0, [77] = 0x304D0,
  [78] = 0x304E0, [79] = 0x304F0, [80] = 0x30500, [81] = 0x30510,
  [82] = 0x30520, [83] = 0x30530, [84] = 0x30540, [86] = 0x30560,
  [87] = 0x30570, [88] = 0x30580, [89] = 0x30590, [90] = 0x305A0,
  [91] = 0x305B0, [92] = 0x305C0, [93] = 0x305D0, [94] = 0x305E0,
  [95] = 0x305F0, [96] = 0x30600, [97] = 0x30610, [160] = 0x30A00,
  [161] = 0x30A10,
}
local WORLD_MAP_ROOM_132_FLOOR_TILE_IDS = {
  [38] = true, [43] = true, [66] = true, [67] = true, [68] = true,
  [69] = true, [70] = true, [71] = true, [72] = true, [73] = true,
  [78] = true, [79] = true, [80] = true, [81] = true, [92] = true,
  [93] = true, [94] = true, [95] = true, [96] = true, [97] = true,
  [160] = true, [161] = true,
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
      -- VERIFIED by live ground truth: read the real DMG hardware
      -- palette registers directly (mGBA core.memory.u8[0xFF47/48/49])
      -- at the starting room. BGP=$E4 decodes to the identity mapping
      -- [0,1,2,3] -- confirms TileImage.DEFAULT_PALETTE's grey-ramp
      -- assumption was already correct for backgrounds/UI. OBP0/OBP1
      -- both $D0, decoding to [0,0,1,3] -- raw pixel index 1 renders as
      -- shade 0 (white, same as background), not mid-grey -- sprites
      -- render mostly as outlines against white, not solid grey blocks.
      -- This was the exact visible difference between this project's
      -- sprite rendering and a ground-truth screenshot before this fix
      -- (see docs/progress.md). A DMG hardware fact for this game state
      -- (both OBP0/OBP1 agree) -- not proven immutable across every
      -- future screen not yet captured.
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
        -- Punctuation glyphs missing from Font.lua's original 64-char
        -- quad set -- TextDecoder already decoded these bytes correctly,
        -- Font just never drew them (a rendering gap, not a decode gap).
        -- Offsets follow `fileOffset + tileId*16`, tileId = 64 + (byte -
        -- 0xF0); confirmed by decoding each 8x8 pixel grid directly.
        -- Tile 0x41 (byte 0xF1, unassigned) shows a plausible quote-pair
        -- glyph but no ROM text byte is confirmed to map there yet, so
        -- it's left out rather than guessed.
        extraGlyphs = {
          ["."] = 0x22F00, -- tile 0x70, TextDecoder.PERIOD_BYTE (0xF0)
          ["-"] = 0x22F20, -- tile 0x72, TextDecoder.HYPHEN_BYTE (0xF2)
          ["!"] = 0x22F30, -- tile 0x73, TextDecoder.EXCLAMATION_BYTE (0xF3)
          ["?"] = 0x22F40, -- tile 0x74, TextDecoder.QUESTION_BYTE (0xF4)
          [":"] = 0x22F50, -- tile 0x75, TextDecoder.COLON_BYTE (0xF5)
          -- Umlaut/eszett glyphs, tiles 0x19-0x1F, immediately preceding
          -- the main font block -- keyed by the same UTF-8 byte-escape
          -- strings TextDecoder.lua emits (kept as \ddd escapes so this
          -- source file's own bytes stay plain ASCII).
          ["\195\132"] = 0x22990, -- Ä, tile 0x19 (25)
          ["\195\150"] = 0x229A0, -- Ö, tile 0x1a (26)
          ["\195\156"] = 0x229B0, -- Ü, tile 0x1b (27)
          ["\195\164"] = 0x229C0, -- ä, tile 0x1c (28)
          ["\195\182"] = 0x229D0, -- ö, tile 0x1d (29)
          ["\195\188"] = 0x229E0, -- ü, tile 0x1e (30)
          ["\195\159"] = 0x229F0, -- ß, tile 0x1f (31)
        },
      },
      -- Real HUD decoration bar, found on the WINDOW layer (`$9C00`
      -- tilemap, LCDC bit 6, WY/WX=128/7 -- earlier captures only ever
      -- read the background map and missed it). Row 1 (below the
      -- LP/MP/G text) is a start-cap + 16 repeating segments + end-cap,
      -- confirmed against a live screenshot. Always the same 16
      -- segments in every capture -- no evidence of a fillable gauge
      -- (tested holding attack for 180 frames, found nothing, see
      -- combat.md's "Power gauge" note); treated as static decoration.
      -- Row 0's own LP/MP/G icon/label tiles are a separate, still-
      -- undecoded tile set -- not implemented here.
      hudBar = {
        status = "VERIFIED",
        tileOffsets = { startCap = 0x22780, segment = 0x227A0, endCap = 0x227E0 },
        segmentCount = 16,
        screenX = 0,
        screenY = 136, -- window row 1: WY(128) + 8
      },
      -- CORRECTED (same day): an earlier capture this same session,
      -- using reach_room.py's exact button sequence, was not the real
      -- starting room -- it was a later screen (an empty bordered box)
      -- mistaken for gameplay. Direct user pushback (that this might be
      -- the main menu, not the first scene where the boss is fought)
      -- led to re-verifying: (1) the "player" sprite in that capture
      -- jumped 72px in a single frame when a direction was held,
      -- instead of the independently-verified 1px/frame walk speed
      -- (Player.lua) -- a decisive tell it wasn't the field-movement
      -- entity; (2) a fresh, from-boot scan screenshotting at regular
      -- intervals found the real room appears earlier, right after the
      -- intro dialogue, and reach_room.py's extra name-entry START
      -- presses were firing after gameplay had already begun -- almost
      -- certainly opening the in-game pause menu (Menu.lua), the empty
      -- box wrongly captured as "the room." The real room (a barred
      -- gate, textured floor, a 4x2-tile enemy above a 2-tile player)
      -- was re-captured and is what startRoom/playerSprite/enemySprite
      -- below now describe. reach_room.py was also fixed so this
      -- doesn't silently regress for the next investigation.
      --
      -- VERIFIED real title screen -- captured the same way as
      -- startRoom below (live VRAM tilemap + per-tile ROM offset
      -- search, cross-checking multiple matches for consistency rather
      -- than trusting the first hit -- some sparse tile patterns
      -- matched dozens of places; every one here was resolved to a real
      -- offset inside bank 11 (the "MYSTIC QUEST" logo art) or bank 8
      -- (the font block's unlabeled tail, a stylized title-specific
      -- menu font distinct from the regular dialogue font). grid is 18
      -- rows x 20 cols (the full screen -- no HUD split like startRoom,
      -- since this isn't a gameplay room). Real BGP at capture: $E4
      -- (identity ramp, same as the room).
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
          -- zero fill), rendered as empty space, not a real offset.
          -- [200]/[224] share one real ROM offset (0x2CAE0) -- both live
          -- VRAM patterns matched that single bank-11 location exactly.
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
        -- Real menu cursor: OAM sprite, not part of the static tilemap
        -- (confirmed via live OAM dump). 8x16 mode, so each of its 2
        -- side-by-side OAM entries is 2 stacked tiles. Reuses tile IDs
        -- 0x12-0x15 (coincidentally the same IDs an early, since-
        -- corrected pass had misidentified as "the player sprite").
        cursorSprite = {
          cols = 2,
          rows = 2,
          tileOffsets = { 0x21F60, 0x21F70, 0x21F80, 0x21F90 },
        },
        -- Captured OAM position, aligned with the "Weiterspielen" row.
        -- `rowY` gives both real Y positions (index 1 = "Neues Spiel",
        -- index 2 = "Weiterspielen", 8px apart, per `grid` above).
        cursor = {
          screenX = 8,
          rowY = { 88, 104 },
        },
      },
      -- Real intro-text scroll after "Neues Spiel": background scrolls
      -- continuously upward (SCY ~1 unit/5.2 frames) with a lighter BGP
      -- ramp during the scroll, reverting after. Scrolled content is the
      -- same background tilemap as the title screen, extended with the
      -- intro story text.
      --
      -- `text`: the actual literal ROM bytes at `0xBED8`, decoded via
      -- `TextDecoder.decodeString` at runtime, not a hardcoded string --
      -- found by decoding the live tilemap scroll then confirming the
      -- exact byte sequence in the ROM file (stored as plain literal
      -- bytes here, unlike the still-unsolved dual-table dialogue text).
      introText = {
        status = "VERIFIED",
        fileOffset = 0xBED8,
        -- `totalUnits`: real cumulative SCY delta from scroll-trigger to
        -- the frame the window-enable bit reverts (494 over 2503 real
        -- frames). Intro.lua itself clamps the EFFECTIVE scroll shorter
        -- than this (real hardware keeps scrolling ~14s of blank padding
        -- after the last sentence, which reads as a stuck screen) -- a
        -- documented Intro.lua UX choice, not a correction to this data.
        scy = { unitsPerFrame = 494 / 2503, totalUnits = 494 },
      },
      -- Real hero/heroine name-entry screens, right after the intro
      -- scroll: a "Held"/"Frau" label box above a bordered on-screen
      -- keyboard. The OAM cursor reuses the title screen's own menu-
      -- cursor sprite (tiles 0x12-0x15). START confirms only once at
      -- least one character is entered. The long-observed "AAAA" default
      -- name is explained: it's what selecting the grid's first cell
      -- ('A', the cursor's start position) four times produces, not an
      -- auto-fill (confirmed via WRAM `$D79D-$D7A0` = `0xBA` x4).
      --
      -- `tileset`: all tiles this screen needs (letters, digits, umlauts,
      -- border) live in one contiguous ROM block, the SAME real font
      -- block `font` above already uses -- confirmed by the border
      -- tiles (0x77-0x7E) falling on the same `0x22900 + (tileId-0x10)*16`
      -- relationship as the font's own offsets.
      --
      -- `grid`: the real, live-captured keyboard layout (VRAM tile IDs,
      -- row-major, 9 cols, last 2 rows 8 wide -- real, not truncated:
      -- 26 letters/10 digits don't fill 9 evenly). Rows 0-2 uppercase
      -- A-Z, 3-5 lowercase a-z, 6 punctuation, 7-8 digits + umlauts --
      -- this exact grouping is what pinned down the 3 uppercase umlaut
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
      -- direct user request to find the actual ROM code rather than do
      -- this evidence-based (from side effects). Used tools/rom/
      -- watcher.py (SM83 watchpoints) + disasm.py to find and read the
      -- actual routines, not just infer them from OAM/tilemap effects.
      --
      -- Real walk-in: right after the heroine name is confirmed, the
      -- player is hidden for ~68 frames, then appears already at the
      -- entrance and walks from screen X=152 to X=72 (Y fixed at 80,
      -- the same spawn position playerSprite uses) over 80 frames --
      -- exactly 1px/frame, the same speed independently verified for
      -- ordinary movement (Player.PIXELS_PER_STEP), not a separate
      -- cutscene speed. Confirmed at the code level: ROM $0659/$065B
      -- initialize the entrance position, then every per-frame
      -- decrement is executed by ROM $09A6, inside the same generic
      -- entity-update routine at $0961-$09BE already found driving
      -- ordinary player/enemy movement -- the ROM doesn't special-case
      -- this cutscene walk, it feeds the normal movement system a
      -- synthetic leftward input (see BattleIntro.lua: drives the real
      -- Player:update with a synthetic held-left input, not custom
      -- position math).
      --
      -- Real "Kaempfe!" textbox: a bordered box (same border tile IDs
      -- as nameEntry.border above) appears on the background layer (a
      -- deliberate difference from name-entry's box) at the top of the
      -- screen, ~208 frames after the heroine name is confirmed, then
      -- types its text one letter every exactly 5 frames. Real text
      -- (not "Kampf" as informally guessed from an early low-resolution
      -- screenshot -- see text.md): "Kaempfe!" (German imperative
      -- "Fight!"), found the same two-independent-ways method as the
      -- intro text -- decoded live, then found verbatim as literal ROM
      -- bytes at file offset 0x346D4. Box closes ~324 frames after
      -- heroine-confirm.
      --
      -- Real enemy appearance: OAM stays fully hidden until ~468 frames
      -- after heroine-confirm, then appears already in motion, settling
      -- into the existing Enemy.MOVEMENT_CYCLE by ~frame 513 -- no
      -- distinct entrance animation, it just becomes visible mid-cycle.
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
        -- Real barred-gate open/close animation, position/tile IDs/
        -- timing confirmed via a per-frame VRAM sweep. openTileId's
        -- pattern is 16 bytes of 0xFF (a solid dark tile, not blank).
        -- No dedicated ROM offset recorded: the tile-patch blob driving
        -- this (file 0x200B0, bank 8) just repoints tilemap cells to an
        -- already-VRAM-resident slot, no new pixel data loaded.
        gate = {
          status = "VERIFIED",
          bgRow = 0, bgCol = 8, rows = 4, cols = 4, -- BG tilemap rows0-3, cols8-11
          openFrame = 396, closeFrame = 461, -- same battleIntro `self.frame` counter as phaseBounds()
          openTileId = 149,
          openTilePattern = string.rep("\255", 16), -- real live-captured 2bpp bytes, solid color-index-3
        },
        -- Second, independent tile-patch mechanic (direct user report:
        -- an open tile in the right wall that closes after the player
        -- walks through): the courtyard's right wall, at the walk-in
        -- spot, patches in a 2x2 floor opening for the walk-in then
        -- seals back to normal wall tiles once the player arrives.
        -- startRoom.grid models that spot as permanently solid, so the
        -- player used to visually walk through un-opened wall. Frame
        -- numbers calibrated relative to hiddenFrames (same live run):
        -- opens 2 frames before the player sprite appears, seals 117
        -- frames later.
        --
        -- CODE-TRACED (2026-08-19, direct follow-up: "versuche das mal
        -- anhand des codes auch für die rechte wand" -- the same rigor
        -- `battleIntro.gate` already had, this entry originally didn't).
        -- Live memory watchpoints on all 4 real destination BG tilemap
        -- cells ($9952/$9953/$9972/$9973, map 0 base $9800 + row*32 +
        -- col) plus a full CallTracer call-stack capture at each hit
        -- (not just the write's own PC) found TWO STRUCTURALLY
        -- DIFFERENT real call chains for open vs. close -- a genuine,
        -- new finding, not assumed from the gate's own shape:
        --   OPEN (bank 1 live, all 4 cells, values 0x8D/0x8E matching
        --     openGrid exactly): `$21AC` -> `$1DDA` (the already-known
        --     general VRAM-write JOB QUEUE drain routine -- the same
        --     one `victorySequence`'s own black-screen wipe uses,
        --     WRAM `$C8E8`/`$CEE8`) -- a real hardware VBlank interrupt
        --     ($0040 vector) fires WHILE `$1DDA` is executing, and the
        --     ISR path reaches `$1E3F` -> `$1D74` -> `$1D87`/`$1D88`
        --     (the same general safe-VRAM-byte writer `battleIntro.
        --     gate` already uses). So the OPEN write is QUEUED and
        --     drained asynchronously during a real VBlank, unlike the
        --     gate's own fully synchronous chain.
        --   CLOSE (bank 8 live, all 4 cells, values 0x80/0x81/0x82/
        --     0x82 matching closedGrid exactly): `$0F24` -> `$2400` ->
        --     `$056C` (the already-known "real tile-redraw/cursor-blit
        --     workhorse," its SECOND real entry point -- the first,
        --     `$051D`, was already known to be called from 3 bank-1 and
        --     3 bank-2 sites; `$0F24`/`$2400` are a real caller not
        --     previously catalogued) -> `$0495` -> `$049A` -> `$1D74`
        --     -> `$1D87`/`$1D88`. Structurally the SAME shape as the
        --     gate's own already-documented chain (also through `$0495`
        --     /`$049A`/`$1D74`), just reached via `$056C` instead of
        --     directly, and via a different, newly-found top-level
        --     caller (`$0F24`).
        -- Both writes land in the exact same general low-level
        -- primitive the gate already uses -- confirms (rather than
        -- merely assumes, as the original 2026-08-12 entry honestly
        -- flagged it had to) that this is the same real underlying
        -- mechanism, while also showing open/close are NOT symmetric
        -- at the code level -- a real, previously-unknown structural
        -- detail.
        --
        -- SAME DAY, direct follow-up ("ja mach das", tracing WHICH
        -- script drives the close): decisive, historic-for-this-thread
        -- finding. `$0F1E` is exactly this project's own already-
        -- decoded `ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS`
        -- (real script opcode `0xB0`) -- live-captured real operands
        -- for THIS specific invocation: `byteValue=0x6C, wordValue=
        -- 0x0509`, script bytes at ROM file `0x346C9` (bank 13). This
        -- is a real script dispatch, not hardcoded room-init code (see
        -- `$0F24`'s own `CALL $3727` tail, returning to the main
        -- dispatch loop) -- and it answers this project's own long-
        -- standing "$2400 helper -- HYPOTHESIS" open question (see
        -- `StandardScriptHandlers.byteWordCommand`'s own doc comment):
        -- for this real invocation, `$2400` performs the entrance-seal
        -- close write.
        --
        -- Traced further, HOW bank 13 gets reached: zero of the 1357
        -- `scriptPointerTable` entries resolve to bank 13 at all (a
        -- real, direct check, not assumed) -- so this script is NOT
        -- one of the 1357 top-level scripts. Live bank-stack tracing
        -- (watching every `$29FB`/`$2A0A` push/pop transition) found
        -- the real PUSH of bank 13 happens at `$3260` -> `$3C6B` (a
        -- bank-calling trampoline, same shape as this project's own
        -- already-documented "save regs, `CALL $29FB`, jump through the
        -- target bank's own local table" convention).
        --
        -- CORRECTED same day, direct follow-up ("wie weiter" ->
        -- checking this precisely before building further on it): `$3260`
        -- is straight-line fall-through from `$3213`, a REAL,
        -- independently-called subroutine (3 real static callers, all
        -- bank-0-fixed: `$24F0`/`$2516`/`$253D`) -- NOT literally
        -- `$31AD`'s own body (`$31AD` has its own `RET` at `$3212`,
        -- confirmed via fresh disassembly and a direct call-site scan:
        -- `$31AD` itself has 15 real callers, `$3213` has its own,
        -- separate 3). `$3213` instead calls DIRECTLY into `$31C7` --
        -- **this project's own already-documented "decisive" shared
        -- internal tail of the `$31AD` routine** (task #149: writes
        -- `$D864=5`, resolves via `$3282`'s table lookup or the 3
        -- special-case fixed buffers, stores the persistent cursor,
        -- `CALL $3727`) -- the SAME real machinery `$31AD`'s own normal
        -- top-level entry eventually reaches internally, just entered
        -- through a different, real, sibling front door. So: genuinely
        -- the same underlying redirect mechanism, confirmed by shared
        -- internal code, not by assuming two similar-looking routines
        -- are identical -- but reached via `$3213`, not `$31AD`'s own
        -- entry point, a real, previously-imprecise detail worth
        -- stating correctly rather than leaving the earlier looser
        -- claim standing.
        --
        -- **Historic significance for the wider room-connectivity
        -- investigation** (see events.md's own 2026-08-19 "bank-14
        -- transition" entries): this is a SECOND, independent, live-
        -- observed real trigger reaching the `$31AD`-family's shared
        -- "redirect the persistent script cursor" machinery (room-load
        -- via `$3213`, not actor-despawn-edge-detection via `$31AD`'s
        -- own entry) -- direct proof this machinery is genuinely
        -- GENERAL, reached by at least 2 real, structurally different
        -- front doors, not a boss-defeat-specific one-off, AND that it
        -- can reach bank 13 in real play -- one bank further than the
        -- exhaustive whole-corpus STATIC simulation ever found reachable
        -- (bank 12 max, with generous-but-fixed stub gate answers) --
        -- because that simulation could only cover the 1357 known
        -- scripts' own reachable content, never this machinery's own
        -- real trigger conditions, which live outside that corpus
        -- entirely. Does NOT by itself reach bank 14 (this session's
        -- real remaining open connectivity target) -- what specifically
        -- calls `$3213` for THIS trigger (room-load, as opposed to the
        -- boss-defeat trigger) was not traced further this pass -- a
        -- real, well-scoped, promising follow-up: if this machinery has
        -- a THIRD real front door reaching bank 14, that would be the
        -- first genuine, live-provable path into the 82 real
        -- `CutTransitionTable` transitions this project has been
        -- chasing all session. `$31AD`'s own 15 real static callers
        -- (found this same pass, not yet traced individually) are the
        -- next concrete candidates to check.
        entranceSeal = {
          status = "VERIFIED",
          bgRow = 10, bgCol = 18, rows = 2, cols = 2, -- BG tilemap row10-11, col18-19
          openFrame = 66, closeFrame = 185, -- hiddenFrames-2, hiddenFrames+117
          openGrid = { { 141, 142 }, { 142, 141 } },
          closedGrid = { { 128, 129 }, { 130, 130 } },
        },
      },
      -- Real post-victory scene, traced directly from ROM code (see
      -- combat.md's "Real post-victory scene transition" entry for the
      -- full instruction-level trace).
      --
      -- The real ROM implements this via a general VRAM-write job queue
      -- (WRAM `$C8E8`/`$CEE8`, drained once/frame) and a cursor-relative
      -- tile-blit helper (`$045D`) -- NOT a hardware palette fade
      -- (BGP/OBP/LCDC/WY/WX watched live, never changed). The "black
      -- screen" is a full tilemap overwrite with the blank tile below,
      -- through that same general queue -- the same mechanism the ROM
      -- uses to load any room's tiles, not a bespoke fade. This
      -- project's renderer skips the queue's own frame timing-safety (a
      -- real GB PPU-race concern that doesn't apply to a Love2D redraw)
      -- to reproduce the same on-screen result -- see VictorySequence.lua.
      victorySequence = {
        status = "PARTIALLY VERIFIED",
        -- Real blank/background tile the ROM fills the tilemap with for
        -- the black screen (confirmed via a live watchpoint: DE=$8080
        -- written repeatedly, i.e. tile $80 twice per call).
        wipeBlankTileId = 0x80,
        textbox = {
          border = { topLeft = 0x77, top = 0x78, topRight = 0x79,
            left = 0x7a, right = 0x7b,
            bottomLeft = 0x7c, bottom = 0x7d, bottomRight = 0x7e },
          framesPerLetter = 5, -- same real cadence as battleIntro's box
        },
        -- Text content below is transcribed from a live VRAM/screenshot
        -- capture, not decoded from a located ROM offset -- general
        -- dialogue is still real-but-compressed (see text.md). `%s` =
        -- the real player-entered name. Line breaks are this project's
        -- own safe word-boundary re-wrap, not a pixel-exact reproduction
        -- of the real ROM's own mid-word hyphenated wrapping.
        -- CORRECTED (direct user report the sequence was incomplete): a
        -- careful live re-trace found the REAL first box after the
        -- black wipe is `storyPages[1]` below -- `victoryLine` never
        -- appears there. It's real ROM text (rom-map.md's own finding
        -- independently places this sentence as firing LATER, from a
        -- separate status/flex trigger once free-roaming) -- kept here
        -- as a confirmed string for whenever that trigger is found, but
        -- no longer inserted into the fixed intro page list.
        victoryLine = "%s ist ein\ntapferer Kaempfer.",
        -- Real ROM source found: `dump_strings.py --gaps` found the real
        -- byte header `04 10 14` (bank 14, file `0x03a1bb`) immediately
        -- before this sentence -- `0x14` is the hero-name substitution
        -- token -- and the text tail decodes cleanly from `0x03a1be` to
        -- the real terminator at `0x03a1d1`, byte-exact match (with the
        -- real umlaut "Kämpfer"). `%HERO_NAME%` is a marker the caller
        -- substitutes, not a real ROM byte. Formula-proven and
        -- regression-tested, not yet wired into any live UI trigger.
        victoryLineSegments = {
          { literal = "%HERO_NAME%" },
          { fromOffset = 0x03a1be, toOffsetExclusive = 0x03a1d1 }, -- real terminator (0x00) sits at 0x03a1d1
        },
        -- Re-traced live. Found two issues with the previous single-page
        -- version below: (1) it silently stopped the sentence early, at
        -- "...jeden Tag zu kaempfen." -- the real box continues onto a
        -- second box with "zur Unterhaltung des Dark Lord, zu
        -- kaempfen." (the full sentence names who the fighting is for,
        -- entirely missing before); (2) the previously-honest "at least
        -- one more lore page, cut off by this project's own capture
        -- window" gap is now closed -- that page reads in full "Viele
        -- liessen dabei unnoetig ihr Leben." (a plain single-page
        -- sentence, not a longer cut-off block as the old ellipsis
        -- implied).
        -- SUPERSEDED (direct continuation of the Willy-exchange live-
        -- decoding work): the hand-transcribed storyPages table that
        -- used to live here is gone -- VictorySequence.lua now live-
        -- decodes all 3 pages directly from their ROM offsets
        -- (STORY_PAGE_OFFSETS, file 0x3A1E5/0x3A208/0x3A234, same
        -- bank-14 dialogue block the Willy exchange lives in) via
        -- TextDecoder.decodeString, matching the Willy-exchange lines'
        -- own convention of keeping a ROM offset directly in app code
        -- rather than a second, parallel data table here that could
        -- drift out of sync. See VictorySequence.lua's own doc comment
        -- for the exact offsets, the real line breaks/hyphenation this
        -- uncovered, and the one content difference found (page 3 has
        -- no trailing period). This comment intentionally stays -- the
        -- research history above (victoryLine's own doc comment) is
        -- still accurate and still explains how these 3 pages were
        -- originally found.
        --
        -- Real room transition (traced and implemented -- see
        -- graphics.willyRoom below and rom-map.md's "Real room-tile
        -- decompression pipeline, found"): a genuinely different room
        -- loads before the Willy dialogue plays. Code path, bank 0:
        -- $04E8 reads the source pointer at WRAM $D392/$D393 (resolves
        -- live to ROM bank 8, file offset 0x206B0), and for each raw
        -- source byte looks it up through a 256-entry tile-ID remap
        -- table staged at WRAM $D070-$D16F before drawing 2x2 tile
        -- blocks via the same general cursor-relative blit ($045D/
        -- $048C) and VRAM job-queue ($1E9F) already found for the
        -- black-screen wipe -- the same general drawing machinery, just
        -- fed a different (non-blank) tile source. A newly-found room-
        -- decompression pipeline, distinct from both the starting
        -- courtyard's hardcoded capture (startRoom below) and the
        -- still-not-understood bank-5 RLE table (see rom-map.md's
        -- "Maps" section).
      },
      -- The real second room, captured the same way `startRoom` was: a
      -- live VRAM tilemap read (20x16, no scroll), not reconstructed
      -- from the raw compressed source bytes.
      --
      -- CORRECTED: this entry originally assumed tile IDs 0x80-0xAB
      -- indexed the general environment tileset at a flat
      -- `tilesetFileOffset + id*16` stride -- wrong (rendered as a
      -- checkerboard where the real screenshot shows brick walls).
      -- Re-verified by reading the live VRAM tile pattern directly for
      -- each ID -- matched the real screenshot exactly. Each tile's
      -- real ROM source offset was then found by exact 16-byte search:
      -- these live scattered across `0x321B0-0x32630`, NOT at a simple
      -- `id*16` stride -- a separate, room-specific tile set assembled
      -- into contiguous VRAM slots 0x80-0xAB, indexed explicitly below.
      willyRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $46B0, shared by roomSelectors 2-6
        -- (the willyRoom/secondRoom/thirdRoom family). Live-traced WRAM
        -- `$C3F5` (the room-selector byte) through the real post-boss
        -- sequence: `0x0f` during the black-wipe, then a stable `0x04`
        -- from the Willy dialogue through free-roam -- willyRoom's own
        -- real roomSelectorTable index is 4.
        --
        -- Honest negative result, same investigation: unlike unknownRoomA
        -- (selectors 8-13), the `roomSelector N = mapTable record N`
        -- identity does NOT hold here -- decoding bank-5 record 4 and
        -- comparing cell-by-cell against this room's own live-captured
        -- grid found only 96/320 matches (no other record 0-7 does
        -- better). This room's own content stays the live-captured grid
        -- below; the "320 decodable rooms" claim only means 320 records
        -- decode as real ROM art -- only unknownRoomA's 6 are also
        -- confirmed to correspond to a specific in-game room identity.
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        romRoomSelectorConfirmed = 4, -- live-traced via WRAM $C3F5, see doc comment above
        -- `$C3F5` stays exactly 4 through the entire willyRoom ->
        -- secondRoom -> thirdRoom checkpoint chain -- confirms these 3
        -- rooms are one continuous space, scrolled via hardware
        -- SCX/SCY, not 3 separate roomSelector dispatches.
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
        -- below: only the checkerboard floor tiles are open -- live-
        -- verified by holding UP after the Willy dialogue: the player
        -- moves 72px north then stops dead at the wall/arch boundary.
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
        -- Real north door (arch structure at BG row0-1, cols8-11).
        -- Opens deterministically on the first centered approach (a
        -- prior "never opens" finding was a test-harness artifact --
        -- the player had drifted to X 88, outside the door's working
        -- range). `triggerXMin`/`triggerXMax` are an empirically-
        -- bracketed range (X 75/76/79/83 opened it; X 88 didn't), not a
        -- proven exact pixel boundary.
        door = {
          status = "VERIFIED",
          bgRow = 0, bgCol = 8, rows = 2, cols = 4, -- BG tilemap row0-1, cols8-11
          closedGrid = { {135,136,139,140}, {137,138,141,142} },
          openGrid = { {172,152,151,174}, {173,154,153,175} },
        },
        -- General room-exit schema (see RoomChain.lua's own doc comment
        -- for the engine this drives). Each entry: `zone` (a real,
        -- empirically-bracketed screen-space rectangle, any bound may be
        -- omitted = unbounded that side), `transition`
        -- (`{type="scroll",axis=,totalPixels=,pixelsPerFrame=}` for a
        -- hardware-scroll pan, or `{type="cut"}` for an instant room
        -- change via `$D392`/`$D393`), `targetRoom`, `landingX`/
        -- `landingY`, optional `dialoguePages`/`holdInput`. Covers every
        -- real transition mechanism found so far (scroll + cut).
        --
        -- `totalPixels` is code-verified, not just empirical: the real
        -- scroll-completion routine (`$46C4`, bank 1) computes its
        -- threshold as `roomHeightTiles*8` for a vertical scroll
        -- (confirmed `0x10`=16 for willyRoom, 16*8=128 exactly) but a
        -- plain hardcoded `160` for horizontal -- the same fixed
        -- constant every room's horizontal scroll uses.
        -- `pixelsPerFrame=4` matches the real per-frame delta this same
        -- routine applies (confirmed via live SCY/SCX watches).
        exits = {
          {
            status = "VERIFIED",
            -- Real player left-edge screen X range (bracketed, not an
            -- exact proven pixel boundary -- X 75/76/79/83 all opened
            -- it live, X 88 confirmed did not) and the real screen Y
            -- reached when blocked against the closed door.
            zone = { xMin = 72, xMax = 86, yMax = 24 },
            -- totalPixels = roomHeightTiles(16) * 8, code-verified.
            --
            -- `reverse=true`: `VictorySequence:draw()`'s scroll-pan code
            -- defaults to "current room slides toward the negative axis
            -- side" for every exit -- correct for secondRoom's own east
            -- exit, but wrong for this north door (walking north should
            -- reveal new area above, sliding down -- the opposite sign).
            -- This flag flips the slide direction for this specific exit.
            transition = { type = "scroll", axis = "y", totalPixels = 128, pixelsPerFrame = 4, reverse = true },
            targetRoom = "secondRoom",
            -- Real measured landing position (72,96), re-derived via a
            -- calibrated screenshot pixel-grid overlay after an earlier
            -- pass wrongly used the raw, un-adjusted WRAM position (which
            -- is also a world-space value that accumulates through the
            -- scroll, not a per-room local one). Cross-checked against
            -- `TileWalkability`: (72,96) is real open floor, the old
            -- (80,136) was not -- matches the live screenshot exactly.
            landingX = 72, landingY = 96,
            -- REMOVED: a 3-line "Amanda!..." dialogue used to fire on
            -- this transition -- disproved live (900 frames idle after
            -- landing produced no dialogue). The real trigger is per-NPC
            -- proximity instead (see `secondRoom.scene.characterA
            -- .dialogue` below), a different mechanism -- field removed
            -- rather than reattached as a guess.
          },
        },
      },
      -- Real second room beyond the Willy-room's north door -- NOT
      -- reached via the `$D392`/`$D393` room-load pipeline: this room's
      -- content was already sitting in VRAM (rows 16-31, off-screen)
      -- before the door opened; the real transition is a pure hardware
      -- background-scroll (`$D392`/`$D393` never change). Reuses most
      -- of `willyRoom`'s own tileset plus 12 new tile IDs (176-187).
      secondRoom = {
        status = "VERIFIED",
        -- Same real tile-source pointer/family as `willyRoom` above
        -- ($46B0, roomSelectors 2-6) -- the same continuous scrollable
        -- source, not a separately-selected room.
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
          -- New tile IDs, found the same way, not part of
          -- willyRoom.tileOffsets:
          [176]=0x32ec0,[177]=0x32ed0,[178]=0x32ee0,[179]=0x32ef0,
          [180]=0x32280,[181]=0x32290,[182]=0x32380,[183]=0x32390,
          [184]=0x322c0,[185]=0x323c0,[186]=0x322d0,[187]=0x323d0,
        },
        -- HYPOTHESIS: only the checkerboard floor tiles are open,
        -- matching willyRoom's own convention -- not individually
        -- re-verified (4-directional movement confirmed working, exact
        -- wall boundary tiles not tested).
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
        -- Two new characters standing in this room -- neither matches
        -- the known Willy sprite. Identity unknown (the room's dialogue
        -- names a character "Amanda" but doesn't visually tag which
        -- sprite is her).
        --
        -- CORRECTED: screenX/screenY are not a stable, ROM-authored
        -- fixed position -- live-traced to a general spawn primitive
        -- ($42BD, bank 3) fed by a procedural placement loop. The
        -- values below are one live-captured sample, used as each
        -- character's starting point for the wander movement below.
        --
        -- dialogue: the real trigger is per-NPC proximity, not room
        -- entry -- confirmed by walking up to each OAM-tracked NPC and
        -- watching a dialogue box appear on overlap, no button needed.
        -- characterA (approached first): "Der Monsterein-gang fuehrt
        -- nach drausen." characterB's own line, found via a
        -- dump_strings.py scan, sits immediately after characterA's own
        -- box in the same ROM data stream: "Hallo!Willkommen\nin
        -- Toppel!" (an NPC greeting naming the ROM's own town,
        -- "Toppel"). Stored as a plain string (not live-decoded) since
        -- NpcProximity.lua's existing dispatch expects one.
        --
        -- FOUND AND FIXED: three problems, from one extended live mgba
        -- re-trace (900 frames, OAM-tracked every frame): (1) the old
        -- tileOffsets were simply wrong -- readable ROM bytes, but from
        -- the font region, not a creature sprite. (2) the shape was
        -- wrong too: modeled as 2x2-tile (16x16px) like Willy/the
        -- player, but real OAM only uses two sprite slots per character
        -- (one 8x16 column, top+bottom). (3) both characters really do
        -- animate and move -- each OAM tile ID cycles through a
        -- 4-direction, 2-phase walk cycle while wandering, no obvious
        -- short fixed loop across 900 frames (a continuous random walk).
        -- All 16 tile IDs (8 per character, a clean +0x20 shift between
        -- the two) were found via exact 16-byte ROM search (each
        -- matched exactly one location) and are wired below as
        -- animation. HONESTY NOTE: the movement algorithm itself was
        -- not decoded -- wander below is a reasonable random-walk
        -- approximation, not a reproduction of the real PRNG sequence.
        -- The animation tiles and their direction/phase/flip pairing,
        -- by contrast, are the real, directly-observed data.
        scene = {
          characterA = {
            screenX = 128, screenY = 58,
            dialogue = { "Der Monsterein-\ngang f\195\188hrt nach\ndrau\195\159en." },
            -- Real ROM source found: `dialogue` above was hand-
            -- transcribed from a live VRAM capture -- `dump_strings.py`
            -- found it decodes cleanly at bank 13, file
            -- `0x0378aa`-`0x0378c6`, byte-exact match. VictorySequence.lua
            -- now resolves this live via `DialogueTextResolver` when
            -- `romData` is available, falling back to the hand-
            -- transcribed string when it isn't (e.g. `NpcCatalog.build`).
            dialogueSegments = {
              { { fromOffset = 0x0378aa, toOffsetExclusive = 0x0378c6 } },
            },
            -- CORRECTED FOR REAL (direct user report from actual play):
            -- this animation table was built on a wrong model (a single
            -- 8x16-OBJ-mode column, 2 OAM entries stacked). A fresh
            -- live OAM re-trace found the real shape: 2 OAM entries at
            -- the same Y, 8px apart -- a LEFT+RIGHT pair, each already
            -- 8x16 in hardware, so the true on-screen character is a
            -- 16x16 block using 4 tiles, not 2.
            --
            -- SECOND CORRECTION (direct user report left/right halves
            -- were swapped): reordering the 4 tiles by their live OAM
            -- screen X position was wrong (produces 2 disconnected
            -- blobs when rendered); the plain, unreordered sequential
            -- order ({T, T+0x10, T+0x20, T+0x30}) renders a single,
            -- coherent 16x16 humanoid, confirmed for both characterA's
            -- "left" and characterB's "up" capture -- the ROM simply
            -- stores each pose's 4 tiles consecutively in row-major file
            -- order already; no OAM-position-based reordering was ever
            -- needed, that extra step was the bug. flip/flipY booleans
            -- are unchanged (only the tile order was wrong) -- but
            -- honestly flagged: the exact left-vs-right facing/flip
            -- semantics were not independently re-verified this pass (a
            -- live capture matched by value to this "left" entry showed
            -- real hardware X-flip set, which doesn't obviously square
            -- with flip=false here) -- a still-open follow-up (see
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
            -- RESOLVED (direct user report the previous dialogue was
            -- wrong -- it's Amanda, with a different topic about her
            -- brother): the old text ("Hallo!Willkommen\nin Toppel!")
            -- was found via simple ROM-adjacency and was wrong -- 3
            -- failed live re-verification attempts plus the user
            -- directly naming the character confirmed it. Found the
            -- real line via a dump_strings.py --gaps scan for "Bruder"/
            -- "Amanda": file offset 0x03783e (bank 13), a first-person
            -- 3-page Amanda monologue mentioning Willy and her little
            -- brother -- unmistakably right. Decoded via TextDecoder's
            -- byte-exact formula except two bytes (0x82/0x5B), resolved
            -- locally for "meinem"/"raus" at the time. RESOLVED later:
            -- the real ROM digraph table (found by disassembly) proved
            -- 0x5B="us" universally -- these words were right all along
            -- ("Julia" was itself a mis-read of "Julius", see
            -- namedCharacters above); the shared global table now reads
            -- "us" directly, no local override needed.
            realName = "Amanda", -- unmistakable, appears 15+ times in this ROM's own real story text
            dialogue = {
              "Amanda:Das mit\nWilly tut mir\nleid.", -- no space after the speaker colon (0x2c never inserts one), same convention as Julius's own line
              "Wir müssen hier\nraus!",
              "Ich möchte nach\nHause zu meinem\nkleinen Bruder.",
            },
            -- Real ROM source: `dump_strings.py --gaps` found the exact
            -- ranges for all 3 pages, bank 13 -- page 1 decodes cleanly
            -- end to end; pages 2/3 each need the one documented
            -- per-occurrence digraph override above, spliced between
            -- real, cleanly-decoding ranges. Byte-exact regression:
            -- `dialogue_text_resolver_test.lua`. VictorySequence.lua
            -- resolves this live via `DialogueTextResolver` when
            -- available, same fallback as `characterA` above.
            dialogueSegments = {
              { { fromOffset = 0x037840, toOffsetExclusive = 0x037859 } },
              {
                { fromOffset = 0x03785b, toOffsetExclusive = 0x037867 },
                { literal = "us" }, -- real byte 0x5B at file 0x037867
                { fromOffset = 0x037868, toOffsetExclusive = 0x037869 },
              },
              {
                { fromOffset = 0x03786b, toOffsetExclusive = 0x03787b },
                { literal = "me" }, -- real byte 0x82 at file 0x03787b
                { fromOffset = 0x03787c, toOffsetExclusive = 0x037889 },
              },
            },
            -- Real tile set is characterA's own +0x20 (confirmed
            -- independently from this NPC's own live OAM capture, not
            -- assumed from the shift alone). Same real 4-tile shape fix
            -- as characterA: plain sequential file order
            -- `{T,T+0x10,T+0x20,T+0x30}` (not OAM-position-reordered).
            -- This character's own "up" pose (T=0x25540) independently
            -- cross-validated the exact tile set and confirmed the
            -- correct order by direct pixel rendering (a single,
            -- coherent 16x16 humanoid).
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
        -- VERIFIED: the real east exit -- a different transition axis
        -- from willyRoom's own door (horizontal, not vertical) -- see
        -- rom-map.md "Yes, it keeps going". Real working trigger window
        -- bracketed narrower than the north door's: screen Y ~64-65
        -- confirmed working; 16/32/48/80/96/112 all confirmed not to (a
        -- live position sweep, not a guess) -- zone below uses a small
        -- margin around the one confirmed-working value.
        exits = {
          {
            status = "VERIFIED",
            -- Real working zone (xMin=110, y=60-68): an earlier
            -- unbounded zone (no xMin/xMax) let a straight walk up from
            -- the door false-trigger this east exit; a first fix
            -- (xMin=136) then landed on a wall tile the player can
            -- never stand on. xMin=110 is open floor the whole way to
            -- this room's reachable max (128) at this y band.
            zone = { xMin = 110, yMin = 60, yMax = 68 },
            -- totalPixels=160: code-verified as the ROM's own hardcoded
            -- horizontal-scroll constant (one screen width), see the
            -- schema comment on willyRoom's own exits above.
            transition = { type = "scroll", axis = "x", totalPixels = 160, pixelsPerFrame = 4 },
            targetRoom = "thirdRoom",
            -- Real landing (0,64), re-measured after an earlier pass
            -- (80,64) turned out to be a methodology bug: the checkpoint
            -- used to capture it deliberately walks 200 frames past the
            -- landing spot for unrelated investigation convenience, and
            -- that extra walking got recorded as if it were the landing
            -- position. Re-measured by releasing RIGHT the instant SCX
            -- settles at 160 and confirming no drift over 40 more
            -- frames. X=0 is thirdRoom's own west edge (the door
            -- threshold), landing on verified floor tile 151.
            --
            -- Code-verified via a Watcher+CallTracer write-watchpoint on
            -- $C245/$C244 across the whole scroll: (1) the generic
            -- per-frame position writer keeps running throughout, with
            -- X = 160 - SCX holding frame-by-frame the entire way, so
            -- X=0 the instant SCX finishes at 160 is real ROM
            -- arithmetic; (2) a separate one-shot call chain
            -- (bank 1 $4f0d->$4f48->fixed-bank-0 $29ba->$0611->$0659/
            -- $065b) explicitly re-commits Y=64/X=0 via a path never
            -- taken during ordinary movement -- the ROM's own "landing
            -- commit" step, not a byproduct of walk math alone.
            landingX = 0, landingY = 64,
          },
        },
      },
      -- Real third room, reached through secondRoom's own east exit.
      -- Reuses most of secondRoom's own tileset plus 8 new tile IDs
      -- (188-195). 188-191 (real screen cols 16-17, rows 2-3, top-right)
      -- are the user-reported staircase. No dialogue or new sprites
      -- found (live OAM capture showed only the player).
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
          -- Real, NEW tile IDs, not part of secondRoom's own set. 188-191
          -- had 2 ambiguous byte-identical ROM matches each -- picked
          -- `0x32170-0x321a0`, immediately adjacent to 192-195's own
          -- unambiguous matches, over the more distant alternative.
          [188]=0x32170,[189]=0x32180,[190]=0x32190,[191]=0x321a0,
          [192]=0x322a0,[193]=0x322b0,[194]=0x323a0,[195]=0x323b0,
        },
        -- HYPOTHESIS, same status/method as other rooms. 188-191 (the
        -- staircase) included as walkable -- live testing confirmed
        -- standing on it, and the exit zone is unreachable otherwise.
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
        -- Real staircase -- a fourth, different transition mechanism:
        -- not a scroll. $D392/$D393 actually change ($B0/$46 -> $B0/
        -- $40) and SCX/SCY both snap to 0 -- an instant cut via the
        -- same relocatable-pointer pipeline the courtyard->willyRoom
        -- transition uses. zone is the staircase's screen position; the
        -- whole visible tile block is used as the trigger zone (a
        -- coarser sweep than the other two exits, a reasonable superset).
        --
        -- Code-traced: this cut is real, general, data-driven
        -- infrastructure. The ROM's "commit new room" routine ($01AF3,
        -- bank 0) is fed by a table lookup ($026DC, bank 1): an
        -- 11-byte-stride record table at bank 8 file 0x20000, indexed
        -- by a literal roomSelector byte (this staircase uses selector
        -- 1; its record is 00 00 00 b0 40 80 06 00 40 0e 11, bytes 3-4
        -- = this room's $D392/$D393 target). This project's engine
        -- doesn't read that table at runtime -- recorded here so
        -- targetRoom is understood as table-verified ROM data, not an
        -- empirical guess.
        exits = {
          {
            status = "VERIFIED",
            zone = { xMin = 128, xMax = 143, yMin = 16, yMax = 31 },
            transition = { type = "cut" },
            targetRoom = "fourthRoom",
            -- CORRECTED (same user report as the two exits above): the
            -- old (72,96) was an explicitly-flagged placeholder guess.
            -- Live-traced from staircase_ready.state: held UP until the
            -- instant-cut fired ($D392/$D393 changing from thirdRoom's
            -- to fourthRoom's pointer), released input at that exact
            -- frame (the cut lands the player 9 frames later -- position
            -- stays at the old room's coordinates in between, a real
            -- sequencing detail, not a bug), then confirmed the position
            -- stabilized at exactly (120,112) for 60+ further frames.
            --
            -- REAL HARDWARE OFFSET FOUND (direct user report the
            -- character spawns shifted south/right by a tile) -- see
            -- Player.lua's own RENDER_OFFSET_X/RENDER_OFFSET_Y doc
            -- comment for the full real-hardware OAM trace. Direct
            -- pushback (twice) against both ways this was tried:
            -- editing this value directly (breaks the general "landingX/
            -- landingY is always the raw WRAM value, collision-space"
            -- invariant every other room relies on), and applying the
            -- offset as a general per-draw-call render correction
            -- (regressed startRoom's own rendering, cause not yet
            -- root-caused -- see Player.lua's own doc comment). This
            -- value is deliberately back to the raw, ROM-verified WRAM
            -- value (120,112) -- collision-space, untouched, consistent
            -- with every other room -- while the render-side fix is
            -- properly finished (see Player.lua).
            landingX = 120, landingY = 112,
            -- ROM-TABLE-VERIFIED (task to make everything fully
            -- interpreter-driven, blocker resolution): this pair isn't
            -- just an empirical WRAM capture anymore -- it's the
            -- decoded tile coordinate (14,12) at ROM file 0x382f3
            -- (bank 14), part of a general 186-record landing table
            -- this session found and decoded (see src/import/
            -- CutTransitionTable.lua's own doc comment for the full
            -- derivation). (14+1)*8=120, (12+2)*8=112 -- exact match,
            -- confirming this project's own tile-to-pixel formula
            -- (TileLandingPosition.lua) end to end.
            --
            -- INTERPRETER-DRIVEN, real ROM bytecode (direct user
            -- instruction that everything should run through the
            -- interpreter): a live single-step trace (PC watchpoint on
            -- $11B7, opcode 0xF4's handler) found this transition's own
            -- entry point -- bank 14, CPU $42F6 (file 0x382F6, the 0xF4
            -- byte itself, immediately before the already-known landing
            -- record's A1/A2 bytes at file 0x382F7) -- reached via
            -- genuine top-level script dispatch (74 hits across the
            -- transition, all bank 14). roomSelector/subIndexByte
            -- (below) are now live-captured by CutTransitionInterpreter
            -- at this exact ROM address, not just read from the static
            -- table -- see that module's own doc comment for the full
            -- trace and the honest limit (only this one peek is reached
            -- via top-level dispatch; the landing-tile peek is reached
            -- via the real $413C step automaton's own internal jump,
            -- not top-level dispatch, so landingX/landingY above stay
            -- the pre-baked, already ROM-table-verified constants --
            -- not yet interpreter-captured).
            scriptEntry = {
              bank = 14,
              cpuAddress = 0x42F6,
              transitionKey = "thirdRoomToFourthRoom",
            },
            romRoomSelector = 1, -- live-captured cross-check target, see VictorySequence.lua's own switchToTargetRoom
          },
        },
      },
      -- Real fourth room, reached through thirdRoom's own staircase.
      -- Visually/structurally different from the willyRoom chain: a
      -- simple, repetitive 8-tile set. 6 of 8 tile IDs matched the
      -- known startRoom/environment tileset byte-for-byte, reused
      -- directly. Dominant tile 128 (fills the top) is a solid
      -- all-0xFF pattern, same signature as the courtyard gate's open
      -- state -- reads structurally like an entrance to a bigger
      -- outdoor area, not confirmed.
      --
      -- CORRECTED: this room DOES have a further real exit -- an
      -- earlier "dead end" conclusion from a straight-line-only probe
      -- was retracted after systematic exploration (see fifthRoom's
      -- own doc comment below).
      fourthRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $40B0, roomSelectors 0-1 -- live-
        -- confirmed (via $C3F5) to be the exact same pointer as
        -- startRoom's own pre-combat state. This room's own captured
        -- tiles only partially overlap startRoom's (6/8 exact matches)
        -- -- plausibly the same source rendered through a different
        -- per-byte $D070 remap, not merged into one definition since
        -- the captures genuinely differ visually.
        romRoomSelectors = { 0, 1 },
        -- RESOLVED: live-traced the real thirdRoom->fourthRoom
        -- transition's own `$4395` call site directly -- A=0x1 at that
        -- exact moment, and that's the real target roomSelectorTable
        -- index unmodified. fourthRoom's own real roomSelector is 1,
        -- not 0 (implying startRoom, sharing the same {0,1} candidate
        -- pair, is 0 -- a reasonable inference, not separately
        -- confirmed, so left as {0,1} there).
        romRoomSelectorConfirmed = 1,
        -- CONFIRMED (direct user report the boss room and the room
        -- before it are both on the world map): this room is directly
        -- present in the bank6 (8x8) world-map catalog at grid
        -- (row=7,col=5) -- record index 61 (see startRoom's own doc
        -- comment for sibling record 60/(7,4)). Verified by resolving
        -- each cell's fresh tile ID through its own real file offset
        -- (not comparing raw local tile IDs directly) and comparing
        -- cell-by-cell against this room's own `tileOffsets`: 216/320
        -- cells (67.5%) match, far above the ~15-17% coincidental
        -- baseline. Also directly WEST of startRoom's own (7,4) record,
        -- matching the already-confirmed fourthRoom->sixthRoom(=
        -- startRoom) west exit direction -- independent corroboration.
        -- `table` here uses the rom-inspector website's own source
        -- label ("bank6"), not this module's own field name
        -- (`mapTableBank6`) -- same underlying table, kept distinct so
        -- export can string-match the already-exported catalog.
        worldMapCatalogRecord = { table = "bank6", recordIndex = 61, row = 7, col = 5 },
        -- OBSERVED (2026-08-18, direct user framing "das ist quasi der
        -- Rückweg"): fourthRoom's own two exits both terminate back
        -- inside already-known territory, not new content -- a pure
        -- bridge/junction node between the two real map clusters this
        -- project has found so far. North exit -> fifthRoom, which
        -- carries sameRomIdentityAs={willyRoom,secondRoom,thirdRoom}
        -- (the dungeon cluster); west exit -> sixthRoom, which carries
        -- sameRomIdentityAs={startRoom} (the castle/world-map cluster,
        -- see startRoom's own worldMapCatalogRecord (7,4) and
        -- fourthRoom's own (7,5) above -- directly adjacent). Concrete
        -- corroborating detail for the north/dungeon exit specifically:
        -- fifthRoom's own real landing (136,32) falls inside thirdRoom's
        -- own real exit-zone X-range (128-143) and right at its Y-range
        -- boundary (16-31) -- consistent with, though not decisive proof
        -- of, landing back at/near the same staircase the player left
        -- from (fifthRoom's own captured tiles are honestly only a 17.5%
        -- grid match against thirdRoom's own capture -- a DIFFERENT
        -- scroll excerpt of the identical ROM room, not literally the
        -- same rendered screen -- see fifthRoom's own sameRomIdentityNote
        -- for that already-measured number, not restated as a stronger
        -- claim here). Practical consequence for "World scope": neither
        -- of fourthRoom's own exits is a lead toward new content --
        -- the real remaining frontier is the castle cluster's own
        -- further neighbors (see events.md's 2026-08-18 grid-adjacency
        -- entry) and any still-untested wall of the dungeon cluster
        -- itself.
        bridgeNote = "fourthRoom ist eine reine Brücke zwischen den zwei bekannten Clustern -- " ..
          "beide Exits führen zurück in bereits bekanntes Gebiet, nicht zu neuem Inhalt. " ..
          "Norden -> fifthRoom (= willyRoom/secondRoom/thirdRoom, Dungeon-Cluster; die reale " ..
          "Landeposition (136,32) liegt innerhalb thirdRooms eigener Exit-Zone X=128-143 und " ..
          "direkt an deren Y-Grenze 16-31 -- unterstützend, nicht beweisend, da nur 17.5% " ..
          "Kachel-Übereinstimmung, ein anderer Scroll-Ausschnitt desselben ROM-Raums). " ..
          "Westen -> sixthRoom (= startRoom, Burg-/Weltkarten-Cluster, direkt östlich von " ..
          "fourthRooms eigener Weltkarten-Position (7,5)). Siehe events.md 2026-08-18.",
        cols = 20,
        rows = 16,
        tileOffsets = {
          [128] = string.rep("\255", 16), -- real solid tile, literal pattern (see doc comment above)
          [129] = 0x30300, [130] = 0x30310, [131] = 0x30D10, [132] = 0x30D20,
          [133] = 0x302E0, [134] = 0x302F0,
          [135] = 0x307F0, -- disambiguated like thirdRoom's 188-191: picked the match in the same bank12 neighborhood as this room's other offsets
          -- Real, NEW tile IDs -- the corridor's own wall/border tiles
          -- that only scroll into view once SCX moves off 0 (not
          -- visible at the original landing-spot capture). 136-140/
          -- 143/144/147 each had exactly one real ROM match, clustered
          -- next to this room's own known 131/132. 145/146 had 2
          -- candidates each, picked the closer same-neighborhood match.
          [136] = 0x30D70, [137] = 0x30DC0, [138] = 0x30E50, [139] = 0x30DB0,
          [140] = 0x30D40, [143] = 0x30D90, [144] = 0x30DA0, [145] = 0x30B20,
          [146] = 0x30B30, [147] = 0x30D30,
        },
        -- CORRECTED (direct user report of spawning inside the wall
        -- after the staircase): 129/130 (the border trim) used to be
        -- excluded on a never-tested visual guess -- the staircase's
        -- landing spot (120,112) puts the player's top-half footprint
        -- exactly on 130/129, confirmed both statically and against
        -- live VRAM. With them excluded, TileWalkability blocked the
        -- player from moving away from that overlap at all -- exactly
        -- the reported symptom.
        --
        -- Live re-verified: holding UP from the settled landing spot
        -- walks real screen Y 112->102->95->88 over 30 frames with zero
        -- hesitation crossing the 129/130 row -- open floor, not a
        -- wall. Promoted to verified floor/decoration.
        --
        -- CLOSED (direct user report the spawn/transition were still
        -- broken): 135 promoted from hypothesis to verified floor. Root
        -- cause: the player's 16px-tall footprint touches tile 135 the
        -- instant Y moves even 1px off its spawn-time alignment; with
        -- 135 excluded from floorTileIds, vertical movement was
        -- completely frozen from the instant of landing (confirmed
        -- live, Y never changed over 60 frames) -- explaining both the
        -- "spawn feels wrong" and "fifthRoom exit doesn't work" reports
        -- at once. Directly contradicted by this room's own already-
        -- recorded live evidence above (Y walks freely 112->88) -- 135
        -- was simply never added to floorTileIds to match it.
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
        -- does not go through that pipeline).
        --
        -- Fell back to direct live-movement probing instead of a
        -- decoded table (a raw WRAM position poke proved unreliable in
        -- this environment -- every number below comes from a
        -- genuinely walked real path).
        --
        -- Real, decisive, twice-reproduced finding: holding LEFT from
        -- the landing spot (row 14) or row 13 moves the player NOT AT
        -- ALL for 100+ frames -- a real wall west of column 14. The
        -- same input from row 12 moves freely to the west wall (column
        -- 0); DOWN is also blocked at that same column range. The
        -- staircase landing is a real, narrow alcove (columns ~14-19),
        -- not full-width open floor -- `floorTileIds` can't express
        -- this (same tile IDs appear inside and outside the alcove),
        -- so `TileWalkability.build`'s `blockedRects` escape hatch is
        -- used instead. `colMax=14` (not 13): a first attempt at 13 let
        -- the player's 2-wide footprint take one wrong 8px step before
        -- stopping (caught live), landing at x=112 instead of x=120.
        blockedRects = {
          { rowMin = 13, rowMax = 15, colMin = 0, colMax = 14 },
        },
        -- Real, live-traced exit -- see fifthRoom's own doc comment for
        -- the full evidence trail.
        --
        -- RESOLVED: a dedicated live mgba session (replaying the real
        -- staircase cut, walking the corridor while logging Y/X, SCX/
        -- SCY, and the full VRAM tilemap every step) found: (1) the
        -- zones below (raw WRAM Y/X) are already correct, no transform
        -- needed -- this project's own coordinate space already uses
        -- the same raw WRAM values. (2) the real reconciliation formula
        -- for a live sample -> exact BG tile is `bgRow=(Y+SCY)//8 mod
        -- 32`, `bgCol=(X+SCX)//8 mod 32` (no OAM offset correction --
        -- this ROM's own WRAM->OAM copy is unshifted, confirmed via
        -- direct OAM reads). (3) restricting SCX to its real scrolled
        -- value DOES turn up 10 real, previously-uncaptured tile IDs
        -- (136-140/143-147) -- but all are wall/border decoration near
        -- the top of the screen, never where the player's feet are; the
        -- floor the player stands on stayed ordinary known floor at
        -- every sampled position, so the exit zones never needed
        -- correcting. (4) not further fixable within this room's own
        -- static single-screen grid: Field.lua has no camera-scroll
        -- implementation, so a "cut" transition never needs to render
        -- the scrolled-past corridor -- the new tile IDs are kept in
        -- `tileOffsets` as real documentation, not wired into `grid`.
        --
        -- CLOSED, then CORRECTED (2026-08-18, direct user instruction
        -- "dann kopiere den kollisions/timer mechanismus" after being
        -- told holdFrames=64 was an empirical approximation, not a ROM-
        -- derived value): the "~64 frames" figure above was itself an
        -- external, screenshot-based measurement of when the LANDING
        -- POSITION changes, not the real ROM's own arming condition --
        -- live re-traced via a WRAM write-watchpoint + full disassembly
        -- (`tools/rom/watcher.py`/`calltrace.py`) to find the actual
        -- mechanism:
        --
        -- The real ROM does NOT require the player to hold DOWN
        -- continuously for anything close to 64 frames. It's a genuine
        -- ARM-THEN-AUTONOMOUS state machine:
        --   1. ARMING: live-bisected precisely -- holding DOWN into the
        --      blocked wall for 8 frames never arms it (released after
        --      8 -> no transition, confirmed over 150 further frames of
        --      zero input); 9 frames always does. This is the real,
        --      minimum continuous-hold requirement, not 64.
        --   2. AUTONOMOUS COMPLETION: once armed, the transition runs to
        --      completion ENTIRELY ON ITS OWN, independent of any
        --      further input -- live-verified by releasing DOWN after
        --      only 15 frames (well past arming, nowhere near 64) and
        --      holding zero further input at all: the real ROM room
        --      pointer (`$D392`/`$D393`) still commits and the player
        --      still lands at the exact documented real spot
        --      (Y=32,X=136) around 64 frames after DOWN was first
        --      pressed -- i.e. "~64 frames" was always real and
        --      reproducible, but as an AUTONOMOUS animation duration
        --      after a 9-frame arm, not a required 64-frame hold.
        --   3. THE REAL MECHANISM DRIVING THOSE ~64 FRAMES: a genuine
        --      WRAM counter, `$D49A`, live-watched byte-for-byte via a
        --      write watchpoint: ramps UP 0->30 (one increment per real
        --      frame, bank-1 routine at CPU `$41E2`-`$41EE`: `LD
        --      A,(HL)/SUB 0x02/CP C/JR C,.../JR Z,.../LD (HL),A/LD
        --      HL,0xD49A/INC (HL)`), then, once the room pointer has
        --      already committed and the landing tile write has already
        --      fired, ramps back DOWN 30->0 (bank-1 routine at CPU
        --      `$4205`-`$420A`: `PUSH DE/LD HL,0xD49A/DEC (HL)/JR
        --      Z,$421C` -- the `JR Z` is the real end-of-sequence exit).
        --      `$D499` (the already-known cut-automaton step counter)
        --      advances at specific `$D49A` milestones throughout. This
        --      is the real, ROM-authored wipe-band close/reopen timer
        --      (0->30 close, 30->0 reopen -- the same real visual
        --      mechanism `RoomWipeTransition.lua` already models for a
        --      DIFFERENT transition, cross-confirming the general
        --      mechanism rather than being a coincidence).
        --
        -- REPRODUCED as `holdFrames=9` below (the real, live-bisected
        -- arm threshold) instead of the old `64` (which conflated the
        -- arm condition with the autonomous animation's own total
        -- duration). This engine has no wipe/scroll rendering for cuts
        -- (already established, see the "no camera-scroll
        -- implementation" note above) -- firing instantly once armed is
        -- the honest, correct analog of the real autonomous completion,
        -- not a claim that the real ~55 further ROM frames of wipe
        -- animation are being reproduced too.
        --
        -- Python tooling for the live trace (`find_hold_counter.py`,
        -- `trace_d49a.py`, `test_release_early.py`,
        -- `test_min_press.py`, scratchpad, not checked in, same
        -- convention as every other live-tracing pass this project has
        -- done).
        exits = {
          {
            -- CORRECTED (direct user report the transition doesn't
            -- fire, two real bugs found together): the zone's own
            -- `yMin`/`yMax` (100-108) never actually overlapped a real
            -- wall -- open floor continues from y=32 to y=112 (the
            -- landing spot), so `ZoneMatch` (current-position-only, no
            -- collision) never accumulates the 64-frame hold. Live-
            -- verified where the player actually stops walking up:
            -- exactly y=32 -- the real wall sits between y=30 (blocked)
            -- and y=32 (open), matching this exit's own `landingY`.
            --
            -- Second bug, found testing the first fix: a small zone
            -- right at y=32 still never fires, because holding DOWN
            -- there isn't blocked either -- the player just walks back
            -- out within ~8 frames. `HoldTrigger`/`ZoneMatch` have no
            -- "blocked while held" concept, only "inside the zone this
            -- frame." Rather than inventing unverified wall tiles, the
            -- zone is sized tall enough that a continuous down-hold
            -- starting at y=32 stays inside it for the whole hold, by
            -- construction -- a documented engineering choice, not a
            -- claimed ROM fact. SUPERSEDED SIZING RATIONALE (see
            -- `holdFrames`' own doc comment below): originally sized for
            -- a 64-frame hold; the real ROM arm threshold is only 9
            -- frames, so this zone is now a harmless superset, not
            -- shrunk since an oversized zone causes no bug.
            zone = { xMin = 112, xMax = 128, yMin = 32, yMax = 96 },
            transition = { type = "cut" },
            targetRoom = "fifthRoom",
            landingX = 136, landingY = 32,
            -- ROM-table-verified: real tile coordinate (16,2) at ROM
            -- file `0x38c82` (bank 14) -- `(16+1)*8=136`, `(2+2)*8=32`,
            -- exact match. Live entry point: real opcode 0xF4 at bank
            -- 14, file `0x38c84` -- VictorySequence.lua's own
            -- `switchToTargetRoom` live-captures and cross-checks this
            -- exit's roomSelector too, same as thirdRoom->fourthRoom.
            scriptEntry = {
              bank = 14,
              cpuAddress = 0x4C84,
              transitionKey = "fourthRoomToFifthRoom",
            },
            romRoomSelector = 4, -- live-captured cross-check target, matches fifthRoom's own romRoomSelectorConfirmed above
            -- CORRECTED 2026-08-18: 64 -> 9, the real, live-bisected arm
            -- threshold (see this exit's own "CLOSED, then CORRECTED"
            -- doc comment above for the full disassembly/trace).
            holdFrames = 9, holdDirection = "down",
          },
          {
          -- RE-ADDED (direct user bug report that walking west should
          -- lead somewhere). History: this exit was RETRACTED after
          -- live re-tracing found the real ROM corridor keeps scrolling
          -- as one continuous fourthRoom canvas rather than cutting to
          -- a separate room (still true). This project's renderer has
          -- no camera-scroll implementation though, and the user
          -- directly confirmed walking west is expected to lead
          -- somewhere in THIS app -- so sixthRoom's own already-
          -- captured tile grid is exposed as a static "cut" screen,
          -- the same pragmatic choice already made for willyRoom/
          -- secondRoom/thirdRoom. HONEST STATUS: the ROM itself never
          -- cuts here -- a deliberate engineering choice to make real,
          -- already-decoded content reachable in this project's no-
          -- scroll engine, not a claimed ROM fact (contrast the `down`
          -- exit above, which IS a live-confirmed real cut).
          -- `holdFrames=220` reuses the original real-measured pause
          -- value (real, just not a "cut" trigger in the actual ROM).
          --
          -- CORRECTED: `yMax` shrunk from 110 to 96 -- real collision
          -- blocks LEFT entirely below row 12 (see `blockedRects`
          -- above), so the old zone relied on a west edge the player
          -- can no longer reach by holding LEFT.
          zone = { xMin = 0, xMax = 16, yMin = 40, yMax = 96 },
          transition = { type = "cut" },
          targetRoom = "sixthRoom",
          landingX = 144, landingY = 80,
          holdFrames = 220, holdDirection = "left",
          },
          -- RETRACTED-THEN-RECONSIDERED (kept for the record -- still an
          -- accurate account of what the real ROM does, just no longer
          -- read as "don't build this"): a re-investigation found three
          -- converging pieces of evidence this was never a real "cut":
          -- (1) much longer live holds (3000+ frames) never fire it --
          -- the corridor is bigger than originally captured, with a
          -- second real wall further west; the original "settles at
          -- X=80" was a false read of a temporary ~260-frame pause.
          -- (2) the original "confirmation" (dynamicBank $C3F0=6) is
          -- non-discriminating -- it already reads 6 the instant
          -- fourthRoom itself is entered. (3) decisive: live-captured
          -- the real scroll-time VRAM-write-queue calls during the
          -- corridor walk -- the same mechanism already proven for
          -- secondRoom's own continuation of willyRoom's single
          -- continuous space, with the same tile vocabulary fourthRoom
          -- already uses. A separate, pre-existing doc comment
          -- (StandardScriptHandlers.lua's own `peekTwoByteGate`) had
          -- also already flagged no real cut-sequence table entry for
          -- fourthRoom->sixthRoom exists, unlike the confirmed
          -- thirdRoom->fourthRoom/fourthRoom->fifthRoom entries.
          --
          -- Conclusion, still true: "sixthRoom" is real further columns
          -- of fourthRoom's own single continuous space, not a
          -- genuinely separate ROM room -- this exit is an honestly-
          -- labeled stand-in until real scroll-camera support exists.
        },
      },
      -- Real room found live (a direct user instruction to
      -- systematically probe fourthRoom for further exits, after an
      -- earlier, wrong "dead end" conclusion had to be retracted).
      -- Reached by walking north from fourthRoom's landing spot into a
      -- previously-uncaptured corridor (still fourthRoom's own tile
      -- source, a continuous-scroll extension), then holding DOWN for
      -- ~64 frames against what looks like a wall -- a genuine,
      -- live-confirmed "cut" transition into this room.
      --
      -- Real tile-source pointer $46B0, dynamicBank 7 -- confirmed live
      -- to be the exact same source as the willyRoom/secondRoom/
      -- thirdRoom family -- a different screen/layout of that same
      -- shared tileset, not a new ROM tile region. 44 of 48 distinct
      -- tile IDs already had a verified offset from willyRoom's own
      -- tileOffsets (reused directly); the remaining 4 (172-175) were
      -- found via the same live exact-byte ROM search, one match each.
      --
      -- CORRECTED/DEEPENED (direct user claim this transition just goes
      -- back to thirdRoom): the "dynamicBank 7" framing above was
      -- misleading -- a fresh live check across willyRoom/secondRoom/
      -- thirdRoom/fifthRoom found dynamicBank=7 is ALSO their own value
      -- (never cross-checked before). All four real room-identity
      -- registers this project tracks ($D392/$D393 tile-source
      -- pointer, $C3F0 dynamicBank, $C3F5 roomSelector) are byte-
      -- identical across the whole set -- the user is right that this
      -- "cut" does not land in a genuinely separate ROM room; by the
      -- real ROM's own bookkeeping, fifthRoom IS willyRoom/secondRoom/
      -- thirdRoom (same real record). The only real difference is
      -- SCX/SCY (scroll position): the trio accumulates nonzero SCX/SCY
      -- via continuous scrolling, while fifthRoom is reached via a
      -- genuine cut that resets SCX/SCY to 0/0 -- landing at that same
      -- shared canvas's own origin corner, not continuing from wherever
      -- the willyRoom walk had scrolled to.
      --
      -- HONEST NUANCE: fifthRoom's SCX=0/SCY=0 view is visually close
      -- to thirdRoom's own captured view (same courtyard shape,
      -- checkerboard floor, wall layout) but not byte-identical to
      -- either thirdRoom's or willyRoom's own grid -- a controlled
      -- cell-by-cell comparison (matching real file offsets, not raw
      -- tile-ID numbers) found only 56/320 (17.5%) cells match, vs.
      -- 264-284/320 (82-89%) for any two of the willyRoom/secondRoom/
      -- thirdRoom trio against each other. Most consistent reading: the
      -- real underlying canvas behind roomSelector=4 is LARGER than the
      -- trio's own walking path has ever scrolled through, and this cut
      -- lands at a genuinely different, not-yet-walked section of that
      -- same shared canvas -- real ROM-wise the same room, not an
      -- independent one. See events.md's own dated entry for the full
      -- trace, screenshots, and register table.
      fifthRoom = {
        status = "VERIFIED",
        romRoomSelectors = { 2, 3, 4, 5, 6 },
        -- RESOLVED: a live PC watch on the shared roomSelector-argument
        -- subroutine during the real trigger sequence caught A=4 --
        -- resolving the candidate set above to the confirmed 4.
        -- Independently cross-checked via the same trace's opcode 0xF4
        -- peek (CutTransitionInterpreter's fourthRoomToFifthRoom entry
        -- point): captured (B,C)=(4,80), B=4 again -- two independent
        -- angles agree.
        romRoomSelectorConfirmed = 4,
        -- STRUCTURED, EXPORTABLE cross-reference for the finding
        -- documented in prose further below (direct user claim this
        -- transition just goes back to thirdRoom) -- real, live-
        -- confirmed identity registers ($D392/$D393/$C3F0/$C3F5)
        -- byte-identical to willyRoom/secondRoom/thirdRoom; kept as
        -- real fields (not just a comment) so export_data.lua can
        -- surface this on the website without duplicating the claim.
        sameRomIdentityAs = { "willyRoom", "secondRoom", "thirdRoom" },
        sameRomIdentityNote = "Reale ROM-Identitaetsregister ($D392/$D393 Tile-Source-Pointer, " ..
          "$C3F0 dynamicBank, $C3F5 roomSelector) sind byte-identisch mit willyRoom/secondRoom/" ..
          "thirdRoom (live bestaetigt 2026-08-17) -- derselbe reale ROM-Raum, ein anderer, per " ..
          "Cut erreichter Scroll-Ausschnitt derselben Leinwand, kein unabhaengiger Raum. Nur " ..
          "17.5% Grid-Zellen-Uebereinstimmung mit thirdRoom (vs. 82-89% zwischen je zwei der " ..
          "willyRoom/secondRoom/thirdRoom-Trias) -- nicht dasselbe bereits erfasste Bild, aber " ..
          "dieselbe ROM-Rauminstanz. Siehe events.md 2026-08-17. UNTERSTUETZENDES DETAIL " ..
          "(2026-08-18, \"das ist quasi der Rueckweg\"): die reale Landeposition hier (136,32) " ..
          "liegt innerhalb thirdRooms eigener Exit-Zone nach fourthRoom (X=128-143, Y=16-31) -- " ..
          "konsistent mit einer Landung nahe der ursprünglichen Treppe, aber NICHT die staerkere " ..
          "17.5%-Aussage ueberschreibend (andere Kamera-Position, gleicher ROM-Raum). Siehe " ..
          "fourthRooms eigenes bridgeNote fuer die volle Einordnung.",
        -- FIX, 2026-08-18 (same direct, repeated, frustrated user report
        -- as sixthRoom's own note -- see that field for the full
        -- reasoning). "thirdRoom" specifically (not willyRoom/secondRoom,
        -- the other two same-family members): fifthRoom is reached
        -- EXCLUSIVELY via thirdRoom's own exit and lands back inside
        -- thirdRoom's own exit-zone coordinates (see this note's own
        -- "UNTERSTUETZENDES DETAIL" above) -- the most specific, best-
        -- justified single merge target of the three.
        mergeInto = "thirdRoom",
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
          [172] = 0x32410, -- NEW, found this pass (VRAM pattern search, 1 match each)
          [173] = 0x32430,
          [174] = 0x32360,
          [175] = 0x32370,
        },
        -- Real, live-confirmed floor tiles: the landing spot walked
        -- freely left/down, both staying within the checkered 147-150
        -- pattern, while RIGHT/UP hit walls almost immediately. Border
        -- tiles (128-146/155-175) default to non-floor per this
        -- project's honest untested-border-defaults-to-wall convention.
        floorTileIds = { [147] = true, [148] = true, [149] = true, [150] = true },
        -- Real VRAM tilemap capture at the settled landing position
        -- (background map 0, rows 0-15/cols 0-19, standard 20x16 grid).
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
        -- RETRACTED (direct user report this was still the wrong room --
        -- "looks like the start room where the first boss fight
        -- happens"; live back-and-forth confirmed it's reached by
        -- walking WEST out of fourthRoom's corridor): a `secondBoss`
        -- entry used to live here. Moved to sixthRoom (see that room's
        -- own doc comment) since the described room is reached going
        -- west, not north. fifthRoom itself is real (the north exit is
        -- a genuine live-traced cut) but isn't where this encounter lives.
      },
      -- Real room found live (direct user bug report that the room
      -- after the staircase should keep scrolling west). An earlier
      -- flood-fill DID try LEFT from the staircase landing and found a
      -- wall -- but gave up after only 10 stall frames, short of the
      -- ~64-frame hold already known for the north exit (a false
      -- negative). Re-tested with a longer (200+ frame) hold from the
      -- same corridor -- the real SCX shadow ($C0A6) genuinely moves
      -- (0 -> 184 -> settles at 96), confirming an actual hardware
      -- scroll, revealing this previously-uncaptured screen. Real tile-
      -- source pointer $46B0, dynamicBank 6 -- confirmed live to be the
      -- same willyRoom/secondRoom/thirdRoom/fifthRoom family, matching
      -- fourthRoom's own selector-1 dynamicBank -- further content of
      -- that same already-explored screen, not a new tile region.
      --
      -- CORRECTED: the paragraph above already had the answer; three
      -- further confirmations made it decisive -- see fourthRoom.exits'
      -- own "RETRACTED" doc comment for the full evidence trail (the
      -- documented cut-trigger never fires even after 3000+ frames; the
      -- $C3F0=6 "confirmation" was non-discriminating; the same scroll-
      -- reveal mechanism that proved secondRoom is part of willyRoom
      -- fires here too). tileOffsets are kept (genuine, cross-validated
      -- ROM data) -- the ROM structure genuinely never cuts here.
      --
      -- RE-WIRED (direct user bug report -- see fourthRoom.exits' own
      -- "RE-ADDED" doc comment): fourthRoom.exits points here again as
      -- an honestly-labeled engineering choice, not a reversal of the
      -- finding above -- this project's no-camera-scroll engine has no
      -- other way to make this content reachable, and the user directly
      -- confirmed something should be here going west.
      --
      -- Also now hosts the second-boss encounter (moved here from
      -- fifthRoom per the user's third correction on this feature,
      -- confirmed to be reached walking west out of fourthRoom).
      --
      -- RETRACTED (direct user claim sixthRoom must clearly be
      -- startRoom, correct): the "HONEST CAVEAT" that used to sit here
      -- (claiming this room's tileset is the willyRoom/secondRoom/
      -- thirdRoom family, not startRoom's) was WRONG -- it compared
      -- tile graphics against the wrong reference family and never
      -- checked the real WRAM room-identity registers against
      -- startRoom's own live value. Live re-checked:
      --   startRoom:  D392/D393=(0xb0,0x40) C3F0=6 C3F5=1 SCX/SCY=0/0
      --   fourthRoom: D392/D393=(0xb0,0x40) C3F0=6 C3F5=1 SCX/SCY=0/0
      --   sixthRoom:  D392/D393=(0xb0,0x40) C3F0=6 C3F5=1 SCX=96 SCY=0
      -- All three identity registers are byte-identical -- the user's
      -- "looks like the start room" was literally correct, and this
      -- project's prior dismissal was the actual mistake. Further
      -- corroboration: a fresh sixthRoom screenshot shows the same
      -- "Kämpfe!" battle-intro textbox startRoom's own boss-encounter
      -- script drives. romRoomSelectors corrected from the wrong
      -- {2,3,4,5,6} (willyRoom family, apparently copied from a
      -- neighboring room, never confirmed) to the real, live-confirmed
      -- {0,1}/1, matching startRoom/fourthRoom's own family. Extends
      -- the "one continuous scrolled canvas, several named screens"
      -- pattern to a second chain: startRoom/fourthRoom/sixthRoom.
      -- Doesn't retract the west-direction connectivity or the
      -- secondBoss placement's own honest status -- only the room-
      -- identity claim was wrong. See events.md for the full trace.
      sixthRoom = {
        status = "VERIFIED (real tile/collision data; wired as a static room reachable " ..
          "west of fourthRoom -- see doc comment above for the honest 'engineering choice, not a ROM cut' caveat)",
        romRoomSelectors = { 0, 1 },
        romRoomSelectorConfirmed = 1,
        sameRomIdentityAs = { "startRoom", "fourthRoom" },
        sameRomIdentityNote = "Reale ROM-Identitaetsregister ($D392/$D393 Tile-Source-Pointer, " ..
          "$C3F0 dynamicBank, $C3F5 roomSelector) sind byte-identisch mit startRoom/fourthRoom " ..
          "(live bestaetigt 2026-08-17) -- derselbe reale ROM-Raum (die 'Glaive Castle prison " ..
          "arena'), ein anderer, per Scroll erreichter Ausschnitt derselben Leinwand, kein " ..
          "unabhaengiger Raum. Zusaetzlich bestaetigt: die reale ROM-eigene \"Kaempfe!\"-Textbox " ..
          "(dieselbe wie in startRoom) erscheint auch hier. Siehe events.md 2026-08-17.",
        -- FIX, 2026-08-18 (direct, repeated, frustrated user report: "DER
        -- FITH ROOM IST DOCH IMMERNOCH IM RAUMSYSTEM UND DER STARTRAUM
        -- IST IMMERNOCH NOICHT IDENTISCH MIT DEM 6. ROOM" -- the violet
        -- "same identity" BADGE alone was never enough; the room-system
        -- graph still rendered this as its own separate box, because it
        -- was still added as its own node whenever an exit's own
        -- `targetRoom` referenced it by name). `mergeInto` tells the
        -- graph renderer to redirect any incoming edge to the named
        -- room instead of creating a separate node at all -- "startRoom"
        -- specifically (not "fourthRoom", the OTHER same-family member),
        -- since the visual/live-confirmed identity match is against
        -- startRoom's own real capture (the "Kaempfe!" textbox proof
        -- above), not fourthRoom's own, genuinely different capture.
        mergeInto = "startRoom",
        cols = 20,
        rows = 16,
        -- 7 of 16 distinct real tile IDs (`128`-`134`) already had a
        -- real, verified ROM offset from `fourthRoom`'s own
        -- tileOffsets (reused directly, since this is the same
        -- underlying tileset); the remaining 9 (136/137/142-147/150)
        -- were found via the same live VRAM-pattern ROM search. 2 of
        -- them (145/146/150) had 2 byte-identical matches each --
        -- disambiguated the same way thirdRoom's own 188-191 were:
        -- picked the match adjacent to this room's other unambiguous
        -- offsets (0x30b2x-0x30b4x, a consistent 16-byte-apart run)
        -- over a more distant alternative.
        tileOffsets = {
          [128] = string.rep("\255", 16), [129] = 0x30300, [130] = 0x30310,
          [131] = 0x30D10, [132] = 0x30D20, [133] = 0x302E0, [134] = 0x302F0,
          [136] = 0x30D70, [137] = 0x30DC0, [142] = 0x30D80, [143] = 0x30D90,
          [144] = 0x30DA0, [145] = 0x30B20, [146] = 0x30B30, [147] = 0x30D30,
          [150] = 0x30B40,
        },
        -- HYPOTHESIS (same status/method as fourthRoom's own
        -- floorTileIds, reused directly): 129-134 are the same
        -- checkered floor tiles already promoted to VERIFIED there --
        -- not re-tested here, on the strength of being the same shared
        -- tileset. 128 (solid 0xFF) stays non-floor.
        --
        -- CORRECTED (follow-up while verifying the second-boss fight
        -- end to end): 145/146 were originally left non-floor as
        -- "gate/pillar" tiles on a visual guess. Wrong -- the captured
        -- grid shows 145/146 form a clean checkerboard alternation
        -- (rows 5-14, cols 14-17) structurally identical to the two
        -- already-confirmed floor pairs (129/130 and 133/134) -- a
        -- third floor texture variant, not a decoration. The remaining
        -- 7 gate/pillar tiles (136/137/142-144/150) don't share this
        -- signature and stay non-floor. Concretely surfaced by a
        -- reproducible symptom: with 145/146 classified as wall, the
        -- second boss (spawnX=64) was unreachable walking left from the
        -- landing spot (landingX=144) -- live-caught stalling at x=128.
        floorTileIds = { [129] = true, [130] = true, [131] = true, [132] = true,
          [133] = true, [134] = true, [145] = true, [146] = true },
        -- ADDED (direct user description: the exit opens halfway once
        -- the 2nd boss is defeated): an honest engineering-choice tile
        -- swap, same shape/precedent as willyRoom's own decoded door
        -- (closedGrid/openGrid), but not independently ROM-confirmed
        -- since this whole encounter is this project's own addition
        -- with no live ROM trigger. "Opens halfway": only the bottom 2
        -- of 4 rows swap to already-decoded floor tile 131.
        --
        -- RETRACTED CLAIM (see this file's capture-bug retraction on
        -- sixthRoom.grid above): this doc comment used to claim
        -- bgRow=0,bgCol=16 matches the real 136/137 gate/pillar strip
        -- in this room's captured grid -- true of the old, now-
        -- retracted (capture-bug) grid, but false of the corrected
        -- content (startRoom's grid there is plain wall). The mechanism
        -- still functions unchanged -- just a purely cosmetic stand-in
        -- now, not a claim about matching surrounding art. Real
        -- redesign against the corrected background is open follow-up
        -- work, not done this pass.
        gate = {
          bgRow = 0, bgCol = 16, rows = 4, cols = 2,
          closedGrid = { {136,137}, {136,137}, {136,137}, {136,137} },
          openGrid = { {136,137}, {136,137}, {131,131}, {131,131} },
        },
        -- RETRACTED (see this file's post-construction fixup loop,
        -- right before RomProfiles.match, for the full explanation):
        -- this grid/tileOffsets/floorTileIds turned out to be a capture
        -- bug (a raw VRAM tilemap read that never corrected for the
        -- nonzero hardware SCX at this room's settled position) -- not
        -- a real screen any player would see. Kept unedited as the
        -- historical record the retraction comment cites; sixthRoom's
        -- actual render data is overridden further down to correct
        -- startRoom data instead.
        --
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
        -- Second boss encounter -- see this table's top-of-entry doc
        -- comment for the full placement history and room-identity
        -- caveat. Species-byte/structural evidence trail is unchanged
        -- from the original investigation (docs/reverse-engineering/
        -- events.md's "second boss investigation" section) -- only the
        -- room it's placed in moved.
        --
        -- spawnX/spawnY sit inside this room's live-tested floorTileIds
        -- checkerboard (129-134, the open courtyard away from the
        -- gate/pillar structure) -- not a decoded ROM position (no live
        -- trigger was ever found, same honest limit as the original
        -- fifthRoom placement had).
        -- REAL-ROM TEST (after finding this room chain is really the
        -- Glaive Castle prison arena intro, not Marsh Cave -- see
        -- docs/references.md): fought and defeated the real boss under
        -- real ROM emulation and found an honest negative result: the
        -- gate shows no visible/collision change before vs. after, even
        -- after a generous settle (2700+ frames). Combined with the
        -- story context (the real second-Jackal/gate event happens
        -- immediately after the first fight, in the same short arena
        -- sequence, not past a multi-room corridor), this is evidence
        -- against sixthRoom being the right location for this mechanic
        -- -- not proof, but an honest data point. See events.md's
        -- "Real-ROM test of the sixthRoom gate mechanic" entry.
        secondBoss = {
          status = "IMPLEMENTATION CHOICE, evidence-based (species-byte + structural-family match to the " ..
            "real first-boss record; room placement itself matches the user's own live-confirmed 'west of " ..
            "fourthRoom' report, not an independently ROM-confirmed spawn trigger for this specific room) -- " ..
            "REAL-ROM gate test 2026-08-17 found NO detectable gate change after defeating this boss, real " ..
            "evidence AGAINST this specific placement, see events.md",
          spawnX = 64, spawnY = 80,
        },
        -- ADDED (direct user report: after the 2nd boss, the exit opens
        -- in the north): a general requiresFlag gate on an exit (built
        -- alongside the second-boss feature, see VictorySequence.lua's
        -- own HoldTrigger-resolution doc comment) finally has something
        -- to gate. Same honest category as secondBoss above: an
        -- implementation choice, not an independently ROM-confirmed
        -- exit -- but grounded in real room data: the captured grid
        -- shows a gate/pillar structure (tiles 136/137, a non-floor
        -- 2-column strip) at cols 16-17, rows 0-3 -- the room's north
        -- edge, matching the user's "opens in the north" report before
        -- any exit was wired here. zone below sits under that feature.
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
      -- SUPERSEDED (2026-08-17, direct user report: "und ja nach dem
      -- zweiten boss nachdem sich das tor geöffnet hat und der player
      -- durchgegangen ist kommt er auf der kleinen weltmap an 6.3
      -- raus"): this room used to be a pure engineering CHOICE (bank 5,
      -- mapTable record 220, picked only by a "reasonable middle
      -- ground" walkable-percentage heuristic, no real spatial/story
      -- basis at all -- see events.md's own 2026-08-16 entry for that
      -- history, kept there unedited as a historical record). The
      -- user's direct, first-hand claim -- same evidentiary category
      -- that already confirmed startRoom/fourthRoom's own world-map
      -- positions this same day -- gives a real destination instead:
      -- the bank6 (8x8) world-map catalog, record 51, grid (row=6,
      -- col=3). Decoded via the same corrected `0x30000` pipeline used
      -- everywhere else (`RoomFloorLayout.buildRoomFromMapTableRecord`/
      -- `toTileGridBackgroundData`) -- a coherent, real outdoor scene
      -- (a castle-wall exterior, pine trees, an open dotted-ground
      -- path), a plausible "stepped out through the gate onto the
      -- overworld" scene, qualitatively unlike the old checkerboard-
      -- interior guess. Cross-checked against the OLD data: only 17.5%
      -- cell overlap -- confirms these are genuinely different rooms,
      -- not a coincidental re-derivation of the same one. HONEST LIMIT:
      -- unlike startRoom/fourthRoom, no independent live-VRAM ground
      -- truth exists for this specific room (there was never a live
      -- gameplay capture of "what's past the second-boss gate") -- this
      -- rests on the user's direct testimony plus a coherent decode,
      -- not the live-VRAM-cross-check standard those two have. Still an
      -- IMPLEMENTATION CHOICE, just with a real narrative/positional
      -- basis now instead of a blind heuristic pick.
      -- RETRACTED same pass: the old seventhRoom->eighthRoom south exit
      -- was picked via a byte-exact shared-edge match against the OLD
      -- south row -- no longer exists here, so removed rather than left
      -- pointing at stale geometry (see eighthRoom's own doc comment).
      -- sixthRoom's exit into this room keeps its landingX/landingY
      -- (80,112), tuned for the OLD room and unverified against this
      -- one -- happens to land on walkable floor here too (tile 46/47)
      -- by coincidence, kept as a placeholder rather than re-guessed.
      seventhRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank6 (world-map catalog) " ..
          "record 51, grid row=6/col=3 -- placed per a direct, credible user report of the real landing " ..
          "spot after the second-boss gate, 2026-08-17; not independently ROM-confirmed to the live-VRAM " ..
          "standard startRoom/fourthRoom have) -- SUPERSEDES the earlier bank5-record-220 placeholder, see doc comment above",
        cols = 20,
        rows = 16,
        worldMapCatalogRecord = { table = "bank6", recordIndex = 51, row = 6, col = 3 },
        tileOffsets = {
          [37] = 0x30250, [46] = 0x302E0, [47] = 0x302F0, [66] = 0x30420, [67] = 0x30430,
          [68] = 0x30440, [69] = 0x30450, [70] = 0x30460, [71] = 0x30470, [72] = 0x30480,
          [73] = 0x30490, [78] = 0x304E0, [79] = 0x304F0, [80] = 0x30500, [81] = 0x30510,
          [82] = 0x30520, [83] = 0x30530, [84] = 0x30540, [89] = 0x30590, [90] = 0x305A0,
          [91] = 0x305B0, [150] = 0x30960, [151] = 0x30970, [152] = 0x30980, [153] = 0x30990,
          [209] = 0x30D10, [210] = 0x30D20, [211] = 0x30D30, [212] = 0x30D40, [213] = 0x30D50,
          [214] = 0x30D60, [215] = 0x30D70, [216] = 0x30D80, [217] = 0x30D90, [218] = 0x30DA0,
          [219] = 0x30DB0, [220] = 0x30DC0,
        },
        -- HYPOTHESIS, not decoded ROM collision data (bank6 is RLE-mode
        -- -- per the external FFA-Disassembly doc, real per-tile "Door
        -- Bytes" collision only exists for templated-mode/bank7 maps).
        -- Visual classification only: 46/47 (dotted open-ground texture,
        -- file offsets exactly matching fourthRoom's/startRoom's own
        -- classified walkable floor) as floor; castle-wall pillars
        -- (66-84), trees (150-153), border trim (209-220, matching
        -- fourthRoom's wall-family offsets) as non-walkable.
        floorTileIds = { [46] = true, [47] = true },
        grid = {
          { 66, 67, 66, 67, 70, 71,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          { 68, 69, 68, 69, 72, 73,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          { 78, 79, 78, 79, 82, 83,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          { 80, 81, 80, 81, 84, 37,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          {150,151,150,151,150,151,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          {152,153,152,153,152,153,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          {150,151,150,151,150,151,219,212,209,209,215,220,209,209,209,209,209,209,219,212},
          {152,153,152,153,152,153,219,212,209,209,215,220,210,210,210,210,210,210,219,212},
          {150,151,150,151, 46, 47,211,212,209,209,215,216, 46, 47, 46, 47, 46, 47,211,212},
          {152,153,152,153, 46, 47,213,214,210,210,217,218, 46, 47, 46, 47, 46, 47,213,214},
          {150,151, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          {152,153, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          { 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47, 46, 47},
          {150,151,150,151,150,151, 46, 47, 46, 47, 46, 47, 46, 47, 37, 89, 70, 71, 70, 71},
          {152,153,152,153,152,153, 46, 47, 46, 47, 46, 47, 46, 47, 90, 91, 72, 73, 72, 73},
        },
        -- RETRACTED (see doc comment above): the old south exit to
        -- eighthRoom was byte-matched against a row that no longer
        -- exists here. No real destination known for this room's south
        -- row or east edge yet -- left honestly unexplored.
        --
        -- ADDED then RETRACTED 2026-08-19 (both same day, direct user
        -- instruction each time): a door to `unknownRoomA_8` was briefly
        -- added here as an explicit ENGINEERING CHOICE ("Regel für
        -- unknownRoomA bewusst lockern... voll spielbare Version"),
        -- policy-relaxed the same way `sixthRoom`'s own static west exit
        -- was. It was pulled back after a direct, blunt user report
        -- ("alles nach dem 7. raum ist müll") triggered a full re-audit:
        -- `unknownRoomA`'s own `floorTileIds` -- the ONLY thing this
        -- door's landing spot, and the whole 6-room chain behind it,
        -- depended on -- turned out to mismatch this project's own
        -- stated collision-byte classification rule for 42 of 82 tiles
        -- actually used. Rebuilding the set by applying that rule fully
        -- and mechanically (see `UNKNOWN_ROOM_A_FLOOR_TILE_IDS`'s own
        -- doc comment above) did NOT fix it -- it revealed a checkerboard
        -- artifact with almost no coherent 2x2-footprint-walkable area
        -- in most of the 6 rooms (2 of 6 rooms had ZERO connected
        -- walkable footprint at all under the corrected rule). This
        -- confirms the room's own original caution ("stays a hypothesis
        -- for unknownRoomA specifically... no live trigger exists to
        -- verify it directly") was right to begin with: the collision-
        -- byte heuristic simply does not hold for unknownRoomA's
        -- metatile table, so no honest door can be placed here yet.
        -- `unknownRoomA`'s room CONTENT (tile-art grids) is untouched
        -- and stays real, decoded ROM data -- only connectivity is
        -- withdrawn again, back to empty, until a trustworthy floor
        -- source exists for this specific metatile table.
        exits = {},
      },
      -- ADDED (same continuation, same self-correction): real bank-5
      -- catalog record 236 -- seventhRoom's own SOUTH neighbor (not the
      -- west one from the retracted first attempt). Its north row is a
      -- byte-exact match against seventhRoom's own south row at the
      -- reachable columns (8-15) -- verified via the same collision-
      -- grid re-derivation this room's test file runs live.
      -- TILESET CORRECTED: same fix, same evidence as seventhRoom's own
      -- doc comment above -- see mapTable.tilesetFileOffset's own
      -- dated correction for the full formula. grid unchanged, only
      -- tileOffsets.
      -- CONNECTION TO seventhRoom RETRACTED (same day, direct follow-
      -- up): the "byte-exact shared-edge match" above was against
      -- seventhRoom's OLD data (bank5 record 220) -- seventhRoom was
      -- superseded this same pass with real bank6 record 51 (per a
      -- direct user report of the actual post-second-boss landing
      -- spot), whose south row shares nothing with this room's north
      -- row. This room's own data is untouched and still real -- only
      -- the "sits south of seventhRoom" claim is now false and no
      -- longer asserted (seventhRoom's exits is empty). This room keeps
      -- its own exit to ninthRoom below (an independent edge-match,
      -- unaffected) -- simply no longer reachable from the known
      -- sixthRoom/seventhRoom chain, an honest regression in known
      -- connectivity, not silently left contradictory.
      eighthRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank 5, mapTable record 236; " ..
          "chosen via a byte-exact shared-edge match with seventhRoom's own (NOW SUPERSEDED, no longer valid) south row (at the real, BFS-" ..
          "confirmed reachable columns), not independently ROM-confirmed) -- " ..
          "TILESET CORRECTED 2026-08-17 after a direct, credible user report -- see seventhRoom's own doc comment",
        cols = 20,
        rows = 16,
        -- ADDED (2026-08-18, direct user report "7. raum ist auch auf
        -- der weltkarte. genau wie 8 und 9"): this room already WAS a
        -- real bank-5 (16x16 grid) catalog record (236) by construction
        -- -- it just never got the same `worldMapCatalogRecord`
        -- cross-reference field startRoom/fourthRoom/seventhRoom carry,
        -- so the website's own 🗺 Weltkarte badge never showed it.
        -- row/col via the project's own established formula
        -- (row=floor(index/16), col=index%16, stride=16 for bank5 --
        -- see worldmap.js's own doc comment): 236 -> (14,12). Same
        -- confidence level as this room's own `status` above already
        -- states (edge-match choice, not independently live-verified)
        -- -- NOT the stronger live-VRAM standard startRoom/fourthRoom
        -- carry; also on a DIFFERENT real grid than seventhRoom's own
        -- bank6 badge (bank5 is a separate 16x16 "map0", not adjacent
        -- to bank6's "map1").
        --
        -- RE-CHECKED, NOT MOVED (2026-08-18, direct user instruction
        -- "na dann fixe das", after being told this room sits on a
        -- different map than seventhRoom's now-corrected bank6
        -- position): since the OLD seventhRoom->eighthRoom edge-match
        -- that originally placed this room is itself now known-invalid
        -- (see this room's own `status` above), ran a full, exhaustive
        -- content re-check -- decoded this room's own real grid as file
        -- offsets (via its own tileOffsets) and compared cell-by-cell
        -- against EVERY OTHER bank5 (255) and bank6 (64) catalog
        -- record's own real decoded content, the exact same "compare by
        -- real file offset" method that found startRoom's 98.8%/
        -- fourthRoom's 67.5% exact matches. Result: NO decisive match --
        -- best candidate (bank5 record 217, row13/col9, not even
        -- spatially adjacent to this room's own row14/col12) is only
        -- 48.1% (154/320), with a gradual, structureless falloff from
        -- there (47.8%, 46.2%, 44.4%, ...) -- the shape of generic
        -- shared-tileset overlap across the whole catalog, not a real
        -- identity spike the way the 65%+ real matches elsewhere show.
        -- Honest conclusion: this room's own existing bank5 position
        -- (236) remains the best-supported placement -- no evidence
        -- found to move it. The real, still-open gap is connectivity
        -- (no known live trigger reaches it since seventhRoom moved),
        -- not this room's own content or position -- the same
        -- "how does the ROM select any room beyond the 16 known
        -- roomSelectorTable slots" mystery already flagged elsewhere,
        -- not a new, separate problem. See events.md 2026-08-18.
        worldMapCatalogRecord = { table = "bank5", recordIndex = 236, row = 14, col = 12 },
        tileOffsets = {
          [12] = 0x300C0, [13] = 0x300D0, [14] = 0x300E0, [15] = 0x300F0,
          [17] = 0x30110, [18] = 0x30120, [19] = 0x30130, [20] = 0x30140,
          [21] = 0x30150, [25] = 0x30190, [26] = 0x301A0, [37] = 0x30250,
          [45] = 0x302D0, [46] = 0x302E0, [47] = 0x302F0, [54] = 0x30360,
          [55] = 0x30370, [56] = 0x30380, [57] = 0x30390, [62] = 0x303E0,
          [63] = 0x303F0, [64] = 0x30400, [66] = 0x30420, [67] = 0x30430,
          [68] = 0x30440, [69] = 0x30450, [74] = 0x304A0, [75] = 0x304B0,
          [77] = 0x304D0, [150] = 0x30960, [151] = 0x30970, [152] = 0x30980,
          [153] = 0x30990,
        },
        -- Real per-metatile-instance collision bytes. Tile 68 is
        -- genuinely position-dependent (8 instances floor, 4 wall --
        -- same category of imprecision already accepted elsewhere, e.g.
        -- sixthRoom's 145/146). Checked: every wall instance sits
        -- outside the BFS-reachable region from the landing spot -- so
        -- marking 68 as floor is safe for every reachable cell, even
        -- though imprecise for cells nobody can walk to anyway.
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
      -- ADDED (same continuation): real bank-5 catalog record 237 --
      -- eighthRoom's own east neighbor, same byte-exact shared-edge
      -- standard (both rooms' east/west columns read WWWWWW at rows
      -- 0-5). BFS-confirmed 36 cells reachable from the landing spot;
      -- further neighbors not investigated this pass.
      -- TILESET CORRECTED: same fix/evidence as seventhRoom's own doc
      -- comment above. grid unchanged, only tileOffsets.
      ninthRoom = {
        status = "IMPLEMENTATION CHOICE (real, decoded ROM room-catalog data -- bank 5, mapTable record 237; " ..
          "chosen via a byte-exact shared-edge match with eighthRoom's own east column, not independently " ..
          "ROM-confirmed) -- " ..
          "TILESET CORRECTED 2026-08-17 after a direct, credible user report -- see seventhRoom's own doc comment",
        cols = 20,
        rows = 16,
        -- ADDED (2026-08-18, same direct user report as eighthRoom's
        -- own doc comment above): 237 -> (14,13), directly east of
        -- eighthRoom's own (14,12) -- matching this room's own already-
        -- documented "eighthRoom's own east neighbor" placement exactly.
        -- Same honest confidence caveat as eighthRoom's own field.
        --
        -- RE-CHECKED, NOT MOVED (2026-08-18, same "na dann fixe das"
        -- re-check as eighthRoom's own doc comment above, same exhaustive
        -- whole-catalog method): best candidate for THIS room's own real
        -- content is bank5 record 249 at only 45.3% (145/320), again a
        -- gradual, structureless falloff -- not a real-identity spike.
        -- Own existing bank5 position (237) remains the best-supported
        -- placement. Same open connectivity gap as eighthRoom, not a
        -- content/position problem. See events.md 2026-08-18.
        worldMapCatalogRecord = { table = "bank5", recordIndex = 237, row = 14, col = 13 },
        tileOffsets = {
          [12] = 0x300C0, [13] = 0x300D0, [14] = 0x300E0, [15] = 0x300F0,
          [17] = 0x30110, [18] = 0x30120, [19] = 0x30130, [20] = 0x30140,
          [21] = 0x30150, [22] = 0x30160, [23] = 0x30170, [24] = 0x30180,
          [27] = 0x301B0, [28] = 0x301C0, [34] = 0x30220, [35] = 0x30230,
          [36] = 0x30240, [37] = 0x30250, [45] = 0x302D0, [54] = 0x30360,
          [55] = 0x30370, [62] = 0x303E0, [63] = 0x303F0, [64] = 0x30400,
          [66] = 0x30420, [67] = 0x30430, [68] = 0x30440, [69] = 0x30450,
          [70] = 0x30460, [71] = 0x30470, [72] = 0x30480, [73] = 0x30490,
          [74] = 0x304A0, [75] = 0x304B0, [77] = 0x304D0, [78] = 0x304E0,
          [79] = 0x304F0, [80] = 0x30500, [81] = 0x30510, [82] = 0x30520,
          [83] = 0x30530, [84] = 0x30540, [127] = 0x307F0, [132] = 0x30840,
          [133] = 0x30850, [134] = 0x30860, [135] = 0x30870,
        },
        -- Same position-dependent tile-68 imprecision as eighthRoom
        -- above -- every wall instance here also sits outside the
        -- BFS-reachable region from the landing spot.
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
        -- No further exits wired this pass -- the BFS-confirmed
        -- reachable region (36 of 320 cells, top-left block) has no
        -- further edge opening beyond the west column used to enter it.
        -- An honest dead end, not chased further given seventhRoom's
        -- earlier caught mistake: every claim here is BFS-verified, not
        -- just edge-pattern-matched.
      },
      -- Real player + "Willy" sprites standing in the room above, found
      -- by direct user report (the first implementation drew the room
      -- but neither character). Live OAM capture: 4 active sprite
      -- entries (8x16 OBJ mode), 2 16x16 characters side by side.
      -- Per-tile ROM offsets found the same way as willyRoom.tileOffsets
      -- (VRAM-pattern byte search) -- a third, distinct ROM region from
      -- either the room's tileset or the field player/enemy sprites --
      -- this scene loads its own dedicated small sprite set.
      willyScene = {
        status = "VERIFIED",
        -- Real screen position (OAM Y/X minus the standard 16/8 hardware
        -- offset, same convention as playerSprite/enemySprite).
        player = {
          screenX = 80, screenY = 80,
          -- Row-major top-left/top-right/bottom-left/bottom-right
          -- (8x16-mode tile pairs: OAM tile 0x00 implies 0x00+0x01
          -- stacked, same convention as attackSwing/other 2x2 blocks).
          tileOffsets = { 0x21b00, 0x21b10, 0x21b20, 0x21b30 },
          flipX = false,
        },
        willy = {
          screenX = 64, screenY = 80,
          tileOffsets = { 0x26d80, 0x26d90, 0x26da0, 0x26db0 },
          -- OAM attribute byte 0x10 (bit 4 set) -- Willy renders with
          -- OBP1, not the player's OBP0 (same palette-select mechanism
          -- already found for the enemy sprite).
          palette = "OBP1",
          flipX = false,
        },
        -- CORRECTED (direct user report NPC sprites don't match): this
        -- 0xFB capture was real, but a momentary value specific to the
        -- exact instant read (mid-dialogue-box flash effect), not
        -- Willy's/any NPC's resting palette -- and VictorySequence.lua
        -- was reusing it for every room's scene characters, not just
        -- this cutscene moment. Live re-checked well after any dialogue
        -- box: real OBP0/OBP1 are both 0xD3 in willyRoom AND secondRoom
        -- during free-roam -- functionally the same (ignoring the
        -- hardware-transparent id0) as the VERIFIED spritePalette
        -- .shadeIndices above (0xD0 -> {0,0,1,3}; 0xD3 differs only in
        -- id0). VictorySequence.lua now uses spritePalette.shadeIndices
        -- for its shared NPC/Willy palette instead -- this field is
        -- kept as an honest record of the capture, no longer treated as
        -- "the general resting palette" (that was the actual bug).
        paletteShadeIndices = { 3, 2, 3, 3 },
      },
      startRoom = {
        status = "VERIFIED",
        -- Real tile-source pointer $40B0, roomSelectors 0-1 -- see
        -- `fourthRoom`'s own doc comment above for the full "same
        -- pointer, partially-different capture" note.
        romRoomSelectors = { 0, 1 },
        -- ADDED (direct user instruction that startRoom needs different
        -- treatment in the room-system graph): the reciprocal side of
        -- sixthRoom.sameRomIdentityAs above -- this room's WRAM identity
        -- registers are byte-identical to sixthRoom's (already
        -- confirmed), so this room isn't merely "isolated" in the
        -- play-flow graph -- it's the exact same ROM room as sixthRoom,
        -- which DOES have live-traced connections (fourthRoom->
        -- sixthRoom->seventhRoom). The website shows this via the same
        -- violet "same identity" styling sixthRoom carries, taking
        -- visual priority over the plain amber "isolated" framing (see
        -- rooms.js's border-priority doc comment) -- accurate: this
        -- graph node has no traced exit of its own, but the real room
        -- it represents is not disconnected.
        sameRomIdentityAs = { "sixthRoom" },
        sameRomIdentityNote = "Reale ROM-Identitaetsregister sind byte-identisch mit sixthRoom (live bestaetigt, siehe sixthRoom's eigenen Kommentar) -- derselbe reale ROM-Raum. Dieser Graph-Knoten selbst hat keinen eigenen live erfassten Exit (er wird nur ueber die separate Bosskampf-Einleitung erreicht), aber der reale Raum dahinter IST verbunden (fourthRoom -> sixthRoom -> seventhRoom).",
        -- CONFIRMED (direct user report -- same discovery as fourthRoom's
        -- own doc comment above, see there for the verification
        -- methodology): this room is directly present in the bank6
        -- (8x8) world-map catalog at grid (row=7,col=4), i.e.
        -- mapTableBank6 record index row*8+col=60. Cell-by-cell
        -- real-file-offset comparison: 316/320 cells (98.8%) match this
        -- room's tileOffsets below -- even stronger than fourthRoom's
        -- own 67.5%, consistent with this being the room's "clean",
        -- unobstructed base capture. Directly east of fourthRoom's own
        -- (row=7,col=5) record. A 10-room neighbor sweep around this
        -- catalog position was also rendered and checked against every
        -- other known live-captured room -- confirmed (direct user
        -- correction that the other rooms are not on the world map)
        -- that none of these are further known rooms: the (7,6) record
        -- looks like a checkerboard courtyard, structurally similar to
        -- the willyRoom/secondRoom/thirdRoom family, but is 0/320
        -- real-file-offset matches -- a coincidental shared tile motif,
        -- not the same room; (7,7)'s weak 26.9%/34.1% overlap with
        -- eighthRoom/ninthRoom is likewise not a real identity, just a
        -- tileset-family overlap. startRoom/fourthRoom are the only two
        -- rooms this project has live-confirmed on the 8x8 world map so
        -- far. See events.md's "startRoom and fourthRoom are on the 8x8
        -- world map" entry for the complete trace.
        worldMapCatalogRecord = { table = "bank6", recordIndex = 60, row = 7, col = 4 },
        -- Real room size (see TileGridBackground.lua / rom-map.md's
        -- "real rooms are exactly one non-scrolling 20x16-tile screen"
        -- dynamic finding) -- explicit here (2026-08-09) so this entry
        -- has the same shape as `willyRoom` and both can share one
        -- general renderer instead of each hardcoding its own COLS/ROWS
        -- module constants.
        cols = 20,
        rows = 16,
        -- HYPOTHESIS, not decoded ROM collision data (none found -- see
        -- rom-map.md "Maps"): visual classification of tile IDs into
        -- floor/decoration (141-147, plus confirmed-blank 127) vs.
        -- wall/gate/border (everything else), used for per-tile
        -- movement collision (Player.lua's canMoveTo).
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
      -- CORRECTED (direct user catch: sprites render truncated). Root
      -- cause: LCDC bit 2 (OBJ size) is set -- 8x16 sprite mode is
      -- active, meaning every OAM entry draws a 16px-tall block using
      -- tile N (top) and N+1 (bottom), not the flat 8px tile this
      -- project's renderer had assumed. Only top halves were ever
      -- rendered before. Found each N+1 partner's live VRAM pattern and
      -- searched the ROM for its exact offset (real byte match -- the
      -- offsets aren't evenly strided, so guessing would be wrong).
      --
      -- Real player sprite: 2x2 tiles (16x16px) at OAM (Y=96,X=80/88)
      -- -> screen (72,80). Tile order (row-major): $00 $02 / $01 $03 --
      -- not sequential, hence CreatureSprite.fromOffsets (explicit
      -- list) rather than .static. Verified real facing: held each
      -- D-pad direction, read OAM tile order + attribute byte. DOWN/UP/
      -- LEFT are identical (tile $00 left column, attr 0). RIGHT swaps
      -- the column order and sets X-flip -- one piece of art, mirrored
      -- for right-facing, not a separate sprite per direction.
      --
      -- CORRECTED (same day): previously claimed "no walk-cycle
      -- animation" -- wrong. Direct user pushback prompted re-checking
      -- the raw VRAM byte CONTENT at the fixed tile index (not just the
      -- OAM tile index, which alone doesn't change) sampled every
      -- frame. It changes -- a DMA content-swap animation (some GB
      -- games redraw pixel data at a fixed OAM slot instead of
      -- switching which slot is referenced). See playerAnimation below.
      -- flipX is still the only per-direction mirroring mechanism
      -- (CreatureSprite.lua's draw) -- this correction is about
      -- whether it animates, not about facing.
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
      -- VERIFIED real walk-cycle animation, captured by sampling raw
      -- VRAM bytes (not OAM tile index) every frame while holding each
      -- direction. DOWN and LEFT/RIGHT each have an independently-
      -- captured 2-phase leg-cycle (4 GB frames/phase, steady-state
      -- over 40 frames for both); LEFT/RIGHT share identical tile bytes
      -- (mirrored via the same X-flip as idle) -- only one left/right
      -- data set is stored. UP showed no tile-content change in every
      -- clean (contact-free) window isolated -- walking up from spawn
      -- reaches the enemy quickly, and contact triggers its own,
      -- separate discovery (knockback + flicker reaction, not
      -- implemented yet, see docs/progress.md) that couldn't be fully
      -- untangled from a possible slow UP-specific animation in time --
      -- UP is left static (idle pose), an honest "not found, not
      -- disproven" rather than the original (wrong) "no animation" claim.
      --
      -- Structure per direction: top = the sprite's top-tile pair,
      -- legsB/legsC = the two alternating leg pairs. DOWN's top switches
      -- once (idle -> constant walking pose); LEFT/RIGHT's top DOES
      -- toggle in sync with the legs (2 distinct top poses) -- a genuine
      -- difference between the two, not simplified away.
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
          -- Both phases have their own top pose here (unlike DOWN) --
          -- topB looks superficially similar to the idle top but is a
          -- byte-for-byte different tile (exact-match ROM search, not
          -- assumed/reused from idle above).
          topB = { 0x21B00, 0x21B10 },
          legsB = { 0x21B20, 0x21B30 },
          topC = { 0x21B40, 0x21B50 },
          legsC = { 0x21B60, 0x21B70 },
        },
      },
      -- VERIFIED, CORRECTED after a more thorough re-trace (direct user
      -- request to find the ROM's own points rather than doing this
      -- empirically). The original capture sampled OAM position/
      -- attribute every frame but only checked VRAM tile content at 2
      -- points, assuming just 2 content blocks ("A"/"B") existed. A
      -- full per-frame content-offset trace found the swing actually
      -- cycles through 3 distinct content blocks (X, Y, Z) across its 4
      -- phases -- e.g. UP's phases are X,Y,X,Z, not two alternating
      -- blocks. This entry replaces the incomplete one.
      --
      -- Direct fix for a real gap (attacks previously applied damage
      -- with zero visual feedback). Pressing A activates 2 OAM slots
      -- (10/11), otherwise parked off-screen (x=248) while idle. dx/dy
      -- are captured OAM-space deltas from the player's own OAM
      -- position (cancels the shared -8/-16 OAM->screen offset). One
      -- incidental side effect of the capture: it revealed the idle/
      -- spawn facing is really "up" (Player.DEFAULT_FACING), not "down"
      -- as previously assumed.
      --
      -- HONEST LIMIT: whether the swing actually connects for damage was
      -- not re-derived from this capture (no confirmed enemy-HP RAM
      -- address exists -- see combat.md); hit detection is a separate
      -- mechanism (AttackSwing:getHitboxes, unaffected). A single
      -- A-press plays the swing once; holding A for 180 frames only
      -- ever played it once (no charge/power-gauge mechanic).
      attackSwing = {
        status = "VERIFIED",
        -- Real content blocks: pixel data loaded at the fixed OAM
        -- tile-ID slots 8/9 ("A" pair) and 10/11 ("B" pair) at a given
        -- moment -- a DMA content-swap mechanism (same technique
        -- driving the walk-cycle animation), not a tile-swap between
        -- two static sprites. Block Z is byte-for-byte identical to the
        -- thrust attack's own tiles (attackThrust below) -- the swing's
        -- final phase reuses the thrust's ready pose.
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
        -- Per-facing phase sequences (one A-press per direction,
        -- sampled every frame, cross-checked against a second
        -- independent full-content re-trace). content = which block
        -- (X/Y/Z) is active this phase, global to both L/R (both always
        -- use the same block at once). pair = which physical OAM
        -- tile-ID slot (A=8/9, B=10/11) this side renders -- swaps
        -- between phases, independently of the loaded content block.
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
      -- VERIFIED real thrust attack -- direct fix for a named gap (user
      -- report that the sword should thrust forward when attacking
      -- while moving). Confirmed live: pressing A while holding a
      -- direction produces a different animation from standing-still
      -- attackSwing -- shorter (12 frames, not 16), a single fixed pose
      -- repositioned in 3 phases (retract close -> thrust far out ->
      -- return), rather than a rotating arc. Confirmed at the
      -- tile-content level too: reuses attackSwing's own block "Z"
      -- verbatim -- the ROM doesn't store a separate thrust sprite, it
      -- reuses the swing's final pose as the thrust's single held frame.
      attackThrust = {
        status = "VERIFIED",
        -- Real per-frame motion (not coarse phases -- a 4-frame gradual
        -- retract, then instant jump-and-hold extend, then instant
        -- jump-and-hold return -- sampled every frame, not smoothed).
        -- One axis moves (facing direction), the other stays constant --
        -- both L/R share the same per-frame sequence on the moving
        -- axis, offset by a constant 8px on it, since a thrust doesn't
        -- rotate the blade like the swing does. Always block "Z" (see
        -- attackSwing.tileOffsets) -- the ROM's own art reuse.
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
        -- ATTEMPTED CORRECTION, REVERTED (same day): a live OAM re-scan
        -- found only 8 of these 16 tiles in each individual OAM
        -- snapshot (alternating $40/$42/$48/$4A + $44/$46/$4C/$4E, 16px
        -- apart -- same shape as the entrance-phase enemyDescent
        -- sprite), never catching the other 8 in any single sample.
        -- Tried switching to that 8-tile/16px-gap shape -- a live
        -- screenshot showed the creature rendered as two visibly
        -- separate chunks with floor showing through, worse than the
        -- original (unlike the entrance sprite, where the same fix did
        -- look right). Reverted to the original 4x4/16-tile/flush
        -- capture. Open question: the 16px-gap OAM snapshots are real,
        -- individually-observed facts -- possibly hardware relies on a
        -- persistence-of-vision effect (rapid alternation between two
        -- vertically-offset 8-tile halves) to look solid despite any
        -- single frozen frame showing only half -- not confirmed, not
        -- implemented, left as a bounded gap rather than a guess.
        tileOffsets = {
          0x2FE00, 0x2FE10, 0x2FE80, 0x2FE90, -- $40 $42 $48 $4A
          0x2FE20, 0x2FE30, 0x2FEA0, 0x2FEB0, -- $41 $43 $49 $4B
          0x2FE40, 0x2FE50, 0x2FEC0, 0x2FED0, -- $44 $46 $4C $4E
          0x2FE60, 0x2FE70, 0x2FEE0, 0x2FEF0, -- $45 $47 $4D $4F
        },
        screenX = 71,
        screenY = 34,
        -- VERIFIED (direct user reports the boss should have animations
        -- and the boss-intro sequence isn't right): live OAM-traced the
        -- gate-creature's patrol/hover cycle (Enemy.MOVEMENT_CYCLE)
        -- also toggles OAM attribute bit 5 (X-flip) every movement
        -- step -- attr 0x30 at one waypoint, 0x10 at the next,
        -- alternating, using the same 16 known tiles every time (the
        -- per-step Y-position change is already accounted for by
        -- MOVEMENT_CYCLE's own deltas, a separate fact from this flip
        -- bit) -- the "flapping" animation is a hardware X-flip mirror
        -- of the same art, not a second drawn frame and NOT a Y-flip
        -- (CORRECTED same day: the first implementation wired this into
        -- flipY by mistake -- bits 5/6 transposed -- fixed to flipX,
        -- see Enemy.lua/Field.lua/BattleIntro.lua). Enemy:isFlipped()
        -- exposes this as a simple movementIndex-parity toggle.
        flipXTogglesPerStep = true,
      },
      -- VERIFIED (same investigation, direct follow-up to the boss-
      -- intro report): the gate creature does not simply appear at its
      -- resting spot when the "Kaempfe!" box closes -- live OAM-traced
      -- the battle-intro sequence frame by frame and found the creature
      -- spawns near the top of the screen (the courtyard's barred gate,
      -- see battleIntro.gate above) and descends straight down (screen
      -- X constant at 64 -- CORRECTED, was documented as 80, a 16px
      -- error, see screenX doc comment below -- Y climbing 7->28 over
      -- ~20 frames, 4 steps of ~5 frames each) using a second,
      -- previously-uncaptured 4x2 tile block (CORRECTED, was documented
      -- as 4x4 -- see enemySprite's own doc comment above for the same
      -- mistake, found the same day) -- not the same tiles as the
      -- resting/patrol pose above. Confirmed via the same exact-16-byte
      -- ROM search method as enemySprite.tileOffsets: every one of the
      -- 8 top-tile IDs matches exactly one ROM location, contiguous in
      -- bank 11 immediately after the resting-pose block.
      -- Once the descent reaches the patrol's own Y range (~frame 20),
      -- OAM switches over to the already-known enemySprite.tileOffsets/
      -- MOVEMENT_CYCLE patrol -- this block is only the one-time
      -- gate-to-patrol transition, not an alternate ongoing pose.
      enemyDescent = {
        status = "VERIFIED",
        bank = 11,
        cols = 4,
        rows = 4,
        -- ROOT CAUSE FOUND (direct user instruction to check the ROM's
        -- draw code, not guess): read the real ROM OAM-writer code
        -- (traced live via the shadow-OAM buffer at $C000) and checked
        -- LCDC at the descent -- bit 2 (OBJ size) is set, 8x16 sprite
        -- mode. In that mode each OAM tile index has its LSB forced to
        -- 0 and draws that tile as the top 8px plus tile|1 as the
        -- bottom 8px automatically, with no CPU-visible second OAM
        -- write. The previous 8-tile/cols=4,rows=2 capture only ever
        -- recorded the top half of each OAM row and never the bottom
        -- halves hardware appends on its own -- the exact cause of the
        -- missing-rows symptom: the bottom-half tiles were never in
        -- tileOffsets at all, not a spacing problem. Every attempted
        -- rowSpacing fix was addressing the wrong variable.
        --
        -- Full 4x4/16-tile grid below uses the same interleaved ROM
        -- layout already verified for enemySprite above (pairs of
        -- columns, top-half block then bottom-half block, contiguous
        -- in bank 11 right after that sprite's 0x2FE00-0x2FEFF block)
        -- -- confirmed directly: all 16 offsets contain distinct,
        -- non-zero tile data, and the 8 top-half offsets exactly match
        -- this table's previous (correct) values, so only the
        -- bottom-half offsets were newly added:
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
        -- screenX stays constant at 64 through all 4 descent frames
        -- (confirmed live) -- the earlier 80 value was a 16px error,
        -- unrelated to and not affected by the 8x16-mode fix above.
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
      -- VERIFIED (direct response to a user correction that the
      -- explosion definitely exists -- an earlier pass this same
      -- session wrongly trusted a stale negative result, see
      -- combat.md's "Explicit negative result" entry, which only ruled
      -- out one despawn call chain and left the $D3EC event-queue
      -- consumer untraced). Live-traced the gate creature's own death
      -- sequence frame by frame and found a visual effect the earlier
      -- OAM-content check had missed: the creature's six body-part OAM
      -- pairs (tiles 0x38/0x3a/0x3c/0x3e, the same tiles combat.md's
      -- hit-reaction-pose note already named) do not just vanish --
      -- their screen positions scatter outward to six different
      -- corners of the room over ~85 frames (confirmed via a direct
      -- screenshot at frame 86: six round part-clusters visibly spread
      -- apart), then all six vanish simultaneously (OAM entry count
      -- drops to 0 at frame 86, matching the already-documented $0AE3
      -- despawn routine's "clear the six body-part slots" behavior --
      -- that routine's own negative result, "no new tile ID is ever
      -- loaded," is still correct: this is the creature's own existing
      -- body-part art being repositioned, not a dedicated explosion
      -- sprite). Net effect on screen: a "body bursts apart into
      -- pieces, then all pieces vanish" animation -- accurate for what
      -- a player sees, even though the mechanism is body parts
      -- scattering, not a dedicated particle effect.
      --
      -- HONEST LIMIT: the 4 body-part tiles' file offsets are not
      -- uniquely confirmed -- the exact 16-byte search returned 2-3
      -- matches each (not this project's usual "exactly one" bar), in
      -- two internally-consistent clusters (bank 8 around 0x23db0 and
      -- bank 9 around 0x27900, both with the same relative tile
      -- spacing) -- the art is plausibly duplicated across banks
      -- (common on MBC2 titles that need the same graphics reachable
      -- from more than one bank-switch
      -- context), not a search bug. Bank 8's cluster is used below
      -- (closest to the other battle-related graphics already sourced
      -- from bank 8) -- a reasonable choice, not a uniquely-proven one;
      -- if the art looks wrong, the bank 9 cluster (0x27900/0x27910/
      -- 0x27940/0x27950) is the other candidate to try.
      --
      -- Screen positions for each of the 6 part-pairs, sampled at the
      -- frame boundaries the live OAM trace held steady on (5-frame
      -- steps) -- dx/dy are captured deltas from each part's starting
      -- position (the creature's resting pose), not an invented
      -- starburst.
      enemyDeath = {
        status = "VERIFIED (positions + real 2-frame debris shape)",
        bank = 8,
        -- CORRECTED (direct user report the lower half seems to be
        -- missing from each sprite during the explosion): the old "6
        -- body-part pairs" framing was never cross-checked against a
        -- fresh live capture -- these 4 tile offsets were being drawn
        -- as one static 2x2 (16x16) sprite at each scatter position. A
        -- live OAM trace (sampled every 8 frames through the whole
        -- death sequence) found hardware never shows all 4 tiles
        -- together: each of the 6 flying OAM pairs is only two tiles
        -- wide, one tile tall ($38/$3a or $3c/$3e, never all four at
        -- once), alternating over time -- a 2-frame debris animation,
        -- not a static double-height block. frameA/frameB below are
        -- those 2 captured frames; Field.lua alternates between them.
        frameA = { 0x23db0, 0x23dc0 }, -- real tiles $38 $3a
        frameB = { 0x23df0, 0x23e00 }, -- real tiles $3c $3e
        -- Live-confirmed (not a bug): the same OAM trace checked OBP1
        -- through the whole death sequence -- reads $D0 throughout,
        -- this game's already-implemented default sprite palette (see
        -- spritePalette.registerValue above, same value) -- already
        -- what CreatureSprite.fromOffsets falls back to when no
        -- explicit palette is passed. A direct user suspicion (there
        -- should be a palette effect over it) was checked and found not
        -- needed: no separate death-flash palette exists, the ordinary
        -- default already matches. (The enemy's pre-death resting pose
        -- DID read a different value, $3F -- a separate, not-yet-
        -- investigated fact about its idle rendering, out of scope here.)
        totalFrames = 86, -- real: OAM entry count hits 0 exactly here
        -- 6 body-part pairs, each {dx, dy} -- the captured delta from
        -- the creature's resting top-left position (frame 0) to its
        -- final scattered position (frame 81, last sample before the
        -- frame-86 vanish) -- a straight-line interpolation over
        -- totalFrames, not a reproduction of every intermediate jump
        -- (the live capture shows each part taking a slightly irregular
        -- multi-step path -- an honest simplification, not a claim of
        -- frame-exact fidelity).
        parts = {
          { dx = 0, dy = 0 }, { dx = 27, dy = -3 }, { dx = -23, dy = 21 },
          { dx = -1, dy = 16 }, { dx = -14, dy = -10 }, { dx = -1, dy = -43 },
        },
      },
      -- VERIFIED real hit-flash -- direct fix for a named gap (the enemy
      -- sprite should flash briefly on being hit). Traced live: OBP1
      -- (the enemy's palette register, OAM attribute bit 4 confirms
      -- OBP1 not OBP0) briefly changes from $D0 to $BF for ~1 frame
      -- right as a hit lands, then reverts -- a palette-swap flash, not
      -- an invented tint. Decoded the same way as spritePalette: pixel
      -- indices 1 and 2 (normally white/light-gray) both flash to shade
      -- 3 (black), index 3 (normally black) flashes to shade 2 (dark
      -- gray) -- an almost-solid black silhouette, not a color inversion.
      enemyHitFlash = {
        status = "VERIFIED",
        registerValue = 0xBF,
        shadeIndices = { 3, 3, 3, 2 },
        frames = 2, -- real observed flash was ~1 real frame; held 2 here for visibility
      },
      creatureSpritesBank9 = {
        -- CORRECTED: the earlier "VERIFIED" status overclaimed
        -- uniformity. A screenshot comparison showed the bank does not
        -- decode as coherent tile art starting at tile 0 -- there's a
        -- run of noise-looking data first, with sprite-like art
        -- appearing only well into the bank. Real bytes, but "this
        -- whole bank is clean graphics" wasn't established -- kept
        -- PARTIALLY VERIFIED and not used as a default sprite source
        -- (Field.lua uses bank 10 instead).
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
      -- NOT -- no live gameplay trigger into this area was ever found.
      -- `src/app/states/RoomExplorer.lua` (F8 from Field.lua) remains
      -- the clearly-marked dev-only way to browse all 6 without any
      -- invented door.
      --
      -- POLICY CHANGE 2026-08-19, then RETRACTED same day: a linear
      -- 8->9->10->11->12->13 engineering-choice door chain was added
      -- here on direct user instruction ("Regel für unknownRoomA
      -- bewusst lockern... voll spielbare Version"), each door
      -- individually landing-spot-checked against `floorTileIds`. It
      -- was pulled back after a direct, blunt user report ("alles nach
      -- dem 7. raum ist müll") triggered a full re-audit: `floorTileIds`
      -- itself mismatched this project's own stated collision-byte
      -- classification rule for 42 of 82 tiles actually used across
      -- these 6 rooms, and rebuilding it by applying that rule fully
      -- and mechanically (see `UNKNOWN_ROOM_A_FLOOR_TILE_IDS`'s own
      -- doc comment above) revealed a checkerboard artifact with almost
      -- no coherent, 2x2-footprint-walkable area in most of the 6
      -- rooms -- 2 of 6 had ZERO connected walkable footprint at all.
      -- The single-cell landing-spot check used at the time was too
      -- narrow to catch this (it never checked the real 2x2/16x16
      -- footprint `TileWalkability.build` actually uses, nor did any
      -- in-game walk test happen before the chain was reported done).
      -- CONCLUSION: the collision-byte heuristic does not hold for
      -- unknownRoomA's own metatile table, so no honest door can be
      -- placed here yet -- exactly the situation this doc comment's
      -- very first version already anticipated before being relaxed.
      -- The room CONTENT (tile-art grids) is untouched and stays real,
      -- decoded ROM data; only connectivity is withdrawn again, back to
      -- none, until a trustworthy floor source exists for this specific
      -- metatile table.
      unknownRoomA_8 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 8,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[8],
      },
      unknownRoomA_9 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 9,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[9],
      },
      unknownRoomA_10 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 10,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[10],
      },
      unknownRoomA_11 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 11,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[11],
      },
      unknownRoomA_12 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 12,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[12],
      },
      unknownRoomA_13 = {
        status = "VERIFIED (room content only); no connectivity -- see the block doc comment above for the 2026-08-19 add-then-retract story",
        romRoomSelector = 13,
        cols = 20, rows = 16,
        tileOffsets = UNKNOWN_ROOM_A_TILE_OFFSETS,
        floorTileIds = UNKNOWN_ROOM_A_FLOOR_TILE_IDS,
        grid = UNKNOWN_ROOM_A_GRIDS[13],
      },
      -- `worldMapRoom_131`/`worldMapRoom_132`: real bank-5 world-map
      -- catalog records 131/132 -- see `WORLD_MAP_ROOM_131_GRID`'s own
      -- doc comment above for the full evidence trail (100% tile-exact
      -- edge match found via a systematic full-grid scan, zero internal
      -- collision conflicts, large non-fragmented footprint-reachable
      -- regions on both sides, visually confirmed continuous). This is
      -- a TRIAL, deliberately the single most-defensible candidate of
      -- the 6 perfect-match pairs found, not a claim the others are
      -- wrong -- see that doc comment for why the other 5 were left
      -- unwired. STRUCTURALLY-DERIVED, meaningfully stronger evidence
      -- than `unknownRoomA`'s own ENGINEERING-CHOICE doors (those had
      -- no edge-match evidence at all, pure invented placement) -- but
      -- still NOT independently ground-truth-verified the way a live-
      -- reachable room's collision table is, since no gameplay reaches
      -- any bank5/6 catalog room. Door placed on the one row range (15-
      -- 16, fully open on both sides in both rooms) that lets landing
      -- spots sit well inside each room rather than right at the seam,
      -- avoiding the "landing inside the exit zone" bounce-loop bug
      -- this project already found and fixed once this session.
      -- Reachable today only via the same dev-only teleport machinery
      -- (`MYSTICQUEST_VICTORY_START_ROOM=worldMapRoom_131`) already used
      -- to verify every other room this session -- deliberately NOT
      -- wired to any currently-reachable room via a new engineering-
      -- choice entry door; that would be a separate decision, not made
      -- here.
      worldMapRoom_131 = {
        status = "STRUCTURALLY-DERIVED (100% tile-exact edge match with worldMapRoom_132, see doc comment above); floor/collision meaning for this metatile table is NOT independently verified",
        bank5RecordIndex = 131,
        cols = 20, rows = 16,
        tileOffsets = WORLD_MAP_ROOM_131_TILE_OFFSETS,
        floorTileIds = WORLD_MAP_ROOM_131_FLOOR_TILE_IDS,
        grid = WORLD_MAP_ROOM_131_GRID,
        exits = {
          {
            status = "STRUCTURALLY-DERIVED, not ROM-live-trigger-confirmed (see doc comment above)",
            zone = { xMin = 152, xMax = 160, yMin = 112, yMax = 128 },
            transition = { type = "cut" },
            targetRoom = "worldMapRoom_132",
            -- row15,col6 (1-based) in worldMapRoom_132 -- real floor,
            -- footprint-verified, well inside the room (not at the seam).
            landingX = 48, landingY = 128,
          },
        },
      },
      worldMapRoom_132 = {
        status = "STRUCTURALLY-DERIVED (100% tile-exact edge match with worldMapRoom_131, see doc comment above); floor/collision meaning for this metatile table is NOT independently verified",
        bank5RecordIndex = 132,
        cols = 20, rows = 16,
        tileOffsets = WORLD_MAP_ROOM_132_TILE_OFFSETS,
        floorTileIds = WORLD_MAP_ROOM_132_FLOOR_TILE_IDS,
        grid = WORLD_MAP_ROOM_132_GRID,
        exits = {
          {
            status = "STRUCTURALLY-DERIVED, not ROM-live-trigger-confirmed (see doc comment above)",
            zone = { xMin = 0, xMax = 16, yMin = 112, yMax = 128 },
            transition = { type = "cut" },
            targetRoom = "worldMapRoom_131",
            -- row15,col15 (1-based) in worldMapRoom_131 -- real floor,
            -- footprint-verified, well inside the room (not at the seam).
            landingX = 120, landingY = 128,
          },
        },
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
      -- record decodes to one full, coherent room by itself (tile_entropy
      -- 1.0-1.8 bits, confirmed for every rendered record).
      --
      -- SCOPE CORRECTED: "room-composition" above means the structural
      -- decode (RLE stream -> 80 metatile indices -> a full grid) is
      -- verified. It does NOT mean the picture uses the correct
      -- metatile table for records other than 8-13
      -- (unknownRoomACandidates.rooms) -- see that table's own
      -- "CORRECTED" doc comment.
      --
      -- UPGRADED (same day, following the map-header hint): all 256
      -- records now use genericCatalogMetatileTableFileOffset (see
      -- unknownRoomACandidates's own doc comment), a structurally-
      -- justified derivation from roomSelectorTable record 0 --
      -- corroborated against the FFA-Disassembly project's documented
      -- "one tileset per map" architecture, not a guess. Not
      -- independently ground-truth-verified (no live gameplay reaches
      -- these rooms).
      status = "VERIFIED (encoding + room-composition); tile ASSIGNMENT now uses genericCatalogMetatileTableFileOffset " ..
        "(structurally-derived default, see the UPGRADED note above) -- not independently ground-truth-verified",
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
      --
      -- CORRECTED (direct user pushback that this must have different
      -- tiles, something in the pipeline must define which): the code
      -- that copies a GFX-tile's pixel bytes into VRAM was found, fully
      -- disassembled, and closed this pass -- rom-map.md's "$D070's real
      -- populator" section had already found the allocator ($1BA1) but
      -- left its own tail as an open item. Finished live (single-step
      -- trace synchronized to a live VRAM-allocation burst during the
      -- willy-exchange dialogue): the real formula is
      --   fileOffset = bank*0x4000 + ((rawGfxByte*16 + $D390:$D391) - 0x4000)
      -- with bank a literal code constant (0x0C=12, or 0x0B=11 if the
      -- computed address overflows into bit7 of H -- a disassembled
      -- address-range fixup, $1BF5-$1C15), switched in via the MBC
      -- bank-select register (found by finishing the trace into the
      -- queue-drain routine, $2D57-$2DF4, run under a per-frame
      -- LY-scanline budget -- $1BA1's tail only enqueues via $2DF5, it
      -- doesn't copy immediately). Exact-matched against known-good
      -- ground truth: willyRoom's own live-confirmed $D390:$D391=0x6000,
      -- raw byte 0x1b -> 12*0x4000 + ((0x1b*16+0x6000)-0x4000) = 0x321b0
      -- -- byte-for-byte identical to willyRoom's own independently-
      -- verified tileOffsets[0x97]=0x321b0.
      --
      -- Applying this same formula to roomSelector 0/1's own real
      -- $D390:$D391 (=0x4000) gives 0x30000, not 0x32000 -- the old
      -- value here was reusing willyRoom's own pixel-pool base
      -- (roomSelector 2-6's family, $D390:$D391=0x6000) for the
      -- 384-room catalog's default, a previously-undetected mismatch:
      -- the catalog's genericCatalogMetatileTableFileOffset (the
      -- metatile-definition table) was always correctly roomSelector-
      -- 0/1-based, but the raw pixel pool it was combined with was
      -- roomSelector-2-6's -- two different ROM "maps" mixed together
      -- (the external FFA-Disassembly project's documented format has
      -- exactly two per-map pointers, tilesetGfxOutdoor +
      -- metatilesOutdoor -- this project had a correct value for one
      -- and the wrong one for the other).
      --
      -- Empirically re-rendered every spot-checked sanity record
      -- (0/128/200/240/255) plus the disputed seventhRoom/eighthRoom/
      -- ninthRoom records (220/236/237) with the corrected 0x30000
      -- base: every one changed from a generic, oddly-repetitive
      -- "bookshelf/chain-link dungeon" look (an artifact of reusing
      -- willyRoom's wrong-family art) to a coherent, distinct scene --
      -- record 0 is a wooden gate + grass + bushes + mountains (an
      -- outdoor town/wilderness entrance, not a dungeon corridor),
      -- 220/236/237 show trees/grass/water/roads. Dramatically more
      -- convincing than any alternate pointer tried in the earlier
      -- (now-superseded) pass. See events.md for the full trace.
      --
      -- HONEST SCOPE: this closes the "which tileset" question for the
      -- roomSelector-0/1 family (bank 5/6/7's shared default).
      -- unknownRoomACandidates's own tilesetFileOffset (roomSelector
      -- 8-13 family, $D390:$D391=0x7000, the same formula would predict
      -- 0x33000) was also re-tested this pass -- inconclusive (both
      -- 0x32000 and 0x33000 render equally plausible, structurally-
      -- identical dungeon art) -- left unchanged, flagged as a
      -- separate open question rather than force-changed on weak
      -- evidence. Still no live gameplay reaches any of these 384
      -- catalog rooms -- a code-derived, exact-match-verified formula,
      -- not a live-gameplay confirmation the way willyRoom's tiles are.
      tilesetFileOffset = 0x30000,
    },

    -- A SECOND, independently-found map/room-block pointer table --
    -- found while looking for a general way to decode rooms beyond the
    -- exhausted 16-entry roomSelectorTable (direct user instruction to
    -- be able to decode all rooms). VERIFIED the same way bank 5's
    -- table was originally verified (see mapTable above): the 4-byte
    -- per-map header immediately before the pointer table (00 04 08 08
    -- at file 0x18000, encodingMode=0/RLE, rleLength=4) matches this
    -- ROM's documented format, just with a different rleLength.
    -- Applying it: 128 monotonic, strictly-increasing, valid-CPU-
    -- address pointer entries follow at file 0x18004 = 64 (headerPtr,
    -- dataPtr) record pairs -- a clean round number. All 64 records
    -- decode cleanly (rleLength=4) to exactly 80 values -- the same
    -- metatile-grid size as bank 5's records, not the 8x8=64 the
    -- header's 3rd/4th bytes would naively suggest (those bytes
    -- evidently mean something else for this table -- flagged, not
    -- force-fit).
    -- Visually + quantitatively confirmed, all 64 records: rendered
    -- every one through the known shared bank-8 metatile pool and
    -- MapTable's verified direct tileset formula -- tile_entropy for
    -- every room: 1.08-1.63 bits, inside the ~1.0-1.8 band already
    -- established for unknownRoomA's 6 rooms, zero outliers toward
    -- blank or noise. Two examples eyeballed directly (record 0, 21):
    -- unmistakable, structured dungeon/shrine art.
    --
    -- SCOPE CORRECTED: "visually + quantitatively confirmed" above
    -- means real, non-noise GB tile art, nothing more. It does NOT mean
    -- these 64 records use the semantically correct metatile table
    -- (only unknownRoomACandidates's own 6 bank-5 records have that
    -- independently confirmed -- see that table's own doc comment).
    -- Applying the same table to these 64 bank-6 records was always
    -- the same unverified placeholder -- direct visual review (user
    -- report: "total off") found it doesn't look right compared to the
    -- 6 actually-confirmed rooms.
    --
    -- UPGRADED (same day, following the map-header hint): all 64
    -- records now use genericCatalogMetatileTableFileOffset (see
    -- unknownRoomACandidates's own doc comment) -- a structurally-
    -- justified derivation from roomSelectorTable record 1 (bank6's own
    -- "map"), cross-checked against the FFA-Disassembly project's
    -- documented "one tileset per map" architecture. Not independently
    -- ground-truth-verified.
    mapTableBank6 = {
      status = "VERIFIED (table location + encoding + all 64 records real-render as non-noise GB art); " ..
        "tile ASSIGNMENT now uses genericCatalogMetatileTableFileOffset (structurally-derived default, see the " ..
        "UPGRADED note above) -- not independently ground-truth-verified",
      bankFileStart = 0x18000,
      bank = 6,
      pointerTableFileOffset = 0x18004,
      recordCount = 64,
      -- Shares the same tileset as bank 5's table -- both render
      -- coherently against it, cross-confirming this as the right base
      -- for the shared bank-8 metatile pool's GFX-tile bytes.
      --
      -- CORRECTED: same fix/reasoning as mapTable's own dated
      -- correction above (the code-derived, exact-match-verified
      -- bank*0x4000 + ((rawByte*16+$D390:$D391)-0x4000) formula) --
      -- roomSelector 1 (bank6's "map") shares roomSelector 0's
      -- $D390:$D391=0x4000, so the same corrected 0x30000 applies here.
      tilesetFileOffset = 0x30000,
    },

    -- A THIRD map/room-block table -- bank 7, the other encoding this
    -- ROM's per-map header names (encodingMode=1, "Templated" -- see
    -- MapTable.readMapHeader's own doc comment). Found the same way as
    -- mapTableBank6: 01 04 08 08 at file 0x1C000.
    --
    -- CRACKED end to end (direct user instruction to keep drilling
    -- until finished -- see rom-map.md's "bank 7 Templated revisited,
    -- CRACKED" section). Structural shape (all boundaries land exactly,
    -- zero slack): 4-byte header, then a 2-byte base-room template
    -- pointer (0x411e -> file 0x1C11E), then a 24-byte per-map door-
    -- data block (bytes captured, bit layout not decoded), then the
    -- usual 64-record (headerPtr,dataPtr) pointer list starting at file
    -- 0x1C01E -- ending exactly at the template pointer's own file
    -- offset, zero gap. RLE-decoding the template (rleLength=4)
    -- produces exactly 80 tiles, landing precisely on record 0's own
    -- header pointer -- a second independently-derived boundary match.
    --
    -- Each record's data blob is a diff against that shared base
    -- template (MapTable.applyTemplatedDiff): a 4-byte per-record
    -- prefix (small values, not decoded -- plausibly door/exit-flag
    -- data) followed by (value, position) byte pairs, position =
    -- (row<<4)|col, terminated by 0xFF. Verified against all 64
    -- records: 566/566 diff positions decode to valid (row,col) pairs
    -- (zero exceptions), and every reconstructed room renders as
    -- structurally coherent, visually distinct dungeon art
    -- (tile_entropy 1.30-1.40 bits, zero outliers).
    --
    -- Tile assignment uses the same genericCatalogMetatileTableFileOffset
    -- default as mapTable/mapTableBank6 (not independently ground-truth-
    -- verified -- no playthrough reaches these rooms).
    --
    -- COLLISION CRACKED (direct user instruction to continue with door
    -- and collision): RoomFloorLayout.buildCollisionGridFromMapTableRecord
    -- dispatches to buildCollisionGridFromTemplatedMapTableRecord for
    -- this table, same per-metatile collision-byte lookup as bank 5/6 --
    -- live-verified via real love . screenshots, same honest
    -- "extrapolated bank-5/6 rule, not ROM-confirmed" caveat.
    --
    -- DOOR BYTES: real structural progress, still not decoded. Each
    -- record's 4-byte prefix is a clean 8-value alphabet across all 256
    -- bytes ({0,1,2,5,8,9,12,13}, zero outliers): bits0-1 is always
    -- 0/1/2 (never the 4th combination), matching the external FFA-
    -- Disassembly doc's claimed "open/closed/wall" 3-state layout;
    -- bits2-7 is always 0-3 (240/256 bytes are 0). The map-level 24-byte
    -- block doesn't share this pattern -- genuinely different data. See
    -- rom-map.md for the full statistical breakdown. Not implemented as
    -- door/exit behavior: no live bank-7 gameplay exists to confirm
    -- which byte is which direction or what each value means.
    mapTableBank7 = {
      status = "VERIFIED end to end (Templated/mode-1 structure + base-template/diff tile decode AND " ..
        "collision); tile ASSIGNMENT uses genericCatalogMetatileTableFileOffset like " ..
        "mapTable/mapTableBank6, not independently ground-truth-verified against live gameplay; " ..
        "door-data bytes (map-level 24 + per-record 4) show a real, clean statistical structure " ..
        "(see doc comment) but remain semantically undecoded -- no live gameplay to confirm against",
      bankFileStart = 0x1C000,
      bank = 7,
      -- The record-pointer list itself starts at +30 (4-byte header +
      -- 2-byte template pointer + 24-byte door data), not +4 like
      -- mapTable/mapTableBank6 -- a Templated-mode-specific structural
      -- difference, not a typo.
      pointerTableFileOffset = 0x1C01E,
      recordCount = 64,
      -- Shares the same tileset as bank 5/6's tables.
      --
      -- CORRECTED: same fix as mapTable/mapTableBank6 above -- kept
      -- consistent with them (this table was always assumed to share
      -- their tileset, never independently derived), even though which
      -- roomSelector family bank 7 corresponds to is honestly less
      -- established than bank 5/6's own roomSelector-0/1 identification.
      tilesetFileOffset = 0x30000,
    },

    -- The real room-connectivity table -- see docs/reverse-engineering/
    -- rom-map.md "BREAKTHROUGH: the real room table, found" and "The
    -- bank-8 room table, fully documented". VERIFIED via both a static
    -- ROM dump and two independent live CallTracer traces (the post-
    -- victory staircase, and a separate pre-combat transition) hitting
    -- the exact same code ($04138->$02B70->$026DC->$01AF3, bank-
    -- resolved). A real, general, roomSelector-indexed table the ROM
    -- uses to load rooms -- not this project's invention, and not the
    -- long-searched-for bank-5 table (purpose remains unidentified).
    -- Table length (16, not a full byte range) is itself derived: byte
    -- 6 of each record must be a valid MBC bank number, and this ROM
    -- has exactly 16 banks -- record 16 onward immediately produces
    -- impossible bank numbers, confirming the table's real end.
    --
    -- src/import/RoomSelectorTable.lua is the generic decoder; nothing
    -- about the 11-byte stride or field meanings is hardcoded here,
    -- only real offsets/values.
    roomSelectorTable = {
      status = "VERIFIED",
      bank = 8,
      fileOffset = 0x20000,
      recordLength = 11,
      recordCount = 16,
      -- Per-record field layout (byte offsets within each 11-byte
      -- record), from the live-traced $026DC lookup routine:
      --   bytes 0-1: 16-bit LE offset, added to $4000 to form the HL
      --     parameter to $01AF3 (committed to WRAM $D390/$D391).
      --   byte 2: not consumed by $026DC/$01AF3 -- meaning unknown.
      --   bytes 3-4: 16-bit LE value, the DE parameter to $01AF3 --
      --     committed to WRAM $D392/$D393, the already-known room
      --     tile-source pointer.
      --   byte 5: not consumed by $026DC/$01AF3 -- meaning unknown.
      --   byte 6: the dynamic MBC bank number, committed to WRAM $C3F0
      --     (the already-known trampoline bank-select flag).
      --   bytes 7-8: 16-bit LE pointer, staged to WRAM $C3F2/$C3F3, THEN
      --     dereferenced by $026DC's own tail: 4 bytes are copied from
      --     it into $C3F8-$C3FB (a stream-cursor read, pointer advanced
      --     past them afterward). CONFIRMED (direct user hypothesis
      --     that these might be "room states"): $C3F8 is the already-
      --     known gate/enable flag $235B (the door-open check) reads
      --     before proceeding -- the real mechanism giving each
      --     roomSelector its own per-instance state, even though
      --     $C3F9-$C3FB's individual roles weren't traced.
      --   bytes 9-10: never read by $026DC/$01AF3 in this trace --
      --     meaning unknown, real bytes, not guessed at.
      --
      -- FOLLOW-UP (pure static disassembly): $235B(A=direction), when
      -- its own $C3F8 flag is nonzero, switches to this record's byte 6
      -- dynamic bank and reads a small per-direction 16-bit value from
      -- ptr+2+selector*2 (selector 0-3, chosen by which bit of A is
      -- set) -- a traced read from the dynamic bank (bank 5 for records
      -- 0/9). That value is fed into $05BB (the already-known
      -- "$D392:$D393 + A*6" source-address formula) as an INDEX, not
      -- used as tile data directly -- the tile bytes drawn always come
      -- from hardcoded bank 8 via $D392/$D393, same pipeline as every
      -- other confirmed room/patch draw. Reframes bank 5's likely
      -- purpose: small per-exit index/reference metadata selecting
      -- which bank-8 tile-patch block to reveal, not raw room tile art
      -- -- a plausible explanation for why bank 5's 255 RLE records
      -- never matched any known room's pixels. Deliberately static-only
      -- this pass; see rom-map.md for the full call chain and open ends.
      --
      -- RESOLVED (same day, direct user instruction to resolve the open
      -- questions): $235B/$22FE are a confirmed matched "open exit"/
      -- "close exit" script opcode pair, called with a one-hot
      -- direction arg -- exhaustively found via whole-ROM scan, exactly
      -- 4 call sites each: A=0x04->North, A=0x02->West, A=0x01->East,
      -- A=0x08(default)->South. This mechanism only ever runs from
      -- room-script bytecode, never generic per-frame code. Also
      -- exhaustively searched all 5 callers of $26DC: 3 hardcode
      -- index=7; the other 2 derive the index dynamically from a
      -- script/data-cursor byte or an inherited register argument --
      -- neither literally hardcodes 0 or 9 anywhere. So index 0/9
      -- selection is genuinely script/data-driven, not a fixed code
      -- branch -- explains why live play never observed it. See
      -- rom-map.md "Resolving the 3 open ends" for the full trace.
      --
      -- Cross-reference to this project's own implemented rooms
      -- (graphics above), live-confirmed (marked "live") or inferred
      -- from the shared tile-source pointer alone (marked "static-
      -- only", a real but less rigorously confirmed link):
      --
      -- dynamicBank (read directly from byte 6 of each 11-byte record
      -- via a file-level dump -- not live-traced, purely static): the
      -- MBC bank each roomSelector switches in before resolving its ptr
      -- field. Full column: 5,6,7,7,7,7,7,7,6,5,6,7,7,7,6,6. Recorded
      -- here because it closes an exhaustive static search for bank 5's
      -- only access point in the whole ROM: indices 0 and 9 are the
      -- only two places anywhere that ever switch bank 5 in (confirmed
      -- by two independent whole-ROM byte-pattern scans finding zero
      -- hardcoded bank-5 switches elsewhere).
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

    -- VERIFIED (direct user instruction to fully solve the map -- see
    -- rom-map.md "MILESTONE 3 SOLVED" for the full trace): the general
    -- room-floor-layout decompression pipeline. Ported to a real Lua
    -- decoder -- src/import/RoomFloorLayout.lua, cross-checked end to
    -- end in tests/import/room_floor_layout_test.lua (not just one-off
    -- Python scratch verification). src/import/MapTable.lua still
    -- separately implements the older, bank-5-specific RLE scheme (a
    -- different table shape, see rom-map.md "Bank 5, revisited").
    --
    -- Per room (indexed via the same roomSelectorTable record used for
    -- the metatile table below):
    --   1. targetPointer + dynamicBank point to a metatile table:
    --      6-byte records [gfxTileTL, gfxTileTR, gfxTileBL, gfxTileBR,
    --      collision, interaction] (matches the FFA-Disassembly
    --      project's documented US-ROM format exactly). The 4 GFX-tile
    --      bytes aren't final tile IDs directly -- each must be
    --      remapped through the live WRAM $D070-$D16F table (populated
    --      at runtime, not ROM-static -- this project used a targeted
    --      live dump for willyRoom; a generic extractor needs the same
    --      per-room, or to find $D070's own real populator).
    --   2. A separate compressed layout stream (found via $2740's
    --      $C3F8-gated $25F6/$25D1 resolvers, indexed by $C3FB and the
    --      roomSelector's own ptr field -- for willyRoom this resolves
    --      to file offset 0x1DA50, bank 7, a different bank than the
    --      metatile table's bank 8) holds the room's per-cell metatile-
    --      index grid, RLE-compressed: bit 7 set means "write byte &
    --      0x7F, repeated $C3F9 times" (live-confirmed $C3F9=4 for
    --      willyRoom -- a per-room run-length, not a fixed constant);
    --      bit 7 clear is a literal metatile index. $242B is the ROM
    --      decompressor, writing 80 output bytes (willyRoom's 8x10
    --      metatile grid, stride 10) into WRAM $C350.
    --   3. Combine: for grid position (metatileRow, metatileCol), look
    --      up the decompressed index, resolve its metatile-table
    --      record, and place the 4 GFX tiles (D070-remapped) into the
    --      final pixel grid at (metatileRow*2, metatileCol*2).
    --   4. The 4 door/exit graphics (N/W/E/S) are deliberately not part
    --      of this base layout (the compressed stream encodes blank
    --      placeholders there) -- they're drawn by the separate,
    --      already-documented $235B/$225D/$2281/$056C exit-reveal
    --      mechanism, confirmed by an exact match: rendering willyRoom
    --      via steps 1-3 alone reproduces 288/320 tile positions
    --      exactly, and the remaining 32 fall precisely inside the 4
    --      known door zones (8 tiles each).
    --
    -- Cross-validated end to end against graphics.willyRoom.grid --
    -- not a hypothesis, a working, live-verified decode.
    --
    -- GENERALIZED (same day, continuing the world-scope push): the
    -- Milestone-3 generalization proof, closed. unknownRoomB
    -- (roomSelectors 14-15, the black-wipe transition backdrop) was
    -- reached via a real, transition-triggered room load (not forced),
    -- single-stepped to its own live $242B call to find its layout-
    -- stream source. This project's own unchanged RoomFloorLayout.
    -- decodeLayoutStream function, pointed at that address, reproduces
    -- the live WRAM result exactly (80/80 bytes = 12) -- the pipeline
    -- mechanism itself is now proven, with real code against real ROM
    -- bytes, to generalize to a genuinely different room. The room's
    -- content happens to be trivial (a uniform backdrop tile, matching
    -- its role), but the mechanism proof is exactly what Milestone 3's
    -- own DoD needed.
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
        -- Live-confirmed via a genuine transition (the post-boss black
        -- wipe), not forced -- see rom-map.md's "unknownRoomB SOLVED".
        metatileTableFileOffset = 0x203B0,   -- bank 8, CPU $43B0
        layoutStreamFileOffset = 0x19CFB,    -- live-found via single-stepping to $242B's own entry HL
        metatileGridRows = 8,
        metatileGridCols = 10,
        rleLength = 4,                       -- live WRAM $C3F9 at this room's own load
        -- Live-confirmed content: all 80 decoded indices equal 12, a
        -- genuine uniform/solid metatile (record 12's own 4 GFX bytes
        -- are all 0x26) -- the black-wipe backdrop is really just one
        -- solid tile repeated across the whole grid, not a decode-time
        -- special case.
      },
      -- UPGRADED TO VERIFIED (same day, direct follow-up): rendered all
      -- 6 candidate rooms to real PNGs using this project's established
      -- formulas end to end -- tools/graphics/render_unknown_room_a.py
      -- is the checked-in, reproducible recipe (deliberately not
      -- committing the rendered PNGs -- they embed extractable
      -- copyrighted game graphics, same "recipe not output" rule as
      -- checkpoints.py's .state files). All 6 rooms are unmistakably
      -- coherent dungeon interiors: brick wall borders, a mesh/net
      -- floor pattern, torches, distinct furniture/feature objects --
      -- not remotely what a wrong/misaligned decode produces. Backed by
      -- a quantified metric too: gbtile.py's tile_entropy() heuristic
      -- averages 1.22-1.51 bits across all 6 rooms -- squarely in its
      -- documented "real art" band (~1.0-1.8), far from blank or noise.
      -- Both hypotheses confirmed at once: (1) roomSelector N's own
      -- layout stream IS bank 5's own record N, and (2) the final
      -- GFX-tile-byte -> pixel-data step reuses MapTable.lua's verified
      -- tilesetFileOffset=0x32000 + tileId*16 formula (previously only
      -- established for bank 5's older, superseded "direct tile ID"
      -- reading -- turns out it's the right formula for the final
      -- metatile-GFX-byte stage instead). See rom-map.md's "unknownRoomA
      -- VISUALLY CONFIRMED" section for the full writeup.
      --
      -- Still honestly-scoped open items: no live gameplay trigger
      -- found means this is ROM-verified, not yet gameplay-gated the
      -- way willyRoom is; BGP/palette values for these rooms are
      -- unverified (rendered with the default DMG grey ramp used
      -- elsewhere); not yet wired into the LÖVE app as walkable content.
      --
      -- CORRECTED / SCOPE SHARPENED (direct user report after the
      -- room-catalog export that the tiles look totally wrong for every
      -- catalog room except the known ones). metatileTableFileOffset
      -- below (0x20938) is independently ROM-confirmed correct only for
      -- these 6 records (roomSelector 8-13's own $D392/$D393 DE field
      -- from the verified $026DC dispatch table -- a live-traced fact).
      -- It was also reused, as a best-effort placeholder with no
      -- independent confirmation, for every other bank-5/bank-6 record
      -- in the 320-room catalog -- the "VISUALLY + QUANTITATIVELY
      -- CONFIRMED" language on mapTable/mapTableBank6 below only ever
      -- meant "decodes to real, non-noise GB tile art," not "uses the
      -- semantically correct tiles for that room" (an already-recorded
      -- warning materializing). A new lead was tried and ruled out: the
      -- small per-record header MapTable.decode already parses (a
      -- 0xFF-terminated blob before each data blob, never previously
      -- interpreted) was tested as a possible per-record metatile-table
      -- pointer -- record 9 (part of this confirmed family, real table
      -- 0x20938) has a 6-byte header whose trailing u16 decodes to
      -- 0x20381, not 0x20938 -- falsified against known-good ground
      -- truth, and a full 256-record scan found zero bank-5 records
      -- whose header resolves to 0x20938 at all. No working alternative
      -- mechanism is currently known; the real blocker remains how the
      -- ROM selects any room beyond the 16 roomSelectorTable entries,
      -- not which metatile table. The room-catalog website now labels
      -- this explicitly (see
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
          "320-room catalog now uses genericCatalogMetatileTableFileOffset instead, see the UPGRADED doc comment above.",
        metatileTableFileOffset = 0x20938, -- bank 8, CPU $4938 (already-found real unknownRoomA metatile table)
        bank5PointerTableFileOffset = 0x14004, -- already-VERIFIED mapTable.pointerTableFileOffset
        bank5BankFileStart = 0x14000,          -- already-VERIFIED mapTable.bankFileStart
        rleLength = 3,                          -- bank 5's own established header rleLength (MapTable.lua)
        -- NOT RE-DERIVED, NEWLY FLAGGED: this value was always a direct
        -- reuse of mapTable's own project-wide constant, never
        -- independently confirmed for this specific room family
        -- (roomSelector 8-13) on its own terms -- the "VERIFIED...
        -- coherent dungeon art" status above only ever meant "not
        -- noise," the same weaker standard mapTable's own now-
        -- corrected value used to rely on. Now that the code-derived
        -- formula is known (see mapTable's own dated correction
        -- above), roomSelector 8-13's real $D390:$D391 (=0x7000)
        -- predicts 0x33000, not 0x32000 -- tried both this pass,
        -- genuinely inconclusive (both render equally plausible,
        -- structurally-identical dungeon art, no decisive signal the
        -- way bank 5/6/7's own correction had). Left unchanged rather
        -- than force-picking one guess over another.
        tilesetFileOffset = 0x32000,             -- MapTable.lua's own already-VERIFIED formula; tileId*16 bytes/tile
        metatileGridRows = 8,
        metatileGridCols = 10,
        -- Real roomSelector -> real bank-5 record index (identical by
        -- this now-VERIFIED hypothesis) -- all 6 of unknownRoomA's own
        -- real selectors, each a distinct, real dungeon room.
        rooms = { 8, 9, 10, 11, 12, 13 },
      },
      -- The 320-room catalog's own default metatile table (same day,
      -- following the map-header hint) -- see the UPGRADED doc comment
      -- above unknownRoomACandidates for the full chain of evidence.
      -- Derivation, every link independently real:
      --   1. roomSelectorTable's record 0 (bank5's "map") and record 1
      --      (bank6's "map") both have real tileSourcePointer = $40B0
      --      (the same value startRoom's own doc comment cites).
      --   2. Resolved via the verified bank8-relative formula
      --      (bank8Base + (tileSourcePointer - 0x4000), independently
      --      confirmed for willyRoom/unknownRoomA/unknownRoomB):
      --      0x20000 + (0x40B0-0x4000) = 0x200B0.
      --   3. Cross-checked against the external FFA-Disassembly
      --      project's documented US-ROM architecture: one metatile
      --      table per map, shared by every room in it, no per-room
      --      override documented -- roomSelector 0/1 are each their own
      --      "map" (verified via resolveMapRoomPointersFileOffset's
      --      exact byte match), so this is the correct default for all
      --      320 of their rooms.
      --   4. Directly visually re-checked: 12 widely-spread bank-5
      --      records (0, 15-17, 31-32, 63-64, 128, 200, 240, 255) all
      --      show the same recurring door-arch symbol and dotted-floor
      --      pattern with this table -- a consistent visual vocabulary
      --      across the whole 16x16 grid, not present with the old
      --      unknownRoomACandidates-borrowed placeholder.
      -- HONEST STATUS: a structurally-justified, externally-
      -- corroborated derivation -- not independently ground-truth-
      -- verified the way unknownRoomACandidates's own table is (no
      -- live gameplay reaches any of these 320 rooms). Upgraded from
      -- "unverified placeholder, likely wrong" to "best current
      -- derivation," not to "proven."
      --
      -- RE-CHECKED, NOT CHANGED (direct user report that rooms 7, 8,
      -- and 9 have the wrong tilesets, confirmed based on real first-
      -- hand ROM knowledge): fetched the external FFA-Disassembly
      -- project's own devlog directly this pass (not cited from
      -- memory) -- re-confirms link 3 above verbatim, and confirms
      -- there are 16 real maps total, matching this ROM's 16-entry
      -- roomSelectorTable 1:1. Also checked bank 5's 256-record table
      -- for a hidden internal map boundary near records 220/236/237 --
      -- none found (pointers monotonic throughout, no tile-ID regime
      -- shift). Tried every other known candidate pointer for those 3
      -- records -- all decode to plausible-looking art, none
      -- definitively better except one suggestive (not proven) lead:
      -- $46B0 (willyRoom family) produces richer, more distinct results
      -- for all 3. This default stays unchanged (no proof either
      -- replacement is right) -- see seventhRoom's own doc comment and
      -- events.md's dated entry for the full trace.
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

    -- FOUND (external-reference-driven search -- see
    -- src/import/EnemyStatTable.lua's own doc comment for the full
    -- evidence trail): 21 real records, 24-byte stride, bank 4. Every
    -- record's speed/hpBase/xp/gold bytes matched the US "Final Fantasy
    -- Adventure" disassembly's documented boss list byte-for-byte (all
    -- 21 bosses' 4-byte signatures found at this exact stride) -- this
    -- EU localization kept the same combat balance numbers as the US
    -- cartridge. Independently cross-checked against this project's own
    -- earlier, unrelated live-CPU-trace finding (Enemy.lua's
    -- HP_INIT_TRACE_NOTE): file 0x108ba (this table's row 16 hpBase
    -- byte) already had a confirmed role in the enemy HP-randomization
    -- formula, landing on the exact same byte this search found
    -- independently.
    --
    -- SAME TABLE, found again (same day): this is the exact same table
    -- as messageTextPointer below's own already-known message-settings
    -- record base/stride (CPU $4739/file 0x10739, 24 bytes/record) --
    -- itself reused from an even earlier investigation (events.md's
    -- "Second boss investigation") that independently found a "species
    -- byte" field at this table's own +5 and 5 sibling rows (3, 5, 10,
    -- 16, 18) sharing it -- all 5 confirmed byte-for-byte against this
    -- table too. See EnemyStatTable.lua's own doc comment for the full
    -- reconciliation (field renamed projectileType -> speciesByte to
    -- match that earlier, independently-verified name).
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
    -- interpreter -- FOUND, FULLY DECODED" for the full trace. VERIFIED:
    -- bank 2, file offset 0x8576, 256 records x 2 bytes (CPU handler
    -- addresses, LE), indexed by WRAM "current opcode" byte ($D85A).
    -- Confirmed exactly 256 entries (file 0x8776 onward is ordinary
    -- code, not more table data) and live-verified against 2
    -- independently-traced opcodes (0x04 and 0xFE, "display message").
    -- src/import/ScriptOpcodeTable.lua is the generic decoder.
    --
    -- UPDATE (continuing back to the primary opcodes): a ~70-opcode-wide
    -- family found across opcodes 0x10-0x7B (see events.md's "Back to
    -- the primary table") -- 7 clean groups, each gated by an actor-
    -- struct accessor ($28C2 -> $0C6D, a 16-byte-record WRAM array at
    -- $C200, indexed by a "slot" number -- slots 4 and 7 confirmed used
    -- elsewhere) and an 8-way "action code" funneling into a shared
    -- dispatcher ($2879) which tail-calls bank 3 -- not followed across
    -- that bank switch this pass. The gaps in this grid are exactly the
    -- already-known HEAL_LP opcodes (0x12/0x13, 0x22/0x23, ...) -- the
    -- two families tile the same opcode space without overlap.
    -- Structural understanding for ~70-80 opcodes now exists even
    -- though the bank-3 "what does action 0x0A do" layer remains open.
    --
    -- UPDATE (continuing to bank 3): that layer is now closed too --
    -- see events.md's "Bank 3, followed". The bank-3 trampoline ($1F35)
    -- preserves the caller's 8-way action code through the bank switch,
    -- so all 8 variants funnel into one bank-3 function (0x0A, file
    -- 0xCB70), not 8 separate ones. Found: an 8-slot "known/active ID"
    -- list at WRAM $C5A0 (shared linear-search primitive $4B62), and a
    -- third distinct WRAM actor/object array at $C4E0 (24-byte stride,
    -- different from $C200's 16-byte structs). Well-supported
    -- conclusion: this whole 70+11-opcode span is a "mark actor/flag N
    -- as having reached state V, tracked in a global known-list"
    -- mechanism -- plausibly this ROM's quest/story-progress-flag system.
    scriptOpcodeTable = {
      status = "VERIFIED",
      bank = 2,
      fileOffset = 0x8576,
      recordCount = 256,
    },

    -- THE real script/event pointer table -- answers the question left
    -- open since first finding the opcode dispatch table: where do
    -- script bytes live, and how does the interpreter's persistent
    -- cursor ($D8B6/$D8B7) get pointed at one. See docs/reverse-
    -- engineering/events.md's "A real script-pointer table FOUND" / "The
    -- index question, CONCLUSIVELY RESOLVED" for the full chain,
    -- live-traced end to end for a real trigger (the boss-defeat story
    -- sequence) and confirmed twice over (live execution AND
    -- independent static ROM-byte computation agreeing exactly).
    --
    -- VERIFIED mechanism: HL = table[index] (byte-indexed, 2-bytes-per-
    -- entry, same shape as every other indexed table in this ROM), then
    -- the caller adds 0x4000 to get the CPU address -- this table
    -- stores small bank-8-relative offsets, not full addresses. index
    -- comes from a WRAM actor/context record (a bank-select byte + a
    -- 16-bit ROM pointer, dereferenced twice, +2 to skip a small
    -- header) via a shared dispatcher at $31AD (15 independent call
    -- sites found across the ROM) -- 3 special-cased small index values
    -- (0x0B/4/8) redirect to fixed WRAM addresses instead of this table
    -- (some scripts are WRAM-resident, not ROM data).
    --
    -- Live-verified for index 232 (0xE8, the boss-defeat trigger):
    -- table[232] = 0x070F -> +0x4000 = 0x470F -- matches the live-
    -- observed interpreter cursor jump target exactly. Table content
    -- dumped through at least index 89 (a structured, mostly-monotonic
    -- sequence, including one 12-entry run of 0x0000 -- an unused/
    -- reserved block, not noise).
    --
    -- Honestly still open: what the $C3F0/$C3FE/$C3FF WRAM record
    -- represents in general (per-room? per-actor? only the mechanism
    -- that reads it is confirmed, not its broader schema); the real-
    -- world meaning of the 3 special-cased index values. Not wired into
    -- ScriptInterpreter.lua yet -- verified data location, not yet a
    -- consumed runtime data source (most of the 256 primary opcodes'
    -- semantics remain undecoded, the actual blocker for driving real
    -- gameplay from this).
    scriptPointerTable = {
      status = "VERIFIED (table location + lookup formula + one real, live-traced index + real recordCount all confirmed)",
      bank = 8,
      fileOffset = 0x20F11, -- CPU $4F11
      cpuBankOffsetBase = 0x4000, -- add to each raw table entry to get the real CPU address
      -- Confirmed (searching the script table for more real content):
      -- index 1356 is real/sensible, index 1357 onward is uniform
      -- 0xFFFF unprogrammed-ROM filler (2714 raw bytes checked at the
      -- boundary) -- see events.md "The script-pointer table's real
      -- size: exactly 1357 entries".
      recordCount = 1357,
      -- Live-traced example (see events.md for the full chain): index
      -- 232 -> table[232]=0x070F -> +0x4000 = 0x470F (real script
      -- start, bank 8 file 0x2070F) -- the boss-defeat story trigger.
      verifiedExample = { index = 232, tableValue = 0x070F, scriptCpuAddress = 0x470F },
    },

    -- THE real message-text pointer, found via the $1F64 dispatcher
    -- investigation (direct instruction to investigate the dispatcher)
    -- -- see docs/reverse-engineering/text.md's "SOLVED: the real
    -- message-settings-table text pointer" section for the full
    -- disassembly chain ($04E2 5-way sub-dispatcher -> $1F64 -> bank-4
    -- table index 1 -> $102F7). Reuses the already-known message-
    -- settings record base/stride (CPU $4739/file 0x10739, 24 bytes/
    -- record) -- a new field in that same already-partially-
    -- characterized table, not a new table of its own.
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

    -- THE real second-level sub-dispatch table, reached only via the
    -- primary table's opcode 0xFF (handler $38E6) -- see docs/reverse-
    -- engineering/rom-map.md "The 0xFF sub-dispatch table -- bounded
    -- and disassembled" for the full trace. VERIFIED: fixed bank 0
    -- (always mapped, matching $38E6 itself living at a fixed-bank
    -- address), file offset 0x3BAC, indexed by WRAM $D86B (a separate
    -- "current sub-opcode" byte from the primary table's $D85A).
    -- Mechanism (full disassembly): LD A,($D86B) / LD HL,0x3BAC / LD
    -- B,0 / LD C,A / ADD HL,BC / ADD HL,BC / LD A,(HL+) / LD H,(HL) /
    -- LD L,A / JP HL -- the same byte-indexed, 2-bytes-per-entry,
    -- tail-jump shape as the primary table, different base/index.
    -- Confirmed not 256 entries: entries decode as plausible fixed-bank
    -- code-pointer values for exactly 11 records, then the 12th
    -- "entry" (file 0x3BC2) decodes as 0x21 -- the real LD HL,nn
    -- opcode, genuine CPU code immediately following the table. Also
    -- confirmed from the other side: the routine immediately before
    -- the table is a clean, self-contained JP 0x0150, the normal
    -- "code ends, table begins" shape this project's other tables share.
    -- No bounds check on the $D86B index before the ADD HL,BC -- an
    -- honest observation (not a bug this project patches): if $D86B is
    -- ever >= 11 in real play, the ROM would index into its own
    -- ordinary code bytes as a bogus pointer.
    --
    -- UPDATE (continuing on the opcodes): 7 of the 11 entries now have
    -- a disassembled conclusion -- see events.md's "The 0xFF sub-table,
    -- continued". Headline find: $3C74, a shared "reschedule the sub-
    -- dispatch to a different entry on the next tick" primitive (writes
    -- both $D86B and $D85A=0xFF, then returns without fetching the next
    -- opcode) -- how 4 of the 11 entries (indices 3/$3C1B, 4/$350F,
    -- 7/$3B18, 8/$3B2C) form a structurally-verified multi-tick
    -- "wait/halt" family, each conditionally skipping the CALL $3727
    -- that would otherwise resume the interpreter. Index 8 is the
    -- release point (halts on $D853 bit 7, resumes once clear).
    -- Live-traced twice for real-world trigger conditions (Watcher on
    -- $D86B across the full post-boss dialogue AND the real door->
    -- secondRoom scroll) -- zero hits both times, an honest negative
    -- (later found to be a tooling bug, see below).
    --
    -- UPDATE (same day, continuing to the last 4): all 11 entries now
    -- disassembled to a stated conclusion (events.md's "The 0xFF
    -- sub-table, finished" has the full per-entry table) -- and the
    -- "plausibly NPC movement" guess above was wrong, corrected: entry
    -- 0 and several of entry 1's internal branches end by calling
    -- $36D0, which caches HL into $D8B6/$D8B7 (the script cursor) and
    -- sets $D85A=0x04 -- the address already flagged elsewhere as the
    -- real-time typewriter dispatch, not the general interpreter. Entry
    -- 1 also has a 5-tick pacing gate ($36C2/WRAM $D864) matching the
    -- independently-confirmed "5 frames per letter" cadence, a
    -- 4-direction cursor-delta dispatcher, and entry 2 blanks tile runs
    -- with the space glyph (0x7F). This is the driver for a more
    -- elaborate multi-line textbox variant on top of the already-known
    -- single-line typewriter, not an NPC-movement system -- explaining
    -- the 2 live-trace negatives above: both tested checkpoints
    -- plausibly use the simpler, direct $D3E9-based reveal instead.
    -- Entry 5 independently reads WRAM $D3E8 -- one byte before the
    -- verified $D3E9 reveal timer (text.md) -- a second cross-link.
    -- Still open: several entries (5, 10, and more) delegate into bank
    -- 2 functions not followed across the bank switch this pass.
    --
    -- CORRECTED (follow-up on whether the tooling bug affected other
    -- spots): the "zero hits both times" dialogue claim above was
    -- wrong -- a tooling bug (see tooling.md's "session.run(N)+Watcher
    -- can silently drop hits"; $D86B was watched together with the
    -- fast-changing $D85A, driven by session.run(1), which can
    -- silently lose a hit).
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
    -- "Item/spell table" (PARTIALLY VERIFIED: names, the record's
    -- 16-byte width, the per-category ID byte, AND the price field
    -- (bytes 13-14, found 2026-08-18 -- see ItemTable.lua's own doc
    -- comment, 8/8 external gold-cost matches) are confirmed; the
    -- remaining stat bytes (10-12) are not decoded). src/import/
    -- ItemTable.lua is the generic decoder.
    -- EXTENDED (monster/npc/item census): a fresh static scan (name-
    -- decode success/failure per record, same method already used to
    -- find enemySpeciesTable's boundary) found clean content well past
    -- the previously-documented 20 records -- German item names through
    -- at least record 58 ("Bonbon"/"Schlüssel"/"Knochen"/"Bronze"/
    -- "Träne"/"Öl"/"Kristall"/"Rubin"/"Smaragd"/"Saphir"/"Diamant"/
    -- "Gold"/"Zähne"), interspersed with several records that don't
    -- cleanly decode at either known name offset (real, unresolved
    -- gaps -- ItemTable.decode returns name="" for those rather than
    -- guessing). recordCount extended to 59; records beyond that
    -- returned only short, non-word fragments and were not included.
    itemTable = {
      status = "PARTIALLY VERIFIED -- price field VERIFIED (2026-08-18, 8/8 external " ..
        "matches); mpCost field VERIFIED (2026-08-19, 8/8 external matches + live-" ..
        "disassembled ROM deduction code, see ItemTable.lua's own doc comment)",
      fileOffset = 0x9DE5,
      bank = 2,
      recordLength = 16,
      nameLength = 8, -- 0x00-padded
      recordCount = 59, -- extended 2026-08-15, see doc comment above
      -- Byte 15 (0-based) is a per-category item ID that resets to 0 at
      -- the boundary between records 0-7 and records 8-19 -- see
      -- rom-map.md for the exact evidence.
      --
      -- CORRECTED (2026-08-19): the labels below used to read
      -- "consumable items (0-7) / spells (8-19)" -- backwards from what
      -- ItemTable.lua's own 2026-08-19 doc comment now decisively shows.
      -- Records 0-7 are the real 8 MP-costed, CASTABLE spells (Cure/
      -- Heal/Sleep/Mute/Fire/Ice/Lightning/Nuke -- see `mpCost`, 8/8
      -- external matches); records 8-19 are the shop-PURCHASABLE
      -- recovery/status-cure items (see `price`, also 8/8 external
      -- matches, 2026-08-18). Both real, both fully priced/costed now --
      -- just swapped from this field's own original naming guess.
      categoryBoundaryRecord = 8,
    },

    -- Weapon/equipment name+stat table -- see docs/reverse-engineering/
    -- rom-map.md "Weapon/equipment table" (PARTIALLY VERIFIED: names and
    -- the record's 16-byte width are confirmed via a live UI cross-check
    -- against the in-game menu's equipped-weapon readout ("Breit"); the
    -- stat bytes and the table's true start/end boundaries are not).
    --
    -- EXTENDED (monster/npc/item census): the same static name-decode
    -- scan found clean weapon/armor names through record 47 ("Bronze"/
    -- "Eisen"/"Silber"/"Gold"/"Flamme"/"Drache"/"Ägis"/"Opal"/"Samurai"/
    -- "Excali"[bur]/"Zeus"/"Lanze", material-tier armor sets and named
    -- unique weapons) -- previous recordCount=20 was cutting off more
    -- than half the table. Record 48 onward returned only short
    -- fragments, not real words.
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

    -- FOUND (external-reference-driven search, same method as
    -- enemyStatTable above -- see src/import/WeaponStatTable.lua's own
    -- doc comment for the full evidence trail). A separate table from
    -- weaponTable above (its file offset doesn't land on a shared
    -- record boundary -- see WeaponStatTable.lua for why these stay two
    -- independent decoders): 16 records, 16-byte stride, bank 2. Every
    -- record's 7-byte stat signature matched the US "Final Fantasy
    -- Adventure" disassembly's documented weapon list byte-for-byte.
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

    -- NEW (direct user request to search out all monsters and NPCs with
    -- all their data, text, and graphics from the ROM): a ROM-wide text
    -- census, found via tools/rom/dump_strings.py's already-proven
    -- decoder (the same tool/method that found Amanda's real secondRoom
    -- dialogue) -- not a live OAM/room capture, since these are plain
    -- decodable ROM strings. Every fileOffset here is a directly-
    -- verifiable location (open the ROM at that byte and re-run
    -- TextDecoder.decodeString to reproduce it).
    --
    -- HONEST SCOPE: a census of names and text this project can decode,
    -- not a census of confirmed live positions/sprites. Exactly 2 of
    -- the named characters below (Willy, Amanda) have a known room/
    -- sprite (see graphics.willyScene/secondRoom above) -- every other
    -- name was found only in dialogue text, with no live room, OAM
    -- sprite, or WRAM position ever captured for it. Finding those
    -- would mean live-exploring the specific room each character's
    -- dialogue triggers in (unknown which of the ~384 catalogued rooms
    -- that is) -- substantial future work, not attempted this pass.
    -- Similarly, bossDefeats below are monster names with real "<Name>
    -- bezwungen/besiegt" messages, but this pass found no structural
    -- link (shared index, pointer, adjacent table) between these name
    -- strings and enemySpeciesTable's 11 numbered species rows --
    -- real, but not mapped to a specific stat row; presented
    -- standalone, not force-matched.
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

-- CORRECTED, capture-bug fix (direct user pushback that the room looks
-- like a combination of startRoom and fourthRoom, as if something got
-- shifted while reading -- exactly right). sixthRoom.grid/tileOffsets/
-- floorTileIds as originally hand-written above were a previously-
-- uncaught capture bug, not real ROM content: a live re-check (reading
-- the real hardware SCX/SCY registers directly, not just the WRAM
-- shadow) found the room settles at real SCX=96, SCY=0 -- but the
-- original grid capture read the raw 32-column VRAM background tilemap
-- starting at column 0 (as if SCX were still 0), the same "ignoring
-- hardware SCX/SCY" pitfall this project has hit and fixed elsewhere.
-- Reproduced the bug directly: a fresh, deliberately-uncorrected raw
-- VRAM read at this exact live moment produces the same "half brick
-- corridor wall, half checkerboard courtyard" combination already
-- sitting in sixthRoom.grid, pixel-for-pixel -- while a correctly
-- SCX-windowed read shows something completely different: the real
-- "Kämpfe!" battle-intro textbox over an ordinary courtyard floor --
-- more of startRoom's own content (consistent with, and now visually
-- confirming, this pass's WRAM-register finding that sixthRoom shares
-- startRoom/fourthRoom's exact room identity). The stored grid above
-- was a reproducible artifact of the 32-column tilemap wraparound
-- colliding with stale/unrelated cells -- content no real player would
-- ever see on screen. Not hand-edited above (the literal stays as a
-- documented historical record of the bug, cited by this comment) --
-- corrected here instead, after every profile has been constructed, by
-- pointing sixthRoom's render data at startRoom's own already-correct
-- capture (a Lua table reference, not a duplicated copy -- guarantees
-- the two can never drift apart again). secondBoss's own placement/
-- spawn fields are untouched -- only the room render data was wrong.
for _, profile in pairs(RomProfiles.PROFILES) do
  local g = profile.graphics
  if g and g.sixthRoom and g.startRoom then
    g.sixthRoom.grid = g.startRoom.grid
    g.sixthRoom.tileOffsets = g.startRoom.tileOffsets
    g.sixthRoom.floorTileIds = g.startRoom.floorTileIds
  end
end

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
