local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Real room wired 2026-08-16, direct user report: "im zweiten
-- Bossraum nachdem der Boss besiegt wurde öffnet sich das im Norden --
-- das ist der Weg in den nächsten Raum". See rom_profiles.lua's own
-- doc comment on `sixthRoom.exits`/`seventhRoom` for the full honest
-- provenance: seventhRoom is a real, decoded bank-5 room-catalog entry
-- (mapTable record 220) this project chose as sixthRoom's own north
-- destination -- not an independently ROM-confirmed connection, same
-- evidentiary category as `secondBoss` itself.
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
    -- The zone sits directly under this room's own real, already-
    -- decoded gate/pillar tiles (136/137, rows 0-3, cols 16-17) --
    -- see rom_profiles.lua's own doc comment for the full reasoning.
    Harness.assertEqual(sixth.grid[1][17], 136)
    Harness.assertEqual(sixth.grid[1][18], 137)
  end
)

Harness.testIfAvailable(
  "seventhRoom: real bank-5 catalog data (mapTable record 220), structurally sound",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local seventh = profile.graphics.seventhRoom
    Harness.assertTrue(seventh ~= nil, "expected profile.graphics.seventhRoom to exist")
    Harness.assertEqual(seventh.cols, 20)
    Harness.assertEqual(seventh.rows, 16)
    Harness.assertEqual(#seventh.grid, 16)
    for r = 1, 16 do
      Harness.assertEqual(#seventh.grid[r], 20)
    end

    -- Every real tileOffset is a real, in-bounds, non-trivial ROM
    -- address (same "not garbage" check every other room's own test
    -- already runs).
    for id, offset in pairs(seventh.tileOffsets) do
      Harness.assertTrue(offset >= 0 and offset + 16 <= #romData,
        "expected tile " .. id .. "'s offset to be a real, in-bounds ROM address")
      local allZero = true
      for i = 0, 15 do
        if romData:byte(offset + i + 1) ~= 0 then allZero = false; break end
      end
      Harness.assertTrue(not allZero, "expected tile " .. id .. "'s real bytes to be non-trivial")
    end

    -- Every grid cell's own tile ID must have a real tileOffset entry
    -- (no dangling/undefined tile references).
    for r = 1, 16 do
      for c = 1, 20 do
        local id = seventh.grid[r][c]
        Harness.assertTrue(seventh.tileOffsets[id] ~= nil,
          string.format("grid cell (%d,%d) references tile %d with no real tileOffset", r, c, id))
      end
    end
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
