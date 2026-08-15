local Harness = require("tests.harness")
local NpcCatalog = require("src.import.NpcCatalog")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("NpcCatalog.build: fails loudly without a profile", function()
  Harness.assertTrue(not pcall(NpcCatalog.build, nil))
end)

Harness.test("NpcCatalog.build: an empty profile (no graphics data) yields an empty catalog, not an error", function()
  local entries = NpcCatalog.build({})
  Harness.assertEqual(#entries, 0)
end)

Harness.test("NpcCatalog.build: reads a synthetic profile's willyScene/secondRoom scene data", function()
  local profile = {
    graphics = {
      willyScene = {
        willy = { screenX = 64, screenY = 80, tileOffsets = { 1, 2, 3, 4 }, palette = "OBP1" },
      },
      secondRoom = {
        scene = {
          characterA = {
            screenX = 128, screenY = 58,
            dialogue = { "Hallo A" },
            -- Real 4-tile row-major 2x2 block shape (see
            -- rom_profiles.lua's own 2026-08-15 doc comment) -- not the
            -- old, wrong 2-tile top/bottom pair.
            animation = { down = { { tileOffsets = { 0x100, 0x101, 0x102, 0x103 } } } },
          },
          characterB = {
            screenX = 80, screenY = 58,
            dialogue = { "Hallo B" },
            animation = { down = { { tileOffsets = { 0x200, 0x201, 0x202, 0x203 } } } },
          },
        },
      },
    },
  }
  local entries = NpcCatalog.build(profile)
  Harness.assertEqual(#entries, 3)
  Harness.assertEqual(entries[1].name, "Willy")
  Harness.assertEqual(entries[1].room, "willyRoom")
  Harness.assertEqual(entries[1].palette, "OBP1")
  Harness.assertEqual(entries[1].animation, nil) -- honest gap: no real animation data for Willy
  Harness.assertEqual(entries[2].name, "characterA")
  Harness.assertEqual(entries[2].room, "secondRoom")
  Harness.assertEqual(entries[2].dialogue[1], "Hallo A")
  Harness.assertEqual(entries[2].tileOffsets[1], 0x100)
  Harness.assertEqual(entries[2].tileOffsets[2], 0x101)
  Harness.assertEqual(entries[2].tileOffsets[3], 0x102)
  Harness.assertEqual(entries[2].tileOffsets[4], 0x103)
  Harness.assertEqual(entries[2].animation.down[1].tileOffsets[1], 0x100) -- the full real animation table is passed through
  Harness.assertEqual(entries[3].name, "characterB")
  Harness.assertEqual(entries[3].dialogue[1], "Hallo B")
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "NpcCatalog.build: real ROM profile yields the 3 real, already-verified NPCs this project has found",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local entries = NpcCatalog.build(profile)
    Harness.assertEqual(#entries, 3)

    local byName = {}
    for _, e in ipairs(entries) do byName[e.name] = e end

    Harness.assertTrue(byName["Willy"] ~= nil)
    Harness.assertEqual(byName["Willy"].room, "willyRoom")

    Harness.assertTrue(byName["characterA"] ~= nil)
    Harness.assertEqual(byName["characterA"].room, "secondRoom")
    Harness.assertTrue(byName["characterA"].dialogue[1]:find("Monsterein") ~= nil)
    -- Real, full 4-direction x 2-phase animation table (see
    -- rom_profiles.lua's own `secondRoom.scene.characterA.animation`).
    Harness.assertEqual(byName["characterA"].framesPerPhase, 10)
    Harness.assertTrue(byName["characterA"].animation.down ~= nil)
    Harness.assertTrue(byName["characterA"].animation.up ~= nil)
    Harness.assertTrue(byName["characterA"].animation.left ~= nil)
    Harness.assertTrue(byName["characterA"].animation.right ~= nil)
    Harness.assertEqual(#byName["characterA"].animation.down, 2) -- 2 real phases
    -- Real 16x16 (4-tile 2x2) shape, not the old, wrong 2-tile column
    -- (see rom_profiles.lua's own 2026-08-15 doc comment: a fresh live
    -- OAM re-trace found these are a genuine LEFT+RIGHT 2-OAM-entry
    -- pair, each already 8x16 in hardware).
    Harness.assertEqual(#byName["characterA"].animation.down[1].tileOffsets, 4)
    Harness.assertEqual(#byName["characterA"].tileOffsets, 4)
    -- Real tile ORDER (2026-08-15, same-day 2nd correction, direct user
    -- report "die linke und rechte haelfte ... sind vertauscht"): a
    -- first fix reordered these 4 tiles by their own live-captured OAM
    -- screen X position and got 2 disconnected blobs, not a character
    -- -- the real ROM stores each pose's 4 tiles in plain, UNREORDERED
    -- sequential file order (`{T,T+0x10,T+0x20,T+0x30}`), confirmed by
    -- directly rendering the decoded pixels. Locking in the exact real
    -- offsets for `down` phase 1 so a future edit can't silently
    -- reintroduce the reordering bug without a test catching it.
    local down1 = byName["characterA"].animation.down[1].tileOffsets
    Harness.assertEqual(down1[1], 0x25100)
    Harness.assertEqual(down1[2], 0x25110)
    Harness.assertEqual(down1[3], 0x25120)
    Harness.assertEqual(down1[4], 0x25130)

    -- Real name (2026-08-15, direct user report "das ist amanda"):
    -- `characterB` now surfaces as "Amanda" (see rom_profiles.lua's own
    -- `realName` field/doc comment) -- the internal `characterB` key
    -- itself is no longer the exposed `name`.
    Harness.assertTrue(byName["Amanda"] ~= nil)
    Harness.assertTrue(byName["Amanda"].dialogue[1]:find("Willy") ~= nil)
    Harness.assertTrue(byName["Amanda"].dialogue[3]:find("Bruder") ~= nil)
    Harness.assertEqual(#byName["Amanda"].dialogue, 3) -- real 3-page monologue
    Harness.assertTrue(byName["Amanda"].animation ~= nil)
  end
)

if romData then
  print("(NpcCatalog ROM-dependent tests ran against a real dev ROM)")
end
