local Harness = require("tests.harness")
local HoldTrigger = require("src.entities.HoldTrigger")

Harness.test("HoldTrigger.step: fires exactly once holdFrames consecutive matched steps have happened", function()
  local state = { frames = 0 }
  local fired = nil
  for i = 1, 64 do
    fired = HoldTrigger.step(state, true, 64)
    if i < 64 then
      Harness.assertTrue(not fired, "should not fire before reaching holdFrames (step " .. i .. ")")
    end
  end
  Harness.assertTrue(fired, "should fire exactly on the 64th consecutive matched step")
end)

Harness.test("HoldTrigger.step: resets to 0 the instant matched goes false, not an accumulating total", function()
  local state = { frames = 0 }
  for _ = 1, 40 do
    HoldTrigger.step(state, true, 64)
  end
  Harness.assertEqual(state.frames, 40)

  HoldTrigger.step(state, false, 64) -- released early
  Harness.assertEqual(state.frames, 0)

  -- Re-holding needs the FULL 64 again, not just the remaining 24.
  local fired = false
  for i = 1, 63 do
    fired = HoldTrigger.step(state, true, 64)
  end
  Harness.assertTrue(not fired, "63 steps after a reset should not be enough")
end)

Harness.test("HoldTrigger.step: after firing, resets so a second real trigger needs the full hold again", function()
  local state = { frames = 0 }
  for _ = 1, 64 do
    HoldTrigger.step(state, true, 64)
  end
  Harness.assertEqual(state.frames, 0)

  local fired = HoldTrigger.step(state, true, 64)
  Harness.assertTrue(not fired, "the very next step alone should not immediately re-fire")
end)

Harness.test("HoldTrigger.step: never fires for holdFrames=1 until the very first matched step", function()
  local state = { frames = 0 }
  Harness.assertTrue(HoldTrigger.step(state, true, 1))
end)
