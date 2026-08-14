-- KnockbackFlicker: real live-captured contact-hit reaction (task #12
-- -- see src/entities/KnockbackFlicker.lua's own doc comment for the
-- exact frame-by-frame capture this reproduces). Pure Lua, no love.*
-- calls, headlessly testable like Enemy.lua.

local Harness = require("tests.harness")
local KnockbackFlicker = require("src.entities.KnockbackFlicker")

local function stepN(kb, n)
  local lastDx, lastDy = 0, 0
  for _ = 1, n do
    lastDx, lastDy = kb:update(1 / 60)
  end
  return lastDx, lastDy
end

Harness.test("KnockbackFlicker.new: inactive, visible, not invincible before any hit", function()
  local kb = KnockbackFlicker.new()
  Harness.assertTrue(kb:isVisible())
  Harness.assertTrue(not kb:isInvincible())
  Harness.assertTrue(not kb:isKnockbackActive())
  local dx, dy = kb:update(1 / 60)
  Harness.assertEqual(dx, 0)
  Harness.assertEqual(dy, 0)
end)

Harness.test("KnockbackFlicker:trigger: direction snaps to the dominant cardinal axis", function()
  local kb = KnockbackFlicker.new()
  -- Enemy above the player (real captured case: player approaches from
  -- below, enemy knocks it back down/away).
  kb:trigger(0, 0, 0, 40)
  Harness.assertEqual(kb.dirX, 0)
  Harness.assertEqual(kb.dirY, 1)

  local kb2 = KnockbackFlicker.new()
  kb2:trigger(0, 0, 40, 0) -- enemy to the left -> knockback to the right
  Harness.assertEqual(kb2.dirX, 1)
  Harness.assertEqual(kb2.dirY, 0)
end)

Harness.test("KnockbackFlicker: real knockback window is 8 frames of 4px each, starting 2 frames after the hit", function()
  local kb = KnockbackFlicker.new()
  kb:trigger(0, 0, 0, 40) -- knockback direction: +Y
  Harness.assertTrue(kb:isInvincible())

  -- Frames 0-1: no motion yet (real captured lead-in).
  local dx, dy = kb:update(1 / 60)
  Harness.assertEqual(dx, 0); Harness.assertEqual(dy, 0)
  dx, dy = kb:update(1 / 60)
  Harness.assertEqual(dx, 0); Harness.assertEqual(dy, 0)

  -- Frames 2-9 (8 frames): real 4px/frame knockback motion.
  local totalDy = 0
  for _ = 1, 8 do
    dx, dy = kb:update(1 / 60)
    Harness.assertEqual(dx, 0)
    Harness.assertEqual(dy, KnockbackFlicker.KNOCKBACK_PX_PER_FRAME)
    Harness.assertTrue(kb:isKnockbackActive())
    totalDy = totalDy + dy
  end
  Harness.assertEqual(totalDy, 32, "8 frames * 4px should total the real captured 32px knockback")

  -- Frame 10 on: knockback motion has ended.
  dx, dy = kb:update(1 / 60)
  Harness.assertEqual(dx, 0); Harness.assertEqual(dy, 0)
  Harness.assertTrue(not kb:isKnockbackActive())
end)

Harness.test("KnockbackFlicker: real flicker schedule matches the exact live-captured run lengths", function()
  local kb = KnockbackFlicker.new()
  kb:trigger(0, 0, 40, 0)

  local function runOf(n, expected, label)
    for i = 1, n do
      kb:update(1 / 60)
      Harness.assertEqual(kb:isVisible(), expected,
        label .. " frame " .. i .. " of " .. n)
    end
  end

  runOf(2, true, "lead-in")     -- frames 0-1
  runOf(8, false, "knockback")  -- frames 2-9
  runOf(5, true, "1st visible") -- frames 10-14 (the real irregular 5-frame run)
  runOf(8, false, "2nd invis")  -- frames 15-22
  runOf(8, true, "2nd visible") -- frames 23-30
  runOf(8, false, "3rd invis")  -- frames 31-38
  runOf(8, true, "3rd visible") -- frames 39-46
  runOf(8, false, "4th invis")  -- frames 47-54 -- still real-invisible on
                                 -- this very last reaction frame; matches
                                 -- the live capture exactly

  Harness.assertTrue(not kb:isInvincible(), "invincibility should end exactly at the real captured 55-frame mark")

  -- One more update (frame 55, post-reaction) is needed before
  -- isVisible() reflects "back to normal" -- it always mirrors the last
  -- frame update() actually processed, and frame 54 (just processed
  -- above) is itself still a real invisible frame.
  kb:update(1 / 60)
  Harness.assertTrue(kb:isVisible())
end)

Harness.test("KnockbackFlicker: a fresh trigger mid-reaction restarts the whole real schedule", function()
  local kb = KnockbackFlicker.new()
  kb:trigger(0, 0, 0, 40)
  stepN(kb, 20) -- deep into the reaction
  Harness.assertTrue(kb:isInvincible())

  kb:trigger(0, 0, 0, 40)
  Harness.assertEqual(kb.frame, 0)
  Harness.assertTrue(kb:isInvincible())
end)
