-- Decodes the real, general "cut-transition landing record" format
-- found 2026-08-16 (direct user instruction: "then do those blockers.
-- dont stop before they are solved. if one strategy does not work try
-- another one" -- tackling the two long-standing genuinely-open
-- blockers this project's own "Consolidated reference" section
-- (rom-map.md) named: room connectivity and player spawn/landing
-- position).
--
-- REAL, LIVE-CONFIRMED BACKGROUND (2026-08-14 session, see
-- `TileLandingPosition.lua`'s own doc comment for the full byte-exact
-- chain): a real bank-0 handler (`$11B7`, registered as primary
-- opcode `0xF4`) reads 2 literal bytes from a script cursor into `B`/
-- `C`, which flow through `$44A5` (tile-to-pixel: `pixelX=(B+1)*8,
-- pixelY=(C+2)*8`) and `$0611` (the real per-tick entity position-
-- commit routine, same one ordinary movement uses) to set the
-- player's own landing position after a "wipe-style" cut transition.
-- That session found the REAL ROM address for exactly 2 real
-- transitions by live mGBA tracing, one at a time, and left "which
-- real ROM address holds the literal tile-coordinate bytes for every
-- OTHER room transition" as an open, unautomated question.
--
-- NEW THIS PASS (2026-08-16): found the real, GENERAL record shape
-- these bytes live inside, via a live watchpoint on WRAM `$C244`/
-- `$C245` (the very write literal-address static search had already
-- tried and failed to find, since the real write is INDIRECT --
-- `LD (HL),D` / `LD (HL),E` -- not a literal `LD (nn),A`, exactly the
-- blind spot a byte-pattern grep can never cover but a live hardware
-- watchpoint always does regardless of addressing mode) followed all
-- the way back through the real call chain: `$0659`/`$065B` (the
-- write itself) <- `$4992` (`$0611`'s own caller) <- `$1ED7` selector
-- `0x03` (`$498E`) <- `$1ED7` selector `0x0F` (`$4130`, the real
-- `$D499`-indexed cut-transition STATE MACHINE, table base file/CPU
-- `0x413C`) <- the real opcode `0xF4`/`$11B7` handler itself (already
-- known).
--
-- Static-searching the ROM for the exact byte shape surrounding BOTH
-- already-known real examples found a real, general, REPEATING 9-byte
-- record BODY:
--
--   00 05 F4 <A1> <A2> <tileCol> <tileRow> 00 0B
--
-- (the byte immediately BEFORE this body varies -- `0xC9`/RET 173
-- times, `0xC1`/POP BC 11 times, `0x77`/LD (HL),A 2 times, 186 total
-- -- real, ordinary bytes belonging to whatever PRECEDING instruction/
-- record happens to end there, not part of this record's own fixed
-- shape; an earlier pass of this same investigation assumed a fixed
-- `0xC9` prefix and undercounted by 13 real records before this
-- correction, caught by re-deriving the pattern without that
-- assumption and finding real, additional, byte-exact matches).
--
-- **186 real matches, ALL in bank 14, ZERO elsewhere in the whole
-- 256KB ROM -- a real, deliberate record format, not statistical
-- noise.** Cross-validated byte-exact against BOTH already-known real
-- landing positions (thirdRoom->fourthRoom: tileCol=14,tileRow=12 ->
-- pixel (120,112), exact match; fourthRoom->fifthRoom: tileCol=16,
-- tileRow=2 -> pixel (136,32), exact match) -- and, just as
-- importantly, the 3 OTHER already-recorded `landingX`/`landingY`
-- pairs in `rom_profiles.lua` (72,96 / 80,64 / 144,80) do NOT appear
-- anywhere in this table -- a real, CONSISTENT negative: all 3 are
-- already independently known to be non-CUT mechanisms (startRoom =
-- the initial spawn, never a transition at all; willyRoom's own exit
-- = a SCROLL-type transition, which this project's own established
-- finding says never needs a "set position" step; sixthRoom = a
-- genuinely continuous, non-single-cut hardware scroll, already
-- flagged as "not a real, single ROM-authored constant"). This
-- table's own scope is exactly, cleanly "wipe-style same-dungeon cut
-- transitions," matching the ROM's own real boundaries, not a
-- coincidental byte pattern.
--
-- HONEST, NOT-YET-CLOSED SCOPE: **which of these 186 records applies
-- to which specific real transition is NOT yet decoded.** A real,
-- promising, DOCUMENTED-BUT-UNCONFIRMED lead: an adjacent, structurally
-- similar record body (`00 08 C5 <idx> F4 <a> <b> 09 0C EC 00 0B`, 36
-- real matches, all `0xC9`-preceded, also bank-14-exclusive) has an
-- `idx` operand ranging 0-15 -- EXACTLY `roomSelectorTable`'s own real
-- 16-entry index range -- a strong structural candidate for the real
-- connectivity/selection key, but not live-cross-validated against a
-- third real transition this pass (would need the same live-tracing
-- effort the 2 already-known cases each took). Reported honestly as a
-- lead, not forced into a false closure -- this project's own "no
-- silent fallbacks" rule applies as much to a promising correlation as
-- to an opcode handler.
--
-- Pure Lua, no love.* calls, same convention as MapTable.lua/
-- RoomSelectorTable.lua (raw-ROM-table decoders).

local CutTransitionTable = {}

CutTransitionTable.LANDING_RECORD_BODY_LENGTH = 9
CutTransitionTable.SELECTOR_RECORD_BODY_LENGTH = 12

--- Scans `romData` for every real landing record body
-- (`00 05 F4 A1 A2 tileCol tileRow 00 0B`). Returns a plain 1-based
-- array of `{ fileOffset, bank, a1, a2, tileCol, tileRow, pixelX,
-- pixelY }`, `fileOffset` pointing at the record body's own leading
-- `0x00` byte (NOT at whatever precedes it, which varies -- see this
-- module's own doc comment). `pixelX`/`pixelY` use the already-
-- VERIFIED real formula (`TileLandingPosition.lua`): `(tileCol+1)*8`,
-- `(tileRow+2)*8`.
function CutTransitionTable.scanLandingRecords(romData)
  assert(type(romData) == "string", "CutTransitionTable.scanLandingRecords expects a byte string")
  local records = {}
  local n = #romData
  for i = 0, n - CutTransitionTable.LANDING_RECORD_BODY_LENGTH do
    -- 1-based Lua string indexing: byte at file offset `i` is romData:byte(i+1).
    if romData:byte(i + 1) == 0x00
      and romData:byte(i + 2) == 0x05
      and romData:byte(i + 3) == 0xF4
      and romData:byte(i + 8) == 0x00
      and romData:byte(i + 9) == 0x0B
    then
      local a1 = romData:byte(i + 4)
      local a2 = romData:byte(i + 5)
      local tileCol = romData:byte(i + 6)
      local tileRow = romData:byte(i + 7)
      records[#records + 1] = {
        fileOffset = i,
        bank = math.floor(i / 0x4000),
        a1 = a1,
        a2 = a2,
        tileCol = tileCol,
        tileRow = tileRow,
        pixelX = (tileCol + 1) * 8,
        pixelY = (tileRow + 2) * 8,
      }
    end
  end
  return records
end

--- Scans `romData` for every real "selector" record body
-- (`00 08 C5 idx F4 a b 09 0C EC 00 0B`) -- the real, promising-but-
-- unconfirmed lead for room-selector correlation (see this module's
-- own doc comment). Returns `{ fileOffset, bank, idx, a, b }`.
function CutTransitionTable.scanSelectorRecords(romData)
  assert(type(romData) == "string", "CutTransitionTable.scanSelectorRecords expects a byte string")
  local records = {}
  local n = #romData
  for i = 0, n - CutTransitionTable.SELECTOR_RECORD_BODY_LENGTH do
    if romData:byte(i + 1) == 0x00
      and romData:byte(i + 2) == 0x08
      and romData:byte(i + 3) == 0xC5
      and romData:byte(i + 5) == 0xF4
      and romData:byte(i + 8) == 0x09
      and romData:byte(i + 9) == 0x0C
      and romData:byte(i + 10) == 0xEC
      and romData:byte(i + 11) == 0x00
      and romData:byte(i + 12) == 0x0B
    then
      records[#records + 1] = {
        fileOffset = i,
        bank = math.floor(i / 0x4000),
        idx = romData:byte(i + 4),
        a = romData:byte(i + 6),
        b = romData:byte(i + 7),
      }
    end
  end
  return records
end

return CutTransitionTable
