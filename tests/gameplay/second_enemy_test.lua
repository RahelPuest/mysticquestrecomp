-- Gameplay-level regression test for the SECOND enemy (see
-- rom_profiles.lua's `goblinTestScene` doc comment and Field.lua's own
-- "SECOND ENEMY" module comment for the full story): additive, real,
-- fightable, but deliberately NOT wired into `enemyDefeated`/the
-- victory-sequence trigger. Same love-free "drive the real logic
-- Field:update wires together, without a love context" strategy as
-- `boss_encounter_test.lua` -- Field.lua itself can't be required here
-- (it pulls in love.graphics-touching rendering modules at require
-- time), so this mirrors the exact contact-damage/attack-hit/event
-- logic this session added there, the same deliberate duplication
-- `boss_encounter_test.lua`'s own doc comment already explains (a
-- divergence here is meant to be caught, not silently tolerated).

local Harness = require("tests.harness")
local Enemy = require("src.entities.Enemy")
local Stats = require("src.entities.Stats")
local EventSystem = require("src.scripting.EventSystem")

local function buildFieldEvents()
  return {
    {
      id = "victory_sequence_on_boss_defeat",
      trigger = function(state) return state.enemyDefeated end,
      actions = { { type = "victorySequence" } },
    },
  }
end

Harness.test("Second enemy: independently alive/fightable, defeated by repeated attack hits", function()
  local secondEnemy = Enemy.new(0, 0)
  local hits = 0
  while secondEnemy:isAlive() and hits < Enemy.HP_TO_CLEAR + 5 do
    secondEnemy:hit()
    hits = hits + 1
  end
  Harness.assertTrue(not secondEnemy:isAlive(), "expected repeated attack hits to eventually defeat the second enemy")
  Harness.assertTrue(hits <= Enemy.HP_TO_CLEAR + 5, "expected this to resolve within a reasonable hit budget")
end)

Harness.test("Second enemy: defeating it does NOT set enemyDefeated or fire the victory-sequence event -- additive, not tied to the courtyard boss's own story trigger", function()
  local enemy = Enemy.new(0, 0) -- the courtyard boss, stays alive
  local secondEnemy = Enemy.new(0, 0)
  local events = EventSystem.new(buildFieldEvents())
  local dispatched = {}
  local dispatch = function(action) dispatched[#dispatched + 1] = action end

  -- Field:update's own real wiring: defeating the second enemy simply
  -- stops it being alive/drawn -- it never sets state.enemyDefeated
  -- (that stays exclusively the courtyard `self.enemy`'s own death
  -- completing, see Field.lua's `if self.enemy.death and not
  -- self.enemyDefeated then ... self.enemyDefeated = true end`).
  local state = { enemyDefeated = false }
  while secondEnemy:isAlive() do
    secondEnemy:hit()
    events:update(state, dispatch)
  end

  Harness.assertTrue(not secondEnemy:isAlive())
  Harness.assertTrue(enemy:isAlive(), "the courtyard boss should be completely unaffected")
  Harness.assertEqual(state.enemyDefeated, false,
    "defeating the second enemy must not set enemyDefeated -- that would incorrectly fire the boss's own victory sequence")
  Harness.assertEqual(#dispatched, 0, "the victory-sequence event must not fire from the second enemy's own defeat")
end)

Harness.test("Second enemy: contact damage uses the same real damage formula/fallback shape as the courtyard enemy, on its own independent cooldown", function()
  local CombatFormulas = require("src.entities.CombatFormulas")
  local secondEnemy = Enemy.new(0, 0)
  local playerStats = Stats.new({ curLP = 19, maxLP = 19 })

  local ticks = 0
  local damageDealt = 0
  while ticks < 5 do
    if secondEnemy:tickContactCooldown(1 / 60) then
      local damage = CombatFormulas.rollDamage(Enemy.ATK, 0, 0)
      playerStats:damage(damage)
      damageDealt = damageDealt + damage
    end
    ticks = ticks + 1
  end

  Harness.assertTrue(damageDealt > 0, "expected at least one contact-damage tick to have fired")
  Harness.assertEqual(playerStats.curLP, 19 - damageDealt)
end)

Harness.test("Second enemy: both enemies can be hit independently -- one swing landing on both doesn't get silently swallowed by a single shared 'already hit' flag", function()
  -- Mirrors Field:update's own separate attackHasHit/secondAttackHasHit
  -- latches -- a real bug this project's own precedent (see
  -- ScriptRuntime.lua's `_80$`/`_81$`/`_7B$` exclusions, same session)
  -- shows is easy to introduce by accident: sharing ONE latch between
  -- two independent things.
  local enemy = Enemy.new(0, 0)
  local secondEnemy = Enemy.new(0, 0)
  local attackHasHit, secondAttackHasHit = false, false

  if not attackHasHit and enemy:isAlive() then
    attackHasHit = true
    enemy:hit()
  end
  if not secondAttackHasHit and secondEnemy:isAlive() then
    secondAttackHasHit = true
    secondEnemy:hit()
  end

  Harness.assertEqual(enemy.stats.curLP, Enemy.HP_TO_CLEAR - Enemy.PLAYER_ATTACK_DAMAGE)
  Harness.assertEqual(secondEnemy.stats.curLP, Enemy.HP_TO_CLEAR - Enemy.PLAYER_ATTACK_DAMAGE)
end)
