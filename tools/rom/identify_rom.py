#!/usr/bin/env python3
"""Identify a Game Boy ROM: hashes + cartridge header fields.

Usage:
    python3 identify_rom.py <path-to-rom> [<path-to-rom> ...]

This tool is read-only: it never modifies the ROM it inspects and never
writes ROM bytes anywhere. It prints a small report to stdout. It is safe to
run against copyrighted ROMs because it does not copy or embed their content
in its output beyond a handful of header fields (title string, checksums,
sizes) that are needed to identify *which* game/revision a dump is.

No third-party dependencies; stdlib only (hashlib).
"""
import hashlib
import json
import sys
from pathlib import Path

# --- Game Boy cartridge header (0x0100-0x014F) field offsets ---------------
HEADER_START = 0x0100
HEADER_END = 0x0150

CART_TYPES = {
    0x00: "ROM ONLY", 0x01: "MBC1", 0x02: "MBC1+RAM", 0x03: "MBC1+RAM+BATTERY",
    0x05: "MBC2", 0x06: "MBC2+BATTERY", 0x08: "ROM+RAM", 0x09: "ROM+RAM+BATTERY",
    0x0B: "MMM01", 0x0C: "MMM01+RAM", 0x0D: "MMM01+RAM+BATTERY",
    0x0F: "MBC3+TIMER+BATTERY", 0x10: "MBC3+TIMER+RAM+BATTERY", 0x11: "MBC3",
    0x12: "MBC3+RAM", 0x13: "MBC3+RAM+BATTERY", 0x19: "MBC5",
    0x1A: "MBC5+RAM", 0x1B: "MBC5+RAM+BATTERY", 0x1C: "MBC5+RUMBLE",
    0x1D: "MBC5+RUMBLE+RAM", 0x1E: "MBC5+RUMBLE+RAM+BATTERY",
    0x20: "MBC6", 0x22: "MBC7+SENSOR+RUMBLE+RAM+BATTERY",
    0xFC: "POCKET CAMERA", 0xFD: "BANDAI TAMA5", 0xFE: "HuC3",
    0xFF: "HuC1+RAM+BATTERY",
}

ROM_SIZES = {
    0x00: (2, "32 KiB (no banking)"), 0x01: (4, "64 KiB"), 0x02: (8, "128 KiB"),
    0x03: (16, "256 KiB"), 0x04: (32, "512 KiB"), 0x05: (64, "1 MiB"),
    0x06: (128, "2 MiB"), 0x07: (256, "4 MiB"), 0x08: (512, "8 MiB"),
}

RAM_SIZES = {
    0x00: "None", 0x01: "2 KiB (unofficial)", 0x02: "8 KiB",
    0x03: "32 KiB (4 banks of 8 KiB)", 0x04: "128 KiB (16 banks of 8 KiB)",
    0x05: "64 KiB (8 banks of 8 KiB)",
}

NEW_LICENSEES = {
    "00": "None", "01": "Nintendo R&D1", "08": "Capcom", "13": "Electronic Arts",
    "18": "Hudson Soft", "19": "b-ai", "20": "KSS", "22": "pow", "24": "PCM Complete",
    "25": "san-x", "28": "Kemco Japan", "29": "seta", "30": "Viacom", "31": "Nintendo",
    "32": "Bandai", "33": "Ocean/Acclaim", "34": "Konami", "35": "Hector",
    "37": "Taito", "38": "Hudson", "39": "Banpresto", "41": "Ubi Soft",
    "42": "Atlus", "44": "Malibu", "46": "angel", "47": "Bullet-Proof",
    "49": "irem", "50": "Absolute", "51": "Acclaim", "52": "Activision",
    "53": "American sammy", "54": "Konami", "55": "Hi tech entertainment",
    "56": "LJN", "57": "Matchbox", "58": "Mattel", "59": "Milton Bradley",
    "60": "Titus", "61": "Virgin", "64": "LucasArts", "67": "Ocean",
    "69": "Electronic Arts", "70": "Infogrames", "71": "Interplay",
    "72": "Broderbund", "73": "sculptured", "75": "sci", "78": "THQ",
    "79": "Accolade", "80": "misawa", "83": "lozc", "86": "Tokuma Shoten Intermedia",
    "87": "Tsukuda Original", "91": "Chunsoft", "92": "Video system",
    "93": "Ocean/Acclaim", "95": "Varie", "96": "Yonezawa/s'pal", "97": "Kaneko",
    "99": "Pack in soft", "A4": "Konami (Yu-Gi-Oh!)",
}

