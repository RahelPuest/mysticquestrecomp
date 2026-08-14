local Harness = require("tests.harness")
local NpcWander = require("src.entities.NpcWander")

--- A deterministic fake rng: returns the next value from a fixed
-- sequence each call (wrapping), instead of `math.random`'s global
-- seed -- makes every test below exactly reproducible.
local function fakeRng(sequence)
  local i = 0
  return function()
    i = (i % #sequence) + 1
    return sequence[i]
  end
end

Harness.test("NpcWander.step: picks a new direction once the timer expires", function()
  local state = { x = 0, y = 0, facing = "down", wanderDir = nil, wanderTimer = 0 }
  -- rng()=0 -> DIRECTIONS[floor(0*5)+1] = DIRECTIONS[1] = "up"
  local moving = NpcWander.step(state, 0.1, nil, fakeRng({ 0, 0 }))
  Harness.assertEqual(state.wanderDir, "up")
  Harness.assertTrue(moving, "an unblocked, non-pause direction should move")
  Harness.assertEqual(state.y, -1)
end)

Harness.test("NpcWander.step: 'pause' direction does not move and reports moving=false", function()
  local state = { x = 5, y = 5, facing = "down", wanderDir = nil, wanderTimer = 0 }
  -- rng()=0.9 -> floor(0.9*5)+1 = floor(4.5)+1 = 4+1 = 5 = DIRECTIONS[5] = "pause"
  local moving = NpcWander.step(state, 0.1, nil, fakeRng({ 0.9, 0 }))
  Harness.assertEqual(state.wanderDir, "pause")
  Harness.assertTrue(not moving)
  Harness.assertEqual(state.x, 5)
  Harness.assertEqual(state.y, 5)
end)

Harness.test("NpcWander.step: keeps the same direction while the timer hasn't expired", function()
  local state = { x = 0, y = 0, facing = "down", wanderDir = "right", wanderTimer = 10 }
  -- rng sequence would pick "up" if consulted -- it must NOT be, since wanderTimer is still positive after this one small step.
  NpcWander.step(state, 0.1, nil, fakeRng({ 0 }))
  Harness.assertEqual(state.wanderDir, "right", "should not re-roll before the timer expires")
  Harness.assertEqual(state.x, 1, "should keep moving right")
end)

Harness.test("NpcWander.step: a real regression -- blocked by canMoveTo, position unchanged, moving=false", function()
  local state = { x = 10, y = 10, facing = "down", wanderDir = nil, wanderTimer = 0 }
  local canMoveTo = function() return false end -- wall everywhere
  local moving = NpcWander.step(state, 0.1, canMoveTo, fakeRng({ 0, 0 })) -- picks "up"
  Harness.assertTrue(not moving, "a blocked step must report moving=false")
  Harness.assertEqual(state.x, 10, "x must not change when blocked")
  Harness.assertEqual(state.y, 10, "y must not change when blocked")
end)

Harness.test("NpcWander.step: unblocked canMoveTo allows the step through", function()
  local state = { x = 10, y = 10, facing = "down", wanderDir = nil, wanderTimer = 0 }
  local canMoveTo = function() return true end
  local moving = NpcWander.step(state, 0.1, canMoveTo, fakeRng({ 0, 0 })) -- picks "up"
  Harness.assertTrue(moving)
  Harness.assertEqual(state.y, 9)
end)

Harness.test("NpcWander.step: each cardinal direction moves exactly one pixel on its own axis", function()
  local cases = {
    { seq = 0.0, dir = "up", dx = 0, dy = -1 },
    { seq = 0.21, dir = "down", dx = 0, dy = 1 }, -- floor(0.21*5)=1 -> index 2 = "down"
    { seq = 0.41, dir = "left", dx = -1, dy = 0 }, -- floor(0.41*5)=2 -> index 3 = "left"
    { seq = 0.61, dir = "right", dx = 1, dy = 0 }, -- floor(0.61*5)=3 -> index 4 = "right"
  }
  for _, c in ipairs(cases) do
    local state = { x = 50, y = 50, facing = "down", wanderDir = nil, wanderTimer = 0 }
    NpcWander.step(state, 0.1, nil, fakeRng({ c.seq, 0 }))
    Harness.assertEqual(state.wanderDir, c.dir)
    Harness.assertEqual(state.x, 50 + c.dx, c.dir .. ": x")
    Harness.assertEqual(state.y, 50 + c.dy, c.dir .. ": y")
    Harness.assertEqual(state.facing, c.dir, c.dir .. ": facing should follow movement")
  end
end)

Harness.test("NpcWander.step: real captured cadence -- new timer is always between 0.5 and 2.0 seconds", function()
  local state = { x = 0, y = 0, facing = "down", wanderDir = nil, wanderTimer = 0 }
  NpcWander.step(state, 0.1, nil, fakeRng({ 0, 0 })) -- timer rng = 0 -> 0.5 + 0*1.5 = 0.5
  Harness.assertEqual(state.wanderTimer, 0.5)
  state.wanderTimer = 0
  NpcWander.step(state, 0.1, nil, fakeRng({ 0, 0.999999999 })) -- timer rng ~= 1 -> ~2.0
  Harness.assertTrue(state.wanderTimer > 1.9 and state.wanderTimer <= 2.0)
end)
