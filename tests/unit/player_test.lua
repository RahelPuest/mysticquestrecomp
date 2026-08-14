local Harness = require("tests.harness")
local Player = require("src.entities.Player")

local function fakeInput(down)
  return {
    isDown = function(_, button) return down[button] == true end,
  }
end

Harness.test("Player.new: defaults to (0,0), not moving", function()
  local p = Player.new()
  Harness.assertEqual(p.x, 0)
  Harness.assertEqual(p.y, 0)
  Harness.assertTrue(not p.moving)
end)

Harness.test("Player.new: defaults to a generic single-tile size when none given, real size when passed", function()
  local p = Player.new(0, 0)
  Harness.assertEqual(p.width, Player.DEFAULT_WIDTH)
  Harness.assertEqual(p.height, Player.DEFAULT_HEIGHT)

  -- Real gameplay code passes the actual ROM-derived size (see
  -- Field.lua) instead of relying on this generic fallback.
  local p2 = Player.new(0, 0, 16, 16)
  Harness.assertEqual(p2.width, 16)
  Harness.assertEqual(p2.height, 16)
end)

Harness.test("Player:update: moves exactly 1px per step when a direction is held (VERIFIED speed)", function()
  local p = Player.new(10, 10)
  p:update(1 / 60, fakeInput({ right = true }))
  Harness.assertEqual(p.x, 11)
  Harness.assertEqual(p.y, 10)
  Harness.assertTrue(p.moving)
  Harness.assertEqual(p.facing, "right")
end)

Harness.test("Player:update: does not move when no direction is held", function()
  local p = Player.new(5, 5)
  p:update(1 / 60, fakeInput({}))
  Harness.assertEqual(p.x, 5)
  Harness.assertEqual(p.y, 5)
  Harness.assertTrue(not p.moving)
end)

Harness.test("Player:update: repeated steps accumulate at exactly 1px/step (no drift)", function()
  local p = Player.new(0, 0)
  local input = fakeInput({ down = true })
  for _ = 1, 39 do
    p:update(1 / 60, input)
  end
  Harness.assertEqual(p.y, 39, "39 steps at 1px/step should move exactly 39px, matching the traced sample")
end)

Harness.test("Player:update: no diagonal movement -- vertical wins when both are held (VERIFIED)", function()
  local p = Player.new(0, 0)
  p:update(1 / 60, fakeInput({ up = true, left = true }))
  -- VERIFIED live (see module doc comment): holding two directions at
  -- once moves only vertically, not diagonally.
  Harness.assertEqual(p.x, 0, "horizontal movement should be suppressed while a vertical direction is held")
  Harness.assertEqual(p.y, -1)
  Harness.assertEqual(p.facing, "up")
end)

Harness.test("Player:update: sticky axis -- an already-held direction keeps control when a perpendicular one is added (2026-08-12 fix)", function()
  -- Real, live-captured behavior (see module doc comment): holding
  -- RIGHT, then adding DOWN while RIGHT stays held, kept moving
  -- horizontally in the real ROM -- the old flat "vertical always wins"
  -- rule got this wrong (would have snapped to vertical the instant
  -- DOWN was added). Direct user report this fix responds to: "die
  -- controls scheinen off zu sein."
  local p = Player.new(0, 0)
  p:update(1 / 60, fakeInput({ right = true }))
  Harness.assertEqual(p.x, 1)
  Harness.assertEqual(p.y, 0)
  -- DOWN added while RIGHT is still held -- should keep moving right,
  -- not snap to vertical.
  p:update(1 / 60, fakeInput({ right = true, down = true }))
  Harness.assertEqual(p.x, 2, "should still be moving on the already-active horizontal axis")
  Harness.assertEqual(p.y, 0, "vertical should stay suppressed while the horizontal axis is still active")
  -- RIGHT released, DOWN still held -- NOW it should switch to vertical.
  p:update(1 / 60, fakeInput({ down = true }))
  Harness.assertEqual(p.x, 2, "x should stop advancing once the active axis's own key is released")
  Harness.assertEqual(p.y, 1, "should re-arbitrate to vertical once the horizontal key is released")
end)

Harness.test("Player:update: sticky axis -- releasing and re-pressing both freshly still gives vertical priority", function()
  local p = Player.new(0, 0)
  p:update(1 / 60, fakeInput({ right = true }))
  p:update(1 / 60, fakeInput({}))  -- everything released -- axis clears
  p:update(1 / 60, fakeInput({ right = true, up = true }))  -- fresh simultaneous press
  Harness.assertEqual(p.x, 1, "x should not have advanced on this fresh-press step")
  Harness.assertEqual(p.y, -1, "vertical should win the fresh simultaneous press, same as the un-sticky case")
end)

Harness.test("Player:update: horizontal-only input still moves/faces normally", function()
  local p = Player.new(0, 0)
  p:update(1 / 60, fakeInput({ left = true }))
  Harness.assertEqual(p.x, -1)
  Harness.assertEqual(p.facing, "left")
end)

Harness.test("Player:update: clamps to supplied bounds", function()
  local p = Player.new(0, 0)
  local bounds = { 0, 0, 152, 112 } -- 160-8 x 128-16, the room's known extent
  p:update(1 / 60, fakeInput({ left = true, up = true }), bounds)
  Harness.assertEqual(p.x, 0)
  Harness.assertEqual(p.y, 0)

  local p2 = Player.new(152, 112)
  p2:update(1 / 60, fakeInput({ right = true, down = true }), bounds)
  Harness.assertEqual(p2.x, 152)
  Harness.assertEqual(p2.y, 112)
end)
