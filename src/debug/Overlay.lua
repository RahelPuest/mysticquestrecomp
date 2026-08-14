-- F1 debug overlay. Per the master brief, debug tooling is first-class and
-- should exist from milestone 1 onward, even though most of the fields it
-- will eventually show (map id, player x/y, flags, entities, hitboxes...)
-- don't exist yet. This starts with what milestone 1 actually has: FPS/
-- update rate, active state, ROM status -- and is meant to grow field by
-- field alongside the systems it inspects, not be rebuilt later.

local Overlay = {}
Overlay.__index = Overlay

function Overlay.new()
  return setmetatable({
    visible = false,
    lines = {}, -- extra {label, value} rows a state can contribute this frame
  }, Overlay)
end

function Overlay:toggle()
  self.visible = not self.visible
end

--- A state calls this during its own draw() to add a row, e.g.
-- overlay:addLine("map", tostring(mapId)). Cleared automatically each frame
-- by Game.lua before draw runs.
function Overlay:addLine(label, value)
  self.lines[#self.lines + 1] = { label, value }
end

function Overlay:clearLines()
  for i = #self.lines, 1, -1 do self.lines[i] = nil end
end

function Overlay:draw(fixedStepHz)
  if not self.visible then return end

  local pad = 4
  local lineH = 12
  local rows = { { "FPS", tostring(love.timer.getFPS()) } }
  if fixedStepHz then
    rows[#rows + 1] = { "step hz", string.format("%.4f", fixedStepHz) }
  end
  for _, line in ipairs(self.lines) do rows[#rows + 1] = line end

  local width = 0
  for _, row in ipairs(rows) do
    local text = row[1] .. ": " .. tostring(row[2])
    width = math.max(width, love.graphics.getFont():getWidth(text))
  end
  width = width + pad * 2
  local height = #rows * lineH + pad * 2

  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(0, 1, 0.4, 1)
  for i, row in ipairs(rows) do
    local text = row[1] .. ": " .. tostring(row[2])
    love.graphics.print(text, pad, pad + (i - 1) * lineH)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Overlay
