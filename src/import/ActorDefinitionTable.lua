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
-- used table indices 99 and 121. Sampling the surrounding index range
-- (0-9, 95-124, 160-174, direct ROM reads) confirms the table is real
-- and structurally regular across at least ~175 entries; indices 0-9
-- look like a DIFFERENT record family (a near-constant embedded
-- pointer across all of them, unlike 95+) and are honestly left
-- uninterpreted -- may not be NPC-relevant at all.
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
-- entry" question stays open): the *spawn mechanism* is closed, the
-- *full table semantics* (all 24 bytes of both record types, the exact
-- RNG -> index derivation, and the table's real total extent) are not.

local ActorDefinitionTable = {}

local BANK = 3
local TABLE_BASE_CPU = 0x5f5a
local RECORD_SIZE = 24

--- Converts a bank + CPU address (0x4000-0x7fff, banked ROM window) to
-- a flat ROM file offset. Same formula this project already uses
-- throughout its other bank-relative table readers.
local function fileOffset(bank, cpuAddr)
  return bank * 0x4000 + (cpuAddr - 0x4000)
end
ActorDefinitionTable.fileOffset = fileOffset

--- Reads the raw 24-byte outer record at table index `index` (0-based).
-- Returns the raw bytes plus the two currently-understood fields:
-- `allocParam` (byte[0], passed as `C` into the real `$0A74` entity
-- allocator) and `spritePointer` (bytes[8..9], little-endian CPU
-- address of the record's own sprite sub-record, same bank). All other
-- bytes are real ROM data but NOT decoded -- available only inside
-- `raw`, honestly left uninterpreted rather than guessed at.
function ActorDefinitionTable.readRecord(romData, index)
  local off = fileOffset(BANK, TABLE_BASE_CPU) + index * RECORD_SIZE
  local raw = romData:sub(off + 1, off + RECORD_SIZE)
  if #raw < RECORD_SIZE then return nil end
  local lo, hi = raw:byte(9), raw:byte(10)
  return {
    index = index,
    fileOffset = off,
    raw = raw,
    allocParam = raw:byte(1),
    spritePointer = lo + hi * 256,
  }
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
