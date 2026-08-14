local Harness = require("tests.harness")
local ItemTable = require("src.import.ItemTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("ItemTable.decode: parses a synthetic 2-record table", function()
  -- record0: name "Lebe" (0x00-padded to 8), then 8 stat/trailer bytes,
  -- id byte (byte 15) = 1.
  local rec0 = "\197\216\213\216\0\0\0\0" .. "\66\16\20\0\0\0\0\1"
  -- record1: name "Salb", category byte differs, id = 2.
  local rec1 = "\204\212\223\213\0\0\0\0" .. "\65\16\0\0\0\0\0\2"
  local rom = rec0 .. rec1
  local itemTable = { fileOffset = 0, recordLength = 16, nameLength = 8, recordCount = 2 }

  local records = ItemTable.decode(rom, itemTable)
  Harness.assertEqual(#records, 2)
  Harness.assertEqual(records[1].name, "Lebe")
  Harness.assertEqual(records[1].id, 1)
  Harness.assertEqual(records[1].categoryByte, 0x42)
  Harness.assertEqual(records[2].name, "Salb")
  Harness.assertEqual(records[2].id, 2)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ItemTable.decode: real ROM decodes the known item/spell name sequence",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)
    Harness.assertEqual(#records, 20)

    -- Cross-check against docs/reverse-engineering/text.md's documented
    -- item list (first 8 slots -- consumable items).
    local expectedNames = {
      "Lebe", "Salb", "Blok", "Ruhe", "Flam", "Eis ", "Bliz", "Bomb",
    }
    for i, name in ipairs(expectedNames) do
      Harness.assertEqual(records[i].name, name,
        "record " .. (i - 1) .. " name")
    end

    -- The per-category ID byte (byte 15) is VERIFIED to reset to 0 right
    -- at the item/spell category boundary (rom-map.md "Item/spell table").
    -- categoryBoundaryRecord is the 0-based index of the first spell
    -- record; records[] is 1-based, so +1 to convert.
    Harness.assertEqual(records[profile.itemTable.categoryBoundaryRecord + 1].id, 1,
      "first spell record's id should restart the per-category counter at 1")
    Harness.assertEqual(records[profile.itemTable.categoryBoundaryRecord].id, 0,
      "last item record's id is the documented 0 boundary marker")
  end
)

if romData then
  print("(ItemTable ROM-dependent tests ran against a real dev ROM)")
end
