#!/usr/bin/env python3
"""Scan the ROM for byte runs that decode to plausible text, under
various *hypotheses* about dialogue byte encoding -- this is a LEAD
GENERATOR, exactly like scan_pointers.py/scan_graphics.py: a hit here is
evidence worth chasing by hand, not proof of anything. Mark findings
VERIFIED in docs/reverse-engineering/text.md only after cross-checking
against something else (e.g. bytes that visibly change with in-game
dialogue, or a matching pointer table).

Three subcommands, corresponding to hypotheses tested so far (see
docs/reverse-engineering/text.md for the full writeup and results):

  words     Decode candidate byte runs under a given --encoding and score
            them against a small, high-precision dictionary (--lang).
            This is what ruled out "direct tile-index" and "direct ASCII"
            encoding in both English and German (2026-08-08): near-zero
            real-word hits across the whole 256 KiB ROM for either.

  shift     Brute-force every constant shift of the tile-index charmap
            (e.g. "what if dialogue indexes from the umlaut block instead
            of the digit row") and report which shift scores best against
            the dictionaries. Found: no shift does meaningfully better
            than noise -- ruling out a simple constant-offset encoding.

  charmap   Look for a compact (60-130 byte), non-degenerate, low-value
            (0-95) byte run elsewhere in ROM that could be a *scrambled*
            byte->glyph lookup table (distinct from the font's own ROM
            tile order, which is asset/editor order, not necessarily
            compressor/encoding order). Lead generator only -- every
            candidate needs to be manually dereferenced and tested.

The charmap used by `words`/`shift` is transcribed directly from
rom_profiles.lua's `graphics.font.rowGlyphs` for the one profile this
project targets (Mystic Quest EU) -- if that ever changes, update both
together.
"""

import argparse
import re
import sys

GLYPHS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
# Row 4 (indices 64-79 in the real font) is only partially known
# (". . . - ! ? :" plus non-text icons per rom-map.md) -- left out of
# GLYPHS deliberately rather than guess an ordering we haven't verified.

WORD_RE = re.compile(r"[A-Za-z]{3,}")

# Deliberately small, high-precision dictionaries: the point is NOT
# coverage (these will miss lots of real text) -- it's to reject the
# "any run of letters scores high" false-positive flood a bare regex
# produces (checked: a bare letter-density heuristic scores >1400 runs
# "plausible" out of 3606 candidates; requiring an actual dictionary word
# collapses that to near zero for every hypothesis tried so far).
COMMON_WORDS = {
    "en": {
        "the", "you", "your", "and", "are", "is", "was", "not", "for", "with",
        "this", "that", "have", "has", "will", "can", "to", "of", "in", "on",
        "at", "it", "me", "my", "he", "she", "his", "her", "who", "what",
        "where", "when", "why", "how", "yes", "no", "ok", "go", "get", "give",
        "take", "use", "open", "door", "key", "gold", "item", "items", "level",
        "hero", "sword", "shield", "armor", "armour", "potion", "magic",
        "spell", "attack", "defense", "health", "hp", "mp", "gil", "gp",
        "town", "village", "castle", "cave", "forest", "shop", "buy", "sell",
        "save", "quest", "king", "queen", "witch", "wizard", "dragon",
        "monster", "enemy", "boss", "friend", "help", "thank", "thanks",
        "welcome", "goodbye", "bye", "hello", "hi", "please", "sorry",
        "here", "there", "now", "then", "come", "went", "find", "found",
        "lost", "look", "see", "want", "need", "must", "let", "us",
    },
    # ASCII-transliterated (no umlauts -- the scan operates over A-Za-z
    # only; real dialogue would use the ROM's own accented glyphs, which
    # this word-list approach can't match anyway since it only flags
    # runs of plain A-Za-z bytes). Confirmed relevant: the game's own
    # in-game text is German (per the font's adjacent umlaut glyph set,
    # see rom-map.md, and confirmed by the project owner) even though the
    # EU cartridge brand name "Mystic Quest" / header title is English.
    "de": {
        "der", "die", "das", "und", "ist", "nicht", "ein", "eine", "einen",
        "du", "dein", "deine", "sie", "ich", "mit", "von", "zum", "zur", "auf",
        "was", "wer", "wie", "wo", "hier", "jetzt", "kann", "muss", "hast",
        "habe", "bist", "sind", "war", "schwert", "schild", "ring", "zauber",
        "magie", "trank", "held", "dorf", "stadt", "schloss", "burg", "wald",
        "laden", "kaufen", "verkaufen", "gold", "leben", "danke", "hallo",
        "bitte", "freund", "koenig", "koenigin", "hexe", "drache", "monster",
        "gehe", "komm", "nein", "ja",
    },
}


def make_charmap(shift=0):
    return {i + shift: ch for i, ch in enumerate(GLYPHS)}


def decode_tileindex(byte_values, charmap):
    return "".join(charmap.get(b, "�") for b in byte_values)


