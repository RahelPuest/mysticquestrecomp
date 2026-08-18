-- Decodes the general room-FLOOR-layout pipeline found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/rom-map.md "MILESTONE
-- 3 SOLVED: the full room-layout decompression pipeline, found and
-- cross-verified end to end" for the full disassembly/live-tracing
-- evidence. This module is the Lua port of that pipeline, verified
-- against willyRoom (see the "Real ROM" tests in this module's own
-- test file).
--
-- Three distinct stages, each ROM-verified separately:
--
--   1. METATILE TABLE: a flat array of 6-byte records
--      `[gfxTL, gfxTR, gfxBL, gfxBR, collision, interaction]` -- the 4
--      GFX-tile bytes are indices into a general environment tileset,
--      *not* final tile IDs -- see stage 3. Matches the FFA-Disassembly
--      project's documented format for the US cartridge exactly (see
--      rom-map.md's external-source section).
--
--   2. LAYOUT STREAM: an RLE-compressed byte stream, decoded by the
--      ROM's `$242B` routine: a byte with its high bit (0x80) set means
--      "emit `byte - 0x80`, repeated `rleLength` times"; any other byte
--      is one literal metatile index. `rleLength` is a per-room WRAM
--      value (`$C3F9`) -- this project has only ever observed it live
--      (=4 for willyRoom), not derived it statically; callers must
--      supply it (see `rom_profiles.lua`'s
--      `roomFloorLayoutPipeline.exampleRoom.rleLength`). The decoded
--      stream is a flat array of `metatileGridRows * metatileGridCols`
--      indices into the metatile table (stage 1), laid out row-major
--      (ROM-verified: `$23F1`'s `$C350 + row*stride + col` WRAM
--      addressing).
--
--   3. TILE REMAP: each metatile's 4 raw GFX-tile bytes must be passed
--      through a 256-entry remap table (`table[byte] = tile ID`) before
--      they mean anything -- this is the already-known `$D070` WRAM
--      table this project's room-drawing pipeline has used since much
--      earlier (see rom-map.md's original "real room-tile
--      decompression pipeline" section). `$D070` is populated at
--      runtime, not ROM-static -- this module does not (cannot yet)
--      derive it; callers must supply a live snapshot (a 256-byte
--      string, `d070[byte+1] = tile ID`, 1-based like every other byte
--      string in this codebase). Finding $D070's own populator is a
--      named, still-open follow-up (see rom-map.md).
--
-- HONEST SCOPE: this reconstructs the room's base FLOOR layout only.
-- The 4 door/exit graphics (North/West/East/South) are deliberately not
-- part of it -- the compressed stream encodes blank placeholder
-- metatiles there, and the door art is drawn by a separate,
-- already-documented mechanism (`$235B`/`$225D`/`$2281`/`$056C`, see
-- rom-map.md "Following $C3F8's consumers"). Verified against
-- willyRoom: this module's `buildPixelGrid` reproduces 288/320 tiles
-- exactly; the remaining 32 fall precisely inside those 4 door zones
-- and are not a bug -- see this module's own test file for the exact
-- zone-by-zone check, not a hand-waved "close enough".
--
-- Pure Lua, no love.* calls, so it's headlessly testable like
-- MapTable/RoomSelectorTable.

local bit = require("bit")

local RoomFloorLayout = {}

local RLE_FLAG = 0x80

--- Decode `outputCount` metatile indices from an RLE-compressed layout
-- stream starting at `fileOffset` in `romData` (VERIFIED scheme, see
-- module doc comment stage 2). `rleLength` must be passed explicitly --
-- it's a real per-room WRAM value, not a constant this module guesses.
function RoomFloorLayout.decodeLayoutStream(romData, fileOffset, rleLength, outputCount)
  assert(type(romData) == "string", "RoomFloorLayout.decodeLayoutStream expects a byte string")
  assert(type(rleLength) == "number" and rleLength > 0,
    "RoomFloorLayout.decodeLayoutStream expects a positive rleLength")
  assert(type(outputCount) == "number" and outputCount > 0,
    "RoomFloorLayout.decodeLayoutStream expects a positive outputCount")

  local out = {}
  local n = 0
  local i = fileOffset
  while n < outputCount do
    local byte = romData:byte(i + 1)
    assert(byte, "RoomFloorLayout.decodeLayoutStream: ran off the end of romData at file offset " ..
      i .. " before producing " .. outputCount .. " values (got " .. n .. ")")
    if byte >= RLE_FLAG then
      local value = byte - RLE_FLAG
      for _ = 1, rleLength do
        if n >= outputCount then break end
        n = n + 1
        out[n] = value
      end
    else
      n = n + 1
      out[n] = byte
    end
    i = i + 1
  end
  return out
end

--- Read one 6-byte metatile record (0-based `index`) from `romData`
-- (VERIFIED shape, see module doc comment stage 1).
function RoomFloorLayout.readMetatile(romData, metatileTableFileOffset, index)
  assert(type(romData) == "string", "RoomFloorLayout.readMetatile expects a byte string")
  assert(type(index) == "number" and index >= 0,
    "RoomFloorLayout.readMetatile expects a non-negative index")
  local base = metatileTableFileOffset + index * 6
  local b1, b2, b3, b4, b5, b6 = romData:byte(base + 1, base + 6)
  assert(b6 ~= nil, "RoomFloorLayout.readMetatile: index " .. index ..
    " reads past the end of romData")
  return {
    gfxTL = b1, gfxTR = b2, gfxBL = b3, gfxBR = b4,
    collision = b5, interaction = b6,
  }
end

--- Remap one raw GFX-tile byte through a live `$D070`-style 256-entry
-- snapshot (`d070`, a 256-byte string, 1-based like every byte string
-- in this codebase: `d070:byte(byte + 1)`).
function RoomFloorLayout.remapTile(d070, byte)
  assert(type(d070) == "string" and #d070 == 256,
    "RoomFloorLayout.remapTile expects a 256-byte $D070 snapshot")
  return d070:byte(byte + 1)
end

--- Build the room's base floor pixel-tile grid (see module doc comment
-- for the honest "floor only, not doors" scope). `layout` is a
-- `roomFloorLayoutPipeline`-shaped table (or that table's own
-- `exampleRoom`, which additionally carries the per-room fields this
-- function needs): `metatileTableFileOffset`, `layoutStreamFileOffset`,
-- `rleLength`, `metatileGridRows`, `metatileGridCols`. `d070` is a
-- live 256-byte remap snapshot (see `RoomFloorLayout.remapTile`).
--
-- Returns a 1-based 2D array `grid[row][col]`, `row` 1..metatileGridRows*2,
-- `col` 1..metatileGridCols*2 -- matches `rom_profiles.lua`'s own
-- `graphics.<room>.grid` shape exactly, so callers can diff the two
-- directly.
function RoomFloorLayout.buildPixelGrid(romData, layout, d070)
  assert(type(layout) == "table" and layout.metatileTableFileOffset and
    layout.layoutStreamFileOffset and layout.rleLength and
    layout.metatileGridRows and layout.metatileGridCols,
    "RoomFloorLayout.buildPixelGrid expects a layout table with " ..
    "metatileTableFileOffset/layoutStreamFileOffset/rleLength/metatileGridRows/metatileGridCols")

  local metatileCount = layout.metatileGridRows * layout.metatileGridCols
  local indices = RoomFloorLayout.decodeLayoutStream(
    romData, layout.layoutStreamFileOffset, layout.rleLength, metatileCount)

  local grid = {}
  for r = 1, layout.metatileGridRows * 2 do
    grid[r] = {}
  end

  for mr = 0, layout.metatileGridRows - 1 do
    for mc = 0, layout.metatileGridCols - 1 do
      local index = indices[mr * layout.metatileGridCols + mc + 1]
      local mt = RoomFloorLayout.readMetatile(romData, layout.metatileTableFileOffset, index)
      local row1, row2 = mr * 2 + 1, mr * 2 + 2
      local col1, col2 = mc * 2 + 1, mc * 2 + 2
      grid[row1][col1] = RoomFloorLayout.remapTile(d070, mt.gfxTL)
      grid[row1][col2] = RoomFloorLayout.remapTile(d070, mt.gfxTR)
      grid[row2][col1] = RoomFloorLayout.remapTile(d070, mt.gfxBL)
      grid[row2][col2] = RoomFloorLayout.remapTile(d070, mt.gfxBR)
    end
  end
  return grid
