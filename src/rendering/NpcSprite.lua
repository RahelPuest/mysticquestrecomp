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
-- CORRECTED (2026-08-15, direct user report "die npc sprites a und b
-- jeweils 16x16 gross sind"): a fresh live OAM re-trace found these are
-- REAL 16x16 (2x2-tile) sprites -- 2 real OAM entries at the SAME Y, X
-- 8px apart (a genuine LEFT+RIGHT pair, each already 8x16 in hardware
-- 8x16-OBJ-mode), not the single 8x16-OBJ-mode column this project
-- previously, wrongly, modeled them as (that earlier claim only ever
-- captured the upper-row tile of each column, silently dropping the
-- entire lower row). See rom_profiles.lua's `secondRoom.scene
-- .characterA/B.animation` doc comment for the full live-trace
-- evidence and the formula that recovered the missing tiles.

local CreatureSprite = require("src.rendering.CreatureSprite")
local FixedStep = require("src.core.FixedStep")

local NpcSprite = {}
NpcSprite.__index = NpcSprite

local DIRECTIONS = { "down", "up", "left", "right" }

--- `def.tileOffsets`: the real 4-tile, row-major 2x2 block (see
-- rom_profiles.lua's own doc comment) -- {top-left, top-right,
-- bottom-left, bottom-right}, matching `TileImage.buildSheet`'s own
-- row-major layout convention exactly (the SAME one Willy/the player
-- already use for their own 2x2 sprites).
local function buildPose(romData, def, palette)
  return {
    sprite = CreatureSprite.fromOffsets(romData, def.tileOffsets, 2, 2, palette),
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
