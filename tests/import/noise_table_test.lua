local Harness = require("tests.harness")
local NoiseTable = require("src.import.NoiseTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("NoiseTable.decode: parses a synthetic 4-byte table", function()
  local rom = "\1\2\3\4"
  local noiseTable = { fileOffset = 0, length = 4 }
  local bytes = NoiseTable.decode(rom, noiseTable)
  Harness.assertEqual(#bytes, 4)
  Harness.assertEqual(bytes[1], 1)
  Harness.assertEqual(bytes[4], 4)
end)

Harness.test("NoiseTable.decode: fails loudly when the ROM is shorter than the declared table", function()
  local rom = "\1\2"
  local noiseTable = { fileOffset = 0, length = 4 }
  local ok = pcall(NoiseTable.decode, rom, noiseTable)
  Harness.assertTrue(not ok, "expected NoiseTable.decode to raise on a truncated table")
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "NoiseTable.decode: real ROM's 256-byte table decodes and looks noise-shaped, not structured",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local bytes = NoiseTable.decode(romData, profile.noiseTable)
    Harness.assertEqual(#bytes, 256)
    for i = 1, 256 do
      Harness.assertTrue(bytes[i] >= 0 and bytes[i] <= 255, "byte " .. i .. " out of 0-255 range")
    end
    -- Real, informal "does this look like noise, not a repeated
    -- pattern" check: at least some real variety among the first 16
    -- bytes (a genuinely structured/blank table would fail this).
    local distinct = {}
    for i = 1, 16 do
      distinct[bytes[i]] = true
    end
    local count = 0
    for _ in pairs(distinct) do
      count = count + 1
    end
    Harness.assertTrue(count > 4, "expected real variety in the first 16 noise-table bytes, got " .. count .. " distinct values")
  end
)
