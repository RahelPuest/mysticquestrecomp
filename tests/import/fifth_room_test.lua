local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Real room found live (2026-08-12, "fourthRoom systematisch
-- flutfüllen"): a genuine further exit from fourthRoom, reached via a
-- previously-uncaptured corridor and a real "cut" transition -- see
-- rom_profiles.lua's own `fifthRoom` doc comment and events.md's
-- "Correction and a real find" section for the full live-trace
-- evidence. This room reuses the willyRoom/secondRoom/thirdRoom
-- family's own real tile source (`$46B0`) -- 44 of its 48 distinct
-- tile IDs are the SAME real ROM offsets `willyRoom` already uses;
-- only 4 (`172`-`175`) were newly found this pass.
--
-- `RomProfiles.match` needs a real ROM SHA-1, so -- like every other
-- rom_profiles.lua structural test in this project -- these all need
-- a real development ROM, gated the same way as everything else here.
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "fifthRoom: shares the willyRoom/secondRoom/thirdRoom real roomSelector family",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fifth = profile.graphics.fifthRoom
    Harness.assertTrue(fifth ~= nil, "expected profile.graphics.fifthRoom to exist")
    Harness.assertEqual(#fifth.romRoomSelectors, 5)
    for i, sel in ipairs(fifth.romRoomSelectors) do
      Harness.assertEqual(sel, profile.graphics.willyRoom.romRoomSelectors[i])
    end
  end
)

Harness.testIfAvailable(
  "fifthRoom: real tileOffsets for shared tile IDs (128-171) exactly match willyRoom's own",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fifth = profile.graphics.fifthRoom
    local willy = profile.graphics.willyRoom
    local checked = 0
    for id = 128, 171 do
      if fifth.tileOffsets[id] then
        Harness.assertEqual(fifth.tileOffsets[id], willy.tileOffsets[id],
          string.format("tile %d should reuse willyRoom's real offset", id))
        checked = checked + 1
      end
    end
    Harness.assertTrue(checked >= 40, "expected most of fifthRoom's tiles to reuse willyRoom's real offsets, got " .. checked)
  end
)

Harness.testIfAvailable(
  "fifthRoom: the 4 newly-found real tile offsets (172-175) are real, in-bounds ROM addresses with genuine tile data",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fifth = profile.graphics.fifthRoom
    for id = 172, 175 do
      local off = fifth.tileOffsets[id]
      Harness.assertTrue(off ~= nil, "expected a real offset for tile " .. id)
      Harness.assertTrue(off > 0 and off < 0x80000, "tile " .. id .. " offset out of a sane ROM range: " .. tostring(off))
      -- Real, structural sanity: the real ROM bytes at this offset are
      -- a genuine, non-degenerate 16-byte GB tile pattern (not
      -- all-zero, which would be a red flag for a bogus "found by
      -- exact match" result).
      local bytes = romData:sub(off + 1, off + 16)
      Harness.assertEqual(#bytes, 16, "expected a full real 16-byte GB tile pattern at tile " .. id)
      Harness.assertTrue(bytes ~= string.rep("\0", 16), "tile " .. id .. " reads as a suspicious all-zero pattern")
    end
  end
)

Harness.testIfAvailable(
  "fourthRoom: real, live-traced exit targets fifthRoom",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    -- CORRECTED AGAIN (2026-08-14, "gamemap absolute prio"): fourthRoom
    -- briefly had a real SECOND exit recorded here (west, into
    -- sixthRoom, 2026-08-13) -- RETRACTED this pass, see sixth_room_test
    -- .lua's own "RETRACTED" test and rom_profiles.lua's doc comments
    -- for the full evidence trail (it was never a real cut). Still
    -- asserting `>= 1` rather than an exact count, same reasoning as
    -- before -- this test only cares about the FIRST (north, fifthRoom)
    -- exit either way.
    Harness.assertTrue(fourth.exits ~= nil and #fourth.exits >= 1, "expected fourthRoom to have at least 1 real exit")
    local exit = fourth.exits[1]
    Harness.assertEqual(exit.targetRoom, "fifthRoom")
    Harness.assertEqual(exit.transition.type, "cut")
    Harness.assertEqual(exit.landingX, 136)
    Harness.assertEqual(exit.landingY, 32)
    -- Real ROM hold-to-trigger delay (2026-08-13, "fourthRoom-
    -- >fifthRoom-Lücken schließen"), confirmed live frame-by-frame:
    -- ~64 real frames holding DOWN against the wall before the cut
    -- fires, not the instant the zone is entered.
    Harness.assertEqual(exit.holdFrames, 64)
    Harness.assertEqual(exit.holdDirection, "down")
  end
)
