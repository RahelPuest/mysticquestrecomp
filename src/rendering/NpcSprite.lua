-- A real, animated 4-direction/2-phase NPC sprite -- built for
-- secondRoom's two wandering NPCs (task #28, direct user reports: "die
-- beiden npcs ... haben immer noch keine grafik" then, once the wrong
-- tile data itself was fixed, "diese [npcs] haben animationen und
-- bewegungspattern"). Same general shape as PlayerSprite.lua (a small
-- pose table + a timed phase flip), generalized to 4 directions instead
-- of 2 (down/left-right) since these NPCs -- unlike the player, whose
-- own UP animation was never confirmed -- were directly observed
-- animating in all four.
--
-- Real, single-column 8x16-OBJ-mode sprites (ONE tile stacked top over
-- bottom, not a 2x2 block like Willy/the player) -- see
-- rom_profiles.lua's `secondRoom.scene.characterA/B.animation` doc
-- comment for the live OAM trace that found this (this project
-- previously, wrongly, modeled them as 2x2).

local CreatureSprite = require("src.rendering.CreatureSprite")
local FixedStep = require("src.core.FixedStep")

local NpcSprite = {}
NpcSprite.__index = NpcSprite

local DIRECTIONS = { "down", "up", "left", "right" }

local function buildPose(romData, def, palette)
  return {
    sprite = CreatureSprite.fromOffsets(romData, { def.top, def.bottom }, 1, 2, palette),
    flip = def.flip,
    flipY = def.flipY,
  }
end

--- `animData`: a `{ framesPerPhase=, down={pose1,pose2}, up=..., left=...,
-- right=... }` table (see rom_profiles.lua's own doc comment for the
-- real per-pose `{top=,bottom=,flip=}` shape). `palette`: as
-- CreatureSprite -- normally `CreatureSprite.getDefaultPalette()`.
function NpcSprite.new(romData, animData, palette)
  local dirs = {}
  for _, dir in ipairs(DIRECTIONS) do
    local pair = animData[dir]
    dirs[dir] = { buildPose(romData, pair[1], palette), buildPose(romData, pair[2], palette) }
  end
  return setmetatable({
    dirs = dirs,
    phaseSeconds = (animData.framesPerPhase or 10) * FixedStep.STEP,
    facing = "down",
    phase = 1,
    timer = 0,
  }, NpcSprite)
end

--- Advance the walk-cycle timer. `moving`: whether to animate at all
-- (freezes on the current phase otherwise, same real-observed behavior
-- as PlayerSprite -- the sprite doesn't revert to a separate "idle"
-- pose, it just stops cycling). `facing`: one of "down"/"up"/"left"/
-- "right" -- only read while `moving` (matches PlayerSprite's own
-- convention of not switching pose on a direction that isn't actually
-- being walked).
function NpcSprite:update(dt, moving, facing)
  if not moving then return end
  if facing and self.dirs[facing] then
    if self.facing ~= facing then
      self.facing = facing
      self.phase = 1
      self.timer = 0
    end
  end
  self.timer = self.timer + dt
  while self.timer >= self.phaseSeconds do
    self.timer = self.timer - self.phaseSeconds
    self.phase = (self.phase == 1) and 2 or 1
  end
end

function NpcSprite:draw(x, y)
  local pose = self.dirs[self.facing][self.phase]
  pose.sprite:draw(x, y, pose.flip, pose.flipY)
end

return NpcSprite
