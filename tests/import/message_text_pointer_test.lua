local Harness = require("tests.harness")
local MessageTextPointer = require("src.import.MessageTextPointer")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "MessageTextPointer.resolveText: real messageID 13 resolves to 'gefunden' (2026-08-13, extracted for the interpreter's own onMessage wiring)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local text = MessageTextPointer.resolveText(romData, profile.messageTextPointer, 13)
    Harness.assertEqual(text, "gefunden")
  end
)

Harness.testIfAvailable(
  "MessageTextPointer.resolveText: fails loudly on a missing profile field",
  romData ~= nil,
  "no development ROM found",
  function()
    Harness.assertTrue(not pcall(MessageTextPointer.resolveText, romData, {}, 13))
  end
)
