-- Regression tests for the 2026-08-19 engineering-choice exit chain
-- connecting seventhRoom -> unknownRoomA_8 -> 9 -> 10 -> 11 -> 12 -> 13
-- (see rom_profiles.lua's own doc comment on `graphics.unknownRoomA_8`
-- for the full "policy change, direct user instruction" story). Every
-- landing tile is checked against the real, already-decoded
-- `floorTileIds` for its OWN target room -- the doors/positions are
-- invented (explicitly, honestly labeled `status = "ENGINEERING
-- CHOICE, not ROM-derived"` in the data itself), but this test locks
-- in that the invented geometry is at least internally consistent
-- (never landing a player inside a wall), not just eyeballed once.

local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

--- Asserts `room.exits[1]` (must exist) targets `expectedTarget` and
-- lands on real, confirmed floor in the target room's own grid.
local function assertExitLandsOnFloor(profile, roomKey, expectedTarget)
  local room = profile.graphics[roomKey]
  Harness.assertTrue(room ~= nil, roomKey .. " should exist in profile.graphics")
  Harness.assertTrue(room.exits ~= nil and #room.exits >= 1,
    roomKey .. " should have at least 1 exit (the new engineering-choice door)")
  local exit = room.exits[1]
  Harness.assertEqual(exit.targetRoom, expectedTarget)

  local target = profile.graphics[expectedTarget]
  Harness.assertTrue(target ~= nil, expectedTarget .. " should exist in profile.graphics")
  local tileX = (exit.landingX - 8) / 8
  local tileY = (exit.landingY - 16) / 8
  Harness.assertTrue(tileX == math.floor(tileX) and tileY == math.floor(tileY),
    roomKey .. "'s own landingX/landingY should land exactly on a tile boundary")
  local row, col = tileY + 1, tileX + 1
  Harness.assertTrue(target.grid[row] ~= nil and target.grid[row][col] ~= nil,
    string.format("%s -> %s: landing row/col (%d,%d) should be inside the target room's real grid",
      roomKey, expectedTarget, row, col))
  local tileId = target.grid[row][col]
  Harness.assertTrue(target.floorTileIds[tileId],
    string.format("%s -> %s: landing tile (row %d, col %d, tile %d) should be real, confirmed floor",
      roomKey, expectedTarget, row, col, tileId))
end

Harness.testIfAvailable(
  "unknownRoomA engineering-choice chain: every link lands on real, confirmed floor (2026-08-19)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    assertExitLandsOnFloor(profile, "seventhRoom", "unknownRoomA_8")
    assertExitLandsOnFloor(profile, "unknownRoomA_8", "unknownRoomA_9")
    assertExitLandsOnFloor(profile, "unknownRoomA_9", "unknownRoomA_10")
    assertExitLandsOnFloor(profile, "unknownRoomA_10", "unknownRoomA_11")
    assertExitLandsOnFloor(profile, "unknownRoomA_11", "unknownRoomA_12")
    assertExitLandsOnFloor(profile, "unknownRoomA_12", "unknownRoomA_13")
  end
)

Harness.testIfAvailable(
  "unknownRoomA engineering-choice chain: unknownRoomA_13 is the deliberate dead end (no further exit)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local room13 = profile.graphics.unknownRoomA_13
    Harness.assertTrue(room13.exits == nil or #room13.exits == 0,
      "unknownRoomA_13 should have no outgoing exit -- its own real floor doesn't support a clean 7th door")
  end
)

Harness.testIfAvailable(
  "unknownRoomA engineering-choice chain: every new exit is honestly labeled, not claimed as ROM-derived",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, roomKey in ipairs({
      "seventhRoom", "unknownRoomA_8", "unknownRoomA_9",
      "unknownRoomA_10", "unknownRoomA_11", "unknownRoomA_12",
    }) do
      local room = profile.graphics[roomKey]
      for _, exit in ipairs(room.exits) do
        Harness.assertTrue(exit.status ~= nil and exit.status:find("ENGINEERING CHOICE") ~= nil,
          roomKey .. "'s own new exit should be explicitly labeled as an engineering choice, not a ROM fact")
      end
    end
  end
)

if romData then
  print("(unknownRoomA chain ROM-dependent tests ran against a real dev ROM)")
end
