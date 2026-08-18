-- The general WRAM entity-slot struct this ROM uses for the player,
-- enemies, and NPCs alike -- found while chasing the "where is the
-- player's spawn/landing position encoded" question (see
-- docs/reverse-engineering/rom-map.md's "Consolidated reference: the
-- general room/map system" section, and events.md's "spawn position +
-- trigger zones" investigation, for the full disassembly trail this is
-- distilled from).
--
-- VERIFIED base/stride: `$C200 + slotIndex*16`, 20 slots (0-19) --
-- confirmed via two independent routines that both compute this exact
-- address:
--   `$0AE3` (the general entity despawn primitive, already documented
--   via the enemy-death-dispatch chain) -- receives a slot index in
--   `C`, computes `HL = $C200 + C*16` via 4 `ADD HL,HL` doublings
--   (`C*2*2*2*2 = C*16`), zeroes fields `+4`/`+5`/`+8`/`+9`, and
--   memsets that slot's 8-byte OAM shadow-copy block (pointed to by
--   `+8`/`+9`).
--   `$0A74` (the general entity allocate primitive -- the exact
--   structural counterpart, found this same investigation): scans up
--   to 20 slots (`LD B,0x14`) for the first with `+0 == 0xFF` (the
--   dead/empty sentinel), then initializes every field below.
--
-- Pure Lua, no love.* calls, no ROM bytes needed to define the layout
-- itself (it's a WRAM/code convention, not something read from ROM
-- data at runtime) -- but see `tests/import/entity_struct_layout_
-- test.lua` for byte-level cross-checks against the actual disassembly
-- this file documents.

local EntityStructLayout = {}

EntityStructLayout.BASE = 0xC200
EntityStructLayout.STRIDE = 16
EntityStructLayout.SLOT_COUNT = 20

-- Real per-slot field offsets (0-based, within one 16-byte record).
EntityStructLayout.FIELD = {
  ALIVE = 0,     -- alive/state byte: 0xFF = dead/empty sentinel; 0x08 on allocate
  TYPE = 1,      -- caller-supplied "type" param (ROM meaning not decoded further)
  -- REFINED (chasing the $C4E0 actor-command array's "+0x12 pointer
  -- field" writer): still just a "caller-supplied param" by direct
  -- meaning, but now known to be a general, heavily-used field, not
  -- incidental scratch data -- a dedicated getter/setter pair (`$0C6D`
  -- read, `$0C86` swap; both `HL = $C200 + slotIndex*16 + 2`, `$0C6D`
  -- additionally guards on FIELD.ALIVE==0xFF returning 0) has 24 + 17
  -- callers respectively, spread across every ROM bank (0/1/2/3 all
  -- confirmed), the widest caller spread of any EntityStructLayout
  -- accessor found so far. The $C4E0 array's slot-scan code (bank-3
  -- `$4BE0`, already known as the "$C5AF actor count refresh" routine,
  -- and a bank-0 sibling at `$278F`) reads this field via `$0C6D` for
  -- each active $C4E0 slot's ID byte (used as the $C200 slot index) and
  -- classifies its high nibble against a recurring value set
  -- (`0x90`/`0xB0`/`0x10` at `$4BE0`; only `0x90`/`0x10` at `$278F` --
  -- an honest, unresolved discrepancy, not forced into one story). A
  -- concrete, well-scoped next step for whoever continues:
  -- `$0C6D`/`$0C86`'s other ~35 call sites (bank 1/2, i.e. outside the
  -- map/actor-command machinery this project has mostly focused on) are
  -- far more likely to reveal PARAM2's overall meaning quickly than
  -- more $C4E0-side tracing.
  PARAM2 = 2,    -- caller-supplied param
  PARAM3 = 3,    -- 0 at allocate time
  POSITION_Y = 4,   -- Y position, pixel space
  POSITION_X = 5,   -- X position, pixel space
  PARAM6 = 6,    -- caller-supplied param
  PARAM7 = 7,    -- caller-supplied param
  OAM_SHADOW_PTR = 8, -- 16-bit LE pointer to this slot's 8-byte OAM shadow-copy block
  -- Tracing $0C6D/$0C86's ~35 other callers per the PARAM2 note above
  -- found the whole accessor family these two belong to, one
  -- getter/setter pair per field, all sharing the exact same `HL =
  -- $C200 + slotIndex*16 [+ offset]` shape -- see
  -- `EntityStructLayout.FIELD_ACCESSOR_ADDRESS` below for the full
  -- address table. Two fields beyond the previously-documented 0-8
  -- range have dedicated accessors too:
  UNKNOWN_10 = 10, -- getter $0CD3/setter $0CE4; 6+3 callers (bank 0/1/3)
  UNKNOWN_11 = 11, -- getter $0CF7/setter $0D08; 0+1 callers (setter only reached once, bank 0)
}

