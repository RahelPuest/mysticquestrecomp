-- General real ROM "tile-patch" overlay: temporarily repaints a small
-- block of BG cells for a scripted frame window, then reveals the
-- room's own static base art again once the window ends.
--
-- GENERALIZED (2026-08-12, direct instruction after a user playtest bug
-- sweep: "untersuche die dinge die ueber einzelfixes hinnaus gehen,
-- dokumentiere sie als systeme und implementiere sie in der app so das
-- sie allgemeingueltig sind"): this project has now found the SAME real
-- ROM mechanism -- a small ROM-resident tile-patch blob repointing a
-- handful of BG cells for a scripted window, then letting the room's
-- own static art show through again -- in THREE independent places
-- (willyRoom's door, the courtyard gate, the courtyard's right-wall
-- entrance). That's not a coincidence worth re-implementing three
-- separate ways; it's this ROM's general convention for "a temporary
-- opening," and any future one found should fit this same shape. This
-- module replaces the two frame-window-driven instances that used to be
-- separate, near-identical modules (`GateAnimation.lua`, the courtyard
-- gate; `EntranceSeal.lua`, the right-wall entrance) with one general
-- implementation. `willyRoom`'s own door is NOT folded in here -- it's
-- driven by a live proximity/state condition, not a frame window, and
-- swaps a whole second pre-built background image rather than drawing
-- a small overlay (see VictorySequence.lua's own `willyRoomDoorOpenBg`)
-- -- a genuinely different real implementation shape for the same
-- general ROM concept, left as-is rather than forced into this module.
--
-- Two real tile-SOURCING shapes, both real ROM data, exactly one
-- required per patch:
--  - `openTilePattern`: one uniform literal 2bpp byte pattern, repeated
--    across every cell -- for a real tile with no single identified ROM
--    source offset (see the courtyard gate's own rom_profiles.lua doc
--    comment for why). Stretched across the full `rows`x`cols` block.
--  - `openGrid` + `tileOffsets`: a real grid of (possibly different)
--    real tile IDs, each individually addressable via the room's own
--    `tileOffsets` table -- for a patch built from ordinary, already-
--    catalogued room tiles (the courtyard's right-wall entrance).
--
-- The "closed" state is deliberately NOT drawn by this module at all --
-- every real instance found so far patches to exactly what the room's
-- own static base grid already shows underneath (confirmed byte-for-
-- byte for the right-wall entrance), so redrawing it would be a no-op
-- at best and a silent second source of truth to drift out of sync at
-- worst. `:isOpen(frame)` tells the caller when to skip `:draw()`
-- entirely and just let the base room art show through, same
-- convention the original `GateAnimation.lua` already used.

local GBTile = require("src.rendering.GBTile")
local TileImage = require("src.rendering.TileImage")

local TilePatch = {}
TilePatch.__index = TilePatch

--- `patch`: `{bgRow, bgCol, rows, cols, openFrame, closeFrame, ...}`
-- plus exactly one of `openTilePattern` or `openGrid` (see module doc
-- comment). `tileOffsets`: the room's own real per-tile-ID ROM offsets
-- -- required (and every `openGrid` tile ID must be a key in it) iff
-- `patch.openGrid` is used; ignored for `openTilePattern`.
function TilePatch.new(romData, patch, tileOffsets)
  assert(patch.openTilePattern or patch.openGrid,
    "TilePatch.new: patch needs either openTilePattern or openGrid")
  local image, uniform

  if patch.openTilePattern then
    local tile = GBTile.decodeTile(patch.openTilePattern)
    image = TileImage.buildSheet({ tile }, 1, nil, false)
    uniform = true
  else
    assert(tileOffsets, "TilePatch.new: patch.openGrid requires tileOffsets")
    local offsets = {}
    local i = 0
    for _, row in ipairs(patch.openGrid) do
      for _, tileId in ipairs(row) do
        i = i + 1
        offsets[i] = assert(tileOffsets[tileId],
          "TilePatch.new: no tileOffsets entry for real tile " .. tostring(tileId))
      end
    end
    image = TileImage.sheetFromOffsets(romData, offsets, patch.cols)
    uniform = false
  end

  return setmetatable({ patch = patch, image = image, uniform = uniform }, TilePatch)
end

--- Whether the patch should render as open at real `frame` (the same
-- frame counter the caller's own phase-bounds logic uses).
function TilePatch:isOpen(frame)
  return frame >= self.patch.openFrame and frame < self.patch.closeFrame
end

--- Draws the real open-state art over its BG cell block. `uniform`
-- patches stretch their single tile across the whole `rows`x`cols`
-- block (love's own draw scale params); `openGrid` patches already
-- built a full `rows`x`cols` sheet, drawn 1:1.
function TilePatch:draw()
  local p = self.patch
  love.graphics.setColor(1, 1, 1, 1)
  if self.uniform then
    love.graphics.draw(self.image, p.bgCol * GBTile.TILE_W, p.bgRow * GBTile.TILE_H,
      0, p.cols, p.rows)
  else
    love.graphics.draw(self.image, p.bgCol * GBTile.TILE_W, p.bgRow * GBTile.TILE_H)
  end
end

return TilePatch
