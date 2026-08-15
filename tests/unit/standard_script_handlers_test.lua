local Harness = require("tests.harness")
local ScriptInterpreter = require("src.scripting.ScriptInterpreter")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local StandardScriptHandlers = require("src.scripting.StandardScriptHandlers")
local Stats = require("src.entities.Stats")

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

Harness.test("StandardScriptHandlers.message: consumes the real messageID operand byte and calls back with it", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFE] = ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS }))
  local received = nil
  interp:registerHandler(ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS,
    StandardScriptHandlers.message(function(id) received = id end))

  local stream = { 0xFE, 16, 0x99 }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(received, 16)
  Harness.assertEqual(nextCursor, 3) -- opcode + 1 operand byte consumed
end)

Harness.test("StandardScriptHandlers.healToMax: real 'restore to max' opcode sets curLP = maxLP", function()
  local heal = ScriptOpcodeTable.HEAL_LP_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x12] = heal }))
  local stats = Stats.new({ curLP = 3, maxLP = 19 })
  interp:registerHandler(heal, StandardScriptHandlers.healToMax(stats, "curLP", "maxLP"))

  local stream = { 0x12 }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(stats.curLP, 19)
  Harness.assertEqual(nextCursor, 2) -- no operand bytes, only the opcode itself

  -- Real ROM behavior: even already-full HP is safely reset to max
  -- (a plain assignment, not a conditional/clamped add).
  local nextCursor2 = interp:step(stream, 1)
  Harness.assertEqual(stats.curLP, 19)
  Harness.assertEqual(nextCursor2, 2)
end)

Harness.test("StandardScriptHandlers.healToMax: MP sibling works the same way with different fields", function()
  local heal = ScriptOpcodeTable.HEAL_MP_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x33] = heal }))
  local stats = Stats.new({ curLP = 19, maxLP = 19, curMP = 0, maxMP = 6 })
  interp:registerHandler(heal, StandardScriptHandlers.healToMax(stats, "curMP", "maxMP"))

  interp:step({ 0x33 }, 1)
  Harness.assertEqual(stats.curMP, 6)
  Harness.assertEqual(stats.curLP, 19) -- untouched
end)

Harness.test("StandardScriptHandlers.skip: real relative-skip opcode (0x01, ROM $32F3) jumps forward by the operand byte", function()
  local skip = ScriptOpcodeTable.SKIP_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x01] = skip }))
  interp:registerHandler(skip, StandardScriptHandlers.skip())

  -- opcode(1) + operand(2) + 2 skipped bytes (0xAA/0xBB, never read) + real next opcode
  local stream = { 0x01, 2, 0xAA, 0xBB, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(nextCursor, 5) -- lands exactly on the real 0xFE, not 0xAA
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.chain: real 'jump to next page' opcode (0x02, ROM $32FE) reads a real big-endian pointer + 0x4000", function()
  local chain = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x02] = chain }))
  interp:registerHandler(chain, StandardScriptHandlers.chain())

  -- Real ROM shape (CORRECTED 2026-08-12, see events.md's "Opcode
  -- 0x00, resolved" -- a fresh, careful re-disassembly found the real
  -- 2 operand bytes are read BIG-endian, plus a real, unconditional
  -- +0x4000 bank-window offset -- this project's own earlier little-
  -- endian, no-offset implementation was genuinely wrong, not just
  -- incomplete).
  local stream = { 0x02, 0x01, 0x02 } -- target = 0x01*256 + 0x02 + 0x4000 = 0x4102
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(nextCursor, 0x4102)
end)

Harness.test("StandardScriptHandlers.chain: pushes a real B==2 queue entry (resume point right after its own 2 operand bytes) when given a queue", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local chain = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x02] = chain }))
  local queue = ScriptContinuationQueue.new()
  interp:registerHandler(chain, StandardScriptHandlers.chain(queue))

  local stream = { 0x02, 0x01, 0x02 }
  interp:step(stream, 1)
  Harness.assertTrue(not queue:isEmpty())
  local shouldRedirect, resumeCursor = queue:pop()
  Harness.assertTrue(shouldRedirect)
  Harness.assertEqual(resumeCursor, 4) -- right after the opcode's own 2 operand bytes
end)

Harness.test("StandardScriptHandlers.chain: onChainTarget fires with the real computed jump target (2026-08-13, task #86)", function()
  local chain = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x02] = chain }))
  local seen
  interp:registerHandler(chain, StandardScriptHandlers.chain(nil, function(target) seen = target end))

  local stream = { 0x02, 0x01, 0x02 } -- byte1=1, byte2=2 -> 1*256+2+0x4000
  interp:step(stream, 1)
  Harness.assertEqual(seen, 1 * 256 + 2 + 0x4000)
end)

Harness.test("StandardScriptHandlers.chain: queue is optional (no queue, still jumps correctly)", function()
  local chain = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x02] = chain }))
  interp:registerHandler(chain, StandardScriptHandlers.chain())

  local nextCursor = interp:step({ 0x02, 0, 0 }, 1)
  Harness.assertEqual(nextCursor, 0x4000)
end)

Harness.test("StandardScriptHandlers.setFlagBit/clearFlagBit: real WRAM $D874 bit1 set/clear opcodes (0xDC/0xDD)", function()
  local setAddr, clearAddr = ScriptOpcodeTable.FLAG_SET_HANDLER_ADDRESS, ScriptOpcodeTable.FLAG_CLEAR_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xDC] = setAddr, [0xDD] = clearAddr }))
  local flags = { byte = 0x00 }
  interp:registerHandler(setAddr, StandardScriptHandlers.setFlagBit(flags, 1))
  interp:registerHandler(clearAddr, StandardScriptHandlers.clearFlagBit(flags, 1))

  local nextCursor = interp:step({ 0xDC }, 1)
  Harness.assertEqual(flags.byte, 0x02) -- bit 1 set
  Harness.assertEqual(nextCursor, 2) -- no operand bytes

  -- Setting an already-set bit is idempotent (real SET semantics).
  interp:step({ 0xDC }, 1)
  Harness.assertEqual(flags.byte, 0x02)

  -- Other bits are untouched by set/clear.
  flags.byte = 0x05 -- bits 0 and 2 already set
  interp:step({ 0xDC }, 1)
  Harness.assertEqual(flags.byte, 0x07) -- bit 1 added, 0/2 preserved

  interp:step({ 0xDD }, 1)
  Harness.assertEqual(flags.byte, 0x05) -- bit 1 cleared, 0/2 preserved
end)

Harness.test("StandardScriptHandlers.wramBitCommand: real WRAM $C3F1 bit0 set/clear opcodes (0xB8/0xB9), each firing its own opaque leaf callback", function()
  local setAddr, clearAddr =
    ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B8, ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xB8] = setAddr, [0xB9] = clearAddr }))
  local flags = { byte = 0x00 }
  local setLeafCalls, clearLeafCalls = 0, 0
  interp:registerHandler(setAddr,
    StandardScriptHandlers.wramBitCommand(flags, 0, true, function() setLeafCalls = setLeafCalls + 1 end))
  interp:registerHandler(clearAddr,
    StandardScriptHandlers.wramBitCommand(flags, 0, false, function() clearLeafCalls = clearLeafCalls + 1 end))

  local nextCursor = interp:step({ 0xB8 }, 1)
  Harness.assertEqual(flags.byte, 0x01) -- bit 0 set
  Harness.assertEqual(setLeafCalls, 1)
  Harness.assertEqual(nextCursor, 2) -- no operand bytes, always continues

  flags.byte = 0x07 -- bits 0-2 already set
  interp:step({ 0xB9 }, 1)
  Harness.assertEqual(flags.byte, 0x06) -- bit 0 cleared, 1/2 preserved
  Harness.assertEqual(clearLeafCalls, 1)
end)

Harness.test("StandardScriptHandlers.wramBitCommand: the onLeaf callback is optional", function()
  local addr = ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B8
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xB8] = addr }))
  local flags = { byte = 0x00 }
  interp:registerHandler(addr, StandardScriptHandlers.wramBitCommand(flags, 0, true, nil))

  interp:step({ 0xB8 }, 1)
  Harness.assertEqual(flags.byte, 0x01)
end)

Harness.test("StandardScriptHandlers.dualGateLeafCommand: real dual-WRAM-gated opcodes (0xE8/0xE9, ROM $0F5A/$0F71) halt while the gate is closed, retrying the SAME opcode without consuming bytes", function()
  local addr = ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E8
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xE8] = addr }))
  local gateClear = false
  local leafCalls = 0
  interp:registerHandler(addr,
    StandardScriptHandlers.dualGateLeafCommand(function() return gateClear end,
      function() leafCalls = leafCalls + 1 end))

  local stream = { 0xE8 }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(cursor, 1) -- real halt: cursor unchanged, re-dispatches the same opcode
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(leafCalls, 0) -- the real leaf never fires while the gate is closed

  gateClear = true
  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 2) -- no operand bytes, now continues
  Harness.assertEqual(leafCalls, 1)
end)

Harness.test("StandardScriptHandlers.dualGateLeafCommand: with no isGateClear, always continues immediately (matches the one real case this project has observed)", function()
  local addr = ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E9
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xE9] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.dualGateLeafCommand(nil, nil))

  local cursor = interp:step({ 0xE9 }, 1)
  Harness.assertEqual(cursor, 2)
end)

Harness.test("StandardScriptHandlers.dualGateLeafCommand: real opcodes 0xEA/0xEB (ROM $0F2C/$0F43), the family's own remaining East/West directions, wire to the SAME real shared gate", function()
  local addrEA = ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EA
  local addrEB = ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EB
  Harness.assertEqual(addrEA, 0x0F2C)
  Harness.assertEqual(addrEB, 0x0F43)
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xEA] = addrEA, [0xEB] = addrEB }))
  local gateClear = false
  local eaCalls, ebCalls = 0, 0
  interp:registerHandler(addrEA, StandardScriptHandlers.dualGateLeafCommand(
    function() return gateClear end, function() eaCalls = eaCalls + 1 end))
  interp:registerHandler(addrEB, StandardScriptHandlers.dualGateLeafCommand(
    function() return gateClear end, function() ebCalls = ebCalls + 1 end))

  local stream = { 0xEA, 0xEB }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted") -- gate closed: real halt, no bytes consumed
  Harness.assertEqual(eaCalls, 0)

  gateClear = true
  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 2)
  Harness.assertEqual(eaCalls, 1)

  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 3)
  Harness.assertEqual(ebCalls, 1)
end)

