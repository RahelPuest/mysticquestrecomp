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
  -- NOTE: earlier rooms' own tests also checked "not all-zero bytes"
  -- as a rough not-garbage heuristic -- dropped here after a real,
  -- direct ROM byte read confirmed eighthRoom's own tile 17 (file
  -- 0x32110) genuinely IS all-zero in the real ROM (a real blank/void
  -- decoration tile, consistent with this room's own maze-corridor
  -- content) -- not a fabricated/wrong offset. The in-bounds check
  -- above is the real, always-valid guarantee; "non-trivial bytes" was
  -- never a guaranteed property of real ROM data, just a heuristic
  -- that happened to hold for earlier rooms' own specific tile sets.
  for r = 1, 16 do
    for c = 1, 20 do
      local id = room.grid[r][c]
      Harness.assertTrue(room.tileOffsets[id] ~= nil,
        string.format("%s: grid cell (%d,%d) references tile %d with no real tileOffset", label, r, c, id))
    end
  end
end

Harness.testIfAvailable(
  "seventhRoom: real bank-5 catalog data (mapTable record 220), structurally sound",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    assertRoomStructurallySound(profile.graphics.seventhRoom, romData, "seventhRoom")
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

-- Real chain continuation, 2026-08-16, same continuation ("an dem
-- neuem raum sind noch mehr räume angeschlossen explorire weiter").
-- SELF-CORRECTED the same pass: a first attempt wired seventhRoom's
-- own exit WEST (into a since-abandoned "eighthRoom" candidate,
-- mapTable record 219) purely on an edge-collision-pattern match,
-- without checking whether that edge was actually REACHABLE from the
-- landing spot -- it wasn't (seventhRoom's own internal wall divider
-- seals the west edge off entirely), caught by a real `love .`
-- playthrough getting stuck. Every exit below is now verified with a
-- real BFS reachability check over each room's own live collision
-- grid FIRST, not just an edge-pattern match -- see
-- rom_profiles.lua's own doc comments for the full corrected trail.
-- The real chain is now: seventhRoom (220) --south--> eighthRoom
-- (236) --east--> ninthRoom (237).

--- Real BFS reachability over `grid` (a position-aware collision
-- grid, e.g. from RoomFloorLayout.buildCollisionGridFromMapTableRecord),
-- 4-directional, 1-based (row,col). Returns a `visited[row][col]`
-- table. Same algorithm this project's own live investigation used to
-- catch the west-exit mistake -- reused here so the test suite itself
-- enforces "every wired exit's own zone must be reachable," not just
-- "the destination room decodes without error."
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
  "seventhRoom: has a real south exit into eighthRoom, zone reachable from the real landing spot",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local seventh = profile.graphics.seventhRoom
    Harness.assertTrue(seventh.exits ~= nil and #seventh.exits == 1)
    local exit = seventh.exits[1]
    Harness.assertEqual(exit.targetRoom, "eighthRoom")
    Harness.assertEqual(exit.holdDirection, "down")

    -- Real reachability check: the sixthRoom exit's own landing spot
    -- (80,112) must reach every cell inside seventhRoom's own new exit
    -- zone (64-128, 112-128) via real, position-aware collision -- the
    -- exact check that would have caught the retracted west-exit
    -- mistake before it ever got reported as done.
    local g220 = collisionGridFor(profile, romData, 220)
    local sixthExit = profile.graphics.sixthRoom.exits[1]
    local startRow = math.floor(sixthExit.landingY / 8) + 1
    local startCol = math.floor(sixthExit.landingX / 8) + 1
    local visited = reachableFrom(g220, startRow, startCol)
    local zone = exit.zone
    for y = zone.yMin, zone.yMax - 8, 8 do
      for x = zone.xMin, zone.xMax - 8, 8 do
        local r, c = math.floor(y / 8) + 1, math.floor(x / 8) + 1
        Harness.assertTrue(visited[r] and visited[r][c],
          string.format("seventhRoom exit zone cell (row %d, col %d) must be reachable from the real landing spot", r, c))
      end
    end
  end
)

Harness.testIfAvailable(
  "eighthRoom: real bank-5 catalog data (record 236), structurally sound, has a real east exit into ninthRoom",
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

    local g236 = collisionGridFor(profile, romData, 236)
    local seventhExit = profile.graphics.seventhRoom.exits[1]
    local startRow = math.floor(seventhExit.landingY / 8) + 1
    local startCol = math.floor(seventhExit.landingX / 8) + 1
    local visited = reachableFrom(g236, startRow, startCol)
    local zone = exit.zone
    for y = zone.yMin, zone.yMax - 8, 8 do
      for x = zone.xMin, zone.xMax - 8, 8 do
        local r, c = math.floor(y / 8) + 1, math.floor(x / 8) + 1
        Harness.assertTrue(visited[r] and visited[r][c],
          string.format("eighthRoom exit zone cell (row %d, col %d) must be reachable from the real landing spot", r, c))
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
    local seventh = profile.graphics.seventhRoom
    local eighth = profile.graphics.eighthRoom

    local exit1 = seventh.exits[1]
    local row1 = math.floor(exit1.landingY / 8) + 1
    local col1 = math.floor(exit1.landingX / 8) + 1
    Harness.assertTrue(eighth.floorTileIds[eighth.grid[row1][col1]],
      "expected eighthRoom's own landing spot to be real floor")

    local exit2 = eighth.exits[1]
    local ninth = profile.graphics.ninthRoom
    local row2 = math.floor(exit2.landingY / 8) + 1
    local col2 = math.floor(exit2.landingX / 8) + 1
    Harness.assertTrue(ninth.floorTileIds[ninth.grid[row2][col2]],
      "expected ninthRoom's own landing spot to be real floor")
  end
)

Harness.testIfAvailable(
  "seventhRoom<->eighthRoom<->ninthRoom: shared edges are byte-exact collision matches (the real evidence behind each exit)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local g220 = collisionGridFor(profile, romData, 220)
    local g236 = collisionGridFor(profile, romData, 236)
    local g237 = collisionGridFor(profile, romData, 237)

    -- seventhRoom (220) south row == eighthRoom (236) north row, at
    -- the real reachable columns only (8-15, 0-based -- see
    -- rom_profiles.lua's own doc comment: the rest of the room is a
    -- disconnected pocket, not a claim about the WHOLE edge).
    for c = 9, 16 do
      Harness.assertEqual(g220[16][c], g236[1][c],
        "col " .. c .. ": seventhRoom south row vs eighthRoom north row")
    end
    -- eighthRoom (236) east column == ninthRoom (237) west column, at
    -- the real reachable rows only (rows 1-6).
    for r = 1, 6 do
      Harness.assertEqual(g236[r][20], g237[r][1],
        "row " .. r .. ": eighthRoom east col vs ninthRoom west col")
    end
  end
)
