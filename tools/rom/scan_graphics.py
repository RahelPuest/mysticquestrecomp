#!/usr/bin/env python3
"""Heuristic scan for candidate 2bpp graphics regions in a Game Boy ROM.

This is a *lead generator*, not a source of truth: it ranks tile-aligned
16-byte windows by how "tile-like" their decoded entropy looks, then reports
runs of consecutive plausible tiles. Every candidate this prints must still
be visually confirmed (render it with tools/graphics/gbtile.py and look at
it) before it can be recorded as VERIFIED in the ROM map. Nothing here reads
as ground truth by itself — code, text, and structured tables can all
produce false positives.

Method:
  1. Slide a 16-byte window over the whole file, tile-aligned (stride 16,
     matching the hardware tile size).
  2. Decode each window as a 2bpp tile, compute its Shannon entropy over the
     4 palette-index symbols (see gbtile.tile_entropy).
  3. Flag tiles whose entropy sits in a plausible "real art" band, are not
     stuck on a single repeated 2-byte row pattern (rules out code executing
     as degenerate flat rows), and are not the all-zero/all-one tiles.
  4. Report runs of >= --min-run consecutive flagged tiles as candidates,
     sorted by run length (longer runs are more likely to be real tile
     sheets rather than incidental matches in code/tables).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "graphics"))
from gbtile import TILE_BYTES, decode_tile, tile_entropy  # noqa: E402

# Empirically reasonable band for real DMG tile art: pure noise (code
# misread as pixels) tends to sit close to the 2-bit max; a blank/near-blank
# tile sits at or near 0. Real font/sprite/tileset art usually falls between.
ENTROPY_LOW = 0.55
ENTROPY_HIGH = 1.85


def is_plausible(tile) -> bool:
    ent = tile_entropy(tile)
    if not (ENTROPY_LOW <= ent <= ENTROPY_HIGH):
        return False
    # Reject tiles where every row is identical (common false positive from
    # a run of identical bytes -- e.g. 0x00 padding, or a repeated code
    # opcode pair -- rather than real per-row pixel structure).
    rows = {tuple(r) for r in tile}
    if len(rows) <= 1:
        return False
    return True


def scan(data: bytes, bank_size: int = 0x4000):
    n_tiles = len(data) // TILE_BYTES
    flags = bytearray(n_tiles)
    for i in range(n_tiles):
        tile = decode_tile(data[i * TILE_BYTES:(i + 1) * TILE_BYTES])
        flags[i] = 1 if is_plausible(tile) else 0

    runs = []
    i = 0
    while i < n_tiles:
        if flags[i]:
            j = i
            while j < n_tiles and flags[j]:
                j += 1
            runs.append((i, j - i))  # (start tile index, run length)
            i = j
        else:
            i += 1
    return runs


def offset_to_bank(offset: int, bank_size: int = 0x4000) -> tuple[int, int]:
    """Best-effort bank/address label for a flat file offset, ASSUMING the
    file is a flat concatenation of fixed-size banks (true for a plain .gb
    dump). Bank 0 is 0x0000-0x3FFF; bank N>=1 covers file offset
    N*0x4000..N*0x4000+0x3FFF and is addressed at 0x4000-0x7FFF when
    switched in. This is just arithmetic on the file layout, not a claim
    about what the game actually stores there."""
    bank = offset // bank_size
    addr_in_bank = offset % bank_size
    cpu_addr = addr_in_bank if bank == 0 else (0x4000 + addr_in_bank)
    return bank, cpu_addr


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rom")
    ap.add_argument("--min-run", type=int, default=32,
                     help="minimum consecutive plausible tiles to report (default 32 = 512 bytes)")
    ap.add_argument("--top", type=int, default=25, help="max candidates to print")
    args = ap.parse_args(argv[1:])

    data = Path(args.rom).read_bytes()
    runs = scan(data)
    runs = [r for r in runs if r[1] >= args.min_run]
    runs.sort(key=lambda r: -r[1])

    print(f"{len(runs)} candidate run(s) with >= {args.min_run} consecutive "
          f"plausible tiles (scanned {len(data)} bytes, tile-aligned):\n")
    for start_tile, length in runs[:args.top]:
        offset = start_tile * TILE_BYTES
        bank, addr = offset_to_bank(offset)
        end_offset = offset + length * TILE_BYTES
        print(f"  offset 0x{offset:06X}-0x{end_offset:06X}  "
              f"bank {bank:2d} addr 0x{addr:04X}  "
              f"{length:4d} tiles ({length * TILE_BYTES} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
