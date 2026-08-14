"""Live, bank-accurate CALL/RET/RST/interrupt tracer for the SM83 core.

Built to replace a failed technique: reading raw stack bytes *after* a
watchpoint fires and guessing which bank each value was pushed from (see
docs/reverse-engineering/rom-map.md, the door/room-transition trace --
that approach mis-attributed a stack slot to bank 8 and disassembled it
as code when it was actually graphics data, because nothing recorded
which bank was live at the moment each return address got pushed).

This instead decodes the opcode at PC on *every* single step, alongside
Watcher's own stepping, and tracks a real call-frame stack, resolving
each caller/callee address through `rom_offset()` (which reads the
*live* MBC bank registers at that exact instant) -- so by construction
every frame's bank is correct, no post-hoc guessing involved.

Also handles hardware interrupt dispatch (PC jumping to one of the 5 ISR
vectors $40/$48/$50/$58/$60 without a CALL/RST opcode driving it) as a
synthetic call frame, since GB games commonly do exactly the kind of
carefully-timed hardware-register write (e.g. SCY) we're chasing from
inside a VBlank handler -- omitting this would silently desync the frame
stack the first time an interrupt fires mid-trace.

Usage (see also door_calltrace.py style scripts):

    from watcher import Watcher
    from calltrace import CallTracer

    w = Watcher(session.core)
    w.watch(0xFF42)  # SCY, WATCHPOINT_WRITE
    tracer = CallTracer(session.core, rom_bytes)
    for i in range(200000):
        pc_before = session.core.cpu.pc
        op = tracer.peek(pc_before)
        hit = w.step()
        tracer.record(pc_before, op)
        if hit and w.last_hit.get("newValue") == 252:
            print(tracer.format_stack())
            break

Known limitation (documented, not silently swallowed): a CALL/RST whose
own instruction happens to be immediately followed by its own target
address (self-targeting jump-to-next-instruction trick) would read as
"not taken" under the PC-delta heuristic this uses -- not observed in
practice here, flagged for anyone reusing this on unfamiliar code.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from watcher import rom_offset  # noqa: E402

CALL_OPCODES = {0xCD, 0xC4, 0xCC, 0xD4, 0xDC}
RET_OPCODES = {0xC9, 0xD9, 0xC0, 0xC8, 0xD0, 0xD8}
RST_TARGETS = {
    0xC7: 0x00, 0xCF: 0x08, 0xD7: 0x10, 0xDF: 0x18,
    0xE7: 0x20, 0xEF: 0x28, 0xF7: 0x30, 0xFF: 0x38,
}
INT_VECTORS = {0x40, 0x48, 0x50, 0x58, 0x60}


class CallTracer:
    def __init__(self, core, rom_bytes):
        self.core = core
        self.rom = rom_bytes
        self.frames = []  # outermost first; each: caller_pc/off, callee_pc/off, kind
        self.events = []  # flat chronological log, capped by caller if desired

    def peek(self, pc):
        """Read the opcode byte about to execute at `pc`, straight from
        the ROM file via the *current live bank* -- not a guess, since
        rom_offset() reads GBMemory.currentBank/currentBank0 right now."""
        off = rom_offset(self.core, pc)
        if off is None or off >= len(self.rom):
            return None, None
        return self.rom[off], off

    def record(self, pc_before, peeked, log=True):
        """Call immediately after stepping exactly one instruction (via
        Watcher.step() or core.step()) that started at `pc_before`, whose
        opcode+offset came from a prior `peek(pc_before)` call."""
        op, off = peeked
        cpu = self.core.cpu
        pc_after = cpu.pc

        if op is None:
            return  # not ROM-mapped (executing out of RAM/HRAM -- rare)

        if pc_after in INT_VECTORS and pc_after != pc_before + 1 and pc_after != pc_before + 3:
            # PC landed exactly on an ISR vector without the instruction
            # we just read being the thing that put it there -- hardware
            # interrupt dispatch (5 M-cycle atomic push+jump, no opcode
            # byte of its own).
            self._push(pc_before, off, pc_after, "int")
            if log:
                self.events.append(("int", pc_before, off, pc_after))
            return

        if op in RST_TARGETS:
            self._push(pc_before, off, pc_after, "rst")
            if log:
                self.events.append(("rst", pc_before, off, pc_after))
            return

        if op in CALL_OPCODES:
            taken = pc_after != pc_before + 3
            if taken:
                self._push(pc_before, off, pc_after, "call")
                if log:
                    self.events.append(("call", pc_before, off, pc_after))
            return

        if op in RET_OPCODES:
            taken = pc_after != pc_before + 1
            if taken and self.frames:
                popped = self.frames.pop()
                if log:
                    self.events.append(("ret", pc_before, off, pc_after, popped))
            return

    def _push(self, caller_pc, caller_off, callee_pc, kind):
        callee_off = rom_offset(self.core, callee_pc)
        self.frames.append({
            "caller_pc": caller_pc, "caller_off": caller_off,
            "callee_pc": callee_pc, "callee_off": callee_off,
            "kind": kind, "depth": len(self.frames),
        })

    def format_stack(self):
        """Current call stack, outermost (outer) first -- each line is
        the real, bank-resolved caller -> callee for that nesting level,
        unlike raw stack bytes which can't tell you the bank at all."""
        lines = []
        for f in self.frames:
            co = f"{f['callee_off']:#07x}" if f['callee_off'] is not None else "????"
            lines.append(
                f"  depth={f['depth']:2d} [{f['kind']:4s}] "
                f"caller {f['caller_off']:#07x} (PC {f['caller_pc']:#06x}) "
                f"-> callee {co} (PC {f['callee_pc']:#06x})"
            )
        return "\n".join(lines) if lines else "  (empty -- top level)"