Harness.test("StandardScriptHandlers.timerListSearch: real opcodes 0x09/0x0A fire the timer-array side effect once, then run the list-search to a clean exit when every byte is found", function()
  local addr = ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_0A
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x0A] = addr }))
  local timerAdjustCalls = 0
  local tested = {}
  interp:registerHandler(addr, StandardScriptHandlers.timerListSearch(
    function() timerAdjustCalls = timerAdjustCalls + 1 end,
    function(byte) tested[#tested + 1] = byte; return true end, -- every byte "found"
    nil))

  -- 0x0A, then a real 2-entry list (5, 9), then the zero terminator.
  local stream = { 0x0A, 5, 9, 0, 0xFE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(timerAdjustCalls, 1) -- fires exactly once per dispatch, not per list item
  Harness.assertEqual(tested[1], 5)
  Harness.assertEqual(tested[2], 9)
  Harness.assertEqual(#tested, 2)
  -- Real, VERIFIED cursor: `$33CF` itself returns right after the
  -- consumed terminator (opcode + 2 list bytes + terminator = 4), but
  -- the OUTER `0x09`/`0x0A` wrapper has its OWN separate real `INC HL`
  -- on this exact clean-exit path (`$33CA`) -- combined, this
  -- reproduces the SAME net "+1" `zeroTerminatedFlagList` already
  -- applies for opcode `0x08` (there, baked into the shared `$338B`
  -- leaf itself instead of split across 2 real routines) -- confirmed
  -- by direct disassembly of both real wrapper bytes, not assumed.
  Harness.assertEqual(cursor, 6)
end)

Harness.test("StandardScriptHandlers.timerListSearch: a byte NOT found in the target array hits the real 'exhausted' leaf, same contract as opcode 0x08", function()
  local addr = ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_09
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x09] = addr }))
  local exhaustedAt = nil
  interp:registerHandler(addr, StandardScriptHandlers.timerListSearch(
    nil,
    function() return false end, -- not found
    function(cursorAfterTerminator) exhaustedAt = cursorAfterTerminator; return 999 end))

  local stream = { 0x09, 7, 0, 0xFE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(exhaustedAt, 4) -- cursor right after the real zero terminator
  Harness.assertEqual(cursor, 999) -- the exhausted callback's own return value wins
end)

Harness.test("StandardScriptHandlers.timerListSearch: immediately-empty list still fires the timer adjust, then continues via the same extra INC-HL skip as opcode 0x08", function()
  local addr = ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_09
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x09] = addr }))
  local timerAdjustCalls = 0
  interp:registerHandler(addr, StandardScriptHandlers.timerListSearch(
    function() timerAdjustCalls = timerAdjustCalls + 1 end, nil, nil))

  local stream = { 0x09, 0, 0xAA, 0xFE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(timerAdjustCalls, 1)
  Harness.assertEqual(cursor, 4) -- opcode + terminator + the real extra skip byte
end)

Harness.test("StandardScriptHandlers.runListSearch: real opcode 0x0B (searches when the gate is CLEAR) finds a matching byte in the real FLAT candidate list and skips to just past its own terminator", function()
  local addr = ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0B
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x0B] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.runListSearch(
    false, function() return 9 end, function() return false end, nil)) -- gate CLEAR -> 0x0B searches

  -- Real shape: a FLAT list of candidate bytes (5, 3, 9, 2), ONE real
  -- terminator at the end -- NOT independently-terminated entries
  -- (confirmed by direct disassembly: `$3466`'s own "byte==0" check
  -- exhausts IMMEDIATELY, it does not skip to a "next entry").
  local stream = { 0x0B, 5, 3, 9, 2, 0, 0xEE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 8) -- matched at index 4 (value 9), skipped the remaining candidates + terminator
end)

Harness.test("StandardScriptHandlers.runListSearch: a real 0 encountered before any match hits the exhausted leaf immediately (no extra scanning)", function()
  local addr = ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0B
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x0B] = addr }))
  local exhaustedAt = nil
  interp:registerHandler(addr, StandardScriptHandlers.runListSearch(
    false, function() return 9 end, function() return false end,
    function(c) exhaustedAt = c; return 999 end))

  local stream = { 0x0B, 5, 1, 0, 0xEE } -- neither 5 nor 1 match 9; real terminator hit
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(exhaustedAt, 5) -- cursor right after the real terminator byte
  Harness.assertEqual(cursor, 999)
end)

Harness.test("StandardScriptHandlers.runListSearch: a real gate MISMATCH skips the search entirely, scanning straight to the terminator", function()
  local addr = ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0B
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x0B] = addr }))
  local exhaustedAt = nil
  interp:registerHandler(addr, StandardScriptHandlers.runListSearch(
    false, function() return 9 end, function() return true end, -- gate SET -> 0x0B does NOT search
    function(c) exhaustedAt = c; return 999 end))

  local stream = { 0x0B, 9, 1, 0, 0xEE } -- would have matched if searched -- but the gate blocks it
  interp:step(stream, 1)
  Harness.assertEqual(exhaustedAt, 5) -- real $3476 scans PAST the would-be-matching byte too
end)

Harness.test("StandardScriptHandlers.runListSearch: real opcode 0x0C is the exact polarity mirror of 0x0B", function()
  local addr = ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0C
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x0C] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.runListSearch(
    true, function() return 9 end, function() return true end, nil)) -- gate SET -> 0x0C searches

  local stream = { 0x0C, 9, 7, 0, 0xEE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 6) -- matched immediately, skipped the remaining candidate + terminator
end)

Harness.test("StandardScriptHandlers.runListSearch: fails loudly with no matchByte/isGateSet rather than guessing a default", function()
  local ok1 = pcall(StandardScriptHandlers.runListSearch(false, nil, function() return false end, nil), {}, 1)
  Harness.assertTrue(not ok1)
  local ok2 = pcall(StandardScriptHandlers.runListSearch(false, function() return 1 end, nil, nil), {}, 1)
  Harness.assertTrue(not ok2)
end)

-- CORRECTED (2026-08-15, live mgba watchpoint trace on WRAM $D85A --
-- see StandardScriptHandlers.tick's own doc comment for the full
-- evidence): the real ROM does NOT dispatch this opcode once then
-- immediately continue -- it self-reschedules for many real frames at
-- a real, live-confirmed 5-frame pace (identical to `.textboxWait`'s
-- own already-known cadence), gated by the SAME `isDone` concept, not
-- "always advances immediately." These 2 tests are rewritten to match
-- (and are now structurally identical to the `.textboxWait` tests just
-- below, since the two opcodes share the same real mechanism).
-- REWRITTEN 2026-08-15 ("mach trotzdem, ändere den code"): opcode
-- `0x04` is a real per-byte text/control-code classifier ($333D), not
-- a simple tick gated by an external `isDone` -- see
-- `StandardScriptHandlers.tick`'s own doc comment for the full
-- disassembly trail. These tests cover the 3 real, distinct branches
-- plus the "no silent guess" failure case.

Harness.test("StandardScriptHandlers.tick: real TERMINATOR byte (0x00) advances immediately, no pacing", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  interp:registerHandler(tick, StandardScriptHandlers.tick())

  local stream = { 0x04, 0x00 }
  local nextCursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0x04)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(nextCursor, 3) -- real ROM: INC HL skips the terminator too
end)

Harness.test("StandardScriptHandlers.tick: real CONTROL CODE (0x10-0x1F) with no onControlCode advances immediately by exactly 1 byte", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  interp:registerHandler(tick, StandardScriptHandlers.tick())

  local stream = { 0x04, 0x14 } -- 0x14: the real name-insertion control byte
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(nextCursor, 3) -- consumes exactly the 1 real control byte
end)

Harness.test("StandardScriptHandlers.tick: real CONTROL CODE releasing with 0 extra bytes advances by exactly 1 byte", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  local seen = nil
  interp:registerHandler(tick, StandardScriptHandlers.tick(nil, function(byte) seen = byte; return 0 end))

  local stream = { 0x04, 0x14 }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(seen, 0x14)
  Harness.assertEqual(nextCursor, 3)
end)

-- REAL, live-verified refinement (2026-08-15, mgba watchpoint trace of
-- WRAM $D853 bit 7): at least control byte 0x11 genuinely PACES before
-- its own real $36D0 bridge fires, consuming 1 EXTRA real byte beyond
-- the control byte itself -- see VictorySequence.lua's own
-- `buildBossSequenceInterpreter` for the real, live-timed wiring this
-- generalizes.
Harness.test("StandardScriptHandlers.tick: real CONTROL CODE can halt (return false/nil) then release with extra bytes consumed", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  local calls = 0
  interp:registerHandler(tick, StandardScriptHandlers.tick(nil, function(_byte)
    calls = calls + 1
    if calls < 3 then
      return false -- still real-pacing
    end
    return 1 -- release: 1 extra real byte via the real $36D0 bridge
  end))

  local stream = { 0x04, 0x11, 0x00 } -- the control byte's own real $36D0 bridge consumes the byte after it too
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "halted")
  local nextCursor
  nextCursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(calls, 3)
  Harness.assertEqual(nextCursor, 4) -- 1 (control byte) + 1 (extra, real $36D0 bridge) past afterOpcode
end)

Harness.test("StandardScriptHandlers.tick: real TEXT CHARACTER paces at the real 5-frame cadence, then advances by exactly 1 byte", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  local ticks = 0
  interp:registerHandler(tick, StandardScriptHandlers.tick(function() ticks = ticks + 1 end))

  -- 0xFF = TextDecoder.SPACE_BYTE, a real, recognized printable byte.
  local stream = { 0x04, 0xFF }
  local cursor = 1
  local kind
  for i = 1, 5 do
    local nextCursor, _, k = interp:step(stream, cursor)
    cursor, kind = nextCursor, k
    if i < 5 then
      Harness.assertEqual(kind, "halted")
      Harness.assertEqual(cursor, 1) -- real halt: cursor doesn't move while pacing
    end
  end
  -- Real, live-confirmed 5-frame pacing gate (frame_counter deltas of
  -- exactly 5 across dozens of consecutive real observations).
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 3) -- released: advances past the 1 real text byte
  Harness.assertEqual(ticks, 1) -- one real onTick call for this one real character
end)

Harness.test("StandardScriptHandlers.tick: fails loudly on a real byte that's neither terminator, control code, nor recognized text (no silent guess)", function()
  local tick = ScriptOpcodeTable.TICK_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x04] = tick }))
  interp:registerHandler(tick, StandardScriptHandlers.tick())

  local stream = { 0x04, 0x09 } -- 0x09: not 0x00, not 0x10-0x1F, not TextDecoder-recognized
  local ok = pcall(function() interp:step(stream, 1) end)
  Harness.assertTrue(not ok)
end)

