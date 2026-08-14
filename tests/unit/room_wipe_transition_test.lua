local Harness = require("tests.harness")
local RoomWipeTransition = require("src.entities.RoomWipeTransition")

Harness.test("RoomWipeTransition.visibleBand: closing starts fully open (frame 0 = full height, centered)", function()
  local top, height = RoomWipeTransition.visibleBand("closing", 0, 20, 128)
  Harness.assertEqual(top, 0)
  Harness.assertEqual(height, 128)
end)

Harness.test("RoomWipeTransition.visibleBand: closing ends fully closed (zero height, centered)", function()
  local top, height = RoomWipeTransition.visibleBand("closing", 20, 20, 128)
  Harness.assertEqual(height, 0)
  Harness.assertEqual(top, 64) -- centered: (128-0)/2
end)

Harness.test("RoomWipeTransition.visibleBand: closing midpoint is a real, symmetric half-height band", function()
  local top, height = RoomWipeTransition.visibleBand("closing", 10, 20, 128)
  Harness.assertEqual(height, 64)
  Harness.assertEqual(top, 32) -- (128-64)/2, symmetric top+bottom convergence
end)

Harness.test("RoomWipeTransition.visibleBand: opening is the exact mirror of closing", function()
  local closeTop, closeHeight = RoomWipeTransition.visibleBand("closing", 5, 20, 128)
  local openTop, openHeight = RoomWipeTransition.visibleBand("opening", 20 - 5, 20, 128)
  Harness.assertEqual(closeTop, openTop)
  Harness.assertEqual(closeHeight, openHeight)
end)

Harness.test("RoomWipeTransition.visibleBand: opening starts closed and ends fully open", function()
  local topStart, heightStart = RoomWipeTransition.visibleBand("opening", 0, 20, 128)
  Harness.assertEqual(heightStart, 0)
  local topEnd, heightEnd = RoomWipeTransition.visibleBand("opening", 20, 20, 128)
  Harness.assertEqual(heightEnd, 128)
  Harness.assertEqual(topEnd, 0)
  Harness.assertTrue(topStart == 64)
end)

Harness.test("RoomWipeTransition.visibleBand: clamps an out-of-range frame instead of extrapolating", function()
  local top, height = RoomWipeTransition.visibleBand("closing", 999, 20, 128)
  Harness.assertEqual(height, 0)
  Harness.assertEqual(top, 64)
end)

Harness.test("RoomWipeTransition.visibleBand: fails loudly on an invalid phase string", function()
  local ok = pcall(RoomWipeTransition.visibleBand, "sideways", 0, 20, 128)
  Harness.assertTrue(not ok)
end)

Harness.test("RoomWipeTransition.visibleBand: converges toward an explicit centerY, not always the room's geometric middle", function()
  -- Real, live-confirmed behavior (see this module's own doc comment):
  -- the real ROM wipe converges toward wherever the exit/player
  -- actually is, not the room's own vertical center. centerY=80 (far
  -- enough from either edge that the 64px-tall band isn't clamped)
  -- should center exactly there, not at the room's own middle (64).
  local top, height = RoomWipeTransition.visibleBand("closing", 10, 20, 128, 80)
  Harness.assertEqual(height, 64)
  Harness.assertEqual(top, 48) -- 80 - 64/2
end)

Harness.test("RoomWipeTransition.visibleBand: clamps the band inside [0, fullHeight] when centerY sits near an edge", function()
  -- centerY=24 with a 64px-tall band would naively start at 24-32=-8 --
  -- clamped to 0 instead of drawing outside the real room area.
  local top, height = RoomWipeTransition.visibleBand("closing", 10, 20, 128, 24)
  Harness.assertEqual(top, 0)
  Harness.assertEqual(height, 64)
end)

Harness.test("RoomWipeTransition.visibleBand: omitting centerY still defaults to the room's own geometric middle", function()
  local withDefault = { RoomWipeTransition.visibleBand("closing", 10, 20, 128) }
  local withExplicitCenter = { RoomWipeTransition.visibleBand("closing", 10, 20, 128, 64) }
  Harness.assertEqual(withDefault[1], withExplicitCenter[1])
  Harness.assertEqual(withDefault[2], withExplicitCenter[2])
end)
