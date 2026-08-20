-- worldMapRoom_131<->132 connectivity REMOVED, 2026-08-20 (direct,
-- blunt user correction: "die Konnektivität, die du da gemacht hast,
-- ist völliger Bullshit... Mach die 131 raus, mach die 132 raus").
-- Every exit-dependent test that used to live here (both exits' own
-- footprint reachability, the bounce-loop check, the exit-label check)
-- is removed along with the doors -- `worldMapRoom_131`/`132.exits` are
-- both empty again. The underlying 100% tile-exact edge match between
-- these two records is still a real, measured byte fact about their
-- shared border, but the user's report that the resulting connectivity
-- is wrong is taken at face value here, not re-litigated. Room CONTENT
-- (`grid`/`tileOffsets`/`floorTileIds`) is untouched, still real decoded
-- ROM data -- see rom_profiles.lua's own matching doc comment and
-- events.md's 2026-08-20 retraction entry for the full record.
--
-- The one test kept below checks room CONTENT only (no exits involved)
-- and stays real and valid regardless of the connectivity retraction.

local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "worldMapRoom_131/132: every tile ID's collision is internally consistent (the exact audit that caught unknownRoomA's own broken set)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, key in ipairs({ "worldMapRoom_131", "worldMapRoom_132" }) do
      local room = profile.graphics[key]
      local seenWalkability = {}
      for r = 1, #room.grid do
        for c = 1, #room.grid[r] do
          local id = room.grid[r][c]
          local walkable = room.floorTileIds[id] == true
          if seenWalkability[id] == nil then
            seenWalkability[id] = walkable
          else
            Harness.assertEqual(seenWalkability[id], walkable,
              string.format("%s: tile %d should have ONE consistent walkability value, not conflicting per-cell", key, id))
          end
        end
      end
    end
  end
)

Harness.testIfAvailable(
  "worldMapRoom_131/132: both rooms carry no exits (connectivity retracted 2026-08-20)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, key in ipairs({ "worldMapRoom_131", "worldMapRoom_132" }) do
      Harness.assertEqual(#profile.graphics[key].exits, 0,
        key .. " should have zero exits -- connectivity is retracted")
    end
  end
)

if romData then
  print("(worldMapRoom_131/132 pair ROM-dependent tests ran against a real dev ROM)")
end
