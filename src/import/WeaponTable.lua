-- Decodes the weapon/equipment name+stat table found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/rom-map.md "Weapon/
-- equipment table" for the full evidence writeup (status: PARTIALLY
-- VERIFIED -- names and the 16-byte record width are confirmed via a
-- live UI cross-check: the in-game menu's equipped-weapon readout,
-- "Breit", was found verbatim in the ROM at this table; the stat bytes
-- and the table's true start/end boundaries are not confirmed).
--
-- Record shape differs from ItemTable's: 5 stat bytes, then a category/
-- icon byte, THEN the name (not name-first) -- see rom-map.md.
--
-- This module only knows the *record shape*; every actual offset comes
-- from a profile (src/import/rom_profiles.lua's `weaponTable` field).
-- Pure Lua, no love.* calls, so it's headlessly testable.

local TextDecoder = require("src.import.TextDecoder")

local WeaponTable = {}

--- Decode all records from `weaponTable` profile info against `romData`.
-- Returns an array of:
--   { index, name = <string>, categoryByte = <0-255>,
--     statBytes = <5-byte string, bytes 0-4>, raw = <16-byte string> }
-- 1-based like every other Lua array in this codebase. `statBytes`/
-- `categoryByte` are UNKNOWN meaning -- returned raw for callers to
-- experiment with, not interpreted here (per the project's "don't guess
-- silently" rule).
function WeaponTable.decode(romData, weaponTable)
  assert(type(romData) == "string", "WeaponTable.decode expects a byte string")
  assert(weaponTable and weaponTable.fileOffset,
    "WeaponTable.decode expects a profile.weaponTable table")

  local recordLength = weaponTable.recordLength
  local nameOffset = weaponTable.nameOffset
  local records = {}

  for i = 0, weaponTable.recordCount - 1 do
    local recordFile = weaponTable.fileOffset + i * recordLength
    local raw = romData:sub(recordFile + 1, recordFile + recordLength)
    local name = TextDecoder.decodeString(raw, nameOffset)
    local categoryByte = raw:byte(nameOffset) -- byte right before the name
    local statBytes = raw:sub(1, nameOffset - 1)

    records[i + 1] = {
      index = i,
      name = name,
      categoryByte = categoryByte,
      statBytes = statBytes,
      raw = raw,
    }
  end

  return records
end

--- Groups already-decoded `records` (from `WeaponTable.decode`) by
-- their real `categoryByte`, in ascending categoryByte order -- same
-- shape/intent as `EnemySpeciesTable.groupBySpecies`/
-- `ItemTable.groupByCategory`.
--
-- FOUND, 2026-08-15 (catalog plan Phase 2, direct user request "Items
-- in mehr auswählbare Kategorien unterteilen"): grouping the real,
-- live-decoded 48-record weapon/equipment table by `categoryByte`
-- produces 13 real, non-overlapping groups. Three of them (`160`,
-- `161`, `162`; 9/7/9 records) show a clear, real, human-readable
-- material/elemental TIER PROGRESSION when read in ROM order (e.g.
-- `162`: Bronze/Eisen/Silber/Gold/Flamme/Eis/Drache/Samurai/Opal) --
-- strongly suggestive of 3 real equipment SLOTS (weapon/armor/helm or
-- similar), but the exact real slot each byte value corresponds to is
-- NOT confirmed (no live equip-slot cross-check has been done -- see
-- `docs/roadmap.md` task #128, "Trace $5BA7 (attack-side equip
-- lookup)", still pending) -- so this function groups by the real
-- byte only, it does not name or claim a specific slot. The remaining
-- 10 categoryByte values are small groups (1-3 records each) --
-- individual, named pieces of equipment (e.g. `165`: Axt/Streit/Zeus)
-- rather than a tier ladder.
--
-- `sizeClass` is a plain, honest, SIZE-only label (`"group"` for
-- categoryByte values shared by >=5 records, `"single"` otherwise),
-- same convention as `ItemTable.groupByCategory` -- see its own doc
-- comment for why this stays size-only rather than naming a slot.
function WeaponTable.groupByCategory(records)
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

return WeaponTable
