-- Native player entity: position + movement, driven by FixedStep ticks
-- (not render framerate) per the project's timing-fidelity rule.
--
-- Movement speed is not guessed: it's the VERIFIED fact from dynamic
-- tracing (see docs/progress.md "Player OAM slot and walk speed
-- VERIFIED", docs/reverse-engineering/tooling.md) -- holding a direction
-- in-game moves the hero sprite exactly 1 pixel per frame, every frame,
-- no acceleration or sub-pixel remainder, confirmed by sampling the real
-- OAM sprite X coordinate for 39 consecutive frames under mGBA. At the
-- DMG's real ~59.7275 Hz (`FixedStep.HZ`), that's this constant.
--
-- VERIFIED (2026-08-09): vertical speed is exactly 1px/frame too, same
-- as horizontal -- held UP from a real live position with open floor
-- above and sampled OAM Y every frame; matches PIXELS_PER_STEP exactly
-- (one frame of input-registration lag on the very first held frame,
-- then 1px every frame after).
--
-- VERIFIED (2026-08-09): diagonal movement is NOT allowed -- holding
-- UP+RIGHT simultaneously from a fresh (nothing previously held) input
-- state moved only vertically, X never changed. HONEST LIMIT (recorded
-- the same pass): a follow-up test (RIGHT held first, then DOWN added
-- while RIGHT continued) kept moving horizontally instead, and
-- releasing RIGHT afterward didn't switch to vertical for several more
-- frames -- real behavior here looks stateful ("keep moving on
-- whichever axis is already active, only re-arbitrate once no direction
-- is held") rather than a flat vertical-always-wins rule -- but only the
-- simultaneous-fresh-press case was actually implemented that pass, not
-- the sticky/release-order nuance the SAME pass's own capture already
-- pointed at.
--
-- IMPLEMENTED (2026-08-12, direct user report: "die controls scheinen
-- off zu sein" -- this exact, already-documented gap): `self.activeAxis`
-- now tracks whichever axis is currently "owned" by movement -- once
-- set, it keeps controlling movement for as long as ITS OWN key(s) stay
-- held, even if a perpendicular key is newly pressed alongside it
-- (matching the real "RIGHT held, DOWN added, kept going right"
-- capture above); it's only cleared (letting a fresh arbitration run,
-- vertical-wins-on-simultaneous-press) once its own key is released.
-- STILL HONEST LIMIT: the real capture's own "releasing RIGHT didn't
-- switch to vertical for several more frames" nuance (a real lag on
-- release, not an instant re-arbitration) is NOT reproduced -- this
-- switches immediately on release, a reasonable middle ground, not a
-- claimed frame-exact reproduction of that specific lag (which this
-- project has not pinned down to an exact frame count).
--
-- Real wall collision (2026-08-09): now checked via an optional
-- `canMoveTo(x, y)` callback (see `Player:update` below), applied per
-- axis so movement naturally slides along a wall instead of stopping
-- dead on any contact -- Field.lua builds this from the real starting
-- room's own captured tile grid (rom_profiles.lua's `startRoom`), not
-- a decoded per-tile ROM collision-flag table (none has been found --
-- see rom-map.md "Maps") -- it's this project's own classification of
-- which real tile IDs read as floor/decoration vs. wall/gate structure,
-- a reasonable approximation of real collision, not a verified ROM fact
-- itself.

local GBTile = require("src.rendering.GBTile")

local Player = {}
Player.__index = Player

-- VERIFIED (see module doc comment above): 1 px per fixed step.
Player.PIXELS_PER_STEP = 1

