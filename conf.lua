-- LÖVE configuration. Window is an integer multiple of the Game Boy's
-- 160x144 output resolution (see docs/architecture.md) so pixel art scales
-- cleanly; Renderer.lua does the actual nearest-neighbor integer scaling
-- to a 160x144 canvas, this just picks a sane default OS window size.

local GB_W, GB_H = 160, 144
local SCALE = 4

function love.conf(t)
  t.identity = "mysticquestrecomp"
  t.version = "11.5"
  t.console = true

  t.window.title = "Mystic Quest Recomp"
  t.window.width = GB_W * SCALE
  t.window.height = GB_H * SCALE
  t.window.resizable = true
  t.window.minwidth = GB_W
  t.window.minheight = GB_H
  t.window.vsync = 1

  t.modules.joystick = true
  t.modules.touch = false
  t.modules.video = false
end
