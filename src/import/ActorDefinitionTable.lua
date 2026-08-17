-- 2026-08-16, direct continuation of the "NPC-Platzierungstabelle
-- suchen" investigation (user selection, AskUserQuestion) -- a REAL,
-- general ROM table found and decoded to structural certainty behind
-- at least one live, mGBA-traced NPC spawn. This is the FIRST concrete
-- mechanism ever traced for `rom_profiles.lua`'s own long-standing
-- `secondRoom.scene.characterA`/`characterB` doc comment, which has
-- called their placement "PRNG-driven" since before this session with
-- no traced mechanism behind that claim.
--
-- THE REAL CHAIN (live-traced during the willyRoom -> secondRoom
-- scroll; every bank re-confirmed via `core._native.memory
-- .currentBank` at the live PC, never assumed -- see this session's own
-- "bank mislabeling" self-correction, the same pitfall this project has
-- hit and fixed more than once):
--   a proximity/distance-check routine (bank 3, ~$44A0) compares
--   |D-H| / |E-L| against a threshold of 4
--     -> calls `$2B1E`, the ALREADY-KNOWN real combat PRNG (see
--        `docs/reverse-engineering/combat.md`)
--     -> calls a table-lookup helper (bank 3, CPU `$42BD`, file
--        `0xc2bd`) which computes `TABLE_BASE_CPU (0x5f5a) + C*24`
--        (`C` = a caller-supplied index, RNG-influenced)
--     -> reads that table's byte[0] as an allocate "param" and its
--        bytes[8..9] (little-endian) as a SECOND pointer, into a
--        SECOND 24-byte record in the same bank
--     -> calls `$0A74` (the already-known real entity-slot allocator)
--        with A=2 (fixed "type"), C=the table's own param byte
--
-- WHAT THIS IS **NOT**: a simple "one row per room" NPC placement
-- table like `CutTransitionTable.lua`'s landing records. The index fed
-- into this table is computed AT RUNTIME (RNG-influenced), not a
-- static per-room constant baked into any call site -- which is
-- exactly why this project's own repeated static-table searches for
-- "the NPC placement table" (see `docs/reverse-engineering
-- /rom-map.md`, "NPCs" section, "no static ROM table backs NPC
-- placement") never found one: there IS a real table, but you cannot
-- read a row off it per room the way the cut-transition table works.
--
-- LIVE-CONFIRMED INDICES: two real spawn events, captured live via
-- PC-history tracing (60-instruction window, not a static guess),
-- used table indices 99 and 121.
--
-- **UPDATE 2026-08-16, direct continuation ("Tabelle voll ausmessen")**:
-- the table's real extent is now MEASURED, not sampled. A static
-- plausibility scan (does bytes[8..9] land inside the real bank-3
-- banked window, 0x4000-0x7fff?) across every index that fits before
-- the bank ends finds real, structured data through index 217 -- then,
-- at index 218, the byte shape abruptly changes to short repeating
-- 4-byte groups (`24 77 24 77`, `bd bd bd bd`, ...), a visibly
-- different, NOT actor-record-shaped region -- confirming the table
-- really ends at 217 (218 entries total, indices 0-217). WITHIN that
-- range, 5 entries are real but anomalous (bytes[8..9] point into the
-- FIXED bank-0 region, 0x0000-0x3fff, not the swappable bank-3 window
-- every other entry uses): index 0 alone, then a tight cluster at
-- 12/13/14/15 that additionally share near-identical bytes[1..8] and
-- TWO repeated bank-0 pointers (0x2cab for 12-14, 0x2cc3 for 15) --
-- plausibly a small family of reserved/fixed-graphics slots (e.g.
-- always-loaded UI or story-specific actors that don't need the
-- swappable-bank sprite pipeline), not confirmed live. Both
-- live-confirmed indices (99, 121) sit inside the normal, non-anomalous
-- range. See `scanTable` for a full-extent reader.
--
-- THE EMBEDDED SECOND POINTER (bytes[8..9]) resolves to a SECOND real
-- 24-byte block, same bank, whose varying bytes are all small
-- (<=0x6e) -- structurally what OAM hardware sprite tile IDs look
-- like (NOT ROM file offsets, unlike this project's own `tileOffsets`
-- convention used elsewhere in `rom_profiles.lua`). Comparing the two
-- live-captured indices' sub-records byte-for-byte: EVERY varying byte
-- of index 99's sub-record is EXACTLY +0x20 above index 121's own
-- (same byte position), while the structural/separator bytes (0x10,
-- 0x30) stay identical. This is a
-- striking, byte-exact match to this project's OWN independently-
-- confirmed fact -- found via a completely different method, live OAM
-- tile-ID capture, not ROM table decoding -- that secondRoom's
-- characterB uses "a clean +0x20 shift" of characterA's own real OAM
-- tile IDs (see `rom_profiles.lua`'s `secondRoom.scene.characterA` doc
-- comment: "8 per character, a clean +0x20 shift between the two").
-- Two independent methods landing on the exact same "+0x20" number is
-- strong corroboration -- but HONESTLY NOT FULLY CLOSED: this project
-- has not independently re-confirmed, from the live trace itself,
-- WHICH of the two spawn events (index 99 vs. 121) was characterA vs.
-- characterB -- only that the pattern matches structurally. See
-- `LIVE_CONFIRMED` below for the exact, hedged wording.
--
-- Bottom line, matching this session's room-connectivity precedent (a
-- real, general table found and decoded, decisively explaining a
-- long-open mechanism, while the full general "what triggers each
-- entry" question stays open): the *spawn mechanism* is closed, and
-- (2026-08-16 update) the table's real total EXTENT is now measured
-- too (218 records, indices 0-217). What's still open: the *full
-- field semantics* (all 24 bytes of both record types beyond the 2
-- currently-decoded fields) and the exact RNG -> index derivation.

-- SPRITE PIXEL SOURCE FOUND (2026-08-17, direct user instruction
-- "versuche mal über einen ähnlichen hebel wie bei den tiles alle npc,
-- boss und monstersprites zu extrahieren"): every record's own bytes
-- [2..7] are a real "outer sprite record" (`readRecord`'s own
-- `spriteSource` field) feeding a general ROM->VRAM sprite-tile-copy
-- formula -- see `SpriteTileFormula.lua`'s own doc comment for the full
-- disassembly/live-validation. This is a DIFFERENT question from the
-- `spritePointer`/`spriteSubRecord` mechanism above (which OAM slots an
-- entity's sprite occupies on screen) -- this one answers WHICH REAL
-- ROM BYTES fill them. Live-validated exact against characterA/
-- characterB (both all 16 real tiles). `MonsterDefinitionTable.lua` is
-- the sibling table for monsters/bosses (bank 4, a separate 24-byte-
-- stride table, same outer-record shape at a different byte offset).

local ActorDefinitionTable = {}

local BANK = 3
local TABLE_BASE_CPU = 0x5f5a
local RECORD_SIZE = 24

--- 2026-08-16, direct continuation ("Tabelle voll ausmessen"): the
-- table's real extent, measured (not guessed) via a static plausibility
-- scan -- for every index, is bytes[8..9] (LE) a CPU address inside the
-- real bank-3 banked window (0x4000-0x7fff)? Real, structured records
-- run through index 217 (218 entries, 0-217); index 218 onward
-- abruptly changes shape (repeating 4-byte groups like `24 77 24 77`,
-- `bd bd bd bd` -- a visibly different, NOT actor-record-shaped, data
-- region starts exactly there). WITHIN 0-217, 5 entries are real but
-- anomalous: index 0, plus a tight cluster at 12/13/14/15 (near-
-- identical bytes[1..8], 2 repeated bank-0 pointers) -- their own
-- bytes[8..9] point into the FIXED bank-0 region (0x0000-0x3fff,
-- always mapped regardless of the active bank), not the swappable
-- bank-3 window every other real record uses -- plausibly a small
-- reserved/fixed-graphics family, not confirmed live.
-- `TABLE_COUNT` includes all of them (218 total) since they ARE real,
-- structurally present ROM data at the expected stride -- `scanTable`
-- marks each one `anomalous = true` rather than silently treating them
-- like the rest.
local TABLE_COUNT = 218

--- Converts a bank + CPU address (0x4000-0x7fff, banked ROM window) to
-- a flat ROM file offset. Same formula this project already uses
-- throughout its other bank-relative table readers.
local function fileOffset(bank, cpuAddr)
  return bank * 0x4000 + (cpuAddr - 0x4000)
end
ActorDefinitionTable.fileOffset = fileOffset
ActorDefinitionTable.TABLE_COUNT = TABLE_COUNT

--- True when `cpuAddr` falls inside the real, swappable bank-3 ROM
-- window (0x4000-0x7fff) -- the same plausibility test used to measure
-- the table's own real extent (see `TABLE_COUNT`'s doc comment above).
local function inBankedWindow(cpuAddr)
  return cpuAddr >= 0x4000 and cpuAddr <= 0x7fff
end

--- Reads the raw 24-byte outer record at table index `index` (0-based).
-- Returns the raw bytes plus the currently-understood fields:
-- `allocParam` (byte[0], passed as `C` into the real `$0A74` entity
-- allocator), `spritePointer` (bytes[8..9], little-endian CPU address
-- of the record's own OAM-arrangement sub-record, same bank -- WHICH
-- on-screen tile slots this entity uses, see `readSpriteSubRecord`),
-- and `spriteSource` (bytes[2..7], the real ROM->VRAM sprite-tile
-- SOURCE formula's own "outer record" -- WHICH raw ROM pixel bytes fill
-- them, see `SpriteTileFormula.lua`'s own doc comment for the full
-- derivation and live-validation). All other bytes are real ROM data
-- but NOT decoded -- available only inside `raw`, honestly left
-- uninterpreted rather than guessed at.
function ActorDefinitionTable.readRecord(romData, index)
  local off = fileOffset(BANK, TABLE_BASE_CPU) + index * RECORD_SIZE
  local raw = romData:sub(off + 1, off + RECORD_SIZE)
  if #raw < RECORD_SIZE then return nil end
  local lo, hi = raw:byte(9), raw:byte(10)
  local spritePointer = lo + hi * 256
  return {
    index = index,
    fileOffset = off,
    raw = raw,
    allocParam = raw:byte(1),
    spritePointer = spritePointer,
    -- true when spritePointer does NOT land in the normal bank-3
    -- banked window -- real, but structurally different from every
    -- other record (see `TABLE_COUNT`'s doc comment; index 0 is the
    -- one currently-known case).
    anomalous = not inBankedWindow(spritePointer),
    -- Real "outer sprite record" (2026-08-17, see SpriteTileFormula.lua)
    -- -- bytes[2..7] of this SAME 24-byte row, not a separate pointer
    -- chase. Live-validated exactly against BOTH characterA (index 121)
    -- and characterB (index 99)'s own already-known real tileOffsets,
    -- all 16 tiles each.
    spriteSource = {
      dest0 = raw:byte(3),
      count = raw:byte(4),
      cByte = raw:byte(5),
      kindByte = raw:byte(6),
      innerPtr = raw:byte(7) + raw:byte(8) * 256,
      bank = 8 + math.floor(raw:byte(6) / 64),
      -- Real, live-corroborated "family" membership (2026-08-17, see
      -- SpriteTileFormula.lua's own `HUMANOID_4POSE_INNER_PTR` doc
      -- comment): true when this record shares the exact same
      -- `innerPtr` as characterA/characterB AND its own `count` is
      -- even (so its raw tiles divide cleanly into 4-tile pose groups)
      -- -- 172 of 218 records qualify (190 share the innerPtr, 18 of
      -- those have an odd count=1 and are excluded), 91 of them with a
      -- DISTINCT `kindByte` (a genuinely different real NPC design, not
      -- a repeat placement of an already-known one).
      arrangementFamily = (raw:byte(7) + raw:byte(8) * 256 == 0x7B5A and raw:byte(4) % 2 == 0)
        and "humanoid4pose" or nil,
    },
  }
end

--- Resolves a record's own `spriteSource` (see `readRecord`) into the
-- full, ordered list of real ROM file offsets for every raw GFX-tile
-- this entity's sprite actually uses -- no live OAM capture needed,
-- see `SpriteTileFormula.lua`'s own doc comment for the formula and its
-- live validation. `tableBank` defaults to this module's own `BANK`
-- (3) since the outer record's `innerPtr` is a same-bank pointer.
-- When `record.spriteSource.arrangementFamily == "humanoid4pose"`, the
-- result is ALREADY reordered into the real on-screen pose order (see
-- `SpriteTileFormula.reconstructPoseOrder`'s own doc comment) -- callers
-- don't need to reorder it themselves.
function ActorDefinitionTable.resolveSpriteTileOffsets(romData, record)
  local SpriteTileFormula = require("src.import.SpriteTileFormula")
  local offsets, bank = SpriteTileFormula.resolveTileOffsets(romData, record.spriteSource, BANK)
  if record.spriteSource.arrangementFamily == "humanoid4pose" then
    offsets = SpriteTileFormula.reconstructPoseOrder(offsets)
  end
  return offsets, bank
end

--- Reads every real record across the table's own measured extent
-- (`TABLE_COUNT`, indices 0..TABLE_COUNT-1). Each entry additionally
-- carries `spriteSubRecord` (via `readSpriteSubRecord`) when its own
-- `spritePointer` is plausible (skipped, left nil, for anomalous
-- records -- following an out-of-window pointer with the same-bank
-- formula would silently read the wrong bank's bytes).
function ActorDefinitionTable.scanTable(romData)
  local records = {}
  for index = 0, TABLE_COUNT - 1 do
    local record = ActorDefinitionTable.readRecord(romData, index)
    if record then
      if not record.anomalous then
        record.spriteSubRecord = ActorDefinitionTable.readSpriteSubRecord(romData, record)
      end
      records[#records + 1] = record
    end
  end
  return records
end

--- Follows a record's own `spritePointer` to its real sprite sub-
-- record (same bank, same 24-byte stride convention). Returns raw
-- bytes only -- see this module's own doc comment above for what's
-- understood about their shape (small, <=0x6e tile-ID-like varying
-- bytes, separated by fixed 0x10/0x30 structural bytes) and what's
-- still open.
function ActorDefinitionTable.readSpriteSubRecord(romData, record)
  local off = fileOffset(BANK, record.spritePointer)
  local raw = romData:sub(off + 1, off + RECORD_SIZE)
  if #raw < RECORD_SIZE then return nil end
  return { fileOffset = off, raw = raw }
end

--- The two real spawn events captured live this session (2026-08-16)
-- via mGBA watchpoint + PC-history tracing during the willyRoom ->
-- secondRoom scroll. `plausibleCharacter` is a REASONED, NOT
-- independently re-verified, assignment (see this module's own doc
-- comment above for exactly what is and isn't confirmed).
ActorDefinitionTable.LIVE_CONFIRMED = {
  { index = 121, plausibleCharacter = "secondRoom.scene.characterA (lower sub-record tile bytes)" },
  { index = 99, plausibleCharacter = "secondRoom.scene.characterB / Amanda (sub-record tile bytes are index 121's own +0x20, matching the independently-confirmed real OAM tile-ID shift)" },
}

return ActorDefinitionTable
