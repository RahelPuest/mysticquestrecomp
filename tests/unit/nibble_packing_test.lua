local Harness = require("tests.harness")
local NibblePacking = require("src.save.NibblePacking")

Harness.test("NibblePacking.packByte: known real values", function()
  -- The real magic byte (0x6C = 0110 1100): low nibble 0xC, high nibble 0x6.
  local lo, hi = NibblePacking.packByte(0x6C)
  Harness.assertEqual(lo, 0xC)
  Harness.assertEqual(hi, 0x6)

  local lo0, hi0 = NibblePacking.packByte(0x00)
  Harness.assertEqual(lo0, 0)
  Harness.assertEqual(hi0, 0)

  local loF, hiF = NibblePacking.packByte(0xFF)
  Harness.assertEqual(loF, 0xF)
  Harness.assertEqual(hiF, 0xF)
end)

Harness.test("NibblePacking.unpackByte: inverse of packByte", function()
  Harness.assertEqual(NibblePacking.unpackByte(0xC, 0x6), 0x6C)
  Harness.assertEqual(NibblePacking.unpackByte(0, 0), 0)
  Harness.assertEqual(NibblePacking.unpackByte(0xF, 0xF), 0xFF)
end)

Harness.test("NibblePacking: pack/unpack round-trips for every possible byte value (0-255)", function()
  for byte = 0, 255 do
    local lo, hi = NibblePacking.packByte(byte)
    Harness.assertTrue(lo >= 0 and lo <= 15, "low cell out of nibble range for byte " .. byte)
    Harness.assertTrue(hi >= 0 and hi <= 15, "high cell out of nibble range for byte " .. byte)
    Harness.assertEqual(NibblePacking.unpackByte(lo, hi), byte)
  end
end)

Harness.test("NibblePacking.packByte: fails loudly on an out-of-range byte", function()
  Harness.assertTrue(not pcall(NibblePacking.packByte, 256))
  Harness.assertTrue(not pcall(NibblePacking.packByte, -1))
end)

Harness.test("NibblePacking.packBytes/unpackBytes: round-trip a whole array, real 2-cells-per-byte layout", function()
  local bytes = { 0x6C, 0x13, 0x00, 0xFF, 0x42 }
  local cells = NibblePacking.packBytes(bytes)
  Harness.assertEqual(#cells, #bytes * 2)
  -- Real layout: cell[1]=low(byte1), cell[2]=high(byte1), cell[3]=low(byte2), ...
  Harness.assertEqual(cells[1], 0xC) -- low(0x6C)
  Harness.assertEqual(cells[2], 0x6) -- high(0x6C)

  local roundTrip = NibblePacking.unpackBytes(cells)
  Harness.assertEqual(#roundTrip, #bytes)
  for i, b in ipairs(bytes) do
    Harness.assertEqual(roundTrip[i], b)
  end
end)

Harness.test("NibblePacking.unpackBytes: fails loudly on an odd cell count", function()
  local ok = pcall(NibblePacking.unpackBytes, { 1, 2, 3 })
  Harness.assertTrue(not ok, "expected unpackBytes to reject an odd number of cells")
end)
