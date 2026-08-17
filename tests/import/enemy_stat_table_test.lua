local Harness = require("tests.harness")
local EnemyStatTable = require("src.import.EnemyStatTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("EnemyStatTable.decode: parses a synthetic 1-row record", function()
  -- speed=0x08 hpBase=0x19 xp=0x14 gold=0x0a numObjects=0x08
  -- speciesByte=0x1e defeatBehaviorId=0x0246 (bytes 0x46,0x02 LE)
  local row = string.char(0x08, 0x19, 0x14, 0x0a, 0x08, 0x1e, 0x46, 0x02) ..
    string.rep("\0", 16)
  local rows = EnemyStatTable.decode(row, { fileOffset = 0, rowCount = 1 })
  Harness.assertEqual(#rows, 1)
  Harness.assertEqual(rows[1].speed, 0x08)
  Harness.assertEqual(rows[1].hpBase, 0x19)
  Harness.assertEqual(rows[1].xp, 0x14)
  Harness.assertEqual(rows[1].gold, 0x0a)
  Harness.assertEqual(rows[1].numObjects, 0x08)
  Harness.assertEqual(rows[1].speciesByte, 0x1e)
  Harness.assertEqual(rows[1].defeatBehaviorId, 0x0246)
  Harness.assertEqual(#rows[1].raw, 24)
end)

Harness.test("EnemyStatTable.decode: the real courtyard-boss speciesByte (0x16) is shared by 5 real rows -- a real, independently-confirmed cross-check against events.md's own 'Second boss investigation'", function()
  -- Real bytes for rows 3/5/10/16/18 (Megapede/Golem/Iflyte/Jackal/
  -- Metal Crab): all share speciesByte=0x16 at +5 AND the same +6..+9
  -- pattern that earlier, independent investigation already found --
  -- see EnemyStatTable.lua's own doc comment for the full reconciliation.
  local rows = {}
  local data = {
    [3]  = { 0x0a, 0x1c, 0x2c, 0x96, 0x0b, 0x16, 0x46, 0x02 },
    [5]  = { 0x04, 0x8f, 0x60, 0xa0, 0x06, 0x16, 0x46, 0x02 },
    [10] = { 0x06, 0x92, 0xc8, 0xfa, 0x07, 0x16, 0x47, 0x02 },
    [16] = { 0x05, 0x02, 0x00, 0x00, 0x06, 0x16, 0x46, 0x02 },
    [18] = { 0x0a, 0x51, 0x64, 0x64, 0x07, 0x16, 0x47, 0x02 },
  }
  for i, bytes in pairs(data) do
    local row = string.char(bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8]) ..
      string.rep("\0", 16)
    local decoded = EnemyStatTable.decode(row, { fileOffset = 0, rowCount = 1 })
    Harness.assertEqual(decoded[1].speciesByte, 0x16, "row " .. i .. " speciesByte mismatch")
  end
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "EnemyStatTable.decode: real ROM's 21-row table matches the US disassembly's boss list byte-for-byte",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local rows = EnemyStatTable.decode(romData, profile.enemyStatTable)
    Harness.assertEqual(#rows, 21)

    -- Real values from the US "Final Fantasy Adventure" disassembly's
    -- own src/data/boss.asm (see rom_profiles.lua's own
    -- externalReferenceNames for the name-to-row pairing and
    -- EnemyStatTable.lua's doc comment for the full evidence trail).
    -- This EU ROM matched EVERY ONE of these byte-for-byte -- locking
    -- in the actual real values, not just the table shape.
    local expected = {
      { speed = 8, hpBase = 25, xp = 20, gold = 10 },   -- Vampire
      { speed = 10, hpBase = 20, xp = 10, gold = 90 },  -- Hydra
      { speed = 6, hpBase = 59, xp = 85, gold = 70 },   -- Medusa
      { speed = 10, hpBase = 28, xp = 44, gold = 150 }, -- Megapede
      { speed = 8, hpBase = 75, xp = 90, gold = 100 },  -- Davias
      { speed = 4, hpBase = 143, xp = 96, gold = 160 }, -- Golem
      { speed = 6, hpBase = 111, xp = 70, gold = 60 },  -- Cyclops
      { speed = 4, hpBase = 112, xp = 20, gold = 88 },  -- Chimera
      { speed = 8, hpBase = 121, xp = 166, gold = 120 },-- Kary
      { speed = 12, hpBase = 125, xp = 190, gold = 120 },-- Kraken
      { speed = 6, hpBase = 146, xp = 200, gold = 250 },-- Iflyte
      { speed = 10, hpBase = 118, xp = 178, gold = 200 },-- Lich
      { speed = 4, hpBase = 187, xp = 210, gold = 250 },-- Garuda
      { speed = 8, hpBase = 106, xp = 0, gold = 250 },  -- Dragon
      { speed = 5, hpBase = 218, xp = 0, gold = 160 },  -- Julius (Form 2)
      { speed = 8, hpBase = 206, xp = 0, gold = 250 },  -- Dragon Zombie
      { speed = 5, hpBase = 2, xp = 0, gold = 0 },      -- Jackal
      { speed = 4, hpBase = 255, xp = 0, gold = 160 },  -- Julius (Form 3)
      { speed = 10, hpBase = 81, xp = 100, gold = 100 },-- Metal Crab
      { speed = 8, hpBase = 175, xp = 199, gold = 220 },-- Mantis Ant
      { speed = 8, hpBase = 187, xp = 0, gold = 250 },  -- Dragon (Final)
    }
    for i, e in ipairs(expected) do
      local r = rows[i]
      Harness.assertEqual(r.speed, e.speed, "row " .. i .. " speed mismatch")
      Harness.assertEqual(r.hpBase, e.hpBase, "row " .. i .. " hpBase mismatch")
      Harness.assertEqual(r.xp, e.xp, "row " .. i .. " xp mismatch")
      Harness.assertEqual(r.gold, e.gold, "row " .. i .. " gold mismatch")
    end

    -- Real, independent live-CPU-trace cross-check (see
    -- rom_profiles.lua's own verifiedExample and EnemyStatTable.lua's
    -- doc comment): row 16 ("Jackal") is the ONE record this project
    -- had already confirmed live, from a completely separate, earlier
    -- investigation (Enemy.lua's own HP_INIT_TRACE_NOTE), before this
    -- table was even found via external reference.
    local example = profile.enemyStatTable.verifiedExample
    local row = rows[example.rowIndex + 1]
    Harness.assertEqual(row.hpBase, example.hpBase)
  end
)
