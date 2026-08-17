-- Real, concrete opcode handler implementations for the few opcodes
-- this project has actually decoded the SEMANTICS of (not just the
-- table entry) -- see docs/reverse-engineering/rom-map.md "THE real
-- event/script interpreter -- FOUND, FULLY DECODED" for each one's own
-- disassembly trace. Register these with `ScriptInterpreter
-- :registerHandler(address, handler)` using the matching
-- `ScriptOpcodeTable.*_HANDLER_ADDRESS` constant.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local ScriptInterpreter = require("src.scripting.ScriptInterpreter")
-- Real, decoded per-byte text/control-code classification (opcode
-- 0x04's own real handler, see `.tick`'s own doc comment below) reuses
-- the SAME real byte->character rules `TextDecoder.lua` already
-- independently reverse-engineered from the static text corpus --
-- one project-wide source of truth for "what does this byte mean as
-- text", not a second, separately-guessed copy. `TextDecoder.lua` has
-- no dependency back on this module (verified -- no circularity).
local TextDecoder = require("src.import.TextDecoder")
-- LuaJIT's `bit` library, not the `|`/`&`/`<<`/`~` infix bitwise
-- operators (Lua 5.3+ syntax) -- CORRECTED, direct consequence of a
-- request to start the interpreter for real: setFlagBit/clearFlagBit
-- originally used those infix operators, which the local luajit CLI in
-- this dev environment tolerates (a newer/patched build), but real
-- LÖVE 11.5's bundled LuaJIT does not -- a live love . launch crashed
-- immediately with a syntax error the first time this module was ever
-- pulled into the app's real require chain (ScriptRuntime.lua, required
-- unconditionally by VictorySequence.lua regardless of the
-- MYSTICQUEST_SCRIPT_INTERPRETER switch -- this bug broke the whole
-- app's boot, not just the interpreter feature, until fixed here).
-- bit.bor/bit.band/bit.bnot/bit.lshift are standard LuaJIT library
-- functions (not language syntax), portable across every LuaJIT build.
local bit = require("bit")

local StandardScriptHandlers = {}

--- Real "display message" handler (opcode 0xFE, ROM `$0E69`):
--   LD A,(HL+)      ; messageID = the next real operand byte
--   CALL $04E2       ; dispatch into the message-settings table
--                      (text.md) -- a SEPARATE, already-decoded
--                      subsystem, not reimplemented inside this
--                      interpreter itself, matching the real ROM's own
--                      separation of concerns
--   CALL $3727        ; fetch the next opcode (the interpreter does
--                       NOT block on a message -- see rom-map.md)
--
-- `onMessage(messageID)` is called with the real messageID byte --
-- what happens next (looking it up via MessageSettingsTable, showing a
-- real dialogue box) is the caller's own responsibility, exactly
-- mirroring the real ROM's own `$04E2` being a distinct call, not
-- inline logic in `$0E69` itself.
function StandardScriptHandlers.message(onMessage)
  return function(stream, cursor)
    local messageID, nextCursor = ScriptInterpreter.fetch(stream, cursor)
    onMessage(messageID)
    return nextCursor
  end
end

--- Real "restore to max" handler family (ROM `$394F`/`$3968`, see
-- rom-map.md for the exact disassembly): no operand bytes, immediately
-- sets `stats[curField] = stats[maxField]`. `stats` is bound at
-- registration time (a real `Stats` instance, or any table with the
-- matching fields) -- e.g. `StandardScriptHandlers.healToMax(stats,
-- "curLP", "maxLP")` for the live-verified LP case, or `"curMP"`/
-- `"maxMP"` for the structurally-identical (but not independently
-- live-verified) MP sibling.
function StandardScriptHandlers.healToMax(stats, curField, maxField)
  return function(_stream, cursor)
    stats[curField] = stats[maxField]
    return cursor
  end
end

--- Real "relative skip" handler (opcode `0x01`, ROM `$32F3`, see
-- events.md's "Every remaining open question, resolved" for the
-- disassembly): `LD E,A(next byte) / D=0 / ADD HL,DE` -- reads ONE
-- real operand byte `n` and advances the cursor `n` FURTHER past it --
-- a genuine "goto forward n bytes" script flow-control primitive, the
-- first one this project has found with a fully pinned, simple,
-- real-world meaning (as opposed to the already-known `[0x12][0x1B]`
-- control-byte pair, which is a fixed jump-to-next-page, not a
-- variable relative skip).
function StandardScriptHandlers.skip()
  return function(stream, cursor)
    local n, nextCursor = ScriptInterpreter.fetch(stream, cursor)
    return nextCursor + n
  end
end

