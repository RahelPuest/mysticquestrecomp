local Harness = require("tests.harness")
local RoomSelectorTable = require("src.import.RoomSelectorTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Synthetic-data test: exercise the record decoder against a hand-built
-- 11-byte record so the field layout itself is verified independent of
-- any real ROM, per the "headlessly testable" rule.
Harness.test("RoomSelectorTable.decodeRecord: parses a synthetic 11-byte record", function()
  -- Matches the real roomSelector=1 record found live this session:
  -- 00 00 00 b0 40 80 06 00 40 0e 11
  local rom = "\0\0\0\176\64\128\6\0\64\14\17"
  local roomSelectorTable = { fileOffset = 0, recordLength = 11, recordCount = 1 }
  local rec = RoomSelectorTable.decodeRecord(rom, roomSelectorTable, 0)
  Harness.assertEqual(rec.index, 0)
  Harness.assertEqual(rec.offsetParam, 0x4000) -- $4000 + 0x0000
  Harness.assertEqual(rec.tileSourcePointer, 0x40B0) -- bytes 3-4, LE
  Harness.assertEqual(rec.dynamicBank, 6) -- byte 6
  Harness.assertEqual(rec.stagedPointer, 0x4000) -- bytes 7-8, LE
end)

Harness.test("RoomSelectorTable.decodeRecord: fails loudly on an out-of-range index", function()
  local rom = string.rep("\0", 11)
  local roomSelectorTable = { fileOffset = 0, recordLength = 11, recordCount = 1 }
  local ok = pcall(RoomSelectorTable.decodeRecord, rom, roomSelectorTable, 1)
  Harness.assertTrue(not ok, "expected decode to raise on an out-of-range roomSelector")
end)

Harness.test("RoomSelectorTable.groupByTileSource: groups selectors sharing a room", function()
  local records = {
    { index = 0, tileSourcePointer = 0x40B0 },
    { index = 1, tileSourcePointer = 0x40B0 },
    { index = 2, tileSourcePointer = 0x46B0 },
  }
  local groups = RoomSelectorTable.groupByTileSource(records)
  Harness.assertEqual(#groups[0x40B0], 2)
  Harness.assertEqual(groups[0x40B0][1], 0)
  Harness.assertEqual(groups[0x40B0][2], 1)
  Harness.assertEqual(#groups[0x46B0], 1)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "RoomSelectorTable.decodeAll: real ROM's 16 records, grouped, match this session's live traces",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = RoomSelectorTable.decodeAll(romData, profile.roomSelectorTable)
    Harness.assertEqual(#records, 16)

    -- Real, live-confirmed values (see rom-map.md "BREAKTHROUGH: the
    -- real room table, found" and its cross-check section).
    Harness.assertEqual(records[1].tileSourcePointer, 0x40B0) -- roomSelector 0
    Harness.assertEqual(records[2].tileSourcePointer, 0x40B0) -- roomSelector 1 (live-confirmed via $C3F5 twice)
    Harness.assertEqual(records[2].dynamicBank, 6) -- live-confirmed $C3F0

    local groups = RoomSelectorTable.groupByTileSource(records)
    Harness.assertEqual(#groups[0x40B0], 2)
    Harness.assertEqual(#groups[0x46B0], 5) -- willyRoom/secondRoom/thirdRoom family
    Harness.assertEqual(#groups[0x4938], 6) -- unknownRoomA family
    Harness.assertEqual(#groups[0x43B0], 2) -- unknownRoomB family
    Harness.assertEqual(#groups[0x4C1A], 1) -- pre-transition placeholder

    -- Real length bound: byte 6 (dynamicBank) must be a valid bank for
    -- this 16-bank ROM.
    for _, rec in ipairs(records) do
      Harness.assertTrue(rec.dynamicBank >= 0 and rec.dynamicBank < 16,
        "roomSelector " .. rec.index .. " has an out-of-range dynamicBank " .. rec.dynamicBank)
    end
  end
)

-- WIRING (2026-08-10, direct user instruction "geh mal 1 an" -- the
-- biggest P4 gap: the real bank-8 table and this project's own
-- already-implemented rooms were two separately-maintained parallel
-- data sets, cross-referenced only in prose ("an honest, unreconciled
-- note" in rom-map.md), never actually enforced. This test makes that
-- link a real, automated invariant: every implemented room's own
-- `romRoomSelectors` field (rom_profiles.lua) must equal the REAL
-- selector group the live-decoded ROM table itself produces for that
-- room's `tileSourcePointer` -- not a re-assertion of the same magic
-- numbers twice, an actual cross-check that would fail loudly the
-- moment either side drifts from the other.
Harness.testIfAvailable(
  "RoomSelectorTable <-> rom_profiles.lua wiring: every implemented room's romRoomSelectors matches the REAL decoded table",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = RoomSelectorTable.decodeAll(romData, profile.roomSelectorTable)
    local groups = RoomSelectorTable.groupByTileSource(records)

    local function sortedCopy(t)
      local copy = {}
      for i, v in ipairs(t) do copy[i] = v end
      table.sort(copy)
      return copy
    end

    local function assertRoomMatchesRealTable(roomName)
      local room = profile.graphics[roomName]
      Harness.assertTrue(room ~= nil, "profile.graphics." .. roomName .. " does not exist")
      Harness.assertTrue(room.romRoomSelectors ~= nil,
        roomName .. " has no romRoomSelectors field to cross-check against the real ROM table")

      local claimed = sortedCopy(room.romRoomSelectors)
      Harness.assertTrue(#claimed > 0, roomName .. ".romRoomSelectors is empty")

      -- The real table's own tileSourcePointer for this room's first
      -- claimed selector -- then every OTHER claimed selector must
      -- share that exact same real pointer too (not just the first).
      local realPointer = records[claimed[1] + 1].tileSourcePointer
      for _, selector in ipairs(claimed) do
        Harness.assertEqual(records[selector + 1].tileSourcePointer, realPointer,
          roomName .. ": claimed selector " .. selector ..
          " does not share " .. roomName .. "'s real tileSourcePointer in the live table")
      end

      -- And the real group for that pointer must be EXACTLY the
      -- claimed set -- not a subset (missing a real sibling selector)
      -- and not a superset (claiming one that doesn't really belong).
      local realGroup = sortedCopy(groups[realPointer])
      Harness.assertEqual(#claimed, #realGroup,
        roomName .. ": claims " .. #claimed .. " selectors " ..
        "but the real table's own group for pointer " .. string.format("0x%04X", realPointer) ..
        " has " .. #realGroup)
      for i = 1, #claimed do
        Harness.assertEqual(claimed[i], realGroup[i],
          roomName .. ": selector mismatch at sorted position " .. i)
      end
    end

    assertRoomMatchesRealTable("willyRoom")
    assertRoomMatchesRealTable("secondRoom")
    assertRoomMatchesRealTable("thirdRoom")
    assertRoomMatchesRealTable("fourthRoom")
    assertRoomMatchesRealTable("startRoom")

    -- Real, live-confirmed fact this cross-check should reproduce
    -- structurally (not just re-assert): willyRoom/secondRoom/thirdRoom
    -- share ONE real roomSelector family, fourthRoom/startRoom share a
    -- DIFFERENT one -- i.e. rom_profiles.lua's own family grouping
    -- (which rooms list identical romRoomSelectors) must match which
    -- rooms the real ROM table itself groups under the same pointer.
    local willyPtr = records[profile.graphics.willyRoom.romRoomSelectors[1] + 1].tileSourcePointer
    local secondPtr = records[profile.graphics.secondRoom.romRoomSelectors[1] + 1].tileSourcePointer
    local thirdPtr = records[profile.graphics.thirdRoom.romRoomSelectors[1] + 1].tileSourcePointer
    local fourthPtr = records[profile.graphics.fourthRoom.romRoomSelectors[1] + 1].tileSourcePointer
    local startPtr = records[profile.graphics.startRoom.romRoomSelectors[1] + 1].tileSourcePointer
    Harness.assertEqual(willyPtr, secondPtr, "willyRoom/secondRoom should share one real roomSelector family")
    Harness.assertEqual(secondPtr, thirdPtr, "secondRoom/thirdRoom should share one real roomSelector family")
    Harness.assertEqual(fourthPtr, startPtr, "fourthRoom/startRoom should share one real roomSelector family")
    Harness.assertTrue(willyPtr ~= fourthPtr,
      "willyRoom family and fourthRoom family should NOT be the same real roomSelector family")
  end
)

Harness.testIfAvailable(
  "RoomSelectorTable.resolveMapRoomPointersFileOffset: roomSelector 0/1's own real 'mapRoomPointers' field IS bank5/bank6's own map-table start (2026-08-14, new structural find)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Direct follow-up to a real user push to keep investigating
    -- ("versuche andere methoden... es muss ja auf die eine oder
    -- andere art exsistieren"): cross-referencing the external
    -- FFA-Disassembly project's own documented US-ROM MAP_HEADER
    -- format ("tilesetGfx, metatiles, mapRoomPointers, ...") against
    -- this EU ROM's own previously-undocumented `offsetParam` field
    -- found the real, byte-exact match this test locks in.
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = RoomSelectorTable.decodeAll(romData, profile.roomSelectorTable)

    local sel0 = records[0 + 1]
    local sel1 = records[1 + 1]
    local sel0File = RoomSelectorTable.resolveMapRoomPointersFileOffset(sel0)
    local sel1File = RoomSelectorTable.resolveMapRoomPointersFileOffset(sel1)

    Harness.assertEqual(sel0File, profile.mapTable.bankFileStart,
      "roomSelector 0's own real mapRoomPointers should resolve to bank5 mapTable's own real start")
    Harness.assertEqual(sel1File, profile.mapTableBank6.bankFileStart,
      "roomSelector 1's own real mapRoomPointers should resolve to bank6 mapTableBank6's own real start")

    -- Not just the address -- the real BYTES there must be mapTable's/
    -- mapTableBank6's own already-VERIFIED header, byte for byte (the
    -- decisive, not-a-coincidence proof).
    local bytesAtSel0 = romData:sub(sel0File + 1, sel0File + 4)
    local bytesAtSel1 = romData:sub(sel1File + 1, sel1File + 4)
    Harness.assertEqual(bytesAtSel0, "\0\3\16\16", "roomSelector 0's mapRoomPointers target should be mapTable's own real [00 03 10 10] header")
    Harness.assertEqual(bytesAtSel1, "\0\4\8\8", "roomSelector 1's mapRoomPointers target should be mapTableBank6's own real [00 04 08 08] header")
  end
)
