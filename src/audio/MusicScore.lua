-- Converts one `MusicDecoder.decodeChannel` event array into a flat,
-- playback-ready "score": a list of `{freqHz, seconds, duty}` segments
-- (silence has `freqHz = nil`), plus a `loopToIndex` telling playback
-- which segment to resume from once the score ends -- the ROM's repeat
-- point (a `0xE1` JUMP), not necessarily segment 1 (most songs have a
-- short non-repeating intro before the loop).
--
-- Porting the decoded music format into src/audio/ + love.audio
-- playback. Pure Lua, no love.* calls -- this is the layer between the
-- ROM-format decoder (MusicDecoder, already headlessly tested against
-- ROM bytes) and the LÖVE-facing player (MusicPlayer.lua,
-- GBSquareSynth.lua), so a scoring bug is catchable without ever
-- touching real audio hardware.
--
-- HONEST SCOPE (matches MusicDecoder.lua's and audio.md's notes):
-- several driver commands this project has disassembled but not
-- modeled here (`0xE2`/`0xE3`/`0xE4`/`0xE7`/`0xE9`/`0xEA`/`0xEB`/`0xEC`
-- -- pitch-bend/vibrato/tempo/panning/priority) are simply skipped (no
-- audio effect) -- this produces the melody and rhythm, duty-cycle
-- timbre, and loop structure, but not the fine per-frame vibrato layer
-- or stereo panning. Documented, not silently missing.

local FixedStep = require("src.core.FixedStep")
local GBSquareSynth = require("src.audio.GBSquareSynth")

local MusicScore = {}

local function dutyFraction(duty)
  return GBSquareSynth.DUTY_FRACTIONS[duty] or GBSquareSynth.DUTY_FRACTIONS[2]
end

--- `events`: the array `MusicDecoder.decodeChannel` returns. Returns
-- `{ segments = {...}, loopToIndex = N or nil }`.
function MusicScore.build(events)
  local segments = {}
  local currentDuty = 2 -- GB power-on default (50%) until a real 0xE5 sets one
  local loopToFileOffset = nil

  for _, e in ipairs(events) do
    if e.type == "NOTE" then
      local freqHz = 131072.0 / (2048 - e.period)
      segments[#segments + 1] = {
        freqHz = freqHz,
        seconds = (e.durationFrames or 0) / FixedStep.HZ,
        duty = dutyFraction(currentDuty),
        startFileOffset = e.startFileOffset,
      }
    elseif e.type == "REST" or e.type == "NOTE_OFF" then
      -- Both are silence from this synth's honest-scope point of view:
      -- REST plays nothing by definition, and NOTE_OFF (an explicit
      -- early cutoff) has no separate "release" envelope this project
      -- models -- immediate silence is the closest approximation
      -- without fabricating an envelope shape.
      segments[#segments + 1] = {
        freqHz = nil,
        seconds = (e.durationFrames or 0) / FixedStep.HZ,
        duty = dutyFraction(currentDuty),
        startFileOffset = e.startFileOffset,
      }
    elseif e.type == "COMMAND" and e.byte == 0xE5 then
      -- NRx1 duty-cycle write (see MusicDecoder.lua's COMMAND_NAMES
      -- doc) -- bits 7-6 of the raw operand byte.
      currentDuty = math.floor((e.operand[1] or 0) / 64) % 4
    elseif e.type == "COMMAND" and e.byte == 0xE1 and e.jumpTarget then
      loopToFileOffset = e.jumpTarget
      break -- an unconditional JUMP always ends the walkable event list
    elseif e.type == "STOP" or e.type == "EOF" or e.type == "LOOP_DETECTED" then
      break
    end
    -- Every other event type (SET_OCTAVE/SHIFT_OCTAVE, and COMMAND
    -- bytes not handled above) has no direct audio segment --
    -- SET_OCTAVE/SHIFT_OCTAVE only affect which frequency-table note a
    -- later NOTE event resolves to, already baked into that NOTE
    -- event's `period` by MusicDecoder itself.
  end

  local loopToIndex = nil
  if loopToFileOffset then
    for i, seg in ipairs(segments) do
      if seg.startFileOffset == loopToFileOffset then
        loopToIndex = i
        break
      end
    end
    -- Honest fallback: if the jump target doesn't line up with any
    -- decoded segment's start (e.g. it lands on a byte this decoder's
    -- event walk never visited as a segment boundary), loop from the
    -- beginning rather than not looping at all -- still real ROM
    -- melody, just not necessarily starting exactly where the hardware
    -- repeat does.
    loopToIndex = loopToIndex or 1
  end

  return { segments = segments, loopToIndex = loopToIndex }
end

return MusicScore
