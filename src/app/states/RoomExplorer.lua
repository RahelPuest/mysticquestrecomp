-- DEV-ONLY content browser for all 384 individually-confirmed rooms
-- this project can decode (256 bank-5 records + 64 bank-6 records + 64
-- bank-7 records, see docs/reverse-engineering/rom-map.md "World scope,
-- round 5" and "bank 7 Templated revisited, CRACKED" and
-- `RoomFloorLayout.buildRoomFromMapTableRecord`) -- REWRITTEN from an
-- earlier version that only knew the original 6 `unknownRoomA` rooms as
-- hand-baked `rom_profiles.lua` data. Every room here is now decoded
-- live, straight from the ROM, via the same general, tested, ROM-static
-- function this project's test suite already exercises
-- (`tests/import/room_floor_layout_test.lua`) -- no per-room profile
-- entries to maintain, no risk of the browser and the decoder drifting
-- apart.
--
-- WHY a separate dev-only state instead of wiring these into the real
-- room chain: this project's engineering rule is "don't fabricate ROM
-- behavior" -- no live gameplay trigger into any of these rooms (beyond
-- the original 8 already in the real chain) was ever found (a bounded
-- search, see rom-map.md's "World scope, round 4"). The room content is
-- ROM-verified data; reaching it here is an explicit, clearly-labeled
-- developer shortcut (F8 from Field.lua), the same spirit as the
-- existing F2 TileViewer / F3-F7 shortcuts.
--
-- HONEST SCOPE, sharpened by a parity check against willyRoom's
-- captured data: "384 individually-confirmed rooms" means all 384
-- decode as coherent ROM art (`tile_entropy()` + visual spot-checks) --
-- it does not mean all 384 are confirmed to be a specific in-game room.
-- That stronger claim only holds for the original 6 (`unknownRoomA`,
-- roomSelectors 8-13) -- willyRoom's own roomSelector (live-traced:
-- index 4) was checked against bank-5 record 4 and every other
-- low-index bank-5/6 record, and none matched (best: 124/320 tiles,
-- nowhere near an identification) -- see rom-map.md's "World scope,
-- round 6" for the full trace. This browser still shows ROM art either
-- way; just don't read "room N here" as "this is definitely some
-- specific dungeon room" for anything past the original 6.
--
-- CORRECTED 2026-08-19 (direct P0 follow-up): the generic-tileset
-- upgrade below (adopted to replace an "unknownRoomA-borrowed
-- placeholder" that used to stand in for all 384 rooms) had
-- accidentally regressed bank-5 records 8-13 -- rendering them with the
-- GENERIC catalog metatile table + tileset instead of unknownRoomA's
-- own dedicated, independently-VERIFIED ones (`roomFloorLayoutPipeline
-- .unknownRoomACandidates`, metatile table file `0x20938`, tileset
-- file `0x32000` -- genuinely different real ROM regions from the
-- generic catalog's own `0x20690`/`0x30000`, not the same value under
-- two names). `_loadRoom` below now special-cases 8-13 back onto their
-- own real table pair -- confirmed live (`MYSTICQUEST_DEBUG_STATE=
-- roomexplorer:9`/`:14`, screenshotted): renders the exact real
-- brick-wall/mesh-floor dungeon art already established, matching
-- `render_unknown_room_a.py`'s own independent rendering exactly. This
-- also gives `unknownRoomA` real, position-aware, per-metatile-
-- instance walkability automatically (this module's own existing
-- `TileWalkability.buildFromCollisionGrid` mechanism, already built
-- for exactly this shape of data) -- the "trustworthy floor source"
-- `rom_profiles.lua`'s own `unknownRoomA_8` doc comment says was still
-- missing, without needing a flat, tile-ID-keyed `floorTileIds` set at
-- all (proven structurally incapable of representing this table's real
-- collision data -- see that doc comment's own 2026-08-19 entries).
--
-- TILESET UPGRADED: now uses `genericCatalogMetatileTableFileOffset`
-- (`roomSelector` 0/1's `tileSourcePointer`, `0x200B0`) instead of the
-- old, unknownRoomA-borrowed placeholder -- a structurally-derived
-- default (bank5/bank6 are each one literal 16x16/8x8 room-grid "map,"
-- per the external FFA-Disassembly project's documented format, and
-- its "one tileset per map, no per-room override" rule), visually
-- re-checked (a consistent recurring vocabulary -- same door-arch, same
-- floor pattern -- across widely-spread records, which the old
-- placeholder never produced). Still honestly not gameplay-ground-
-- truth-verified -- see rom-map.md's write-up for the full evidence
-- chain and its honest limits.
--
-- BANK 7 ADDED: the "Templated" (mode 1) encoding is now cracked for
-- both tile content and collision (`MapTable.applyTemplatedDiff`,
-- `RoomFloorLayout.buildRoomFromTemplatedMapTableRecord`/
-- `buildCollisionGridFromTemplatedMapTableRecord`) -- `resolveSource`
-- below simply routes into it as a third range, no other change needed
-- here since `buildRoomFromMapTableRecord`/`buildCollisionGrid
-- FromMapTableRecord` both already dispatch on `encodingMode`
-- internally.
--
-- HONEST SCOPE (quick win #2): movement now uses per-metatile-instance
-- collision data via `RoomFloorLayout.buildCollisionGridFromMapTableRecord`
-- (+ `TileWalkability.buildFromCollisionGrid`), replacing quick win #1's
-- original flat permissive-bounds placeholder. This is not the same
-- thing as "verified ROM collision," though -- the underlying "upper
-- collision-byte nibble non-zero = wall" rule this leans on
-- (`RoomFloorLayout.COLLISION_WALL_MASK`) is confirmed true for
-- fourthRoom's metatile table (a live movement test) but demonstrably
-- false for willyRoom's (the same rule misreads willyRoom's live-
-- verified checkerboard floor as wall in some cells). No gameplay has
-- ever reached any of these rooms (that's the whole reason this
-- ROM-static decode pipeline exists), so there is no live movement test
-- possible here -- applying the rule to bank 5/6/7 is an honestly-
-- labeled extrapolation, not confirmed ROM behavior. The on-screen
-- footer says so explicitly.
--
-- Controls: arrows move (per-room collision, caveat above), A = next
-- room, B = previous room, START = jump forward 10 rooms (384 rooms is
-- a lot to page through one at a time), SELECT or F8 = back to Field.

local Player = require("src.entities.Player")
local PlayerSprite = require("src.rendering.PlayerSprite")
local TileGridBackground = require("src.rendering.TileGridBackground")
local GBTile = require("src.rendering.GBTile")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local TileWalkability = require("src.entities.TileWalkability")

local RoomExplorer = { opaque = true }
RoomExplorer.__index = RoomExplorer

-- Room pixel size (see TileGridBackground.lua / rom-map.md's "rooms are
-- exactly one non-scrolling 20x16-tile screen" finding) -- same as
-- every other room in this project.
local ROOM_W, ROOM_H = 160, 128
local FOOTER_H = 16 -- dev-info bar below the room, same idea as Field's HUD strip

-- Shared metatile pool + tileset base -- the same two constants every
-- room this project has ever decoded via this pipeline uses (see
-- rom_profiles.lua's `roomFloorLayoutPipeline.unknownRoomACandidates`
-- doc comment for the full evidence this pool is genuinely shared, not
-- a per-room coincidence).
local METATILE_GRID_ROWS = 8
local METATILE_GRID_COLS = 10

--- Flat room index (1..384) -> which map table + which record. Bank 5
-- (256 records) first, then bank 6 (64 records), then bank 7 (64
-- Templated records, added once `buildRoomFromMapTableRecord`/
-- `buildCollisionGridFromMapTableRecord` both dispatch transparently on
-- encodingMode -- this function needed no special bank-7 tile/collision
-- logic, only one more range check) -- matches the order all three
-- tables were found in, nothing deeper than that.
local function resolveSource(profile, flatIndex)
  if flatIndex <= profile.mapTable.recordCount then
    return profile.mapTable, flatIndex - 1, "bank5"
  end
  flatIndex = flatIndex - profile.mapTable.recordCount
  if flatIndex <= profile.mapTableBank6.recordCount then
    return profile.mapTableBank6, flatIndex - 1, "bank6"
  end
  local bank7Index = flatIndex - profile.mapTableBank6.recordCount - 1
  return profile.mapTableBank7, bank7Index, "bank7"
end

function RoomExplorer.new(romData, profile, input, overlay, stack)
  local totalRooms = profile.mapTable.recordCount + profile.mapTableBank6.recordCount +
    profile.mapTableBank7.recordCount
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    roomIndex = 1,
    totalRooms = totalRooms,
    player = Player.new(0, 0),
  }, RoomExplorer)

  self.playerSprite = PlayerSprite.new(romData, profile)
  local ps = profile.graphics.playerSprite
  if ps then
    self.player.width, self.player.height = ps.cols * GBTile.TILE_W, ps.rows * GBTile.TILE_H
  end

  self:_loadRoom(self.roomIndex)
  return self
end

function RoomExplorer:_loadRoom(index)
  local mapTable, recordIndex, sourceLabel = resolveSource(self.profile, index)
  self.sourceLabel = sourceLabel
  self.recordIndex = recordIndex

  -- CORRECTED 2026-08-19 (direct P0 follow-up, "unknownRoomA's own
  -- floor data" investigation): bank-5 records 8-13 are the ONLY 6 of
  -- these 384 catalog entries with an independently-VERIFIED, DEDICATED
  -- metatile table of their own (`roomFloorLayoutPipeline
  -- .unknownRoomACandidates.metatileTableFileOffset`, file `0x20938`)
  -- -- this module's doc comment already says so ("that stronger claim
  -- only holds for the original 6, unknownRoomA, roomSelectors 8-13").
  -- The generic `genericCatalogMetatileTableFileOffset` default below
  -- was adopted for the OTHER 378 records (replacing an earlier,
  -- cruder "borrow unknownRoomA's own table for everything" placeholder
  -- -- see this file's own "TILESET UPGRADED" doc comment above) but
  -- accidentally stopped special-casing 8-13 back to their own real
  -- table in the process -- a real, previously-unnoticed regression,
  -- not an intentional simplification. Restoring it here also gives
  -- `unknownRoomA` real, position-aware, per-metatile-instance
  -- collision data automatically (this module's own `collisionGrid`
  -- below) -- the exact "trustworthy floor source" `rom_profiles.lua`'s
  -- `unknownRoomA_8` doc comment says is still missing, WITHOUT needing
  -- a flat, tile-ID-keyed `floorTileIds` set at all (already proven
  -- structurally incapable of representing this specific table's real
  -- collision data -- see that doc comment's own 2026-08-19 "DEEPER
  -- BLOCKER" entry).
  local isUnknownRoomA = sourceLabel == "bank5" and recordIndex >= 8 and recordIndex <= 13
  local unknownRoomACandidates = self.profile.roomFloorLayoutPipeline.unknownRoomACandidates
  -- Both the metatile table AND the tileset differ for unknownRoomA's
  -- own dedicated pipeline -- `unknownRoomACandidates.tilesetFileOffset`
  -- (file 0x32000) vs. `mapTable.tilesetFileOffset` (file 0x30000, the
  -- generic bank5 tileset) are genuinely different real ROM regions,
  -- not the same value under two names. Swapping only the metatile
  -- table and leaving the generic tileset in place (a real bug this
  -- fix's own first attempt made) pairs unknownRoomA's own real
  -- metatile/collision data against the WRONG graphics -- garbled,
  -- not the clean brick-wall/mesh-floor art already visually confirmed
  -- (see rom_profiles.lua's own `unknownRoomA_8` doc comment).
  local metatileTableFileOffset = isUnknownRoomA
    and unknownRoomACandidates.metatileTableFileOffset
    or self.profile.roomFloorLayoutPipeline.genericCatalogMetatileTableFileOffset
  local tilesetFileOffset = isUnknownRoomA
    and unknownRoomACandidates.tilesetFileOffset
    or mapTable.tilesetFileOffset
  self.isUnknownRoomA = isUnknownRoomA

  local opts = {
    metatileTableFileOffset = metatileTableFileOffset,
    tilesetFileOffset = tilesetFileOffset,
    metatileGridRows = METATILE_GRID_ROWS,
    metatileGridCols = METATILE_GRID_COLS,
  }
  local fileOffsetGrid = RoomFloorLayout.buildRoomFromMapTableRecord(self.romData, mapTable, recordIndex, opts)
  local room = RoomFloorLayout.toTileGridBackgroundData(fileOffsetGrid, opts.tilesetFileOffset)

  self.background = TileGridBackground.new(self.romData, room)

  -- Quick win #2 -- per-metatile-instance collision, see this module's
  -- doc comment for the honest "extrapolated, not verified" caveat on
  -- the underlying bitmask rule.
  local collisionGrid = RoomFloorLayout.buildCollisionGridFromMapTableRecord(
    self.romData, mapTable, recordIndex, opts)
  local collisionCheck = TileWalkability.buildFromCollisionGrid(
    collisionGrid, self.player.width, self.player.height)
  self.canMoveTo = function(x, y)
    if x < 0 or y < 0 or x > ROOM_W - self.player.width or y > ROOM_H - self.player.height then
      return false
    end
    return collisionCheck(x, y)
  end

  -- Spawning at a fixed (0,0) turned out to strand the player inside
  -- solid wall/decoration on several rooms once quick win #2's
  -- collision replaced quick win #1's permissive floor (found via live
  -- smoke test: room 1/320's collision grid is ~90% wall, including its
  -- whole top-left corner -- a second, independent confirmation, after
  -- willyRoom, that `COLLISION_WALL_MASK` is a noisy heuristic here, not
  -- verified ROM truth -- see this module's doc comment). Scanning for
  -- the first walkable spot is a dev-tool UX choice only -- it does not
  -- claim to be this room's ROM spawn point (no such thing is known or
  -- reachable for these catalog rooms); it just keeps the browser
  -- usable under an imperfect heuristic instead of silently leaving the
  -- player stuck.
  self.player.x, self.player.y = 0, 0
  for row = 0, (METATILE_GRID_ROWS * 2) - 1 do
    local found = false
    for col = 0, (METATILE_GRID_COLS * 2) - 1 do
      local px, py = col * 8, row * 8
      if px <= ROOM_W - self.player.width and py <= ROOM_H - self.player.height
        and collisionCheck(px, py) then
        self.player.x, self.player.y = px, py
        found = true
        break
      end
    end
    if found then break end
  end
  self.player.facing = "down"
  self.player.moving = false
end

function RoomExplorer:keypressed(key)
  if key == "f8" and self.stack then
    self.stack:pop()
  end
end

function RoomExplorer:update(dt)
  if self.stack and self.input:pressed("select") then
    self.stack:pop()
    return
  end
  if self.input:pressed("a") then
    self.roomIndex = self.roomIndex % self.totalRooms + 1
    self:_loadRoom(self.roomIndex)
    return
  end
  if self.input:pressed("b") then
    self.roomIndex = (self.roomIndex - 2) % self.totalRooms + 1
    self:_loadRoom(self.roomIndex)
    return
  end
  if self.input:pressed("start") then
    self.roomIndex = (self.roomIndex - 1 + 10) % self.totalRooms + 1
    self:_loadRoom(self.roomIndex)
    return
  end

  local bounds = { 0, 0, ROOM_W - self.player.width, ROOM_H - self.player.height }
  self.player:update(dt, self.input, bounds, self.canMoveTo)
  self.playerSprite:update(dt, self.player.moving, self.player.facing)
end

function RoomExplorer:draw()
  if self.background then
    self.background:draw(0, 0)
  end
  if self.playerSprite then
    local flipX = self.player.facing == "right"
    self.playerSprite:draw(self.player.x, self.player.y, flipX)
  end

  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, ROOM_H, 160, FOOTER_H)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(
    string.format("DEV: room %d/%d (%s #%d) A/B cycle,START +10,SELECT/F8 exit",
      self.roomIndex, self.totalRooms, self.sourceLabel, self.recordIndex),
    2, ROOM_H + 3)
  love.graphics.setColor(1, 1, 1, 1)

  if self.overlay then
    self.overlay:addLine("room (dev-only, no ROM connectivity)",
      string.format("%s record %d%s", self.sourceLabel, self.recordIndex,
        self.isUnknownRoomA and " (unknownRoomA)" or ""))
    if self.isUnknownRoomA then
      self.overlay:addLine("tileset",
        "unknownRoomA's own dedicated, VERIFIED metatile table (file 0x20938) -- not the generic catalog default")
      self.overlay:addLine("collision",
        "VISUALLY CONFIRMED (2026-08-19: collision 0x30 renders as real brick wall, 0x00/0x08 as real mesh floor) -- still no live movement test")
    else
      self.overlay:addLine("tileset",
        "structurally derived (roomSelector 0/1's real tileSourcePointer) -- not gameplay-confirmed")
      self.overlay:addLine("collision",
        "extrapolated (COLLISION_WALL_MASK) -- not live-verified for this room")
    end
  end
end

return RoomExplorer