end

-- Bitmask-based collision-byte interpretation, from the
-- fourthRoom/unknownRoomA investigation -- a metatile's 5th byte
-- (`collision`) has its upper nibble (bits 4-7) non-zero exactly on
-- wall/border/solid-decoration metatiles in THOSE rooms (consistent
-- with an N/E/S/W-style directional block mask -- matches the
-- FFA-Disassembly documented format's `$10/$20/$30/$40/$80/$C0`
-- values).
--
-- CORRECTED (while trying to generalize this rule to willyRoom): this
-- bitmask rule is not a universal, ROM-wide fact -- it does not hold
-- for willyRoom. Running this exact rule against willyRoom's metatile
-- stream shows its already-extensively-live-verified checkerboard
-- floor (tile IDs 151-154 -- real movement through this exact area has
-- been core, tested gameplay since early in this project) has
-- collision `0x30` every place it actually appears in the room -- i.e.
-- this rule would wrongly call willyRoom's floor "wall." The one thing
-- that IS directly, independently confirmed is fourthRoom's case
-- specifically (a live movement test -- held UP, watched the player
-- walk freely through tiles this rule calls "floor" -- an empirical
-- fact about that room, true regardless of whether the rule
-- generalizes). Most likely explanation: bank 8's metatile table
-- collision byte is not one single global encoding -- different
-- rooms/metatile-table regions plausibly assign their own meaning to
-- the same byte values (ordinary for a hand-authored, per-map
-- collision-class scheme). Practical consequence: `UNKNOWN_ROOM_A_
-- FLOOR_TILE_IDS` (rom_profiles.lua) rests on this same rule,
-- extrapolated to a third, independent metatile table (unknownRoomA's,
-- not fourthRoom's or willyRoom's) with no live-movement confirmation
-- possible (no live gameplay trigger exists) -- this counter-example is
-- material evidence that its own "still HYPOTHESIS" status is doing
-- real work, not a formality. This module keeps the rule/function
-- available (see `buildCollisionGrid` below) as a tested mechanism --
-- position-aware collision from per-metatile-instance data is a
-- genuine improvement over a flat tile-ID set regardless -- but callers
-- must not assume this specific bit-interpretation transfers to a new
-- room without either a live movement check (fourthRoom's standard) or
-- the room's own independent cross-check (matching a metatile whose
-- role is already known some other way).
RoomFloorLayout.COLLISION_WALL_MASK = 0xF0

