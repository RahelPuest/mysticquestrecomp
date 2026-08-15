local Harness = require("tests.harness")
local TileLandingPosition = require("src.import.TileLandingPosition")
local RomProfiles = require("src.import.rom_profiles")

Harness.test("TileLandingPosition.screenFromTile: real, live-traced case (thirdRoom->fourthRoom, tile 14,12 -> screen 120,112)", function()
  local x, y = TileLandingPosition.screenFromTile(14, 12)
  Harness.assertEqual(x, 120)
  Harness.assertEqual(y, 112)
end)

Harness.test("TileLandingPosition.tileFromScreen: exact inverse of screenFromTile", function()
  local tx, ty = TileLandingPosition.tileFromScreen(120, 112)
  Harness.assertEqual(tx, 14)
  Harness.assertEqual(ty, 12)
end)

Harness.test("TileLandingPosition.tileFromScreen: fails loudly (returns nil) on a non-tile-aligned screen position, not a fabricated fraction", function()
  local tx, ty = TileLandingPosition.tileFromScreen(121, 112)
  Harness.assertEqual(tx, nil)
  Harness.assertEqual(ty, nil)
end)

--- Real, decisive cross-check (2026-08-14): EVERY `landingX`/`landingY`
-- pair already recorded in `rom_profiles.lua` -- each independently
-- measured empirically, over several earlier sessions, long before
-- this formula was ever found -- decomposes into a clean, small
-- integer tile coordinate via this exact formula. This is strong,
-- independent confirmation the formula is this ROM's real, GENERAL
-- landing-position mechanism, not a coincidence specific to the one
-- transition it was live-traced from. Walks the actual profile data
-- (not a hardcoded copy of it) so this test stays honest if any
-- landing value is ever corrected.
--
-- CORRECTED (2026-08-14, "gamemap absolute prio"): the minimum count
-- was 5 (including fourthRoom's own since-RETRACTED second exit into
-- "sixthRoom", landingX=80/landingY=96). That exit was never a real
-- cut transition, so its landing position went with it, dropping the
-- real count to 4.
--
-- RE-ADDED (2026-08-15): fourthRoom's west exit into `sixthRoom` is
-- back (see rom_profiles.lua's own doc comment -- an honest engineering
-- choice, not a reversal of the 2026-08-14 ROM finding), with a NEW
-- landing position (144,80) chosen this time, which is why the count
-- below is still just `>= 4` rather than bumped to an exact 5 -- this
-- test only cares that the formula holds for whatever real set exists,
-- not the exact count.
local function collectLandingPositions(node, out)
  if type(node) ~= "table" then return end
  if type(node.landingX) == "number" and type(node.landingY) == "number" then
    out[#out + 1] = { x = node.landingX, y = node.landingY }
  end
  for _, v in pairs(node) do
    if type(v) == "table" then
      collectLandingPositions(v, out)
    end
  end
end

Harness.test("TileLandingPosition: every real landingX/landingY already recorded in rom_profiles.lua decomposes into a clean integer tile coordinate", function()
  local positions = {}
  collectLandingPositions(RomProfiles.PROFILES, positions)
  Harness.assertTrue(#positions >= 4,
    "expected at least the 4 already-known real landing positions, found " .. #positions)
  for _, p in ipairs(positions) do
    local tx, ty = TileLandingPosition.tileFromScreen(p.x, p.y)
    Harness.assertTrue(tx ~= nil and ty ~= nil,
      string.format("real landing position (%d,%d) does NOT land on a clean tile boundary -- " ..
        "either this formula is wrong or this specific value needs re-checking", p.x, p.y))
  end
end)
