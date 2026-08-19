-- Decodes a previously-undocumented per-monster/boss "entity
-- definition" table -- bank 4, 24-byte stride, found while chasing the
-- ROM->VRAM sprite-tile-copy pipeline (see `SpriteTileFormula.lua`'s
-- doc comment for the full derivation).
--
-- FOUND BY: disassembling bank4 file `0x1039c`-`0x103cc` (a byte-for-
-- byte duplicate of bank3's `ActorDefinitionTable`-feeding routine at
-- `0xc400`-`0xc449`) and tracing its caller backward
-- (`0x10373`-`0x1039c`, itself entered via `0x102f7`-`0x1030d`, which
-- computes `TABLE_BASE_CPU (0x4739) + A*24` -- `A` being the incoming
-- monster/encounter index -- and stashes the resulting pointer in WRAM
-- `$D438:$D439`, a per-entity "current record" cell, same role as the
-- room-tile pipeline's `$D390:$D391`).
--
-- LIVE-CONFIRMED EVIDENCE this is the right table: `$D438`/`$D439`
-- (this table's own "current record" pointer) reads exactly `$48B9`
-- during a real live encounter (`checkpoints.courtyard_enemy_engaged()`
-- + a short settle) -- resolves via this table's own `fileOffset(BANK,
-- cpuAddr)` formula to file `0x108b9`, exactly row 16. Its
-- `spriteSource` (bytes[8..13], see below) also resolves via
-- `SpriteTileFormula` to all 32 of this project's already-known
-- `enemySprite`/`enemyDescent` tileOffsets, exactly -- two independent
-- confirmations, not one.
--
-- CORRECTED (2026-08-19, direct follow-up: "weiter mit p1"): the
-- earlier claim here ("bytes[+2..+5] get written straight to WRAM
-- $D3F4/$D3F5") was wrong -- disassembling the real write site (bank4
-- file `0x1034d`-`0x10372`) shows a genuine COMPUTATION, not a raw
-- copy: byte[1] of the row (a per-row "HP factor," e.g. `0x02` for row
-- 16) is passed as one operand into `$2B7B` -- a real, recognizable
-- 8x8->16-bit multiply subroutine (classic shift-and-add: `ADD HL,HL` /
-- `RLCA` / conditional `ADD HL,DE`, 8 iterations) -- multiplied by a
-- SECOND factor supplied by the CALLER in `A` (not stored in this table
-- at all), then the 16-bit product is shifted left 4 bits (`x16`)
-- before landing in `$D3F5`(high)/`$D3F4`(low). Live-confirmed for row
-- 16: real HP reads 31 (not the earlier doc's approximate "30") a few
-- frames after contact -- the exact caller-supplied multiplier for
-- this specific encounter was not further isolated this pass.
-- CONCRETE CONSEQUENCE: `hpFieldBytes` below is NOT itself a usable
-- final HP value for any row (including row 16) -- it's one real
-- ingredient of a live formula whose OTHER input isn't in this table.
-- Reading raw bytes off the other 20 rows and comparing them to known
-- species HP would be comparing the wrong quantity -- flagged here so
-- nobody (this project included) repeats that mistake.
--
-- MEASURED EXTENT: a plausibility scan (same method as
-- `ActorDefinitionTable`'s -- does `innerPtr` land in the bank-4 banked
-- window, and is `count` a sane small number?) finds 21 structured rows
-- (0-20); row 21 abruptly breaks into a tight repeating 4-byte pattern
-- (`20 90 01 1a` x3), the same "shape changes completely" signal that
-- closed `ActorDefinitionTable`'s extent. 19 of the 21 rows resolve to
-- bank 11 (the known creature/monster bank); rows 1 and 14 resolve to
-- bank 9 (the NPC/character bank) -- honestly flagged, not
-- re-classified as "not really monsters" without further evidence; this
-- table may hold a couple of named/special characters alongside
-- ordinary monsters, not confirmed either way.
--
-- HONEST SCOPE: this table's row count (21) does not obviously match
-- `EnemySpeciesTable`'s 11 distinct species (that table is a separate,
-- already-decoded combat-stat table, bank4 file `0x10c80`, 8-byte
-- stride -- structurally unrelated, no shared index confirmed). Whether
-- this table is "one row per species" or "one row per
-- encounter/placement" (several rows per species) is not resolved --
-- left as a concrete open question rather than assumed either way.
-- `SpriteTileFormula.resolveTileOffsets` closes the pixel-source half
-- for every one of these 21 rows (individually-decodable tile pixel
-- data, no further live capture needed) -- it does not close the
-- on-screen arrangement half (which tile goes at which screen
-- position): a first attempt at guessing a generic column-count grid
-- for the unconfirmed rows rendered as visibly scrambled (but
-- correctly-decoded) tile blobs, retracted rather than shipped as a
-- real layout. See this table's `SPECIES_HINT` below for the one row
-- (16) whose arrangement is independently known.
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
-- Returns the raw bytes plus `spriteSource` (bytes[8..13], the "outer
-- sprite record" -- see `SpriteTileFormula.lua`'s doc comment) and
-- `hpFieldBytes` (bytes[2..5] -- kept for backward compatibility, but
-- CORRECTED 2026-08-19: this is NOT a raw HP pair. Only byte[1] of the
-- row (not included in this slice -- see `raw:byte(2)`) is the real HP
-- INPUT, fed as one factor into a live multiply (`$2B7B`, real 8x8->16
-- routine) against a second, caller-supplied factor NOT stored in this
-- table, then shifted left 4 bits -- see this file's own top doc
-- comment for the full disassembly. Do not read `hpFieldBytes` as a
-- usable HP value for any row). All other bytes are real ROM data but
-- not decoded -- available only inside `raw`.
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
    -- true when innerPtr does not land in the normal bank-4 banked
    -- window -- would indicate a mis-measured table row; none of the
    -- 21 rows this table's TABLE_COUNT covers hit this.
    anomalous = not inBankedWindow(innerPtr),
  }
end

--- Reads every record across the table's measured extent.
function MonsterDefinitionTable.scanTable(romData)
  local records = {}
  for index = 0, TABLE_COUNT - 1 do
    local record = MonsterDefinitionTable.readRecord(romData, index)
    if record then records[#records + 1] = record end
  end
  return records
end

--- Resolves a record's `spriteSource` into the full, ordered list of
-- ROM file offsets for every raw GFX-tile this entity's sprite actually
-- uses. See `SpriteTileFormula.lua`'s doc comment for the formula and
-- its live validation.
--
-- Direct follow-up (reconstruct the actual monsters with their
-- animation phases, the way species 4 was): also applies
-- `SpriteTileFormula.reconstructCreaturePoseOrder`, chunk by chunk (see
-- that function's doc comment for the checkable per-chunk eligibility
-- test and its honest confidence tier). Returns `(offsets, bank,
-- chunksReordered, chunksTotal)` -- `chunksReordered` is how many of
-- this record's 16-tile chunks (animation poses) got a confident
-- arrangement; `chunksTotal` is how many whole 16-tile chunks exist at
-- all (a trailing remainder under 16 never counts). `chunksReordered ==
-- 0` means nothing could be reordered -- the result is identical to the
-- raw DMA order.
function MonsterDefinitionTable.resolveSpriteTileOffsets(romData, record)
  local SpriteTileFormula = require("src.import.SpriteTileFormula")
  local offsets, bank, rawBytes = SpriteTileFormula.resolveTileOffsets(romData, record.spriteSource, BANK)
  local reordered, chunksReordered, chunksTotal = SpriteTileFormula.reconstructCreaturePoseOrder(rawBytes, offsets)
  return reordered, bank, chunksReordered, chunksTotal
end

--- The one row whose identity and on-screen arrangement are both
-- independently confirmed (see this module's doc comment above for the
-- full live-trace evidence): row 16 is the first-boss/gate-creature,
-- matching `rom_profiles.lua`'s `enemySprite`/`enemyDescent` (a 4x4
-- grid each, back-to-back in this table's 32-tile resolved list --
-- offsets[1..16]=enemySprite's 4x4, [17..32]=enemyDescent's 4x4).
MonsterDefinitionTable.LIVE_CONFIRMED = {
  { index = 16, plausibleEntity = "the real first-boss/gate-creature (rom_profiles.lua's enemySprite + enemyDescent)" },
}

return MonsterDefinitionTable