-- REAL, general Game Boy hardware fact (2026-08-15, direct follow-up
-- to a user-reported spawn-position bug): a live dump of the real OAM
-- table showed the player's own WRAM position (`$C244`/`$C245`, this
-- module's own `x`/`y`) copies DIRECTLY into hardware OAM with no
-- shift applied anywhere in this ROM. But real Game Boy hardware
-- ALWAYS encodes an OAM sprite's Y/X as `(true screen top-left) + (8,
-- 16)` -- fixed PPU silicon behavior, not ROM-specific, unavoidable on
-- real hardware. So `self.x`/`self.y` (this project's own collision-
-- space coordinate, matching the real ROM's WRAM value byte-for-byte)
-- is NOT the same thing as where the sprite actually appears on a real
-- screen -- it's 8px right / 16px down from the true rendered
-- position. Live-verified this exact relationship at 2 independent
-- real transitions (thirdRoom's staircase and fourthRoom's own north
-- exit) -- see docs/reverse-engineering/rom-map.md's own dated "Real
-- hardware OAM-vs-WRAM sprite offset" section for the full trace.
--
-- HONEST SCOPE: only confirmed for the PLAYER's own entity slot
-- (`EntityStructLayout.PLAYER_SLOT_INDEX_HYPOTHESIS = 4`). A live check
-- of the courtyard boss's own entity slot at the same moment found NO
-- other slot populated with a real Y/X pair at all (the enemy doesn't
-- appear to use this same 20-slot struct's position fields the way the
-- player does, or wasn't populated yet at that exact checkpoint) --
-- genuinely unconfirmed for enemies/NPCs, NOT assumed to share this
-- constant. `Field.lua`/`VictorySequence.lua` apply this ONLY to the
-- player (and the player-attached attack-swing/thrust overlays, which
-- must move with it) -- enemy/boss/NPC draw calls are deliberately
-- left untouched.
--
-- Used ONLY at the final draw call, never for collision: `self.x`/
-- `self.y` themselves stay the real, raw WRAM-matching value
-- everywhere else in this project (movement, `TileWalkability`
-- .canMoveTo`, every room's own `floorTileIds`/`grid`/`blockedRects`,
-- all of which were built and tuned against this SAME raw convention)
-- -- changing what those represent would risk silently breaking every
-- already-verified collision boundary in the game. Purely a rendering
-- correction.
Player.RENDER_OFFSET_X = -8
Player.RENDER_OFFSET_Y = -16

--- Where the player's sprite should actually be DRAWN on a real
-- screen -- see `RENDER_OFFSET_X`/`RENDER_OFFSET_Y`'s own doc comment.
-- `self.x`/`self.y` themselves are deliberately left untouched (still
-- the real, raw collision-space coordinate) -- call this only at the
-- point of drawing, never for movement/collision.
function Player:renderPosition()
  return self.x + Player.RENDER_OFFSET_X, self.y + Player.RENDER_OFFSET_Y
end

