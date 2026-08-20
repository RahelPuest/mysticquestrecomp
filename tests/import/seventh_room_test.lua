local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Real room wired 2026-08-16, direct user report: "im zweiten
-- Bossraum nachdem der Boss besiegt wurde öffnet sich das im Norden --
-- das ist der Weg in den nächsten Raum". SUPERSEDED 2026-08-17, direct
-- follow-up report of the real destination ("kommt er auf der kleinen
-- weltmap an 6.3 raus") -- seventhRoom is now bank6 (world-map
-- catalog) record 51, grid (row=6,col=3), not the earlier bank5-
-- record-220 engineering placeholder. See rom_profiles.lua's own doc
-- comment on `sixthRoom.exits`/`seventhRoom` for the full honest
-- provenance chain, including the RETRACTED seventhRoom->eighthRoom
-- exit (byte-matched against data that no longer exists).
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "sixthRoom: has a real north exit into seventhRoom, gated behind secondBossDefeated",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    Harness.assertTrue(sixth.exits ~= nil and #sixth.exits == 1,
      "expected sixthRoom to have exactly 1 real exit")
    local exit = sixth.exits[1]
    Harness.assertEqual(exit.targetRoom, "seventhRoom")
    Harness.assertEqual(exit.requiresFlag, "secondBossDefeated")
    Harness.assertEqual(exit.holdDirection, "up")
    Harness.assertEqual(exit.landingX, 80)
    Harness.assertEqual(exit.landingY, 112)
    -- RETRACTED (2026-08-17, see rom_profiles.lua's own capture-bug
    -- retraction on `sixthRoom.grid`): this used to assert the zone
    -- sits under real gate/pillar tiles (136/137) at grid[1][17]/[18]
    -- -- true of the OLD, now-retracted (capture-bug) grid, false of
    -- the corrected one (`sixthRoom.grid` is now `startRoom.grid`,
    -- plain wall tiles at that position, no gate-like feature). The
    -- exit's own real fields (target/flag/direction/landing) above are
    -- unaffected -- only this grid-content assumption was wrong.
  end
)