OLD_LICENSEES = {
    0x01: "Nintendo", 0x08: "Capcom", 0x09: "Hot-B", 0x0A: "Jaleco",
    0x0B: "Coconuts Japan", 0x0C: "Elite Systems", 0x13: "EA (Electronic Arts)",
    0x18: "Hudsonsoft", 0x19: "ITC Entertainment", 0x1A: "Yanoman",
    0x1D: "Japan Clary", 0x1F: "Virgin Interactive", 0x24: "PCM Complete",
    0x25: "San-X", 0x28: "Kotobuki Systems", 0x29: "Seta", 0x30: "Infogrames",
    0x31: "Nintendo", 0x32: "Bandai", 0x33: "USE NEW LICENSEE CODE",
    0x34: "Konami", 0x35: "HectorSoft", 0x38: "Capcom", 0x39: "Banpresto",
    0x3C: "Entertainment i", 0x3E: "Gremlin", 0x41: "Ubisoft", 0x42: "Atlus",
    0x44: "Malibu", 0x46: "Angel", 0x47: "Spectrum Holoby", 0x49: "Irem",
    0x4A: "Virgin Interactive", 0x4D: "Malibu", 0x4F: "U.S. Gold",
    0x50: "Absolute", 0x51: "Acclaim", 0x52: "Activision",
    0x53: "American Sammy", 0x54: "Gametek", 0x55: "Park Place",
    0x56: "LJN", 0x57: "Matchbox", 0x59: "Milton Bradley", 0x5A: "Mindscape",
    0x5B: "Romstar", 0x5C: "Naxat Soft", 0x5D: "Tradewest",
    0x60: "Titus", 0x61: "Virgin Interactive", 0x67: "Ocean Interactive",
    0x69: "EA (Electronic Arts)", 0x6E: "Elite Systems", 0x6F: "Electro Brain",
    0x70: "Infogrames", 0x71: "Interplay", 0x72: "Broderbund",
    0x73: "Sculptered Soft", 0x75: "The Sales Curve", 0x78: "t.hq",
    0x79: "Accolade", 0x7A: "Triffix Entertainment", 0x7C: "Microprose",
    0x7F: "Kemco", 0x80: "Misawa Entertainment", 0x83: "Lozc",
    0x86: "Tokuma Shoten Intermedia", 0x8B: "Bullet-Proof Software",
    0x8C: "Vic Tokai", 0x8E: "Ape", 0x8F: "I'Max", 0x91: "Chunsoft",
    0x92: "Video System", 0x93: "Tsubaraya Productions", 0x95: "Varie",
    0x96: "Yonezawa/S'Pal", 0x97: "Kaneko", 0x99: "Arc",
    0x9A: "Nihon Bussan", 0x9B: "Tecmo", 0x9C: "Imagineer", 0x9D: "Banpresto",
    0x9F: "Nova", 0xA1: "Hori Electric", 0xA2: "Bandai", 0xA4: "Konami",
    0xA6: "Kawada", 0xA7: "Takara", 0xA9: "Technos Japan", 0xAA: "Broderbund",
    0xAC: "Toei Animation", 0xAD: "Toho", 0xAF: "Namco", 0xB0: "Acclaim",
    0xB1: "ASCII or Nexsoft", 0xB2: "Bandai", 0xB4: "Square Enix",
    0xB6: "HAL Laboratory", 0xB7: "SNK", 0xB9: "Pony Canyon",
    0xBA: "Culture Brain", 0xBB: "Sunsoft", 0xBD: "Sony Imagesoft",
    0xBF: "Sammy", 0xC0: "Taito", 0xC2: "Kemco", 0xC3: "Squaresoft",
    0xC4: "Tokuma Shoten Intermedia", 0xC5: "Data East", 0xC6: "Tonkinhouse",
    0xC8: "Koei", 0xC9: "UFL", 0xCA: "Ultra", 0xCB: "Vap", 0xCC: "Use Corporation",
    0xCD: "Meldac", 0xCE: "Pony Canyon or", 0xCF: "Angel", 0xD0: "Taito",
    0xD1: "Sofel", 0xD2: "Quest", 0xD3: "Sigma Enterprises", 0xD4: "Ask Kodansha",
    0xD6: "Naxat Soft", 0xD7: "Copya Systems", 0xD9: "Banpresto",
    0xDA: "Tomy", 0xDB: "LJN", 0xDD: "NCS", 0xDE: "Human", 0xDF: "Altron",
    0xE0: "Jaleco", 0xE1: "Towa Chiki", 0xE2: "Yutaka", 0xE3: "Varie",
    0xE5: "Epcoh", 0xE7: "Athena", 0xE8: "Asmik ACE Entertainment",
    0xE9: "Natsume", 0xEA: "King Records", 0xEB: "Atlus", 0xEC: "Epic/Sony Records",
    0xEE: "IGS", 0xF0: "A Wave", 0xF3: "Extreme Entertainment", 0xFF: "LJN",
}

DEST_CODES = {0x00: "Japan (and possibly overseas)", 0x01: "Overseas only"}

CGB_FLAGS = {
    0x80: "CGB backward compatible (works on DMG too)",
    0xC0: "CGB only",
}


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def crc32(data: bytes) -> str:
    import zlib
    return format(zlib.crc32(data) & 0xFFFFFFFF, "08x")


