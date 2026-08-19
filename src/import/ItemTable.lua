-- Decodes the item/spell name+stat table found in the Mystic Quest (EU)
-- ROM -- see docs/reverse-engineering/rom-map.md "Item/spell table" for
-- the full evidence writeup (status: PARTIALLY VERIFIED -- names, the
-- 16-byte record width, and the per-category ID byte (byte 15) are
-- confirmed; bytes 9-14's meaning is not).
--
-- This module only knows the *record shape*; every actual offset comes
-- from a profile (src/import/rom_profiles.lua's `itemTable` field), per
-- the project rule that ROM-version-specific knowledge stays centralized
-- there. Pure Lua, no love.* calls, so it's headlessly testable like
-- MapTable/GBTile.
--
-- INCONCLUSIVE STATIC PASS, 2026-08-16 (task "Item-/Waffen-Effektformeln
-- reverse-engineeren", see combat.md's own dated entry for the full
-- writeup): bytes 9-14 (0-based) remain genuinely undecoded, but this
-- pass at least narrowed them down. Byte 9 is redundant with
-- `categoryByte` (mirrors the record's tier: `0x10` basic items,
-- `0xA0`/`0xB0`/`0x90` the 3 real spell tiers). Byte 10 is the most
-- promising candidate for a real "power" field, but does NOT converge
-- to one confident reading: the 4 real status-cure spells (Salbe/Auge/
-- Bewege/Spruch) show a clean single-bit progression (`01`/`02`/`04`/
-- `08`, plausibly "which status this cures"), while the elemental
-- attack items (Flam/Eis/Bliz/Bomb, `08`/`12`/`20`/`40`) look more like
-- a power scalar -- but `0x12` sets 2 bits, breaking the clean-bitmask
-- reading. No live item-use trigger exists yet to resolve this
-- (`Inventory.lua`'s own doc comment: no real WRAM held-item struct has
-- been traced), so this stays a named, honestly-unresolved candidate,
-- not a formula -- `Inventory:useItem` still applies no numeric effect.
--
-- FOUND, 2026-08-15 (extending the catalog for the monster/npc/item
-- census): records 8-19 (the real spell section, per
-- `itemTable.categoryBoundaryRecord=8`) do NOT store their name at
-- offset 0 like records 0-7 (consumable items) do -- byte 0 there is
-- instead a real, consistent PREFIX byte (`0xA9` for records 8-17,
-- `0xAF` for 18-19/22-27, `0xD7` for the one still-unexplained
-- anomaly at record 21) and the real name text starts at offset 1.
-- Live-verified: offset-1 decoding of records 8-19 produces clean,
-- real German spell names ("Lebe"[n]/"S-Lebe"/"Magi"[e]/"S-Magi"/
-- "Elixier"/"Salbe"/"Auge"/"Bewege"/"Spruch"/"Allheil"/"Stille"/
-- "Schlaf" -- classic Seiken Densetsu 1 spell names). The real
-- meaning of the prefix byte itself (spell tier? icon ID?) is NOT
-- decoded -- returned as `namePrefixByte` for a future pass, not
-- guessed at.
--
-- FOUND, 2026-08-18 ("mach das magiesystem" -- same external-reference
-- method that already closed enemyStatTable/weaponStatTable): bytes
-- 13-14 (0-based, LE u16) are the real shop PRICE, closing part of this
-- module's own long-standing "bytes 9-14 undecoded" gap. Cross-checked
-- against a real, fetched Final Fantasy Adventure walkthrough
-- (gamesurge.com, see docs/references.md) -- 8 of 8 checkable records
-- match EXACTLY: record 8 "Lebe" 40g (Cure), 9 "S-Lebe" 160g (X-Cure),
-- 10 "Magi" 320g (Ether), 11 "S-Magi" 640g (X-Ether), 13 "Salbe" 30g
-- (Pure), 14 "Auge" 60g (Eyedrop), 15 "Bewege" 90g (Soft), 16 "Spruch"
-- 120g (Moogle) -- the latter 4 also form a clean, self-evident +30g
-- arithmetic progression even before the external cross-check. Records
-- 0-7 (the found/thrown combat items -- Flam/Eis/Bliz/Bomb etc.) all
-- price=0, consistent with "not sold in a shop" rather than
-- contradicting the field. HONEST SCOPE, narrower than the task that
-- prompted this search: this is the shop ITEM catalog (potions,
-- status-cure items, thrown elemental items), not the player's
-- MP-costed Magic-menu spell list (Cure/Heal/Sleep/Mute/Fire/Ice/Lit/
-- Nuke per the same walkthrough) -- a direct AND strided (stride 2-32)
-- search for that 8-value MP-cost byte sequence across the whole ROM
-- came back genuinely negative. The real castable-spell system (Magic
-- Ring menu, MP consumption against the already-known `$D7B6`/`$D7B8`
-- curMP/maxMP cells) has NOT been located by this pass -- it is
-- evidently a separate ROM structure from this item/price table, not
-- yet found. See events.md's own 2026-08-18 entry for the full trail.
--
-- FIXED, 2026-08-18, direct user report ("buchstabensalat" -- garbled
-- names on the website): `TextDecoder.decodeString` has no field-width
-- concept of its own -- given the FULL 16-byte `raw` record (as this
-- module used to pass it), it happily kept decoding past the real
-- 8-byte name field into the following stat/price bytes whenever one of
-- THOSE bytes also happened to fall in a mapped glyph/digraph range --
-- common, since item stat values are small integers that frequently
-- collide with the wide 0x80-0xFF glyph range. Real, concrete examples
-- this bug produced: record 38's real name "Spiegel" read as
-- " Spiegelne" (the extra "ne" came from `categoryByte`/stat bytes,
-- not the name); records 45-48 shared a real "NWpGnsc" prefix but each
-- grew 2 more nonsense characters from their own differing stat bytes.
-- **This was NOT a digraph-table gap** (the individual byte->character
-- mappings involved were themselves correct) -- it was a missing upper
-- bound on WHERE those correct mappings should even be attempted.
-- VERIFIED the underlying 16-byte-stride table itself was never in
-- doubt: the real per-category `id` counter (byte 15) increments
-- unbroken 1->51 across the entire 59-record range with exactly one
-- reset at the documented item/spell boundary -- proof this table
-- genuinely continues that far; the garbling was a display artifact of
-- this module's own decode call, not evidence of an over-extended
-- table boundary. Fixed by slicing `raw` down to exactly `nameLength`
-- bytes before ever calling `TextDecoder.decodeString`, so decoding can
-- structurally never reach `categoryByte` or any stat byte beyond it.
-- See events.md's own 2026-08-18 entry for the full before/after
-- diagnostic.
--
-- FURTHER CHARACTERIZED, same day, direct follow-up ("fixe die
-- restlichen einträge"): after the field-overrun fix above, several
-- records still stop short of a full 8 characters (e.g. record 29
-- "eh", 37 "gW", 55 "Äns") at one of exactly 4 bytes (`0xA2`/`0xA4`/
-- `0xA7`/`0xA8`). These are NOT a digraph-table gap -- see
-- `TextDecoder.lua`'s own matching 2026-08-18 note (right before its
-- `DIGRAPH_PARTIAL`) for the evidence: all 4 bytes recur, in the real
-- dialogue region specifically, immediately before an item name in an
-- "<Item> gefunden" pickup message -- very plausibly a per-message
-- control/type byte (same category as the already-verified `0x12`),
-- not a missing letter. Practical consequence: these records' short
-- names are very likely already their FULL, correct real content, not
-- truncated. A SEPARATE, still-genuinely-open group (records that
-- decode completely within the 8-byte bound -- every byte mapped, no
-- stop at all -- but still don't read as plausible German, e.g. record
-- 43/50's identical "i-vJpORq" or 45-48's shared "NWpGnsc" prefix) was
-- deliberately NOT forced to a guess this pass -- no evidence met this
-- project's own 2-independent-occurrence bar for revising an existing,
-- already-correctly-used mapping. Real candidates from a fetched
-- walkthrough's key-item list (Opal, 4 stat-boost Stones, Pendant,
-- Silver, Fang) remain unmatched to any specific record.
--
-- DECISIVE FIND, 2026-08-19 ("was können wir jetzt bezüglich der großen
-- blocker machen" -> Magic/spell system): records 0-7 -- previously
-- assumed to be "found/thrown combat items, never sold" purely because
-- their `price` reads 0 -- are the real 8 MP-costed, castable Magic-menu
-- spells (Cure/Heal/Sleep/Mute/Fire/Ice/Lightning/Nuke), not junk items.
--
-- Found by live-disassembling the real ROM's own MP-deduction code
-- (`tools/rom/watcher.py`/`disasm.py`, direct scan for every real
-- literal reference to `$D7B6`-`$D7B9`, the already-known curMP/maxMP
-- WRAM cells): bank 2, CPU `$B18F`-`$B1AB` (the menu-context "cast"
-- routine) and its battle-context sibling `$A660`-`$A67E` (same shape,
-- gated behind an extra `$D6EF`/index<9 check first) both do the exact
-- same real thing --
--   LD HL,0x5DEC / CALL 0x768C   -- resolve a per-spell-index pointer
--   LD A,(HL) / AND 0x1F          -- the real MP-cost field, masked
--   LD A,(0xD7B6) / SUB B          -- curMP -= cost
--   JR C,<fail>                    -- insufficient MP: SCF, bail, no write
--   LD (0xD7B6),A                  -- else: commit the new curMP
-- `$768C` (fully disassembled too) computes `($5DEC+1) + ((A AND
-- 0x7F)-1)*16` -- a real, 1-based, 16-byte-stride index into a table
-- whose resolved base (`$5DED`, file `0x9DED` in bank 2) is exactly
-- `itemTable.fileOffset (0x9DE5) + 8` -- i.e. this "spell cost" table
-- is NOT a separate structure. **It's `categoryByte` (byte 8, 0-based)
-- of this SAME already-decoded 16-byte-record table, masked to its low
-- 5 bits.**
--
-- Cross-checked against the SAME external walkthrough this project's
-- own 2026-08-18 price-field pass already used (gamesurge.com's Final
-- Fantasy Adventure guide, "8 magic spells with MP cost": Cure 2/Heal
-- 1/Sleep 1/Mute 1/Fire 1/Ice 2/Lightning 2/Nuke 3): records 0-7's own
-- real `categoryByte AND 0x1F` reads **2,1,1,1,1,2,2,3 -- an exact,
-- 8/8, IN-ORDER match**. Independently corroborated by the records'
-- own already-decoded (if short/truncated) German names lining up
-- semantically: "Lebe"(Cure)/"Salb"(Heal, Salbe=balm)/"Blok"(Sleep)/
-- "Ruhe"(Mute, Ruhe=silence)/"Flam"(Fire, Flamme)/"Eis "(Ice)/
-- "Bliz"(Lightning, Blitz)/"Bomb"(Nuke, Bombe). Every record 8+ reads
-- `categoryByte AND 0x1F == 0` without exception -- consistent with
-- "not a spell, this field doesn't apply," not contradicting the read.
--
-- This directly answers the milestone's own long-standing stated
-- blocker ("search opcodes... that read or write $D7B6/$D7B8 directly
-- -- no such reference exists yet in this codebase, meaning the
-- MP-consuming opcode itself hasn't been identified at all," see
-- events.md's 2026-08-18 entry): it has now been identified, real,
-- disassembled, and cross-validated two independent ways.
--
-- HONEST SCOPE: this closes "which record is which spell, its real MP
-- cost, and the real ROM code that deducts it" -- it does NOT close
-- "what does casting a given spell actually DO in combat" (the
-- elemental-damage/status-effect/heal-amount formulas each spell
-- triggers remain genuinely unfound), and this is NOT wired into
-- `Inventory.lua`/`Menu.lua`'s own gameplay yet -- `Menu.lua`'s
-- "Magie" option still honestly closes immediately (see its own doc
-- comment), matching the real ROM's own live-confirmed behavior for a
-- fresh character with zero known spells (no real ROM trigger for
-- LEARNING a spell has been found, same open gap this project already
-- has for granting items). `mpCost` below exposes the real, decoded
-- field; using it to drive actual spell-casting gameplay is separate,
-- not-yet-attempted follow-up work.

local TextDecoder = require("src.import.TextDecoder")

local ItemTable = {}

--- Decode all records from `itemTable` profile info against `romData`.
-- Returns an array of:
--   { index, name = <string>, categoryByte = <0-255>, id = <0-255>,
--     price = <0-65535>, namePrefixByte = <0-255 or nil>,
--     raw = <16-byte string> }
-- 1-based like every other Lua array in this codebase. `categoryByte`
-- is the record's byte 8 (0-based) -- HYPOTHESIS: a category/type flag,
-- correlated with but not independently proven beyond the item/spell
-- boundary match (see rom-map.md). `id` is byte 15 -- VERIFIED as a
-- real per-category counter (resets to 0 exactly at
-- itemTable.categoryBoundaryRecord). `price` is bytes 13-14 (LE u16) --
-- VERIFIED, 8 of 8 external gold-cost matches, see this module's own
-- top-of-file 2026-08-18 doc comment; 0 for records never sold in a
-- shop (the found/thrown combat items).
--
-- `name` tries offset 0 first (the real consumable-item shape); if
-- that decodes empty, retries at offset 1 (the real spell shape found
-- 2026-08-15, see this module's own top-of-file doc comment) and, if
-- THAT succeeds, records the real skipped byte 0 as `namePrefixByte`
-- -- an honest "try the known real shapes, don't guess a third one"
-- fallback, not silent papering-over: a record where BOTH attempts
-- come back empty still surfaces as `name = ""`, not a fabricated
-- guess.
function ItemTable.decode(romData, itemTable)
  assert(type(romData) == "string", "ItemTable.decode expects a byte string")
  assert(itemTable and itemTable.fileOffset,
    "ItemTable.decode expects a profile.itemTable table")

  local recordLength = itemTable.recordLength
  local nameLength = itemTable.nameLength
  local records = {}

  for i = 0, itemTable.recordCount - 1 do
    local recordFile = itemTable.fileOffset + i * recordLength
    local raw = romData:sub(recordFile + 1, recordFile + recordLength)
    -- BOUNDED to the real name field (found 2026-08-18, direct user
    -- report "buchstabensalat" -- see this module's own top-of-file
    -- 2026-08-18 doc comment for the full trail): `TextDecoder
    -- .decodeString` has no field-width concept of its own -- given the
    -- FULL 16-byte `raw` record, it happily keeps decoding past the
    -- real 8-byte name field into the stat/price bytes whenever one of
    -- THOSE bytes also happens to fall in a mapped glyph/digraph range
    -- (common -- item stat values are small integers that frequently
    -- collide with the wide 0x80-0xFF glyph range), producing an
    -- overlong, garbled name (e.g. record 38's real "Spiegel" used to
    -- read as " Spiegelne", record 45-48's shared "NWpGnsc" prefix used
    -- to grow 2 more nonsense characters each from their own differing
    -- stat bytes). `nameField` caps the slice at exactly `nameLength`
    -- bytes so decoding can never read past `categoryByte` (always at
    -- 0-based position `nameLength`, per the unchanged read below --
    -- true for BOTH name shapes) or any stat byte beyond it. The
    -- offset-1/prefixed shape does NOT get an extra byte past this
    -- field -- its prefix occupies the field's own first slot, leaving
    -- `nameLength-1` (7) bytes for the actual name text in that shape,
    -- not `nameLength`.
    local nameField = raw:sub(1, nameLength)
    local name = TextDecoder.decodeString(nameField, 0)
    local namePrefixByte = nil
    if name == "" then
      local altName = TextDecoder.decodeString(nameField, 1)
      if altName ~= "" then
        name = altName
        namePrefixByte = raw:byte(1)
      end
    end
    local categoryByte = raw:byte(nameLength + 1)
    local id = raw:byte(recordLength)
    -- Price: bytes 13-14 (0-based), i.e. raw:byte(14)/raw:byte(15) in
    -- this 1-based string -- see this module's own 2026-08-18 doc
    -- comment for the external cross-check. Fixed absolute positions
    -- within the 16-byte record, independent of nameLength/prefix --
    -- unlike `name`, this field's real position never shifts.
    local price = raw:byte(14) + raw:byte(15) * 256
    -- mpCost: `categoryByte AND 0x1F` -- found 2026-08-19 by live-
    -- disassembling the real ROM's own MP-deduction routine (bank 2,
    -- CPU $B18F-$B1AB and its battle-context sibling $A660-$A67E; see
    -- this module's own top-of-file doc comment for the full trace).
    -- Only genuinely meaningful for records 0-7 (the real castable
    -- spells -- masked value is 0 for every other record, records 8+
    -- use `categoryByte`'s other bits for a different, still-uncertain
    -- purpose). Exposed unconditionally here (same "decoder doesn't
    -- editorialize which records matter" convention as every other
    -- field) -- callers that care about spells specifically should
    -- combine this with `itemTable.categoryBoundaryRecord`.
    local mpCost = categoryByte % 32

    records[i + 1] = {
      index = i,
      name = name,
      categoryByte = categoryByte,
      id = id,
      price = price,
      mpCost = mpCost,
      namePrefixByte = namePrefixByte,
      raw = raw,
    }
  end

  return records
end

--- Groups already-decoded `records` (from `ItemTable.decode`) by their
-- real `categoryByte`, in ascending categoryByte order -- same shape/
-- intent as `EnemySpeciesTable.groupBySpecies`, just keyed by a
-- scattered byte value instead of consecutive identical rows.
--
-- FOUND, 2026-08-15 (catalog plan Phase 2, direct user request "Items
-- in mehr auswählbare Kategorien unterteilen"): grouping the real,
-- live-decoded 41-record item/spell table by `categoryByte` produces
-- 6 real, non-overlapping groups (`0`=22, `64`=13, `65`=4, `66`=3,
-- `67`=1, `128`=16 -- see `tests/import/item_table_test.lua` for the
-- exact locked-in counts). What each byte VALUE actually represents
-- (consumable/spell tier? icon sheet index?) is still genuinely
-- UNKNOWN -- this function only groups by the real, observed byte,
-- it does not name or interpret the groups. One real, honest
-- correlation IS independently confirmed by inspection (not asserted
-- here in code, since it's about NAME CONTENT, not the grouping
-- itself): `categoryByte=64`'s 13 records correlate heavily with
-- names that fail to decode into plausible German words -- flagged in
-- docs, not encoded as a boolean here, since "looks like a real word"
-- has no reliable, honest programmatic test.
--
-- `sizeClass` is a plain, honest, SIZE-only label (`"group"` for
-- categoryByte values shared by >=5 records, `"single"` otherwise) --
-- it says nothing about what the category itself means, only how many
-- real records share it. Useful for a UI to visually distinguish "a
-- real, multi-item category" from "an outlier/one-off record" without
-- claiming a specific real-world slot name (e.g. "potion"/"material")
-- this project has not confirmed.
function ItemTable.groupByCategory(records)
  local groups = {}
  local order = {}
  for _, r in ipairs(records) do
    if not groups[r.categoryByte] then
      groups[r.categoryByte] = { categoryByte = r.categoryByte, count = 0, records = {} }
      order[#order + 1] = r.categoryByte
    end
    local g = groups[r.categoryByte]
    g.count = g.count + 1
    g.records[g.count] = r
  end
  table.sort(order)
  local result = {}
  for i, categoryByte in ipairs(order) do
    local g = groups[categoryByte]
    g.sizeClass = (g.count >= 5) and "group" or "single"
    result[i] = g
  end
  return result
end

return ItemTable
