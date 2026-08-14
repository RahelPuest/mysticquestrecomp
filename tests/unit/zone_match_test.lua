local Harness = require("tests.harness")
local ZoneMatch = require("src.entities.ZoneMatch")

Harness.test("ZoneMatch.contains: an unbounded side always passes", function()
  Harness.assertTrue(ZoneMatch.contains({ yMin = 60, yMax = 68 }, -9999, 64),
    "no xMin/xMax should mean unbounded on x")
  Harness.assertTrue(ZoneMatch.contains({ yMin = 60, yMax = 68 }, 9999, 64),
    "no xMin/xMax should mean unbounded on x")
end)

Harness.test("ZoneMatch.contains: real regression -- a zone missing xMin matches ANY x", function()
  -- Direct reproduction of the same-day secondRoom east-exit bug (see
  -- rom_profiles.lua's own dated doc comment on that exit): a zone with
  -- only yMin/yMax let the player fire the transition from clear across
  -- the room, nowhere near the real east wall.
  local zone = { yMin = 60, yMax = 68 }
  Harness.assertTrue(ZoneMatch.contains(zone, 72, 64), "the door's own landing x, wrongly inside the zone")
end)

Harness.test("ZoneMatch.contains: all four bounds enforced together", function()
  local zone = { xMin = 110, xMax = 140, yMin = 60, yMax = 68 }
  Harness.assertTrue(ZoneMatch.contains(zone, 120, 64))
  Harness.assertTrue(not ZoneMatch.contains(zone, 100, 64), "x below xMin")
  Harness.assertTrue(not ZoneMatch.contains(zone, 150, 64), "x above xMax")
  Harness.assertTrue(not ZoneMatch.contains(zone, 120, 50), "y below yMin")
  Harness.assertTrue(not ZoneMatch.contains(zone, 120, 80), "y above yMax")
end)

Harness.test("ZoneMatch.contains: boundary values are inclusive", function()
  local zone = { xMin = 110, xMax = 140, yMin = 60, yMax = 68 }
  Harness.assertTrue(ZoneMatch.contains(zone, 110, 60), "xMin/yMin themselves should match")
  Harness.assertTrue(ZoneMatch.contains(zone, 140, 68), "xMax/yMax themselves should match")
end)

Harness.test("ZoneMatch.first: nil list returns nil, not an error", function()
  Harness.assertEqual(ZoneMatch.first(nil, 10, 10), nil)
end)

Harness.test("ZoneMatch.first: returns the first matching entry, ignoring later ones", function()
  local list = {
    { zone = { xMin = 0, xMax = 10 }, id = "a" },
    { zone = { xMin = 0, xMax = 100 }, id = "b" },
  }
  local match = ZoneMatch.first(list, 5, 0)
  Harness.assertEqual(match.id, "a")
end)

Harness.test("ZoneMatch.first: skips non-matching entries to find a later match", function()
  local list = {
    { zone = { xMin = 200, xMax = 300 }, id = "far" },
    { zone = { xMin = 0, xMax = 100 }, id = "near" },
  }
  local match = ZoneMatch.first(list, 5, 0)
  Harness.assertEqual(match.id, "near")
end)

Harness.test("ZoneMatch.first: no match returns nil", function()
  local list = { { zone = { xMin = 200 }, id = "far" } }
  Harness.assertEqual(ZoneMatch.first(list, 5, 0), nil)
end)
