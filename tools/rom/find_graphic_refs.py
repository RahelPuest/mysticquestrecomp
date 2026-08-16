#!/usr/bin/env python3
"""Static lead generator: for a list of known real tile-region base
addresses (this project's own GraphicsCandidates.lua entries, plus a
couple of ALREADY-CONFIRMED regions used as a positive control), scans
the WHOLE ROM file for byte sequences that look like code LOADING that
address as a 16-bit immediate into BC/DE/HL (opcodes 0x01/0x11/0x21) --
the standard SM83 idiom for "here is a source pointer for a block
copy". Byte-pattern matching is bank-agnostic (the search doesn't care
which CPU bank was active), but the CPU address used for matching IS
bank-relative ($4000-$7FFF, `0x4000 + fileOffset % 0x4000`) -- the same
convention this project's own tile tables already use everywhere.

This is a LEAD GENERATOR ONLY, same status as scan_graphics.py/
scan_pointers.py -- a hit here is a real, byte-exact code reference
worth manually inspecting (with disasm.py's own `disasm_range`, and
ideally a live mgba breakpoint), NOT proof of "this is how species N
gets its graphics." A 2-byte immediate can coincidentally match
unrelated code; cross-bank ambiguity means the SAME cpu address can
"hit" in code that actually executes in a different bank.

Usage: `python3 find_graphic_refs.py <rom_path>`
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from disasm import disasm_range  # noqa: E402
from graphics_candidates_addresses import CANDIDATES, to_cpu, bank_of  # noqa: E402

# Opcode -> which 16-bit register pair it loads (SM83: 0x01=LD BC,nn;
# 0x11=LD DE,nn; 0x21=LD HL,nn; 0x31=LD SP,nn -- SP is never a graphics
# source pointer in practice, so left out to cut noise).
LOAD_IMM16_OPCODES = {0x01: "BC", 0x11: "DE", 0x21: "HL"}


def find_immediate_refs(data, cpu_addr):
    """Every file offset where `cpu_addr` appears as the 2-byte LE
    operand of a real LD BC/DE/HL,nn instruction. Returns a list of
    (fileOffset_of_opcode, register)."""
    lo = cpu_addr & 0xFF
    hi = (cpu_addr >> 8) & 0xFF
    hits = []
    # Search for the 2-byte pattern first (cheap), then check the
    # preceding byte is one of the load-immediate opcodes.
    start = 0
    needle = bytes([lo, hi])
    while True:
        i = data.find(needle, start)
        if i == -1:
            break
        if i > 0 and data[i - 1] in LOAD_IMM16_OPCODES:
            hits.append((i - 1, LOAD_IMM16_OPCODES[data[i - 1]]))
        start = i + 1
    return hits


def find_raw_occurrences(data, cpu_addr):
    """Every file offset where the raw 2-byte LE value appears at all
    (no opcode gate) -- much noisier, but catches pointer-TABLE
    storage (a data value, not a code immediate). Returns a plain list
    of file offsets."""
    lo = cpu_addr & 0xFF
    hi = (cpu_addr >> 8) & 0xFF
    needle = bytes([lo, hi])
    hits = []
    start = 0
    while True:
        i = data.find(needle, start)
        if i == -1:
            break
        hits.append(i)
        start = i + 1
    return hits


def context(data, file_offset, before=6, after=10):
    """A short disassembly window AROUND a hit, for a human to read.
    Addresses printed are FLAT FILE offsets (not real CPU addresses --
    disasm.py has no bank concept), explicitly labeled as such."""
    lo = max(0, file_offset - before)
    # Re-sync disassembly a few bytes back so multi-byte instructions
    # straddling `lo` don't desync the window -- not perfect (SM83 is
    # not self-synchronizing), good enough for a short human-read window.
    lines = disasm_range(data, lo, file_offset + after)
    return lines


def main():
    rom_path = sys.argv[1]
    data = open(rom_path, "rb").read()
    print(f"ROM: {rom_path} ({len(data)} bytes)\n")

    for name, bank, file_offset, _tile_count in CANDIDATES:
        cpu = to_cpu(file_offset)
        print(f"=== {name}  bank={bank}  fileOffset={file_offset:#07x}  cpu={cpu:#06x} ===")
        imm_hits = find_immediate_refs(data, cpu)
        raw_hits = find_raw_occurrences(data, cpu)
        print(f"  LD BC/DE/HL,{cpu:#06x} code hits: {len(imm_hits)}")
        for off, reg in imm_hits[:8]:
            hb = bank_of(off)
            print(f"    file {off:#07x} (bank {hb}, matches candidate bank: {hb == bank})  LD {reg},{cpu:#06x}")
            for a, raw, mn in context(data, off):
                marker = " <=" if a == off else ""
                print(f"      {a:#07x}  {raw:<9s} {mn}{marker}")
        print(f"  raw 2-byte occurrences (incl. above): {len(raw_hits)}")
        print()


if __name__ == "__main__":
    main()
