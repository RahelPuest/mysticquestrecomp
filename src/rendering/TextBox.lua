-- A general, reusable bordered textbox using the real in-ROM border tiles
-- (the same contiguous tileset as `nameEntry`/`battleIntro.textbox` --
-- see rom_profiles.lua's doc comments for the provenance) plus the real
-- font, with an optional real per-letter typewriter reveal
-- (`framesPerLetter`, same VERIFIED 5-frames-per-letter cadence found for
-- the "Kaempfe!" box -- see docs/reverse-engineering/combat.md).
--
-- Extracted from BattleIntro.lua's original box-drawing code (which drew
-- the border at a hardcoded (0,0) with a hardcoded 20x8 size) so a second
-- sequence (VictorySequence) doesn't re-derive the same real tile-offset
-- math with its own position/size baked in -- the position/size/text are
-- now real constructor-time parameters instead. This does NOT claim the
-- ROM's own code shares one textbox routine this way (see rom-map.md's
-- "Enemy HP struct + death dispatch" writeup: the real ROM draws boxes
-- via its own general tile-blit-queue primitive, a lower-level and even
-- more general mechanism this project's renderer doesn't need to copy
-- 1:1 to reproduce the same real, on-screen result) -- this is this
-- project's own reusable Love2D component built to match that result.

local TileImage = require("src.rendering.TileImage")
local GBTile = require("src.rendering.GBTile")
local FixedStep = require("src.core.FixedStep")

local TextBox = {}
TextBox.__index = TextBox

local QUAD_ORDER = { "topLeft", "top", "topRight", "left", "right", "bottomLeft", "bottom", "bottomRight" }

--- `romData`/`profile`: as elsewhere. `font`: a built Font instance.
-- `border`: a `{topLeft=tileId, top=..., ...}` table (see rom_profiles
-- .lua's `nameEntry.border`/`battleIntro.textbox.border` -- both real,
-- identical tile IDs from the one shared tileset).
function TextBox.new(romData, profile, font, border)
  local ts = profile.graphics.nameEntry.tileset
  local function tileOffset(tileId)
    return ts.fileOffset + (tileId - ts.tileBase) * GBTile.TILE_BYTES
  end
  local offsets = {}
  for _, key in ipairs(QUAD_ORDER) do
    offsets[#offsets + 1] = tileOffset(border[key])
  end
  local sheet = TileImage.sheetFromOffsets(romData, offsets, 8,
    { { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 } }, true)
  local quads = {}
  for i, key in ipairs(QUAD_ORDER) do
    quads[key] = love.graphics.newQuad((i - 1) * GBTile.TILE_W, 0, GBTile.TILE_W, GBTile.TILE_H,
      sheet:getWidth(), sheet:getHeight())
  end
  return setmetatable({ sheet = sheet, quads = quads, font = font }, TextBox)
end

--- Draw the border/fill at `(x, y)`, `cols`x`rows` tiles. Real captured
-- screenshots (see docs/reverse-engineering/combat.md) show a solid
-- white interior -- the real border TILES themselves are only ~50%-
-- filled edge/corner art (confirmed by decoding them: real pixel counts
-- checked directly, not assumed), covering just the outer ring of cells,
-- so an explicit white fill rect for the interior is needed first (a
-- real fix over BattleIntro.lua's original ring-only drawBox, which
-- happened to look right only because a light room background showed
-- through the gap -- not correct against a black backdrop, as this
-- module's own VictorySequence caller exposed).
function TextBox:drawBorder(x, y, cols, rows)
  local q = self.quads
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, cols * GBTile.TILE_W, rows * GBTile.TILE_H)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.draw(self.sheet, q.topLeft, x, y)
  love.graphics.draw(self.sheet, q.bottomLeft, x, y + (rows - 1) * GBTile.TILE_H)
  for c = 1, cols - 2 do
    love.graphics.draw(self.sheet, q.top, x + c * GBTile.TILE_W, y)
    love.graphics.draw(self.sheet, q.bottom, x + c * GBTile.TILE_W, y + (rows - 1) * GBTile.TILE_H)
  end
  love.graphics.draw(self.sheet, q.topRight, x + (cols - 1) * GBTile.TILE_W, y)
  love.graphics.draw(self.sheet, q.bottomRight, x + (cols - 1) * GBTile.TILE_W, y + (rows - 1) * GBTile.TILE_H)
  for r = 1, rows - 2 do
    love.graphics.draw(self.sheet, q.left, x, y + r * GBTile.TILE_H)
    love.graphics.draw(self.sheet, q.right, x + (cols - 1) * GBTile.TILE_W, y + r * GBTile.TILE_H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw `text` inside the border at `(x, y)` with a `padding`-px inset.
-- `\n` starts a new line (a plain formatting convenience -- pre-wrapped
-- by the caller, same convention as DialogueBox.lua; no automatic word-
-- wrap/hyphenation is implemented -- see this module's doc comment).
function TextBox:drawText(text, x, y, padding)
  padding = padding or 8
  local row = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    self.font:print(line, x + padding, y + padding + row * GBTile.TILE_H, { 0, 0, 0, 1 })
    row = row + 1
  end
end

--- A real, VERIFIED per-letter typewriter reveal helper (see this
-- module's doc comment): how many characters of `text` should be shown
-- after `elapsedFrames` real GB frames at `framesPerLetter` frames/char.
-- `\n` bytes still consume a character slot (matches the real captured
-- "Kaempfe!"/intro-text timing, which counts every decoded byte, not
-- just visible glyphs).
function TextBox.revealedCount(text, elapsedFrames, framesPerLetter)
  if elapsedFrames <= 0 then return 0 end
  return math.min(#text, math.floor(elapsedFrames / framesPerLetter))
end

TextBox.FRAME_SECONDS = FixedStep.STEP

return TextBox
