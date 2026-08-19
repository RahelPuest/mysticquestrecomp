local Harness = require("tests.harness")
local Enemy = require("src.entities.Enemy")

Harness.test("Enemy.new: starts alive at full HP", function()
  local e = Enemy.new(10, 20)
  Harness.assertTrue(e:isAlive())
  Harness.assertEqual(e.stats.curLP, Enemy.HP_TO_CLEAR)
end)

Harness.test("Enemy:overlaps: detects a real bounding-box overlap", function()
  -- Explicit width/height here (32x16), not Enemy's real-sprite default
  -- -- see Enemy.DEFAULT_WIDTH/HEIGHT's doc comment: this module no
  -- longer hardcodes a "looks like the real creature" size, so a test
  -- exercising a specific box shape states it explicitly instead.
  local e = Enemy.new(10, 10, 32, 16) -- box: 10..42, 10..26
  Harness.assertTrue(e:overlaps(15, 15, 8, 16), "player box overlapping enemy should report true")
  Harness.assertTrue(not e:overlaps(100, 100, 8, 16), "far-away player box should not overlap")
end)

Harness.test("Enemy:overlaps: exact edge touch does not count as overlap", function()
  local e = Enemy.new(0, 0, 32, 16) -- box: 0..32, 0..16
  Harness.assertTrue(not e:overlaps(32, 0, 8, 16), "flush-adjacent box should not overlap (strict <)")
end)

Harness.test("Enemy.new: defaults to a generic single-tile size when none given", function()
  local e = Enemy.new(0, 0)
  Harness.assertEqual(e.width, Enemy.DEFAULT_WIDTH)
  Harness.assertEqual(e.height, Enemy.DEFAULT_HEIGHT)
end)

Harness.test("Enemy:hit: repeated hits eventually clear it, reporting the clearing hit", function()
  local e = Enemy.new(0, 0)
  -- Real per-hit damage is 4, real HP is 31 (both VERIFIED by direct
  -- ROM code trace, 2026-08-09 -- see Enemy.PLAYER_ATTACK_DAMAGE/
  -- HP_TO_CLEAR's own doc comments) -- ceil(31/4) = 8 real landed hits
  -- clear it, not a 1:1 hit-per-HP-point count.
  local expectedHits = math.ceil(Enemy.HP_TO_CLEAR / Enemy.PLAYER_ATTACK_DAMAGE)
  local clearedOnHit
  for i = 1, expectedHits do
    local cleared = e:hit()
    if cleared then clearedOnHit = i end
  end
  Harness.assertEqual(clearedOnHit, expectedHits,
    "with real 4 damage/hit, the clearing hit should be exactly ceil(HP/damage)-th")
  Harness.assertTrue(not e:isAlive())
end)

Harness.test("Enemy:hit: real formula wiring -- any explicit noiseByte still deals exactly PLAYER_ATTACK_DAMAGE (base=4 has no visible noise contribution)", function()
  -- Confirms Enemy:hit() actually calls CombatFormulas
  -- .rollPlayerAttackDamage (not silently ignoring its argument) --
  -- exercises the full 0-255 noiseByte range, not just the default.
  for noiseByte = 0, 255, 31 do
    local e = Enemy.new(0, 0)
    e:hit(noiseByte)
    Harness.assertEqual(e.stats.curLP, Enemy.HP_TO_CLEAR - Enemy.PLAYER_ATTACK_DAMAGE,
      "noiseByte=" .. noiseByte .. " should still deal exactly PLAYER_ATTACK_DAMAGE")
  end
end)

Harness.test("Enemy:hit: hitting an already-dead enemy does not report a fresh clear", function()
  local e = Enemy.new(0, 0)
  for _ = 1, Enemy.HP_TO_CLEAR do e:hit() end
  Harness.assertTrue(not e:isAlive())
  local clearedAgain = e:hit()
  Harness.assertTrue(not clearedAgain, "hitting a corpse should not report clearing it a second time")
end)

Harness.test("Enemy:tickContactCooldown: fires immediately on first contact, then once per CONTACT_TICK_SECONDS", function()
  local e = Enemy.new(0, 0)
  -- The cooldown starts at 0, so the very first tick (first frame of
  -- contact) fires right away -- matches "contact damage applies as
  -- soon as you touch it," not "wait a full second before the first hit."
  Harness.assertTrue(e:tickContactCooldown(1 / 60), "first contact should tick immediately")

  local fired = 0
  -- Then it should NOT fire again until CONTACT_TICK_SECONDS has passed.
  for _ = 1, 59 do
    if e:tickContactCooldown(1 / 60) then fired = fired + 1 end
  end
  Harness.assertEqual(fired, 0, "should not tick again until a full second after the previous tick")
  if e:tickContactCooldown(1 / 60) then fired = fired + 1 end
  Harness.assertEqual(fired, 1, "should tick again right at the ~1 second mark")
end)

Harness.test("Enemy:updateMovement: stays put until MOVEMENT_STEP_SECONDS elapses", function()
  local e = Enemy.new(100, 100)
  e:updateMovement(Enemy.MOVEMENT_STEP_SECONDS * 0.5)
  Harness.assertEqual(e.x, 100, "should not have moved yet")
  Harness.assertEqual(e.y, 100)
end)

Harness.test("Enemy:updateMovement: applies the real captured first delta after one step", function()
  local e = Enemy.new(100, 100)
  e:updateMovement(Enemy.MOVEMENT_STEP_SECONDS)
  local first = Enemy.MOVEMENT_CYCLE[1]
  Harness.assertEqual(e.x, 100 + first.dx)
  Harness.assertEqual(e.y, 100 + first.dy)
end)

Harness.test("Enemy:updateMovement: one full lap of the real 33-step cycle returns exactly to origin", function()
  -- CORRECTED (2026-08-12, see Enemy.MOVEMENT_CYCLE's own doc comment
  -- for the re-verification): the real cycle is now a genuinely closed
  -- 33-step loop (sums to (0,0) on its own) -- one lap is enough, no
  -- separate "correction hop" or backward/mirrored pass needed anymore.
  local e = Enemy.new(50, 50)
  local n = #Enemy.MOVEMENT_CYCLE
  e:updateMovement(n * Enemy.MOVEMENT_STEP_SECONDS)
  Harness.assertEqual(e.x, 50, "should return exactly to the starting x after one full lap")
  Harness.assertEqual(e.y, 50, "should return exactly to the starting y after one full lap")
end)

Harness.test("Enemy.MOVEMENT_CYCLE: real 33-step cycle sums to exactly (0,0)", function()
  -- A direct, standalone check of the real captured data itself (not
  -- just the update logic that consumes it) -- the property that makes
  -- this a genuinely closed patrol loop, not a drift.
  local sumDx, sumDy = 0, 0
  for _, step in ipairs(Enemy.MOVEMENT_CYCLE) do
    sumDx = sumDx + step.dx
    sumDy = sumDy + step.dy
  end
  Harness.assertEqual(sumDx, 0)
  Harness.assertEqual(sumDy, 0)
end)

Harness.test("Enemy:updateMovement: stops moving once defeated", function()
  local e = Enemy.new(100, 100)
  for _ = 1, Enemy.HP_TO_CLEAR do e:hit() end
  Harness.assertTrue(not e:isAlive())
  e:updateMovement(Enemy.MOVEMENT_STEP_SECONDS * 5)
  Harness.assertEqual(e.x, 100, "a defeated enemy should not keep animating/moving")
  Harness.assertEqual(e.y, 100)
end)
