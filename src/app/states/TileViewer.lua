-- Debug/proof-of-concept state: decodes real Mystic Quest graphics regions
-- (per the VERIFIED entries in docs/reverse-engineering/rom-map.md, via
-- src/import/rom_profiles.lua) and displays them, satisfying milestone 2's
-- "render at least one verified ... sprite or tileset" requirement end to
-- end: ROM bytes -> GBTile decode -> love Image -> on screen.
--
-- Reached from Field via F2 (see Field:keypressed), not from Boot -- Boot
-- hands off straight to the real playable scene now (see Boot.lua's doc
-- comment). This is purely a developer tool.
--
-- Controls: LEFT/RIGHT (or A/D) switch region, UP/DOWN (or W/S) scroll,
-- SELECT (tab/rshift) jumps to MapBlockViewer (the map/room-block pointer
-- table debug view -- see docs/reverse-engineering/rom-map.md "Maps"),
-- F2 pops back to Field.

local TileImage = require("src.rendering.TileImage")

local TileViewer = { opaque = true }
TileViewer.__index = TileViewer

local COLUMNS = 16

function TileViewer.new(romData, profile, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    regionIndex = 1,
    scrollY = 0,
    regions = {},
    images = {},
  }, TileViewer)

  local g = profile.graphics
  local function addRegion(name, fileOffset, fileOffsetEnd, transparent0)
    local byteLen = fileOffsetEnd - fileOffset
    local tileCount = math.floor(byteLen / 16)
    self.regions[#self.regions + 1] = {
      name = name,
      offset = fileOffset,
      count = tileCount,
      transparent0 = transparent0,
    }
  end

  if g.font then
    addRegion("font (bank 8)", g.font.fileOffset,
      g.font.fileOffset + g.font.tileCount * 16, true)
  end
  if g.creatureSpritesBank9 then
    addRegion("sprites (bank 9)", g.creatureSpritesBank9.fileOffsetStart,
      g.creatureSpritesBank9.fileOffsetEnd, true)
  end
  if g.creatureSpritesBank10 then
    addRegion("sprites (bank 10)", g.creatureSpritesBank10.fileOffsetStart,
      g.creatureSpritesBank10.fileOffsetEnd, true)
  end
  if g.creatureSpritesBank11 then
    addRegion("sprites (bank 11)", g.creatureSpritesBank11.fileOffsetStart,
      g.creatureSpritesBank11.fileOffsetEnd, true)
  end
  if g.environmentTilesetBank12 then
    addRegion("tileset (bank 12)", g.environmentTilesetBank12.fileOffsetStart,
      g.environmentTilesetBank12.fileOffsetEnd, false)
  end

  return self
end

-- F2 toggles back off (symmetric with Field:keypressed pushing this on).
function TileViewer:keypressed(key)
  if key == "f2" and self.stack then
    self.stack:pop()
  end
end

function TileViewer:_currentImage()
  local region = self.regions[self.regionIndex]
  if not region then return nil end
  local cached = self.images[self.regionIndex]
  if cached then return cached, region end
  local image, w, h = TileImage.sheetFromBytes(
    self.romData, region.offset, region.count, COLUMNS, nil, region.transparent0)
  cached = { image = image, w = w, h = h }
  -- See TileImage.buildCheckerboard's comment: without this, index-3 (pure
  -- black) ink on a transparent0 sheet is invisible against the canvas's
  -- black clear color, so a correctly-decoded region can look empty.
  if region.transparent0 then
    cached.backdrop = TileImage.buildCheckerboard(w, h, 4)
  end
  self.images[self.regionIndex] = cached
  return cached, region
end

function TileViewer:update(dt)
  if self.stack and self.input:pressed("select") and self.profile.mapTable then
    local MapBlockViewer = require("src.app.states.MapBlockViewer")
    self.stack:push(MapBlockViewer.new(self.romData, self.profile, self.input, self.overlay, self.stack))
    return
  end
  if #self.regions == 0 then return end
  if self.input:pressed("right") or self.input:pressed("b") then
    self.regionIndex = self.regionIndex % #self.regions + 1
    self.scrollY = 0
  elseif self.input:pressed("left") then
    self.regionIndex = (self.regionIndex - 2) % #self.regions + 1
    self.scrollY = 0
  end
  local scrollSpeed = 90 * dt
  if self.input:isDown("down") then self.scrollY = self.scrollY + scrollSpeed end
  if self.input:isDown("up") then self.scrollY = self.scrollY - scrollSpeed end

  local cached = self:_currentImage()
  if cached then
    local maxScroll = math.max(0, cached.h - 144)
    self.scrollY = math.max(0, math.min(self.scrollY, maxScroll))
  end
end

function TileViewer:draw()
  local cached, region = self:_currentImage()
  love.graphics.setColor(1, 1, 1, 1)
  if not cached then
    love.graphics.print("no graphics regions in this ROM profile", 4, 4)
    return
  end

  love.graphics.push()
  love.graphics.translate(0, -math.floor(self.scrollY))
  if cached.backdrop then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(cached.backdrop, 0, 0)
  end
  love.graphics.draw(cached.image, 0, 0)
  love.graphics.pop()

  -- Header bar (drawn after so it stays on top of the scrolled content).
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, 160, 10)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(
    string.format("%d/%d %s", self.regionIndex, #self.regions, region.name),
    2, 1)
  love.graphics.setColor(1, 1, 1, 1)

  if self.overlay then
    self.overlay:addLine("region", region.name)
    self.overlay:addLine("tiles", tostring(region.count))
    self.overlay:addLine("file offset", string.format("0x%06X", region.offset))
  end
end

return TileViewer
