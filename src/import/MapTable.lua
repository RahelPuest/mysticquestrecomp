-- Decodes the bank-5 map/room-block pointer table found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/rom-map.md "Maps" for the
-- full evidence writeup.
--
-- BREAKTHROUGH (2026-08-09): the table's real per-map header AND its
-- room-data compression scheme are now VERIFIED, not just hypothesized.
-- The 4 bytes immediately before the pointer table (`mapTable
-- .bankFileStart`, i.e. CPU `$4000-$4003` in bank 5) match the format
-- the external FFA-Disassembly project documented for the US cartridge's
-- own per-map header exactly: `[encodingMode, rleLength, gridHeight,
-- gridWidth]`. In this EU ROM that's `[0x00, 0x03, 0x10, 0x10]` --
-- encodingMode 0 (RLE), rleLength 3, and a 16x16 grid whose 256 cells
-- match this project's own already-VERIFIED 256-record count exactly
-- (not a coincidence -- see the record-count field itself, independently
-- discovered by a totally different method, a pointer-density scan).
-- Applying the documented RLE rule (a blob byte with its high bit set
-- means "repeat `byte & 0x7F`, `rleLength` times"; otherwise it's one
-- literal tile index) with this real, header-derived `rleLength=3`
-- decodes **all 255 data blobs to an exact, uniform 80 tiles (20x4)** --
-- tested against every other plausible rleLength (1-11) for comparison,
-- every one of which decodes 0/255 blobs to a clean length, so this is
-- not an artifact of blob-length parity. Rendered against the confirmed
-- environment tileset (see docs/progress.md; the original renderer,
-- `RoomBackground.lua`, was removed 2026-08-12 as dead code once
-- Milestone 3's own real room-table composition breakthrough
-- superseded it -- see rom-map.md), the decoded tiles are clearly
-- coherent dungeon-wall art (hedge borders,
-- brick trim, torches), not noise. See rom-map.md "Maps" for the full
-- writeup, including what's still open (how multiple records compose
-- into an on-screen room -- naive 4-record vertical stacking did NOT
-- produce a unified box, so that part remains unverified).
--
-- This module only knows the *table shape* (word-aligned pointer pairs,
-- header terminated by 0xFF, data blob bounded by the next pointer) plus
-- the now-VERIFIED per-map header/RLE format -- every actual offset comes
-- from a profile (src/import/rom_profiles.lua's `mapTable` field), per
-- the project rule that ROM-version-specific knowledge stays centralized
-- there; only the *parsing logic* (byte meanings, RLE rule), not any
-- literal offset or ROM value, lives in this file. Pure Lua, no love.*
-- calls, so it's headlessly testable like GBTile/RomIdentity.

local MapTable = {}

local function readU16LE(data, fileOffset)
  local lo, hi = data:byte(fileOffset + 1, fileOffset + 2)
  return lo + hi * 256
end

--- Convert a bank-relative CPU address ($4000-$7FFF) to a flat file offset,
-- given the bank's own file start (profile.mapTable.bankFileStart).
local function cpuToFile(bankFileStart, cpuAddr)
  return bankFileStart + (cpuAddr - 0x4000)
end

--- Decode all records from `mapTable` profile info against `romData`.
-- Returns an array of { index, header = <string>, blob = <string> },
-- 1-based like every other Lua array in this codebase.
--
-- header: the raw bytes of the short, 0xFF-terminated header entry
--   (0xFF itself included, so callers can see the real terminator).
-- blob: the raw bytes of the variable-length data blob, bounded by the
--   *next* record's header pointer (or, for the last record, by
--   `mapTable.recordCount`'s implied end -- there is no known explicit
--   terminator inside a blob itself, see rom-map.md).
--
-- NAMING CORRECTED (2026-08-14, direct user question "welche tiles
-- gehören zu den räumen"): "header" is a MISNOMER kept only for
-- backward compatibility (the field/param names below are unchanged,
-- a rename would be a wider, separate refactor). The external
-- FFA-Disassembly project's own docs name this SAME pointer-pair
-- position "script" (not "header"), and testing it directly against
-- this project's own already-built `ScriptInterpreter`/
-- `ScriptOpcodeTable` confirms that: these bytes decode as REAL,
-- valid opcodes resolving to already-catalogued ROM handler addresses
-- (e.g. bank-5 record 0's own first byte, `0x76`, resolves to the
-- real, ALREADY-DOCUMENTED `$28C2`/`$2879` "~70-opcode actor action"
-- family, see events.md's "Back to the primary table" section -- a
-- WRAM `$C200` actor-struct command, NOT a graphics/tileset selector).
-- So: every one of the 320 room-catalog records carries its own real,
-- tiny per-room EVENT SCRIPT (likely room-entry NPC/actor setup),
-- structurally consistent with the external doc's "script, tiles"
-- pointer-pair naming -- but this does NOT resolve the separate,
-- still-open "which metatile table" question (see rom_profiles.lua's
-- own `genericCatalogMetatileTableFileOffset` doc comment) -- a real,
-- different kind of per-room data, honestly reported as a negative
-- result for THAT specific question.
function MapTable.decode(romData, mapTable)
  assert(type(romData) == "string", "MapTable.decode expects a byte string")
  assert(mapTable and mapTable.pointerTableFileOffset,
    "MapTable.decode expects a profile.mapTable table")

  local ptrOffset = mapTable.pointerTableFileOffset
  local recordCount = mapTable.recordCount
  local bankFileStart = mapTable.bankFileStart
  local entryCount = recordCount * 2

  -- Read every pointer up front (each is 2 bytes).
  local ptrs = {}
  for i = 0, entryCount - 1 do
    ptrs[i + 1] = readU16LE(romData, ptrOffset + i * 2)
  end

  local records = {}
  for i = 0, recordCount - 1 do
    local headerAddr = ptrs[i * 2 + 1]
    local dataAddr = ptrs[i * 2 + 2]
    local headerFile = cpuToFile(bankFileStart, headerAddr)
    local dataFile = cpuToFile(bankFileStart, dataAddr)

    -- The header is self-terminating (ends in 0xFF); find that terminator
    -- rather than trusting the next pointer, since the next pointer is the
    -- *data* blob's start, not the header's end.
    local headerEnd = headerFile
    while romData:byte(headerEnd + 1) ~= 0xFF do
      headerEnd = headerEnd + 1
      assert(headerEnd - headerFile < 64,
        "MapTable.decode: header " .. i .. " has no 0xFF terminator within 64 bytes")
    end
    local header = romData:sub(headerFile + 1, headerEnd + 1)

    -- The data blob has no self-terminator; its end is the next record's
    -- header pointer (or, for the last record, unknown -- callers must not
    -- assume a length for it without an explicit blobEndFile).
    local nextHeaderAddr = ptrs[i * 2 + 3]
    local blob, blobEndFile
    if nextHeaderAddr then
      blobEndFile = cpuToFile(bankFileStart, nextHeaderAddr)
      blob = romData:sub(dataFile + 1, blobEndFile)
    end

    records[i + 1] = {
      index = i,
      headerAddr = headerAddr,
      dataAddr = dataAddr,
      header = header,
      blob = blob, -- nil for the final record (no known end)
    }
  end

  return records
end

--- Decode one record's data blob into tile indices (0-255, one per byte)
-- -- a convenience for renderers; does not itself decode graphics (see
-- GBTile for that). Superseded for real room content by `MapTable.rle
-- Decode` (see module doc comment) -- kept as a raw/no-op convenience
-- for callers that genuinely want the literal bytes (e.g. inspecting the
-- compressed stream itself), not as "the" room decoder.
function MapTable.blobToTileIndices(blob)
  local indices = {}
  for i = 1, #blob do
    indices[i] = blob:byte(i)
  end
  return indices
end

--- Read the 4-byte per-map header immediately preceding the pointer
-- table (VERIFIED format, see module doc comment): `[encodingMode,
-- rleLength, gridHeight, gridWidth]` at `mapTable.bankFileStart`.
function MapTable.readMapHeader(romData, mapTable)
  assert(type(romData) == "string", "MapTable.readMapHeader expects a byte string")
  local base = mapTable.bankFileStart
  local b0, b1, b2, b3 = romData:byte(base + 1, base + 4)
  return {
    encodingMode = b0, -- 0 = RLE (VERIFIED for this ROM), 1 = Templated (not implemented)
    rleLength = b1,
    gridHeight = b2,
    gridWidth = b3,
  }
end

--- Decode one data blob per the VERIFIED RLE scheme (module doc comment):
-- a byte with its high bit (0x80) set means "repeat `byte & 0x7F`,
-- `rleLength` times"; any other byte is one literal tile index (0-127).
-- Pure function, `rleLength` passed explicitly (read it once via
-- `MapTable.readMapHeader`, not re-read per call) -- no ROM-specific
-- constant is hardcoded here.
function MapTable.rleDecode(blob, rleLength)
  assert(type(rleLength) == "number" and rleLength > 0,
    "MapTable.rleDecode expects a positive rleLength (see MapTable.readMapHeader)")
  local indices = {}
  local n = 0
  for i = 1, #blob do
    local byte = blob:byte(i)
    if byte >= 0x80 then
      local tile = byte - 0x80
      for _ = 1, rleLength do
        n = n + 1
        indices[n] = tile
      end
    else
      n = n + 1
      indices[n] = byte
    end
  end
  return indices
end

--- Convenience: decode record `recordIndex`'s (1-based) tile content
-- using the map's own real header (encoding mode + rleLength). Fails
-- loudly (per project rule: no silent fallback on unknown data) if the
-- header names an encoding mode this decoder doesn't implement yet
-- (Templated, mode 1 -- documented to exist for the US ROM but not yet
-- confirmed present or needed for this EU ROM's 256 records, all of
-- which this project has only ever seen encodingMode 0/RLE for).
function MapTable.decodeRoomTiles(romData, mapTable, recordIndex)
  local header = MapTable.readMapHeader(romData, mapTable)
  assert(header.encodingMode == 0,
    "MapTable.decodeRoomTiles: unimplemented encodingMode " ..
    tostring(header.encodingMode) .. " (only RLE/mode 0 is implemented -- " ..
    "see module doc comment)")
  local records = MapTable.decode(romData, mapTable)
  local record = records[recordIndex]
  assert(record and record.blob, "MapTable.decodeRoomTiles: record " ..
    tostring(recordIndex) .. " has no data blob")
  return MapTable.rleDecode(record.blob, header.rleLength), header
end

--- Try to extract a real `(group, action)` pair from a record's own
-- "header" bytes (2026-08-14, direct follow-up to "verfolge mal diese
-- eventscripte und schaue dir an was diese machen" -- see this
-- module's own "NAMING CORRECTED" doc comment above `MapTable.decode`
-- for why "header" is really a per-room event-script pointer).
--
-- The first (or, if that byte resolves to the real, ROM-confirmed
-- no-op `ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS`, the second)
-- opcode byte is resolved through the real `scriptOpcodeTable` to its
-- own real ROM handler address. If that address holds the EXACT,
-- already-documented "ACTOR_ACTION" family instruction sequence
-- (`src/import/ScriptOpcodeTable.lua`'s own `ACTOR_ACTION_HANDLER_
-- ADDRESS_*` constants, events.md's "Back to the primary table"
-- section: `CALL $28C2 / ADD A,<group> / LD C,A / LD A,<action> /
-- CALL $2879 / RET`), the real, baked-in `group`/`action` constants
-- are read directly out of the handler's own bytes -- not inferred,
-- not guessed, the literal immediate operands of that specific real
-- routine. Returns `nil` if neither byte matches (a real, honest
-- "not this family" result, not a fabricated default).
--
-- HONEST SCOPE: this identifies WHICH real actor-action command a
-- room's own entry script enqueues (see `ScriptOpcodeTable.lua`'s own
-- corrected note: a real actor-COMMAND-QUEUE mechanism, `$C4E0`/
-- `$C5A0`, NOT room-selection or spawn-coordinate data) -- it does
-- NOT reveal which TILES a room uses (a separate, still-open
-- question, see rom_profiles.lua's own `genericCatalogMetatileTable
-- FileOffset` doc comment) and does NOT explain the exact real-world
-- GAMEPLAY MEANING of a given `action` value (open per events.md).
--
-- All handler addresses seen for this family so far are `< 0x4000`
-- (fixed bank 0, file offset == CPU address directly, same
-- convention already established for `ScriptOpcodeTable.DEFAULT_
-- HANDLER_ADDRESS` elsewhere) -- a handler `>= 0x4000` is honestly
-- reported as "not resolvable this way" (`nil`) rather than guessing
-- a bank.
local ACTOR_ACTION_PATTERN_PREFIX = string.char(0xCD, 0xC2, 0x28) -- CALL $28C2
local ACTOR_ACTION_PATTERN_MID = string.char(0x4F, 0x3E) -- LD C,A / LD A,n
local ACTOR_ACTION_PATTERN_SUFFIX = string.char(0xCD, 0x79, 0x28) -- CALL $2879

local function matchActorActionHandler(romData, handlerAddr)
  if handlerAddr >= 0x4000 then return nil end
  local b = romData:sub(handlerAddr + 1, handlerAddr + 11)
  if #b < 11 then return nil end
  if b:sub(1, 3) ~= ACTOR_ACTION_PATTERN_PREFIX then return nil end
  if b:byte(4) ~= 0xC6 then return nil end -- ADD A,n
  local group = b:byte(5)
  if b:sub(6, 7) ~= ACTOR_ACTION_PATTERN_MID then return nil end
  local action = b:byte(8)
  if b:sub(9, 11) ~= ACTOR_ACTION_PATTERN_SUFFIX then return nil end
  return { group = group, action = action }
end

function MapTable.tryDecodeActorAction(romData, header, opcodeEntries)
  assert(type(romData) == "string", "MapTable.tryDecodeActorAction expects a byte string")
  assert(type(header) == "string" and #header >= 1,
    "MapTable.tryDecodeActorAction expects a non-empty header byte string")
  assert(type(opcodeEntries) == "table", "MapTable.tryDecodeActorAction expects decoded scriptOpcodeTable entries")

  local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
  local firstOpcode = header:byte(1)
  local firstHandler = opcodeEntries[firstOpcode + 1]
  if firstHandler ~= ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS then
    return matchActorActionHandler(romData, firstHandler)
  end
  -- First byte is a real, confirmed no-op -- try the second (matches
  -- the live step-by-step trace this finding was based on).
  if #header < 2 or header:byte(2) == 0xFF then return nil end
  local secondOpcode = header:byte(2)
  local secondHandler = opcodeEntries[secondOpcode + 1]
  return matchActorActionHandler(romData, secondHandler)
end

return MapTable
