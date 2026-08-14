local Harness = require("tests.harness")
local RomScriptStream = require("src.scripting.RomScriptStream")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

--- Builds a synthetic "ROM" byte string, `size` bytes, where byte at
-- 0-based file offset `i` has value `i % 251` -- lets tests assert exact
-- addressing without needing real ROM data. Deliberately `% 251` (a
-- prime), NOT `% 256`: a plain `i % 256` would silently make every bank
-- (each exactly `0x4000` = 16384 = 64*256 bytes, an exact multiple of
-- 256) look byte-for-byte identical to every other bank, defeating the
-- whole point of a cross-bank distinctness test below -- 251 doesn't
-- divide 16384, so offsets one whole bank apart get genuinely different
-- synthetic values.
local function syntheticRom(size)
  local bytes = {}
  for i = 0, size - 1 do
    bytes[i + 1] = string.char(i % 251)
  end
  return table.concat(bytes)
end

Harness.test("RomScriptStream.forBank: stream[cpuAddr] reads the real byte at bankFileStart + (cpuAddr - 0x4000)",
  function()
    local romData = syntheticRom(0x4000 * 3) -- 3 banks' worth
    local stream = RomScriptStream.forBank(romData, 1) -- bank 1: file 0x4000-0x7FFF
    -- CPU $4000 (bank window start) -> file offset 0x4000.
    Harness.assertEqual(stream[0x4000], 0x4000 % 251)
    -- CPU $470F (a real example address, see the boss-defeat script) ->
    -- file offset 0x470F.
    Harness.assertEqual(stream[0x470F], 0x470F % 251)
    -- CPU $7FFF (bank window end) -> file offset 0x7FFF.
    Harness.assertEqual(stream[0x7FFF], 0x7FFF % 251)
  end)

Harness.test("RomScriptStream.forBank: a different bank index shifts the real file offset by a whole bank", function()
  local romData = syntheticRom(0x4000 * 3)
  local bank1 = RomScriptStream.forBank(romData, 1)
  local bank2 = RomScriptStream.forBank(romData, 2)
  -- Same CPU address, different bank -> different real file offset, so a
  -- different real byte (since the synthetic ROM's own byte values are
  -- distinct per file offset within this range).
  Harness.assertTrue(bank1[0x4500] ~= bank2[0x4500])
  Harness.assertEqual(bank2[0x4500], (0x4500 + 0x4000) % 251)
end)

Harness.test("RomScriptStream.forBank: returns nil outside the real $4000-$7FFF bank window (not garbage)", function()
  local romData = syntheticRom(0x4000 * 2)
  local stream = RomScriptStream.forBank(romData, 0)
  Harness.assertEqual(stream[0x3FFF], nil)
  Harness.assertEqual(stream[0x8000], nil)
  Harness.assertEqual(stream["not a number"], nil)
end)

Harness.test("RomScriptStream.forFileOffset: derives the same bank forBank(floor(fileOffset/0x4000)) would", function()
  local romData = syntheticRom(0x4000 * 9)
  -- 0x2070F is bank 8's own real file region (0x2070F / 0x4000 = 8.02...).
  local byOffset = RomScriptStream.forFileOffset(romData, 0x2070F)
  local byBank = RomScriptStream.forBank(romData, 8)
  Harness.assertEqual(byOffset[0x470F], byBank[0x470F])
end)

Harness.test("RomScriptStream.forBank: fails loudly on a non-string romData or a negative bank index", function()
  Harness.assertTrue(not pcall(RomScriptStream.forBank, 12345, 0))
  Harness.assertTrue(not pcall(RomScriptStream.forBank, "abc", -1))
end)

-- --- ROM-dependent: cross-checked against the real, live-verified -----
-- boss-defeat script address (see rom_profiles.lua's scriptPointerTable
-- .verifiedExample and events.md's "A real script-pointer table FOUND").
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "RomScriptStream: the real boss-defeat script's own first byte matches a direct romData:byte() read",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable
    local stream = RomScriptStream.forFileOffset(romData, spt.fileOffset)
    local cpuAddr = spt.verifiedExample.scriptCpuAddress
    -- Real, independent cross-check: file offset 0x2070F is the
    -- already-documented real location of this exact script (see
    -- rom_profiles.lua's own doc comment on scriptPointerTable).
    local expectedFileOffset = 0x2070F
    Harness.assertEqual(stream[cpuAddr], romData:byte(expectedFileOffset + 1))
  end
)

Harness.testIfAvailable(
  "RomScriptStream.forScriptIndex: resolves the real table's own bank rollover correctly (2026-08-13 correction)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable

    -- The already-verified example (index 232, safely bank-8) -- same
    -- real byte `RomScriptStream.forFileOffset` already cross-checks
    -- above, now reached via the general per-index resolver instead.
    local stream1, cpuAddr1 = RomScriptStream.forScriptIndex(romData, spt, spt.verifiedExample.index)
    Harness.assertEqual(cpuAddr1, spt.verifiedExample.scriptCpuAddress)
    Harness.assertEqual(stream1[cpuAddr1], romData:byte(0x2070F + 1))

    -- Real table index 667: rolls into bank 9 -- this only reads the
    -- real, correct byte if `.forScriptIndex` actually built the stream
    -- against the RESOLVED bank (9), not the table's own base bank (8).
    local stream2, cpuAddr2 = RomScriptStream.forScriptIndex(romData, spt, 667)
    Harness.assertEqual(cpuAddr2, 0x403C)
    Harness.assertEqual(stream2[cpuAddr2], 0x19)

    -- A real 0xFFFF filler entry: `nil, "filler"`, not a fabricated
    -- stream. No such entry exists WITHIN the real table's own declared
    -- `recordCount` (per rom_profiles.lua's own doc comment: filler
    -- only starts AFTER it) -- exercised against a small synthetic
    -- table instead (the real-ROM cases above already cover the
    -- resolved-address path this function layers on top of).
    local fillerRom = string.char(0xFF, 0xFF)
    local fillerSpt = { fileOffset = 0, recordCount = 1, cpuBankOffsetBase = 0x4000 }
    local fillerStream, err = RomScriptStream.forScriptIndex(fillerRom, fillerSpt, 0)
    Harness.assertEqual(fillerStream, nil)
    Harness.assertEqual(err, "filler")
  end
)