-- NOT the real sprite size -- deliberately a generic single-tile
-- fallback (see `Player.new`'s `width`/`height` params), used only when
-- no real ROM profile sprite data is available (e.g. some unit tests
-- construct a Player with no ROM at all). Real gameplay code (Field.lua)
-- always passes the actual size, computed from `profile.graphics
-- .playerSprite.cols/rows * GBTile.TILE_W/TILE_H` -- i.e. derived from
-- the same real ROM data used to build the actual sprite image, not a
-- second, independently-hardcoded number that could silently drift out
-- of sync with it (which is exactly what happened here once already:
-- an earlier pass hardcoded 16x16 by hand after re-deriving it, and
-- direct user feedback -- "bitte hardcode die sprite sizes nicht, nimm
-- sie aus dem rom" -- correctly called that out as still wrong in
-- principle even though the number itself was briefly right).
Player.DEFAULT_WIDTH = GBTile.TILE_W
Player.DEFAULT_HEIGHT = GBTile.TILE_H

--- `width`/`height`: real sprite pixel size, normally
-- `cols * GBTile.TILE_W` / `rows * GBTile.TILE_H` from the ROM's own
-- sprite profile (see rom_profiles.lua's `playerSprite`) -- callers
-- with no real ROM data available may omit them, falling back to
-- `Player.DEFAULT_WIDTH/HEIGHT` (a generic single tile, not a guess at
-- the real creature's size).
-- VERIFIED (2026-08-09, real attack-swing investigation): the idle/spawn
-- facing is UP, not "down" as this project previously assumed without
-- ever actually checking. The idle sprite alone can't distinguish
-- left/up/down (all three render identically -- see CreatureSprite
-- .draw's doc comment), so this was unverifiable until the real
-- directional attack-swing animation was found and captured (see
-- rom_profiles.lua's `attackSwing` entry): a fresh, never-moved spawn's
-- swing exactly matches the swing captured after deliberately holding
-- UP (same tile/attr sequence, dx values identical, dy differing only by
-- the small vertical offset expected from the two captures' slightly
-- different player Y) -- i.e. the game's own internal facing state at
-- spawn really is "up," this project's engine just never rendered it
-- differently because the idle art doesn't change.
Player.DEFAULT_FACING = "up"

function Player.new(x, y, width, height)
  return setmetatable({
    x = x or 0,
    y = y or 0,
    width = width or Player.DEFAULT_WIDTH,
    height = height or Player.DEFAULT_HEIGHT,
    facing = Player.DEFAULT_FACING,
    moving = false,
    -- Real "sticky axis" state (see :update's own doc comment) -- nil
    -- (no axis in control), "x", or "y".
    activeAxis = nil,
  }, Player)
end

--- Advance one fixed step. `input` is a src.core.Input instance.
-- `bounds` is a { minX, minY, maxX, maxY } rectangle (inclusive pixel
-- range for the sprite's top-left corner) the player is confined to --
-- caller's responsibility (e.g. Field state passes the current room's
-- known extent). `canMoveTo(x, y)` is an optional callback -- if given,
-- each axis's move is applied only if `canMoveTo` (checked against the
-- *post-move* position on that axis) returns true, otherwise that axis
-- is reverted -- real per-tile wall collision, checked one axis at a
-- time so movement slides along a wall rather than stopping outright.
function Player:update(dt, input, bounds, canMoveTo)
  local dx, dy = 0, 0
  if input:isDown("left") then dx = dx - 1 end
  if input:isDown("right") then dx = dx + 1 end
  if input:isDown("up") then dy = dy - 1 end
  if input:isDown("down") then dy = dy + 1 end

  -- Real "sticky axis" arbitration (see module doc comment): an axis
  -- already in control stays in control as long as ITS OWN key(s) are
  -- still held, regardless of what the other axis is doing; only a
  -- released axis re-arbitrates, with vertical winning a fresh
  -- simultaneous press (the one case directly VERIFIED live).
  if self.activeAxis == "y" and dy == 0 then self.activeAxis = nil end
  if self.activeAxis == "x" and dx == 0 then self.activeAxis = nil end
  if self.activeAxis == "y" then
    dx = 0
  elseif self.activeAxis == "x" then
    dy = 0
  elseif dy ~= 0 then
    dx = 0
    self.activeAxis = "y"
  elseif dx ~= 0 then
    self.activeAxis = "x"
  end

  self.moving = (dx ~= 0 or dy ~= 0)
  if dx < 0 then self.facing = "left"
  elseif dx > 0 then self.facing = "right"
  elseif dy < 0 then self.facing = "up"
  elseif dy > 0 then self.facing = "down"
  end

  local newX = self.x + dx * Player.PIXELS_PER_STEP
  local newY = self.y + dy * Player.PIXELS_PER_STEP

  if dx ~= 0 and (not canMoveTo or canMoveTo(newX, self.y)) then
    self.x = newX
  end
  if dy ~= 0 and (not canMoveTo or canMoveTo(self.x, newY)) then
    self.y = newY
  end

  if bounds then
    if self.x < bounds[1] then self.x = bounds[1] end
    if self.y < bounds[2] then self.y = bounds[2] end
    if self.x > bounds[3] then self.x = bounds[3] end
    if self.y > bounds[4] then self.y = bounds[4] end
  end
end

return Player
