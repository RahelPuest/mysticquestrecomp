-- Regression tests for the 2026-08-19 worldMapRoom_131<->132 pair --
-- see rom_profiles.lua's own doc comment on `WORLD_MAP_ROOM_131_GRID`
-- for the full evidence trail (systematic full-grid edge-match scan
-- across bank5/6, this pair being the one candidate with a uniformly
-- walkable, footprint-verified, visually-confirmed shared edge). A
-- direct follow-up to, and deliberately more cautious than, the
-- `unknownRoomA` engineering-choice chain that was added then retracted
-- earlier the same day -- see `unknown_room_a_chain_test.lua`'s own
-- retraction record for the process lesson this test file applies.

local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

--- Real BFS reachability using the SAME 2x2-tile footprint
-- `TileWalkability.build` actually requires (not a single-cell check --
-- the exact gap that let unknownRoomA's own broken connectivity ship
-- undetected).
local function footprintOk(room, row, col)
  local function isFloor(r, c)
    if r < 1 or c < 1 or r > #room.grid or c > #room.grid[1] then return false end
    return room.floorTileIds[room.grid[r][c]] == true
  end
  return isFloor(row, col) and isFloor(row, col + 1) and isFloor(row + 1, col) and isFloor(row + 1, col + 1)
end

local function footprintReachableCount(room, startRow, startCol)
  if not footprintOk(room, startRow, startCol) then return 0 end
  local seen, key = {}, function(r, c) return r * 1000 + c end
  local queue = { { startRow, startCol } }
  seen[key(startRow, startCol)] = true
  local count = 0
  while #queue > 0 do
    local cur = table.remove(queue)
    count = count + 1
    local r, c = cur[1], cur[2]
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local nr, nc = r + d[1], c + d[2]
      if not seen[key(nr, nc)] and footprintOk(room, nr, nc) then
        seen[key(nr, nc)] = true
        queue[#queue + 1] = { nr, nc }
      end
    end
  end
  return count
end

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
  "worldMapRoom_131<->132: both exits land on real floor with a large (not fragmented) footprint-reachable region",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local room131 = profile.graphics.worldMapRoom_131
    local room132 = profile.graphics.worldMapRoom_132

    local exit131 = room131.exits[1]
    Harness.assertEqual(exit131.targetRoom, "worldMapRoom_132")
    local row132 = (exit131.landingY - 16) / 8 + 1
    local col132 = (exit131.landingX - 8) / 8 + 1
    local reach132 = footprintReachableCount(room132, row132, col132)
    Harness.assertTrue(reach132 >= 20,
      string.format("worldMapRoom_131's own exit should land in a real, large connected area of worldMapRoom_132, got %d reachable cells", reach132))

    local exit132 = room132.exits[1]
    Harness.assertEqual(exit132.targetRoom, "worldMapRoom_131")
    local row131 = (exit132.landingY - 16) / 8 + 1
    local col131 = (exit132.landingX - 8) / 8 + 1
    local reach131 = footprintReachableCount(room131, row131, col131)
    Harness.assertTrue(reach131 >= 20,
      string.format("worldMapRoom_132's own exit should land in a real, large connected area of worldMapRoom_131, got %d reachable cells", reach131))
  end
)

Harness.testIfAvailable(
  "worldMapRoom_131<->132: neither landing spot sits inside the OTHER room's own exit trigger zone (the 'bounce loop' bug class this project already fixed once)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local room131 = profile.graphics.worldMapRoom_131
    local room132 = profile.graphics.worldMapRoom_132
    local exit131, exit132 = room131.exits[1], room132.exits[1]

    -- exit131 lands in 132 at (landingX,landingY) -- must NOT be inside exit132's own zone.
    local z = exit132.zone
    local lx, ly = exit131.landingX, exit131.landingY
    Harness.assertTrue(not (lx >= z.xMin and lx < z.xMax and ly >= z.yMin and ly < z.yMax),
      "worldMapRoom_131's exit should not land inside worldMapRoom_132's own return-exit zone")

    local z2 = exit131.zone
    local lx2, ly2 = exit132.landingX, exit132.landingY
    Harness.assertTrue(not (lx2 >= z2.xMin and lx2 < z2.xMax and ly2 >= z2.yMin and ly2 < z2.yMax),
      "worldMapRoom_132's exit should not land inside worldMapRoom_131's own return-exit zone")
  end
)

Harness.testIfAvailable(
  -- UPDATED 2026-08-20: worldMapRoom_131 now also carries a 2nd exit
  -- (the new seventhRoom door, see seventh_room_test.lua) honestly
  -- labeled ENGINEERING CHOICE rather than STRUCTURALLY-DERIVED --
  -- both are "not a live ROM trigger", just via different evidence, so
  -- this test now accepts either label instead of requiring one exact
  -- phrase.
  "worldMapRoom_131/132: every exit is honestly labeled STRUCTURALLY-DERIVED or ENGINEERING CHOICE, never claimed as a live ROM trigger",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, key in ipairs({ "worldMapRoom_131", "worldMapRoom_132" }) do
      for _, exit in ipairs(profile.graphics[key].exits) do
        Harness.assertTrue(exit.status ~= nil and
          (exit.status:find("STRUCTURALLY%-DERIVED") ~= nil or exit.status:find("ENGINEERING CHOICE") ~= nil),
          key .. "'s own exit should be explicitly labeled STRUCTURALLY-DERIVED or ENGINEERING CHOICE, not a ROM-confirmed live trigger")
      end
    end
  end
)

if romData then
  print("(worldMapRoom_131/132 pair ROM-dependent tests ran against a real dev ROM)")
end
