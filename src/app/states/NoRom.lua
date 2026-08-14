-- Shown when no supported ROM could be found/verified. Never silently
-- fabricates a ROM or falls back to placeholder content (project rule:
-- "no silent fallbacks" -- docs/gen1recomp-analysis.md / master brief).

local NoRom = { opaque = true }
NoRom.__index = NoRom

function NoRom.new(reason)
  return setmetatable({ reason = reason }, NoRom)
end

function NoRom:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("MYSTIC QUEST RECOMP", 8, 8)
  love.graphics.print("No supported ROM found.", 8, 28)
  love.graphics.setColor(0.8, 0.8, 0.8, 1)
  local reason = self.reason or "unknown reason"
  -- Wrap long reasons across the 160px-wide canvas.
  love.graphics.printf(reason, 8, 44, 144)
  love.graphics.setColor(0.6, 0.9, 1, 1)
  love.graphics.printf(
    "Set MYSTICQUEST_ROM to your ROM's path, or place it in baseroms/.",
    8, 90, 144)
  love.graphics.setColor(1, 1, 1, 1)
end

return NoRom
