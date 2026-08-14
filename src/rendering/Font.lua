-- Renders decoded Mystic Quest text (src/import/TextDecoder.lua output)
-- using the real, VERIFIED in-ROM font tiles (rom_profiles.lua's
-- `graphics.font` region) -- the first real font-rendering in this
-- project; previously dialogue/HUD text only existed as decoded Lua
-- strings or `love.graphics.print` placeholder text (see Field.lua's
-- former "HUD placeholder" comment).
--
-- Glyph coverage: TextDecoder.MAIN_GLYPHS (the 64-character alphabet
-- VERIFIED via the font's own ROM tile order, see rom_profiles.lua's
-- `rowGlyphs`) plus `font.extraGlyphs` (punctuation, and -- 2026-08-10
-- -- the 7 real umlaut/eszett glyphs, see that field's own doc
-- comment). Space (` `) advances the cursor without drawing (the font
-- has no blank/space tile in its VERIFIED range).
--
-- CORRECTED (2026-08-10, direct user report: "es gibt ein problem mit
-- umlauten"): `TextDecoder` now emits umlauts as their real single
-- UTF-8 characters (2 bytes each, e.g. "\195\164" for ä) instead of a
-- 2-LETTER ASCII substitution ("ae") -- this module's own `:print`/
-- `:measure` used to iterate `text` one BYTE at a time (`text:sub(i,i)`
-- ), which is wrong for any multi-byte UTF-8 character: it would have
-- tried to look up each raw UTF-8 byte as its own "glyph" (finding
-- nothing, silently skipping both and leaving a double-wide gap).
-- `nextGlyph()` below now advances by a real UTF-8 character boundary
-- (1 byte for ASCII, 2-4 bytes for a multi-byte sequence, detected from
-- the lead byte's own high bits -- standard UTF-8 encoding, not a
-- guess), so a german ROM string with ä/ö/ü/ß renders and measures
-- correctly.

local TileImage = require("src.rendering.TileImage")
local GBTile = require("src.rendering.GBTile")

local Font = {}
Font.__index = Font

-- Every non-zero palette index renders as solid white "ink"; index 0 is
-- made transparent (transparent0=true below) so the font sheet can sit
-- over any background color. Deliberately NOT TileImage.DEFAULT_PALETTE
-- (a white->black shade ramp): this project already hit, and documented,
-- exactly this failure once before (see TileImage.buildCheckerboard's
-- doc comment) -- DEFAULT_PALETTE's darkest shade (index 3) is pure
-- black, which is invisible with transparent0 against a black-cleared
-- canvas or (here) a black HUD bar. Rendering all ink as white sidesteps
-- needing to know which of 1-3 the real font tiles actually use for
-- strokes vs. anti-aliasing, and matches this project's own live
-- gameplay screenshots (white HUD text on a black bar).
local INK_PALETTE = {
  { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 },
}

--- Build a Font from `romData` + a matched rom_profiles entry. Requires
-- love.graphics (not headlessly testable, unlike GBTile/TextDecoder --
-- see docs/architecture.md's rendering-vs-pure-logic split).
function Font.new(romData, profile)
  assert(profile and profile.graphics and profile.graphics.font,
    "Font.new expects a profile with a graphics.font entry")
  local fontInfo = profile.graphics.font

  -- Flatten rowGlyphs into a single glyph-order string, matching how the
  -- tiles are laid out sequentially in ROM (16 tiles/row).
  local glyphOrder = table.concat(fontInfo.rowGlyphs)

  local sheet, sheetW, sheetH = TileImage.sheetFromBytes(
    romData, fontInfo.fileOffset, fontInfo.tileCount, 16, INK_PALETTE, true)

  -- Build a char -> { image, quad } lookup, one per glyph tile. Stored
  -- with an explicit `image` (not just a bare Quad assuming `self.sheet`)
  -- because `extraGlyphs` below live at real ROM offsets outside this
  -- contiguous main sheet -- a second, small sheet, not a hole in this
  -- one.
  local quads = {}
  for i = 1, #glyphOrder do
    local ch = glyphOrder:sub(i, i)
    local index = i - 1
    local tx = (index % 16) * GBTile.TILE_W
    local ty = math.floor(index / 16) * GBTile.TILE_H
    quads[ch] = { image = sheet,
      quad = love.graphics.newQuad(tx, ty, GBTile.TILE_W, GBTile.TILE_H, sheetW, sheetH) }
  end

  -- VERIFIED (2026-08-09) real period/hyphen glyphs (see rom_profiles
  -- .lua's `font.extraGlyphs` doc comment -- direct fix for text
  -- silently missing its punctuation, e.g. sentences in the intro-text
  -- scroll rendering with no "."). Each real ROM offset, one tile each,
  -- not part of the main contiguous sheet above.
  if fontInfo.extraGlyphs then
    for ch, offset in pairs(fontInfo.extraGlyphs) do
      local extraSheet, extraW, extraH = TileImage.sheetFromBytes(romData, offset, 1, 1, INK_PALETTE, true)
      quads[ch] = { image = extraSheet,
        quad = love.graphics.newQuad(0, 0, GBTile.TILE_W, GBTile.TILE_H, extraW, extraH) }
    end
  end

  return setmetatable({
    sheet = sheet,
    quads = quads,
    charW = GBTile.TILE_W,
    charH = GBTile.TILE_H,
  }, Font)
end

--- Real UTF-8 character-boundary step: given a byte at 1-based index
-- `i` in `text`, returns the number of bytes that one real character
-- occupies starting there (1 for plain ASCII, 2-4 for a multi-byte
-- UTF-8 sequence, per the lead byte's own high bits -- standard UTF-8,
-- not project-specific). A stray/invalid continuation byte (shouldn't
-- happen with real TextDecoder output, but defensive) steps by 1
-- rather than throwing, so a corrupt string degrades to a skipped
-- glyph instead of crashing rendering.
local function utf8CharLen(text, i)
  local b = text:byte(i)
  if not b then return 1 end
  if b < 0x80 then return 1 end
  if b >= 0xF0 then return 4 end
  if b >= 0xE0 then return 3 end
  if b >= 0xC0 then return 2 end
  return 1 -- a bare continuation byte -- not a real lead byte
end

--- Draw `text` (a TextDecoder.decodeString-style Lua string) at (x, y),
-- one glyph tile per real character (UTF-8-aware, see `utf8CharLen` --
-- 2026-08-10, fixes umlauts silently mis-rendering as a double-wide
-- gap), left to right, no wrapping. Unknown characters (including a
-- genuinely undecoded umlaut/icon byte) are skipped with a cursor
-- advance, not drawn as a guess. Returns the final cursor x (useful for
-- chaining prints).
function Font:print(text, x, y, color)
  love.graphics.setColor(color or { 1, 1, 1, 1 })
  local cursorX = x
  local i = 1
  while i <= #text do
    local len = utf8CharLen(text, i)
    local ch = text:sub(i, i + len - 1)
    local entry = self.quads[ch]
    if entry then
      love.graphics.draw(entry.image, entry.quad, cursorX, y)
    end
    cursorX = cursorX + self.charW
    i = i + len
  end
  love.graphics.setColor(1, 1, 1, 1)
  return cursorX
end

--- Pixel width `text` would occupy when printed (fixed-width glyphs).
-- CORRECTED (2026-08-10): counts real UTF-8 characters, not raw bytes
-- -- `#text * self.charW` overcounted any umlaut (2 bytes, 1 real
-- glyph) as two characters' worth of width, same root cause as
-- `:print`'s own fix above.
function Font:measure(text)
  local count = 0
  local i = 1
  while i <= #text do
    i = i + utf8CharLen(text, i)
    count = count + 1
  end
  return count * self.charW
end

return Font
