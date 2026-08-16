-- The READ side of the generated-cache pipeline (task #34's own
-- write side -- `RomExtractor`/`LuaWriter`/`scripts/extract_rom_cache
-- .lua` -- shipped 2026-08-16; this is the read-side migration that
-- file's own doc comment explicitly deferred as a separate follow-up).
-- Direct continuation of the "komplett autark interpretiert" gap
-- analysis's second concretely-actionable item.
--
-- `data/generated/*.lua` files are real Lua SOURCE (not raw bytes) --
-- LÖVE's own `require()` already knows how to find/load `.lua` modules
-- bundled anywhere in the project source tree (the exact same
-- mechanism every `require("src.import...")` call in this app already
-- relies on -- see `RomLocator.lua`'s own doc comment for why
-- `love.filesystem` vs. plain `io.open` matters for content bundled
-- IN the app vs. an external path). So the read side is just `require`
-- wrapped in `pcall` for graceful absence -- no bespoke file-reading
-- code needed, unlike the WRITE side (which is real, external-path,
-- plain-`io` CLI glue, per `scripts/extract_rom_cache.lua`'s own doc
-- comment).
--
-- SAFETY: `data/generated/` is gitignored (it embeds directly-
-- extractable copyrighted ROM content) and absent by default on a
-- fresh checkout -- `tryLoad` returns `nil` gracefully in that case,
-- the SAME honest "generated file missing -> caller falls back to
-- live ROM decode" convention this project already uses for "no
-- romData loaded" throughout Field.lua/VictorySequence.lua. A REAL
-- correctness check this module also owns: a stale cache generated
-- from a DIFFERENT ROM revision must never be silently served as if
-- current -- `verifyManifest` compares the cache's own recorded
-- `romSha1` (see `RomExtractor.lua`'s own manifest) against the
-- currently-loaded ROM's real SHA-1 and refuses (returns false, not a
-- guess) on any mismatch.

local GeneratedCache = {}

--- Loads `data/generated/<name>.lua` via `require`, returning `nil` (not
-- erroring) if the module doesn't exist or fails to load -- the one
-- real "is the cache present at all" question this module answers.
function GeneratedCache.tryLoad(name)
  assert(type(name) == "string" and name ~= "", "GeneratedCache.tryLoad expects a real stage name")
  local ok, value = pcall(require, "data.generated." .. name)
  if not ok then return nil end
  return value
end

--- Real safety check: loads the cache's own manifest and confirms its
-- recorded `romSha1` matches `romSha1` (the CURRENTLY loaded ROM's own
-- real hash, from `RomIdentity.identify(romData).sha1`). Returns
-- `true` only when a manifest exists AND its sha1 matches -- `false`
-- for "no cache at all" AND for "cache exists but is for a different
-- ROM," the SAME real, honest signal either way: don't trust it,
-- fall back to live decode.
function GeneratedCache.verifyManifest(romSha1)
  assert(type(romSha1) == "string", "GeneratedCache.verifyManifest expects the current ROM's real sha1")
  local manifest = GeneratedCache.tryLoad("manifest")
  if not manifest or type(manifest.romSha1) ~= "string" then return false end
  return manifest.romSha1 == romSha1
end

--- Loads every stage `RomExtractor.STAGES` names (reusing that list
-- directly rather than a second, hand-kept copy that could drift out
-- of sync -- adding a new stage to `RomExtractor` automatically makes
-- it available here too) -- returns `{ [stageName] = <cached data> }`
-- only when the manifest verifies AND every single stage is actually
-- present; returns `nil` (never a PARTIAL table) the instant either
-- check fails, so a caller never has to guess whether a missing key
-- means "not generated yet" or "real bug" -- same "all or nothing, no
-- silent partial cache" discipline `RomExtractor.run` itself already
-- uses for the write side.
function GeneratedCache.loadAll(romData)
  assert(type(romData) == "string", "GeneratedCache.loadAll expects a real ROM byte string")
  local RomIdentity = require("src.import.RomIdentity")
  local report = RomIdentity.identify(romData)
  if report.error or not GeneratedCache.verifyManifest(report.sha1) then
    return nil
  end
  local RomExtractor = require("src.import.RomExtractor")
  local data = {}
  for _, stage in ipairs(RomExtractor.STAGES) do
    local value = GeneratedCache.tryLoad(stage.name)
    if not value then return nil end
    data[stage.name] = value
  end
  return data
end

return GeneratedCache
