-- Locks in the real `font.extraGlyphs` tile offsets in rom_profiles.lua
-- against the actual ROM bytes -- a real regression guard for glyph
-- rendering data, same spirit as room_floor_layout_test.lua locking in
-- exact-grid decodes rather than trusting a one-time screenshot forever.
--
-- Deliberately its OWN small file rather than folded into
-- text_decoder_test.lua: that file tests TextDecoder's byte->character
-- DECODING (`decodeByte(0xF4) == "?"`, already covered there); this file
-- tests the separate, previously-missing FONT RENDERING data (does
-- `rom_profiles.lua` know which real ROM tile draws that "?"), which
-- needs GBTile + RomProfiles, not TextDecoder at all.

local Harness = require("tests.harness")
local GBTile = require("src.rendering.GBTile")
local DevRomLocator = require("tests.dev_rom_locator")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")

local romData = DevRomLocator.find()

--- Render a decoded GBTile.decodeTile grid (0-3 palette indices) as an
-- 8-row array of "." / "#" strings (0 = blank, anything else = ink) --
-- matches this project's own established ASCII-art convention for
-- eyeballing/locking in font glyph shapes (see rom_profiles.lua's
-- `font.extraGlyphs` doc comment, tools/graphics/gbtile.py).
local function asciiRows(tile)
  local rows = {}
  for y = 1, 8 do
    local chars = {}
    for x = 1, 8 do
      chars[x] = (tile[y][x] ~= 0) and "#" or "."
    end
    rows[y] = table.concat(chars)
  end
  return rows
end

local function assertRowsEqual(actual, expected, label)
  Harness.assertEqual(#actual, #expected, label .. ": row count")
  for i = 1, #expected do
    Harness.assertEqual(actual[i], expected[i], label .. ": row " .. i)
  end
end

Harness.testIfAvailable(
  "rom_profiles font.extraGlyphs: '?' (QUESTION_BYTE 0xF4) is a real, correctly-shaped glyph tile (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local offset = profile.graphics.font.extraGlyphs["?"]
    Harness.assertEqual(offset, 0x22F40,
      "expected the real, formula-derived tile offset for QUESTION_BYTE (tile 0x44)")

    local tile = GBTile.decodeTile(romData, offset)
    -- Real, decoded pixel grid (see rom_profiles.lua's own doc comment
    -- for the full derivation) -- an unambiguous "?": a curved hook
    -- over a single dot.
    assertRowsEqual(asciiRows(tile), {
      "..####..",
      ".##..##.",
      ".##..##.",
      "....##..",
      "...##...",
      "...##...",
      "........",
      "...##...",
    }, "'?' glyph tile")
  end
)

Harness.testIfAvailable(
  "rom_profiles font.extraGlyphs: ':' (COLON_BYTE 0xF5) is a real, correctly-shaped glyph tile (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local offset = profile.graphics.font.extraGlyphs[":"]
    Harness.assertEqual(offset, 0x22F50,
      "expected the real, formula-derived tile offset for COLON_BYTE (tile 0x45)")

    local tile = GBTile.decodeTile(romData, offset)
    -- Real, decoded pixel grid -- two stacked dots, an unambiguous ":".
    assertRowsEqual(asciiRows(tile), {
      "........",
      ".##.....",
      ".##.....",
      "........",
      "........",
      ".##.....",
      ".##.....",
      "........",
    }, "':' glyph tile")
  end
)

Harness.testIfAvailable(
  "rom_profiles font: the still-unmapped gap tile (byte 0xF1, between PERIOD and HYPHEN) is NOT silently guessed into extraGlyphs (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Honest negative check, matching this project's own "don't
    -- fabricate ROM behavior" rule: rom_profiles.lua's own doc comment
    -- notes this tile (0x22F10) visually looks like a real glyph (two
    -- side-by-side dots, plausibly a double-quote) but no real ROM text
    -- byte has been confirmed to map to it yet -- so it must stay OUT
    -- of `extraGlyphs` until (if ever) that confirmation exists, not be
    -- silently added on shape alone. This test exists so a future,
    -- well-meaning "complete the punctuation set" pass doesn't
    -- accidentally re-introduce a guessed mapping without also adding
    -- the real byte-occurrence evidence this project's own bar requires.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    for char, offset in pairs(profile.graphics.font.extraGlyphs) do
      Harness.assertTrue(offset ~= 0x22F10,
        "found a real extraGlyphs entry ('" .. char .. "') pointing at the " ..
        "still-unconfirmed gap tile 0x22F10 -- see this test's own doc " ..
        "comment before adding one")
    end
  end
)

if romData then
  print("(rom_profiles font tests ran against a real dev ROM)")
end
