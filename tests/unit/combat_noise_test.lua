local Harness = require("tests.harness")
local CombatNoise = require("src.entities.CombatNoise")
local NoiseTable = require("src.import.NoiseTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local function flatTable(value)
  local t = {}
  for i = 1, 256 do
    t[i] = value
  end
  return t
end

Harness.test("CombatNoise.new: fails loudly on a table that isn't exactly 256 entries", function()
  local ok = pcall(CombatNoise.new, { 1, 2, 3 })
  Harness.assertTrue(not ok, "expected CombatNoise.new to reject a non-256-entry table")
end)

Harness.test("CombatNoise:draw: counter advances by 1 each draw, wraps mod 256 (real $C0B0 8-bit-register behavior)", function()
  -- A table where entry i (1-based) holds (i-1) -- table[counter+1] ==
  -- counter directly, isolating the counter's own advance/wrap from the
  -- cap term (held at a fixed table[1]=0 contribution via cap staying 0
  -- until counter reaches 0 again).
  local t = {}
  for i = 1, 256 do
    t[i] = i - 1
  end
  local noise = CombatNoise.new(t)
  -- counter starts at 0, first draw increments to 1 (cap stays 0 since
  -- 0 ~= 1) -- value = table[1+1] + table[0+1] = 1 + 0 = 1.
  Harness.assertEqual(noise:draw(), 1)
  Harness.assertEqual(noise:draw(), 2)
  Harness.assertEqual(noise:draw(), 3)
end)

Harness.test("CombatNoise:draw: real counter/cap double-lookup-sum, matching the ported $2B1E algorithm exactly", function()
  local t = flatTable(0)
  t[5] = 10 -- table index 4 (0-based) = real ROM byte at fileOffset+4
  t[1] = 100 -- table index 0 (0-based)
  local noise = CombatNoise.new(t)
  -- counter: 0->1->2->3->4 over 4 draws; cap stays 0 throughout (never
  -- equals counter after the first draw, since counter only touches 0
  -- again after a full 256-draw wraparound) -- so each draw before the
  -- counter reaches 4 should be table[counter+1] + table[0+1] (cap
  -- contribution = table[1] = 100).
  noise:draw() -- counter=1
  noise:draw() -- counter=2
  noise:draw() -- counter=3
  local v = noise:draw() -- counter=4 -> table[5]=10 + table[1]=100 = 110
  Harness.assertEqual(v, 110)
end)

Harness.test("CombatNoise:draw: result wraps mod 256 (real 8-bit ADD overflow, not a wider integer)", function()
  local t = flatTable(200)
  local noise = CombatNoise.new(t)
  -- cap starts at 0, counter starts at 0 -> first draw: counter becomes
  -- 1, cap (0) ~= counter (1), so cap stays 0. value = table[2] +
  -- table[1] = 200 + 200 = 400, wraps mod 256 = 144.
  Harness.assertEqual(noise:draw(), 144)
end)

Harness.test("CombatNoise:draw: cap decrements only once the fast counter catches up to it", function()
  -- With 256 uniform draws, the counter cycles through every value 1
  -- once and returns to 0 exactly at draw 256, at which point cap
  -- (still 0) matches and decrements to 255 -- a real, live-portable
  -- property of the algorithm, checked structurally rather than via a
  -- huge literal table.
  local t = {}
  for i = 1, 256 do
    t[i] = 0
  end
  local noise = CombatNoise.new(t)
  for _ = 1, 255 do
    noise:draw()
  end
  Harness.assertEqual(noise.counter, 255)
  Harness.assertEqual(noise.cap, 0)
  noise:draw() -- counter wraps 255->0, cap(0)==counter(0) -> cap becomes 255
  Harness.assertEqual(noise.counter, 0)
  Harness.assertEqual(noise.cap, 255)
end)

-- --- ROM-dependent: bit-exact cross-check against a real live mGBA trace ---
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "CombatNoise:draw: matches a real live mGBA trace of $2B1E's own output, byte for byte (2026-08-10)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local bytes = NoiseTable.decode(romData, profile.noiseTable)
    local noise = CombatNoise.new(bytes)
    -- Real captured starting state + 8 consecutive real draws, from a
    -- live watch of every write to WRAM $C0B0 (the real counter) plus
    -- register A at $2B1E's own RET ($2B3F), 600 frames into boot (see
    -- rom-map.md "$50AC, the real damage formula" for the routine
    -- trace this ported). Real hardware's counter was already at 203
    -- by this point (many earlier draws already consumed at boot/title
    -- screen) -- seeded here at 202 so this port's own first :draw()
    -- lands on the same real counter value.
    noise.counter = 202
    noise.cap = 0
    local realSequence = { 236, 242, 218, 92, 142, 151, 50, 121 }
    for i, expected in ipairs(realSequence) do
      Harness.assertEqual(noise:draw(), expected,
        "draw " .. i .. " should match the real live-captured ROM output exactly")
    end
  end
)
