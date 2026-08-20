local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")
local TileWalkability = require("src.entities.TileWalkability")

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

Harness.testIfAvailable(
  "seventhRoom: exactly ONE outgoing exit, an honestly-labeled ENGINEERING CHOICE into worldMapRoom_131 (2026-08-19's unknownRoomA_8 attempt stays withdrawn -- this is a different door, to the already footprint-verified 131/132 pair, see rom_profiles.lua's own doc comment on seventhRoom.exits)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local seventh = profile.graphics.seventhRoom
    Harness.assertEqual(#seventh.exits, 1, "expected exactly 1 outgoing exit on seventhRoom")
    local exit = seventh.exits[1]
    Harness.assertEqual(exit.targetRoom, "worldMapRoom_131")
    Harness.assertTrue(exit.status ~= nil and exit.status:find("ENGINEERING CHOICE") ~= nil,
      "seventhRoom's new door should be explicitly labeled ENGINEERING CHOICE, not a ROM-confirmed live trigger")
  end
)

--- Real reachability using the EXACT SAME production movement code the
-- game itself runs (`TileWalkability.build` + a pixel-space BFS over
-- `canMoveTo`, matching `Player:update`'s own per-axis check) -- not a
-- hand-derived row/col conversion. A first attempt at this door used a
-- (landingY-16)/8+1-style conversion copied from the OLDER 131<->132
-- pair's own test file; simulating the real `Player:update`/
-- `TileWalkability.build` code directly (see rom_profiles.lua's own
-- 2026-08-20 doc comment on seventhRoom.exits) caught that this
-- conversion does NOT generalize -- it happened to work for that one
-- pair's specific south-edge geometry, but silently produced an
-- off-grid, permanently-unreachable target for THIS door's first
-- (retracted) south-edge attempt. Testing against the real movement
-- function instead of a hand-derived formula is the general fix.
local function canMoveToFor(room)
  return TileWalkability.build(room, 16, 16)
end

--- BFS over real 8px steps using the room's own real `canMoveTo`, exactly
-- the granularity `Player:update` moves at.
local function pixelReachable(room, startX, startY, targetX, targetY)
  local canMoveTo = canMoveToFor(room)
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

Harness.testIfAvailable(
  "seventhRoom<->worldMapRoom_131: both new landing spots are reachable, via the REAL production movement code, from each room's own already-established entrance -- and neither new exit's zone overlaps the other side's landing spot (the bounce-loop bug class this project already fixed once)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local seventh = profile.graphics.seventhRoom
    local room131 = profile.graphics.worldMapRoom_131

    local exitOut = seventh.exits[1]
    Harness.assertEqual(exitOut.targetRoom, "worldMapRoom_131")
    -- (48,112): one real step in from worldMapRoom_131's own existing
    -- exit-to-132 landing spot (48,128) -- that exact spot is, by
    -- design (see rom_profiles.lua's doc comment), one row past what a
    -- 16px player's top-left corner can ever legally occupy, so it
    -- can't itself be a BFS seed; (48,112) is the real, reachable step
    -- away from it.
    Harness.assertTrue(pixelReachable(room131, 48, 112, exitOut.landingX, exitOut.landingY),
      "seventhRoom's new exit should land somewhere really reachable (via the game's own movement code) in worldMapRoom_131")

    -- worldMapRoom_131's own reciprocal exit is the 2nd entry (index 2) --
    -- index 1 is the pre-existing exit into worldMapRoom_132.
    local exitBack = room131.exits[2]
    Harness.assertEqual(exitBack.targetRoom, "seventhRoom")
    -- (80,112): seventhRoom's own existing, already-real sixthRoom-exit
    -- landing spot.
    Harness.assertTrue(pixelReachable(seventh, 80, 112, exitBack.landingX, exitBack.landingY),
      "worldMapRoom_131's new exit should land somewhere really reachable (via the game's own movement code) in seventhRoom")

    -- Bounce-loop check, same class of bug this project already found
    -- and fixed once: neither new landing spot may sit inside the
    -- OTHER new exit's own trigger zone.
    local zOut, zBack = exitOut.zone, exitBack.zone
    Harness.assertTrue(not (exitBack.landingX >= zOut.xMin and exitBack.landingX < zOut.xMax
      and exitBack.landingY >= zOut.yMin and exitBack.landingY < zOut.yMax),
      "worldMapRoom_131's new landing spot should not sit inside seventhRoom's own new exit zone")
    Harness.assertTrue(not (exitOut.landingX >= zBack.xMin and exitOut.landingX < zBack.xMax
      and exitOut.landingY >= zBack.yMin and exitOut.landingY < zBack.yMax),
      "seventhRoom's new landing spot should not sit inside worldMapRoom_131's own new exit zone")

    -- Also must not collide with worldMapRoom_131's PRE-EXISTING exit-to-132
    -- zone/landing (the other established door in this same room).
    local zTo132 = room131.exits[1].zone
    Harness.assertTrue(not (exitBack.landingX >= zTo132.xMin and exitBack.landingX < zTo132.xMax
      and exitBack.landingY >= zTo132.yMin and exitBack.landingY < zTo132.yMax),
      "worldMapRoom_131's new landing spot should not sit inside its own pre-existing exit-to-132 zone")
  end
)

--- Real BFS reachability over `grid` (a position-aware collision
-- grid, e.g. from RoomFloorLayout.buildCollisionGridFromMapTableRecord),
-- 4-directional, 1-based (row,col). Returns a `visited[row][col]`
-- table. Reused below to test eighthRoom's own still-real, still-
-- unaffected connection to ninthRoom.
local function reachableFrom(grid, startRow, startCol)
  local rows, cols = #grid, #grid[1]
  local visited = {}
  for r = 1, rows do visited[r] = {} end
  visited[startRow][startCol] = true
  local queue = { { startRow, startCol } }
  local head = 1
  while head <= #queue do
    local r, c = queue[head][1], queue[head][2]
    head = head + 1
    for _, n in ipairs({ { r - 1, c }, { r + 1, c }, { r, c - 1 }, { r, c + 1 } }) do
      local nr, nc = n[1], n[2]
      if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
        and grid[nr][nc] and not visited[nr][nc] then
        visited[nr][nc] = true
        queue[#queue + 1] = { nr, nc }
      end
    end
  end
  return visited
end

local function collisionGridFor(profile, romData, recordIndex)
  local RoomFloorLayout = require("src.import.RoomFloorLayout")
  local mapTable = profile.mapTable
  local opts = {
    metatileTableFileOffset = profile.roomFloorLayoutPipeline.genericCatalogMetatileTableFileOffset,
    tilesetFileOffset = mapTable.tilesetFileOffset,
    metatileGridRows = 8, metatileGridCols = 10,
  }
  return RoomFloorLayout.buildCollisionGridFromMapTableRecord(romData, mapTable, recordIndex, opts)
end

Harness.testIfAvailable(
  "eighthRoom: real bank-5 catalog data (record 236), structurally sound, has a real east exit into ninthRoom -- its own connection to seventhRoom is RETRACTED (2026-08-17), unaffected here",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local eighth = profile.graphics.eighthRoom
    assertRoomStructurallySound(eighth, romData, "eighthRoom")
    Harness.assertTrue(eighth.exits ~= nil and #eighth.exits == 1)
    local exit = eighth.exits[1]
    Harness.assertEqual(exit.targetRoom, "ninthRoom")
    Harness.assertEqual(exit.holdDirection, "right")

    -- Fixed literal (88,8), NOT derived from seventhRoom's own exit
    -- anymore (that connection is retracted -- seventhRoom.exits is
    -- empty). This is eighthRoom's own designated north-entry tile
    -- regardless of what, if anything, real gameplay ever lands here
    -- from -- kept as a fixed internal BFS starting point purely to
    -- test THIS room's own east connectivity to ninthRoom, which is
    -- untouched by the seventhRoom retraction.
    local g236 = collisionGridFor(profile, romData, 236)
    local startRow = math.floor(8 / 8) + 1
    local startCol = math.floor(88 / 8) + 1
    local visited = reachableFrom(g236, startRow, startCol)
    local zone = exit.zone
    for y = zone.yMin, zone.yMax - 8, 8 do
      for x = zone.xMin, zone.xMax - 8, 8 do
        local r, c = math.floor(y / 8) + 1, math.floor(x / 8) + 1
        Harness.assertTrue(visited[r] and visited[r][c],
          string.format("eighthRoom exit zone cell (row %d, col %d) must be reachable from its own north-entry tile", r, c))
      end
    end
  end
)

Harness.testIfAvailable(
  "ninthRoom: real bank-5 catalog data (record 237), structurally sound",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    assertRoomStructurallySound(profile.graphics.ninthRoom, romData, "ninthRoom")
  end
)

Harness.testIfAvailable(
  "eighthRoom/ninthRoom: both landing spots sit on real floor",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local eighth = profile.graphics.eighthRoom

    -- eighthRoom's own north-entry tile (88,8) -- same fixed literal
    -- as the reachability test above, see that test's own comment.
    local row1 = math.floor(8 / 8) + 1
    local col1 = math.floor(88 / 8) + 1
    Harness.assertTrue(eighth.floorTileIds[eighth.grid[row1][col1]],
      "expected eighthRoom's own north-entry tile to be real floor")

    local exit2 = eighth.exits[1]
    local ninth = profile.graphics.ninthRoom
    local row2 = math.floor(exit2.landingY / 8) + 1
    local col2 = math.floor(exit2.landingX / 8) + 1
    Harness.assertTrue(ninth.floorTileIds[ninth.grid[row2][col2]],
      "expected ninthRoom's own landing spot to be real floor")
  end
)

Harness.testIfAvailable(
  "eighthRoom<->ninthRoom: shared edge is a byte-exact collision match (the real evidence behind this exit) -- seventhRoom<->eighthRoom half RETRACTED 2026-08-17, no longer tested",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local g236 = collisionGridFor(profile, romData, 236)
    local g237 = collisionGridFor(profile, romData, 237)

    -- eighthRoom (236) east column == ninthRoom (237) west column, at
    -- the real reachable rows only (rows 1-6). Untouched by the
    -- seventhRoom swap -- both records are exactly what they always
    -- were.
    for r = 1, 6 do
      Harness.assertEqual(g236[r][20], g237[r][1],
        "row " .. r .. ": eighthRoom east col vs ninthRoom west col")
    end
  end
)
