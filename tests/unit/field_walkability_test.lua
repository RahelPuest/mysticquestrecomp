-- Field.buildWalkabilityCheck: real per-tile wall collision (see
-- Player.lua's `canMoveTo` doc comment, rom_profiles.lua's `startRoom
-- .floorTileIds`). Pure function, no love.* calls, headlessly testable.
-- `footprintW`/`footprintH` are passed explicitly in these tests (not
-- read from Player.WIDTH/HEIGHT -- that module no longer hardcodes a
-- "looks like the real sprite" size, see Player.DEFAULT_WIDTH/HEIGHT's
-- doc comment) so the test states exactly what shape it's checking.

local Harness = require("tests.harness")
local Field = require("src.app.states.Field")

local FOOTPRINT_W, FOOTPRINT_H = 16, 16 -- matches the real player sprite size

local function makeRoom()
  return {
    -- 4x4 tile grid; a 2x2 floor patch in the middle, wall everywhere
    -- else -- exactly large enough for a 16x16 (2x2-tile) footprint.
    grid = {
      { 1, 1, 1, 1 },
      { 1, 9, 9, 1 },
      { 1, 9, 9, 1 },
      { 1, 1, 1, 1 },
    },
    floorTileIds = { [9] = true },
  }
end

Harness.test("Field.buildWalkabilityCheck: allows a position fully on floor tiles", function()
  local canMove = Field.buildWalkabilityCheck(makeRoom(), FOOTPRINT_W, FOOTPRINT_H)
  Harness.assertTrue(canMove(8, 8), "16x16 footprint at (8,8) is entirely the floor patch")
end)

Harness.test("Field.buildWalkabilityCheck: rejects a position overlapping any wall tile", function()
  local canMove = Field.buildWalkabilityCheck(makeRoom(), FOOTPRINT_W, FOOTPRINT_H)
  Harness.assertTrue(not canMove(0, 8), "footprint starting at x=0 overlaps the left wall column")
  Harness.assertTrue(not canMove(8, 0), "footprint starting at y=0 overlaps the top wall row")
end)

Harness.test("Field.buildWalkabilityCheck: rejects a position off the known grid", function()
  local canMove = Field.buildWalkabilityCheck(makeRoom(), FOOTPRINT_W, FOOTPRINT_H)
  Harness.assertTrue(not canMove(-8, 8), "negative x is off-grid")
  Harness.assertTrue(not canMove(8, 1000), "far-off y is off-grid")
end)