def decode_title(header: bytes, cgb_flag: int) -> str:
    """Title field is 0x0134-0x0143 (16 bytes), but shrinks as newer header
    fields (manufacturer code, CGB flag) were carved out of it over time.
    We just read all 16 bytes and stop at the first NUL / non-printable byte,
    which works for both old and new-style headers."""
    raw = header[0x34:0x44]
    out = []
    for b in raw:
        if b == 0:
            break
        if 0x20 <= b <= 0x7E:
            out.append(chr(b))
        else:
            out.append(f"\\x{b:02x}")
    return "".join(out)


def verify_header_checksum(header: bytes) -> tuple:
    """Header checksum at 0x014D over bytes 0x0134-0x014C."""
    x = 0
    for b in header[0x34:0x4D]:
        x = (x - b - 1) & 0xFF
    stored = header[0x4D]
    return stored, x, stored == x


def verify_global_checksum(data: bytes, header: bytes) -> tuple:
    """Global checksum at 0x014E-0x014F, big-endian, sum of all bytes except
    the checksum bytes themselves."""
    stored = (header[0x4E] << 8) | header[0x4F]
    total = sum(data) - header[0x4E] - header[0x4F]
    total &= 0xFFFF
    return stored, total, stored == total


def identify(path: Path) -> dict:
    data = path.read_bytes()
    size = len(data)
    report = {
        "file": path.name,
        "size_bytes": size,
        "size_kib": size / 1024,
        "sha1": sha1(data),
        "sha256": sha256(data),
        "md5": md5(data),
        "crc32": crc32(data),
    }

    if size < HEADER_END:
        report["error"] = f"File too small to contain a GB header ({size} bytes)"
        return report

    header = data[HEADER_START:HEADER_END]

    cgb_flag = header[0x43]
    title = decode_title(header, cgb_flag)
    new_licensee_raw = header[0x44:0x46]
    try:
        new_licensee_code = new_licensee_raw.decode("ascii")
    except UnicodeDecodeError:
        new_licensee_code = new_licensee_raw.hex()
    sgb_flag = header[0x46]
    cart_type = header[0x47]
    rom_size_code = header[0x48]
    ram_size_code = header[0x49]
    dest_code = header[0x4A]
    old_licensee_code = header[0x4B]
    mask_rom_version = header[0x4C]

    header_checksum_stored, header_checksum_calc, header_ok = verify_header_checksum(header)
    global_checksum_stored, global_checksum_calc, global_ok = verify_global_checksum(data, header)

    rom_size_banks, rom_size_desc = ROM_SIZES.get(rom_size_code, (None, f"UNKNOWN (0x{rom_size_code:02x})"))

    report.update({
        "title_raw": title,
        "cgb_flag": f"0x{cgb_flag:02x}",
        "cgb_flag_desc": CGB_FLAGS.get(cgb_flag, "None (DMG only)" if cgb_flag not in CGB_FLAGS else "?"),
        "sgb_flag": f"0x{sgb_flag:02x}",
        "sgb_supported": sgb_flag == 0x03,
        "cartridge_type_code": f"0x{cart_type:02x}",
        "cartridge_type": CART_TYPES.get(cart_type, f"UNKNOWN (0x{cart_type:02x})"),
        "rom_size_code": f"0x{rom_size_code:02x}",
        "rom_size_desc": rom_size_desc,
        "rom_size_matches_file": (rom_size_banks * 16 * 1024 == size) if rom_size_banks else None,
        "ram_size_code": f"0x{ram_size_code:02x}",
        "ram_size_desc": RAM_SIZES.get(ram_size_code, f"UNKNOWN (0x{ram_size_code:02x})"),
        "destination_code": f"0x{dest_code:02x}",
        "destination_desc": DEST_CODES.get(dest_code, f"UNKNOWN (0x{dest_code:02x})"),
        "old_licensee_code": f"0x{old_licensee_code:02x}",
        "old_licensee_desc": OLD_LICENSEES.get(old_licensee_code, f"UNKNOWN (0x{old_licensee_code:02x})"),
        "new_licensee_code": new_licensee_code if old_licensee_code == 0x33 else None,
        "new_licensee_desc": NEW_LICENSEES.get(new_licensee_code) if old_licensee_code == 0x33 else None,
        "mask_rom_version": mask_rom_version,
        "header_checksum_stored": f"0x{header_checksum_stored:02x}",
        "header_checksum_calculated": f"0x{header_checksum_calc:02x}",
        "header_checksum_ok": header_ok,
        "global_checksum_stored": f"0x{global_checksum_stored:04x}",
        "global_checksum_calculated": f"0x{global_checksum_calc:04x}",
        "global_checksum_ok": global_ok,
    })
    return report


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    for arg in argv[1:]:
        path = Path(arg)
        if not path.is_file():
            print(f"error: not a file: {path}", file=sys.stderr)
            continue
        report = identify(path)
        print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
