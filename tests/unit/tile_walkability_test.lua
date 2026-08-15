-- TileWalkability.build's new `room.blockedRects` escape hatch
-- (2026-08-15, direct user demand: "suche einfach einen allgemeinen
-- kollisions mechanismus" -- see rom_profiles.lua's `fourthRoom
-- .blockedRects` doc comment for the full real-ROM evidence trail this
-- was built from). Pure function, no love.* calls, headlessly testable.

local Harness = require("tests.harness")
local TileWalkability = require("src.entities.TileWalkability")

local FOOTPRINT_W, FOOTPRINT_H = 16, 16

local function makeRoom()
  return {
    -- 4x4 tile grid, all floor -- a flat `floorTileIds` classification
    -- alone would call every position walkable.
    grid = {
      { 9, 9, 9, 9 },
      { 9, 9, 9, 9 },
      { 9, 9, 9, 9 },
      { 9, 9, 9, 9 },
    },
    floorTileIds = { [9] = true },
  }
end

Harness.test("TileWalkability.build: with no blockedRects, behaves exactly as before (regression guard)", function()
  local room = makeRoom()
  local canMove = TileWalkability.build(room, FOOTPRINT_W, FOOTPRINT_H)
  Harness.assertTrue(canMove(8, 8), "an all-floor room stays fully walkable with no overrides")
end)

Harness.test("TileWalkability.build: blockedRects forces a real wall despite floor-classified tile IDs", function()
  local room = makeRoom()
  -- Block the bottom-left 2x2 native-tile quadrant (rows 2-3, cols 0-1)
  -- even though its tile IDs are the same real floor ID as everywhere
  -- else -- exactly the class of bug a flat, tile-ID-keyed
  -- `floorTileIds` set cannot express (same ID, different real
  -- walkability by POSITION).
  room.blockedRects = { { rowMin = 2, rowMax = 3, colMin = 0, colMax = 1 } }
  local canMove = TileWalkability.build(room, FOOTPRINT_W, FOOTPRINT_H)
  Harness.assertTrue(not canMove(0, 16), "footprint at (0,16) overlaps the blocked quadrant despite floor tile IDs")
  Harness.assertTrue(canMove(16, 0), "an unrelated, unblocked position elsewhere in the same room is unaffected")
end)

Harness.test("TileWalkability.build: a footprint straddling a blockedRects edge is still blocked", function()
  -- Real regression this project's own fourthRoom fix hit live: a
  -- 16x16 (2-native-tile-wide) footprint moving one step toward a
  -- blocked rect must be stopped by the FIRST tile it would newly
  -- overlap, not just once its far edge crosses the boundary -- an
  -- off-by-one here let the player take one real, wrong 8px step
  -- before the real ROM's own east side, caught via a live `love .`
  -- screenshot (see rom_profiles.lua's own "CORRECTED" doc comment).
  local room = makeRoom()
  room.blockedRects = { { rowMin = 0, rowMax = 3, colMin = 0, colMax = 1 } }
  local canMove = TileWalkability.build(room, FOOTPRINT_W, FOOTPRINT_H)
  -- Footprint at native col 1 spans cols 1-2 -- col 1 is inside the
  -- blocked rect, so this must be rejected even though col 2 alone is not.
  Harness.assertTrue(not canMove(8, 0), "a footprint straddling the blocked/open boundary is still blocked")
end)