Harness.test("StandardScriptHandlers.textboxWait: halts (real ROM sub-opcode 1/3/4 family) until isDone() says the box is revealed", function()
  local wait = ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = wait }))
  local done = false
  interp:registerHandler(wait, StandardScriptHandlers.textboxWait(nil, function() return done end))

  local stream = { 0xFF, 0xFE }
  local cursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0xFF)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1) -- real halt: does not advance past the opcode byte

  done = true
  local nextCursor, _, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(nextCursor, 2) -- released: advances past the 0xFF opcode byte
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.textboxWait: calls onTick once per real 5-frame pacing gate while waiting", function()
  local wait = ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = wait }))
  local ticks = 0
  interp:registerHandler(wait, StandardScriptHandlers.textboxWait(function() ticks = ticks + 1 end, function() return false end))

  local stream = { 0xFF }
  local cursor = 1
  for _ = 1, 12 do
    cursor = interp:step(stream, cursor)
  end
  -- Real $36C2 pacing gate: one onTick call at tick 1, then again every
  -- 5th tick thereafter (1, 6, 11, ...) -- see StandardScriptHandlers
  -- .textboxWait's own doc comment for the real evidence.
  Harness.assertEqual(ticks, 3)
end)

Harness.test("StandardScriptHandlers.textboxWait: two separate real occurrences (different cursors) don't share pacing state", function()
  -- Regression test for a real, self-caught design flaw (2026-08-12):
  -- the first version used one shared closure counter for EVERY real
  -- use of this opcode, so a second box's pacing silently inherited
  -- whatever countdown phase the first box's last tick left behind.
  local wait = ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = wait }))
  local ticks = 0
  local done = false
  interp:registerHandler(wait, StandardScriptHandlers.textboxWait(function() ticks = ticks + 1 end, function() return done end))

  -- First real occurrence, at cursor 1: tick 3 times, then release.
  local stream = { 0xFF, 0x99, 0xFF, 0xFE }
  local cursor = 1
  for _ = 1, 3 do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(ticks, 1) -- only the first of the 3 ticks lands on the 5-tick gate
  done = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 2) -- released past the first 0xFF

  -- A SECOND, separate real occurrence at a different cursor (3): its
  -- own first tick must fire onTick immediately (a fresh 5-tick gate),
  -- not silently continue the first occurrence's leftover countdown.
  done = false
  ticks = 0
  local nextCursor, opcode, kind = interp:step(stream, 3)
  Harness.assertEqual(opcode, 0xFF)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(ticks, 1)
end)

Harness.test("StandardScriptHandlers.startTextboxWait: real opcode 0xF0 -- consumes 1 operand byte, then behaves like textboxWait", function()
  local start = ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF0] = start }))
  local done = false
  local seenOperand = nil
  interp:registerHandler(start, StandardScriptHandlers.startTextboxWait(nil, function() return done end))

  -- opcode(1) + 1 real operand byte (the real $D84D setup value) + next real opcode
  local stream = { 0xF0, 0x07, 0xFE }
  local cursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0xF0)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1) -- unchanged: real halt semantics

  done = true
  local nextCursor, _, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(nextCursor, 3) -- past BOTH the opcode byte and its 1 real operand byte
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.startTextboxWait: calls onTick at the real 5-frame pacing gate while waiting", function()
  local start = ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF0] = start }))
  local ticks = 0
  interp:registerHandler(start, StandardScriptHandlers.startTextboxWait(function() ticks = ticks + 1 end, function() return false end))

  local stream = { 0xF0, 0x00 }
  local cursor = 1
  for _ = 1, 11 do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(ticks, 3) -- ticks 1, 6, 11
end)

Harness.test("StandardScriptHandlers.soundParam: real 0xF8/0xF9 opcodes consume 1 operand byte each and call back", function()
  local p1, p2 = ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS, ScriptOpcodeTable.SOUND_PARAM_2_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF8] = p1, [0xF9] = p2 }))
  local seen1, seen2 = nil, nil
  interp:registerHandler(p1, StandardScriptHandlers.soundParam(function(v) seen1 = v end))
  interp:registerHandler(p2, StandardScriptHandlers.soundParam(function(v) seen2 = v end))

  local stream = { 0xF8, 10, 0xF9, 20, 0xFE }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(seen1, 10)
  Harness.assertEqual(cursor, 3)
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(seen2, 20)
  Harness.assertEqual(cursor, 5)
  Harness.assertEqual(stream[cursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.soundParam: onParam is optional", function()
  local p1 = ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF8] = p1 }))
  interp:registerHandler(p1, StandardScriptHandlers.soundParam())

  local nextCursor = interp:step({ 0xF8, 99 }, 1)
  Harness.assertEqual(nextCursor, 3)
end)

Harness.test("StandardScriptHandlers.triggerEvent: real 0xE0 opcode consumes no operand bytes and calls back", function()
  local addr = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xE0] = addr }))
  local fired = 0
  interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(function() fired = fired + 1 end))

  local nextCursor = interp:step({ 0xE0, 0xFE }, 1)
  Harness.assertEqual(fired, 1)
  Harness.assertEqual(nextCursor, 2)
end)

Harness.test("StandardScriptHandlers.triggerEvent: onTrigger is optional", function()
  local addr = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xE0] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.triggerEvent())

  local nextCursor = interp:step({ 0xE0 }, 1)
  Harness.assertEqual(nextCursor, 2)
end)

Harness.test("StandardScriptHandlers.typewriterCommand: real 0x03 opcode consumes 2 operand bytes, calls back with only the first", function()
  local addr = ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x03] = addr }))
  local seen = nil
  interp:registerHandler(addr, StandardScriptHandlers.typewriterCommand(function(v) seen = v end))

  -- opcode(1) + used operand(1) + skipped operand(1) + next real opcode
  local stream = { 0x03, 5, 0xAA, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(seen, 5)
  Harness.assertEqual(nextCursor, 4) -- past BOTH operand bytes, landing exactly on 0xFE
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.typewriterCommand: onCommand is optional", function()
  local addr = ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x03] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.typewriterCommand())

  local nextCursor = interp:step({ 0x03, 1, 2 }, 1)
  Harness.assertEqual(nextCursor, 4)
end)

Harness.test("StandardScriptHandlers.typewriterCommand: pushes a real B==3 queue entry (inert, but real) when given a queue", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local addr = ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x03] = addr }))
  local queue = ScriptContinuationQueue.new()
  interp:registerHandler(addr, StandardScriptHandlers.typewriterCommand(nil, queue))

  interp:step({ 0x03, 1, 2 }, 1)
  Harness.assertTrue(not queue:isEmpty())
  local shouldRedirect = queue:pop()
  Harness.assertTrue(not shouldRedirect) -- real B==3: never redirects when popped
end)

Harness.test("StandardScriptHandlers.actorAction: real opcode 0x10 family halts (WRAM $C272 gate) until isReady(), then fires onAction(group) and continues", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x10] = addr }))
  local ready = false
  local seenGroup = nil
  interp:registerHandler(addr, StandardScriptHandlers.actorAction(0x04, function() return ready end, function(g) seenGroup = g end))

  local stream = { 0x10, 0xFE }
  local cursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0x10)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  Harness.assertEqual(seenGroup, nil) -- not fired yet

  ready = true
  local nextCursor, _, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(seenGroup, 0x04)
  Harness.assertEqual(nextCursor, 2)
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.actorAction: the other 4 real opcodes register at their own distinct real addresses with their own real group", function()
  local cases = {
    { opcode = 0x20, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_20, group = 0x04 },
    { opcode = 0x25, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_25, group = 0x1F },
    { opcode = 0x30, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_30, group = 0x04 },
    { opcode = 0x7B, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_7B, group = 0x0F },
  }
  for _, c in ipairs(cases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local seenGroup = nil
    interp:registerHandler(c.addr, StandardScriptHandlers.actorAction(c.group, function() return true end, function(g) seenGroup = g end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertEqual(seenGroup, c.group)
    Harness.assertEqual(nextCursor, 2)
  end
end)

Harness.test("StandardScriptHandlers.actorAction: isReady/onAction re-evaluated fresh each tick (no stale halt state)", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x10] = addr }))
  local checks = 0
  interp:registerHandler(addr, StandardScriptHandlers.actorAction(0x04, function()
    checks = checks + 1
    return checks >= 3
  end))

  local stream = { 0x10 }
  local cursor = 1
  local kind
  for _ = 1, 3 do
    cursor, _, kind = interp:step(stream, cursor)
  end
  Harness.assertEqual(checks, 3)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 2)
end)

Harness.test("StandardScriptHandlers.queuedAction: real opcodes 0x38/0x78 halt (WRAM $C5A0 gate) until isReady(), then fire and continue", function()
  local addr38, addr78 = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_38, ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_78
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x38] = addr38, [0x78] = addr78 }))
  local ready = false
  local fired38, fired78 = 0, 0
  interp:registerHandler(addr38, StandardScriptHandlers.queuedAction(function() return ready end, function() fired38 = fired38 + 1 end))
  interp:registerHandler(addr78, StandardScriptHandlers.queuedAction(function() return ready end, function() fired78 = fired78 + 1 end))

  local stream = { 0x38, 0x78 }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(fired38, 0)

  ready = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(fired38, 1)
  Harness.assertEqual(cursor, 2)

  ready = false
  local _, _, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "halted")
  Harness.assertEqual(fired78, 0)
  ready = true
  local finalCursor = interp:step(stream, cursor)
  Harness.assertEqual(fired78, 1)
  Harness.assertEqual(finalCursor, 3)
end)

Harness.test("StandardScriptHandlers.actorSlotPosition: real opcode 0x49 halts (SAME WRAM $C5A0 gate) WITHOUT consuming operand bytes, then reads them once ready", function()
  local addr = ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x49] = addr }))
  local ready = false
  local seenByte1, seenByte2
  interp:registerHandler(addr, StandardScriptHandlers.actorSlotPosition(
    function() return ready end,
    function(b1, b2) seenByte1, seenByte2 = b1, b2 end))

  local stream = { 0x49, 10, 20, 0x3C }
  -- Not ready yet: halts BEFORE reading the operand bytes -- re-checking
  -- the exact same gate (and the exact same still-unconsumed bytes) next
  -- tick, per this opcode's own real, verified byte ordering (the real
  -- `RET NZ` precedes both `LD A,(HL+)` reads).
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  Harness.assertEqual(seenByte1, nil)

  ready = true
  local nextCursor, opcode2, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(opcode2, 0x49)
  Harness.assertEqual(seenByte1, 10)
  Harness.assertEqual(seenByte2, 20)
  Harness.assertEqual(nextCursor, 4) -- past the opcode AND both real operand bytes
  Harness.assertEqual(stream[nextCursor], 0x3C) -- next real opcode untouched
