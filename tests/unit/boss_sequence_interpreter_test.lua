local Harness = require("tests.harness")
local BossSequenceInterpreter = require("src.scripting.BossSequenceInterpreter")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "BossSequenceInterpreter: starts at the real, live-verified bank 13 (not scriptPointerTable's own bank 8)",
  romData ~= nil,
  "no development ROM found",
  function()
    local bsi = BossSequenceInterpreter.new(romData, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      isTextboxDone = function() return true end,
    })
    Harness.assertEqual(bsi.bank, 13)
    Harness.assertEqual(bsi.cursor, 0x470F)
  end
)

Harness.testIfAvailable(
  "BossSequenceInterpreter: switches to the real, live-verified bank 14 on the first real CHAIN dispatch",
  romData ~= nil,
  "no development ROM found",
  function()
    local bsi = BossSequenceInterpreter.new(romData, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      isTextboxDone = function() return true end,
    })
    for _ = 1, 5000 do
      if bsi.bankSwitched or bsi.done then break end
      bsi:tick()
    end
    Harness.assertTrue(bsi.bankSwitched)
    Harness.assertEqual(bsi.bank, 14)
    -- Real, honest check: this should NOT have stopped on a genuinely
    -- undecoded opcode by the time the bank switch happens -- every
    -- opcode up to and including the first real CHAIN is already
    -- wired (see events.md's own "task #86" section).
    if bsi.runtime.stopped then
      error("BossSequenceInterpreter stopped before the real bank switch: " ..
        tostring(bsi.runtime.stopError))
    end
  end
)

Harness.testIfAvailable(
  "BossSequenceInterpreter: runs a real, bounded number of further real ticks in bank 14 without hitting a genuinely undecoded opcode",
  romData ~= nil,
  "no development ROM found",
  function()
    local bsi = BossSequenceInterpreter.new(romData, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      isTextboxDone = function() return true end,
    })
    for _ = 1, 2000 do
      bsi:tick()
      if bsi.done then break end
    end
    if bsi.runtime.stopped then
      error("BossSequenceInterpreter stopped on a real, undecoded opcode within the first 2000 ticks: " ..
        tostring(bsi.runtime.stopError))
    end
  end
)
