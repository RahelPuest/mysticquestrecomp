-- Real ROM damage formula, `$50AC` (bank 1) -- FULLY DECODED, see
-- docs/reverse-engineering/combat.md's own "$50AC, the real damage
-- formula" section for the full instruction-by-instruction trace and
-- the live encounter that verified it (real enemy ATK=8, register B,
-- matching the live-traced formula's own operand exactly, twice).
--
--   base   = max(0, atk - def) + 1
--   damage = floor(noiseByte * base / 1024) + base
--
-- `atk`/`def` are plain integers (attacker's ATK, defender's computed
-- DEF); `noiseByte` is one real PRNG draw, 0-255 (see CombatNoise.lua,
-- which ports the real ROM routine this formula's own live trace
-- showed feeding it -- not `math.random()`).
--
-- Pure Lua, no state, no love.* calls -- headlessly testable against
-- the exact live-captured registers this formula was decoded from.

local bit = require("bit")

local CombatFormulas = {}

function CombatFormulas.rollDamage(atk, def, noiseByte)
  local base = atk - def
  if base < 0 then
    base = 0
  end
  base = base + 1
  return math.floor((noiseByte * base) / 1024) + base
end

--- Real ROM enemy-HP roll formula, bank 4 `$10340`-`$10372` -- see
-- `Enemy.lua`'s own `HP_INIT_TRACE_NOTE` doc comment and rom-map.md
-- for the full instruction-by-instruction trace this was decoded
-- from. Real shape: `n = noiseByte >> 4` (the noise byte's own high
-- nibble, 0-15, uniform over the 256-byte noise table) feeds a real
-- 16-bit multiply, `HP = ((256-n) * speciesByte) >> 4`.
--
-- VERIFIED for `n = 1..15` (real, live-captured example:
-- `speciesByte=2` -> HP=31 for `n=1..8` [prob 8/16], HP=30 for
-- `n=9..15` [prob 7/16], matching `Enemy.HP_TO_CLEAR`'s own modal
-- value exactly).
--
-- The real ROM's own `n=0` case (odds 1/16) takes a GENUINELY
-- DIFFERENT code path -- a real conditional skip of the multiply
-- entirely (`JR Z` in the ROM routine) whose own real effect is
-- UNEXPLAINED (not independently traced this pass either -- see
-- task #5's own events.md entry for what WAS chased this pass and
-- came back negative). Per this project's own "no silent fallbacks"
-- rule, this is NOT guessed at: a real, loud Lua error instead of a
-- fabricated HP value for that one real 1/16 case, so a caller can't
-- silently ship a wrong number for it.
--
-- `speciesByte`: the real per-species multiplier (row+1 of the
-- per-creature record, see rom-map.md -- `2` for this project's own
-- one live-verified creature). `noiseByte`: one real PRNG draw, 0-255
-- (see `CombatNoise.lua`, the same real noise source `.rollDamage`
-- above uses -- NOT `math.random()`).
function CombatFormulas.rollHP(speciesByte, noiseByte)
  local n = bit.rshift(noiseByte, 4)
  assert(n >= 1, "CombatFormulas.rollHP: real ROM n=0 case (noiseByte < 16) " ..
    "takes an unexplained, different code path -- not modeled here, see " ..
    "Enemy.lua's own HP_INIT_TRACE_NOTE and this function's own doc comment")
  return bit.rshift((256 - n) * speciesByte, 4)
end

return CombatFormulas
