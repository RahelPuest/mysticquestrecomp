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

return WeaponTable