-- ROM addresses of the two known routines that operate on this struct
-- -- kept here (not just in a doc comment) so future investigation/
-- tests have one centralized reference point, matching this project's
-- "ROM-version-specific data lives in one place" convention.
EntityStructLayout.DESPAWN_ROUTINE_ADDRESS = 0x0AE3
EntityStructLayout.ALLOCATE_ROUTINE_ADDRESS = 0x0A74

-- A cohesive block of small per-field getter/setter routines living
-- together at `$0C41`-`$0D1B` (bank 0), each one the exact same shape
-- `HL = $C200 + C*16 [+ offset]` this project already knew piecemeal
-- (`$02AB`'s `$0C99`, `PARAM2`'s `$0C6D`/`$0C86`). Disassembled the
-- whole block directly against the ROM bytes -- every entry below is
-- VERIFIED, not inferred from naming alone. `nil` means no accessor
-- for that direction was found in this contiguous block (may still
-- exist elsewhere, not searched for further).
EntityStructLayout.FIELD_ACCESSOR_ADDRESS = {
  [EntityStructLayout.FIELD.ALIVE] = { get = 0x0C99, set = 0x0CA6 },
  -- $0CA6's own setter is GUARDED: if the slot's OLD value was already
  -- the dead sentinel (0xFF), it writes the NEW value then immediately
  -- forces it back to 0xFF -- a real "can't revive a dead slot through
  -- this specific setter" rule, distinct from the real allocate
  -- routine (`$0A74`) which presumably bypasses it.
  [EntityStructLayout.FIELD.TYPE] = { get = 0x0C4F, set = 0x0C5D },
  -- Real usage sample (bank 1, `$4B65`/`$4B78`/`$4FA9`): all 3 real
  -- call sites found write TYPE for slot 4 (the PLAYER's own slot)
  -- with small integers (`1`, `4`) alongside PARAM2 writes in the SAME
  -- functions.
  --
  -- RETRACTED (2026-08-14, direct live-test follow-up, "ja mach mal"):
  -- this doc comment previously read "reads like a real, dynamic
  -- per-frame STATE value... plausibly attack-related" -- a hypothesis
  -- built from the static shape alone (facing/direction-masked
  -- dispatch, a `$C4D2:=0x3C` timer write, `CALL $02AB` right after).
  -- Live-tested it directly: mGBA watchpoints on TYPE/PARAM2/PARAM3/
  -- PARAM6/PARAM7/UNKNOWN_10/UNKNOWN_11/`$C4D2` across a real A-press
  -- attack (`courtyard_enemy_engaged` checkpoint) found ZERO real value
  -- changes; a follow-up direct PC/execution check (600,000 real single
  -- steps spanning the whole attack) found the handler blocks at ALL 3
  -- real TYPE-setter call sites (`$4B60`, `$4B72`, `$4F9D`) and their
  -- own further dispatch targets (`$5010`, `$5084`) are NEVER REACHED
  -- during a normal melee attack -- a clean, decisive, honest NEGATIVE,
  -- not an inconclusive one. The "attack-related" hypothesis is WRONG
  -- as stated. What remains true (byte-level, unaffected by this
  -- correction): the 3 real static call sites exist and do write small
  -- integers to slot 4's TYPE field. Whether this whole code region is
  -- genuinely dead code, or reached under some OTHER real condition
  -- this pass didn't test (a different room/game state, a move not
  -- available this early), stays open.
  [EntityStructLayout.FIELD.PARAM2] = { get = 0x0C6D, set = 0x0C86 },
  [EntityStructLayout.FIELD.POSITION_Y] = { get = 0x0C41, set = nil },
  -- Offsets 6/7 (`PARAM6`/`PARAM7`): no separate 1-byte accessors
  -- found in this block -- instead, `$0CBA` is a real, GUARDED 16-bit
  -- setter treating them as ONE PAIRED field (`LD (HL),E / INC HL /
  -- LD (HL),D` at offset+6/+7 together, skipped entirely if the slot
  -- is dead). Real evidence these two nominally-separate byte fields
  -- are, in practice, used as a single 16-bit value by at least this
  -- caller -- a refinement of the current FIELD table's split naming,
  -- not yet strong enough to rename them outright.
  PAIRED_6_7_SET = 0x0CBA,
  [EntityStructLayout.FIELD.UNKNOWN_10] = { get = 0x0CD3, set = 0x0CE4 },
  -- Cross-confirms the $4BE0/$278F "$C4E0 record's own ID byte is used
  -- AS a $C200 slot index" finding via a SECOND, independent code
  -- path: `$404A` (this session's own real per-record tick handler,
  -- see ScriptOpcodeTable.lua) calls `$0CD3` with `C` = the record's
  -- own ID byte, feeding the result into its own internal branch.
  [EntityStructLayout.FIELD.UNKNOWN_11] = { get = 0x0CF7, set = 0x0D08 },
}

