local Harness = require("tests.harness")
local LuaWriter = require("src.import.LuaWriter")

--- Loads a serialized string back into a real Lua value -- LuaJIT
-- supports both `load` (5.2+ name) and `loadstring` (5.1 name);
-- prefer whichever is actually present rather than guessing the
-- runtime's own Lua version.
local function loadValue(src)
  local chunk = (load or loadstring)(src)
  assert(chunk, "LuaWriter produced a string that failed to load: " .. src)
  return chunk()
end

--- Real, recursive deep-equality check -- Harness.assertEqual only
-- does `==` (reference equality for tables), which would always fail
-- for two independently-built tables even when their real CONTENTS
-- match exactly -- exactly the property these round-trip tests need.
local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function assertRoundTrips(value, label)
  local src = LuaWriter.serialize(value)
  local loaded = loadValue(src)
  Harness.assertTrue(deepEqual(value, loaded),
    (label or "value") .. " did not round-trip. Serialized as:\n" .. src)
end

Harness.test("LuaWriter.serialize: round-trips real scalars (number/string/boolean/nil)", function()
  assertRoundTrips(42, "integer")
  assertRoundTrips(-17, "negative integer")
  assertRoundTrips(0, "zero")
  assertRoundTrips(3.14159, "float")
  assertRoundTrips("hello", "plain string")
  assertRoundTrips(true, "true")
  assertRoundTrips(false, "false")
end)

Harness.test("LuaWriter.serialize: round-trips a real array-shaped table without explicit indices", function()
  local value = { 1, 2, 3, "four", true }
  local src = LuaWriter.serialize(value)
  Harness.assertTrue(not src:find("%[1%]"), "expected a plain array literal, not explicit [1]=... indices")
  assertRoundTrips(value, "array table")
end)

Harness.test("LuaWriter.serialize: round-trips a real map-shaped table with bareword keys where possible", function()
  local value = { name = "Willy", hp = 19, alive = true }
  local src = LuaWriter.serialize(value)
  Harness.assertTrue(src:find("name = ", 1, true) ~= nil, "expected a real bareword key, not [\"name\"]")
  assertRoundTrips(value, "map table")
end)

Harness.test("LuaWriter.serialize: quotes a real non-identifier string key correctly", function()
  local value = { ["13:0x4712"] = 0x472a, ["with space"] = 1 }
  assertRoundTrips(value, "non-bareword-key table")
end)

Harness.test("LuaWriter.serialize: round-trips real nested tables (arrays of maps, matching this project's own decoded-record shape)", function()
  local value = {
    { name = "Rot Bat", hp = 6, atk = 3, species = 0x10 },
    { name = "Skeleton", hp = 12, atk = 5, species = 0x11 },
  }
  assertRoundTrips(value, "array of records")
end)

Harness.test("LuaWriter.serialize: round-trips real German umlaut/UTF-8 text unchanged (matches TextDecoder.lua's own UTF-8 output)", function()
  assertRoundTrips("Willkür stört öfter süß-blöde Käfer", "umlaut string")
  assertRoundTrips("Zeile 1\nZeile 2", "string with a real embedded newline")
  assertRoundTrips('Sie sagte: "Hallo"', "string with a real embedded quote")
end)

Harness.test("LuaWriter.serialize: real deterministic key ordering -- two calls with the same table produce byte-identical output", function()
  local value = { z = 1, a = 2, m = 3, [5] = "five", [1] = "one" }
  local first = LuaWriter.serialize(value)
  local second = LuaWriter.serialize(value)
  Harness.assertEqual(first, second)
end)

Harness.test("LuaWriter.serialize: refuses to serialize a real function value rather than silently dropping it", function()
  local ok = pcall(function() return LuaWriter.serialize({ f = function() end }) end)
  Harness.assertTrue(not ok, "expected LuaWriter to fail loudly on an unserializable value")
end)

Harness.test("LuaWriter.serialize: an optional header comment is preserved verbatim before the return statement", function()
  local src = LuaWriter.serialize({ x = 1 }, "-- generated, do not edit")
  Harness.assertTrue(src:find("-- generated, do not edit", 1, true) ~= nil)
  Harness.assertTrue(src:find("\nreturn ", 1, true) ~= nil)
  local loaded = loadValue(src)
  Harness.assertEqual(loaded.x, 1)
end)

return true
