#!/usr/bin/env python3
"""Dump all decodable text strings from the ROM using the VERIFIED text
encoding (see docs/reverse-engineering/text.md): a byte >= 0xB0 encodes a
character as `GLYPHS[byte - 0xB0]` for the main 64-glyph alphabet (digits/
letters/punctuation, matching the font's own ROM tile order -- see
src/import/rom_profiles.lua's `graphics.font.rowGlyphs`), 0xFF is a space,
0x00 terminates a string, 0x90-0xAF is a partially-decoded umlaut/icon
block, and a real digraph (two-character) compression table lives below
0xB0 (see `DIGRAPH_PARTIAL`). Mirrors `src/import/TextDecoder.lua` --
keep both in sync when a new byte gets confirmed.

This is NOT a lead-generator like scan_text.py's `words`/`shift` modes --
the formula is confirmed (found via dynamic tracing with a real emulator,
see docs/reverse-engineering/tooling.md) and reproducible against the ROM
alone, no emulator needed to re-run this scan.

Two modes:
  (default) `find_strings`: reports only maximal runs where EVERY byte
    decodes (a byte that doesn't decode ends the run there) -- clean,
    but stops at the very first still-unmapped byte, hiding whatever
    readable text continues past it.
  `--gaps`: `find_blocks` instead -- renders unknown bytes inline as
    `[XX]` hex markers rather than ending the run, so long otherwise-
    readable stretches (and their gaps, in context) stay visible. This
    is the technique that found the original 15-entry digraph table
    (2026-08-09) and its 2026-08-10 continuation (see text.md) -- the
    real way to find MORE digraph/control-byte candidates: look at what
    German word the gap must complete, then check if the same byte
    recurs with the same completion in an unrelated word.
"""

import argparse
import sys
from collections import Counter

MAIN_GLYPHS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',"
MAIN_BASE = 0xB0
SPACE_BYTE = 0xFF
TERMINATOR_BYTE = 0x00
PERIOD_BYTE = 0xF0
HYPHEN_BYTE = 0xF2
NEWLINE_BYTE = 0x1A
EXCLAMATION_BYTE = 0xF3
QUESTION_BYTE = 0xF4  # VERIFIED 2026-08-10, see text.md
COLON_BYTE = 0xF5  # VERIFIED 2026-08-10, see text.md

# Keep in sync with TextDecoder.lua's own UMLAUT_PARTIAL/DIGRAPH_PARTIAL.
#
# FIXED (2026-08-12, found while hunting real dialogue-line offsets for
# quick win "weitere Dialogzeilen live decodieren"): this table had
# silently drifted out of sync with TextDecoder.lua's own real,
# UTF-8-umlaut UMLAUT_PARTIAL -- it still had the OLD 2-letter ASCII
# substitutions ("ae"/"oe"/"ue"/"ss") that TextDecoder.lua itself moved
# away from back on 2026-08-10 (see that file's own doc comment: "es
# gibt ein problem mit umlauten" -- `Font.lua`'s UTF-8-aware `nextGlyph`
# fix was the OTHER half of that same correction). The byte VALUES here
# were always right (this genuinely never caused a wrong decode), only
# the OUTPUT STRING was stale -- but a stale mirror is exactly the kind
# of thing this module's own header comment ("Mirrors TextDecoder.lua")
# promises won't happen, and it was actively misleading while reading
# this scan's own output during this pass (e.g. "Ritter! Er weiss,"
# instead of the real "Ritter! Er weiß," -- looked like a possible
# real ROM spelling quirk worth double-checking, and wasn't one).
UMLAUT_PARTIAL = {
    0x9C: "ä", 0x9D: "ö", 0x9E: "ü", 0x9F: "ß",
    0x99: "Ä", 0x9A: "Ö", 0x9B: "Ü",
}

