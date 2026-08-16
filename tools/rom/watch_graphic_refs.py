#!/usr/bin/env python3
"""Live follow-up to find_graphic_refs.py's decisive static negative
result (no clean `LD BC/DE/HL,<addr>` code reference found for ANY
GraphicsCandidates.lua entry -- INCLUDING the two positive controls,
`enemySprite` and the font tileset, both of which this project has
already independently, visually confirmed ARE loaded and rendered by
real code). That means the real tile-loading code does not embed a
literal per-region source pointer as an immediate operand -- it must
compute the address (base + index*stride, matching the ALREADY-known
`tilesetFileOffset + tileId*16` formula this project uses for the
generic environment tileset) or fetch it from a data table this
project hasn't independently confirmed as a pointer table yet.

So: watch REAL ROM READS (not a static byte pattern) on each
candidate's own base CPU address while the real game is actively
running through a state we ALREADY KNOW exercises real graphics
loading (`courtyard_enemy_engaged` -- the real gate-creature enemy
sprite is on screen and animating right before/at contact, per
rom_profiles.lua's own `enemySprite` doc comment) -- this is a
sensitive-enough, honest DYNAMIC cross-check of the static result, not
a claim of exhaustive coverage of the whole game.

Uses `Watcher` (watcher.py) -- `core.step()`-driven single-stepping
with native mGBA watchpoints, the SAME primitive task #150's own
concurrent-script investigation already used, per that doc comment
in rom-map.md.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import mgba_env  # noqa: E402
import checkpoints  # noqa: E402
from watcher import Watcher, rom_offset  # noqa: E402
from mgba._pylib import lib  # noqa: E402

CANDIDATES = [
    ("CONTROL_enemySprite", 11, 0x2FE00),
    ("CONTROL_font", 8, 0x22B00),
    ("bank10_7900", 10, 0x2B900),
    ("bank10_6400", 10, 0x2A400),
    ("bank10_6A20", 10, 0x2AA20),
    ("bank10_6D90", 10, 0x2AD90),
    ("bank11_5220", 11, 0x2D220),
    ("bank8_portraits", 8, 0x22260),
    ("bank8_icon_fragments", 8, 0x22EE0),
    ("bank9_creature_columns", 9, 0x24400),
    ("bank9_icon_fragments", 9, 0x27000),
    ("bank11_creatures_a", 11, 0x2C400),
    ("bank11_creatures_b", 11, 0x2D180),
    ("bank11_creatures_c", 11, 0x2DF00),
    ("bank11_creatures_d", 11, 0x2EC80),
    ("bank12_environment_b", 12, 0x31000),
]


def to_cpu(file_offset):
    return 0x4000 + (file_offset % 0x4000)


def main():
    steps_budget = int(sys.argv[1]) if len(sys.argv) > 1 else 300000
    print(f"Reaching courtyard_enemy_engaged() (real, active-combat state)...")
    s = checkpoints.courtyard_enemy_engaged()
    core = s.core

    w = Watcher(core)
    addr_to_name = {}
    for name, bank, file_offset in CANDIDATES:
        cpu = to_cpu(file_offset)
        w.watch(cpu, kind=lib.WATCHPOINT_READ)
        addr_to_name.setdefault(cpu, []).append((name, bank))
        print(f"  armed READ watch: {name}  bank={bank}  cpu={cpu:#06x}")

    print(f"\nSingle-stepping up to {steps_budget} real SM83 instructions "
          f"(attacking the engaged enemy periodically to keep combat/animation active)...")
    hits = []
    cpu_iface = core.cpu
    attack_every = 4000
    i = 0
    while i < steps_budget:
        if i % attack_every == 0:
            # Real A-button tap, same convention as courtyard_boss_defeated's
            # own attack loop -- keeps the fight (and its real animation/
            # combat scripts) actively running instead of the enemy just
            # idling, without ending the fight (courtyard_enemy_engaged's
            # own real HP is high enough to absorb many taps).
            core.set_keys(core.KEY_A)
        else:
            core.set_keys(0)
        hit = w.step()
        i += 1
        if hit:
            pc = cpu_iface.pc
            addr = w.last_hit.get("address")
            names = addr_to_name.get(addr, [("?", "?")])
            off = rom_offset(core, pc)
            hits.append((i, addr, names, pc, off, core._native.memory.currentBank))
            print(f"  HIT at step {i}: watched addr {addr:#06x} ({names}) "
                  f"read from PC={pc:#06x} (file {off if off is not None else '?'}) "
                  f"activeBank={core._native.memory.currentBank}")
    print(f"\nDone. {len(hits)} total hits across {i} steps.")
    if not hits:
        print("NO hits for ANY candidate, including the 2 positive controls "
              "(enemySprite/font) -- during this real active-combat window, "
              "these known-used regions were not read via a plain memory "
              "load either. Consistent with the static scan's own finding: "
              "real tile loading likely happens via a bulk DMA-style/OAM "
              "transfer mechanism this simple byte/read-address probe does "
              "not observe this way, or happened earlier (before this "
              "checkpoint) and is cached/already resident, not re-read per "
              "frame.")


if __name__ == "__main__":
    main()
