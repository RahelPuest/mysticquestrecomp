#!/usr/bin/env python3
"""Game Boy 2bpp tile decoding — a hardware-format decoder, not specific to
any one game's ROM layout.

The Game Boy's tile format is a fixed hardware fact (Pan Docs, "VRAM Tile
Data"): each 8x8 tile is 16 bytes, stored as 8 rows of 2 bytes each. For row
y, byte0 = the low bit of each pixel's 2-bit color index (bit 7 = leftmost
pixel), byte1 = the high bit. Combining byte0/byte1 per column gives a
0-3 palette index per pixel; on DMG hardware that index is mapped through
BGP/OBP0/OBP1 to one of 4 shades of grey (or, on a color-aware pipeline, an
RGB palette).

This module has no dependency on which game a ROM belongs to: it is exactly
as applicable to Mystic Quest as to Pokémon or any other Game Boy title.
"""
from __future__ import annotations

from pathlib import Path
from typing import Iterable, Sequence

TILE_BYTES = 16
TILE_W = 8
TILE_H = 8

# Default 4-shade DMG-style grey ramp, index 0 (lightest/background) to
# index 3 (darkest), matching the classic Game Boy palette convention used
# when BGP = 0xE4 (11 10 01 00 -> id3=black..id0=white). This is a
# *display* choice, not a ROM fact — real in-game palettes (BGP/OBP0/OBP1
# writes) are a separate, still-unverified question for Mystic Quest.
DEFAULT_GREYS = (
    (255, 255, 255),
    (170, 170, 170),
    (85, 85, 85),
    (0, 0, 0),
)


def decode_tile(data: bytes) -> list[list[int]]:
    """Decode one 16-byte 2bpp tile into an 8x8 list of 0-3 palette indices."""
    if len(data) < TILE_BYTES:
        raise ValueError(f"tile needs {TILE_BYTES} bytes, got {len(data)}")
    rows = []
    for y in range(TILE_H):
        lo = data[y * 2]
        hi = data[y * 2 + 1]
        row = []
        for x in range(TILE_W):
            bit = 7 - x
            pixel = ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)
            row.append(pixel)
        rows.append(row)
    return rows


def decode_tiles(data: bytes, count: int | None = None) -> list[list[list[int]]]:
    """Decode a contiguous run of tiles. count=None decodes as many whole
    tiles as fit in data."""
    n = len(data) // TILE_BYTES if count is None else count
    return [decode_tile(data[i * TILE_BYTES:(i + 1) * TILE_BYTES]) for i in range(n)]


def tile_entropy(tile: Sequence[Sequence[int]]) -> float:
    """Shannon entropy (bits) over the 4 palette-index symbols in one tile.
    Used as a cheap "does this look like real graphics, not code/text/
    padding" heuristic: real tile art tends to sit in a middle entropy band
    (some structure, not flat, not fully random), never 0 (a blank/solid
    tile) and rarely near the 2.0-bit max (pure noise, i.e. code
    disassembled as if it were pixels)."""
    import math
    counts = [0, 0, 0, 0]
    total = 0
    for row in tile:
        for v in row:
            counts[v] += 1
            total += 1
    if total == 0:
        return 0.0
    h = 0.0
    for c in counts:
        if c == 0:
            continue
        p = c / total
        h -= p * math.log2(p)
    return h


def sheet_image(tiles: Iterable[Sequence[Sequence[int]]], columns: int = 16,
                 scale: int = 2, palette: Sequence[tuple] = DEFAULT_GREYS,
                 transparent0: bool = False):
    """Lay decoded tiles out into a grid PNG (via Pillow) for visual
    inspection. Returns a PIL.Image."""
    from PIL import Image

    tiles = list(tiles)
    if not tiles:
        raise ValueError("no tiles to render")
    rows = (len(tiles) + columns - 1) // columns
    mode = "RGBA" if transparent0 else "RGB"
    img = Image.new(mode, (columns * TILE_W * scale, rows * TILE_H * scale),
                     (255, 255, 255) if not transparent0 else (0, 0, 0, 0))
    px = img.load()
    for i, tile in enumerate(tiles):
        tx = (i % columns) * TILE_W * scale
        ty = (i // columns) * TILE_H * scale
        for y, row in enumerate(tile):
            for x, idx in enumerate(row):
                if transparent0 and idx == 0:
                    color = (0, 0, 0, 0)
                else:
                    r, g, b = palette[idx]
                    color = (r, g, b, 255) if transparent0 else (r, g, b)
                for sy in range(scale):
                    for sx in range(scale):
                        px[tx + x * scale + sx, ty + y * scale + sy] = color
    return img


def save_sheet(data: bytes, out_path: str | Path, columns: int = 16,
               scale: int = 2, count: int | None = None):
    tiles = decode_tiles(data, count)
    img = sheet_image(tiles, columns=columns, scale=scale)
    img.save(out_path)
    return len(tiles)


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rom", help="path to a .gb ROM (or any binary file)")
    ap.add_argument("--offset", type=lambda s: int(s, 0), required=True,
                     help="byte offset into the file (accepts 0x.. hex)")
    ap.add_argument("--count", type=int, default=256, help="tile count")
    ap.add_argument("--columns", type=int, default=16)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--out", required=True, help="output PNG path")
    args = ap.parse_args()

    raw = Path(args.rom).read_bytes()
    chunk = raw[args.offset:args.offset + args.count * TILE_BYTES]
    n = save_sheet(chunk, args.out, columns=args.columns, scale=args.scale)
    print(f"wrote {n} tiles ({n * TILE_BYTES} bytes from offset "
          f"0x{args.offset:X}) to {args.out}")
