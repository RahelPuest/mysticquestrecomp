-- The real title screen: the "MYSTIC QUEST" logo, "Neues Spiel"/
-- "Weiterspielen" menu, and copyright lines, all real ROM tiles (see
-- src/rendering/TitleScreenBackground.lua and rom_profiles.lua's
-- `graphics.titleScreen` entry for the full ground-truth method), plus
-- the real OAM cursor sprite moving between the two real menu rows.
--
-- First state now (see Boot.lua) -- previously Boot handed off straight
-- to Field, skipping the title screen/name entry/intro entirely. Direct
-- user request (2026-08-09): "bitte den title screen, namenseingabe und
-- die damit verbundenen menüns + musik komplett implementieren... den
-- kompletten flow vom starten des roms über das erstellen eines neuen
-- spiels bis zum ersten kampf."
--
-- "Neues Spiel" hands off to Intro.lua (the real scroll + real story
-- text, 2026-08-09) -- name-entry, the first-battle intro, and combat
-- feedback beyond that are still being built incrementally (see
-- docs/progress.md); Intro currently continues straight to Field once
-- its own scroll finishes, an honest interim endpoint, not a faked step.
--
-- "Weiterspielen" (2026-08-10, task P6): now real -- loads a real save
-- via SaveFile.load() (src/save/SaveFormat.lua's VERIFIED nibble-
-- packed/magic-byte/duplicate-copy container) and jumps straight into
-- Field with the restored Stats + heroName, skipping Intro/NameEntry
-- (a returning player already has a character). If no valid save
-- exists (missing file, corrupt copies, bad magic byte -- see
-- SaveFile.load's own real checks), fails loudly via the same overlay
-- message mechanism as before rather than silently starting a new
-- game or crashing.

local TitleScreenBackground = require("src.rendering.TitleScreenBackground")
local CreatureSprite = require("src.rendering.CreatureSprite")
local TileImage = require("src.rendering.TileImage")
local SaveFile = require("src.save.SaveFile")

local TitleScreen = { opaque = true }
TitleScreen.__index = TitleScreen

-- The two real, live-captured menu rows (see rom_profiles.lua
-- `titleScreen.grid`: "Neues Spiel" at row 11, "Weiterspielen" at row
-- 13) -- order matches on-screen top-to-bottom, index 1 = top.
TitleScreen.MENU_ITEMS = { "neues_spiel", "weiterspielen" }

function TitleScreen.new(romData, profile, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    -- CORRECTED (2026-08-09, later same day): the previous reasoning
    -- here was wrong. Directly checked live: the cursor OAM sits on
    -- "Weiterspielen" (screenY=104) continuously from frame 200 through
    -- frame 600 (sampled at 6 points, zero movement) -- not a transient
    -- state, the real default. reach_room.py's proven single-A-press
    -- sequence still reaches a working fresh room, but via
    -- "Weiterspielen" -> an empty/default save-slot screen -> effectively
    -- a new game, NOT via "Neues Spiel" directly as this project had
    -- assumed. Real "Neues Spiel" requires pressing UP first, confirmed
    -- live (cursor moves screenY 104 -> 88).
    selectedIndex = 2,
  }, TitleScreen)

  if romData and profile then
    self.background = TitleScreenBackground.new(romData, profile)
    local title = profile.graphics.titleScreen
    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end
    if title and title.cursorSprite then
      local cs = title.cursorSprite
      self.cursorSprite = CreatureSprite.fromOffsets(romData, cs.tileOffsets, cs.cols, cs.rows)
    end
    self.cursor = title and title.cursor
  end

  return self
end

function TitleScreen:update(dt)
  if not self.input then return end

  -- Real 2-row cursor navigation -- clamped (no wraparound claimed;
  -- never observed live, see module doc comment).
  if self.input:pressed("down") and self.selectedIndex < #TitleScreen.MENU_ITEMS then
    self.selectedIndex = self.selectedIndex + 1
  elseif self.input:pressed("up") and self.selectedIndex > 1 then
    self.selectedIndex = self.selectedIndex - 1
  end

  if self.input:pressed("a") and self.stack then
    local selected = TitleScreen.MENU_ITEMS[self.selectedIndex]
    if selected == "neues_spiel" then
      -- Real flow (2026-08-09, direct user reference description,
      -- matching independent mGBA verification): "Neues Spiel" ->
      -- Intro (real scroll + real story text), not straight to Field.
      local Intro = require("src.app.states.Intro")
      self.stack:replace(Intro.new(self.romData, self.profile, self.input, self.overlay, self.stack))
    else
      -- "Weiterspielen" (continue): real save/load (task P6, see module
      -- doc comment above).
      local savedStats, result = SaveFile.load()
      if savedStats then
        local Field = require("src.app.states.Field")
        self.stack:replace(Field.new(self.romData, self.profile, self.input, self.overlay,
          self.stack, result, savedStats))
      else
        self.statusMessage = "Weiterspielen: kein gueltiger Spielstand (" .. tostring(result) .. ")"
      end
    end
  end
end

function TitleScreen:draw()
  if self.background then
    self.background:draw(0, 0)
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("(no ROM loaded -- title screen unavailable)", 4, 4)
  end

  if self.cursorSprite and self.cursor then
    local y = self.cursor.rowY[self.selectedIndex]
    self.cursorSprite:draw(self.cursor.screenX, y)
  end

  if self.overlay then
    self.overlay:addLine("state", "TitleScreen")
    self.overlay:addLine("selected", TitleScreen.MENU_ITEMS[self.selectedIndex])
    if self.statusMessage then
      self.overlay:addLine("status", self.statusMessage)
    end
    self.overlay:addLine("dev keys", "arrows navigate, A confirms")
  end
end

return TitleScreen
