-- LÖVE-facing real music playback -- the actual `love.audio` port task
-- #151 asks for, built on top of the already-tested, pure-Lua
-- MusicDecoder (ROM format) / MusicScore (event-list -> playable
-- segments) / GBSquareSynth (PCM rendering) modules.
--
-- Streams audio via `love.audio.newQueueableSource` (one real GB
-- channel = one queueable source), synthesizing a few buffers'-worth
-- of PCM samples ahead of playback every real `:update(dt)` call
-- rather than pre-rendering a whole song up front -- the same
-- "generate just enough, just in time" shape a real GB APU driver
-- itself uses, and it means an unbounded/looping song never needs an
-- unbounded amount of memory.
--
-- HONEST SCOPE: up to 3 real channels per song (this ROM's own song
-- table format, see MusicDecoder.lua), each independently synthesized
-- and mixed by the OS/hardware audio mixer (3 separate mono sources
-- playing simultaneously) rather than summed into one buffer in
-- software -- simpler, and real GB hardware itself mixes its own
-- channels this way (independent DACs summed on the analog side), so
-- this isn't a meaningful fidelity loss. No live ROM trigger for
-- "which song plays when" has been found yet (see rom-map.md's own
-- "Audio format -- DECODED" section) -- this module only knows how to
-- play song N on request; deciding which N to play for which real
-- game moment is separate, undone work. Wired to a dev-only jukebox
-- (`src/app/states/MusicJukebox.lua`, F9 from Field.lua) for now, same
-- "real content, no fabricated trigger" precedent as RoomExplorer.lua.

local MusicDecoder = require("src.import.MusicDecoder")
local MusicScore = require("src.audio.MusicScore")
local GBSquareSynth = require("src.audio.GBSquareSynth")

local MusicPlayer = {}
MusicPlayer.__index = MusicPlayer

local SAMPLE_RATE = 22050 -- plenty for chiptune content (real GB note range tops out well under the ~11kHz Nyquist limit this implies); low enough to keep synthesis cheap
local BUFFER_SECONDS = 0.15 -- how much audio each queued chunk covers
local BUFFER_COUNT = 8 -- queueable-source buffer slots (LÖVE convention: several small buffers, not one giant one, so playback can start quickly and looping/stopping stays responsive)
local CHANNEL_AMPLITUDE = 6000 -- peak PCM value per channel (int16 range +-32767) -- keeps up to 3 simultaneous real channels well under clipping when the OS mixer sums them
local MAX_SEGMENT_ADVANCES_PER_FILL = 4000 -- safety bound against a degenerate all-zero-duration score spinning this project's own fill loop forever; real songs never come close

function MusicPlayer.new(romData)
  return setmetatable({
    romData = romData,
    channels = {}, -- array of {source, score, segIndex, segElapsed, phase, done}
    songIndex = nil,
  }, MusicPlayer)
end

--- Starts real song `songIndex` (1-based, matching MusicDecoder
-- .loadSongTable's own indexing) playing. Stops whatever was already
-- playing first. Returns true, or false + a reason string if the song
-- table doesn't have that index or every one of its channels decoded
-- to an empty score (e.g. a genuinely silent/placeholder slot).
function MusicPlayer:play(songIndex)
  self:stop()
  local songs = MusicDecoder.loadSongTable(self.romData)
  local song = songs[songIndex]
  if not song then
    return false, "no real song at index " .. tostring(songIndex) .. " (table has " .. #songs .. ")"
  end
  for ch = 1, 3 do
    local events = MusicDecoder.decodeChannel(self.romData, song[ch], 2000)
    local score = MusicScore.build(events)
    if #score.segments > 0 then
      local source = love.audio.newQueueableSource(SAMPLE_RATE, 16, 1, BUFFER_COUNT)
      self.channels[#self.channels + 1] = {
        source = source, score = score, segIndex = 1, segElapsed = 0, phase = 0, done = false,
      }
    end
  end
  if #self.channels == 0 then
    return false, "song " .. tostring(songIndex) .. " decoded to zero playable segments on all 3 channels"
  end
  self.songIndex = songIndex
  for _, c in ipairs(self.channels) do
    self:_fillChannel(c) -- prime the first buffers before starting playback, so there's no initial silence gap
    c.source:play()
  end
  return true
end

function MusicPlayer:stop()
  for _, c in ipairs(self.channels) do
    c.source:stop()
  end
  self.channels = {}
  self.songIndex = nil
end

function MusicPlayer:isPlaying()
  return #self.channels > 0
end

--- Call once per real frame. Keeps every channel's queueable source
-- topped up; a channel with no real loop point (score.loopToIndex ==
-- nil) naturally runs out of segments and goes quiet on its own once
-- its own already-queued audio finishes, same as the real ROM's own
-- one-shot (non-looping) streams would.
function MusicPlayer:update(dt)
  for _, c in ipairs(self.channels) do
    if not c.done then
      self:_fillChannel(c)
    end
  end
end

function MusicPlayer:_fillChannel(c)
  local sampleCount = math.floor(SAMPLE_RATE * BUFFER_SECONDS)
  while c.source:getFreeBufferCount() > 0 and not c.done do
    local buffer = {}
    local filled = 0
    local advances = 0
    while filled < sampleCount do
      local seg = c.score.segments[c.segIndex]
      if not seg then
        if c.score.loopToIndex then
          c.segIndex = c.score.loopToIndex
          c.segElapsed = 0
          seg = c.score.segments[c.segIndex]
        end
        if not seg then
          -- Real one-shot stream ended with no loop point: pad the
          -- rest of this final buffer with silence and mark done --
          -- no more buffers get queued after this one.
          for i = filled + 1, sampleCount do buffer[i] = 0 end
          filled = sampleCount
          c.done = true
          break
        end
      end
      local samplesLeftInSeg = math.max(0, math.floor((seg.seconds - c.segElapsed) * SAMPLE_RATE))
      local samplesToRender = math.min(samplesLeftInSeg, sampleCount - filled)
      if samplesToRender <= 0 then
        c.segIndex = c.segIndex + 1
        c.segElapsed = 0
        advances = advances + 1
        if advances > MAX_SEGMENT_ADVANCES_PER_FILL then
          -- Degenerate score (every remaining segment has ~0 real
          -- duration) -- bail out to silence rather than spin forever;
          -- a real song never approaches this bound.
          for i = filled + 1, sampleCount do buffer[i] = 0 end
          filled = sampleCount
          c.done = true
          break
        end
      else
        c.phase = GBSquareSynth.render(buffer, filled + 1, samplesToRender, seg.freqHz, seg.duty, SAMPLE_RATE, c.phase, CHANNEL_AMPLITUDE)
        filled = filled + samplesToRender
        c.segElapsed = c.segElapsed + samplesToRender / SAMPLE_RATE
        if c.segElapsed >= seg.seconds - 1e-9 then
          c.segIndex = c.segIndex + 1
          c.segElapsed = 0
        end
      end
    end

    local soundData = love.sound.newSoundData(sampleCount, SAMPLE_RATE, 16, 1)
    for i = 0, sampleCount - 1 do
      soundData:setSample(i, (buffer[i + 1] or 0) / 32768)
    end
    c.source:queue(soundData)
  end
end

return MusicPlayer
