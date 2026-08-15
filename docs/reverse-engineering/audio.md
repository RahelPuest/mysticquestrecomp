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

## Priority

No longer the lowest-priority *unknown* — the format is real and
decoded. Actually wiring playback into `love.audio` (synthesizing GB
square-wave channels or rendering to PCM) remains separate, substantial
follow-up work, not attempted this pass.
