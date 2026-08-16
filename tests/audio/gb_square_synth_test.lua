local Harness = require("tests.harness")
local GBSquareSynth = require("src.audio.GBSquareSynth")

Harness.test("GBSquareSynth.render: nil freqHz (a real REST) produces pure silence", function()
  local buffer = {}
  GBSquareSynth.render(buffer, 1, 100, nil, 0.5, 22050, 0, 6000)
  for i = 1, 100 do
    Harness.assertEqual(buffer[i], 0)
  end
end)

Harness.test("GBSquareSynth.render: only ever emits +amplitude/-amplitude (a real square wave, no intermediate levels)", function()
  local buffer = {}
  GBSquareSynth.render(buffer, 1, 500, 440, 0.5, 22050, 0, 6000)
  for i = 1, 500 do
    Harness.assertTrue(buffer[i] == 6000 or buffer[i] == -6000,
      "sample " .. i .. " was " .. tostring(buffer[i]) .. ", expected exactly +-6000")
  end
end)

Harness.test("GBSquareSynth.render: the real duty-cycle fraction controls how much of each cycle is high, not just an arbitrary 50/50 split", function()
  -- A frequency chosen so one full cycle divides evenly into the
  -- sample buffer (sampleRate/freqHz = 100 samples/cycle, 10 full
  -- cycles in 1000 samples) -- makes the expected high-sample COUNT an
  -- exact, not approximate, real number to assert against.
  local sampleRate = 10000
  local freqHz = 100
  local totalSamples = 1000 -- exactly 10 cycles
  for _, duty in ipairs({ { GBSquareSynth.DUTY_FRACTIONS[0], 0.125 }, { GBSquareSynth.DUTY_FRACTIONS[1], 0.25 },
                           { GBSquareSynth.DUTY_FRACTIONS[2], 0.5 }, { GBSquareSynth.DUTY_FRACTIONS[3], 0.75 } }) do
    local dutyFraction = duty[1]
    local buffer = {}
    GBSquareSynth.render(buffer, 1, totalSamples, freqHz, dutyFraction, sampleRate, 0, 100)
    local highCount = 0
    for i = 1, totalSamples do
      if buffer[i] > 0 then highCount = highCount + 1 end
    end
    local expected = totalSamples * dutyFraction
    Harness.assertTrue(math.abs(highCount - expected) <= 10,
      string.format("duty %.3f: expected ~%d high samples, got %d", dutyFraction, expected, highCount))
  end
end)

Harness.test("GBSquareSynth.render: phase carries across consecutive calls -- splitting one render into two chunks matches one big call exactly", function()
  local wholeBuffer = {}
  GBSquareSynth.render(wholeBuffer, 1, 300, 440, 0.5, 22050, 0, 6000)

  local splitBuffer = {}
  local phase = GBSquareSynth.render(splitBuffer, 1, 137, 440, 0.5, 22050, 0, 6000)
  GBSquareSynth.render(splitBuffer, 138, 163, 440, 0.5, 22050, phase, 6000)

  for i = 1, 300 do
    Harness.assertEqual(splitBuffer[i], wholeBuffer[i],
      "sample " .. i .. " diverged between one-shot and split rendering -- phase continuity broke")
  end
end)

Harness.test("GBSquareSynth.render: a real REST->NOTE transition (nil then a real frequency) starts the note at phase 0, no leftover state from the silence", function()
  local buffer = {}
  local phase = GBSquareSynth.render(buffer, 1, 50, nil, 0.5, 22050, 0, 6000)
  Harness.assertEqual(phase, 0) -- silence never advances phase -- see this function's own early-return branch
  GBSquareSynth.render(buffer, 51, 50, 440, 0.5, 22050, phase, 6000)
  Harness.assertEqual(buffer[51], 6000) -- phase 0 is always the start of the "high" half of any real duty cycle
end)

Harness.test("GBSquareSynth.render: a frequency at/above Nyquist (would alias into noise) is silenced, not rendered raw", function()
  -- LIVE-FOUND 2026-08-16 (real `love .` smoke test, song 1 channel 3):
  -- the real GB formula genuinely produces 65536 Hz for one real note
  -- byte -- see this module's own doc comment for the full story. At a
  -- real 22050 Hz sample rate (Nyquist 11025 Hz), that must come out
  -- as silence, not raw aliased noise.
  local buffer = {}
  GBSquareSynth.render(buffer, 1, 100, 65536, 0.5, 22050, 0, 6000)
  for i = 1, 100 do
    Harness.assertEqual(buffer[i], 0)
  end
end)

Harness.test("GBSquareSynth.render: a real, ordinary musical frequency well under Nyquist still renders normally", function()
  local buffer = {}
  GBSquareSynth.render(buffer, 1, 100, 440, 0.5, 22050, 0, 6000)
  local sawNonZero = false
  for i = 1, 100 do
    if buffer[i] ~= 0 then sawNonZero = true end
  end
  Harness.assertTrue(sawNonZero, "a real, audible 440Hz note should not be silenced")
end)

return true
