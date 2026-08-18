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
-- CORRECTED (direct user report that the textbox line spacing is
-- wrong): was 8 (one native GB tile row) -- live-captured the BG
-- tilemap for a multi-line ROM textbox (mgba, courtyard_boss_defeated
-- -> post_black_wipe) and found text glyph rows sit two tile-rows
-- apart, confirmed a second, independent time on the next box in the
-- same sequence. Same "double spacing" bug already found and fixed for
-- `Intro.lua`'s scrolling story text (docs/progress.md) -- this
-- component had the identical bug, never cross-checked against it.
local LINE_H = 16

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
  local text = self.lines[self.index]
  -- Line-height fix, continued: BOX_H (40px) was sized for the old,
  -- wrong 8px spacing (exactly 4 lines with 4px top/bottom padding) --
  -- at the corrected 16px spacing that only fits 2 lines, which would
  -- clip a longer message. Grow the box to fit the current text's line
  -- count instead of guessing a fixed worst case; never shrinks below
  -- the original BOX_H for a short one.
  local lineCount = 1
  if text then
    for _ in (text .. "\n"):gmatch("(.-)\n") do lineCount = lineCount + 1 end
    lineCount = lineCount - 1
  end
  local boxH = math.max(BOX_H, 4 * 2 + lineCount * LINE_H)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", BOX_X, BOX_Y, BOX_W, boxH)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", BOX_X, BOX_Y, BOX_W, boxH)

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
