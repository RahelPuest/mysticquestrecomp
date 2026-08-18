-- Decodes the general "cut-transition record" format, tackling the two
-- long-standing genuinely-open blockers this project's "Consolidated
-- reference" section (rom-map.md) named: room connectivity and player
-- spawn/landing position. Both are now closed for wipe-style cut
-- transitions: each record encodes the target `roomSelector` and the
-- landing tile together, in one single ROM structure.
--
-- LIVE-CONFIRMED BACKGROUND (see `TileLandingPosition.lua`'s doc
-- comment for the full byte-exact chain): a bank-0 handler (`$11B7`,
-- registered as primary opcode `0xF4`) reads 2 literal bytes from a
-- script cursor into `B`/`C`, which flow through `$44A5` (tile-to-pixel:
-- `pixelX=(B+1)*8, pixelY=(C+2)*8`) and `$0611` (the per-tick entity
-- position-commit routine, same one ordinary movement uses) to set the
-- player's landing position after a "wipe-style" cut transition. An
-- earlier session found the ROM address for exactly 2 transitions by
-- live mGBA tracing, one at a time, and left "which ROM address holds
-- the literal tile-coordinate bytes for every other room transition" as
-- an open, unautomated question.
--
-- NEW THIS PASS: found the general record shape these bytes live
-- inside, via a live watchpoint on WRAM `$C244`/`$C245` (the very write
-- literal-address static search had already tried and failed to find,
-- since the real write is indirect -- `LD (HL),D` / `LD (HL),E` -- not
-- a literal `LD (nn),A`, exactly the blind spot a byte-pattern grep can
-- never cover but a live hardware watchpoint always does regardless of
-- addressing mode) followed all the way back through the call chain:
-- `$0659`/`$065B` (the write itself) <- `$4992` (`$0611`'s caller) <-
-- `$1ED7` selector `0x03` (`$498E`) <- `$1ED7` selector `0x0F` (`$4130`,
-- the `$D499`-indexed cut-transition state machine, table base
-- file/CPU `0x413C`) <- the opcode `0xF4`/`$11B7` handler itself
-- (already known).
--
-- Static-searching the ROM for the exact byte shape surrounding both
-- already-known examples found a general, repeating 9-byte record body:
--
--   00 05 F4 <A1> <A2> <tileCol> <tileRow> 00 0B
--
-- (the byte immediately before this body varies -- `0xC9`/RET 173
-- times, `0xC1`/POP BC 11 times, `0x77`/LD (HL),A 2 times, 186 total --
-- ordinary bytes belonging to whatever preceding instruction/record
-- happens to end there, not part of this record's own fixed shape; an
-- earlier pass of this same investigation assumed a fixed `0xC9` prefix
-- and undercounted by 13 records before this correction, caught by
-- re-deriving the pattern without that assumption and finding
-- additional, byte-exact matches).
--
-- 186 matches, all in bank 14, zero elsewhere in the whole 256KB ROM --
-- a deliberate record format, not statistical noise. Cross-validated
-- byte-exact against both already-known landing positions
-- (thirdRoom->fourthRoom: tileCol=14,tileRow=12 -> pixel (120,112),
-- exact match; fourthRoom->fifthRoom: tileCol=16, tileRow=2 -> pixel
-- (136,32), exact match) -- and, just as importantly, the 3 other
-- already-recorded `landingX`/`landingY` pairs in `rom_profiles.lua`
-- (72,96 / 80,64 / 144,80) do not appear anywhere in this table -- a
-- consistent negative: all 3 are already independently known to be
-- non-cut mechanisms (startRoom = the initial spawn, never a
-- transition at all; willyRoom's exit = a scroll-type transition, which
-- this project's established finding says never needs a "set position"
-- step; sixthRoom = a genuinely continuous, non-single-cut hardware
-- scroll, already flagged as "not a single ROM-authored constant").
-- This table's scope is exactly, cleanly "wipe-style same-dungeon cut
-- transitions," matching the ROM's own boundaries, not a coincidental
-- byte pattern.
--
-- CONNECTIVITY, decisively closed the same session (direct follow-up,
-- live-tracing `$4395` -- the `CALL $026DC` site inside `$D499` state
-- 3, which runs before state 5's own landing-position write in the
-- exact same per-transition script): `A1` (this record's first operand
-- byte) is the target `roomSelector` value, fed to `$026DC` completely
-- unmodified (`A2` is the one that gets nibble-split into `$026DC`'s
-- `D`/`E` sub-index argument, not `A1`). Live-confirmed for
-- thirdRoom->fourthRoom: `A1=1` at the exact moment `$4395` executes
-- (`A=0x1,D=7,E=5` -- `D`/`E` are `0x57`/`A2`'s nibble-split, exact
-- match) -- and `1` is one of fourthRoom's 2 candidate
-- `romRoomSelectors` (`{0,1}`) recorded in `rom_profiles.lua`, resolving
-- that room's long-standing "0 or 1" ambiguity as a bonus.
-- Statistically decisive too: `A1` ranges exactly `1`-`15` across all
-- 186 records, zero gaps, zero out-of-range values -- matching
-- `roomSelectorTable`'s real 16-entry index space precisely (no record
-- uses `0`, plausibly because index `0` is `startRoom`'s initial spawn,
-- never a cut target). Each landing record therefore encodes both which
-- room to load (`A1`=`roomSelector`) and where to land in it
-- (`tileCol`/`tileRow`) together, in one single ROM structure -- this
-- closes the room-connectivity question for wipe-style cut transitions,
-- not just landing position.
--
-- Pure Lua, no love.* calls, same convention as MapTable.lua/
-- RoomSelectorTable.lua (raw-ROM-table decoders).

