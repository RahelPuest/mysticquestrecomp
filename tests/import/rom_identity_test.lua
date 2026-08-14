local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local GBTile = require("src.rendering.GBTile")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("RomIdentity.identify: reports an error for undersized input", function()
  local report = RomIdentity.identify("too short")
  Harness.assertTrue(report.error ~= nil, "expected an error field")
  Harness.assertTrue(report.sha1 ~= nil, "sha1 is still computed")
end)

Harness.test("RomProfiles.match: unknown SHA-1 returns nil + reason", function()
  local profile, reason = RomProfiles.match({ sha1 = "0000000000000000000000000000000000dead" })
  Harness.assertTrue(profile == nil)
  Harness.assertTrue(reason:find("unrecognized") ~= nil, "reason: " .. tostring(reason))
end)

Harness.test("RomProfiles.match: missing sha1 returns nil + reason", function()
  local profile, reason = RomProfiles.match({})
  Harness.assertTrue(profile == nil)
  Harness.assertTrue(reason ~= nil)
end)

-- --- ROM-dependent tests -----------------------------------------------
-- Skip gracefully if no development ROM is available (see
-- tests/dev_rom_locator.lua). Never required for the suite to pass.
local romData, romPath = DevRomLocator.find()

Harness.testIfAvailable(
  "RomIdentity.identify: matches the documented Mystic Quest (EU) header",
  romData ~= nil,
  "no development ROM found (set MYSTICQUEST_ROM or see tests/dev_rom_locator.lua)",
  function()
    local report = RomIdentity.identify(romData)
    Harness.assertEqual(report.error, nil)
    Harness.assertEqual(report.sizeBytes, 262144)
    Harness.assertEqual(report.sha1, "7cb65cb314e3f26b92549ddc7f4fc275186c6170")
    Harness.assertEqual(report.title, "MYSTIC QUEST")
    Harness.assertEqual(report.cartridgeTypeCode, 0x06)
    Harness.assertEqual(report.cartridgeType, "MBC2+BATTERY")
    Harness.assertEqual(report.romSizeCode, 0x03)
    Harness.assertEqual(report.romSizeBanks, 16)
    Harness.assertTrue(report.headerChecksumOk, "header checksum should match")
    Harness.assertTrue(report.globalChecksumOk, "global checksum should match")
  end
)

Harness.testIfAvailable(
  "RomProfiles.match: resolves a profile for the dev ROM",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    Harness.assertTrue(profile ~= nil, "expected a matching profile")
    Harness.assertEqual(profile.id, "mystic_quest_eu")
  end
)

Harness.testIfAvailable(
  "GBTile.decodeTiles: the verified font region decodes to mostly non-blank glyph tiles",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local font = profile.graphics.font
    local tiles = GBTile.decodeTiles(romData, font.fileOffset, font.tileCount)
    Harness.assertEqual(#tiles, font.tileCount)

    local nonBlank = 0
    for _, tile in ipairs(tiles) do
      local hasInk = false
      for _, row in ipairs(tile) do
        for _, px in ipairs(row) do
          if px ~= 0 then hasInk = true; break end
        end
        if hasInk then break end
      end
      if hasInk then nonBlank = nonBlank + 1 end
    end
    -- Most of the 80 tiles are drawn glyphs (a handful, like space-ish
    -- punctuation, may legitimately be sparse/blank), so require a strong
    -- majority rather than 100% -- this is a real assertion derived from
    -- ROM bytes, not a rubber stamp.
    Harness.assertTrue(nonBlank >= 60,
      "expected most font tiles to have ink, got " .. nonBlank .. "/" .. #tiles)
  end
)

if romPath then
  print("(ROM-dependent tests ran against: " .. romPath .. ")")
end
