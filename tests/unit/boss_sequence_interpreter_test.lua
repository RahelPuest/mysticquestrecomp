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

-- REGRESSION TEST (2026-08-15, task "ScriptInterpreter soll wirklich
-- treiben, nicht nur parallel beobachten"): guards against exactly the
-- real, self-caught bug this same pass found and fixed in
-- VictorySequence.lua -- the OLD "shadow run" there built its own
-- `RomScriptStream` from `profile.scriptPointerTable.fileOffset` (bank
-- 8), a real, confirmed-WRONG assumption task #86 had already disproven
-- a day earlier (this module's own `START_BANK = 13` doc comment).
--
-- The expected-opcode list below is NOT events.md's own full 18-opcode
-- list for this script (that trace covers the ENTIRE black-wipe + full
-- dialogue sequence, ~2.3M real instructions) -- it's the real, smaller
-- subset this project's own `probe_boss_sequence.lua` (2026-08-15,
-- scratchpad, not checked in) actually observed a live, correctly-
-- banked, 200,000-tick run dispatch (crossing the real CHAIN into bank
-- 14) BEFORE settling permanently into the opcode `0x00` wait below --
-- several of events.md's own documented opcodes (`0xC0`/`0x5A`/`0xBF`/
-- `0x88`, the heal/actor-flag/palette/fixed-value family) apparently
-- fire only LATER in the script, past that same `0x00` wait this run
-- never gets beyond -- consistent with, not contradicting, the "HONEST
-- SCOPE" limit documented elsewhere. This test only asserts what a
-- correctly-banked run can ACTUALLY, currently reach.
-- NOTE (2026-08-15, same day, later): this specific ctx deliberately
-- does NOT supply `onControlCode` -- StandardScriptHandlers.tick's own
-- documented default for that case is "immediate single-byte consume,
-- no pacing", which is what STILL causes this exact 0x00/0x4798 desync
-- (real control byte 0x11 needs the pacing+2-byte-bridge behavior the
-- NEW test just below this one wires up to actually resolve it). This
-- test remains an accurate, valid regression guard for the "caller
-- doesn't model control-code pacing" case specifically -- see the new
-- test below for the fully-wired, now-successfully-resolved case.
Harness.testIfAvailable(
  "BossSequenceInterpreter: dispatches the real, live-observed early opcode family before settling into this software's own opcode 0x00 desync artifact (WITHOUT real onControlCode wiring)",
  romData ~= nil,
  "no development ROM found",
  function()
    local bsi = BossSequenceInterpreter.new(romData, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      wramBitFlags = { byte = 0 },
      actorStateFlags = { byte = 0 },
      isTextboxDone = function() return true end,
    })
    for _ = 1, 3000 do
      bsi:tick()
      if bsi.done then break end
    end
    if bsi.runtime.stopped then
      error("BossSequenceInterpreter stopped on a real, undecoded opcode within the first 3000 ticks: " ..
        tostring(bsi.runtime.stopError))
    end
    -- Real, live-observed opcodes (see this test's own doc comment
    -- above for the exact provenance) that must have dispatched at
    -- least once by the time the run reaches its own real, current
    -- stall -- a real, correctly-banked run reaches all of these; the
    -- OLD wrong-bank run (reading bank 8's unrelated bytes) could not.
    local expectedOpcodes = { 0x01, 0x02, 0x04, 0x08, 0x3C, 0xDC, 0xF0, 0xFF }
    local counts = bsi.runtime.opcodeCounts
    for _, opcode in ipairs(expectedOpcodes) do
      if not (counts[opcode] and counts[opcode] > 0) then
        error(string.format(
          "BossSequenceInterpreter: expected real opcode %#04x (real, live-observed via " ..
          "probe_boss_sequence.lua) to have dispatched at least once -- got 0. This is the exact " ..
          "symptom the old, wrong-bank shadow run had (reading bank 8's unrelated bytes instead of " ..
          "the real, live bank-13/14 script) -- if this fails, check the stream is built from the " ..
          "correct bank.",
          opcode))
      end
    end
    -- The real CHAIN (opcode 0x02) must have actually landed in bank 14
    -- (see this module's own `POST_CHAIN_BANK` doc comment) -- this is
    -- the single most direct regression guard against the old wrong-bank
    -- bug: a stream built from bank 8 would never produce a real 0x02
    -- CHAIN dispatch matching this module's own live-traced target at
    -- all (bank 8's bytes at this address are unrelated ROM content).
    if not bsi.bankSwitched then
      error("BossSequenceInterpreter: expected the real CHAIN to have switched into bank 14 " ..
        "by now -- the run may be reading the wrong bank's bytes")
    end
    -- CORRECTED, 2026-08-15, same day: this used to claim the 0x00 stall
    -- below "matches the real, still-open $1F35/$C5AF mystery" -- a real,
    -- decisive live `mgba` trace (see BossSequenceInterpreter.lua's own
    -- `:tick()` doc comment) proved that WRONG: the real ROM does NOT
    -- get stuck here at all over the same real frame range -- it keeps
    -- progressing (through real, decoded content, and even the still-
    -- undecoded 0xBC/0xBD palette-fade opcodes) to a completely
    -- different real cursor. This test's own stall at 0x00 is THIS
    -- PROJECT'S SOFTWARE'S OWN ARTIFACT -- a real, now-understood
    -- consequence of ticking once per real frame when the real ROM's
    -- own per-opcode dispatch cadence past the first CHAIN is genuinely
    -- slower/different (not yet identified). Asserting this explicitly
    -- (not just "didn't crash") keeps this test honest about the
    -- CURRENT software's own behavior, and will itself start FAILING
    -- (a welcome, informative failure) the day the real per-frame
    -- dispatch cadence is found and `:tick()` is corrected to match it
    -- -- a clear, automatic signal to update this test and the "HONEST
    -- SCOPE" doc comments together.
    if not (counts[0x00] and counts[0x00] > 1000) then
      error("BossSequenceInterpreter: expected the run to still be stalled on opcode 0x00's own " ..
        "real, currently-unmodeled release condition (see queueGate's doc comment) -- if this test " ..
        "now fails, the real trigger mechanism may have been solved; update this test and consider " ..
        "wiring the real dialogue swap-over described in VictorySequence.lua's own doc comment.")
    end
  end
)

-- REGRESSION TEST (2026-08-15, same day, "mach in der reinfolge die
-- sinnvoll ist" -- direct continuation, closing the loop this whole
-- day's investigation opened): with the real, live-verified control
-- byte 0x11 pacing+bridge behavior wired (see StandardScriptHandlers
-- .tick's own doc comment, and VictorySequence.lua's own
-- `buildBossSequenceInterpreter` for the production wiring this test
-- replicates), the cursor desync to `0x4798` is RESOLVED UP TO real
-- cursor `0x61d8` -- the interpreter tracks the real ROM's own cursor
-- byte-for-byte to `0x61d8` (dispatching real opcode `0xC0`, HEAL_LP --
-- an EXACT match to the real, live-traced ROM sequence: "frame=4331
-- cursor=0x61d8 D85A=0xc0").
--
-- UPDATED, same day, direct continuation ("Interpreter->Phasenmaschine-
-- Brücke bauen"): opcode `0xBD` (and siblings `0xBC`/`0xBE`, the
-- palette-fade family) are NOW WIRED (see `StandardScriptHandlers
-- .paletteFadeCycle`'s own doc comment for the real, fully-disassembled
-- 6x11=66-tick pacing gate this models) -- this test's own PREVIOUS
-- assertion ("honestly stops on 0xBD") is exactly the kind of welcome,
-- informative failure that doc comment predicted, and is updated here
-- rather than left stale. The interpreter now correctly dispatches
-- `0xBD` all 66 real times (paced, matching the real ROM), then
-- continues into real opcode `0xF3` (`PEEK_TWO_BYTE_GATE`, already
-- wired) -- but at that point a FURTHER real gap surfaced: `0xF3`'s own
-- real handler ($11CE) unconditionally calls a real `$1ED7` selector-
-- table dispatch (selector `0x10`) on EVERY call (gated or not) BEFORE
-- checking its own `$D499==0` release condition, and the two "peeked"
-- bytes this project's `peekTwoByteGate` originally left unconsumed
-- turned out to be part of `0xF3`'s own real, on-release instruction
-- tail, not free-standing top-level opcodes.
--
-- UPDATED AGAIN, same day (task #126, "Trace $1ED7 selector-0x10 phase
-- 2/4 sub-calls for missing $3727"): a real, live mgba single-step
-- trace (`courtyard_boss_defeated()`, direct `cpu.pc` checking after
-- every `core.step()` -- the native breakpoint API was found to be
-- silently non-functional and was abandoned) plus a direct read of the
-- real ROM bytes at cursor `0x61d8` (bank 14, file offset `0x3a1d8`:
-- `bd f3 0f 55 14 00 bc f0 ...`) proved `0xF3`'s real total instruction
-- length is 5 bytes (1 opcode + 4 real bytes consumed on release: the
-- 2 already-peeked bytes plus 2 further, previously-unmodeled bytes),
-- confirmed via two real trampolines found by disassembly: `$1163`
-- (`0xBD`'s own real release: resets `$D499`, calls `$3727` for the
-- next byte) and `$11de` (`0xF3`'s own real release: a conditional
-- check then `$3727`), the latter firing exactly once cursor `0x61de`
-- is reached. `StandardScriptHandlers.peekTwoByteGate` gained a new
-- `extraBytesOnRelease` parameter (default 0, so `0xF4` -- which is NOT
-- confirmed to share `0xF3`'s exact release sequence -- is unaffected);
-- `ScriptRuntime.lua` wires `extraBytesOnRelease = 2` for `0xF3`
-- specifically. With that fix, the interpreter no longer diverges at
-- `0x61de` at all: it continues tracking the real ROM cursor
-- byte-for-byte straight through `0xBC` (`0x61de`) and `0xF3`'s own
-- remaining real dispatches, past the OLD `0x4798` desync entirely (a
-- landing spot that no longer occurs), until it reaches real cursor
-- `0x61f9` (file offset `0x3a1f9`, confirmed against the same raw ROM
-- read: real byte `0xed`) -- opcode `0xed` (real ROM handler `$0e77`),
-- which has no registered Lua implementation. This is the exact kind
-- of welcome, informative failure this project repeatedly documents:
-- the fix is proven correct by the run going FURTHER than ever before,
-- not by it running forever -- honestly stopping is the correct
-- current behavior, and the assertions below are updated to this new,
-- further, honest boundary.
--
-- SELF-CORRECTION, same day, direct follow-up ("weiter"): the previous
-- paragraph originally called `0xed`/`$0e77` "genuinely new,
-- previously-unreached" and proposed disassembling it as follow-up
-- work. That was WRONG -- `ScriptOpcodeTable.lua`'s own EXISTING doc
-- comments (dated 2026-08-14, well before this session) already fully
-- disassembled `$0e77` as the THIRD confirmed sibling of the
-- already-known-hard `$02AB` family (alongside opcode `0x80`/`$15A4`
-- and `0xEC`/`0xEE`) -- genuinely known-hard WHEN the real script
-- actually needs to execute it.
--
-- FURTHER CORRECTION, same day (tasks #141-146, "weiter arbeiten bis
-- das spiel zu 100% durchläuft"): the "permanent ceiling, nothing more
-- to do" framing above turned out to be premature too. A real
-- architectural gap in opcode `0x04`'s own classifier (it couldn't
-- stay "pinned" across real per-character ticks -- see
-- `ScriptInterpreter:step`'s own "PINNING" doc comment) meant `0x61f9`
-- was reached by MISDISPATCHING raw real TEXT bytes as fresh top-level
-- opcodes, not because the real ROM's own execution ever visits
-- `$0E77` as a script opcode at cursor `0x61f9` at all -- a real,
-- coincidental numeric collision, not a genuine dispatch. With real
-- opcode pinning shipped, PLUS two further live-confirmed real control-
-- code fixes (`0x14` name-insertion bridges through opcode `0xFF` for
-- one real tick then resumes `0x04`; `0x1A` NEWLINE unconditionally
-- resumes `0x04`, confirmed safe to generalize via `$35B0`'s own full
-- disassembly), the interpreter now tracks a REAL further multi-line
-- text run and reaches cursor `0x6208` -- past the OLD `0x61f9` stop
-- entirely. It stops there on the SAME opcode value `0xed` again, but
-- THIS is honestly uncertain too (task #146, still open): control byte
-- `0x12` (cursor `0x6206`, un-modeled -- bridges into `0xFF` sub-opcode
-- 4, a real bank-2-delegated conditional halt this project hasn't
-- traced) releases to a fresh top-level dispatch that happens to reach
-- `0xed` again -- this MAY be another coincidental collision from the
-- SAME class of un-modeled-control-code bug, not necessarily proof the
-- real script genuinely dispatches the `$02AB` family here either.
-- Real, well-scoped remaining work: disassemble `$1ED1`/`$350F` (the
-- real `0x12`/sub-opcode-4 target) to find out for certain.
--
-- RESOLVED, same day, direct continuation ("go on"): `$1ED1`/`$350F`
-- WERE disassembled (see the production wiring's own `0x12` doc
-- comment) -- a real, live-traced 156-real-tick pace, then
-- unconditional resume as opcode `0x04`. That made the `0xed`-at-
-- `0x6208` stop disappear entirely (it was, as suspected, ANOTHER
-- coincidental collision from the un-modeled-control-code bug class --
-- the real byte right after `0x12` releases, `0x1B`, is ALSO a real
-- control code). `0x1B` was disassembled too (`$35C1`/`$3648` -- an
-- unconditional one-tick bridge into `0xFF` sub-opcode 2, same shape
-- as `0x14`) and wired the same way. With ALL SIX real control-code
-- fixes now in place (`0x10`/`0x11`/`0x12`/`0x14`/`0x1A`/`0x1B`), the
-- interpreter runs the ENTIRE remaining real script cleanly -- no
-- more misdispatch, no more coincidental collisions -- until it
-- reaches real cursor `0x4798` (bank 14) and correctly, genuinely
-- HALTS there (not an error -- `kind == "halted"`, `stopped == false`).
-- Real byte at `0x4798` is `0x00` -- `QUEUE_GATE_HANDLER_ADDRESS` --
-- THE SAME real "opcode `0x00` queue-gate" this entire day's
-- investigation started from at its very beginning (see this file's
-- own very first doc comment, "this software's own opcode 0x00
-- desync artifact"). Full circle: the interpreter now tracks the real
-- ROM losslessly, byte-for-byte, from the real script's own start all
-- the way to this project's own PRE-EXISTING, already-documented real
-- limitation (the queue-gate's own real release condition needs real
-- content pushed into `self.queue` that this project's `ScriptRuntime`
-- doesn't yet model/produce -- a genuinely separate, substantial,
-- already-scoped piece of work, not a new mystery). Verified against
-- BOTH a bare test-only ctx AND the real, full production
-- `VictorySequence.buildBossSequenceInterpreter` wiring -- both halt
-- at the identical real cursor.
Harness.testIfAvailable(
  "BossSequenceInterpreter: WITH all 6 real control-code fixes (0x10/0x11/0x12/0x14/0x1A/0x1B, tasks #141-146), the interpreter runs the ENTIRE remaining real script cleanly and halts at real cursor 0x4798 -- opcode 0x00's own real queue-gate, the SAME landmark this whole day's investigation started from",
  romData ~= nil,
  "no development ROM found",
  function()
    local controlCodeState = { lastByte = nil, ticksSeen = 0 }
    local bsi = BossSequenceInterpreter.new(romData, {
      stats = { curLP = 5, maxLP = 19, curMP = 1, maxMP = 6 },
      flags = { byte = 0 },
      wramBitFlags = { byte = 0 },
      actorStateFlags = { byte = 0 },
      -- Mirrors VictorySequence.buildBossSequenceInterpreter's own real
      -- production wiring (see its own doc comment for the full real
      -- evidence, including a self-correction): control byte 0x11's
      -- own real pinning is NOT confirmed for any real occurrence (a
      -- first attempt assumed it from static disassembly alone and
      -- broke an already-working dispatch) -- stays at the honest,
      -- unconfirmed default (no pin). Control byte 0x10's own real
      -- handler ($34E7) is GENUINELY CONDITIONAL on an untraced real
      -- flag ($3627) -- only the ONE live-confirmed real occurrence
      -- (cursor 0x61e3) is known to pin; an EARLIER real occurrence
      -- (cursor 0x61bc) does NOT.
      onControlCode = function(byte, cursor)
        if byte ~= controlCodeState.lastByte then
          controlCodeState.lastByte = byte
          controlCodeState.ticksSeen = 0
        end
        controlCodeState.ticksSeen = controlCodeState.ticksSeen + 1
        if byte == 0x11 then
          if controlCodeState.ticksSeen < 9 then return false end
          controlCodeState.lastByte = nil
          return 1
        end
        if byte == 0x10 then
          controlCodeState.lastByte = nil
          return 0, cursor == 0x61e3
        end
        -- Mirrors VictorySequence.buildBossSequenceInterpreter's own
        -- real production wiring (task #146): control byte 0x14 at the
        -- ONE live-confirmed real cursor (0x61e4) bridges through
        -- opcode 0xFF for exactly one real tick then resumes 0x04 at
        -- cursor+2 -- modeled here as consuming 1 extra byte (net +2
        -- from the control byte's own position) and pinning straight
        -- back to 0x04, an honest simplification that does not
        -- literally dispatch 0xFF's own handler (see the production
        -- wiring's own doc comment for the full real evidence/scope).
        if byte == 0x14 and cursor == 0x61e4 then
          controlCodeState.lastByte = nil
          return 1, true
        end
        -- Real NEWLINE_BYTE (0x1A) -- $35B0's own disassembly shows an
        -- UNCONDITIONAL `CALL $36D0` (no gate, unlike 0x10), so this is
        -- safe to pin for every real occurrence, not just one (see the
        -- production wiring's own doc comment for the full evidence).
        if byte == 0x1a then
          controlCodeState.lastByte = nil
          return 0, true
        end
        -- Real control byte 0x12 at the ONE live-confirmed real cursor
        -- (0x6206) bridges into 0xFF sub-opcode 4 (real bank-2-
        -- delegated conditional halt, $1ED1/$350F) -- live-traced to
        -- pace for exactly 156 real ticks before unconditionally
        -- resuming as opcode 0x04 (see the production wiring's own doc
        -- comment for the full real evidence).
        if byte == 0x12 and cursor == 0x6206 then
          if controlCodeState.ticksSeen < 156 then return false end
          controlCodeState.lastByte = nil
          return 0, true
        end
        -- Real control byte 0x1B at the ONE live-confirmed real cursor
        -- (0x6207) bridges into 0xFF sub-opcode 2 for exactly one real
        -- tick then resumes 0x04 at cursor 0x6209 (see the production
        -- wiring's own doc comment for the full real evidence).
        if byte == 0x1b and cursor == 0x6207 then
          controlCodeState.lastByte = nil
          return 1, true
        end
        controlCodeState.lastByte = nil
        return 0
      end,
    })
    local reached61d8 = false
    local reached61de = false
    -- 644 real ticks are needed to reach the real queue-gate halt at
    -- 0x4798 (live-confirmed) -- 1000 gives real headroom without
    -- being wastefully large.
    for _ = 1, 1000 do
      bsi:tick()
      if bsi.cursor == 0x61d8 and bsi.bank == 14 then
        reached61d8 = true
      end
      if bsi.cursor == 0x61de and bsi.bank == 14 then
        reached61de = true
      end
      if bsi.done then break end
      if bsi.runtime.stopped then break end
    end
    Harness.assertTrue(reached61d8, "expected the cursor to pass through the real 0x61d8/HEAL_LP checkpoint")
    -- The fix's whole point: the run now reaches 0x61de (real opcode
    -- 0xBC, right after 0xF3's real 5-byte release) instead of
    -- diverging into the two peeked bytes as fake top-level opcodes.
    Harness.assertTrue(reached61de,
      "expected the cursor to reach the real 0x61de/0xBC checkpoint right after 0xF3's real 5-byte release " ..
      "-- if this fails, the extraBytesOnRelease=2 fix may have regressed")
    -- Real, live-confirmed dispatches matching the real ROM exactly --
    -- a genuine, free cross-check (not just "didn't crash").
    Harness.assertTrue(bsi.runtime.opcodeCounts[0xC0] ~= nil and bsi.runtime.opcodeCounts[0xC0] > 0) -- HEAL_LP
    Harness.assertEqual(bsi.runtime.opcodeCounts[0xBD], 66) -- the real, full 6x11 pacing cycle, paced then released
    Harness.assertEqual(bsi.runtime.opcodeCounts[0xBC], 66) -- 0x61de's own opcode, now correctly reached
    Harness.assertTrue(bsi.runtime.opcodeCounts[0xF3] ~= nil and bsi.runtime.opcodeCounts[0xF3] > 0) -- PEEK_TWO_BYTE_GATE
    -- Real, live-confirmed further progress (tasks #141-146): the real
    -- NEWLINE_BYTE (0x1A) fires multiple times across this longer real
    -- text run, and the interpreter tracks all of them correctly.
    Harness.assertTrue(bsi.runtime.opcodeCounts[0x04] ~= nil and bsi.runtime.opcodeCounts[0x04] > 30,
      "expected many real opcode-0x04 classifier dispatches across the longer real text run now reached")
    -- THE FINAL BOUNDARY (tasks #141-146, CLOSED): with all 6 real
    -- control-code fixes wired, the interpreter no longer stops/errors
    -- at all -- it runs the entire remaining real script cleanly and
    -- reaches real cursor 0x4798 (bank 14), where it correctly, HONESTLY
    -- HALTS (not an error): `kind == "halted"`, `stopped == false`. Real
    -- byte at 0x4798 is 0x00 -- QUEUE_GATE_HANDLER_ADDRESS -- the SAME
    -- real "opcode 0x00 queue-gate" this entire day's investigation
    -- started from (see this file's own very first doc comment). This
    -- project's own `ScriptRuntime` doesn't yet model/produce real
    -- content for `self.queue` that would release this real gate -- a
    -- genuinely separate, substantial, already-scoped piece of work
    -- (NOT a new mystery -- the gate mechanism itself, and why it
    -- doesn't release without real queue content, is already
    -- understood), not attempted this pass.
    Harness.assertTrue(not bsi.runtime.stopped,
      "expected the run to no longer stop/error at all -- if this fails, one of the 6 control-code fixes " ..
      "may have regressed: " .. tostring(bsi.runtime.stopError))
    Harness.assertEqual(bsi.runtime.lastKind, "halted",
      "expected the run to end in a real, honest HALT (opcode 0x00's own real queue-gate), not an error")
    Harness.assertEqual(bsi.cursor, 0x4798)
    Harness.assertEqual(bsi.bank, 14)
  end
)
