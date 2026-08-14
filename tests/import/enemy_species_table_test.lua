local Harness = require("tests.harness")
local EnemySpeciesTable = require("src.import.EnemySpeciesTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("EnemySpeciesTable.decode: parses a synthetic 2-row table", function()
  -- row 1: flagVariant=0x90, defCandidate1=0x02, atk=0x8C, defCandidate2=0x02
  -- row 2: flagVariant=0xFF, defCandidate1=0x41, atk=0x8C, defCandidate2=0x32
  local rom = "\0\32\144\0\140\2\2\0" .. "\0\32\255\0\140\65\50\0"
  local rows = EnemySpeciesTable.decode(rom, { fileOffset = 0, rowCount = 2 })
  Harness.assertEqual(#rows, 2)
  Harness.assertEqual(rows[1].atk, 0x8C)
  Harness.assertEqual(rows[1].flagVariant, 0x90)
  Harness.assertEqual(rows[1].defCandidate1, 0x02)
  Harness.assertEqual(rows[1].defCandidate2, 0x02)
  Harness.assertEqual(rows[2].atk, 0x8C)
  Harness.assertEqual(rows[2].flagVariant, 0xFF)
  Harness.assertEqual(#rows[1].raw, 8)
end)

Harness.test("EnemySpeciesTable.groupBySpecies: collapses consecutive identical rows", function()
  local rom = string.rep("\0\32\144\0\140\2\2\0", 2) .. "\0\32\255\0\140\65\50\0"
  local rows = EnemySpeciesTable.decode(rom, { fileOffset = 0, rowCount = 3 })
  local species = EnemySpeciesTable.groupBySpecies(rows)
  Harness.assertEqual(#species, 2)
  Harness.assertEqual(species[1].count, 2)
  Harness.assertEqual(species[1].firstRowIndex, 1)
  Harness.assertEqual(species[2].count, 1)
  Harness.assertEqual(species[2].firstRowIndex, 3)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "EnemySpeciesTable.decode: real ROM's 46-row table decodes, 11 distinct species, live-verified ATK",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local rows = EnemySpeciesTable.decode(romData, profile.enemySpeciesTable)
    Harness.assertEqual(#rows, 46)

    -- Real, live-verified example (see rom_profiles.lua's own
    -- verifiedExample and combat.md/rom-map.md for the full trace):
    -- row 20 (1-based; 19 0-based) is the tutorial enemy this project
    -- has actually fought, ATK=8, matching the live $50AC register B.
    local example = profile.enemySpeciesTable.verifiedExample
    local row = rows[example.rowIndex + 1]
    Harness.assertEqual(row.atk, example.atk)

    -- Every real row's structurally-constant bytes stay constant --
    -- a real, cheap sanity check that the table boundary/stride is
    -- still right (would fail loudly if the ROM ever changed or the
    -- offset drifted).
    for i, r in ipairs(rows) do
      Harness.assertEqual(r.raw:byte(1), 0x00, "row " .. i .. " byte+0 should be constant 0x00")
      Harness.assertEqual(r.raw:byte(2), 0x20, "row " .. i .. " byte+1 should be constant 0x20")
      Harness.assertEqual(r.raw:byte(4), 0x00, "row " .. i .. " byte+3 should be constant 0x00")
      Harness.assertEqual(r.raw:byte(8), 0x00, "row " .. i .. " byte+7 should be constant 0x00")
    end

    -- Real, confirmed count: exactly 11 distinct species patterns
    -- across the 46 rows (see EnemySpeciesTable.lua's own doc comment
    -- for the full dump this was found from).
    local species = EnemySpeciesTable.groupBySpecies(rows)
    Harness.assertEqual(#species, 11)

    -- Real ATK values, one per distinct species (in table order) --
    -- locks in the actual byte dump, not just the count.
    local expectedAtk = { 0x8C, 0x8C, 0x21, 0x21, 0x08, 0x00, 0xBC, 0xBC, 0x4D, 0x4D, 0x79 }
    for i, s in ipairs(species) do
      Harness.assertEqual(s.row.atk, expectedAtk[i], "species " .. i .. " ATK mismatch")
    end
  end
)
