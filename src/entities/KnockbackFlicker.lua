-- Player contact-hit reaction: knockback + invincibility flicker (see
-- docs/reverse-engineering/combat.md "Real contact-hit reaction").
--
-- VERIFIED (precise live capture -- upgrades earlier "~6 frames"/"~8
-- frames" estimates to exact numbers): walked the player into the
-- starting-room creature under mGBA and watched, frame by frame, from
-- the exact instant WRAM `$D7B2` (current LP) drops: (1) the player's
-- OAM Y coordinate, and (2) whether the player's OAM tile *content*
-- (not just its index -- a hardware bug this project already learned
-- the hard way once, see `rom_profiles.lua`'s player-sprite doc
-- comment: OAM/sprite tiles always use unsigned `$8000` addressing
-- regardless of `LCDC` bit 4, unlike BG/window tiles -- an earlier
-- attempt wrongly applied the BG addressing rule to sprite tiles and
-- got "always blank" as a false reading until this was caught and
-- fixed) matches its known-good ROM bytes (visible) or reads all-zero
-- (invisible).
--
-- Captured schedule, frame offset from the hit (frame 0 = the frame
-- `$D7B2` visibly changed):
--   0-1    visible   (still settling -- the hit has registered but
--                      neither effect has visibly started yet)
--   2-9    invisible, and this is exactly when the knockback motion
--          happens: OAM Y moved by a clean, constant 4px every frame
--          for these 8 frames (32px total), always away from the
--          enemy along the approach axis (only a straight-on approach
--          was tested -- see `knockbackDirection` below for how this
--          generalizes to the untested axis).
--   10-14  visible (5 frames)
--   15-22  invisible (8 frames)
--   23-30  visible (8 frames)
--   31-38  invisible (8 frames)
--   39-46  visible (8 frames)
--   47-54  invisible (8 frames)
--   55+    back to normal -- visible, and (matches this project's
--          already-VERIFIED `Enemy.CONTACT_TICK_SECONDS = 1.0` = 60
--          frames) contact damage can fire again almost immediately
--          after invincibility ends, not a long safe window.
-- The one irregular run (5 frames visible at 10-14, vs. a clean 8
-- everywhere else) is recorded exactly as captured, not smoothed into a
-- tidier-looking "always 8" pattern that wasn't actually measured.
--
-- NOT independently ROM-code-traced (no WRAM knockback-timer/velocity
-- field or ROM routine address is known for this effect) -- this is
-- precise, live-captured behavior, reproduced faithfully, the same
-- evidentiary standing as `Enemy.MOVEMENT_CYCLE`'s captured-not-decoded
-- data. A genuine ROM-code trace (the project's normal preference) is a
-- reasonable future upgrade, not done yet.
--
-- Pure Lua, no love.* calls, so it's headlessly testable like Enemy.lua.

local FixedStep = require("src.core.FixedStep")

local KnockbackFlicker = {}
KnockbackFlicker.__index = KnockbackFlicker

-- Real captured (start, end, visible) runs, frame offsets from the hit
-- (inclusive), in order -- see module doc comment.
KnockbackFlicker.SCHEDULE = {
  { from = 0, to = 1, visible = true },
  { from = 2, to = 9, visible = false },
  { from = 10, to = 14, visible = true },
  { from = 15, to = 22, visible = false },
  { from = 23, to = 30, visible = true },
  { from = 31, to = 38, visible = false },
  { from = 39, to = 46, visible = true },
  { from = 47, to = 54, visible = false },
}
-- Frame 55+ is real normal state (visible, hittable again) -- one past
-- the schedule's last entry.
KnockbackFlicker.TOTAL_FRAMES = 55

-- The real invisible+moving window (frames 2-9 above): 8 frames, 4px
-- each, always away from the enemy.
KnockbackFlicker.KNOCKBACK_START_FRAME = 2
KnockbackFlicker.KNOCKBACK_FRAMES = 8
KnockbackFlicker.KNOCKBACK_PX_PER_FRAME = 4

function KnockbackFlicker.new()
  return setmetatable({
    active = false,
    frame = 0,
    dirX = 0,
    dirY = 0,
    -- Cached results for the frame `update()` most recently processed,
    -- so `isVisible()`/`isKnockbackActive()` (typically called later
    -- the same tick, for drawing/control decisions) agree exactly with
    -- what `update()` itself just computed -- no separate off-by-one-
    -- prone frame arithmetic in each query method.
    visibleNow = true,
    knockbackActiveNow = false,
  }, KnockbackFlicker)
end

--- Start a contact-hit reaction. `enemyX/enemyY`/`playerX/playerY` are
-- box centers -- direction is the dominant (larger-magnitude) axis from
-- enemy to player, snapped to a single cardinal direction (matches this
-- being a simple top-down grid game with no diagonal knockback
-- observed) -- see module doc comment: only the straight-on approach
-- axis was directly captured, so a perpendicular hit's direction is
-- this module's reasonable extrapolation, not independently verified.
--
-- KNOWN EDGE CASE (found during screenshot testing, not fixed -- the
-- enemy patrols, see Enemy.MOVEMENT_CYCLE): since direction is computed
-- from box centers at the exact contact instant, an approach that
-- overlaps the enemy from an unusual angle (e.g. the player still
-- holding a direction that has carried it past the enemy's current
-- patrol position) can compute an "away" vector that points back toward
-- the room's wall/gate rather than into open floor. The one directly-
-- tested scenario (a clean approach from the south, the only approach
-- direction the actual room's layout allows) always knocks the player
-- south into open space, matching the live capture exactly -- this edge
-- case needs an unusually aggressive/held approach to reach and was not
-- observed in ordinary play.
function KnockbackFlicker:trigger(enemyX, enemyY, playerX, playerY)
  local dx, dy = playerX - enemyX, playerY - enemyY
  if math.abs(dx) >= math.abs(dy) then
    self.dirX, self.dirY = (dx >= 0) and 1 or -1, 0
  else
    self.dirX, self.dirY = 0, (dy >= 0) and 1 or -1
  end
  self.active = true
  self.frame = 0
end

--- Advances one real frame (call once per FixedStep tick, matching the
-- live capture's own per-frame granularity -- not a seconds-accumulator
-- like Enemy:tickContactCooldown, since this is schedule/frame-indexed
-- data, not a repeating timer). Returns (dx, dy): the real pixel offset
-- to apply to the player's position this frame (0,0 outside the
-- knockback window). Also updates `isVisible()`/`isKnockbackActive()`'s
-- cached results for this same frame -- call this once per tick BEFORE
-- querying either.
function KnockbackFlicker:update(dt)
  if not self.active then
    self.visibleNow, self.knockbackActiveNow = true, false
    return 0, 0
  end

  local dx, dy = 0, 0
  local kf = self.frame - KnockbackFlicker.KNOCKBACK_START_FRAME
  self.knockbackActiveNow = kf >= 0 and kf < KnockbackFlicker.KNOCKBACK_FRAMES
  if self.knockbackActiveNow then
    dx = self.dirX * KnockbackFlicker.KNOCKBACK_PX_PER_FRAME
    dy = self.dirY * KnockbackFlicker.KNOCKBACK_PX_PER_FRAME
  end

  self.visibleNow = true
  for _, run in ipairs(KnockbackFlicker.SCHEDULE) do
    if self.frame >= run.from and self.frame <= run.to then
      self.visibleNow = run.visible
      break
    end
  end

  self.frame = self.frame + 1
  if self.frame >= KnockbackFlicker.TOTAL_FRAMES then
    self.active = false
  end
  return dx, dy
end

--- Whether contact damage should be blocked right now (real invincibility
-- window -- matches this project's own established F4 dev-invulnerable
-- naming, but this is the real ROM-observed mechanic, not the dev
-- shortcut).
function KnockbackFlicker:isInvincible()
  return self.active
end

--- Whether player control should be suspended right now (the real
-- knockback motion frames only -- a reasonable implementation choice
-- for "don't fight forced motion with held input," not itself
-- independently verified -- see module doc comment). Reflects the frame
-- `update()` most recently processed.
function KnockbackFlicker:isKnockbackActive()
  return self.knockbackActiveNow
end

--- Whether the player sprite should be drawn this frame (real flicker
-- schedule -- see module doc comment). Reflects the frame `update()`
-- most recently processed; always true once the reaction has ended.
function KnockbackFlicker:isVisible()
  return self.visibleNow
end

return KnockbackFlicker
