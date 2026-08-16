-- Converts one `MusicDecoder.decodeChannel` event array into a flat,
-- playback-ready "score": a list of `{freqHz, seconds, duty}` segments
-- (silence has `freqHz = nil`), plus a `loopToIndex` telling playback
-- which segment to resume from once the score ends -- the real ROM's
-- own repeat point (a `0xE1` JUMP), NOT necessarily segment 1 (most
-- real songs have a short non-repeating intro before the loop).
--
-- Task #151 ("port the decoded music format into src/audio/ + love
-- .audio playback"), 2026-08-16. Pure Lua, no love.* calls -- this is
-- the layer between the ROM-format decoder (MusicDecoder, already
-- headlessly tested against real ROM bytes) and the LÖVE-facing
-- player (MusicPlayer.lua, GBSquareSynth.lua), so a scoring bug is
-- catchable without ever touching real audio hardware.
--
-- HONEST SCOPE (matches MusicDecoder.lua's own and audio.md's own
-- notes): several real driver commands this project has disassembled
-- but not modeled here (`0xE2`/`0xE3`/`0xE4`/`0xE7`/`0xE9`/`0xEA`/
-- `0xEB`/`0xEC` -- pitch-bend/vibrato/tempo/panning/priority) are
-- simply SKIPPED (no audio effect) -- this produces the real melody
-- and rhythm, real duty-cycle timbre, and the real loop structure, but
-- NOT the fine per-frame vibrato layer or stereo panning. Documented,
-- not silently missing.

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
      -- Both are real silence from this synth's own honest-scope point
      -- of view: REST plays nothing by definition, and NOTE_OFF (an
      -- explicit early cutoff) has no separate "release" envelope this
      -- project models -- immediate silence is the closest real
      -- approximation without fabricating an envelope shape.
      segments[#segments + 1] = {
        freqHz = nil,
        seconds = (e.durationFrames or 0) / FixedStep.HZ,
        duty = dutyFraction(currentDuty),
        startFileOffset = e.startFileOffset,
      }
    elseif e.type == "COMMAND" and e.byte == 0xE5 then
      -- Real NRx1 duty-cycle write (see MusicDecoder.lua's own
      -- COMMAND_NAMES doc) -- bits 7-6 of the raw operand byte.
      currentDuty = math.floor((e.operand[1] or 0) / 64) % 4
    elseif e.type == "COMMAND" and e.byte == 0xE1 and e.jumpTarget then
      loopToFileOffset = e.jumpTarget
      break -- a real, unconditional JUMP always ends the walkable event list
    elseif e.type == "STOP" or e.type == "EOF" or e.type == "LOOP_DETECTED" then
      break
    end
    -- Every other real event type (SET_OCTAVE/SHIFT_OCTAVE, and
    -- COMMAND bytes not handled above) has no direct audio segment --
    -- SET_OCTAVE/SHIFT_OCTAVE only affect which frequency-table note a
    -- LATER NOTE event resolves to, already baked into that NOTE
    -- event's own `period` by MusicDecoder itself.
  end

  local loopToIndex = nil
  if loopToFileOffset then
    for i, seg in ipairs(segments) do
      if seg.startFileOffset == loopToFileOffset then
        loopToIndex = i
        break
      end
    end
    -- Real, honest fallback: if the jump target doesn't line up with
    -- any decoded segment's own start (e.g. it lands on a byte this
    -- decoder's own event walk never visited as a segment boundary),
    -- loop from the beginning rather than not looping at all -- still
    -- real ROM melody, just not necessarily starting exactly where the
    -- real hardware's own repeat does.
    loopToIndex = loopToIndex or 1
  end

  return { segments = segments, loopToIndex = loopToIndex }
end

return MusicScore