# HYPOTHESIS (2026-08-18): 0xA2/0xA4/0xA7/0xA8 are very plausibly CONTROL
# bytes (same category as the already-verified 0x12), not unmapped digraph
# characters -- found sitting in the same consistent position (right before
# an item name in an "<Item> gefunden" pickup message) across 5-12 real
# occurrences each in the real dialogue region (file 0x34800-0x3B000).
# Deliberately left OUT of this table -- see TextDecoder.lua's own matching
# note (right before its DIGRAPH_PARTIAL) for the full evidence.
DIGRAPH_PARTIAL = {
    0x24: "en", 0x2A: "ie", 0x2F: "te", 0x31: "be", 0x37: "un",
    0x39: "le", 0x3A: " i", 0x3B: "se", 0x3C: "as", 0x4E: "da",
    0x51: "it", 0x55: "ll", 0x58: "or", 0x5A: "ma", 0x5C: "em",
    0x5F: "li",
    # 2026-08-11 additions (see TextDecoder.lua's own DIGRAPH_PARTIAL).
    # 0x5B REVISED 2026-08-17: was "a" ("Julia") -- the real ROM digraph
    # table (found by disassembly) reads it as "us" ("Julius"). See
    # TextDecoder.lua's own 0x5B note for the full evidence trail.
    0x23: "er", 0x25: "n ", 0x29: "in", 0x2B: "ge", 0x34: "an",
    0x3F: "he", 0x47: "ar", 0x4C: " b", 0x5B: "us", 0x65: " h",
    0x6E: "mm", 0x88: "Da", 0x21: "de", 0x43: "n",
    # 2026-08-12 additions ("versuche die text decoder digraphs komplett
    # zu schliessen" -- see TextDecoder.lua's own DIGRAPH_PARTIAL for the
    # full evidence trail per entry).
    0x20: "ch", 0x22: "e ", 0x26: "r ", 0x28: "t ", 0x2D: "st",
    0x2E: "ei", 0x30: "d", 0x33: "s ", 0x36: "es", 0x3D: "d",
    0x3E: "au", 0x41: ", ", 0x45: "du", 0x49: "u ", 0x4F: "re",
    0x50: "ir", 0x53: "tt", 0x54: "m ", 0x59: "Ma", 0x5D: "al",
    0x5E: "W", 0x60: "t", 0x64: "sc", 0x6B: "et", 0x6D: " v",
    0x83: " G", 0x84: "ac", 0x87: "na", 0x89: "a ", 0x8E: "ra",
    # Second round, same pass (see TextDecoder.lua for the credits-
    # screen cross-check that fixed the 0x35/0x38/0x8D boundary split,
    # and the honest 0x6C contradiction it also caught, deliberately
    # NOT included here).
    # 0x86 REVISED 2026-08-17: was "ih" -- the real ROM digraph table
    # reads it as "Di" ("wird Dir helfen"). See TextDecoder.lua's own
    # 0x86 note.
    0x35: "ic", 0x38: "h ", 0x69: "we", 0x6A: "d ", 0x80: "rt",
    0x86: "Di", 0x8D: "Ic", 0x8F: "eg",
    0x6C: "si",  # dialogue-region value; one honest credits-screen
    # counter-example ("Yoshinori" wanting "shi") -- see TextDecoder.lua.
    # Third round ("na dann loese was noch offen ist" / "versuche ...
    # den kompletten text ... zu dekodieren") -- see TextDecoder.lua's
    # own DIGRAPH_PARTIAL for the full per-entry evidence.
    0x32: "nd", 0x40: "ne", 0x42: " e", 0x44: "is", 0x46: " s",
    0x48: "rd", 0x4A: " g", 0x4B: "ht", 0x4D: " w", 0x52: " M",
    0x56: "el", 0x57: " m", 0x61: " n", 0x62: "nn",
    0x67: "ef", 0x68: "mi", 0x6F: " B", 0x81: " a", 0x85: "di",
    0x8A: "eh", 0x8B: "ns", 0x8C: "ha",
    # 0x66 REVISED 2026-08-17: was "! " -- the real ROM digraph table
    # AND a direct font-tile-bitmap render both independently confirm
    # tile 0x70 is a period, not an exclamation mark. See
    # TextDecoder.lua's own 0x66 note.
    0x66: ". ",
    # FOUND, 2026-08-17: the real ROM digraph lookup table itself (ROM
    # `$3F3F`, see docs/reverse-engineering/text.md). 0x82 was
    # previously left unmapped on purpose (see the retired note this
    # replaces) as genuinely CONTRADICTORY across dynamic occurrences --
    # the real table proves a single, unambiguous answer instead. Also
    # adds 0x27/0x63/0x70-0x7F, previously unmapped. Kept in sync with
    # TextDecoder.lua's own DIGRAPH_PARTIAL.
    0x82: "me", 0x27: "..", 0x63: "ng",
    0x70: "rt", 0x71: " a", 0x72: "me", 0x73: " G", 0x74: "ac",
    0x75: "di", 0x76: "Di", 0x77: "na", 0x78: "Da", 0x79: "a ",
    0x7A: "eh", 0x7B: "ns", 0x7C: "ha", 0x7D: "Ic", 0x7E: "ra",
    0x7F: "eg",
}


