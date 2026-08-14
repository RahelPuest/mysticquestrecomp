-- Mystic Quest Recomp -- entry point.
-- See docs/architecture.md for the runtime layout this wires together.

local FixedStep = require("src.core.FixedStep")
local StateStack = require("src.core.StateStack")
local Input = require("src.core.Input")
local Renderer = require("src.rendering.Renderer")
local Overlay = require("src.debug.Overlay")
local Boot = require("src.app.states.Boot")

local stack, input, renderer, overlay, fixedStep

-- Dev/CI-only: MYSTICQUEST_SCRIPT holds named Input.BUTTONS down for
-- given fixed-step frame windows, so a specific downstream game state
-- can be reached and exercised (e.g. a full field-movement + combat
-- sequence) for screenshot verification without any OS-level window-
-- focus automation. Two forms, comma-separated:
--   "start"            -- bare button name: held frames 3-8 (legacy
--                          form, e.g. to drive TileViewer -> Field).
--   "up@10-50"         -- button@startFrame-endFrame: held for that
--                          exact fixed-step frame range -- e.g. to
--                          script "walk up, then attack N times" for
--                          reproducing a real live-mGBA-verified
--                          sequence (see docs/progress.md's boss-fight
--                          verification for where this was needed).
-- Only consulted when MYSTICQUEST_SCREENSHOT is also set; never armed
-- in normal play.
local scriptButtons = {} -- legacy bare-name set (frames 3-8)
local scriptRanges = {} -- { {button=, from=, to=}, ... }
do
  local raw = os.getenv("MYSTICQUEST_SCRIPT")
  if raw then
    for entry in raw:gmatch("[^,%s]+") do
      local button, from, to = entry:match("^(%a+)@(%d+)-(%d+)$")
      if button then
        scriptRanges[#scriptRanges + 1] =
          { button = button, from = tonumber(from), to = tonumber(to) }
      else
        scriptButtons[entry] = true
      end
    end
  end
end
local scriptFrame = 0

-- Dev/CI-only: MYSTICQUEST_KEYS="f1@5,f3@40" fires a real love.keypressed
-- for the named raw key at the given fixed-step frame -- for keys that
-- aren't polled Input.BUTTONS (F1 overlay toggle, F2-F6 Field dev
-- shortcuts), which MYSTICQUEST_SCRIPT's held-button model can't reach.
local scriptKeys = {} -- { {key=, frame=}, ... }
do
  local raw = os.getenv("MYSTICQUEST_KEYS")
  if raw then
    for entry in raw:gmatch("[^,%s]+") do
      local key, frame = entry:match("^(%w+)@(%d+)$")
      if key then
        scriptKeys[#scriptKeys + 1] = { key = key, frame = tonumber(frame) }
      end
    end
  end
end

-- Button -> real keyboard key this project's DEFAULT_KEYBOARD maps it to
-- (see src/core/Input.lua) -- scripted presses simulate real key state,
-- not the abstract button name directly, since Input:poll() itself
-- checks real key names.
local BUTTON_TO_KEY = {
  up = "up", down = "down", left = "left", right = "right",
  a = "z", b = "x", start = "return", select = "rshift",
}

local function scriptedIsDown(key)
  if scriptButtons.start and key == "return" then
    return scriptFrame >= 3 and scriptFrame <= 8
  end
  for _, r in ipairs(scriptRanges) do
    if BUTTON_TO_KEY[r.button] == key and scriptFrame >= r.from and scriptFrame <= r.to then
      return true
    end
  end
  return false
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")

  stack = StateStack.new()
  input = Input.new()
  renderer = Renderer.new()
  overlay = Overlay.new()

  fixedStep = FixedStep.new(function(dt)
    if next(scriptButtons) or #scriptRanges > 0 or #scriptKeys > 0 then
      scriptFrame = scriptFrame + 1
      input:poll(scriptedIsDown)
      for _, k in ipairs(scriptKeys) do
        if k.frame == scriptFrame then
          if k.key == "f1" then
            overlay:toggle()
          else
            stack:keypressed(k.key)
          end
        end
      end
    else
      input:poll()
    end
    stack:update(dt)
  end)

  -- Dev/CI-only: MYSTICQUEST_VICTORY_DEMO=1 (2026-08-13, added to
  -- screenshot-verify the new interpreter->rendering pipeline demo --
  -- see VictorySequence.lua's own `runMessagePipelineDemo` doc comment)
  -- skips the real Boot->TitleScreen->Field flow and pushes a real
  -- VictorySequence directly, same real ROM data Boot.lua itself loads,
  -- so `MYSTICQUEST_SCRIPT_INTERPRETER=1 MYSTICQUEST_VICTORY_DEMO=1
  -- MYSTICQUEST_SCREENSHOT=out.png love .` can verify this (and any
  -- future) VictorySequence-only change without replaying a full boss
  -- fight first. Never armed unless the env var is set.
  if os.getenv("MYSTICQUEST_VICTORY_DEMO") == "1" then
    local RomLocator = require("src.import.RomLocator")
    local RomIdentity = require("src.import.RomIdentity")
    local RomProfiles = require("src.import.rom_profiles")
    local VictorySequence = require("src.app.states.VictorySequence")
    local Stats = require("src.entities.Stats")
    local data, pathOrReason = RomLocator.find()
    if data then
      local identity = RomIdentity.identify(data)
      local profile = RomProfiles.match(identity)
      if profile then
        stack:push(VictorySequence.new(data, profile, input, overlay, stack,
          "Held", Stats.new()))
        return
      end
    end
    print("MYSTICQUEST_VICTORY_DEMO: could not load a real ROM (" .. tostring(pathOrReason) ..
      ") -- falling back to the normal Boot flow")
  end

  -- Dev/CI-only: MYSTICQUEST_ROOM_EXPLORER_DEMO=1 (2026-08-14, same
  -- reasoning/pattern as MYSTICQUEST_VICTORY_DEMO above -- added to
  -- screenshot-verify RoomExplorer.lua changes, e.g. the bank-7
  -- Templated-mode dispatch, "ok weiter mit tür und kollision") skips
  -- the real Boot->TitleScreen->Field->F8 flow and pushes a real
  -- RoomExplorer directly. Optional MYSTICQUEST_ROOM_EXPLORER_INDEX=N
  -- jumps straight to flat room index N (1-based, see RoomExplorer
  -- .lua's own `resolveSource`) instead of starting at room 1 --
  -- e.g. 321 for the first bank-7 record, without needing to script
  -- 32 real "start" (+10) button presses through the normal browser.
  if os.getenv("MYSTICQUEST_ROOM_EXPLORER_DEMO") == "1" then
    local RomLocator = require("src.import.RomLocator")
    local RomIdentity = require("src.import.RomIdentity")
    local RomProfiles = require("src.import.rom_profiles")
    local RoomExplorer = require("src.app.states.RoomExplorer")
    local data, pathOrReason = RomLocator.find()
    if data then
      local identity = RomIdentity.identify(data)
      local profile = RomProfiles.match(identity)
      if profile then
        local explorer = RoomExplorer.new(data, profile, input, overlay, stack)
        local startIndex = tonumber(os.getenv("MYSTICQUEST_ROOM_EXPLORER_INDEX"))
        if startIndex then
          explorer.roomIndex = startIndex
          explorer:_loadRoom(startIndex)
        end
        stack:push(explorer)
        return
      end
    end
    print("MYSTICQUEST_ROOM_EXPLORER_DEMO: could not load a real ROM (" .. tostring(pathOrReason) ..
      ") -- falling back to the normal Boot flow")
  end

  stack:push(Boot.new(stack, input, overlay))
end

-- Dev/CI-only: MYSTICQUEST_SCREENSHOT=<path> captures a screenshot after a
-- few frames (enough for Boot to hand off and a real frame to render) and
-- quits -- lets automated verification see actual rendered output without
-- any OS-level window-focus automation. Never armed unless the env var is
-- set, so it has no effect on normal play.
-- Note: captureScreenshot writes relative to LÖVE's save directory (its
-- sandboxed filesystem root), not an arbitrary OS path -- pass a bare
-- filename, then look it up via love.filesystem.getSaveDirectory().
local screenshotPath = os.getenv("MYSTICQUEST_SCREENSHOT")
local frameCount = 0
-- A scripted run needs extra settle time past the last button-hold
-- window before the screenshot, and past that before quitting.
local screenshotAt = 10
if next(scriptButtons) then
  screenshotAt = 20
end
for _, r in ipairs(scriptRanges) do
  if r.to + 10 > screenshotAt then screenshotAt = r.to + 10 end
end
for _, k in ipairs(scriptKeys) do
  if k.frame + 10 > screenshotAt then screenshotAt = k.frame + 10 end
end

-- Dev/CI-only: MYSTICQUEST_WAIT_FOR="key=value" (2026-08-11, added after
-- this exact class of problem repeatedly wasted real verification time in
-- one session: `screenshotAt` above is a blindly-guessed frame count --
-- "how many frames does it take to walk to the door, then through the
-- scroll, then to the exit corridor?" -- and every wrong guess costs a
-- full app relaunch to find out). When set, this OVERRIDES the
-- `screenshotAt` computed above: instead of screenshotting at a fixed
-- frame, it polls the current top state's own `:debugState()` (a plain,
-- love.*-free table any state may optionally implement -- see e.g.
-- VictorySequence:debugState/Field:debugState) every frame and takes the
-- screenshot the instant `tostring(state[key]) == value` -- e.g.
-- `MYSTICQUEST_WAIT_FOR=room=thirdRoom` or `phase=dialogue`. A state with
-- no `:debugState()`, or a condition that never becomes true, safely
-- times out after `MYSTICQUEST_WAIT_FOR_MAX` frames (default 18000, ~5
-- real minutes at 60Hz) and screenshots/quits anyway, printing a clear
-- diagnostic (including the last-seen value, if any) instead of hanging
-- forever.
local waitForSpec = os.getenv("MYSTICQUEST_WAIT_FOR")
local waitForKey, waitForValue
if waitForSpec then
  waitForKey, waitForValue = waitForSpec:match("^([%w_]+)=(.-)$")
  if not waitForKey then
    print("MYSTICQUEST_WAIT_FOR: could not parse '" .. waitForSpec .. "', expected key=value -- ignoring")
  end
end
local waitForMaxFrames = tonumber(os.getenv("MYSTICQUEST_WAIT_FOR_MAX")) or 18000
local waitForResolved = false

-- Dev/CI-only: MYSTICQUEST_STATE_LOG=<path> (2026-08-11, added directly
-- for automated ROM-vs-recomp parity checks -- see tools/parity/). A
-- screenshot alone can't be compared to a real ROM's own numeric WRAM
-- reads; this writes the SAME `:debugState()` table `MYSTICQUEST_
-- WAIT_FOR` already polls (whether or not `WAIT_FOR` is even set -- at
-- plain `screenshotAt` time otherwise) as simple `key=value` lines, one
-- per field, so an external script can parse exact numbers instead of
-- eyeballing/OCR-ing a screenshot.
local stateLogPath = os.getenv("MYSTICQUEST_STATE_LOG")

local function writeStateLog(state)
  if not stateLogPath or not state then return end
  local f = love.filesystem.newFile(stateLogPath, "w")
  if not f then return end
  for k, v in pairs(state) do
    f:write(tostring(k) .. "=" .. tostring(v) .. "\n")
  end
  f:close()
end

function love.update(dt)
  fixedStep:update(dt)
  if screenshotPath then
    frameCount = frameCount + 1
    if waitForKey and not waitForResolved then
      local top = stack:top()
      local state = top and top.debugState and top:debugState()
      local lastSeen = state and state[waitForKey]
      if state and tostring(lastSeen) == waitForValue then
        waitForResolved = true
        screenshotAt = frameCount + 1
        writeStateLog(state)
        print(string.format("[wait_for] %s=%s matched at frame %d", waitForKey, waitForValue, frameCount))
      elseif frameCount >= waitForMaxFrames then
        waitForResolved = true
        screenshotAt = frameCount + 1
        writeStateLog(state)
        print(string.format(
          "[wait_for] TIMEOUT after %d frames waiting for %s=%s (last seen: %s, state: %s)",
          frameCount, waitForKey, waitForValue, tostring(lastSeen),
          state and "present" or "no debugState() on current top state"))
      end
    end
    -- With `waitForKey` set, the ORIGINAL `screenshotAt` above (a fixed
    -- frame count, possibly small -- default 10 with no script at all)
    -- must not fire on its own before the wait condition resolves --
    -- that's the exact bug that would otherwise silently defeat this
    -- whole mechanism.
    local waitForPending = waitForKey and not waitForResolved
    if not waitForPending and frameCount == screenshotAt then
      love.graphics.captureScreenshot(screenshotPath)
      if stateLogPath and not waitForKey then
        -- No WAIT_FOR in play (that path already wrote its own log
        -- above, at the frame it actually resolved) -- log whatever
        -- state exists right at this plain, fixed-frame screenshot.
        local top = stack:top()
        writeStateLog(top and top.debugState and top:debugState())
      end
      print("save dir: " .. love.filesystem.getSaveDirectory())
    elseif not waitForPending and frameCount > screenshotAt + 2 then
      -- Same `waitForPending` guard as the screenshot branch above: the
      -- ORIGINAL small `screenshotAt` (default 10) must not drive an
      -- early quit either while a wait condition is still unresolved --
      -- that quit would fire around frame 13, well before e.g. a
      -- 18000-frame timeout ever gets a chance to run. (Real bug hit
      -- and fixed while first testing this mechanism, 2026-08-11.)
      love.event.quit()
    end
  end
end

function love.draw()
  -- Cleared BEFORE the state draws (not after): states contribute overlay
  -- lines via overlay:addLine from inside stack:draw() below, so clearing
  -- has to happen first or it would wipe out the very lines just added.
  overlay:clearLines()
  renderer:renderTo(function()
    stack:draw()
  end)
  renderer:present()
  -- The overlay itself draws in real window space, unscaled, on top of the
  -- presented GB canvas -- crisp regardless of the integer GB->window scale.
  overlay:draw(FixedStep.HZ)
end

function love.keypressed(key, scancode, isrepeat)
  if key == "f1" then
    overlay:toggle()
    return
  end
  stack:keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
  stack:keyreleased(key, scancode)
end
