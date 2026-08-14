-- General per-tile-grid collision check -- extracted from Field.lua's
-- own `buildWalkabilityCheck` (2026-08-09) once a second real room
-- (the post-victory scene) needed the exact same real mechanism: "is
-- every tile a footprint rectangle would occupy at (x,y) a floor tile,
-- not wall/border structure." Same honesty status as before: `floorTileIds`
-- is this project's own classification of a real captured tile grid, not
-- a decoded ROM collision table (see rom_profiles.lua's `startRoom
-- .floorTileIds`/`willyRoom.floorTileIds` doc comments for exactly how
-- each was found).
--
-- Pure function, no love.* calls -- headlessly testable like the rest of
-- src/entities/.

local TileWalkability = {}

--- Build a `canMoveTo(x, y)` predicate from a `{grid, floorTileIds}`-
-- shaped room table (e.g. `profile.graphics.startRoom`/`.willyRoom`):
-- true iff every tile a real `footprintW`x`footprintH` (from the real
-- ROM sprite size, not a hardcoded guess) footprint would occupy at
-- (x, y) is a floor/decoration tile.
function TileWalkability.build(room, footprintW, footprintH)
  local grid, floorTileIds = room.grid, room.floorTileIds
  local rows, cols = #grid, #grid[1]
  return function(x, y)
    local left = math.floor(x / 8)
    local right = math.floor((x + footprintW - 1) / 8)
    local top = math.floor(y / 8)
    local bottom = math.floor((y + footprintH - 1) / 8)
    for row = top, bottom do
      for col = left, right do
        if row < 0 or row >= rows or col < 0 or col >= cols then
          return false -- off the known grid entirely
        end
        if not floorTileIds[grid[row + 1][col + 1]] then
          return false
        end
      end
    end
    return true
  end
end

--- Same real footprint-vs-grid check as `build` above, but against a
-- plain boolean walkable/wall grid (`grid[row][col] = true/false`,
-- 1-based, 8px cells) instead of a `{grid, floorTileIds}` room table --
-- 2026-08-12, quick win #2 ("1 dann 2 dann 3 dann 4"): lets
-- `RoomFloorLayout.buildCollisionGridFromMapTableRecord`'s own
-- per-metatile-instance collision grid drive real movement checks
-- directly, without first having to invent a fake `floorTileIds` set
-- keyed by tile ID (which `RoomFloorLayout`'s own doc comments
-- explicitly call out as the wrong shape for position-aware data, see
-- `buildCollisionGrid`'s doc comment there).
function TileWalkability.buildFromCollisionGrid(collisionGrid, footprintW, footprintH)
  local rows, cols = #collisionGrid, #collisionGrid[1]
  return function(x, y)
    local left = math.floor(x / 8)
    local right = math.floor((x + footprintW - 1) / 8)
    local top = math.floor(y / 8)
    local bottom = math.floor((y + footprintH - 1) / 8)
    for row = top, bottom do
      for col = left, right do
        if row < 0 or row >= rows or col < 0 or col >= cols then
          return false -- off the known grid entirely
        end
        if not collisionGrid[row + 1][col + 1] then
          return false
        end
      end
    end
    return true
  end
end

return TileWalkability
