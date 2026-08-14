-- 160x144 Game Boy-resolution canvas, nearest-neighbor integer-scaled up to
-- fill the actual OS window. Pattern adopted from gen1recomp's
-- src/render/Renderer.lua (docs/gen1recomp-analysis.md SS2) -- this is
-- genre-agnostic "how do you present authentically low-res pixel art on a
-- high-DPI modern display" plumbing, not specific to any one game.

local GB_W, GB_H = 160, 144

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new()
  local canvas = love.graphics.newCanvas(GB_W, GB_H)
  canvas:setFilter("nearest", "nearest")
  return setmetatable({
    canvas = canvas,
    w = GB_W,
    h = GB_H,
  }, Renderer)
end

--- Run `drawFn` with the GB canvas as the render target (origin 0,0,
-- 160x144). Clears to black first.
function Renderer:renderTo(drawFn)
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 1)
  drawFn()
  love.graphics.setCanvas()
end

--- Blit the canvas to the real window, centered, scaled by the largest
-- integer factor that fits (never upscaled with filtering artifacts, never
-- stretched non-uniformly).
function Renderer:present()
  local winW, winH = love.graphics.getDimensions()
  local scale = math.max(1, math.floor(math.min(winW / self.w, winH / self.h)))
  local drawW, drawH = self.w * scale, self.h * scale
  local x = math.floor((winW - drawW) / 2)
  local y = math.floor((winH - drawH) / 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.canvas, x, y, 0, scale, scale)
  return x, y, scale
end

return Renderer
