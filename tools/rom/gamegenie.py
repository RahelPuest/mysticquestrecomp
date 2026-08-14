"""Decode Game Boy Game Genie codes into (address, new_value, check_value)
-- ported directly from mgba's own `GBCheatAddGameGenieLine`
(tools-external/mgba/src/gb/cheats.c) rather than re-derived from
scratch, since that's the authoritative, already-correct implementation.

Used this round (2026-08-08, sixth pass) to cross-check community
GameShark/Game Genie codes for the US "Final Fantasy Adventure" cartridge
against this project's own independently-traced ROM addresses -- see
docs/references.md and docs/reverse-engineering/rom-map.md "Breakthrough"
for what this found. GameShark codes need no decoding beyond byte-
swapping the address pair (`01VVAAAA` -> real address is `AAAA` swapped)
so they don't get their own helper here.

A Game Genie code is a ROM patch, not a RAM write: at the decoded
`address`, if the ROM byte there equals `check_value` (when present --
6-digit codes have no check), it's read as `new_value` instead. This is
different in kind from GameShark's "write this RAM address every frame."
"""


def _hex12(s):
    return int(s[:3], 16)


def decode(code):
    """Returns (address, new_value, check_value_or_None)."""
    parts = code.split("-")
    op1 = _hex12(parts[0])
    op2 = _hex12(parts[1])
    op3 = _hex12(parts[2]) if len(parts) > 2 else 0x1000

    address = (op1 & 0xF) << 8
    address |= (op2 >> 4) & 0xFF
    address |= ((op2 & 0xF) ^ 0xF) << 12
    new_value = op1 >> 4

    check_value = None
    if op3 < 0x1000:
        v = ((op3 & 0xF00) << 20) | (op3 & 0xF)
        v = ((v >> 2) | (v << 30)) & 0xFFFFFFFF  # ROR 2 (32-bit)
        v |= v >> 24
        v ^= 0xBA
        check_value = v & 0xFF

    return address, new_value, check_value


def decode_gameshark(code):
    """`01VVAAAA` hex string -> (address, value). GB GameShark stores the
    address byte-swapped relative to how it reads in the code string."""
    op = int(code, 16)
    address = ((op & 0xFF) << 8) | ((op >> 8) & 0xFF)
    value = (op >> 16) & 0xFF
    return address, value


if __name__ == "__main__":
    import sys
    for code in sys.argv[1:]:
        if len(code) == 8 and "-" not in code:
            addr, val = decode_gameshark(code)
            print(f"{code} (GameShark): address={addr:#06x} value={val:#04x}")
        else:
            addr, val, chk = decode(code)
            chk_s = "none" if chk is None else f"{chk:#04x}"
            print(f"{code} (Game Genie): address={addr:#06x} new_value={val:#04x} check_value={chk_s}")
