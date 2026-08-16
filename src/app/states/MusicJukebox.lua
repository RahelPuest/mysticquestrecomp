-- DEV-ONLY music browser for all 30 real songs this project's own
-- MusicDecoder/MusicScore/MusicPlayer pipeline can now actually play
-- through `love.audio` (task #151, 2026-08-16, "port the decoded
-- music format into src/audio/ + love.audio playback"). Same "real
-- content, no fabricated trigger" precedent as RoomExplorer.lua (F8):
-- no live ROM trigger for "which song plays at which real game
-- moment" has been found yet (see docs/reverse-engineering/rom-map.md
-- "Audio format -- DECODED"), so this is an explicit, clearly-labeled
-- developer shortcut (F9 from Field.lua) rather than a fabricated
-- in-fiction music cue.
--
-- Controls: A = next song, B = previous song, START = play/pause the
-- current song, SELECT or F9 = stop and exit back to Field.

local MusicPlayer = require("src.audio.MusicPlayer")
local MusicDecoder = require("src.import.MusicDecoder")

local MusicJukebox = { opaque = true }
MusicJukebox.__index = MusicJukebox

local SONG_COUNT_FALLBACK = 30 -- real, VERIFIED table size (rom-map.md) -- used only if loadSongTable somehow returns fewer (defensive, not expected)

function MusicJukebox.new(romData, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    input = input,
    overlay = overlay,
    stack = stack,
    songIndex = 1,
    player = MusicPlayer.new(romData),
    statusMessage = "",
  }, MusicJukebox)

  self.songs = MusicDecoder.loadSongTable(romData)
  self.songCount = math.max(#self.songs, SONG_COUNT_FALLBACK)
  return self
end

function MusicJukebox:_playCurrent()
  local ok, err = self.player:play(self.songIndex)
  self.statusMessage = ok and "" or ("kein Playback: " .. tostring(err))
end

function MusicJukebox:keypressed(key)
  if key == "f9" and self.stack then
    self.stack:pop()
  end
end

function MusicJukebox:update(dt)
  if self.stack and self.input:pressed("select") then
    self.player:stop()
    self.stack:pop()
    return
  end
  if self.input:pressed("a") then
    self.songIndex = self.songIndex % self.songCount + 1
    self:_playCurrent()
  elseif self.input:pressed("b") then
    self.songIndex = (self.songIndex - 2) % self.songCount + 1
    self:_playCurrent()
  elseif self.input:pressed("start") then
    if self.player:isPlaying() then
      self.player:stop()
    else
      self:_playCurrent()
    end
  end
  self.player:update(dt)
end

-- Real state-stack lifecycle hook (see StateStack.lua's own doc
-- comment: `:exit()` runs on pop) -- makes sure leaving this screen by
-- ANY path (SELECT, F9, or a future caller replacing the whole stack)
-- always releases the real `love.audio` sources instead of leaving
-- them playing silently in the background.
function MusicJukebox:exit()
  self.player:stop()
end

-- Plain, love.*-free state snapshot (see main.lua's own
-- MYSTICQUEST_WAIT_FOR/MYSTICQUEST_STATE_LOG doc comments -- the same
-- convention Field.lua/VictorySequence.lua already use). Used to
-- LIVE-VERIFY real playback progress (2026-08-16, task #151): each
-- channel's own `segIndex` only advances once its current segment's
-- real audio has actually been synthesized and queued, so watching it
-- climb across real frames is direct, numeric proof the pipeline is
-- genuinely streaming -- not just "no crash happened."
function MusicJukebox:debugState()
  local state = {
    songIndex = self.songIndex,
    playing = self.player:isPlaying(),
    channelCount = #self.player.channels,
  }
  for i, c in ipairs(self.player.channels) do
    state["ch" .. i .. "_segIndex"] = c.segIndex
    state["ch" .. i .. "_segCount"] = #c.score.segments
    state["ch" .. i .. "_freeBuffers"] = c.source:getFreeBufferCount()
    state["ch" .. i .. "_sourcePlaying"] = c.source:isPlaying()
  end
  return state
end

function MusicJukebox:draw()
  love.graphics.setColor(0.05, 0.05, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(
    string.format("DEV Jukebox: Song %d/%d", self.songIndex, self.songCount), 4, 4)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(
    self.player:isPlaying() and "spielt..." or "gestoppt", 4, 20)
  if self.statusMessage ~= "" then
    love.graphics.setColor(1, 0.5, 0.5, 1)
    love.graphics.print(self.statusMessage, 4, 36)
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.print("A/B Song, START Play/Stop, SELECT/F9 Exit", 4, 128)

  if self.overlay then
    self.overlay:addLine("jukebox (dev-only, kein bekannter echter Trigger)",
      string.format("Song %d/%d, %d echte Kanäle aktiv", self.songIndex, self.songCount, #self.player.channels))
  end
end

return MusicJukebox
