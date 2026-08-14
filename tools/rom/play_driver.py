#!/usr/bin/env python3
"""Small interactive-ish driver for dynamic ROM analysis: runs the game
under mGBA for N frames, optionally holding buttons down for a window of
frames, and can dump a screenshot + VRAM tilemap snapshot at named
checkpoints. Meant to be edited/extended per investigation, not a stable
CLI -- see docs/reverse-engineering/tooling.md for the underlying
mgba_env.py bootstrap and technique this builds on.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
import mgba_env  # noqa: E402


class Session:
    def __init__(self, rom_path=None):
        import mgba.image
        self.core = mgba_env.load_core(rom_path)
        w, h = self.core.desired_video_dimensions()
        self.img = mgba.image.Image(w, h)
        self.core.set_video_buffer(self.img)
        self.core.reset()
        self.frame = 0

    def run(self, n):
        for _ in range(n):
            self.core.run_frame()
            self.frame += 1

    def press(self, *keys, hold=6, then_wait=10):
        """Hold `keys` (mgba.core.KEY_* ints) for `hold` frames, release,
        then wait `then_wait` more frames -- mimics a deliberate button
        tap during normal play speed."""
        mask = 0
        for k in keys:
            mask |= k
        self.core.add_keys(mask)
        self.run(hold)
        self.core.clear_keys(mask)
        self.run(then_wait)

    def screenshot(self, path):
        mgba_env.save_frame_png(self.core, self.img, path)

    def vram_tilemap(self, map_index=0):
        """Return the 32x32 background tilemap (map 0: $9800-$9BFF, map
        1: $9C00-$9FFF) as a list of 32 rows of 32 tile indices."""
        vram = self.core.memory.vram.u8[:]
        base = 0x1800 if map_index == 0 else 0x1C00
        rows = []
        for r in range(32):
            rows.append(list(vram[base + r * 32: base + (r + 1) * 32]))
        return rows

    def print_tilemap(self, map_index=0, rows=range(32), cols=range(32)):
        grid = self.vram_tilemap(map_index)
        for r in rows:
            print(f"{r:2d} " + " ".join(f"{grid[r][c]:02x}" for c in cols))


if __name__ == "__main__":
    import mgba.core as _c
    s = Session()
    s.run(71)  # to just before the title text appears (see tooling.md)
    s.run(600 - 71)
    s.screenshot("/tmp/play_00_title.png")
    print("frame", s.frame, "-- title screen, saved /tmp/play_00_title.png")
