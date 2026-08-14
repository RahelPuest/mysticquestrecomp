-- Player character stats, matching the VERIFIED WRAM struct layout found
-- by dynamic tracing (see docs/reverse-engineering/rom-map.md "Player
-- stats struct and combat" and "Data Crystal's US-cartridge RAM map").
--
-- Field order/widths mirror the real ROM struct at WRAM $D7B2 exactly
-- (confirmed byte-for-byte against the HUD's `LP 19 MP 6 G 50` at every
-- field, and cross-checked against Data Crystal's independently-derived
-- US-cartridge RAM map, which matched with zero address shift):
--   $D7B2 curLP (u16)   $D7B4 maxLP (u16)
--   $D7B6 curMP (u16)   $D7B8 maxMP (u16)
--   $D7BA level (u8)    $D7BE gold (u16)
-- Not yet included here: the four stats (stamina/power/wisdom/will,
-- $D7C1-$D7C4) and attack/defense power ($D7DF/$D7E0) confirmed present
-- in RAM but not yet wired into any formula this module implements.
--
-- UPDATED (2026-08-10, P1 revisited): live-traced HOW $D7DF/$D7E0
-- (attack/defense power) actually get computed, not just their
-- addresses (bank 2, file $9801 region) -- a real "total = base stat +
-- equipment bonus" formula, confirmed as a stable, rarely-recomputed
-- value (only 2 writes across a 15-million-step trace spanning title
-- screen through mid-combat, both reassigning the identical value):
--   defense ($D7E0, mirrored via $D6C3) = $D7C1(stamina) + $D6C0 + $D6C2
--   attack  ($D7DF, mirrored via $D6C1) = $D7C2(power)   + CALL $5BA7
-- ($D6C0/$D6C2/the $5BA7 call are plausibly equipment/weapon bonus
-- lookups, tying into the already-decoded `weaponTable` from task P5 --
-- not confirmed this pass). Also found a real, previously-unnoted flag
-- byte at $D7C0 (bit 3 gates whether this whole recompute runs at all)
-- sitting immediately before the four-stat block. See combat.md's
-- "Damage formula" entry for the full trace -- this resolves the
-- damage formula's own `$D6C3` operand as the PLAYER's (not an
-- enemy's) computed defense, redirecting the search for real per-enemy
-- ATK/DEF to the formula's other, still-untraced operand.
--
-- damage() implements the VERIFIED "subtract N from current HP, clamp at
-- zero" primitive (ROM $3E30, see rom-map.md): a real 16-bit subtract
-- with an underflow check that clamps to 0 rather than wrapping negative.
-- What ROM $3E30 does NOT include -- the actual damage-amount formula --
-- is a SEPARATE, now fully-decoded module, `src/entities/CombatFormulas
-- .lua` (`$50AC`, see combat.md's own "FULLY DECODED" section); callers
-- of damage() must supply the amount themselves, this module does not
-- compute one.
--
-- WIRED (2026-08-10): `defense` below is the real, live-captured
-- `$D6C3` value this formula needs as its DEF operand -- see this
-- field's own doc comment just above `Stats.new`.

local Stats = {}
Stats.__index = Stats

-- Real, live-captured `$D6C3` value for a fresh level-1 character (see
-- this file's own doc comment above and rom-map.md's "$D6C3 identified"
-- entry): `defense = $D7C1(stamina) + $D6C0 + $D6C2`, watched from
-- title screen through mid-combat, live value `6`. The full formula's
-- own equipment-bonus terms ($D6C0/$D6C2) aren't decoded, so this
-- won't scale with equipment/level changes -- a real, level-1-only
-- starting value, not a general recompute.
Stats.DEFAULT_DEFENSE = 6

function Stats.new(opts)
  opts = opts or {}
  return setmetatable({
    curLP = opts.curLP or 1,
    maxLP = opts.maxLP or 1,
    curMP = opts.curMP or 0,
    maxMP = opts.maxMP or 0,
    level = opts.level or 1,
    gold = opts.gold or 0,
    defense = opts.defense or Stats.DEFAULT_DEFENSE,
  }, Stats)
end

--- Subtract `amount` from current LP, clamped at 0 (never negative) --
-- matches ROM $3E30's verified 16-bit-subtract-with-underflow-check.
-- Returns true if this brought LP to exactly 0 (VERIFIED as the ROM's
-- own death-check condition, immediately following $3E30 at $3E51: an
-- `OR` of both LP bytes, branching only when the result is zero).
function Stats:damage(amount)
  self.curLP = self.curLP - amount
  if self.curLP < 0 then
    self.curLP = 0
  end
  return self.curLP == 0
end

--- Restore `amount` LP, clamped at maxLP. Not itself traced from the ROM
-- (no healing item/spell encountered yet in dynamic play) -- modeled as
-- the mirror image of damage() since that's the conventional pairing,
-- flagged HYPOTHESIS unlike damage()'s verified clamp behavior.
function Stats:heal(amount)
  self.curLP = self.curLP + amount
  if self.curLP > self.maxLP then
    self.curLP = self.maxLP
  end
end

function Stats:isDead()
  return self.curLP == 0
end

return Stats
