-- Resolves an index into `profile.scriptPointerTable` (see
-- `rom_profiles.lua`) into the concrete ROM location that entry
-- actually points to -- bank, CPU address, and file offset.
--
-- VERIFIED (direct follow-up to a user question about whether a bug
-- affected other information -- see docs/reverse-engineering/events.md's
-- matching "CORRECTION" section for the full trail): a whole-corpus
-- census tool originally assumed every one of the table's 1357 entries
-- lives in the same fixed bank as the one, already-VERIFIED example
-- (`spt.verifiedExample`, index 232, bank 8 -- a small raw value that
-- never exercises this). That assumption is wrong for roughly half the
-- table: the raw 16-bit `tableValue` can exceed one bank's 16KB span
-- and roll into later banks -- a deliberate encoding, not noise. The
-- split is exact and structural: every index below 666 has `tableValue
-- <= 0x3FFF` (safely bank-local); starting exactly at index 666,
-- `tableValue` jumps to precisely `0x4000` and keeps climbing from
-- there.
--
-- Decisively confirmed (not just inferred from the clean split):
-- re-decoding the "out of range" entries with the formula below
-- immediately produces bytes that decode as sensible, already-known
-- opcodes -- e.g. index 667's first byte is `0x19`, resolving to
-- handler `$12AE`, the exact `actorSlotPosition` handler this project
-- wired this same session -- not garbage. See this module's tests for
-- the literal byte cross-check.
--
-- HONEST SCOPE: this resolves a script's starting location only.
-- Whether individual opcodes within a script (specifically `CHAIN`,
-- opcode `0x02`) can also jump across this same kind of bank boundary
-- was a separate, open question -- substantially resolved:
-- `StandardScriptHandlers.chain()` now reuses this same "roll into a
-- later bank" formula for its own overflowing operand bytes (see that
-- function's doc comment for the full, honestly-scoped candidate-status
-- reasoning -- not fully live-confirmed, unlike this module's
-- decisively-confirmed table-entry rollover).

local ScriptPointerTable = {}

--- `romData`: the full ROM byte string. `spt`: `profile.scriptPointerTable`
-- (needs `.fileOffset`, `.recordCount`, `.cpuBankOffsetBase`). `index`:
-- 0-based table index. Returns `{bank, cpuAddress, fileOffset,
-- tableValue}`, or `nil, "filler"` for an `0xFFFF` filler entry (see
-- `spt`'s doc comment -- everything at/after the table's boundary is
-- uniform unprogrammed-ROM filler, not a script).
function ScriptPointerTable.resolve(romData, spt, index)
  assert(type(romData) == "string", "ScriptPointerTable.resolve expects a byte string")
  assert(type(spt) == "table" and spt.fileOffset and spt.recordCount,
    "ScriptPointerTable.resolve expects a real scriptPointerTable profile (fileOffset + recordCount)")
  assert(index >= 0 and index < spt.recordCount,
    string.format("ScriptPointerTable.resolve: index %d out of the real table's own %d-record range",
      index, spt.recordCount))

  local entryOffset = spt.fileOffset + index * 2
  local lo = romData:byte(entryOffset + 1)
  local hi = romData:byte(entryOffset + 2)
  local tableValue = lo + hi * 256
  if tableValue == 0xFFFF then
    return nil, "filler"
  end

  local baseBank = math.floor(spt.fileOffset / 0x4000)
  local bankExtra = math.floor(tableValue / 0x4000)
  local bank = baseBank + bankExtra
  local cpuAddress = 0x4000 + (tableValue % 0x4000)
  local fileOffset = bank * 0x4000 + (cpuAddress - 0x4000)

  return {
    bank = bank,
    cpuAddress = cpuAddress,
    fileOffset = fileOffset,
    tableValue = tableValue,
  }
end

return ScriptPointerTable
