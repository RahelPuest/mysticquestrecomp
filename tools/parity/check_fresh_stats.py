#!/usr/bin/env python3
"""ROM-vs-recomp parity check #2 (2026-08-12, quick win #4, "1 dann 2
dann 3 dann 4" -- expanding parity-check tooling past the single
door-zone proof of concept).

Checks the real ROM's own fresh-character player-stats struct (WRAM
`$D7B2`, see docs/reverse-engineering/combat.md's "Player stats
struct" -- VERIFIED) against the recomp's own hardcoded fresh-character
defaults (`Field.lua`'s `Stats.new(savedStats or {curLP=19, maxLP=19,
curMP=6, maxMP=6, level=1, gold=50})`), read at a real, reproducible
early checkpoint (`checkpoints.courtyard_enemy_engaged` -- fresh boot,
walked up to the gate creature, BEFORE any combat/damage/gold pickup
could have changed these values away from their fresh-character
starting point).

Unlike `check_door_zone.py` (which drives the recomp side via a tiny
pure-Lua `ZoneMatch` snippet, since that specific check is pure logic),
this check's recomp side is a single, static constant already checked
into `Field.lua` -- read directly from the source file via a small,
targeted regex, not a live `love` launch (no rendering/timing is
involved in "what number is hardcoded here," so launching the whole
app would only add real startup cost for zero real additional
coverage). A parity check that DOES need real recomp *behavior* (e.g.
"does the HUD draw the right string") belongs in a THIRD script using
`MYSTICQUEST_STATE_LOG`/`MYSTICQUEST_WAIT_FOR`, same pattern
`check_door_zone.py`'s own doc comment already anticipated -- not
duplicated here, since this check's whole point is the underlying DATA
value, not any rendering of it.

Usage: python3 tools/parity/check_fresh_stats.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "rom"))
import checkpoints as cp  # noqa: E402

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
FIELD_LUA = os.path.join(REPO_ROOT, "src", "app", "states", "Field.lua")

# Real WRAM struct (see this script's own doc comment): $D7B2 curLP(u16)
# $D7B4 maxLP(u16) $D7B6 curMP(u16) $D7B8 maxMP(u16) $D7BA level(u8)
# $D7BE gold(u16) -- little-endian, matching every other multi-byte GB
# WRAM read this project's own tools/rom/ scripts already use.
STRUCT_BASE = 0xD7B2
FIELDS = [
    ("curLP", 0x00, 2),
    ("maxLP", 0x02, 2),
    ("curMP", 0x04, 2),
    ("maxMP", 0x06, 2),
    ("level", 0x08, 1),
    ("gold", 0x0C, 2),
]


def real_rom_fresh_stats():
    """Real WRAM struct values at the real, reproducible
    `courtyard_enemy_engaged` checkpoint (fresh boot, gate creature
    engaged, no combat/damage/gold pickup possible yet)."""
    s = cp.courtyard_enemy_engaged()
    m = s.core.memory
    result = {}
    for name, delta, width in FIELDS:
        addr = STRUCT_BASE + delta
        if width == 1:
            result[name] = m.u8[addr]
        else:
            result[name] = m.u8[addr] | (m.u8[addr + 1] << 8)
    return result


def recomp_fresh_stats():
    """The recomp's OWN hardcoded fresh-character defaults, read
    directly from `Field.lua`'s own source (not re-typed here, so this
    check can't silently drift from the real checked-in constant it's
    supposed to be checking)."""
    with open(FIELD_LUA, "r", encoding="utf-8") as f:
        src = f.read()
    match = re.search(
        r"Stats\.new\(savedStats or \{([^}]*)\}\)", src)
    if not match:
        raise RuntimeError(
            "could not find Field.lua's own 'Stats.new(savedStats or {...})' "
            "fresh-character default table -- has it moved/been renamed?")
    body = match.group(1)
    result = {}
    for name, _, _ in FIELDS:
        field_match = re.search(name + r"\s*=\s*(\d+)", body)
        if not field_match:
            raise RuntimeError(f"Field.lua's default table has no '{name}' field")
        result[name] = int(field_match.group(1))
    return result


if __name__ == "__main__":
    print("Checking fresh-character player stats: real ROM ($D7B2 struct) vs "
          "recomp's own Field.lua default\n")

    real = real_rom_fresh_stats()
    recomp = recomp_fresh_stats()

    mismatches = []
    for name, _, _ in FIELDS:
        r, c = real[name], recomp[name]
        status = "OK" if r == c else "MISMATCH"
        if r != c:
            mismatches.append(name)
        print(f"  {name:6s}  real ROM={r:<5d}  recomp={c:<5d}  [{status}]")

    print()
    if mismatches:
        print(f"FAIL: {len(mismatches)} mismatch(es): {mismatches} -- "
              "the recomp's own Field.lua default disagrees with the real "
              "ROM's fresh-character WRAM values.")
        sys.exit(1)
    else:
        print("PASS: recomp's fresh-character defaults agree with the real "
              "ROM's own WRAM struct for all 6 fields.")
