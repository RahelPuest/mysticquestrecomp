-- The ROM->VRAM sprite-tile SOURCE formula, found by directly
-- generalizing the METHOD (not the specific WRAM cell) that closed the
-- room-tile pipeline earlier this project: instead of a per-room WRAM
-- base pointer ($D390:$D391), sprites use a per-record constant baked
-- directly into a previously-undocumented "entity definition" record --
-- no WRAM roundtrip needed, the base is right there in the ROM table.
--
-- THE DISPATCH ROUTINE (found via static disassembly, `disasm.py`, of
-- the already-known "kind byte -> bank 8-11" mechanism from an earlier
-- access-analysis pass, see rom-map.md's "Task #160" entry -- that pass
-- found the mechanism but explicitly left "which candidate region
-- belongs to which species/NPC" open; this closes it): two
-- byte-for-byte identical routines, bank3 file `0xc400`-`0xc449` and
-- bank4 file `0x1039c`-`0x103cc` (both reached by falling through from
-- their own bank's "process one entity-definition record" routine,
-- bank3 `0xc3dc`, bank4 `0x10373`/`0x10340`). Each walks a fixed-size
-- "outer sprite record" (6 bytes: `dest0, count, C, kindByte,
-- innerPtrLo, innerPtrHi`) embedded directly inside a bigger per-entity
-- definition row (see `ActorDefinitionTable.lua` for NPCs -- outer
-- record = that table's bytes[2..7] -- and `MonsterDefinitionTable.lua`
-- for monsters/bosses -- outer record = that table's bytes[8..13]). For
-- `count*2` raw bytes read sequentially from `innerPtr` (a same-bank
-- CPU pointer to a small, per-entity list of raw GFX-tile indices --
-- not literally 0,1,2,... for every entity, though several do use that
-- simple sequence):
--   sourceCpuAddr = (rawByte*16 + (kindByte*256 + C)) mod 0x10000,
--     then its high byte gets `RES 7,H` / `SET 6,H` applied
--     unconditionally (clears bit7, forces bit6 -- an unconditional
--     variant of the room-tile pipeline's own conditional bit7/bit6
--     fixup, cheaper because sprite source addresses apparently never
--     need the room-tile formula's "wrap to the other half" case)
--   bank = 8 + floor(kindByte / 64)   -- i.e. kindByte's top 2 bits
--     select one of exactly 4 graphics banks (8/9/10/11), the same 4
--     banks an earlier access-analysis pass already found
--   realFileOffset = bank*0x4000 + (sourceCpuAddr - 0x4000)
-- Then `A=bank, HL=sourceCpuAddr, DE=destVramAddr, CALL $2df5` -- the
-- same generic tile-streaming DMA entry the room-tile pipeline's
-- `$2DF5`/`$2D57` disassembly already fully documented (rom-map.md's
-- "Task #160" entry) -- sprites and room tiles share one ROM->VRAM
-- graphics subsystem, this was simply the other caller of it.
--
-- LIVE-VALIDATED, THREE INDEPENDENT WAYS, ALL EXACT
-- (`trace_npc_sprite_dispatch2.py`/`trace_monster_sprite_dispatch2.py`,
-- scratchpad -- single-stepped the CPU through the secondRoom-NPC-spawn
-- window and the first-boss-spawn window, watching every `CALL
-- 0x2df5`, reading A/HL/DE/BC live at that exact moment):
--   1. secondRoom.scene.characterA: kindByte=0x51, C=0x00 -- all 16 of
--      this project's already-live-captured tileOffsets (0x25100-
--      0x251f0) reproduced exactly, as a SET (rawByte runs
--      0,2,1,3,4,6,5,7,... -- a live-confirmed "swapped pairs" copy
--      order, not plain 0,1,2,3 -- a different ordering from
--      rom_profiles.lua's `animation` table, which groups tiles by
--      final logical pose/on-screen arrangement, not raw DMA order;
--      see `sprite_tile_formula_test.lua`'s `assertSameOffsetSet`).
--   2. secondRoom.scene.characterB: kindByte=0x55, C=0x00 -- all 16 of
--      this project's already-live-captured tileOffsets (0x25500-
--      0x255f0) reproduced exactly, same way. (The already-
--      independently-known "characterB's tiles are a clean +0x20 shift
--      of characterA's" finding is now explained: it's simply kindByte
--      0x51 -> 0x55, a +4 shift in the record's kindByte field, which
--      is a +0x400 shift in `base`, i.e. +0x40 tiles * 16 bytes... the
--      on-screen OAM-tile-ID +0x20 shift is a different, destination-
--      side fact -- both real, just describing different halves of the
--      same pipeline.)
--   3. The first-boss/gate-creature: kindByte=0xFE, C=0x00 -- all 32 of
--      this project's already-live-captured tileOffsets (`enemySprite`
--      0x2FE00-0x2FEF0 and `enemyDescent` 0x2FF00-0x2FFF0, both sets,
--      one continuous 32-tile DMA burst) reproduced exactly.
-- Three ground truths, found via three completely different original
-- methods (live OAM tile-ID capture + exact-16-byte ROM search, twice,
-- for the NPCs; live OAM capture + the room-tile pipeline's bank-11
-- sweep, for the boss), all exactly reproduced by this one formula.
-- This is the same standard of evidence the room-tile pipeline fix used
-- (exact match against willyRoom's independently-known pixel).
--
-- HONEST SCOPE: this closes the source half of sprite extraction --
-- given any entity's outer-record fields, its ROM pixel data is now
-- computable, no live OAM capture needed. It does not (yet) close the
-- arrangement half -- which on-screen position/OAM slot each resolved
-- tile occupies for entities other than the 3 ground-truth ones above.
-- A first attempt at guessing a generic "N columns" grid for the new
-- monster-table entries rendered as visibly scrambled blobs (correctly-
-- decoded tile pixels, wrong 2D placement) -- retracted rather than
-- shipped; each entity's per-tile screen position is a separate,
-- still-open question (rom_profiles.lua's `enemySprite`/`characterA`
-- entries hand-document the specific arrangements already
-- independently confirmed via live OAM capture).

local bit = require("bit")

local SpriteTileFormula = {}

--- Resolves ONE raw GFX-tile index byte to its real ROM file offset,
-- given the entity's own outer-record `kindByte`/`C` fields (see this
-- module's own doc comment above for where those come from).
function SpriteTileFormula.resolveFileOffset(rawByte, kindByte, cByte)
  local base = bit.bor(bit.lshift(kindByte, 8), cByte)
  local srcCpu = bit.band(rawByte * 16 + base, 0xFFFF)
  local hi = bit.band(bit.rshift(srcCpu, 8), 0xFF)
  local lo = bit.band(srcCpu, 0xFF)
  -- RES 7,H / SET 6,H -- unconditional: clear bit7, force bit6 set.
  local hiFixed = bit.bor(bit.band(hi, 0x7F), 0x40)
  local fixedAddr = bit.bor(bit.lshift(hiFixed, 8), lo)
  local bank = 8 + bit.rshift(kindByte, 6)
  return bank * 0x4000 + (fixedAddr - 0x4000), bank
end

--- Resolves a whole real "outer sprite record" (see doc comment above --
-- `{dest0, count, cByte, kindByte, innerPtr}`) plus the ROM bytes into
-- the full ordered list of real file offsets, one per raw GFX-tile
-- index read from `innerPtr` (same-bank CPU pointer, `count*2` bytes).
-- `tableBank` is which bank the outer record itself (and therefore its
-- own `innerPtr` list) lives in -- 4 for `MonsterDefinitionTable`, 3
-- for `ActorDefinitionTable` (see each module's own `BANK` constant).
-- Third return value is the raw GFX-tile index bytes themselves (same
-- length/order as `offsets`) -- needed by `reconstructCreaturePoseOrder`
-- to detect which chunks are safe to reorder.
function SpriteTileFormula.resolveTileOffsets(romData, outerRecord, tableBank)
  local innerPtr = outerRecord.innerPtr
  local listOff = tableBank * 0x4000 + (innerPtr - 0x4000)
  local rawBytes = romData:sub(listOff + 1, listOff + outerRecord.count * 2)
  local offsets = {}
  local spriteBank
  for i = 1, #rawBytes do
    local rawByte = rawBytes:byte(i)
    local fileOffset, bank = SpriteTileFormula.resolveFileOffset(rawByte, outerRecord.kindByte, outerRecord.cByte)
    offsets[i] = fileOffset
    spriteBank = bank
  end
  return offsets, spriteBank, rawBytes
end

-- REAL ON-SCREEN POSE ARRANGEMENT, found 2026-08-17, direct follow-up
-- to the pixel-source formula above (direct user instruction "du
-- sollst mehr npcs suchen"): `ActorDefinitionTable`'s own 218 NPC
-- records are NOT all one-off -- 190 of them share the EXACT SAME
-- `innerPtr` (0x7B5A, same bank), meaning they all read raw GFX-tile
-- indices from the identical shared list, just through a different
-- `kindByte` (a different real pixel pool -- a different visual
-- design). Of those 190, 172 have an even `count` (their raw tiles
-- divide cleanly into 4-tile pose groups -- see the reordering logic
-- below); the other 18 have `count=1` (a single 2-tile icon, no pose
-- structure to speak of) and are left out of the family. Across the
-- 172, there are 91 DISTINCT `kindByte` values -- i.e. 91 real,
-- individually different NPC sprite designs, not just 91 placements of
-- the same 2 already-known ones.
--
-- The shared list itself reads `0,2,1,3, 4,6,5,7, 8,10,9,11, ...` --
-- NOT plain sequential order -- a real, live-confirmed "swapped middle
-- pair" pattern PER 4-TILE GROUP. Comparing this raw order against
-- characterA's/characterB's own already-independently-known real
-- on-screen pose grouping (`rom_profiles.lua`'s own `down`/`up`/`left`
-- animation table, each a real 4-tile pose) found the exact
-- correspondence: raw-order position [a,b,c,d] within each group of 4
-- is on-screen position [a,c,b,d] -- i.e. swap the middle two. Applying
-- this SAME swap to a sample of brand-new `kindByte` values (never
-- independently live-captured) rendered coherent, clearly humanoid,
-- individually DISTINCT sprite sheets (4 real poses: down/up/left-
-- frame1/left-frame2) -- see events.md's own dated entry for the
-- rendered examples -- confirming the reconstruction generalizes across
-- the whole shared-`innerPtr` family, not just the 2 already-known
-- members.
--
-- HONEST CONFIDENCE TIER: this is FAMILY-level evidence (2 independent
-- live ground truths + a consistent, coherent visual result across a
-- sample of the other 89), NOT an individual live OAM capture for each
-- of the 91 -- kept as a clearly separate, weaker confidence tier from
-- `arrangementConfirmed` (characterA/characterB only) wherever this
-- project's own data distinguishes the two (see `ActorDefinitionTable
-- .lua`'s own `spriteSource.arrangementFamily` field and rom-inspector's
-- own "Anordnung bestätigt" vs. "Anordnung wahrscheinlich (Familie)"
-- badges). Only applies to records whose own `count` is even (so raw
-- tiles divide evenly into groups of 4) -- 18 of the 190 have
-- `count=1` (a single 2-tile icon, no pose structure to reorder) and
-- are left in raw order, honestly unclassified.
SpriteTileFormula.HUMANOID_4POSE_INNER_PTR = 0x7B5A

--- Reorders a flat, raw-DMA-order tile-offset list (see
-- `resolveTileOffsets`) into the real on-screen pose order -- swaps the
-- middle two entries of every 4-tile group, a no-op for any trailing
-- group smaller than 4. See this module's own doc comment above for the
-- live evidence this reordering is correct.
function SpriteTileFormula.reconstructPoseOrder(offsets)
  local reordered = {}
  local n = #offsets
  local i = 1
  while i <= n do
    local groupLen = math.min(4, n - i + 1)
    if groupLen == 4 then
      reordered[#reordered + 1] = offsets[i]
      reordered[#reordered + 1] = offsets[i + 2]
      reordered[#reordered + 1] = offsets[i + 1]
      reordered[#reordered + 1] = offsets[i + 3]
    else
      for k = 0, groupLen - 1 do reordered[#reordered + 1] = offsets[i + k] end
    end
    i = i + groupLen
  end
  return reordered
end

-- REAL MONSTER/BOSS POSE ARRANGEMENT, found 2026-08-17, direct follow-up
-- (direct user instruction: "versuche daraus die tatsächlichen monster
-- mit den animationsphasen zu rekonstruieren wie du es bei spezies 4
-- gemacht hast" -- reconstruct the actual monsters with their
-- animation phases from the tilesets, the way species 4 already was).
--
-- Species 4 (`MonsterDefinitionTable` row 16, the real first-boss/gate-
-- creature) is the ONE monster this project has independently live-
-- verified, both its real pixel source AND its real on-screen 4x4
-- arrangement (`rom_profiles.lua`'s own `enemySprite`/`enemyDescent`,
-- found via live OAM tracing well before this session). Deriving the
-- exact raw-DMA-order -> real-4x4-position permutation from that ONE
-- ground truth (comparing `resolveSpriteTileOffsets`'s own raw-order
-- output against `enemySprite.tileOffsets`/`enemyDescent.tileOffsets`'s
-- own already-known real order, `derive_creature_perm.lua`, scratchpad)
-- found a clean, regular 16-tile permutation:
--   raw position ->  real on-screen position (1-based, within one
--   16-tile pose):
--     1->1, 3->2, 9->3, 11->4, 2->5, 4->6, 10->7, 12->8,
--     5->9, 7->10, 13->11, 15->12, 6->13, 8->14, 14->15, 16->16
-- (equivalently: real position i is fed by raw position
-- CREATURE_4X4_POSE_PERMUTATION[i]). This is a DIFFERENT, more complex
-- permutation than the NPC family's own simple "swap the middle two"
-- rule -- consistent with `rom_profiles.lua`'s own doc comment on
-- `enemySprite`, which describes a genuinely more complex 4-column,
-- 2-OAM-row hardware layout for this creature than the NPCs' simple
-- 16x16 2-column block.
--
-- HONEST CONFIDENCE, WEAKER than the NPC family tier: this rests on
-- exactly ONE independently live-verified ground truth (not two), so
-- it is applied ONLY where a 16-raw-tile CHUNK's own relative byte
-- pattern (`0,2,1,3,4,6,5,7,8,10,9,11,12,14,13,15` relative to its own
-- first byte) is a byte-for-byte match to species 4's own real chunks
-- -- a real, checkable structural fact, not a guess -- and left in raw
-- DMA order for any chunk (or trailing remainder shorter than 16) that
-- doesn't match. A per-record scan (`detect_eligible_chunks.lua`,
-- scratchpad) found most of the 21 monster/boss records have AT LEAST
-- one matching chunk; several (rows 2, 3, 5, 7, 12, 16, 19) have EVERY
-- chunk matching -- those are the strongest candidates. Rendered a
-- sample of newly-reconstructed rows and confirmed coherent, distinct,
-- creature-shaped sprites (not scrambled blobs) -- see events.md's own
-- dated entry for the rendered examples.
SpriteTileFormula.CREATURE_4X4_POSE_PERMUTATION = { 1, 3, 9, 11, 2, 4, 10, 12, 5, 7, 13, 15, 6, 8, 14, 16 }

--- True when `rawByteChunk` (a 16-entry array of raw GFX-tile index
-- bytes) matches species 4's own real relative byte pattern -- i.e. is
-- a real "4x4 creature pose" chunk, safe to reorder with
-- `CREATURE_4X4_POSE_PERMUTATION`.
local CREATURE_4X4_REF_SHAPE = { 0, 2, 1, 3, 4, 6, 5, 7, 8, 10, 9, 11, 12, 14, 13, 15 }
function SpriteTileFormula.matchesCreature4x4Shape(rawByteChunk)
  if #rawByteChunk ~= 16 then return false end
  local base = rawByteChunk[1]
  for i = 1, 16 do
    if bit.band(rawByteChunk[i] - base, 0xFF) ~= CREATURE_4X4_REF_SHAPE[i] then return false end
  end
  return true
end

--- Reorders a flat, raw-DMA-order tile-offset list into the real
-- on-screen 4x4 pose order, chunk by chunk (16 tiles per chunk) --
-- ONLY for chunks whose own raw GFX-tile bytes (`rawBytes`, a Lua
-- string, same length as `offsets`) match `matchesCreature4x4Shape`;
-- every other chunk (and any trailing remainder under 16) is left in
-- raw DMA order, honestly unreconstructed. Returns the reordered
-- offsets plus `chunksReordered`/`chunksTotal` (whole 16-tile chunks
-- only -- a trailing remainder never counts as a "total" chunk) so
-- callers can show an honest per-record confidence, not a single
-- blanket claim.
function SpriteTileFormula.reconstructCreaturePoseOrder(rawBytes, offsets)
  local reordered = {}
  local chunksReordered, chunksTotal = 0, 0
  local n = #offsets
  local i = 1
  while i <= n do
    local chunkLen = math.min(16, n - i + 1)
    if chunkLen == 16 then
      chunksTotal = chunksTotal + 1
      local chunk = {}
      for k = 1, 16 do chunk[k] = rawBytes:byte(i + k - 1) end
      if SpriteTileFormula.matchesCreature4x4Shape(chunk) then
        chunksReordered = chunksReordered + 1
        for outPos = 1, 16 do
          reordered[#reordered + 1] = offsets[i + SpriteTileFormula.CREATURE_4X4_POSE_PERMUTATION[outPos] - 1]
        end
      else
        for k = 0, 15 do reordered[#reordered + 1] = offsets[i + k] end
      end
    else
      for k = 0, chunkLen - 1 do reordered[#reordered + 1] = offsets[i + k] end
    end
    i = i + chunkLen
  end
  return reordered, chunksReordered, chunksTotal
end

return SpriteTileFormula
