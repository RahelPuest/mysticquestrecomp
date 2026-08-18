-- A curated, honestly-scoped list of candidate creature/character
-- graphics regions found via `tools/rom/scan_graphics.py` (a heuristic
-- 2bpp-tile entropy scan -- see that tool's doc comment) and visually
-- confirmed by rendering each one with `tools/graphics/gbtile.py` and
-- looking at it (a methodical step, not a claim based on the entropy
-- score alone).
--
-- FOUND following the exact methodology already scoped in this
-- project's planning notes for this work
-- (`docs/reverse-engineering/rom-map.md`'s "Bank 9-11 candidate scan"
-- lead, never previously acted on).
--
-- EXTENDED (direct follow-up asking to keep searching for graphics
-- until all are found): the first pass only checked individual
-- `scan_graphics.py` hits one at a time and stopped at 5 entries. This
-- pass instead rendered every ROM bank (0-15) in full (`gbtile.py`,
-- whole 16KB bank at once) and visually reviewed each -- a systematic
-- sweep, not more sampling. Confirmed banks 0/1/2/3/4/5/6/7/13/14/15
-- are genuinely code/text/room-table data (pure noise when rendered as
-- tiles, no real pixel structure) and bank 12 is predominantly
-- environment/tileset art (walls, floors -- matches this project's
-- already-used room tilesets) with no clear creature content. Banks 8,
-- 9, 10, and 11 turned out to be genuinely, densely packed with
-- creature/character/icon art -- 7 more regions added below from this
-- fuller sweep, on top of the original 5.
--
-- HONEST SCOPE, matching this project's "no silent fallbacks" rule:
-- every entry below is a ROM-verified tile region (you can render it
-- yourself with `gbtile.py` and see the same art) that looks like
-- genuine creature/character sprite work, not random code/data misread
-- as pixels. What this does not claim:
--   - which (if any) of the 11 `EnemySpeciesTable` species each region
--     belongs to (no live OAM trace exists for any of these -- the
--     already-known enemy sprite's tile block, `rom_profiles.lua`'s
--     `enemySprite`, was only found because that one species is
--     actually spawnable/fightable in this project's known content;
--     none of these are)
--   - the exact sprite boundaries within each region (a region's
--     `tileCount` is the contiguous entropy-scan run length, not a
--     claimed "this is exactly one creature" -- a sprite might use a
--     subset, or an OAM-scattered layout the same way the known
--     `enemySprite` does, see that field's doc comment)
--   - real in-game reachability (none of these have a known
--     trigger/spawn condition -- they might be used, cut content, or
--     reused for a system this project hasn't identified yet)
-- Every entry's `note` records what it visually looks like, in plain
-- language, exactly as a human would describe the rendered PNG -- an
-- honest visual impression, not a decoded fact.
--
-- EXTENDED AGAIN (direct follow-up: do the same search for
-- map/environment tiles that was just done for monster/NPC tiles).
-- Bank 12 is the one bank this project's full 16-bank sweep (above)
-- already confirmed holds environment/architecture tileset art, not
-- creatures -- `rom_profiles.lua`'s `environmentTilesetBank12` entry
-- and the `tilesetFileOffset = 0x32000` formula MapTable.lua/
-- rom_profiles.lua already use for real, live rooms. So "search for
-- map tiles" here means something more precise than the monster search
-- did: check exactly how much of bank 12's 1024 tiles are already
-- wired into a walkable room, vs. genuinely unconfirmed -- not just
-- "does this look like tileset art" (the whole bank already does).
--
-- Rendered the whole bank in 4 natural 256-tile chunks (256 tiles is
-- exactly one full loadable Game Boy background-tile VRAM page --
-- 0x30000/0x31000/0x32000/0x33000, a hardware-meaningful boundary, not
-- an arbitrary split) and cross-checked each chunk against every
-- literal ROM-offset tile reference already recorded in
-- `rom_profiles.lua` (`grep`, not a guess):
--   - 0x30000-0x30FFF: 57 distinct, live-disambiguated tile offsets
--     already in use (e.g. `fourthRoom`'s tileOffsets 129-147) --
--     already wired into rooms, just via scattered individual per-tile
--     picks rather than the systematic table, so not re-cataloged as a
--     new "candidate" here (would misrepresent already-confirmed
--     content as newly found).
--   - 0x31000-0x31FFF: zero confirmed usage anywhere in this project.
--     The only mention of this range at all is `secondRoom`'s doc
--     comment (rom_profiles.lua ~line 1614) recording `0x31f80-0x31fb0`
--     as an ambiguous candidate match that was explicitly not chosen
--     (0x32170-0x321a0 was picked instead) -- i.e. the one time this
--     range came up, it was rejected. A clean, genuinely unconfirmed
--     256-tile region -- the single new entry added below,
--     `bank12_environment_b`.
--   - 0x32000-0x33FFF (chunks 3+4): the systematic `tilesetFileOffset
--     = 0x32000 + tileId*16` table every room using the generic
--     tileset already resolves through -- confirmed, no new entry
--     needed, this is what `environmentTilesetBank12.confirmedFrom`
--     already documents.
--
-- Same honest scope as every entry above: `bank12_environment_b` is
-- visually-confirmed tileset-style art (matches its neighbors'
-- established style -- stone/architecture textures, decorative
-- borders) with no live in-game room proven to use it -- not a claim
-- that it's cut content, unused, or reachable by any specific means.
--
-- Pure Lua, no love.* calls, same convention as EnemySpeciesTable/
-- NpcCatalog. See `tests/import/graphics_candidates_test.lua` for
-- structural checks (every fileOffset/tileCount is an in-bounds ROM
-- region).

local GraphicsCandidates = {}

--- Hand-curated candidate list. `fileOffset` is the ROM file offset of
-- the region's first tile (16-byte tile-aligned); `tileCount` is the
-- contiguous run of tile-shaped bytes found by `scan_graphics.py` there
-- (entropy-based lead generation, then visually confirmed by rendering
-- it). `cols` is a display-only column count chosen for a readable grid
-- (not a claimed sprite sheet width -- no such structure is confirmed).
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
  {
    id = "bank8_portraits",
    bank = 8,
    fileOffset = 0x22260,
    tileCount = 32,
    cols = 8,
    kind = "npc",
    note = "4 distinct humanoid character portraits, each wearing a " ..
      "different hat/hood (a beret-like cap, a dark hood, a visored " ..
      "helmet, a full dark hood) -- sits right before this project's " ..
      "own already-known dialogue font block (fileOffset 0x22B00) in " ..
      "the same bank. Reads like a real 'class/profession' portrait " ..
      "icon set (shopkeeper/NPC-role icons) rather than a monster -- " ..
      "the strongest NPC-shaped candidate found this pass.",
  },
  {
    id = "bank8_icon_fragments",
    bank = 8,
    fileOffset = 0x22EE0,
    tileCount = 274,
    cols = 16,
    kind = "fragment",
    note = "A dense field of small icon/creature fragments right after " ..
      "the dialogue font block: weapon-like shapes, plant/mushroom " ..
      "shapes, and partial creature pieces (a flame-like shape, a " ..
      "crab/spider-like shape) -- individually small and hard to tell " ..
      "apart as complete sprites, more likely a shared icon/decoration " ..
      "sheet than one specific creature.",
  },
  {
    id = "bank9_creature_columns",
    bank = 9,
    fileOffset = 0x24400,
    tileCount = 704,
    cols = 16,
    kind = "monster",
    note = "A very large, dense field of tall, segmented humanoid/" ..
      "totem-like creature columns -- many similar-looking stacked " ..
      "figures repeating down the bank, plus a few distinct larger " ..
      "shapes (a dragon/dinosaur-like head, a spiky urchin-like " ..
      "creature). By far the single richest graphics region found in " ..
      "this whole pass -- genuinely too dense and repetitive to " ..
      "confidently split into individual creature boundaries without " ..
      "a live OAM trace, so kept as one large honest region rather " ..
      "than guessing where one sprite ends and the next begins. " ..
      "SELF-CAUGHT CORRECTION (2026-08-16, task #160, access analysis " ..
      "-- see rom-map.md's own 'the real graphics-loading mechanism' " ..
      "section for the full disassembly): real code at file 0x24228 " ..
      "(bank 9's own graphics-dispatch routine) walks a 6-byte-stride " ..
      "RECORD TABLE starting at file 0x24479 -- INSIDE this claimed " ..
      "range. Raw bytes there show a clearly repeating, small-period, " ..
      "non-pixel structure, not 2bpp tile noise -- that sub-range is " ..
      "real STRUCTURED DATA, not pixel art, confirmed via the code " ..
      "that actually consumes it. The bulk of this region still " ..
      "visually reads as real creature art on direct render (that " ..
      "part of the original finding stands), but this note is no " ..
      "longer claiming EVERY byte in fileOffset..fileOffset+tileCount" ..
      "*16 is pixel data -- an honest, partial retraction.",
  },
  {
    id = "bank9_icon_fragments",
    bank = 9,
    fileOffset = 0x27000,
    tileCount = 256,
    cols = 16,
    kind = "fragment",
    note = "Small icon/creature fragments at the tail of bank 9 -- hat/" ..
      "cap shapes, weapon-like shapes, mushroom shapes -- the same " ..
      "style as bank8_icon_fragments, plausibly a shared icon-sheet " ..
      "convention reused across banks.",
  },
  {
    id = "bank11_creatures_a",
    bank = 11,
    fileOffset = 0x2C400,
    tileCount = 216,
    cols = 16,
    kind = "monster",
    note = "Dense creature art immediately below the real 'MYSTIC " ..
      "QUEST' title-logo art in the same bank -- wings, horns, and " ..
      "dragon/wolf-like shapes clearly visible, matching this " ..
      "project's own earlier visual-scan lead (rom-map.md's now-acted-" ..
      "on 'Bank 9-11 candidate scan' note). First of 4 contiguous " ..
      "regions covering this bank's own real creature-art field.",
  },
  {
    id = "bank11_creatures_b",
    bank = 11,
    fileOffset = 0x2D180,
    tileCount = 216,
    cols = 16,
    kind = "monster",
    note = "Continuation of bank11_creatures_a, immediately following " ..
      "it in the file (no gap) -- more dense wing/horn/creature-face " ..
      "shapes, including what looks like a tentacle-like form.",
  },
  {
    id = "bank11_creatures_c",
    bank = 11,
    fileOffset = 0x2DF00,
    tileCount = 216,
    cols = 16,
    kind = "monster",
    note = "Continuation of bank11_creatures_b, immediately following " ..
      "it in the file (no gap) -- same dense creature-art style " ..
      "continues.",
  },
  {
    id = "bank11_creatures_d",
    bank = 11,
    fileOffset = 0x2EC80,
    tileCount = 216,
    cols = 16,
    kind = "monster",
    note = "Continuation of bank11_creatures_c, immediately following " ..
      "it in the file (no gap) -- the last of the 4 contiguous " ..
      "regions; ends before a real gap that leads into this project's " ..
      "OWN ALREADY-KNOWN, confirmed enemy sprite (rom_profiles.lua's " ..
      "`enemySprite`, fileOffset 0x2FE00, further into the same bank).",
  },
  {
    id = "bank12_environment_b",
    bank = 12,
    fileOffset = 0x31000,
    tileCount = 256,
    cols = 16,
    kind = "tileset",
    note = "A full, real 256-tile environment/architecture block -- a " ..
      "black crenellated (castle-wall-style) top border repeated " ..
      "across the sheet, window/door-like building fragments, tree " ..
      "and vine/waterfall textures, fence sections, and furniture-" ..
      "like shapes (a dresser/drawer silhouette) near the bottom. " ..
      "Same general visual family as its neighbors on both sides " ..
      "(bank12_environment_b sits between the ALREADY-WIRED 0x30000 " ..
      "block, used piecemeal by real rooms like fourthRoom, and the " ..
      "ALREADY-WIRED systematic tileset table starting at 0x32000) -- " ..
      "but, unlike both of those, this exact 256-tile block has NO " ..
      "confirmed real room using it (see this file's own doc comment " ..
      "above for the full grep-based evidence). The single cleanest " ..
      "'new' map-tile candidate this pass found: real ROM pixel data " ..
      "in visually the right style, honestly unconfirmed as to actual " ..
      "in-game usage.",
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
