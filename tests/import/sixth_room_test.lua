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

-- CORRECTED (2026-08-17, direct user claim "und der sixth raum muss
-- ganz klar der startraum sein. das habe ich 1000 mal im rom
-- beobachtet" -- confirmed correct via a live WRAM register trace,
-- see rom_profiles.lua's own dated retraction on `sixthRoom` for the
-- full evidence): this test used to assert the WRONG family
-- (`{2,3,4,5,6}`, the willyRoom/secondRoom/thirdRoom group) even
-- though this same file's own top-of-file doc comment already said
-- `sixthRoom` reuses `fourthRoom`'s own real tile source (`$40B0`) --
-- an internal inconsistency nobody had cross-checked live before now.
-- The real, live-confirmed family is `startRoom`/`fourthRoom` (`{0,1}`,
-- roomSelector 1 specifically).
Harness.testIfAvailable(
  "sixthRoom: shares the startRoom/fourthRoom real roomSelector family, not willyRoom's",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    Harness.assertTrue(sixth ~= nil, "expected profile.graphics.sixthRoom to exist")
    Harness.assertEqual(#sixth.romRoomSelectors, 2)
    for i, sel in ipairs(sixth.romRoomSelectors) do
      Harness.assertEqual(sel, i - 1) -- {0,1}
    end
    Harness.assertEqual(sixth.romRoomSelectorConfirmed, 1)
    Harness.assertTrue(sixth.sameRomIdentityAs ~= nil, "expected a real sameRomIdentityAs cross-reference")
    Harness.assertEqual(sixth.sameRomIdentityAs[1], "startRoom")
    Harness.assertEqual(sixth.sameRomIdentityAs[2], "fourthRoom")
  end
)

-- RETIRED (2026-08-17, see rom_profiles.lua's own capture-bug
-- retraction on `sixthRoom.grid`/`tileOffsets`/`floorTileIds` for the
-- full evidence): the 2 tests that used to sit here ("real tileOffsets
-- for shared tile IDs (128-134) exactly match fourthRoom's own" and
-- "the 9 newly-found real tile offsets...") asserted properties of a
-- `sixthRoom.tileOffsets` table that turned out to be a real, caught
-- capture bug -- a raw VRAM read that never corrected for the room's
-- own nonzero hardware SCX, producing a "half brick corridor, half
-- courtyard" tile arrangement that never appears on real hardware.
-- Replaced below with a test of the REAL fix: `sixthRoom` now reuses
-- `startRoom`'s own already-correct `grid`/`tileOffsets`/
-- `floorTileIds` directly (a real Lua table reference, not a
-- duplicate), since a live WRAM register trace (`$D392`/`$D393`/
-- `$C3F0`/`$C3F5`, see the test above) confirmed they're the same real
-- ROM room.
Harness.testIfAvailable(
  "sixthRoom: render data (grid/tileOffsets/floorTileIds) is startRoom's own, not a separate (buggy) capture",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local start = profile.graphics.startRoom
    local sixth = profile.graphics.sixthRoom
    Harness.assertTrue(sixth.grid == start.grid,
      "expected sixthRoom.grid to be the exact same real table as startRoom.grid")
    Harness.assertTrue(sixth.tileOffsets == start.tileOffsets,
      "expected sixthRoom.tileOffsets to be the exact same real table as startRoom.tileOffsets")
    Harness.assertTrue(sixth.floorTileIds == start.floorTileIds,
      "expected sixthRoom.floorTileIds to be the exact same real table as startRoom.floorTileIds")
  end
)

Harness.testIfAvailable(
  "fourthRoom: RE-ADDED -- the west exit into sixthRoom is back, as an honest engineering choice (2026-08-15)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- History: this test used to assert `#fourth.exits == 1` after the
    -- 2026-08-14 retraction (see the RETRACTED evidence trail this test
    -- used to carry, now moved to rom_profiles.lua's own "RETRACTED-
    -- THEN-RECONSIDERED" doc comment on this exact exit). The underlying
    -- ROM finding is UNCHANGED: the real corridor genuinely just keeps
    -- scrolling as one continuous canvas, it never "cuts" here. What
    -- changed 2026-08-15 (direct user bug report: "dann sollte wenn der
    -- spieler dem weg nach westen folgt eun neuer raum da sein... bau
    -- das ein") is that this project's own no-camera-scroll engine has
    -- no other way to expose `sixthRoom`'s real, already-decoded tile
    -- content, so the exit is back as a deliberate, honestly-labeled
    -- stand-in -- see rom_profiles.lua's own doc comment for the full
    -- reasoning.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    Harness.assertTrue(fourth.exits ~= nil and #fourth.exits == 2,
      "expected fourthRoom to have 2 exits again (north->fifthRoom, west->sixthRoom)")
    local west
    for _, exit in ipairs(fourth.exits) do
      if exit.targetRoom == "sixthRoom" then west = exit end
    end
    Harness.assertTrue(west ~= nil, "expected a real exit targeting sixthRoom")
    Harness.assertEqual(west.holdFrames, 220)
    Harness.assertEqual(west.holdDirection, "left")
  end
)

Harness.testIfAvailable(
  "sixthRoom: hosts the second-boss encounter (moved here 2026-08-15, see doc comment for the correction history)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local sixth = profile.graphics.sixthRoom
    Harness.assertTrue(sixth.secondBoss ~= nil, "expected sixthRoom.secondBoss to exist")
    Harness.assertTrue(sixth.floorTileIds[sixth.grid[math.floor(sixth.secondBoss.spawnY / 8) + 1][math.floor(sixth.secondBoss.spawnX / 8) + 1]],
      "expected secondBoss's own spawn position to sit on real floor")
  end
)