--- Whether a metatile `collision` byte reads as walkable floor under
-- this project's established bitmask rule (see `COLLISION_WALL_MASK`'s
-- doc comment). This is the fourthRoom/unknownRoomA-style rule
-- specifically -- not a ROM-wide default, see `buildCollisionGrid`'s
-- `isWalkable` parameter below. Kept as the default for existing
-- callers (`buildCollisionGridFromMapTableRecord`, used by bank 5/6's
-- un-ground-truthed 320-room browser) that have no reason yet to
-- prefer a different table's rule.
function RoomFloorLayout.isWalkableCollision(collision)
  return bit.band(collision, RoomFloorLayout.COLLISION_WALL_MASK) == 0
end

-- CRACKED: willyRoom's metatile table
-- (`roomFloorLayoutPipeline.exampleRoom`, file 0x206B0) uses the
-- opposite polarity from fourthRoom/unknownRoomA -- confirmed
-- decisively, not extrapolated, by cross-tabulating every one of
-- willyRoom's 320 grid cells' collision byte against
-- `rom_profiles.lua`'s already-live-movement-verified `floorTileIds`
-- (only 151-154 are floor, confirmed by holding UP and watching the
-- player stop dead at the wall boundary): tiles 151-154 show collision
-- `0x30` at every one of their 192 occurrences (48 each), and every
-- other one of the room's 39 other tile IDs shows only `0x00`/`0x08`,
-- never `0x30`, at any of their combined 128 occurrences -- a perfectly
-- clean, zero-exception split across all 320 grid cells, not a
-- majority/heuristic rule. So for this table specifically: `collision
-- == 0x30` means floor, full stop -- exactly backwards from
-- `isWalkableCollision`'s `COLLISION_WALL_MASK` rule. Matches this
-- module's earlier "collision byte meanings are set per metatile
-- TABLE, not fixed ROM-wide" hypothesis (see `COLLISION_WALL_MASK`'s
-- doc comment) -- now confirmed with a second, independently-derived
-- table, not just asserted.
--
-- Note on an earlier, less precise claim: this module's
-- `buildCollisionGrid` doc comment (below) used to say willyRoom's
-- floor tiles 151-154 show "both 0x08 (open) and 0x30 (wall) collision
-- bytes across different metatile instances." A full, exhaustive
-- re-derivation (all 320 cells, not a sample) found this is not the
-- case for 151-154 specifically -- they are 0x30 at every one of their
-- 192 occurrences, no exceptions. The earlier claim may have been
-- checking a different tile range or an earlier, since-corrected
-- version of `willyRoom.grid`; left as an open historical discrepancy
-- rather than silently erased, since this project doesn't overwrite an
-- earlier claim without flagging the correction.
function RoomFloorLayout.isWalkableCollisionWillyFamily(collision)
  return collision == 0x30
end

