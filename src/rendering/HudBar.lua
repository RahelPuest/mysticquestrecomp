-- The real HUD horizontal bar/arrow decoration -- direct fix for a
-- named gap (user report: "Poweranzeige fehlt im HUD"). See
-- rom_profiles.lua's `hudBar` doc comment for how this was found (the
-- WINDOW layer, never checked before this pass) and why it's modeled as
-- a static decoration, not a fillable gauge (no evidence of it ever
-- changing length was found).

local TileImage = require("src.rendering.TileImage")

local HudBar = {}
HudBar.__index = HudBar

-- Same reasoning as Font.lua's INK_PALETTE: render every non-zero
-- pixel as solid white and let `:draw`'s color tint pick the real
-- on-screen color (black, matching the live mGBA screenshot this was
-- found from) -- avoids needing to know which of raw indices 1-3 the
-- real tile art actually uses for its line vs. anti-aliasing.
local INK_PALETTE = {
  { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 },
}

function HudBar.new(romData, profile)
  local data = profile.graphics and profile.graphics.hudBar
  assert(data, "HudBar.new expects profile.graphics.hudBar")

  local offsets = { data.tileOffsets.startCap }
  for _ = 1, data.segmentCount do
    offsets[#offsets + 1] = data.tileOffsets.segment
  end
  offsets[#offsets + 1] = data.tileOffsets.endCap

  local sheet = TileImage.sheetFromOffsets(romData, offsets, #offsets, INK_PALETTE, true, #offsets)

  return setmetatable({
    sheet = sheet,
    x = data.screenX,
    y = data.screenY,
  }, HudBar)
end

function HudBar:draw()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.draw(self.sheet, self.x, self.y)
  love.graphics.setColor(1, 1, 1, 1)
end

return HudBar
