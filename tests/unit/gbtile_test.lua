local Harness = require("tests.harness")
local GBTile = require("src.rendering.GBTile")

-- Hand-derived synthetic tile, independent of any ROM: a checkerboard
-- where even columns (x=0,2,4,6) are palette index 1 (low bit set, high
-- bit clear) and odd columns (x=1,3,5,7) are palette index 2 (low bit
-- clear, high bit set), same on every row.
--
-- Low-bit-plane byte per row: bit(7-x) set for x=0,2,4,6 -> 0b10101010 = 0xAA
-- High-bit-plane byte per row: bit(7-x) set for x=1,3,5,7 -> 0b01010101 = 0x55
Harness.test("GBTile.decodeTile: checkerboard pattern", function()
  local rowBytes = string.char(0xAA, 0x55)
  local tile = string.rep(rowBytes, 8)
  Harness.assertEqual(#tile, 16)
  local decoded = GBTile.decodeTile(tile)
  Harness.assertEqual(#decoded, 8, "8 rows")
  for y = 1, 8 do
    Harness.assertEqual(#decoded[y], 8, "8 columns in row " .. y)
    for x = 1, 8 do
      local expected = (x % 2 == 1) and 1 or 2
      Harness.assertEqual(decoded[y][x], expected,
        string.format("pixel (row %d, col %d)", y, x))
    end
  end
end)

Harness.test("GBTile.decodeTile: all-zero tile is all palette index 0", function()
  local tile = string.rep("\0", 16)
  local decoded = GBTile.decodeTile(tile)
  for y = 1, 8 do
    for x = 1, 8 do
      Harness.assertEqual(decoded[y][x], 0)
    end
  end
end)

Harness.test("GBTile.decodeTile: all-0xFF tile is all palette index 3", function()
  local tile = string.rep("\255", 16)
  local decoded = GBTile.decodeTile(tile)
  for y = 1, 8 do
    for x = 1, 8 do
      Harness.assertEqual(decoded[y][x], 3)
    end
  end
end)

Harness.test("GBTile.decodeTile: leftmost pixel is bit 7 (MSB-first)", function()
  -- Row byte pair (0x80, 0x00): only bit 7 set in the low-plane byte ->
  -- pixel x=0 (leftmost) should be index 1, all others 0.
  local tile = string.rep(string.char(0x80, 0x00), 8)
  local decoded = GBTile.decodeTile(tile)
  Harness.assertEqual(decoded[1][1], 1, "leftmost pixel")
  for x = 2, 8 do
    Harness.assertEqual(decoded[1][x], 0, "pixel " .. x .. " should be blank")
  end
end)

Harness.test("GBTile.decodeTiles: decodes N consecutive tiles", function()
  local blank = string.rep("\0", 16)
  local solid = string.rep("\255", 16)
  local data = blank .. solid .. blank
  local tiles = GBTile.decodeTiles(data, 0, 3)
  Harness.assertEqual(#tiles, 3)
  Harness.assertEqual(tiles[1][1][1], 0)
  Harness.assertEqual(tiles[2][1][1], 3)
  Harness.assertEqual(tiles[3][1][1], 0)
end)

Harness.test("GBTile.decodeTiles: offset into a larger buffer", function()
  local blank = string.rep("\0", 16)
  local solid = string.rep("\255", 16)
  local data = blank .. solid
  local tiles = GBTile.decodeTiles(data, 16, 1)
  Harness.assertEqual(#tiles, 1)
  Harness.assertEqual(tiles[1][1][1], 3)
end)

Harness.test("GBTile.tileEntropy: blank tile has zero entropy", function()
  local tile = GBTile.decodeTile(string.rep("\0", 16))
  Harness.assertEqual(GBTile.tileEntropy(tile), 0.0)
end)

Harness.test("GBTile.tileEntropy: checkerboard (2 equal symbols) has entropy 1.0", function()
  local tile = GBTile.decodeTile(string.rep(string.char(0xAA, 0x55), 8))
  local h = GBTile.tileEntropy(tile)
  Harness.assertTrue(math.abs(h - 1.0) < 1e-9,
    "expected entropy ~1.0, got " .. tostring(h))
end)
