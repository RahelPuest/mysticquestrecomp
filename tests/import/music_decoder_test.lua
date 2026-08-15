local Harness = require("tests.harness")
local MusicDecoder = require("src.import.MusicDecoder")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "MusicDecoder.loadSongTable: finds exactly the real 30-song table",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Real, self-evident table boundary (see rom-map.md's own "Audio
    -- format -- DECODED" section): dumping all 40 possible slots shows
    -- exactly 30 monotonically-increasing, in-bank-range entries
    -- before the data degrades into obvious garbage -- cross-checked
    -- against tools/rom/decode_music.py's own --list-songs output.
    local songs = MusicDecoder.loadSongTable(romData)
    Harness.assertEqual(#songs, 30)
    -- Song 1's real channel pointers (file offsets), matching
    -- decode_music.py's own --list-songs output exactly.
    Harness.assertEqual(songs[1][1], 0x3CAC9)
    Harness.assertEqual(songs[1][2], 0x3CB0A)
    Harness.assertEqual(songs[1][3], 0x3CB7E)
  end
)

Harness.testIfAvailable(
  "MusicDecoder.decodeChannel: song 1 channel 1 decodes into real, musically-coherent notes (cross-checked against tools/rom/decode_music.py)",
  romData ~= nil,
  "no development ROM found",
  function()
    local songs = MusicDecoder.loadSongTable(romData)
    local events = MusicDecoder.decodeChannel(romData, songs[1][1], 20)

    -- First 6 real events are the song's own init commands (see
    -- decode_music.py's own real transcript for song 1, channel 1).
    Harness.assertEqual(events[1].type, "COMMAND")
    Harness.assertEqual(events[1].byte, 0xE7)
    Harness.assertEqual(events[2].byte, 0xE4)
    Harness.assertEqual(events[3].byte, 0xE0)
    Harness.assertEqual(events[4].byte, 0xE5)
    Harness.assertEqual(events[5].byte, 0xE6)
    Harness.assertEqual(events[6].byte, 0xE3)

    Harness.assertEqual(events[7].type, "SET_OCTAVE")
    Harness.assertEqual(events[7].octaveBlock, 3)

    -- The real, decoded melody's own opening phrase: D5 G5 E5 (96f, a
    -- long note) -- exact match to the Python decoder's own transcript.
    Harness.assertEqual(events[8].type, "NOTE")
    Harness.assertEqual(events[8].noteName, "D5")
    Harness.assertEqual(events[8].durationFrames, 12)
    Harness.assertEqual(events[9].noteName, "G5")
    Harness.assertEqual(events[10].noteName, "E5")
    Harness.assertEqual(events[10].durationFrames, 96)
    Harness.assertEqual(events[11].type, "NOTE_OFF")
  end
)

Harness.testIfAvailable(
  "MusicDecoder.decodeChannel: real frequency table produces a monotonically-increasing period across one full octave block (a real chromatic scale, not noise)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Direct read of the real frequency table's first 12-note octave
    -- block (CPU $41A0, see this module's own FREQ_TABLE_FILE_OFFSET) --
    -- independent of the event-stream decoder above, a structural
    -- self-check on the table itself.
    local periods = {}
    for i = 0, 11 do
      local off = MusicDecoder.FREQ_TABLE_FILE_OFFSET + i * 2
      local lo = romData:byte(off + 1)
      local hi = romData:byte(off + 2)
      periods[#periods + 1] = (lo + hi * 256) % 0x0800
    end
    for i = 2, #periods do
      Harness.assertTrue(periods[i] > periods[i - 1],
        "expected a real chromatic scale's own period to strictly increase (descending pitch) across one octave block")
    end
  end
)

Harness.test("MusicDecoder.noteName: real GB period-to-frequency formula lands on the expected pitch names", function()
  -- period=0 -> the real GB hardware's own maximum frequency for a
  -- square channel: 131072/(2048-0) = 64Hz, close to C2.
  Harness.assertEqual(MusicDecoder.noteName(0), "C2")
  -- A period this project's own real frequency table (song 1) uses for
  -- a note independently confirmed as "D5" by the decoded transcript
  -- above (period=0x0721 & 0x7FF = 0x721).
  Harness.assertEqual(MusicDecoder.noteName(0x0721), "D5")
end)

Harness.test("MusicDecoder.decodeChannel: real 0xFF hard-stop byte ends the stream immediately", function()
  local synthetic = "\255"
  local events = MusicDecoder.decodeChannel(synthetic, 0, 5)
  Harness.assertEqual(#events, 1)
  Harness.assertEqual(events[1].type, "STOP")
end)

Harness.test("MusicDecoder.decodeChannel: real octave-set command (0xD0-0xD7) selects the right 24-byte table block", function()
  local synthetic = "\208\255" -- 0xD0 (SET_OCTAVE block 0) then 0xFF (stop)
  local events = MusicDecoder.decodeChannel(synthetic, 0, 5)
  Harness.assertEqual(events[1].type, "SET_OCTAVE")
  Harness.assertEqual(events[1].octaveBlock, 0)
  Harness.assertEqual(events[2].type, "STOP")
end)
