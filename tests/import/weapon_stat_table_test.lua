local Harness = require("tests.harness")
local WeaponStatTable = require("src.import.WeaponStatTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("WeaponStatTable.decode: parses a synthetic 1-row record", function()
  -- flagA=0x00 typeTag=0x11 variantFlag=0x01 byte3=0x00 power=0x04
  -- price=0x003c (bytes 0x3c,0x00 LE) = 60 -- real Broad Sword values
  local row = string.char(0x00, 0x11, 0x01, 0x00, 0x04, 0x3c, 0x00) ..
    string.rep("\0", 9)
  local rows = WeaponStatTable.decode(row, { fileOffset = 0, rowCount = 1 })
  Harness.assertEqual(#rows, 1)
  Harness.assertEqual(rows[1].flagA, 0x00)
  Harness.assertEqual(rows[1].typeTag, 0x11)
  Harness.assertEqual(rows[1].variantFlag, 0x01)
  Harness.assertEqual(rows[1].byte3, 0x00)
  Harness.assertEqual(rows[1].power, 0x04)
  Harness.assertEqual(rows[1].price, 60)
  Harness.assertEqual(#rows[1].raw, 16)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "WeaponStatTable.decode: real ROM's 16-row table matches the US disassembly's weapon list byte-for-byte",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local rows = WeaponStatTable.decode(romData, profile.weaponStatTable)
    Harness.assertEqual(#rows, 16)

    -- Real values from the US "Final Fantasy Adventure" disassembly's
    -- own src/data/items.asm equipmentDataTable (see rom_profiles
    -- .lua's own externalReferenceNames for the name-to-row pairing
    -- and WeaponStatTable.lua's doc comment for the full evidence
    -- trail). This EU ROM matched EVERY ONE of these byte-for-byte.
    local expected = {
      { power = 4, price = 60 },     -- Broad Sword
      { power = 8, price = 180 },    -- Battle Axe
      { power = 9, price = 240 },    -- Sickle
      { power = 10, price = 320 },   -- Chain Flail
      { power = 14, price = 562 },   -- Silver Sword
      { power = 16, price = 1150 },  -- Wind Spear
      { power = 20, price = 1500 },  -- Were Axe
      { power = 30, price = 2025 },  -- Morning Star
      { power = 26, price = 1875 },  -- Blood Sword
      { power = 56, price = 8000 },  -- Dragon Sword
      { power = 38, price = 6300 },  -- Flame Flail
      { power = 40, price = 7500 },  -- Ice Blade
      { power = 48, price = 9800 },  -- Zeus Axe
      { power = 20, price = 35000 }, -- Rusty Sword
      { power = 46, price = 11250 }, -- Thunder Spear
      { power = 85, price = 22500 }, -- Excalibur
    }
    for i, e in ipairs(expected) do
      local r = rows[i]
      Harness.assertEqual(r.power, e.power, "row " .. i .. " power mismatch")
      Harness.assertEqual(r.price, e.price, "row " .. i .. " price mismatch")
    end

    -- `typeTag` (+1) is a real, structurally-constant field across
    -- every row -- a cheap sanity check the table boundary/stride is
    -- still right (would fail loudly if the ROM ever changed or the
    -- offset drifted), same convention as EnemySpeciesTable's own
    -- constant-byte checks.
    for i, r in ipairs(rows) do
      Harness.assertEqual(r.typeTag, 0x11, "row " .. i .. " typeTag should be constant 0x11")
    end
  end
)
