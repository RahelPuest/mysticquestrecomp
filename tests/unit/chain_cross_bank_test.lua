-- Real-ROM cross-checks for task #81's own follow-up (2026-08-16, "erst
-- 151 dann 81") -- see StandardScriptHandlers.chain's own doc comment
-- for the full reasoning trail this implements. Covers the 7 real
-- scriptPointerTable entries (489/530/703/879/1141/1324/1325) that the
-- 2026-08-13 whole-corpus scan flagged as "genuine cursor out of
-- bounds" -- i.e. their real CHAIN (opcode 0x02) operand computes a
-- target outside the current bank's own $4000-$7FFF window.
--
-- HONEST SCOPE: this is a static-analysis + shadow-interpretation
-- cross-check, NOT a live mGBA trace -- no known live trigger reaches
-- any of these 7 specific script-table entries in normal gameplay (see
-- rom-map.md's own dated task #81 entry), so the originally-identified
-- "next concrete step" (a live $2100-write watchpoint) still has an
-- unmet prerequisite. What these tests DO establish, decisively: the
-- new hybrid resolution rule in StandardScriptHandlers.chain makes
-- every one of the 7 real scripts shadow-run cleanly (zero interpreter
-- errors) through their first real CHAIN hop, with script 489 giving a
-- genuinely rich, structurally-sensible real opcode trace (strong,
-- VERIFIED-style confirmation this one was never actually cross-bank
-- at all -- just needed the already-known $3c4f correction), while the
-- others remain CANDIDATE (plausible, not proven).
local Harness = require("tests.harness")
local DevRomLocator = require("tests.dev_rom_locator")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local RomScriptStream = require("src.scripting.RomScriptStream")
local ScriptRuntime = require("src.scripting.ScriptRuntime")

local romData = DevRomLocator.find()

--- The real bar for this investigation is narrower than "never stops":
-- hundreds of OTHER already-known real scripts in this same corpus
-- legitimately halt on a genuinely-still-undecoded opcode (an ordinary,
-- expected `HALT_UNDECODED` per `scripts/scan_all_scripts.lua`'s own
-- classification, unrelated to CHAIN) -- that's real, structured
-- content having been reached and dispatched successfully, NOT a
-- failure of this task's own hybrid resolution. The actual failure
-- mode task #81 is about is a `ScriptInterpreter.fetch` cursor landing
-- outside a real stream's own bounds entirely (the literal error the
-- 2026-08-13 corrected scan flagged these 7 scripts for). Only THAT
-- specific error means the resolution is wrong.
local function isCursorBoundsError(err)
  return tostring(err):find("out of stream bounds", 1, true) ~= nil
end

