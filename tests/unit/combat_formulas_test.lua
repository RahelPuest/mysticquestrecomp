local Harness = require("tests.harness")
local CombatFormulas = require("src.entities.CombatFormulas")

Harness.test("CombatFormulas.rollDamage: base = max(0, atk-def)+1, no noise contribution when base is small", function()
  -- Real, live-confirmed values: enemy ATK=8, player DEF=6 (see
  -- combat.md's "$50AC" section and Stats.DEFAULT_DEFENSE). base=3, and
  -- 3*noiseByte/1024 rounds to 0 for every possible noiseByte (0-255),
  -- so damage is exactly 3 regardless of the PRNG draw -- a real
  -- property of the formula for this specific pairing, cross-checked
  -- against the OLD, independently-traced Enemy.CONTACT_DAMAGE=3.
  for noiseByte = 0, 255, 17 do
    Harness.assertEqual(CombatFormulas.rollDamage(8, 6, noiseByte), 3)
  end
end)

Harness.test("CombatFormulas.rollDamage: clamps base at 1 when def >= atk (no negative base)", function()
  Harness.assertEqual(CombatFormulas.rollDamage(5, 5, 0), 1)
  Harness.assertEqual(CombatFormulas.rollDamage(2, 20, 0), 1)
end)

Harness.test("CombatFormulas.rollDamage: noise term becomes visible once base is large enough", function()
  -- base = 8 - 0 + 1 = 9. floor(255*9/1024) = 2, so a high noise byte
  -- should push damage above the base-only value.
  local low = CombatFormulas.rollDamage(8, 0, 0)
  local high = CombatFormulas.rollDamage(8, 0, 255)
  Harness.assertEqual(low, 9)
  Harness.assertEqual(high, 11)
  Harness.assertTrue(high > low, "a higher noise byte should never produce lower damage")
end)

Harness.test("CombatFormulas.rollHP: real live-verified speciesByte=2 case matches Enemy.HP_TO_CLEAR's own documented 31/30 split exactly", function()
  -- n = noiseByte >> 4 (the noise byte's own high nibble). n=1..8 (real
  -- noiseByte 16-143) -> HP=31 (the real modal value this project's
  -- own Enemy.HP_TO_CLEAR is pinned to); n=9..15 (real noiseByte
  -- 144-255) -> HP=30. Exhaustively checks EVERY real noiseByte in
  -- each real n's own 16-byte range, not just one sample per n.
  for n = 1, 8 do
    for offset = 0, 15 do
      local noiseByte = n * 16 + offset
      Harness.assertEqual(CombatFormulas.rollHP(2, noiseByte), 31)
    end
  end
  for n = 9, 15 do
    for offset = 0, 15 do
      local noiseByte = n * 16 + offset
      Harness.assertEqual(CombatFormulas.rollHP(2, noiseByte), 30)
    end
  end
end)

Harness.test("CombatFormulas.rollHP: fails loudly (no fabricated value) on the real, unexplained n=0 case", function()
  -- noiseByte 0-15 all shift to n=0 -- the real ROM's own genuinely
  -- different, unexplained code path (see this function's own doc
  -- comment) -- must error, never silently return a guessed HP.
  for noiseByte = 0, 15 do
    Harness.assertTrue(not pcall(CombatFormulas.rollHP, 2, noiseByte),
      "rollHP must fail loudly for noiseByte=" .. noiseByte .. " (real n=0 case)")
  end
end)
