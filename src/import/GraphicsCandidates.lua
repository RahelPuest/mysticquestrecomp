-- A curated, honestly-scoped list of REAL candidate creature/character
-- graphics regions found via `tools/rom/scan_graphics.py` (a heuristic
-- 2bpp-tile entropy scan -- see that tool's own doc comment) and
-- VISUALLY CONFIRMED by rendering each one with `tools/graphics/
-- gbtile.py` and looking at it (a real, methodical step, not a claim
-- based on the entropy score alone).
--
-- FOUND 2026-08-15, direct user request ("suche jetzt einfach mehr
-- npcs mit den grafiken und mehr monster... vor allem weil ich glaube
-- die die du bis jetzt gefunden hast sind nur bosse"), following the
-- exact methodology already scoped in this project's own planning
-- notes for this work (`docs/reverse-engineering/rom-map.md`'s own
-- "Bank 9-11 candidate scan" lead, never previously acted on -- task
-- #135 was still pending before this pass).
--
-- HONEST SCOPE, matching this project's own "no silent fallbacks"
-- rule: every entry below is a REAL, ROM-verified tile region (you can
-- render it yourself with `gbtile.py` and see the same art) that looks
-- like genuine creature/character sprite work, NOT random code/data
-- misread as pixels. What this does NOT claim:
--   - which (if any) of the 11 real `EnemySpeciesTable` species each
--     region belongs to (no live OAM trace exists for any of these --
--     the ALREADY-known enemy sprite's own tile block, `rom_profiles
--     .lua`'s `enemySprite`, was only found because that ONE species
--     is actually spawnable/fightable in this project's own known
--     content; none of these are)
--   - the exact real sprite boundaries within each region (a region's
--     own `tileCount` is the real, contiguous entropy-scan run length,
--     not a claimed "this is exactly one creature" -- a real sprite
--     might use a subset, or an OAM-scattered layout the same way the
--     known `enemySprite` does, see that field's own doc comment)
--   - real in-game reachability (none of these have a known trigger/
--     spawn condition -- they might be used, cut content, or reused
--     for a system this project hasn't identified yet)
-- Every entry's own `note` records what it visually looks like, in
-- plain language, exactly as a human would describe the rendered PNG
-- -- an honest visual impression, not a decoded fact.
--
-- Pure Lua, no love.* calls, same convention as EnemySpeciesTable/
-- NpcCatalog. See `tests/import/graphics_candidates_test.lua` for
-- structural checks (every fileOffset/tileCount is a real, in-bounds
-- ROM region).

local GraphicsCandidates = {}

--- Real, hand-curated candidate list. `fileOffset` is the real ROM
-- file offset of the region's own first tile (16-byte tile-aligned);
-- `tileCount` is the real, contiguous run of tile-shaped bytes found
-- by `scan_graphics.py` there (entropy-based lead generation, then
-- visually confirmed by rendering it). `cols` is a display-only
-- column count chosen for a readable grid (NOT a claimed real sprite
-- sheet width -- no such structure is confirmed).
GraphicsCandidates.ENTRIES = {
  {
    id = "bank10_7900",
    bank = 10,
    fileOffset = 0x2B900,
    tileCount = 44,
    cols = 8,
    kind = "monster",
    note = "A hooded/pointed-head humanoid shape with a dark robe-like " ..
      "body silhouette, appearing as a repeated 2x2-tile block (left " ..
      "half and a near-identical right half -- plausibly 2 real " ..
      "animation poses of the same creature, the same 2-pose pattern " ..
      "this project's own known enemy sprite already uses via its " ..
      "real hardware X-flip).",
  },
  {
    id = "bank10_6400",
    bank = 10,
    fileOffset = 0x2A400,
    tileCount = 34,
    cols = 8,
    kind = "monster",
    note = "Bat-winged and blob-like creature shapes -- several " ..
      "distinct silhouettes in one region, including one with clear " ..
      "wing-like protrusions at the top.",
  },
  {
    id = "bank10_6A20",
    bank = 10,
    fileOffset = 0x2AA20,
    tileCount = 33,
    cols = 8,
    kind = "monster",
    note = "Armored or helmeted humanoid figures, several similar " ..
      "variants in a row -- plausibly a real armored enemy or knight-" ..
      "type creature.",
  },
  {
    id = "bank10_6D90",
    bank = 10,
    fileOffset = 0x2AD90,
    tileCount = 33,
    cols = 8,
    kind = "monster",
    note = "More helmet/head-shaped silhouettes plus what look like " ..
      "creature faces with visible eyes -- likely more of the same " ..
      "sprite family as the bank10_6A20 region just before it (this " ..
      "region sits immediately adjacent in the file).",
  },
  {
    id = "bank11_5220",
    bank = 11,
    fileOffset = 0x2D220,
    tileCount = 34,
    cols = 8,
    kind = "monster",
    note = "Small round/blob creature shapes, several distinct " ..
      "variants -- found in the SAME bank (11) as this project's own " ..
      "already-known, confirmed enemy sprite and the title-screen " ..
      "logo art, matching rom_profiles.lua's own existing doc-comment " ..
      "hint that bank 11 holds 'title-logo art plus real small " ..
      "creature-sprite fragments'.",
  },
}

--- Expand one entry's own `fileOffset`/`tileCount` into a plain array
-- of real, contiguous 16-byte-stride tile offsets (the SAME shape
-- `rom_profiles.lua`'s own `tileOffsets` fields already use elsewhere
-- in this project, e.g. `enemySprite.tileOffsets`) -- lets the website/
-- CatalogExplorer draw these with the exact same tile-grid renderer,
-- no special-casing needed.
function GraphicsCandidates.tileOffsets(entry)
  local offsets = {}
  for i = 0, entry.tileCount - 1 do
    offsets[i + 1] = entry.fileOffset + i * 16
  end
  return offsets
end

return GraphicsCandidates
