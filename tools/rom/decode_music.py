#!/usr/bin/env python3
"""Decodes the real Bank 15 music/sound driver's event-byte format into a
human-readable note transcript -- see docs/reverse-engineering/audio.md
for the full disassembly trail this is built from (2026-08-15, direct
user request "schau dir mal das musik und sound system an und
entschluessel es").

REAL, VERIFIED structure (found by disassembling bank 15's real code,
not guessed):

- Song table at file offset 0x3CA12 (CPU $4A12, bank 15): 30 real
  songs, 6 bytes/record -- 3 real CPU-address pointers (2 bytes each,
  little-endian), one per "channel" stream. Entry point $3C09E takes a
  1-based song index in A.
- Each channel's own byte stream is read one event at a time:
    - byte == 0xFF: hard stop (silences the channel for good).
    - 0xE0-0xEC: one of 13 real driver COMMANDS (jump table at CPU
      $4365) -- loop-point save/jump and several vibrato/envelope
      commands confirmed; not all 13 fully characterized yet, this
      decoder stops cleanly (does not guess) on an unhandled one.
    - 0xD0-0xD7: SET the current octave directly (low 3 bits, 0-7)
      -- confirmed via the real code computing `(byte&7)*24` and
      storing it as a byte-stride OCTAVE OFFSET into the 24-byte-wide
      (12 notes x 2 bytes) frequency table below.
    - 0xD8-0xDF: ADD a signed octave/detune SHIFT (looked up from an
      8-entry real ROM table, CPU $47D1) instead of overwriting.
    - else (0x00-0xCF): a real NOTE event. High nibble (0-12) indexes
      a real 13-entry DURATION table (CPU $424A, one byte each, real
      frame counts -- values found: 96/72/48/32/36/24/16/18/12/8/6/4/3,
      a musically coherent whole/dotted-half/half/dotted-quarter/
      quarter/... rhythm tree). Low nibble: 0-13 = a real NOTE index
      (0=highest pitch in the current octave); 14 = rest (silence,
      keeps the previous pitch cached but produces no new hardware
      trigger); 15 = explicit note-off.
- Frequency table at CPU $41A0 (file 0x3C1A0): a REAL, ready-to-write
  GB hardware register pair per note (little-endian 16-bit: low byte
  -> NRx3, high byte -> NRx4, already including the trigger bit 7 and
  the period's own top 3 bits in the low nibble) -- 7 full 12-note
  chromatic octave blocks (84 real notes) plus one extra top note (85
  total), monotonically increasing period (= descending pitch) exactly
  as a real chromatic scale should. This decoder writes both the raw
  register pair AND a derived note name (via the real GB period formula,
  freq_hz = 131072 / (2048 - period), converted to nearest equal-
  tempered pitch) for readability -- the register pair is the real,
  verified fact; the note NAME is a derived convenience, not itself an
  independent ROM finding.

NOT decoded by this tool (left honest, not guessed): the auxiliary
per-frame vibrato/delta stream (a SEPARATE pointer set by one of the
0xE0-0xEC commands, adding small per-frame pitch deltas on top of the
cached base frequency -- real, disassembled, but not wired into this
transcript since it's a fine modulation layer, not the core melody);
which commands set the envelope-pointer/instrument; the noise/wave
channel's own real format (channel 3 in the song table almost
certainly drives a differently-shaped stream, not investigated this
pass).
"""
import sys
import argparse