end)

Harness.test("StandardScriptHandlers.oneShotTriggerGate: fires once, consumes its real operand byte, and continues when the gate is clear (2026-08-13, task #86)", function()
  local latch = { false }
  local fired = {}
  local handler = StandardScriptHandlers.oneShotTriggerGate(
    5,
    function() return latch[1] end,
    function(v) latch[1] = v end,
    nil, -- gate defaults to "always clear" -- matches the real, live-observed case
    function(operand, group) fired[#fired + 1] = { operand, group } end)

  local addr = 0x9999
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFC] = addr }))
  interp:registerHandler(addr, handler)

  local stream = { 0xFC, 42, 0x3C } -- opcode, 1 real operand byte, next real opcode
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(#fired, 1)
  Harness.assertEqual(fired[1][1], 42) -- the real operand byte
  Harness.assertEqual(fired[1][2], 5) -- the real selector group
  Harness.assertEqual(nextCursor, 3) -- opcode + 1 operand byte, gate clear -> continues
  Harness.assertEqual(latch[1], false) -- latch reset once the gate clears
end)

Harness.test("StandardScriptHandlers.oneShotTriggerGate: halts (real conditional-halt convention) when the gate is blocked, THEN resumes at the real, remembered position", function()
  local latch = { false }
  local blocked = true
  local handler = StandardScriptHandlers.oneShotTriggerGate(
    4,
    function() return latch[1] end,
    function(v) latch[1] = v end,
    function() return not blocked end,
    function() end)
  local addr = 0x9998
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFD] = addr }))
  interp:registerHandler(addr, handler)

  local stream = { 0xFD, 7, 0x3C }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1) -- real halt semantics: same opcode re-dispatches next tick
  Harness.assertEqual(latch[1], 3) -- the real resume cursor, remembered across the halt

  blocked = false
  local nextCursor, opcode2, kind2 = interp:step(stream, cursor)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(opcode2, 0xFD)
  Harness.assertEqual(nextCursor, 3) -- the SAME 1 operand byte, not re-consumed a second time
end)

Harness.test("StandardScriptHandlers.actorAction/queuedAction/triggerEvent: round 2 -- 9 more real opcodes reusing the same already-tested factories", function()
  -- Round 2 (2026-08-12, "mach erstmal 2"): a fresh re-scan found 9
  -- more real opcodes using the EXACT SAME actor-flag/state family
  -- (just different real group constants) plus one more real
  -- trigger-event opcode -- all wired by simply registering the
  -- SAME, already-thoroughly-tested factories at their own real
  -- addresses. This test locks in that every one of them dispatches
  -- correctly, not a re-test of the shared logic itself (see the
  -- dedicated tests above for that).
  local actorCases = {
    { opcode = 0x11, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_11, group = 0x05 },
    { opcode = 0x14, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_14, group = 0x1E },
    { opcode = 0x1B, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1B, group = 0x0F },
    { opcode = 0x3A, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3A, group = 0x0E },
    { opcode = 0x40, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_40, group = 0x04 },
    { opcode = 0x60, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_60, group = 0x04 },
    { opcode = 0x70, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_70, group = 0x04 },
  }
  for _, c in ipairs(actorCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local seenGroup = nil
    interp:registerHandler(c.addr, StandardScriptHandlers.actorAction(c.group, function() return true end, function(g) seenGroup = g end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertEqual(seenGroup, c.group)
    Harness.assertEqual(nextCursor, 2)
  end

  local queuedCases = {
    { opcode = 0x18, addr = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_18 },
    { opcode = 0x48, addr = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_48 },
  }
  for _, c in ipairs(queuedCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local fired = false
    interp:registerHandler(c.addr, StandardScriptHandlers.queuedAction(function() return true end, function() fired = true end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertTrue(fired)
    Harness.assertEqual(nextCursor, 2)
  end

  local addrE4 = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E4
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xE4] = addrE4 }))
  local fired = false
  interp:registerHandler(addrE4, StandardScriptHandlers.triggerEvent(function() fired = true end))
  local nextCursor = interp:step({ 0xE4 }, 1)
  Harness.assertTrue(fired)
  Harness.assertEqual(nextCursor, 2)
end)

Harness.test("StandardScriptHandlers.actorAction: real opcode 0x85 -- a THIRD real gate ($C240 bit7) but a fixed group", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_85
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x85] = addr }))
  local ready = false
  local seenGroup = nil
  interp:registerHandler(addr, StandardScriptHandlers.actorAction(0x08, function() return ready end, function(g) seenGroup = g end))

  local _, _, kind = interp:step({ 0x85 }, 1)
  Harness.assertEqual(kind, "halted")
  ready = true
  local nextCursor, _, kind2 = interp:step({ 0x85 }, 1)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(seenGroup, 0x08)
  Harness.assertEqual(nextCursor, 2)
end)

Harness.test("StandardScriptHandlers.actorAction: real opcode 0x80 -- group is a real DYNAMIC function, re-resolved fresh on every real release", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x80] = addr }))
  -- Simulates the real ROM's own "(actor#4 low nibble) + 0x90" live
  -- computation -- this project's own caller-supplied stand-in.
  local actor4LowNibble = 0x03
  local getGroup = function() return actor4LowNibble + 0x90 end
  local seenGroups = {}
  interp:registerHandler(addr, StandardScriptHandlers.actorAction(getGroup, function() return true end,
    function(g) seenGroups[#seenGroups + 1] = g end))

  interp:step({ 0x80 }, 1)
  Harness.assertEqual(seenGroups[1], 0x93)

  -- Real, live WRAM state changes between two separate real dispatches
  -- -- the SAME registered handler must reflect the NEW value, not a
  -- value cached from registration time.
  actor4LowNibble = 0x0A
  interp:step({ 0x80 }, 1)
  Harness.assertEqual(seenGroups[2], 0x9A)
end)

Harness.test("StandardScriptHandlers.triggerEvent: real opcode 0xDE (real WRAM housekeeping, no operand, always continues) reuses the same factory", function()
  local addr = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_DE
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xDE] = addr }))
  local fired = 0
  interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(function() fired = fired + 1 end))

  local stream = { 0xDE, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(fired, 1)
  Harness.assertEqual(nextCursor, 2)
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.actorAction/triggerEvent: round 3 -- 5 more actor-flag opcodes + 2 more trigger-event opcodes", function()
  local actorCases = {
    { opcode = 0x21, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_21, group = 0x05 },
    { opcode = 0x3B, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3B, group = 0x0F },
    { opcode = 0x47, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_47, group = 0x1D },
    { opcode = 0x71, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_71, group = 0x05 },
    { opcode = 0x77, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_77, group = 0x1D },
  }
  for _, c in ipairs(actorCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local seenGroup = nil
    interp:registerHandler(c.addr, StandardScriptHandlers.actorAction(c.group, function() return true end, function(g) seenGroup = g end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertEqual(seenGroup, c.group)
    Harness.assertEqual(nextCursor, 2)
  end

  local triggerCases = {
    ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E2,
    ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E5,
  }
  for _, addr in ipairs(triggerCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x99] = addr }))
    local fired = false
    interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(function() fired = true end))
    local nextCursor = interp:step({ 0x99 }, 1)
    Harness.assertTrue(fired)
    Harness.assertEqual(nextCursor, 2)
  end
end)

Harness.test("StandardScriptHandlers.byteWordCommand: real opcode 0xB0 consumes 1 byte + 1 little-endian word, always continues", function()
  local addr = ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xB0] = addr }))
  local seenByte, seenWord = nil, nil
  interp:registerHandler(addr, StandardScriptHandlers.byteWordCommand(function(b, w) seenByte, seenWord = b, w end))

  -- opcode(1) + byte(1) + word-lo(1) + word-hi(1) + next real opcode
  local stream = { 0xB0, 0x07, 0x34, 0x12, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(seenByte, 0x07)
  Harness.assertEqual(seenWord, 0x1234) -- little-endian: lo=0x34, hi=0x12
  Harness.assertEqual(nextCursor, 5)
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.byteWordCommand: onCommand is optional", function()
  local addr = ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xB0] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.byteWordCommand())
  Harness.assertEqual(interp:step({ 0xB0, 1, 2, 3 }, 1), 5)
end)

Harness.test("StandardScriptHandlers.wordCommand: real opcode 0xD0 consumes 1 little-endian word, always continues", function()
  local addr = ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xD0] = addr }))
  local seenWord = nil
  interp:registerHandler(addr, StandardScriptHandlers.wordCommand(function(w) seenWord = w end))

  local stream = { 0xD0, 0x34, 0x12, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(seenWord, 0x1234)
  Harness.assertEqual(nextCursor, 4)
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.wordCommand: onCommand is optional", function()
  local addr = ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xD0] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.wordCommand())
  Harness.assertEqual(interp:step({ 0xD0, 1, 2 }, 1), 4)
end)

Harness.test("StandardScriptHandlers.actorAction/triggerEvent/wordCommand: round 4 -- 4 more actor-flag opcodes, 3 more trigger-event opcodes, 1 more wordCommand reuse", function()
  local actorCases = {
    { opcode = 0x15, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_15, group = 0x1F },
    { opcode = 0x17, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_17, group = 0x1D },
    { opcode = 0x56, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_56, group = 0x1C },
    { opcode = 0x65, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_65, group = 0x1F },
  }
  for _, c in ipairs(actorCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local seenGroup = nil
    interp:registerHandler(c.addr, StandardScriptHandlers.actorAction(c.group, function() return true end, function(g) seenGroup = g end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertEqual(seenGroup, c.group)
    Harness.assertEqual(nextCursor, 2)
  end

  local triggerAddrs = {
    ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E1,
    ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_B9,
    ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_C3,
  }
  for _, addr in ipairs(triggerAddrs) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x99] = addr }))
    local fired = false
    interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(function() fired = true end))
    local nextCursor = interp:step({ 0x99 }, 1)
    Harness.assertTrue(fired)
    Harness.assertEqual(nextCursor, 2)
  end

  local wordAddr = ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_EF
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xEF] = wordAddr }))
  local seenWord = nil
  interp:registerHandler(wordAddr, StandardScriptHandlers.wordCommand(function(w) seenWord = w end))
  local nextCursor = interp:step({ 0xEF, 0x34, 0x12 }, 1)
  Harness.assertEqual(seenWord, 0x1234)
  Harness.assertEqual(nextCursor, 4)
end)

