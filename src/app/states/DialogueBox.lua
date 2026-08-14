-- A real, bordered dialogue box using actual in-ROM font tiles (see
-- src/rendering/Font.lua). Advances one line at a time on A, matching
-- this project's own live-observed dialogue-box behavior.
--
-- IMPORTANT provenance note: the *text* passed to DialogueBox.new is
-- NOT decoded live from ROM bytes the way item/weapon names are (see
-- src/import/ItemTable.lua/WeaponTable.lua) -- this project has VERIFIED
-- the byte-encoding formula for simple strings, but general dialogue
-- prose like the "Willy" scene could not be located as literal ROM
-- bytes even with that verified formula (see docs/reverse-engineering/
-- text.md "sixth pass" -- likely a still-uncracked compression scheme).
-- The lines shown here are hardcoded plain Lua strings, transcribed
-- from this project's own live gameplay screenshots/VRAM reads, not
-- pulled from `romData` at runtime. Callers must not mistake this for
-- a general "decode any dialogue from its ROM offset" capability.

local DialogueBox = { opaque = false }
DialogueBox.__index = DialogueBox

local BOX_X, BOX_Y = 4, 4
local BOX_W, BOX_H = 152, 40
local LINE_H = 8

--- `lines`: array of strings (each already short enough to fit BOX_W --
-- no wrapping is implemented). `onComplete`: called once, after the
-- last line is dismissed.
function DialogueBox.new(lines, font, input, stack, onComplete)
  assert(font, "DialogueBox.new requires a built Font")
  return setmetatable({
    lines = lines,
    index = 1,
    font = font,
    input = input,
    stack = stack,
    onComplete = onComplete,
  }, DialogueBox)
end

function DialogueBox:update(dt)
  if self.input:pressed("a") or self.input:pressed("start") then
    self.index = self.index + 1
    if self.index > #self.lines then
      self.stack:pop()
      if self.onComplete then self.onComplete() end
    end
  end
end

function DialogueBox:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", BOX_X, BOX_Y, BOX_W, BOX_H)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", BOX_X, BOX_Y, BOX_W, BOX_H)

  local text = self.lines[self.index]
  if text then
    -- '\n' splits a logical line into displayed rows within the box --
    -- a plain formatting convenience, not a decoded ROM control code
    -- (see docs/reverse-engineering/text.md for the real, still-
    -- unconfirmed line-wrapping/control-code question).
    local row = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      self.font:print(line, BOX_X + 4, BOX_Y + 4 + row * LINE_H, { 0, 0, 0, 1 })
      row = row + 1
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return DialogueBox
