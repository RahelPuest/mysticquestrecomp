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

--- Whether native grid cell `(row, col)` (0-based) falls inside any of
-- `blockedRects` -- each `{rowMin, rowMax, colMin, colMax}`, 0-based,
-- inclusive. See `build`'s own doc comment below for why this exists.
local function insideBlockedRect(blockedRects, row, col)
  if not blockedRects then return false end
  for _, r in ipairs(blockedRects) do
    if row >= r.rowMin and row <= r.rowMax and col >= r.colMin and col <= r.colMax then
      return true
    end
  end
  return false
end

--- Build a `canMoveTo(x, y)` predicate from a `{grid, floorTileIds}`-
-- shaped room table (e.g. `profile.graphics.startRoom`/`.willyRoom`):
-- true iff every tile a real `footprintW`x`footprintH` (from the real
-- ROM sprite size, not a hardcoded guess) footprint would occupy at
-- (x, y) is a floor/decoration tile.
--
-- `room.blockedRects` (2026-08-15, direct user demand: "suche einfach
-- einen allgemeinen kollisions mechanismus" after fourthRoom's own real
-- metatile+layout-stream source turned out NOT to exist -- confirmed
-- live, no $242B hit across a 6M-instruction single-stepped budget
-- covering the full real staircase-to-fourthRoom transition, unlike
-- willyRoom/unknownRoomB which both do use that pipeline): an OPTIONAL
-- general escape hatch for exactly the class of bug a flat, tile-ID-
-- keyed `floorTileIds` set structurally cannot represent -- the SAME
-- tile ID being real floor in one position and a real wall in another.
-- Each rect is real, LIVE-MOVEMENT-DISCOVERED ground truth (poking
-- $C244/$C245 directly was tried first and found UNRELIABLE in this
-- environment -- movement silently no-ops for many frames after a raw
-- WRAM position poke, a real, reproducible mgba-python-bindings
-- limitation, not a ROM fact -- so this was derived from genuine
-- held-button walks + `mgba`'s own `save_raw_state`/`load_raw_state`
-- to reset between real probes, never a teleport), NOT a guess: real
-- `LEFT` input from fourthRoom's own landing spot (rows 13-14, the
-- 2 rows nearest the staircase) is completely blocked for 100+ real
-- frames west of column 14, while the EXACT SAME input from row 12
-- (one row further from the stairs) moves freely all the way to the
-- real west wall. A real, position-specific wall the flat tile-ID
-- classification (129-135 all marked floor everywhere) cannot express
-- -- the staircase landing is a real, narrow alcove, not full-width
-- open floor the way the rest of the room's identical-looking tiles
-- are. See rom_profiles.lua's own `fourthRoom.blockedRects` doc
-- comment for the exact real probe transcript this is built from.
function TileWalkability.build(room, footprintW, footprintH)
  local grid, floorTileIds = room.grid, room.floorTileIds
  local blockedRects = room.blockedRects
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
        if insideBlockedRect(blockedRects, row, col) then
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