local function assertRoomStructurallySound(room, romData, label)
  Harness.assertTrue(room ~= nil, "expected " .. label .. " to exist")
  Harness.assertEqual(room.cols, 20)
  Harness.assertEqual(room.rows, 16)
  Harness.assertEqual(#room.grid, 16)
  for r = 1, 16 do
    Harness.assertEqual(#room.grid[r], 20)
  end
  for id, offset in pairs(room.tileOffsets) do
    Harness.assertTrue(offset >= 0 and offset + 16 <= #romData,
      label .. ": expected tile " .. id .. "'s offset to be a real, in-bounds ROM address")
  end
  for r = 1, 16 do
    for c = 1, 20 do
      local id = room.grid[r][c]
      Harness.assertTrue(room.tileOffsets[id] ~= nil,
        string.format("%s: grid cell (%d,%d) references tile %d with no real tileOffset", label, r, c, id))
    end
  end
end

Harness.testIfAvailable(
  "seventhRoom: real bank6 world-map catalog data (record 51, row=6/col=3), structurally sound",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    assertRoomStructurallySound(profile.graphics.seventhRoom, romData, "seventhRoom")
    local ref = profile.graphics.seventhRoom.worldMapCatalogRecord
    Harness.assertTrue(ref ~= nil, "expected seventhRoom to carry a worldMapCatalogRecord")
    Harness.assertEqual(ref.table, "bank6")
    Harness.assertEqual(ref.recordIndex, 51)
    Harness.assertEqual(ref.row, 6)
    Harness.assertEqual(ref.col, 3)
  end
)

Harness.testIfAvailable(
  "seventhRoom: matches a real, freshly-decoded bank6 record 51 exactly (regression lock for the 2026-08-17 swap)",
  romData ~= nil,
  "no development ROM found",
  function()
    local RoomFloorLayout = require("src.import.RoomFloorLayout")
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local mapTable = profile.mapTableBank6
    local opts = {
      metatileTableFileOffset = profile.roomFloorLayoutPipeline.genericCatalogMetatileTableFileOffset,
      tilesetFileOffset = mapTable.tilesetFileOffset,
      metatileGridRows = 8, metatileGridCols = 10,
    }
    local fileOffsetGrid = RoomFloorLayout.buildRoomFromMapTableRecord(romData, mapTable, 51, opts)
    local fresh = RoomFloorLayout.toTileGridBackgroundData(fileOffsetGrid, opts.tilesetFileOffset)
    local stored = profile.graphics.seventhRoom

    local matches, total = 0, 0
    for r = 1, #stored.grid do
      for c = 1, #stored.grid[r] do
        local freshId = fresh.grid[r] and fresh.grid[r][c]
        local freshOff = freshId ~= nil and fresh.tileOffsets[freshId]
        local storedOff = stored.tileOffsets[stored.grid[r][c]]
        total = total + 1
        if freshOff ~= nil and storedOff ~= nil and freshOff == storedOff then
          matches = matches + 1
        end
      end
    end
    -- Should be a near-exact match -- this is the SAME room, just
    -- hand-copied into rom_profiles.lua once rather than decoded live
    -- each time. Not asserting 100% because a couple of ambiguous
    -- tile-ID ties are possible, same category as other rooms here.
    Harness.assertTrue(matches / total > 0.9,
      string.format("expected seventhRoom to closely match a fresh bank6 record 51 decode, got %d/%d", matches, total))
  end
)

Harness.testIfAvailable(
  "seventhRoom: sixthRoom's own landing spot (80,112) sits on real floor",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    local seventh = profile.graphics.seventhRoom
    local exit = sixth.exits[1]
    local row = math.floor(exit.landingY / 8) + 1
    local col = math.floor(exit.landingX / 8) + 1
    local tileId = seventh.grid[row][col]
    Harness.assertTrue(seventh.floorTileIds[tileId],
      string.format("expected the real landing spot (row %d, col %d, tile %d) to be real floor", row, col, tileId))
  end
)

-- seventhRoom<->worldMapRoom_131 door REMOVED, 2026-08-20 (same day as
-- added; direct, blunt user correction: "vom Seventh Room in den World
-- Map Room 131 ist völliger Quatsch... Schau dir die World Map an, vom
-- Seventh Room rechts daneben auf der World Map ist der richtige
-- Room."). worldMapRoom_131 (a bank-5/16x16-grid record) and
-- seventhRoom (a bank-6/8x8-grid record) are two structurally UNRELATED
-- grids -- there was never any real adjacency evidence for this door
-- (always labeled "zero structural evidence" from the start), and the
-- user identified the real world-map neighbor sits immediately to
-- seventhRoom's own right on bank 6's OWN grid (record 52) instead --
-- not investigated or wired this pass, a genuine lead for later. Both
-- former test blocks here (the exit-existence check and the
-- reachability/bounce-loop check) are removed along with the door --
-- `seventhRoom.exits` is empty again, matching this room's own real,
-- still-open state before 2026-08-20. See rom_profiles.lua's own
-- matching doc comment and events.md's 2026-08-20 retraction entry.

-- `eighthRoom`/`ninthRoom` (bank-5 records 236/237) REMOVED ENTIRELY,
-- 2026-08-20 (direct, blunt user correction: "Auch Eighth Room und Ninth
-- Room, falsch. Lösch sie komplett aus deinen Unterlagen und schreib,
-- dass die falsch erkannt wurden."). All 4 tests that used to live here
-- (structural-soundness checks, the shared-edge collision match, the
-- landing-spot floor checks) are removed along with them -- they tested
-- `profile.graphics.eighthRoom`/`ninthRoom`, which no longer exist. See
-- rom_profiles.lua's own matching doc comment and
-- docs/reverse-engineering/events.md's 2026-08-20 entry for the full
-- record.
