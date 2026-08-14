-- Minimal headless test harness. No love.* dependency at all -- every
-- module under tests/unit and tests/import is pure Lua, so plain `luajit`
-- runs the whole suite with no stub needed (contrast gen1recomp's
-- love_stub.lua, which exists because its modules DO touch love.filesystem/
-- love.data directly; ours don't, by design -- see docs/architecture.md).

local Harness = {}
Harness.tests = {}
Harness.skipped = {}

function Harness.test(name, fn)
  Harness.tests[#Harness.tests + 1] = { name = name, fn = fn }
end

--- Register a test that only runs if `available` is true; otherwise it is
-- recorded as skipped with `reason`. Used for ROM-dependent tests so the
-- suite passes cleanly with no development ROM present (per the project
-- rule: never require a copyrighted ROM to be checked into source control
-- or to be present for the suite to pass).
function Harness.testIfAvailable(name, available, reason, fn)
  if available then
    Harness.test(name, fn)
  else
    Harness.skipped[#Harness.skipped + 1] = { name = name, reason = reason }
  end
end

local function fmt(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function Harness.assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s",
      message or "assertEqual", fmt(expected), fmt(actual)), 2)
  end
end

function Harness.assertTrue(value, message)
  if not value then
    error(message or "expected truthy value, got " .. fmt(value), 2)
  end
end

function Harness.run()
  local passed, failed = 0, 0
  for _, t in ipairs(Harness.tests) do
    local ok, err = pcall(t.fn)
    if ok then
      passed = passed + 1
      print("  PASS  " .. t.name)
    else
      failed = failed + 1
      print("  FAIL  " .. t.name)
      print("        " .. tostring(err))
    end
  end
  for _, s in ipairs(Harness.skipped) do
    print("  SKIP  " .. s.name .. "  (" .. s.reason .. ")")
  end
  print(string.format("\n%d passed, %d failed, %d skipped",
    passed, failed, #Harness.skipped))
  return failed == 0
end

return Harness
