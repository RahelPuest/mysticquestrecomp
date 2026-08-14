local Harness = require("tests.harness")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

--- Builds a synthetic "scriptPointerTable"-shaped byte string: `count`
-- little-endian 16-bit entries starting at file offset 0, plus a real
-- `spt` profile table pointing at it. `entries[i]` (1-based) is the raw
-- `tableValue` for 0-based table index `i-1`.
local function syntheticTable(entries)
  local bytes = {}
  for _, v in ipairs(entries) do
    table.insert(bytes, string.char(v % 256))
    table.insert(bytes, string.char(math.floor(v / 256) % 256))
  end
  local romData = table.concat(bytes)
  local spt = { fileOffset = 0, recordCount = #entries, cpuBankOffsetBase = 0x4000 }
  return romData, spt
end

Harness.test("ScriptPointerTable.resolve: a small tableValue stays in the table's own base bank", function()
  -- fileOffset=0 -> baseBank=0. tableValue=0x070F (well under 0x4000) ->
  -- no bank rollover, matching the real, VERIFIED boss-defeat-script
  -- shape (base bank 8, tableValue 0x070F -> cpuAddress 0x470F).
  local romData, spt = syntheticTable({ 0x070F })
  local resolved = ScriptPointerTable.resolve(romData, spt, 0)
  Harness.assertEqual(resolved.bank, 0)
  Harness.assertEqual(resolved.cpuAddress, 0x470F)
  Harness.assertEqual(resolved.fileOffset, 0x070F)
  Harness.assertEqual(resolved.tableValue, 0x070F)
end)

Harness.test("ScriptPointerTable.resolve: a tableValue >= 0x4000 rolls into the NEXT bank (real, confirmed encoding)", function()
  -- The real, structural finding this module exists to encode: past
  -- one bank's own 16KB span, the raw tableValue keeps counting instead
  -- of wrapping -- real bank = baseBank + floor(tableValue/0x4000).
  local romData, spt = syntheticTable({ 0x4000, 0x403C, 0x8005 })
  local a = ScriptPointerTable.resolve(romData, spt, 0)
  Harness.assertEqual(a.bank, 1) -- baseBank(0) + floor(0x4000/0x4000)=1
  Harness.assertEqual(a.cpuAddress, 0x4000)

  local b = ScriptPointerTable.resolve(romData, spt, 1)
  Harness.assertEqual(b.bank, 1)
  Harness.assertEqual(b.cpuAddress, 0x403C)

  local c = ScriptPointerTable.resolve(romData, spt, 2)
  Harness.assertEqual(c.bank, 2) -- floor(0x8005/0x4000) = 2
  Harness.assertEqual(c.cpuAddress, 0x4005)
end)

Harness.test("ScriptPointerTable.resolve: a real 0xFFFF filler entry returns nil, 'filler' (not a fabricated address)", function()
  local romData, spt = syntheticTable({ 0x070F, 0xFFFF })
  local resolved, err = ScriptPointerTable.resolve(romData, spt, 1)
  Harness.assertEqual(resolved, nil)
  Harness.assertEqual(err, "filler")
end)

Harness.test("ScriptPointerTable.resolve: fails loudly on an out-of-range index", function()
  local romData, spt = syntheticTable({ 0x070F })
  Harness.assertTrue(not pcall(ScriptPointerTable.resolve, romData, spt, 1))
  Harness.assertTrue(not pcall(ScriptPointerTable.resolve, romData, spt, -1))
end)

-- --- ROM-dependent: cross-checks against the real, live-verified -----
-- boss-defeat script AND the real, structurally-confirmed bank rollover
-- (2026-08-13, see events.md's "CORRECTION" section for the full trail:
-- table index 667's first byte decodes as opcode 0x19 -> handler
-- $12AE, an exact, already-known real handler -- decisive evidence this
-- is the ROM's own real encoding, not a misreading).
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ScriptPointerTable.resolve: matches the real, VERIFIED boss-defeat script exactly (index 232)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local spt = profile.scriptPointerTable
    local resolved = ScriptPointerTable.resolve(romData, spt, spt.verifiedExample.index)
    Harness.assertEqual(resolved.bank, 8)
    Harness.assertEqual(resolved.cpuAddress, spt.verifiedExample.scriptCpuAddress)
    Harness.assertEqual(resolved.fileOffset, 0x2070F)
  end
)

Harness.testIfAvailable(
  "ScriptPointerTable.resolve: real table index 667 rolls into bank 9 and decodes as a real, already-known opcode",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local spt = profile.scriptPointerTable
    local resolved = ScriptPointerTable.resolve(romData, spt, 667)
    Harness.assertEqual(resolved.bank, 9)
    Harness.assertEqual(resolved.tableValue, 0x403C)
    Harness.assertEqual(resolved.cpuAddress, 0x403C)
    -- Decisive real-content confirmation: the first byte at this
    -- resolved location is a genuine, sensible opcode (0x19), not noise.
    local firstByte = romData:byte(resolved.fileOffset + 1)
    Harness.assertEqual(firstByte, 0x19)
  end
)

Harness.testIfAvailable(
  "ScriptPointerTable.resolve: real table index 665/666 straddle the exact real bank-rollover boundary",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local spt = profile.scriptPointerTable
    local before = ScriptPointerTable.resolve(romData, spt, 665)
    local at = ScriptPointerTable.resolve(romData, spt, 666)
    Harness.assertEqual(before.bank, 8)
    Harness.assertEqual(at.bank, 9)
    Harness.assertEqual(at.tableValue, 0x4000)
    Harness.assertEqual(at.cpuAddress, 0x4000)
  end
)
