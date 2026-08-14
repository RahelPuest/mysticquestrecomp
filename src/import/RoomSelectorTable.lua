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

--- Real, VERIFIED (2026-08-14, direct instruction "versuche andere
-- methoden" -- cross-referenced against the external FFA-Disassembly
-- project's own documented US-ROM `MAP_HEADER` format: "tilesetGfx,
-- metatiles, mapRoomPointers, ..."): `offsetParam` was previously
-- undocumented beyond "meaning unknown, not consumed by traced
-- routines except being staged to WRAM." It is this record's own real
-- `mapRoomPointers` field, the same field the external US disassembly
-- names -- resolved the SAME WAY as `tileSourcePointer` (a bank-
-- relative CPU address -> file offset), but relative to THIS record's
-- own `dynamicBank` (byte 6), not a fixed bank.
--
-- Confirmed via an EXACT byte match, not inference: roomSelector 0's
-- own `mapRoomPointers` resolves to file `0x14000` -- BYTE-IDENTICAL
-- to `profile.mapTable`'s own already-VERIFIED header+pointer-table
-- start (`00 03 10 10` followed by real pointer entries); roomSelector
-- 1's own resolves to file `0x18000` -- BYTE-IDENTICAL to `profile.
-- mapTableBank6`'s own header (`00 04 08 08` + real pointer entries).
-- This is the real mechanism connecting `roomSelectorTable`'s 16
-- "maps" to the 320-room bank-5/bank-6 catalog: roomSelector 0 "owns"
-- all of bank 5's 256 records as its own room list; roomSelector 1
-- owns all of bank 6's 64. See rom-map.md's own dated writeup for the
-- full trace -- INCLUDING the honest caveat this does NOT resolve the
-- separate, still-open "which metatile table does an individual
-- catalog record use" question: the one CONFIRMED real room for these
-- two selectors, `startRoom`, does not even use the metatile-table
-- pipeline at all (its own real tiles are live-captured direct
-- offsets, see rom_profiles.lua's own `graphics.startRoom.tileOffsets`),
-- so it can't cross-validate a metatile-table guess derived the same
-- way `tileSourcePointer` is.
function RoomSelectorTable.resolveMapRoomPointersFileOffset(record)
  assert(type(record) == "table" and record.dynamicBank and record.offsetParam,
    "RoomSelectorTable.resolveMapRoomPointersFileOffset expects a decoded record (dynamicBank/offsetParam)")
  return record.dynamicBank * 0x4000 + (record.offsetParam - 0x4000)
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
