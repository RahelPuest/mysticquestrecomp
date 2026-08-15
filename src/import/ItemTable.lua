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
--
-- FOUND, 2026-08-15 (extending the catalog for the monster/npc/item
-- census): records 8-19 (the real spell section, per
-- `itemTable.categoryBoundaryRecord=8`) do NOT store their name at
-- offset 0 like records 0-7 (consumable items) do -- byte 0 there is
-- instead a real, consistent PREFIX byte (`0xA9` for records 8-17,
-- `0xAF` for 18-19/22-27, `0xD7` for the one still-unexplained
-- anomaly at record 21) and the real name text starts at offset 1.
-- Live-verified: offset-1 decoding of records 8-19 produces clean,
-- real German spell names ("Lebe"[n]/"S-Lebe"/"Magi"[e]/"S-Magi"/
-- "Elixier"/"Salbe"/"Auge"/"Bewege"/"Spruch"/"Allheil"/"Stille"/
-- "Schlaf" -- classic Seiken Densetsu 1 spell names). The real
-- meaning of the prefix byte itself (spell tier? icon ID?) is NOT
-- decoded -- returned as `namePrefixByte` for a future pass, not
-- guessed at.

local TextDecoder = require("src.import.TextDecoder")

local ItemTable = {}

--- Decode all records from `itemTable` profile info against `romData`.
-- Returns an array of:
--   { index, name = <string>, categoryByte = <0-255>, id = <0-255>,
--     namePrefixByte = <0-255 or nil>, raw = <16-byte string> }
-- 1-based like every other Lua array in this codebase. `categoryByte`
-- is the record's byte 8 (0-based) -- HYPOTHESIS: a category/type flag,
-- correlated with but not independently proven beyond the item/spell
-- boundary match (see rom-map.md). `id` is byte 15 -- VERIFIED as a
-- real per-category counter (resets to 0 exactly at
-- itemTable.categoryBoundaryRecord).
--
-- `name` tries offset 0 first (the real consumable-item shape); if
-- that decodes empty, retries at offset 1 (the real spell shape found
-- 2026-08-15, see this module's own top-of-file doc comment) and, if
-- THAT succeeds, records the real skipped byte 0 as `namePrefixByte`
-- -- an honest "try the known real shapes, don't guess a third one"
-- fallback, not silent papering-over: a record where BOTH attempts
-- come back empty still surfaces as `name = ""`, not a fabricated
-- guess.
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
    local namePrefixByte = nil
    if name == "" then
      local altName = TextDecoder.decodeString(raw, 1)
      if altName ~= "" then
        name = altName
        namePrefixByte = raw:byte(1)
      end
    end
    local categoryByte = raw:byte(nameLength + 1)
    local id = raw:byte(recordLength)

    records[i + 1] = {
      index = i,
      name = name,
      categoryByte = categoryByte,
      id = id,
      namePrefixByte = namePrefixByte,
      raw = raw,
    }
  end

  return records
end

--- Groups already-decoded `records` (from `ItemTable.decode`) by their
-- real `categoryByte`, in ascending categoryByte order -- same shape/
-- intent as `EnemySpeciesTable.groupBySpecies`, just keyed by a
-- scattered byte value instead of consecutive identical rows.
--
-- FOUND, 2026-08-15 (catalog plan Phase 2, direct user request "Items
-- in mehr auswählbare Kategorien unterteilen"): grouping the real,
-- live-decoded 41-record item/spell table by `categoryByte` produces
-- 6 real, non-overlapping groups (`0`=22, `64`=13, `65`=4, `66`=3,
-- `67`=1, `128`=16 -- see `tests/import/item_table_test.lua` for the
-- exact locked-in counts). What each byte VALUE actually represents
-- (consumable/spell tier? icon sheet index?) is still genuinely
-- UNKNOWN -- this function only groups by the real, observed byte,
-- it does not name or interpret the groups. One real, honest
-- correlation IS independently confirmed by inspection (not asserted
-- here in code, since it's about NAME CONTENT, not the grouping
-- itself): `categoryByte=64`'s 13 records correlate heavily with
-- names that fail to decode into plausible German words -- flagged in
-- docs, not encoded as a boolean here, since "looks like a real word"
-- has no reliable, honest programmatic test.
--
-- `sizeClass` is a plain, honest, SIZE-only label (`"group"` for
-- categoryByte values shared by >=5 records, `"single"` otherwise) --
-- it says nothing about what the category itself means, only how many
-- real records share it. Useful for a UI to visually distinguish "a
-- real, multi-item category" from "an outlier/one-off record" without
-- claiming a specific real-world slot name (e.g. "potion"/"material")
-- this project has not confirmed.
function ItemTable.groupByCategory(records)
  local groups = {}
  local order = {}
  for _, r in ipairs(records) do
    if not groups[r.categoryByte] then
      groups[r.categoryByte] = { categoryByte = r.categoryByte, count = 0, records = {} }
      order[#order + 1] = r.categoryByte
    end
    local g = groups[r.categoryByte]
    g.count = g.count + 1
    g.records[g.count] = r
  end
  table.sort(order)
  local result = {}
  for i, categoryByte in ipairs(order) do
    local g = groups[categoryByte]
    g.sizeClass = (g.count >= 5) and "group" or "single"
    result[i] = g
  end
  return result
end

return ItemTable
