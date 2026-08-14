-- Draws a small entity (player, enemy) as a real decoded sprite-bank
-- tile block, animated between two frames while moving, instead of a
-- flat-color rectangle placeholder.
--
-- HONESTY NOTE: banks 9-11 contain real graphics data, but NOT
-- uniformly clean creature-sprite art -- a direct screenshot comparison
-- (see docs/progress.md) found bank 9 starts with a run of noise-
-- looking (non-tile) data before real sprite art appears, while bank 10
-- is a clean, coherent creature-portrait sheet from tile 0 (see
-- rom_profiles.lua's per-bank status notes). Callers should source from
-- a bank confirmed clean at the tile index they intend to use -- see
-- Field.lua's own comment for which bank/index it picked and why. This
-- project has also explicitly NOT determined sprite-tile *boundaries*
-- within a confirmed-clean region -- which specific tiles compose one
-- on-screen character, or its real walk-cycle frames. This module
-- picks a small block of adjacent tiles and alternates between two
-- nearby blocks while `moving` is true, to get real, animated ROM
-- pixels on screen -- it does NOT claim this is the verified player/
-- enemy sprite or its real animation. Treat the tile indices passed in
-- as a display choice, not a rom-map.md fact.

local TileImage = require("src.rendering.TileImage")
local GBTile = require("src.rendering.GBTile")

local CreatureSprite = {}
CreatureSprite.__index = CreatureSprite

-- Seconds per animation frame while moving -- a plain UI choice (not a
-- decoded ROM animation-timing fact; see roadmap.md "animation timing
-- untested").
CreatureSprite.FRAME_SECONDS = 0.2

--- `tileBase`: rom_profiles.lua graphics.* entry to source tiles from.
-- `startIndex`: which tile (within that bank) is the block's top-left
-- corner. `cols`/`rows`: block size in tiles (e.g. 2x2 for a 16x16
-- sprite). `frameStride`: tile-index offset between animation frames.
-- `palette`: color table (see TileImage.buildSheet); defaults to the
-- real, live-verified DMG sprite palette (rom_profiles.lua's
-- `graphics.spritePalette`) via `CreatureSprite.setDefaultPalette`,
-- falling back to `TileImage.DEFAULT_PALETTE` if never set.
function CreatureSprite.new(romData, bankInfo, startIndex, cols, rows, frameStride, palette)
  local self = setmetatable({
    romData = romData,
    fileOffsetStart = bankInfo.fileOffsetStart,
    cols = cols,
    rows = rows,
    startIndex = startIndex,
    frameStride = frameStride or (cols * rows),
    palette = palette,
    frame = 0,
    animTimer = 0,
    images = {},
  }, CreatureSprite)
  return self
end

-- Set once (see main.lua/Field.lua) from the live-verified OBP0/OBP1
-- register decode, so every CreatureSprite instance renders with the
-- real sprite palette without each call site having to pass it
-- explicitly. Falls back to TileImage.DEFAULT_PALETTE (an arbitrary
-- identity grey ramp) if never called -- e.g. headless/test contexts.
function CreatureSprite.setDefaultPalette(palette)
  CreatureSprite._defaultPalette = palette
end

--- Read back the current default palette (see `setDefaultPalette`) --
-- for other rendering modules (e.g. PlayerSprite.lua) that build their
-- own CreatureSprite instances and want the same real hardware palette
-- rather than duplicating the fallback chain.
function CreatureSprite.getDefaultPalette()
  return CreatureSprite._defaultPalette or TileImage.DEFAULT_PALETTE
end

function CreatureSprite:_buildFrame(frameIndex)
  if self.images[frameIndex] then return self.images[frameIndex] end
  local palette = self.palette or CreatureSprite._defaultPalette or TileImage.DEFAULT_PALETTE
  local image
  if self.isOffsetSprite then
    image = TileImage.sheetFromOffsets(
      self.romData, self.tileOffsets, self.cols, palette, true, nil, self.rowSpacing)
  else
    local indices = {}
    local base = self.startIndex + frameIndex * self.frameStride
    for r = 0, self.rows - 1 do
      for c = 0, self.cols - 1 do
        indices[#indices + 1] = base + r * self.cols + c
      end
    end
    image = TileImage.sheetFromIndices(
      self.romData, self.fileOffsetStart, indices, self.cols, palette, true)
  end
  self.images[frameIndex] = image
  return image
end

--- A live-verified, non-animated sprite built directly from `count`
-- sequential tiles at `fileOffset` (not a bank+startIndex lookup into a
-- shared tileset -- for a sprite whose own exact ROM location is known,
-- like the real player sprite -- see rom_profiles.lua's `playerSprite`
-- entry). No 2-frame walk-cycle guess: `update` is a no-op, matching
-- that this sprite was never observed to change tiles during movement
-- in the live capture that found it.
function CreatureSprite.static(romData, fileOffset, cols, rows, palette)
  local self = setmetatable({
    romData = romData,
    fileOffsetStart = fileOffset,
    cols = cols,
    rows = rows,
    startIndex = 0,
    frameStride = 0,
    palette = palette,
    frame = 0,
    animTimer = 0,
    images = {},
  }, CreatureSprite)
  return self
end

--- A live-verified, non-animated sprite built from an explicit list of
-- real ROM tile offsets (not a regular bank+startIndex stride -- for a
-- sprite whose tiles were found scattered at individually-confirmed
-- offsets, like the real enemy -- see rom_profiles.lua's `enemySprite`
-- entry). `tileOffsets` must have `cols*rows` entries, row-major.
-- `rowSpacing` (optional): real pixel distance between row starts, for
-- a sprite whose own rows are captured NOT flush -- see
-- `TileImage.buildSheet`'s own doc comment (added for `enemyDescent`'s
-- own real, documented "row2 16px lower" gap).
function CreatureSprite.fromOffsets(romData, tileOffsets, cols, rows, palette, rowSpacing)
  local self = setmetatable({
    romData = romData,
    tileOffsets = tileOffsets,
    cols = cols,
    rows = rows,
    startIndex = 0,
    frameStride = 0,
    palette = palette,
    rowSpacing = rowSpacing,
    frame = 0,
    animTimer = 0,
    images = {},
    -- NOT named `fromOffsets` -- that would collide with the class
    -- method `CreatureSprite.fromOffsets` above via the `__index =
    -- CreatureSprite` metatable fallback (a function value is truthy,
    -- so `self.fromOffsets` would read as "true" on EVERY instance,
    -- not just ones actually built this way -- hit exactly this bug
    -- when a `.static` player sprite tried to use the offsets branch).
    isOffsetSprite = true,
  }, CreatureSprite)
  return self
end

function CreatureSprite:update(dt, moving)
  if self.frameStride == 0 then return end -- static sprite (see .static above)
  if not moving then
    self.frame = 0
    self.animTimer = 0
    return
  end
  self.animTimer = self.animTimer + dt
  if self.animTimer >= CreatureSprite.FRAME_SECONDS then
    self.animTimer = self.animTimer - CreatureSprite.FRAME_SECONDS
    self.frame = 1 - self.frame -- 2-frame walk cycle
  end
end

--- `flipX`/`flipY`: draw horizontally/vertically mirrored -- real GB OAM
-- attribute bits (Pan Docs "OBJ Flags" bit 5 / bit 6), not invented
-- visual flourishes. `flipX` alone is the VERIFIED real mechanism for
-- the player's own facing (see rom_profiles.lua's `playerSprite` doc
-- comment): live OAM tracing found the real sprite's attribute byte
-- sets the X-flip bit (and its two tile columns swap order)
-- specifically while facing right, with left/up/down all sharing the
-- same unflipped art. `flipY` was added once the real attack-swing
-- sprite (rom_profiles.lua's `attackSwing`) was found to use BOTH bits
-- (individually and combined) across its 4 real captured phases to fake
-- a rotating arc from 2 real tile blocks -- see AttackSwing.lua.
function CreatureSprite:draw(x, y, flipX, flipY)
  local image = self:_buildFrame(self.frame)
  love.graphics.setColor(1, 1, 1, 1)
  local sx = flipX and -1 or 1
  local sy = flipY and -1 or 1
  local ox = flipX and image:getWidth() or 0
  local oy = flipY and image:getHeight() or 0
  love.graphics.draw(image, x + ox, y + oy, 0, sx, sy)
end

CreatureSprite.TILE_W = GBTile.TILE_W
CreatureSprite.TILE_H = GBTile.TILE_H

return CreatureSprite
