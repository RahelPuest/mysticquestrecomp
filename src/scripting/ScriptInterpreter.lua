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
-- unit of work). Returns `newCursor, opcode, kind` where `kind` is
-- `"default"` (a real, ROM-confirmed no-op opcode), `"handled"` (a
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
function ScriptInterpreter:step(stream, cursor)
  local opcode, afterOpcode = ScriptInterpreter.fetch(stream, cursor)
  local addr = self:handlerAddress(opcode)

  if addr == ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS then
    return afterOpcode, opcode, "default"
  end

  local handler = self.handlers[addr]
  if not handler then
    error(string.format(
      "ScriptInterpreter:step: opcode %#04x (real ROM handler %#06x) has no registered " ..
      "Lua implementation -- this is a real, undecoded opcode, not guessed at", opcode, addr))
  end

  local nextCursor = handler(stream, afterOpcode)
  if nextCursor == nil then
    return cursor, opcode, "halted"
  end
  return nextCursor, opcode, "handled"
end

return ScriptInterpreter
