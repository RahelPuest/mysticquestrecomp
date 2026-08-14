-- Decodes the real bank-8 room-connectivity table found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/rom-map.md
-- "BREAKTHROUGH: the real room table, found" and "The bank-8 room
-- table, fully documented" for the full evidence writeup (found via two
-- independent, bank-accurate live `CallTracer` traces hitting the exact
-- same code, plus a static ROM dump).
--
-- Real record shape (11 bytes each, VERIFIED against the ROM's own
-- `$026DC`/`$01AF3` routines): bytes 0-1 = a 16-bit LE offset added to
-- $4000 to become the real WRAM `$D390`/`$D391` pointer; byte 2 =
-- unknown (not consumed by the traced routines); bytes 3-4 = a 16-bit
-- LE value that becomes the real WRAM `$D392`/`$D393` room tile-source
-- pointer (the one this project's whole room-chain implementation
-- already reads); byte 5 = unknown; byte 6 = the real dynamic MBC bank
-- number (becomes WRAM `$C3F0`); bytes 7-8 = a 16-bit LE pointer staged
-- to `$C3F2`/`$C3F3` (role not traced further); bytes 9-10 = never read
-- by the traced routines, real but unexplained bytes.
--
-- Table length is itself a real, derived fact, not a guess: this
-- module does not hardcode `16` -- callers pass `profile.roomSelector
-- Table.recordCount` (see rom_profiles.lua's own comment on how that
-- number was determined: byte 6 must be a valid MBC bank number, and
-- this ROM has exactly 16 banks -- record 16 onward immediately
-- produces impossible bank numbers).
--
-- Pure Lua, no love.* calls, so it's headlessly testable like
-- MapTable/ItemTable.

local RoomSelectorTable = {}

local function readU16LE(data, fileOffset)
  local lo, hi = data:byte(fileOffset + 1, fileOffset + 2)
  return lo + hi * 256
end

--- Decode one record (0-based `index`) from `romData` per `table`
-- (`profile.roomSelectorTable`). Returns a table with the real fields:
-- `offsetParam` (the $4000+bytes0-1 value that becomes $D390/$D391),
-- `tileSourcePointer` (bytes 3-4, becomes $D392/$D393 -- the field
-- every other room-chain module in this project already keys off of),
-- `dynamicBank` (byte 6, becomes $C3F0), `stagedPointer` (bytes 7-8,
-- becomes $C3F2/$C3F3), plus the raw bytes for anything not yet decoded
-- (byte 2, byte 5, bytes 9-10).
function RoomSelectorTable.decodeRecord(romData, roomSelectorTable, index)
  assert(type(romData) == "string", "RoomSelectorTable.decodeRecord expects a byte string")
  assert(roomSelectorTable and roomSelectorTable.fileOffset,
    "RoomSelectorTable.decodeRecord expects a profile.roomSelectorTable")
  assert(index >= 0 and index < roomSelectorTable.recordCount,
    "RoomSelectorTable.decodeRecord: index " .. tostring(index) ..
    " out of range (0.." .. (roomSelectorTable.recordCount - 1) .. ")")

  local base = roomSelectorTable.fileOffset + index * roomSelectorTable.recordLength
  local b = { romData:byte(base + 1, base + roomSelectorTable.recordLength) }

  local bytes01 = b[1] + b[2] * 256
  local bytes34 = b[4] + b[5] * 256
  local bytes78 = b[8] + b[9] * 256

  return {
    index = index,
    offsetParam = 0x4000 + bytes01, -- -> WRAM $D390/$D391 (via $01AF3)
    tileSourcePointer = bytes34, -- -> WRAM $D392/$D393 (the already-known room pointer)
    dynamicBank = b[7], -- -> WRAM $C3F0
    stagedPointer = bytes78, -- -> WRAM $C3F2/$C3F3
    byte2 = b[3], -- meaning unknown
    byte5 = b[6], -- meaning unknown
    bytes9_10 = { b[10], b[11] }, -- meaning unknown
  }
end

--- Decode every record in the table. Returns an array, 1-based like
-- every other Lua array in this codebase, each entry's own `.index`
-- field keeping the real 0-based `roomSelector` value.
function RoomSelectorTable.decodeAll(romData, roomSelectorTable)
  local records = {}
  for i = 0, roomSelectorTable.recordCount - 1 do
    records[i + 1] = RoomSelectorTable.decodeRecord(romData, roomSelectorTable, i)
  end
  return records
end

--- Convenience: group record indices (0-based `roomSelector` values) by
-- their real `tileSourcePointer`, i.e. "which roomSelectors land on the
-- same underlying room". Returns `{ [tileSourcePointer] = {selector, ...} }`.
function RoomSelectorTable.groupByTileSource(records)
  local groups = {}
  for _, rec in ipairs(records) do
    local key = rec.tileSourcePointer
    groups[key] = groups[key] or {}
    table.insert(groups[key], rec.index)
  end
  return groups
end

return RoomSelectorTable
