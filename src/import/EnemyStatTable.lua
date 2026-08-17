-- Decodes the real per-species enemy/boss stat table found in the
-- Mystic Quest (EU) ROM -- bank 4, file `0x10739`, 24-byte stride, 21
-- real records (regular field monsters AND named story bosses share
-- this ONE table, see below).
--
-- FOUND, 2026-08-17 (direct user instruction, "suche eine möglichst
-- umfangreiche Komplettlösung mir karten, items, gegnerlisten usw und
-- benutzte die als grundlage um möglichst viele dinge im rom zu
-- finden"): the public disassembly project for the US "Final Fantasy
-- Adventure" cartridge (daid/FFA-Disassembly, github.com/daid/
-- FFA-Disassembly, `src/data/boss.asm` -- see docs/references.md)
-- documents a real 24-byte boss data record with named fields (speed,
-- HP, XP, money, ...) and lists all 21 real bosses' exact numeric
-- values. Searched this EU ROM for each boss's own 4-byte
-- (speed,HP,XP,money) signature: **all 21 matched byte-for-byte, at a
-- perfect 24-byte stride, starting at file `0x10739`** -- i.e. this
-- EU localization kept the exact same underlying combat-balance
-- numbers as the US cartridge, only the surrounding text changed.
-- This is airtight, reproducible evidence (re-run the search against
-- the ROM file directly, no emulator needed), not a guess transferred
-- from a different revision.
--
-- **Decisive independent cross-check, found in THIS project's own
-- EARLIER, unrelated work**: `Enemy.lua`'s own `HP_INIT_TRACE_NOTE`
-- (a real, live CPU trace from a completely different investigation,
-- long before this table was found by external reference) already
-- documented "HP = ((256-n)*speciesByte)>>4 ... speciesByte=2 for
-- this creature (record+1, file offset 0x108ba)". File `0x108ba` is
-- EXACTLY this table's own row 16 ("Jackal"), byte offset +1 (the
-- `hpBase` field below) -- and that row's real byte there IS `0x02`,
-- matching "speciesByte=2" exactly. Two independent lines of evidence
-- (an external reference's boss list, and this project's own earlier
-- live trace) landing on the exact same byte is strong confirmation
-- this table is real and this project has the right field.
--
-- **Important correction this cross-check forces**: the `hpBase`
-- field is NOT flat starting HP (despite the external disassembly
-- calling it "HP" outright) -- it is the MULTIPLIER in a real,
-- PRNG-randomized formula (`HP = ((256-n)*hpBase)>>4`, `n` a real
-- 0-15 PRNG draw), confirmed live for row 16. Whether the same
-- formula applies uniformly to every row (regular monsters AND named
-- story bosses alike, since they share this one table) is NOT yet
-- independently re-confirmed for a SECOND row -- a real, honest open
-- follow-up, not assumed.
--
-- **SECOND, even bigger connection found the same day** (direct user
-- instruction "marsch cave ist was anderes als die start sequenz!
-- weiter schauen" -- while re-examining this project's own room-graph
-- story context): this table is THE SAME real table as the already-
-- independently-found "message-settings table" from an EARLIER
-- session (2026-08-15, events.md's own "Second boss investigation" --
-- `rom_profiles.lua`'s `messageTextPointer`, "ALREADY-known message-
-- settings record base/stride (CPU `$4739`/file `0x10739`, 24 bytes/
-- record)"). That investigation independently found "species byte
-- `0x16` (22)" for the real courtyard boss at its own `hpBase+3`
-- offset (this table's `+5`, called `projectileType` below at the
-- time) -- and its own "5 sibling records sharing this species byte"
-- (indices 3, 5, 10, 16, 18) match this table's own rows 3/5/10/16/18
-- (Megapede/Golem/Iflyte/Jackal/Metal Crab per the external reference
-- names) BYTE-FOR-BYTE, both at `+5` (`0x16` in all 5) and `+6..+9`
-- (the exact `70/71,2,64,16/24` pattern that investigation already
-- documented). Renamed `projectileType` -> `speciesByte` to match
-- that EARLIER, independently-verified name rather than invent a
-- second one for the same real field. **Note the real, honest
-- surprise this reconciliation surfaced**: `speciesByte` is NOT
-- unique per named boss (5 very different bosses -- a centipede, a
-- golem, a flying creature, a jackal, a crab -- all share `0x16`) --
-- most consistent with a shared sprite/animation-family grouping
-- rather than a strict per-creature identity, per that earlier
-- investigation's own framing ("this project's OWN evidence-based
-- implementation choice, not a claimed decoded ROM fact" for exactly
-- which script ties to which room).
--
-- Record shape (0-based byte offset; only speed/hpBase/xp/gold are
-- confirmed by the cross-check above; the rest are the external
-- disassembly's own labels, unverified against this EU ROM's actual
-- code -- exposed anyway since they're free, real bytes, per this
-- project's own "return raw, don't guess silently" convention):
--   +0  speed            -- real, cross-checked value-for-value
--   +1  hpBase           -- real, cross-checked value-for-value; see
--                           the correction above (a formula input,
--                           not flat HP)
--   +2  xp               -- real, cross-checked value-for-value
--   +3  gold              -- real, cross-checked value-for-value
--   +4  numObjects        -- UNCONFIRMED against this EU ROM (external
--                            disassembly's own label: count of 16x16
--                            sprite objects)
--   +5  speciesByte       -- REAL, independently confirmed (see the
--                            "second connection" note above) -- a real
--                            creature-species/sprite-family selector,
--                            read by the real bank-4 spawn routine
--                            (file `0x101d1`) off a message-settings
--                            record via opcode `0xFE`. NOT unique per
--                            named boss (see the note above).
--   +6-7 defeatBehaviorId (LE u16) -- UNCONFIRMED; only 3 distinct
--                            real values seen across all 21 EU rows
--                            (`0x0246`/`0x0247`/`0x024F`), clustering
--                            bosses into a handful of groups rather
--                            than one unique value per boss -- more
--                            consistent with a real "post-defeat
--                            behavior TYPE selector" than a literal
--                            per-boss script pointer, but NOT traced
--                            live -- a promising, concrete lead for
--                            the still-open "which script fires on
--                            which boss's defeat" question (see
--                            events.md's "Second boss investigation"),
--                            not a resolved answer.
--   +8-23 unknown          -- real bytes, returned as part of `raw`;
--                            the external disassembly's own summary
--                            calls this region "graphics and animation
--                            data" but doesn't give a field-by-field
--                            breakdown, so nothing here is claimed.
--
-- **Real, concrete next step this connection opens up**: `messageText
-- Pointer`'s own table is indexed by `messageID` across (per events.md)
-- 1357 real records -- this decoder currently only covers the first 21
-- rows (the ones this pass could byte-match against the external boss
-- list). Extending `rowCount` and re-deriving `externalReferenceNames`
-- for the FULL real table (regular field monsters, not just named
-- bosses) is a real, scoped, not-yet-attempted follow-up.
--
-- Pure Lua, no love.* calls, same convention as EnemySpeciesTable/
-- ItemTable/WeaponTable.

local EnemyStatTable = {}

EnemyStatTable.ROW_STRIDE = 24

--- Decode all real records from `romData` per `enemyStatTable`
-- (`profile.enemyStatTable`, `{fileOffset, rowCount}`). Returns a
-- plain 1-based array of `rowCount` records, each `{speed, hpBase,
-- xp, gold, numObjects, speciesByte, defeatBehaviorId, raw}`.
function EnemyStatTable.decode(romData, enemyStatTable)
  assert(type(romData) == "string", "EnemyStatTable.decode expects a byte string")
  assert(enemyStatTable and enemyStatTable.fileOffset and enemyStatTable.rowCount,
    "EnemyStatTable.decode expects a profile.enemyStatTable")

  local rows = {}
  for i = 0, enemyStatTable.rowCount - 1 do
    local base = enemyStatTable.fileOffset + i * EnemyStatTable.ROW_STRIDE
    local raw = romData:sub(base + 1, base + EnemyStatTable.ROW_STRIDE)
    assert(#raw == EnemyStatTable.ROW_STRIDE,
      "EnemyStatTable.decode: row " .. i .. " ran past the end of romData")
    rows[i + 1] = {
      speed = raw:byte(1),
      hpBase = raw:byte(2),
      xp = raw:byte(3),
      gold = raw:byte(4),
      numObjects = raw:byte(5),
      speciesByte = raw:byte(6),
      defeatBehaviorId = raw:byte(7) + raw:byte(8) * 256,
      raw = raw,
    }
  end
  return rows
end

return EnemyStatTable
