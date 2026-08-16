-- The "extract once, cache forever" half of the generated-cache
-- pipeline `docs/architecture.md` already names as this project's own
-- committed target architecture (gen1recomp's own real
-- ROM-in/generated-cache-out shape, task #34, 2026-08-16 --
-- deliberately deferred back on 2026-08-11 ("erstmal nur vormerken")
-- until enough real normalized game data existed to make caching pay
-- for itself; now 384 real decodable rooms, 201/256 opcodes, and full
-- monster/item/NPC catalogs exist, so it does).
--
-- Pure Lua, no `love.*`/`io.*` calls -- runs a bounded, real set of
-- this project's OWN ALREADY-EXISTING importers (the same ones
-- `rom-inspector/tools/export_data.lua` already calls for the
-- website) against a real `romData` string and returns one plain Lua
-- table -- `{ stageName = <decoded data>, ... }` -- plus a real
-- manifest recording which ROM this came from. Turning that table
-- into real files on disk is `scripts/extract_rom_cache.lua`'s own
-- job (matching `SaveFile.lua`'s own already-established "thin,
-- untested I/O glue around a pure, tested core" split).
--
-- HONEST SCOPE, deliberately bounded (NOT every importer in
-- `src/import/` is wired here yet): this first pass includes the
-- real, self-contained, parameter-simple decoders whose OUTPUT is a
-- plain, already-fully-decoded table with no further live/room-
-- specific arguments needed (`EnemySpeciesTable`, `ItemTable`,
-- `WeaponTable`, `NpcCatalog`). Real, larger decoders this project
-- also has (`RoomFloorLayout` -- needs a specific room selector per
-- call, not a single "decode everything" entry point; `MapTileCatalog`/
-- `GraphicsCandidates` -- produce real pixel/image data needing an
-- `ImageWriter`, not `LuaWriter`, the gen1recomp shape this project
-- hasn't built yet) are a real, valuable, clearly-scoped follow-up,
-- not silently skipped -- see this file's own `STAGES` table, which is
-- the single, explicit place to extend this list.

local EnemySpeciesTable = require("src.import.EnemySpeciesTable")
local ItemTable = require("src.import.ItemTable")
local WeaponTable = require("src.import.WeaponTable")
local NpcCatalog = require("src.import.NpcCatalog")
local RomIdentity = require("src.import.RomIdentity")

local RomExtractor = {}

--- Each stage: `name` (also the generated file's own basename,
-- `data/generated/<name>.lua`), `run(romData, profile)` (returns the
-- real decoded value to cache). Order matches this file's own doc
-- comment above; adding a new real importer here is the ONLY change
-- needed to extend the cache (`scripts/extract_rom_cache.lua` and the
-- round-trip test both iterate this table generically, not by name).
RomExtractor.STAGES = {
  {
    name = "monsters",
    run = function(romData, profile)
      local rows = EnemySpeciesTable.decode(romData, profile.enemySpeciesTable)
      return { rows = rows, species = EnemySpeciesTable.groupBySpecies(rows) }
    end,
  },
  {
    name = "items",
    run = function(romData, profile)
      local records = ItemTable.decode(romData, profile.itemTable)
      return { records = records, categories = ItemTable.groupByCategory(records) }
    end,
  },
  {
    name = "weapons",
    run = function(romData, profile)
      local records = WeaponTable.decode(romData, profile.weaponTable)
      return { records = records, categories = WeaponTable.groupByCategory(records) }
    end,
  },
  {
    name = "npcs",
    run = function(_romData, profile)
      -- NpcCatalog.build takes `profile` directly (not `romData` +
      -- a sub-table) -- see that module's own doc comment: NPC data
      -- isn't a static ROM table, it's hand-captured scene data
      -- already embedded in `rom_profiles.lua` itself.
      return NpcCatalog.build(profile)
    end,
  },
}

--- Runs every real stage in `RomExtractor.STAGES` against `romData`/
-- `profile` and returns `data, manifest`:
-- `data` = `{ [stage.name] = <that stage's real decoded value>, ... }`
-- `manifest` = `{ romSha1, romTitle, stages = {names...},
-- generatedAt }` -- `generatedAt` is the ONE real non-deterministic
-- field (a real wall-clock timestamp, `os.time()`) -- deliberately
-- excluded from anything this module claims is "deterministic" (the
-- per-stage DATA itself is fully deterministic for a given ROM; only
-- the manifest's own bookkeeping timestamp isn't, matching how a real
-- build system's own manifest works).
--
-- A real failure in any ONE stage aborts the whole run (no partial,
-- silently-incomplete cache) -- re-raises with the real stage name
-- prefixed, so a failure is traceable to which importer broke, not a
-- bare Lua error deep in some shared helper.
function RomExtractor.run(romData, profile)
  assert(type(romData) == "string", "RomExtractor.run expects a real ROM byte string")
  assert(type(profile) == "table", "RomExtractor.run expects a real rom_profiles.lua profile table")

  local data = {}
  local stageNames = {}
  for _, stage in ipairs(RomExtractor.STAGES) do
    local ok, result = pcall(stage.run, romData, profile)
    if not ok then
      error(("RomExtractor.run: real stage %q failed: %s"):format(stage.name, tostring(result)))
    end
    data[stage.name] = result
    stageNames[#stageNames + 1] = stage.name
  end

  local report = RomIdentity.identify(romData)
  local manifest = {
    romSha1 = report.sha1,
    romTitle = report.title,
    stages = stageNames,
    generatedAt = os.time(),
  }
  return data, manifest
end

return RomExtractor
