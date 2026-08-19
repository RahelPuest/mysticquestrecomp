local Harness = require("tests.harness")
local MapTileCatalog = require("src.import.MapTileCatalog")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("MapTileCatalog.build: fails loudly without a profile", function()
  Harness.assertTrue(not pcall(MapTileCatalog.build, nil))
end)

Harness.test("MapTileCatalog.build: an empty profile yields an empty catalog, not an error", function()
  local catalog = MapTileCatalog.build({ graphics = {} })
  Harness.assertEqual(#catalog.entries, 0)
  Harness.assertEqual(catalog.roomCount, 0)
end)

Harness.test("MapTileCatalog.build: dedupes a real offset shared by 2 synthetic rooms into one entry with both room names", function()
  local profile = {
    graphics = {
      roomA = { grid = { { 1 } }, tileOffsets = { [1] = 0x30000, [2] = 0x30010 } },
      roomB = { grid = { { 1 } }, tileOffsets = { [1] = 0x30000, [2] = 0x30020 } },
      -- Not a real room (no .grid) -- must be skipped, same filter
      -- export_data.lua's own ROOM_MAPS section uses.
      notARoom = { tileOffsets = { [1] = 0x99999 } },
    },
  }
  local catalog = MapTileCatalog.build(profile)
  Harness.assertEqual(catalog.roomCount, 2)
  Harness.assertEqual(#catalog.entries, 3) -- 0x30000 (shared), 0x30010, 0x30020

  local byOffset = {}
  for _, e in ipairs(catalog.entries) do byOffset[e.fileOffset] = e end

  Harness.assertEqual(#byOffset[0x30000].rooms, 2)
  Harness.assertEqual(byOffset[0x30000].rooms[1], "roomA")
  Harness.assertEqual(byOffset[0x30000].rooms[2], "roomB")
  Harness.assertEqual(byOffset[0x30000].bank, 12)
  Harness.assertEqual(#byOffset[0x30010].rooms, 1)
  Harness.assertEqual(byOffset[0x30010].rooms[1], "roomA")
end)

Harness.test("MapTileCatalog.build: skips literal (non-ROM-address) tile patterns, same exception as export_data.lua's ROOM_MAPS", function()
  local profile = {
    graphics = {
      roomA = { grid = { { 1 } }, tileOffsets = { [1] = string.rep("\255", 16), [2] = 0x30000 } },
    },
  }
  local catalog = MapTileCatalog.build(profile)
  Harness.assertEqual(#catalog.entries, 1)
  Harness.assertEqual(catalog.entries[1].fileOffset, 0x30000)
end)

Harness.test("MapTileCatalog.forBank: returns only that bank's sorted offsets", function()
  local profile = {
    graphics = {
      roomA = { grid = { { 1 } }, tileOffsets = { [1] = 0x30010, [2] = 0x20000, [3] = 0x30000 } },
    },
  }
  local catalog = MapTileCatalog.build(profile)
  local bank12 = MapTileCatalog.forBank(catalog, 12)
  Harness.assertEqual(#bank12, 2)
  Harness.assertEqual(bank12[1], 0x30000)
  Harness.assertEqual(bank12[2], 0x30010)
  local bank8 = MapTileCatalog.forBank(catalog, 8)
  Harness.assertEqual(#bank8, 1)
  Harness.assertEqual(bank8[1], 0x20000)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "MapTileCatalog.build: real ROM profile matches this project's own known 17-room / 266-tile / 3-bank finding",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local catalog = MapTileCatalog.build(profile)

    -- Same "real, decoded room" filter export_data.lua's own ROOM_MAPS
    -- section uses -- this count must always match ROOM_MAPS.length.
    -- UPDATED (2026-08-16, seventhRoom added -- sixthRoom's own new
    -- north exit): 14->15 rooms, 243->256 distinct tile entries (13 of
    -- seventhRoom's own 20 real tileOffsets are genuinely NEW ROM
    -- addresses; the other 7 already existed in the catalog, real
    -- shared-tileset reuse, same shape as the existing roomA/roomB
    -- shared-offset test case above).
    -- UPDATED AGAIN (2026-08-16, same day, self-corrected chain: a
    -- first eighthRoom/ninthRoom attempt (records 219/203, reusing
    -- already-catalogued offsets) was RETRACTED after live testing
    -- found its own exit zone unreachable -- see rom_profiles.lua's
    -- own doc comment on seventhRoom.exits for the full story. The
    -- REAL, corrected chain (records 236/237) introduces genuinely new
    -- real tile addresses: 15->17 rooms, 256->266 distinct entries,
    -- bank 12 143->153.
    -- CORRECTED AGAIN (2026-08-17, real capture-bug fix, direct user
    -- report "raum 7 8 und 9 haben die falschen tilesets" then "bleib
    -- dran" -- see rom_profiles.lua's own `mapTable.tilesetFileOffset`
    -- dated correction for the full disassembly/formula trace):
    -- seventhRoom/eighthRoom/ninthRoom's own `tileOffsets` moved from
    -- the wrong `0x32xxx` base (willyRoom's own real pixel pool,
    -- accidentally reused) to the correct `0x30xxx` base (their own
    -- real family's pool) -- 266->303 distinct entries. This is an
    -- INCREASE, not a decrease: the old, wrong `0x32xxx` values
    -- happened to coincidentally OVERLAP with willyRoom's own already-
    -- catalogued tiles (both used the same wrong pool), so many
    -- entries were being silently de-duplicated; the corrected,
    -- distinct `0x30xxx` pool no longer overlaps, so the true count of
    -- genuinely separate real tiles is now visible. roomCount (17)
    -- and bank 8/11 counts are unaffected (only bank 12's own count
    -- moved, matching where both the old and new pools both live).
    -- CORRECTED AGAIN (2026-08-17, same day, direct follow-up: "und ja
    -- nach dem zweiten boss... kommt er auf der kleinen weltmap an 6.3
    -- raus"): seventhRoom's own tileOffsets were replaced wholesale
    -- (bank5 record 220's engineering-choice pick -> real bank6 record
    -- 51, see rom_profiles.lua's own dated doc comment) -- 36 distinct
    -- real tile addresses now instead of the old 20, but with more
    -- overlap against tiles fourthRoom/startRoom/eighthRoom/ninthRoom
    -- already contributed (the new room shares the wall/border family
    -- almost exactly with fourthRoom, see that room's own doc comment)
    -- -- net count went DOWN slightly (303->300), all in bank 12.
    -- UPDATED AGAIN (2026-08-19, same day as the unknownRoomA add-then-
    -- retract: `worldMapRoom_131`/`worldMapRoom_132` added, real bank5
    -- catalog records 131/132, see rom_profiles.lua's own doc comment
    -- on `WORLD_MAP_ROOM_131_GRID`) -- 17->19 rooms, 300->313 distinct
    -- entries, all new tiles in bank 12 (file 0x30xxx, same pool
    -- seventhRoom/eighthRoom/ninthRoom already use -- real, honest tile
    -- reuse across several of the 39 tile IDs these 2 rooms share).
    Harness.assertEqual(catalog.roomCount, 19)
    Harness.assertEqual(#catalog.entries, 313)

    -- Real map/environment tiles live in exactly 3 banks (8, 11, 12) --
    -- NOT just bank 12, the honest finding this whole module exists to
    -- surface (see this module's own doc comment for the full story).
    -- worldMapRoom_131/132's own tiles are all bank 12 -- only that
    -- bank's count moved with the 2026-08-19 addition.
    Harness.assertEqual(catalog.byBank[8], 28)
    Harness.assertEqual(catalog.byBank[11], 85)
    Harness.assertEqual(catalog.byBank[12], 200)

    -- Every entry's own fileOffset must be inside the real ROM and
    -- tile-aligned (16-byte stride) -- same non-fabrication check every
    -- other real ROM-offset catalog in this project already runs.
    for _, e in ipairs(catalog.entries) do
      Harness.assertTrue(e.fileOffset >= 0 and e.fileOffset + 16 <= #romData)
      Harness.assertEqual(e.fileOffset % 16, 0)
      Harness.assertTrue(#e.rooms > 0)
    end
  end)

return true
