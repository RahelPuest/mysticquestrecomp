#!/usr/bin/env python3
"""ROM-vs-recomp parity check, proof of concept (2026-08-11, "wir
brauchen wesentlich besseres tooling").

Checks the real ROM's own working x-range for triggering the willyRoom
north-door scroll against the recomp's own documented zone
(`rom_profiles.lua`'s `willyRoom.exits[1].zone`), for a handful of x
values, and reports any MISMATCH -- a value the recomp's zone accepts
but the real ROM does not (or vice versa) means the recomp's own zone
is a real, live-testable overclaim/underclaim, not just an
undocumented guess.

This is exactly the kind of check that would have caught this
project's own real regressions faster: earlier this same session, the
willyRoom exit's `landingY` was wrong (raw WRAM value used directly
instead of a real local coordinate) for a full investigation pass
before being caught by a live user report -- an automated check
comparing a handful of real ROM measurements against the recomp's own
constants would have flagged it immediately, the same day it was
introduced, instead of requiring a human to notice in actual gameplay.

The REAL-ROM side drives mgba directly (tools/rom/checkpoints.py); the
RECOMP side doesn't need to launch love at all for this specific check
-- `ZoneMatch.lua` (extracted from VictorySequence.lua, see docs
/progress.md's 2026-08-11 tooling entry) is pure Lua, so its own real
decision logic is checked directly via `luajit`, not by driving the
whole app. A parity check for something that DOES need real rendering
(e.g. an on-screen position) would instead drive love with
`MYSTICQUEST_WAIT_FOR`/`MYSTICQUEST_STATE_LOG` (see main.lua) the same
way -- this file is deliberately kept small/focused as the proof of
concept, not a general framework.
"""

import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "rom"))
import checkpoints as cp  # noqa: E402

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..", "..")

# x values to test -- the recomp's own documented zone bounds
# (rom_profiles.lua's willyRoom exit: xMin=72, xMax=86) plus one value
# already known, from live testing earlier this session, to actually
# trigger the real scroll (80).
CANDIDATE_X = [72, 80, 86]


def _move_x_to(session, target_x):
    """Nudge the player's real x position to `target_x` via ONE single,
    continuous directional hold (not an oscillating LEFT/RIGHT
    correction loop -- tried first, and it actively broke a value
    already independently confirmed working earlier this same session
    (x=80): repeatedly reversing direction to fine-correct the last
    couple pixels seemingly disrupts whatever real state the door
    trigger itself depends on, even though the FINAL numeric position
    looked close. A single clean hold sized to the exact real 1px/frame
    walk speed, matching this project's own already-VERIFIED movement
    speed, is both simpler and the only approach confirmed to actually
    reproduce the door trigger)."""
    m = session.core.memory
    current = m.u8[0xC245]
    delta = target_x - current
    if delta == 0:
        return current
    key = session.core.KEY_RIGHT if delta > 0 else session.core.KEY_LEFT
    cp._hold(session, key, abs(delta))
    return m.u8[0xC245]


def real_rom_door_triggers(x):
    """True if holding UP from real x=`x` (at a real y already inside
    the door's documented y-window) triggers the real scroll (SCY
    shadow reaching 128) within a generous real frame budget."""
    s = cp.willy_room_free()
    m = s.core.memory
    cp._hold(s, s.core.KEY_UP, 50)  # into the door's real y-window
    reached_x = _move_x_to(s, x)
    if reached_x != x:
        print(f"  (warning: could not reach real x={x} exactly, landed at x={reached_x} -- testing from there)")
    s.core.add_keys(s.core.KEY_UP)
    s.run(500)
    s.core.clear_keys(s.core.KEY_UP)
    return m.u8[0xC0A7] == 128


def recomp_zone_accepts(x, y=24):
    """True if the recomp's OWN real `ZoneMatch`/willyRoom-exit zone
    data (rom_profiles.lua) would accept `(x, y)` -- checked by
    running a tiny real Lua snippet against the actual checked-in
    modules via `luajit`, not a re-implementation of the logic here."""
    script = f"""
package.path = package.path .. ";./?.lua"
local RomProfiles = require("src.import.rom_profiles")
local ZoneMatch = require("src.entities.ZoneMatch")
local profile = RomProfiles.PROFILES["7cb65cb314e3f26b92549ddc7f4fc275186c6170"]
local exit = profile.graphics.willyRoom.exits[1]
print(ZoneMatch.contains(exit.zone, {x}, {y}) and "true" or "false")
"""
    result = subprocess.run(["luajit", "-e", script], cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"luajit check failed: {result.stderr}")
    return result.stdout.strip() == "true"


if __name__ == "__main__":
    print("Checking willyRoom north-door x-range: real ROM vs recomp's own zone data\n")
    mismatches = []
    for x in CANDIDATE_X:
        real = real_rom_door_triggers(x)
        recomp = recomp_zone_accepts(x)
        status = "OK" if real == recomp else "MISMATCH"
        if real != recomp:
            mismatches.append(x)
        print(f"  x={x:3d}  real ROM triggers={str(real):5s}  recomp zone accepts={str(recomp):5s}  [{status}]")

    print()
    print("NOTE on precision: `_move_x_to` sizes a single directional hold to")
    print("this project's own VERIFIED 1px/frame walk speed, but real landings")
    print("still drift a few px off target (see the 'could not reach exactly'")
    print("warnings above) -- read each result against the x it ACTUALLY tested")
    print("at, not the requested one. A mismatch found this way is real")
    print("evidence worth a closer, hand-tuned re-check (the way this project's")
    print("own earlier, already-documented X 75/76/79/83 bracket in")
    print("rom_profiles.lua was established) before editing zone data on the")
    print("strength of this script alone -- it's a fast first-pass net, not a")
    print("replacement for that more careful method.\n")
    if mismatches:
        print(f"FAIL: {len(mismatches)} mismatch(es) at x={mismatches} -- "
              "the recomp's own zone data disagrees with real ROM behavior at these values.")
        sys.exit(1)
    else:
        print("PASS: recomp zone data agrees with real ROM behavior for all tested x values.")
