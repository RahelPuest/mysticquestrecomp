local Harness = require("tests.harness")
local ActorDefinitionTable = require("src.import.ActorDefinitionTable")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("ActorDefinitionTable.fileOffset: bank 3 CPU 0x5f5a matches the known real table base", function()
  Harness.assertEqual(ActorDefinitionTable.fileOffset(3, 0x5f5a), 0xdf5a)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ActorDefinitionTable.readRecord: both live-confirmed indices resolve to well-formed real records",
  romData ~= nil,
  "no development ROM found",
  function()
    for _, entry in ipairs(ActorDefinitionTable.LIVE_CONFIRMED) do
      local record = ActorDefinitionTable.readRecord(romData, entry.index)
      Harness.assertTrue(record ~= nil, "expected a record at index " .. entry.index)
      Harness.assertEqual(#record.raw, 24)
      -- The sprite pointer must land in the real bank-3 banked window
      -- (0x4000-0x7fff) -- every live-sampled record does.
      Harness.assertTrue(
        record.spritePointer >= 0x4000 and record.spritePointer <= 0x7fff,
        "expected spritePointer inside the bank-3 window, got " .. record.spritePointer
      )
    end
  end
)

Harness.testIfAvailable(
  "ActorDefinitionTable: the two live-confirmed sub-records differ by exactly +0x20 on every varying byte",
  romData ~= nil,
  "no development ROM found",
  function()
    local rec99 = ActorDefinitionTable.readRecord(romData, 99)
    local rec121 = ActorDefinitionTable.readRecord(romData, 121)
    local sub99 = ActorDefinitionTable.readSpriteSubRecord(romData, rec99)
    local sub121 = ActorDefinitionTable.readSpriteSubRecord(romData, rec121)
    Harness.assertEqual(#sub99.raw, 24)
    Harness.assertEqual(#sub121.raw, 24)

    local sawVaryingByte = false
    for i = 1, 24 do
      local b99, b121 = sub99.raw:byte(i), sub121.raw:byte(i)
      if b99 ~= b121 then
        sawVaryingByte = true
        Harness.assertEqual(b99 - b121, 0x20)
      end
    end
    Harness.assertTrue(sawVaryingByte, "expected at least one varying byte between the two sub-records")
  end
)

Harness.testIfAvailable(
  "ActorDefinitionTable.scanTable: the real measured extent is exactly 218 records, 5 of them anomalous (index 0 and the 12-15 cluster)",
  romData ~= nil,
  "no development ROM found",
  function()
    local records = ActorDefinitionTable.scanTable(romData)
    Harness.assertEqual(#records, ActorDefinitionTable.TABLE_COUNT)
    Harness.assertEqual(#records, 218)

    local anomalousIndices, plausibleCount, subRecordCount = {}, 0, 0
    for _, record in ipairs(records) do
      if record.anomalous then
        anomalousIndices[#anomalousIndices + 1] = record.index
      else
        plausibleCount = plausibleCount + 1
        Harness.assertTrue(record.spriteSubRecord ~= nil, "expected a sub-record for a non-anomalous entry")
        subRecordCount = subRecordCount + 1
      end
    end
    Harness.assertEqual(#anomalousIndices, 5)
    Harness.assertEqual(table.concat(anomalousIndices, ","), "0,12,13,14,15")
    Harness.assertEqual(plausibleCount, 213)
    Harness.assertEqual(subRecordCount, 213)
  end
)

Harness.testIfAvailable(
  "ActorDefinitionTable.readRecord: index 218 (just past the measured extent) is a real record but NOT part of the coherent table",
  romData ~= nil,
  "no development ROM found",
  function()
    -- This is the exact boundary this module's own extent measurement
    -- rests on: index 218's spritePointer must NOT land in the normal
    -- bank-3 window, confirming the table really does end at 217.
    local record = ActorDefinitionTable.readRecord(romData, 218)
    Harness.assertTrue(record ~= nil)
    Harness.assertTrue(record.anomalous, "expected index 218 to fall outside the coherent table")
  end
)
