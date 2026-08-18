-- Decodes the bank-5 map/room-block pointer table found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/rom-map.md "Maps" for
-- the full evidence writeup.
--
-- BREAKTHROUGH: the table's per-map header and its room-data
-- compression scheme are VERIFIED, not just hypothesized. The 4 bytes
-- immediately before the pointer table (`mapTable.bankFileStart`, i.e.
-- CPU `$4000-$4003` in bank 5) match the format the external
-- FFA-Disassembly project documented for the US cartridge's per-map
-- header exactly: `[encodingMode, rleLength, gridHeight, gridWidth]`.
-- In this EU ROM that's `[0x00, 0x03, 0x10, 0x10]` -- encodingMode 0
-- (RLE), rleLength 3, and a 16x16 grid whose 256 cells match this
-- project's already-VERIFIED 256-record count exactly (not a
-- coincidence -- see the record-count field itself, independently
-- discovered by a totally different method, a pointer-density scan).
-- Applying the documented RLE rule (a blob byte with its high bit set
-- means "repeat `byte & 0x7F`, `rleLength` times"; otherwise it's one
-- literal tile index) with this header-derived `rleLength=3` decodes
-- all 255 data blobs to an exact, uniform 80 tiles (20x4) -- tested
-- against every other plausible rleLength (1-11) for comparison, every
-- one of which decodes 0/255 blobs to a clean length, so this is not an
-- artifact of blob-length parity. Rendered against the confirmed
-- environment tileset (see docs/progress.md; the original renderer,
-- `RoomBackground.lua`, was removed as dead code once Milestone 3's
-- room-table composition breakthrough superseded it -- see rom-map.md),
-- the decoded tiles are clearly coherent dungeon-wall art (hedge
-- borders, brick trim, torches), not noise. See rom-map.md "Maps" for
-- the full writeup, including what's still open (how multiple records
-- compose into an on-screen room -- naive 4-record vertical stacking
-- did not produce a unified box, so that part remains unverified).
--
-- This module only knows the *table shape* (word-aligned pointer pairs,
-- header terminated by 0xFF, data blob bounded by the next pointer)
-- plus the now-VERIFIED per-map header/RLE format -- every actual
-- offset comes from a profile (src/import/rom_profiles.lua's
-- `mapTable` field), per the project rule that ROM-version-specific
-- knowledge stays centralized there; only the *parsing logic* (byte
-- meanings, RLE rule), not any literal offset or ROM value, lives in
-- this file. Pure Lua, no love.* calls, so it's headlessly testable
-- like GBTile/RomIdentity.

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
-- NAMING CORRECTED: "header" is a misnomer kept only for backward
-- compatibility (the field/param names below are unchanged, a rename
-- would be a wider, separate refactor). The external FFA-Disassembly
-- project's docs name this same pointer-pair position "script" (not
-- "header"), and testing it directly against this project's
-- already-built `ScriptInterpreter`/`ScriptOpcodeTable` confirms that:
-- these bytes decode as valid opcodes resolving to already-catalogued
-- ROM handler addresses (e.g. bank-5 record 0's first byte, `0x76`,
-- resolves to the already-documented `$28C2`/`$2879` "~70-opcode actor
-- action" family, see events.md's "Back to the primary table" section
-- -- a WRAM `$C200` actor-struct command, not a graphics/tileset
-- selector). So: every one of the 320 room-catalog records carries its
-- own tiny per-room event script (likely room-entry NPC/actor setup),
-- structurally consistent with the external doc's "script, tiles"
-- pointer-pair naming -- but this does not resolve the separate,
-- still-open "which metatile table" question (see rom_profiles.lua's
-- `genericCatalogMetatileTableFileOffset` doc comment) -- a different
-- kind of per-room data, honestly reported as a negative result for
-- that specific question.
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
    encodingMode = b0, -- 0 = RLE (VERIFIED); 1 = Templated (CRACKED, see
    -- `readTemplatedHeader`/`applyTemplatedDiff` below -- `MapTable.decodeRoomTiles`
    -- itself still only implements mode 0, the Templated path lives in
    -- `RoomFloorLayout.buildRoomFromMapTableRecord`, which dispatches on this field)
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
-- header names encodingMode 1 (Templated) -- THIS function only
-- implements the plain RLE path (mode 0); Templated's own base-template
-- + per-record-diff scheme is CRACKED (see `readTemplatedHeader`/
-- `applyTemplatedDiff` below) but needs a metatile table to be useful
-- (a diff overrides METATILE indices, same as the base), so its real
-- entry point lives in `RoomFloorLayout.buildRoomFromMapTableRecord`
-- instead, not here.
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

