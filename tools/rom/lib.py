#!/usr/bin/env python3
"""Reusable helpers for live mgba ROM investigation -- consolidates
patterns that got hand-rolled from scratch, repeatedly, across one long
investigation session (2026-08-10/11): an OAM dump, an exact-byte ROM
tile-source search, the real Pan Docs OAM hardware-offset conversion
(a units-confusion bug hit more than once this same session), and a
pixel-grid screenshot annotator for precisely reading a position off a
screenshot instead of eyeballing it. See docs/reverse-engineering
/tooling.md for the underlying mgba_env.py bootstrap this all sits on.

Usage: `import lib` from another tools/rom/*.py script (this directory
is already on sys.path via each script's own `sys.path.insert(0, ...)`
convention), or run this file directly for a couple of self-checks.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))


def oam_dump(core):
    """All 40 real OAM entries currently non-hidden (`y` byte not 0 or
    255), as `(slot, y, x, tile, attr)` tuples -- the raw hardware
    values (Pan Docs convention: `y`/`x` are each +16/+8 versus the
    real on-screen position -- see `oam_to_screen` below to convert).
    Reads one byte at a time via `core.memory.oam.u8[i]` rather than a
    slice (`u8[:]` silently returns 159 bytes instead of 160 on this
    binding -- a real off-by-one hit and worked around this same
    session, not a style preference)."""
    oam = core.memory.oam
    out = []
    for slot in range(40):
        base = slot * 4
        y, x, tile, attr = oam.u8[base], oam.u8[base + 1], oam.u8[base + 2], oam.u8[base + 3]
        if y != 0 and y != 255:
            out.append((slot, y, x, tile, attr))
    return out


def oam_to_screen(y, x):
    """The real Pan Docs OAM hardware-offset conversion (`y`-16, `x`-8)
    -- same convention this project's own rom_profiles.lua uses
    throughout (`playerSprite`/`enemySprite`/`willyScene`/etc. doc
    comments). NOT always the right conversion to use blind, though:
    mid-scroll or shortly after a hardware scroll settles, `$C244`/
    `$C245` (the WRAM position shadow, same raw convention as OAM) can
    be a WORLD-space value that has accumulated straight through the
    scroll distance rather than a simple per-room local coordinate --
    confirmed live this same session (see docs/progress.md's dated
    "the secondRoom landing spot" entry) after this exact conversion
    alone gave a wrong answer. Cross-check any result against a real
    screenshot (see `read_position_from_grid` below) before trusting it
    for anything that matters."""
    return y - 16, x - 8


def find_tile_source(rom_bytes, tile_bytes, max_matches=20):
    """Exact-byte search for a real 16-byte GB tile pattern (as read
    live from VRAM, e.g. `bytes(core.memory.vram.u8[t*16:t*16+16])` for
    sprite tile index `t`, unsigned `$8000` addressing -- real OAM/
    sprite tiles always use this addressing regardless of LCDC bit 4)
    within the raw ROM file bytes. Returns a list of matching byte
    offsets (empty if none). This project's own established "exact
    16-byte search" method for finding a real sprite's true ROM source
    -- see rom_profiles.lua's various `tileOffsets` doc comments for
    prior uses; a tile that matches EXACTLY ONE location is
    high-confidence evidence (not proof) that's the real source, not a
    coincidental byte run."""
    positions = []
    start = 0
    while len(positions) < max_matches:
        idx = rom_bytes.find(tile_bytes, start)
        if idx == -1:
            break
        positions.append(idx)
        start = idx + 1
    return positions


def dump_sprite_tiles(core, tile_ids):
    """`{tileId: 16 real raw bytes}` for each id in `tile_ids` -- pairs
    naturally with `find_tile_source` (call this to get the bytes, then
    search the ROM file for each one) and with `oam_dump` (whose own
    `tile` field is exactly what belongs in `tile_ids` here)."""
    vram = core.memory.vram
    out = {}
    for t in tile_ids:
        base = t * 16
        out[t] = bytes(vram.u8[base + i] for i in range(16))
    return out


def grid_overlay_screenshot(src_path, dst_path, crop=None, scale=4, grid=8, label_every=16):
    """Save a copy of the GB-native 160x144 region of `src_path`
    (mgba/love screenshots may be padded to a larger canvas -- this
    project's own screenshots run 256x224, GB content always at the
    top-left origin, see this function's own real-position use in
    docs/progress.md's "secondRoom landing spot" entry) with real pixel
    gridlines and coordinate labels burned in, so a position can be
    read directly off the image instead of eyeballed. `crop`: optional
    `(x0,y0,x1,y1)` in real GB-canvas pixels to zoom into first (labels
    stay in real GB-canvas coordinates, not crop-relative, so they're
    directly comparable across different crops of the same screenshot).

    IMPORTANT (a real calibration bug hit and fixed this same session):
    always sanity-check this technique once against an ALREADY-known
    real position (e.g. rom_profiles.lua's own `playerSprite.screenX/
    screenY`) in an unrelated screenshot before trusting a NEW
    measurement from it -- an earlier crop-coordinate mixup this same
    session produced a measurement off by dozens of pixels that looked
    plausible until cross-checked this way.
    """
    from PIL import Image, ImageDraw  # local import: PIL is not a hard dependency of every script here

    im = Image.open(src_path).crop((0, 0, 160, 144)).convert("RGB")
    x0, y0, x1, y1 = crop or (0, 0, 160, 144)
    im = im.crop((x0, y0, x1, y1))
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    d = ImageDraw.Draw(im)
    for x in range(0, x1 - x0 + 1, grid):
        real_x = x0 + x
        d.line([(x * scale, 0), (x * scale, im.height)], fill=(255, 0, 0), width=1)
        if real_x % label_every == 0:
            d.text((x * scale + 2, 2), str(real_x), fill=(255, 0, 0))
    for y in range(0, y1 - y0 + 1, grid):
        real_y = y0 + y
        d.line([(0, y * scale), (im.width, y * scale)], fill=(0, 0, 255), width=1)
        if real_y % label_every == 0:
            d.text((2, y * scale + 2), str(real_y), fill=(0, 0, 255))
    im.save(dst_path)
    return dst_path


def capture_closed_cycle(session, oam_filter, step_frames, max_steps=400):
    """Sample a moving OAM-tracked object's own CENTROID every
    `step_frames` real frames (default matches this project's own real
    25f/step captures), looking for a genuinely CLOSED repeating cycle
    -- not just "however many frames I happened to capture."

    GENERALIZED (2026-08-12, direct instruction to turn one-off
    investigation scripts into reusable systems) from the real mistake
    that produced this project's own original, WRONG `Enemy.
    MOVEMENT_CYCLE` (see docs/progress.md's "Enemy movement" entry, and
    rom-map.md's 2026-08-12 correction): that capture ran only 700 real
    frames, never actually saw the real cycle close, and got "fixed" by
    inventing a mirror-image return leg to force it closed -- a
    plausible-looking guess this project itself later had to correct
    once a much longer real capture (6000 frames) found the true period
    was 825 frames, not <=700. This function encodes the FIX as the
    default method, not a warning to remember by hand: it runs until it
    can PROVE closure (a later sample position exactly matches an
    earlier one), not until a fixed frame budget runs out, and reports
    honestly if it can't find one within `max_steps`.

    `oam_filter(entries)`: given `oam_dump()`'s own real per-frame
    output, return just the entries belonging to the object being
    tracked (e.g. `lambda es: [e for e in es if e[0] not in (8, 9)]` to
    exclude two known player slots) -- this function doesn't guess
    which OAM entries matter.

    Returns `(cycle, period_frames)` where `cycle` is a list of real
    `(dy, dx)` per-step deltas that sum to EXACTLY `(0, 0)` -- a
    genuinely closed loop, confirmed by direct repetition, not just
    arithmetic -- or `(None, None)` if no closure was found within
    `max_steps` (an honest negative, not a forced/guessed answer).
    """
    positions = []  # list of (avg_y, avg_x), one per real sample
    last = None
    for _ in range(max_steps):
        session.run(step_frames)
        entries = oam_filter(oam_dump(session.core))
        if not entries:
            continue
        avg_y = sum(e[1] for e in entries) / len(entries)
        avg_x = sum(e[2] for e in entries) / len(entries)
        cur = (avg_y, avg_x)
        if cur != last:
            positions.append(cur)
            last = cur
            # Look for the CURRENT position exactly matching any earlier
            # one -- a real, direct closure proof, not an assumption.
            for i in range(len(positions) - 1):
                if positions[i] == cur and i > 0:
                    period = len(positions) - 1 - i
                    cycle = [
                        (round(positions[i + 1 + k][0] - positions[i + k][0]),
                         round(positions[i + 1 + k][1] - positions[i + k][1]))
                        for k in range(period)
                    ]
                    return cycle, period * step_frames
    return None, None


def sample_palette_at(session_factory, checkpoint_fns):
    """Read real OBP0/OBP1/BGP at each of several DIFFERENT, real,
    presumed-calm checkpoints (not one single live sample) -- returns a
    dict `{checkpoint_name: (obp0, obp1, bgp)}` plus a printed warning
    if they disagree.

    GENERALIZED (2026-08-12) from a real bug this exact single-sample
    habit caused: `willyScene.paletteShadeIndices` (`0xFB`) was a real,
    correctly-read value -- captured mid-dialogue-box, then wrongly
    reused as if it were the general resting palette everywhere. A
    second live sample (this project's own `willy_room_free()`, well
    after any dialogue box) would have caught the discrepancy on the
    spot instead of shipping it. `checkpoint_fns`: `{name: fn}`, each
    `fn(session=None)` a real checkpoint recipe (see checkpoints.py) --
    call with EVERY checkpoint that's supposed to represent the "same"
    real resting state, and check they actually agree before trusting
    any one of them as "the" value.
    """
    results = {}
    for name, fn in checkpoint_fns.items():
        s = session_factory() if session_factory else None
        s = fn(session=s) if s is not None else fn()
        m = s.core.memory
        results[name] = (m.u8[0xFF48], m.u8[0xFF49], m.u8[0xFF47])
    distinct = set(results.values())
    if len(distinct) > 1:
        print("sample_palette_at: DISAGREEMENT across checkpoints -- do not "
              "trust any single sample as \"the\" resting palette:")
        for name, val in results.items():
            print("  %s: OBP0=%#04x OBP1=%#04x BGP=%#04x" % (name, *val))
    return results


if __name__ == "__main__":
    # Self-check: oam_to_screen against an already-known real value
    # (rom_profiles.lua's willyScene.player: raw OAM (96,88) -> real
    # (80,80)).
    assert oam_to_screen(96, 88) == (80, 80), "oam_to_screen convention regressed"
    print("lib.py self-check OK")