--- Real "chain to next message page" handler (opcode 0x02, ROM $32FE,
-- see events.md's "Opcode 0x00, resolved" for the full disassembly).
-- Reads two operand bytes and jumps the cursor there -- the same shape
-- already known from the [0x12][0x1B] control-byte pair (the "close
-- this box, show the next box" mechanism), reached via its own
-- dedicated opcode instead.
--
-- CORRECTED (continuation of resolving opcode 0x00's WRAM queue -- see
-- ScriptContinuationQueue.lua): a careful re-disassembly found the
-- previous implementation wrong on two counts: the ROM reads the two
-- operand bytes big-endian (byte1*256 + byte2, not little-endian), and
-- always adds an unconditional 0x4000 bank-window offset.
--
-- New side effect the earlier implementation didn't reproduce: the ROM
-- also pushes an entry onto the same WRAM queue opcode 0x00 pops from
-- (CALL $36DF, always with B=2 -- every CHAIN is a "jump away now,
-- remember to come back here" bookmark; a later 0x00 dispatch that
-- pops this entry redirects the cursor back to right after this
-- CHAIN's 2 operand bytes). queue is optional (a caller not yet wiring
-- opcode 0x00 doesn't need one) -- when supplied, pushes via
-- ScriptContinuationQueue:push(true, <cursor after this opcode's 2 bytes>).
--
-- HONEST LIMIT, NARROWED: the ROM computes the queued resume value from
-- a cursor conditionally +0x4000-adjusted first (when the cursor's high
-- byte is <0x80 AND WRAM $D86A reads 0x0E) -- not reproduced here
-- (pushes the un-adjusted cursor always) -- a narrow, flagged gap.
--
-- CORRECTED AGAIN (task #86, direct continuation after a decisive
-- cursor mismatch surfaced by BossSequenceInterpreter's own tests): the
-- earlier claim that the ROM "selects the bank ambiently, not from any
-- formula" compared the raw byte1*256+byte2+0x4000 value against the
-- observed post-CHAIN cursor and found a mismatch -- but CHAIN's real
-- handler ($32FE) doesn't stop there: it unconditionally calls a second
-- routine ($3c4f) that reads the just-committed cursor back out of WRAM
-- and applies a correction, confirmed via fresh disassembly:
--   $3c4f: reads the cursor's high byte H. If H < 0x80: no change. If
--   0x80 <= H < 0xC0: the cursor gets a -0x4000 correction (H -= 0x40)
--   -- the case the real boss-defeat CHAIN actually hits (raw target
--   $a1b2, corrected to the live-observed $61b2). If H >= 0xC0: no
--   change either (a distinct third case, not exercised by this
--   project's known scene). $3c4f also writes a small "which of two
--   adjacent banks" marker (0x0D/0x0E) into WRAM $D86A -- HONEST SCOPE:
--   $D86A's broader ROM-wide purpose isn't understood (possibly
--   specific to whatever banked "chapter" this scene's dialogue lives
--   in) -- only the observable cursor-normalization effect is modeled
--   here, and it's unconditional ROM code that runs on every CHAIN
--   dispatch, not scene-specific.
-- onChainTarget (task #86): optional function(normalizedCursor,
-- bankOffset), fired with the post-correction jump target right before
-- this handler returns it. RomScriptStream is bound to one fixed bank
-- per instance (no way to know which MBC bank a normalized cursor >=
-- $8000 maps into), so a caller following a cross-bank CHAIN can use
-- this to swap which stream it feeds the next ScriptRuntime:step call
-- -- $3c4f's 0x0D/0x0E marker is a hint, not a proven general bank
-- number, so callers should still verify their target bank empirically
-- (see BossSequenceInterpreter). bankOffset (task #81, see below) is 0
-- for the verified $3c4f same-window case; callers ignoring the 2nd
-- argument (every existing caller does) keep working unchanged.
--
-- TASK #81 FOLLOW-UP: the "7 scripts CHAIN to a cursor that overflows
-- the current bank's $4000-$7FFF window" mystery (indices 489/530/703/
-- 879/1141/1324/1325) turned out to be two separate things:
--
-- 1. Script 489's CHAIN (operand 0x53 0x03) was never actually
--    cross-bank -- byte1*256+byte2+0x4000 = 0x9303, which fits in 16
--    bits, so the $3c4f correction resolves it to 0x5303 -- inside the
--    same bank's window. Re-shadow-running from there plays 80 clean
--    steps through 41 distinct opcodes with zero errors -- decisive
--    confirmation this "mystery" simply predated the $3c4f discovery.
--
-- 2. The other 6 residual CHAIN operands are genuinely different:
--    byte1*256+byte2 itself is large enough (>= 0xC000) that +0x4000
--    overflows the 16-bit CPU address space entirely, not just the
--    $3c4f high-byte window. NEW HYPOTHESIS, tested via static
--    analysis (not live-confirmed): apply the same "roll into a later
--    bank" formula ScriptPointerTable.resolve already uses --
--    bankOffset = floor((byte1*256+byte2) / 0x4000), target = 0x4000 +
--    ((byte1*256+byte2) % 0x4000), relative to whatever bank the CHAIN
--    executed from. Re-shadow-running all 6 with this hybrid rule
--    resolved every one into an in-window address with zero errors --
--    but the resulting opcode content is a much weaker confirmation
--    than case 1: several land in long runs of opcode 0x00 (ambiguous
--    -- also this ROM's own unprogrammed-filler byte value elsewhere).
--    CANDIDATE status, not VERIFIED: structurally plausible, but
--    unconfirmed whether real hardware actually does this for CHAIN's
--    operand bytes -- no known live trigger reaches any of these 7
--    scriptPointerTable entries in normal gameplay, so the next step
--    (a live $2100-write watchpoint) still needs finding what, if
--    anything, calls these scripts. See rom-map.md's task #81 entry.
function StandardScriptHandlers.chain(queue, onChainTarget)
  return function(stream, cursor)
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if queue then
      queue:push(true, afterByte2)
    end
    local tableValueLike = byte1 * 256 + byte2
    local rawTarget = tableValueLike + 0x4000
    local target, bankOffset
    if rawTarget <= 0xFFFF then
      -- Real `$3c4f` correction (see doc comment above) -- the high
      -- byte of `rawTarget` is `math.floor(rawTarget / 256)`.
      target = rawTarget
      local highByte = math.floor(target / 256)
      if highByte >= 0x80 and highByte < 0xC0 then
        target = target - 0x4000
      end
      bankOffset = 0
    else
      -- CANDIDATE, not VERIFIED (see doc comment above, task #81):
      -- the operand pair itself overflows the 16-bit CPU address
      -- space -- reuse `ScriptPointerTable.resolve`'s own already-
      -- proven "roll into a later real bank" formula instead.
      bankOffset = math.floor(tableValueLike / 0x4000)
      target = 0x4000 + (tableValueLike % 0x4000)
    end
    if onChainTarget then
      onChainTarget(target, bankOffset)
    end
    return target
  end
end

--- Real "set/clear flag bit" handler pair (opcodes `0xDC`/`0xDD`, ROM
-- `$3B5B`/`$3B66`: `SET 1,(WRAM $D874)` / `RES 1,(WRAM $D874)`, see
-- events.md for the disassembly) -- no operand bytes, sets or clears
-- one bit of a real, shared, multi-bit WRAM state byte (bit 0 of this
-- SAME byte was already separately known, as a real conditional-skip
-- gate read by opcode `0x00`'s own handler). `flags` is a plain table
-- bound at registration time with an integer `.byte` field (the
-- caller's own real or simulated `$D874` shadow) -- `bit` is 0-based,
-- matching the real ROM's own `SET`/`RES` bit-index convention.
function StandardScriptHandlers.setFlagBit(flags, bitIndex)
  return function(_stream, cursor)
    flags.byte = bit.bor(flags.byte, bit.lshift(1, bitIndex))
    return cursor
  end
end

function StandardScriptHandlers.clearFlagBit(flags, bitIndex)
  return function(_stream, cursor)
    flags.byte = bit.band(flags.byte, bit.bnot(bit.lshift(1, bitIndex)))
    return cursor
  end
end

--- Real "set/clear a WRAM status bit, then an opaque per-opcode leaf,
-- always continue" handler pair (opcodes 0xB8/0xB9, ROM $1178/$1186,
-- found via the whole-corpus shadow-run scan -- the single highest-
-- count clean structural match among the top 40 most-blocking
-- undecoded handlers). Verified disassembly: PUSH HL / LD HL,$C3F1 /
-- SET|RES 0,(HL) / CALL <leaf> / POP HL / CALL $3727 / RET -- sets/
-- clears bit 0 of a different WRAM cell than .setFlagBit/.clearFlagBit's
-- own $D874 (kept as its own factory since the address differs and
-- this pair also has a leaf call those don't), then calls a self-
-- contained leaf ($01F4/$0204) before always continuing. HONEST SCOPE:
-- the leaf's effect (writing fixed sound-parameter bytes into $C0AA/
-- $C0AC and toggling bit 1 of a third WRAM cell, $C4D4) is disassembled
-- but not consumed by anything this project currently models --
-- exposed as an opaque onLeaf callback per this project's "interpreter
-- doesn't render, it calls back" convention, same as .tick's own
-- onTick or opcode 0x00's own onIdle.
function StandardScriptHandlers.wramBitCommand(flags, bitIndex, setBit, onLeaf)
  return function(_stream, cursor)
    if setBit then
      flags.byte = bit.bor(flags.byte, bit.lshift(1, bitIndex))
    else
      flags.byte = bit.band(flags.byte, bit.bnot(bit.lshift(1, bitIndex)))
    end
    if onLeaf then onLeaf() end
    return cursor
  end
end

-- Real $36C2 pacing gate: one real game frame per tick, releases every
-- 5th one -- matches this project's own already-VERIFIED 5-frames-per-
-- letter typewriter cadence. Declared here (moved up from just above
-- `.textboxWait` 2026-08-15) since `.tick` now needs it too -- both
-- share the exact same real pacing constant.
local FRAMES_PER_TICK = 5

--- Real "text/control-code classifier" handler (opcode 0x04, ROM
-- $333D) -- see docs/reverse-engineering/events.md's "the $38F6 table
-- decoded" section for the full disassembly trail this implements.
--
-- REWRITTEN, direct continuation ("do it anyway, change the code"):
-- every previous version modeled opcode 0x04 as a simple tick with no
-- per-byte semantics -- disassembly proved that's wrong at a deeper
-- level than timing: $333D is a per-byte text/control-code classifier.
-- LD A,(HL) reads the byte at the current cursor (not (HL+) -- doesn't
-- advance the cursor) and dispatches via threshold comparisons:
--   A == 0x00 (TERMINATOR_BYTE) -- ROM: INC HL / CALL $3727 / RET --
--     skips the terminator and recursively re-dispatches the next
--     opcode within the same instant. This project's interpreter can't
--     recurse inside one handler call -- the next opcode dispatches on
--     the following tick instead, one frame later than true hardware --
--     a small, documented timing simplification that doesn't affect
--     cursor position.
--   0x10 <= A <= 0x1F -- a control code, dispatched through the jump
--     table at $38F6 (bytes 0x16-0x19 are confirmed-unused/reserved
--     slots) -- see events.md for what each of the 12 populated entries
--     does (mode switches, name insertion, cursor moves, bridges into
--     the already-documented "0xFF sub-table" system). onControlCode
--     (byte, cursor) is the caller's hook for whatever per-code
--     behavior it wants to model -- see ScriptRuntime.lua's own doc
--     comment for what this project currently does with it. HONEST
--     SCOPE: the jump table's targets mostly bridge into the "0xFF
--     sub-table" via the $3C74 reschedule primitive, or delegate into
--     still-unfollowed bank-2 code -- this handler consumes exactly
--     the 1 control byte and calls back; it does not reproduce the
--     deeper WRAM side effects those targets perform, since that would
--     need the not-yet-done bank-2 trace.
--   anything else -- a printable text character (must be TextDecoder
--     .decodeByte-recognized -- fails loudly, no silent guess, if it
--     isn't). Paced at the live-confirmed 5-frame cadence
--     (FRAMES_PER_TICK, matching .textboxWait's own cadence -- both
--     opcodes share the identical typewriter mechanism), calling
--     onTick once per pacing tick, then consuming exactly this one
--     byte once released (the classifier re-enters for the next byte
--     on the interpreter's next dispatch, naturally discovering the
--     terminator/control codes/more text as it goes -- no pre-computed
--     text length needed).
--
-- PINNING FIX (task #144/#145, direct continuation of the 0xF3 fix):
-- "the classifier re-enters for the next byte on the next dispatch"
-- above was true in intent but not actually implemented until now -- a
-- live mgba trace (watching writes to the persistent cursor $D8B6/
-- $D8B7, filtered to exclude an unrelated interrupt handler's noise on
-- those same cells) found the ROM keeps WRAM $D85A ("current opcode")
-- pinned at 0x04 across many per-character ticks ($36D0's body
-- advances the cursor and re-arms $D85A=0x04 directly, without ever
-- calling $3727 again) while the cursor keeps moving through raw text
-- bytes underneath it -- the old interpreter architecture always
-- re-read stream[cursor] as a fresh top-level opcode on every tick, so
-- once one character finished, the next raw text byte's numeric value
-- got misdispatched as an unrelated opcode -- "succeeding" for a while
-- purely by coincidence before eventually landing on a genuinely
-- undecoded one and stopping, which looked like (but wasn't) a real
-- content boundary. ScriptInterpreter:step now supports opcode pinning
-- -- the text-character-release path below always returns a second
-- value, true, requesting exactly this: stay dispatched as opcode 0x04
-- for the resulting cursor, regardless of the raw byte sitting there.
-- Live evidence supports pinning unconditionally for text characters
-- (every byte in a live-traced ~74-character run advanced this exact
-- way, confirmed via the same $36D9 PC repeatedly).
--
-- The control-code-release path's own pin comes from onControlCode
-- itself now (see that parameter's updated doc comment below) -- not a
-- blanket default -- because a separate live trace caught this project
-- over-generalizing "control codes always pin": an earlier occurrence's
-- control byte does not stay pinned in the ROM (its target hands off
-- elsewhere) -- only some control codes route through $36D0 (confirmed
-- for 0x10/0x11 so far), others bridge into the 0xFF sub-table or
-- bank-2 code not yet traced. Pinning only what's confirmed per byte
-- value, not one blanket rule, is the discipline this project runs on
-- -- see events.md's task #144/#145 entry for the trace that caught the
-- over-generalization. The terminator case also never pins -- the ROM
-- genuinely hands control back to a fresh top-level dispatch there
-- (confirmed: this is exactly how the classifier lands on a real CHAIN
-- (0x02) opcode once a multi-character text run's terminator is
-- reached). Per-occurrence pacing state, same reasoning as
-- .textboxWait's own doc comment (a shared closure counter would
-- misalign two separate uses of this opcode) -- keyed by the current
-- byte's cursor position, since each byte gets its own 5-frame pacing
-- cycle.
function StandardScriptHandlers.tick(onTick, onControlCode)
  local states = {}
  return function(stream, cursor)
    local byte = stream[cursor]
    assert(byte ~= nil, string.format(
      "StandardScriptHandlers.tick: cursor %s out of stream bounds while classifying a real text/control byte",
      tostring(cursor)))

    if byte == TextDecoder.TERMINATOR_BYTE then
      states[cursor] = nil
      return cursor + 1
    end

    if byte >= 0x10 and byte <= 0x1F then
      -- Live-confirmed refinement (a live mgba trace of WRAM $D853 bit
      -- 7 -- the same "pacing timer active" flag the text-character
      -- branch's 5-frame cadence relies on -- found it set immediately
      -- on entering at least control byte 0x11's classify state, and
      -- cleared only several frames later, exactly when the cursor
      -- finally advances past it). Not every control code is an
      -- instant, single-byte consume -- some genuinely pace first, then
      -- (via the $36D0 bridge already disassembled) advance by more
      -- than 1 byte. onControlCode(byte) contract, extended: returning
      -- a number (0 or more) means "done -- consume 1 control byte plus
      -- this many extra bytes" (0x11's $36D0 bridge needs 1 extra,
      -- matching its INC HL beyond the control byte itself); returning
      -- false/nil means "still pacing, not done yet" -- a halt,
      -- re-dispatched next tick, same shape as the text-character
      -- branch below. A caller that doesn't supply onControlCode keeps
      -- the old, simpler "immediate single-byte consume" behavior
      -- (matches every control code this project hasn't live-traced
      -- yet -- an honest default, not a guess).
      if not onControlCode then
        states[cursor] = nil
        return cursor + 1
      end
      -- onControlCode now receives the cursor too (2nd arg), and may
      -- return a second value, pin (boolean, follow-up to the PINNING
      -- FIX above): true means this specific occurrence's target is
      -- $36D0 (the same bridge the text-character path below always
      -- pins through). The cursor matters, not just the byte value:
      -- full disassembly of $34E7 (control byte 0x10's handler) found a
      -- genuine conditional -- CALL $3627 / CALL Z,$36D0 -- so whether
      -- this byte pins depends on a still-untraced condition, not the
      -- byte value alone (live-confirmed: the same byte value 0x10 pins
      -- at one script position and does not at another, in the same
      -- playthrough). The caller is the right place for this decision
      -- since it has live, per-occurrence evidence -- this generic
      -- classifier can't know on its own (see this function's own doc
      -- comment above for why not every control code pins). Omitting
      -- pin (old callers, or occurrences not yet live-traced) keeps the
      -- honest, safe default: no pin, hand off to a fresh top-level
      -- dispatch.
      local extraBytes, pin = onControlCode(byte, cursor)
      if extraBytes then
        states[cursor] = nil
        return cursor + 1 + extraBytes, pin
      end
      return nil
    end

    assert(TextDecoder.decodeByte(byte) ~= nil, string.format(
      "StandardScriptHandlers.tick: real byte %#04x at the current text-reveal cursor is neither the real " ..
      "terminator (0x00), a real control code (0x10-0x1F), nor a TextDecoder-recognized printable character " ..
      "-- refusing to guess (see docs/reverse-engineering/events.md's \"the $38F6 table decoded\" section)",
      byte))

    local remaining = states[cursor]
    if remaining == nil or remaining <= 0 then
      remaining = FRAMES_PER_TICK
      if onTick then
        onTick()
      end
    end
    remaining = remaining - 1
    if remaining <= 0 then
      states[cursor] = nil
      return cursor + 1, true
    end
    states[cursor] = remaining
    return nil
  end
end

--- Real "0xF0 -> hands off into 0xFF's own sub-opcode 3" wrapper
-- (opcode 0xF0, ROM $3C04, see ScriptOpcodeTable
-- .START_TEXTBOX_WAIT_HANDLER_ADDRESS's own doc comment for the full
-- disassembly). Consumes one operand byte (the ROM uses it, via two
-- undecoded helper calls, to set up WRAM $D84D -- the exact condition
-- sub-opcode 3 tests -- HYPOTHESIS on the precise meaning, same honesty
-- status as textboxWait's own doc comment), then behaves exactly like
-- textboxWait from that point on -- confirmed: the ROM's own $3C74
-- reschedule call at the end of $3C04 is byte-identical to how opcode
-- 0xFF itself reaches sub-opcode 3.
--
-- Per-occurrence state (keyed by the cursor position right after this
-- opcode's byte, one WRAM-$D84D-setup instance per script position) --
-- not a single shared closure counter, so two separate uses of this
-- opcode don't corrupt each other's state. Assumes cursor positions are
-- unique per occurrence within whatever stream this interpreter
-- instance is driving -- true for this project's "one interpreter
-- instance drives one script execution" convention.
function StandardScriptHandlers.startTextboxWait(onTick, isDone)
  local states = {}
  return function(stream, cursor)
    local st = states[cursor]
    if not st then
      local _, afterOperand = ScriptInterpreter.fetch(stream, cursor)
      st = { ticksUntilPace = 0, releaseCursor = afterOperand }
      states[cursor] = st
    end
    if isDone() then
      states[cursor] = nil
      return st.releaseCursor
    end
    if st.ticksUntilPace <= 0 then
      st.ticksUntilPace = FRAMES_PER_TICK
      if onTick then
        onTick()
      end
    end
    st.ticksUntilPace = st.ticksUntilPace - 1
    return nil
  end
end

--- Real "0xFF textbox driver" handler (opcode 0xFF, ROM $38E6 -> an
-- 11-entry sub-table keyed by WRAM $D86B, see ScriptOpcodeTable
-- .SUBTABLE_DISPATCH_HANDLER_ADDRESS's own doc comment for the full
-- evidence trail). No operand bytes.
--
-- HONEST SCOPE: this does not reproduce the ROM's byte-exact $D86B
-- sub-opcode state machine (which of sub-opcodes 1/2/3/4 runs on a
-- given tick, and the exact WRAM condition that flips sub-opcode 3 or
-- 4's own halt) -- that detail isn't pinned down even in this
-- project's own disassembly (events.md marks the 3/4 halt conditions
-- HYPOTHESIS, not VERIFIED). What is verified, and what this
-- implements: the whole {1,2,3,4} family together forms one observable
-- unit -- "pace the reveal forward one tick at a time, at the 5-frame/
-- letter cadence, then release once the box is fully revealed" --
-- confirmed by two independent live traces. Rather than guess at
-- internal sub-opcode transitions, this reproduces that outer,
-- confirmed behavior directly: halt (re-dispatch 0xFF next tick, via
-- ScriptInterpreter's halt support) until isDone() says the current
-- box's reveal is finished, calling onTick once per pacing tick (the
-- same callback opcode 0x04's .tick() handler uses -- the ROM's
-- sub-opcode 1 hands off to the identical typewriter mechanism, so
-- reusing that callback here is the documented hand-off point, not a
-- guess). isDone is the caller's own responsibility (e.g. DialogueBox
-- .lua already tracks its own reveal state) -- this module doesn't
-- track WRAM $D853/$D84D itself, matching this project's "don't
-- reimplement a subsystem that already exists elsewhere" convention.
--
-- Per-occurrence state (keyed by cursor -- see startTextboxWait's own
-- doc comment for why: fixed after a self-caught design flaw -- the
-- original version shared one counter across every use of this opcode
-- for the interpreter's whole lifetime, which would have subtly
-- misaligned pacing across separate textboxes).
function StandardScriptHandlers.textboxWait(onTick, isDone)
  local states = {}
  return function(_stream, cursor)
    if isDone() then
      states[cursor] = nil
      return cursor
    end
    local remaining = states[cursor]
    if remaining == nil or remaining <= 0 then
      remaining = FRAMES_PER_TICK
      if onTick then
        onTick()
      end
    end
    states[cursor] = remaining - 1
    return nil
  end
end

--- Real "sound/timing parameter" handler (opcodes 0xF8/0xF9, ROM
-- $119B/$1194, see ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS's
-- own doc comment for the full disassembly). Consumes one operand byte
-- and calls back with it -- what it means (this project has no real
-- sound emulation, see audio.md) is entirely the caller's business,
-- mirroring .message()'s "interpreter doesn't render, it calls back"
-- shape. Register the same factory at both SOUND_PARAM_1_HANDLER_ADDRESS
-- and SOUND_PARAM_2_HANDLER_ADDRESS with two different callbacks -- the
-- ROM handlers are byte-for-byte independent (0xF8 also caches into 2
-- WRAM cells this project has no reason to shadow), not shared.
function StandardScriptHandlers.soundParam(onParam)
  return function(stream, cursor)
    local value, nextCursor = ScriptInterpreter.fetch(stream, cursor)
    if onParam then
      onParam(value)
    end
    return nextCursor
  end
end

--- Real "trigger fixed event" handler (opcode 0xE0, ROM $0FB4, see
-- ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS's own doc comment
-- for the disassembly). No operand bytes -- immediately calls back,
-- same shape as .tick(). What the event actually does ($235B's own
-- effect) is HYPOTHESIS, not modeled here -- the caller decides.
function StandardScriptHandlers.triggerEvent(onTrigger)
  return function(_stream, cursor)
    if onTrigger then
      onTrigger()
    end
    return cursor
  end
end

--- Real "typewriter cursor command" handler (opcode 0x03, ROM $332F,
-- see ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS's own doc
-- comment for the disassembly). Consumes two operand bytes -- the
-- first is a meaningful command value (calls back with it,
-- onCommand(value)); the second is consumed but its value is never
-- read by the ROM itself (a genuine skip, INC HL, not an omission
-- here) so it's dropped. What the command value does ($36DF's own
-- effect) is HYPOTHESIS -- the caller decides.
--
-- EXTENDED (resolving opcode 0x00's WRAM queue -- see
-- ScriptContinuationQueue.lua): the ROM handler also pushes an entry
-- onto the same queue opcode 0x00 pops from (CALL $36DF, always with
-- B=3) -- confirmed to have no further observable effect on its own
-- (every 0x00 dispatch that pops a B=3 entry just halts, discarding it
-- -- see ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS's own doc
-- comment), but reproduced faithfully anyway since it's confirmed ROM
-- behavior with a real (if inert) effect on the queue's length/
-- ordering. queue is optional, same convention as .chain().
function StandardScriptHandlers.typewriterCommand(onCommand, queue)
  return function(stream, cursor)
    local value, afterValue = ScriptInterpreter.fetch(stream, cursor)
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterValue)
    if queue then
      queue:push(false, afterSkip)
    end
    if onCommand then
      onCommand(value)
    end
    return afterSkip
  end
end

--- Real "actor-ready action" handler (opcodes 0x10/0x11/0x14/0x1B/
-- 0x20/0x25/0x30/0x3A/0x40/0x60/0x70/0x7B, ROM handlers $125C/$1268/
-- $128C/$12C4/$12D0/$130C/$1344/$13A0/$13B8/$14A0/$1514/$157C -- see
-- ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_*'s own doc comment
-- for the full disassembled chain: a family of structurally-identical
-- opcodes, each just passing a different fixed "group" constant). No
-- operand bytes.
--
-- HONEST SCOPE: the gating condition is fully verified (halt while
-- WRAM actor-record #7's state field, $C272, has a high nibble other
-- than 0xD0 -- confirmed by disassembling the dispatch chain down to
-- the bank-3 handler that sets the tested flag). What the action
-- itself does ($4AF9, called once the condition holds) is HYPOTHESIS,
-- not decoded further. isReady() is the caller's own responsibility
-- (this project has no live WRAM actor-record array modeled yet, same
-- honest-scope status as textboxWait's own isDone). onAction(group)
-- fires once, right before continuing, with this opcode's group value
-- -- what to do with it is entirely the caller's business.
--
-- group is normally a fixed constant (true for every opcode this
-- family shares its gate with) -- but EXTENDED (opcodes 0x80/0x85, a
-- different gate reusing this same shape -- see ScriptOpcodeTable
-- .ACTOR_ACTION_HANDLER_ADDRESS_80/_85's own doc comment): those two
-- opcodes compute their group dynamically, live, from a different WRAM
-- actor record's current state (not a compile-time constant baked into
-- the ROM code the way the other 12 opcodes' groups are) -- so group
-- may also be a plain Lua function, called fresh on every release
-- (group()), for exactly that case.
function StandardScriptHandlers.actorAction(group, isReady, onAction)
  return function(_stream, cursor)
    if not isReady() then
      return nil
    end
    local resolvedGroup = (type(group) == "function") and group() or group
    if onAction then
      onAction(resolvedGroup)
    end
    return cursor
  end
end

--- Real "queued action" handler (opcodes `0x38`/`0x78`, real ROM
-- handlers `$138C`/`$155C` -- see `ScriptOpcodeTable
-- .QUEUED_ACTION_HANDLER_ADDRESS_*`'s own doc comment for the
-- disassembled chain). No operand bytes. A real, DIFFERENT halt
-- condition from `actorAction`'s own (found in the SAME investigation
-- pass): halts while ANY of 8 real WRAM bytes at `$C5A0` is nonzero,
-- releasing once they're all zero. Same honest scope as `actorAction`:
-- the real ACTION (`$27E3`, reading a real WRAM table at `$C4E0`) is
-- HYPOTHESIS, not modeled -- `isReady()`/`onAction()` are the caller's
-- own responsibility.
function StandardScriptHandlers.queuedAction(isReady, onAction)
  return function(_stream, cursor)
    if not isReady() then
      return nil
    end
    if onAction then
      onAction()
    end
    return cursor
  end
end

--- Real "actor-slot position command" handler (opcode `0x49`, ROM
-- `$140A` -> `$123E` -> the already-mapped `$1F35` selector `0x0D` ->
-- `$4AF9`, see `ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49`'s
-- own doc comment for the full, byte-for-byte disassembled chain --
-- found 2026-08-13 by a live `ScriptRuntime` shadow run against the real
-- boss-defeat script, which correctly STOPPED here rather than
-- misreading the next bytes, per this project's own "no silent
-- fallbacks" rule).
--
-- Real, VERIFIED structure, genuinely DIFFERENT from every other member
-- of the actor-action/queued-action families this project has decoded
-- so far: this is the FIRST one that consumes real operand bytes (TWO
-- of them) -- every sibling opcode (`0x10`.."0x85`, `0x18`.."0x78`) has
-- zero. Real, VERIFIED ordering: the SAME halt gate the queued-action
-- family shares (`$289B`, ANY of WRAM `$C5A0`-`$C5A7` nonzero) is
-- checked BEFORE the two operand bytes are read (`RET NZ` precedes the
-- first real `LD A,(HL+)`) -- a real halt leaves the cursor pointing at
-- the STILL-UNCONSUMED operand bytes, re-checking the same gate next
-- tick rather than having already read past them. `isReady()` mirrors
-- this exactly: checked BEFORE `ScriptInterpreter.fetch` runs at all.
--
-- HONEST SCOPE: once ready, the real ROM transforms each operand byte
-- via `(n+K)*8` (K=1 for the first, K=2 for the second) before
-- dispatching (through selector `0x0D`'s own real `$C4E0 + index*24`
-- actor-slot lookup) to a further, still-undecoded leaf helper (`$0C99`,
-- then `$0611` -- the SAME real low-level routine selector `0x0B`'s own
-- trampoline calls, a genuine new cross-link found this pass). The `*8`
-- shape is a real, well-evidenced HYPOTHESIS for a tile-to-pixel
-- conversion (GB tiles are 8px) -- i.e. this opcode plausibly sets a
-- real actor slot's on-screen POSITION -- but that is NOT proven by
-- tracing `$0C99`/`$0611` themselves, which remain undecoded. Per this
-- project's own "interpreter doesn't render, it calls back" convention
-- (same as `.message()`/`.soundParam()`), `onSetPosition(byte1, byte2)`
-- fires with the RAW real operand bytes, NOT the `*8`-transformed
-- values -- reproducing the transform here would overstate confidence
-- in a hypothesis this project hasn't independently confirmed.
function StandardScriptHandlers.actorSlotPosition(isReady, onSetPosition)
  return function(stream, cursor)
    if not isReady() then
      return nil
    end
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if onSetPosition then
      onSetPosition(byte1, byte2)
    end
    return afterByte2
  end
end

--- Real "one-shot trigger + dual-gate wait" handler (opcodes `0xFC`/
-- `0xFD`, ROM `$27F9`/`$2820`, see `ScriptOpcodeTable
-- .TRIGGER_EVENT_HANDLER_ADDRESS_FC`/`_FD`'s own doc comment for the
-- full disassembly -- first structurally traced in task #83, wired
-- 2026-08-13 in task #86 after a real live trace resolved the one
-- remaining open question).
--
-- Real, VERIFIED structure: a WRAM latch (`$D499`) gates whether the
-- ONE real operand byte gets consumed at all -- fired exactly once per
-- real "activation" (`getLatch()`/`setLatch(resumeCursor)`), dispatched
-- through `$1F35`'s own selector system via `onFire(operand,
-- selectorGroup)` (this project's own "interpreter doesn't render, it
-- calls back" convention, same as `.message()`). AFTER that
-- (unconditionally, whether or not this dispatch was the one that
-- fired it), checks two more real WRAM gates (`$C8E0`/`$CEE8`) --
-- `RET NZ` on either, matching this whole project's real conditional-
-- halt convention (return `nil`, caller re-dispatches next tick).
-- Once BOTH clear, resets the latch (`getLatch()` returns `false`
-- again) and continues normally.
--
-- `$C8E0` CRACKED 2026-08-16 (task #160, live mGBA read-watchpoints
-- during real combat + full disassembly of bank 0 `$2D57`-`$2E31`,
-- see `rom-map.md`'s "the real graphics-loading mechanism" section):
-- it's the real queue depth of a ROM->VRAM tile-streaming DMA system
-- -- this gate is the real ROM genuinely waiting for pending graphics
-- tile transfers to finish before letting the script continue. This
-- project's own `isGateClear` still correctly defaults to "always
-- ready" (see the HONEST SCOPE note below) -- knowing WHAT the real
-- ROM waits for doesn't change that this project's rendering has no
-- VRAM-transfer latency to wait for in the first place; the value is
-- purely documentary. `$CEE8`'s own real meaning is still untraced.
--
-- HONEST SCOPE, NARROWED (2026-08-13): a live trace of the real post-
-- boss sequence caught a genuine, real `0xFC` dispatch consuming its
-- own operand byte and landing DIRECTLY on the very next real opcode
-- two bytes later (cursor `$625B` -> `$625D`, `0xFD` immediately after)
-- -- i.e. a real case where BOTH gates were already clear on the very
-- first activation, confirming the cursor commits normally when
-- nothing blocks. What real hardware does to the ALREADY-consumed
-- operand byte's own cursor advance on a GENUINE block (gates NOT
-- clear on the first activation) was not independently observed this
-- pass -- `isGateClear` defaults to "always ready" here (same
-- established convention as `.actorAction`/`.actorSlotPosition`'s own
-- `isReady`), which reproduces exactly the real, live-observed case.
-- CORRECTED (2026-08-13, self-caught via this module's own new test):
-- the first version tracked only a boolean "have I fired yet," which
-- loses the real resume position across a genuine halt-then-retry --
-- on a re-dispatch with `isTriggered()` already true, the handler has
-- no way to recover "how far past the operand byte" the FIRST call
-- had already gotten, since a real interpreter halt resets the cursor
-- PARAMETER back to right after the opcode byte (pointing AT the
-- operand again, not past it) every retry. Fixed by having the latch
-- itself carry the real resume CURSOR (or `false` when not yet
-- fired), not just a bare boolean -- `getLatch()`/`setLatch(cursor)`.
function StandardScriptHandlers.oneShotTriggerGate(selectorGroup, getLatch, setLatch, isGateClear, onFire)
  return function(stream, cursor)
    local nextCursor = getLatch()
    if not nextCursor then
      local operand, afterOperand = ScriptInterpreter.fetch(stream, cursor)
      if onFire then
        onFire(operand, selectorGroup)
      end
      nextCursor = afterOperand
      setLatch(nextCursor)
    end
    if isGateClear and not isGateClear() then
      return nil
    end
    setLatch(false)
    return nextCursor
  end
end

--- Real "wait for the dual WRAM gate, then an opaque leaf, always
-- continue" handler (opcodes `0xE8`/`0xE9`, ROM `$0F5A`/`$0F71`,
-- CLOSED 2026-08-14 -- this project's own `ScriptOpcodeTable.lua` had
-- already flagged these as "structurally traced, real CONDITIONAL
-- HALT found, NOT wired... condition not characterized" pending the
-- `$1ED7` dispatcher this session separately fully mapped while
-- tracing the real cut-transition tile-coordinate mechanism).
--
-- Real, VERIFIED chain: both opcodes call TWO real `$1ED7`-selector
-- trampolines in sequence -- `$0232` (always selector `1`, real
-- target `$48BE`) unconditionally first, then `$049E`/`$0F71`'s own
-- sibling (selector `0x18`, real target `$44D8`) -- whose OWN return
-- value is what the outer `CP 0x00 / RET NZ` actually tests. `$48BE`
-- turns out to be the SAME real routine this project already traced
-- (and initially misread as a room-transition wipe before self-
-- correcting) while investigating the thirdRoom->fourthRoom cut --
-- the real VRAM tile-PATTERN rewrite subsystem. `$44D8`'s own first 2
-- real instructions, byte-for-byte, are the EXACT SAME dual-WRAM gate
-- (`$C8E0`/`$CEE8`, `RET NZ` on either) already modeled by
-- `.oneShotTriggerGate` for opcodes `0xFC`/`0xFD` -- confirmed by
-- direct comparison, not assumed to match (see that handler's own doc
-- comment for `$C8E0`'s now-CRACKED real meaning, task #160: the real
-- ROM->VRAM tile-streaming DMA queue's own depth counter). Once BOTH
-- real gates clear,
-- the real leaf goes on to do the real VRAM tile-pattern update itself
-- (branching on the opcode's own literal `case` parameter, `4` for
-- `0xE8` vs `8` for `0xE9`, real bytes `0x0F5A`/`$0F71`).
--
-- HONEST SCOPE: this project's own rendering pipeline draws via pre-
-- decoded sprite/tile assets, not a simulated raw VRAM tile-pattern
-- buffer, so the real leaf's own effect is exposed as an opaque
-- `onLeaf()` callback rather than reimplemented -- same "interpreter
-- doesn't render, it calls back" convention as every other opaque
-- leaf in this file. No operand bytes.
function StandardScriptHandlers.dualGateLeafCommand(isGateClear, onLeaf)
  return function(_stream, cursor)
    if isGateClear and not isGateClear() then
      return nil
    end
    if onLeaf then onLeaf() end
    return cursor
  end
end

--- Real "zero-terminated flag-test list" handler (opcode `0x08`, ROM
-- `$3370`, see `ScriptOpcodeTable.ACTOR_FLAG_LIST_HANDLER_ADDRESS`'s
-- own doc comment) -- structurally traced in task #83, its real
-- per-item leaf (`$35EF`/`$3602`) fully live-confirmed the same day,
-- and its real "list exhausted" continuation FINALLY pinned down live
-- in task #86 (2026-08-13, direct instruction "weiter machen, das muss
-- stehen").
--
-- Real, VERIFIED structure: reads a zero-terminated byte list from the
-- script stream. Each NONZERO byte is a real "flag index" -- calls the
-- opaque `onFlagTest(byte)` leaf (this project's own "interpreter
-- doesn't render, it calls back" convention, matching `$35EF`'s own
-- real Z/NZ-returning shape) to decide which of TWO real, structurally
-- DIFFERENT continuations happens next:
--   Z (`onFlagTest` returns true): loops back and reads the NEXT list
--     byte normally (the common per-item case).
--   NZ (`onFlagTest` returns false -- the DEFAULT, matching the ONE
--     real, live-confirmed case this project has actually observed:
--     input byte `0x08` during the real boss-defeat sequence): a
--     ONE-WAY exit -- scans raw bytes (no further flag tests, no real
--     `$D85A` writes along the way) until a real zero terminator, then
--     FORCES the interpreter's own "current opcode" cell to `0x01`
--     WITHOUT a normal fetch (the real `$D85A` direct-overwrite trick).
-- An IMMEDIATELY zero first byte (empty list) is a THIRD, simpler real
-- case (`$338B`): consumes the terminator and skips ONE MORE real byte
-- (a real, confirmed `INC HL`) before continuing normally -- NOT the
-- same as the NZ-path's own forced-opcode-1 trick.
--
-- HONEST SCOPE, CORRECTED (2026-08-13, live single-stepped via this
-- session's own `trace_08_singlestep.py`, direct follow-up to "das
-- muss stehen"): an EARLIER pass here (see events.md's "task #82"
-- section) guessed the real forced-opcode-1 continuation was "a real
-- WRAM block-clear loop over ~20 bytes at $C480" -- that guess is
-- WRONG, decisively disproven this pass by two independent checks:
-- (1) the forced dispatch does NOT reach `$32F3`
-- (`SKIP_HANDLER_ADDRESS`'s own real, independently-verified code) --
-- `$32F3`'s own formula (cursor-after-operand + unsigned operand)
-- predicts cursor `$4803` for the real boss-sequence's own live case,
-- but the real next script-level dispatch lands at `$472a` instead, a
-- real, decisive mismatch; (2) single-stepping the REAL CPU from the
-- forced write onward shows execution actually LEAVING `$3370`'s own
-- bank entirely -- through `$3274`-`$327d` (bank 13), `$2a0a`-`$2a16`
-- (bank 13, ends with a REAL MBC bank switch to bank 1), then
-- `$3280`-`$49ac`-`$1fc2`+ (bank 1, resembling the ALREADY-documented
-- `$1F35` cross-bank selector dispatcher used elsewhere in this
-- project), landing around `$043b` before eventually returning to
-- real script-level dispatch. This is a genuinely deep, cross-bank
-- subsystem -- NOT a simple WRAM clear, and NOT chased to a full
-- understanding this pass (diminishing returns against this project's
-- current, narrower goal: making ONE specific real scene's dispatch
-- sequence work, not a general theory of opcode `0x01`-when-forced).
-- `onExhausted(cursorAfterTerminator)` is exposed as an OPAQUE,
-- REQUIRED-in-practice callback for this real leaf effect (asserts
-- loudly if missing and actually reached, per this project's own "no
-- silent fallbacks" rule) -- callers without real, live-verified
-- knowledge of where it lands should NOT guess; `BossSequenceInterpreter`
-- supplies the real, empirically-traced continuation for its own known
-- occurrence(s) rather than reusing `.skip()`'s own (proven-wrong-here)
-- formula.
function StandardScriptHandlers.zeroTerminatedFlagList(onFlagTest, onExhausted)
  return function(stream, cursor)
    while true do
      local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
      if byte == 0 then
        -- `$338B`: immediately-empty list -- consumes the terminator,
        -- skips ONE more real byte (`INC HL`), then continues normally
        -- (no forced-opcode trick on this path).
        return afterByte + 1
      end
      local isZero = onFlagTest ~= nil and onFlagTest(byte) or false
      if isZero then
        cursor = afterByte -- loop back: re-fetch a fresh loop-test byte
      else
        -- `$337D`: NZ -- scan raw bytes for the real zero terminator
        -- (no further flag tests, no `$D85A` writes along the way).
        local scanCursor = afterByte
        while true do
          local b2, afterB2 = ScriptInterpreter.fetch(stream, scanCursor)
          if b2 == 0 then
            -- `$3381`+: real "force next opcode to 1" trick -- see this
            -- function's own doc comment for the honest, corrected
            -- scope of what happens next.
            assert(onExhausted, "StandardScriptHandlers.zeroTerminatedFlagList: " ..
              "hit the real NZ exit with no onExhausted callback -- " ..
              "guessing this continuation is KNOWN to be wrong (see doc comment)")
            return onExhausted(afterB2)
          end
          scanCursor = afterB2
        end
      end
    end
  end
end

--- Real "adjust 3 fixed WRAM timer/cooldown arrays, then a zero-
-- terminated list-search against ONE of them" handler pair (opcodes
-- `0x09`/`0x0A`, ROM `$3390`/`$33B0`, CLOSED 2026-08-14 -- direct
-- follow-up disassembling `$33CF`/`$3411`/`$3430`/`$343F`, the real
-- shared open question ("what does `$33CF` do with this WRAM-queued
-- pointer+type pair") this project's own docs had left unresolved
-- since an earlier session, and this session's own top remaining
-- combined blocker on the whole-corpus scan, 72 real scripts).
--
-- Real, VERIFIED structure: BOTH opcodes unconditionally INCREMENT 3
-- real fixed WRAM byte arrays (`$D6E9` x6, `$D6DD` x12, `$D6C5` x16)
-- by fixed amounts (`0x41`/`0x41`/`0x08`), skipping any byte already
-- `0x80` (a real "maxed out" sentinel) or already `0` -- via `$33CF`
-- calling `$343F` three times -- THEN unconditionally DECREMENT the
-- SAME 3 arrays by the SAME amounts (`$3411`/`$3430`, the exact
-- mirror of `$343F`) -- THEN read a real zero-terminated list of bytes
-- DIRECTLY FROM THE SCRIPT STREAM, searching each (masked `0x7F`)
-- against ONE target array: `0x09`'s own list searches the 6-byte
-- `$D6E9` array with a real loop bound of 7 (`$D870=0x07`); `0x0A`'s
-- own list searches the 16-byte `$D6C5` array with a real loop bound
-- of 43 (`$D870=0x2B`).
--
-- STRUCTURALLY IDENTICAL, byte-for-byte, to opcode `0x08`'s own
-- `.zeroTerminatedFlagList` (the SAME real "immediately-empty list"
-- leaf, the SAME real "force `$D85A=1`" exit the moment one list byte
-- ISN'T found in the target array, the SAME terminator handling) --
-- confirmed by direct comparison, not assumed: `found in the array`
-- maps to `.zeroTerminatedFlagList`'s own `isZero`/loop-back case,
-- `not found` maps to its own NZ/exhausted case. Reuses that exact
-- factory for the list-search half, prefixed with the real
-- (increment, then decrement) side effect `0x08` itself doesn't have.
--
-- HONEST SCOPE: this project has no simulated model of the 3 real
-- WRAM timer arrays (plausibly a per-item cooldown/status-effect
-- countdown table -- HYPOTHESIS, not confirmed) -- `onAdjustTimers`
-- is an opaque, optional callback for the real increment-then-
-- decrement pair, which (taken together, every real dispatch) are a
-- real NO-OP on the arrays' own FINAL values UNLESS a byte hits the
-- `0x80`/`0` skip-sentinel boundary during the increment half,
-- preventing the decrement from perfectly reversing it -- HYPOTHESIS:
-- the real, useful side effect is plausibly THAT boundary-clamping
-- behavior, not the arithmetic itself; not confirmed further.
-- `onFlagTest`/`onExhausted` follow the EXACT SAME "REQUIRED in
-- practice, no guessing" contract `.zeroTerminatedFlagList` already
-- documents for `0x08` -- this project does NOT assume the same real
-- continuation address applies here without independent live
-- confirmation, even though the static shape is identical.
function StandardScriptHandlers.timerListSearch(onAdjustTimers, onFlagTest, onExhausted)
  local search = StandardScriptHandlers.zeroTerminatedFlagList(onFlagTest, onExhausted)
  return function(stream, cursor)
    if onAdjustTimers then onAdjustTimers() end
    return search(stream, cursor)
  end
end

--- Real "search an IN-LINE list embedded in the script stream itself
-- for an entry matching an external WRAM byte, then skip past it"
-- handler pair (opcodes `0x0B`/`0x0C`, ROM `$344E`/`$345B`, CLOSED
-- 2026-08-14, direct follow-up to the `0x09`/`0x0A` pass -- this
-- session's own next-largest combined blocker, 71 real scripts).
--
-- Real, VERIFIED structure -- genuinely DIFFERENT from every other
-- "zero-terminated list" shape this project has already decoded
-- (`0x08`, `0x09`/`0x0A`): the list being searched is NOT a fixed WRAM
-- array, and NOT a list of single bytes -- it's a real sequence of
-- `[idByte, payload byte(s)..., 0 terminator]` ENTRIES living directly
-- IN THE SCRIPT STREAM at the current cursor. Both opcodes read the
-- SAME 2 real WRAM cells first (`C = *($D871)`, the real byte to
-- search for; bit 7 of `*($D873)`, a real gate) but with OPPOSITE
-- polarity: `0x0B` only performs the search when bit 7 is CLEAR,
-- `0x0C` only when it's SET -- when the gate doesn't match, both
-- skip straight to the same "scan to the next real 0, then force
-- `$D85A=1`" leaf `0x08`'s own NZ-exit and `0x09`/`0x0A`'s own
-- not-found exit ALSO use (same real opcode-1-forcing trick, a
-- different address each time but the same technique). When the gate
-- DOES allow a search: reads one script byte at a time -- a real `0`
-- before any match means "not found," same force-opcode-1 exit;
-- `CP C` matching means found -- skips forward past that entry's own
-- remaining nonzero payload bytes, then ONE more (the real terminator
-- byte itself, via `INC HL`), then continues normally.
--
-- HONEST SCOPE: this project has no simulated model of the real WRAM
-- cells `$D871`/`$D873` -- `matchByte`/`isGateSet` are REQUIRED
-- callbacks (asserts loudly if reached without them, same "no silent
-- fallbacks" rule as everywhere else) rather than defaulted, since
-- there is no real "safe default" for a byte comparison the way
-- "always ready"/"always clear" is for a halt gate. `onExhausted`
-- follows the EXACT SAME "REQUIRED in practice, no guessing" contract
-- already established for `0x08`/`0x09`/`0x0A` -- this project does
-- NOT assume the same real continuation address applies here without
-- independent live confirmation, even though it's reached via the
-- same real `$D85A`-force-1 technique.
function StandardScriptHandlers.runListSearch(searchWhenGateSet, matchByte, isGateSet, onExhausted)
  return function(stream, cursor)
    assert(matchByte, "StandardScriptHandlers.runListSearch: matchByte is required -- " ..
      "this project has no simulated model of real WRAM $D871 to default it")
    assert(isGateSet, "StandardScriptHandlers.runListSearch: isGateSet is required -- " ..
      "this project has no simulated model of real WRAM $D873 bit 7 to default it")

    local function exhaust(afterZero)
      assert(onExhausted, "StandardScriptHandlers.runListSearch: " ..
        "hit the real 'not found' exit with no onExhausted callback -- " ..
        "guessing this continuation would be a real, unverified guess")
      return onExhausted(afterZero)
    end

    if isGateSet() ~= searchWhenGateSet then
      -- Real `$3476`: the gate itself blocks the search -- scan
      -- forward (consuming arbitrary bytes) for the first real
      -- terminator, THEN exhaust. This is the ONLY real path that
      -- scans past more than one byte before finding a zero.
      local scanCursor = cursor
      while true do
        local b, afterB = ScriptInterpreter.fetch(stream, scanCursor)
        if b == 0 then
          return exhaust(afterB)
        end
        scanCursor = afterB
      end
    end

    local c = matchByte()
    while true do
      local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
      if byte == 0 then
        -- Real `$3466`'s own direct "AND A / JR Z,$347A" -- a zero
        -- fetched DURING the search itself exhausts IMMEDIATELY, no
        -- further scanning (unlike the gate-blocked path above).
        return exhaust(afterByte)
      end
      if byte == c then
        -- Found: skip forward past the REST of the real flat list
        -- (any further nonzero candidate bytes), then the real
        -- terminator, then continue.
        local scanCursor = afterByte
        while true do
          local b2, afterB2 = ScriptInterpreter.fetch(stream, scanCursor)
          if b2 == 0 then
            return afterB2 + 1
          end
          scanCursor = afterB2
        end
      end
      cursor = afterByte -- no match yet -- keep scanning the SAME flat list
    end
  end
end

--- Real "script continuation queue gate" handler (opcode `0x00`, ROM
-- `$3297`, see `ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS`'s own
-- doc comment for the complete, byte-for-byte disassembly -- this
-- session's own "löse 1" investigation, resolving what was, by a wide
-- margin, the single largest remaining blocker found by this
-- project's own opcode-frequency scan: 275 of 1357 real scripts).
-- No operand bytes.
--
-- Real, VERIFIED structure (unlike the actor-flag/state family, where
-- only the halt CONDITION was pinned down, here the entire real flow
-- -- both halt conditions AND the release/redirect mechanism -- is
-- fully understood, traced down to a real, shared WRAM FIFO with two
-- confirmed producers, see `ScriptContinuationQueue.lua`):
--   1. `isBlocked()`: real WRAM flag byte (`$D874`), bit 0 -- halts
--      while true. RETRACTED 2026-08-14, same day (task #86, re-
--      verified with a DIRECT `$D874` watchpoint instead of the
--      earlier indirect inference): the "actor-command queue"
--      explanation above does NOT hold -- bit 0 never changes at all
--      across a real, reproduced ~200,000-step boss-defeat block, and
--      the `$C5A0` table it was said to depend on stays all-zero the
--      entire time. **CLOSED FOR REAL, same day**: the boss-defeat
--      block isn't `isBlocked()`/halt-#1 at all -- it's a completely
--      SEPARATE mechanism overwriting the persistent script cursor
--      out from under this handler. A periodic `$1F35` selector `0x13`
--      tick (`$4BE0`) reports "ready" only on the specific tick a real
--      classified-actor count (cached at `$C5AF`) edge-transitions
--      from nonzero to exactly 0 (i.e. the boss's own entity slot has
--      genuinely finished despawning) -- live-confirmed directly
--      (`$C5AF` sits at `0x01` for the whole block, flips to `0x00`
--      right before release). That gates a facing-driven dispatch
--      (`$24A7`, reading the player's own current facing nibble) into
--      `$31AD` (this project's own already-understood cross-actor
--      dispatch, task #85), which redirects the persistent cursor
--      directly. **Practical implication for THIS handler**:
--      `isBlocked` still models a real ROM mechanism (bit 0 of `$D874`
--      is real and genuinely gates SOMETHING, just not this specific
--      delay) -- but the boss-defeat-style "wait for an entity to
--      finish despawning" pattern is a DIFFERENT real mechanism this
--      handler does not model at all (it would need to live outside
--      the queue entirely, as a cursor-redirect trigger). See
--      `ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS`'s own doc
--      comment and events.md's dated entries for the complete,
--      live-verified trace.
--   2. else if `queue:isEmpty()`: halts, optionally calling `onIdle`
--      (the real ROM ALSO does a `$D86E`->`$C0A0` WRAM copy and clears
--      a few bits of `$C0A1`/`$C0A2` here -- exposed only as this
--      optional callback, still not modeled by any real caller of this
--      module. CONFIRMED live, not just HYPOTHESIS, 2026-08-15 (task
--      #147): the real code right before `$31AD` does exactly `LD
--      HL,$C0A1 / SET 3,(HL) / LD HL,$C0A2 / SET 3,(HL) / RET` on this
--      path, live-observed clobbering `$D8B6`/`$D8B7` (this project's
--      own "persistent cursor" cells) with `0xC0A2` in the process --
--      i.e. those cells do NOT hold a meaningful resume cursor while a
--      script is genuinely idle. Task #147 ALSO found, live, that real
--      further progress past this genuine halt does NOT come from
--      `self.queue` gaining new content at all -- it comes from the
--      SAME already-understood `$31AD` cross-actor dispatcher (tasks
--      #85/#111) firing again for a DIFFERENT real trigger and
--      overwriting `$D8B6`/`$D8B7` with a fresh script entry point,
--      completely independent of this handler/queue. See events.md's
--      2026-08-15 "task #147" entry for the full live trace and the
--      new, correctly-scoped follow-up (task #149).
--   3. else: pops one real entry. If it was a real `B==2` entry (only
--      opcode `0x02` CHAIN ever pushes one), redirects the persistent
--      cursor there and continues. Any other real entry (only opcode
--      `0x03` is a confirmed producer, always `B==3`) just halts,
--      consumed.
-- `isBlocked` and `onIdle` are the caller's own responsibility (no
-- live WRAM flag-byte state modeled yet, same honest-scope pattern as
-- `actorAction`'s own `isReady`). `queue` is REQUIRED (unlike
-- `.chain()`/`.typewriterCommand()`'s own optional queue -- this
-- handler's entire real purpose is consuming it, so a caller without
-- one hasn't actually wired opcode `0x00` meaningfully).
function StandardScriptHandlers.queueGate(queue, isBlocked, onIdle)
  assert(queue, "StandardScriptHandlers.queueGate requires a real ScriptContinuationQueue -- " ..
    "this handler's entire real purpose is consuming it")
  return function(_stream, cursor)
    if isBlocked and isBlocked() then
      return nil -- real halt #1: WRAM flag bit 0 set
    end
    if queue:isEmpty() then
      if onIdle then
        onIdle()
      end
      return nil -- real halt #2: queue empty
    end
    local shouldRedirect, resumeCursor = queue:pop()
    if shouldRedirect then
      return resumeCursor -- real release: popped B==2, redirect + continue
    end
    return nil -- real halt #3/#4: popped B==3 (or any other value), consumed
  end
end

--- Real "byte + word command" handler (opcode `0xB0`, ROM `$0F1E`, see
-- `ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS`'s own doc
-- comment for the disassembly). Consumes THREE real operand bytes: one
-- plain byte, then a real 16-bit LITTLE-endian word (unlike `.chain()`,
-- which reads its own word big-endian via a real byte-swap trick this
-- opcode's handler doesn't use). Always continues -- no real
-- conditional branch anywhere in this opcode's own routine.
-- `onCommand(byteValue, wordValue)` fires once; what the real `$2400`
-- helper actually does with them is HYPOTHESIS.
function StandardScriptHandlers.byteWordCommand(onCommand)
  return function(stream, cursor)
    local byteValue, afterByte = ScriptInterpreter.fetch(stream, cursor)
    local lo, afterLo = ScriptInterpreter.fetch(stream, afterByte)
    local hi, afterHi = ScriptInterpreter.fetch(stream, afterLo)
    if onCommand then
      onCommand(byteValue, lo + hi * 256)
    end
    return afterHi
  end
end

--- Real "word command" handler (opcode `0xD0`, ROM `$3A4F`, see
-- `ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS`'s own doc comment
-- for the disassembly). Consumes TWO real operand bytes -- a real
-- 16-bit LITTLE-endian word. Always continues -- no real conditional
-- branch anywhere in this opcode's own routine (the real WRAM-counter
-- clamp-at-`0xFFFF` logic is internal bookkeeping this project doesn't
-- reproduce). `onCommand(wordValue)` fires once; what the real WRAM
-- counter (`$D7BE`/`$D7BF`) represents is HYPOTHESIS.
function StandardScriptHandlers.wordCommand(onCommand)
  return function(stream, cursor)
    local lo, afterLo = ScriptInterpreter.fetch(stream, cursor)
    local hi, afterHi = ScriptInterpreter.fetch(stream, afterLo)
    if onCommand then
      onCommand(lo + hi * 256)
    end
    return afterHi
  end
end

--- Real "two-byte command" handler (opcode `0xF6`, ROM `$3CA2`, see
-- `ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS`'s own doc
-- comment for the disassembly). Consumes TWO real operand bytes, kept
-- SEPARATE (unlike `.wordCommand()`, the real ROM copies each one to
-- its own, different WRAM cell -- NOT combined into a 16-bit value).
-- Always continues. `onCommand(byte1, byte2)` fires once; the real
-- routine's own many WRAM writes (a plausible "start a new textbox/
-- scene" initializer) are HYPOTHESIS, not reproduced here.
function StandardScriptHandlers.twoByteCommand(onCommand)
  return function(stream, cursor)
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if onCommand then
      onCommand(byte1, byte2)
    end
    return afterByte2
  end
end

--- Real "gated single-byte leaf command" handler family (opcodes
-- `0xD4`/`0xD6`/`0xD8`, ROM `$3AA8`/`$3ABA`/`$3ACC`, found live
-- 2026-08-13 task #86 against `BossSequenceInterpreter` itself) --
-- reads ONE real operand byte, INCREMENTS it (`INC A`), and passes the
-- result to an opaque per-opcode leaf routine (`$30C3`/`$30C9`/`$30CF`,
-- spaced 6 bytes apart, byte-for-byte identical calling shape --
-- untraced leaves, this project's own "interpreter doesn't render, it
-- calls back" convention). Afterward, ALWAYS checks a real, SHARED
-- WRAM flag (`$D86F` bit 1) -- when CLEAR (the common case, matching
-- every real occurrence this project has actually observed live so
-- far), continues normally.
--
-- HONEST SCOPE: when that flag is SET, real hardware runs a further,
-- genuinely deep sequence (`$3ADE`: sets WRAM `$D84A`=6, calls two
-- MORE untraced leaves `$3BEF`/`$3627`, then conditionally halts based
-- on `$3627`'s own real return flags) that this project does NOT
-- reproduce -- not live-observed to actually fire for this scene, and
-- guessing at it risks a genuine cursor-desync bug (the same reasoning
-- already applied to `.oneShotTriggerGate`'s own dual-gate check).
-- Conservatively HALTS (returns `nil`) instead, matching this
-- project's "no silent fallbacks" rule -- a caller that later finds
-- this path DOES fire for a real scene should trace `$3ADE` properly
-- rather than rely on this halt. `isFadeActive` defaults to "never
-- active" (the happy path), same convention as `isActorReady`/
-- `isGateClear` elsewhere in this project.
function StandardScriptHandlers.gatedByteLeafCommand(onByte, isFadeActive)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onByte then
      onByte(byte + 1)
    end
    if isFadeActive and isFadeActive() then
      return nil -- HONEST SCOPE: the real $3ADE path isn't modeled yet
    end
    return afterByte
  end
end

--- Real "peek-two-bytes gate" handler pair (opcodes `0xF3`/`0xF4`, ROM
-- `$11CE`/`$11B7`, found live 2026-08-13 task #86). Real, VERIFIED
-- structure, decoded carefully instruction-by-instruction (the SM83
-- byte sequence here is genuinely unusual, so this is spelled out in
-- full): `LD A,(HL+) / LD B,A` reads byte1 into B, advancing HL by 1;
-- `LD A,(HL-) / LD C,A` then reads byte2 (the NEXT byte) into C but
-- immediately DECREMENTS HL back -- net effect, HL ends up back at
-- its OWN STARTING position (byte1's own address) despite having read
-- 2 bytes. Calls an opaque per-opcode leaf with `BC` (`$11C8` for
-- `0xF4`, `$11DF` for `0xF3`), then checks a real, SHARED WRAM cell
-- (`$D499` -- the SAME cell `.oneShotTriggerGate` also uses for
-- `0xFC`/`0xFD`, though this project does not claim a further
-- relationship beyond sharing the address): while nonzero, `RET NZ`
-- real-halts (this project's usual "return nil, caller retries next
-- tick" convention) -- and since NOTHING advanced the cursor, a retry
-- re-peeks the exact same 2 bytes. Once `$D499` reads zero, falls
-- through to `CALL $3727 / RET` -- continuing from the SAME starting
-- cursor (the 2 peeked bytes are NEVER actually consumed; the next
-- real dispatch re-reads THIS SAME position as a fresh opcode). This
-- is a real, deliberate "wait for a WRAM gate, then let the normal
-- byte stream carry on unmodified" mechanic, not a normal 2-operand
-- opcode. `isGateClear` defaults to "always clear" (matches
-- `.oneShotTriggerGate`'s own established convention for this exact
-- WRAM cell).
--
-- **The opaque per-opcode leaf, fully decoded (2026-08-14, direct
-- follow-up: "such die ROM-Adresse der Tile-Byte-Paare für die anderen
-- Übergänge... und die genaue Struktur des $11B7-Skriptformats selbst
-- und verallgemeinere den algorithmus")**: `0xF4`'s own leaf (`$11C8`)
-- does `PUSH AF` (saves `byte2`, still in `A`) `/ LD A,0x0F / JP
-- $1ED7`. `$1ED7` is a real, general "selector -> bank-1 handler"
-- dispatcher (SAME `$4000`-base, 2-byte-stride table SHAPE as the
-- already-known `$1F35` family, but a genuinely SEPARATE table
-- instance -- confirmed real, not assumed, by direct ROM byte read):
-- switches to bank 1, computes `HL = *($4000 + selector*2)`, restores
-- the ORIGINAL caller HL (the still-unconsumed script cursor) and `A`
-- (byte2), then does a real computed-jump (`PUSH HL / RET`) straight
-- into `table[selector]` -- for `0xF4`'s own selector `0x0F`,
-- **`table[0x0F] = $4130`, the ALREADY-known real entry point for the
-- `$413C` cut-transition sequence** (previously only known to be
-- reached from the room-load dispatch -- now CONFIRMED to ALSO be
-- reachable directly from a real script opcode). CORRECTED 2026-08-14
-- (task #85): earlier docs assumed 30 real steps; a fresh full-table
-- dump plus a second, previously-undocumented sibling table found the
-- same pass ($418C, byte-for-byte the same $4130-style dispatcher
-- shape) both show plausible, address-shaped entries only for indices
-- 0-7, becoming non-address garbage at EXACTLY index 8 in BOTH tables
-- independently -- real, strong (not yet live-confirmed) evidence the
-- true step count is 8, not 30; see events.md's dated entry. `$4130`
-- dispatches to
-- `$413C[real $D499 step index]` -- i.e. **`0xF4`'s real job is
-- "peek 2 literal bytes into B/C, then hand control to whichever step
-- of the current cut-sequence is active right now, with those 2 bytes
-- available in `B`/`C` for that step's own use."** Neither `$1ED7`
-- nor `$4130`/`$02B70`'s own table-walk touches `B` or `C` at any
-- point, so they survive completely intact into the step handler --
-- this is a deliberate calling convention, not incidental register
-- survival (independently re-verified via a full instruction-by-
-- instruction disassembly of every intervening routine).
--
-- **Real, live-confirmed example** (the thirdRoom->fourthRoom cut):
-- step 5's own real handler (`$43A3`) uses the peeked `B,C` as a TILE
-- coordinate, converting to real screen pixels via `E=(B*8)+8,
-- D=(C*8)+16` (see `src/import/TileLandingPosition.lua`) and
-- committing through the real per-tick entity position-commit routine
-- (`$0611`). **This generalizes**: EVERY step of the `$413C` sequence
-- that needs a 2-byte parameter gets it via its own preceding `0xF4`
-- peek -- confirmed live for a SECOND real transition (fourthRoom->
-- fifthRoom): the exact same step-5 tile-coordinate use, real ROM
-- bytes `10 02` (tile 16,2 -> screen 136,32, an EXACT match to this
-- project's own already-recorded `landingX=136,landingY=32`) at real
-- bank 14, file offset `0x38C87` -- and 2 OTHER real `0xF4` peeks
-- fire earlier in the SAME script (bytes `04 50` and later `00 0B`,
-- real file offsets `0x38C85`/`0x38C89`) for OTHER steps' own,
-- different real parameters (not landing coordinates -- which step
-- consumes which peek, and what each OTHER step's own bytes mean, was
-- not decoded further this pass -- a real, honestly-scoped follow-up).
-- The known real landing-tile source addresses, so far: thirdRoom->
-- fourthRoom = bank 14, file `0x382F9` (bytes `0E 0C`); fourthRoom->
-- fifthRoom = bank 14, file `0x38C87` (bytes `10 02`). fourthRoom->
-- sixthRoom was NOT resolved this pass -- live re-tracing found its
-- own real trigger does NOT behave like a simple "hold at a wall for N
-- frames" cut at all (matches this project's own EARLIER, independent
-- finding in `rom_profiles.lua`'s own `sixthRoom` exit doc comment:
-- "a genuinely CONTINUOUS real hardware scroll... not a real, single
-- ROM-authored constant") -- a real, different mechanism, left open
-- rather than forced into this same live-trace method.
-- `extraBytesOnRelease` (default 0): CORRECTED 2026-08-15 (direct user
-- request "suchen alle... quick wins" -> task #126, "trace $1ED7
-- selector-0x10 phase 2/4 sub-calls for missing $3727"). A live mGBA
-- trace (single-step, real execution-address tracking from
-- `courtyard_boss_defeated()` through the real black-wipe/fade) found
-- the ACTUAL real bytes at the exact real cursor this project's own
-- BossSequenceInterpreter test already locks in (`0x61d8`, bank 14):
-- `bd f3 0f 55 14 00 bc f0 ...`. I.e. opcode `0xF3`'s own real total
-- instruction length is **5 bytes**, not the 1-byte-net-zero this
-- function previously modeled: `0f`/`55` are the already-known 2
-- peeked bytes, but `14`/`00` are ALSO real, silently-consumed bytes
-- -- confirmed by directly reading real `$3727` return addresses via
-- an execution-address trace: 0xF3's own real completion trampoline
-- (`$11de`, a real `CALL $3727` epilogue, distinct from opcode
-- `0xBD`'s own completion at `$1163`) fires ONLY once cursor `0x61de`
-- (5 bytes past 0xF3's own opcode byte) is reached -- `0x61da`-`0x61dd`
-- (the `0f 55 14 00` bytes) never individually re-enter `$3727`, so
-- they're consumed by `$1ED7` selector-0x10's own internal HL
-- increments (real phase 2/4 work), not the top-level dispatch loop --
-- exactly matching this project's own prior hypothesis ("one of phase
-- 2/4's own untraced sub-calls also advances the real cursor"), now
-- confirmed with byte-exact evidence instead of suspected. WHY 2 more
-- bytes get consumed (`0x14` is the already-confirmed hero-name token,
-- `0x00` a plausible terminator -- suggestively a real "flash the
-- hero's name" effect tied to this completion, but NOT independently
-- confirmed this pass) is left honestly UNMODELED -- only the real
-- BYTE COUNT is fixed here, not fabricated semantics for what those 2
-- bytes mean. Deliberately a NEW OPTIONAL parameter, not a change to
-- this function's own default behavior -- opcode `0xF4` also calls
-- `.peekTwoByteGate` but via the generic `ctx.isPeekGateClear` default
-- (explicitly NOT assumed to share `0xF3`'s own real sequence, per
-- this function's own existing doc comment above), so it keeps
-- `extraBytesOnRelease=0` unless independently proven otherwise.
function StandardScriptHandlers.peekTwoByteGate(onPeek, isGateClear, extraBytesOnRelease)
  extraBytesOnRelease = extraBytesOnRelease or 0
  return function(stream, cursor)
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if onPeek then
      onPeek(byte1, byte2)
    end
    if isGateClear and not isGateClear() then
      return nil -- real halt: $D499 still nonzero, retry (re-peeks same bytes)
    end
    if extraBytesOnRelease == 0 then
      return cursor -- gate clear: continue from the SAME position (bytes NOT consumed)
    end
    -- gate clear AND this opcode's own real release consumes further
    -- bytes beyond the 2 peeked ones (see doc comment above) -- fetch
    -- (and discard) exactly that many more, real ROM byte-for-byte.
    local after = afterByte2
    for _ = 1, extraBytesOnRelease do
      local _, next_ = ScriptInterpreter.fetch(stream, after)
      after = next_
    end
    return after
  end
end

--- Real "ungated single-byte leaf command" handler family (opcodes
-- `0xD5`/`0xD7`/`0xD9`, ROM `$3B3A`/`$3B45`/`$3B50`, found live
-- 2026-08-13 task #86, immediately adjacent to `0xD4`/`0xD6`/`0xD8`
-- above) -- the EXACT same real shape (`LD A,(HL+)/INC A/PUSH HL/CALL
-- <leaf>/POP HL`), calling its own per-opcode opaque leaf (`$30D5`/
-- `$30E1`/`$30DB`), but WITHOUT the `$D86F` bit-1 gate check --
-- `CALL $3727 / RET` directly, ALWAYS continuing. Kept as its own,
-- separate, honestly-named factory rather than reusing
-- `.gatedByteLeafCommand` with a no-op gate, since these opcodes'
-- real handlers genuinely never gate at all -- reusing the "gated"
-- name for them would misrepresent their real disassembly.
function StandardScriptHandlers.byteLeafCommand(onByte)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onByte then
      onByte(byte + 1)
    end
    return afterByte
  end
end

--- Real "raw single-byte leaf command" handler family (opcodes
-- `0x9C`/`0x9D`, ROM `$0F0A`/`$0F14`, found 2026-08-14 -- the
-- whole-corpus scan's own next real untouched blocker after `0xD1`).
-- Byte-for-byte:
--   LD A,(HL+) / PUSH HL / CALL $2895 / POP HL / CALL $3727 / RET
-- ALMOST the exact same real shape as `.byteLeafCommand` above (opcodes
-- `0xD5`/`0xD7`/`0xD9`) -- one real operand byte, an opaque per-opcode
-- leaf call, always continues, one more real byte consumed via the
-- standard `$3727` skip -- but a genuine, real difference: `.byteLeafCommand`'s
-- own family does `INC A` before calling its leaf; THIS family does
-- NOT (confirmed absent from the real bytes, not an oversight) -- the
-- RAW fetched byte reaches the leaf unmodified. Kept as its own,
-- separate, honestly-named factory rather than reusing
-- `.byteLeafCommand` with a fake "no-op increment", since baking in
-- the `+1` there would misrepresent this family's real disassembly
-- (same reasoning `.byteLeafCommand`'s own doc comment already applies
-- to keeping it separate from `.gatedByteLeafCommand`). Both `0x9C`
-- and `0x9D` share the SAME real leaf (`$2895`) -- HYPOTHESIS on its
-- real-world meaning, matching this project's established scope for
-- opaque-leaf opcodes; the mechanism itself is fully, decisively
-- traced.
function StandardScriptHandlers.rawByteLeafCommand(onByte)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onByte then
      onByte(byte)
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterByte)
    return afterSkip
  end
end

--- Real "actor-slot-position, readiness-as-parameter" handler (opcode
-- `0x79`, real ROM `$1566`, found 2026-08-14 -- the whole-corpus
-- scan's own next real untouched blocker after `0xC5`). Byte-for-byte:
--   CALL $28C2 / ADD A,0x06 / LD C,A / CALL $123E / RET
-- The `$123E`-leaf sibling of `.actorActionWithReadinessParam` (`0x7A`/
-- `0x7B`/...) -- SAME real shape (`$28C2`'s own real 0/1 result plus a
-- fixed offset becomes the callee's own `C` parameter), just tail-
-- calling `$123E` instead of `$2879`. Since neither this opcode NOR
-- `.actorSlotPosition` above preserves `HL` across the call, `$123E`
-- reads its own 2 real operand bytes directly from the live script
-- cursor -- confirmed by `.actorSlotPosition`'s own contract.
--
-- CORRECTED alongside `.actorActionWithReadinessParam`'s own same-day
-- self-caught fix: `isReady()` now GATES (matching that function's
-- own corrected reasoning -- this is the exact same real underlying
-- Family-A-shaped mechanism, its real halt lives inside the callee's
-- own dispatch chain, and `isReady()` is this project's established
-- approximate stand-in for it) rather than being pure unconditional
-- data. On the real not-ready path, this halts WITHOUT consuming the
-- 2 real position bytes (matching `.actorSlotPosition`'s own halt
-- contract exactly -- a real retry-same-opcode-next-tick, not a
-- partial read). `onSetPosition(param, byte1, byte2)` fires only on
-- the real ready path, with `param` always `offset+1` (see
-- `.actorActionWithReadinessParam`'s own doc comment for why the
-- `offset+0` case is folded into the gate's own halt, an honest
-- limit).
function StandardScriptHandlers.actorSlotPositionWithReadinessParam(offset, isReady, onSetPosition)
  return function(stream, cursor)
    if not isReady() then
      return nil -- approximate gate, matches .actorSlotPosition's own halt contract
    end
    local param = 1 + offset
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if onSetPosition then
      onSetPosition(param, byte1, byte2)
    end
    return afterByte2
  end
end

--- Real "6-bit WRAM field write" handler (opcode `0xC5`, real ROM
-- `$3B71`, found 2026-08-14 -- the whole-corpus scan's own next real
-- untouched blocker after `0xAF`). Byte-for-byte:
--   LD A,(HL+) / AND 0x3F / LD C,A          ; real operand byte, masked to 6 bits
--   LD DE,0xD7D4 / LD A,(DE) / AND 0xC0 / OR C / LD (DE),A
--                                              ; merge into $D7D4's low 6 bits,
--                                              ; preserving its own top 2 bits
--   CALL $3727 / RET
-- Simpler than `.twoBitFieldCommand` above -- no opaque leaf call at
-- all, purely a direct real operand-byte mask-and-merge into WRAM
-- `$D7D4`. Consumes the 1 real operand byte plus 1 more via the
-- standard trailing `$3727` skip; always continues. `onWrite(value)`
-- fires once per dispatch with the real, already-masked (`AND 0x3F`)
-- 6-bit value.
function StandardScriptHandlers.sixBitFieldCommand(onWrite)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onWrite then
      onWrite(bit.band(byte, 0x3F))
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterByte)
    return afterSkip
  end
end

--- Real "chained opaque effect" handler (opcode `0xAF`, real ROM
-- `$2CE7`, found 2026-08-14 -- the whole-corpus scan's own next real
-- untouched blocker after `0xC2`). Byte-for-byte:
--   PUSH HL / LD A,($C5B0) / LD C,A / PUSH BC / CALL $05EF / POP BC
--   PUSH DE / CALL $2D13 / POP DE / CALL $2CE1 / LD A,0x0F / CALL $297D
--   POP HL / CALL $3727 / RET
-- ZERO real script-stream operand bytes are read directly -- 4
-- sequential opaque leaf calls, each getting their own real parameter
-- from live WRAM/fixed constants (NOT the script stream), no branch
-- anywhere. The only real byte consumed is the standard trailing
-- `$3727` skip. All 4 leaves (`$05EF`/`$2D13`/`$2CE1`/`$297D`) remain
-- untraced -- HYPOTHESIS on their combined real effect, matching this
-- project's established scope for opaque-leaf opcodes; the STRUCTURE
-- (0 explicit operand bytes, 1 via `$3727`, unconditional) is fully,
-- decisively verified. `onEffect()` fires once per real dispatch,
-- with no parameters (this project has no honest way to summarize 4
-- chained opaque calls into one meaningful value).
function StandardScriptHandlers.chainedOpaqueEffectCommand(onEffect)
  return function(stream, cursor)
    if onEffect then
      onEffect()
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

--- Real opcode `0xAD` handler (`$0DBC`, CLOSED 2026-08-15 -- direct
-- user request "ok die restlichen bitte auch noch" -- task #152).
-- Byte-for-byte: `PUSH HL / CALL $1ED1 / CP 0x00 / JR NZ,<release>`,
-- where `$1ED1` (`PUSH AF / LD A,0x01 / JP $1F06`) reaches selector
-- `0x01` of the ALREADY-known bank-2 `$1F35`/`$1F06` dispatcher family
-- (rom-map.md's own "$1ED7" section already documents this as a real
-- sibling of `$1ED7`, just switching to bank 2 instead of bank 1 --
-- confirmed here by cross-checking `$1F06`'s own table base against
-- `$1ED7`'s: passing `A=2` instead of `A=1` to the shared `$29FB`
-- bank-switch primitive lands on a COMPLETELY DIFFERENT real table,
-- ruling out a shared-table coincidence). Selector `0x01`'s own real
-- target (`$4218`) is a **complete, classic Game Boy joypad-polling
-- routine**: `LD HL,$FF00 / LD (HL),0x10 / <2 real settle reads> / LD
-- (HL),0x20` (the standard D-pad-then-buttons hardware select
-- sequence) `/ CPL / AND 0x0F / CP 0x0F / JP Z,$0150` (the real
-- A+B+Select+Start SOFT-RESET COMBO check -- all 4 button bits read as
-- "pressed" simultaneously) `/ SWAP A / LD C,A / <8 more real settle
-- reads> / LD (HL),0x30 / CPL / AND 0x0F / OR C / LD C,A` (combines
-- D-pad + button bits into one real 8-bit state byte) `/ LD A,($C0AF)
-- / XOR C / AND C / LD B,A` (a real rising-edge "just pressed"
-- computation, discarded by this specific caller) `/ LD A,C / LD
-- ($C0AF),A / RET` (real state byte returned in `A`, also cached for
-- next time). Back in `$0DBC`: **if the returned state is NONZERO
-- (ANY real button held), releases immediately** (`CALL $3727`); if
-- ZERO (nothing held), increments a real WRAM idle counter (`$D49A`)
-- and calls one of 2 real, opaque leaf effects every real tick
-- (`$0695` once the counter's own bit 5 sets, ~32 real frames; else
-- `$05CD`) -- both real branches HALT (never reach `$3727` while
-- idle). **A real "wait for any button press" gate**, zero explicit
-- script-stream operand bytes. The real soft-reset combo's own `JP Z,
-- $0150` branch (INSIDE the joypad-poll routine, bypassing this
-- opcode's normal return path entirely) is genuinely NOT modeled here
-- -- a rare, separate real code path, matching this project's already-
-- narrower existing `ctx.onSoftReset` scope (real opcode `0xC8`, a
-- DIFFERENT trigger). `onIdleTick(elapsedFrames)` is an optional
-- observer for the 2 real, still-opaque idle-leaf calls -- this
-- project has no honest way to distinguish which of the 2 real
-- branches fired without tracing `$0695`/`$05CD` further.
--
-- `isAnyButtonPressed` is REQUIRED (matching this project's own
-- established convention for gate predicates, e.g. `actorAction`'s/
-- `queuedAction`'s own `isReady()` -- called directly, no internal nil
-- default). The "unwired gate defaults open" convention lives one
-- layer UP, in `ScriptRuntime.lua`'s own `ctx.isAnyButtonPressed or
-- function() return true end` wiring, same as `ctx.isActorReady`.
function StandardScriptHandlers.waitForAnyButtonCommand(isAnyButtonPressed, onIdleTick)
  local state = { idleFrames = 0 }
  return function(stream, cursor)
    if isAnyButtonPressed() then
      state.idleFrames = 0
      local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
      return afterSkip
    end
    if onIdleTick then
      onIdleTick(state.idleFrames)
    end
    state.idleFrames = state.idleFrames + 1
    -- Real halt: per ScriptInterpreter:step's own halt convention, a
    -- handler signals "re-dispatch me again next tick" by returning
    -- `nil` (NOT the unchanged cursor) -- `step` then re-derives the
    -- opcode from the ORIGINAL pre-fetch position, matching the real
    -- ROM's own bare RET (never reaching $3727).
    return nil
  end
end

--- Real opcode `0x8B` handler (`$0D1B`, CLOSED 2026-08-15 -- direct
-- follow-up "ok die restlichen bitte auch noch", task #152). A real
-- "play back a pre-baked waypoint/step sequence" gate -- see
-- `ScriptOpcodeTable.WAYPOINT_STEP_COMMAND_HANDLER_ADDRESS_8B`'s own
-- doc comment for the full real disassembly this is distilled from.
--
-- Real shape: reads exactly ONE real script-stream operand byte, but
-- ONLY on its own first real tick (`operand - 0x20`, the real
-- ROM's `$D498`) -- every later tick re-reads nothing, tracked here
-- via closure state (matching `waitForAnyButtonCommand`'s own
-- `state.idleFrames` precedent: the `cursor` parameter this function
-- receives stays FIXED at the same real position across every halting
-- tick, so the "have I already consumed the operand" bookkeeping must
-- live in the closure, not in `cursor`). Real pacing: 1 real frame
-- after init, then 8 real frames between every subsequent step check
-- (both baked in directly, matching this project's convention of
-- encoding verified real numeric constants rather than abstracting
-- them away). `advanceStep(operand, stepIndex)` is the caller's own
-- opaque real evaluator for the untraced real waypoint-table walk --
-- returns `(done, nextStepIndex)`; `done == true` matches the real
-- ROM's own `0x80` low-byte sentinel and releases the script (the
-- standard trailing `$3727` skip); otherwise `nextStepIndex` becomes
-- the real `$D499` value fed back into the NEXT check.
function StandardScriptHandlers.waypointStepCommand(advanceStep)
  local operand = nil
  local stepIndex = 0
  local waitFrames = 0

  return function(stream, cursor)
    if operand == nil then
      -- Real init (`$0D51`, fires exactly once): consumes the ONE real
      -- operand byte for its VALUE only -- the real ROM's own `LD
      -- A,(HL+)` permanently advances its script-stream pointer here,
      -- but since the RETURNED cursor on every halting tick is the
      -- ORIGINAL pre-fetch position anyway (see the halt-convention
      -- note above), the "past the operand" position only matters once
      -- we actually release below, where it becomes `afterSkip`.
      local rawOperand = ScriptInterpreter.fetch(stream, cursor)
      operand = rawOperand - 0x20
      stepIndex = 0
      waitFrames = 1
    end

    waitFrames = waitFrames - 1
    if waitFrames > 0 then
      return nil -- real halt: $D49A hasn't hit 0 yet
    end

    local done, nextStepIndex = advanceStep(operand, stepIndex)
    if done then
      local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
      return afterSkip
    end

    stepIndex = nextStepIndex
    waitFrames = 8 -- real re-arm value (`LD A,0x08`)
    return nil
  end
end

--- Real "bitmask dispatch" handler (opcode `0xC2`, real ROM `$3981`,
-- found 2026-08-14 -- the whole-corpus scan's own next real untouched
-- blocker after `0xDA`/`0xDB`). Byte-for-byte:
--   LD A,(HL+) / CPL / LD C,A         ; real operand byte, COMPLEMENTED into C
--   BIT 0,C / CALL Z,$316B             ; if REAL bit 0 of the operand was SET...
--   BIT 1,C / CALL Z,$3171             ; ...(complemented bit reads as 0, hence "CALL Z")
--   BIT 2,C / CALL Z,$3177
--   BIT 3,C / CALL Z,$317D
--   BIT 4,C / CALL Z,$3183
--   CALL $3727 / RET
-- A real, decodable "checkbox" opcode: the low 5 bits of ONE real
-- operand byte each independently gate a call to their own fixed real
-- leaf (`$316B`/`$3171`/`$3177`/`$317D`/`$3183`, all opaque -- real
-- effects HYPOTHESIS, matching this project's established scope).
-- Always continues (no halt anywhere); consumes the 1 real operand
-- byte plus 1 more via the standard trailing `$3727` skip.
-- `onBit(bitIndex)` fires once per REAL SET bit (0-4), in ascending
-- order, using the real, un-complemented bit meaning (SET = fires) --
-- the complement in the actual Z80 code is purely an implementation
-- detail of using `CALL Z` instead of `CALL NZ`, not a real inversion
-- of the opcode's own semantics.
function StandardScriptHandlers.bitmaskDispatchCommand(onBit)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onBit then
      for bitIndex = 0, 4 do
        if bit.band(byte, bit.lshift(1, bitIndex)) ~= 0 then
          onBit(bitIndex)
        end
      end
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterByte)
    return afterSkip
  end
end

--- Real "dynamic-index flag-bit SET/CLEAR" handler family (opcodes
-- `0xDA`/`0xDB`, real ROM `$3BDB`/`$3BE5`, found 2026-08-14 -- the
-- whole-corpus scan's own next real untouched blocker after `0xC7`).
-- Byte-for-byte, `0xDA`:
--   CALL $3727 / CALL $3BEF / CALL $3727 / RET
-- and `0xDB`, the same shape calling `$3BF9` instead. Fully tractable
-- now that `0xD1`'s own investigation (see
-- `.budgetFlagCommand`'s own doc comment) already fully decoded
-- `$3BEF`/`$3BF9`/`$3602`: a real SET/CLEAR-numbered-flag-bit pair
-- over the same 128-bit WRAM array at `$D7C6`-`$D7D5`. The genuinely
-- NEW piece here: `$3727`'s own real calling convention leaves the
-- just-fetched byte in `A` across the call boundary (confirmed from
-- its own disassembly: the fetched byte is `PUSH`ed, `H`/`L` get
-- cached into `$D8B6`/`$D8B7`, then `POP`ped back into `A` right
-- before `RET`) -- so the FIRST `CALL $3727` here doubles as BOTH
-- "consume 1 real operand byte" AND "load that byte into `A` as the
-- real bit-INDEX parameter" for the immediately-following `$3BEF`/
-- `$3BF9` call. The SECOND `CALL $3727` consumes one more real byte
-- that's never otherwise used -- a genuine 2nd operand byte, matching
-- this project's own established "verified, unexplained 2nd/3rd byte"
-- convention (e.g. `.tileCursorSet`'s own 3rd byte,
-- `.playerEntityTypeWrite`'s own padding byte).
-- `setBit`: `true` for `0xDA` (SET), `false` for `0xDB` (CLEAR).
-- `onBit(bitIndex)` fires once per dispatch with the real, raw operand
-- byte (the bit index the real ROM passes to `$3BEF`/`$3BF9`).
function StandardScriptHandlers.dynamicFlagBitCommand(setBit, onBit)
  return function(stream, cursor)
    local bitIndex, afterIndex = ScriptInterpreter.fetch(stream, cursor)
    if onBit then
      onBit(bitIndex, setBit)
    end
    local _, afterPadding = ScriptInterpreter.fetch(stream, afterIndex)
    return afterPadding
  end
end

--- Real "2-bit WRAM field write" handler (opcode `0xC7`, real ROM
-- `$39BA`, found 2026-08-14 -- the whole-corpus scan's own next real
-- untouched blocker after `0xC6`). Byte-for-byte:
--   PUSH HL / CALL $2B1E / AND 0x03 / LD B,A
--   LD A,($D7D5) / AND 0xFC / OR B / LD ($D7D5),A
--   POP HL / CALL $3727 / RET
-- ZERO real script-stream operand bytes are read directly by this
-- opcode (`$2B1E` is called with no operand fetch beforehand, and HL
-- is preserved unchanged across the call via the `PUSH HL`/`POP HL`)
-- -- the ONLY real stream byte this opcode consumes is the standard
-- trailing `$3727` skip. Always continues (no branch at all).
-- `$2B1E` itself was traced -- a real, self-contained WRAPPING-COUNTER
-- + 2-level table lookup (`$C0B0`/`$C0B1` cycle a counter, indexes a
-- real table at `$2A1E` twice) -- genuinely deep enough that its
-- EXACT return value is left HYPOTHESIS (opaque leaf, same
-- "interpreter doesn't render, it calls back" scope as every other
-- closed opaque-leaf opcode) -- but this does NOT block modeling
-- `0xC7` itself correctly, since the opcode's own real stream
-- behavior (0 explicit bytes + 1 via `$3727`, unconditional) doesn't
-- depend on what `$2B1E` returns. `getValue()` is an optional
-- real-value provider (defaults to 0 -- no live `$C0B0`/`$C0B1`
-- cycling counter modeled); its result is masked to the real 2-bit
-- field (`AND 0x03`) before `onWrite` fires, matching the real ROM's
-- own masking.
function StandardScriptHandlers.twoBitFieldCommand(getValue, onWrite)
  return function(stream, cursor)
    -- SELF-CAUGHT BUG, fixed 2026-08-14: a generic caller (e.g. this
    -- project's own whole-corpus scan tool) may supply a stub
    -- `getValue` that returns a non-number placeholder (its own
    -- generic `__index` stub returns `true` for every unset callback,
    -- regardless of that callback's own real return type) -- coerce
    -- anything that isn't a real number to the documented default (0)
    -- rather than crashing on `boolean % 4`.
    local rawValue = getValue and getValue()
    if type(rawValue) ~= "number" then
      rawValue = 0
    end
    local value = rawValue % 4 -- real AND 0x03 mask
    if onWrite then
      onWrite(value)
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

--- Real "scene/textbox init" handler (opcode `0xC6`, real ROM `$39CF`,
-- found 2026-08-14 -- the whole-corpus scan's own next real untouched
-- blocker after `0x9C`/`0x9D`). Byte-for-byte: reads ONE real operand
-- byte (stored into `$D86C`), then unconditionally runs a long,
-- BRANCHLESS sequence of real WRAM writes -- `$D86E`=0, `$D862`=
-- (current `$C0A0`), `$D86C`=the operand byte, `CALL $30FF` (untraced
-- leaf), `$D853`=1, `$D84A`=0x1D, `$C0A0`=0x0F, `$D874` bit 5 cleared,
-- `$D885`=0, 4 bytes at `$D7A7`-`$D7AA` zeroed, then `CALL $3D10`
-- (B=5, another untraced leaf) -- and returns (no trailing `$3727`
-- skip needed: the routine's own single real operand fetch, `LD
-- A,(HL+)`, already advances the cursor by exactly the 1 real byte
-- this opcode consumes).
--
-- DECISIVE cross-confirmation this is the SAME real "start a new
-- textbox/scene" state machine opcode `0xF6`'s own doc comment
-- (`TWO_BYTE_COMMAND_HANDLER_ADDRESS`) already hypothesized: `$D862`/
-- `$D86C`/`$D853`/`$D84A`/`$C0A0` are the EXACT SAME 5 real WRAM cells
-- both opcodes write -- not a coincidence, strong evidence `0xC6` is
-- a sibling/variant initializer in that same family (HYPOTHESIS on
-- the precise real-world distinction between the two -- the mechanism
-- itself, byte consumption and always-continues behavior, is
-- decisively verified). `$30FF`/`$3D10` remain untraced (HYPOTHESIS
-- on their own real effect, matching this project's established scope
-- for opaque leaves). `onByte(operandByte)` fires once per dispatch.
function StandardScriptHandlers.sceneInitCommand(onByte)
  return function(stream, cursor)
    local byte, afterByte = ScriptInterpreter.fetch(stream, cursor)
    if onByte then
      onByte(byte)
    end
    return afterByte
  end
end

--- Real "periodic WRAM-effect" primitive (added 2026-08-14, whole-
-- corpus scan blockers `$0E8C`/`$0FE0`, opcodes `0xFB`/`0xBF`) -- the
-- SHARED shape behind both: every call fires `onTick(counter)` with a
-- real, private phase counter's CURRENT (pre-increment) value, doing
-- whatever real WRAM write that opcode's own cosmetic effect needs,
-- then advances the counter modulo `period`. On real WRAP (real ROM:
-- `INC A` [+ `AND` mask for a power-of-two period] / compare-or-test /
-- branch), BOTH real handlers call `$3727` -- the SAME already-ported
-- general opcode-fetch primitive this project's OWN main dispatch loop
-- already uses every tick (see `ScriptInterpreter.lua`'s own doc
-- comment: `LD A,(HL+) / LD ($D85A),A` + cache HL into `$D8B6`/`$D8B7`,
-- `RET` -- no dispatch of its own). Neither handler does anything else
-- afterward, and no code path was found anywhere that checks whether
-- `$D85A`/`$D8B6`/`$D8B7` were already primed before this project's
-- own outer per-tick loop does ITS OWN unconditional `$3727` fetch on
-- its very next cycle -- so the wrapped call's ONLY observable effect
-- is a real one-byte SKIP in the script stream; the byte value fetched
-- inline is never itself dispatched. HYPOTHESIS on that last point (no
-- live trace of the real outer dispatch loop's fetch-vs-skip behavior
-- on this exact path was captured this pass) but structurally solid:
-- `$3727` is a plain fetch+cache primitive with no jump/call of its
-- own, and both handlers just `RET` right after.
--
-- `state`: a private per-call-site counter table (`.counter`, defaults
-- 0). Real WRAM `$D499` is genuinely GLOBAL/shared across SEVERAL
-- unrelated ROM mechanisms (see `ScriptOpcodeTable.lua`'s own `$413C`-
-- table note, and `.peekTwoByteGate`'s doc comment above, for two
-- other real, different consumers of this SAME cell) -- since this
-- project runs one script per `ScriptRuntime`, a private zero-
-- initialized counter is the closest honest equivalent (the real ROM
-- resets it to 0 on every wrap anyway, so a real stale cross-mechanism
-- value only ever matters for the first partial cycle).
-- `period`: the real wrap modulus (64 for `0xFB`'s `AND 0x3F`, 10 for
-- `0xBF`'s explicit `CP 0x0A`).
-- `onTick(counter)`: fires every call with the real current/pre-
-- increment counter value.
function StandardScriptHandlers.periodicWramEffect(state, period, onTick)
  assert(type(state) == "table", "periodicWramEffect requires a state table")
  assert(type(period) == "number" and period > 0, "periodicWramEffect requires a positive period")
  assert(type(onTick) == "function", "periodicWramEffect requires onTick")
  state.counter = state.counter or 0
  return function(stream, cursor)
    onTick(state.counter)
    state.counter = (state.counter + 1) % period
    if state.counter == 0 then
      -- real wrap: $3727's own fetch, modeled as a 1-byte stream skip
      -- (see doc comment above for why the fetched VALUE itself is
      -- never dispatched).
      local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
      return afterSkip
    end
    return cursor
  end
end

--- Real opcode `0xFB` handler (`$0E8C`, found 2026-08-14, whole-corpus
-- scan) -- a real WRAM "wave offset" oscillator: `$C0A6` is nudged +-2
-- every call following a real triangle wave (period 8, computed from
-- the shared counter's own low 3 bits: phases 2-5 subtract 2, phases
-- 0/1/6/7 add 2), tracing a real -4..+4 sawtooth over a full 8-call
-- cycle -- a cosmetic sprite-bob/float-style wobble this project has
-- no renderer hook for. `onUpdate(value)`, if given, is called with
-- the real running byte value so a caller CAN observe/use it without
-- this project guessing its real consumer. See `.periodicWramEffect`'s
-- own doc comment for the shared every-64-calls stream-byte-skip.
function StandardScriptHandlers.waveOffsetEffect(onUpdate)
  local state = { counter = 0, value = 0 }
  return StandardScriptHandlers.periodicWramEffect(state, 64, function(counter)
    local phase = counter % 8
    local delta = (phase >= 2 and phase <= 5) and -2 or 2
    state.value = (state.value + delta) % 256
    if onUpdate then
      onUpdate(state.value)
    end
  end)
end

--- Real opcode `0xBF` handler (`$0FE0`, found 2026-08-14, whole-corpus
-- scan -- also one of the boss-defeat script's own real opcodes, see
-- `ScriptRuntime.lua`'s own top-of-file "HONEST SCOPE" note) -- a real
-- 2-triple color pulse/flash: writes a "dim" WRAM triple (`$C0AA`/
-- `$C0AB`/`$C0AC` = `0x3F`/`0x3F`/`0x3F`) for the first 5 calls of a
-- 10-call cycle, then a "bright" triple (`0xE4`/`0xD0`/`0xD0`) for the
-- next 5 -- a classic flash/blink cosmetic effect this project has no
-- renderer hook for. `onDim`/`onBright`, if given, each receive the
-- real `(r, g, b)`-shaped triple so a caller CAN wire it up without
-- this project guessing the real consumer. See `.periodicWramEffect`'s
-- own doc comment for the shared every-10-calls stream-byte-skip.
function StandardScriptHandlers.colorPulseEffect(onDim, onBright)
  local state = { counter = 0 }
  return StandardScriptHandlers.periodicWramEffect(state, 10, function(counter)
    if counter < 5 then
      if onDim then
        onDim(0x3F, 0x3F, 0x3F)
      end
    else
      if onBright then
        onBright(0xE4, 0xD0, 0xD0)
      end
    end
  end)
end

--- Real opcode `0xBC`/`0xBD`/`0xBE` handler family (`$10DC`/`$1046`/
-- `$10A7`, the "palette-fade" family -- SEE `ScriptOpcodeTable.lua`'s
-- own `PALETTE_FADE_HANDLER_ADDRESS_BC/BD/BE` doc comment for the full
-- disassembly trail, including the 2026-08-14 "deliberately unwired"
-- decision and its 2026-08-15 REVERSAL). Unlike `.periodicWramEffect`
-- (used by `0xFB`/`0xBF`, which never halt -- they call the real
-- `$3727` fetch unconditionally every single time and only vary a
-- COSMETIC counter), this family shares a real, genuine CONDITIONAL
-- HALT: the shared real leaf `$1142` only calls `$3727` once every 66
-- real calls (a 6-count inner cycle nested inside an 11-count outer
-- cycle -- see the disassembly in `ScriptOpcodeTable.lua`), returning
-- WITHOUT `$3727` (a real halt, re-dispatching the SAME opcode next
-- real tick) every other time -- so this needs the `nil`-halt / return-
-- cursor-release contract (matching `.tick`/`.textboxWait`), not
-- `.periodicWramEffect`'s always-continue shape.
--
-- `sharedState`: a private `{inner=0, outer=0}` table -- REQUIRED to be
-- the SAME table across all 3 real opcode registrations (`0xBC`/`0xBD`/
-- `0xBE` all read/write the SAME real WRAM cells `$D499`/`$D49A`, so a
-- private-but-shared Lua table is the honest equivalent, same "zero-
-- init is an honest default" convention as every other private shadow
-- WRAM cell in this project -- see `ScriptRuntime.new`'s own doc
-- comment). Consumes ZERO real operand bytes on release (confirmed via
-- disassembly: HL is only pushed/popped around each opcode's own WRAM
-- computation, never dereferenced) -- release returns `cursor`
-- unchanged, exactly matching the real ROM's own `CALL $3727 / RET`
-- with no operand read first.
-- `onStep(outer, inner)`: optional observer, fired on EVERY real call
-- (including the release call) with the CURRENT pre-increment counter
-- pair -- lets a future caller drive an actual on-screen palette fade
-- without this project guessing the real fade curve (the 4 real lookup
-- tables `$101A`/`$1030`/`$107B`/`$1091` themselves stay undecoded, see
-- `ScriptOpcodeTable.lua`'s own doc comment) -- same "paced correctly,
-- cosmetic write left as an optional callback" precedent as
-- `.waveOffsetEffect`/`.colorPulseEffect` above.
function StandardScriptHandlers.paletteFadeCycle(sharedState, onStep)
  assert(type(sharedState) == "table", "paletteFadeCycle requires a shared state table")
  sharedState.inner = sharedState.inner or 0
  sharedState.outer = sharedState.outer or 0
  return function(stream, cursor)
    if onStep then
      onStep(sharedState.outer, sharedState.inner)
    end
    sharedState.inner = sharedState.inner + 1
    if sharedState.inner < 6 then
      return nil -- real RET C at $1149: inner cycle still counting, halt
    end
    sharedState.inner = 0
    sharedState.outer = sharedState.outer + 1
    if sharedState.outer < 11 then
      return nil -- real RET C at $1158: outer cycle still counting, halt
    end
    sharedState.outer = 0
    -- real CALL $3727: fetch the next real opcode. Zero operand bytes
    -- consumed by this opcode itself, so the cursor is unchanged.
    return cursor
  end
end

--- Real opcode `0xF3`'s own true release condition -- `$1ED7` selector
-- `0x10`'s real 6-phase `$D499` state machine (see
-- `ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3`'s own doc
-- comment for the full disassembly of all 6 phases and why none of
-- them can affect the real script cursor). Returns a real `isGateClear`
-- -shaped predicate (no arguments, boolean result) suitable for
-- `.peekTwoByteGate`'s own `isGateClear` parameter -- advances the
-- real phase counter by exactly one step per call (matching the real
-- ROM's own per-tick `$1ED7` dispatch), returning `true` only once the
-- whole real sequence completes (matching the real `$D499` wrap back
-- to 0 on phase 5's own unconditional reset).
--
-- `state`: a private `{phase=0}` table, fresh per real `0xF3`
-- occurrence (deliberately NOT the same table as `.paletteFadeCycle`'s
-- own `sharedState` -- both real mechanisms happen to reuse the SAME
-- WRAM byte `$D499`, but for DIFFERENT, sequenced, non-overlapping
-- real purposes, same "one shared hardware cell, several private Lua
-- shadow counters" precedent as `0xFB`/`0xBF`).
-- `isDualGateClear`: the real `$C8E0`/`$CEE8` dual gate phases 1 and 3
-- both check -- pass `ctx.isTriggerEventGateClear` directly (the SAME
-- real WRAM cells `0xFC`/`0xFD`/`0xE8`-`0xEB` already model, see
-- `.oneShotTriggerGate`'s own doc comment for `$C8E0`'s now-CRACKED
-- real meaning -- task #160's ROM->VRAM tile-streaming DMA queue);
-- optional, defaults to "always clear" like every other real consumer
-- of this gate in this project.
-- `onPhase(phase)`: optional observer, fires on EVERY real call
-- (including repeated halts) with the CURRENT phase number (0-5) --
-- lets a future caller drive phase 2/4's own real (currently
-- unmodeled) transition/OAM side effects without this project
-- guessing them.
function StandardScriptHandlers.paletteFadeCompletionGate(state, isDualGateClear, onPhase)
  assert(type(state) == "table", "paletteFadeCompletionGate requires a state table")
  state.phase = state.phase or 0
  return function()
    if onPhase then
      onPhase(state.phase)
    end
    if state.phase == 0 then
      state.phase = 1 -- real $41CA: unconditional advance
      return false
    elseif state.phase == 1 or state.phase == 3 then
      -- real $4477: gated on the real $C8E0/$CEE8 dual gate
      if isDualGateClear and not isDualGateClear() then
        return false
      end
      state.phase = state.phase + 1
      return false
    elseif state.phase == 2 then
      state.phase = 3 -- real $4387: unconditional advance (real $26DC/$04A4 work, unmodeled)
      return false
    elseif state.phase == 4 then
      state.phase = 5 -- real $43EE: unconditional advance (real OAM work, unmodeled)
      return false
    else -- state.phase == 5
      state.phase = 0 -- real $448C: unconditional reset -- $D499==0 again, real release
      return true
    end
  end
end

--- Real opcodes `0xAC`/`0xAE`'s own true release condition -- `$1ED7`
-- selectors `0x11`/`0x12`'s real 8-phase `$D499` state machine (CLOSED
-- 2026-08-15, "laut website sind noch 2 offen. beende die auch" --
-- task #152's own final pair). Byte-for-byte, both selectors' real
-- jump tables (`$4170`/`$418C`, same `$2B70` multiply-and-jump shape
-- this project already trusts for selector `0x10`'s own table) share
-- 6 of their 8 real entries -- confirmed by reading BOTH tables' raw
-- bytes directly, not assumed:
--   phase 0 (`$419C`): unconditional advance. Real side effects go
--     well beyond the sibling family's own trivial phase 0 (a
--     self-caught correction of THIS SAME DAY's earlier "byte-
--     identical in shape" claim, which only checked the first 2
--     instructions): `$D49A=0`/`$D499++` (the shared housekeeping),
--     THEN a real palette/DMA-transfer call (`$02F3`, table `$40FC` or
--     `$4116` selected by `$C4D4` bit 1), a real `$C0A5` cache-then-
--     mask (`$D49C = $C0A5`, `$C0A5 &= 0xFC`), and a real numbered-
--     effect dispatch (`$297D` with `A=0x24`).
--   phase 1 (`$4477`): the ALREADY-known real `$C8E0`/`$CEE8` dual
--     gate -- the SAME leaf address the sibling family's own phase 1/3
--     use, reused here via `isDualGateClear` exactly like that family.
--   phase 2 (`$41D6`): a real, bounded "2 markers converging" wait --
--     4 real bytes at WRAM `$D3A0`-`$D3A3` (only the low byte `$D3A0`
--     and high byte `$D3A3` are touched; `$D3A1`/`$D3A2` sit unused in
--     between): each real tick, low `+=2`, high `-=2`; while they
--     haven't met/crossed, increments `$D49A` (a real ELAPSED-TICK
--     counter, confirmed reset to 0 by phase 0 above) and halts. Once
--     met: `CALL $0313` (untraced), `$C0A5 &= 0xFC` again, `CALL
--     $1D5E` with `HL=$FF40` (the real LCDC hardware register address,
--     passed as a literal, not directly poked here) -- plausibly a
--     real screen-wipe-closing effect. Advances to phase 3.
--   phase 3 (`$422B` for `0x11` / `$433E` for `0x12`): the ONE real
--     phase that genuinely, substantially DIFFERS between the two
--     selectors -- both do real OAM/sprite-buffer memcpy work (`$2B49`,
--     `HL=$C350`/`$C3A0`, `B=0x50`) and call the ALREADY-known real
--     cross-actor dispatch primitive `$26DC` (task #85's own finding)
--     plus `$04A4` (already flagged as unmodeled by the sibling
--     family's own phase-2-to-3 note above) -- genuinely NOT
--     reproduced here, matching this project's established scope for
--     opaque multi-leaf visual work. Unconditional single-tick advance.
--   phase 4 (`$4477`): the SAME dual-gate leaf as phase 1 (confirmed
--     by reading the raw table bytes, not assumed).
--   phase 5 (`$4422` for `0x11` / `$4456` for `0x12`): a SECOND real
--     palette/DMA call (`$02F3`, table `$4109` or `$4116`, same
--     `$C4D4` bit-1 selector as phase 0), a real numbered-effect
--     dispatch (`$297D` with `A=0x23`, a DIFFERENT effect ID from
--     phase 0's `0x24`), and a call to the ALREADY-known real pending-
--     sound-queue processor `$2EF7` (the SAME leaf opcode `0xAA`'s own
--     selector `0x1F` reaches). `0x11` additionally, conditionally
--     calls `$0DE6` first if `$D49F != 0` -- a real, selector-specific
--     extra branch, opaque. Unconditional single-tick advance.
--   phase 6 (`$4205`, shared): a real COUNTDOWN gate, NOT a marker
--     check -- decrements `$D49A` each real tick (the EXACT value
--     phase 2 counted UP to while converging: a real, decisively-
--     confirmed SYMMETRIC design -- the wipe closes over N ticks in
--     phase 2 and reopens over the SAME N ticks here, sharing one real
--     WRAM counter). While counting down, ALSO drives the SAME
--     `$D3A0`/`$D3A3` markers in the OPPOSITE direction (low `-=2`,
--     high `+=2` -- undoing phase 2's own convergence). Once `$D49A`
--     hits 0: `CALL $0313` again, restores `$C0A5` from phase 0's own
--     `$D49C` cache (undoing the earlier mask), advances to phase 7.
--   phase 7 (`$448C`, shared): the ALREADY-known real reset leaf --
--     the SAME address the sibling family's own phase 5 uses --
--     `$D499=0`, real release.
--
-- `state`: a private `{phase=0, convergeTicks=0}` table, fresh per
-- real occurrence (same "one shared hardware cell, several private Lua
-- shadow counters" precedent as `.paletteFadeCompletionGate`'s own
-- `state`). `convergeTicks` is this Lua port's own internal bookkeeping
-- for the real phase-2/phase-6 SYMMETRIC-duration relationship
-- described above -- NOT a separate ctx hook, since the real ROM's own
-- `$D49A` reuse makes phase 6's duration a deterministic function of
-- phase 2's, not independently observable state.
-- `isDualGateClear`: passed straight through to phases 1/4, same
-- optional/defaults-to-"always clear" contract as
-- `.paletteFadeCompletionGate`'s own parameter of the same name --
-- pass `ctx.isTriggerEventGateClear` to reuse the SAME real gate.
-- `isMarkerConverged`: the real phase-2 "have the 2 `$D3A0`/`$D3A3`
-- markers met/crossed yet" predicate -- REQUIRED (matching this
-- project's now-established convention for brand-new gate predicates,
-- e.g. `waypointStepCommand`'s own `advanceStep`; the "unwired gate
-- defaults open" behavior belongs one layer up, in `ScriptRuntime.lua`'s
-- own `ctx` wiring).
-- `onPhase(phase)`: optional observer, fires on EVERY real call with
-- the CURRENT phase number (0-7) -- same role as the sibling family's
-- own `onPhase`.
function StandardScriptHandlers.wipeCompletionGate(state, isDualGateClear, isMarkerConverged, onPhase)
  assert(type(state) == "table", "wipeCompletionGate requires a state table")
  state.phase = state.phase or 0
  state.convergeTicks = state.convergeTicks or 0
  return function()
    if onPhase then
      onPhase(state.phase)
    end
    if state.phase == 0 then
      state.phase = 1 -- real $419C: unconditional advance (real palette/effect work, unmodeled)
      return false
    elseif state.phase == 1 or state.phase == 4 then
      -- real $4477: gated on the real $C8E0/$CEE8 dual gate (SAME leaf as the sibling family)
      if isDualGateClear and not isDualGateClear() then
        return false
      end
      state.phase = state.phase + 1
      return false
    elseif state.phase == 2 then
      -- real $41D6: gated on the 2 real $D3A0/$D3A3 markers converging
      if not isMarkerConverged() then
        state.convergeTicks = state.convergeTicks + 1
        return false
      end
      state.phase = 3 -- real finish work ($0313/$C0A5/$1D5E), unmodeled
      return false
    elseif state.phase == 3 or state.phase == 5 then
      state.phase = state.phase + 1 -- real $422B/$433E or $4422/$4456: unconditional advance (real work, unmodeled)
      return false
    elseif state.phase == 6 then
      -- real $4205: a real COUNTDOWN gate, taking EXACTLY as many real
      -- ticks as phase 2 took to converge (see this function's own doc
      -- comment for the full evidence).
      if state.convergeTicks > 0 then
        state.convergeTicks = state.convergeTicks - 1
        return false
      end
      state.phase = 7 -- real finish work ($0313/$C0A5 restore), unmodeled
      return false
    else -- state.phase == 7
      state.phase = 0 -- real $448C: unconditional reset -- $D499==0 again, real release
      state.convergeTicks = 0
      return true
    end
  end
end

--- Generic "call a completion predicate each real tick; release once
-- it returns true" handler shape -- zero explicit script-stream
-- operand bytes, matching `chainedOpaqueEffectCommand`'s/
-- `waitForAnyButtonCommand`'s own `$3727`-tail convention (this
-- project's standard "no real operand, but still consumes exactly 1
-- byte via the trailing skip" shape). Used for opcodes `0xAC`/`0xAE`'s
-- own outer wrapper (`PUSH AF / LD A,<selector> / JP $1ED7` trampoline,
-- then `LD A,($D499) / CP 0 / RET NZ / CALL $3727 / RET` -- release
-- exactly when `$D499` returns to 0) -- see
-- `.wipeCompletionGate`'s own doc comment for what actually drives
-- `isComplete()` in that specific case; this wrapper itself is fully
-- generic and doesn't know or care what `isComplete` represents.
function StandardScriptHandlers.completionPredicateCommand(isComplete)
  return function(stream, cursor)
    if isComplete() then
      local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
      return afterSkip
    end
    return nil
  end
end

--- Real opcode `0x88`/`0x89` handler family (`$0153`/`$015E`, found
-- 2026-08-14, direct follow-up to the whole-corpus scan's rank-13
-- blocker -- `0x88` alone blocks 13 real scripts) -- writes a FIXED
-- per-opcode constant (2 for `0x88`, 1 for `0x89`) into the real
-- PLAYER entity's own "TYPE" field (`EntityStructLayout.FIELD.TYPE`,
-- real WRAM `$C241` -- slot 4, the already-confirmed player slot) via
-- a shared helper (`$02A5`/`$02AC` -> `$0C5D`, a real "swap: write A,
-- return the old value" primitive; the returned old value is read but
-- genuinely discarded by both real callers, so not modeled here).
-- Consumes exactly ONE real operand byte -- confirmed via disassembly
-- (`CALL $3727` right before the real `RET`, its result never used
-- afterward) to be a genuine, always-present padding byte the real ROM
-- itself never reads back, not a guess or omission in this project's
-- own port. `onWrite(fixedValue)`, if given, is an optional observer
-- -- this project's own entity model doesn't currently expose a
-- writable "TYPE" field to hook up live.
function StandardScriptHandlers.playerEntityTypeWrite(fixedValue, onWrite)
  return function(stream, cursor)
    if onWrite then
      onWrite(fixedValue)
    end
    local _, afterOperand = ScriptInterpreter.fetch(stream, cursor)
    return afterOperand
  end
end

--- Real "actor-command-queue-empty gate" handler (opcode `0x8F`, ROM
-- `$168E`, found 2026-08-14, whole-corpus scan's own rank-3 blocker --
-- 33 real scripts). Byte-for-byte disassembly:
--   LD HL,0xC5A0 / LD B,0x08
--   loop: LD A,(HL+) / CP 0x00 / JR NZ,<halt> / DEC B / JR NZ,loop
--   ; all 8 slots real zero:
--   CALL $3727 / RET
--   ; a real nonzero slot found:
--   RET                                     ; real halt, no bytes consumed
-- **The SAME real `$C5A0` 8-slot actor-command table this project
-- already traced twice this session** (task #85's own `$4B70`
-- "enqueue" finding; task #86's own `$4B4F` "any genuinely-pending
-- entries" poll, the real condition behind opcode `0x00`'s own bit-0
-- gate) -- this opcode is a THIRD, simpler real consumer: a plain
-- conditional halt on the RAW table being non-all-zero (no per-entry
-- completion-sentinel filtering the way `$4B4F` does), then consumes
-- exactly one real script-stream byte via the same real `$3727`
-- fetch-and-discard convention documented in `.periodicWramEffect`'s
-- own doc comment.
--
-- `isQueueEmpty`, if given, should report the real table's own current
-- emptiness. No live WRAM actor-command simulation exists in this
-- project (same honest gap as `ctx.isActorReady`/`ctx.isQueueBlocked`
-- elsewhere) -- defaults to "always empty" (the opcode always succeeds
-- immediately) rather than guessing a fake pending state.
function StandardScriptHandlers.actorCommandQueueEmptyGate(isQueueEmpty)
  return function(stream, cursor)
    local empty = (isQueueEmpty == nil) or isQueueEmpty()
    if not empty then
      return nil -- real halt: retry the same opcode, no bytes consumed
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

--- Real "actor-ready action, SOFT-SKIP on not-ready" handler (opcodes
-- `0x90`/`0x91`/`0x94`/`0x95`/`0x96`/`0x97`, real ROM `$1606`/`$1613`/
-- `$163A`/`$1647`/`$1620`/`$162D`, found 2026-08-14, whole-corpus scan
-- rank-3 blocker `$1606`, 31 real scripts). Byte-for-byte disassembly
-- (all 6 members structurally identical, only the literal `group`
-- differs -- `0x04`/`0x05`/`0x1E`/`0x1F`/`0x1C`/`0x1D` respectively):
--   CALL $28C2 / JR NZ,<not-ready> / LD A,<group> / LD C,0x00 /
--   CALL $2879 / RET
--   <not-ready>: CALL $3727 / RET
--
-- Shares the EXACT SAME real `$28C2` gate this project's own
-- `ctx.isActorReady` already models (WRAM `$C272`'s own high nibble
-- `==0xD0` -- the SAME real condition `.actorAction`'s own family
-- checks, confirmed by direct comparison against `$28C2`'s own
-- disassembly, not assumed). **But a GENUINELY DIFFERENT real
-- not-ready behavior**: a real, DIFFERENT sibling routine (`$28D5`,
-- checked directly to confirm this isn't a misread) uses the exact
-- same `$28C2` gate with a real `RET NZ` -- a TRUE halt, matching
-- `.actorAction`'s own model exactly. THIS family does NOT halt --
-- it calls the real `$3727` fetch-and-discard primitive (the SAME
-- "consume one real stream byte and move on" convention already
-- documented in `.periodicWramEffect`'s own doc comment) and
-- continues immediately, never retrying. A real, deliberate design
-- difference between two real families sharing one gate check, not
-- an inconsistency in this project's own model.
--
-- `group` is the real fixed per-opcode constant (never dynamic for
-- this family, unlike `.actorAction`'s own `0x80`/`0x85` exception).
-- `onAction(group)` fires once, only on the real ready path (matching
-- `.actorAction`'s own contract) -- the not-ready path never calls it.
function StandardScriptHandlers.actorActionOrSkip(group, isReady, onAction)
  return function(stream, cursor)
    if isReady() then
      if onAction then
        onAction(group)
      end
      return cursor -- real ready path: no operand bytes
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip -- real not-ready path: consumes one real stream byte instead of waiting
  end
end

--- Real "queued action, SOFT-SKIP on not-ready" handler (opcode `0x98`,
-- real ROM `$1654`, found in the SAME `$1606` cluster this same pass).
-- Byte-for-byte identical shape to `.actorActionOrSkip` above, just
-- tail-calling the real `$2859` queued-action leaf (no group) instead
-- of `$2879`:
--   CALL $28C2 / JR NZ,<not-ready> / LD C,0x00 / CALL $2859 / RET
--   <not-ready>: CALL $3727 / RET
-- See `.actorActionOrSkip`'s own doc comment for the full real
-- evidence behind the shared `$28C2` gate and the soft-skip
-- not-ready behavior (a genuine, confirmed difference from
-- `.queuedAction`'s own true-halt sibling family).
function StandardScriptHandlers.queuedActionOrSkip(isReady, onAction)
  return function(stream, cursor)
    if isReady() then
      if onAction then
        onAction()
      end
      return cursor
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

--- Real "actor-slot-position set, SOFT-SKIP on not-ready" handler
-- (opcode `0x99`, real ROM `$1663`, found in the SAME `$1606` cluster
-- this same pass). Byte-for-byte:
--   CALL $28C2 / JR NZ,<not-ready> / LD C,0x00 / CALL $123E / RET
--   <not-ready>: INC HL / INC HL / RET
-- The SAME real `$123E` mechanism as opcodes `0x49`/`0x19`/`0x39`/
-- `0x59`/`0x29` (see `.actorSlotPosition`'s own doc comment) -- a real
-- 2-operand-byte opcode. The not-ready path's own `INC HL / INC HL`
-- confirms this family's real "soft-skip" convention generalizes past
-- the always-1-byte `$3727` shape: it skips exactly the SAME 2 real
-- bytes the ready path would otherwise consume as its own operands
-- (not an unrelated extra byte) -- a real, internally-consistent
-- design (this opcode always consumes exactly 2 bytes, ready or not),
-- distinct from `.actorActionOrSkip`/`.queuedActionOrSkip`'s own
-- 0-real-operand shape (where the skipped byte belongs to whatever
-- comes NEXT, not to this opcode itself).
function StandardScriptHandlers.actorSlotPositionOrSkip(isReady, onSetPosition)
  return function(stream, cursor)
    if isReady() then
      local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
      local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
      if onSetPosition then
        onSetPosition(byte1, byte2)
      end
      return afterByte2
    end
    local _, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local _, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    return afterByte2
  end
end

--- Real "tile-cursor set" handler (opcode `0xEF`, ROM `$0E7F`, found
-- 2026-08-14 while chasing `$0E73`'s own neighborhood). Byte-for-byte:
--   LD A,(HL+) / LD E,A / LD A,(HL+) / LD D,A   ; 2 real operand bytes
--   PUSH HL / CALL $0454 / POP HL                ; $0454: a real, plain
--                                                  leaf -- NO branch, NO
--                                                  computation, just
--                                                  `LD (0xC345),A(D) /
--                                                  LD (0xC344),A(E) /
--                                                  RET` -- stores the 2
--                                                  bytes into 2 fixed
--                                                  WRAM cells, nothing
--                                                  else.
--   CALL $3727 / RET                              ; a real 3rd byte,
--                                                  consumed via the SAME
--                                                  fetch-and-discard
--                                                  convention documented
--                                                  in `.periodicWramEffect`'s
--                                                  own doc comment.
-- `$C344`/`$C345` are read back by neighboring VRAM BG-tilemap-address
-- resolvers (`$045D`/`$047C` family) NOT called by this opcode itself
-- -- plausibly a real "set the tile cursor" primitive some OTHER real
-- opcode/leaf consumes later; not modeled further (HYPOTHESIS on the
-- real-world meaning only, the mechanism itself is fully traced).
-- `onSet(byte1, byte2)` fires once with the 2 real operand bytes in
-- their own real stream order (`byte1`=E, `byte2`=D).
function StandardScriptHandlers.tileCursorSet(onSet)
  return function(stream, cursor)
    local byte1, afterByte1 = ScriptInterpreter.fetch(stream, cursor)
    local byte2, afterByte2 = ScriptInterpreter.fetch(stream, afterByte1)
    if onSet then
      onSet(byte1, byte2)
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterByte2)
    return afterSkip
  end
end

--- Real "actor action, READINESS-AS-PARAMETER" handler (opcodes
-- `0x7A`/`0x7B`/`0x5A`/`0x5B`/`0x6A`, real ROM `$1570`/`$157C`/
-- `$1488`/`$1494`/`$14FC`, found 2026-08-14 -- the whole-corpus scan's
-- own next real untouched blocker after the `$0E73` neighborhood).
-- Byte-for-byte:
--   CALL $28C2 / ADD A,<offset> / LD C,A / LD A,<group> / CALL $2879 / RET
--
-- SELF-CAUGHT CORRECTION (same day, later pass): this doc comment
-- originally claimed this family's real shape was "genuinely
-- different" from the already-established `.actorAction`/"Family A"
-- shape (`0x10`/`0x30`/`0x70`/... -- see `ScriptOpcodeTable.lua`'s own
-- Family-A doc comment), specifically that Family A uses a `JR
-- NZ,<not-ready>` gate right after `CALL $28C2` while this family
-- doesn't. Re-verifying Family A's OWN real bytes directly (`$1344`/
-- `$1514`/`$125C`, i.e. `0x30`/`0x70`/`0x10`) found that claim WRONG:
-- Family A has NO `JR NZ` there either -- it is BYTE-FOR-BYTE THE
-- EXACT SAME real instruction sequence as this family (`CALL $28C2 /
-- ADD A,<base> / LD C,A / LD A,<group> / CALL $2879 / RET`), just
-- different literal constants. Family A's own doc comment had ALREADY
-- correctly identified where the real halt actually lives -- entirely
-- INSIDE `$2879`'s own callee chain (`$2883` -> `$1F35` selector
-- `0x0A` -> `$4B70` -> a real `$C5A0` 8-slot pending-command search,
-- task #85's own finding) -- but this doc comment's own FIRST version
-- mis-stated that as an outer `JR NZ` gate that doesn't exist. Both
-- families are therefore the SAME real mechanism, approximated two
-- DIFFERENT ways by this project: `.actorAction` uses `isReady()` as
-- an outer GATE (an honest approximation of the real, unmodeled
-- `$2879`-internal `$C5A0` check, per that function's own "HONEST
-- LIMIT" note) but throws away the real `$28C2`-derived value (always
-- passes a FIXED group, `C=0x00`); THIS family instead threads the
-- real `$28C2`-derived value through as `param` (a genuine
-- improvement -- `$28C2`'s result determines WHICH of 2 real
-- action-code variants gets enqueued, real information Family A's own
-- model was silently discarding) but originally applied NO gate at
-- all. UNIFIED HERE: `isReady()` is now used for BOTH -- the same
-- approximate gate Family A already uses (so a real, live caller
-- supplying an actual predicate gets CONSISTENT halting behavior
-- across every Family-A-shaped opcode, old and new) AND the source
-- for `param`'s own real `0`/`1` term. The DEFAULT scan/test behavior
-- is unaffected (`ctx.isActorReady` defaults to "always ready," so
-- the gate never fires either way) -- this is a real-behavior
-- consistency fix, not a change to any already-measured scan result.
--
-- REFINEMENT (2026-08-14, task-11 quality pass, "kommentiere alles"):
-- a systematic byte-level re-check of ALL 46 real plain-Family-A
-- (`ACTOR_ACTION_HANDLER_ADDRESS_*`) constants found the "byte-for-
-- byte identical, no JR NZ anywhere" claim above holds for 44 of
-- them, but NOT universally -- `0x9A`/`0x9B` (`$1674`/`$1681`) DO have
-- a real `JR NZ` right after `CALL $28C2`, a genuine, real, direct
-- halt (re-verified directly, not assumed). For those 2 opcodes the
-- generic `.actorAction` gate isn't an approximation at all -- it's
-- the exact real condition. This doesn't change any behavior (the
-- SAME `isActorReady`-based gate already covers both cases correctly,
-- exactly for the 2 real exceptions and approximately for the other
-- 44), but the earlier blanket claim ("Family A has NO JR NZ") was
-- itself an overgeneralization from checking only 3 real examples --
-- corrected here for precision, not because anything was functionally
-- broken. Also found via this same systematic check: `0x7B`'s own
-- OLD `ACTOR_ACTION_HANDLER_ADDRESS_7B` constant (same address,
-- `$157C`) was still being picked up by `ScriptRuntime.lua`'s own
-- generic sweep, silently overwriting THIS family's more precise
-- registration for that one opcode -- a real, separate, self-caught
-- dead-code bug, fixed with an explicit exclusion (see that file's
-- own matching comment for the full story and a live verification).
--
-- `$28C2` itself returns a plain `A=0`(not ready)/`A=1`(ready) (see
-- its own disassembly: `CP 0xD0 / JR Z,+3 / LD A,0x00 / RET` / `LD
-- A,0x01 / RET`), added to a real, fixed per-opcode `offset` and
-- passed as `$2879`'s own `C` parameter. No script-stream operand
-- bytes either way (matching `.actorAction`'s own "zero operand
-- bytes" contract). `group`/`offset` are the real fixed per-opcode
-- constants. `onAction(group, param)` fires only on the real ready
-- path (matching `.actorAction`'s own contract, and this factory's
-- own gate above) -- since `isReady()` gates BEFORE `param` is
-- computed, only the real `A=1` case is ever reachable here, so
-- `param` is always `offset+1` in practice. The real `A=0`/`offset`
-- case exists in the ROM's own bytes but is folded into the gate's
-- own halt path by this approximation, same as `.actorAction`
-- silently discarding its own analogous "not ready" real payload --
-- an honest, documented limit, not a fabricated value.
--- Real "queued action, readiness-as-parameter" handler (opcode
-- `0x68`, real ROM `$14E8`, found 2026-08-14 -- the whole-corpus
-- scan's own next real untouched blocker after `0xA1`). Byte-for-byte:
--   CALL $28C2 / ADD A,0x05 / LD C,A / CALL $2859 / RET
-- The `$2859`-leaf (queued-action) sibling of
-- `.actorActionWithReadinessParam` -- SAME real shape and SAME
-- same-day gate correction (see that function's own doc comment for
-- the full story: this is the exact Family-A-shaped mechanism,
-- `isReady()` approximates the real, unmodeled `$2859`-internal halt,
-- and `param` is only reachable as `offset+1` on the ready path).
-- `onAction(param)` fires only on the real ready path.
function StandardScriptHandlers.queuedActionWithReadinessParam(offset, isReady, onAction)
  return function(_stream, cursor)
    if not isReady() then
      return nil -- approximate gate, same honest limit as .queuedAction
    end
    local param = 1 + offset
    if onAction then
      onAction(param)
    end
    return cursor
  end
end

function StandardScriptHandlers.actorActionWithReadinessParam(group, offset, isReady, onAction)
  return function(_stream, cursor)
    if not isReady() then
      return nil -- approximate gate, same honest limit as .actorAction
    end
    local param = 1 + offset -- real-ready path: $28C2 returned A=1
    if onAction then
      onAction(group, param)
    end
    return cursor
  end
end

--- Real "opcode self-mirror, ZERO real operand bytes" handler (opcode
-- `0xCC`, real ROM `$3AA3`, found 2026-08-14 -- the whole-corpus
-- scan's own next real untouched blocker after `0x7A`/`0x7B`).
-- Byte-for-byte, the ENTIRE real handler:
--   DEC HL / CALL $3727 / RET
-- `$3727` is this project's own already-known general "fetch one byte,
-- remember it in `$D85A`, cache the advanced HL into `$D8B6`/`$D8B7`"
-- primitive (see `ScriptInterpreter.lua`'s own header doc comment --
-- the SAME real routine the interpreter's own dispatch loop uses to
-- fetch every opcode byte in the first place). The leading `DEC HL`
-- rewinds the cursor by exactly 1 byte BEFORE that fetch -- and since
-- `$3727`'s own fetch re-advances HL by 1, the two cancel out: the
-- NET real cursor effect is ZERO, i.e. this opcode consumes no real
-- operand bytes at all. What actually gets (re-)read is the opcode's
-- OWN byte value: on entry, `HL` already points PAST the opcode byte
-- (the interpreter's own standard convention -- see
-- `ScriptInterpreter:step`), so `DEC HL` moves it back ONTO the
-- opcode byte itself. This handler's real, sole effect is therefore
-- to re-mirror its own opcode byte into `$D85A`/`$D8B6`/`$D8B7`.
-- HYPOTHESIS on the real-world PURPOSE (plausibly some generic "last
-- dispatched opcode" bookkeeping a different real routine reads
-- later) -- the MECHANISM itself is fully, decisively traced from
-- real bytes, not guessed. `onMirror(ownOpcodeByte)` is optional,
-- fires once per real dispatch with the real byte read from
-- `stream[cursor - 1]` (the exact same real byte the interpreter's
-- own dispatch already consumed to reach this handler in the first
-- place -- a legitimate lookback, not a guess, since `stream` supports
-- direct indexing by real CPU address per `ScriptInterpreter.fetch`'s
-- own doc comment) -- purely an observability hook, never affects the
-- returned cursor.
function StandardScriptHandlers.opcodeByteMirror(onMirror)
  return function(stream, cursor)
    if onMirror then
      onMirror(stream[cursor - 1])
    end
    return cursor
  end
end

--- Real "SOFT RESET" handler (opcode `0xC8`, real ROM `$3BA9`, found
-- 2026-08-14 -- the whole-corpus scan's own next real untouched
-- blocker after `0xBE`). The ENTIRE real handler is 3 bytes:
--   JP $0150
-- A DECISIVE, byte-for-byte cross-check against the ROM's own real
-- cartridge header confirms this is not a coincidence: `$0100`
-- (the real GB hardware entry vector every cartridge boots through)
-- is `NOP / JP $0150` -- the EXACT SAME 3 target bytes (`C3 50 01`)
-- this opcode jumps to. Following that target one level further:
-- `$0150` is `JP $1FCA`, and `$1FCA` is `DI / LD SP,0xFFFE / CALL
-- $1FF0 / EI / CALL $3153 / HALT` -- a genuine, real COLD-BOOT
-- sequence (disable interrupts, reset the stack pointer, run a real
-- init routine, re-enable interrupts, enter the main loop). **Real,
-- decisive conclusion**: opcode `0xC8` is a genuine, deliberate,
-- real "restart the entire game" script command -- NOT a normal
-- script continuation. Once dispatched, real control leaves the
-- script-interpreter system PERMANENTLY (there is no `RET`, no
-- `$3727` fetch-next-opcode anywhere in this chain) -- plausibly used
-- for a real game-over-into-title-screen flow or similar, though this
-- project doesn't have live evidence of WHICH real script content
-- reaches it, only that ≥1 real script in the corpus does (the
-- whole-corpus scan's own census).
--
-- HONEST MODELING LIMIT: this project's own interpreter model
-- represents an opcode's real effect as "return the next cursor" --
-- it has no way to represent "leave the interpreter forever and jump
-- to unrelated, non-script CPU code" through that same interface.
-- This handler therefore does the most honest thing available: fires
-- `onReset()` (a REQUIRED real side-effect hook -- an actual live
-- caller MUST use this to trigger its own real restart, e.g.
-- re-loading the title screen / resetting game state; there is no
-- sane default), then returns the SAME cursor it received (the real
-- ROM reads zero operand bytes -- `JP` takes none). The returned
-- cursor is a `scan_all_scripts.lua`-classification convenience only
-- (lets this opcode register as `clean` rather than a permanent
-- `halt_undecoded` entry) -- any REAL caller invoking `onReset()`
-- should treat that call as having already ended the script, exactly
-- like the real ROM does, and not attempt further stream processing
-- past this point.
--- Real "budget countdown, SET/CLEAR flag bit" handler (opcode `0xD1`,
-- real ROM `$3A72`, found 2026-08-14 -- the whole-corpus scan's own
-- next real untouched blocker after `0xE7`). Byte-for-byte:
--   LD E,(HL+) / LD D,(HL+)                 ; real operand: DE, LITTLE-endian
--   HL = ($D7BE/$D7BF as 16-bit) - DE       ; a real 16-bit subtract
--   JR NC,<sufficient>                       ; branch on whether it underflowed
--   <exhausted>: $D7BF/$D7BE = HL (the wrapped result) / CALL $3BF9(A=6)  ; CLEAR flag bit 6
--   <sufficient>: CALL $3BEF(A=6)                                         ; SET flag bit 6
--   (both) CALL $3117 / POP HL / CALL $3727 / RET
-- `$3BEF`/`$3BF9` were PREVIOUSLY flagged as untraced (see
-- `.gatedByteLeafCommand`'s own doc comment, which conservatively
-- halts rather than guess at them) -- fully resolved THIS pass: both
-- call a shared resolver (`$3602`) that turns a 0-127 bit INDEX (the
-- fixed `A` parameter) into a real `(address, bitmask)` pair over a
-- 16-byte, 128-bit WRAM flag array at `$D7C6`-`$D7D5` -- `$3BEF` then
-- ORs the bitmask in (SET), `$3BF9` ANDs the complement in (CLEAR).
-- Exactly this project's own already-established "resolve index to
-- (address, bitmask), OR to set / AND-complement to clear" convention
-- (see `.setFlagBit`/`.clearFlagBit`), just a different real base
-- table. `$3117` (the shared tail both branches reach) is a further
-- real trampoline into the already-known `$1F06` cross-bank dispatcher
-- (selector `0x26`, bank 2) -- NOT traced further this pass (its own
-- real-world meaning is HYPOTHESIS, matching this project's own
-- "opaque leaf, callback fires, structure is what's verified" scope
-- for every other closed opaque-leaf opcode).
--
-- DECISIVE REASON this is tractable despite the live 16-bit WRAM
-- comparison: byte consumption is IDENTICAL on both branches (2
-- operand bytes, then always 1 more via `$3727`) -- the branch choice
-- only affects WHICH flag-bit primitive fires and whether the counter
-- gets overwritten, never how many script-stream bytes are consumed.
-- `hasSufficientBudget(amount)` is an optional predicate (defaults to
-- "always sufficient", matching this project's own established
-- `isActorReady`/`isGateClear` "happy path" convention -- no live
-- `$D7BE`/`$D7BF` counter is modeled). `onSufficient(amount)`/
-- `onExhausted(amount)` are optional observers for the 2 real,
-- mutually-exclusive branches.
function StandardScriptHandlers.budgetFlagCommand(hasSufficientBudget, onSufficient, onExhausted)
  return function(stream, cursor)
    local lo, afterLo = ScriptInterpreter.fetch(stream, cursor)
    local hi, afterHi = ScriptInterpreter.fetch(stream, afterLo)
    local amount = lo + hi * 256
    local sufficient = hasSufficientBudget == nil or hasSufficientBudget(amount)
    if sufficient then
      if onSufficient then
        onSufficient(amount)
      end
    else
      if onExhausted then
        onExhausted(amount)
      end
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, afterHi)
    return afterSkip
  end
end

--- Real "fixed WRAM bit SET, then skip 1 byte" handler family
-- (opcodes `0xA3`/`0xA5`/`0xA6`, real ROM `$01D0`/`$01DC`/`$01E8`,
-- found 2026-08-14 -- the whole-corpus scan's own next real untouched
-- blocker after `0x76`). Byte-for-byte:
--   LD A,($C4D4) / SET <bit>,A / LD ($C4D4),A / CALL $3727 / RET
-- The SIMPLEST real handler shape found this whole pass: no leaf call,
-- no branch, no live WRAM predicate needed at all -- a plain bit-set
-- into a fixed real WRAM cell, then the standard trailing `$3727`
-- skip (consumes 1 real byte despite reading no explicit operand, the
-- SAME "zero explicit bytes + 1 via $3727" shape already seen in
-- `.chainedOpaqueEffectCommand`/`.twoBitFieldCommand`). `flags` is a
-- generic mutable state proxy (`.byte` field), same convention as
-- `.setFlagBit`/`.wramBitCommand` above -- kept separate from those
-- since neither has the trailing skip this family's real bytes show.
function StandardScriptHandlers.fixedWramBitSetSkipCommand(flags, bitIndex)
  return function(stream, cursor)
    flags.byte = bit.bor(flags.byte, bit.lshift(1, bitIndex))
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

--- Real "3-way classified flag-bit SET/CLEAR" handler (opcode `0xA9`,
-- real ROM `$0D5F`, found 2026-08-14 -- the whole-corpus scan's own
-- next real untouched blocker after `0x54`). Byte-for-byte:
--   PUSH HL / CALL $220A / CP 0x01 / JR Z,<clear>
--   CP 0x0E / JR Z,<clear> / CP 0x0F / JR Z,<clear>
--   <set>:   LD A,0x7F / CALL $3BEF / POP HL / CALL $3727 / RET
--   <clear>: LD A,0x7F / CALL $3BF9 / POP HL / CALL $3727 / RET
-- Calls an opaque leaf (`$220A`, real effect HYPOTHESIS, matching
-- this project's established scope), classifies its real return value
-- against 3 fixed constants (`0x01`/`0x0E`/`0x0F`), and SETs or
-- CLEARs flag-array bit `0x7F` (the SAME real `$3BEF`/`$3BF9` bit
-- primitives `0xD1`/`0xDA`/`0xDB` already resolved) accordingly. Zero
-- real script-stream operand bytes read directly; the only real byte
-- consumed is the standard trailing `$3727` skip; always continues
-- either way (no real halt in either branch). `classify(rawValue)` is
-- an optional predicate -- given the real leaf's own return value (as
-- reported by `getValue`), returns `true` for the real "clear" branch
-- (value is `0x01`/`0x0E`/`0x0F`) or `false` for "set" -- defaults to
-- classifying via the SAME 3 real constants against `getValue()`'s
-- own result (0 if `getValue` isn't provided, which classifies as
-- "set", the common/majority real case per this project's own
-- established happy-path convention). `onSet()`/`onClear()` fire on
-- their own respective real branch.
function StandardScriptHandlers.threeWayFlagBitCommand(getValue, onSet, onClear)
  return function(stream, cursor)
    -- Same defensive coercion as `.twoBitFieldCommand` -- a generic
    -- caller's own stub `getValue` may return a non-number placeholder
    -- (e.g. this project's own scan tool returns `true` for every
    -- unset callback, regardless of that callback's own real return
    -- type); treat anything non-numeric as the documented default (0).
    local rawValue = getValue and getValue()
    if type(rawValue) ~= "number" then
      rawValue = 0
    end
    local isClear = rawValue == 0x01 or rawValue == 0x0E or rawValue == 0x0F
    if isClear then
      if onClear then
        onClear()
      end
    else
      if onSet then
        onSet()
      end
    end
    local _, afterSkip = ScriptInterpreter.fetch(stream, cursor)
    return afterSkip
  end
end

function StandardScriptHandlers.softReset(onReset)
  return function(_stream, cursor)
    -- Asserted HERE, at real dispatch time, not at factory-construction
    -- time -- a `ScriptRuntime` that never actually reaches opcode
    -- `0xC8` (most real scripts) shouldn't be forced to supply this
    -- callback just to exist. The moment `0xC8` genuinely dispatches
    -- without a real `onReset`, this fails loudly rather than silently
    -- pretending a game restart happened (or silently doing nothing) --
    -- matching this project's own "no silent fallbacks for required
    -- callbacks" rule.
    assert(type(onReset) == "function",
      "StandardScriptHandlers.softReset: real opcode 0xC8 dispatched but ctx.onSoftReset " ..
      "was never provided -- there is no honest default for 'restart the entire game'")
    onReset()
    return cursor
  end
end

return StandardScriptHandlers
