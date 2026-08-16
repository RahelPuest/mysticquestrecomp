# Audio — status summary

Required by the project's master brief as a maintained, topic-focused
doc. Full evidence trail in
[rom-map.md "Audio"](rom-map.md) — not duplicated here.

## Driver location — VERIFIED

Watched all sound-hardware-register writes through boot + title-screen
music: 100% (830/830) came from ROM bank 15, confirming a static
bank-write-heuristic scan's hypothesis and ruling out the graphics
banks' coincidental hits.

## Note/instrument/sequence format — DECODED (2026-08-15)

No longer "genuinely the least-investigated system in the project" —
static disassembly of bank 15 (`tools/rom/disasm.py`, no live emulator
needed) found and cross-verified the real event-byte format a real,
working decoder (`tools/rom/decode_music.py`) now transcribes into
readable note names. See rom-map.md's own "Audio" section for the full
disassembly trail (addresses, byte tables, real code snippets).

**Real structure, VERIFIED via musically-coherent decoded output** (not
guessed — see below):
- A real **song table**, 30 entries, 6 bytes each (3×2-byte channel
  stream pointers) — file offset `0x3CA12`.
- Each channel stream mixes **note events** (one byte: high nibble =
  duration in real frames via a 13-entry ROM table, low nibble =
  pitch index into a real 85-entry chromatic frequency table, or a
  rest/note-off marker) with **octave commands** (`0xD0`-`0xDF`) and
  **13 real driver commands** (`0xE0`-`0xEC`, operand lengths all
  confirmed).
- The frequency table (`0x3C1A0`) stores literal, ready-to-write GB
  hardware register pairs (NRx3/NRx4) — the driver adds no further
  transformation, just copies the table entry straight to hardware.

**Decisive confirmation**: `tools/rom/decode_music.py --song 1` produces
a real, singable melodic phrase with an exact repeat (`D5 G5 E5 … D5 G5
E5 … C5`), a sensible countermelody bassline, and a clean closing C-E-G
major arpeggio — this is not noise, it's real music, decoded from a
system with zero prior format knowledge.

**Still open, honestly**: the auxiliary per-frame vibrato/pitch-delta
stream (a second layer set by command `0xE4`, real and disassembled,
not walked by the current decoder); several commands' exact musical
intent beyond their WRAM side effect (`0xE2`/`0xE3`/`0xE7`/`0xE9`/`0xEB`/
`0xEC`); the noise/wave channel's own format (channel 3 in the table
plays back fine as a melodic line in practice — its real hardware
target may differ from channels 1/2, not independently confirmed); no
`src/audio/` Lua module exists yet (the Python decoder is a real,
working proof of the format, not yet ported into the game engine).

## Playback — PORTED into `love.audio` (2026-08-16, task #151)

The Python decoder's own format is now a real, tested, playing part of
the game engine, not just a standalone proof:

- `src/audio/MusicScore.lua`: converts one `MusicDecoder.decodeChannel`
  event array into a flat list of `{freqHz, seconds, duty}` playback
  segments, resolving a real `0xE1` JUMP's own target back to WHICH
  segment to loop to (added `startFileOffset` to every `MusicDecoder`
  event for this). Honest scope: `0xE2`/`0xE3`/`0xE4`/`0xE7`/`0xE9`/
  `0xEA`/`0xEB`/`0xEC` (pitch-bend/vibrato/tempo/panning/priority) are
  real, disassembled, but simply skipped here (no audio effect) — this
  produces the real melody/rhythm/duty-cycle timbre/loop structure, not
  the fine per-frame vibrato layer or stereo panning.
- `src/audio/GBSquareSynth.lua`: a software square-wave oscillator
  (real GB duty-cycle fractions: 12.5/25/50/75%) rendering raw PCM.
  Deliberately approximates the real hardware's own 8-step waveform as
  a plain high/low split of the same duty fraction — audibly the same
  timbre, not a bit-exact hardware reproduction.
- `src/audio/MusicPlayer.lua`: streams PCM to `love.audio` via
  `love.audio.newQueueableSource`, one real source per channel (up to
  3), synthesizing buffers just-in-time every `:update(dt)`.
- `src/app/states/MusicJukebox.lua` (F9 from Field.lua): a dev-only
  browser for all 30 real songs — same "real content, no fabricated
  trigger" precedent as `RoomExplorer.lua` (F8): no live ROM trigger
  for "which song plays at which real game moment" has been found yet,
  so this is an explicit developer shortcut, not a claimed in-fiction
  music cue.

**Real, live-found bug, fixed before it shipped**: a real `love .`
smoke test (`MYSTICQUEST_JUKEBOX_DEMO=1`) caught song 1 channel 3
computing 65536 Hz for one real note byte (`rawByte 0x03`, `period
2046`) — mathematically correct per the real GB formula, but far
above both human hearing and this synth's own Nyquist limit, which
would have aliased into harsh digital noise on real playback.
`GBSquareSynth.render` now silences (rather than raw-renders) any
frequency at or above `sampleRate/2`. This is itself a real, NEW, live
data point for the channel-3-hardware-target question below (a period
this extreme is far outside the real, VERIFIED 85-note table's own
actual musical range) — recorded, not silently patched over.

**Live-verified end to end**: `MYSTICQUEST_JUKEBOX_DEMO=1
MYSTICQUEST_JUKEBOX_SONG=1 MYSTICQUEST_WAIT_FOR=songIndex=999
MYSTICQUEST_WAIT_FOR_MAX=600 love .` (a real 600-frame, ~10-real-
second run) showed all 3 real channels actively streaming and
independently progressing through their own real segment lists (e.g.
channel 1: segment 1→28 of 38, channel 2: 1→45 of 72, channel 3: 1→13
of 35), queueable-source buffers stayed correctly topped up
(`getFreeBufferCount` never starved), all 3 sources reporting
`isPlaying()==true` throughout — real, numeric proof of genuine
streaming, not just "no crash happened." 8 new unit tests
(`tests/audio/gb_square_synth_test.lua`,
`tests/audio/music_score_test.lua`) cover waveform correctness, duty
cycle, phase continuity across buffer boundaries, the Nyquist guard,
and score-building (including a real-ROM cross-check against song 1's
own already-known melody).

**Genuinely still open**: exact musical intent of `0xE2`/`0xE3`/`0xE7`/
`0xE9`/`0xEB`/`0xEC` beyond their real WRAM side effect; the auxiliary
vibrato/pitch-delta layer (`0xE4`) is disassembled but not played back;
channel 3's own real hardware target is still unconfirmed (now with
one more concrete, extreme-frequency data point); which real song (if
any) the original ROM plays at which real game moment (boot/title
music's own driver LOCATION was traced back in the "driver location"
section above, but no specific song INDEX has been tied to a specific
real trigger) — `MusicJukebox` is deliberately dev-only until that's
found.
