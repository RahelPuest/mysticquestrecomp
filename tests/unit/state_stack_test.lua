local Harness = require("tests.harness")
local StateStack = require("src.core.StateStack")

-- Clears a log table IN PLACE. `log = {}` would rebind the local to a new
-- table while every closure captured by makeState() below still points at
-- the original one -- so clear the existing table instead of replacing it.
local function clear(t)
  for k in pairs(t) do t[k] = nil end
end

local function makeState(log, name, opts)
  opts = opts or {}
  local s = { opaque = opts.opaque }
  s.enter = function(_, ...) log[#log + 1] = name .. ":enter(" .. table.concat({...}, ",") .. ")" end
  s.exit = function() log[#log + 1] = name .. ":exit" end
  s.pause = function() log[#log + 1] = name .. ":pause" end
  s.resume = function() log[#log + 1] = name .. ":resume" end
  s.update = function(_, dt) log[#log + 1] = name .. ":update(" .. dt .. ")" end
  s.draw = function() log[#log + 1] = name .. ":draw" end
  return s
end

Harness.test("StateStack: push calls enter, only top updates/draws", function()
  local log = {}
  local stack = StateStack.new()
  local a = makeState(log, "a")
  stack:push(a, "hello")
  Harness.assertEqual(log[1], "a:enter(hello)")
  stack:update(0.5)
  stack:draw()
  Harness.assertEqual(log[2], "a:update(0.5)")
  Harness.assertEqual(log[3], "a:draw")
end)

Harness.test("StateStack: pushing a second state pauses the first", function()
  local log = {}
  local stack = StateStack.new()
  local a = makeState(log, "a")
  stack:push(a)
  stack:push(makeState(log, "b"))
  Harness.assertEqual(log[2], "a:pause")
  Harness.assertEqual(log[3], "b:enter()")
  Harness.assertTrue(stack:top() ~= a, "top should now be b, not a")
end)

Harness.test("StateStack: pop exits the top state and resumes the one below", function()
  local log = {}
  local stack = StateStack.new()
  stack:push(makeState(log, "a"))
  local b = makeState(log, "b")
  stack:push(b)
  clear(log) -- isolate the pop from the earlier push log lines
  local popped = stack:pop()
  Harness.assertTrue(popped == b, "pop should return the state that was on top")
  Harness.assertEqual(log[1], "b:exit")
  Harness.assertEqual(log[2], "a:resume")
  Harness.assertTrue(stack:top() ~= nil and stack:top() ~= b)
end)

Harness.test("StateStack: draw skips states below the topmost opaque one", function()
  local log = {}
  local stack = StateStack.new()
  stack:push(makeState(log, "bg", { opaque = true }))
  stack:push(makeState(log, "hud", { opaque = false })) -- e.g. a translucent overlay
  clear(log)
  stack:draw()
  -- Both should draw: hud is translucent, so the opaque state beneath it
  -- (bg) is still the "topmost opaque" and drawing starts there.
  Harness.assertEqual(log[1], "bg:draw")
  Harness.assertEqual(log[2], "hud:draw")
end)

Harness.test("StateStack: draw starts at the topmost opaque state, skipping what's under it", function()
  local log = {}
  local stack = StateStack.new()
  stack:push(makeState(log, "bg", { opaque = true }))
  stack:push(makeState(log, "menu", { opaque = true })) -- fully covers bg
  clear(log)
  stack:draw()
  Harness.assertEqual(#log, 1, "only the topmost opaque state should draw")
  Harness.assertEqual(log[1], "menu:draw")
end)

Harness.test("StateStack: replace clears the whole stack first", function()
  local log = {}
  local stack = StateStack.new()
  stack:push(makeState(log, "a"))
  stack:push(makeState(log, "b"))
  clear(log)
  stack:replace(makeState(log, "c"))
  Harness.assertEqual(log[1], "b:exit")
  Harness.assertEqual(log[2], "a:exit")
  Harness.assertEqual(log[3], "c:enter()")
  Harness.assertEqual(#stack.stack, 1)
end)
