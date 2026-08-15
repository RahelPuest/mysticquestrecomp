-- Real port of the ROM's own script/event interpreter core -- see
-- docs/reverse-engineering/rom-map.md "THE real event/script
-- interpreter -- FOUND, FULLY DECODED" for the full live trace this
-- implements.
--
-- Real ROM `$3727` (bank 0, fixed, always mapped) -- the general
-- opcode-fetch primitive, live-confirmed as the real, GENERAL fetch
-- site (not a one-off) by watching WRAM `$D85A` write MANY different
-- values from this one site across a real ~370,000-step trace:
--   LD A,(HL+)          ; opcode = *cursor, cursor advances
--   LD (0xD85A),A         ; $D85A = the current opcode (this project's
--                           ; `opcode` return value)
--   ... cache the advanced HL into $D8B6/$D8B7 (the real, persistent
--       cross-call cursor -- this project's own `cursor` parameter/
--       return value plays that same role, just passed explicitly
--       instead of living in WRAM)
--   RET
--
-- Real dispatch: bank 2's own function 51 (`$4567`, reached via the
-- already-known bank-trampoline convention) does
-- `HL = opcodeTable[opcode]` -- a real, byte-indexed, 2-bytes-per-
-- entry lookup into the 256-entry table `ScriptOpcodeTable.lua`
-- decodes. Ported here as `handlerAddress()`.
--
-- What this does NOT claim to do: interpret the meaning of any opcode
-- this project hasn't actually decoded. `step()` fails loudly (real
-- Lua `error()`, not a silent skip) for any opcode whose real handler
-- address is neither the known genuine no-op (`ScriptOpcodeTable
-- .DEFAULT_HANDLER_ADDRESS`, real ROM-confirmed as "fetch next opcode
-- and continue") nor has a Lua implementation registered via
-- `registerHandler` -- this project does not guess at undecoded
-- opcode semantics, per its own "no silent fallbacks" rule.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")

local ScriptInterpreter = {}
ScriptInterpreter.__index = ScriptInterpreter

--- `opcodeEntries`: the real, decoded 256-entry table (see
-- `ScriptOpcodeTable.decode`) -- `opcodeEntries[opcode + 1]` is the
-- real ROM handler address for that opcode.
function ScriptInterpreter.new(opcodeEntries)
  assert(type(opcodeEntries) == "table" and #opcodeEntries == 256,
    "ScriptInterpreter.new expects the real 256-entry opcode table (see ScriptOpcodeTable.decode)")
  return setmetatable({
    opcodeEntries = opcodeEntries,
    handlers = {}, -- [handlerAddress] = function(stream, cursor) -> nextCursor
  }, ScriptInterpreter)
end

--- Real `$3727` port: fetch one opcode byte and advance the cursor.
-- `stream`: any table supporting `stream[cursor]` (a real script's own
-- data). `cursor`: mirrors HL -- for a plain 1-based synthetic test
-- array this is just a small index, but for a LIVE ROM-backed stream
-- (see `RomScriptStream.lua`) it's a genuine CPU address in the real
-- `$4000`-`$7FFF` bank window, matching `.chain()`/`.skip()`'s own real
-- CPU-address arithmetic (see StandardScriptHandlers.lua). Returns
-- `opcode, newCursor`. A static function (no interpreter state needed)
-- since the real ROM routine's own logic doesn't touch the opcode
-- table either -- kept separate from `step()` so callers needing just
-- the raw fetch (e.g. a handler consuming its own operand bytes) can
-- reuse the exact same primitive.
--
-- CORRECTED (2026-08-13, "baue den interpreter ein"): used to bounds-
-- check via `cursor >= 1 and cursor <= #stream` -- correct for a plain
-- 1-based array, but `#stream` is meaningless (always 0, no matter the
-- real content) for a sparse/proxy table keyed by CPU address, like a
-- live ROM-backed stream -- every real fetch against one would have
-- failed this check regardless of the real byte being perfectly valid.
-- Bounds-checks on the fetched VALUE instead (nil = genuinely missing,
-- whether "past a small synthetic array's own end" or "outside a live
-- stream's real bank-window range") -- behaviorally identical for every
-- existing plain-array caller (a byte can never be a real, valid `nil`
-- entry either way), and now also correct for a sparse one.
function ScriptInterpreter.fetch(stream, cursor)
  local value = stream[cursor]
  assert(value ~= nil, string.format(
    "ScriptInterpreter.fetch: cursor %s out of stream bounds (nil byte -- past a synthetic " ..
    "stream's own end, or outside a live ROM-backed stream's real address range)", tostring(cursor)))
  return value, cursor + 1
end

--- Real table lookup: opcode (0-255) -> the real ROM handler address.
function ScriptInterpreter:handlerAddress(opcode)
  return self.opcodeEntries[opcode + 1]
end

--- Register a real Lua implementation for the handler at
-- `handlerAddress` (e.g. `ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS`,
-- or any other real, decoded handler address). `fn(stream, cursor) ->
-- nextCursor` receives the cursor positioned right after the opcode
-- byte itself (matching the real ROM's own HL-after-fetch convention)
-- and must return the cursor after consuming whatever real operand
-- bytes that opcode needs (0 bytes for opcodes with no operands).
function ScriptInterpreter:registerHandler(handlerAddress, fn)
  self.handlers[handlerAddress] = fn
end

--- One real fetch-and-dispatch step (the real ROM's own per-opcode
-- unit of work). Returns `newCursor, opcode, kind, pin` where `kind`
-- is `"default"` (a real, ROM-confirmed no-op opcode), `"handled"` (a
-- registered Lua implementation ran and advanced the cursor), or
-- `"halted"` (see below). Raises a real Lua error for any opcode that
-- is neither known-default nor registered -- see this module's own
-- doc comment.
--
-- HALT SUPPORT (2026-08-12, added wiring opcode `0xFF`'s own real
-- sub-dispatch family -- see events.md's "0xFF sub-table" sections):
-- several real ROM handlers are genuine CONDITIONAL HALTS -- they
-- return WITHOUT calling the real `$3727` fetch-next-opcode primitive
-- while some condition holds, letting the SAME opcode re-dispatch on
-- the interpreter's next tick instead of advancing (see
-- `ScriptOpcodeTable`'s own sub-table doc comment for the real
-- disassembled family). A registered handler signals this real "not
-- ready yet" case by returning `nil` instead of a cursor -- `step()`
-- then returns the ORIGINAL `cursor` unchanged (kind `"halted"`) so a
-- caller driving this once per real game tick naturally re-dispatches
-- the exact same opcode next time, matching the real ROM's own
-- behavior, without the caller needing to know which opcodes can halt.
--
-- PINNING (2026-08-15, task #144/#145 -- live mgba $D8B6/$D8B7 write-
-- tracing found the REAL mechanism behind opcode `0x04`'s own classifier
-- ($333D): the real ROM keeps WRAM `$D85A` ("current opcode") PINNED at
-- `0x04` across MANY real per-character ticks while the real persistent
-- cursor keeps advancing underneath it through raw TEXT bytes -- each
-- advance goes through `$36D0` directly, WITHOUT ever re-calling `$3727`
-- (confirmed live: `$36D0`'s own body is `INC HL / cache into $D8B6/
-- $D8B7 / LD A,0x04 / LD ($D85A),A / RET` -- no `CALL $3727` at all).
-- This project's OLD architecture had no way to express "re-dispatch
-- THIS SAME handler for the next tick, even though the cursor moved and
-- the raw byte now sitting there isn't a fresh opcode identifier at
-- all" -- it always re-read `stream[cursor]` as a brand-new top-level
-- opcode selection on every call, which happened to "succeed" for many
-- ticks by sheer coincidence (real TEXT byte values occasionally
-- colliding with OTHER real opcodes' own numeric IDs) before finally
-- landing on a genuinely undecoded one -- a real, structural bug, not a
-- missing opcode.
--
-- `pinnedOpcode`, if provided by the caller, bypasses the normal
-- `fetch()` (which would misread real DATA as a fresh opcode byte) --
-- the pinned handler is invoked directly against the CURRENT `cursor`
-- (there is no opcode byte to consume for a pinned re-dispatch, since
-- the real ROM doesn't read one either). A handler may now return a
-- SECOND value, `pin` (boolean): `true` means "keep dispatching ME on
-- this exact opcode for whatever cursor I just returned, don't let the
-- caller re-derive the opcode from the byte now sitting there" --
-- modeling the real ROM's own `$D85A`-pinning technique directly. Every
-- OTHER existing handler (the ~190 already registered) returns only one
-- value; Lua's multi-return semantics make `pin` default to `nil`
-- (falsy) for all of them -- zero behavior change, fully backward
-- compatible.
function ScriptInterpreter:step(stream, cursor, pinnedOpcode)
  local opcode, afterOpcode, addr

  if pinnedOpcode then
    -- Pinned re-dispatch: `cursor` already points at real DATA (a text
    -- character or control-code byte), not an opcode identifier to
    -- consume -- see this function's own "PINNING" doc comment above.
    opcode = pinnedOpcode
    afterOpcode = cursor
    addr = self:handlerAddress(opcode)
  else
    opcode, afterOpcode = ScriptInterpreter.fetch(stream, cursor)
    addr = self:handlerAddress(opcode)
  end

  if addr == ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS then
    return afterOpcode, opcode, "default", false
  end

  local handler = self.handlers[addr]
  if not handler then
    error(string.format(
      "ScriptInterpreter:step: opcode %#04x (real ROM handler %#06x) has no registered " ..
      "Lua implementation -- this is a real, undecoded opcode, not guessed at", opcode, addr))
  end

  local nextCursor, pin = handler(stream, afterOpcode)
  if nextCursor == nil then
    -- Halted: re-dispatch the SAME opcode next time. If we were
    -- already pinned, stay pinned (matches the real ROM: a halt inside
    -- a pinned classify-loop doesn't release the pin either).
    return cursor, opcode, "halted", pinnedOpcode ~= nil
  end
  return nextCursor, opcode, "handled", (pin == true)
end

return ScriptInterpreter
