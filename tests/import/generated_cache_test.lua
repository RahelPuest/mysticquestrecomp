local Harness = require("tests.harness")
local GeneratedCache = require("src.import.GeneratedCache")
local RomIdentity = require("src.import.RomIdentity")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("GeneratedCache.tryLoad: returns nil gracefully for a stage that doesn't exist, no error", function()
  Harness.assertEqual(GeneratedCache.tryLoad("this_stage_does_not_exist"), nil)
end)

Harness.test("GeneratedCache.verifyManifest: returns false (not an error) when no manifest is present or sha1 doesn't match a made-up value", function()
  -- Whether or not data/generated/manifest.lua happens to exist in
  -- this dev environment (gitignored, absent on a fresh checkout), a
  -- deliberately-wrong sha1 must never verify -- real, honest failure
  -- either way.
  Harness.assertEqual(GeneratedCache.verifyManifest("0000000000000000000000000000000000000000"), false)
end)

-- --- Cache-dependent tests (only meaningful once `scripts/extract_rom_cache
-- .lua` has actually been run against a real ROM -- gitignored, absent on
-- a fresh checkout; this test HONESTLY SKIPS rather than failing when
-- that hasn't happened, same convention as Harness.testIfAvailable's
-- other real-ROM/real-cache-dependent tests project-wide) ------------
local romData = DevRomLocator.find()
local manifestPresent = GeneratedCache.tryLoad("manifest") ~= nil

Harness.testIfAvailable(
  "GeneratedCache: verifies a real, freshly-generated cache against the real ROM's own sha1 (task 'komplett autark interpretiert', cache read-side)",
  romData ~= nil and manifestPresent,
  "no development ROM found, or data/generated/manifest.lua hasn't been generated yet (run scripts/extract_rom_cache.lua)",
  function()
    local report = RomIdentity.identify(romData)
    Harness.assertTrue(GeneratedCache.verifyManifest(report.sha1),
      "expected the real, freshly-generated cache's own manifest.romSha1 to match the real loaded ROM")

    local monsters = GeneratedCache.tryLoad("monsters")
    local items = GeneratedCache.tryLoad("items")
    local weapons = GeneratedCache.tryLoad("weapons")
    local npcs = GeneratedCache.tryLoad("npcs")
    Harness.assertTrue(monsters ~= nil and #monsters.rows > 0, "expected real cached monster rows")
    Harness.assertTrue(items ~= nil and #items.records > 0, "expected real cached item records")
    Harness.assertTrue(weapons ~= nil and #weapons.records > 0, "expected real cached weapon records")
    Harness.assertTrue(npcs ~= nil and #npcs > 0, "expected real cached NPC entries")
  end
)

Harness.testIfAvailable(
  "GeneratedCache.loadAll: loads every real RomExtractor.STAGES entry from the cache, all-or-nothing",
  romData ~= nil and manifestPresent,
  "no development ROM found, or data/generated/manifest.lua hasn't been generated yet (run scripts/extract_rom_cache.lua)",
  function()
    local RomExtractor = require("src.import.RomExtractor")
    local data = GeneratedCache.loadAll(romData)
    Harness.assertTrue(data ~= nil, "expected a real loaded cache table")
    for _, stage in ipairs(RomExtractor.STAGES) do
      Harness.assertTrue(data[stage.name] ~= nil, "expected cached stage " .. stage.name)
    end

    -- A wrong-ROM byte string (an empty string is never a real ROM,
    -- and definitely doesn't match the cache's own real sha1) must
    -- return nil, not a stale/wrong cache.
    Harness.assertEqual(GeneratedCache.loadAll(""), nil)
  end
)

return true
