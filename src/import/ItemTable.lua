-- Decodes the item/spell name+stat table found in the Mystic Quest (EU)
-- ROM -- see docs/reverse-engineering/rom-map.md "Item/spell table" for
-- the full evidence writeup (status: PARTIALLY VERIFIED -- names, the
-- 16-byte record width, and the per-category ID byte (byte 15) are
-- confirmed; bytes 9-14's meaning is not).
--
-- This module only knows the *record shape*; every actual offset comes
-- from a profile (src/import/rom_profiles.lua's `itemTable` field), per
-- the project rule that ROM-version-specific knowledge stays centralized
-- there. Pure Lua, no love.* calls, so it's headlessly testable like
-- MapTable/GBTile.

local TextDecoder = require("src.import.TextDecoder")

local ItemTable = {}

--- Decode all records from `itemTable` profile info against `romData`.
-- Returns an array of:
--   { index, name = <string>, categoryByte = <0-255>, id = <0-255>,
--     raw = <16-byte string> }
-- 1-based like every other Lua array in this codebase. `categoryByte`
-- is the record's byte 8 (0-based) -- HYPOTHESIS: a category/type flag,
-- correlated with but not independently proven beyond the item/spell
-- boundary match (see rom-map.md). `id` is byte 15 -- VERIFIED as a
-- real per-category counter (resets to 0 exactly at
-- itemTable.categoryBoundaryRecord).
function ItemTable.decode(romData, itemTable)
  assert(type(romData) == "string", "ItemTable.decode expects a byte string")
  assert(itemTable and itemTable.fileOffset,
    "ItemTable.decode expects a profile.itemTable table")

  local recordLength = itemTable.recordLength
  local nameLength = itemTable.nameLength
  local records = {}

  for i = 0, itemTable.recordCount - 1 do
    local recordFile = itemTable.fileOffset + i * recordLength
    local raw = romData:sub(recordFile + 1, recordFile + recordLength)
    local name = TextDecoder.decodeString(raw, 0)
    local categoryByte = raw:byte(nameLength + 1)
    local id = raw:byte(recordLength)

    records[i + 1] = {
      index = i,
      name = name,
      categoryByte = categoryByte,
      id = id,
      raw = raw,
    }
  end

  return records
end

return ItemTable