Harness.test("StandardScriptHandlers.twoByteCommand: real opcode 0xF6 consumes 2 SEPARATE operand bytes (not combined), always continues", function()
  local addr = ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF6] = addr }))
  local seen1, seen2 = nil, nil
  interp:registerHandler(addr, StandardScriptHandlers.twoByteCommand(function(b1, b2) seen1, seen2 = b1, b2 end))

  local stream = { 0xF6, 0x07, 0x0A, 0xFE }
  local nextCursor = interp:step(stream, 1)
  Harness.assertEqual(seen1, 0x07)
  Harness.assertEqual(seen2, 0x0A)
  Harness.assertEqual(nextCursor, 4)
  Harness.assertEqual(stream[nextCursor], 0xFE)
end)

Harness.test("StandardScriptHandlers.twoByteCommand: onCommand is optional", function()
  local addr = ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF6] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.twoByteCommand())
  Harness.assertEqual(interp:step({ 0xF6, 1, 2 }, 1), 4)
end)

Harness.test("StandardScriptHandlers.actorAction/triggerEvent: round 5 -- 6 more actor-flag opcodes, 1 more $1588-gated opcode, 1 more trigger-event opcode", function()
  local actorCases = {
    { opcode = 0x16, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_16, group = 0x1C },
    { opcode = 0x1A, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1A, group = 0x0E },
    { opcode = 0x26, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_26, group = 0x1C },
    { opcode = 0x2A, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2A, group = 0x0E },
    { opcode = 0x44, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_44, group = 0x1E },
    { opcode = 0x57, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_57, group = 0x1D },
    { opcode = 0x84, addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_84, group = 0x04 },
  }
  for _, c in ipairs(actorCases) do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [c.opcode] = c.addr }))
    local seenGroup = nil
    interp:registerHandler(c.addr, StandardScriptHandlers.actorAction(c.group, function() return true end, function(g) seenGroup = g end))
    local nextCursor = interp:step({ c.opcode }, 1)
    Harness.assertEqual(seenGroup, c.group)
    Harness.assertEqual(nextCursor, 2)
  end

  local addr = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_A0
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xA0] = addr }))
  local fired = false
  interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(function() fired = true end))
  local nextCursor = interp:step({ 0xA0 }, 1)
  Harness.assertTrue(fired)
  Harness.assertEqual(nextCursor, 2)
end)

Harness.test("StandardScriptHandlers.actorAction/queuedAction/soundParam: round 6 -- final long-tail batch this pass", function()
  local addr28 = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_28
  local interp28 = ScriptInterpreter.new(makeOpcodeTable({ [0x28] = addr28 }))
  local fired = false
  interp28:registerHandler(addr28, StandardScriptHandlers.queuedAction(function() return true end, function() fired = true end))
  Harness.assertEqual(interp28:step({ 0x28 }, 1), 2)
  Harness.assertTrue(fired)

  local addr46 = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_46
  local interp46 = ScriptInterpreter.new(makeOpcodeTable({ [0x46] = addr46 }))
  local seenGroup = nil
  interp46:registerHandler(addr46, StandardScriptHandlers.actorAction(0x1C, function() return true end, function(g) seenGroup = g end))
  Harness.assertEqual(interp46:step({ 0x46 }, 1), 2)
  Harness.assertEqual(seenGroup, 0x1C)

  local addr58 = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_58
  local interp58 = ScriptInterpreter.new(makeOpcodeTable({ [0x58] = addr58 }))
  local fired58 = false
  interp58:registerHandler(addr58, StandardScriptHandlers.queuedAction(function() return true end, function() fired58 = true end))
  Harness.assertEqual(interp58:step({ 0x58 }, 1), 2)
  Harness.assertTrue(fired58)

  local addrC4 = ScriptOpcodeTable.SOUND_PARAM_HANDLER_ADDRESS_C4
  local interpC4 = ScriptInterpreter.new(makeOpcodeTable({ [0xC4] = addrC4 }))
  local seenValue = nil
  interpC4:registerHandler(addrC4, StandardScriptHandlers.soundParam(function(v) seenValue = v end))
  local nextCursor = interpC4:step({ 0xC4, 0x2A }, 1)
  Harness.assertEqual(seenValue, 0x2A)
  Harness.assertEqual(nextCursor, 3)
end)

Harness.test("StandardScriptHandlers.actorAction/queuedAction: onAction is optional in both", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x10] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.actorAction(0x04, function() return true end))
  Harness.assertEqual(interp:step({ 0x10 }, 1), 2)

  local addr38 = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_38
  local interp2 = ScriptInterpreter.new(makeOpcodeTable({ [0x38] = addr38 }))
  interp2:registerHandler(addr38, StandardScriptHandlers.queuedAction(function() return true end))
  Harness.assertEqual(interp2:step({ 0x38 }, 1), 2)
end)

Harness.test("StandardScriptHandlers.textboxWait: onTick is optional (no callback still halts/releases correctly)", function()
  local wait = ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = wait }))
  local done = false
  interp:registerHandler(wait, StandardScriptHandlers.textboxWait(nil, function() return done end))

  local _, _, kind = interp:step({ 0xFF }, 1)
  Harness.assertEqual(kind, "halted")
  done = true
  local nextCursor, _, kind2 = interp:step({ 0xFF }, 1)
  Harness.assertEqual(kind2, "handled")
  Harness.assertEqual(nextCursor, 2)
end)

-- --- StandardScriptHandlers.queueGate (opcode 0x00, ROM $3297) --------
-- Resolved 2026-08-12, "löse 1": the single largest real blocker this
-- project's own opcode-frequency scan found (275/1357 scripts). See
-- ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS's own doc comment for
-- the full disassembly these tests lock in.

Harness.test("StandardScriptHandlers.queueGate: halts while isBlocked() is true (real WRAM flag bit0 gate)", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local addr = ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x00] = addr }))
  local blocked = true
  local queue = ScriptContinuationQueue.new()
  interp:registerHandler(addr, StandardScriptHandlers.queueGate(queue, function() return blocked end))

  local _, opcode, kind = interp:step({ 0x00 }, 1)
  Harness.assertEqual(opcode, 0x00)
  Harness.assertEqual(kind, "halted")

  blocked = false
  local nextCursor, _, kind2 = interp:step({ 0x00 }, 1)
  -- not blocked anymore, but queue is empty -> still halts (real halt #2)
  Harness.assertEqual(kind2, "halted")
  Harness.assertEqual(nextCursor, 1)
end)

Harness.test("StandardScriptHandlers.queueGate: halts and calls onIdle while the real queue is empty", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local addr = ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x00] = addr }))
  local queue = ScriptContinuationQueue.new()
  local idleCalls = 0
  interp:registerHandler(addr, StandardScriptHandlers.queueGate(queue, nil, function() idleCalls = idleCalls + 1 end))

  local _, _, kind = interp:step({ 0x00 }, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(idleCalls, 1)
end)

Harness.test("StandardScriptHandlers.queueGate: a real B==2 entry (from .chain()) releases -- redirects the cursor and continues", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local addr = ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x00] = addr }))
  local queue = ScriptContinuationQueue.new()
  queue:push(true, 42) -- the real shape .chain() pushes
  interp:registerHandler(addr, StandardScriptHandlers.queueGate(queue))

  local nextCursor, opcode, kind = interp:step({ 0x00 }, 1)
  Harness.assertEqual(opcode, 0x00)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(nextCursor, 42) -- redirected to the popped real cursor
  Harness.assertTrue(queue:isEmpty()) -- the entry was really consumed
end)

Harness.test("StandardScriptHandlers.queueGate: a real B==3 entry (from .typewriterCommand()) just halts, consumed, no redirect", function()
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local addr = ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x00] = addr }))
  local queue = ScriptContinuationQueue.new()
  queue:push(false, 999) -- the real shape .typewriterCommand() pushes
  interp:registerHandler(addr, StandardScriptHandlers.queueGate(queue))

  local nextCursor, _, kind = interp:step({ 0x00 }, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(nextCursor, 1) -- unchanged: real halt, not a redirect
  Harness.assertTrue(queue:isEmpty()) -- still consumed, even though it halted
end)

Harness.test("StandardScriptHandlers.queueGate: fails loudly without a real queue", function()
  local ok = pcall(StandardScriptHandlers.queueGate, nil)
  Harness.assertTrue(not ok, "expected queueGate to require a real queue")
end)

Harness.test("StandardScriptHandlers.queueGate: end-to-end with .chain() -- CHAIN's own bookmark is exactly what releases opcode 0x00 later", function()
  -- A real, direct reproduction of the confirmed real mechanism: CHAIN
  -- (opcode 0x02) jumps away, bookmarking where to resume; some LATER
  -- real dispatch of opcode 0x00 (once its own real gate opens) pops
  -- that exact bookmark and resumes the ORIGINAL script from right
  -- after the CHAIN instruction -- not from wherever CHAIN jumped to.
  local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
  local chainAddr = ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS
  local gateAddr = ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x02] = chainAddr, [0x00] = gateAddr }))
  local queue = ScriptContinuationQueue.new()
  interp:registerHandler(chainAddr, StandardScriptHandlers.chain(queue))
  interp:registerHandler(gateAddr, StandardScriptHandlers.queueGate(queue))

  -- Real shape: CHAIN jumps to 0x4102 (far outside this synthetic
  -- stream -- fine, we never actually read from there in this test).
  -- Immediately after CHAIN's own 2 bytes (cursor 4), the SAME script
  -- later dispatches opcode 0x00.
  local stream = { 0x02, 0x01, 0x02, 0x00 }
  local afterChain = interp:step(stream, 1)
  Harness.assertEqual(afterChain, 0x4102) -- jumped away, as CHAIN's own immediate effect

  -- Later, something dispatches opcode 0x00 at the bookmarked position
  -- (cursor 4, right after CHAIN) -- it pops CHAIN's own real entry and
  -- redirects right back to that SAME position (a real, if degenerate
  -- in this synthetic test, round trip).
  local nextCursor, opcode, kind = interp:step(stream, 4)
  Harness.assertEqual(opcode, 0x00)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(nextCursor, 4)
end)

