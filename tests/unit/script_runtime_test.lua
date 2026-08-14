local Harness = require("tests.harness")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local RomScriptStream = require("src.scripting.RomScriptStream")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

--- Same synthetic-table convention `script_interpreter_test.lua`
-- already established: 256 real-shaped entries, all DEFAULT unless
-- overridden.
local function makeOpcodeTable(overrides)
  local entries = {}
  for i = 1, 256 do
    entries[i] = ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS
  end
  for opcode, addr in pairs(overrides or {}) do
    entries[opcode + 1] = addr
  end
  return entries
end

Harness.test(
  "ScriptRuntime: a real synthetic script (tick/heal/message/skip) runs happy-path through registered handlers",
  function()
    local entries = makeOpcodeTable({
      [0x04] = ScriptOpcodeTable.TICK_HANDLER_ADDRESS,
      [0xC0] = ScriptOpcodeTable.HEAL_LP_HANDLER_ADDRESS,
      [0xFE] = ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS,
      [0x01] = ScriptOpcodeTable.SKIP_HANDLER_ADDRESS,
      -- A real-shaped but deliberately UNREGISTERED handler address --
      -- if `skip` fails to actually skip over the 3 stream slots holding
      -- this opcode, the run would stop here instead of completing
      -- cleanly, so reaching the end without stopping IS the proof.
      [0x77] = 0xDEAD,
    })
    local stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 }
    local tickCount = 0
    local receivedMessage = nil
    local runtime = ScriptRuntime.new(entries, {
      stats = stats,
      onTick = function() tickCount = tickCount + 1 end,
      onMessage = function(id) receivedMessage = id end,
    })

    -- 1:tick 2:heal 3:message(4:operand) 5:skip(6:n=3) [7,8,9: poison,
    -- skipped over] 10:tick again (the real landing spot: 7+3=10).
    local stream = { 0x04, 0xC0, 0xFE, 42, 0x01, 3, 0x77, 0x77, 0x77, 0x04 }
    runtime:run(stream, 1, 5)

    Harness.assertTrue(not runtime.stopped, "expected the run to complete without hitting the poison opcode")
    Harness.assertEqual(runtime.stepCount, 5)
    Harness.assertEqual(tickCount, 2)
    Harness.assertEqual(receivedMessage, 42)
    Harness.assertEqual(stats.curLP, stats.maxLP) -- real heal-to-max side effect
  end)

