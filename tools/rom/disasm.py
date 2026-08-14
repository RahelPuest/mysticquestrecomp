"""Minimal, careful SM83 (GB CPU) disassembler -- reads ROM bytes reliably
instead of hand-counting hex, which produced at least one real mistake in
the room-load call-chain trace (see docs/reverse-engineering/rom-map.md
"Maps", fourth pass) before this existed. Standard, well-documented GB
opcode table; covers unprefixed + CB-prefixed opcodes actually needed so
far, not a byte-perfect exhaustive table (verify against real ROM bytes +
mgba live traces before trusting a new region, same as everywhere else in
this project's reverse-engineering work).

CLI usage: `python3 disasm.py <rom_path> <start_hex> <end_hex>`.
Library usage: `disasm_range(data, start, end)` -> list of
`(address, raw_hex_str, mnemonic)`.
"""

R8 = ["B", "C", "D", "E", "H", "L", "(HL)", "A"]
R16 = ["BC", "DE", "HL", "SP"]
R16STK = ["BC", "DE", "HL", "AF"]
COND = ["NZ", "Z", "NC", "C"]
ALU = ["ADD A,", "ADC A,", "SUB ", "SBC A,", "AND ", "XOR ", "OR ", "CP "]
CB_OPS = ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL"]


def s8(v):
    return v - 256 if v >= 128 else v


def decode_one(data, addr):
    op = data[addr]
    n = 1

    def u8():
        return data[addr + 1]

    def u16():
        return data[addr + 1] | (data[addr + 2] << 8)

    if op == 0x00:
        return "NOP", 1
    if op == 0x10:
        return "STOP", 2
    if op == 0x76:
        return "HALT", 1
    if op == 0xF3:
        return "DI", 1
    if op == 0xFB:
        return "EI", 1
    if op == 0xC9:
        return "RET", 1
    if op == 0xD9:
        return "RETI", 1
    if op == 0x07:
        return "RLCA", 1
    if op == 0x0F:
        return "RRCA", 1
    if op == 0x17:
        return "RLA", 1
    if op == 0x1F:
        return "RRA", 1
    if op == 0x27:
        return "DAA", 1
    if op == 0x2F:
        return "CPL", 1
    if op == 0x37:
        return "SCF", 1
    if op == 0x3F:
        return "CCF", 1
    if op == 0xE9:
        return "JP HL", 1

    if op == 0xCB:
        op2 = data[addr + 1]
        reg = R8[op2 & 7]
        grp = op2 >> 6
        if grp == 1:
            return f"BIT {(op2>>3)&7},{reg}", 2
        if grp == 2:
            return f"RES {(op2>>3)&7},{reg}", 2
        if grp == 3:
            return f"SET {(op2>>3)&7},{reg}", 2
        return f"{CB_OPS[(op2>>3)&7]} {reg}", 2

    # LD r,n
    if op & 0xC7 == 0x06:
        r = R8[(op >> 3) & 7]
        return f"LD {r},{u8():#04x}", 2
    # LD r,r'
    if 0x40 <= op <= 0x7F:
        dst = R8[(op >> 3) & 7]
        src = R8[op & 7]
        return f"LD {dst},{src}", 1
    # 16-bit inc/dec
    if op & 0xCF == 0x03:
        return f"INC {R16[(op>>4)&3]}", 1
    if op & 0xCF == 0x0B:
        return f"DEC {R16[(op>>4)&3]}", 1
    if op & 0xCF == 0x09:
        return f"ADD HL,{R16[(op>>4)&3]}", 1
    # 8-bit inc/dec
    if op & 0xC7 == 0x04:
        return f"INC {R8[(op>>3)&7]}", 1
    if op & 0xC7 == 0x05:
        return f"DEC {R8[(op>>3)&7]}", 1
    # LD rr,nn
    if op & 0xCF == 0x01:
        return f"LD {R16[(op>>4)&3]},{u16():#06x}", 3
    # LD (rr),A / LD A,(rr)
    if op == 0x02:
        return "LD (BC),A", 1
    if op == 0x12:
        return "LD (DE),A", 1
    if op == 0x0A:
        return "LD A,(BC)", 1
    if op == 0x1A:
        return "LD A,(DE)", 1
    if op == 0x22:
        return "LD (HL+),A", 1
    if op == 0x2A:
        return "LD A,(HL+)", 1
    if op == 0x32:
        return "LD (HL-),A", 1
    if op == 0x3A:
        return "LD A,(HL-)", 1
    if op == 0x08:
        return f"LD ({u16():#06x}),SP", 3
    if op == 0xEA:
        return f"LD ({u16():#06x}),A", 3
    if op == 0xFA:
        return f"LD A,({u16():#06x})", 3
    if op == 0xE0:
        return f"LDH ({0xFF00+u8():#06x}),A", 2
    if op == 0xF0:
        return f"LDH A,({0xFF00+u8():#06x})", 2
    if op == 0xE2:
        return "LD ($FF00+C),A", 1
    if op == 0xF2:
        return "LD A,($FF00+C)", 1
    if op == 0xF9:
        return "LD SP,HL", 1
    if op == 0xF8:
        return f"LD HL,SP{s8(u8()):+d}", 2
    if op == 0xE8:
        return f"ADD SP,{s8(u8()):+d}", 2
    # PUSH/POP
    if op & 0xCF == 0xC5:
        return f"PUSH {R16STK[(op>>4)&3]}", 1
    if op & 0xCF == 0xC1:
        return f"POP {R16STK[(op>>4)&3]}", 1
    # ALU A,r / A,n
    if 0x80 <= op <= 0xBF:
        mn = ALU[(op >> 3) & 7]
        return f"{mn}{R8[op & 7]}", 1
    if op & 0xC7 == 0xC6:
        mn = ALU[(op >> 3) & 7]
        return f"{mn}{u8():#04x}", 2
    # JR
    if op == 0x18:
        tgt = addr + 2 + s8(u8())
        return f"JR {tgt:#06x}", 2
    if op & 0xE7 == 0x20:
        tgt = addr + 2 + s8(u8())
        return f"JR {COND[(op>>3)&3]},{tgt:#06x}", 2
    # JP
    if op == 0xC3:
        return f"JP {u16():#06x}", 3
    if op & 0xE7 == 0xC2:
        return f"JP {COND[(op>>3)&3]},{u16():#06x}", 3
    # CALL
    if op == 0xCD:
        return f"CALL {u16():#06x}", 3
    if op & 0xE7 == 0xC4:
        return f"CALL {COND[(op>>3)&3]},{u16():#06x}", 3
    # RET cc
    if op & 0xE7 == 0xC0:
        return f"RET {COND[(op>>3)&3]}", 1
    # RST
    if op & 0xC7 == 0xC7:
        return f"RST {op & 0x38:#04x}", 1

    return f"DB {op:#04x}", 1


def disasm_range(data, start, end):
    a = start
    out = []
    while a < end:
        mn, n = decode_one(data, a)
        raw = " ".join(f"{b:02x}" for b in data[a:a + n])
        out.append((a, raw, mn))
        a += n
    return out


if __name__ == "__main__":
    import sys
    path = sys.argv[1]
    start = int(sys.argv[2], 16)
    end = int(sys.argv[3], 16)
    data = open(path, "rb").read()
    for a, raw, mn in disasm_range(data, start, end):
        print(f"{a:#06x}  {raw:<9s} {mn}")