-- CONFIRMED (2026-08-14, no longer just a hypothesis): live-traced a
-- real "cut" room transition (thirdRoom -> fourthRoom) end to end --
-- the real landing-position commit chain (`$4992: LD B,0x00 / LD C,
-- 0x04 / CALL $0611`, see `src/import/TileLandingPosition.lua`'s own
-- doc comment for the full trace) passes the LITERAL value `4` as the
-- entity slot index into the SAME real `$0611` position-commit routine
-- this project already fully disassembled for ordinary movement --
-- direct, live, decisive confirmation the player really is slot 4, not
-- just a structural inference from address arithmetic.
EntityStructLayout.PLAYER_SLOT_INDEX_HYPOTHESIS = 4

-- CRACKED (2026-08-14, task 10, "die 6 $02AB-Geschwister wirklich
-- lösen"): the real ROM leaf `$02AB` (shared dependency behind the
-- whole-corpus scan's own known-hard `0x80`/`0xEC`/`0xED`/`0xEE`/
-- `0x81`/`0xA4` opcode family) is nothing more than `LD C,0x04 / CALL
-- $0C99 / RET`, where `$0C99` is a plain, general "read FIELD.ALIVE
-- of slot C" primitive (`HL = $C200+C*16 / A = *(HL)`). With `C`
-- hardcoded to `4` (the PLAYER's own real slot, per
-- `PLAYER_SLOT_INDEX_HYPOTHESIS` above), **`$02AB` simply reads the
-- player's own real `$C240` byte** -- not an opaque, unmodelable leaf.
--
-- Live-traced `$C240`'s own real value across idle/movement/attack
-- (mGBA, `courtyard_enemy_engaged()` checkpoint): the LOW NIBBLE is a
-- real one-hot FACING-DIRECTION bitmask (confirmed decisively: the
-- idle value `0x04` exactly matches "facing up, bit `4`," matching
-- this project's own independently-live-verified `Player
-- .DEFAULT_FACING = "up"`; moving right/left/up/down produced `0x11`/
-- `0x12`/`0x14`/`0x18` -- i.e. `1`/`2`/`4`/`8` in the low nibble). The
-- upper nibble varies with movement/attack sub-state (idle/walk-frame/
-- attack-frame) but is IRRELEVANT to `0x80`'s own real formula
-- (`AND 0x0F`), which masks it away entirely -- `0x80`'s real
-- "dynamic group" is purely a function of the player's CURRENT FACING
-- DIRECTION, independent of movement/attack state. See events.md's
-- own "task 10" entry for the complete live-trace data and the full
-- disassembly.
EntityStructLayout.PLAYER_FACING_BIT = {
  right = 0x01,
  left = 0x02,
  up = 0x04,
  down = 0x08,
}

-- CRACKED (2026-08-14, task "gamemap/connections absolute priority",
-- opcode 0x81/$15B7): a real, general ROM helper (`$29E4`) takes a
-- `PLAYER_FACING_BIT`-shaped low nibble and returns the OPPOSITE
-- direction, via a real bit trick: `AND 0x0F`, then XOR 0x03 on the
-- low pair (bits 0-1, right/left) whenever it's not already zero, XOR
-- 0x0C on the high pair (bits 2-3, up/down) whenever it's not already
-- zero. Worked out by truth table (only one-hot inputs matter, since
-- `$02AB`'s own low nibble is always one-hot per the 0x80 investigation):
-- `0x01<->0x02` (right<->left), `0x04<->0x08` (up<->down), `0x00->0x00`.
-- `$29E4` is a real, general helper -- this table is this project's own
-- Lua-side equivalent (a plain lookup is simpler and exactly as
-- correct as reproducing the bit trick, since the real input is always
-- one-hot in every real call site found so far).
EntityStructLayout.OPPOSITE_FACING = {
  right = "left",
  left = "right",
  up = "down",
  down = "up",
}

--- Real, general helper: the WRAM address of `field` within `slotIndex`.
-- Pure arithmetic, matches the real ROM's own `$C200 + slotIndex*16 +
-- field` computation exactly (both `$0AE3`'s 4x `ADD HL,HL` doubling
-- and `$0A74`'s equivalent `LD DE,0x0010` add reach the same real
-- address).
function EntityStructLayout.address(slotIndex, field)
  return EntityStructLayout.BASE + slotIndex * EntityStructLayout.STRIDE + field
end

return EntityStructLayout
