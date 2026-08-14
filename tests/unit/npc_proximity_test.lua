local Harness = require("tests.harness")
local NpcProximity = require("src.entities.NpcProximity")

local function notShown() return false end
local function alwaysShown() return true end

Harness.test("NpcProximity.match: nil sceneData or nil player returns nil, not an error", function()
  Harness.assertEqual(NpcProximity.match(nil, nil, { x = 0, y = 0, width = 16, height = 16 }, notShown), nil)
  Harness.assertEqual(NpcProximity.match({ a = { dialogue = {"hi"}, screenX = 0, screenY = 0 } }, nil, nil, notShown), nil)
end)

Harness.test("NpcProximity.match: a character with no dialogue field never matches", function()
  local sceneData = { characterB = { screenX = 80, screenY = 58 } } -- no .dialogue, real honest gap
  local player = { x = 80, y = 58, width = 16, height = 16 }
  Harness.assertEqual(NpcProximity.match(sceneData, nil, player, notShown), nil)
end)

Harness.test("NpcProximity.match: an already-shown character is skipped (real one-shot behavior)", function()
  local sceneData = { characterA = { dialogue = { "hi" }, screenX = 80, screenY = 58 } }
  local player = { x = 80, y = 58, width = 16, height = 16 }
  Harness.assertEqual(NpcProximity.match(sceneData, nil, player, alwaysShown), nil)
end)

Harness.test("NpcProximity.match: overlapping the static screenX/screenY position matches", function()
  local sceneData = { characterA = { dialogue = { "Der Monstereingang..." }, screenX = 80, screenY = 58 } }
  local player = { x = 80, y = 58, width = 16, height = 16 }
  local lines, name = NpcProximity.match(sceneData, nil, player, notShown)
  Harness.assertEqual(name, "characterA")
  Harness.assertEqual(lines[1], "Der Monstereingang...")
end)

Harness.test("NpcProximity.match: far away (well outside the pad) does not match", function()
  local sceneData = { characterA = { dialogue = { "hi" }, screenX = 80, screenY = 58 } }
  local player = { x = 0, y = 0, width = 16, height = 16 }
  Harness.assertEqual(NpcProximity.match(sceneData, nil, player, notShown), nil)
end)

Harness.test("NpcProximity.match: real regression -- 900 real frames of zero movement must never match a room-entry-only spawn point far from the player", function()
  -- Direct reproduction of the real live-trace finding (see
  -- rom_profiles.lua's secondRoom.scene doc comment): the player's real
  -- landing spot (72,96) is nowhere near either NPC's own spawn sample
  -- (128,58 / 80,58) -- confirms idling at the landing spot alone can't
  -- accidentally satisfy this proximity check, matching the real
  -- disproof of the old room-entry-triggered mechanism.
  local sceneData = {
    characterA = { dialogue = { "hi" }, screenX = 128, screenY = 58 },
  }
  local player = { x = 72, y = 96, width = 16, height = 16 }
  Harness.assertEqual(NpcProximity.match(sceneData, nil, player, notShown), nil)
end)

Harness.test("NpcProximity.match: uses the LIVE wander position over the static spawn sample when given", function()
  -- Direct reproduction of the 2026-08-10 wander-movement fix: once an
  -- NPC actually walks, the static screenX/screenY (its one-time spawn
  -- sample) is stale -- the live position must be consulted instead.
  local sceneData = { characterA = { dialogue = { "hi" }, screenX = 128, screenY = 58 } }
  local livePositions = { characterA = { x = 40, y = 40 } }
  local playerAtSpawn = { x = 128, y = 58, width = 16, height = 16 }
  local playerAtLive = { x = 40, y = 40, width = 16, height = 16 }
  Harness.assertEqual(NpcProximity.match(sceneData, livePositions, playerAtSpawn, notShown), nil)
  local lines = NpcProximity.match(sceneData, livePositions, playerAtLive, notShown)
  Harness.assertTrue(lines ~= nil, "should match at the live wandered position instead")
end)

Harness.test("NpcProximity.match: custom pad widens or narrows the trigger box", function()
  local sceneData = { characterA = { dialogue = { "hi" }, screenX = 100, screenY = 100 } }
  local playerJustOutsideDefaultPad = { x = 130, y = 100, width = 16, height = 16 } -- 14px right of the 16px box + 8px pad edge
  Harness.assertEqual(NpcProximity.match(sceneData, nil, playerJustOutsideDefaultPad, notShown, 8), nil)
  local lines = NpcProximity.match(sceneData, nil, playerJustOutsideDefaultPad, notShown, 20)
  Harness.assertTrue(lines ~= nil, "a wider pad should reach the same player position")
end)
