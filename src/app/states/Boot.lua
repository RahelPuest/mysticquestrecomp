-- First state: locate a ROM, verify it, match it to a known profile, and
-- hand off to the real title screen (src/app/states/TitleScreen.lua),
-- which itself hands off to real gameplay (Field, the playable
-- starting-room slice) once "Neues Spiel" is confirmed. No silent
-- fallbacks: an unfound or unrecognized ROM goes to NoRom with a
-- concrete reason, never to placeholder content.
--
-- CHANGED (2026-08-09): Boot used to hand off straight to Field,
-- skipping the title screen entirely -- fine for an early vertical
-- slice, but a real gap once the title screen itself became real (direct
-- user request: "den kompletten flow vom starten des roms... bis zum
-- ersten kampf"). TileViewer/MapBlockViewer are still real, useful
-- debugging tools -- see docs/architecture.md's debug-tools section --
-- reachable from Field via F2 (Field:keypressed), not the boot path.

local RomLocator = require("src.import.RomLocator")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local NoRom = require("src.app.states.NoRom")
local Field = require("src.app.states.Field")
local TitleScreen = require("src.app.states.TitleScreen")
local TileViewer = require("src.app.states.TileViewer")
local BattleIntro = require("src.app.states.BattleIntro")
local VictorySequence = require("src.app.states.VictorySequence")
local Stats = require("src.entities.Stats")

local Boot = { opaque = true }
Boot.__index = Boot

function Boot.new(stack, input, overlay)
  return setmetatable({ stack = stack, input = input, overlay = overlay }, Boot)
end

function Boot:enter()
  local data, pathOrReason = RomLocator.find()
  if not data then
    self.stack:replace(NoRom.new(pathOrReason))
    return
  end

  local identity = RomIdentity.identify(data)
  if identity.error then
    self.stack:replace(NoRom.new(
      "ROM at '" .. pathOrReason .. "' could not be read: " .. identity.error))
    return
  end

  local profile, reason = RomProfiles.match(identity)
  if not profile then
    self.stack:replace(NoRom.new(string.format(
      "ROM at '%s' (SHA-1 %s, title '%s') is not a supported Mystic Quest " ..
      "revision: %s", pathOrReason, identity.sha1, identity.title, reason)))
    return
  end

  print(string.format(
    "[Boot] loaded %s (%s), SHA-1 %s, %d bytes",
    profile.displayName, pathOrReason, identity.sha1, identity.sizeBytes))

  -- Dev-only diagnostic override, same spirit as MYSTICQUEST_SCREENSHOT/
  -- MYSTICQUEST_SCRIPT in main.lua: MYSTICQUEST_DEBUG_STATE=tileviewer[:N]
  -- boots straight into TileViewer (optionally at region N, 1-based) so a
  -- specific decoded graphics region can be screenshotted directly,
  -- without navigating there through Field's F2 first. MYSTICQUEST_
  -- DEBUG_STATE=field boots straight into Field, bypassing the real
  -- title screen (added 2026-08-09 when Boot stopped handing off to
  -- Field directly) -- most of this project's existing field/combat
  -- screenshot scripts assume Field is the very first state and would
  -- otherwise need an extra "confirm Neues Spiel" step prepended.
  -- DEBUG_STATE=battleintro boots straight into BattleIntro (added
  -- 2026-08-09, same reasoning, for screenshotting the real gate-open/
  -- close animation -- see BattleIntro.lua/TilePatch.lua -- without
  -- replaying title->new-game->name-entry first). Never set outside
  -- manual/scripted diagnostics.
  local debugState = os.getenv("MYSTICQUEST_DEBUG_STATE")
  if debugState and debugState:match("^tileviewer") then
    local region = tonumber(debugState:match(":(%d+)$"))
    local viewer = TileViewer.new(data, profile, self.input, self.overlay, self.stack)
    if region then viewer.regionIndex = region end
    self.stack:replace(viewer)
    return
  elseif debugState == "field" then
    self.stack:replace(Field.new(data, profile, self.input, self.overlay, self.stack))
    return
  elseif debugState == "battleintro" then
    self.stack:replace(BattleIntro.new(data, profile, self.input, self.overlay, self.stack, "AAAA"))
    return
  elseif debugState == "victory" then
    -- Added 2026-08-09, same reasoning as the other DEBUG_STATE hooks --
    -- for screenshotting the real Willy-room/door/second-room sequence
    -- without replaying the whole boss fight first.
    local stats = Stats.new({ curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, level = 1, gold = 50 })
    self.stack:replace(VictorySequence.new(data, profile, self.input, self.overlay, self.stack, "AAAA", stats))
    return
  end

  self.stack:replace(TitleScreen.new(data, profile, self.input, self.overlay, self.stack))
end

function Boot:draw()
  love.graphics.print("booting...", 4, 4)
end

return Boot
