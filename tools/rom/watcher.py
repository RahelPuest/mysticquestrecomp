"""Native mGBA watchpoints, driven from a bare (non-CLI, non-GDB) debugger.

`mgba.debugger.NativeDebugger.set_watchpoint()` (the bindings' own
convenience wrapper) passes a bare Python int where the native API actually
expects a `const struct mWatchpoint*` -- it doesn't work as-is. And
`mDebuggerCreate()`'s only two concrete types add unwanted machinery for a
scripted driver: DEBUGGER_CLI's `entered` callback (`_reportEntry` in
mgba's cli-debugger.c) unconditionally calls `cliDebugger->backend->printf`
with no null check, so it segfaults unless a real CLI backend (stdio, a
GUI console, ...) is attached; DEBUGGER_GDB needs a socket client on the
other end. Neither fits "single Python process stepping a headless core."

So this builds a bare `struct mDebugger` by hand (`ffi.new`, zero-filled)
and calls `mDebuggerAttach()` directly -- leaving `.entered` NULL, which
`SM83DebuggerEnter` (the platform-level handler that actually matters: it's
what forces `cpu->nextEvent = cpu->cycles`, i.e. what makes a hit visible
promptly) checks for and skips safely. See docs/reverse-engineering/
tooling.md for the reasoning and how this gets used.

Mechanism, confirmed by reading mgba's C sources (src/sm83/debugger/
memory-debugger.c, src/debugger/debugger.c): every SM83 `load8`/`store8`
is shimmed to check the watchpoint list and call `mDebuggerEnter()` on a
match, which sets `debugger.state = DEBUGGER_PAUSED`. That state change
does NOT by itself unwind `core.run_frame()` -- the safe, general way to
notice a hit is to drive the core with `core.step()` (single SM83
instruction each call, same primitive the text-encoding trace used) and
check `watcher.hit` after every step, exactly like a real debugger's
single-step-and-check loop.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
import mgba_env  # noqa: E402
from mgba._pylib import ffi, lib  # noqa: E402


class Watcher:
    def __init__(self, core):
        """`core` is an mgba.gb.GB (or other Core subclass) instance --
        pass the Session's `.core`, not the raw native pointer."""
        self.core = core
        self._debugger = ffi.new("struct mDebugger*")
        lib.mDebuggerAttach(self._debugger, core._core)
        self._watchpoints = []  # keep cdata alive; native list holds copies
        self.last_hit = None
        # mDebugger.entered is a real callback slot (distinct from the
        # SM83 platform's own .entered, which always runs regardless and
        # is what actually forces the CPU loop to notice promptly -- see
        # SM83DebuggerEnter in memory-debugger.c/debugger.c). Wiring this
        # one gets us the full mDebuggerEntryInfo (address/old/new value)
        # instead of just a paused/running flag.
        self._entered_cb = ffi.callback(
            "void(struct mDebugger*, enum mDebuggerEntryReason, struct mDebuggerEntryInfo*)",
            self._on_entered,
        )
        self._debugger.entered = self._entered_cb

    def _on_entered(self, debugger, reason, info):
        if info != ffi.NULL:
            self.last_hit = {
                "reason": reason,
                "address": info.address,
                "oldValue": info.type.wp.oldValue,
                "newValue": info.type.wp.newValue,
                "pointId": info.pointId,
            }
        else:
            self.last_hit = {"reason": reason}

    def watch(self, address, kind=None, segment=-1):
        kind = lib.WATCHPOINT_WRITE if kind is None else kind
        wp = ffi.new(
            "struct mWatchpoint*",
            {"address": address, "segment": segment, "type": kind},
        )
        self._watchpoints.append(wp)
        self._debugger.platform.setWatchpoint(self._debugger.platform, wp)
        return wp

    def watch_many(self, addresses, kind=None):
        for addr in addresses:
            self.watch(addr, kind=kind)

    @property
    def hit(self):
        return self._debugger.state == lib.DEBUGGER_PAUSED

    def resume(self):
        self._debugger.state = lib.DEBUGGER_RUNNING

    def step(self):
        """One SM83 instruction. Returns True if this step triggered a
        watchpoint (and clears the paused state so stepping can continue)."""
        self.core.step()
        if self.hit:
            self.resume()
            return True
        return False

    def run_until_hit(self, max_steps=400000):
        """Single-step until any watchpoint fires. Returns (pc_before,
        steps_taken) for the triggering instruction, or (None, max_steps)."""
        cpu = self.core.cpu
        for i in range(max_steps):
            pc_before = cpu.pc
            if self.step():
                return pc_before, i + 1
        return None, max_steps


def rom_offset(core, pc):
    """Resolve a live SM83 PC into an absolute ROM file offset, honoring
    the current MBC bank mapped at $4000-$7FFF (GBMemory.currentBank) --
    matches the bank*0x4000 + (addr-within-bank) convention already used
    throughout rom-map.md."""
    native = core._native  # struct GB*
    if pc < 0x4000:
        bank0 = native.memory.currentBank0
        return bank0 * 0x4000 + pc
    if pc < 0x8000:
        bank = native.memory.currentBank
        return bank * 0x4000 + (pc - 0x4000)
    return None  # not ROM-mapped (VRAM/WRAM/etc.)
