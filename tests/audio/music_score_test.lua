local Harness = require("tests.harness")
local MusicScore = require("src.audio.MusicScore")
local MusicDecoder = require("src.import.MusicDecoder")
local FixedStep = require("src.core.FixedStep")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("MusicScore.build: a real NOTE event becomes one segment with the correct freqHz and seconds", function()
  local events = {
    { type = "NOTE", period = 0x0721, durationFrames = 12, startFileOffset = 0 }, -- the same real period this project's own MusicDecoder test already cross-checks as "D5"
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(#score.segments, 1)
  local seg = score.segments[1]
  -- 131072 / (2048 - 0x0721) -- the SAME real GB hardware formula
  -- MusicDecoder.noteName already uses, cross-checked independently.
  Harness.assertTrue(math.abs(seg.freqHz - (131072.0 / (2048 - 0x0721))) < 0.001)
  Harness.assertTrue(math.abs(seg.seconds - 12 / FixedStep.HZ) < 1e-9)
  Harness.assertEqual(seg.duty, 0.5) -- real GB power-on default duty (2 = 50%) until a real 0xE5 overrides it
end)

Harness.test("MusicScore.build: REST and NOTE_OFF both become a real silent segment (freqHz = nil)", function()
  local events = {
    { type = "REST", durationFrames = 24, startFileOffset = 0 },
    { type = "NOTE_OFF", durationFrames = 8, startFileOffset = 1 },
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(#score.segments, 2)
  Harness.assertEqual(score.segments[1].freqHz, nil)
  Harness.assertEqual(score.segments[2].freqHz, nil)
end)

Harness.test("MusicScore.build: a real 0xE5 SET_DUTY command changes the duty of LATER notes only, not earlier ones already scored", function()
  local events = {
    { type = "NOTE", period = 0x0400, durationFrames = 8, startFileOffset = 0 },
    { type = "COMMAND", byte = 0xE5, operand = { 0xC0 }, startFileOffset = 1 }, -- 0xC0 = 11000000 -> duty bits (7-6) = 3 = 75%
    { type = "NOTE", period = 0x0400, durationFrames = 8, startFileOffset = 3 },
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(#score.segments, 2)
  Harness.assertEqual(score.segments[1].duty, 0.5) -- still the real power-on default, command hadn't run yet
  Harness.assertEqual(score.segments[2].duty, 0.75) -- real duty bits 0xC0>>6 = 3 -> DUTY_FRACTIONS[3]
end)

Harness.test("MusicScore.build: a real 0xE1 JUMP resolves loopToIndex to the segment whose startFileOffset matches the jump target", function()
  local events = {
    { type = "COMMAND", byte = 0xE7, operand = { 0 }, startFileOffset = 0 }, -- a real init command with no audio segment -- shouldn't shift indices
    { type = "NOTE", period = 0x0500, durationFrames = 8, startFileOffset = 2 }, -- segment 1, real loop target
    { type = "NOTE", period = 0x0600, durationFrames = 8, startFileOffset = 3 }, -- segment 2
    { type = "COMMAND", byte = 0xE1, operand = { 2, 0 }, jumpTarget = 2, startFileOffset = 4 }, -- jumps back to fileOffset 2
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(#score.segments, 2)
  Harness.assertEqual(score.loopToIndex, 1)
end)

Harness.test("MusicScore.build: an unresolvable jump target falls back to looping from the start rather than not looping at all", function()
  local events = {
    { type = "NOTE", period = 0x0500, durationFrames = 8, startFileOffset = 0 },
    { type = "COMMAND", byte = 0xE1, operand = { 99, 0 }, jumpTarget = 99, startFileOffset = 1 }, -- 99 matches no real segment's own startFileOffset
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(score.loopToIndex, 1)
end)

Harness.test("MusicScore.build: a real STOP/EOF ends the score with no loop point", function()
  local events = {
    { type = "NOTE", period = 0x0500, durationFrames = 8, startFileOffset = 0 },
    { type = "STOP", startFileOffset = 1 },
  }
  local score = MusicScore.build(events)
  Harness.assertEqual(#score.segments, 1)
  Harness.assertEqual(score.loopToIndex, nil)
end)

-- --- ROM-dependent test -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "MusicScore.build: real song 1 channel 1 scores into a real, coherent, looping segment list",
  romData ~= nil,
  "no development ROM found",
  function()
    local songs = MusicDecoder.loadSongTable(romData)
    local events = MusicDecoder.decodeChannel(romData, songs[1][1], 200)
    local score = MusicScore.build(events)
    Harness.assertTrue(#score.segments > 0)
    -- The already-known real opening phrase (see music_decoder_test
    -- .lua): D5, G5, E5 -- first 3 segments should be real notes with
    -- real, positive, musically-plausible frequencies (not silence,
    -- not garbage).
    for i = 1, 3 do
      Harness.assertTrue(score.segments[i].freqHz ~= nil and score.segments[i].freqHz > 0)
    end
    -- This real song does loop (confirmed musically-coherent repeat,
    -- see audio.md) -- expect a real loop point to have been found.
    Harness.assertTrue(score.loopToIndex ~= nil and score.loopToIndex >= 1 and score.loopToIndex <= #score.segments)
  end
)

return true
