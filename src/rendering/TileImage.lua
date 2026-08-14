-- Turns GBTile-decoded tiles into a love.graphics.Image sheet, for on-screen
-- display and for the debug tile viewer. Kept separate from GBTile.lua so
-- GBTile itself stays love-free and headlessly testable (see
-- docs/architecture.md).

local GBTile = require("src.rendering.GBTile")

local TileImage = {}

-- Default DMG-style 4-shade grey ramp, index 0 (lightest) to 3 (darkest).
-- A *display* choice (see GBTile-equivalent note in
-- tools/graphics/gbtile.py) -- Mystic Quest's real in-game BGP/OBP palette
-- writes are still unverified.
TileImage.DEFAULT_PALETTE = {
  { 1.00, 1.00, 1.00, 1 },
  { 0.67, 0.67, 0.67, 1 },
  { 0.33, 0.33, 0.33, 1 },
  { 0.00, 0.00, 0.00, 1 },
}

-- The 4 possible DMG grey shades a palette register (BGP/OBP0/OBP1) can
-- map a raw 2bpp pixel index to -- hardware-fixed, not a display choice
-- (unlike DEFAULT_PALETTE's colors, which are just one reasonable RGB
-- rendering of them).
TileImage.DMG_SHADES = {
  { 1.00, 1.00, 1.00, 1 },
  { 0.67, 0.67, 0.67, 1 },
  { 0.33, 0.33, 0.33, 1 },
  { 0.00, 0.00, 0.00, 1 },
}

