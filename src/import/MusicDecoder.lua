-- Decodes the real Bank 15 music/sound driver's event-byte format into
-- a real note transcript -- a direct Lua port of `tools/rom/
-- decode_music.py` (the tool this format was originally found and
-- proven with, 2026-08-15, direct user request "schau dir mal das
-- musik und sound system an und entschluessel es"). See that Python
-- file's own doc comment and docs/reverse-engineering/rom-map.md's
-- "Audio format -- DECODED" section for the full disassembly trail
-- (real ROM addresses, byte tables, code snippets) -- not repeated
-- here. Kept in sync with the Python version by hand; if one changes,
-- update the other.
--
-- Pure Lua, no love.* calls, so it's headlessly testable like every
-- other `src/import/*` module -- this is the SAME module task #151
-- (porting real playback into the game engine) will build on, not a
-- website-only throwaway.

local MusicDecoder = {}

local BANK_START_ADDR = 0x4000
local BANK_FILE_BASE = 0x3C000 -- bank 15 * 0x4000
MusicDecoder.SONG_TABLE_FILE_OFFSET = 0x3CA12
MusicDecoder.FREQ_TABLE_FILE_OFFSET = 0x3C1A0
MusicDecoder.DURATION_TABLE_FILE_OFFSET = 0x3C24A
MusicDecoder.OCTAVE_SHIFT_TABLE_FILE_OFFSET = 0x3C7D1 -- CPU $47D1

MusicDecoder.NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- Real operand lengths (bytes consumed from the stream after the
-- command byte itself) -- see decode_music.py's own table for the
-- full evidence (each confirmed by disassembling its real handler).
MusicDecoder.COMMAND_OPERAND_LENGTHS = {
  [0xE0] = 2, [0xE1] = 2, [0xE2] = 2, [0xE3] = 1, [0xE4] = 2, [0xE5] = 1,
  [0xE6] = 1, [0xE7] = 1, [0xE8] = 0, [0xE9] = 2, [0xEA] = 1, [0xEB] = 1, [0xEC] = 1,
}
MusicDecoder.COMMAND_NAMES = {
  [0xE0] = "SAVE_LOOP_POINT", [0xE1] = "JUMP", [0xE2] = "PITCH_SLIDE_A",
  [0xE3] = "SET_PARAM_C10F", [0xE4] = "SET_VIBRATO_STREAM", [0xE5] = "SET_DUTY",
  [0xE6] = "SET_PANNING", [0xE7] = "SET_PARAM_C101", [0xE8] = "NOP(self-jump)",
  [0xE9] = "PITCH_SLIDE_B", [0xEA] = "SET_PARAM_C119", [0xEB] = "PITCH_SLIDE_C",
  [0xEC] = "SET_PARAM_C1C8",
}

local function cpuToFile(addr)
  if addr >= BANK_START_ADDR and addr < 0x8000 then
    return BANK_FILE_BASE + (addr - BANK_START_ADDR)
  end
  return nil
end

local function readWord(romData, fileOffset)
  -- fileOffset is 0-based; Lua string:byte is 1-based.
  local lo = romData:byte(fileOffset + 1)
  local hi = romData:byte(fileOffset + 2)
  if not lo or not hi then return nil end
  return lo + hi * 256
end

--- Loads the real 30-song table (see this module's own doc comment) --
-- returns an array of `{ch1FileOffset, ch2FileOffset, ch3FileOffset}`.
-- Stops at the first slot whose 3 pointers aren't ALL valid bank-15
-- CPU addresses -- the real table's own self-evident boundary (see
-- rom-map.md), not a guessed/hardcoded count.
function MusicDecoder.loadSongTable(romData, maxSongs)
  maxSongs = maxSongs or 40
  local songs = {}
  for i = 0, maxSongs - 1 do
    local off = MusicDecoder.SONG_TABLE_FILE_OFFSET + i * 6
    local ptrs = {}
    local allValid = true
    for j = 0, 2 do
      local w = readWord(romData, off + j * 2)
      local f = w and cpuToFile(w)
      if not f then allValid = false; break end
      ptrs[j + 1] = f
    end
    if not allValid then break end
    songs[#songs + 1] = ptrs
  end
  return songs
end

--- VERIFIED real GB hardware formula: freq_hz = 131072 / (2048 - period).
-- Note-name conversion (A4=440Hz equal temperament) is a DERIVED
-- convenience for readability, not itself a ROM finding.
function MusicDecoder.noteName(period)
  if period >= 2048 then return "?" end
  local freq = 131072.0 / (2048 - period)
  if freq <= 0 then return "?" end
  local midi = 69 + 12 * (math.log(freq / 440.0) / math.log(2))
  local idx = math.floor(midi + 0.5)
  local name = MusicDecoder.NOTE_NAMES[(idx % 12) + 1]
  local octave = math.floor(idx / 12) - 1
  return name .. tostring(octave)
end

--- Walks one real channel event stream starting at a real ROM file
-- offset (already resolved from the song table). Returns an array of
-- event tables, stopping cleanly (not guessing) on an unhandled
-- command or the real terminator. Event `type`s: "NOTE", "REST",
-- "NOTE_OFF", "SET_OCTAVE", "SHIFT_OCTAVE", "COMMAND", "STOP", "EOF".
function MusicDecoder.decodeChannel(romData, startFileOffset, maxEvents)
  maxEvents = maxEvents or 400
  local romLen = #romData
  local events = {}
  local octaveOffset = 0 -- real "c10b" WRAM cell this driver tracks -- byte stride into the 24-byte octave blocks
  local pos = startFileOffset
  local visited = {} -- real position -> true, to detect the real loop-back and stop cleanly instead of looping this decode forever

  for _ = 1, maxEvents do
    if pos >= romLen then
      events[#events + 1] = { type = "EOF" }
      break
    end
    if visited[pos] then
      events[#events + 1] = { type = "LOOP_DETECTED", atFileOffset = pos }
      break
    end
    visited[pos] = true
    local byte = romData:byte(pos + 1)
    pos = pos + 1

    if byte == 0xFF then
      events[#events + 1] = { type = "STOP" }
      break
    elseif byte >= 0xE0 and byte <= 0xEC then
      local operandLen = MusicDecoder.COMMAND_OPERAND_LENGTHS[byte]
      local operand = {}
      for k = 0, operandLen - 1 do
        operand[k + 1] = romData:byte(pos + k + 1)
      end
      -- Real, disassembled JUMP semantics (opcode 0xE1, see this
      -- module's own doc comment / rom-map.md): the 2-byte operand IS
      -- a real CPU address the stream pointer jumps to directly (the
      -- real loop-back mechanism songs use to repeat) -- honored here
      -- so a full transcript/playback follows the real repeating
      -- structure instead of reading past it as inert operand bytes.
      if byte == 0xE1 then
        local target = operand[1] + operand[2] * 256
        local f = cpuToFile(target)
        events[#events + 1] = { type = "COMMAND", byte = byte, name = MusicDecoder.COMMAND_NAMES[byte], operand = operand, jumpTarget = f }
        if f then pos = f end
      else
        pos = pos + operandLen
        events[#events + 1] = { type = "COMMAND", byte = byte, name = MusicDecoder.COMMAND_NAMES[byte], operand = operand }
      end
    elseif byte >= 0xD0 and byte <= 0xD7 then
      octaveOffset = (byte % 8) * 24
      events[#events + 1] = { type = "SET_OCTAVE", octaveBlock = byte % 8 }
    elseif byte >= 0xD8 and byte <= 0xDF then
      local raw = romData:byte(MusicDecoder.OCTAVE_SHIFT_TABLE_FILE_OFFSET + (byte % 8) + 1)
      local signed = raw >= 128 and (raw - 256) or raw
      octaveOffset = (octaveOffset + signed) % 256
      events[#events + 1] = { type = "SHIFT_OCTAVE", rawTableByte = raw, signedDelta = signed }
    else
      local highNibble = math.floor(byte / 16)
      local lowNibble = byte % 16
      local durationFrames = highNibble < 13 and romData:byte(MusicDecoder.DURATION_TABLE_FILE_OFFSET + highNibble + 1) or nil
      if lowNibble == 0x0F then
        events[#events + 1] = { type = "NOTE_OFF", durationFrames = durationFrames }
      elseif lowNibble == 0x0E then
        events[#events + 1] = { type = "REST", durationFrames = durationFrames }
      else
        local tableOff = MusicDecoder.FREQ_TABLE_FILE_OFFSET + octaveOffset + lowNibble * 2
        local rawWord = readWord(romData, tableOff)
        if not rawWord then
          events[#events + 1] = { type = "EOF" }
          break
        end
        local period = rawWord % 0x0800 -- low 8 bits + low 3 bits of high byte
        events[#events + 1] = {
          type = "NOTE", rawByte = byte, noteIndex = lowNibble,
          durationFrames = durationFrames, regPair = rawWord,
          period = period, noteName = MusicDecoder.noteName(period),
        }
      end
    end
  end
  return events
end

return MusicDecoder
