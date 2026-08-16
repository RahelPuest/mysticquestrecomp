local Harness = require("tests.harness")
local CutTransitionTable = require("src.import.CutTransitionTable")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("CutTransitionTable.scanLandingRecords: finds a synthetic real-shaped record", function()
  local rom = string.rep("\0", 5) .. "\x00\x05\xF4\x01\x57\x0E\x0C\x00\x0B" .. string.rep("\0", 5)
  local records = CutTransitionTable.scanLandingRecords(rom)
  Harness.assertEqual(#records, 1)
  Harness.assertEqual(records[1].tileCol, 14)
  Harness.assertEqual(records[1].tileRow, 12)
  Harness.assertEqual(records[1].pixelX, 120)
  Harness.assertEqual(records[1].pixelY, 112)
end)

Harness.test("CutTransitionTable.scanLandingRecords: does not match a near-miss byte sequence", function()
  -- Same bytes, but the trailing terminator is 0x0C, not 0x0B -- must
  -- not match.
  local rom = "\x00\x05\xF4\x01\x57\x0E\x0C\x00\x0C"
  Harness.assertEqual(#CutTransitionTable.scanLandingRecords(rom), 0)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "CutTransitionTable.scanLandingRecords: real ROM has exactly 186 records, all in bank 14, byte-exact match to both already-known real cut transitions",
  romData ~= nil,
  "no development ROM found",
  function()
    local records = CutTransitionTable.scanLandingRecords(romData)
    Harness.assertEqual(#records, 186)
    for _, r in ipairs(records) do
      Harness.assertEqual(r.bank, 14)
    end

    -- thirdRoom -> fourthRoom: real, live-traced landing (120,112).
    local foundThirdToFourth = false
    for _, r in ipairs(records) do
      if r.pixelX == 120 and r.pixelY == 112 and r.a1 == 1 and r.a2 == 87 then
        Harness.assertEqual(r.tileCol, 14)
        Harness.assertEqual(r.tileRow, 12)
        foundThirdToFourth = true
      end
    end
    Harness.assertTrue(foundThirdToFourth, "expected the real thirdRoom->fourthRoom record")

    -- fourthRoom -> fifthRoom: real, live-traced landing (136,32).
    local foundFourthToFifth = false
    for _, r in ipairs(records) do
      if r.pixelX == 136 and r.pixelY == 32 and r.a1 == 4 and r.a2 == 80 then
        foundFourthToFifth = true
      end
    end
    Harness.assertTrue(foundFourthToFifth, "expected the real fourthRoom->fifthRoom record")
  end
)

Harness.testIfAvailable(
  "CutTransitionTable.scanSelectorRecords: real ROM has 36 real records, idx values fall inside roomSelectorTable's own real 0-15 range",
  romData ~= nil,
  "no development ROM found",
  function()
    local records = CutTransitionTable.scanSelectorRecords(romData)
    Harness.assertEqual(#records, 36)
    for _, r in ipairs(records) do
      Harness.assertEqual(r.bank, 14)
      Harness.assertTrue(r.idx >= 0 and r.idx <= 15, "expected idx inside the real 0-15 roomSelector range")
    end
  end
)

return true
