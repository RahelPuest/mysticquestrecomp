-- The real attack-swing visual: two real OAM tile-ID slots (8/9 = pair
-- "A", 10/11 = pair "B"), each loaded via a real DMA content-swap with
-- one of 3 real content blocks (X/Y/Z -- see rom_profiles.lua's
-- `attackSwing` doc comment) across 4 real captured phases, faking a
-- swinging arc. One real sequence per facing direction.
--
-- CORRECTED (2026-08-09): an earlier version of this module assumed
-- only 2 real content blocks existed (sampled at just 2 points). A full
-- per-frame content-offset re-trace (direct user request: "wieder bitte
-- die punkte im rom code finden anstatt das empirisch zu machen") found
-- a real 3rd block -- see rom_profiles.lua's own correction note.
--
-- Direct fix for a real, named gap: Field.lua's attack previously
-- applied damage with ZERO visual feedback -- pressing A did something
-- (the enemy's HP dropped, checkable via the debug overlay) but nothing
-- ever appeared on screen, so from a player's perspective it looked like
-- attacking simply didn't work. Direct user report: "es gibt noch keine
-- attacke."
--
-- HONEST LIMIT: purely a visual -- hit detection is a separate, real
-- mechanism (`getHitboxes`, checked by Field.lua every active frame).

local CreatureSprite = require("src.rendering.CreatureSprite")
local FixedStep = require("src.core.FixedStep")

local AttackSwing = {}
AttackSwing.__index = AttackSwing

--- Build from `profile.graphics.attackSwing` (see rom_profiles.lua). Real
-- love.graphics-backed (not headlessly testable, same split as
-- CreatureSprite/Font -- see docs/architecture.md).
function AttackSwing.new(romData, profile)
  local data = profile.graphics and profile.graphics.attackSwing
  assert(data, "AttackSwing.new expects profile.graphics.attackSwing")

  -- 6 real sprites: 2 pairs (A/B) x 3 content blocks (X/Y/Z) each. 1 col
  -- x 2 rows: a single real 8x16 OAM sprite (top tile, bottom tile) --
  -- same convention as every other 8x16 sprite in this project.
  local sprites = {}
  for pairName, byContent in pairs(data.tileOffsets) do
    sprites[pairName] = {}
    for content, offs in pairs(byContent) do
      sprites[pairName][content] = CreatureSprite.fromOffsets(romData, { offs.top, offs.bottom }, 1, 2)
    end
  end

  return setmetatable({
    sprites = sprites,
    byFacing = data.byFacing,
    phaseSeconds = data.framesPerPhase * FixedStep.STEP,
    active = false,
    facing = nil,
    phaseIndex = 0,
    phaseTimer = 0,
  }, AttackSwing)
end

--- Start the real swing for `facing` (one of "up"/"down"/"left"/
-- "right"). No-op while already active -- the real ROM never showed a
-- second swing interrupting/restarting an in-progress one in this
-- project's own live captures (a held A only ever played the swing
-- once per press, see rom_profiles.lua's doc comment).
function AttackSwing:trigger(facing)
  if self.active then return end
  if not self.byFacing[facing] then return end
  self.active = true
  self.facing = facing
  self.phaseIndex = 1
  self.phaseTimer = 0
end

function AttackSwing:isActive()
  return self.active
end

function AttackSwing:update(dt)
  if not self.active then return end
  local phases = self.byFacing[self.facing]
  self.phaseTimer = self.phaseTimer + dt
  while self.active and self.phaseTimer >= self.phaseSeconds do
    self.phaseTimer = self.phaseTimer - self.phaseSeconds
    self.phaseIndex = self.phaseIndex + 1
    if self.phaseIndex > #phases then
      self.active = false
    end
  end
end

-- Real 8x16 sprite size -- same convention as CreatureSprite.TILE_W/H.
local PART_W, PART_H = 8, 16

--- Real per-frame hit rectangles for the currently active phase, in
-- screen space (see `draw`'s doc comment for why `dx`/`dy` are already
-- screen-space offsets) -- `{}` while inactive. Used by Field.lua to
-- check the swing against the enemy's actual hitbox every frame it's
-- active, instead of a single static distance check at the instant A
-- was pressed.
function AttackSwing:getHitboxes(px, py)
  if not self.active then return {} end
  local phase = self.byFacing[self.facing][self.phaseIndex]
  if not phase then return {} end
  local boxes = {}
  for _, part in ipairs({ phase.L, phase.R }) do
    boxes[#boxes + 1] = { x = px + part.dx, y = py + part.dy, w = PART_W, h = PART_H }
  end
  return boxes
end

--- Draw at the player's real screen position (`px`, `py` = the same
-- top-left coordinate Field.lua uses for the player sprite) -- the real
-- captured `dx`/`dy` offsets are already in that same screen space (see
-- rom_profiles.lua's doc comment for why the OAM->screen conversion
-- cancels out of the difference).
function AttackSwing:draw(px, py)
  if not self.active then return end
  local phase = self.byFacing[self.facing][self.phaseIndex]
  if not phase then return end
  for _, part in ipairs({ phase.L, phase.R }) do
    local sprite = self.sprites[part.pair][phase.content]
    if sprite then
      sprite:draw(px + part.dx, py + part.dy, part.flipX, part.flipY)
    end
  end
end

return AttackSwing
