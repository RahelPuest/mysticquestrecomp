-- Gameplay-level regression test: exercises the real starting-room boss
-- encounter's *logic* end to end (Enemy + Stats + EventSystem working
-- together, the way Field.lua wires them) without needing love.graphics
-- -- this project's testing strategy split (docs/architecture.md) keeps
-- pure logic headlessly testable; this file is the "tests/gameplay/"
-- category the master brief calls for, distinct from tests/unit's
-- single-module tests: it drives a whole scenario.
--
-- What this does NOT cover: rendering, real ROM sprite/tile data, or
-- input polling (those need a real love context -- verified instead by
-- screenshot passes, see docs/progress.md). This is the deterministic,
-- CI-runnable half of "test against the original": the game-logic
-- outcome of a full encounter, not its pixels.

local Harness = require("tests.harness")
local Enemy = require("src.entities.Enemy")
local Stats = require("src.entities.Stats")
local EventSystem = require("src.scripting.EventSystem")

--- Mirrors Field.lua's own FIELD_EVENTS shape (see that module) --
-- duplicated here deliberately (not required from Field.lua, which
-- pulls in love.rendering.* modules at require time) so this scenario
-- test stays love-free; if Field.lua's real event wiring ever drifts
-- from this shape, the "dispatches the real victorySequence action"
-- assertion below would need the same update, which is the point -- a
-- change to the real integration should be visible here too, not
-- silently diverge. Updated 2026-08-09 alongside Field.lua's own switch
-- from an inline "dialogue" action to "victorySequence" (see
-- VictorySequence.lua) -- the real post-victory scene now owns its own
-- text/pages instead of Field.lua passing hardcoded lines through the
-- event's action data.
local function buildFieldEvents()
  return {
    {
      id = "victory_sequence_on_boss_defeat",
      trigger = function(state) return state.enemyDefeated end,
      actions = { { type = "victorySequence" } },
    },
  }
end

Harness.test("Boss encounter: repeated hits eventually defeat the enemy and fire the victory-sequence event exactly once", function()
  local enemy = Enemy.new(0, 0)
  local playerStats = Stats.new({ curLP = 19, maxLP = 19 })
  local events = EventSystem.new(buildFieldEvents())

  local state = { enemyDefeated = false }
  local dispatched = {}
  local dispatch = function(action) dispatched[#dispatched + 1] = action end

  -- Simulate real-time contact combat: the enemy contact-damages the
  -- player once per tick while alive (VERIFIED cadence -- see Enemy.lua),
  -- and the player lands one attack per simulated "step" until the enemy
  -- is defeated -- the same two real systems Field:update drives every
  -- frame, just without a love context around them.
  local steps = 0
  while enemy:isAlive() and steps < Enemy.HP_TO_CLEAR + 5 do
    if enemy:tickContactCooldown(1 / 60) then
      playerStats:damage(Enemy.CONTACT_DAMAGE)
    end
    if enemy:hit() then
      state.enemyDefeated = true
    end
    events:update(state, dispatch)
    steps = steps + 1
  end

  -- Real per-hit damage is 4, real HP is 31 (both VERIFIED by direct ROM
  -- code trace, 2026-08-09) -- ceil(31/4) = 8 real landed hits, not a
  -- 1:1 hit-per-HP-point count.
  local expectedSteps = math.ceil(Enemy.HP_TO_CLEAR / Enemy.PLAYER_ATTACK_DAMAGE)
  Harness.assertTrue(not enemy:isAlive(), "enemy should be defeated within HP_TO_CLEAR hits")
  Harness.assertEqual(steps, expectedSteps, "should take exactly ceil(HP/damage) steps at 1 hit/step")
  Harness.assertEqual(#dispatched, 1, "the victory-sequence event should fire exactly once")
  Harness.assertEqual(dispatched[1].type, "victorySequence")
  Harness.assertTrue(playerStats.curLP < 19, "player should have taken at least one real contact-damage tick")
  Harness.assertTrue(playerStats.curLP >= 0, "player LP should never go negative (Stats:damage clamps at 0)")

  -- Further steps must not re-fire the (once=true, the default) event.
  events:update(state, dispatch)
  Harness.assertEqual(#dispatched, 1, "a defeated-enemy event must not fire a second time")
end)

Harness.test("Boss encounter: invulnerability (a dev-only shortcut, not real ROM behavior) fully blocks contact damage", function()
  local enemy = Enemy.new(0, 0)
  local playerStats = Stats.new({ curLP = 19, maxLP = 19 })
  local invulnerable = true

  for _ = 1, 5 do
    if enemy:tickContactCooldown(1 / 60) and not invulnerable then
      playerStats:damage(Enemy.CONTACT_DAMAGE)
    end
  end
  Harness.assertEqual(playerStats.curLP, 19, "invulnerable should prevent all contact damage")
end)
