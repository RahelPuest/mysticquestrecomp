-- DEV-ONLY content browser for ALL 320 real, individually-confirmed
-- rooms this project can decode (256 bank-5 records + 64 bank-6
-- records, see docs/reverse-engineering/rom-map.md "World scope,
-- round 5" and `RoomFloorLayout.buildRoomFromMapTableRecord`) --
-- REWRITTEN 2026-08-12 ("1 dann 2 dann 3 dann 4", quick win #1) from
-- an earlier version that only knew the original 6 `unknownRoomA`
-- rooms as hand-baked `rom_profiles.lua` data. Every room here is now
-- decoded LIVE, straight from the ROM, via the same general, tested,
-- ROM-static function this project's own test suite already exercises
-- (`tests/import/room_floor_layout_test.lua`) -- no per-room profile
-- entries to maintain, no risk of the browser and the decoder drifting
-- apart.
--
-- WHY a separate dev-only state instead of wiring these into the real
-- room chain: this project's own engineering rule is "don't fabricate
-- ROM behavior" -- no live gameplay trigger into any of these 320
-- rooms (beyond the original 8 already in the real chain) was ever
-- found (a real, bounded search, see rom-map.md's "World scope, round
-- 4"). The room CONTENT is real, ROM-verified data; reaching it here
-- is an explicit, clearly-labeled developer shortcut (F8 from
-- Field.lua), the same spirit as the existing F2 TileViewer / F3-F7
-- shortcuts.
--
-- HONEST SCOPE, sharpened 2026-08-12 (round 6, a parity check against
-- willyRoom's own real captured data): "320 real, individually-
-- confirmed rooms" means all 320 decode as real, coherent ROM ART
-- (`tile_entropy()` + visual spot-checks) -- it does NOT mean all 320
-- are confirmed to be a SPECIFIC real in-game room. That stronger
-- claim only holds for the original 6 (`unknownRoomA`, roomSelectors
-- 8-13) -- willyRoom's own real roomSelector (live-traced: index 4)
-- was checked against bank-5 record 4 and every other low-index bank-
-- 5/6 record, and none matched (best: 124/320 real tiles, nowhere near
-- a real identification) -- see rom-map.md's "World scope, round 6"
-- for the full trace. This browser still shows real ROM art either
-- way; just don't read "room N here" as "this is definitely some
-- specific real dungeon room" for anything past the original 6.
--
-- HONEST SCOPE (quick win #2, 2026-08-12, "1 dann 2 dann 3 dann 4"):
-- movement now uses REAL per-metatile-instance collision data via
-- `RoomFloorLayout.buildCollisionGridFromMapTableRecord`
-- (+ `TileWalkability.buildFromCollisionGrid`), replacing quick win
-- #1's original flat permissive-bounds placeholder. This is NOT the
-- same thing as "verified ROM collision," though -- the underlying
-- "upper collision-byte nibble non-zero = wall" rule this leans on
-- (`RoomFloorLayout.COLLISION_WALL_MASK`) is CONFIRMED true for
-- fourthRoom's own real metatile table (a live movement test) but
-- DEMONSTRABLY FALSE for willyRoom's (the same rule misreads willyRoom's
-- own live-verified checkerboard floor as wall in some cells). No
-- gameplay has ever reached ANY of these 320 rooms (that's the whole
-- reason this ROM-static decode pipeline exists), so there is no live
-- movement test possible here -- applying the rule to bank 5/6 is a
-- real, honestly-labeled EXTRAPOLATION, not confirmed ROM behavior.
-- The on-screen footer says so explicitly.
--
-- Controls: arrows move (real per-room collision, caveat above), A =
-- next room, B = previous room, START = jump forward 10 rooms (320
-- rooms is a lot to page through one at a time), SELECT or F8 = back
-- to Field.

local Player = require("src.entities.Player")
local PlayerSprite = require("src.rendering.PlayerSprite")
local TileGridBackground = require("src.rendering.TileGridBackground")
local GBTile = require("src.rendering.GBTile")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local TileWalkability = require("src.entities.TileWalkability")

local RoomExplorer = { opaque = true }
RoomExplorer.__index = RoomExplorer

-- Real room pixel size (see TileGridBackground.lua / rom-map.md's "real
-- rooms are exactly one non-scrolling 20x16-tile screen" finding) --
-- same as every other room in this project.
local ROOM_W, ROOM_H = 160, 128
local FOOTER_H = 16 -- dev-info bar below the room, same idea as Field's own HUD strip

-- Real, shared metatile pool + tileset base -- the SAME two constants
-- every room this project has ever decoded via this pipeline uses
-- (see rom_profiles.lua's own `roomFloorLayoutPipeline
-- .unknownRoomACandidates` doc comment for the full evidence this
-- pool is genuinely shared, not a per-room coincidence).
local METATILE_GRID_ROWS = 8
local METATILE_GRID_COLS = 10

--- Flat room index (1..320) -> which real map table + which record.
-- Bank 5 (256 records) first, then bank 6 (64 records) -- matches the
-- order both tables were found in, nothing deeper than that.
local function resolveSource(profile, flatIndex)
  if flatIndex <= profile.mapTable.recordCount then
    return profile.mapTable, flatIndex - 1, "bank5"
  end
  local bank6Index = flatIndex - profile.mapTable.recordCount - 1
  return profile.mapTableBank6, bank6Index, "bank6"
end

function RoomExplorer.new(romData, profile, input, overlay, stack)
  local totalRooms = profile.mapTable.recordCount + profile.mapTableBank6.recordCount
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

  local opts = {
    metatileTableFileOffset = self.profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileTableFileOffset,
    tilesetFileOffset = mapTable.tilesetFileOffset,
    metatileGridRows = METATILE_GRID_ROWS,
    metatileGridCols = METATILE_GRID_COLS,
  }
  local fileOffsetGrid = RoomFloorLayout.buildRoomFromMapTableRecord(self.romData, mapTable, recordIndex, opts)
  local room = RoomFloorLayout.toTileGridBackgroundData(fileOffsetGrid, opts.tilesetFileOffset)

  self.background = TileGridBackground.new(self.romData, room)

  -- Quick win #2 -- real per-metatile-instance collision, see this
  -- module's own doc comment for the honest "extrapolated, not
  -- verified" caveat on the underlying bitmask rule.
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
  -- solid wall/decoration on several real rooms once quick win #2's
  -- real collision replaced quick win #1's permissive floor (found via
  -- live smoke test: room 1/320's own real collision grid is ~90% wall,
  -- including its whole top-left corner -- a SECOND real, independent
  -- confirmation, after willyRoom, that `COLLISION_WALL_MASK` is a
  -- noisy heuristic here, not verified ROM truth -- see this module's
  -- own doc comment). Scanning for the first walkable spot is a
  -- dev-tool UX choice ONLY -- it does not claim to be this room's real
  -- ROM spawn point (no such thing is known or reachable for these 320
  -- rooms); it just keeps the browser usable under an imperfect
  -- heuristic instead of silently leaving the player stuck.
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
      string.format("%s record %d", self.sourceLabel, self.recordIndex))
    self.overlay:addLine("collision",
      "extrapolated (COLLISION_WALL_MASK) -- not live-verified for this room")
  end
end

return RoomExplorer
