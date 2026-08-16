-- A real `ScriptInterpreter`-compatible `stream` view directly over live
-- ROM bytes -- for actually RUNNING a real, decoded script (e.g. the
-- boss-defeat script, see docs/reverse-engineering/events.md's own
-- "boss-defeat script: every opcode it actually uses, decoded" section)
-- instead of only replaying it against a synthetic byte array in a test.
--
-- Real addressing: this project's own handler implementations
-- (StandardScriptHandlers.chain/.skip) manipulate the interpreter's
-- `cursor` as a genuine CPU address in the real `$4000`-`$7FFF` bank-
-- window range (see `.chain()`'s own doc comment -- `byte1*256+byte2+
-- 0x4000` is a real CPU address, not a small index), matching the real
-- ROM's own HL-register semantics. This module returns a proxy table
-- indexed the SAME way -- `stream[cpuAddr]` -- backed by a lazy read
-- straight out of `romData`, converting via the same `bankFileStart +
-- (cpuAddr - 0x4000)` formula this project's own `MapTable.lua` already
-- established (`cpuToFile`) for exactly this kind of bank-relative
-- addressing.
--
-- `stream[cpuAddr]` returns nil for any address outside the real
-- `$4000`-`$7FFF` bank window -- `ScriptInterpreter.fetch`'s own real
-- nil-check bounds check (see that module's 2026-08-13 doc comment)
-- then fails loudly rather than silently reading garbage, matching this
-- project's "no silent fallbacks" rule.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local RomScriptStream = {}

--- `bankIndex`: the real ROM bank number (0-based, 16KB each) the script
-- lives in -- e.g. 8 for the boss-defeat script (`profile
-- .scriptPointerTable`'s own `fileOffset = 0x20F11` is bank 8's table;
-- `0x20F11 / 0x4000 = 8`, matching `verifiedExample.scriptCpuAddress =
-- 0x470F` -> file `0x2070F`, and `0x2070F - 0x70F = 0x20000 = 8*0x4000`).
--
-- HONEST SCOPE: assumes the WHOLE script stays in this one bank for its
-- entire real run (true for every real jump target this project's own
-- decoded handlers can currently produce -- `.chain()`/`.skip()` never
-- themselves change which bank is mapped, only the offset within it).
--
-- UPDATE 2026-08-13: a real cross-bank script jump DOES exist in this
-- ROM -- CONFIRMED, not just hedged as "if one exists" anymore. A
-- whole-corpus census found the script-pointer table itself rolls a
-- script's own STARTING address into later banks past table index 666
-- (see `ScriptPointerTable.resolve`, which correctly computes which
-- bank a given table index's script actually starts in -- use that
-- instead of assuming bank 8 for every index). What remains genuinely
-- unmodeled HERE (this module itself never switches banks -- a caller
-- must build a NEW stream for a new bank) is a MID-SCRIPT cross-bank
-- jump (a real `CHAIN`, opcode `0x02`, landing outside the bank a
-- `RomScriptStream` was built for) -- 7 real scripts hit exactly this.
-- UPDATE 2026-08-16 (task #81): substantially resolved, not fully
-- live-confirmed -- see `StandardScriptHandlers.chain`'s own doc
-- comment for the full trail. A caller following a real cross-bank
-- CHAIN (via `ctx.onChainTarget`'s own `bankOffset` argument) must
-- build a fresh `RomScriptStream` for the new bank and start feeding
-- IT to subsequent `ScriptRuntime:step` calls -- see
-- `BossSequenceInterpreter` and `scripts/scan_all_scripts.lua` for two
-- real, working examples of this pattern.
function RomScriptStream.forBank(romData, bankIndex)
  assert(type(romData) == "string", "RomScriptStream.forBank expects a byte string")
  assert(type(bankIndex) == "number" and bankIndex >= 0,
    "RomScriptStream.forBank expects a real, non-negative ROM bank index")
  local bankFileStart = bankIndex * 0x4000
  return setmetatable({}, {
    __index = function(_, cpuAddr)
      if type(cpuAddr) ~= "number" or cpuAddr < 0x4000 or cpuAddr > 0x7FFF then
        return nil
      end
      return romData:byte(bankFileStart + (cpuAddr - 0x4000) + 1)
    end,
  })
end

--- Convenience for callers that only have a real flat file offset (e.g.
-- `profile.scriptPointerTable.fileOffset`, or any `verifiedExample`'s
-- own script address turned back into a file offset) rather than a bank
-- index -- same `bankIndex = floor(fileOffset / 0x4000)` relationship
-- `forBank`'s own doc comment derives by hand.
function RomScriptStream.forFileOffset(romData, fileOffset)
  assert(type(fileOffset) == "number" and fileOffset >= 0,
    "RomScriptStream.forFileOffset expects a real, non-negative file offset")
  return RomScriptStream.forBank(romData, math.floor(fileOffset / 0x4000))
end

--- Convenience combining `ScriptPointerTable.resolve` with `.forBank` --
-- the correct, general way to start running ANY real script by its own
-- `scriptPointerTable` index (not just the one hand-picked
-- `verifiedExample`), now that a script's real starting bank is known
-- to vary (see `.forBank`'s own 2026-08-13 update above). Returns
-- `stream, cpuAddress`, or `nil, "filler"` for a real `0xFFFF` filler
-- entry -- same convention as `ScriptPointerTable.resolve` itself.
function RomScriptStream.forScriptIndex(romData, spt, index)
  local ScriptPointerTable = require("src.import.ScriptPointerTable")
  local resolved, err = ScriptPointerTable.resolve(romData, spt, index)
  if not resolved then
    return nil, err
  end
  return RomScriptStream.forBank(romData, resolved.bank), resolved.cpuAddress
end

return RomScriptStream