BANK_START_ADDR = 0x4000
BANK_FILE_BASE = 0x3C000  # bank 15 * 0x4000
SONG_TABLE_FILE_OFFSET = 0x3CA12
FREQ_TABLE_FILE_OFFSET = 0x3C1A0
DURATION_TABLE_FILE_OFFSET = 0x3C24A
OCTAVE_SHIFT_TABLE_FILE_OFFSET = 0x3C7D1  # CPU $47D1

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Real operand lengths (bytes consumed from the stream AFTER the command
# byte itself), found by disassembling each of the 13 real jump-table
# targets at CPU $4365 (2026-08-15, see audio.md for the full trail).
# Every command here fetches its operand(s) via the driver's own generic
# "read next stream byte(s), advance the pointer" primitive ($47D9/
# $47E5/$4417) -- confirming these are real, fixed-width instructions,
# not guessed. `name` is a short, evidence-based label; several are
# still only PARTIALLY understood (their WRAM side effect is real and
# disassembled, but not every downstream consequence has been traced)
# -- see audio.md for exactly which.
COMMAND_OPERAND_LENGTHS = {
    0xE0: 2,  # save loop-target address (into a real "resume here" WRAM cell pair)
    0xE1: 2,  # unconditional jump -- sets the stream pointer directly to this address (real loop-back mechanism)
    0xE2: 2,  # conditional pitch-bend/slide setup (real per-frame counter c10f gates a delayed re-check)
    0xE3: 1,  # sets a real per-channel parameter byte (c10f)
    0xE4: 2,  # sets the AUXILIARY note/vibrato-delta stream pointer (c107-c10a) -- see decode_channel's own note on this NOT being walked by this tool
    0xE5: 1,  # writes directly to NRx1 (duty cycle/length) hardware register AND caches the byte (c10c)
    0xE6: 1,  # PANNING: looks up an 8-entry table at CPU $4664 and ORs it into NR51 ($FF25, the real stereo-panning register)
    0xE7: 1,  # sets a real global parameter byte (c101) -- plausibly tempo/speed, not independently confirmed
    0xE8: 0,  # real jump-table target disassembles as a self-jump ("JP $4361" sitting at $4361) -- likely an unused/placeholder slot, treated as a true no-op
    0xE9: 2,  # a second per-channel pitch-bend/slide variant (parallel structure to 0xE2, different WRAM cell c119)
    0xEA: 1,  # sets a real per-channel parameter byte (c119)
    0xEB: 1,  # a third per-channel pitch-bend/slide variant (parallel structure to 0xE2/0xE9)
    0xEC: 1,  # sets a real global parameter byte (c1c8) -- plausibly an SFX-priority/ducking marker, not independently confirmed
}
COMMAND_NAMES = {
    0xE0: "SAVE_LOOP_POINT", 0xE1: "JUMP", 0xE2: "PITCH_SLIDE_A",
    0xE3: "SET_PARAM_C10F", 0xE4: "SET_VIBRATO_STREAM", 0xE5: "SET_DUTY",
    0xE6: "SET_PANNING", 0xE7: "SET_PARAM_C101", 0xE8: "NOP(self-jump)",
    0xE9: "PITCH_SLIDE_B", 0xEA: "SET_PARAM_C119", 0xEB: "PITCH_SLIDE_C",
    0xEC: "SET_PARAM_C1C8",
}


def cpu_to_file(addr):
    if BANK_START_ADDR <= addr < 0x8000:
        return BANK_FILE_BASE + (addr - BANK_START_ADDR)
    return None


def read_word(data, off):
    return data[off] | (data[off + 1] << 8)


def load_song_table(data, max_songs=40):
    songs = []
    for i in range(max_songs):
        off = SONG_TABLE_FILE_OFFSET + i * 6
        ptrs = [read_word(data, off + j * 2) for j in range(3)]
        files = [cpu_to_file(p) for p in ptrs]
        if any(f is None for f in files):
            break  # real table ends here -- ceases to be valid bank-15 pointers
        songs.append(files)
    return songs


def freq_to_note_name(period):
    """VERIFIED formula (real GB hardware): freq_hz = 131072 / (2048 - period).
    Note-name conversion (A4=440Hz equal temperament) is a DERIVED
    convenience for readability, not itself a ROM finding."""
    if period >= 2048:
        return "?"
    freq = 131072.0 / (2048 - period)
    if freq <= 0:
        return "?"
    import math
    midi = 69 + 12 * math.log2(freq / 440.0)
    idx = round(midi)
    name = NOTE_NAMES[idx % 12]
    octave = idx // 12 - 1
    return f"{name}{octave}"


def decode_channel(data, start_file_offset, max_events=400):
    """Walks one real channel event stream starting at a real ROM file
    offset (already resolved from the song table). Returns a list of
    dicts describing each real event, stopping cleanly (not guessing)
    on an unhandled command or the real 0xFF hard-stop byte."""
    events = []
    octave_offset = 0  # real "c10b" WRAM cell this driver tracks -- byte stride into the 24-byte octave blocks
    pos = start_file_offset
    visited = set()  # real position -> seen, to detect the real loop-back and stop cleanly instead of decoding forever
    for _ in range(max_events):
        if pos >= len(data):
            events.append({"type": "EOF"})
            break
        if pos in visited:
            events.append({"type": "LOOP_DETECTED", "atFileOffset": pos})
            break
        visited.add(pos)
        byte = data[pos]
        pos += 1
        if byte == 0xFF:
            events.append({"type": "STOP"})
            break
        if 0xE0 <= byte <= 0xEC:
            operand_len = COMMAND_OPERAND_LENGTHS.get(byte)
            if operand_len is None:
                events.append({"type": "COMMAND", "byte": byte, "note": "operand length not confirmed -- stopping cleanly, not guessing"})
                break
            operand = data[pos:pos + operand_len]
            # Real, disassembled JUMP semantics (opcode 0xE1): the
            # 2-byte operand IS a real CPU address the stream pointer
            # jumps to directly (the real loop-back mechanism songs use
            # to repeat) -- honored here so a full transcript/playback
            # follows the real repeating structure.
            if byte == 0xE1:
                target = operand[0] | (operand[1] << 8)
                f = cpu_to_file(target)
                events.append({"type": "COMMAND", "byte": byte, "name": COMMAND_NAMES.get(byte, "?"), "operand": operand.hex(), "jumpTarget": f})
                if f is not None:
                    pos = f
                continue
            pos += operand_len
            events.append({"type": "COMMAND", "byte": byte, "name": COMMAND_NAMES.get(byte, "?"), "operand": operand.hex()})
            continue
        if 0xD0 <= byte <= 0xD7:
            octave_offset = (byte & 0x07) * 24
            events.append({"type": "SET_OCTAVE", "octaveBlock": byte & 0x07})
            continue
        if 0xD8 <= byte <= 0xDF:
            shift_table = data[OCTAVE_SHIFT_TABLE_FILE_OFFSET:OCTAVE_SHIFT_TABLE_FILE_OFFSET + 8]
            raw = shift_table[byte & 0x07]
            signed = raw - 256 if raw >= 128 else raw
            octave_offset = (octave_offset + signed) & 0xFF
            events.append({"type": "SHIFT_OCTAVE", "rawTableByte": raw, "signedDelta": signed})
            continue
        # else: real note event
        high_nibble = (byte & 0xF0) >> 4
        low_nibble = byte & 0x0F
        duration_table = data[DURATION_TABLE_FILE_OFFSET:DURATION_TABLE_FILE_OFFSET + 13]
        duration_frames = duration_table[high_nibble] if high_nibble < 13 else None
        if low_nibble == 0x0F:
            events.append({"type": "NOTE_OFF", "durationFrames": duration_frames})
            continue
        if low_nibble == 0x0E:
            events.append({"type": "REST", "durationFrames": duration_frames})
            continue
        table_off = FREQ_TABLE_FILE_OFFSET + octave_offset + low_nibble * 2
        if table_off + 1 >= len(data):
            events.append({"type": "EOF"})
            break
        raw_word = read_word(data, table_off)
        period = raw_word & 0x07FF  # low 8 bits + low 3 bits of high byte
        events.append({
            "type": "NOTE", "rawByte": byte, "noteIndex": low_nibble,
            "durationFrames": duration_frames, "regPair": raw_word,
            "period": period, "noteName": freq_to_note_name(period),
        })
    return events


def format_event(e):
    t = e["type"]
    if t == "NOTE":
        return f"NOTE  {e['noteName']:>4}  dur={e['durationFrames']:>3}f  reg=0x{e['regPair']:04x} (raw byte 0x{e['rawByte']:02x})"
    if t == "REST":
        return f"REST         dur={e['durationFrames']:>3}f"
    if t == "NOTE_OFF":
        return f"NOTE_OFF     dur={e['durationFrames']:>3}f"
    if t == "SET_OCTAVE":
        return f"SET_OCTAVE   block={e['octaveBlock']}"
    if t == "SHIFT_OCTAVE":
        return f"SHIFT_OCTAVE delta={e['signedDelta']:+d} (raw table byte 0x{e['rawTableByte']:02x})"
    if t == "COMMAND":
        if "note" in e:
            return f"COMMAND      0x{e['byte']:02x} -- {e['note']}"
        if e.get("jumpTarget") is not None:
            return f"COMMAND      0x{e['byte']:02x} {e['name']:<18} operand={e['operand']} -> file {hex(e['jumpTarget'])}"
        return f"COMMAND      0x{e['byte']:02x} {e['name']:<18} operand={e['operand']}"
    if t == "LOOP_DETECTED":
        return f"LOOP_DETECTED (real stream returns to file {hex(e['atFileOffset'])} -- this IS the real song repeating, not a decoder bug)"
    if t == "STOP":
        return "STOP (real 0xFF)"
    if t == "EOF":
        return "(ran off the end of the ROM data given to this decoder)"
    return str(e)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    ap.add_argument("--song", type=int, default=1, help="1-based song index (real table has 30 real entries)")
    ap.add_argument("--list-songs", action="store_true")
    ap.add_argument("--max-events", type=int, default=60)
    args = ap.parse_args()

    data = open(args.rom, "rb").read()
    songs = load_song_table(data)

    if args.list_songs:
        print(f"{len(songs)} real songs found in the song table (file offset {hex(SONG_TABLE_FILE_OFFSET)}):")
        for i, ch in enumerate(songs):
            print(f"  song {i+1:2d}: ch1={hex(ch[0])} ch2={hex(ch[1])} ch3={hex(ch[2])}")
        sys.exit(0)

    if not (1 <= args.song <= len(songs)):
        print(f"song index out of range -- real table has {len(songs)} entries", file=sys.stderr)
        sys.exit(1)

    ch_offsets = songs[args.song - 1]
    for ch_idx, off in enumerate(ch_offsets):
        print(f"=== song {args.song}, channel {ch_idx+1} (starts at real ROM file offset {hex(off)}) ===")
        events = decode_channel(data, off, max_events=args.max_events)
        for e in events:
            print("  " + format_event(e))
        print()
