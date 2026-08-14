#!/usr/bin/env python3
"""Pointer-table lead generator -- a hardware-format heuristic, not specific
to Mystic Quest's actual data layout.

The Game Boy CPU addresses a switched ROM bank at $4000-$7FFF. Many GB games
store lists of far pointers (2 bytes, little-endian, a $4000-$7FFF CPU
address to be combined with a separately-stored/implied bank number) for
things like: per-map data pointers, per-entity script pointers, dialogue
string pointers, per-level tables. A *run* of several such 2-byte values in
a row, each independently landing in the valid CPU address window, is a
much stronger signal than a single value (which could easily be coincidental
code bytes) -- this scanner finds runs and ranks them by length, exactly the
kind of "byte distributions / pointer tables" analysis the project brief
calls for.

This is a LEAD GENERATOR ONLY. Every candidate must still be manually
dereferenced and visually/structurally confirmed before being marked
VERIFIED or PARTIALLY VERIFIED in docs/reverse-engineering/rom-map.md --
see that document's method notes on why the equivalent graphics heuristic
(scan_graphics.py) produced a confirmed false positive (bank 5).
"""

import argparse
import sys

BANK_SIZE = 0x4000
CPU_LO, CPU_HI = 0x4000, 0x7FFF


def find_runs(data, bank_start, bank_end, min_run, align):
    """Scan data[bank_start:bank_end] for runs of consecutive 2-byte LE
    values that each fall in [CPU_LO, CPU_HI]. Returns a list of
    (file_offset, run_length, [values]).

    `align`: only start/continue runs on offsets congruent to bank_start
    mod `align` bytes -- real tables are conventionally word-aligned; code
    is not, so this alone filters out a lot of "found a CALL operand that
    happens to look like a pointer" false positives without being a
    perfect filter (opcodes can still land on even offsets by chance).
    """
    runs = []
    pos = bank_start
    step = align
    while pos + 1 < bank_end:
        values = []
        p = pos
        while p + 1 < bank_end:
            lo = data[p]
            hi = data[p + 1]
            val = lo | (hi << 8)
            if CPU_LO <= val <= CPU_HI:
                values.append(val)
                p += 2
            else:
                break
        if len(values) >= min_run:
            runs.append((pos, len(values), values))
            pos = p
            if (pos - bank_start) % step != 0:
                pos += step - ((pos - bank_start) % step)
        else:
            pos += step
    return runs


def uniqueness(values):
    return len(set(values)) / len(values) if values else 0.0


def offset_to_bank(file_offset):
    bank = file_offset // BANK_SIZE
    addr = file_offset % BANK_SIZE
    if bank >= 1:
        addr += 0x4000
    return bank, addr


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rom")
    ap.add_argument("--min-run", type=int, default=6,
                     help="minimum consecutive pointer-shaped values to report")
    ap.add_argument("--bank", type=int, default=None,
                     help="restrict scan to one bank (default: all)")
    ap.add_argument("--top", type=int, default=40,
                     help="max number of runs to print, longest first")
    ap.add_argument("--align", type=int, default=2, choices=(1, 2),
                     help="byte alignment for candidate table entries (default 2)")
    ap.add_argument("--min-unique", type=float, default=0.9,
                     help="minimum fraction of distinct values in a run "
                          "(real tables rarely repeat entries; code false "
                          "positives clustering on one common CALL target "
                          "do -- default 0.9 filters those out)")
    args = ap.parse_args()

    with open(args.rom, "rb") as f:
        data = f.read()

    n_banks = len(data) // BANK_SIZE
    banks = [args.bank] if args.bank is not None else range(n_banks)

    all_runs = []
    for bank in banks:
        start = bank * BANK_SIZE
        end = start + BANK_SIZE
        runs = find_runs(data, start, end, args.min_run, args.align)
        for (off, length, values) in runs:
            if uniqueness(values) >= args.min_unique:
                all_runs.append((bank, off, length, values))

    all_runs.sort(key=lambda r: -r[2])

    print(f"{'bank':>4} {'file_off':>10} {'cpu_addr':>8} {'count':>5} {'uniq':>5}  first few targets")
    for bank, off, length, values in all_runs[: args.top]:
        _, addr = offset_to_bank(off)
        preview = ", ".join(f"${v:04X}" for v in values[:6])
        print(f"{bank:>4} {off:#010x} {addr:#06x} {length:>5} {uniqueness(values):>5.2f}  {preview}")

    print(f"\n{len(all_runs)} runs >= {args.min_run} (unique ratio >= "
          f"{args.min_unique}) found across {len(list(banks))} bank(s).")


if __name__ == "__main__":
    sys.exit(main())
