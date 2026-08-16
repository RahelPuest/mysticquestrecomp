local Harness = require("tests.harness")
local DialogueTextResolver = require("src.import.DialogueTextResolver")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("DialogueTextResolver.resolve: plain literal segments concatenate", function()
  local text = DialogueTextResolver.resolve("unused", { { literal = "HELD" }, { literal = " ist da" } })
  Harness.assertEqual(text, "HELD ist da")
end)

Harness.test("DialogueTextResolver.decodeRange: fails loudly on a byte that doesn't decode", function()
  -- 0x0F is a real, unassigned digraph byte (see TextDecoder.lua) --
  -- a real, honest failure, not a guess.
  local rom = string.char(0xB0, 0x0F) -- MAIN_GLYPHS[0] then an undecoded byte
  local ok = pcall(DialogueTextResolver.decodeRange, rom, 0, 2)
  Harness.assertTrue(not ok, "expected decodeRange to fail loudly on an undecodable byte")
end)

Harness.test("DialogueTextResolver.resolve: fails loudly on a segment with neither literal nor a real range", function()
  local ok = pcall(DialogueTextResolver.resolve, "unused", { {} })
  Harness.assertTrue(not ok, "expected resolve to fail loudly on a malformed segment")
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "DialogueTextResolver: real secondRoom NPC dialogue resolves from live ROM bytes, byte-exact match to the hand-transcribed lines (task: 'komplett autark interpretiert')",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local scene = profile.graphics.secondRoom.scene

    -- characterA: a single, cleanly-decodable real ROM range, zero
    -- digraph exceptions needed.
    local charA = DialogueTextResolver.resolvePages(romData, scene.characterA.dialogueSegments)
    Harness.assertEqual(#charA, #scene.characterA.dialogue)
    for i, expected in ipairs(scene.characterA.dialogue) do
      Harness.assertEqual(charA[i], expected)
    end

    -- characterB (Amanda): 3 pages, 2 of which need a real, documented
    -- per-occurrence digraph override (0x5B->"us", 0x82->"me").
    local charB = DialogueTextResolver.resolvePages(romData, scene.characterB.dialogueSegments)
    Harness.assertEqual(#charB, #scene.characterB.dialogue)
    for i, expected in ipairs(scene.characterB.dialogue) do
      Harness.assertEqual(charB[i], expected)
    end
  end
)

Harness.testIfAvailable(
  "DialogueTextResolver: victoryLine's own real ROM segments resolve correctly (formula proven, even though nothing renders it live yet)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local data = profile.graphics.victorySequence
    Harness.assertTrue(data.victoryLineSegments ~= nil, "expected victoryLineSegments on the profile")

    local heroName = "HELD"
    local segments = {}
    for i, seg in ipairs(data.victoryLineSegments) do
      if seg.literal == "%HERO_NAME%" then
        segments[i] = { literal = heroName }
      else
        segments[i] = seg
      end
    end
    local resolved = DialogueTextResolver.resolve(romData, segments)
    Harness.assertEqual(resolved, data.victoryLine:gsub("%%s", heroName):gsub("Kaempfer", "Kämpfer"))
  end
)

return true
