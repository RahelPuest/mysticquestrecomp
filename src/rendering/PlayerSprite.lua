-- The player's real walk-cycle animation -- direct fix for a real,
-- previously-wrong claim (see rom_profiles.lua's `playerSprite`
-- correction note): this project used to assert "no walk-cycle
-- animation exists at all," based only on checking whether the OAM tile
-- *index* ever changed. It doesn't -- but the raw VRAM *content* at that
-- same fixed index does, sampled every frame while moving (a real DMA
-- content-swap animation, not caught by the earlier, narrower check).
-- Direct user pushback: "es muss doch irgendwo im ROM eine tabelle...
-- mit den animationsphasen sein oder?" -- correct.
--
-- See rom_profiles.lua's `playerAnimation` entry for the full real
-- capture and its own honest limits (UP direction not confirmed either
-- way; the sprite freezes on its last walk pose when movement stops,
-- confirmed live over 150 real frames -- it does NOT revert to idle,
-- so this module doesn't either).

local CreatureSprite = require("src.rendering.CreatureSprite")
local FixedStep = require("src.core.FixedStep")

local PlayerSprite = {}
PlayerSprite.__index = PlayerSprite

local function pose(romData, top, bottom, palette)
  return CreatureSprite.fromOffsets(romData, { top[1], top[2], bottom[1], bottom[2] }, 2, 2, palette)
end

function PlayerSprite.new(romData, profile)
  local data = profile.graphics and profile.graphics.playerAnimation
  assert(data, "PlayerSprite.new expects profile.graphics.playerAnimation")
  local palette = CreatureSprite.getDefaultPalette()

  local self = setmetatable({
    poses = {
      idle = pose(romData, data.idle.top, data.idle.bottom, palette),
      down_B = pose(romData, data.down.top, data.down.legsB, palette),
      down_C = pose(romData, data.down.top, data.down.legsC, palette),
      leftright_B = pose(romData, data.leftRight.topB, data.leftRight.legsB, palette),
      leftright_C = pose(romData, data.leftRight.topC, data.leftRight.legsC, palette),
    },
    phaseSeconds = data.framesPerPhase * FixedStep.STEP,
    -- `animGroup`: nil (idle) until the player first moves in a
    -- direction with real captured animation data (down/left/right).
    -- Sticky thereafter while continuing in the SAME direction -- see
    -- module doc comment: the real sprite never reverts to idle just
    -- because movement stops, confirmed live, so this doesn't invent a
    -- revert there either. Moving UP, specifically, DOES reset this to
    -- nil/idle (2026-08-14 fix, see `:update`'s own doc comment) --
    -- `idle` is this game's real up-facing pose, and continuing to
    -- move up has no further confirmed animation beyond it anyway.
    animGroup = nil,
    phase = "B",
    timer = 0,
  }, PlayerSprite)
  return self
end

function PlayerSprite:update(dt, moving, facing)
  if not moving then return end -- freeze on the current pose, real behavior

  local group
  if facing == "down" then
    group = "down"
  elseif facing == "left" or facing == "right" then
    group = "leftright"
  end
  if not group then
    -- FIXED (2026-08-14, direct user report: "er schaut nicht in alle
    -- Richtungen"): this used to be a bare no-op for facing=="up" --
    -- correct for CONTINUING to move up (the real capture found no
    -- further tile-content change there, see this module's own doc
    -- comment), but wrong for the TRANSITION into up-movement from a
    -- different direction: a no-op here leaves `self.animGroup` (and
    -- therefore the rendered pose) stuck on whatever the PREVIOUS
    -- direction was showing -- the sprite kept visually "facing left"
    -- (or down) while the player was genuinely walking up. Since
    -- `idle` (the pose `self.animGroup == nil` renders, see `:draw`)
    -- IS this game's own real up-facing pose (`Player.DEFAULT_FACING
    -- == "up"`, same graphic BattleIntro.lua's own live-OAM-verified
    -- fix already confirmed), resetting to it here is a safe, real
    -- improvement either way: at worst (if the real ROM does show
    -- some not-yet-captured up-walk animation) it's the correct static
    -- frame of it; at best it's exactly right, matching the same fix
    -- already live-verified for the BattleIntro walk-in.
    self.animGroup = nil
    return
  end

  if self.animGroup ~= group then
    self.animGroup = group
    self.phase = "B"
    self.timer = 0
  end

  self.timer = self.timer + dt
  while self.timer >= self.phaseSeconds do
    self.timer = self.timer - self.phaseSeconds
    self.phase = (self.phase == "B") and "C" or "B"
  end
end

function PlayerSprite:draw(x, y, flipX)
  local key = self.animGroup and (self.animGroup .. "_" .. self.phase) or "idle"
  self.poses[key]:draw(x, y, flipX)
end

return PlayerSprite
