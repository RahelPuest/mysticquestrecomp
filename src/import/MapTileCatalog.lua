-- Aggregates the already-VERIFIED map/environment tiles this project
-- has decoded across every fully-mapped room -- not a new discovery,
-- purely a dedup + grouping pass over data that already exists,
-- individually, per room, in `rom_profiles.lua`'s
-- `graphics.<name>.tileOffsets` fields (the exact same offsets
-- `rom-inspector`'s Tile-Viewer page already lets you pick one room at
-- a time and look at -- see js/viz/tiles.js).
--
-- WHY THIS EXISTS (direct user correction): after adding
-- `GraphicsCandidates.lua`'s `bank12_environment_b` (one genuinely new,
-- unconfirmed 256-tile region -- see that module's doc comment), the
-- user pushed back that this project must already know a lot more tile
-- data, since some rooms are already known and completely mapped.
-- Correct: this project has 14 fully-decoded, VERIFIED rooms
-- (`ROOM_MAPS`/`profile.graphics`), together referencing 243 distinct
-- map/environment tile offsets -- spanning bank 8 (28), bank 11 (85),
-- and bank 12 (130), not just bank 12 as this project's
-- `environmentTilesetBank12` doc comment implied. That's already-
-- confirmed content that deserves a place in the Grafiken tab right
-- alongside the honestly-unconfirmed candidates, exactly the way the
-- Monster page already shows its one confirmed sprite before/
-- separately from unconfirmed candidates.
--
-- Every entry here is confirmed, not a candidate: each offset was
-- individually matched against a live-captured VRAM tile pattern by a
-- past session (see each room's `status`/doc comment in
-- rom_profiles.lua) -- this module just deduplicates the (offset ->
-- {which room(s) use it}) relationship so it can be shown as one
-- aggregate "known map tiles" gallery instead of 14 separate,
-- one-room-at-a-time dropdown picks.
--
-- Pure Lua, no love.* calls, same convention as GraphicsCandidates.
-- See `tests/import/map_tile_catalog_test.lua`.

local MapTileCatalog = {}

--- Builds the aggregate catalog from a `rom_profiles.lua` profile
-- table (the same shape `RomProfiles.match(...)` returns). Iterates
-- `profile.graphics` with the EXACT SAME "is this a real, decoded
-- room" filter `rom-inspector/tools/export_data.lua`'s own ROOM_MAPS
-- export already uses (`room.grid and room.tileOffsets`) -- so this
-- catalog's own room count always matches ROOM_MAPS's, by construction
-- not coincidence.
--
-- Returns `{ entries = {...}, byBank = {...}, roomCount = N }`:
--   entries: array of `{fileOffset, bank, rooms = {sorted room names}}`,
--     sorted by fileOffset. Skips the handful of real tiles stored as
--     a literal 16-byte pattern (no single canonical ROM address to
--     dedupe by -- same real exception export_data.lua's own
--     ROOM_MAPS section already documents).
--   byBank: `{ [bankNumber] = distinctTileCount }`.
--   roomCount: how many real rooms contributed (for a sanity cross-
--     check against ROOM_MAPS.length on the website side).
function MapTileCatalog.build(profile)
  assert(type(profile) == "table" and type(profile.graphics) == "table",
    "MapTileCatalog.build expects a profile table with a .graphics field")

  local byOffset = {} -- fileOffset -> { roomsSet = {name=true}, bank = N }
  local roomCount = 0

  for name, room in pairs(profile.graphics) do
    if type(room) == "table" and room.grid and room.tileOffsets then
      roomCount = roomCount + 1
      for _, off in pairs(room.tileOffsets) do
        if type(off) == "number" then
          local rec = byOffset[off]
          if not rec then
            rec = { roomsSet = {}, bank = math.floor(off / 0x4000) }
            byOffset[off] = rec
          end
          rec.roomsSet[name] = true
        end
        -- string (literal 16-byte pattern) entries are intentionally
        -- skipped -- no real ROM address to key on, see doc comment.
      end
    end
  end

  local entries = {}
  local byBank = {}
  for off, rec in pairs(byOffset) do
    local rooms = {}
    for roomName in pairs(rec.roomsSet) do rooms[#rooms + 1] = roomName end
    table.sort(rooms)
    entries[#entries + 1] = { fileOffset = off, bank = rec.bank, rooms = rooms }
    byBank[rec.bank] = (byBank[rec.bank] or 0) + 1
  end
  table.sort(entries, function(a, b) return a.fileOffset < b.fileOffset end)

  return { entries = entries, byBank = byBank, roomCount = roomCount }
end

--- Convenience: just the sorted, distinct real tile offsets belonging
-- to one bank (for a per-bank mosaic render) -- e.g. `forBank(cat, 12)`.
function MapTileCatalog.forBank(catalog, bank)
  local out = {}
  for _, e in ipairs(catalog.entries) do
    if e.bank == bank then out[#out + 1] = e.fileOffset end
  end
  return out
end

return MapTileCatalog
