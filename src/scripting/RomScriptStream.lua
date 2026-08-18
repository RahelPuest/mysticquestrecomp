-- A `ScriptInterpreter`-compatible `stream` view directly over live ROM
-- bytes -- for actually running a decoded script (e.g. the boss-defeat
-- script, see docs/reverse-engineering/events.md's "boss-defeat
-- script: every opcode it actually uses, decoded" section) instead of
-- only replaying it against a synthetic byte array in a test.
--
-- Addressing: this project's handler implementations
-- (StandardScriptHandlers.chain/.skip) manipulate the interpreter's
-- `cursor` as a genuine CPU address in the `$4000`-`$7FFF` bank-window
-- range (see `.chain()`'s doc comment -- `byte1*256+byte2+0x4000` is a
-- CPU address, not a small index), matching the ROM's HL-register
-- semantics. This module returns a proxy table indexed the same way --
-- `stream[cpuAddr]` -- backed by a lazy read straight out of `romData`,
-- converting via the same `bankFileStart + (cpuAddr - 0x4000)` formula
-- this project's `MapTable.lua` already established (`cpuToFile`) for
-- exactly this kind of bank-relative addressing.
--
-- `stream[cpuAddr]` returns nil for any address outside the
-- `$4000`-`$7FFF` bank window -- `ScriptInterpreter.fetch`'s nil-check
-- bounds check then fails loudly rather than silently reading garbage,
-- matching this project's "no silent fallbacks" rule.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local RomScriptStream = {}

--- `bankIndex`: the ROM bank number (0-based, 16KB each) the script
-- lives in -- e.g. 8 for the boss-defeat script (`profile
-- .scriptPointerTable`'s `fileOffset = 0x20F11` is bank 8's table;
-- `0x20F11 / 0x4000 = 8`, matching `verifiedExample.scriptCpuAddress =
-- 0x470F` -> file `0x2070F`, and `0x2070F - 0x70F = 0x20000 = 8*0x4000`).
--
-- HONEST SCOPE: assumes the whole script stays in this one bank for its
-- entire run (true for every jump target this project's decoded
-- handlers can currently produce -- `.chain()`/`.skip()` never
-- themselves change which bank is mapped, only the offset within it).
--
-- UPDATE: a cross-bank script jump does exist in this ROM -- confirmed,
-- not just hedged as "if one exists" anymore. A whole-corpus census
-- found the script-pointer table itself rolls a script's starting
-- address into later banks past table index 666 (see
-- `ScriptPointerTable.resolve`, which correctly computes which bank a
-- given table index's script actually starts in -- use that instead of
-- assuming bank 8 for every index). What remains genuinely unmodeled
-- here (this module itself never switches banks -- a caller must build
-- a new stream for a new bank) is a mid-script cross-bank jump (a real
-- `CHAIN`, opcode `0x02`, landing outside the bank a `RomScriptStream`
-- was built for) -- 7 scripts hit exactly this. Substantially resolved,
-- not fully live-confirmed -- see `StandardScriptHandlers.chain`'s doc
-- comment for the full trail. A caller following a cross-bank CHAIN
-- (via `ctx.onChainTarget`'s `bankOffset` argument) must build a fresh
-- `RomScriptStream` for the new bank and start feeding it to subsequent
-- `ScriptRuntime:step` calls -- see `BossSequenceInterpreter` and
-- `scripts/scan_all_scripts.lua` for two working examples of this
-- pattern.
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

--- Convenience for callers that only have a flat file offset (e.g.
-- `profile.scriptPointerTable.fileOffset`, or any `verifiedExample`'s
-- script address turned back into a file offset) rather than a bank
-- index -- same `bankIndex = floor(fileOffset / 0x4000)` relationship
-- `forBank`'s doc comment derives by hand.
function RomScriptStream.forFileOffset(romData, fileOffset)
  assert(type(fileOffset) == "number" and fileOffset >= 0,
    "RomScriptStream.forFileOffset expects a real, non-negative file offset")
  return RomScriptStream.forBank(romData, math.floor(fileOffset / 0x4000))
end

--- Convenience combining `ScriptPointerTable.resolve` with `.forBank` --
-- the correct, general way to start running any script by its
-- `scriptPointerTable` index (not just the one hand-picked
-- `verifiedExample`), now that a script's starting bank is known to
-- vary (see `.forBank`'s update above). Returns `stream, cpuAddress`,
-- or `nil, "filler"` for an `0xFFFF` filler entry -- same convention as
-- `ScriptPointerTable.resolve` itself.
function RomScriptStream.forScriptIndex(romData, spt, index)
  local ScriptPointerTable = require("src.import.ScriptPointerTable")
  local resolved, err = ScriptPointerTable.resolve(romData, spt, index)
  if not resolved then
    return nil, err
  end
  return RomScriptStream.forBank(romData, resolved.bank), resolved.cpuAddress
end

return RomScriptStream