Harness.test(
  "ScriptRuntime: opcode 0x80's real dynamic group is computed live from ctx.getPlayerFacing() (task 10, $02AB cracked)",
  function()
    local entries = makeOpcodeTable({ [0x80] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80 })
    local facing = "right"
    local seenGroups = {}
    local runtime = ScriptRuntime.new(entries, {
      getPlayerFacing = function() return facing end,
      onActorAction = function(g) seenGroups[#seenGroups + 1] = g end,
    })

    local stream = { 0x80 }
    runtime:run(stream, 1, 1)
    Harness.assertEqual(seenGroups[1], 0x91) -- right = bit 0x01, + 0x90

    facing = "down"
    runtime:run(stream, 1, 1)
    Harness.assertEqual(seenGroups[2], 0x98) -- down = bit 0x08, + 0x90
  end)

Harness.test(
  "ScriptRuntime: opcode 0x80 defaults to facing 'up' (matching Player.DEFAULT_FACING) when ctx.getPlayerFacing is omitted",
  function()
    local entries = makeOpcodeTable({ [0x80] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80 })
    local seenGroup = nil
    local runtime = ScriptRuntime.new(entries, {
      onActorAction = function(g) seenGroup = g end,
    })
    runtime:run({ 0x80 }, 1, 1)
    Harness.assertEqual(seenGroup, 0x94) -- up = bit 0x04, + 0x90
  end)

Harness.test(
  "ScriptRuntime: opcode 0x80 falls back to facing 'up' (not a crash) when ctx.getPlayerFacing returns garbage",
  function()
    -- Regression test for a real, self-caught bug: a generic caller
    -- (this project's own whole-corpus scan tool) supplies a stub
    -- `ctx.getPlayerFacing` returning `true` (not a real facing
    -- string) for every unset callback -- must NOT crash, must fall
    -- back to the same honest default as when the callback is absent.
    local entries = makeOpcodeTable({ [0x80] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80 })
    local seenGroup = nil
    local runtime = ScriptRuntime.new(entries, {
      getPlayerFacing = function() return true end, -- deliberately garbage
      onActorAction = function(g) seenGroup = g end,
    })
    runtime:run({ 0x80 }, 1, 1)
    Harness.assertEqual(seenGroup, 0x94) -- same fallback as the "omitted" case
  end)

Harness.test(
  "ScriptRuntime: opcode 0x81's real dynamic group is the OPPOSITE facing | 0xB0 (2026-08-14, $02AB family continued)",
  function()
    local entries = makeOpcodeTable({ [0x81] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_81 })
    local facing = "right"
    local seenGroups = {}
    local runtime = ScriptRuntime.new(entries, {
      getPlayerFacing = function() return facing end,
      onActorAction = function(g) seenGroups[#seenGroups + 1] = g end,
    })

    local stream = { 0x81 }
    runtime:run(stream, 1, 1)
    Harness.assertEqual(seenGroups[1], 0xB2) -- opposite of right is left (bit 0x02), + 0xB0

    facing = "down"
    runtime:run(stream, 1, 1)
    Harness.assertEqual(seenGroups[2], 0xB4) -- opposite of down is up (bit 0x04), + 0xB0
  end)

Harness.test(
  "ScriptRuntime: opcode 0x81 defaults to the opposite of 'up' (i.e. 'down') when ctx.getPlayerFacing is omitted",
  function()
    local entries = makeOpcodeTable({ [0x81] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_81 })
    local seenGroup = nil
    local runtime = ScriptRuntime.new(entries, {
      onActorAction = function(g) seenGroup = g end,
    })
    runtime:run({ 0x81 }, 1, 1)
    Harness.assertEqual(seenGroup, 0xB8) -- down = bit 0x08, + 0xB0
  end)

Harness.test(
  "ScriptRuntime: opcode 0x81 falls back the same way as 0x80 (not a crash) when ctx.getPlayerFacing returns garbage",
  function()
    -- Same regression shape as 0x80's own garbage-value test above --
    -- 0x81 resolves facing through the SAME shared `resolvePlayerFacing`
    -- helper, so it inherits the same fix.
    local entries = makeOpcodeTable({ [0x81] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_81 })
    local seenGroup = nil
    local runtime = ScriptRuntime.new(entries, {
      getPlayerFacing = function() return true end, -- deliberately garbage
      onActorAction = function(g) seenGroup = g end,
    })
    runtime:run({ 0x81 }, 1, 1)
    Harness.assertEqual(seenGroup, 0xB8) -- same fallback as the "omitted" case
  end)

Harness.test(
  "ScriptRuntime:step: a real, undecoded opcode captures the failure instead of throwing -- and stays stopped",
  function()
    local entries = makeOpcodeTable({ [0x55] = 0xBEEF }) -- a real-shaped, deliberately unregistered address
    local runtime = ScriptRuntime.new(entries, {})
    local stream = { 0x55, 0x04 }

    local cursor = runtime:run(stream, 1, 10)
    Harness.assertTrue(runtime.stopped)
    Harness.assertEqual(runtime.stepCount, 0)
    Harness.assertEqual(cursor, 1) -- unchanged: the failing step never advances
    Harness.assertTrue(tostring(runtime.stopError):find("no registered Lua implementation") ~= nil,
      "expected the real ScriptInterpreter:step error message")

    -- Stepping again is a safe, permanent no-op (no re-throw) -- see
    -- ScriptRuntime:step's own doc comment.
    local cursor2 = runtime:step(stream, 1)
    Harness.assertEqual(cursor2, 1)
    Harness.assertEqual(runtime.stepCount, 0)
  end)

Harness.test("ScriptRuntime: opcode 0x02 (CHAIN) pushes a real entry onto the runtime's own queue", function()
  local entries = makeOpcodeTable({ [0x02] = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS })
  local runtime = ScriptRuntime.new(entries, {})
  local stream = { 0x02, 0x00, 0x05 } -- byte1=0, byte2=5 -> target 0x4005

  local cursorAfter = runtime:step(stream, 1)
  Harness.assertEqual(cursorAfter, 0x4005)
  Harness.assertTrue(not runtime.stopped)
  Harness.assertTrue(not runtime.queue:isEmpty())

  local shouldRedirect, resumeCursor = runtime.queue:pop()
  Harness.assertTrue(shouldRedirect)
  Harness.assertEqual(resumeCursor, 4) -- real cursor right after CHAIN's own 2 operand bytes
end)

-- --- ROM-dependent: a real live run against the REAL boss-defeat script -
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ScriptRuntime: a real run against the real boss-defeat script makes genuine forward progress",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local stream = RomScriptStream.forFileOffset(romData, spt.fileOffset)
    local runtime = ScriptRuntime.new(opcodeEntries, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      isTextboxDone = function() return true end,
    })

    runtime:run(stream, spt.verifiedExample.scriptCpuAddress, 5000)

    -- Real, honest assertion: the boss-defeat script is KNOWN (events.md,
    -- "every opcode it actually uses, decoded") to use several opcodes
    -- this project has traced but not yet given a Lua handler
    -- (0x5A/0x08/0x88/0xBF family) -- a real run should make genuine
    -- progress (not stop at step 0) and, if/when it stops, stop for
    -- exactly that documented reason, not some other failure. Written
    -- this way (not asserting a specific step count or opcode) so this
    -- test keeps passing as more real opcodes get wired over time,
    -- rather than needing to be re-pinned to a shrinking stop point.
    Harness.assertTrue(runtime.stepCount > 0,
      "expected the real interpreter to make genuine progress through the real boss-defeat script")
    if runtime.stopped then
      Harness.assertTrue(tostring(runtime.stopError):find("no registered Lua implementation") ~= nil,
        "expected a real 'undecoded opcode' stop, not some other failure: " .. tostring(runtime.stopError))
    end
  end
)
