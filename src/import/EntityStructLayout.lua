-- The real, general WRAM entity-slot struct this ROM uses for the
-- player, enemies, and NPCs alike -- found 2026-08-13 while chasing
-- the "where is the player's real spawn/landing position encoded"
-- question (see docs/reverse-engineering/rom-map.md's own
-- "Consolidated reference: the general room/map system" section, and
-- events.md's "spawn position + trigger zones" investigation, for the
-- full disassembly trail this is distilled from).
--
-- Real, VERIFIED base/stride: `$C200 + slotIndex*16`, 20 real slots
-- (0-19) -- confirmed via TWO independent real routines that both
-- compute this exact address:
--   `$0AE3` (the real, general entity DESPAWN primitive, already
--   documented via the enemy-death-dispatch chain) -- receives a real
--   slot index in `C`, computes `HL = $C200 + C*16` via 4 real
--   `ADD HL,HL` doublings (`C*2*2*2*2 = C*16`), zeroes fields `+4`/
--   `+5`/`+8`/`+9`, and memsets that slot's own 8-byte OAM shadow-copy
--   block (pointed to by `+8`/`+9`).
--   `$0A74` (the real, general entity ALLOCATE primitive -- the exact
--   structural counterpart, found this same investigation): scans up
--   to 20 real slots (`LD B,0x14`) for the first with `+0 == 0xFF`
--   (the dead/empty sentinel), then initializes every field below.
--
-- Pure Lua, no love.* calls, no ROM bytes needed to define the layout
-- itself (it's a real WRAM/code CONVENTION, not something read from
-- ROM data at runtime) -- but see `tests/import/entity_struct_layout_
-- test.lua` for real byte-level cross-checks against the actual
-- disassembly this file documents.

local EntityStructLayout = {}

EntityStructLayout.BASE = 0xC200
EntityStructLayout.STRIDE = 16
EntityStructLayout.SLOT_COUNT = 20

-- Real per-slot field offsets (0-based, within one 16-byte record).
EntityStructLayout.FIELD = {
  ALIVE = 0,     -- alive/state byte: 0xFF = dead/empty sentinel; 0x08 on real allocate
  TYPE = 1,      -- caller-supplied "type" param (real ROM meaning not decoded further)
  PARAM2 = 2,    -- caller-supplied param
  PARAM3 = 3,    -- real 0 at allocate time
  POSITION_Y = 4,   -- real Y position, pixel space
  POSITION_X = 5,   -- real X position, pixel space
  PARAM6 = 6,    -- caller-supplied param
  PARAM7 = 7,    -- caller-supplied param
  OAM_SHADOW_PTR = 8, -- real 16-bit LE pointer to this slot's own 8-byte OAM shadow-copy block
}

-- Real ROM addresses of the two known routines that operate on this
-- struct -- kept here (not just in a doc comment) so future
-- investigation/tests have one real, centralized reference point,
-- matching this project's own "ROM-version-specific data lives in one
-- place" convention.
EntityStructLayout.DESPAWN_ROUTINE_ADDRESS = 0x0AE3
EntityStructLayout.ALLOCATE_ROUTINE_ADDRESS = 0x0A74

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
