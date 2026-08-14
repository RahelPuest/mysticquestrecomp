#!/usr/bin/env python3
"""Renders `unknownRoomA`'s 6 candidate rooms (real roomSelectors 8-13)
into real PNGs, for visual verification — see docs/reverse-engineering/
rom-map.md "unknownRoomA VISUALLY CONFIRMED" for the full writeup this
tool produced the evidence for.

The recipe (three real, independently-established formulas chained
together, none of it new this pass):
  1. bank 5's own already-VERIFIED 256-record RLE layout-stream table
     (`src/import/MapTable.lua`'s own header-derived `rleLength=3`) --
     HYPOTHESIS under test: roomSelector N's own real layout stream is
     literally bank 5's own record N (bank5's pointer table: file
     `0x14004`, 256 x 2 x u16 (headerPtr,dataPtr) pairs, bank-relative
     to `0x14000`).
  2. `unknownRoomA`'s own real metatile table (bank 8, file `0x20938`,
     already found via the same `roomSelectorTable`-driven formula
     `0x20000 + (targetPointer - 0x4000)` used for every other room).
  3. `MapTable.lua`'s own already-VERIFIED tileset formula
     (`tilesetFileOffset=0x32000 + tileId*16`) applied to each
     metatile's own 4 GFX-tile bytes -- real 2bpp pixel data, decoded
     via `tools/graphics/gbtile.py` (the general, game-agnostic GB
     hardware tile decoder already in this project).

Deliberately NOT committing the rendered PNGs themselves (they embed
real, directly-extractable copyrighted game graphics) -- this script
is the checked-in, reproducible RECIPE, same convention as
`tools/rom/checkpoints.py`'s own real `.state` files (gitignored,
regenerate locally).

Usage: python3 render_unknown_room_a.py <rom_path> --out-dir <dir>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gbtile  # noqa: E402

BANK5_BASE = 0x14000
BANK5_PTR_TABLE = 0x14004
BANK5_RLE_LENGTH = 3  # bank 5's own header-derived value, see MapTable.lua

UNKNOWN_ROOM_A_METATILE_TABLE = 0x20938  # bank 8, CPU $4938
UNKNOWN_ROOM_A_SELECTORS = (8, 9, 10, 11, 12, 13)

TILESET_BASE = 0x32000  # MapTable.lua's own already-VERIFIED formula

METATILE_GRID_ROWS = 8
METATILE_GRID_COLS = 10


def read_u16(rom: bytes, off: int) -> int:
    return rom[off] | (rom[off + 1] << 8)


def decode_layout_stream(rom: bytes, data_off: int, rle_length: int, output_count: int) -> list[int]:
    out: list[int] = []
    i = data_off
    while len(out) < output_count:
        b = rom[i]
        i += 1
        if b & 0x80:
            out.extend([b & 0x7F] * rle_length)
        else:
            out.append(b)
    return out[:output_count]


def read_metatile(rom: bytes, table_off: int, index: int) -> tuple[int, int, int, int]:
    off = table_off + index * 6
    return rom[off], rom[off + 1], rom[off + 2], rom[off + 3]  # TL, TR, BL, BR


def bank5_data_file_offset(rom: bytes, record_index: int) -> int:
    off = BANK5_PTR_TABLE + record_index * 4 + 2  # +2: skip headerPtr, want dataPtr
    cpu_addr = read_u16(rom, off)
    return BANK5_BASE + (cpu_addr - 0x4000)


def render_room(rom: bytes, room_selector: int):
    """Returns a PIL.Image for the given roomSelector, per the recipe
    above (roomSelector N -> bank 5 record N -- the hypothesis this
    tool exists to visually check)."""
    from PIL import Image

    data_off = bank5_data_file_offset(rom, room_selector)
    indices = decode_layout_stream(rom, data_off, BANK5_RLE_LENGTH,
                                    METATILE_GRID_ROWS * METATILE_GRID_COLS)

    img = Image.new("RGB", (METATILE_GRID_COLS * 2 * gbtile.TILE_W,
                             METATILE_GRID_ROWS * 2 * gbtile.TILE_H))
    px = img.load()
    for mrow in range(METATILE_GRID_ROWS):
        for mcol in range(METATILE_GRID_COLS):
            idx = indices[mrow * METATILE_GRID_COLS + mcol]
            tl, tr, bl, br = read_metatile(rom, UNKNOWN_ROOM_A_METATILE_TABLE, idx)
            for tile_id, dr, dc in ((tl, 0, 0), (tr, 0, 1), (bl, 1, 0), (br, 1, 1)):
                tile_off = TILESET_BASE + tile_id * 16
                tile = gbtile.decode_tile(rom[tile_off:tile_off + gbtile.TILE_BYTES])
                base_y = (mrow * 2 + dr) * gbtile.TILE_H
                base_x = (mcol * 2 + dc) * gbtile.TILE_W
                for y, row in enumerate(tile):
                    for x, palette_idx in enumerate(row):
                        px[base_x + x, base_y + y] = gbtile.DEFAULT_GREYS[palette_idx]
    return img


def real_tile_entropy_report(rom: bytes, room_selector: int) -> float:
    """Average tile_entropy() (gbtile.py's own established "does this
    look like real graphics" heuristic) across every distinct GFX tile
    this room actually uses -- a real, quantified, reusable check to
    accompany the eyeballed PNG, not just a visual claim."""
    data_off = bank5_data_file_offset(rom, room_selector)
    indices = decode_layout_stream(rom, data_off, BANK5_RLE_LENGTH,
                                    METATILE_GRID_ROWS * METATILE_GRID_COLS)
    tile_ids: set[int] = set()
    for idx in indices:
        tl, tr, bl, br = read_metatile(rom, UNKNOWN_ROOM_A_METATILE_TABLE, idx)
        tile_ids.update((tl, tr, bl, br))
    entropies = []
    for tid in tile_ids:
        off = TILESET_BASE + tid * 16
        tile = gbtile.decode_tile(rom[off:off + gbtile.TILE_BYTES])
        entropies.append(gbtile.tile_entropy(tile))
    return sum(entropies) / len(entropies) if entropies else 0.0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("rom", help="path to the Mystic Quest (EU) ROM")
    ap.add_argument("--out-dir", required=True, help="directory for the rendered PNGs (not committed)")
    args = ap.parse_args()

    rom_bytes = Path(args.rom).read_bytes()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for sel in UNKNOWN_ROOM_A_SELECTORS:
        img = render_room(rom_bytes, sel)
        out_path = out_dir / f"unknownRoomA_selector{sel}.png"
        img.save(out_path)
        avg_entropy = real_tile_entropy_report(rom_bytes, sel)
        print(f"roomSelector {sel}: saved {out_path}, avg tile entropy {avg_entropy:.2f} bits "
              f"(real art typically ~1.0-1.8, blank=0.0, noise~2.0)")