--- Build a real palette from a decoded DMG palette register's 4 shade
-- indices (see rom_profiles.lua's `graphics.spritePalette`/Pan Docs "LCD
-- Monochrome Palettes") -- e.g. `{0,0,1,3}` for a register whose raw
-- pixel index 1 renders as shade 0 (same as index 0), not a literal
-- identity ramp. General DMG hardware decode, not game-specific.
function TileImage.paletteFromShadeIndices(shadeIndices)
  local palette = {}
  for i, shadeIdx in ipairs(shadeIndices) do
    palette[i] = TileImage.DMG_SHADES[shadeIdx + 1]
  end
  return palette
end

--- Build a love.graphics.Image laying out `tiles` (an array of GBTile
-- decoded-tile tables) into a grid `columns` wide. `transparent0` makes
-- palette index 0 transparent instead of drawing the palette's color 0
-- (useful for sprites over a background; not used for tilesets/fonts).
-- `rowSpacing` (optional, defaults to the tile's own natural
-- `GBTile.TILE_H`, i.e. flush stacking, unchanged from before): real
-- pixel distance between the START of consecutive rows -- for a real
-- sprite whose own rows are NOT flush (a real, live-captured vertical
-- gap between them, e.g. a body segment occluded by something else in
-- front of it) -- see `enemyDescent`'s own doc comment
-- (rom_profiles.lua) for the first real case this was added for: "row2
-- 16px lower" (not the standard 8px flush spacing), rather than
-- forcing every multi-row sprite into a flush grid regardless of what
-- was actually captured.
function TileImage.buildSheet(tiles, columns, palette, transparent0, rowSpacing)
  palette = palette or TileImage.DEFAULT_PALETTE
  columns = columns or 16
  rowSpacing = rowSpacing or GBTile.TILE_H
  local rows = math.ceil(#tiles / columns)
  local w = columns * GBTile.TILE_W
  local h = math.max(1, rows - 1) * rowSpacing + GBTile.TILE_H
  local imageData = love.image.newImageData(w, h)

  for i, tile in ipairs(tiles) do
    local tx = ((i - 1) % columns) * GBTile.TILE_W
    local ty = math.floor((i - 1) / columns) * rowSpacing
    for y = 1, GBTile.TILE_H do
      for x = 1, GBTile.TILE_W do
        local idx = tile[y][x]
        if transparent0 and idx == 0 then
          imageData:setPixel(tx + x - 1, ty + y - 1, 0, 0, 0, 0)
        else
          local c = palette[idx + 1]
          imageData:setPixel(tx + x - 1, ty + y - 1, c[1], c[2], c[3], c[4])
        end
      end
    end
  end

  local image = love.graphics.newImage(imageData)
  image:setFilter("nearest", "nearest")
  return image, w, h, imageData
end

--- Convenience: decode `count` tiles from `data` at `offset` and build a
-- sheet image in one call.
function TileImage.sheetFromBytes(data, offset, count, columns, palette, transparent0)
  local tiles = GBTile.decodeTiles(data, offset, count)
  return TileImage.buildSheet(tiles, columns, palette, transparent0)
end

--- Build a sheet from a list of *tile indices* rather than sequential
-- bytes -- each index selects `tilesetBase + index*16` in `data`
-- independently, unlike sheetFromBytes which reads one contiguous run.
-- For map/room block data (see src/import/MapTable.lua and
-- docs/reverse-engineering/rom-map.md "Maps"), where each data byte is a
-- tile-index reference into a shared tileset rather than raw tile bytes.
function TileImage.sheetFromIndices(data, tilesetBase, indices, columns, palette, transparent0)
  local tiles = {}
  for i, idx in ipairs(indices) do
    local offset = tilesetBase + idx * GBTile.TILE_BYTES
    tiles[i] = GBTile.decodeTile(data, offset)
  end
  return TileImage.buildSheet(tiles, columns, palette, transparent0)
end

--- Build a sheet from an explicit list of *file offsets*, one per cell --
-- unlike `sheetFromIndices` (which assumes `tilesetBase + idx*16`, a
-- regular stride into one contiguous tileset), this is for tiles that
-- are real but scattered at arbitrary, individually-confirmed ROM
-- offsets (e.g. a room whose tiles were identified by searching the ROM
-- for exact live-VRAM tile patterns -- see src/rendering
-- /TileGridBackground.lua). `nil` in `offsets` draws a blank (all-zero)
-- cell (transparent0-style) instead of erroring, for tiles confirmed
-- blank (e.g. an all-zero pattern with no meaningful single ROM
-- source). A `string` entry (exactly `GBTile.TILE_BYTES` long) is a
-- real, live-captured LITERAL tile pattern used directly instead of a
-- ROM offset -- for tiles whose real live content is confirmed (e.g. a
-- genuine solid-fill tile, a real non-blank pattern) but whose ROM
-- *location* is too ambiguous to pick a single one of many identical-
-- byte matches without guessing (same real technique already used for
-- the courtyard gate's own open-state tile, see TilePatch.lua --
-- generalized here 2026-08-09 once a second, independent room needed
-- the same thing: a real solid all-`0xFF` "sky" tile, see rom-map.md).
--
-- `count`: explicit total cell count (defaults to `#offsets`). REQUIRED
-- whenever a blank cell (a `nil` hole) can occur anywhere but the very
-- end of `offsets` -- `#offsets`/`ipairs` both stop at the first nil,
-- silently truncating the whole sheet to zero tiles if cell 1 happens to
-- be blank (found 2026-08-09: startRoom's own blank tile ID never
-- actually starts its grid so this never tripped there, but
-- titleScreen's blank fill tile does -- see TitleScreenBackground.lua).
function TileImage.sheetFromOffsets(data, offsets, columns, palette, transparent0, count, rowSpacing)
  local tiles = {}
  local blankTile = nil
  local literalTiles = {} -- cache by pattern string, avoid re-decoding repeats
  for i = 1, count or #offsets do
    local offset = offsets[i]
    if type(offset) == "string" then
      local cached = literalTiles[offset]
      if not cached then
        cached = GBTile.decodeTile(offset)
        literalTiles[offset] = cached
      end
      tiles[i] = cached
    elseif offset then
      tiles[i] = GBTile.decodeTile(data, offset)
    else
      blankTile = blankTile or GBTile.decodeTile(string.rep("\0", GBTile.TILE_BYTES))
      tiles[i] = blankTile
    end
  end
  return TileImage.buildSheet(tiles, columns, palette, transparent0, rowSpacing)
end

--- Build a two-tone checkerboard Image, `w`x`h`, in `cellSize`-px squares.
-- For displaying transparent0 sheets: DEFAULT_PALETTE's darkest shade is
-- pure black (0,0,0,1), which is indistinguishable from a canvas cleared to
-- black (Renderer:renderTo does exactly that) once transparent0 punches a
-- hole through index-0 pixels -- ink at index 3 silently vanishes against
-- the clear color, with nothing on screen to reveal it's missing (found via
-- the font region: real glyph tiles decoded correctly and had ink per
-- GBTile, but were invisible in the LÖVE app specifically because of this
-- color collision). A checkerboard backdrop guarantees every one of the 4
-- palette shades contrasts against at least one of its two tones, the same
-- treatment image editors use behind transparent layers.
function TileImage.buildCheckerboard(w, h, cellSize, colorA, colorB)
  cellSize = cellSize or 4
  colorA = colorA or { 0.55, 0.55, 0.55, 1 }
  colorB = colorB or { 0.35, 0.35, 0.35, 1 }
  local imageData = love.image.newImageData(w, h)
  imageData:mapPixel(function(x, y)
    local checker = (math.floor(x / cellSize) + math.floor(y / cellSize)) % 2
    local c = checker == 0 and colorA or colorB
    return c[1], c[2], c[3], c[4]
  end)
  local image = love.graphics.newImage(imageData)
  image:setFilter("nearest", "nearest")
  return image
end

return TileImage