--- Build a real, POSITION-AWARE collision grid straight from each real
-- metatile INSTANCE's own collision byte -- `grid[row][col] = true/
-- false` (walkable/not), same 1-based shape and (row,col) numbering as
-- `buildPixelGrid`'s own output, so the two can be zipped together
-- directly.
--
-- WHY THIS EXISTS, not just another `floorTileIds` set (2026-08-12,
-- direct instruction to generalize beyond one-off fixes): every real
-- room's own walkability so far (`startRoom`/`willyRoom`/`secondRoom`/
-- `thirdRoom`/`fourthRoom`) is recorded as a flat `floorTileIds` SET
-- keyed by final rendered tile ID (`TileWalkability.build` checks
-- `floorTileIds[grid[row][col]]`, no position awareness at all) --
-- fine as long as no single tile ID is ever legitimately BOTH floor
-- and wall decoration in the same room. This function sidesteps that
-- limitation entirely by keying on GRID POSITION (via the metatile
-- stream's own real per-cell collision byte) instead of on the
-- remapped tile ID -- strictly more precise than a flat tile-ID set,
-- for any room with real metatile+layout-stream data available.
--
-- GENERALIZED (2026-08-14, task "Kollision generalisieren"): takes an
-- explicit `isWalkable(collision)` predicate now, instead of always
-- calling the module-level `isWalkableCollision`. This fixes a real
-- design flaw the willyRoom investigation exposed: `isWalkableCollision`
-- 's own bit rule is CONFIRMED for fourthRoom's real metatile table but
-- DEMONSTRABLY WRONG (opposite polarity) for willyRoom's -- there is no
-- single ROM-wide rule, so hardcoding one function call here was always
-- going to be right for at most one table. Defaults to
-- `RoomFloorLayout.isWalkableCollision` (unchanged behavior for
-- existing callers -- the bank 5/6 320-room browser, which has no
-- ground truth of its own yet to prefer a different rule); pass
-- `RoomFloorLayout.isWalkableCollisionWillyFamily` explicitly for
-- willyRoom's own table (see that function's own doc comment for the
-- full, exhaustive ground-truth derivation).
function RoomFloorLayout.buildCollisionGrid(romData, layout, isWalkable)
  assert(type(layout) == "table" and layout.metatileTableFileOffset and
    layout.layoutStreamFileOffset and layout.rleLength and
    layout.metatileGridRows and layout.metatileGridCols,
    "RoomFloorLayout.buildCollisionGrid expects a layout table with " ..
    "metatileTableFileOffset/layoutStreamFileOffset/rleLength/metatileGridRows/metatileGridCols")

  local metatileCount = layout.metatileGridRows * layout.metatileGridCols
  local indices = RoomFloorLayout.decodeLayoutStream(
    romData, layout.layoutStreamFileOffset, layout.rleLength, metatileCount)
  return RoomFloorLayout.buildCollisionGridFromIndices(romData, indices, layout, isWalkable)
end

--- Finishing step shared by `buildCollisionGrid` (RLE mode) and
-- `buildCollisionGridFromTemplatedMapTableRecord` (Templated mode,
-- 2026-08-14) -- factored out the exact same way `buildPixelGridFromIndices`
-- was factored out of `buildPixelGridFromTileset`, same reasoning: both
-- real decode paths turn a flat metatile-INDEX array into the same
-- final collision grid, however that index array itself was produced.
function RoomFloorLayout.buildCollisionGridFromIndices(romData, indices, opts, isWalkable)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildCollisionGridFromIndices expects opts.metatileTableFileOffset/" ..
    "metatileGridRows/metatileGridCols")
  isWalkable = isWalkable or RoomFloorLayout.isWalkableCollision

  local grid = {}
  for r = 1, opts.metatileGridRows * 2 do
    grid[r] = {}
  end

  for mr = 0, opts.metatileGridRows - 1 do
    for mc = 0, opts.metatileGridCols - 1 do
      local index = indices[mr * opts.metatileGridCols + mc + 1]
      local mt = RoomFloorLayout.readMetatile(romData, opts.metatileTableFileOffset, index)
      local walkable = isWalkable(mt.collision)
      local row1, row2 = mr * 2 + 1, mr * 2 + 2
      local col1, col2 = mc * 2 + 1, mc * 2 + 2
      grid[row1][col1] = walkable
      grid[row1][col2] = walkable
      grid[row2][col1] = walkable
      grid[row2][col2] = walkable
    end
  end
  return grid
end

-- GENERAL "decode ANY room, no live emulator needed" capability
-- (2026-08-12, direct instruction "du sollst in der lage sein alle
-- räume zu dekodieren. nicht stoppen bevor das nicht möglich ist").
--
-- Everything above this point needs a LIVE `$D070` snapshot
-- (`buildPixelGrid`) -- fine for rooms this project has actually
-- walked through, useless for the ~300+ real map-table records no
-- gameplay has ever reached. `unknownRoomA`'s own 6 rooms were
-- already rendered WITHOUT a live snapshot (see rom_profiles.lua's
-- own `unknownRoomACandidates` doc comment): each metatile's raw GFX-
-- tile byte resolves DIRECTLY through `MapTable.lua`'s own already-
-- VERIFIED, ROM-STATIC formula (`tilesetFileOffset + gfxByte*16` =
-- the tile's own real 16-byte 2bpp graphic, no WRAM remap in the
-- loop at all) -- real, tested, and reproducibly correct (tile_entropy
-- ~1.0-1.8 bits, matching real art, for all 6 rooms). This section
-- generalizes that SAME real recipe to any record from any real
-- MapTable-shaped source (bank 5's own 256-record table, PLUS a
-- second, independently-found one in bank 6 -- see rom_profiles.lua's
-- `mapTableBank6` entry for the full evidence trail: same header
-- shape at file `0x18000` [`00 04 08 08`], real 64-record pointer
-- table at `0x18004`, all 64 records real-render as coherent dungeon
-- art, tile_entropy 1.08-1.63 bits every single one, zero blank/noise
-- outliers).

--- Resolve one raw metatile GFX-tile byte DIRECTLY to its own real
-- ROM file offset (16 raw 2bpp bytes, ready for `gbtile`-style
-- decoding) -- `MapTable.lua`'s own already-VERIFIED
-- `tilesetFileOffset + tileId*16` formula, factored out here so
-- `RoomFloorLayout` callers don't need to require `MapTable` just for
-- this one arithmetic step. Deliberately NOT a `$D070` remap (see
-- `remapTile` above for that, live-snapshot-only path) -- this is the
-- ROM-STATIC alternative that works for a room no gameplay has ever
-- reached.
function RoomFloorLayout.resolveGfxTileFileOffset(tilesetFileOffset, gfxByte)
  assert(type(tilesetFileOffset) == "number", "RoomFloorLayout.resolveGfxTileFileOffset expects a numeric tilesetFileOffset")
  assert(type(gfxByte) == "number" and gfxByte >= 0 and gfxByte <= 255,
    "RoomFloorLayout.resolveGfxTileFileOffset expects a raw GFX-tile byte (0-255)")
  return tilesetFileOffset + gfxByte * 16
end

--- Build a room's full pixel-tile grid using the DIRECT tileset path
-- (no live `$D070` snapshot required) -- same real shape/semantics as
-- `buildPixelGrid`, but `grid[row][col]` holds a real ROM FILE OFFSET
-- (the tile's own raw 16-byte 2bpp graphic location) instead of a
-- remapped tile ID, since there is no live remap table to resolve a
-- final "tile ID" against for a room nothing has ever loaded into
-- VRAM. `layout` needs the same fields as `buildPixelGrid` MINUS any
-- `$D070`-related ones, PLUS `tilesetFileOffset` (see
-- `resolveGfxTileFileOffset`).
function RoomFloorLayout.buildPixelGridFromTileset(romData, layout)
  assert(type(layout) == "table" and layout.metatileTableFileOffset and
    layout.layoutStreamFileOffset and layout.rleLength and
    layout.metatileGridRows and layout.metatileGridCols and layout.tilesetFileOffset,
    "RoomFloorLayout.buildPixelGridFromTileset expects a layout table with " ..
    "metatileTableFileOffset/layoutStreamFileOffset/rleLength/metatileGridRows/metatileGridCols/tilesetFileOffset")

  local metatileCount = layout.metatileGridRows * layout.metatileGridCols
  local indices = RoomFloorLayout.decodeLayoutStream(
    romData, layout.layoutStreamFileOffset, layout.rleLength, metatileCount)
  return RoomFloorLayout.buildPixelGridFromIndices(romData, indices, layout)
end

--- Finishing step shared by `buildPixelGridFromTileset` (RLE mode) and
-- `buildRoomFromTemplatedMapTableRecord` (Templated mode, 2026-08-14) --
-- factored out (same real per-metatile logic, unchanged) so both real
-- decode paths turn a flat metatile-INDEX array into the same final
-- pixel-tile-file-offset grid shape, however that index array itself
-- was produced. `indices` must already be a flat, row-major array of
-- `metatileGridRows*metatileGridCols` metatile-table indices.
function RoomFloorLayout.buildPixelGridFromIndices(romData, indices, opts)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and opts.tilesetFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildPixelGridFromIndices expects opts.metatileTableFileOffset/" ..
    "tilesetFileOffset/metatileGridRows/metatileGridCols")

  local grid = {}
  for r = 1, opts.metatileGridRows * 2 do
    grid[r] = {}
  end

  for mr = 0, opts.metatileGridRows - 1 do
    for mc = 0, opts.metatileGridCols - 1 do
      local index = indices[mr * opts.metatileGridCols + mc + 1]
      local mt = RoomFloorLayout.readMetatile(romData, opts.metatileTableFileOffset, index)
      local row1, row2 = mr * 2 + 1, mr * 2 + 2
      local col1, col2 = mc * 2 + 1, mc * 2 + 2
      grid[row1][col1] = RoomFloorLayout.resolveGfxTileFileOffset(opts.tilesetFileOffset, mt.gfxTL)
      grid[row1][col2] = RoomFloorLayout.resolveGfxTileFileOffset(opts.tilesetFileOffset, mt.gfxTR)
      grid[row2][col1] = RoomFloorLayout.resolveGfxTileFileOffset(opts.tilesetFileOffset, mt.gfxBL)
      grid[row2][col2] = RoomFloorLayout.resolveGfxTileFileOffset(opts.tilesetFileOffset, mt.gfxBR)
    end
  end
  return grid
end

--- Templated-mode (encodingMode 1) sibling of `buildRoomFromMapTableRecord`
-- -- decodes record `recordIndex` from a Templated `mapTable` profile
-- (e.g. `rom_profiles.lua`'s `mapTableBank7`) by RLE-decoding the map's
-- own shared base-room template (`MapTable.readTemplatedHeader`) and
-- applying that record's own real diff list on top
-- (`MapTable.applyTemplatedDiff`) -- see that function's own doc
-- comment for the CRACKED format and its evidence. Same `opts`/return
-- shape as `buildRoomFromMapTableRecord`; normally called THROUGH that
-- function (it dispatches here automatically based on the map's own
-- real header `encodingMode`), not directly, but exposed separately so
-- callers who already know they have a Templated map can skip the
-- header re-read.
function RoomFloorLayout.buildRoomFromTemplatedMapTableRecord(romData, mapTable, recordIndex, opts)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and opts.tilesetFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildRoomFromTemplatedMapTableRecord expects opts.metatileTableFileOffset/" ..
    "tilesetFileOffset/metatileGridRows/metatileGridCols")

  local MapTable = require("src.import.MapTable")
  local header = MapTable.readMapHeader(romData, mapTable)
  assert(header.encodingMode == 1,
    "RoomFloorLayout.buildRoomFromTemplatedMapTableRecord: header names encodingMode " ..
    tostring(header.encodingMode) .. ", not 1 (Templated) -- use buildRoomFromMapTableRecord " ..
    "(it dispatches correctly) or MapTable.decodeRoomTiles for RLE/mode 0")

  local templated = MapTable.readTemplatedHeader(romData, mapTable)
  local gridCount = opts.metatileGridRows * opts.metatileGridCols
  local baseIndices = RoomFloorLayout.decodeLayoutStream(
    romData, templated.templateFileOffset, header.rleLength, gridCount)

  assert(recordIndex >= 0 and recordIndex < mapTable.recordCount,
    "RoomFloorLayout.buildRoomFromTemplatedMapTableRecord: record " .. tostring(recordIndex) ..
    " out of range (recordCount=" .. tostring(mapTable.recordCount) .. ")")
  local dataFileOffset = MapTable.recordDataFileOffset(romData, mapTable, recordIndex)

  local indices = MapTable.applyTemplatedDiff(
    romData, dataFileOffset, baseIndices, opts.metatileGridRows, opts.metatileGridCols)
  return RoomFloorLayout.buildPixelGridFromIndices(romData, indices, opts)
end

--- The real, general entry point: decode ANY record from ANY real
-- MapTable-shaped source (`mapTable` = a `profile.mapTable`-style
-- table -- `bankFileStart`/`pointerTableFileOffset`/`recordCount`,
-- see `MapTable.lua`) into a full pixel-tile-file-offset grid, using
-- the record's own real header-derived `rleLength` (via
-- `MapTable.readMapHeader`) and a caller-supplied `metatileTableFileOffset`
-- (the shared bank-8 metatile pool -- see rom_profiles.lua's own
-- `roomFloorLayoutPipeline.genericCatalogMetatileTableFileOffset` for
-- the real, structurally-derived default this project's own callers
-- use for arbitrary bank-5/bank-6 records, or `unknownRoomACandidates
-- .metatileTableFileOffset` specifically for `unknownRoomA` itself).
-- `metatileGridRows`/`metatileGridCols` must be supplied by the
-- caller (this project has only ever confirmed 8x10 = 80 metatiles
-- for both bank 5 and bank 6's own real records -- not re-derived
-- from `mapTable`'s own header `gridHeight`/`gridWidth` fields here,
-- since those were found NOT to mean "metatile grid shape" directly
-- for bank 6 -- see rom-map.md's own honest note on that).
--
-- Returns the same shape as `buildPixelGridFromTileset` -- a grid of
-- real ROM file offsets, no live emulator state needed anywhere in
-- this call.
--- Shared record-resolution step behind `buildRoomFromMapTableRecord`
-- and `buildCollisionGridFromMapTableRecord` -- both need the exact
-- same real `[encodingMode, rleLength]` header plus the record's own
-- real `layoutStreamFileOffset`; factored out here (2026-08-12, quick
-- win #2) so the two callers can't drift apart on how a record's
-- stream address is computed. RLE/mode-0 ONLY, by design -- Templated/
-- mode-1's own base+diff scheme has no single contiguous
-- "layoutStreamFileOffset" to hand back this way, so `buildRoom
-- FromMapTableRecord` AND `buildCollisionGridFromMapTableRecord` (as
-- of 2026-08-14) both dispatch to their own SEPARATE `...Templated...`
-- path before ever reaching this helper -- see those two functions.
local function resolveMapTableRecordStream(romData, mapTable, recordIndex, callerName)
  assert(type(romData) == "string", callerName .. " expects a byte string")
  assert(type(mapTable) == "table" and mapTable.pointerTableFileOffset and mapTable.bankFileStart,
    callerName .. " expects a profile.mapTable-shaped table")

  local MapTable = require("src.import.MapTable")
  local header = MapTable.readMapHeader(romData, mapTable)
  assert(header.encodingMode == 0,
    callerName .. ": unimplemented encodingMode " .. tostring(header.encodingMode) ..
    " (only RLE/mode 0 is implemented in THIS helper -- Templated/mode 1's own tile " ..
    "decode is implemented separately, see RoomFloorLayout.buildRoomFromTemplatedMapTableRecord, " ..
    "but its COLLISION grid is not -- not silently guessed at here)")

  local records = MapTable.decode(romData, mapTable)
  local record = records[recordIndex + 1]
  assert(record and record.dataAddr, callerName .. ": record " .. tostring(recordIndex) ..
    " has no real data pointer")
  local layoutStreamFileOffset = mapTable.bankFileStart + (record.dataAddr - 0x4000)
  return layoutStreamFileOffset, header.rleLength
end

-- UPDATED 2026-08-14 ("weiter bohren bis es fertig ist"): now dispatches
-- on the map's own real header `encodingMode` -- mode 0 (RLE) via the
-- original path below, mode 1 (Templated) via `buildRoomFromTemplated
-- MapTableRecord` (see that function's own doc comment for the CRACKED
-- format). Callers no longer need to know or care which encoding a
-- given `mapTable` profile uses -- this is genuinely now "ANY record
-- from ANY real MapTable-shaped source," matching the promise above.
function RoomFloorLayout.buildRoomFromMapTableRecord(romData, mapTable, recordIndex, opts)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and opts.tilesetFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildRoomFromMapTableRecord expects opts.metatileTableFileOffset/" ..
    "tilesetFileOffset/metatileGridRows/metatileGridCols")

  local MapTable = require("src.import.MapTable")
  local header = MapTable.readMapHeader(romData, mapTable)
  if header.encodingMode == 1 then
    return RoomFloorLayout.buildRoomFromTemplatedMapTableRecord(romData, mapTable, recordIndex, opts)
  end

  local layoutStreamFileOffset, rleLength = resolveMapTableRecordStream(
    romData, mapTable, recordIndex, "RoomFloorLayout.buildRoomFromMapTableRecord")

  return RoomFloorLayout.buildPixelGridFromTileset(romData, {
    metatileTableFileOffset = opts.metatileTableFileOffset,
    layoutStreamFileOffset = layoutStreamFileOffset,
    rleLength = rleLength,
    metatileGridRows = opts.metatileGridRows,
    metatileGridCols = opts.metatileGridCols,
    tilesetFileOffset = opts.tilesetFileOffset,
  })
end

--- Templated-mode (encodingMode 1) sibling, same real record
-- resolution as `buildRoomFromTemplatedMapTableRecord` (base template
-- + per-record diff, see that function and `MapTable.applyTemplatedDiff`)
-- but returns `buildCollisionGridFromIndices`'s own POSITION-AWARE
-- walkable/wall grid instead of a pixel-tile grid. Added 2026-08-14,
-- direct follow-up ("ok weiter mit tür und kollision") to the tile
-- decode -- same HONEST CAVEAT as `buildCollisionGridFromMapTableRecord`
-- below: no live gameplay reaches any bank-7 room either, so this is a
-- genuine, UNVERIFIED extrapolation of the bank-5/6 collision rule, not
-- a confirmed fact for bank 7's own metatile table.
function RoomFloorLayout.buildCollisionGridFromTemplatedMapTableRecord(romData, mapTable, recordIndex, opts)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildCollisionGridFromTemplatedMapTableRecord expects opts.metatileTableFileOffset/" ..
    "metatileGridRows/metatileGridCols")

  local MapTable = require("src.import.MapTable")
  local header = MapTable.readMapHeader(romData, mapTable)
  assert(header.encodingMode == 1,
    "RoomFloorLayout.buildCollisionGridFromTemplatedMapTableRecord: header names encodingMode " ..
    tostring(header.encodingMode) .. ", not 1 (Templated)")

  local templated = MapTable.readTemplatedHeader(romData, mapTable)
  local gridCount = opts.metatileGridRows * opts.metatileGridCols
  local baseIndices = RoomFloorLayout.decodeLayoutStream(
    romData, templated.templateFileOffset, header.rleLength, gridCount)

  assert(recordIndex >= 0 and recordIndex < mapTable.recordCount,
    "RoomFloorLayout.buildCollisionGridFromTemplatedMapTableRecord: record " .. tostring(recordIndex) ..
    " out of range (recordCount=" .. tostring(mapTable.recordCount) .. ")")
  local dataFileOffset = MapTable.recordDataFileOffset(romData, mapTable, recordIndex)

  local indices = MapTable.applyTemplatedDiff(
    romData, dataFileOffset, baseIndices, opts.metatileGridRows, opts.metatileGridCols)
  return RoomFloorLayout.buildCollisionGridFromIndices(romData, indices, opts, opts.isWalkable)
end

-- UPDATED 2026-08-14 ("ok weiter mit tür und kollision"): now dispatches
-- on the map's own real header `encodingMode`, same as
-- `buildRoomFromMapTableRecord` -- mode 1 (Templated) via
-- `buildCollisionGridFromTemplatedMapTableRecord` above.
--
-- Same real record resolution as `buildRoomFromMapTableRecord`, but
-- returns `buildCollisionGrid`'s own POSITION-AWARE walkable/wall grid
-- instead of a pixel-tile grid -- 2026-08-12, quick win #2 ("1 dann 2
-- dann 3 dann 4"): real per-room collision for the room browser,
-- replacing its original permissive-floor placeholder.
--
-- HONEST CAVEAT, carried over from `COLLISION_WALL_MASK`'s own doc
-- comment above: the "upper nibble non-zero = wall" rule this leans on
-- is CONFIRMED for fourthRoom's own real metatile table (a live
-- movement test) but DEMONSTRABLY WRONG for willyRoom's (the same rule
-- misreads its own live-verified checkerboard floor as wall in some
-- cells there). Bank 5/bank 6/bank 7's own metatile-table region has
-- never had ANY live movement test -- no gameplay reaches these rooms
-- at all, which is the whole reason this ROM-static pipeline exists --
-- so applying this rule here is a genuine, UNVERIFIED extrapolation,
-- not a confirmed fact. Callers (see RoomExplorer.lua) must present
-- this as "best-effort, not verified ROM collision," not as decoded
-- truth.
function RoomFloorLayout.buildCollisionGridFromMapTableRecord(romData, mapTable, recordIndex, opts)
  assert(type(opts) == "table" and opts.metatileTableFileOffset and
    opts.metatileGridRows and opts.metatileGridCols,
    "RoomFloorLayout.buildCollisionGridFromMapTableRecord expects opts.metatileTableFileOffset/" ..
    "metatileGridRows/metatileGridCols")

  local MapTable = require("src.import.MapTable")
  local header = MapTable.readMapHeader(romData, mapTable)
  if header.encodingMode == 1 then
    return RoomFloorLayout.buildCollisionGridFromTemplatedMapTableRecord(romData, mapTable, recordIndex, opts)
  end

  local layoutStreamFileOffset, rleLength = resolveMapTableRecordStream(
    romData, mapTable, recordIndex, "RoomFloorLayout.buildCollisionGridFromMapTableRecord")

  return RoomFloorLayout.buildCollisionGrid(romData, {
    metatileTableFileOffset = opts.metatileTableFileOffset,
    layoutStreamFileOffset = layoutStreamFileOffset,
    rleLength = rleLength,
    metatileGridRows = opts.metatileGridRows,
    metatileGridCols = opts.metatileGridCols,
  }, opts.isWalkable)
end

--- Adapter: turn a `buildRoomFromMapTableRecord`/`buildPixelGridFromTileset`
-- grid (real ROM FILE OFFSETS per cell) into the `{cols, rows, grid,
-- tileOffsets}` shape `src/rendering/TileGridBackground.lua` actually
-- consumes (a tile-ID grid + a `[tileId]=romOffset` dict) -- 2026-08-12,
-- direct instruction "1 dann 2 dann 3 dann 4", quick win #1: browse
-- ALL 320 real rooms live, not just the 6 that got hand-baked into
-- `rom_profiles.lua`. Deliberately a thin, separate adapter rather
-- than changing `buildPixelGridFromTileset`'s own return shape --
-- that function's real contract (a grid of real file offsets) is
-- already locked in by its own test, and other real, ROM-static use
-- cases (e.g. direct `gbtile` decoding, no ID layer at all) want the
-- file-offset form directly.
--
-- The "tile ID" used here is just the raw GFX-tile byte (0-255) the
-- metatile record itself stored -- a real, ROM-native identifier
-- already unique WITHIN one room's own tileset window (recovered from
-- the file offset via the exact inverse of `resolveGfxTileFileOffset`),
-- not an invented numbering.
function RoomFloorLayout.toTileGridBackgroundData(fileOffsetGrid, tilesetFileOffset)
  assert(type(fileOffsetGrid) == "table" and fileOffsetGrid[1],
    "RoomFloorLayout.toTileGridBackgroundData expects a non-empty grid")
  local rows = #fileOffsetGrid
  local cols = #fileOffsetGrid[1]
  local grid = {}
  local tileOffsets = {}
  for r = 1, rows do
    grid[r] = {}
    for c = 1, cols do
      local fileOffset = fileOffsetGrid[r][c]
      local tileId = (fileOffset - tilesetFileOffset) / 16
      grid[r][c] = tileId
      tileOffsets[tileId] = fileOffset
    end
  end
  return { cols = cols, rows = rows, grid = grid, tileOffsets = tileOffsets }
end

return RoomFloorLayout