local CutTransitionTable = {}

CutTransitionTable.LANDING_RECORD_BODY_LENGTH = 9
CutTransitionTable.SELECTOR_RECORD_BODY_LENGTH = 12

--- Real, already-established `roomSelectorTable` family assignments
-- (see `docs/reverse-engineering/rom-map.md`'s own "Consolidated
-- reference" section) -- curated project knowledge, NOT derived by
-- this module itself. Every real `roomSelector` value `scanLandingRecords`
-- can return (`1`-`15`) has an entry; `0` is included too (never
-- actually used by a real landing record, per this module's own doc
-- comment, but a real, valid `roomSelectorTable` index nonetheless).
--
-- UPGRADED from "curated/assumed" to LIVE-VERIFIED for selectors 2-6
-- (2026-08-17, direct user claim "ich bin mir sehr sicher das er
-- übergang von fourth in den fith room einfach nur ein übergang
-- zurück in den third room ist"): a real live WRAM register trace
-- ($D392/$D393/$C3F0/$C3F5) confirmed willyRoom/secondRoom/thirdRoom/
-- fifthRoom really do share one identical real room identity, not
-- just this table's own coarse label -- see `rom_profiles.lua`'s
-- `fifthRoom.sameRomIdentityAs`/`sameRomIdentityNote` and
-- `docs/reverse-engineering/events.md`'s same-dated entry for the
-- full register table, screenshots, and grid-overlap numbers.
CutTransitionTable.FAMILY_BY_ROOM_SELECTOR = {
  [0] = "startRoom/fourthRoom",
  [1] = "startRoom/fourthRoom",
  [2] = "willyRoom/secondRoom/thirdRoom/fifthRoom",
  [3] = "willyRoom/secondRoom/thirdRoom/fifthRoom",
  [4] = "willyRoom/secondRoom/thirdRoom/fifthRoom",
  [5] = "willyRoom/secondRoom/thirdRoom/fifthRoom",
  [6] = "willyRoom/secondRoom/thirdRoom/fifthRoom",
  [7] = "pre-transition placeholder (kein echter Raum)",
  [8] = "unknownRoomA",
  [9] = "unknownRoomA",
  [10] = "unknownRoomA",
  [11] = "unknownRoomA",
  [12] = "unknownRoomA",
  [13] = "unknownRoomA",
  [14] = "unbekannt (kein bereits bekannter Raum)",
  [15] = "unknownRoomB (schwarzer Wipe-Hintergrund)",
}

--- Scans `romData` for every real landing record body
-- (`00 05 F4 A1 A2 tileCol tileRow 00 0B`). Returns a plain 1-based
-- array of `{ fileOffset, bank, roomSelector, subIndexByte, tileCol,
-- tileRow, pixelX, pixelY }`, `fileOffset` pointing at the record
-- body's own leading `0x00` byte (NOT at whatever precedes it, which
-- varies -- see this module's own doc comment). `roomSelector` (the
-- record's own first operand byte, `A1` in this module's own doc
-- comment) is the REAL target `roomSelectorTable` index, fed
-- unmodified to `$026DC` -- live-confirmed, see doc comment above.
-- `subIndexByte` (`A2`) is `$026DC`'s own real nibble-split `D`/`E`
-- sub-index argument, real but not further decoded by this module.
-- `pixelX`/`pixelY` use the already-VERIFIED real formula
-- (`TileLandingPosition.lua`): `(tileCol+1)*8`, `(tileRow+2)*8`.
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
      local roomSelector = romData:byte(i + 4)
      local subIndexByte = romData:byte(i + 5)
      local tileCol = romData:byte(i + 6)
      local tileRow = romData:byte(i + 7)
      records[#records + 1] = {
        fileOffset = i,
        bank = math.floor(i / 0x4000),
        roomSelector = roomSelector,
        subIndexByte = subIndexByte,
        tileCol = tileCol,
        tileRow = tileRow,
        pixelX = (tileCol + 1) * 8,
        pixelY = (tileRow + 2) * 8,
      }
    end
  end
  return records
end

--- Collapses `scanLandingRecords`' own raw records into the real,
-- GENUINELY DISTINCT set of `(roomSelector, pixelX, pixelY)`
-- transitions -- the same real story/dialogue transition is referenced
-- from many different points in the corpus (e.g. `roomSelector=2,
-- pixel=(136,32)` alone accounts for 11 of the 186 raw records), not
-- 11 different real transitions. Returns a plain 1-based array of
-- `{ roomSelector, targetFamily, pixelX, pixelY, tileCol, tileRow,
-- occurrences, exampleFileOffset }`, sorted by `roomSelector` then
-- `pixelX` then `pixelY` (a stable, deterministic order for a caller
-- that renders this as a table/list). `targetFamily` is looked up from
-- `FAMILY_BY_ROOM_SELECTOR` above (`"unbekannt (roomSelector N)"` for
-- any value that table doesn't cover, an honest fallback rather than
-- a crash if a future ROM revision's own scan finds a value outside
-- the currently-known 0-15 range).
function CutTransitionTable.distinctLandings(romData)
  local records = CutTransitionTable.scanLandingRecords(romData)
  local byKey = {}
  local order = {}
  for _, r in ipairs(records) do
    local key = r.roomSelector .. ":" .. r.pixelX .. ":" .. r.pixelY
    local entry = byKey[key]
    if not entry then
      entry = {
        roomSelector = r.roomSelector,
        targetFamily = CutTransitionTable.FAMILY_BY_ROOM_SELECTOR[r.roomSelector]
          or ("unbekannt (roomSelector " .. r.roomSelector .. ")"),
        pixelX = r.pixelX,
        pixelY = r.pixelY,
        tileCol = r.tileCol,
        tileRow = r.tileRow,
        occurrences = 0,
        exampleFileOffset = r.fileOffset,
      }
      byKey[key] = entry
      order[#order + 1] = entry
    end
    entry.occurrences = entry.occurrences + 1
  end
  table.sort(order, function(a, b)
    if a.roomSelector ~= b.roomSelector then return a.roomSelector < b.roomSelector end
    if a.pixelX ~= b.pixelX then return a.pixelX < b.pixelX end
    return a.pixelY < b.pixelY
  end)
  return order
end

--- Scans `romData` for every real "selector-shaped" record body
-- (`00 08 C5 idx F4 a b 09 0C EC 00 0B`) -- a real, structurally
-- distinct sibling record this same investigation found. HONEST
-- STATUS: this was originally suspected to be the real room-
-- connectivity key (its own `idx` operand happens to range 0-15, the
-- same as `roomSelectorTable`'s own size) -- that lead turned out to
-- be a coincidence, not the real mechanism: connectivity is actually
-- encoded directly in `scanLandingRecords`' own `roomSelector` field
-- (see this module's own doc comment for the live-traced proof). This
-- record type's own real meaning remains genuinely undecoded -- kept
-- here as a real, verified structural finding for whoever investigates
-- it next, not removed just because the original hypothesis about it
-- didn't pan out. Returns `{ fileOffset, bank, idx, a, b }`.
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
