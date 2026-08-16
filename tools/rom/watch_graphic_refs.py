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

IMPORTANT real gotcha, fixed 2026-08-16 during cleanup: a watched CPU
address is bank-AMBIGUOUS -- the SAME address can genuinely be read
while a DIFFERENT bank than the one the watch was armed for is
active, and the byte actually read then belongs to whatever candidate
(if any) REALLY owns that (activeBank, address) combination, not the
one the watch happened to be labeled with. Every hit below is
resolved via `graphics_candidates_addresses.resolve()` against the
real (activeBank, address)-derived file offset, not the watch's own
label -- this is exactly how task #160's own real find
(`bank9_icon_fragments` genuinely being read, surfaced under a watch
armed for `bank10_7900`) was actually made.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import mgba_env  # noqa: E402
import checkpoints  # noqa: E402
from watcher import Watcher, rom_offset  # noqa: E402
from mgba._pylib import lib  # noqa: E402
from graphics_candidates_addresses import CANDIDATES, to_cpu, resolve  # noqa: E402


def main():
    steps_budget = int(sys.argv[1]) if len(sys.argv) > 1 else 300000
    print("Reaching courtyard_enemy_engaged() (real, active-combat state)...")
    s = checkpoints.courtyard_enemy_engaged()
    core = s.core

    w = Watcher(core)
    for name, bank, file_offset, _tile_count in CANDIDATES:
        cpu = to_cpu(file_offset)
        w.watch(cpu, kind=lib.WATCHPOINT_READ)
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
            active_bank = core._native.memory.currentBank
            # The real file offset the CPU actually read from, given
            # which bank was genuinely active at hit time -- NOT
            # whichever candidate the watch happened to be armed for.
            real_file_offset = active_bank * 0x4000 + (addr - 0x4000) if addr >= 0x4000 else None
            resolved = resolve(real_file_offset) if real_file_offset is not None else None
            resolved_name = resolved[0] if resolved else "(no known candidate -- real find, or noise)"
            pc_file_offset = rom_offset(core, pc)
            hits.append((i, addr, resolved_name, pc, pc_file_offset, active_bank))
            real_offset_str = f"{real_file_offset:#07x}" if real_file_offset is not None else "?"
            pc_offset_str = f"{pc_file_offset:#07x}" if pc_file_offset is not None else "?"
            print(f"  HIT at step {i}: watched addr {addr:#06x}, activeBank={active_bank} "
                  f"-> real file offset {real_offset_str} = {resolved_name}, "
                  f"read from PC={pc:#06x} (file {pc_offset_str})")
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
