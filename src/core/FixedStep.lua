-- Fixed-step update loop, decoupled from render framerate. Pattern adopted
-- from gen1recomp's src/core/FixedStep.lua (see docs/gen1recomp-analysis.md
-- SS5) -- this is generic game-loop hygiene, not Pokemon-specific, and the
-- master brief explicitly calls for simulation timing independent of host
-- FPS. Reimplemented here rather than copied.
--
-- STEP uses the Game Boy's real hardware frame rate: the DMG PPU redraws
-- every 70224 clock cycles at a 4.194304 MHz clock, i.e. 4194304/70224 =~
-- 59.7275 Hz -- NOT exactly 60 Hz. Marked VERIFIED against Pan Docs'
-- documented DMG clock constants (a hardware fact, independent of Mystic
-- Quest's own ROM); how closely Mystic Quest's own game logic actually
-- tracks vblank-driven timing is still UNKNOWN and will need measuring
-- once real gameplay timing questions come up (see docs/roadmap.md).

local FixedStep = {}
FixedStep.__index = FixedStep

FixedStep.HZ = 4194304 / 70224 -- ~59.7275
FixedStep.STEP = 1 / FixedStep.HZ
local MAX_ACCUM = 0.25 -- avoid a spiral of death after a stall (~15 steps)

function FixedStep.new(callback)
  return setmetatable({
    accum = 0,
    callback = callback,
    maxAccum = MAX_ACCUM,
  }, FixedStep)
end

function FixedStep:update(dt)
  self.accum = math.min(self.accum + dt, self.maxAccum)
  while self.accum >= FixedStep.STEP do
    self.accum = self.accum - FixedStep.STEP
    self.callback(FixedStep.STEP)
  end
end

--- Drop any queued catch-up steps. Useful after a load hitch (map change,
-- long synchronous operation) so the next real dt doesn't release a burst
-- of queued steps as a visible "slide."
function FixedStep:discardCatchup()
  self.accum = 0
end

return FixedStep
