local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Real room found live (2026-08-13, direct user bug report: "im raum
-- nach der treppe müsste ich nach westen weiter gehen können... der
-- raum sollte weiter scrollen") -- a genuine second exit from
-- fourthRoom, reached via the SAME corridor the fifthRoom exit uses,
-- then continuing west -- see rom_profiles.lua's own `sixthRoom` doc
-- comment and events.md for the full live-trace evidence (a real SCX
-- shadow move, not a stationary wall -- an earlier flood-fill probe's
-- own 10-frame stall timeout was a real, caught false negative). This
-- room reuses fourthRoom's own real tile source (`$40B0`) -- 7 of its
-- 16 distinct tile IDs are the SAME real ROM offsets `fourthRoom`
-- already uses; the remaining 9 were newly found this pass.
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "sixthRoom: shares the willyRoom/secondRoom/thirdRoom real roomSelector family",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    Harness.assertTrue(sixth ~= nil, "expected profile.graphics.sixthRoom to exist")
    Harness.assertEqual(#sixth.romRoomSelectors, 5)
    for i, sel in ipairs(sixth.romRoomSelectors) do
      Harness.assertEqual(sel, i + 1) -- {2,3,4,5,6}
    end
  end
)

Harness.testIfAvailable(
  "sixthRoom: real tileOffsets for shared tile IDs (128-134) exactly match fourthRoom's own",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    local sixth = profile.graphics.sixthRoom
    local sharedCount = 0
    for id, offset in pairs(sixth.tileOffsets) do
      if fourth.tileOffsets[id] then
        sharedCount = sharedCount + 1
        Harness.assertEqual(offset, fourth.tileOffsets[id],
          string.format("tile %d should match fourthRoom's own real offset", id))
      end
    end
    -- UPDATED (2026-08-14, task #75 "reconcile live zone coords with
    -- static grid"): was 7 -- fourthRoom's own tileOffsets gained 7 MORE
    -- real entries this pass (136-140/143/144/147, found via a live
    -- corridor-scroll trace, see fourthRoom's own doc comment), and
    -- every one of the 5 that overlap sixthRoom's own independently-
    -- found set (136/137/143/144/147, plus 145/146 already counted
    -- before) landed on the EXACT SAME real ROM offset -- a genuine,
    -- unplanned cross-validation between two separately-run
    -- investigations, not a coincidence this project should quietly
    -- collapse back to the old count.
    Harness.assertEqual(sharedCount, 14)
  end
)

Harness.testIfAvailable(
  "sixthRoom: the 9 newly-found real tile offsets are real, in-bounds ROM addresses with genuine tile data",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    local newIds = { 136, 137, 142, 143, 144, 145, 146, 147, 150 }
    for _, id in ipairs(newIds) do
      local offset = sixth.tileOffsets[id]
      Harness.assertTrue(offset ~= nil, "expected a real offset for tile " .. id)
      Harness.assertTrue(offset >= 0 and offset + 16 <= #romData,
        "expected tile " .. id .. "'s offset to be a real, in-bounds ROM address")
      -- Real tile data is never all-zero (a real, if weak, "not garbage" sanity check).
      local allZero = true
      for i = 0, 15 do
        if romData:byte(offset + i + 1) ~= 0 then allZero = false; break end
      end
      Harness.assertTrue(not allZero, "expected tile " .. id .. "'s real bytes to be non-trivial")
    end
  end
)

Harness.testIfAvailable(
  "fourthRoom: real, live-traced second exit targets sixthRoom",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    Harness.assertTrue(fourth.exits ~= nil and #fourth.exits == 2,
      "expected fourthRoom to have exactly 2 real exits (north->fifthRoom, west->sixthRoom)")
    local exit = fourth.exits[2]
    Harness.assertEqual(exit.targetRoom, "sixthRoom")
    Harness.assertEqual(exit.transition.type, "cut")
    Harness.assertEqual(exit.landingX, 80)
    Harness.assertEqual(exit.landingY, 96)
    Harness.assertEqual(exit.holdFrames, 220)
    Harness.assertEqual(exit.holdDirection, "left")
  end
)