Harness.test("StandardScriptHandlers.periodicWramEffect: fires onTick every call with the real pre-increment counter, no stream byte consumed until wrap", function()
  local addr = 0x9990
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x00] = addr }))
  local seenCounters = {}
  interp:registerHandler(addr, StandardScriptHandlers.periodicWramEffect({}, 3, function(counter)
    seenCounters[#seenCounters + 1] = counter
  end))

  local stream = { 0x00, 0x00, 0x00, 0xAA, 0x00 } -- 0xAA is the real wrap-skip byte
  local cursor = 1
  cursor = interp:step(stream, cursor) -- counter 0 -> 1, no wrap
  Harness.assertEqual(cursor, 2)
  cursor = interp:step(stream, cursor) -- counter 1 -> 2, no wrap
  Harness.assertEqual(cursor, 3)
  cursor = interp:step(stream, cursor) -- counter 2 -> 0, WRAPS: consumes the real skip byte
  Harness.assertEqual(cursor, 5)
  Harness.assertEqual(#seenCounters, 3)
  Harness.assertEqual(seenCounters[1], 0)
  Harness.assertEqual(seenCounters[2], 1)
  Harness.assertEqual(seenCounters[3], 2)
end)

Harness.test("StandardScriptHandlers.periodicWramEffect: fails loudly on required arguments", function()
  Harness.assertTrue(not pcall(StandardScriptHandlers.periodicWramEffect, nil, 3, function() end))
  Harness.assertTrue(not pcall(StandardScriptHandlers.periodicWramEffect, {}, 0, function() end))
  Harness.assertTrue(not pcall(StandardScriptHandlers.periodicWramEffect, {}, 3, nil))
end)

Harness.test("StandardScriptHandlers.waveOffsetEffect: real opcode 0xFB ($0E8C) traces the real -4..+4 triangle wave over one 8-call cycle, back to 0", function()
  local addr = ScriptOpcodeTable.WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFB] = addr }))
  local seenValues = {}
  interp:registerHandler(addr, StandardScriptHandlers.waveOffsetEffect(function(v) seenValues[#seenValues + 1] = v end))

  local stream = {}
  for _ = 1, 8 do stream[#stream + 1] = 0xFB end
  local cursor = 1
  for _ = 1, 8 do
    cursor = interp:step(stream, cursor)
  end
  local expected = { 2, 4, 2, 0, 254, 252, 254, 0 } -- real byte wraparound (-2 = 254, -4 = 252)
  Harness.assertEqual(#seenValues, #expected)
  for i = 1, #expected do
    Harness.assertEqual(seenValues[i], expected[i])
  end
  Harness.assertEqual(cursor, 9) -- no wrap yet (real period is 64, not 8) -- no extra byte consumed
end)

Harness.test("StandardScriptHandlers.waveOffsetEffect: on the real 64th call, wraps and consumes exactly one extra script-stream byte", function()
  local addr = ScriptOpcodeTable.WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFB] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.waveOffsetEffect(nil)) -- onUpdate is optional

  local stream = {}
  for _ = 1, 64 do stream[#stream + 1] = 0xFB end
  stream[65] = 0xAA -- the real wrap-skip byte
  local cursor = 1
  for _ = 1, 63 do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(cursor, 64) -- 63 calls, each consuming just its own opcode byte
  cursor = interp:step(stream, cursor) -- the 64th call: wraps
  Harness.assertEqual(cursor, 66) -- opcode byte + the real wrap-skip byte
end)

Harness.test("StandardScriptHandlers.colorPulseEffect: real opcode 0xBF ($0FE0) writes the dim triple for the first 5 calls of a 10-call cycle, then the bright triple", function()
  local addr = ScriptOpcodeTable.COLOR_PULSE_EFFECT_HANDLER_ADDRESS_BF
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xBF] = addr }))
  local dimCalls, brightCalls = 0, 0
  local lastDim, lastBright
  interp:registerHandler(addr, StandardScriptHandlers.colorPulseEffect(
    function(r, g, b) dimCalls = dimCalls + 1; lastDim = { r, g, b } end,
    function(r, g, b) brightCalls = brightCalls + 1; lastBright = { r, g, b } end))

  local stream = {}
  for _ = 1, 10 do stream[#stream + 1] = 0xBF end
  stream[11] = 0xAA -- the real wrap-skip byte
  local cursor = 1
  for _ = 1, 5 do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(dimCalls, 5)
  Harness.assertEqual(brightCalls, 0)
  Harness.assertEqual(lastDim[1], 0x3F)
  Harness.assertEqual(lastDim[2], 0x3F)
  Harness.assertEqual(lastDim[3], 0x3F)

  for _ = 1, 4 do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(brightCalls, 4)
  Harness.assertEqual(cursor, 10) -- still no wrap (9 calls so far)

  cursor = interp:step(stream, cursor) -- the 10th call: wraps
  Harness.assertEqual(brightCalls, 5)
  Harness.assertEqual(lastBright[1], 0xE4)
  Harness.assertEqual(lastBright[2], 0xD0)
  Harness.assertEqual(lastBright[3], 0xD0)
  Harness.assertEqual(cursor, 12) -- opcode byte + the real wrap-skip byte
end)

Harness.test("StandardScriptHandlers.colorPulseEffect: both callbacks are optional", function()
  local addr = ScriptOpcodeTable.COLOR_PULSE_EFFECT_HANDLER_ADDRESS_BF
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xBF] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.colorPulseEffect(nil, nil))

  local cursor = interp:step({ 0xBF }, 1)
  Harness.assertEqual(cursor, 2)
end)

Harness.test("StandardScriptHandlers.paletteFadeCycle: real opcode 0xBD ($1046) genuinely halts for 65 real calls (the $1142 6x11 pacing gate), then releases on the 66th with zero extra bytes consumed", function()
  local addr = ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BD
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xBD] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.paletteFadeCycle({}, nil))

  local stream = {}
  for _ = 1, 66 do stream[#stream + 1] = 0xBD end
  local cursor = 1
  for i = 1, 65 do
    local nextCursor, opcode, kind = interp:step(stream, cursor)
    Harness.assertEqual(kind, "halted")
    Harness.assertEqual(nextCursor, cursor) -- real RET C: no $3727, same opcode re-dispatches
    cursor = nextCursor
  end
  local nextCursor, opcode, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(nextCursor, cursor + 1) -- the 66th call: real $3727, zero operand bytes of its own
end)

Harness.test("StandardScriptHandlers.paletteFadeCycle: onStep fires every real call with the correct (outer, inner) counter pair", function()
  local addr = ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BD
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xBD] = addr }))
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.paletteFadeCycle({},
    function(outer, inner) seen[#seen + 1] = { outer, inner } end))

  local stream = {}
  for _ = 1, 13 do stream[#stream + 1] = 0xBD end
  local cursor = 1
  for _ = 1, 13 do
    cursor = interp:step(stream, cursor)
  end
  -- Real $D49A (inner) is read/reported BEFORE this call's own increment
  -- -- calls 1-6 report inner 0-5 (outer 0), the 6th call's own
  -- increment then rolls inner back to 0 and bumps outer to 1 for the
  -- 7th call onward.
  local expected = {
    { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 },
    { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 },
    { 2, 0 },
  }
  Harness.assertEqual(#seen, #expected)
  for i = 1, #expected do
    Harness.assertEqual(seen[i][1], expected[i][1])
    Harness.assertEqual(seen[i][2], expected[i][2])
  end
end)

Harness.test("StandardScriptHandlers.paletteFadeCycle: 0xBD and 0xBC share ONE real pacing counter (real WRAM $D499/$D49A) when given the same shared state table", function()
  local addrBD = ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BD
  local addrBC = ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BC
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xBD] = addrBD, [0xBC] = addrBC }))
  local sharedState = {}
  interp:registerHandler(addrBD, StandardScriptHandlers.paletteFadeCycle(sharedState, nil))
  interp:registerHandler(addrBC, StandardScriptHandlers.paletteFadeCycle(sharedState, nil))

  -- 3 real calls to 0xBD (inner: 0->1->2->3), then switch to 0xBC --
  -- the shared counter must CONTINUE from 3, not reset, since both
  -- opcodes read/write the SAME real WRAM cells.
  local stream = { 0xBD, 0xBD, 0xBD, 0xBC, 0xBC, 0xBC }
  local cursor = 1
  for i = 1, 3 do
    local nextCursor, _, kind = interp:step(stream, cursor)
    Harness.assertEqual(kind, "halted")
    cursor = nextCursor
  end
  Harness.assertEqual(sharedState.inner, 3)
  for i = 1, 3 do
    local nextCursor, _, kind = interp:step(stream, cursor)
    Harness.assertEqual(kind, "halted")
    cursor = nextCursor
  end
  Harness.assertEqual(sharedState.inner, 6 % 6) -- 6 real calls total: inner wrapped once (6th call resets it to 0)
  Harness.assertEqual(sharedState.outer, 1) -- and bumped outer to 1
end)

Harness.test("StandardScriptHandlers.paletteFadeCycle: fails loudly without a state table", function()
  Harness.assertTrue(not pcall(StandardScriptHandlers.paletteFadeCycle, nil, nil))
end)

Harness.test("StandardScriptHandlers.paletteFadeCompletionGate: with the real dual gate defaulting to always-clear, completes the whole real 6-phase sequence in exactly 6 calls", function()
  local gate = StandardScriptHandlers.paletteFadeCompletionGate({}, nil, nil)
  for _ = 1, 5 do
    Harness.assertEqual(gate(), false)
  end
  Harness.assertEqual(gate(), true) -- the 6th call: phase 5's own unconditional reset+release
end)

