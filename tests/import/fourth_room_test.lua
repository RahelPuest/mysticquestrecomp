local Harness = require("tests.harness")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Task #75 ("fourthRoom exit: reconcile live zone coords with static
-- grid", 2026-08-14): a dedicated live mgba session (real corridor
-- walk, both the fifthRoom and sixthRoom exit paths, real SCX/SCY
-- scroll shadows logged every step) found 10 real, previously-
-- uncaptured wall/border decoration tile IDs (136-140/143-147) that
-- only scroll into the visible screen once the corridor's own real
-- SCX genuinely moves away from 0 -- see rom_profiles.lua's own
-- `fourthRoom.exits` doc comment for the full evidence trail and the
-- real `bgRow=(Y+SCY)//8`/`bgCol=(X+SCX)//8` reconciliation formula.
--
-- `RomProfiles.match` needs a real ROM SHA-1, gated the same way as
-- every other rom_profiles.lua structural test in this project.
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "fourthRoom: the 10 newly-found real corridor tile offsets are real, in-bounds ROM addresses with genuine tile data",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    for _, id in ipairs({ 136, 137, 138, 139, 140, 143, 144, 145, 146, 147 }) do
      local off = fourth.tileOffsets[id]
      Harness.assertTrue(off ~= nil, "expected a real offset for tile " .. id)
      Harness.assertTrue(off > 0 and off < 0x80000, "tile " .. id .. " offset out of a sane ROM range: " .. tostring(off))
      local bytes = romData:sub(off + 1, off + 16)
      Harness.assertEqual(#bytes, 16, "expected a full real 16-byte GB tile pattern at tile " .. id)
      Harness.assertTrue(bytes ~= string.rep("\0", 16), "tile " .. id .. " reads as a suspicious all-zero pattern")
    end
  end
)

Harness.testIfAvailable(
  "fourthRoom: 5 of the newly-found tile offsets exactly cross-validate against sixthRoom's independently-found real offsets",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local fourth = profile.graphics.fourthRoom
    local sixth = profile.graphics.sixthRoom
    -- These 5 IDs were found by TWO separately-run live investigations
    -- (fourthRoom's own corridor-scroll trace here, and sixthRoom's own
    -- earlier "gate/pillar" tileset capture) -- landing on the exact
    -- same real ROM offset each time is strong, unplanned corroboration
    -- that neither disambiguation pick was a fluke.
    for _, id in ipairs({ 136, 137, 143, 144, 147 }) do
      Harness.assertEqual(fourth.tileOffsets[id], sixth.tileOffsets[id],
        string.format("tile %d: fourthRoom and sixthRoom should have independently found the exact same real offset", id))
    end
  end
)
