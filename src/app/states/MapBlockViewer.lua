-- Debug/proof-of-concept state for the bank-5 map/room-block pointer table
-- (see docs/reverse-engineering/rom-map.md "Maps"). Renders each record's
-- data blob as tile-index references into the confirmed environment
-- tileset, proving those bytes are real graphics data end to end -- but
-- deliberately does NOT assume a fixed width/height, since that part of
-- the format is still UNKNOWN: LEFT/RIGHT page through records, UP/DOWN
-- change the reshape width live so a developer can eyeball which width (if
-- any single one) makes a given record look "right." This is exactly the
-- kind of instrumentation the project's engineering principles call for
-- when a structure is real but not fully understood yet -- see
-- docs/progress.md's "current reverse-engineering questions."
--
-- SELECT (tab/rshift) pops back to whatever pushed this (TileViewer).

local MapTable = require("src.import.MapTable")
local TileImage = require("src.rendering.TileImage")

local MapBlockViewer = { opaque = true }
MapBlockViewer.__index = MapBlockViewer

function MapBlockViewer.new(romData, profile, input, overlay, stack)
  local records = MapTable.decode(romData, profile.mapTable)
  local self = setmetatable({
    romData = romData,
    tilesetBase = profile.mapTable.tilesetFileOffset,
    records = records,
    input = input,
    overlay = overlay,
    stack = stack,
    recordIndex = 1,
    width = 10, -- arbitrary starting guess; adjustable live, see header comment
    image = nil,
    imageW = 0,
    imageH = 0,
  }, MapBlockViewer)
  self:_rebuild()
  return self
end

function MapBlockViewer:_currentRecord()
  return self.records[self.recordIndex]
end

function MapBlockViewer:_rebuild()
  local record = self:_currentRecord()
  if not record or not record.blob or #record.blob == 0 then
    self.image = nil
    return
  end
  local indices = MapTable.blobToTileIndices(record.blob)
  local width = math.max(1, math.min(self.width, #indices))
  local image, w, h = TileImage.sheetFromIndices(
    self.romData, self.tilesetBase, indices, width, nil, false)
  self.image = image
  self.imageW, self.imageH = w, h
  self.width = width
end

function MapBlockViewer:update(dt)
  if self.stack and self.input:pressed("select") then
    self.stack:pop()
    return
  end
  if #self.records == 0 then return end
  local changed = false
  if self.input:pressed("right") then
    self.recordIndex = self.recordIndex % #self.records + 1
    changed = true
  elseif self.input:pressed("left") then
    self.recordIndex = (self.recordIndex - 2) % #self.records + 1
    changed = true
  end
  if self.input:pressed("up") then
    self.width = self.width + 1
    changed = true
  elseif self.input:pressed("down") then
    self.width = math.max(1, self.width - 1)
    changed = true
  end
  if changed then self:_rebuild() end
end

function MapBlockViewer:draw()
  local record = self:_currentRecord()
  love.graphics.setColor(1, 1, 1, 1)

  if self.image then
    -- Center the (usually small) block on the 160x144 canvas so it's easy
    -- to look at regardless of the current reshape width/height.
    local x = math.floor((160 - self.imageW) / 2)
    local y = math.floor((144 - self.imageH) / 2) + 6
    love.graphics.draw(self.image, x, y)
  else
    love.graphics.print("record has no data blob (last table entry)", 4, 20)
  end

  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, 160, 12)
  love.graphics.setColor(1, 1, 0.6, 1)
  local blobLen = record.blob and #record.blob or 0
  love.graphics.print(string.format(
    "block %d/%d  w=%d h=%.1f  blob=%dB  hdr=%s",
    self.recordIndex, #self.records, self.width, blobLen / self.width, blobLen,
    (function()
      local hex = {}
      for i = 1, #record.header do hex[i] = string.format("%02X", record.header:byte(i)) end
      return table.concat(hex, " ")
    end)()
  ), 2, 1)
  love.graphics.setColor(1, 1, 1, 1)

  if self.overlay then
    self.overlay:addLine("map record", tostring(self.recordIndex - 1) .. "/" .. tostring(#self.records - 1))
    self.overlay:addLine("reshape width", tostring(self.width))
    self.overlay:addLine("header bytes", blobLen > 0 and tostring(#record.header) or "?")
    self.overlay:addLine("data addr", string.format("$%04X", record.dataAddr))
  end
end

return MapBlockViewer
