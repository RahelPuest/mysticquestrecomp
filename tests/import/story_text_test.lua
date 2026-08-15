-- Byte-exact regression tests for rom_profiles.lua's new `storyText`
-- census (2026-08-15, direct user request "suchen alle monster und
-- npcs mit allen daten, texten und grafiken aus dem rom") -- locks in
-- every real `bossDefeats` file offset against the real ROM so a
-- future edit can't silently drift from the actual bytes.

local Harness = require("tests.harness")
local TextDecoder = require("src.import.TextDecoder")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "storyText.bossDefeats: every entry's real fileOffset decodes to its own claimed message",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local bossDefeats = profile.storyText.bossDefeats
    Harness.assertEqual(#bossDefeats, 8)
    for _, entry in ipairs(bossDefeats) do
      local decoded = TextDecoder.decodeString(romData, entry.fileOffset)
      Harness.assertTrue(
        decoded:find(entry.message, 1, true) ~= nil,
        entry.name .. ": expected to find " .. entry.message .. " in decoded text " .. decoded)
    end
  end
)

Harness.testIfAvailable(
  "storyText.namedCharacters: real, honestly-scoped census (2 positioned, rest text-only)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local named = profile.storyText.namedCharacters
    Harness.assertTrue(#named >= 15)

    local positioned = 0
    for _, c in ipairs(named) do
      Harness.assertTrue(c.name ~= nil and c.name ~= "")
      Harness.assertTrue(c.occurrences ~= nil and c.occurrences > 0)
      Harness.assertTrue(c.positionKnown == true or c.positionKnown == false)
      if c.positionKnown then positioned = positioned + 1 end
    end
    -- Willy and Amanda are the only 2 with a real, live-verified
    -- room/sprite -- every other name is text-only, honestly flagged.
    Harness.assertEqual(positioned, 2)
  end
)

if romData then
  print("(StoryText ROM-dependent tests ran against a real dev ROM)")
end
