-- Catalogs the NPCs this project has actually found and placed, by
-- reading the already-verified scene data straight out of
-- `rom_profiles.lua` (`graphics.willyScene.willy`,
-- `graphics.secondRoom.scene.characterA/B`) instead of duplicating it
-- -- this module is a thin, headlessly-testable NORMALIZER, not a
-- second source of truth.
--
-- HONEST SCOPE, 2026-08-15 (monster/npc/item census, direct user
-- request "versuche mal alle monster, npcs und items zu extrahieren"):
-- unlike `EnemySpeciesTable`/`ItemTable`/`WeaponTable`, this catalog
-- itself is still built by hand-normalizing live-captured scene data
-- (OAM tracing + per-room proximity/dialogue testing), not by
-- mechanically walking a table.
--
-- CORRECTED, 2026-08-20 (direct follow-up to that same day's "second
-- enemy" investigation, see docs/reverse-engineering/events.md's
-- 2026-08-20 "SOLVED" entry): the claim this doc comment used to make
-- here -- "an earlier, separate investigation already established,
-- live and exhaustively, that NPCs are NOT placed via a fixed table in
-- this ROM" -- is now known to be WRONG, not just incomplete. A real,
-- ROM-verified, 109-row x 3-column spawn table (`src/import/
-- NpcSpawnTable.lua`, CPU `$7142`, byte-identical to the external
-- FFA-Disassembly's own documented `NPCSpawnPointers`) DOES place every
-- NPC and monster in this game, driven by real script opcodes
-- (`0xFC`/`0xFD`). The earlier investigation's own negative was real
-- for whatever it specifically checked, but the broader claim it drew
-- from that check did not hold. This catalog's own "hand-normalize
-- live-captured scenes" approach remains valid (finding which real
-- ROM script fires which `(row, col)` in the wild is a separate,
-- still-open problem -- see `NpcSpawnTable.lua`'s own "HONEST SCOPE"
-- note), it just isn't because no table exists.
--
-- Pure Lua, no love.* calls, so it's headlessly testable like
-- ItemTable/WeaponTable/EnemySpeciesTable.

local NpcCatalog = {}

--- Build the catalog from a matched `profile` (`rom_profiles.lua`'s
-- own `RomProfiles.match` result). Returns a plain 1-based array of:
--   { name, room, screenX, screenY, tileOffsets, dialogue = {lines}
--     or nil, palette = <string> or nil, animation = <table> or nil,
--     framesPerPhase = <number> or nil }
-- `tileOffsets` stays the single real resting-pose 4-tile 2x2 block
-- (down-facing, phase 1 -- see rom_profiles.lua's own doc comment on
-- its real 2026-08-15 shape fix) for any caller that only wants a
-- static preview -- same convention as `enemySprite.tileOffsets`
-- elsewhere. `animation`, ADDED
-- 2026-08-15 (direct follow-up, "die sprites mit animationsphasen"),
-- is the FULL real per-direction/per-phase table where this project
-- has one (`rom_profiles.lua`'s own `secondRoom.scene.*.animation` --
-- 4 directions x 2 real phases each, already live-verified when this
-- data was first captured, see that file's own doc comment history for
-- the flipY correction) -- passed through as-is rather than
-- re-shaped, so `CatalogExplorer.lua`/the website can drive the SAME
-- real animation this project's own `NpcSprite.lua` renders during
-- actual gameplay, not a re-derived approximation.
--
-- Entries whose source data isn't present in `profile` are simply
-- omitted (not a fabricated placeholder) -- a profile without
-- `graphics.willyScene`/`graphics.secondRoom.scene`, for instance,
-- yields an empty catalog rather than an error, since not every real
-- ROM profile this project might ever match is guaranteed to have
-- reached the same live-tracing depth.
function NpcCatalog.build(profile)
  assert(type(profile) == "table", "NpcCatalog.build expects a matched rom profile")
  local entries = {}
  local graphics = profile.graphics

  local willyScene = graphics and graphics.willyScene
  local willy = willyScene and willyScene.willy
  if willy then
    entries[#entries + 1] = {
      name = "Willy",
      room = "willyRoom",
      screenX = willy.screenX,
      screenY = willy.screenY,
      tileOffsets = willy.tileOffsets,
      palette = willy.palette,
      -- Willy's own real dialogue is a long, multi-page live-decoded
      -- exchange (see VictorySequence.lua's own `self.pages` -- "top"
      -- box entries), not a single fixed string like secondRoom's
      -- NPCs below -- not duplicated here, left nil.
      dialogue = nil,
      -- HONEST GAP: no real per-direction/per-phase animation data was
      -- ever captured for Willy (only this one static resting pose) --
      -- left nil rather than fabricating a 4-direction set from the
      -- single known frame.
      animation = nil,
    }
  end

  -- The second, real, FIGHTABLE creature (see rom_profiles.lua's
  -- `goblinTestScene` doc comment for the full honest-scope story --
  -- reached only via a scratchpad-only patched-ROM test, not a natural
  -- trigger). Cataloged the same way Willy is, above.
  local goblinTestScene = graphics and graphics.goblinTestScene
  if goblinTestScene then
    entries[#entries + 1] = {
      name = "Goblin (Test)",
      room = "willyRoom",
      screenX = goblinTestScene.screenX,
      screenY = goblinTestScene.screenY,
      tileOffsets = goblinTestScene.tileOffsets,
      palette = goblinTestScene.palette,
      dialogue = nil,
      animation = nil,
    }
  end

  local secondRoomScene = graphics and graphics.secondRoom and graphics.secondRoom.scene
  if secondRoomScene then
    -- Real, live-confirmed order (see rom_profiles.lua's own doc
    -- comment on each): characterA then characterB, matching the ROM's
    -- own real text-stream order the dialogue was decoded from.
    for _, key in ipairs({ "characterA", "characterB" }) do
      local c = secondRoomScene[key]
      if c then
        -- CORRECTED (2026-08-15, see rom_profiles.lua's own doc comment
        -- on this exact fix): each pose is now a real 4-tile 2x2 block
        -- (`.tileOffsets`), not a 2-tile `.top`/`.bottom` pair -- just
        -- pass it straight through instead of re-assembling.
        local tileOffsets = nil
        if c.animation and c.animation.down and c.animation.down[1] then
          tileOffsets = c.animation.down[1].tileOffsets
        end
        entries[#entries + 1] = {
          -- Real German names for these townsfolk: `characterA`'s own
          -- name was never decoded/confirmed (only her dialogue was) --
          -- falls back to the plain internal `key`, not a claimed real
          -- ROM name. `characterB`, as of 2026-08-15 (direct user
          -- report "das ist amanda"), has a confirmed real name --
          -- `rom_profiles.lua`'s own `realName` field (see its doc
          -- comment for the evidence) is preferred when present.
          name = c.realName or key,
          room = "secondRoom",
          screenX = c.screenX,
          screenY = c.screenY,
          tileOffsets = tileOffsets,
          dialogue = c.dialogue,
          animation = c.animation,
          framesPerPhase = c.animation and c.animation.framesPerPhase,
        }
      end
    end
  end

  return entries
end

return NpcCatalog
