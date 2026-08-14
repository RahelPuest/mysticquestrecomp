-- Game Boy button abstraction: UP/DOWN/LEFT/RIGHT/A/B/START/SELECT, decoupled
-- from any specific keyboard/controller binding, with per-fixed-step edge
-- detection (pressed()/released() are true only on the step the state
-- actually changed, not held down every frame). Pattern adopted from
-- gen1recomp's Input abstraction (docs/gen1recomp-analysis.md SS2).
--
-- This is intentionally generic/genre-agnostic; Mystic Quest-specific
-- meaning (what A does in a menu vs. the field) belongs in game states, not
-- here.

local Input = {}
Input.__index = Input

Input.BUTTONS = { "up", "down", "left", "right", "a", "b", "start", "select" }

local DEFAULT_KEYBOARD = {
  up = "up", down = "down", left = "left", right = "right",
  a = "z", b = "x", start = "return", select = "rshift",
}
-- Secondary bindings layered on top of DEFAULT_KEYBOARD (both are checked).
local DEFAULT_KEYBOARD_ALT = {
  up = "w", down = "s", left = "a", right = "d",
  a = "space", b = "backspace", start = "escape", select = "tab",
}

function Input.new(keymap)
  local self = setmetatable({
    keymap = keymap or DEFAULT_KEYBOARD,
    keymapAlt = DEFAULT_KEYBOARD_ALT,
    held = {},
    prevHeld = {},
  }, Input)
  for _, b in ipairs(Input.BUTTONS) do
    self.held[b] = false
    self.prevHeld[b] = false
  end
  return self
end

--- Poll the real keyboard state (love.keyboard.isDown) into `held`. Call
-- once per fixed step, before reading pressed()/released() for that step.
function Input:poll(isDown)
  isDown = isDown or (love and love.keyboard and love.keyboard.isDown)
  for _, b in ipairs(Input.BUTTONS) do
    self.prevHeld[b] = self.held[b]
    local key = self.keymap[b]
    local alt = self.keymapAlt[b]
    self.held[b] = (key and isDown(key)) or (alt and isDown(alt)) or false
  end
end

function Input:isDown(button)
  return self.held[button] or false
end

function Input:pressed(button)
  return self.held[button] and not self.prevHeld[button]
end

function Input:released(button)
  return (not self.held[button]) and self.prevHeld[button]
end

--- Rebind a button to a new primary key (used by an eventual OPTIONS ->
-- CONTROLS screen, per the master brief's QoL goals -- not implemented yet).
function Input:rebind(button, key)
  assert(self.keymap[button] ~= nil, "unknown button: " .. tostring(button))
  self.keymap[button] = key
end

return Input
