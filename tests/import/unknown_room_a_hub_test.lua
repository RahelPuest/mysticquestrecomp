-- Regression tests for the 2026-08-20 unknownRoomA_8..13 <-> worldMapRoom_132
-- hub-and-spoke connectivity -- see rom_profiles.lua's own doc comment on
-- unknownRoomA_8's `exits` for the full rationale (fixed position-aware
-- collision, zero structural edge-match evidence among the 6 rooms
-- themselves, so each is wired independently off the hub instead of
-- chained). Uses the SAME real production movement code
-- (TileWalkability + VictorySequence's own unknownRoomA collision
-- special-case) as seventh_room_test.lua's own 2026-08-20 rewrite, not a
-- hand-derived row/col conversion -- the exact discipline that caught a
-- real bug before any live run this same day.

local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local TileWalkability = require("src.entities.TileWalkability")

local romData = DevRomLocator.find()

--- Mirrors VictorySequence:ensureRoomLoaded's own real per-room dispatch
-- (see that file's 2026-08-20 doc comment) so this test exercises the
-- exact same collision the game itself uses for each room.
local function canMoveToFor(profile, roomKey)
  local isUnknownRoomA = roomKey:match("^unknownRoomA_(%d+)$") ~= nil
  if isUnknownRoomA then
    local recordIndex = tonumber(roomKey:match("^unknownRoomA_(%d+)$"))
    local candidates = profile.roomFloorLayoutPipeline.unknownRoomACandidates
    local opts = {
      metatileTableFileOffset = candidates.metatileTableFileOffset,
      tilesetFileOffset = candidates.tilesetFileOffset,
      metatileGridRows = candidates.metatileGridRows,
      metatileGridCols = candidates.metatileGridCols,
    }
    local collisionGrid = RoomFloorLayout.buildCollisionGridFromMapTableRecord(
      romData, profile.mapTable, recordIndex, opts)
    return TileWalkability.buildFromCollisionGrid(collisionGrid, 16, 16)
  end
  return TileWalkability.build(profile.graphics[roomKey], 16, 16)
end

local function pixelReachable(canMoveTo, startX, startY, targetX, targetY)
  if not (canMoveTo(startX, startY) and canMoveTo(targetX, targetY)) then return false end
  local seen, key = {}, function(x, y) return x * 100000 + y end
  seen[key(startX, startY)] = true
  local queue, head = { { startX, startY } }, 1
  while head <= #queue do
    local x, y = queue[head][1], queue[head][2]
    head = head + 1
    if x == targetX and y == targetY then return true end
    for _, d in ipairs({ { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 } }) do
      local nx, ny = x + d[1], y + d[2]
      if not seen[key(nx, ny)] and canMoveTo(nx, ny) then
        seen[key(nx, ny)] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return false
end

local SPOKES = { "unknownRoomA_8", "unknownRoomA_9", "unknownRoomA_10",
  "unknownRoomA_11", "unknownRoomA_12", "unknownRoomA_13" }

Harness.testIfAvailable(
  "worldMapRoom_132: exactly 7 outgoing exits (1 pre-existing to worldMapRoom_131 + 6 new unknownRoomA spokes)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    Harness.assertEqual(#profile.graphics.worldMapRoom_132.exits, 7)
  end
)

for _, spoke in ipairs(SPOKES) do
  Harness.testIfAvailable(
    spoke .. "<->worldMapRoom_132: both landing spots are reachable via the REAL production movement code, and neither new exit's zone overlaps the other side's landing spot",
    romData ~= nil,
    "no development ROM found",
    function()
      local profile = RomProfiles.match(RomIdentity.identify(romData))
      local room = profile.graphics[spoke]
      local hub = profile.graphics.worldMapRoom_132

      Harness.assertEqual(#room.exits, 1, spoke .. " should have exactly 1 outgoing exit")
      local outExit = room.exits[1]
      Harness.assertEqual(outExit.targetRoom, "worldMapRoom_132")

      -- Find the matching hub exit (targeting this spoke).
      local hubExit
      for _, e in ipairs(hub.exits) do
        if e.targetRoom == spoke then hubExit = e end
      end
      Harness.assertTrue(hubExit ~= nil, "worldMapRoom_132 should have a real exit targeting " .. spoke)

      -- `outExit.landingX/Y` (the spoke's own exit) is where the player
      -- appears IN THE HUB; `hubExit.landingX/Y` (the hub's exit
      -- targeting this spoke) is where the player appears IN THE SPOKE
      -- -- opposite of what the field names might suggest at a glance
      -- (matches the established convention: `exit.landingX/Y` is always
      -- in the TARGET room's own coordinate space, never the room
      -- defining the exit).
      local canMoveToHub = canMoveToFor(profile, "worldMapRoom_132")
      Harness.assertTrue(pixelReachable(canMoveToHub, 48, 112, outExit.landingX, outExit.landingY),
        spoke .. "'s own hub landing spot should be really reachable in worldMapRoom_132")

      -- Spoke's own landing (from the hub) reachable, and its own
      -- return-exit zone reachable from that landing.
      local canMoveToSpoke = canMoveToFor(profile, spoke)
      Harness.assertTrue(canMoveToSpoke(hubExit.landingX, hubExit.landingY),
        spoke .. "'s own landing spot (from the hub) should be real, walkable floor")
      Harness.assertTrue(pixelReachable(canMoveToSpoke, hubExit.landingX, hubExit.landingY, outExit.zone.xMin, outExit.zone.yMin),
        spoke .. "'s own return-exit zone should be reachable from its own landing spot")

      -- Bounce-loop check: the spoke's own landing (from the hub) must
      -- not sit inside its own return-exit zone.
      local sz = outExit.zone
      Harness.assertTrue(not (hubExit.landingX >= sz.xMin and hubExit.landingX < sz.xMax
        and hubExit.landingY >= sz.yMin and hubExit.landingY < sz.yMax),
        spoke .. ": own landing spot (from the hub) should not sit inside own return-exit zone")

      -- Bounce-loop check: the hub landing (for this spoke) must not sit
      -- inside this spoke's own outgoing hub-zone.
      local hz = hubExit.zone
      Harness.assertTrue(not (outExit.landingX >= hz.xMin and outExit.landingX < hz.xMax
        and outExit.landingY >= hz.yMin and outExit.landingY < hz.yMax),
        spoke .. ": hub landing should not sit inside this spoke's own outgoing hub-zone")
    end
  )
end

Harness.testIfAvailable(
  "worldMapRoom_132: the pre-existing exit-to-131's own landing spot, AFTER Player:update's real bounds clamp, does not sit inside any of the 6 new unknownRoomA hub-exit zones (a real bug caught this way, not by the reachability tests above)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local hub = profile.graphics.worldMapRoom_132
    -- worldMapRoom_131's own exit into this room lands at raw (120,128) --
    -- Player:update's own unconditional bounds clamp (maxY = ROOM_H -
    -- HUD_H - 16 = 112) snaps this to (120,112) on the very next real
    -- tick, before any input is even read.
    local clampedX, clampedY = 120, 112
    for _, exit in ipairs(hub.exits) do
      if exit.targetRoom ~= "worldMapRoom_131" then
        local z = exit.zone
        Harness.assertTrue(not (clampedX >= z.xMin and clampedX < z.xMax
          and clampedY >= z.yMin and clampedY < z.yMax),
          "the real (post-clamp) worldMapRoom_131 landing spot should not sit inside the exit-to-" .. exit.targetRoom .. " zone")
      end
    end
  end
)

Harness.testIfAvailable(
  "worldMapRoom_132: all 6 new unknownRoomA hub-exit zones are mutually non-overlapping and clear of the pre-existing exit-to-131 zone",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local hub = profile.graphics.worldMapRoom_132
    for i = 1, #hub.exits do
      for j = i + 1, #hub.exits do
        local a, b = hub.exits[i].zone, hub.exits[j].zone
        local overlapX = a.xMin < b.xMax and b.xMin < a.xMax
        local overlapY = a.yMin < b.yMax and b.yMin < a.yMax
        Harness.assertTrue(not (overlapX and overlapY),
          string.format("worldMapRoom_132 exits #%d (%s) and #%d (%s) should not overlap",
            i, hub.exits[i].targetRoom, j, hub.exits[j].targetRoom))
      end
    end
  end
)

Harness.testIfAvailable(
  "unknownRoomA_8..13: every exit is honestly labeled ENGINEERING CHOICE, never claimed as a live ROM trigger",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for _, spoke in ipairs(SPOKES) do
      for _, exit in ipairs(profile.graphics[spoke].exits) do
        Harness.assertTrue(exit.status ~= nil and exit.status:find("ENGINEERING CHOICE") ~= nil,
          spoke .. "'s own exit should be explicitly labeled ENGINEERING CHOICE")
      end
    end
  end
)

if romData then
  print("(unknownRoomA hub-and-spoke ROM-dependent tests ran against a real dev ROM)")
end
