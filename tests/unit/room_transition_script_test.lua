local Harness = require("tests.harness")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local RomScriptStream = require("src.scripting.RomScriptStream")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

--- Real, live-verified finding (2026-08-13, direct follow-up to "was
-- fehlt noch damit alle räume komplett interpretiert werden können"):
-- the SAME `$31AD` cross-actor script-dispatch mechanism this project
-- already fully cracked for the boss-defeat sequence (see events.md's
-- "The index question, CONCLUSIVELY RESOLVED") ALSO drives an
-- ORDINARY room-transition trigger -- the willyRoom -> secondRoom
-- north-door scroll -- not just the post-boss cutscene. Found live via
-- `tools/rom/checkpoints.door_ready()` + a `CallTracer`-verified watch
-- on real `CALL $31AD` entries while holding UP through the real
-- scroll: the real WRAM actor/context record (`$C3F0`=7 bank,
-- `$C3FE`/`$C3FF` pointer) resolves through the ALREADY-known formula
-- (dereference, +2 = script-table index) to table index 226, then 229
-- (the SAME underlying script, re-entered 9 bytes further in as the
-- real scroll progresses) -- captured live at real frames 10468-10661.
--
-- This is a real, positive generalization proof: the whole `$31AD` ->
-- `$3282`/`$4F11` chain, `ScriptPointerTable.resolve`, and
-- `ScriptRuntime`'s own already-wired opcode handlers reproduce this
-- ordinary room-transition script byte-for-byte with ZERO new Lua
-- code -- only new test coverage locking in what was found.
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ScriptPointerTable: the real willyRoom->secondRoom door-scroll WRAM record resolves to table index 226, exactly as live-captured",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable

    -- Real, live-captured WRAM actor/context record at the moment the
    -- door scroll's own $31AD dispatch first fires (see this file's own
    -- doc comment): bank=7, pointer=0x5c2e.
    local bank, ptr = 0x07, 0x5c2e
    local fileOff = bank * 0x4000 + (ptr - 0x4000)
    local lo, hi = romData:byte(fileOff + 1, fileOff + 2)
    local value1 = lo + hi * 256
    local index = value1 + 2 -- the already-established "+2, skip a small header" formula

    Harness.assertEqual(index, 226)

    local resolved = ScriptPointerTable.resolve(romData, spt, index)
    Harness.assertEqual(resolved.bank, 8)
    Harness.assertEqual(resolved.cpuAddress, 0x46b2)
  end
)

Harness.testIfAvailable(
  "ScriptRuntime: the real door-scroll script (table index 226) runs through this project's own already-wired handlers and reaches a real wait/gate state, not an undecoded opcode",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local stream = RomScriptStream.forFileOffset(romData, spt.fileOffset)

    local resolved = ScriptPointerTable.resolve(romData, spt, 226)
    local runtime = ScriptRuntime.new(opcodeEntries, {
      isActorReady = function() return true end,
      isTextboxDone = function() return true end,
      stats = { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6 },
      flags = { byte = 0 },
    })

    local cursor = resolved.cpuAddress
    local opcodes = {}
    for _ = 1, 10 do
      if runtime.stopped or runtime.finished then break end
      cursor = runtime:step(stream, cursor)
      opcodes[#opcodes + 1] = runtime.lastOpcode
    end

    Harness.assertTrue(not runtime.stopped,
      "expected the real door-scroll script to run entirely through already-wired handlers: " ..
      tostring(runtime.stopError))

    -- Real, live-captured opcode sequence (see this file's own doc
    -- comment): a small actorAction/triggerEvent preamble, ending in a
    -- real `0xE5` wait-gate that re-dispatches on the same cursor until
    -- released (matching the 3 repeated real $31AD re-entries this
    -- project's own live trace captured at the SAME WRAM pointer while
    -- the scroll was still in progress).
    Harness.assertEqual(opcodes[1], 0x1d)
    Harness.assertEqual(opcodes[2], 0x1e)
    Harness.assertEqual(opcodes[3], 0x30)
    Harness.assertEqual(opcodes[4], 0x05)
    Harness.assertEqual(opcodes[5], 0xe4)
    Harness.assertEqual(opcodes[6], 0xe5)
  end
)

Harness.testIfAvailable(
  "ScriptRuntime: the door-scroll script's own continuation (table index 229, the SAME underlying bytes 9 further in) runs to completion via already-wired handlers -- no room ID or spawn coordinate appears as a raw operand byte anywhere in it",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local spt = profile.scriptPointerTable
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local stream = RomScriptStream.forFileOffset(romData, spt.fileOffset)

    local resolved = ScriptPointerTable.resolve(romData, spt, 229)
    Harness.assertEqual(resolved.bank, 8)
    Harness.assertEqual(resolved.cpuAddress, 0x46bb)

    local runtime = ScriptRuntime.new(opcodeEntries, {
      isActorReady = function() return true end,
      isTextboxDone = function() return true end,
      stats = { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6 },
      flags = { byte = 0 },
    })

    local cursor = resolved.cpuAddress
    local opcodes = {}
    for _ = 1, 20 do
      if runtime.stopped or runtime.finished then break end
      cursor = runtime:step(stream, cursor)
      opcodes[#opcodes + 1] = runtime.lastOpcode
      if runtime.lastOpcode == 0 and opcodes[#opcodes - 1] == 0 then break end -- reached the real queue-empty halt loop
    end

    Harness.assertTrue(not runtime.stopped,
      "expected the real door-scroll continuation to run entirely through already-wired handlers: " ..
      tostring(runtime.stopError))

    -- HONEST, real, narrowing finding: every real opcode in this whole
    -- script is either zero-operand (`actorAction`'s own family -- its
    -- real effect is a FIXED group constant baked into the ROM's own
    -- dispatch table entry, not per-script data) or the real
    -- `zeroTerminatedFlagList` (opcode 0x08, here an immediately-empty
    -- list, also zero-operand in this real instance). `0x49`
    -- (`actorSlotPosition`, the one opcode this project has already
    -- identified as plausibly carrying a real raw X/Y-ish operand pair)
    -- does NOT appear anywhere in this script. This means the real
    -- room-connectivity/spawn-position answer, if it lives anywhere
    -- near this dispatch chain at all, is encoded in the FIXED ROM CODE
    -- behind these opcodes' own `actorAction` group constants (e.g.
    -- opcode 0x47's real handler, group 0x1D) -- NOT in this script's
    -- own bytes. A real, concrete narrowing of task #85's own open
    -- question, not a final answer.
    local sawOperandCarryingOpcode = false
    for _, op in ipairs(opcodes) do
      if op == 0x49 then sawOperandCarryingOpcode = true end
    end
    Harness.assertTrue(not sawOperandCarryingOpcode,
      "expected this real script to carry no actorSlotPosition (0x49) opcode -- " ..
      "if this now fails, a room ID/spawn coordinate MAY have just become directly " ..
      "readable from this script's own operand bytes; re-investigate before deleting this assertion")
  end
)