--- Read the Templated-mode (encodingMode 1) header extension -- the
-- base-room template pointer and 24-byte directional door-data block
-- the external FFA-Disassembly project's docs describe as sitting
-- between the map's 4-byte `[encodingMode,...]` header (see
-- `readMapHeader`) and its `(headerPtr,dataPtr)` record-pointer list.
--
-- CRACKED (see rom-map.md's "bank 7 Templated revisited, CRACKED"
-- section for the full evidence). VERIFIED against this EU ROM's
-- bank-7 table: the template pointer's file offset lands exactly where
-- `mapTable.pointerTableFileOffset`'s record-pointer list ends (zero
-- slack bytes), and RLE-decoding from it with the map's header
-- `rleLength` produces exactly `gridRows*gridCols` tiles, consuming
-- exactly enough bytes to land precisely on the first record's header
-- pointer -- an airtight structural fit across two independently-
-- derived boundaries, not a coincidence or a guess.
--
-- `doorData`'s 24 raw bytes are returned as-is -- their per-bit meaning
-- (the external doc's claimed "bits 0-1 = open/closed/wall, bits 2-7 =
-- map-exit flag" layout) has not been tested against this ROM's real
-- data and is not decoded here -- honestly left as raw bytes, not
-- silently assumed. A separate, per-record 4-byte field with similar
-- small values also exists at the start of every record's own data
-- blob (see `applyTemplatedDiff`'s doc comment) -- structurally
-- distinct from this map-level 24-byte block, likely per-room door
-- state rather than a per-map default, but also not decoded here.
function MapTable.readTemplatedHeader(romData, mapTable)
  assert(type(romData) == "string", "MapTable.readTemplatedHeader expects a byte string")
  assert(mapTable and mapTable.bankFileStart,
    "MapTable.readTemplatedHeader expects a profile.mapTable table")
  local base = mapTable.bankFileStart
  local templateCpuAddr = readU16LE(romData, base + 4)
  return {
    templateFileOffset = cpuToFile(base, templateCpuAddr),
    doorData = romData:sub(base + 6 + 1, base + 6 + 24),
  }
end

--- Return record `recordIndex`'s (0-based) real data-blob FILE OFFSET
-- directly from the pointer table -- unlike `MapTable.decode(...)`
-- records' own `blob` field (which is deliberately `nil` for the FINAL
-- record, since a plain RLE blob's real end genuinely can't be known
-- without a following pointer to bound it, see `MapTable.decode`'s doc
-- comment), this works for every record including the last, because
-- self-terminating formats (Templated-mode's own diff list, see
-- `applyTemplatedDiff` below) don't need an externally-supplied bound.
function MapTable.recordDataFileOffset(romData, mapTable, recordIndex)
  assert(type(romData) == "string", "MapTable.recordDataFileOffset expects a byte string")
  assert(type(mapTable) == "table" and mapTable.pointerTableFileOffset and mapTable.bankFileStart,
    "MapTable.recordDataFileOffset expects a profile.mapTable table")
  local dataAddr = readU16LE(romData, mapTable.pointerTableFileOffset + recordIndex * 4 + 2)
  return cpuToFile(mapTable.bankFileStart, dataAddr)
end

--- Apply one Templated-mode record's `(value, position)` diff list on
-- top of `baseIndices` (the shared base-room template's flat
-- metatile-index array -- `#baseIndices` entries, row-major -- see
-- `readTemplatedHeader` for how to decode that base array via
-- `MapTable.rleDecode`/`RoomFloorLayout.decodeLayoutStream`).
-- `dataFileOffset` is the record's data pointer's file offset (see
-- `recordDataFileOffset`) -- this function reads directly from
-- `romData` at that offset (like `RoomFloorLayout.decodeLayoutStream`
-- does for RLE streams) rather than requiring a pre-sliced blob, since
-- the format is self-terminating and needs no externally-supplied end.
--
-- CRACKED format (see rom-map.md "bank 7 Templated revisited,
-- CRACKED"): each record's raw data starts with a 4-byte per-record
-- field (small values, `0x00-0x0d` observed -- plausibly per-room
-- door/exit-flag data, see `readTemplatedHeader`'s doc comment -- not
-- decoded, deliberately skipped here) followed by `(value, position)`
-- byte pairs, `position` packing `(row << 4) | col`, terminated by a
-- position byte of `0xFF`. Found via an exhaustive, automated search
-- over all 4 plausible (prefix length x pair order) combinations
-- against every record in this EU ROM's bank-7 table: this exact
-- combination was the unique one scoring 557/557 (100%) valid
-- `row/col` pairs -- the next-best alternative only reached 97.1%.
-- VERIFIED end to end: 566/566 diff positions across all 64 records
-- decode to valid `0 <= row < gridRows`, `0 <= col < gridCols` pairs
-- (zero exceptions), and every one of the 64 resulting reconstructed
-- rooms (base template + that record's diff) renders as structurally
-- coherent, visually distinct dungeon art (`tile_entropy()` 1.30-1.40
-- bits for all 64, squarely in the same real-art band already
-- established for bank 5/6 -- zero outliers -- plus direct PNG
-- eyeballing of 6 spot-checked records, each showing genuinely
-- different room content, e.g. a distinct central statue/creature
-- shape vs. a row of urn/skull decorations vs. a triangular banner
-- formation -- not the same room repeated).
--
-- Returns a new array (does not mutate `baseIndices`), same length,
-- same row-major layout (`index = row*gridCols + col + 1`, 1-based).
-- Fails loudly (not silently) if a diff position decodes outside the
-- `gridRows x gridCols` bounds, or if no `0xFF` terminator turns up
-- within a sane bound (one diff per grid cell at most, plus slack) --
-- this project has never observed either in real data, so both would
-- be a genuine anomaly worth surfacing, not silently absorbed.
function MapTable.applyTemplatedDiff(romData, dataFileOffset, baseIndices, gridRows, gridCols)
  assert(type(romData) == "string", "MapTable.applyTemplatedDiff expects a byte string")
  assert(type(baseIndices) == "table", "MapTable.applyTemplatedDiff expects a base indices array")
  assert(type(gridRows) == "number" and type(gridCols) == "number",
    "MapTable.applyTemplatedDiff expects numeric gridRows/gridCols")

  local indices = {}
  for i, v in ipairs(baseIndices) do indices[i] = v end

  local i = dataFileOffset + 4 -- skip the real 4-byte per-record prefix (0-based file offset)
  local maxPairs = gridRows * gridCols + 16 -- safety bound: at most 1 diff/cell, plus slack
  local pairsSeen = 0
  while true do
    local value, pos = romData:byte(i + 1), romData:byte(i + 2)
    assert(value and pos, "MapTable.applyTemplatedDiff: ran off the end of romData at file offset " ..
      i .. " before finding a real 0xFF terminator")
    if pos == 0xFF then break end
    local row = math.floor(pos / 16)
    local col = pos % 16
    assert(row >= 0 and row < gridRows and col >= 0 and col < gridCols,
      string.format("MapTable.applyTemplatedDiff: diff position byte %#04x decodes to " ..
        "out-of-range row/col (%d,%d) for a %dx%d grid -- not the recognized position encoding",
        pos, row, col, gridRows, gridCols))
    indices[row * gridCols + col + 1] = value
    i = i + 2
    pairsSeen = pairsSeen + 1
    assert(pairsSeen <= maxPairs,
      "MapTable.applyTemplatedDiff: no real 0xFF terminator found within " .. maxPairs ..
      " diff pairs -- likely reading a non-Templated blob or a corrupt offset")
  end
  return indices
end

--- Try to extract a `(group, action)` pair from a record's "header"
-- bytes (see this module's "NAMING CORRECTED" doc comment above
-- `MapTable.decode` for why "header" is really a per-room event-script
-- pointer).
--
-- The first (or, if that byte resolves to the ROM-confirmed no-op
-- `ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS`, the second) opcode byte
-- is resolved through the `scriptOpcodeTable` to its ROM handler
-- address. If that address holds the exact, already-documented
-- "ACTOR_ACTION" family instruction sequence
-- (`src/import/ScriptOpcodeTable.lua`'s `ACTOR_ACTION_HANDLER_
-- ADDRESS_*` constants, events.md's "Back to the primary table"
-- section: `CALL $28C2 / ADD A,<group> / LD C,A / LD A,<action> / CALL
-- $2879 / RET`), the baked-in `group`/`action` constants are read
-- directly out of the handler's bytes -- not inferred, not guessed,
-- the literal immediate operands of that specific routine. Returns
-- `nil` if neither byte matches (an honest "not this family" result,
-- not a fabricated default).
--
-- HONEST SCOPE: this identifies which actor-action command a room's
-- entry script enqueues (see `ScriptOpcodeTable.lua`'s corrected note:
-- an actor-command-queue mechanism, `$C4E0`/`$C5A0`, not room-selection
-- or spawn-coordinate data) -- it does not reveal which tiles a room
-- uses (a separate, still-open question, see rom_profiles.lua's
-- `genericCatalogMetatileTableFileOffset` doc comment) and does not
-- explain the exact real-world gameplay meaning of a given `action`
-- value (open per events.md).
--
-- All handler addresses seen for this family so far are `< 0x4000`
-- (fixed bank 0, file offset == CPU address directly, same convention
-- already established for `ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS`
-- elsewhere) -- a handler `>= 0x4000` is honestly reported as "not
-- resolvable this way" (`nil`) rather than guessing a bank.
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
