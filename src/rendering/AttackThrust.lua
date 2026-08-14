-- The real thrust attack visual: pressing A WHILE moving (a direction
-- held) produces a completely different real animation from standing-
-- still `AttackSwing` -- direct fix for a named gap the user pointed
-- out (this project had only ever tested "release direction, then
-- attack" -- never "attack while still holding a direction"): "wenn
-- sich der Spieler nach vorne bewegt und dabei angreift, wird das
-- Schwert nach vorne gestochen. Wenn der Spieler im Stehen angreift,
-- wird das Schwert normal geschwungen."
--
-- Real, VERIFIED mechanics (see rom_profiles.lua's `attackThrust` doc
-- comment for the full capture): shorter than the swing (12 real
-- frames, not 16), a single fixed pose (no flip-cycling within one
-- direction) that moves through 3 real motions on one axis only --
-- retract close (4 real frames, gradual), thrust far out (instant jump,
-- held 3 frames), return to ready (instant jump, held 4 frames) -- not
-- a rotating arc. Reuses `AttackSwing`'s own real content block "Z"
-- verbatim (the real ROM's own art reuse, confirmed byte-for-byte
-- identical, not this project's simplification).

local CreatureSprite = require("src.rendering.CreatureSprite")
local FixedStep = require("src.core.FixedStep")

local AttackThrust = {}
AttackThrust.__index = AttackThrust

function AttackThrust.new(romData, profile)
  local data = profile.graphics and profile.graphics.attackThrust
  assert(data, "AttackThrust.new expects profile.graphics.attackThrust")
  -- Reuses AttackSwing's own real "Z" content block -- see this
  -- module's doc comment; not a separate, independently-guessed offset.
  local swingData = profile.graphics.attackSwing
  local zA, zB = swingData.tileOffsets.A.Z, swingData.tileOffsets.B.Z

  return setmetatable({
    sprites = {
      A = CreatureSprite.fromOffsets(romData, { zA.top, zA.bottom }, 1, 2),
      B = CreatureSprite.fromOffsets(romData, { zB.top, zB.bottom }, 1, 2),
    },
    byFacing = data.byFacing,
    frameSeconds = FixedStep.STEP, -- real per-frame data, not per-phase
    active = false,
    facing = nil,
    frameIndex = 0,
    frameTimer = 0,
  }, AttackThrust)
end

--- Start the real thrust for `facing`. No-op while already active (same
-- reasoning as AttackSwing:trigger).
function AttackThrust:trigger(facing)
  if self.active then return end
  if not self.byFacing[facing] then return end
  self.active = true
  self.facing = facing
  self.frameIndex = 1
  self.frameTimer = 0
end

function AttackThrust:isActive()
  return self.active
end

function AttackThrust:update(dt)
  if not self.active then return end
  local d = self.byFacing[self.facing]
  self.frameTimer = self.frameTimer + dt
  while self.active and self.frameTimer >= self.frameSeconds do
    self.frameTimer = self.frameTimer - self.frameSeconds
    self.frameIndex = self.frameIndex + 1
    if self.frameIndex > #d.frames then
      self.active = false
    end
  end
end

local PART_W, PART_H = 8, 16

--- Real per-facing dx/dy for the current real frame -- `axis="y"` means
-- the captured sequence drives `dy` (both L/R share it, offset by their
-- own fixed `dx`); `axis="x"` means the sequence drives `dx` (L uses it
-- directly, R = value + `rOffset`, their own fixed 8px real spacing).
local function currentDxDy(d, frameIndex)
  local v = d.frames[frameIndex]
  if d.axis == "y" then
    return { dx = d.L.dx, dy = v }, { dx = d.R.dx, dy = v }
  else
    return { dx = v, dy = d.L.dy }, { dx = v + d.rOffset, dy = d.R.dy }
  end
end

function AttackThrust:getHitboxes(px, py)
  if not self.active then return {} end
  local d = self.byFacing[self.facing]
  local lPos, rPos = currentDxDy(d, self.frameIndex)
  return {
    { x = px + lPos.dx, y = py + lPos.dy, w = PART_W, h = PART_H },
    { x = px + rPos.dx, y = py + rPos.dy, w = PART_W, h = PART_H },
  }
end

function AttackThrust:draw(px, py)
  if not self.active then return end
  local d = self.byFacing[self.facing]
  local lPos, rPos = currentDxDy(d, self.frameIndex)
  local lSprite = self.sprites[d.L.pair]
  local rSprite = self.sprites[d.R.pair]
  if lSprite then lSprite:draw(px + lPos.dx, py + lPos.dy, d.L.flipX, d.L.flipY) end
  if rSprite then rSprite:draw(px + rPos.dx, py + rPos.dy, d.R.flipX, d.R.flipY) end
end

return AttackThrust
