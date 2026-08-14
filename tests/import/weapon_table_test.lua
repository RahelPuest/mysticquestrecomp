local Harness = require("tests.harness")
local WeaponTable = require("src.import.WeaponTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("WeaponTable.decode: parses a synthetic record (stats, category, then name)", function()
  -- 5 stat bytes, 1 category byte, 8-byte name "Breit" (0x00-padded), 2 trailer bytes.
  local rec = "\0\0\255\255\0" .. "\164" .. "\187\229\216\220\231\0\0\0" .. "\17\1"
  local weaponTable = { fileOffset = 0, recordLength = 16, nameOffset = 6, recordCount = 1 }

  local records = WeaponTable.decode(rec, weaponTable)
  Harness.assertEqual(#records, 1)
  Harness.assertEqual(records[1].name, "Breit")
  Harness.assertEqual(records[1].categoryByte, 0xA4)
  Harness.assertEqual(#records[1].statBytes, 5)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "WeaponTable.decode: real ROM decodes the live-cross-checked \"Breit\" weapon name",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = WeaponTable.decode(romData, profile.weaponTable)
    Harness.assertEqual(#records, 20)

    -- "Breit" is the specific name this project found live in the
    -- in-game menu's equipped-weapon HUD readout and then located
    -- verbatim in the ROM (rom-map.md "the menu's `Breit` equipped-
    -- weapon readout") -- the single strongest cross-check this table
    -- has. It's the 4th record in the scanned window.
    Harness.assertEqual(records[4].name, "Breit")

    -- A few more names from the same documented scan, for a broader
    -- sanity check that record alignment holds across the whole table.
    Harness.assertEqual(records[1].name, "Juwelen")
    Harness.assertEqual(records[2].name, "Opale")
    Harness.assertEqual(records[5].name, "Axt")
  end
)

if romData then
  print("(WeaponTable ROM-dependent tests ran against a real dev ROM)")
end
