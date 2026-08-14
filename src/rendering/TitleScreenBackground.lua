-- Draws the REAL title screen -- the "MYSTIC QUEST" logo, "Neues
-- Spiel"/"Weiterspielen" menu text, and copyright lines, confirmed
-- against a live mGBA ground-truth capture of the real ROM (see
-- profile.graphics.titleScreen's doc comment in rom_profiles.lua for the
-- full method).
--
-- Same technique as TileGridBackground.lua (live VRAM tilemap + every
-- distinct tile's real ROM offset found by exact byte search), just
-- covering the FULL 18-row screen instead of the 16-row playable area of
-- a gameplay room -- there's no HUD split here, this isn't a room.

local TileImage = require("src.rendering.TileImage")

local TitleScreenBackground = {}
TitleScreenBackground.__index = TitleScreenBackground

TitleScreenBackground.COLS = 20
TitleScreenBackground.ROWS = 18

function TitleScreenBackground.new(romData, profile)
  local title = profile.graphics and profile.graphics.titleScreen
  assert(title, "TitleScreenBackground.new expects profile.graphics.titleScreen")

  local offsets = {}
  for r, row in ipairs(title.grid) do
    for c, tileId in ipairs(row) do
      local i = (r - 1) * TitleScreenBackground.COLS + c
      offsets[i] = title.tileOffsets[tileId] -- nil (blank) for the confirmed-blank fill tile
    end
  end

  local sheet = TileImage.sheetFromOffsets(
    romData, offsets, TitleScreenBackground.COLS, nil, false,
    TitleScreenBackground.COLS * TitleScreenBackground.ROWS)

  return setmetatable({ sheet = sheet }, TitleScreenBackground)
end

function TitleScreenBackground:draw(x, y)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.sheet, x or 0, y or 0)
end

return TitleScreenBackground
