"""Shared (bank, fileOffset) list for the two task #160 access-analysis
tools (find_graphic_refs.py, watch_graphic_refs.py) -- factored out
2026-08-16 during cleanup so the two scripts don't carry two silently-
divergible copies of the same 14 GraphicsCandidates.lua base addresses
plus positive controls. This is a plain, hand-copied snapshot (not a
live read of GraphicsCandidates.lua -- these are one-off investigation
scripts, not part of the tested export pipeline), so if
GraphicsCandidates.lua ever gains/loses entries, update this list too.

Each entry: (name, bank, fileOffset, tileCount). `fileOffset` is the
real, 16-byte-tile-aligned ROM file offset of the region's own first
tile; `tileCount` (real, from GraphicsCandidates.lua/rom_profiles.lua)
lets `resolve()` below map a live hit's own (activeBank, address) back
to the CORRECT candidate by range containment -- not just by whichever
candidate a watchpoint happened to be armed under (a real gotcha task
#160 hit live: a watch armed for `bank10_7900`'s own base address
fired while a DIFFERENT bank was active, and the byte actually read
was really inside `bank9_icon_fragments`). `to_cpu()` converts a file
offset to the bank-relative CPU address ($4000-$7FFF) both tools
actually search/watch for.
"""

CANDIDATES = [
    # --- Positive controls: ALREADY-CONFIRMED regions (rom_profiles.lua) ---
    ("CONTROL_enemySprite", 11, 0x2FE00, 16),
    ("CONTROL_font", 8, 0x22B00, 80),  # see rom_profiles.lua graphics.font
    # --- The 14 real GraphicsCandidates.lua entries (unconfirmed identity) ---
    ("bank10_7900", 10, 0x2B900, 44),
    ("bank10_6400", 10, 0x2A400, 34),
    ("bank10_6A20", 10, 0x2AA20, 33),
    ("bank10_6D90", 10, 0x2AD90, 33),
    ("bank11_5220", 11, 0x2D220, 34),
    ("bank8_portraits", 8, 0x22260, 32),
    ("bank8_icon_fragments", 8, 0x22EE0, 274),
    ("bank9_creature_columns", 9, 0x24400, 704),
    ("bank9_icon_fragments", 9, 0x27000, 256),
    ("bank11_creatures_a", 11, 0x2C400, 216),
    ("bank11_creatures_b", 11, 0x2D180, 216),
    ("bank11_creatures_c", 11, 0x2DF00, 216),
    ("bank11_creatures_d", 11, 0x2EC80, 216),
    ("bank12_environment_b", 12, 0x31000, 256),
]


def to_cpu(file_offset):
    """Real bank-relative CPU address ($4000-$7FFF) for a flat ROM file
    offset -- same convention as `watcher.py`'s own `rom_offset()`
    (inverse direction)."""
    return 0x4000 + (file_offset % 0x4000)


def bank_of(file_offset):
    return file_offset // 0x4000


def resolve(file_offset):
    """The candidate (if any) whose own [fileOffset, fileOffset +
    tileCount*16) range genuinely CONTAINS `file_offset` -- the correct
    way to name a live hit (see the module doc comment's own real
    cross-bank mislabeling gotcha). Returns the matching CANDIDATES
    tuple, or None if `file_offset` isn't inside any of them."""
    for entry in CANDIDATES:
        name, bank, base, tile_count = entry
        if base <= file_offset < base + tile_count * 16:
            return entry
    return None
