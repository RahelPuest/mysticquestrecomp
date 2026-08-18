-- Software square-wave oscillator matching the Game Boy APU's real
-- pulse-channel behavior (channels 1/2 -- see MusicDecoder.lua's doc
-- comment for how channel 3's hardware target is honestly still
-- unconfirmed; this project treats it the same way since it
-- decodes/plays back coherently in practice, per audio.md's note).
--
-- Porting the decoded music format into src/audio/ + love.audio
-- playback. Pure Lua, no love.* calls -- this module only computes
-- PCM sample values; MusicPlayer.lua is what actually hands them to
-- `love.audio` via a queueable source. Kept separate and headlessly
-- testable for the same reason every other `src/import`-adjacent
-- decoder in this project is: a synthesis bug should be catchable by a
-- plain `luajit` test run, not only by listening to the real app.
--
-- HONEST SCOPE: real GB hardware generates each duty-cycle waveform as
-- a literal 8-step bit pattern (Pan Docs), not a continuous ramp. This
-- synth instead holds the output high for exactly `dutyFraction` of
-- each cycle and low for the rest -- audibly the same duty-cycle timbre
-- (the fraction of time high vs. low is what actually shapes the
-- harmonic content a human ear picks up on), but not a bit-exact
-- reproduction of the real 8-step hardware stepping. A deliberate
-- simplification, not a claimed hardware fact.

local GBSquareSynth = {}

-- GB duty-cycle register values (NRx1 bits 7-6) -> the fraction of
-- each cycle the hardware output is high. VERIFIED hardware fact (Pan
-- Docs), independent of this ROM's own data.
GBSquareSynth.DUTY_FRACTIONS = { [0] = 0.125, [1] = 0.25, [2] = 0.5, [3] = 0.75 }

--- Renders `sampleCount` signed 16-bit PCM samples of a square wave at
-- `freqHz` (or silence if `freqHz` is nil/0 -- a REST/gap) into
-- `buffer` (a plain 1-based Lua array) starting at `buffer[bufferIndex]`,
-- overwriting `sampleCount` consecutive slots. `phase` is the
-- oscillator's own position within one cycle (0..1) carried IN from
-- the previous call and returned for the next one, so consecutive
-- calls across note/rest boundaries produce one continuous waveform
-- with no phase-reset click at the seam. `amplitude` is the peak
-- sample value (e.g. 6000 out of the int16 range, real GB channels
-- mix well below full scale so multiple channels can sum without
-- clipping -- a mixing/engineering choice, not a ROM fact).
-- LIVE-FOUND (a `love .` smoke test, song 1 channel 3, rawByte 0x03
-- decoding to period=2046): the GB frequency formula (freq =
-- 131072/(2048-period)) legitimately produces 65536 Hz there --
-- mathematically correct per the formula, but far above human hearing
-- and above this synth's Nyquist limit at any sane sample rate, so
-- naively rendering it would just alias into harsh digital noise, not
-- a "very high note." This is a new, concrete data point for
-- audio.md's already-flagged open question ("channel 3's hardware
-- target may differ from channels 1/2, not independently confirmed")
-- -- a period this extreme is far outside the VERIFIED 85-note musical
-- frequency table's actual range (7 chromatic octaves, topping out
-- nowhere near this), so this byte plausibly means something other
-- than "play this pitch" on channel 3 specifically. Silencing rather
-- than aliasing is the honest choice either way: this project doesn't
-- know what it means, so it doesn't guess a pitch.
local function isAudible(freqHz, sampleRate)
  return freqHz and freqHz > 0 and freqHz < sampleRate / 2
end

function GBSquareSynth.render(buffer, bufferIndex, sampleCount, freqHz, dutyFraction, sampleRate, phase, amplitude)
  dutyFraction = dutyFraction or GBSquareSynth.DUTY_FRACTIONS[2]
  amplitude = amplitude or 6000
  if not isAudible(freqHz, sampleRate) then
    for i = 0, sampleCount - 1 do
      buffer[bufferIndex + i] = 0
    end
    return phase
  end
  local phaseStep = freqHz / sampleRate
  for i = 0, sampleCount - 1 do
    buffer[bufferIndex + i] = (phase < dutyFraction) and amplitude or -amplitude
    phase = (phase + phaseStep) % 1.0
  end
  return phase
end

return GBSquareSynth