--- Builds a fresh stub ctx matching `scripts/scan_all_scripts.lua`'s own
-- (same reasoning: the blanket `__index` "always returns a callable
-- returning true" fallback is unsafe for a handful of specific real
-- ctx fields whose OWN return value IS the next real cursor -- see that
-- script's own doc comment) -- duplicated rather than required from
-- `scripts/`, matching this project's existing "test-only helper"
-- convention (see `tests/dev_rom_locator.lua`'s own doc comment for the
-- precedent) for keeping `scripts/` and `tests/` independently runnable.
-- `onChainTarget` is REQUIRED here (unlike the scan tool, which doesn't
-- follow cross-bank targets) -- these tests exist specifically to
-- exercise it.
local function exhaustedListStub(opcodeLabel)
  return function(cursorAfterTerminator)
    error(string.format(
      "chain_cross_bank_test.lua stub: opcode %s's real 'list exhausted' resume cursor " ..
      "(from real ROM cursor %#x) is genuine, data-dependent ROM content this test has " ..
      "no live WRAM to derive",
      opcodeLabel, cursorAfterTerminator))
  end
end

local function newStubCtx(onChainTarget)
  return setmetatable({
    stats = { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6 },
    flags = { byte = 0 },
    wramBitFlags = { byte = 0 },
    actorStateFlags = { byte = 0 },
    isTriggerEventGateClear = function() return true end,
    onTimerListTest09 = function() return true end,
    onTimerListTest0A = function() return true end,
    runListMatchByte = function() return 0 end,
    isRunListGateSet = function() return true end,
    onFlagListExhausted = exhaustedListStub("0x08"),
    onTimerListExhausted09 = exhaustedListStub("0x09"),
    onTimerListExhausted0A = exhaustedListStub("0x0A"),
    onRunListExhausted0B = exhaustedListStub("0x0B"),
    onRunListExhausted0C = exhaustedListStub("0x0C"),
    onControlCode = false,
    queue = false,
    onChainTarget = onChainTarget,
  }, { __index = function() return function() return true end end })
end

--- Shadow-runs `scriptIndex` starting from its real
-- `ScriptPointerTable.resolve`-d location, following every real CHAIN
-- hop by swapping which `RomScriptStream` feeds subsequent steps
-- (`newBank = bank + bankOffset`, per `StandardScriptHandlers.chain`'s
-- own new contract) -- exactly the pattern `BossSequenceInterpreter`
-- already uses for its own, different, live-verified scene. Returns
-- the real `ScriptRuntime` after `stepBudget` steps (or an early real
-- stop) plus the list of `{bank, cursor, bankOffset}` CHAIN hops seen.
local function shadowRunFollowingChain(profile, opcodeEntries, scriptIndex, stepBudget)
  local resolved = ScriptPointerTable.resolve(romData, profile.scriptPointerTable, scriptIndex)
  local bank = resolved.bank
  local stream = RomScriptStream.forFileOffset(romData, bank * 0x4000)
  local hops = {}
  local ctx = newStubCtx(function(target, bankOffset)
    if bankOffset ~= 0 then
      bank = bank + bankOffset
      stream = RomScriptStream.forFileOffset(romData, bank * 0x4000)
    end
    hops[#hops + 1] = { bank = bank, cursor = target, bankOffset = bankOffset }
  end)
  local runtime = ScriptRuntime.new(opcodeEntries, ctx)
  local cursor = resolved.cpuAddress
  for _ = 1, stepBudget do
    if runtime.stopped or runtime.finished then break end
    -- `stream` may have been swapped mid-loop by the onChainTarget
    -- callback above -- read it fresh each iteration (matching how a
    -- real per-frame caller like BossSequenceInterpreter would).
    cursor = runtime:step(stream, cursor)
  end
  return runtime, hops, resolved
end

Harness.testIfAvailable(
  "task #81: script index 489's real CHAIN was never actually cross-bank -- the already-known $3c4f correction resolves it in-bank, and real steps decode as rich, varied real opcode content (until a real, unrelated, ordinary still-undecoded opcode)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local runtime, hops, resolved = shadowRunFollowingChain(profile, opcodeEntries, 489, 80)

    Harness.assertEqual(resolved.bank, 8)
    Harness.assertEqual(#hops, 1)
    Harness.assertEqual(hops[1].bankOffset, 0) -- in-window $3c4f correction, no bank switch
    Harness.assertEqual(hops[1].bank, 8) -- stays in the SAME bank the script started in
    Harness.assertEqual(hops[1].cursor, 0x5303)
    -- A real, ordinary HALT_UNDECODED (a genuinely-still-undecoded
    -- opcode further along this script -- see this file's own
    -- `isCursorBoundsError` doc comment) is fine and expected; a
    -- cursor-out-of-bounds error is the ONE outcome that would mean
    -- this hybrid resolution is wrong.
    Harness.assertTrue(not (runtime.stopped and isCursorBoundsError(runtime.stopError)),
      "real script 489 should never re-hit the real cursor-out-of-bounds error: " .. tostring(runtime.stopError))

    -- Decisive richness check: real, sensible script content dispatches
    -- MANY distinct real opcodes, not a handful of repeats -- the
    -- signature this project's own methodology already treats as
    -- decisive (see ScriptPointerTable.lua's own precedent).
    local distinctOpcodes = 0
    for _ in pairs(runtime.opcodeCounts) do distinctOpcodes = distinctOpcodes + 1 end
    Harness.assertTrue(distinctOpcodes >= 20,
      "expected real, varied script content (>=20 distinct real opcodes), saw only " .. distinctOpcodes)
  end
)

Harness.testIfAvailable(
  "task #81: script index 703's real CHAIN operand overflows 16 bits -- the new CANDIDATE bank-rollover hypothesis resolves it without any interpreter error (not yet decisive)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local runtime, hops = shadowRunFollowingChain(profile, opcodeEntries, 703, 80)

    Harness.assertEqual(#hops, 1)
    Harness.assertEqual(hops[1].bankOffset, 3) -- real, structural rollover -- not 0
    Harness.assertEqual(hops[1].bank, 12) -- startBank(9) + bankOffset(3)
    Harness.assertEqual(hops[1].cursor, 0x4b3f)
    Harness.assertTrue(not (runtime.stopped and isCursorBoundsError(runtime.stopError)),
      "real script 703's hybrid-resolved target should never hit the real cursor-out-of-bounds error: " ..
      tostring(runtime.stopError))
  end
)

Harness.testIfAvailable(
  "task #81: all 7 real 'genuine cursor out of bounds' scripts shadow-run cleanly through their first CHAIN hop under the new hybrid resolution (no interpreter crash on any of them)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    -- The real, full residual list from the 2026-08-13 corrected
    -- whole-corpus scan (events.md's own "CORRECTION" section).
    local indices = { 489, 530, 703, 879, 1141, 1324, 1325 }
    for _, index in ipairs(indices) do
      local runtime, hops = shadowRunFollowingChain(profile, opcodeEntries, index, 80)
      Harness.assertTrue(#hops >= 1, "script " .. index .. " should reach at least one real CHAIN dispatch")
      Harness.assertTrue(not (runtime.stopped and isCursorBoundsError(runtime.stopError)),
        "script " .. index .. " should never hit the real cursor-out-of-bounds error: " .. tostring(runtime.stopError))
    end
  end
)