Harness.test("StandardScriptHandlers.paletteFadeCompletionGate: onPhase reports the real phase sequence 0,1,2,3,4,5", function()
  local seen = {}
  local gate = StandardScriptHandlers.paletteFadeCompletionGate({}, nil, function(phase) seen[#seen + 1] = phase end)
  for _ = 1, 6 do gate() end
  local expected = { 0, 1, 2, 3, 4, 5 }
  Harness.assertEqual(#seen, #expected)
  for i = 1, #expected do
    Harness.assertEqual(seen[i], expected[i])
  end
end)

Harness.test("StandardScriptHandlers.paletteFadeCompletionGate: real dual-gate phases (1 and 3) genuinely halt while the gate is closed, and re-check it on every call", function()
  local gateOpen = false
  local checkCalls = 0
  local gate = StandardScriptHandlers.paletteFadeCompletionGate({}, function()
    checkCalls = checkCalls + 1
    return gateOpen
  end, nil)
  Harness.assertEqual(gate(), false) -- phase 0 -> 1, unconditional
  -- phase 1: real dual gate closed -- halts here as long as it stays closed.
  for _ = 1, 5 do
    Harness.assertEqual(gate(), false)
  end
  Harness.assertTrue(checkCalls >= 5)
  gateOpen = true -- real dual gate clears
  Harness.assertEqual(gate(), false) -- phase 1 -> 2, now that the gate is clear
  Harness.assertEqual(gate(), false) -- phase 2 -> 3, unconditional
  gateOpen = false -- real dual gate closes again for phase 3's own check
  for _ = 1, 3 do
    Harness.assertEqual(gate(), false) -- phase 3 halts again
  end
  gateOpen = true
  Harness.assertEqual(gate(), false) -- phase 3 -> 4
  Harness.assertEqual(gate(), false) -- phase 4 -> 5, unconditional
  Harness.assertEqual(gate(), true)  -- phase 5 -> 0, real release
end)

Harness.test("StandardScriptHandlers.paletteFadeCompletionGate: fails loudly without a state table", function()
  Harness.assertTrue(not pcall(StandardScriptHandlers.paletteFadeCompletionGate, nil, nil, nil))
end)

Harness.test("StandardScriptHandlers.peekTwoByteGate + paletteFadeCompletionGate: real opcode 0xF3 halts for the whole real 6-tick sequence (default dual gate), then releases without consuming the peeked bytes", function()
  local addr = ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xF3] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.peekTwoByteGate(nil,
    StandardScriptHandlers.paletteFadeCompletionGate({}, nil, nil)))

  local stream = { 0xF3, 0x0f, 0x55 }
  local cursor = 1
  for i = 1, 5 do
    local nextCursor, _, kind = interp:step(stream, cursor)
    Harness.assertEqual(kind, "halted")
    Harness.assertEqual(nextCursor, cursor)
    cursor = nextCursor
  end
  local nextCursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(nextCursor, 2) -- released at afterOpcode -- byte1 (0x0f) becomes the next real fetch
end)

Harness.test("StandardScriptHandlers.playerEntityTypeWrite: real opcodes 0x88/0x89 each fire their own fixed constant and consume exactly one real (unused) padding byte", function()
  local addr88 = ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_88
  local addr89 = ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_89
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x88] = addr88, [0x89] = addr89 }))
  local seen = {}
  local onWrite = function(v) seen[#seen + 1] = v end
  interp:registerHandler(addr88, StandardScriptHandlers.playerEntityTypeWrite(2, onWrite))
  interp:registerHandler(addr89, StandardScriptHandlers.playerEntityTypeWrite(1, onWrite))

  local stream = { 0x88, 0xAA, 0x89, 0xBB, 0x3C } -- 0xAA/0xBB are the real, genuinely-unused padding bytes
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + 1 padding byte
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 5)
  Harness.assertEqual(seen[1], 2) -- 0x88's own fixed constant
  Harness.assertEqual(seen[2], 1) -- 0x89's own fixed constant
end)

Harness.test("StandardScriptHandlers.playerEntityTypeWrite: onWrite is optional", function()
  local addr = ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_88
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x88] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.playerEntityTypeWrite(2, nil))

  local cursor = interp:step({ 0x88, 0xAA }, 1)
  Harness.assertEqual(cursor, 3)
end)

Harness.test("StandardScriptHandlers.actorCommandQueueEmptyGate: real opcode 0x8F halts while the queue is non-empty, then consumes one byte once empty", function()
  local addr = ScriptOpcodeTable.ACTOR_COMMAND_QUEUE_EMPTY_GATE_HANDLER_ADDRESS_8F
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x8F] = addr }))
  local empty = false
  interp:registerHandler(addr, StandardScriptHandlers.actorCommandQueueEmptyGate(function() return empty end))

  local stream = { 0x8F, 0xAA, 0x3C }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(cursor, 1) -- real halt: cursor unchanged, re-dispatches the same opcode
  Harness.assertEqual(kind, "halted")

  empty = true
  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 3) -- opcode + the real consumed byte
end)

Harness.test("StandardScriptHandlers.actorCommandQueueEmptyGate: with no isQueueEmpty, defaults to 'always empty' and continues immediately", function()
  local addr = ScriptOpcodeTable.ACTOR_COMMAND_QUEUE_EMPTY_GATE_HANDLER_ADDRESS_8F
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x8F] = addr }))
  interp:registerHandler(addr, StandardScriptHandlers.actorCommandQueueEmptyGate(nil))

  local cursor = interp:step({ 0x8F, 0xAA }, 1)
  Harness.assertEqual(cursor, 3)
end)

Harness.test("StandardScriptHandlers.actorActionOrSkip: real opcode 0x90 fires its real group with no bytes consumed when ready, but SOFT-SKIPS one byte (not halt) when not ready", function()
  local addr = ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_90
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x90] = addr }))
  local ready = false
  local seenGroups = {}
  interp:registerHandler(addr, StandardScriptHandlers.actorActionOrSkip(0x04,
    function() return ready end, function(g) seenGroups[#seenGroups + 1] = g end))

  local stream = { 0x90, 0xAA, 0x90, 0xBB }
  -- not ready: real soft-skip, NOT a halt -- consumes one byte and continues.
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 3) -- opcode + the real skipped byte
  Harness.assertEqual(#seenGroups, 0) -- onAction never fires on the not-ready path

  -- ready: real action, zero operand bytes.
  ready = true
  cursor, _, kind = interp:step(stream, cursor)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 4)
  Harness.assertEqual(seenGroups[1], 0x04)
end)

Harness.test("StandardScriptHandlers.queuedActionOrSkip: real opcode 0x98, same soft-skip shape without a group", function()
  local addr = ScriptOpcodeTable.QUEUED_ACTION_OR_SKIP_HANDLER_ADDRESS_98
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x98] = addr }))
  local ready = false
  local actionCalls = 0
  interp:registerHandler(addr, StandardScriptHandlers.queuedActionOrSkip(
    function() return ready end, function() actionCalls = actionCalls + 1 end))

  local stream = { 0x98, 0xAA }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- not ready: soft-skip, 1 byte consumed
  Harness.assertEqual(actionCalls, 0)
end)

Harness.test("StandardScriptHandlers.actorSlotPositionOrSkip: real opcode 0x99 skips exactly its own 2 real operand bytes when not ready (not an unrelated byte)", function()
  local addr = ScriptOpcodeTable.ACTOR_SLOT_POSITION_OR_SKIP_HANDLER_ADDRESS_99
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x99] = addr }))
  local ready = false
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.actorSlotPositionOrSkip(
    function() return ready end, function(b1, b2) seen[#seen + 1] = { b1, b2 } end))

  local stream = { 0x99, 10, 20, 0x99, 30, 40 }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 4) -- not ready: skips exactly 2 bytes, onSetPosition never fires
  Harness.assertEqual(#seen, 0)

  ready = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 7)
  Harness.assertEqual(seen[1][1], 30)
  Harness.assertEqual(seen[1][2], 40)
end)

Harness.test("StandardScriptHandlers.tileCursorSet: real opcode 0xEF captures its 2 real operand bytes AND consumes a genuine 3rd byte via $3727", function()
  local addr = ScriptOpcodeTable.TILE_CURSOR_SET_HANDLER_ADDRESS_EF
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xEF] = addr }))
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.tileCursorSet(
    function(b1, b2) seen[#seen + 1] = { b1, b2 } end))

  -- real stream shape: opcode, byte1(E), byte2(D), then a 3rd real byte
  -- consumed by the inline `$3727` -- NOT part of the tile-cursor value
  -- itself, but still real bytes the cursor must skip past.
  local stream = { 0xEF, 5, 9, 0x77 }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 5) -- opcode + 2 operand bytes + 1 skipped byte
  Harness.assertEqual(#seen, 1)
  Harness.assertEqual(seen[1][1], 5)
  Harness.assertEqual(seen[1][2], 9)
end)

Harness.test("StandardScriptHandlers.actorActionWithReadinessParam: real opcodes 0x7A/0x7B gate on isReady() (same approximate-halt convention as .actorAction), param is always offset+1 on the reachable ready path", function()
  local addrA = ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7A
  local addrB = ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7B
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x7A] = addrA, [0x7B] = addrB }))
  local ready = false
  local seen = {}
  interp:registerHandler(addrA, StandardScriptHandlers.actorActionWithReadinessParam(
    0x0E, 0x06, function() return ready end, function(g, p) seen[#seen + 1] = { g, p } end))
  interp:registerHandler(addrB, StandardScriptHandlers.actorActionWithReadinessParam(
    0x0F, 0x06, function() return ready end, function(g, p) seen[#seen + 1] = { g, p } end))

  local stream = { 0x7A, 0x7B }
  -- not ready: halts (same approximate-gate convention as
  -- .actorAction), never fires onAction, cursor stays unchanged.
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  Harness.assertEqual(#seen, 0)

  -- ready: param = 1 + 6 = 7.
  ready = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 2)
  Harness.assertEqual(seen[1][1], 0x0E)
  Harness.assertEqual(seen[1][2], 7)

  -- second opcode (0x7B), still ready: param = 1 + 6 = 7.
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 3)
  Harness.assertEqual(seen[2][1], 0x0F)
  Harness.assertEqual(seen[2][2], 7)
end)

Harness.test("StandardScriptHandlers.opcodeByteMirror: real opcode 0xCC consumes ZERO operand bytes (DEC HL / $3727-fetch cancel out) and re-reports its own opcode byte", function()
  local addr = ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xCC] = addr }))
  local seenByte = nil
  interp:registerHandler(addr, StandardScriptHandlers.opcodeByteMirror(function(b) seenByte = b end))

  -- real stream shape: opcode 0xCC immediately followed by the NEXT
  -- real opcode (0x00 here, a harmless placeholder) -- since 0xCC
  -- consumes zero real operand bytes, the interpreter must land
  -- exactly back on that next byte, not skip past it.
  local stream = { 0xCC, 0x00 }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 2) -- opcode consumed, ZERO operand bytes
  Harness.assertEqual(seenByte, 0xCC) -- re-mirrors its own real opcode byte
end)

Harness.test("StandardScriptHandlers.softReset: real opcode 0xC8 fires the required onReset callback and fails loudly without one", function()
  local addr = ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8

  -- real path: onReset provided, fires exactly once, cursor unchanged
  -- (the real ROM reads zero operand bytes -- a plain JP).
  do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC8] = addr }))
    local resetCount = 0
    interp:registerHandler(addr, StandardScriptHandlers.softReset(function() resetCount = resetCount + 1 end))
    local cursor = interp:step({ 0xC8 }, 1)
    Harness.assertEqual(cursor, 2)
    Harness.assertEqual(resetCount, 1)
  end

  -- honest failure path: no onReset provided -- this project's own
  -- "no silent fallback for a required callback" rule, asserted at
  -- real dispatch time (not construction time, so scripts that never
  -- reach 0xC8 aren't forced to supply this).
  do
    local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC8] = addr }))
    interp:registerHandler(addr, StandardScriptHandlers.softReset(nil))
    Harness.assertTrue(not pcall(function() interp:step({ 0xC8 }, 1) end))
  end
end)

