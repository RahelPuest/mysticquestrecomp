-- Pure random-walk NPC movement step -- extracted from
-- VictorySequence.lua's inline `updateNpcWander` (see that method's doc
-- comment: a reasonable approximation of secondRoom's wandering NPCs,
-- not a reproduction of the real PRNG algorithm -- that wasn't decoded,
-- only the fact that they genuinely move was confirmed live). Pulled
-- out here (no love.* calls, and the RNG itself is injectable) so it's
-- directly unit-testable -- see tests/unit/npc_wander_test.lua.

local NpcWander = {}

NpcWander.DIRECTIONS = { "up", "down", "left", "right", "pause" }

--- Advances one frame of wander movement. `state`: `{x=,y=,
-- facing=,wanderDir=,wanderTimer=}`, mutated in place (matches this
-- project's existing per-frame `:update(dt, ...)` convention rather
-- than returning a new table). `canMoveTo(x,y)`: optional collision
-- predicate (a room's `TileWalkability`-built function) -- a blocked
-- step leaves `state.x/y` unchanged. `rng`: optional `function() ->
-- float in [0,1)`, defaults to `math.random` (called with no
-- arguments, which is exactly this signature) -- inject a fixed/fake
-- sequence for deterministic tests instead of relying on
-- `math.random`'s global seed.
--
-- Returns `moving` (boolean) -- false while paused or blocked, matching
-- the captured behavior that the sprite freezes its walk-cycle
-- animation exactly then (see NpcSprite.lua).
function NpcWander.step(state, dt, canMoveTo, rng)
  rng = rng or math.random
  state.wanderTimer = state.wanderTimer - dt
  if state.wanderTimer <= 0 then
    local dirs = NpcWander.DIRECTIONS
    state.wanderDir = dirs[math.floor(rng() * #dirs) + 1]
    state.wanderTimer = 0.5 + rng() * 1.5
  end
  if not state.wanderDir or state.wanderDir == "pause" then
    return false
  end
  local dx, dy = 0, 0
  if state.wanderDir == "up" then dy = -1
  elseif state.wanderDir == "down" then dy = 1
  elseif state.wanderDir == "left" then dx = -1
  elseif state.wanderDir == "right" then dx = 1
  end
  local newX, newY = state.x + dx, state.y + dy
  if canMoveTo and not canMoveTo(newX, newY) then
    return false
  end
  state.x, state.y = newX, newY
  state.facing = state.wanderDir
  return true
end

return NpcWander
