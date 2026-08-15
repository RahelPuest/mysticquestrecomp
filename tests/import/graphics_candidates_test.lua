local Harness = require("tests.harness")
local GraphicsCandidates = require("src.import.GraphicsCandidates")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("GraphicsCandidates.tileOffsets: expands a real, contiguous 16-byte-stride run", function()
  local offsets = GraphicsCandidates.tileOffsets({ fileOffset = 0x2B900, tileCount = 4 })
  Harness.assertEqual(#offsets, 4)
  Harness.assertEqual(offsets[1], 0x2B900)
  Harness.assertEqual(offsets[2], 0x2B910)
  Harness.assertEqual(offsets[3], 0x2B920)
  Harness.assertEqual(offsets[4], 0x2B930)
end)

Harness.test("GraphicsCandidates.ENTRIES: every entry has the required fields, no fabricated confidence", function()
  Harness.assertTrue(#GraphicsCandidates.ENTRIES > 0)
  for _, e in ipairs(GraphicsCandidates.ENTRIES) do
    Harness.assertTrue(type(e.id) == "string" and #e.id > 0)
    Harness.assertTrue(type(e.bank) == "number")
    Harness.assertTrue(type(e.fileOffset) == "number" and e.fileOffset >= 0)
    Harness.assertTrue(type(e.tileCount) == "number" and e.tileCount > 0)
    Harness.assertTrue(type(e.cols) == "number" and e.cols > 0)
    Harness.assertTrue(type(e.note) == "string" and #e.note > 0)
    -- Real, tile-aligned (matches the 16-byte GB tile stride every
    -- offset in this project's own tileOffsets fields already assumes).
    Harness.assertEqual(e.fileOffset % 16, 0)
  end
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "GraphicsCandidates: every real entry's own tile range stays inside the actual ROM file",
  romData ~= nil,
  "no development ROM found",
  function()
    for _, e in ipairs(GraphicsCandidates.ENTRIES) do
      local offsets = GraphicsCandidates.tileOffsets(e)
      local lastTileEnd = offsets[#offsets] + 16
      Harness.assertTrue(lastTileEnd <= #romData,
        "entry " .. e.id .. " runs past the real ROM's own end")
      -- Real, non-degenerate tile data: not every byte in the region is
      -- identical (rules out an entry accidentally pointing at a solid
      -- fill/padding block instead of real art).
      local region = romData:sub(e.fileOffset + 1, offsets[#offsets] + 16)
      local allSame = true
      for i = 2, #region do
        if region:byte(i) ~= region:byte(1) then allSame = false; break end
      end
      Harness.assertTrue(not allSame, "entry " .. e.id .. " is a solid fill, not real art")
    end
  end)

return true
