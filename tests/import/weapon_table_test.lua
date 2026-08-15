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
    Harness.assertEqual(#records, 48) -- extended 2026-08-15, see rom_profiles.lua's own doc comment

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

Harness.testIfAvailable(
  "WeaponTable.decode: real, further weapon/armor names found past the previous 20-record boundary, 2026-08-15",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = WeaponTable.decode(romData, profile.weaponTable)
    -- Real material-tier armor names and unique named weapons found by
    -- extending the scan (see rom_profiles.lua's own doc comment for
    -- the full trail) -- previous recordCount=20 silently cut off more
    -- than half the real table.
    Harness.assertEqual(records[13].name, "Drache")
    Harness.assertEqual(records[17].name, "Rostig")
    Harness.assertEqual(records[20].name, "Bronze")
    Harness.assertEqual(records[37].name, "Ägis")
    Harness.assertEqual(records[47].name, "Samurai")
    Harness.assertEqual(records[20].name, records[42].name) -- "Bronze" armor tier repeats, real not a bug
  end
)

Harness.testIfAvailable(
  "WeaponTable.groupByCategory: real categoryByte groups from the ROM (catalog plan Phase 2, 2026-08-15)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = WeaponTable.decode(romData, profile.weaponTable)
    local groups = WeaponTable.groupByCategory(records)

    -- Real, live-decoded counts (see WeaponTable.lua's own
    -- `groupByCategory` doc comment) -- locks in the exact grouping so
    -- a future table-boundary extension shows up as a clear, honest
    -- test failure instead of silently drifting.
    local expected = {
      [153] = 2, [160] = 9, [161] = 7, [162] = 9, [163] = 2, [164] = 7,
      [165] = 3, [166] = 1, [167] = 1, [168] = 2, [173] = 2, [225] = 2, [227] = 1,
    }
    local totalRecords = 0
    for _, g in ipairs(groups) do
      Harness.assertEqual(g.count, expected[g.categoryByte],
        "categoryByte " .. g.categoryByte .. " count")
      Harness.assertEqual(#g.records, g.count)
      totalRecords = totalRecords + g.count
    end
    Harness.assertEqual(#groups, 13)
    Harness.assertEqual(totalRecords, #records, "every real record must land in exactly one group")

    -- The 3 real, human-readable material/elemental tier progressions
    -- this project found (see the module's own doc comment) --
    -- sizeClass is a plain size threshold, not a claimed slot name.
    for _, categoryByte in ipairs({ 160, 161, 162 }) do
      local found = false
      for _, g in ipairs(groups) do
        if g.categoryByte == categoryByte then
          Harness.assertEqual(g.sizeClass, "group")
          found = true
        end
      end
      Harness.assertTrue(found, "categoryByte " .. categoryByte .. " should be present")
    end
    -- A real one-off, individually-named piece of equipment.
    for _, g in ipairs(groups) do
      if g.categoryByte == 166 then
        Harness.assertEqual(g.sizeClass, "single")
        Harness.assertEqual(g.records[1].name, "Sichel")
      end
    end

    -- Groups come back sorted ascending by the real categoryByte.
    for i = 2, #groups do
      Harness.assertTrue(groups[i].categoryByte > groups[i - 1].categoryByte)
    end
  end
)

if romData then
  print("(WeaponTable ROM-dependent tests ran against a real dev ROM)")
end