def decode_byte(b):
    if b == SPACE_BYTE:
        return " "
    if b == PERIOD_BYTE:
        return "."
    if b == HYPHEN_BYTE:
        return "-"
    if b == NEWLINE_BYTE:
        return "\n"
    if b == EXCLAMATION_BYTE:
        return "!"
    if b == QUESTION_BYTE:
        return "?"
    if b == COLON_BYTE:
        return ":"
    if b in UMLAUT_PARTIAL:
        return UMLAUT_PARTIAL[b]
    if b in DIGRAPH_PARTIAL:
        return DIGRAPH_PARTIAL[b]
    if MAIN_BASE <= b < MAIN_BASE + len(MAIN_GLYPHS):
        return MAIN_GLYPHS[b - MAIN_BASE]
    return None


def find_strings(data, min_len):
    """A 'string' here is a maximal run of bytes that each decode to
    something (letter, space, hyphen, umlaut, digraph, punctuation) --
    i.e. runs of >= min_len consecutive known-good bytes, split at the
    terminator or at the first byte that doesn't decode at all."""
    strings = []
    i, n = 0, len(data)
    while i < n:
        b = data[i]
        if b == TERMINATOR_BYTE or decode_byte(b) is not None:
            start = i
            chars = []
            while i < n:
                b = data[i]
                if b == TERMINATOR_BYTE:
                    i += 1
                    break
                ch = decode_byte(b)
                if ch is None:
                    break
                chars.append(ch)
                i += 1
            text = "".join(chars)
            if len(text) >= min_len:
                strings.append((start, text))
        else:
            i += 1
    return strings


def find_blocks(data, min_len, min_ratio=0.7):
    """A 'block' is a maximal run bounded by TERMINATOR bytes (0x00),
    with unknown bytes rendered as [XX] markers instead of ending the
    run early -- lets long otherwise-readable prose stay visible with
    its gaps in context. Only reports blocks where >= min_ratio of
    bytes are already-known (filters out coincidental non-text data)."""
    blocks = []
    i, n = 0, len(data)
    cur_start = None
    chars = []
    unknown_positions = []

    def flush(end):
        nonlocal cur_start, chars, unknown_positions
        if cur_start is not None:
            text = "".join(chars)
            total = end - cur_start
            ratio = 1 - (len(unknown_positions) / max(1, total))
            if len(text) >= min_len and ratio >= min_ratio:
                blocks.append((cur_start, end, text, list(unknown_positions), ratio))
        cur_start = None
        chars = []
        unknown_positions = []

    while i < n:
        b = data[i]
        if b == TERMINATOR_BYTE:
            flush(i)
            i += 1
            continue
        if cur_start is None:
            cur_start = i
        ch = decode_byte(b)
        if ch is not None:
            chars.append(ch)
        else:
            chars.append(f"[{b:02x}]")
            unknown_positions.append((i, b))
        i += 1
    flush(n)
    return blocks


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    ap.add_argument("--min-len", type=int, default=3)
    ap.add_argument("--bank", type=int, default=None)
    ap.add_argument("--gaps", action="store_true",
                     help="show blocks with inline [XX] gap markers instead of "
                          "stopping at the first unknown byte -- see module docstring")
    ap.add_argument("--min-ratio", type=float, default=0.7,
                     help="(--gaps mode) minimum known-byte ratio to report a block")
    args = ap.parse_args()

    with open(args.rom, "rb") as f:
        data = f.read()

    if args.bank is not None:
        start = args.bank * 0x4000
        data = data[start:start + 0x4000]
        base_off = start
    else:
        base_off = 0

    if not args.gaps:
        strings = find_strings(data, args.min_len)
        print(f"{len(strings)} strings (min length {args.min_len})\n")
        for off, text in strings:
            abs_off = off + base_off
            bank = abs_off // 0x4000
            print(f"bank {bank:2} off {abs_off:#08x}  {text!r}")
        return

    blocks = find_blocks(data, args.min_len, args.min_ratio)
    blocks.sort(key=lambda t: -t[4])
    print(f"{len(blocks)} candidate text blocks (min_len={args.min_len}, "
          f">={args.min_ratio:.0%} known bytes)\n")
    tally = Counter()
    for start, end, text, unk, ratio in blocks:
        abs_start = start + base_off
        bank = abs_start // 0x4000
        print(f"bank {bank:2} off {abs_start:#08x}-{end + base_off:#08x} "
              f"ratio={ratio:.2f} unk={len(unk)}")
        print(f"   {text!r}")
        for _, b in unk:
            tally[b] += 1
    print("\n=== unknown byte frequency across candidate blocks ===")
    for b, cnt in tally.most_common(40):
        print(f"  0x{b:02x}: {cnt}")


if __name__ == "__main__":
    sys.exit(main())
