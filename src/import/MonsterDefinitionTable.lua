-- Decodes a real, previously-undocumented per-monster/boss "entity
-- definition" table -- bank 4, 24-byte stride, found 2026-08-17 while
-- chasing the real ROM->VRAM sprite-tile-copy pipeline (see
-- `SpriteTileFormula.lua`'s own doc comment for the full derivation).
--
-- FOUND BY: disassembling bank4 file `0x1039c`-`0x103cc` (a byte-for-
-- byte duplicate of bank3's own `ActorDefinitionTable`-feeding routine
-- at `0xc400`-`0xc449`) and tracing its own caller backward
-- (`0x10373`-`0x1039c`, itself entered via `0x102f7`-`0x1030d`, which
-- computes `TABLE_BASE_CPU (0x4739) + A*24` -- `A` being the incoming
-- monster/encounter index -- and stashes the resulting pointer in real
-- WRAM `$D438:$D439`, a per-entity "current record" cell, same role as
-- the room-tile pipeline's own `$D390:$D391`).
--
-- REAL, LIVE-CONFIRMED EVIDENCE this is the right table: bytes[+2..+5]
-- of this SAME 24-byte row get written straight to real WRAM
-- `$D3F4`/`$D3F5` (bank4 file `0x1036a`-`0x1036e`, `LD (0xd3f5),A` /
-- `LD (0xd3f4),A`) -- and `$D3F4`/`$D3F5` is THIS PROJECT'S OWN already-
-- documented real HP-populate location (`checkpoints.courtyard_
-- enemy_engaged`'s own doc comment: "real HP=30 populated at
-- $D3F4/$D3F5"). Directly single-stepped the real first-boss encounter
-- (`reach_room.reach_first_room()`, no further input) and confirmed:
-- row 16 (file `0x108b9`) is byte-for-byte the record active at that
-- exact moment, AND its own `spriteSource` (bytes[8..13], see below)
-- resolves via `SpriteTileFormula` to all 32 of this project's own
-- already-known real `enemySprite`/`enemyDescent` tileOffsets, exactly.
--
-- REAL, MEASURED EXTENT: a plausibility scan (same method as
-- `ActorDefinitionTable`'s own -- does `innerPtr` land in the real
-- bank-4 banked window, and is `count` a sane small number?) finds 21
-- real, structured rows (0-20); row 21 abruptly breaks into a tight
-- repeating 4-byte pattern (`20 90 01 1a` x3), the same "shape changes
-- completely" signal that closed `ActorDefinitionTable`'s own extent.
-- 19 of the 21 rows resolve to bank 11 (the known creature/monster
-- bank); rows 1 and 14 resolve to bank 9 (the NPC/character bank) --
-- honestly flagged, NOT re-classified as "not really monsters" without
-- further evidence; this table may hold a couple of named/special
-- characters alongside ordinary monsters, not confirmed either way.
--
-- HONEST SCOPE: this table's own row COUNT (21) does not obviously
-- match `EnemySpeciesTable`'s own 11 distinct species (that table is a
-- separate, already-decoded combat-stat table, bank4 file `0x10c80`,
-- 8-byte stride -- structurally unrelated, no shared index confirmed).
-- Whether this table is "one row per species" or "one row per
-- encounter/placement" (several rows per species) is NOT resolved --
-- left as a real, concrete open question rather than assumed either
-- way. `SpriteTileFormula.resolveTileOffsets` closes the PIXEL-SOURCE
-- half for every one of these 21 rows (real, individually-decodable
-- tile pixel data, no further live capture needed) -- it does NOT close
-- the on-screen ARRANGEMENT half (which tile goes at which screen
-- position): a first attempt at guessing a generic column-count grid
-- for the un-confirmed rows rendered as visibly scrambled (but
-- correctly-decoded) tile blobs, retracted rather than shipped as a
-- real layout. See this table's own `SPECIES_HINT` below for the one
-- row (16) whose real arrangement IS independently known.
--
-- Pure Lua, no love.* calls, same convention as ActorDefinitionTable.

local MonsterDefinitionTable = {}

local BANK = 4
local TABLE_BASE_CPU = 0x4739
local RECORD_SIZE = 24
local TABLE_COUNT = 21

local function fileOffset(bank, cpuAddr)
  return bank * 0x4000 + (cpuAddr - 0x4000)
end
MonsterDefinitionTable.fileOffset = fileOffset
MonsterDefinitionTable.TABLE_COUNT = TABLE_COUNT
MonsterDefinitionTable.BANK = BANK

local function inBankedWindow(cpuAddr)
  return cpuAddr >= 0x4000 and cpuAddr <= 0x7fff
end

--- Reads the raw 24-byte record at table index `index` (0-based).
-- Returns the raw bytes plus `spriteSource` (bytes[8..13], the real
-- "outer sprite record" -- see `SpriteTileFormula.lua`'s own doc
-- comment) and `hpFieldBytes` (bytes[2..5], live-confirmed written to
-- real WRAM `$D3F4`/`$D3F5` -- only the first 2 of these 4 bytes are
-- independently confirmed as the real HP pair; the other 2 are real
-- ROM data, NOT yet independently interpreted). All other bytes are
-- real ROM data but NOT decoded -- available only inside `raw`.
function MonsterDefinitionTable.readRecord(romData, index)
  local off = fileOffset(BANK, TABLE_BASE_CPU) + index * RECORD_SIZE
  local raw = romData:sub(off + 1, off + RECORD_SIZE)
  if #raw < RECORD_SIZE then return nil end
  local kindByte = raw:byte(12)
  local innerPtr = raw:byte(13) + raw:byte(14) * 256
  return {
    index = index,
    fileOffset = off,
    raw = raw,
    hpFieldBytes = raw:sub(3, 6),
    spriteSource = {
      dest0 = raw:byte(9),
      count = raw:byte(10),
      cByte = raw:byte(11),
      kindByte = kindByte,
      innerPtr = innerPtr,
      bank = 8 + math.floor(kindByte / 64),
    },
    -- true when innerPtr does NOT land in the normal bank-4 banked
    -- window -- would indicate a mis-measured table row; none of the
    -- real 21 rows this table's own TABLE_COUNT covers hit this.
    anomalous = not inBankedWindow(innerPtr),
  }
end

--- Reads every real record across the table's own measured extent.
function MonsterDefinitionTable.scanTable(romData)
  local records = {}
  for index = 0, TABLE_COUNT - 1 do
    local record = MonsterDefinitionTable.readRecord(romData, index)
    if record then records[#records + 1] = record end
  end
  return records
end

--- Resolves a record's own `spriteSource` into the full, ordered list
-- of real ROM file offsets for every raw GFX-tile this entity's sprite
-- actually uses. See `SpriteTileFormula.lua`'s own doc comment for the
-- formula and its live validation.
function MonsterDefinitionTable.resolveSpriteTileOffsets(romData, record)
  local SpriteTileFormula = require("src.import.SpriteTileFormula")
  return SpriteTileFormula.resolveTileOffsets(romData, record.spriteSource, BANK)
end

--- The one row whose real identity AND on-screen arrangement are BOTH
-- independently confirmed (see this module's own doc comment above for
-- the full live-trace evidence): row 16 is the real first-boss/gate-
-- creature, matching `rom_profiles.lua`'s own `enemySprite`/
-- `enemyDescent` (a 4x4 grid each, back-to-back in this table's own
-- 32-tile resolved list -- offsets[1..16]=enemySprite's own 4x4,
-- [17..32]=enemyDescent's own 4x4).
MonsterDefinitionTable.LIVE_CONFIRMED = {
  { index = 16, plausibleEntity = "the real first-boss/gate-creature (rom_profiles.lua's enemySprite + enemyDescent)" },
}

return MonsterDefinitionTable
