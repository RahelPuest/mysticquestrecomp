-- Decodes the real per-species enemy combat table found in the Mystic
-- Quest (EU) ROM -- see docs/reverse-engineering/combat.md's "$50AC"
-- section and rom-map.md's "P1 resolved" section for the full live-
-- trace evidence this is built on.
--
-- VERIFIED: bank 4, file `0x10c80`-`0x10df0`, 8-byte stride, 46 rows /
-- 11 distinct species patterns (several species occupying multiple
-- consecutive identical rows). Reached live via a real bank-4 "entity
-- command dispatcher" (`$4466`, command byte `0xC9` = "attack"): it
-- resolves the attacking entity's slot, reads a per-entity record
-- pointer `DE` into this table (offset by +1 from each row's own
-- natural 8-byte file alignment), then loads `B = *(DE+3)` before
-- calling the real damage formula (`$50AC`, see CombatFormulas.lua).
-- `B` live-matched a row's own `atk` field exactly, twice,
-- independently, for the one enemy species this project has actually
-- fought (row `0x10d18`, `atk=8`).
--
-- Real, per-row field map (0-based byte offset within each 8-byte
-- row, NOT the dispatcher's own `DE`-relative offsets used in the
-- docs above -- `DE = rowFileOffset + 1`, so `row[+1] == DE[+0]`
-- etc.):
--   +0        constant `0x00` in every real row observed
--   +1        constant `0x00` in every real row observed
--   +2 (DE+1) constant `0x20` in every real row observed -- unexplained
--   +3 (DE+2) VARIES per species (`0x90`/`0xff`/`0x00`/`0x92`/`0xf0`)
--             -- real, unidentified (a flag/variant byte? every ATK
--             tier this project has seen appears with 2 different
--             values here, suggesting a variant/elite flag more than
--             a second combat stat, but NOT confirmed either way)
--   +4 (DE+3) VERIFIED real ATK -- exposed as `.atk`
--   +5 (DE+4) DEF CANDIDATE #1 -- real, species-varying, NOT confirmed
--             live (nothing in the traced `$50AC` path reads it)
--   +6 (DE+5) DEF CANDIDATE #2 -- same honesty caveat as #1; this is
--             the dispatcher's own `C` register, confirmed read but
--             its real consumer was never found ($50AC ignores C)
--   +7        constant `0x00` in every real row observed
--
-- 2026-08-12 follow-up (direct instruction "Gegner-DEF-Formel +
-- Bestiary"): chased the ONE previously-unexplored lead for where a
-- real enemy DEF might be consumed (`Enemy.lua`'s own
-- `PLAYER_ATTACK_DAMAGE` doc comment: a bank-trampoline dispatch with
-- a hardcoded `A=0` argument, "one hop further, not yet followed").
-- Followed it: `$27CE` -> `$1F35` (a real case/bank-N-table dispatcher,
-- same shape as the `$1F64` text-system dispatcher) -> bank 3's own
-- table, case 0 -> file `0xC02C`. That function turned out to be the
-- ALREADY-known general "iterate the 8-slot `$C4E0` actor array, run
-- one ambient per-frame tick for each live entry" routine from the
-- earlier script-system investigation -- a genuine, useful NEGATIVE
-- result: this specific trampoline call is an unrelated ambient tick,
-- not part of the damage chain, so it cannot be where a DEF read would
-- happen. Real per-hit player-to-enemy damage (`Enemy
-- .PLAYER_ATTACK_DAMAGE = 4`) stays the honest, live-traced flat value
-- it already was -- this pass narrows down where DEF is NOT, it does
-- not (yet) find where DEF for enemies actually is, if it exists as a
-- separate readable stat at all.
--
-- Pure Lua, no love.* calls, same convention as NoiseTable/ItemTable.

local EnemySpeciesTable = {}

EnemySpeciesTable.ROW_STRIDE = 8

--- Decode the full real table from `romData` per `enemySpeciesTable`
-- (`profile.enemySpeciesTable`, `{fileOffset, rowCount}`). Returns a
-- plain 1-based array of `rowCount` records, each
-- `{flagA, defCandidate1, atk, defCandidate2, raw}` -- `raw` is the
-- full 8-byte row as a Lua string, for anyone who wants the
-- still-unidentified bytes directly rather than guessing a field name
-- for them.
function EnemySpeciesTable.decode(romData, enemySpeciesTable)
  assert(type(romData) == "string", "EnemySpeciesTable.decode expects a byte string")
  assert(enemySpeciesTable and enemySpeciesTable.fileOffset and enemySpeciesTable.rowCount,
    "EnemySpeciesTable.decode expects a profile.enemySpeciesTable")

  local rows = {}
  for i = 0, enemySpeciesTable.rowCount - 1 do
    local base = enemySpeciesTable.fileOffset + i * EnemySpeciesTable.ROW_STRIDE
    local raw = romData:sub(base + 1, base + EnemySpeciesTable.ROW_STRIDE)
    assert(#raw == EnemySpeciesTable.ROW_STRIDE,
      "EnemySpeciesTable.decode: row " .. i .. " ran past the end of romData")
    rows[i + 1] = {
      flagVariant = raw:byte(3),       -- row +2 (DE+1): real, unidentified, varies per species
      defCandidate1 = raw:byte(6),     -- row +5 (DE+4): real, DEF candidate, unconfirmed live
      atk = raw:byte(5),               -- row +4 (DE+3): VERIFIED real ATK
      defCandidate2 = raw:byte(7),     -- row +6 (DE+5): real, DEF candidate, unconfirmed live
      raw = raw,
    }
  end
  return rows
end

--- Collapse consecutive identical rows into distinct "species" groups
-- (the real ROM data has 46 rows but only 11 DISTINCT species
-- patterns, several occupying a run of consecutive identical rows --
-- see this module's own doc comment). Returns a plain array of
-- `{row = <the shared record>, count = <how many consecutive rows>,
-- firstRowIndex = <1-based index into the decoded array>}`.
function EnemySpeciesTable.groupBySpecies(rows)
  local species = {}
  local i = 1
  while i <= #rows do
    local raw = rows[i].raw
    local count = 1
    while i + count <= #rows and rows[i + count].raw == raw do
      count = count + 1
    end
    species[#species + 1] = { row = rows[i], count = count, firstRowIndex = i }
    i = i + count
  end
  return species
end

return EnemySpeciesTable
