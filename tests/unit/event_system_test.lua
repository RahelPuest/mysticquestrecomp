local Harness = require("tests.harness")
local EventSystem = require("src.scripting.EventSystem")

Harness.test("EventSystem:update: fires an event once its trigger becomes true", function()
  local dispatched = {}
  local es = EventSystem.new({
    {
      id = "test_event",
      trigger = function(state) return state.flag == true end,
      actions = { { type = "dialogue", lines = { "hi" } } },
    },
  })
  local state = { flag = false }
  local fired = es:update(state, function(action) dispatched[#dispatched + 1] = action end)
  Harness.assertEqual(#fired, 0, "should not fire while trigger is false")
  Harness.assertEqual(#dispatched, 0)

  state.flag = true
  fired = es:update(state, function(action) dispatched[#dispatched + 1] = action end)
  Harness.assertEqual(#fired, 1)
  Harness.assertEqual(fired[1], "test_event")
  Harness.assertEqual(#dispatched, 1)
  Harness.assertEqual(dispatched[1].type, "dialogue")
end)

Harness.test("EventSystem:update: a 'once' event (the default) never fires twice", function()
  local count = 0
  local es = EventSystem.new({
    { id = "e", trigger = function() return true end, actions = { { type = "x" } } },
  })
  es:update({}, function() count = count + 1 end)
  es:update({}, function() count = count + 1 end)
  es:update({}, function() count = count + 1 end)
  Harness.assertEqual(count, 1, "once=true (the default) should only ever dispatch actions on the first fire")
end)

Harness.test("EventSystem:update: once=false events re-fire every time their trigger is true", function()
  local count = 0
  local es = EventSystem.new({
    { id = "e", trigger = function() return true end, actions = { { type = "x" } }, once = false },
  })
  es:update({}, function() count = count + 1 end)
  es:update({}, function() count = count + 1 end)
  Harness.assertEqual(count, 2, "once=false should dispatch again on every update its trigger is true")
end)

Harness.test("EventSystem:update: dispatches multiple actions for one event, in order", function()
  local seen = {}
  local es = EventSystem.new({
    {
      id = "e",
      trigger = function() return true end,
      actions = { { type = "a" }, { type = "b" }, { type = "c" } },
    },
  })
  es:update({}, function(action) seen[#seen + 1] = action.type end)
  Harness.assertEqual(seen[1], "a")
  Harness.assertEqual(seen[2], "b")
  Harness.assertEqual(seen[3], "c")
end)

Harness.test("EventSystem:hasFired: reflects a one-shot event's real fired state", function()
  local es = EventSystem.new({
    { id = "boss_defeated", trigger = function(state) return state.defeated end, actions = {} },
  })
  Harness.assertTrue(not es:hasFired("boss_defeated"))
  es:update({ defeated = true }, function() end)
  Harness.assertTrue(es:hasFired("boss_defeated"))
end)

Harness.test("EventSystem:hasFired: unknown id reports false, not an error", function()
  local es = EventSystem.new({})
  Harness.assertTrue(not es:hasFired("nonexistent"))
end)