Harness.test("StandardScriptHandlers.budgetFlagCommand: real opcode 0xD1 reads a little-endian 16-bit amount, fires the matching branch, and ALWAYS consumes exactly 3 bytes regardless of which branch fires", function()
  local addr = ScriptOpcodeTable.BUDGET_FLAG_COMMAND_HANDLER_ADDRESS_D1
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xD1] = addr }))
  local sufficient = true
  local seenSufficient, seenExhausted = nil, nil
  interp:registerHandler(addr, StandardScriptHandlers.budgetFlagCommand(
    function() return sufficient end,
    function(amount) seenSufficient = amount end,
    function(amount) seenExhausted = amount end))

  -- real stream shape: opcode + 2 little-endian operand bytes + 1
  -- real trailing byte consumed by the shared `$3727` tail (identical
  -- on both branches).
  local stream = { 0xD1, 0x34, 0x12, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 5) -- opcode + 2 operand bytes + 1 trailing byte
  Harness.assertEqual(seenSufficient, 0x1234)
  Harness.assertEqual(seenExhausted, nil)

  sufficient = false
  seenSufficient = nil
  cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 5) -- SAME byte consumption on the other branch
  Harness.assertEqual(seenExhausted, 0x1234)
  Harness.assertEqual(seenSufficient, nil)
end)

Harness.test("StandardScriptHandlers.rawByteLeafCommand: real opcodes 0x9C/0x9D pass the RAW byte (no +1, unlike .byteLeafCommand) and consume 2 real bytes total", function()
  local addrC = ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9C
  local addrD = ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9D
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x9C] = addrC, [0x9D] = addrD }))
  local seen = {}
  interp:registerHandler(addrC, StandardScriptHandlers.rawByteLeafCommand(function(b) seen[#seen + 1] = b end))
  interp:registerHandler(addrD, StandardScriptHandlers.rawByteLeafCommand(function(b) seen[#seen + 1] = b end))

  local stream = { 0x9C, 5, 0xAA, 0x9D, 9, 0xBB }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 4) -- opcode + 1 operand byte + 1 trailing skipped byte
  Harness.assertEqual(seen[1], 5) -- RAW value, not 6

  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 7)
  Harness.assertEqual(seen[2], 9)
end)

Harness.test("StandardScriptHandlers.sceneInitCommand: real opcode 0xC6 consumes exactly its own 1 real operand byte (no extra $3727 skip) and always continues", function()
  local addr = ScriptOpcodeTable.SCENE_INIT_COMMAND_HANDLER_ADDRESS_C6
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC6] = addr }))
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.sceneInitCommand(function(b) seen[#seen + 1] = b end))

  local stream = { 0xC6, 0x2A }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + exactly 1 operand byte
  Harness.assertEqual(seen[1], 0x2A)
end)

Harness.test("StandardScriptHandlers.twoBitFieldCommand: real opcode 0xC7 reads ZERO explicit stream bytes, masks the real value to 2 bits, and consumes exactly 1 byte via $3727", function()
  local addr = ScriptOpcodeTable.TWO_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C7
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC7] = addr }))
  local seen = nil
  interp:registerHandler(addr, StandardScriptHandlers.twoBitFieldCommand(
    function() return 0x17 end, -- deliberately > 3, must get masked
    function(v) seen = v end))

  local stream = { 0xC7, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + 1 real $3727-skipped byte, ZERO explicit operand bytes
  Harness.assertEqual(seen, 0x17 % 4) -- real AND 0x03 mask applied
end)

Harness.test("StandardScriptHandlers.dynamicFlagBitCommand: real opcodes 0xDA/0xDB pass the real operand byte as the bit index and consume exactly 2 real bytes", function()
  local addrSet = ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DA
  local addrClear = ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DB
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xDA] = addrSet, [0xDB] = addrClear }))
  local seen = {}
  interp:registerHandler(addrSet, StandardScriptHandlers.dynamicFlagBitCommand(true, function(b, s) seen[#seen + 1] = { b, s } end))
  interp:registerHandler(addrClear, StandardScriptHandlers.dynamicFlagBitCommand(false, function(b, s) seen[#seen + 1] = { b, s } end))

  local stream = { 0xDA, 0x2C, 0xFF, 0xDB, 0x0B, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 4) -- opcode + bit-index byte + 1 unused padding byte
  Harness.assertEqual(seen[1][1], 0x2C)
  Harness.assertEqual(seen[1][2], true)

  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 7)
  Harness.assertEqual(seen[2][1], 0x0B)
  Harness.assertEqual(seen[2][2], false)
end)

Harness.test("StandardScriptHandlers.bitmaskDispatchCommand: real opcode 0xC2 fires once per real SET bit (0-4) of its operand byte, using the REAL (un-complemented) meaning", function()
  local addr = ScriptOpcodeTable.BITMASK_DISPATCH_COMMAND_HANDLER_ADDRESS_C2
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC2] = addr }))
  local seenBits = {}
  interp:registerHandler(addr, StandardScriptHandlers.bitmaskDispatchCommand(function(b) seenBits[#seenBits + 1] = b end))

  -- 0b00010101 = bits 0, 2, 4 set; bit 5+ irrelevant (only bits 0-4 checked)
  local stream = { 0xC2, 0x15, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 4) -- opcode + 1 operand byte + 1 trailing skipped byte
  Harness.assertEqual(#seenBits, 3)
  Harness.assertEqual(seenBits[1], 0)
  Harness.assertEqual(seenBits[2], 2)
  Harness.assertEqual(seenBits[3], 4)
end)

Harness.test("StandardScriptHandlers.chainedOpaqueEffectCommand: real opcode 0xAF reads ZERO explicit operand bytes and consumes exactly 1 via $3727", function()
  local addr = ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AF
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xAF] = addr }))
  local fired = 0
  interp:registerHandler(addr, StandardScriptHandlers.chainedOpaqueEffectCommand(function() fired = fired + 1 end))

  local stream = { 0xAF, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + 1 real $3727-skipped byte, ZERO explicit operand bytes
  Harness.assertEqual(fired, 1)
end)

Harness.test("StandardScriptHandlers.sixBitFieldCommand: real opcode 0xC5 masks its operand byte to 6 bits and consumes exactly 2 real bytes", function()
  local addr = ScriptOpcodeTable.SIX_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C5
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xC5] = addr }))
  local seen = nil
  interp:registerHandler(addr, StandardScriptHandlers.sixBitFieldCommand(function(v) seen = v end))

  local stream = { 0xC5, 0xFF, 0xAA } -- 0xFF masked to 6 bits = 0x3F
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 4) -- opcode + operand byte + 1 trailing skipped byte
  Harness.assertEqual(seen, 0x3F)
end)

Harness.test("StandardScriptHandlers.actorSlotPositionWithReadinessParam: real opcode 0x79 gates on isReady() WITHOUT consuming its 2 position bytes on halt, param is always offset+1 when ready", function()
  local addr = ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_79
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x79] = addr }))
  local ready = false
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.actorSlotPositionWithReadinessParam(
    0x06, function() return ready end, function(p, b1, b2) seen[#seen + 1] = { p, b1, b2 } end))

  local stream = { 0x79, 10, 20 }
  -- not ready: halts, matching .actorSlotPosition's own real halt
  -- contract -- the 2 position bytes are NOT consumed (real retry
  -- next tick, not a partial read).
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  Harness.assertEqual(#seen, 0)

  ready = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 4) -- opcode + 2 real position bytes, no extra skip
  Harness.assertEqual(seen[1][1], 7) -- ready: param = 1 + 6
  Harness.assertEqual(seen[1][2], 10)
  Harness.assertEqual(seen[1][3], 20)
end)

Harness.test("StandardScriptHandlers.queuedActionWithReadinessParam: real opcode 0x68 gates on isReady(), param is always offset+1 when ready", function()
  local addr = ScriptOpcodeTable.QUEUED_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_68
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0x68] = addr }))
  local ready = false
  local seen = {}
  interp:registerHandler(addr, StandardScriptHandlers.queuedActionWithReadinessParam(
    0x05, function() return ready end, function(p) seen[#seen + 1] = p end))

  local stream = { 0x68 }
  local cursor, _, kind = interp:step(stream, 1)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(cursor, 1)
  Harness.assertEqual(#seen, 0)

  ready = true
  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 2)
  Harness.assertEqual(seen[1], 6) -- param = 1 + 5
end)

Harness.test("StandardScriptHandlers.threeWayFlagBitCommand: real opcode 0xA9 classifies its leaf's real value against 3 real constants and consumes exactly 1 byte", function()
  local addr = ScriptOpcodeTable.THREE_WAY_FLAG_BIT_COMMAND_HANDLER_ADDRESS_A9
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xA9] = addr }))
  local rawValue = 0
  local setCount, clearCount = 0, 0
  interp:registerHandler(addr, StandardScriptHandlers.threeWayFlagBitCommand(
    function() return rawValue end,
    function() setCount = setCount + 1 end,
    function() clearCount = clearCount + 1 end))

  local stream = { 0xA9, 0xFF }
  -- non-matching value (e.g. 0): real "set" branch.
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + 1 real $3727-skipped byte, ZERO explicit operand bytes
  Harness.assertEqual(setCount, 1)
  Harness.assertEqual(clearCount, 0)

  -- each of the 3 real matching constants: "clear" branch.
  for _, v in ipairs({ 0x01, 0x0E, 0x0F }) do
    rawValue = v
    interp:step(stream, 1)
  end
  Harness.assertEqual(clearCount, 3)
  Harness.assertEqual(setCount, 1)
end)

Harness.test("StandardScriptHandlers.fixedWramBitSetSkipCommand: real opcodes 0xA3/0xA5/0xA6 set the real bit and consume exactly 1 byte via $3727 despite no explicit operand", function()
  local addr4 = ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A3
  local addr5 = ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A5
  local addr6 = ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A6
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xA3] = addr4, [0xA5] = addr5, [0xA6] = addr6 }))
  local flags = { byte = 0 }
  interp:registerHandler(addr4, StandardScriptHandlers.fixedWramBitSetSkipCommand(flags, 4))
  interp:registerHandler(addr5, StandardScriptHandlers.fixedWramBitSetSkipCommand(flags, 5))
  interp:registerHandler(addr6, StandardScriptHandlers.fixedWramBitSetSkipCommand(flags, 6))

  local stream = { 0xA3, 0xFF, 0xA5, 0xFF, 0xA6, 0xFF }
  local cursor = interp:step(stream, 1)
  Harness.assertEqual(cursor, 3) -- opcode + 1 real $3727-skipped byte, ZERO explicit operand bytes
  Harness.assertEqual(flags.byte, 16) -- bit 4 set (1 << 4)

  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 5)
  Harness.assertEqual(flags.byte, 16 + 32) -- bit 5 also set (1 << 5)

  cursor = interp:step(stream, cursor)
  Harness.assertEqual(cursor, 7)
  -- all 3 bits accumulated on the SAME shared flags table.
  Harness.assertEqual(flags.byte, 16 + 32 + 64) -- bit 6 also set (1 << 6)
end)
