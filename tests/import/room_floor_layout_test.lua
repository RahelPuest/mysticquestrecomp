local Harness = require("tests.harness")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Synthetic-data tests: exercise the pipeline's own parsing logic against
-- hand-built bytes, independent of any real ROM, per the "headlessly
-- testable" rule (same convention as MapTable/RoomSelectorTable).

Harness.test("RoomFloorLayout.decodeLayoutStream: literal bytes (no high bit) pass through 1:1", function()
  local indices = RoomFloorLayout.decodeLayoutStream("\6\40\18", 0, 4, 3)
  Harness.assertEqual(#indices, 3)
  Harness.assertEqual(indices[1], 6)
  Harness.assertEqual(indices[2], 40)
  Harness.assertEqual(indices[3], 18)
end)

Harness.test("RoomFloorLayout.decodeLayoutStream: high-bit byte expands to rleLength copies of byte-0x80", function()
  -- 0x90 = 0x80 | 0x10 -- real willyRoom record-10 shape (see rom-map.md
  -- "MILESTONE 3 SOLVED"): a literal border tile, an RLE-repeated
  -- interior, then a literal closing border tile.
  local indices = RoomFloorLayout.decodeLayoutStream("\16\128\21", 0, 4, 6)
  Harness.assertEqual(#indices, 6)
  Harness.assertEqual(indices[1], 16)
  Harness.assertEqual(indices[2], 0)
  Harness.assertEqual(indices[3], 0)
  Harness.assertEqual(indices[4], 0)
  Harness.assertEqual(indices[5], 0)
  Harness.assertEqual(indices[6], 21)
end)

Harness.test("RoomFloorLayout.decodeLayoutStream: stops exactly at outputCount, even mid-run", function()
  -- A single RLE token can legitimately produce more raw repeats than
  -- are still needed -- the real ROM decompressor (`$242B`) stops
  -- writing once its own output counter (80 for willyRoom) hits zero,
  -- mid-run if necessary. Verify the same truncation here.
  local indices = RoomFloorLayout.decodeLayoutStream("\128", 0, 4, 2)
  Harness.assertEqual(#indices, 2)
  Harness.assertEqual(indices[1], 0)
  Harness.assertEqual(indices[2], 0)
end)

Harness.test("RoomFloorLayout.decodeLayoutStream: fails loudly if romData runs out before outputCount", function()
  local ok = pcall(RoomFloorLayout.decodeLayoutStream, "\1\2", 0, 4, 10)
  Harness.assertTrue(not ok, "expected decode to raise when the stream ends early")
end)

Harness.test("RoomFloorLayout.readMetatile: parses a synthetic 6-byte record", function()
  -- Real willyRoom metatile index 0 (file 0x206B0): 1b 1c 1d 1e 30 05.
  local rom = "\27\28\29\30\48\5"
  local mt = RoomFloorLayout.readMetatile(rom, 0, 0)
  Harness.assertEqual(mt.gfxTL, 0x1b)
  Harness.assertEqual(mt.gfxTR, 0x1c)
  Harness.assertEqual(mt.gfxBL, 0x1d)
  Harness.assertEqual(mt.gfxBR, 0x1e)
  Harness.assertEqual(mt.collision, 0x30)
  Harness.assertEqual(mt.interaction, 0x05)
end)

Harness.test("RoomFloorLayout.readMetatile: indexes past record 0 correctly (index * 6 stride)", function()
  local rom = string.rep("\0", 6) .. "\1\2\3\4\5\6"
  local mt = RoomFloorLayout.readMetatile(rom, 0, 1)
  Harness.assertEqual(mt.gfxTL, 1)
  Harness.assertEqual(mt.interaction, 6)
end)

Harness.test("RoomFloorLayout.remapTile: looks up a byte through a 256-entry snapshot", function()
  local d070 = string.rep("\0", 0x1b) .. "\151" .. string.rep("\0", 256 - 0x1b - 1)
  Harness.assertEqual(RoomFloorLayout.remapTile(d070, 0x1b), 151)
end)

Harness.test("RoomFloorLayout.buildPixelGrid: combines a tiny 1x1 metatile grid end to end", function()
  -- One metatile, RLE stream = single literal index 0.
  local layoutStream = "\0"
  local metatileTable = "\10\11\12\13\0\0" -- gfxTL=10,gfxTR=11,gfxBL=12,gfxBR=13
  local rom = metatileTable .. layoutStream
  local d070 = (function()
    local t = {}
    for i = 0, 255 do t[i] = 0 end
    t[10], t[11], t[12], t[13] = 100, 101, 102, 103
    local chars = {}
    for i = 0, 255 do chars[i + 1] = string.char(t[i]) end
    return table.concat(chars)
  end)()

  local layout = {
    metatileTableFileOffset = 0,
    layoutStreamFileOffset = #metatileTable,
    rleLength = 1,
    metatileGridRows = 1,
    metatileGridCols = 1,
  }
  local grid = RoomFloorLayout.buildPixelGrid(rom, layout, d070)
  Harness.assertEqual(#grid, 2)
  Harness.assertEqual(#grid[1], 2)
  Harness.assertEqual(grid[1][1], 100)
  Harness.assertEqual(grid[1][2], 101)
  Harness.assertEqual(grid[2][1], 102)
  Harness.assertEqual(grid[2][2], 103)
end)

Harness.test("RoomFloorLayout.isWalkableCollision: upper-nibble-zero is walkable, non-zero is not", function()
  -- Real observed byte values (see rom_profiles.lua's own
  -- UNKNOWN_ROOM_A_FLOOR_TILE_IDS / RoomFloorLayout.COLLISION_WALL_MASK
  -- doc comments for the full, honest "confirmed for fourthRoom,
  -- disproven for willyRoom" story -- this test only checks the pure
  -- bitmask arithmetic itself, not a universal claim about what it
  -- means in any given room).
  Harness.assertTrue(RoomFloorLayout.isWalkableCollision(0x00))
  Harness.assertTrue(RoomFloorLayout.isWalkableCollision(0x08))
  Harness.assertTrue(not RoomFloorLayout.isWalkableCollision(0x30))
  Harness.assertTrue(not RoomFloorLayout.isWalkableCollision(0x31))
  Harness.assertTrue(not RoomFloorLayout.isWalkableCollision(0xF0))
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

-- The live $D070 remap snapshot this project captured at the exact
-- moment willyRoom's own real draw completed (2026-08-11, a single,
-- targeted, bounded WRAM read via tools/rom/checkpoints.py's
-- willy_room_free() -- NOT exploratory play, see rom-map.md "MILESTONE
-- 3 SOLVED"). $D070 is populated at runtime, not ROM-static, so this
-- fixture is real captured DATA, not a derived/guessed constant --
-- checked in here so the pipeline test below is reproducible without
-- re-running mgba. Finding $D070's own real ROM-side populator remains
-- a named, open follow-up (see rom-map.md).
local WILLY_ROOM_D070 =
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" ..
  "\0\0\0\0\0\0\0\0\0\0\0\151\152\153\154\0" ..
  "\128\129\133\164\145\149\155\163\0\0\0\0\0\0\146\147" ..
  "\130\131\165\146\147\162\170\171\0\0\0\0\0\0\0\0" ..
  "\166\168\167\169\132\143\134\144\148\150\159\158\160\161\157\156" ..
  "\135\136\139\140\0\0\0\0\0\0\177\203\202\0\0\0" ..
  "\137\138\141\142\137\138\141\142\145\146\149\150\178\179\182\183" ..
  "\131\132\135\136\139\140\143\144\147\148\151\152\180\181\184\185" ..
  "\153\154\157\158\161\162\165\166\169\170\173\174\204\205\208\209" ..
  "\155\156\159\160\163\164\167\168\171\172\175\176\206\207\210\211" ..
  "\186\187\190\191\194\195\198\199\212\213\216\217\220\221\224\225" ..
  "\188\189\141\142\148\197\200\201\214\215\218\219\222\223\226\227" ..
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" ..
  "\0\130\136\143\135\144\145\131\138\139\140\134\132\0\0\0" ..
  "\0\0\0\0\0\133\137\0\0\0\0\0\0\0\0\0" ..
  "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
Harness.assertEqual(#WILLY_ROOM_D070, 256)

-- The 4 door/exit zones this session's OWN separately-traced mechanism
-- ($235B/$225D/$2281/$056C) draws over the base floor layout -- the base
-- layout deliberately leaves these blank (see rom-map.md "MILESTONE 3
-- SOLVED"). 1-based (row, col) ranges, inclusive, matching
-- `graphics.willyRoom.grid`'s own indexing.
local DOOR_ZONES = {
  { rowMin = 1, rowMax = 2, colMin = 9, colMax = 12 },   -- North
  { rowMin = 7, rowMax = 10, colMin = 1, colMax = 2 },   -- West
  { rowMin = 7, rowMax = 10, colMin = 19, colMax = 20 }, -- East
  { rowMin = 15, rowMax = 16, colMin = 9, colMax = 12 }, -- South
}

local function inADoorZone(row, col)
  for _, z in ipairs(DOOR_ZONES) do
    if row >= z.rowMin and row <= z.rowMax and col >= z.colMin and col <= z.colMax then
      return true
    end
  end
  return false
end

Harness.testIfAvailable(
  "RoomFloorLayout.buildPixelGrid: real ROM reproduces willyRoom's known grid outside the 4 door zones",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local layout = profile.roomFloorLayoutPipeline.exampleRoom
    local grid = RoomFloorLayout.buildPixelGrid(romData, layout, WILLY_ROOM_D070)

    local realGrid = profile.graphics.willyRoom.grid
    Harness.assertEqual(#grid, #realGrid)

    local matches, doorZoneMismatches, otherMismatches = 0, 0, 0
    for r = 1, #realGrid do
      Harness.assertEqual(#grid[r], #realGrid[r], "row " .. r .. " width")
      for c = 1, #realGrid[r] do
        if grid[r][c] == realGrid[r][c] then
          matches = matches + 1
        elseif inADoorZone(r, c) then
          doorZoneMismatches = doorZoneMismatches + 1
        else
          otherMismatches = otherMismatches + 1
          print(string.format(
            "  UNEXPECTED mismatch at row %d col %d: decoded=%d real=%d",
            r, c, grid[r][c], realGrid[r][c]))
        end
      end
    end

    -- The real, precise result this pass found (see rom-map.md
    -- "MILESTONE 3 SOLVED"): 288 exact matches, 32 mismatches, and
    -- EVERY mismatch inside a door zone -- not a loose "close enough"
    -- check, the exact real numbers.
    Harness.assertEqual(otherMismatches, 0,
      "found " .. otherMismatches .. " mismatch(es) OUTSIDE the known door zones -- " ..
      "a real decode error, not the already-understood door-overlay gap")
    Harness.assertEqual(doorZoneMismatches, 32,
      "expected exactly 32 door-zone placeholders (8 tiles x 4 doors), got " .. doorZoneMismatches)
    Harness.assertEqual(matches, 288, "expected exactly 288 real tile matches")
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.decodeLayoutStream: generalizes to a SECOND, genuinely different room (unknownRoomB, roomSelector 15)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Real, live-confirmed values (2026-08-12, "weiter der world scope"
    -- -- see rom-map.md's own "unknownRoomB SOLVED" + follow-up
    -- sections): unknownRoomB (roomSelectors 14-15, targetPointer
    -- 0x43B0) is the real ROM mechanism behind the post-boss black-wipe
    -- transition backdrop -- confirmed live (a real, transition-
    -- triggered room load, not a forced/synthetic one): the real
    -- layout-stream source is file 0x19CFB (found by single-stepping
    -- to the live $242B call and reading its own real HL, resolved
    -- through the currently-mapped bank via `watcher.rom_offset`'s
    -- same convention), the real per-room RLE run-length is
    -- $C3F9=4 (same value as willyRoom's own, live-read), and the
    -- real WRAM result ($C350-$C39F) is 80 bytes, EVERY ONE equal to
    -- 12 -- this project's own decoder must reproduce that exactly
    -- from the real ROM bytes to prove the pipeline genuinely
    -- generalizes, not just re-decode willyRoom successfully again.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local indices = RoomFloorLayout.decodeLayoutStream(romData, 0x19CFB, 4, 80)
    Harness.assertEqual(#indices, 80)
    for i = 1, 80 do
      Harness.assertEqual(indices[i], 12, "metatile index " .. i .. " should be the real, live-observed value 12")
    end

    -- Cross-check: unknownRoomB's own real metatile table (bank 8,
    -- `0x20000 + (0x43B0 - 0x4000)` -- the same formula already
    -- established for willyRoom/unknownRoomA) record 12 is a real,
    -- uniform/solid tile (all 4 GFX bytes identical) -- exactly what a
    -- blank black-wipe backdrop needs, matching the live screenshot.
    local mt = RoomFloorLayout.readMetatile(romData, 0x20000 + (0x43B0 - 0x4000), 12)
    Harness.assertEqual(mt.gfxTL, 0x26)
    Harness.assertEqual(mt.gfxTR, 0x26)
    Harness.assertEqual(mt.gfxBL, 0x26)
    Harness.assertEqual(mt.gfxBR, 0x26)
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout: unknownRoomA's 6 real rooms (bank5 record N = roomSelector N) decode to stable, coherent, non-uniform structure",
  romData ~= nil,
  "no development ROM found",
  function()
    -- VERIFIED 2026-08-12 (see rom_profiles.lua's own
    -- `unknownRoomACandidates` doc comment and rom-map.md's "unknownRoomA
    -- VISUALLY CONFIRMED" section for the full writeup): all 6 rooms
    -- render as real, coherent dungeon art (brick walls, a mesh floor,
    -- torches, distinct furniture) via `tools/graphics/
    -- render_unknown_room_a.py`, with `gbtile.py`'s own established
    -- `tile_entropy()` heuristic landing squarely in its real-art band
    -- (1.22-1.51 bits) for all 6. This Lua-side test only re-checks the
    -- index-decode layer (no PIL/image rendering in headless Lua), so it
    -- stays a stability/coherence regression check here, not a re-run of
    -- the full visual proof -- confirms this project's own decoder
    -- produces the SAME real, non-degenerate result every run for all 6
    -- real roomSelectors, against real ROM bytes.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local cand = profile.roomFloorLayoutPipeline.unknownRoomACandidates

    local function bank5DataFileOffset(recordIndex)
      local off = cand.bank5PointerTableFileOffset + recordIndex * 4 + 2
      local lo, hi = romData:byte(off + 1, off + 2)
      local cpuAddr = lo + hi * 256
      return cand.bank5BankFileStart + (cpuAddr - 0x4000)
    end

    for _, sel in ipairs(cand.rooms) do
      local dataFileOffset = bank5DataFileOffset(sel)
      local indices = RoomFloorLayout.decodeLayoutStream(romData, dataFileOffset, cand.rleLength, 80)
      Harness.assertEqual(#indices, 80)

      -- Real coherence check: NOT every value identical (a truly blank/
      -- degenerate decode, like unknownRoomB's own real content) AND at
      -- least one value repeats often enough to look like a real floor
      -- pattern (this project's own established "checkerboard" signature).
      local distinct, counts = 0, {}
      for _, v in ipairs(indices) do
        counts[v] = (counts[v] or 0) + 1
      end
      for _ in pairs(counts) do distinct = distinct + 1 end
      Harness.assertTrue(distinct > 1, "roomSelector " .. sel .. ": expected non-uniform structure, got a single repeated value")
      Harness.assertTrue(distinct < 80, "roomSelector " .. sel .. ": expected a real repeating pattern, got 80 distinct values (noise-shaped)")
    end
  end
)

Harness.testIfAvailable(
  "rom_profiles.lua's graphics.unknownRoomA_8..13: real, checked-in grid/tileOffsets exactly reproduce a fresh pipeline decode",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Built in 2026-08-12 (direct instruction "du kannst das gerne
    -- einbauen") -- see rom_profiles.lua's own `UNKNOWN_ROOM_A_*` local
    -- doc comments and RoomExplorer.lua for the full "why dev-only, not
    -- a real door" reasoning. This test's real job: the literal 16x20
    -- grid tables pasted into rom_profiles.lua were generated once by a
    -- one-off script (not checked in) and hand-verified against
    -- `render_unknown_room_a.py`'s own PNGs -- re-decoding here straight
    -- from real ROM bytes via this project's own `RoomFloorLayout`
    -- module (no copy-paste transcription risk) and diffing catches any
    -- transcription mistake a purely-visual check could miss.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local cand = profile.roomFloorLayoutPipeline.unknownRoomACandidates

    local function bank5DataFileOffset(recordIndex)
      local off = cand.bank5PointerTableFileOffset + recordIndex * 4 + 2
      local lo, hi = romData:byte(off + 1, off + 2)
      local cpuAddr = lo + hi * 256
      return cand.bank5BankFileStart + (cpuAddr - 0x4000)
    end

    for _, sel in ipairs(cand.rooms) do
      local room = profile.graphics["unknownRoomA_" .. sel]
      Harness.assertTrue(room ~= nil, "missing graphics.unknownRoomA_" .. sel)
      Harness.assertEqual(#room.grid, 16)
      Harness.assertEqual(#room.grid[1], 20)

      local dataFileOffset = bank5DataFileOffset(sel)
      local indices = RoomFloorLayout.decodeLayoutStream(romData, dataFileOffset, cand.rleLength, 80)

      -- Rebuild the same 16x20 grid `render_unknown_room_a.py` builds:
      -- 8x10 metatiles, each expanding to a 2x2 block of its own real
      -- GFX-tile bytes (identity mapping -- these ARE the final tile
      -- IDs this room's own `tileOffsets` keys on, no live $D070 remap
      -- involved, see rom_profiles.lua's own doc comment for why).
      for mr = 0, cand.metatileGridRows - 1 do
        for mc = 0, cand.metatileGridCols - 1 do
          local idx = indices[mr * cand.metatileGridCols + mc + 1]
          local mt = RoomFloorLayout.readMetatile(romData, cand.metatileTableFileOffset, idx)
          local row1, row2 = mr * 2 + 1, mr * 2 + 2
          local col1, col2 = mc * 2 + 1, mc * 2 + 2
          Harness.assertEqual(room.grid[row1][col1], mt.gfxTL,
            "roomSelector " .. sel .. " [" .. row1 .. "][" .. col1 .. "]")
          Harness.assertEqual(room.grid[row1][col2], mt.gfxTR,
            "roomSelector " .. sel .. " [" .. row1 .. "][" .. col2 .. "]")
          Harness.assertEqual(room.grid[row2][col1], mt.gfxBL,
            "roomSelector " .. sel .. " [" .. row2 .. "][" .. col1 .. "]")
          Harness.assertEqual(room.grid[row2][col2], mt.gfxBR,
            "roomSelector " .. sel .. " [" .. row2 .. "][" .. col2 .. "]")
        end
      end

      -- Every real tile ID this room's own grid actually uses must have
      -- a real tileOffsets entry, following the same already-VERIFIED
      -- `0x32000 + tileId*16` formula (MapTable.lua).
      for r = 1, 16 do
        for c = 1, 20 do
          local tileId = room.grid[r][c]
          Harness.assertEqual(room.tileOffsets[tileId], cand.tilesetFileOffset + tileId * 16,
            "roomSelector " .. sel .. ": tileOffsets[" .. tileId .. "]")
        end
      end
    end
  end
)

Harness.testIfAvailable(
  "rom_profiles.lua's graphics.unknownRoomA_8..13: TileWalkability builds a usable (non-degenerate) canMoveTo",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Not a claim that the floor classification is exhaustively correct
    -- (still HYPOTHESIS -- see rom_profiles.lua's own
    -- `UNKNOWN_ROOM_A_FLOOR_TILE_IDS` doc comment) -- just a sanity
    -- check that it isn't degenerate (all-wall would make the room
    -- unenterable; all-floor would mean the classification did nothing).
    local TileWalkability = require("src.entities.TileWalkability")
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, sel in ipairs({ 8, 9, 10, 11, 12, 13 }) do
      local room = profile.graphics["unknownRoomA_" .. sel]
      local canMoveTo = TileWalkability.build(room, 16, 16)
      local floorSpots, wallSpots = 0, 0
      for y = 0, 128 - 16, 8 do
        for x = 0, 160 - 16, 8 do
          if canMoveTo(x, y) then floorSpots = floorSpots + 1 else wallSpots = wallSpots + 1 end
        end
      end
      Harness.assertTrue(floorSpots > 0, "roomSelector " .. sel .. ": no walkable spot at all")
      Harness.assertTrue(wallSpots > 0, "roomSelector " .. sel .. ": no blocked spot at all (degenerate all-floor)")
    end
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.buildCollisionGrid: the DEFAULT (fourthRoom/unknownRoomA) rule reads willyRoom's own real floor backwards (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Kept as a real, concrete regression check that the default rule
    -- (`isWalkableCollision`) really does NOT transfer to willyRoom's
    -- own table -- see `isWalkableCollisionWillyFamily`'s own doc
    -- comment (RoomFloorLayout.lua) for the full, exhaustive
    -- ground-truth derivation of the CORRECT rule, exercised in the
    -- next test below.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local ex = profile.roomFloorLayoutPipeline.exampleRoom
    local pixelGrid = profile.graphics.willyRoom.grid

    local collisionGrid = RoomFloorLayout.buildCollisionGrid(romData, ex) -- default rule, no 3rd arg
    Harness.assertEqual(#collisionGrid, 16)
    Harness.assertEqual(#collisionGrid[1], 20)

    Harness.assertEqual(pixelGrid[3][3], 151)
    Harness.assertTrue(not collisionGrid[3][3],
      "willyRoom's own real floor (tile 151) reads as collision-non-walkable under the DEFAULT " ..
      "rule -- expected, see RoomFloorLayout.lua's own isWalkableCollisionWillyFamily doc comment")
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.buildCollisionGrid + isWalkableCollisionWillyFamily: exactly matches willyRoom's live-tested floorTileIds, all 320 real cells (2026-08-14)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Task "Kollision generalisieren" (2026-08-14): the general
    -- position-aware mechanism, with willyRoom's own real, ground-truth
    -- -derived rule, checked against EVERY real cell of the room's own
    -- grid -- not a spot check. `willyRoom.floorTileIds` is this
    -- project's own extensively live-movement-tested ground truth
    -- (2026-08-09: held UP, watched the real player stop dead at the
    -- wall boundary) -- this test proves the ROM-decoded collision byte
    -- reproduces it exactly, cell for cell, with zero disagreement.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local ex = profile.roomFloorLayoutPipeline.exampleRoom
    local room = profile.graphics.willyRoom

    local collisionGrid = RoomFloorLayout.buildCollisionGrid(
      romData, ex, RoomFloorLayout.isWalkableCollisionWillyFamily)

    local checked, disagreements = 0, 0
    for row = 1, 16 do
      for col = 1, 20 do
        checked = checked + 1
        local tileId = room.grid[row][col]
        local expectedFloor = room.floorTileIds[tileId] == true
        if collisionGrid[row][col] ~= expectedFloor then
          disagreements = disagreements + 1
        end
      end
    end
    Harness.assertEqual(checked, 320)
    Harness.assertEqual(disagreements, 0,
      "expected the real collision-byte-derived grid to exactly match willyRoom's own " ..
      "live-tested floorTileIds everywhere -- any disagreement here is a real, new finding, " ..
      "not a rounding error")
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.buildRoomFromMapTableRecord: decodes ANY room, no live emulator needed (2026-08-12, \"alle raeume dekodieren\")",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Direct answer to "du sollst in der lage sein alle raeume zu
    -- dekodieren. nicht stoppen bevor das nicht moeglich ist": proves
    -- the general, ROM-static (no `$D070`/live-capture) decode path
    -- works end to end against a REAL record from the newly-found
    -- SECOND map table (bank 6, see rom_profiles.lua's own
    -- `mapTableBank6`) -- not just re-testing the already-known bank-5
    -- `unknownRoomA` path.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opts = {
      metatileTableFileOffset = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileTableFileOffset,
      tilesetFileOffset = profile.mapTableBank6.tilesetFileOffset,
      metatileGridRows = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileGridRows,
      metatileGridCols = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileGridCols,
    }

    local grid = RoomFloorLayout.buildRoomFromMapTableRecord(romData, profile.mapTableBank6, 0, opts)
    -- Real shape: 8 metatile rows x 10 metatile cols, each metatile a
    -- real 2x2 pixel-tile block -> 16x20 final grid, matching every
    -- other room this project has ever decoded.
    Harness.assertEqual(#grid, 16)
    Harness.assertEqual(#grid[1], 20)

    -- Every cell must be a real, in-range ROM file offset (inside
    -- environmentTilesetBank12's own already-VERIFIED bounds), not a
    -- garbage/overflowed address -- a real, cheap sanity check that
    -- doesn't rely on eyeballing a rendered PNG (see rom-map.md's own
    -- "World scope" writeup for the actual visual + tile_entropy
    -- confirmation this test doesn't re-do headlessly).
    local tilesetStart = profile.graphics.environmentTilesetBank12.fileOffsetStart
    local tilesetEnd = profile.graphics.environmentTilesetBank12.fileOffsetEnd
    for row = 1, 16 do
      for col = 1, 20 do
        local off = grid[row][col]
        Harness.assertTrue(off >= tilesetStart and off < tilesetEnd,
          string.format("grid[%d][%d]=%#x outside the real environment tileset bounds", row, col, off))
      end
    end

    -- Cross-check against a second, different record (bank 6's own
    -- record 21, independently eyeballed as real, coherent shrine art
    -- during this investigation) -- a DIFFERENT real result, not the
    -- same grid repeated (would indicate the record-index plumbing is
    -- silently ignored).
    local grid21 = RoomFloorLayout.buildRoomFromMapTableRecord(romData, profile.mapTableBank6, 21, opts)
    Harness.assertTrue(grid[1][1] ~= grid21[1][1] or grid[8][10] ~= grid21[8][10],
      "record 0 and record 21 produced an identical grid -- recordIndex likely ignored")
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.buildCollisionGridFromMapTableRecord: real per-room collision, no live emulator needed (2026-08-12, quick win #2)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Same real record (bank 6, record 0) as the buildRoomFromMapTableRecord
    -- test above, so the two grids can be sanity-cross-checked against
    -- each other -- this does NOT claim the walkable/wall verdict is
    -- ROM-confirmed (see the function's own honest doc-comment caveat:
    -- the underlying bitmask rule is confirmed for fourthRoom, wrong for
    -- willyRoom, and untested for bank 5/6) -- only that the plumbing
    -- (record -> layout stream -> per-metatile collision byte -> a real
    -- 16x20 boolean grid) works end to end without throwing.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opts = {
      metatileTableFileOffset = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileTableFileOffset,
      metatileGridRows = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileGridRows,
      metatileGridCols = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileGridCols,
    }

    local collisionGrid = RoomFloorLayout.buildCollisionGridFromMapTableRecord(
      romData, profile.mapTableBank6, 0, opts)
    Harness.assertEqual(#collisionGrid, 16)
    Harness.assertEqual(#collisionGrid[1], 20)

    -- Every cell must be a real boolean (not nil/garbage) -- a cheap
    -- structural sanity check.
    local sawTrue, sawFalse = false, false
    for row = 1, 16 do
      for col = 1, 20 do
        local v = collisionGrid[row][col]
        Harness.assertTrue(v == true or v == false,
          string.format("collisionGrid[%d][%d]=%s is not a real boolean", row, col, tostring(v)))
        if v then sawTrue = true else sawFalse = true end
      end
    end
    -- Not a hard ROM fact (a room COULD be all-floor or all-wall), but
    -- for this specific real record (a rendered, eyeballed shrine-style
    -- room, see rom-map.md) both a floor and a border are expected --
    -- a genuine, if soft, regression check that the collision byte
    -- isn't silently constant across the whole grid.
    Harness.assertTrue(sawTrue and sawFalse,
      "expected both walkable and non-walkable cells in a real rendered room, got all one value")
  end
)

Harness.testIfAvailable(
  "RoomFloorLayout.buildRoomFromMapTableRecord: ALL 320 real bank-5/bank-6 records decode without error (2026-08-14, \"andere räume, so viele wie möglich\")",
  romData ~= nil,
  "no development ROM found",
  function()
    -- The room-catalog website export (rom-inspector/tools/export_data.lua)
    -- now runs this exact function across every single one of the 320
    -- real map-table records (256 bank-5 + 64 bank-6), not just the 2
    -- spot-checked bank-6 records the test above already covers. This
    -- is the regression guard for that: if some record's own real RLE
    -- stream or metatile index ever decoded out of range (a genuine
    -- possibility the 2-record spot check wouldn't catch), this test
    -- would fail loudly instead of the website silently shipping a
    -- broken/truncated catalog entry.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local tilesetStart = profile.graphics.environmentTilesetBank12.fileOffsetStart
    local tilesetEnd = profile.graphics.environmentTilesetBank12.fileOffsetEnd
    local metatileOpts = profile.roomFloorLayoutPipeline.unknownRoomACandidates

    local function checkAllRecords(mapTable, label)
      local opts = {
        metatileTableFileOffset = metatileOpts.metatileTableFileOffset,
        tilesetFileOffset = mapTable.tilesetFileOffset,
        metatileGridRows = metatileOpts.metatileGridRows,
        metatileGridCols = metatileOpts.metatileGridCols,
      }
      for recordIndex = 0, mapTable.recordCount - 1 do
        local grid = RoomFloorLayout.buildRoomFromMapTableRecord(romData, mapTable, recordIndex, opts)
        Harness.assertEqual(#grid, 16,
          label .. " record " .. recordIndex .. ": expected 16 real grid rows")
        for row = 1, 16 do
          Harness.assertEqual(#grid[row], 20,
            label .. " record " .. recordIndex .. " row " .. row .. ": expected 20 real grid cols")
          for col = 1, 20 do
            local off = grid[row][col]
            Harness.assertTrue(off >= tilesetStart and off < tilesetEnd,
              string.format("%s record %d: grid[%d][%d]=%#x outside the real environment tileset bounds",
                label, recordIndex, row, col, off))
          end
        end
      end
    end

    checkAllRecords(profile.mapTable, "bank5")
    checkAllRecords(profile.mapTableBank6, "bank6")
  end
)

if romData then
  print("(RoomFloorLayout ROM-dependent tests ran against a real dev ROM)")
end
