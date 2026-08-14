-- General renderer for "a room captured as a live tile-ID grid, each ID
-- resolved through an explicit per-tile ROM offset dict" -- the shape
-- StartRoomBackground.lua (the courtyard) and WillyRoomBackground.lua
-- (the post-victory room) both independently duplicated before this
-- module existed. Extracted 2026-08-09 per direct user instruction to
-- look for general mechanisms ("suche nach allgemeinen Mechanismen für
-- Dinge wie... sprite load") rather than one hardcoded module per room.
--
-- `room`: a plain data table (e.g. `profile.graphics.startRoom` or
-- `.willyRoom`) shaped `{ cols, rows, grid = {{tileId,...},...},
-- tileOffsets = {[tileId]=romOffset,...} }` -- NOT a profile-key lookup
-- (callers pass the sub-table directly), so this module has zero
-- knowledge of which named rooms exist.
--
-- WHY explicit per-tile offsets, not a flat `base + id*16` stride:
-- every real room this project has ground-truthed so far (the
-- courtyard, the post-victory room) turned out to load its own small,
-- scattered tile-graphics set into VRAM rather than referencing one
-- shared contiguous tileset by plain index -- assuming a flat stride
-- here already produced one confirmed-wrong render (`willyRoom`'s
-- original implementation, corrected the same day -- see rom-map.md's
-- "Real room-tile decompression pipeline" entry for the full story and
-- the general lesson: a plausible-looking render is not sufficient
-- confirmation of the tileset base).
--
-- The flat-stride alternative used to live in `RoomBackground.lua`
-- (a `MapTable`-based renderer for bank 5's own RLE map records) --
-- removed 2026-08-12 as real dead code (never `require`d by anything,
-- confirmed via a full-repo sweep): the "how do multiple records
-- compose into an on-screen room" question it was built to answer
-- stayed open at the single-record level and was later actually
-- resolved through a different, real mechanism (Milestone 3's bank-5
-- room-table composition breakthrough, see rom-map.md/progress.md),
-- which this project's actual room content (`rom_profiles.lua` +
-- `Field.lua`) is built on instead.

local TileImage = require("src.rendering.TileImage")

local TileGridBackground = {}
TileGridBackground.__index = TileGridBackground

function TileGridBackground.new(romData, room)
  assert(room and room.grid and room.tileOffsets and room.cols and room.rows,
    "TileGridBackground.new expects a room table with cols/rows/grid/tileOffsets")

  local offsets = {}
  for r, row in ipairs(room.grid) do
    for c, tileId in ipairs(row) do
      local i = (r - 1) * room.cols + c
      offsets[i] = room.tileOffsets[tileId] -- nil (blank) for an unmapped/blank tile ID
    end
  end

  local sheet = TileImage.sheetFromOffsets(
    romData, offsets, room.cols, nil, false, room.cols * room.rows)

  return setmetatable({ sheet = sheet }, TileGridBackground)
end

function TileGridBackground:draw(x, y)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.sheet, x or 0, y or 0)
end

return TileGridBackground
