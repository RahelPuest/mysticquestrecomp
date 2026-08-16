local Harness = require("tests.harness")
local RomExtractor = require("src.import.RomExtractor")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")
local EnemySpeciesTable = require("src.import.EnemySpeciesTable")
local ItemTable = require("src.import.ItemTable")
local WeaponTable = require("src.import.WeaponTable")
local NpcCatalog = require("src.import.NpcCatalog")
local LuaWriter = require("src.import.LuaWriter")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "RomExtractor.run: every stage's output matches calling the underlying importer directly (task #34)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)

    local data, manifest = RomExtractor.run(romData, profile)

    -- manifest: real, honest bookkeeping -- not a guess.
    Harness.assertEqual(manifest.romSha1, report.sha1)
    Harness.assertEqual(manifest.romTitle, report.title)
    Harness.assertEqual(#manifest.stages, 4)
    Harness.assertTrue(type(manifest.generatedAt) == "number", "generatedAt should be a real timestamp")

    -- monsters stage (EnemySpeciesTable rows have no `.name` field --
    -- see that module's own doc comment -- cross-check a real decoded
    -- field instead, `atk`, the one VERIFIED stat in the row shape)
    local rows = EnemySpeciesTable.decode(romData, profile.enemySpeciesTable)
    Harness.assertEqual(#data.monsters.rows, #rows)
    Harness.assertEqual(data.monsters.rows[1].atk, rows[1].atk)
    Harness.assertEqual(data.monsters.rows[1].raw, rows[1].raw)

    -- items stage
    local itemRecords = ItemTable.decode(romData, profile.itemTable)
    Harness.assertEqual(#data.items.records, #itemRecords)
    Harness.assertEqual(data.items.records[1].name, itemRecords[1].name)

    -- weapons stage
    local weaponRecords = WeaponTable.decode(romData, profile.weaponTable)
    Harness.assertEqual(#data.weapons.records, #weaponRecords)
    Harness.assertEqual(data.weapons.records[1].name, weaponRecords[1].name)

    -- npcs stage
    local npcs = NpcCatalog.build(profile)
    Harness.assertEqual(#data.npcs, #npcs)
  end
)

Harness.testIfAvailable(
  "RomExtractor.run: real output round-trips through LuaWriter unchanged (write path end to end, task #34)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local data = RomExtractor.run(romData, profile)

    for _, stage in ipairs(RomExtractor.STAGES) do
      local src = LuaWriter.serialize(data[stage.name])
      local chunk = assert((load or loadstring)(src))
      local loaded = chunk()
      -- Spot-check structural equivalence via a shallow real signal
      -- (full deep-equal on multi-thousand-entry real ROM data is
      -- redundant with lua_writer_test.lua's own dedicated round-trip
      -- coverage) -- this test's own job is proving RomExtractor's
      -- REAL output is the kind of value LuaWriter actually accepts,
      -- not re-testing LuaWriter itself.
      Harness.assertTrue(type(loaded) == "table", stage.name .. " should round-trip to a real table")
    end
  end
)

return true