def decode_ascii(byte_values):
    return "".join(chr(b) for b in byte_values)


def word_hit_count(text, words):
    return sum(1 for m in WORD_RE.finditer(text) if m.group(0).lower() in words)


def find_runs_by_predicate(data, min_len, in_alphabet):
    runs = []
    i, n = 0, len(data)
    while i < n:
        if in_alphabet(data[i]):
            start = i
            while i < n and in_alphabet(data[i]):
                i += 1
            if i - start >= min_len:
                runs.append((start, data[start:i]))
        else:
            i += 1
    return runs


def cmd_words(data, args):
    words = COMMON_WORDS[args.lang]
    if args.encoding == "tileindex":
        charmap = make_charmap(args.shift)
        runs = find_runs_by_predicate(data, args.min_len, lambda b: b in charmap)
        decode = lambda raw: decode_tileindex(raw, charmap)
    else:
        runs = find_runs_by_predicate(data, args.min_len, lambda b: 0x20 <= b <= 0x7E)
        decode = decode_ascii

    hits = []
    for off, raw in runs:
        text = decode(raw)
        wc = word_hit_count(text, words)
        if wc >= args.min_words:
            hits.append((wc, off, text))
    hits.sort(key=lambda s: -s[0])

    print(f"encoding={args.encoding} lang={args.lang} shift={args.shift}: "
          f"{len(runs)} raw runs >= {args.min_len} bytes; "
          f"{len(hits)} with >= {args.min_words} common-word hit(s)\n")
    for wc, off, text in hits[: args.top]:
        bank = off // 0x4000
        print(f"bank {bank:2} off {off:#08x}  words {wc}  {text!r}")


def cmd_shift(data, args):
    words = COMMON_WORDS["en"] | COMMON_WORDS["de"]
    results = []
    for shift in range(-args.range, args.range + 1):
        charmap = make_charmap(shift)
        runs = find_runs_by_predicate(data, args.min_len, lambda b: b in charmap)
        total = 0
        for off, raw in runs:
            total += word_hit_count(decode_tileindex(raw, charmap), words)
        results.append((total, shift, len(runs)))
    results.sort(key=lambda r: -r[0])
    print(f"Brute-forced shifts -{args.range}..+{args.range} of the tile-index "
          f"charmap, scored against English+German combined:\n")
    for hits, shift, nruns in results[: args.top]:
        print(f"shift={shift:4d}  hits={hits:3d}  candidate_runs={nruns}")


def cmd_charmap(data, args):
    n = len(data)
    candidates = []
    i = 0
    while i < n:
        if data[i] <= args.max_value:
            start = i
            while i < n and data[i] <= args.max_value:
                i += 1
            length = i - start
            if args.min_len <= length <= args.max_len:
                chunk = data[start:i]
                uniq = len(set(chunk))
                ascending = all(chunk[j] <= chunk[j + 1] for j in range(len(chunk) - 1))
                if uniq >= length * args.min_unique_ratio and not ascending:
                    candidates.append((start, length, uniq))
        else:
            i += 1
    print(f"{len(candidates)} candidate lookup-table-shaped runs "
          f"({args.min_len}-{args.max_len} bytes, values 0-{args.max_value}, "
          f"non-degenerate)\n")
    for start, length, uniq in candidates[: args.top]:
        bank = start // 0x4000
        print(f"bank {bank:2} off {start:#08x}  len={length}  unique={uniq}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_words = sub.add_parser("words", help="score candidate runs against a word dictionary")
    p_words.add_argument("--encoding", choices=("tileindex", "ascii"), default="tileindex")
    p_words.add_argument("--lang", choices=("en", "de"), default="de")
    p_words.add_argument("--shift", type=int, default=0,
                          help="constant offset applied to the tile-index charmap")
    p_words.add_argument("--min-len", type=int, default=6)
    p_words.add_argument("--min-words", type=int, default=1)
    p_words.add_argument("--top", type=int, default=60)

    p_shift = sub.add_parser("shift", help="brute-force charmap shifts")
    p_shift.add_argument("--range", type=int, default=40)
    p_shift.add_argument("--min-len", type=int, default=6)
    p_shift.add_argument("--top", type=int, default=15)

    p_charmap = sub.add_parser("charmap", help="look for a scrambled lookup-table candidate")
    p_charmap.add_argument("--max-value", type=int, default=95)
    p_charmap.add_argument("--min-len", type=int, default=60)
    p_charmap.add_argument("--max-len", type=int, default=130)
    p_charmap.add_argument("--min-unique-ratio", type=float, default=0.5)
    p_charmap.add_argument("--top", type=int, default=30)

    args = ap.parse_args()
    with open(args.rom, "rb") as f:
        data = f.read()

    {"words": cmd_words, "shift": cmd_shift, "charmap": cmd_charmap}[args.cmd](data, args)


if __name__ == "__main__":
    sys.exit(main())
