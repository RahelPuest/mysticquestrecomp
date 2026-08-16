# Mystic Quest (EU) — ROM Map

Target ROM: `MYSTIC QUEST`, SHA-1 `7cb65cb314e3f26b92549ddc7f4fc275186c6170`
(see [../rom-identification.md](../rom-identification.md)). 256 KiB, MBC2,
16 banks of 16 KiB. Bank 0 is fixed at CPU `$0000-$3FFF`; banks 1-15 are
switched into `$4000-$7FFF`. All offsets below are given as both a flat
**file offset** (byte position in the raw 262,144-byte dump) and the
**bank/CPU-address** pair that implies, computed by `tools/rom/
scan_graphics.py`'s `offset_to_bank()`: `bank = file_offset // 0x4000`,
`addr = 0x4000 + (file_offset % 0x4000)` for bank ≥ 1.

Every entry is marked:

- **VERIFIED** — directly confirmed against the ROM bytes by a reproducible
  method described inline (usually: decode as Game Boy 2bpp tiles, render
  to PNG, visually inspect the result).
- **PARTIALLY VERIFIED** — a region/structure is confirmed to exist and
  roughly where, but its exact boundaries, count, or internal layout are
  not yet pinned down.
- **HYPOTHESIS** — a plausible but unconfirmed claim, usually from an
  external source (see [../references.md](../references.md)) that has not
  yet been checked against this specific ROM.
- **UNKNOWN** — not yet investigated.

No claim here was invented without a method to reproduce it. Where the
method is "decode 2bpp and look at it," anyone can re-run
`tools/graphics/gbtile.py` against their own copy of the same ROM (by SHA-1)
and see the same picture — the report below states exact offsets so that
is always reproducible.

## Method notes (so findings can be reproduced or falsified)

1. `tools/rom/scan_graphics.py` scans the whole ROM tile-aligned (16-byte
   stride) and scores each tile by Shannon entropy over its 4 decoded
   palette-index symbols, flagging tiles in a plausible "real art" entropy
   band. This is a **lead generator only** — see bank 5 below, which scores
   81.7% "plausible" by this heuristic but is visually noise/code when
   rendered. Every candidate must be visually confirmed before being marked
   VERIFIED.
2. `tools/graphics/gbtile.py` decodes raw bytes as Game Boy 2bpp tiles
   (hardware-format decode, not ROM-specific) and lays them into a grid PNG
   for inspection. Rendering the *same* bytes at different `--columns`
   widths can look different — sequential same-order-as-VRAM image data
   (rare; only relevant if a title screen or similar is stored pre-arranged)
   reads correctly only at the width matching its real tilemap, while a
   *tileset* (individual reusable tiles, referenced by a separate tilemap
   elsewhere) looks like plausible art at any reasonable column width since
   each tile is independently meaningful. An earlier pass in this
   investigation misread a small full-bank thumbnail of bank 12 as
   containing legible "MYSTIC QUEST" logo text; a full-scale re-render at
   several column widths did not reproduce that reading, so **that specific
   claim is retracted** — recorded here as a caution against trusting
   small/scaled-down preview renders for text-legibility claims.
3. Per-bank "percent of tiles scored plausible" (whole-ROM sweep):

   | bank | plausible % | visual check |
   | ---: | ---: | --- |
   | 0 | 12.5% | not yet visually swept (fixed bank; holds interrupt vectors $0000-$0067, entry point $0100-$0103, Nintendo logo $0104-$0133, and cartridge header $0134-$014F per the hardware spec — VERIFIED by definition, not by this project) |
   | 1 | 37.3% | not yet visually swept |
   | 2 | 20.8% | not yet visually swept |
   | 3 | 67.1% | visually swept (4 sub-regions): **noise/code**, not graphics — heuristic false positive |
   | 4 | 38.5% | not yet visually swept |
   | 5 | 81.7% | visually swept (full bank): **noise/code**, not graphics — heuristic false positive despite the highest score of any bank |
   | 6 | 53.1% | not yet visually swept |
   | 7 | 37.9% | not yet visually swept |
   | 8 | 68.6% | visually swept (full bank + zoom): **font glyphs + status-bar/UI icons + creature sprites** — VERIFIED |
   | 9 | 73.8% | visually swept (full bank): **creature/character sprite columns** — VERIFIED |
   | 10 | 82.0% | visually swept (full bank + zoom): **creature/character sprite columns**, high density — VERIFIED |
   | 11 | 77.3% | visually swept (full bank): **creature/character sprites + weapon/item icon row** — VERIFIED |
   | 12 | 77.8% | visually swept (full bank + zoom): **environment tileset** (stone/brick walls, fences, water/cave textures) + more icons — VERIFIED |
   | 13 | 30.0% | not yet visually swept |
   | 14 | 48.6% | not yet visually swept |
   | 15 | 18.1% | not yet visually swept |

   Takeaway: banks 8-12 are graphics-heavy; the entropy heuristic alone is
   not reliable evidence (bank 5 vs banks 8-12 both score "high" but only
   one is actually graphics) — **visual confirmation is required**, which
   is why every VERIFIED entry below states it was rendered and inspected.
4. No decompression step was needed to get recognizable art out of any of
   the regions below — unlike gen1recomp's Pokémon front/back sprites
   (which need `Rom.decompressPic`), what we found in banks 8-12 reads as
   plain, uncompressed planar 2bpp tile data straight off the ROM. This
   does not rule out compression existing elsewhere (e.g. for maps or a
   dedicated title-screen image) — only that these particular regions
   don't need it.

## Graphics

### Font / text glyphs — bank 8 — VERIFIED

File offset `0x22900`-`0x22C00` (bank 8, CPU `$6900`-`$6C00`), decoded as
16-tiles-per-row, contains a complete, orderly Latin character set:

- Row at tile index 32 relative to `0x22900` (file offset `0x22B00`, bank 8
  `$6B00`): `0123456789ABCDEF`
- Next row (`0x22C00`... — 16 tiles further): `GHIJKLMNOPQRSTUV`
- Next row: `WXYZabcdefghijkl`
- Next row: `mnopqrstuvwxyz',`
- Next row: `. . . - ! ? :` followed by non-text icon tiles (arrows/UI
  glyphs)

Immediately before this (file offset ~`0x22900`-`0x22B00`) are German
umlaut/extended-Latin glyphs — `ÄÖÜäöüß` — plus assorted small icon tiles,
and just above that (~`0x22300`-`0x22900`) a row reading `HPMSGLE/` next to
a horizontal gauge/bar graphic and a circular icon, sitting below several
rows of creature-head sprites.

**VERIFIED**: this is font/glyph tile data (16 glyphs precisely fill each
16-tile-wide row, in ascending ASCII-like order, immediately adjacent to a
German-specific extended character set — not plausible as anything but a
font). **HYPOTHESIS**: `HPMSGLE/` are UI-label tile fragments (e.g. "HP"
health abbreviation, "LV" level, "MSG"/message-box chrome) rather than part
of the running font — needs confirming once we know how the status/menu
screens reference these tiles. **UNKNOWN**: the byte-value-to-tile-index
encoding actually used by dialogue/text data in ROM (i.e. does text byte
`0x00` select this font's first glyph, or is there an indirection table?);
the presence of French/Spanish glyph sets elsewhere for a possible
in-game language switch; whether this is the *only* font (vs. a separate
bold/menu font).

### Creature / character sprites — banks 9, 10, 11 (and part of 8) — VERIFIED

Full-bank renders of banks 9, 10, and 11 (file offsets `0x24000-0x28000`,
`0x28000-0x2C000`, `0x2C000-0x30000`) show dense, repeating columns of
humanoid and monster silhouettes — robed figures, helmeted heads, creature
forms with clearly intentional (not noise-like) shading and outlines,
arranged in what look like vertical animation-frame or size-variant
sequences. Bank 8 also holds a smaller run of creature-head sprites above
its font data.

**VERIFIED**: these regions are 2bpp tile art depicting characters/
creatures, confirmed by direct visual inspection of the decoded tiles at
multiple zoom levels. **PARTIALLY VERIFIED**: which sprite belongs to which
in-game entity, sprite pixel dimensions (8x8 single tile vs. a multi-tile
metasprite), and exact tile-index boundaries between one creature's sprite
and the next are all still open — this entry only establishes *where the
sprite data lives*, not its internal structure. **UNKNOWN**: whether
banks 9/10/11 are organized by area/enemy-set (a common GB-RPG pattern —
one bank of monster graphics "in scope" per dungeon/region) or as one big
shared pool; corresponding OAM/metasprite assembly tables (which tiles
combine into one on-screen sprite, and in what arrangement) have not been
located.

### Environment tileset — bank 12 — VERIFIED

Full-bank render of bank 12 (file offset `0x30000-0x34000`) shows, from
roughly file offset `0x33000` (bank 12, CPU `$7000`) onward: stone-brick
wall patterns, a fenced/gate structure, cobblestone ground, and cave/water
textures — unambiguous overworld or dungeon tileset art, not sprite/
character graphics. The bank's first two tile rows were previously
misread as containing a legible "MYSTIC QUEST" logo from a small preview
thumbnail; a full-scale re-render did not confirm that (see method note
above) — that specific claim is **retracted**; the region is UNKNOWN
pending a proper tilemap-aware re-render (it may still be title-screen art
assembled via a tilemap this project hasn't reconstructed yet, or it may be
more tileset/UI-icon art like the rest of the bank).

**VERIFIED**: bank 12 (at least from ~`0x33000` onward) is environment
tileset art. **UNKNOWN**: exact tile boundaries, which cells form which
named "tileset" (town vs. dungeon vs. field, if MQ's engine separates
them the way many GB action-RPGs do), and the metatile/collision
assembly (which raw 8x8 tiles combine into a walkable/blocking 16x16 unit —
see gen1recomp's cell/block model in
[../gen1recomp-analysis.md](../gen1recomp-analysis.md) §4 for the *kind* of
structure to look for, not its values).

**Extended, VERIFIED (2026-08-08)**: the region `0x32000-0x33000` (tile
page 2 of bank 12, immediately before the previously-confirmed page 3)
is *also* environment/architecture art — full-bank render at this offset
shows columns, pillars, urns/vases, arches, and decorative pedestals
(interior/dungeon architecture, distinct in subject from page 3's
brick/cave/water textures but clearly the same tileset family: same line
weight, same DMG 4-shade rendering style, same tile grid). Found while
verifying the map-data pointer table below — see "Maps" — by using this
region as a tile-index lookup base and getting coherent art out, then
confirming with a full-bank render. `0x32000-0x34000` (tile indices
0-511 of a would-be 2-page lookup, or equivalently tiles 512-1023 of the
whole bank) should now be treated as the confirmed environment tileset
range, not just `0x33000-0x34000`.

### Item/weapon icons — bank 11 (bottom rows) — PARTIALLY VERIFIED

Bottom portion of bank 11's full render shows small, distinct iconographic
shapes (weapon/item silhouettes) separate from the creature-sprite columns
above them. Plausible as inventory/equipment icons given the master
brief's expected item/weapon systems, but not cross-checked against any
in-game screen yet, so this stays PARTIALLY VERIFIED rather than VERIFIED.

### Remaining banks — visually swept, no graphics found — VERIFIED (of absence)

Banks 0, 1, 2, 4, 6, 7, 13, 14, 15 were each rendered whole-bank (1024
tiles, 32 columns, via `tools/graphics/gbtile.py`) and visually inspected.
None show anything resembling the font/sprite/tileset structure found in
banks 8-12 — every one decodes as dense, unstructured noise consistent with
executable code and/or non-graphics data tables. Bank 6 and bank 7 show a
distinctive vertical-stripe texture at a glance, visually different from
the "salt and pepper" look of the other noise banks; zooming into bank 6 at
full scale shows this is still noise/code under close inspection (no
tile-sized repeating shapes), not art — recorded here so the same
zoomed-out visual pattern isn't mistaken for a lead a second time.

**VERIFIED**: graphics data in this ROM is concentrated in banks 8-12;
banks 0-2, 4, 6, 7, 13-15 contain no full-bank-scale tile art. **Caveat**:
this whole-bank low-zoom method can only catch graphics regions large
enough to visually register at 32-tiles-wide/1-pixel-per-source-pixel
scale (roughly the same size as the font/sprite regions already found) —
it cannot rule out a *small* embedded image (e.g. a title-screen logo a
few hundred bytes long) hiding inside one of these banks' code/data noise.
That would need a targeted, not full-bank, search if a specific reason to
look ever comes up (e.g. a pointer found elsewhere that resolves into one
of these banks).

**Bank 6 revisited (2026-08-08, twelfth pass)** — a concrete reason to
look came up: bank 6 was confirmed this session as a live target of the
dynamic bank-dispatch mechanism (see "Bank-calling convention" below),
so it was re-examined structurally rather than just visually. Its tile-
entropy signature (98.4% of tiles "high entropy," mean 1.77) sits
solidly in this ROM's code/data cluster (matching banks 0-7/13-15, all
93-99.8%), clearly distinct from the confirmed-graphics cluster (banks
8-12, 77-93%) — this quantitatively confirms, rather than overturns, the
original visual sweep's "no full-bank-scale art" finding. **New,
different finding**: bank 6's very first 16 words decode as a **real,
plausible function-index jump table** structurally identical to the
confirmed trampoline-target banks (entries 2-15 all resolve to valid,
increasing in-bank addresses; entries 0-1 read as invalid, consistent
with unused/reserved low indices, a pattern also seen in other banks'
tables) — so bank 6 does have real dispatch-table structure at its
start, not just code noise. But the function bodies those entries point
to (checked function `2`, file `0x18104`) do **not** disassemble as
plausible executable code — dense, regular repeating byte patterns
(`0d 0e 3f`, `1d 1e 3c`, `25 a5`, ...) more consistent with a compact,
non-pixel **data table** than instructions. **HYPOTHESIS, not verified**:
bank 6 may hold metatile-style data (a genuine possibility raised
directly by the FFA-Disassembly project's documented format — metatile
definitions are a compact 6-bytes-per-entry table, distinct from raw
pixel graphics, exactly the kind of content that would show non-art
tile-entropy *and* non-code disassembly at once) rather than being pure
code. **Tested directly, same pass — inconclusive, does not confirm metatile
data at this exact location.** Decoded the first 10 records as 6-byte
`[tile0,tile1,tile2,tile3,collision,interaction]` metatiles per the
documented format: only the first record's "collision" byte (`0x03`)
falls in the documented plausible set (`$00-$07`/`$08`/`$10`/`$20`/
`$30`/`$40`/`$80`/`$C0`/`$F0`); the following 9 do not (`0x3F`, `0x0E`,
`0x1D`, `0xA5` ×3, `0x0D`, `0xAF`, `0xFF`). Not a confirming pattern —
either this isn't metatile data, the real stride/alignment differs, or
this project simply hasn't found the right offset within bank 6 yet.
Recorded as a real, executed test with a negative-ish result, not
further pursued this pass.

**A real, independent cross-confirmation, same pass**: re-ran this
project's existing `tools/rom/scan_text.py charmap` lead-generator
(built several passes ago for the "is there a scrambled byte->glyph
table hiding somewhere" question, not re-run since) with fresh eyes —
**bank 6 produced 4 of its 10 candidate lookup-table-shaped hits**
(60-130 byte, low-value, non-degenerate runs), more than any other
single bank. This is a genuinely independent method (byte-value/
structure statistics, nothing to do with the trampoline/jump-table
discovery above) converging on the same bank as "holds real, structured,
non-code, non-graphics data." Dumped the actual bytes of all 4
candidates: each shows a plausible real-table structure (clustered,
narrow-range values with a repeating small-increment-then-larger-value
pattern), consistent with *some* kind of genuine lookup/index table —
but not yet distinguished from the several plausible candidates (the
text dual-character table, metatile data, a script/event offset table,
or something not yet imagined). **Bank 6 is now this project's
best-evidenced "there is real, un-identified structured data here"
lead**, worth a dedicated follow-up pass rather than further
speculation in this one.

## Maps

**Update (2026-08-09): the room-decompression scheme is now VERIFIED —
see "Room decompression format — CRACKED" near the end of this section**
for the full writeup. Read the history below first; it's preserved
because it's how the crack was actually found (the "real per-map header"
lead came directly out of re-reading the FFA-Disassembly findings
recorded here), not because it's still the current state of belief.

### Bank 5 map/room pointer table — file offset `0x14004` — PARTIALLY VERIFIED

Method: `tools/rom/scan_pointers.py` (new tool, this pass) scans each bank
for runs of word-aligned 2-byte little-endian values that fall in the GB
CPU's switchable-bank address window (`$4000-$7FFF`), a generic pointer-
table lead heuristic (not Mystic Quest-specific). It found one enormous,
extremely clean candidate head and shoulders above every other bank's
noise: **512 consecutive word-aligned values at file offset `0x14004`
(bank 5, CPU `$4004`), strictly monotonically increasing (511/511 positive
deltas), spanning `$4404` to `$7CA1`, 100% unique** — i.e. every single
2-byte slot in a 1024-byte run resolves to a distinct, validly-ordered
in-bank address. This is a far stronger signal than any of the ~250 other
candidate runs the same scan found elsewhere (those cluster around
duplicate/repeated targets typical of incidental `CALL`/`JP` operand bytes
in real code — see the tool's `--min-unique` filter).

Dereferencing the 512 values (each is a CPU address in bank 5; converted
to a file offset via `0x14000 + (addr - 0x4000)`, i.e. relative to bank
5's own start) shows a strict, 100%-consistent alternating structure —
confirmed across all 256 record pairs, not just a hand-picked few:

- **Even-indexed entries (256 of them) point to a short "header" — VERIFIED structure, UNKNOWN meaning.**
  Every one is terminated by byte `0xFF` (256/256, no exceptions). 206 of
  256 are exactly 3 bytes (`byte0, 0x00, 0xFF`); the rest are 6, 9, or
  (once) 15 bytes, always ending `...0xFF`, with 1-4 extra bytes inserted
  before the terminator. `byte0` varies widely (seen: 0x3D-0xEF range) and
  has no simple arithmetic relationship to the paired data blob's length
  (checked exact-match, half-match, and divisibility against all 255 pairs
  -- zero matches on all three). **HYPOTHESIS**: this is a per-room
  flags/type/link byte plus, in ~20% of records, extra fields (possibly a
  warp/exit target or linked-room reference, given the shape
  `[flag, 0x00or0x04, x?, y?, id?, 0xFF]`). **UNKNOWN**: actual semantics.
  **Strengthened this pass (2026-08-08, fifth pass), still HYPOTHESIS —
  static only, not dynamically confirmed**: re-read all 50 of the
  non-3-byte headers directly (not just eyeballed). Every 6-byte one has
  the shape `[w0, w1, x, y, b, 0xFF]` where `b` (the 5th byte) is
  **always exactly `2`, `3`, or `4`** across all 50 records (18/18/9
  split) — an unusually tight range that reads much more like a small
  ROM-bank selector (this ROM has 16 banks total, but a warp system would
  plausibly only ever target a handful of "linked" banks) than a
  coordinate or ID. Stronger evidence still: the **two 9-byte
  double-triplet records** (`#92`, `#129`) each contain **two adjacent
  triplets differing by exactly 1** in their first byte (`[0x34,0x8a,2]`
  then `[0x35,0x8a,2]`; `[0x34,0x80,2]` then `[0x35,0x80,2]`) — exactly
  the shape you'd expect from "two adjacent target map-table record
  indices, same secondary field, same bank" (e.g. a 2-tile-wide doorway
  needing two linked target records, or two exits sharing a destination
  area). Reads as `[targetRecordIndex, unknown, bank]` triplets, repeated
  once per exit. **Not dynamically confirmed** — this session could not
  trigger any real room transition to test the hypothesis against a live
  warp (see the Milestone 5 note above); the next concrete step is
  re-attempting live triggering (or tracing `$048C`'s caller further) now
  armed with a specific, falsifiable prediction: walking through a real
  exit should populate the `$C8E8`-family record via the parameterized
  `$1E6F` populator with a `byte0`/bank drawn from one of these `{2,3,4}`
  triplets, not the hardcoded `Block C` both live captures hit so far.
- **Odd-indexed entries (255 of them, since the table's last entry has no
  successor to bound it) point to a variable-length data blob — VERIFIED
  as real tile-index data, role UNKNOWN.** Length ranges 32-74 bytes
  (bounded by the gap to the *next* record's header pointer, since nothing
  in the blob itself is self-terminating), always an even number of
  bytes, but **not** reliably divisible by any single candidate rectangle
  width from 3-20 (best fit, width 4, only covers half of them) — so this
  is almost certainly not literally one fixed-width row-major tile
  rectangle per record; something else (a separate, not-yet-found width
  source, a non-rectangular shape, or a different encoding entirely)
  determines how each blob's bytes map to 2D positions.

**VERIFIED, with a control**: treating each data-blob byte as a tile
index into the confirmed bank-12 environment tileset (`0x32000 +
byte*16`, see "Environment tileset" above) and decoding+rendering it
produces clearly non-random, thematically-coherent architecture/terrain
art (brick walls, pillars, cave/water textures matching bank 12's known
visual vocabulary) — reproduced for the first 40 records regardless of
which row-width was guessed for the 2D reshape (even deliberately "wrong"
narrow 2-wide reshapes still show clean vertical bands of coherent
texture, never noise). A **negative control** — decoding the exact same
blob bytes against bank 9's creature-sprite region and against bank 8's
code region instead — produces incoherent, fragmented junk (chopped-up
humanoid pieces, noise) in both cases, which is what "the bytes reference
a specific, correct source range" should look like versus "any base
offset renders equally plausible art" (which would have undermined the
finding). This rules out coincidence as the explanation for the
bank-12-tileset match.

**What this means, stated precisely**: it is VERIFIED that (a) a genuine,
intentional 256-record pointer table exists at this address, and (b) its
data blobs are real references into the confirmed environment tileset,
not incidental bytes. It is HYPOTHESIS, not verified, that these records
are literally "maps" in the master brief's sense (one full walkable room
per record) — the blob sizes (32-74 raw tile-equivalent bytes) are far
smaller than a full 20x18-tile GB screen (360 tiles), so each record is
more likely either (i) a *decorative object/prop* built from a handful of
tiles (a building facade, a fountain, a cluster of pillars) placed onto a
separately-stored base layer, or (ii) a compressed/metatile-referencing
encoding of a small room whose expansion to full screen size hasn't been
found yet, or (iii) something not yet imagined. **UNKNOWN**: which of
these is correct, the real 2D width/height per record, whether a
separate base/background layer exists elsewhere in ROM, and how (or
whether) the even-indexed header records relate to placement (world
position, warp targets, or something else).

Recorded machine-readably in
[`src/import/rom_profiles.lua`](../../src/import/rom_profiles.lua)'s
`mapTable` field so nothing downstream hardcodes `0x14004` directly. A
debug `MapBlockViewer` state renders these records live in the LÖVE app
(see `src/app/states/MapBlockViewer.lua`) with an adjustable reshape width
for exactly this "we know the bytes are real, we don't yet know the true
shape" reason.

**Immediate next steps for this thread** (see
[../progress.md](../progress.md)): (1) find whatever determines each
record's true width/height (scan bank 5 code around the table for a
`div`/`mod`-by-a-constant pattern, or look for a second, smaller table
indexed the same way); (2) figure out the even-record header semantics,
especially the 6/9/15-byte extended variants; (3) determine whether this
table is "the" map data or a sub-component (props/decorations) of a
larger, still-unfound room format.

**Dynamic finding (2026-08-08), narrows the search**: played the ROM to
a real first-game room via mGBA (see [tooling.md](tooling.md)) and
dumped the live VRAM background tilemap (`tools/rom/play_driver.py`).
The room is **exactly one 20x16-tile screen** (GB's full visible
playfield minus the bottom 2 HUD rows), does **not** scroll, and its
tile layout is strongly bilaterally symmetric (left half mirrors right
half almost exactly — see the raw tilemap dump in this session's tool
output) with large repeated runs of only ~20 distinct tile values. A
raw, uncompressed 20x16 room would need 320 bytes — far more than any
observed bank-5 blob (32-74 bytes) — but a symmetric/repeat-structured
encoding (e.g. "describe one quadrant + mirror flags," or metatile
run-length) easily could compress into that range. **Revises the
milestone-3 "decorative prop" hypothesis above**: PARTIALLY VERIFIED that
single rooms in this game occupy exactly one non-scrolling screen (a
useful fact for milestone 4's camera design regardless of the encoding
question), and the small blob sizes are now better explained by *within-
room compression* than by *the blob being a sub-room prop*. Exact
compression scheme still UNKNOWN — has not yet been matched byte-for-byte
against a specific bank-5 record.

**Dynamic finding (2026-08-08, third pass), the room-draw call chain —
PARTIALLY TRACED**: built real native watchpoints this round (see
[tooling.md](tooling.md) "Native watchpoints") and used them to catch the
exact instruction that writes the first game room's tiles into VRAM, then
walked outward from there via static disassembly of the surrounding ROM
bytes (all in fixed bank 0, so directly readable from the ROM file at the
same address as the live PC). VERIFIED, with live register traces at the
actual hit (not just static reading) backing every claim below:

- **The low-level VRAM writer, ROM `$1D74`**: a generic, HBlank-
  synchronized "write two tile bytes" primitive — polls `$FF41` (STAT)
  for the *start* of HBlank/VBlank before writing (via `$FF40`/LCDC's
  enable bit to skip the wait if the LCD is off), then executes
  `LD A,D` / `LD (HL+),A` / `LD (HL),E` / `RET`: writes register `D` to
  `(HL)`, increments `HL`, writes `E` to the new `(HL)`. **Not
  room-specific** — confirmed reused later (frame 2121 in the traced
  session, different caller at `$0484`) to draw a dialogue-box border
  tile, so this is shared VRAM-write infrastructure, not part of the
  decompressor itself.
- **The room-draw loop, ROM `~$1E2C-$1E42`**: calls `$1D74` in a loop
  (confirmed 9 times across the 3 frames the room's tiles actually
  changed, frames 1946-1948 in the traced session — matches the
  `run_frame()`-bisected "map0 tilemap hash changes across exactly 3
  consecutive frames, then stabilizes" finding from the previous pass).
  Each iteration pops one byte from a small WRAM queue (see below), tests
  it against sentinel `0x10`, and derives the pair of tile values written
  as `(D, E)` where, over 9 live-captured writes, `E` was always either
  `D` (repeat) or `D+1` (increment) — consistent with a 2-tile-wide
  "meta-cell" unit rather than one byte per screen tile, which would
  materially help explain how a 32-74 byte blob covers up to 320 tiles.
  **UNKNOWN**: the exact byte-to-`(D,E)` derivation formula (the popped
  byte was read into `A` then immediately discarded via `LD A,D` before
  use in the observed case, meaning `D`'s own update path wasn't caught
  by this pass — the popped byte's role appeared limited to the `0x10`
  sentinel test in what was traced).
- **A small WRAM byte-queue utility, ROM `$29FB` (push) / `$2A0A`
  (pop)**: `$FF8A` (HRAM) is a depth counter; `$C000-$C0FF` is the
  backing buffer. Pop decrements the counter and returns the newly
  exposed byte; push increments the counter, stores the byte, *and*
  also writes it to the MBC ROM-bank-select register `$2100` (bank
  aliasing whose purpose isn't pinned down — may be incidental reuse of
  a generic byte-queue helper for unrelated bank-management call sites
  elsewhere, not necessarily meaningful in the room-draw context). The
  room-draw loop only **pops** from this queue — so the real
  decompression work (whatever turns a ROM-resident compressed blob into
  the sequence of bytes sitting in this queue) happens somewhere that
  **pushes** to it, not yet located. **This is now the concrete next
  target**, narrower than "find room decompression" broadly: watch
  writes to `$C000-$C0FF` (or reads from wherever the real ROM blob
  pointer lives) starting a bit earlier in the room-transition sequence.
- **A 6-byte WRAM staging record at fixed address `$C8E8-$C8ED`**,
  populated once per room-load by a distinct ROM routine (**`$1EA6-
  $1EB2`**, confirmed live via a real transition mid-session, frame 2543)
  and then read back by the room-draw loop's init code (`~$1DF4-$1E01`)
  as: byte0 (nicknamed `C`), byte1 (`B`), byte2 (`E`), byte3 (`D`), then a
  little-endian 16-bit value loaded via the `LD A,(HL+)` / `LD H,(HL)` /
  `LD L,A` self-pointer idiom. **Correcting an initial misread this
  round**: that 16-bit value is **not** a ROM source pointer — in both
  live captures it decoded to exactly `$9800`, the live map0 tilemap base
  address, i.e. it's the **destination** VRAM cursor the write loop
  starts from, not a source. A nearby `CP $10` / `JR NC` branch on byte0
  (`C`) was initially misread as "byte0 selects an MBC ROM bank via
  `$2100`" from static reading alone; the live captures (`C = 0x20` for
  the real first room, which is `>= 0x10`) showed the **branch not
  taken** for real rooms — the bank-switch-via-`$2100` code at that
  address only runs for a `C < 0x10` case not yet observed live. Real
  rooms were drawn with MBC bank **1** already active (confirmed via
  `GBMemory.currentBank` at the exact hit), so the actual bank-select
  point is somewhere else not yet located. **UNKNOWN**: what populates
  `$C8E8-$C8ED` (i.e. is `$1EA6-$1EB2`'s own data source the bank-5 map
  table at `$14004`, connecting this whole chain back to the
  already-known static table — plausible but not yet confirmed by
  reading `$1EA6`'s own disassembly), and the real meaning of byte0/
  byte1 (`C`/`B`) now that "ROM bank number" is ruled out for the normal
  case.

Net effect of this pass: the room-load call chain from "VRAM write" back
to "a 6-byte WRAM record" is now traced and address-verified end to end;
what's still open is the hop from that WRAM record back to the bank-5
static table, and the byte-queue's actual producer (the real
decompressor). Both are concrete, narrow, watchpoint-reachable next
targets rather than an open-ended search. Tooling for this (`tools/rom/
watcher.py`, `tools/rom/reach_room.py`) is now committed and reusable —
see [tooling.md](tooling.md).

**Dynamic finding (2026-08-08, fourth pass), the `$C8E8` chain traced one
level further, with a correction and a dead end**: wrote a small,
validated SM83 disassembler (manual hex-counting had already produced one
real mistake the previous pass — see the correction below) and used it to
read the ROM around the previous pass's addresses precisely, cross-checked
against fresh live register captures.

- **Correction: `$C8E8` is not one fixed record, it's the base of an
  array.** `$1DCA` (called by every populator block below) computes
  `HL = $C8E8 + 6 * [$CEE8]` — a slot pointer indexed by a one-byte
  counter at `$CEE8` that each populator increments (`INC (HL)`,
  `HL=$CEE8`) right before returning. The two live populates seen so far
  both happened to land on slot 0 (`[$CEE8] == 0`), which is why they read
  back as "the same fixed address" last pass.
- **Three sibling populator routines exist, not one**: `$1E6F` ("Block
  A" — byte0/byte1 taken from the *caller's* `A`/`B` registers, i.e.
  genuinely parameterized), `$1E87` ("Block B" — byte0/byte1 hardcoded
  `0x10`/`0x01`, **zero static `CALL` references found anywhere in the
  ROM** — either dead code or reached only indirectly, not chased
  further), and `$1E9F` ("Block C" — byte0/byte1 hardcoded `0x20`/`0x02`,
  exactly **one** static call site, `$0491`). **Both of this session's
  live room-load captures (frame 1946 and frame 2543) went through Block
  C** — meaning both were (most likely) the *same* room being redrawn
  (matches the frame-2543 trigger lining up with the "Kämpfe!" dialogue
  box closing in the screenshot sequence), not two different rooms. Block
  A — the one plausibly parameterized *from* the bank-5 table — has not
  yet been observed to fire live.
- **Bytes 5-6 (the VRAM destination) are computed by a real "row,col ->
  tilemap address" helper, `$045D`**: `HL = $9800 + (($C343 + row) & 0x1F)
  * 32 + (($C342 + col) & 0x1F)`, i.e. it honors a per-room scroll/origin
  pair at `$C342`/`$C343` (both were `0` for the observed field room, so
  the destination reduced to the tilemap's raw top-left). This is
  legitimate, reusable "place a byte at world position (row,col)"
  infrastructure, not room-decompression-specific.
- **Chased Block A's two call sites (`$1AB6`, `$1AE5`) hoping to find the
  bank-5 connection — inconclusive.** Both sit inside a shared routine
  (`$1A8C`) that walks a byte stream via `LD A,(HL+)` / `CP $FF` — i.e.
  it consumes an **`0xFF`-terminated byte table, exactly the bank-5
  even-record header shape** — and feeds each byte through a
  nibble-swap-and-mask hash into a `$8000`-based lookup (`LD HL,$8000;
  ADD HL,BC`), which reads as a generic tile/OAM-slot allocator, not
  obviously room-specific. Critically, the byte0 value actually handed to
  Block A at both call sites is a **hardcoded `0x08`** immediate, not
  read from that table — so this pass could not confirm the table walk
  is *the* connection to bank-5's records, only that *some* `0xFF`-
  terminated-table-consuming code exists nearby. **Still UNKNOWN.**
- **Ruled out `$C000-$C0FF` (the byte-queue buffer from the previous
  pass) as a useful watch target.** Watching the full range across the
  boot-to-room-load window produced **71,444 hits** from dozens of
  distinct PCs, at a roughly constant ~50-hits/frame rate sustained for
  *every* frame observed (not concentrated around the room-load window at
  all) — this is a hot, shared per-frame scratch buffer (reads as OAM/
  sprite shadow-copy bookkeeping) reused by many unrelated systems, not a
  quiet buffer a single decompressor fills once. Isolating a room-
  specific producer here would need a much narrower filter (e.g. only
  writes whose value matches an already-known compressed source byte) —
  recorded here so the next pass doesn't re-spend time on the same broad
  watch.

**Revised next step**: both live room-loads traced so far went through
the *hardcoded* Block C, not the parameterized Block A — so confirming
the bank-5 connection needs either (a) triggering a **genuine room-to-room
transition** (walking through an actual exit — not yet possible
dynamically, since `Player`/`Field` don't have real collision or multiple
rooms wired up yet) so a different, table-driven populate call fires
live, or (b) tracing `$048C`'s own caller one level further up by hand.
(a) is more likely to be conclusive and may fall out naturally once
milestone 4/5 engine work adds real room transitions to test against.

**Dynamic finding (2026-08-08, fifth pass), no exit found in the starting
room; a position-triggered dialogue confirmed instead**: drove the player
in all 4 directions for 200 frames each (well over the ~160 frames a full
screen crossing needs at the VERIFIED 1px/frame walk speed) — the player
never left the visible screen in any direction; this starting room
appears to be **fully walled with no walkable exit found**, consistent
with a small tutorial/arena room by design rather than a missed exit tile.
Walking directly up to the barred-gate structure at the top of the room
triggered an **empty dialogue box** (a real message-box UI element drawn,
with no legible text captured in this pass) — real, position-triggered
event logic exists and fires from ordinary field movement, not just from
scripted cutscenes. This is genuine milestone-7 (event system) evidence,
not just a milestone-5 dead end: worth tracing with `tools/rom/watcher.py`
(watch the dialogue-box-drawing VRAM writes, same technique as the
original room trace, to find the trigger check and message-pointer
source) as a concrete next step for **both** milestones. Separately, real
contact damage from the room's bat enemy (see "Player stats struct and
combat" below) was reproducible in an earlier attempt at the same
position but not this one — suggests the encounter/dialogue outcome may
be state-dependent (RNG, an internal timer, or an already-triggered flag)
rather than deterministic on position alone; not yet disambiguated.

**Also observed, worth recording**: the game's HUD reads
`LP <n> MP <n> G <n>` (Lebenspunkte/Magiepunkte/Gold — HP/MP/Gold),
confirming German is used in status UI too, not just dialogue (see
[text.md](text.md)). Starting a new game triggers an immediate save-RAM
write (`GB Memory: Savedata synced`, an mGBA log line, not a ROM fact by
itself, but confirms save RAM is live and reachable this early for
future save-format work).

**Breakthrough (2026-08-08, sixth pass): the starting-room "bat" blocks a
real chokepoint, defeating/passing it unlocks real story progression —
and the room-load model above needed a correction.** Acting on a direct
tip (the user had outside knowledge that "the first room switch is only
possible once the first boss is killed" and suggested memory-hacking
past it), re-investigated with much more care than the fifth pass's blind
4-direction walk:

- **The room-draw loop's earlier report needs a correction: `$CEE8` is
  NOT a stable slot index into a `$C8E8` array.** Watching it precisely
  (every single write, not spot-checks) shows it's a **fast loop counter**
  that free-runs from `0` to `0xA0` (160) over ~3 frames every time the
  populate-and-draw sequence fires, then gets reset to `0` by a *different*
  instruction (`$1E33`) once the draw loop finishes. The fifth pass's "it's
  an array, indexed by a stable per-room slot" theory was wrong — both
  observations landing on "slot 0" was not a coincidence of timing, it's
  because there's no stable slot at all, just a counter that always ends
  back at 0. Filed as a correction, not silently fixed.
- **The `$1E9F`/"Block C" populate-and-draw sequence (hardcoded
  `0x20`,`0x02`, dest `$9800`) fires repeatedly during ordinary play, not
  once per "room load"**: caught live at frame 967 (during the intro,
  before the player is even placed in the room), frame 3644, and frame
  4629 (see below) — same hardcoded header every time, but **different
  actual tile content each time** (confirmed via the same VRAM-write
  watch used for the original room trace). This means the header fields
  (`0x20`/`0x02`/`$9800`) describe a generic "redraw this 20x16 region"
  operation, not "which room" — the real content must be selected by
  something else entirely, upstream of this shared draw utility, not yet
  located. This reframes the whole `$1E6F`/`$1E87`/`$1E9F` "populator"
  investigation from the previous two passes: they're redraw-region
  parameterizers, not room loaders per se.
- **Real, live combat + real collision confirmed, with a genuine
  position system found along the way.** Walking `UP` into the
  creature blocking the gate makes the player's Y position (traced to
  WRAM `$C244`, synced to the OAM shadow copy at `$C020` every frame via
  a real, generic "position += velocity" entity-update routine at
  `~$0961-$09BE`) **stop advancing entirely** while contact damage
  continues — a real, enforced collision block, not a rendering artifact
  (confirmed by directly poking the OAM shadow byte and watching the
  game's own logic silently correct it back every single frame; the true
  source, `$C244`, does *not* get auto-corrected the same way, so pinning
  down the real vs. derived copy mattered here).

  **CORRECTED (2026-08-09)**: this entry originally called `$C244`/
  `$C245` an "8.8-fixed-point pixel/subpixel pair" of the *same* axis
  (Y). Tracing the real first-battle walk-in (a second, independent
  watchpoint session — see `battleIntro` in rom_profiles.lua) found
  `$C245` changing on its own, independently of `$C244`, while the
  player visibly moved *horizontally* (X), not vertically — the actual
  entity-update routine's real store instructions are at `$09A1`
  (writes `$C244`) and `$09A6` (writes `$C245`), confirmed live under a
  watchpoint. **`$C244` = Y, `$C245` = X** (two different axes, plain
  integer pixel values), not one axis's integer/fractional pair. The
  routine itself, its trigger conditions, and the collision-block
  finding above are unaffected by this correction — only the field
  *labeling* was wrong.
  mattered here).
- **Pressing `A` (not `B`) while adjacent, repeated ~30-60 times,
  eventually clears the creature and unlocks real story text** — this is
  the concrete mechanic the user's tip predicted. Confirmed getting real,
  legible decoded German dialogue for the first time outside the
  title/intro sequence: `"AAAA und viele andere wurden gezwun[gen]..."`
  (the hero's own entered name, confirming this is genuinely
  player-name-substituted story text) and later `"Die Gemma Ritter müssen
  das wissen."`, alongside a visually distinct new scene: a walled square
  chamber with a diamond-tile floor and a central altar/idol graphic,
  clearly different tile art from the starting courtyard. **This is a
  real scene transition** — but see the point above: it does **not**
  touch `$C8E8`/`$CEE8` differently from the courtyard's own redraws, so
  it's produced by the same generic redraw utility with different
  upstream-selected content, not by a distinct "load room N" call we can
  point to. A previous pass's "no exit found, room is fully enclosed"
  conclusion was directionally right (there's no ordinary walking exit)
  but incomplete — the real progression gate is the creature encounter,
  not a missed tile.
- **Resolved: the new chamber IS a real, player-controllable room, not a
  cutscene insert** — the "no player sprite visible" observation above
  was premature; the dialogue chain (real, named-NPC content: "Willy"
  warns `"Mana ist in Gefahr"` / "Mana is in danger", and confirms the
  place-name read earlier, `"Gemma"`) runs much longer than first
  checked. Once it genuinely finishes (verified by two full-screen
  screenshots ~1200 frames apart showing byte-identical state), all 4
  directions produce real OAM movement (player Y/X traced across a wide
  range, screenshots confirm the sprite visibly separates from the
  central altar icon and walks around). **This chamber has no exit
  either**, though — walked into every wall over 150 frames each
  direction, same "fully enclosed" shape as the starting courtyard, and
  `$CEE8` (the populate-sequence marker) never fired during any of it.
  Reads as a self-contained vision/flashback room the hero is placed in
  (not connected to the persistent overworld the way an ordinary dungeon
  room would be) rather than evidence against the bank-5 connection
  existing somewhere else. The original bank-5 map-table connection
  question is still open — this encounter chain never invoked the
  parameterized `$1E6F` populator, only the hardcoded `$1E9F` path, in
  either room. The `{2,3,4}` extended-header-triplet hypothesis from the
  fifth pass remains untested.
- **Static search for the map table's real consumer (2026-08-08, eighth
  pass) — thorough, but came up empty; two clean negative results.**
  (1) Searched the entire ROM for any `LD reg16,nn`/`CALL nn`/`JP nn`
  instruction whose literal operand is the table's own base address
  (`$4004`) — found only 5 byte-level matches, all demonstrably false
  positives inside known DATA regions (4 of them recur at the exact same
  sub-offset every 4 banks inside bank 12's tileset data, a dead
  giveaway of coincidental graphics-byte alignment, not code; the 5th,
  in bank 1, sits inside a dense, regular non-code byte pattern with no
  plausible surrounding instruction flow). **No genuine literal reference
  to the table's base address exists anywhere in the ROM.** (2) Searched
  for the bank-switch-to-bank-5 idiom (`LD A,$05` followed within a few
  bytes by a write to the MBC bank-select register `$2100`) — zero
  matches anywhere. (3) Checked whether bank 5 itself contains any real
  executable code outside the already-mapped table/blob region (its
  first 4 bytes and its ~800-byte tail past the last blob) — both areas
  disassemble as further non-code data (regular STOP-opcode / graphics-
  like byte patterns), not code, ruling out an in-bank dispatcher too.
  **Conclusion**: whatever reads this table does not reference its base
  address as a literal constant and does not select bank 5 via a
  hardcoded immediate — if it's read at all by code reachable in normal
  play, the bank number and/or table address must be computed or read
  from a further, not-yet-found intermediate table, not hardcoded
  in either of the two most common idioms. This first rules out the two
  most likely, cheapest explanations rather than finding the real one —
  a genuine negative result, not a dead end for the investigation as a
  whole (see roadmap.md for the next concrete angle).
- **`SELECT` during gameplay tested — inconclusive, likely not a save
  trigger.** Following up a German forum's `Select → Batt → Savegame`
  mention (see progress.md "seventh pass"): pressing `SELECT` during
  normal field control produced a blank dialogue box indistinguishable
  from the courtyard's existing position-triggered empty box (see
  earlier in this section) — no new text, no `$A000` SRAM write
  observed, and the same result whether triggered near the gate or after
  moving well away from it first. Most likely explanation: the forum
  reference describes a physical flashcart/repro-cartridge's own
  hardware save-UI (common on reproduction GB carts, entirely outside
  ROM code), not an in-game software menu — not investigated further,
  flagged so this specific lead isn't re-tried the same way.
- **Two new confirmed text bytes, found decoding the creature-encounter
  dialogue directly from live VRAM tile indices** (not a screenshot
  transcription — see [text.md](text.md) for the full sentence, "AAAA ist
  ein tapferer Kaempfer."): `0x9C` = ae-umlaut (joins `0x9D` = oe-umlaut
  in `UMLAUT_PARTIAL`), and `0xF0` = `.` (period) — outside the
  contiguous `MAIN_BASE` run, needed its own case in `TextDecoder`, same
  treatment as the space byte. Both implemented and tested in
  `src/import/TextDecoder.lua`. Attempting to locate this sentence's real
  ROM offset by encoding it and searching the ROM file directly **failed
  even for short, unambiguous substrings** ("tapferer", "ist ein") that
  the (verified-correct) encoder round-trips perfectly — while shorter,
  more generic words ("ein", "ist" alone) *do* exist elsewhere in the ROM
  (unrelated occurrences). Best explanation: freeform dialogue prose (as
  opposed to the short, fixed-width name-table entries already verified)
  may use some form of text compression/tokenization not yet
  characterized — flagged as a new, real possibility rather than assumed.
- **Community GameShark/Game Genie codes for the US cartridge, used as a
  third independent cross-check** (at the user's suggestion): every
  GameShark code checked decoded (GB GameShark's `01VVAAAA`, address
  byte-swapped) to exactly the WRAM addresses this project and Data
  Crystal already agreed on — see [references.md](../references.md) for
  the full list and `tools/rom/gamegenie.py` (ported from mgba's own
  `GBCheatAddGameGenieLine`, `src/gb/cheats.c`) for the decoder. The
  Game Genie "Walk Through Walls" code decodes to a ROM patch at `$067F`
  (`OR E` -> `OR L`, disabling a movement-delta-is-zero check) whose
  checked byte matches this EU ROM exactly — applied live
  (`core.memory.u8.raw_write`, bypasses the normal MBC-redirected bus
  write) and confirmed it disables the collision block with **no combat
  damage taken while clipping through**, further corroborating this
  project's own independently-traced `entity+4`/`+5` movement-delta
  fields. **Its practical use as a noclip explorer was limited**, though:
  holding a direction with the patch active overshoots almost
  immediately into a wrapped, clearly-out-of-bounds `Y` value (`207`) and
  the game enters a stuck state (an empty dialogue box that never
  advances, not new room content) — reads as further evidence there's no
  real content past the courtyard's boundaries in that direction, rather
  than content the patch failed to reveal. A second Game Genie code
  ("reduce damage taken") decoded to an address inside this project's own
  traced damage-application routine but with a checked byte that does
  **not** match this EU ROM — real confirmation that ROM code
  addresses/bytes (unlike the WRAM data layout) can and do differ between
  the US and EU builds; each code needs individual verification, not
  blanket trust.

### Room decompression format — CRACKED (2026-08-09), at explicit user direction to resolve this definitively

Direct response to explicit user instruction: *"jetzt muss unbedingt die
map daten engültig entschlüsselt werden"* ("the map data must now
definitely be decoded once and for all"). The tenth pass (see "External
source" below) had already found and documented the US cartridge's real
RLE scheme but could not confirm it applied to this EU ROM — a blind
search over `rleLength` 2-40 only hit a clean 320/360-tile total for a
small, inconsistent minority of records, and the pass concluded the real
next step was "finding this EU ROM's own equivalent of the ... per-map
header ... rather than continuing to guess the length." That header was
never actually looked for. This pass looked for it directly, first.

**The header. The US format's own documented shape is `[encodingMode
(0=RLE,1=Templated), rleLength, heightInRooms, widthInRooms]`, stored as
the first 4 bytes of a map's `mapRoomPointers` region, immediately before
its list of pointer pairs.** This project's own already-known table
starts at file offset `0x14004` — i.e. the 4 bytes immediately
*before* it (`0x14000-0x14003`, bank 5's own CPU `$4000-$4003`) had never
been individually read as a header candidate in nine prior passes. They
are:

```
0x14000: 00 03 10 10
```

Read against the documented shape: `encodingMode=0` (RLE), `rleLength=3`,
`heightInRooms=16`, `widthInRooms=16`. **`16 * 16 = 256`** — exactly the
record count this project already independently verified via a completely
different method (`tools/rom/scan_pointers.py`'s pointer-density scan,
sixth pass). Two unrelated methods agreeing on 256 is a strong prior that
this reading is correct before even testing the RLE rule itself.

**The RLE test, decisive.** Applying the documented rule (a data-blob byte
with its high bit set means "repeat `byte & 0x7F`, `rleLength` times";
any other byte is one literal tile index) with `rleLength=3` to all 255
data blobs:

- **255/255 records decode to an exact multiple of 20 tiles.**
- **255/255 records decode to *exactly* 80 tiles (20x4).**

Tested every other plausible `rleLength` (1 through 11) the same way for
comparison: **every single one decodes 0/255 records to a clean 80-tile
result.** `rleLength=3` is not a lucky value in a forgiving search space —
it is the unique value (of everything tested) that makes the whole table
click into a perfectly uniform shape, and it's the value the ROM's own
header byte actually contains, not a guess. This rules out coincidence
about as thoroughly as a static, non-emulator test can.

Method reproduced in
`/private/tmp/.../scratchpad/rle_test.py` (ad hoc analysis script, not
committed — the real, permanent, tested implementation is
`src/import/MapTable.lua`'s `readMapHeader`/`rleDecode`/`decodeRoomTiles`,
exercised by `tests/import/map_table_test.lua`, including a ROM-dependent
test asserting all 255 records decode to exactly 80 tiles against the
real dev ROM).

**Visual cross-check.** Rendered several RLE-decoded records against the
confirmed environment tileset (bank 12) and against a direct dump of the
tileset itself for comparison. Both are clean, obviously-real Game Boy
art — recognizable hedge/foliage borders, brick/stone floor trim, torch-
like props, fence and pillar shapes — a dramatic, qualitative difference
from the "shuffled real tiles into visual noise" result the *previous*
(wrong) assumption produced (treating raw undeciphered blob bytes as
literal tile indices, without RLE decoding first — see
`src/rendering/RoomBackground.lua`'s revision history for the full
before/after). This is what prompted the fix in the first place: direct
user feedback ("das ist grafics garbage... nicht real tiles") after
actually running the app, not a test failure.

**What is now VERIFIED**: the RLE compression algorithm itself, and the
real header-derived `rleLength=3` constant that makes it apply cleanly
to every single record in this EU ROM's table. This is implemented,
tested, and in production use (`MapTable.lua`, `RoomBackground.lua`).

**What is still NOT verified — stated precisely, so this isn't
overclaimed**: how multiple 20x4 records compose into a full on-screen
room. An obvious hypothesis — 4 consecutive records (e.g. records 0-3)
stack vertically into one 20x16 screen, matching the already-VERIFIED
"real rooms are exactly one non-scrolling 20x16 screen" dynamic finding —
was tested by literally stacking them and rendering the result. **It did
not produce a unified room**: each of the 4 stacked strips still shows
its own independent top border and bottom trim, reading as 4 separate
small scenes stacked on top of each other, not one coherent box with
walls only at the true outer top/bottom. So either (a) real rooms combine
non-consecutive records via a selection rule not yet found, (b) each
record is already a small, complete, independent element (a corridor
segment, a decorative band) rather than 1/4 of a bigger room, or (c)
something else. A live ground-truth comparison — capturing a real,
table-driven room's VRAM tilemap and matching it byte-for-byte against a
decoded record — was attempted this pass (`tools/rom/reach_room.py`) but
the only room reachable in this project's current playthrough draws via
the already-documented *hardcoded* "Block C" path (`$1E9F`, see the
"Dynamic finding... fourth pass" entry above), not the parameterized,
table-driven path — so it's a plain box (5 distinct tiles, no decorative
content) and cannot serve as a cross-check for this table's content. That
remains the concrete next step for a full ground-truth confirmation, not
a gap in the algorithm finding itself.

**Follow-up composition attempts, same pass — both tried, both negative,
recorded so they aren't retried the same way.** (1) Records 2-5 happen to
share an *identical* 3-byte header (`64 00 ff`) — a plausible "these 4
belong to one room" signal, stronger than the arbitrary index-order
grouping tested above. Rendered stacked the same way: same result as
before, 4 independent-looking bordered strips, not one unified box. (2)
Scanned all 256 records for every run of consecutive identical headers,
expecting groups of (a multiple of) 4 if "N identical headers = N/4
rooms" were the rule: real run lengths are **2, 3, 4, and 5**, not
consistently a multiple of 4 (one run is exactly 5 long, which can't be
whole 20x16 rooms under the "4 strips per room" model at all). Reads as
the header byte most likely being a coarse, reused *room-type/terrain*
tag (many unrelated rooms of the same type, e.g. "outdoor courtyard,"
placed near each other in the table by whoever built it) rather than a
room-grouping key — plausible but not confirmed either. **Composition
remains genuinely open**; further blind grouping hypotheses weren't
pursued past this point in favor of recording two clean negative results
and deferring to the live ground-truth approach described above.

## External source: the FFA-Disassembly project — a real US disassembly, used as a reference this pass (2026-08-08, tenth pass)

At the user's direction ("du musst das Spiel besser verstehen — suche
nach Komplettlösungen und technischen Dokumentationen"), searched for and
found a genuine, dedicated disassembly project for the US "Final Fantasy
Adventure" cartridge — [daid/FFA-Disassembly](https://github.com/daid/FFA-Disassembly),
with a 4-part technical devlog (see [references.md](../references.md)
for links and the "US-only until verified" caveat that applies to
everything below). This is real, substantial, previously-untapped
information — a categorically different kind of source than the fan
save-file archive or community cheat codes used in earlier passes.

### Immediate, strong cross-confirmation of our own sixth-pass finding

The disassembly's own text dump (bank `$0D`/`$0E`, described by its
author as "pretty corrupt" and only partially decoded) includes this
fragment verbatim:

> `<BOY>:__ Willy!\nWilly:\n<BOY>_ Mana\n is in danger now`

This is **the exact same story beat** this project independently found
and decoded in our EU ROM this session ("AAAA: WILLY!" / "Willy: [Mana]
ist in Gefahr" — see "Breakthrough" above) — `<BOY>` is their tool's
placeholder for the hero-name-substitution byte, matching our own
`"AAAA"` (the literal name entered in our playthrough). Independent
confirmation, from a completely different source using a completely
different ROM revision, that this project correctly identified and
decoded a real, specific scene — strong validation of the whole sixth-
pass thread, not just a coincidental similar sentence.

### Map data format (their part2) — a real, documented RLE + template scheme

Full scheme, as documented for the US ROM: **16 total maps**, each with
a header (`MAP_HEADER tilesetGfx, ?, metatiles, ?, mapRoomPointers, ?,
?`) at the start of US bank `$08`. Each map's `mapRoomPointers` region
starts with its **own 4-byte header**: `[encodingMode(0=RLE,1=Templated),
rleLength, heightInRooms, widthInRooms]`, followed by a flat list of
**pointer PAIRS per room — `(script_pointer, tiles_pointer)`**, not
`(header, data)`. RLE decoding: each tile-data byte is a literal tile
index UNLESS its high bit (`0x80`) is set, in which case it means
"repeat `byte & 0x7F`, `rleLength` times" (`rleLength` is a single
constant for the whole map, from the 4-byte header — not embedded
per-run). Template mode (encoding byte `1`) adds a base-room RLE
template pointer plus 24 bytes of directional "door tile" data (bits
0-1 = open/closed/wall, bits 2-7 = "this is a map exit" flag) between
the header and the room-pointer list — i.e. **door/exit encoding is a
real, separate, documented mechanism**, directly relevant to this
project's still-open milestone 5 question. Metatiles: 6 bytes each (4
bytes = four 8x8 GFX tile indices forming one 16x16 "metatile", byte 5 =
collision class, byte 6 = interaction type — weapon-destructible,
water, ice/cart-slide, climbable, damage-spikes, etc., all as concrete,
named categories).

**Reframes this project's own bank-5 finding**: what this project has
called "even-indexed header records" and "odd-indexed data blobs" for
five passes now are, per this scheme, far more likely **`(script
pointer, tile pointer)` pairs** — i.e. the "header" isn't a room header
at all, it's a **compiled script** (a short one, for the ~80% of records
that are exactly 3 bytes — consistent with a minimal script being just
one or two opcodes plus a terminator), and the map-level 4-byte
RLE/size header (which this project has never located) must live
somewhere separate, the way the US ROM keeps it in a distinct per-map
region rather than inline in the 512-pointer array this project found
at `0x14004`.

**Tested directly against our own data — a real attempt, inconclusive
at the byte level.** Applied the documented RLE rule to all 255
odd-indexed blobs, searching `rleLength` 2-40 for values producing a
clean, exact 320-tile (20x16, this project's own VERIFIED room
dimensions) or 360-tile total: only a small, inconsistent minority of
blobs (13/255 at best, for 360) hit an exact match for any single
`rleLength`, and swapping to test the even-indexed entries as the "real"
tile data instead did not improve this. **Does not confirm the RLE
scheme applies byte-identically to this EU ROM** — plausible
explanations, none yet distinguished: the *bit-level* RLE encoding
differs between builds even though the *concept* transfers; this
project's blob boundaries (derived from the raw pointer array, not a
per-map header) are subtly wrong; or the real per-map `rleLength`
constant is genuinine but this project doesn't have it and is
effectively guessing blind across a search range that doesn't include
the right value. **Not resolved this pass** — the concrete next step is
finding this EU ROM's own equivalent of the "`MAP_HEADER`... beginning of
[a] bank" structure (a small, fixed-position header holding pointers to
tileset/metatiles/room-data plus the real per-map RLE length) rather
than continuing to guess the length, the same "find the real header,
don't brute-force around it" lesson from the save-checksum thread.

### The real event/script system (their part3) — reframes milestone 7 entirely

The US ROM's event system is a **real, general-purpose bytecode script
engine**, not a collection of ad hoc position-triggered checks: **1283
total scripts**, one active at a time (blocking player input while
running), with documented opcodes including `$00` (end of script,
matching this project's own independently-found `TERMINATOR_BYTE`
exactly) and `$04` (display message — the text-block-start byte this
project also independently found, `$04 $10` before dialogue). Scripts
are reached via an **index into a script-pointer table** (not a direct
address), and every one of the following is script-driven: NPC dialogue
(story, shop, random), monster/boss spawning, "last enemy/boss killed"
handlers, story events, **map transitions (doors/entrances)** — directly
answering this project's own still-open milestone-5/7 question — chest
spawning and opening, the `Frage`/"ask your follower" menu option this
project found and tested this session (explaining why it did nothing
near "Willy" — he isn't a follower, and there was likely no script
attached to try), player death, and the ending credits. Trigger types:
entering a room, exiting a room, last-enemy-in-room-killed (two of
these three are **implicit sequential indices** — script N = room
enter, N+1 = room exit, N+2 = last-enemy-killed, not separately
referenced in code), walking onto a specific tile, opening a chest,
talking to an NPC, killing an enemy, killing a boss.

**Directly explains multiple of this project's own findings and dead
ends from earlier passes**: the position-triggered gate dialogue and the
"Willy" scene are now understood as ordinary script triggers (room-enter
or tile-walk scripts), not a special or unusual mechanism; the empty
`Frage` result is explained (no follower is present in either room
tested, or that specific interaction has no attached script yet); and
the whole reason earlier static searches for "the map table's consumer"
kept failing is now clear — **rooms are entered via a script-index
dispatch, not a direct table walk**, so there was never going to be a
literal `LD HL,$4004`-style reference to find.

### Bank-calling convention (their part1) — explains this pass's earlier static-search dead ends directly

FFA uses **function-index jump tables at the start of each code bank**
(except one dedicated to sound) rather than per-call-site hardcoded
bank-select instructions: a caller stores a function index in a WRAM
scratch variable (`wScratchBankCallFunctionNumber`, alongside
`wScratchBankCallA/H/L` to preserve registers across the call), invokes
a shared `pushBankNrAndSwitch` trampoline, and a shared
`returnFromBankCall` handles unwinding. **This is exactly why this
project's eighth-pass static searches (a literal `LD A,5`/`$2100`-write
idiom, a literal reference to the map table's base address) came up
clean-but-empty** — those searches were looking for an idiom this engine
doesn't use for indirect calls; a real caller would show up as a write
to two or three WRAM scratch bytes followed by a call to one shared
trampoline address, an idiom not yet searched for in our own ROM.
**Concrete new next step**: locate this EU ROM's own equivalent
scratch-variable-plus-trampoline pattern (find the trampoline first —
it's shared infrastructure, called from many places, so it should stand
out as a heavily-referenced single address — then search for what
writes to the WRAM bytes immediately before each call to it) instead of
re-attempting either of the eighth pass's now-understood-to-be-wrong
idioms.

**Executed this same pass (eleventh) — the trampoline mechanism is now
fully located, decoded, and VERIFIED in this EU ROM, end to end.**
Tallied every `CALL nn` target in the ROM; the single most-referenced
bank-0-resident address is a real, distinct routine, but a **different**
one (`$3727`, a generic register-scratch-save helper) turned out not to
be it — the real trampoline family was found one level away, via a
cluster of small 6-byte stubs (`PUSH AF` / `LD A,<const>` / `JP
<trampoline>`) that precede it. **The trampoline itself, fully traced**
(example at `$1F35`, one instance per target bank): saves the incoming
`A` (a per-bank function index) and the caller's `H`/`L` to fixed WRAM
scratch bytes (`$C0B2-$C0B5`), pushes a fixed return address (`$1FC2`),
loads a **hardcoded bank number** into `A`, and calls `$29FB` — **this
project's own long-known "byte-queue push" routine from the very first
room-load trace, now understood correctly**: its "also writes to the MBC
bank-select register `$2100`" behavior (flagged back then as
"incidental," dismissed) **is** the actual bank switch, and the
"queue" is genuinely a push-down stack of the *previous* bank number,
popped again by `$2A0A` (called from the shared `$1FC2` return handler)
to restore it — i.e. `$29FB`/`$2A0A` are this ROM's own
`pushBankNrAndSwitch`/`popBankNrAndSwitch`, exactly matching the US
disassembly's documented convention, found independently rather than
copied. After switching, the trampoline reads a pointer from `$4000 +
functionIndex*2` — **a real, live-verified function-index jump table at
the start of the target bank**, matching the documented convention
exactly — and jumps to it, restoring the caller's `H`/`L`/`A` first.
**Confirmed working end-to-end**: dumped bank 1's and bank 3's actual
jump tables (`file offset bankBase + index*2`) and found valid,
in-range pointers at every tested index. **Found 7 hardcoded trampoline
instances by scanning every `CALL $29FB` site for a preceding `LD A,n`**:
targets are banks **1, 2, 3, 4, 8 (11 separate call sites — heavily
used), 9, and 15**. Watching the trampoline's own scratch bytes
(`$C0B2-$C0B5`) live through the whole boot-to-room-entry sequence
found **48,932 hits** — this is genuinely core, pervasive infrastructure,
not a rare or special-purpose mechanism.

**A second, dynamic-bank variant also found and partially traced, but
NOT yet confirmed to reach bank 5.** Some `$29FB` call sites load `A`
from a **WRAM variable** (`$C3F0`) instead of a hardcoded constant — a
single write site for that variable (`$26FC`) sits inside a routine that
reads a small table (base `$4000` in a bank switched-to via a *separate*,
hardcoded `LD A,8` — i.e. this lookup table itself lives in bank 8,
alongside the confirmed font data) at an offset computed as
`function_of(A) * HL`, where the multiply routine used (`$2B7B`,
already known from the combat-formula trace) takes its **stride from
the caller's own `A` register, not a fixed constant** — so a single
static dump of "table stride 8" is unreliable; an early attempt at that
produced a plausible-looking `bank=5` byte at index 0 that could not be
verified as real (not solid enough to report as a finding) once this
was understood. **This is a real, live-verified, general mechanism** (a
per-entry table naming its own destination bank, exactly the shape of
"a per-item, per-event-type, or per-room-type handler dispatch," and a
strong remaining candidate for how bank 5 is eventually reached) but
**the specific question "does any live invocation of this pick bank
5" is still open** — the concrete next step is a live watchpoint on
`$C3F0` itself (catching the moment, if any, it's ever set to `5`)
rather than more static table-stride guessing.

**That watchpoint was run this same pass — a real result, not bank 5.**
Watched `$C3F0` across the fullest sequence traced yet in one session
(boot, both hero-name screens, the whole intro, first-room entry,
walking into the creature repeatedly, and opening the real menu) — it
was written **exactly once**, to value **`6`**, not `5`. This is a
genuine, informative negative for every context tested so far (not
proof bank 5 is never a dynamic target — only these specific screens
were exercised), and a new positive fact: **bank 6 is reached via this
dynamic dispatch mechanism** — bank 6 has not been individually
profiled by this project before (milestone 2's visual sweep found no
full-bank-scale art there, so it was assumed to be "code, unswept" —
this is now a concrete, live-confirmed reason to look at it next,
alongside continuing to hunt for a context that sets `$C3F0` to `5`).

The US ROM's freeform dialogue text (distinct from simple menu/name
strings) uses a **two-character-per-byte compression table** ("dual
character mapping," at US ROM address `00:3f1d`), with an unexplained
split indexing scheme (source bytes `$20-$70` index one half of the
table, `$80-$A0` index the other). This is a highly plausible
explanation for this project's own sixth-pass finding — the *simple*
encoding (`0xB0 + glyphIndex`, VERIFIED, used successfully for item
names and the "AAAA ist ein tapferer Kaempfer" sentence) round-trips
perfectly, but the *same* formula failed to locate the "Willy" dialogue
as literal bytes in the ROM file even for short, safe substrings — **if
general dialogue prose in this EU ROM is compressed the same way**, that
would explain exactly this pattern (simple strings decode fine, general
narrative text doesn't exist as literal byte runs at all). Also
confirmed independently: the `add $80` VRAM-tile-offset relationship the
US devlog found by debugging character-draw code matches this project's
own independently-derived formula exactly (`0xB0 = 0x80 + 0x30`, the
`0x30` VRAM DMA slot this project found via the title-screen trace) —
a second, specific point of agreement between the two independent
investigations, not just the general shape.

**Not yet tested against our own ROM**: whether the same dual-table
compression scheme exists in our EU build (at a different bank-relative
offset, per the "bank numbers differ" caveat), and if so, decoding it.
This is now the best-supported concrete next step for the still-open
"why can't the Willy dialogue be found as literal bytes" question,
ahead of the window-layer-tile-addressing angle explored (inconclusively)
last pass.

## Text / dialogue data — encoding VERIFIED, extent PARTIALLY VERIFIED

Byte encoding solved via dynamic tracing (a real emulator, since static
analysis alone could not crack it) — full writeup in
[text.md](text.md) and [tooling.md](tooling.md). Formula: byte
`0xB0 + fontGlyphIndex` (i.e. bit 7 set + the font's own VERIFIED ROM
tile order), `0xFF` = space, `0x00` = terminator. Confirmed against real
decoded German sentences (`"Der Mana Baum"`, `"Hier hast Du Deine"`,
`"Lebens- und Magiepunkte erhoeht"`) and an item/spell name table at file
offset `0x9de5` (bank 2). **UNKNOWN**: a dialogue pointer table (strings
found so far by direct scanning, not by walking an index — see text.md
"What's still open"); whether this is the *only* encoding used for all
in-game text or just this subset; full decoding of the umlaut/icon block
(`0x90-0xAF`, only 1/32 bytes confirmed).

## Save RAM (MBC2 built-in RAM, `$A000-$A1FF`, low nibble significant) — format VERIFIED (2026-08-08, fifth pass)

**Dynamic finding**: no save-RAM write happened anywhere in ~2800 frames
of boot -> room-entry (contradicting a previous-round note that assumed
"New Game" itself triggers one immediately — that note is now believed to
have been misreading mGBA's own periodic `.sav`-file-flush log line, not
an actual SRAM content change; corrected here). Watching all of
`$A000-$A1FF` (`tools/rom/watcher.py`) during ~3000 further frames of
mixed movement/menu-button input **did** catch a real write, letting the
encoding be read directly from the ROM (`tools/rom/disasm.py`) instead of
guessed:

- **Every stored value is nibble-packed into two consecutive SRAM
  bytes**, low nibble first: `WriteNibblePair` (bank-2-local, file
  `0xB46E`; PC is only meaningful with the bank — see tooling.md
  "gotcha" about this) does `PUSH AF` / `AND $0F` / `LD (HL+),A` / `POP
  AF` / `SWAP A` / `AND $0F` / `LD (HL+),A` — i.e. one real 8-bit byte of
  game data costs exactly 2 bytes of MBC2's nibble-significant RAM, which
  is *why* the RAM is nibble-addressed in the first place, not an
  arbitrary hardware quirk. `ReadNibblePair` (file `0xB479`) does the
  inverse (`SWAP`+`OR` to recombine). Confirmed structurally: every
  single value observed in the live write was `<= 0x0F`.
- **A 0x6C magic/validity byte** is the very first packed value (SRAM
  `$A000`/`$A001` decode to `0x6C`) — `0xB48D` (`CP $6C`) checks it
  immediately after a `ReadNibblePair`+SRAM-enable sequence, branching
  away (presumably to "no valid save, initialize fresh") on mismatch.
  Real, minimal save-corruption/absence detection.
- **The save is duplicated**: the observed write touched `$A000-$A0F7`
  (124 real bytes packed as 248 nibble-cells) at one point, then wrote
  **byte-for-byte identical** content to `$A100-$A1F7` ~49 frames later —
  a plain `LD A,(HL+)` / `LD (DE),A` copy loop (file `0xB45B`) rather
  than a second encode pass, i.e. a primary+backup copy for corruption
  resilience within MBC2's 512-nibble budget, not two different save
  slots.
- **SRAM enable/disable via the standard MBC `$0000` register**: `LD
  A,$0A` / `LD ($0000),A` (file `0xB462`) before touching SRAM, `LD
  A,$09` / `LD ($0000),A` (file `0xB468`) afterward — the standard
  MBC-family "enable external RAM" command, `$0A`; the disable value used
  here (`$09`) is unusual (`$00` is the textbook disable value) and not
  investigated further.
- **UNKNOWN**: the trigger condition (happened during undirected
  mixed-input testing, not tied to a specific confirmed player action
  yet — a menu open, an item pickup, and a periodic autosave timer are
  all plausible and untested), and the meaning of the ~122 remaining
  packed bytes beyond the magic byte (presumably the same stats/
  inventory/position fields as the live WRAM struct above, copied
  through the nibble-pack routine, but not yet matched field-by-field).

**External validation, and a real cross-region limitation found
(2026-08-08, seventh pass)**: at the user's suggestion, found and
downloaded a set of 23 real, progressively-advanced save files for the
**US** "Final Fantasy Adventure" cartridge from a fan archive
(fantasyanime.com — see references.md for the exact source and URLs; a
network fetch actually worked in this sandbox, contrary to an earlier
assumption). Decoding the first save's raw bytes with this project's own
independently-derived nibble-unpack formula (`real_byte = low_nibble(cellA)
| (low_nibble(cellB) << 4)`) produced **`0x6C` as the very first decoded
byte** — an exact match to the VERIFIED magic byte above, from a
completely independent, external data source. This is strong,
real-world confirmation the nibble-pack format finding is correct, not
an artifact of this project's own tracing.

**Feeding a real, further-progressed save into the EU ROM does not work
cleanly, though — a genuine, informative negative result**: writing a
real save's full 124-byte payload into SRAM (mirrored into both the
primary and backup regions, per the VERIFIED duplicate-copy structure
above) and booting caused a **hard CPU lockup**: `core.cpu.pc` frozen at
the exact same address (`$0120`, inside the ROM header's ​Nintendo-logo
data bytes, disassembling as the real, genuinely illegal SM83 opcode
`0xDD`) for 20,000+ consecutive single-steps — this is mGBA faithfully
emulating what a real DMG CPU does on an illegal opcode (an authentic
hardware lockup, not an emulator bug).

**Correction, same session — a first bisection attempt was
methodologically flawed and gave the wrong answer**: bisecting by
checking "does a known title-screen tilemap pattern appear by frame 600"
found an apparent boundary at real-decoded byte offset 27 — but that
signal conflates "still loading/animating" with "genuinely, permanently
locked up," and was wrong. Re-bisecting with a strict signal instead
(`core.cpu.pc` sampled across thousands of `core.step()` calls staying
on a *single* value — the actual, unambiguous lockup signature already
used to confirm the illegal-opcode lockup above) found the **real**
boundary is the payload's **very last byte** (raw file offset 247, the
high nibble of decoded real-byte 123 — i.e. the final byte of the whole
124-byte record, decoded value `0xC6`): bytes 0-246 load and run without
locking up; adding byte 247 causes the hard lockup. Zeroing *only* that
one byte (leaving all 246 other real bytes — stats, presumably inventory
— intact) reliably avoids the lockup. This corrects and supersedes the
earlier "byte 27" claim, which is now believed to have been an artifact
of the flawed detection method, not a real boundary.

**"Checksum" hypothesis tested and revised (2026-08-08, eighth pass)**:
downloaded 8 more real US saves (12 total, spanning the whole game from
the first cave to the final boss) and decoded all of them. **Every
single one has the exact same value at this position, `0xC6`** — a real
per-save checksum would vary with the payload; a constant across 12
completely different game states rules that out. This is a fixed marker
(plausibly a build/version tag baked into the US save-write routine),
not a per-record checksum. **Brute-forced all 256 possible values** of
this byte against the real Wendel save (each tested for a genuine
`core.cpu.pc`-frozen lockup, not the flawed frame-count proxy) to map
out the real EU-ROM-compatible range: **163 of 256 values are safe,
93 cause the hard lockup** — including the US constant `0xC6` itself
(the whole `0xC0-0xCF` and `0xD0-0xDF` ranges are 100% unsafe). The safe/
unsafe pattern (e.g. `0x60-0x6F` entirely unsafe but `0x70-0x7F`
entirely safe; `0x40-0x4F` unsafe except exactly `0x41`/`0x48`) doesn't
resemble a computed checksum's pass/fail boundary — it reads much more
like this byte selects a **jump-table entry or code offset directly**,
where "safe" values happen to land on valid instruction boundaries and
"unsafe" ones land mid-instruction or in non-code bytes (matching the
observed lockup: PC frozen inside literal ROM header/logo bytes for the
known-bad `0xC6`). **Practical result**: no formula was needed — `0x00`
(already verified safe) is a reliable, reusable placeholder for this
byte whenever writing external/synthesized save data into this EU ROM
for future research.

**Even with the lockup avoided, "Continue" still doesn't reach a normal
interactive game state** — the screen stays on the Nintendo boot logo
well past 3000 frames (50x longer than every successful fresh-boot
traced this project), while the CPU keeps actively executing real code
(not stuck — cycles through the generic multiply routine at `$2B7B`
this project traced earlier for the damage formula, among other
addresses), so this is not a second lockup, just a boot sequence that
never visibly completes within the window tried. Not investigated
further this pass — a real, open sub-problem of its own.

**A short, safe prefix (bytes 0-53 raw / real bytes 0-26) loads and
reaches the title screen without incident, but selecting
"Weiterspielen" (Continue) against it falls back to fresh-game default
stats** (`LP 19`, `MP 6`, `Gold 50`, matching a brand-new character)
rather than crashing — real evidence the continue-path validates more
than just the magic byte before trusting a save, gracefully rejecting
an incomplete/truncated one rather than loading garbage. (This
observation itself remains valid; only the *exact byte* responsible for
the full-payload lockup has been corrected above.)

**Net assessment**: the SRAM *data format* (nibble-packing, magic byte,
duplicate-copy structure) is now doubly confirmed — once by this
project's own live dynamic trace, once by an independent, external real
save file — and the specific record-final checksum-like byte
responsible for cross-region incompatibility is now precisely
identified (not just "somewhere in the payload"). Getting a real,
externally-sourced save to fully drive a normal, playable "already
progressed" game state on this EU ROM was still not achieved this pass
(recomputing/patching a valid checksum for this ROM's own algorithm, and
resolving why "Continue" stalls past the logo screen even once the
lockup is avoided, are the concrete remaining steps) — but the crash
itself is now understood precisely rather than approximately.

## Player stats struct and combat — PARTIALLY VERIFIED (2026-08-08, fifth pass)

**Dynamic finding**: while trying (and failing — see Milestone 5 note
below) to trigger a room transition, walking the player into the
starting room's bat enemy caused real, observable damage (`LP 19 -> 13`
over two 3-point contact ticks, one per second). Used `core.memory.search`
(the bindings' Cheat-Engine-style value scanner — has a real bug, see
tooling.md) to find the address, then a live watchpoint
(`tools/rom/watcher.py`) to catch the exact write.

- **Player stats struct, WRAM `$D7B2`, VERIFIED** (exact match against
  the HUD's `LP 19 MP 6 G 50` at every field): `+0` current LP (u16 LE),
  `+2` max LP (u16 LE), `+4` current MP (u16 LE), `+6` max MP (u16 LE),
  `+8` a byte reading `1` (plausibly level — unconfirmed), `+12` Gold
  (u16 LE, `= 50`, exact HUD match). Bytes at `+16` (`2,2,2,0,8,...`)
  look stat-shaped (possibly STR/DEF/AGI or similar) but are not yet
  individually confirmed.
- **Generic "subtract N from current HP, clamp at 0" primitive, ROM
  `$3E30`**: 16-bit subtract with an underflow check (`JR NC` / clamp to
  `$0000`), writes back to `$D7B2`/`$D7B3`, then `CALL $310B` (a
  HUD-refresh or death-check hook, not traced further) before returning.
  Immediately followed at `$3E51` by a real death-check pattern: reload
  current LP, `OR` the two bytes together, `RET NZ` (still alive), fall
  through to more logic only when LP `== 0`.
- **Damage-computation call chain, ROM `$50AC`, PARTIALLY TRACED**: not a
  fixed per-enemy constant — combines a defense-like value (`$3D1D`, a
  one-line accessor: `LD A,($D6C3); RET`) with a multiplication (`$2B7B`,
  a real 8-iteration shift-add multiply routine) and what reads as a
  pseudo-RNG (`$2B1E`: increments a wrapping counter at `$C0B0` against a
  bound at `$C0B1`, uses it to index two bytes out of a fixed ROM table
  at `$2A1E` and sums them — the classic "rotating index into a
  precomputed noise table" 8-bit RNG pattern) before calling `$3E30`
  above to actually apply the result. **UNKNOWN**: which operands feed
  the multiply (attacker's weapon power vs. defender's stat — not yet
  disambiguated), the exact role of `$D6C3`, and the `$2A1E` RNG table's
  contents/period. A real formula skeleton is confirmed; the precise
  arithmetic is not.
- Also confirmed: **this is real-time contact/action combat** (Seiken
  Densetsu 1's actual genre — action-RPG, not a menu-driven turn battle),
  not a separate battle-scene state — damage applied directly while
  walking, no mode switch observed. Revises Milestone 9's expected shape:
  no "battle screen" state machine to find, just a hit-detection +
  damage-application path hooked into the normal field-movement loop.
- **`$D6C3`'s role narrowed, not closed (2026-08-08, sixth pass,
  continued)**: live-read at a fresh level-1 character, `$D6C3 = 6`,
  exactly matching Data Crystal's separately-labeled `$D7DF`/`$D7E0`
  "attack/defense power" fields (also `6, 6` — already independently
  confirmed, see "Data Crystal's RAM map" below). Consistent with
  `$D6C3` being a live working-copy of the current attack (or defense)
  stat that the damage formula reads directly, rather than a distinct
  third value — plausible but not proven (no transform connecting it
  back to the equipped `"Breit"` weapon's raw ROM stat bytes was found;
  the weapon record's own bytes don't contain a literal `6`, so if
  `$D6C3` derives from equipment at all, some formula sits in between,
  not yet traced). **Caution surfaced by this check**: Data Crystal's
  `$D6B3-$D6BE` ("equipment power values") reads as a suspiciously clean
  descending countdown (`12,11,10,...,2,1`) for this fresh character —
  more consistent with default/placeholder initialization data than
  genuine per-item power values, a reminder that an address matching
  (this project's own "VERIFIED to match" finding below) doesn't
  guarantee Data Crystal's *field-purpose label* is correct too; each
  field's actual semantics still wants independent confirmation before
  being trusted structurally.

## Enemy HP struct + death dispatch — VERIFIED via direct code trace, not empirical (2026-08-09)

Traced per explicit instruction to find the real code rather than infer
from behavior. Method: `tools/rom/watcher.py` single-stepping through a
live kill with WRAM watchpoints, then breaking on specific PCs and
reading the return address off `cpu.sp` to walk the call stack upward
(caller-of-caller-of-caller), each hop confirmed by disassembling
around the resolved ROM offset (`tools/rom/disasm.py`) rather than
guessed from surrounding bytes.

- **Enemy HP, WRAM `$D3F4` (low byte) / `$D3F5` (high byte), u16 LE,
  VERIFIED.** Damage-subtract routine at ROM file offset `0x1070B`
  (bank 4, local `$470B`): loads HP into `HL` (`H=($D3F5)`,
  `L=($D3F4)`), subtracts the caller-supplied damage in `DE` via
  `CALL $2BAB` (16-bit subtract), and on `Z` (exact 0) or no-carry-clear
  (underflow, damage exceeded remaining HP) clamps `HL` to `$FFFF`
  before storing back — `$FFFF` is the dead sentinel, not `$0000`.
- **Death-dispatch check, ROM `0x1025F`/local `$425F`**: reads
  `$D3F5` (HP high byte) and does `BIT 7,A` once per event-dispatch
  tick — true exactly when HP is the `$FFFF` sentinel (high byte
  `$FF`). If set, jumps straight into `CALL $4575` instead of normal
  per-tick enemy processing.
- **Despawn chain, `$4575` (ROM `0x10575`) → `$4425` (ROM `0x10425`) →
  `$0AE3` (ROM `0xAE3`)**: `$4575` calls `$4425` unconditionally (no
  further HP check — the caller already decided). `$4425` walks a
  14-slot table at WRAM `$D442` (the enemy's own OAM body-part slot
  indices, built at spawn) and calls the generic single-slot despawn
  primitive `$0AE3` for each live entry. `$0AE3` operates on the
  generic entity struct at `$C200 + slotIndex*16`: zeroes the position
  pair (+4/+5), zeroes that slot's 8-byte OAM shadow-copy block via a
  real memset loop at `$2B5D` (pointer stored at struct+8/+9), then
  writes `$FF` to struct+0 (that slot's own alive/dead sentinel — same
  `$FF`-for-dead convention as the HP field, reused at a different
  struct scale). Live-captured for the test enemy: exactly six calls
  with `C = 7..12`, matching the six body-part OAM pairs (bases
  `$C270`,`$C280`,`$C290`,`$C2A0`,`$C2B0`,`$C2C0`) seen going blank
  together.
- **Explicit negative result**: nowhere in this traced chain — from the
  `$D3F5` bit-7 read down through both despawn calls to the final
  zero-fill loop — does any instruction write a new OAM entry, load a
  new tile ID, or call anything resembling a sprite-spawn routine. It
  is a pure "hide my existing parts" cleanup. A user-reported fireball/
  explosion effect on enemy defeat, if real, is not part of *this*
  chain; see `docs/reverse-engineering/combat.md`'s "Enemy HP" section
  for the same finding with the full instruction listing and the
  suggested next trace (follow `$D3F5` forward from wherever it's
  first observed as `$FFFF`, a few attacks before despawn actually
  fires per live capture, rather than backward from the despawn).

Supersedes/replaces the "not found, `$C254`/`$C255` worth tracing"
lead from the previous pass (see `combat.md`).

## Data Crystal's US-cartridge RAM map — VERIFIED to match this EU ROM exactly (2026-08-08, fifth pass)

**Correction to the finding above** (the "$D7B2 struct" was independently
found via a value-scan before checking references.md — once checked, it
turned out to *already be documented*): [references.md](../references.md)'s
Data Crystal RAM-map lead, marked HYPOTHESIS and assumed to need
address-shift correction for the EU cartridge, was cross-checked directly
against live EU ROM state at the first room and **matches with zero
offset on every field checked**:

| Field (Data Crystal, US) | Address | Live EU value | Expected | Match |
|---|---|---|---|---|
| current/max HP | `$D7B2-$D7B5` | `19,19` | HUD `LP 19` | Yes |
| current/max MP | `$D7B6-$D7B9` | `6,6` | HUD `MP 6` | Yes |
| level | `$D7BA` | `1` | fresh character | Yes (plausible) |
| lucre/gold | `$D7BE-$D7BF` | `50,0` | HUD `G 50` | Yes |
| stamina/power/wisdom/will | `$D7C1-$D7C4` | `2,2,2,2` | fresh character | Yes (plausible) |
| attack/defense power | `$D7DF`/`$D7E0` | `6,6` | fresh character | Yes (plausible) |
| hero name buffer | `$D79D-$D7A0` | `0xBA×4` | entered "AAAA" | Yes (4 identical bytes) |
| heroine name buffer | `$D7A2-$D7A5` | `0xBA×4` | entered "AAAA" | Yes (4 identical bytes) |
| experience | `$D7BB-$D7BD` | `0,0,0` | fresh character | Yes (plausible) |
| deathblow gauge | `$D858` | `1` | fresh character | Yes (plausible) |
| items bag / equipment bag / equipment power | `$D6C5-$D6D4` / `$D6DD-$D6E8` / `$D6B3-$D6BE` | all `0` | empty starting inventory | Consistent, not yet positively confirmed (nothing to distinguish from uninitialized memory until an item is acquired) |

**The in-game menu system, found live (2026-08-08, sixth pass,
continued)**: pressing `START` during ordinary field control (confirmed
both in the starting courtyard and the post-creature chamber) opens a
real menu — four options `Dinge`/`Magie`/`Waffe`/`Frage` (Items/Magic/
Weapon/Ask — a status readout showing `Gut` ["Good/fine", presumably a
condition indicator] and `Breit` sits beside it). **`Breit` identified
and its ROM table found** (user correction, then confirmed by direct ROM
search): not "broadsword" spelled out — the literal stored string is
`"Breit"` itself, found at file offset `0xA1F6`, sitting inside the
equipment/ring name table text.md had already flagged (at `0xA275`,
"plausible as equipment/ring names, UNVERIFIED beyond the text itself")
— this live UI cross-check promotes that table from UNVERIFIED
speculation to confirmed weapon/equipment data, and reveals its true
extent is much larger than the 7-name sample previously noted.

**Weapon/equipment table, file offset `~0xA1C0` onward — record
structure PARTIALLY VERIFIED**: a real, clean 16-byte fixed-width record
(same name-field width convention as the item/spell table above):
`bytes 0-4` (5 bytes, stat/price data, UNKNOWN formula), `byte 5` (a
category/icon byte, seen values `0xA2-0xA8` — an adjacent sub-range to
the item table's `0xA9` "premium" marker, plausibly one icon per
equipment slot type: weapon/armor/ring/etc.), `bytes 6-13` (8-byte
0x00-padded name, same convention as the item table), `bytes 14-15` (2
more bytes, UNKNOWN — not a clean monotonic ID like the item table's
byte 15 on a first check). Names decoded so far, scanning `0xA1C0-
0xA330` for glyph runs: `Juwelen` (jewels), `Opale` (opals), **`Breit`**
(the live-confirmed weapon), `Axt` (axe), `Sichel` (sickle), `Ketten`
(chains), `Silber` (silver, appears twice), `Speer` (spear), `Streit`
(likely `Streitkolben`/mace, truncated), `Stern` (star), `Kraft`
(power), `Drache` (dragon), `Flammen` (flames), `Eis` (ice), `Zeus`,
`Rostig` (rusty), `Lanze` (lance), `Excali[bur]`, `Bronze`, `Eisen`
(iron) — a clear mix of weapons, materials, and what read as elemental/
mythological ring names (matching Seiken Densetsu's known ring-magic
system, as text.md's original note guessed). **UNKNOWN**: the table's
true start/end boundaries (only the `0xA1C0-0xA330` window has been
scanned), the 7-byte stat/trailer fields' meaning, and whether this is
one unified equipment table or several adjacent ones (weapons vs. rings)
that happen to share the same record shape.

`Dinge` and `Magie` open empty submenus (both consistent with a fresh
level-1 character owning nothing, matching the all-zero items/equipment
bags already found — still not positively distinguishing "confirmed
empty" from "not yet found the real submenu content path"); `Waffe`
likewise showed nothing (consistent with the weapon being equipped
rather than sitting in an inventory list — matches `Breit` being shown
outside any submenu, as a permanently-equipped item); `Frage` closed the
menu immediately rather than opening a submenu, reading as a
context-dependent "ask/talk" action that
needs an NPC target rather than a real menu page. **Save trigger still
not found**: watched `$A000` through the entire boot-to-free-roam
sequence and through a full pass navigating every menu option — zero
SRAM writes in either. The real trigger (an explicit save point/item, a
different menu context, or something not yet tried) remains open.

**This means the whole Data Crystal RAM map can be upgraded from
HYPOTHESIS to (mostly) VERIFIED for this EU ROM** — Square's EU
localization evidently kept the WRAM data-segment layout byte-identical
to the US cartridge, exactly as references.md's own caveat predicted was
plausible-but-unconfirmed. This is a real shortcut for milestone 8
(items/equipment) and future stats/leveling work: the addresses can be
used directly, cross-checked opportunistically rather than rediscovered
from scratch each time. Still worth spot-verifying any field before
depending on it structurally (the items/equipment bags above are only
"consistent with empty," not positively confirmed — acquiring a real item
and re-checking is the next concrete step there), and note this only
covers **RAM addresses**; Data Crystal's ROM map for this game was noted
in references.md as a stub with no useful entries, so ROM-side formats
(item stat tables, event scripts, enemy data) still need this project's
own reverse engineering.

## Audio — format UNKNOWN, driver bank narrowed (2026-08-08, fifth pass, static only)

**Static finding**: scanned the whole ROM for `LDH (n),A` (opcode `0xE0`)
with `n` in the GB sound-register range `$10-$3F` — a generic "does this
byte region contain code that hits real sound hardware" heuristic (same
spirit as `tools/rom/scan_pointers.py`'s pointer-run heuristic), then
bucketed hits by bank:

| Bank | Sound-reg write count | Note |
|---|---|---|
| 0,1,2,4 | 1-7 | noise-level, ignore |
| 8 | 20 | bank 8 is the VERIFIED font bank — likely coincidental byte patterns in tile data, not real code |
| 9,10,11,12 | 77,75,37,39 | these banks are VERIFIED pure graphics data (sprites/tileset) from milestone 2 — **almost certainly false positives**: raw 2bpp pixel bytes can easily contain `0xE0` followed by a `$10-$3F` byte by chance, so these counts should **not** be read as "these banks contain sound code" |
| 13,14 | 18,13 | previously swept and confirmed to hold **no** full-bank-scale art (milestone 2) — more likely to be real code |
| 15 | 95 | same (no art found here either) — the single densest bucket |

**Dynamically CONFIRMED**: watched all of `$FF10-$FF3F` (`tools/rom/
watcher.py`) through boot + the title screen (which has music playing) —
**all 830 sound-register writes observed came from bank 15** (file
offsets `0x3C2EB-0x3C92F`), zero from any other bank, matching the static
hypothesis exactly and ruling out banks 8-12 as the static scan's caveat
predicted. **Bank 15 is confirmed as the real, active sound driver.**
Still UNKNOWN: no note table, instrument/waveform format, or
music-sequence format has been identified within bank 15 yet — this pass
confirmed *where* the driver lives and that it's genuinely active, not
*how* it's told what to play. `mgba`'s Python bindings also expose live
PCM audio buffers (`core.get_audio_channels()`), not used this pass.

### Audio format — DECODED (2026-08-15, direct user request "schau dir mal das musik und sound system an und entschluessel es")

Full static disassembly of bank 15 (`tools/rom/disasm.py`, no live
emulator needed this pass — the driver's own code is dense enough to
read directly). A real, working decoder now exists:
`tools/rom/decode_music.py` (`--list-songs`, `--song N`) — its own doc
comment mirrors this section, kept in sync.

**Song table — VERIFIED**: file offset `0x3CA12` (CPU `$4A12`), 6
bytes/record, 3×2-byte little-endian CPU-address pointers (one per
channel stream). Dumping all 40 possible slots shows exactly **30**
real, monotonically-increasing, in-bank-range entries before the data
degrades into clearly out-of-range garbage — a real, self-evident table
boundary (same pattern this project has used to bound every other real
table, e.g. the digraph/song tables elsewhere in this file). Entry
point `$3C09E` takes a 1-based song index in `A`; `$3C048` is a
separate "stop all sound" entry (called with no song, or via the
boot-time reset vector at `$3C003`).

**Per-channel event stream — VERIFIED via musically-coherent decoded
output** (`decode_music.py --song 1` produces a real, singable melody
with an exact phrase repeat and a clean closing C-E-G major arpeggio —
not noise; see audio.md for the full transcript excerpt). Each channel
stream is a byte sequence read one event at a time by real, disassembled
per-frame update code (`$3C7C8` region, called every real driver tick
from the top-level update at `$3C006`):
- **`0xFF`**: hard stop (silences the channel).
- **`0xE0`-`0xEC`**: 13 real driver commands, jump table at CPU `$4365`
  (16-slot table, only 13 populated — `0xED`-`0xEF` are unused/never
  emitted). Every command's real operand LENGTH is confirmed by direct
  disassembly of its own handler (all fetch operand bytes via the
  driver's own generic "read next stream byte, advance pointer"
  primitive at `$47D9`/`$47E5`/`$4417` — a real, fixed-width
  instruction, not guessed):
  | Byte | Operand | Real, disassembled effect |
  |---|---|---|
  | `0xE0` | 2 | Saves a real "resume here" address (a loop point) into a WRAM cell pair for later use. |
  | `0xE1` | 2 | Unconditional jump — sets the stream pointer directly (the real loop-BACK mechanism songs use to repeat). |
  | `0xE2` | 2 | Sets up a real, per-frame-countdown-gated pitch bend/slide (WRAM `$C10F` counter). |
  | `0xE3` | 1 | Sets a real per-channel parameter byte (`$C10F`). |
  | `0xE4` | 2 | Sets the pointer for a SEPARATE, auxiliary per-note vibrato/pitch-delta stream (`$C107`-`$C10A`) — pairs of (duration-frames, SIGNED pitch delta) added on top of the channel's cached base frequency every countdown tick. NOT walked by the current decoder (a fine-modulation layer, not the core melody). |
  | `0xE5` | 1 | Writes directly to the real GB duty-cycle/length register (NRx1) and caches the byte. |
  | `0xE6` | 1 | PANNING: indexes an 8-entry real ROM table at CPU `$4664` and ORs the result into NR51 (`$FF25`, the real stereo-panning hardware register). |
  | `0xE7` | 1 | Sets a real global parameter byte (`$C101`) — plausibly tempo/speed, not independently confirmed. |
  | `0xE8` | 0 | Real jump-table target disassembles as a literal self-jump (`JP $4361` sitting AT `$4361`) — an unused/placeholder slot, treated as a true no-op. |
  | `0xE9` | 2 | A second pitch-bend/slide variant (parallel structure to `0xE2`, different WRAM cell `$C119`). |
  | `0xEA` | 1 | Sets a real per-channel parameter byte (`$C119`). |
  | `0xEB` | 1 | A third pitch-bend/slide variant (parallel structure to `0xE2`/`0xE9`). |
  | `0xEC` | 1 | Sets a real global parameter byte (`$C1C8`) — plausibly an SFX-priority/ducking marker, not independently confirmed. |
- **`0xD0`-`0xD7`**: SET the current octave directly (`(byte&7)*24` — a
  real byte-stride offset into the 24-byte-wide, 12-note frequency
  table blocks below — VERIFIED by the real code doing exactly this
  arithmetic before using the result as a table index).
- **`0xD8`-`0xDF`**: ADD a signed octave/detune SHIFT instead of
  overwriting — looked up from a real 8-entry ROM table at CPU `$47D1`
  (`0x18,0x30,0x48,0x60,0xE8,0xD0,0xB8,0xA0` — the first 4 and last 4
  are each other's two's-complement negation, `±24/±48/±72/±96`, a
  clean "shift up/down by N semitones-worth-of-octave-bytes" design).
- **Else (`0x00`-`0xCF`)**: a real NOTE event. High nibble (0-12)
  indexes a real 13-entry ROM duration table at CPU `$424A`
  (`0x60,0x48,0x30,0x20,0x24,0x18,0x10,0x12,0xC,0x8,0x6,0x4,0x3` = a
  musically coherent whole/dotted-half/half/dotted-quarter/quarter/…
  rhythm tree in real frame counts, 96 down to 3). Low nibble: `0`-`13`
  = a real note index (0 = highest pitch in the current octave block);
  `14` = rest; `15` = explicit note-off.

**Frequency table — VERIFIED**: CPU `$41A0` (file `0x3C1A0`). A REAL,
ready-to-write GB hardware register pair per note, little-endian
16-bit, e.g. `0x802C, 0x809D, 0x8107, …, 0x87F0` — low byte is written
directly to NRx3 (frequency low), high byte directly to NRx4 (bit 7
already set = trigger, low 3 bits = the period's own top bits) with
ZERO further transformation by the driver. 7 full 12-note chromatic
octave blocks (84 notes) plus one extra top note (85 total),
monotonically increasing period (= descending pitch) exactly as a real
chromatic scale must — decisive, self-evident structural confirmation
independent of the musical-coherence check above.

**Per-frame playback mechanism — VERIFIED** (`$3C802`-`$3C868` for one
channel, a byte-identical parallel block `$3C869`-`$3C8C8` for a
second): a real per-note duration counter (WRAM `$C106`/`$C11E`)
decrements every real driver tick; at 0, the next (duration, pitch)
byte pair is fetched from the vibrato/delta stream (`$C109`-`$C10A` /
`$C121`-`$C122`), the pitch byte is sign-extended and ADDED to the
channel's cached base frequency (`$C10D`-`$C10E` / `$C125`-`$C126`),
and the result is written straight to hardware (NR23/NR24 for one
channel, NR13/NR14 for the other) — this is the auxiliary vibrato layer
referenced above, confirmed live-structurally even though not walked
by the transcript decoder. A duration byte of `0x00` in this stream is
a real embedded loop marker (`$3C932`): reads a 2-byte address right
there in the stream and jumps the pointer there, i.e. genuine loop-back
support at the fine-grained note level too, not just via command `0xE1`.

**Genuinely still open**: exact musical intent of `0xE2`/`0xE3`/`0xE7`/
`0xE9`/`0xEB`/`0xEC` beyond their real WRAM side effect; the noise/wave
channel's own real target register (channel 3 decodes as a coherent
melodic line via the SAME mechanism in practice, so if it differs it's
subtle); no `src/audio/` Lua module ports this into the actual game
engine yet (`tools/rom/decode_music.py` is a real, standalone Python
proof of the format).

## Item/spell table — real record structure found (2026-08-08, sixth pass, continued)

The item/spell name table at file offset `0x9de5` (bank 2 — see text.md)
was previously read as names only. Re-dumped each record's full 16 bytes
(not just the name) and found a real, consistent structure:

- **Bytes 0-7: the name**, `0x00`-padded (as already known).
- **Byte 15 (the record's last byte): a per-category item ID, VERIFIED
  by the pattern itself.** Slots 0-7 read `01,02,03,04,05,06,07,00`; slots
  8-19 read `01,02,03,04,05,06,07,08,09,0a,0b,0c` — **the counter resets
  exactly at the slot7/slot8 boundary**, which is strong, self-evident
  confirmation this is a real "ID within its category" field (a
  coincidence wouldn't reset cleanly like that), and pins the boundary
  between two real item categories to exactly slot 7|8.
- **Byte 8 correlates with the same boundary**: `0x41-0x43` for slots
  0-7 (consumable items — `Lebe[n]`/`Salbe`/`Blo[c]k`/`Ruhe`/`Flam[me]`/
  `Eis`/`Bliz[zard]`/`Bomb[e]`, matching text.md's item list) vs.
  `0x00`/`0x80` for slots 8-19 (spells — decoded names include `Magi`,
  `Elixier`, `Auge`, `Bewege`, `Spruch`, `Allheil`, `Stille`, `Schlaf`,
  matching text.md's spell list). **HYPOTHESIS**: byte 8 is a category/
  type flag, corroborated by but not independently proven beyond this
  correlation.
- **A new, unconfirmed name-prefix byte, `0xA9`** (within the still-
  partially-decoded `0x90-0xAF` block), appears on slots 8, 9, 13-16 —
  all decoded to visually "upgraded" item names (`[0xA9]Lebe`,
  `[0xA9]S-Lebe`, `[0xA9]Salbe`, `[0xA9]Auge`, `[0xA9]Bewege`,
  `[0xA9]Spruch`) — plausibly an icon glyph (a small graphic tile, not a
  letter) marking premium/advanced items, matching Seiken Densetsu's
  known "S-" prefixed super-potion items. **Correction to an earlier
  reading**: text.md's original transcription glossed slot 8 as
  "S-Lebe[n]" from context; the real decoded bytes show slot 8 as
  `[0xA9]Lebe` (no literal "S-" text) and it's actually **slot 9** that
  spells `[0xA9]S-Lebe` with literal S-hyphen characters *in addition to*
  the `0xA9` byte — meaning either `0xA9` isn't simply "S" (a redundant
  respelling wouldn't make sense) or the two slots represent genuinely
  different items that both look similar in a low-res screenshot. Not
  resolved this pass; flagged rather than guessed at.
- **UNKNOWN**: bytes 9-14 (6 bytes per record) — visibly non-constant,
  plausible candidates include price, power/potency, and a usable-item
  quantity/charge count, but no formula or HUD cross-check has been
  attempted yet (no item has been acquired in dynamic play to compare
  against).

Recorded machine-readably nowhere yet — this is a documentation-only
finding this pass; wiring it into `rom_profiles.lua`/a real Lua importer
is future work once bytes 9-14 are better understood (no sense
committing an incompletely-understood struct to code yet, per this
project's "don't claim finished when only a placeholder exists" rule).

## Everything else (NPC/object data, weapons/armor equip effects, enemy
stat tables, shops, flags, event scripts)

UNKNOWN on the ROM side (see above — the *RAM* layout for stats/
inventory is now known, and the item/spell table's record shape is
partially characterized). Not yet investigated dynamically.

### Real courtyard room tested against all 255 bank-5 RLE records — negative (2026-08-09)

Now that both sides of the comparison are real (the RLE decode algorithm
VERIFIED, and the actual starting-courtyard room's real tile grid
VERIFIED by live ground truth — see "Room decompression format —
CRACKED" above and progress.md's room-correction entry), tested directly
whether the courtyard is itself one of the table's 255 records: RLE-
decoded all of them and compared each against the real room's top 4 rows
(one record's worth) under every possible constant tile-index offset
(0-199). Best match: 36/80 tiles (45%) — consistent with chance across
255 records x 200 offsets, not a real match (the room-decompression
finding itself hit 255/255 exact structural matches; this is nowhere
close). **Negative result**: this specific room is not one of the bank-5
table's records, at least not via a simple constant-offset reading —
consistent with the already-standing finding (rom-map.md "Dynamic
finding... fourth pass") that observed room draws go through the
hardcoded `$1E6F`/`$1E87`/`$1E9F` populate paths, not a table walk. The
bank-5 table's real in-game consumer (if any reachable in normal play)
remains unidentified.

### Real room-tile decompression pipeline, found (2026-08-09) — a THIRD, real, distinct system from the courtyard capture and the bank-5 table

Direct follow-up user instruction, after implementing the post-victory
scene's textboxes: *"der dialog nach dem sieg findet in einem neuem raum
statt. suche im code die raum transition (passiert in dem fall
automatisch) und implementiere sie in der app."* Traced live with
`tools/rom/watcher.py` through the real automatic transition (frame 1626
of the post-victory sequence, found by bisecting real per-frame BG
tilemap diffs for the first >100-cell change after the already-known
black-screen wipe).

**The real per-tile source: a 256-entry WRAM remap table.** The room-draw
routine (bank 0, `$04E8-$056B`) does NOT write raw source bytes as tile
IDs directly. **CORRECTED (2026-08-09, further pass) — see "Real
caller-side map of the tile-redraw pipeline" below**: the real room-draw
body is `$051D`-`$056B` specifically; `$04E8`-`$051C` is a separate,
unrelated enemy-behavior-state dispatcher that happens to sit
immediately before it in the ROM file — the range citation below should
be read as `$051D`-`$056B`, not the full `$04E8`-`$056B` span. For each
raw byte read from the room's source data, it
indexes a **256-byte lookup table staged at WRAM `$D070-$D16F`** (`LD
HL,0xD070 / LD C,A / LD B,0 / ADD HL,BC / LD C,(HL)` — table[byte] = real
tile ID) before drawing. This is a genuinely different, previously-
unknown encoding from both the courtyard's own hardcoded capture and the
bank-5 RLE table's algorithm (`byte&0x7F` repeat-count scheme) — a
per-byte remap, not a run-length scheme.

**The real source pointer and its ROM location.** `$05BB(A)` computes
`HL = ($D392:$D393) + A*6` — a 6-byte-strided lookup into a table whose
BASE address is itself a WRAM variable (`$D392`/`$D393`), not a fixed
constant — i.e. genuinely relocatable per room-load, not hardcoded per
room the way the courtyard was. Live-read during the real transition:
`$D392:$D393 = $46B0`, current MBC bank `8` — resolves to real ROM file
offset **`0x206B0`** (bank 8). Decoding a live-captured VRAM tilemap
confirmed this is a real, working pipeline (see below), though the exact
byte-to-6-bytes-per-row-pair layout at that ROM address was not further
hand-decoded this pass (see "What's still open" below).

**The real destination/blit machinery is NOT new** — it's the same
general system already found and documented for the black-screen wipe
earlier this session (`docs/reverse-engineering/combat.md`'s "Real
post-victory scene transition"): the cursor-relative tile-blit helper
(`$045D`/`$048C`) and the VRAM-write job queue (`$1E9F`, `$C8E8`/`$CEE8`).
Confirmed by watchpoint: the SAME call site (`$0491: CALL $1E9F`) fires
for both the blank-tile wipe (this session, earlier) and this real
room's non-blank tiles (this entry) — one general "draw a tile pair at
cursor+delta" primitive reused for both, not two separate systems.

**Live ground truth — captured, then CORRECTED (2026-08-09, same day).**
Captured the real, post-transition 20x16 BG tilemap directly
(`tools/rom/play_driver.py`'s `vram_tilemap`): tile IDs `0x80-0xAB`.
**First attempt was wrong**: rendered these against the general
environment tileset assuming the same flat `mapTable.tilesetFileOffset +
id*16` stride the bank-5 table uses — produced a plausible-*looking*
checkerboard room that this project shipped, but direct user testing
caught it as wrong ("der neue raum ist noch falsch"). Root cause, found
by re-reading the LIVE VRAM tile *pattern* bytes directly (not the
tilemap indices) and rendering those instead: this room's real tile
graphics are a separate, room-specific set assembled into VRAM slots
`0x80-0xAB`, NOT that flat tileset's own indices at that stride — using
the wrong base silently substituted different, wrong-but-real tile
graphics for the walls (rendering them as more checkerboard instead of
the real brick/stone border with a decorative arch at top-center).
**Corrected**: found each of the 44 used tiles' own real, individual ROM
offset by an exact 16-byte search of the live VRAM pattern data against
the ROM (same method `startRoom.tileOffsets` already used) — they live
scattered across `0x321B0-0x32630` (the same general ROM region as the
environment tileset, but not at its `id*16` stride). Re-rendered against
these explicit per-tile offsets and it now matches the real screenshot
exactly. See `rom_profiles.lua`'s `graphics.willyRoom.tileOffsets` and
`src/rendering/WillyRoomBackground.lua` (now uses `TileImage
.sheetFromOffsets`, the same explicit-offset primitive `startRoom` uses,
not `sheetFromIndices`'s flat-stride assumption). **Lesson for any
future room capture**: a rendered result "looking plausible" (real tile
IDs, coherent-looking pattern) is not sufficient confirmation that the
assumed tileset BASE is correct — cross-check against a live screenshot
or the live VRAM pattern bytes directly, not just against "does this
look like real game art."

**What's still open, stated precisely**: the raw byte layout at ROM
`0x206B0` (bank 8) and its exact mapping through the 6-bytes-per-A-step
stride into the final 20x16 grid was not hand-decoded — this project
captured and is using the known-correct DECODED RESULT (same honesty
level as `startRoom`), not a re-implementation of the compression
algorithm itself. Also open: how/where the `$D070` remap table and
`$D392`/`$D393` source pointer get their own values assigned per room
(not traced backward from this transition) — that would be the natural
next step if a THIRD room needs to be reached in the future, since it
would reveal whether this pipeline is the general "how any room loads"
system (a real candidate for finally explaining the still-unidentified
bank-5 table's purpose, or superseding it) or another special case.

**Answered (2026-08-09, same day): a real THIRD use of this exact
pipeline, confirming it as a genuine general mechanism, not a one-off.**
Direct follow-up user instruction: *"es muss weiterhin einen Mechanismus
geben der die Maps auf Events hin verändert oder andere Versionen
lädt... prüfe den ROM code."* Traced the starting courtyard's own real
barred-gate animation (direct user report: "ein tile [ist] offen wenn
der player beim bossfight den raum betritt und verschliesst sich danach
wieder... das tor nordlich... öffnet sich wenn ein boss den raum
betritt") by diffing the live BG tilemap frame-by-frame across the
entire real `battleIntro` sequence (`tools/rom/play_driver.py`, no
guessing about which frame to look at — every single frame checked).

**Real, VERIFIED finding**: at real frame 396 of the battle-intro
sequence (both in this project's own already-timed `battleIntro` data
and independently reproduced fresh this pass), a 4-row x 4-col block at
BG tilemap rows 0-3, columns 8-11 (the barred structure at the top of
the courtyard) changes from its closed tile IDs (`133`/`137`, both
already real, already in `startRoom.tileOffsets`) to a single open tile
ID (`149`, also already real, already in `startRoom.tileOffsets`) —
then, at real frame 461 (65 frames later, well before the enemy is
considered "appeared" at frame 471), reverts back to the closed IDs.
**This exactly matches the user's report**: the gate opens, then closes
again, trapping player and boss together.

**The code path is the SAME pipeline already found for the Willy room's
full load and the black-screen wipe** — confirmed by watchpoint, not
assumed: the writes land via `$1D87`/`$1D88` (the general safe-VRAM-byte
writer), called from `$049A`, itself inside `$0495` (a `$045D`-style
cursor-blit wrapper), called from a routine at ROM `0x0580` that is
**byte-for-byte the same real/decoded-tile-via-`$D070`-remap-table
structure** already disassembled for the Willy room's own draw routine
(same `$05BB` source-pointer addressing formula, same `LD HL,$D070`
remap lookup). Live-read at the exact call: WRAM `$D392`/`$D393` =
`$40B0`, current MBC bank `8`, resolving to real ROM file offset
**`0x200B0`** — a small, dedicated tile-patch blob, in the SAME bank
(8) as the Willy room's own full-room source (`0x206B0`), just much
smaller. Caller: ROM offset `0x2032A` (bank 8, local `$432D`).

**What this establishes, precisely**: this is now a real, three-times-
confirmed general mechanism — "point WRAM `$D392`/`$D393` (+ current
MBC bank) at a small ROM-resident tile-patch blob in bank 8, then call
the shared cursor-blit/`$D070`-remap/VRAM-queue drawing routine" is used
identically for (1) the full black-screen wipe, (2) the full Willy-room
load, and (3) this small 4x4-tile gate-open/close animation. Bank 8
reads as a real library of tile-patch blobs (room loads AND small
scripted tile events alike), all drawn through one shared primitive —
directly answering the "gibt es einen allgemeinen Mechanismus"
question with real evidence, not a guess.

**DONE (2026-08-09, further pass, task P4 continued)**: the visual gate-
open/close animation is now implemented (`GateAnimation.lua`, wired into
`BattleIntro.lua`, driven by a new `battleIntro.gate` entry in
`rom_profiles.lua`). Re-confirming this pass with a full per-frame VRAM
sweep (not just the tilemap-ID diff the original trace used) turned up
one more real, previously-unnoticed wrinkle: the real open tile's live
VRAM *pattern* (not just its tilemap ID, `149`) is 16 bytes of `0xFF` —
a genuine SOLID dark tile (2bpp palette index 3), not blank/transparent.
This was cross-checked against the already-known-correct
`startRoom.tileOffsets[133]`/`[137]` addressing formula (live VRAM vs.
their real ROM bytes, byte-for-byte match) before being trusted, to rule
out an addressing bug as the explanation for the surprising all-`0xFF`
content. No single ROM *offset* was found for this tile specifically —
plausibly because the small tile-patch blob (`0x200B0`) only needs to
repoint tilemap cells to an already-VRAM-resident tile slot, not load
new pixel data — so the renderer uses the live-captured literal pattern
bytes directly (see `rom_profiles.lua`'s `battleIntro.gate.
openTilePattern` and its doc comment) rather than a ROM-offset lookup,
the one real exception to this project's usual per-tile-offset
convention. Screenshot-verified end to end (closed bars visible before
frame 396, solid dark opening during 396-461, bars re-closed after).
The second half of the user's report — an *entrance* tile that opens
for the player walking in and re-closes afterward, separate from this
north gate — was still not located this pass (only the north-gate
open/close was found in the traced window); if it's real and reachable,
it likely goes through this exact same pipeline too, just with a
different source pointer/position, and would be the natural next thing
to look for.

### Real caller-side map of the tile-redraw pipeline — and a correction to the earlier `$04E8-$056B` claim (2026-08-09, further pass, task P4)

Direct follow-up per explicit instruction to keep working P4 "focus on
general mechanisms": rather than guess whether ordinary door transitions
use the same pipeline (no second reachable ordinary transition exists
in this project's playable slice to test directly), traced *every real
caller* of the already-known low-level primitives — `$045D`/`$048C`
(cursor-blit), `$04E8` (previously labeled as the room-draw routine's
own entry, see correction below), `$05BB` (source-addr formula), the
`$1D74`/`$1D86`/`$1D9E`/`$1D87` VRAM writers, the `$1DDA` queue-drain,
and the `$1E6F`/`$1E87`/`$1E9F`/`$1EB6` enqueue helpers — by scanning
the *entire ROM file* for literal `CALL nn` byte patterns targeting each
address (safe here because all of these routines are bank-0-resident,
i.e. always mapped at `$0000-$3FFF`, so an ordinary `CALL` reaches them
from any bank without needing the bank-trampoline machinery below).

**Correction (found by this scan, not assumed): the earlier
"`$04E8-$056B` is the room-draw routine" claim (this document, "Real
room-tile decompression pipeline" above) conflated two real, unrelated
systems that merely sit adjacent in the ROM file.** Disassembling the
whole range cleanly (`tools/rom/disasm.py`, not hand-counted hex — the
exact mistake this project's own disasm.py docstring warns about)
shows:

- **`$04E8`-`$051C`: NOT room-drawing at all.** A small family of
  bank-0-resident stubs (`$04E8`, `$04F4`, `$0511`, `$0517`, ...), each
  gated by `LD A,($D3E8) / CP $FF / RET Z` (the same real enemy-alive
  flag from the death-despawn trace — i.e. "only act if a real enemy is
  present"), each pushing a small constant (2, 3, 5, 4, ...) and tail-
  jumping (`JP`, not `CALL`) into `$1F64`. This is a real **enemy
  behavior-state dispatcher**, not a tile-drawing routine — see below.
- **`$051D`-`$056B`: the real tile-redraw/cursor-blit workhorse**
  (confirmed: this is what actually calls `$05BB`/`$048C`/reads the
  `$D070` remap table — the code this document's earlier entries were
  really describing). Two real entry points, `$051D` and `$056C`,
  **each independently called from bank 1 (3 real sites: `$469E`,
  `$46B8`, `$4741`) and bank 2 (3 real sites: `$22AE`, `$22B7`,
  `$241F`)** — direct `CALL`s, not through any dispatcher. The bank-1
  call sites loop it 8 and 10 times respectively (`INC B` / `CP 0x08` or
  `0x0A` / `JR C`), reading/writing the SAME already-known cursor state
  (`$C340`/`$C342`/`$C343`/`$C348`) — i.e. bank 1's own code uses this
  exact primitive to paint a strip of tiles one at a time, the same
  general shape as every other confirmed use (Willy-room load, black-
  screen wipe). **This is real, additional evidence that the pipeline
  is genuinely general infrastructure**, reused directly by at least 2
  more banks (1, 2) beyond the ones already traced in detail (8), even
  though what bank 1/2's specific screens *are* was not identified this
  pass (no in-game context for them has been reached yet).

**A second, real, separate general mechanism found along the way: enemy
behavior states are dispatched through this project's own
already-documented bank-calling trampoline** ("Bank-calling convention"
above, found in an earlier pass purely from map-table-loading
investigation). `$1F64` and `$1F93` (reached via the `$04E8`-family
stubs' tail-jumps) are two more real, live-confirmed instances of that
exact same trampoline shape (save `A`/`H`/`L` to `$C0B2-$C0B5`, push the
shared `$1FC2` return address, hardcode a hardware bank number into `A`
— `4` for `$1F64`, `9` for `$1F93` — `CALL $29FB`, then jump through
`$4000 + functionIndex*2`, the target bank's own local jump table).
**This ties two previously-separate investigation threads (map loading,
enemy behavior) into one confirmed, pervasive general mechanism**:
per-bank function tables reached via one shared trampoline, used for
multiple, unrelated subsystems — not a room-loading-specific trick.

**A third real general mechanism found the same way: `$0AE3`**
(previously only known as one step in the enemy-death/despawn chain,
`$4575 → $4425 → $0AE3`) **is itself a real, general per-event-slot
command dispatcher, called from 17 distinct sites spanning banks 0, 1,
2, 8, and 9** — not a despawn-specific routine. It reads a command byte
from each active slot's own data (a `$C200`-based, 16-byte-strided
table) and dispatches on the byte's **high nibble** to one of ~6 real
handlers (`0x10/0x80/0x90/0xD0 → $27E3`, `0x20 → $04E8` — i.e. the
enemy-behavior-state machine above, not tile-drawing, correcting this
pass's own earlier mid-investigation guess that it was — `0x30/0x60/
0x70 → $2BE6`, `0x40/0x50 → $2EF7`, `0xA0/0xB0 → $2D13`, `0xC0 →
$0285`; anything else is a real no-op). A genuinely general "per-slot
event/entity command interpreter," not specific to any one system.

**Live-verified, so this isn't left as an assumption: the courtyard
gate's own real call chain does NOT go through either dispatcher
above.** Watched the exact live moment the gate-open tile write lands
(`$1D88`, a memory watchpoint on the destination BG tilemap cell itself
— reliable regardless of which WRAM field triggers it, unlike guessing
at a source-pointer write) and read the real call stack at that instant:
it shows return address `$432E` (one byte after the already-documented
bank-8 caller `$432D`) sitting on the stack, with **no** trace of
`$0AE3`'s or `$1F64`/`$1F93`'s own return addresses anywhere on it. So
the gate is a **fourth**, independent real path into the same shared
low-level primitives — a direct bank-8-resident call chain, not routed
through either general dispatcher found this pass.

**Net picture, precisely stated**: there is no *single* general "room/
tile-transition" entry point in this ROM — there are (at least) four
real, independent ways code reaches the shared low-level tile-drawing
primitives (`$05BB`/`$048C`/`$D070`-remap/VRAM-write-queue): (1) bank 8's
own direct call chain (courtyard gate, Willy-room load, black-screen
wipe), (2) bank 1's own direct calls (a real, not-yet-identified use,
looped 8x/10x per call), (3) bank 2's own direct calls (also not yet
identified), and (4) indirectly, whatever eventually calls into the
`$0AE3`/trampoline-routed enemy-behavior-state machine, though that path
was shown this pass to reach a *different* system, not this one. **What
this answers about ordinary door transitions**: still not proven either
way (no second reachable ordinary transition exists to test directly),
but the shared low-level pipeline is now confirmed general enough, and
reached by different banks' own independent code often enough, that an
ordinary transition using it too (via a fifth, not-yet-found direct
call site, most plausibly in whichever bank holds overworld/dungeon
room code) is a well-supported expectation, not a hopeful guess — the
concrete next step is finding *that* bank's own code, not re-deriving
the pipeline itself again.

### ANSWERED: the real Willy-room north door DOES open, into a real second room — a genuine ordinary transition, found live (2026-08-09, further pass)

Direct correction from the user, who verified this personally in the
ROM: *"die tür öffnet einfach wenn man mittig dagegen läuft! ich habs
gerade im rom verifiziert."* This project's own earlier live testing
(this same pass) had failed to open the door dozens of times — the
real cause, found once retested with this hint: **every earlier
attempt approached the door off-center** (this project's own test
harness left the player drifted to real screen X `88`, outside the
door's own real walkable range, purely an artifact of the test
methodology's own repositioning probes — not a real gameplay
position). Once approached freshly centered (tested working at real X
`75`, `76`, `79`, `83`; confirmed NOT working at `88`), **the door opens
on the very first approach, every time** — fully deterministic, not
random, confirmed by exact reproduction of the same input sequence
twice with identical results.

**This is a real, third distinct room-transition mechanism, different
from both mechanisms already documented** (the `$D392`/`$D393`
relocatable-pointer pipeline; the direct bank-8 tile-patch call chain
found for the courtyard gate):

1. **The door tiles themselves flip** via a real tile-patch write
   (BG row0-1, cols8-11: `135,136,139,140`/`137,138,141,142` →
   `172,152,151,174`/`173,154,153,175`) — same general *style* as every
   other tile-patch event this project has found, but this pass did not
   re-confirm whether it specifically reuses the `$D392`/`$D393`
   pipeline or the direct bank-8 chain (an open detail, not the main
   finding).
2. **Immediately after, the real transition itself is a pure hardware
   background SCROLL, not a tile reload.** Watched `$FF42` (SCY) at
   real per-frame resolution: it jumps to `252` one frame after the
   door-tiles flip, then decrements by **exactly 4 real pixels every
   real frame** for 32 real frames, landing at exactly `128` (one full
   16-tile-row screen height) — the player's own OAM Y increases in
   perfect lockstep (also +4px/frame), i.e. **the player's position on
   the physical screen never changes during the scroll; the camera pans
   past them**, the classic GB "walk through a door, the room scrolls
   to reveal what's beyond" technique. `$D392`/`$D393` do NOT change
   during this scroll (stayed `$B0`/`$46` throughout) — **the new room's
   tile content was already sitting in VRAM, off-screen, at tilemap rows
   16-31, before the door ever opened** (most likely loaded once
   up-front alongside the original Willy-room's own 20x16 load, at the
   same time this project already found and implemented — a real,
   concrete lead for *how* to find the loader if this needs independent
   confirmation later: watch for a bigger-than-20x16 real VRAM write
   during that original room-load moment).
3. **A real, new textbox appears partway through what's now visible**
   (BG tilemap rows 16-23 of the pre-loaded content, i.e. what scrolls
   into view first): real, fully decoded text (same `TextDecoder`
   formula, live VRAM tile IDs, `tileID-48` convention already
   established for this scene) —
   `"Amanda! Das mit Willy tut mir leid.\nWir muessen hier raus!\nIch moechte nach Hause zu meinem kleinen Bruder!"`
   ("Amanda! I'm sorry about what happened with Willy. We have to get
   out of here! I want to go home to my little brother!") — a real,
   new named character ("Amanda"), not seen in any dialogue this
   project has decoded before.
4. **A real second room floor is revealed below the textbox** (tilemap
   rows 24-31): the same checkerboard floor tile IDs already known from
   `willyRoom` (`151`-`154`) plus several real, new tile IDs not seen
   before (`176`-`187` range) — a genuinely different room layout, not
   a copy of the Willy room.
5. **Two real new OAM sprites appear** the moment the door opens (tile
   IDs `72`/`74`/`76`/`78`/`104`/`106`, distinct from both the player's
   and Willy's own already-known tile IDs, palette attribute `0x30` —
   different from Willy's own `0x10`) — plausibly "Amanda" and a second
   character, not yet identified further.
6. **Real player movement works normally in the new room** once the
   dialogue closes and the scroll settles (tested all 4 directions,
   real position changes confirmed) — this is genuinely playable space,
   not a cutscene-only backdrop.

**This directly, finally answers task P4's own standing question**:
yes, ordinary (non-cutscene, player-triggered) room transitions are
real and now characterized end to end for at least one real case — a
position-gated door trigger leading into a real scroll transition, a
third genuine general mechanism alongside the two already documented.

**Not yet done, honestly scoped** (concrete next steps, not vague
follow-ups): (1) the door tiles' own real ROM source (which pipeline
patches them) was not re-traced this specific pass — a live watchpoint
on the door's own destination tilemap cells, the same technique already
used for the courtyard gate, would settle it directly; (2) ~~the new
room's own tile ROM offsets~~ **DONE (further pass, same day)** — all
12 new tile IDs and 8 new sprite tile IDs found via the same live-VRAM-
pattern-search technique (bank 8, `0x322xx-0x32efx` for tiles,
`0x22c4x`/`0x22e4x` for sprites) and implemented end to end (real
`secondRoom`/`secondRoomScene`/`secondRoomDialogue`/`doorScroll`
profile entries, three new phases in `VictorySequence.lua`, screenshot-
verified working); (3) the two new sprites' identity is still unknown
(their real tile/screen data is now found and rendered, just not who
they *are*); (4) the exact centered-X tolerance window's precise
boundaries were bracketed (works `75-83`, fails at `88`) but not pinned
to the single real pixel/tile boundary; (5) ~~whether there's more
beyond *this* second room~~ **ANSWERED (further pass, same day)** — see
below; (6) the real landing position in the new room after the
transition is this project's own reasonable, labeled placement choice,
not independently pixel-verified (live testing of the real ROM's own
landing spot was confounded by repeated collision retries during the
original investigation).

### Yes, it keeps going — a real THIRD and FOURTH room, and a FOURTH distinct transition mechanism (2026-08-09, further pass)

Direct follow-up per explicit user instruction ("weiter erkunden. es
gibt im neuen raum rechts ein ausgang (mittig) der in einen weiteren
raum führt. dort befindet sich oben rechts eine treppe die wiederum
weiter führt"). Both real, both found and characterized the same way as
every other room in this chain (live position sweep for the trigger,
per-frame register watch for the transition shape, live-VRAM-pattern
search for tile/sprite ROM offsets).

**The east exit (real room 3).** A position-gated trigger, same shape as
the north door but the OTHER real GB scroll axis: approach `secondRoom`'s
east wall roughly vertically centered (bracketed working at real screen
Y `64`-`65`; Y `16`/`32`/`48`/`80`/`96`/`112` all confirmed NOT to
trigger it — a much narrower real window than the north door's) and
walk into it. Real, clean, per-frame-watched transition: `$FF43` (SCX)
jumps from 0 and decrements by an exact 4 real pixels every real frame
for 40 frames, landing at exactly 160 (one full screen WIDTH this
time, not height) — the same "camera pans, player stays screen-fixed"
technique as the north door, just horizontal. `$D392`/`$D393` unchanged
throughout (`$B0`/`$46`, same as `secondRoom`) — room 3's content was
already VRAM-resident, same as room 2's was. Room 3 reuses most of
`secondRoom`'s own tileset (same bank 8 region) plus 8 more real, new
tile IDs (`188`-`195`) — two of which (`188`/`189`/`190`/`191`, at the
room's own real top-right, screen cols 16-17/rows 2-3) are the user-
reported "staircase." No new dialogue or sprites found in this room
(OAM showed only the player).

**The staircase (real room 4) — a DIFFERENT, FOURTH transition
mechanism, not another scroll.** Walking onto the top-right tiles
triggers a real, instant room change: `$D392`/`$D393` actually CHANGE
this time (`$B0`/`$46` → `$B0`/`$40` — a real, different source pointer,
confirming this is the original `$D392`/`$D393` relocatable-pointer
pipeline this project found first, back for a real third confirmed use)
and `SCX`/`SCY` both snap directly to `0` (no smooth pan — an instant
cut, not a scroll). Room 4 is visually and structurally different from
every room in this chain so far: a simple, repetitive 8-tile set,
mostly reusing the ALREADY-KNOWN `startRoom`/environment tileset (bank
12) — 6 of its 8 tile IDs matched `startRoom.tileOffsets`' own real ROM
bytes exactly (a real, clean cross-confirmation, not a coincidence) at
different local tile-ID numbers, same underlying ROM asset. Its most
common tile (dense across the whole top of the room) is a real, solid
all-`0xFF` pattern — the exact same "solid tile" signature already
found for the courtyard gate's open state, reinforcing that this really
is a deliberate ROM convention (a solid-fill tile), not a rendering
quirk specific to one screen. Reads, structurally, like the real
entrance to a much bigger open/outdoor area (the overworld) rather than
another contained interior room — a plausible, not yet confirmed,
interpretation.

**Net picture**: this project has now found and lived-traced FOUR real,
distinct room-transition mechanisms in this one ROM: (1) the
`$D392`/`$D393` relocatable-pointer pipeline (courtyard → Willy room,
and now Willy room → this 4th room); (2) the direct bank-8 tile-patch
call chain (the courtyard gate); (3) the vertical hardware scroll (the
north door, room 2 → room 3); (4) the horizontal hardware scroll (the
east exit, room 3 → room 4) — really the same mechanism as (3) on the
other axis, but worth naming separately since it was independently
re-confirmed, not assumed. **Not yet implemented in the app** — this
pass was investigation/documentation only, room 4's own tile ROM
offsets and the staircase trigger's exact working range were found but
not wired into `VictorySequence.lua`/`rom_profiles.lua` yet (a natural
next step, same shape as room 2/3's own implementation).

### The real scroll/transition engine, found by CODE not by empiricism — `$45C0`-`$4720`, WRAM `$C340`-`$C348` — VERIFIED (2026-08-09, further pass, explicit user direction)

Direct response to explicit user instruction: *"bitte versuche
verschiedene methoden das problem zu knacken. wenn nötig baue neue
debug tools. sollte eine methode nicht funktionieren reevaluiere deinen
ansatz selbstständig und versuche andere lösungen."* Two prior attempts
this same pass dead-ended (see the two entries directly above/before
this one, kept as honest negative results, not deleted): (a) watching
the door's own tile-flip write led back into the already-known tile-
redraw pipeline, a different, earlier-firing, cosmetic signal; (b)
watching `$FF42` (SCY) directly and reading the raw stack post-hoc
mis-attributed a return address to the wrong bank and disassembled
graphics data as if it were code.

**New tooling, built to fix (b) properly**: `tools/rom/calltrace.py`'s
`CallTracer` — instead of reading the stack *after* a watchpoint fires
and guessing which bank each saved return address belongs to, it decodes
the opcode at PC on *every single step* (via the already-existing,
bank-aware `rom_offset()`) and maintains a real call-frame stack live,
including hardware interrupt dispatch (PC jumping to `$40`/`$48`/`$50`/
`$58`/`$60` without a `CALL`/`RST` opcode driving it — GB games commonly
do exactly this kind of hardware-register write from inside the VBlank
handler, and this ROM is no exception, see below). Every frame this
produces is bank-resolved *at the moment it happened*, not reconstructed
afterward, so it cannot repeat mistake (b).

**Also needed: a reusable checkpoint, not a from-scratch playthrough
every attempt.** Reconstructing "Willy dead, standing centered in the
door gap" by blind button-mashing from a cold boot turned out to be
genuinely fragile across restarts of this investigation (the exact
frame counts from an earlier session were lost, and re-deriving them hit
several real, instructive dead ends: (1) OAM slot 8 — used by several of
this project's own earlier scripts as "the player sprite" — turns out to
get **reused for an unrelated status-bubble UI element** once genuinely
free-roaming and idle, stably showing a sentinel `(x=168,y=16)` that
looks like a player position but isn't; the real, always-correct
position source is WRAM `$C244`=Y, `$C245`=X (already documented,
correction dated 2026-08-09 earlier this file); (2) mashing the `A`
button to clear dialogue works *while dialogue is still showing*, but
the exact same mashing **re-triggers a real "X ist ein tapferer
Kämpfer" status bubble** once the player is actually free — over-mashing
past that point gets stuck in a self-inflicted loop that never resolves,
under-mashing leaves a real blocking dialogue box on screen forever (a
purely passive, zero-input wait sat frozen on a real, unadvanced
`"A und viele andere wurden gezwungen..."` story text box for the full
16,000-frame test budget); (3) the real room's lower approach corridor
has a genuine, narrow leftward wall right where earlier scripts' blind
walk-up happened to land (`x=88,y=96`) — `LEFT` is completely blocked
there (confirmed via a symmetric-timing test against `RIGHT`, which
moves freely with identical input), while the corridor is wide open a
short distance further up (`y<=81`), which is where the real door's
usable X range turned out to be centered (`x≈77`-`80`, close to but not
identical to this project's own earlier empirical `72`-`86` bracket).
Once found, this exact "player centered in the door gap, about to
trigger it" moment was saved via `core.save_raw_state()`/
`load_raw_state()` (works with plain Python `bytes`, round-trips
cleanly) to a real checkpoint file, so every further investigation
against this specific moment is instant and exactly reproducible instead
of re-fighting Willy and re-mashing dialogue every time.

**The actual trace, and why the first watch (on `$FF42` again) still
looked noisy.** Disassembling the real VBlank ISR chain (`$0040` →
`$0064` → `$00AA`) shows it's a **generic hardware-register shadow
flush**, copying WRAM shadow bytes to their real registers every single
frame regardless of what's happening: `$C0A5`→LCDC(`$FF40`),
`$C0AA`→OBP0, `$C0AB`→OBP1, `$C0AC`→BGP, **`$C0A6`→SCX(`$FF43`),
`$C0A7`→SCY(`$FF42`)**, `$C0A8`/`$C0A9`→WX/WY. Watching `$FF42` itself,
even with `CallTracer` active, therefore only ever shows *this* generic
flush routine as the immediate caller — informative about the ISR's own
shape, but not about the real decision. **Watching WRITES to the real
WRAM shadow byte `$C0A7` instead** (still using the exact same
checkpoint) caught the transition on the very first real hit, with a
call stack only 1 frame deep and immediately outside the ISR entirely:
`$468C → $46C4` (bank 1, file offsets identical to the CPU addresses
since bank 1's own base cancels the `$4000` CPU offset).

**`$46C4` is the shared "apply one frame of scroll" routine** —
general, not north-door-specific (confirmed: reached from at least 3
sibling call sites at `$45DA`, `$462E`, `$4680`, one per scroll
direction):

```
$46C4  LD A,(0xc0a6)   ; SCX shadow
$46C7  ADD A,E         ; += this frame's X delta (in E)
$46C8  LD (0xc0a6),A
$46CB  LD A,(0xc0a7)   ; SCY shadow
$46CE  ADD A,D         ; += this frame's Y delta (in D)
$46CF  LD (0xc0a7),A   ; <- the real write this pass's watchpoint caught
$46D2  LD A,E / ADD A,D / [sign-normalize to abs] -> C
$46DB  LD A,(0xc348) / ADD A,C / LD (0xc348),A   ; accumulate total scroll distance
$46E2  LD C,0xa0                                  ; default threshold 160
$46E4  XOR A / CP E                                ; if E==0 (a pure vertical scroll)...
$46E8    LD A,(0xc340) / <<3 (x8) -> C             ; ...threshold = C340 * 8 instead
$46EF  LD A,(0xc348) / CP C / RET C                ; not done yet -> return
$46F4  ; --- scroll finished, past this point ---
$46F6  CALL 0x044d                                 ; scratch-swap helper
$46F9  CALL 0x2ef1                                 ; another per-direction dispatch stub cluster
$46FC  LD A,(0xc0a2) / RES 0,1,3,2 / SWAP A / LD (0xc0a2),A ; LCDC shadow bits toggled
$470C  LD (0xc0a1),A                               ; a 2nd shadow copy, same new value
$470F  CALL 0x2926
$4712  LD A,0xff / LD (0xd394),A                    ; <- $D394=0xFF, see below
$4717  LD A,0x00 / LD (0xc341),A
```

immediately followed (`$471D` on) by what reads as the **start of a
fresh room-load setup**: zeroes `$C0A6`/`$C0A7` (scroll shadows back to
0), `$C342`/`$C343` (the already-documented real tilemap row/col scroll-
origin pair `$045D` reads), sets `$C344`/`$C345` to `0xFF`/`0xFF`
(sentinel), then loops a shared populate call (`$2426`) 8 times with an
incrementing counter — the same general shape as the already-documented
tile-redraw pipeline's own per-chunk loops.

**Confirmed live, at the real checkpoint, before triggering**: `$C340 =
0x10` (16 decimal). `16 * 8 = 128` — an **exact match for this
project's own already-VERIFIED real `totalPixels=128`** for the north
door's vertical scroll (captured independently, by a completely
different method, in the earlier live-register-watch pass). This is not
a coincidence or a re-derivation of the same fact two ways — it is a
**real, general, per-room WRAM field**: `$C340` reads as the current
room's height in tiles (16 = one full-screen room, matching the
already-VERIFIED "rooms are exactly one 20x16 screen" finding exactly),
and the scroll-completion threshold for a vertical transition is
`heightInTiles * 8` (tiles-to-pixels). This is the first concrete, code-
verified piece of **general, reusable per-room transition metadata**
found this project has found in live WRAM (as opposed to a hardcoded
per-instance pixel count in `rom_profiles.lua`) — a real candidate for
the kind of "real data structure, not empirical bracketing" the user
asked for, though only this one field (room height) is nailed down; the
paired width/other-direction threshold logic (a different, `SRL A`-based
computation seen in a sibling block, `$4613`-`$4620`) was traced far
enough to see it exists but not far enough to state its exact formula
with the same confidence — recorded here as a real, precise gap, not
glossed over.

Also newly found, same pass: **`$D394`, the byte immediately after the
already-known `$D392`/`$D393` room-source-pointer pair, is a real,
live-written flag** — set to `0xFF` exactly at scroll completion (was
`0x00` at the checkpoint, before triggering). Reads naturally as "room
pointer just changed / redraw needed," a plausible general "dirty" flag
for whatever consumes `$D392`/`$D393` next — not yet traced to a reader,
a concrete next step for whoever picks this thread back up.

**A third, independent instance of the project's own already-documented
"parameterized dispatch stub" convention was found in this same
region**: `$0429`-`$044A` (constants `2,3,4,5,6,7` → shared handler
`$1F06`) and `$2EF1`-`$2F09` (constants `0x1E,0x1F,0x25,0x26` → shared
handler `$1ED7`) both use the exact `PUSH AF / LD A,<small constant> /
JP <shared handler>` shape this project first found for the door's own
open/closed check (`$235B`/`$22FE` family) and later for the bank-
trampoline calling convention — strong, repeated confirmation that this
whole game leans on one consistent "small constant selects a case in a
shared handler, original `A` preserved via the stack" idiom throughout,
not a one-off. **Not traced further this pass** (`$1F06`/`$1ED7`
themselves) — a concrete next step, and very plausibly where the actual
"which room, in which direction" case-selection logic lives, given the
different constants passed from each of the ~4 sibling scroll-direction
call sites above.

**Honest scope of what this does and does not answer.** This IS a real,
code-verified account of the general *scroll mechanics* engine (how a
scroll accumulates, how completion is detected and generalized across
directions, what flips at the moment of completion) — directly useful,
general, per-room data (`$C340`) rather than an empirical pixel count.
It does NOT yet show *which room becomes the new `$D392`/`$D393` target*
after `$D394` gets marked dirty, nor does it show the original door-
open/collision check this session's earlier passes already traced
(`$235B`, the `$0F80` direction-dispatch table) tying together with
*this* mechanism — those two known pieces and this one are not yet
connected into one single, unbroken chain. **Not wired into
`rom_profiles.lua`/`VictorySequence.lua` this pass** — this was the
tracing/documentation half; teaching the engine to read `$C340`-style
real per-room data instead of the current empirical `totalPixels`
constants is the natural, concrete next step, same shape as every other
"found but not yet wired" entry above.

### `pixelsPerFrame=4` -- attempted to upgrade from empirical to code-verified, an honest, bounded negative (2026-08-13, "grafik code... scrolling fertig verdrahten" -> "pixelsPerFrame=4 zu Ende verifizieren")

Direct follow-up to the already-CODE-VERIFIED `totalPixels` formula (see
`rom_profiles.lua`'s own doc comment on `willyRoom`/`secondRoom`'s
`exits`): the one remaining field still flagged "matches... confirmed
via live SCX/SCY watches" rather than "the literal ROM constant" is
`pixelsPerFrame=4`. Found the real 4 call sites into the scroll-apply
routine (`$46C4`) by an exact byte search (`CD C4 46`) rather than
trusting the older, approximate addresses cited above: `$4593`,
`$45E3`, `$4636`, `$468C` (the earlier "$45DA/$462E/$4680" references
were nearby but not exact).

**Traced site 1 ($4593) back 5 real dispatch levels**: `LD A,0xB1 /
CALL $0429` → `$0429` is ITSELF one more real `PUSH AF / LD A,0x06 / JP
$1F06` trampoline (the same bank-crossing "preserve caller's A via the
stack" convention documented throughout this ROM) → `$1F06` is a real,
general cross-bank dispatcher (switches to bank 2 via `CALL $29FB`,
resolves `table[case*2]` at CPU `$4000` in that bank -- case 6 resolves
to `$43DD` -- then restores the caller's original `A`/`H`/`L` and
tail-jumps via the same "push the resolved pointer, then RET" trick
already documented elsewhere in this ROM) → bank 2's own case-6 handler
at `$43DD` DOES contain a real literal `LD C,0x04` early on -- but the
surrounding code (`LD C,0x04` / `CALL $435E` / `LD C,0x07` / `CALL
$435E` / a loop incrementing `C` from 8 up to `0x14`, each iteration
calling `$435E` again) reads as a generic per-frame loop over a
RANGE of small index values (`4, 7, 8..19`), not "compute and return
one scroll pixel delta."

**Honest, bounded stopping point**: could NOT cleanly confirm this `4`
is actually the real per-frame scroll delta `pixelsPerFrame` represents
-- the indirection chain here is real and traced accurately as far as
it goes, but doesn't resolve to the simple "return a delta" shape this
project's own already-clean `$46C4` trace has. Plausibly this whole
`$0429`/`$1F06`/case-6 chain is an UNRELATED subsystem this scroll call
site also happens to invoke alongside the actual delta computation
(which may be simpler and sit elsewhere, not yet found) -- or `$435E`/
the loop itself IS the real mechanism and this project simply didn't
trace far enough. Not resolved further this pass (a real, separate,
still-open question for whoever continues this) rather than guessed at.
`pixelsPerFrame=4` in `rom_profiles.lua` stays at its existing, honest
status -- empirically confirmed via live SCX/SCY register watches, NOT
newly upgraded to code-verified. No app code changed. Full Lua test
suite unaffected (no test touches this).

### Following `$1F06`/`$1ED7` — a real, honest, partly-negative continuation (2026-08-09, same day, direct "na dann los, weiter machen")

Picked up exactly the concrete next step named above. Real findings,
including one that reframes the whole remaining question:

**`$1F06`/`$1ED7` are two more real instances of the already-documented
bank-trampoline stub** (`PUSH AF`-save-original-A / `POP AF`-restore-as-
argument / hardcoded-bank `CALL $29FB` / function-index-into-`$4000`-
jump-table / restore-and-`RET`-as-`JP`) — `$1F06`→bank 2 (function index
6, called with argument `0xB2`/`0xB4`/`0xB8` from the 3 sibling scroll-
direction sites), `$1F35`→bank 3, `$1F64`→bank 4, `$1F93`→bank 9,
`$1ED7`→bank 1 (function index `0x1E`, called once at scroll
completion). A fourth confirmation that this whole game leans on one
single, consistent dispatch idiom everywhere, not case-by-case code.

**Bank 1 function `0x1E`** (resolved via its real jump-table entry, file
`0x403C` → CPU `$5D64`) is a generic **enemy-slot cleanup/search loop**
(6 iterations, condition via `$0A74`, dispatch via the already-known
general per-slot handler `$0AE3`) — plausible as "despawn this room's
enemies before switching," but NOT room-selection logic itself. Recorded
as a real, checked, negative result for this specific lead.

**Bank 2 function 6** (file `0x800C` → CPU `$43DD`) is also NOT simple
delta-arithmetic as guessed — it's a 13-iteration per-slot loop (`$435E`)
doing AABB-style bounds checks (`CP 0x12`/`CP 0x14` then a nested
compare against `$C000`-based records) — reads as a general collision/
proximity system, reused here rather than scroll-specific.

**A real, independently-confirmed structural finding, from watching the
INACTIVE BG tilemap buffer (the one `$9800`/`$9C00` NOT currently
selected by LCDC bit 3) for writes during the live scroll**: exactly one
write occurred in the ~32-frame scroll window this pass's watch budget
covered, at `$9C22`, reached through a real 5-level, 2-bank-crossing
call chain (`$219E→$1D1B→...→$386E→$3899→$1D5E`) that resolves, at its
base, to a generic **LCD-mode-gated "safe VRAM write" utility**
(`$1D5E`: busy-waits on `$FF41` bits 0-1 != 3, i.e. not mid-scanline-
render, before `LD (HL),B`) fed by a **screen-row/col-from-scroll-shadow
address helper** (`$3882`: `(row,col) = ($C0A9,$C0A8) >> 3 + (D,E)`) —
i.e. real, general "stream a newly-about-to-be-revealed tile into the
hidden tilemap buffer, timed safely against the LCD" infrastructure,
confirming the target room's content is populated incrementally *during*
the scroll (raster-synced double-buffering), not rendered all at once
either before or after.

**The one finding that reframes the open question itself: `$D392`/
`$D393` (the already-known room-source pointer) does NOT change during
this scroll transition** — confirmed both by a live before/after WRAM
dump (`0xB0`/`0x46` on both sides of a 200-frame window that fully
completed the scroll, `SCY` ending at the known real `128`) and by this
pass's whole trace never once writing to it. This is a real, meaningful
contrast with the room3→room4 **instant-cut** transition (already
VERIFIED in an earlier pass to genuinely change `$D392`/`$D393`, from
`$B0`/`$46` to `$B0`/`$40`). **Working hypothesis, not yet fully
proven**: scroll-type transitions stay within one continuous, already-
loaded source (the "target room" isn't a separate lookup at all for
these — the hardware pan just reveals more of what's already
resident/streaming from the same source context), while only cut-type
transitions perform a genuine "pick a different room" pointer swap. If
true, this would explain why 10+ passes of searching for one general
"room connectivity table" driving *every* transition kept coming up
empty for the scroll case specifically: there may not be one to find
there, because the connectivity is closer to "this specific door's code
path always continues into this specific neighboring content" (baked
into which bank/function-index gets dispatched per door, per the
trampoline idiom above) rather than a data table a general engine
consults at runtime. **Concrete next step, if this thread continues**:
stop looking for a general scroll-transition room table, and instead
re-focus any future table search specifically on the **cut**-type
transition (room3→room4, `$D392`/`$D393` genuinely changing) — that's
the one mechanism a real lookup table would actually need to serve.

**One real, checked negative result, recorded so it isn't retried**:
`$D398`/`$D399` (right after `$D392`-`$D394`) looked like a promising
"advancing read cursor" candidate from the before/after dump (changed
meaningfully during the scroll while neighboring bytes didn't) — watched
live with the bank-accurate tracer and it's a plain **`+1`-per-tick
counter with no call stack at all** (fires from true top-level mainline
code the tracer never saw a `CALL` into), i.e. a generic, ambient
timer/frame-counter unrelated to the door specifically, not a room-data
cursor. A real, useful negative, not a dead end silently dropped.

### BREAKTHROUGH: the real room table, found — bank 8, file `0x20000`, 11 bytes/record, and a real bytecode-interpreter dispatch loop (2026-08-10, direct user instruction "mach sofort 1 dann bei Erfolg 2 und am Ende 3")

Direct continuation of this same thread's own named next step: stop
searching for a room table behind the *scroll* mechanism (already
searched empty-handed across 10+ passes) and look specifically behind
the **cut** mechanism instead, since that's the one confirmed to
actually swap `$D392`/`$D393`. Reached the real staircase trigger
(`thirdRoom`, top-right) via a fresh, staged, checkpoint-driven replay
(door → scroll → secondRoom → east exit → scroll → thirdRoom →
staircase, each stage using live `$C244`/`$C245` position feedback and
its own saved `save_raw_state()` checkpoint, same discipline as the
earlier door investigation) and watched `$D392`/`$D393` with
`CallTracer`.

**The write happened after only 3 real call frames**, all bank-resolved
cleanly: `$04138→$02B70` (bank 1) → `$04395→$026DC` (bank 1) →
`$0270E→$01AF3` (bank 0). No stack mis-attribution risk this time — the
whole chain is shallow and immediate.

**`$01AF3` is the real, general "commit a new room" entry point** —
called with `HL`/`DE` as parameters, it writes:

```
$01af3  LD A,H / LD (0xd391),A     ; $D390/$D391 = HL  <- A pointer this project had never named before
$01af7  LD A,L / LD (0xd390),A
$01afb  LD A,D / LD (0xd393),A     ; $D392/$D393 = DE  <- the ALREADY-KNOWN room-source pointer
$01aff  LD A,E / LD (0xd392),A
$01b03  ; then zero-fills $D170.. and $D270.. (the ALREADY-KNOWN tile-
        ; redraw staging buffers) via a shared fill helper ($2B5D)
```

i.e. this genuinely is the root "load room" routine: it sets the room's
real tile-source pointer (already known from the door/scroll work) AND
a second, previously-unnamed pointer (`$D390`/`$D391`), then clears the
redraw staging area so the new room draws clean. A `$01B19`/`$01B2B`
sibling routine right after it walks a stream at `($D392:$D393) +
index*6`, reading records in a loop of 80 — consistent with the
already-known "per-room, up to 80 tile-chunk" redraw convention, now
tied to a real per-record stride (6 bytes) instead of just an
observed loop count.

**`$026DC` is the real table lookup feeding `$01AF3`'s `HL`/`DE`**:

```
$026dc  LD (0xc3f5),A         ; save the room-selector byte (real argument, see below)
$026e1  LD A,0x08 / CALL $29fb ; switch to bank 8 (the hardcoded-trampoline convention)
$026e7  LD HL,0x000b / CALL $2b7b  ; HL = 11 * A -- the ALREADY-KNOWN general multiply
                                    ; helper, stride supplied by the caller's own A
$026ed  LD DE,0x4000 / ADD HL,DE   ; HL = bank 8's local $4000 + 11*roomSelector
$026f1  LD C,(HL) / INC / LD B,(HL) / INC INC        ; bytes 0-1 -> BC
$026f6  LD E,(HL) / INC / LD D,(HL) / INC INC        ; bytes 3-4 -> DE
$026fb  LD A,(HL+) / LD ($C3F0),A                    ; byte 6 -> $C3F0 (the
                                                        ; ALREADY-KNOWN dynamic-bank flag!)
$026ff  LD A,(HL+) / LD H,(HL) / LD L,A               ; bytes 7-8 -> a pointer, staged
                                                        ; to $C3F2/$C3F3
$0270a  LD HL,0x4000 / ADD HL,BC                       ; HL_param = $4000 + (bytes0-1)
$0270e  CALL $1AF3                                     ; HL_param, DE(bytes3-4) -> commit
```

**This is a real, general, `roomSelector`-indexed table — exactly the
kind of data structure asked for from the start of this thread.**
Confirmed two independent ways: (1) statically dumped straight from the
ROM file (`file offset 0x20000 + roomSelector*11`, no emulator needed)
and (2) live-verified at the checkpoint — the actual selector used for
the real staircase was `roomSelector=1` (read from `$C3F5` right after),
whose static record is `00 00 00 b0 40 80 06 00 40 0e 11`, and every
field this pass's trace could independently cross-check matched
exactly: `$C3F0` (dynamic bank) live = `0x06` = record byte 6; `$D390`/
`$D391` live = `0x00`/`0x40` = `$4000 + (bytes 0-1 = 0x0000)`; `$D392`/
`$D393` live = `0xb0`/`0x40` = bytes 3-4 exactly. (`$C3F2`/`$C3F3` did
NOT match the record's own bytes 7-8 by the time it was read — real,
honestly-recorded loose end, most likely because that WRAM slot gets
reused for something unrelated later in the same frame window, not a
contradiction of the rest of the match.)

**Dumping the first 20 records (pure static ROM read, `roomSelector`
0-19) shows real, clean, meaningful structure, not noise**:

```
 0  00 00 00 b0 40 80 05 00 40 d7 3c
 1  00 00 00 b0 40 80 06 00 40 0e 11
 2  00 20 00 b0 46 6c 07 71 48 63 08
 3  00 20 00 b0 46 6c 07 00 40 71 08
 4  00 20 00 b0 46 6c 07 32 59 3e 08
 5  00 20 00 b0 46 6c 07 70 61 6f 07
 6  00 20 00 b0 46 6c 07 d0 75 e1 05
 7  00 40 c0 1a 4c 4a 07 b1 7b 09 04
 8  00 30 00 38 49 7b 06 9c 79 59 06
 9  00 30 00 38 49 7b 05 d7 7c 86 02
10  00 30 00 38 49 7b 06 65 6f 37 0a
11  00 30 00 38 49 7b 07 df 68 b8 06
12  00 30 00 38 49 7b 07 97 6f 39 06
13  00 30 00 38 49 7b 07 d4 50 5e 08
14  00 10 00 b0 43 80 06 fc 60 69 0e
15  00 10 00 b0 43 80 06 0e 51 ee 0f
```

Records 0-1 (both DE=`b0/40`) are the two `roomSelector`s that land on
`fourthRoom`'s real content (matches this pass's own live capture
exactly). Records 2-6 (five of them, all DE=`b0/46`) all land on the
SAME willyRoom/secondRoom/thirdRoom source pointer — real, direct
confirmation of last pass's "scroll transitions don't pick a different
room, they keep revealing the same underlying source" conclusion,
generalized: apparently *several* `roomSelector` values (five!) are
reserved for sub-states/sub-entries of that one continuous area, not
one-selector-per-room. Records 8-13 (six of them, DE=`38/49`) are
another such cluster; records 14-15 (DE=`b0/43`) another, smaller one —
the same "same low byte `0xb0`, family of high bytes `0x40/0x43/0x46`"
pattern repeats, suggesting a shared source region organized by high
byte, exactly matching the smooth-scroll-within-one-canvas picture.

**Traced one level further up (`$04395`, inside a small routine at
`$4387`) — real, strong evidence this whole area IS the general script/
event system the FFA-Disassembly project documented, not merely "a room
table"**:

```
$4387  PUSH DE
$4388  LD A,C / LD C,B / LD E,A / AND 0x0F / LD D,A   ; D = (operand C) & 0x0F
$438e  LD A,E / SWAP A / AND 0x0F / LD E,A             ; E = (operand C) >> 4
$4394  LD A,C                                          ; A = operand B (unchanged)
$4395  CALL $026DC                                     ; roomSelector = B, two more nibble
                                                          ; operands from C -> D,E
```

`$4387` takes its `roomSelector` **directly from register B**, a bare
operand, not computed — i.e. it reads exactly like a **"load room
N" bytecode opcode handler**, `B`/`C` being the two operand bytes of a
tiny script instruction (matching this project's own long-standing
"records mostly ~3 bytes" observation about the bank-5 table from many
passes ago — a 1-byte opcode + a room-index operand + a terminator is
*exactly* 3 bytes). Its caller, `$02B70`, is a **two-instruction
computed-jump stub**: `CALL $2B63` (resolve a handler address) / `JP HL`
(jump to it, not `CALL` — which is exactly why this project's own
`CallTracer` correctly shows no frame between `$02B70` and `$4387`: it's
a raw jump, not a call, precisely the mechanism a bytecode dispatcher
uses). `$02B63` itself is a clean, generic, textbook "index a jump table
by a byte, dereference, return the target" routine: `A*2, HL+=A
(16-bit table stride), HL = *HL`. **This is a real, general opcode-
dispatch loop** — the strongest concrete candidate this project has
found yet for the FFA-documented "real, general-purpose bytecode script
engine" itself (see "The real event/script system (their part3)"
above), not proof beyond doubt (the table base / opcode-fetch source
feeding `$02B70` was not traced this pass — a concrete next step), but
a direct structural match: fetch, table-dispatch, per-opcode operand
bytes taken straight from registers.

**Net effect on this whole multi-pass thread**: the original question —
"what real ROM data structure defines door/room connectivity" — now has
a real, concrete, doubly-verified (static + live) answer for the CUT
mechanism: **a real 11-byte-stride room table at bank 8 file `0x20000`**,
reached by loading a small literal `roomSelector` operand (baked into a
tiny bytecode instruction, not looked up from player position at this
level) and looking it up. The remaining open piece is one level higher:
which script, and which specific opcode/operand bytes, get chosen when
the player steps on the staircase tile — very plausibly tied to the
already-known direction-dispatch table (`$0F80`) and gate-check (`$235B`)
found earlier this session, not yet explicitly re-connected to this
chain with the new tracer. **Not wired into `rom_profiles.lua` this
pass** — this was tracing/documentation; teaching the app to read this
real table (even just for cross-checking/documenting the OTHER already-
implemented rooms' own `roomSelector`s) is a natural, concrete next
step.

### Verifying `$02B70` as the script/event interpreter — confirmed, with an honest precision correction (2026-08-10, same day, direct follow-up)

Traced one level further up from `$02B70` (the computed-jump dispatch
stub) to find its opcode-fetch source, per direct user instruction to
verify this specific hypothesis before moving on.

**`$04130`-`$04138`** (bank 1, immediately preceded by a run of literal
data bytes the disassembler correctly refuses to read as sensible code —
a real, useful confirmation in itself that code/data boundaries in this
bank are exactly where expected):

```
$4130  LD D,H / LD E,L      ; preserve caller's HL
$4132  LD A,(0xd499)         ; A = the real opcode/step index
$4135  LD HL,0x413C          ; HL = this table's own fixed base address
$4138  CALL $02B70           ; dispatch: table[A] via $02B63, JP to it (not CALL)
```

**`$D499` is a real, simple, monotonic step counter** — confirmed by
re-examining `$4387` (the room-load handler traced last section): every
opcode handler this project has looked at, regardless of what it does,
ends by `LD HL,0xD499 / INC (HL)` before returning — i.e. "handle the
current step, then advance to the next one," a plain sequential
walk, not an arbitrary jump/branch.

**Dumped the real jump table at `$413C`** (30 entries, pure static ROM
read): a clear, real, repeating structure — entries 0-13 and entries
14-25 are two near-identical 12-14-entry groups sharing most of their
actual handler addresses at the same relative offsets (`$4477`, `$448C`,
`$5D54`, `$99FA`, `$21D4`, `$70CD`, `$C92B` all reappear in both groups),
strongly consistent with "two similar authored phases of one longer
sequence" (plausibly: the willyRoom-departure phase, then the
secondRoom/thirdRoom-departure phase, matching this project's own real
room chain). **`$4387` (the room-load handler) appears at BOTH index 3
and index 16** — i.e. the same opcode/handler is legitimately reused
more than once within this one sequence, exactly matching this project's
own real, independently-found room chain having more than one
`cut`/room-load-style transition.

**Honest precision correction to last section's framing**: this is
real, working, general dispatch INFRASTRUCTURE (opcode byte → jump
table → handler, with per-opcode operands read straight from CPU
registers already staged by the caller) — but `$D499` incrementing
by a plain `+1` each step, walking one FIXED table (`$413C`, a literal
address, not itself read from a per-object pointer), reads more
precisely as **one bespoke, authored step-sequence for this specific
post-Willy-victory epilogue** than as a fully general "any door/NPC can
point to any arbitrary script" engine. The FFA-Disassembly project's own
documented shape ("scripts reached via an index into a script-pointer
table, not a direct address") implies an outer layer this pass did not
find: something that would pick *which* table (`$413C`-shaped) and
*which* starting step to run for a *given* trigger (a specific door, a
specific NPC) — not located this pass. **What this pass DOES confirm,
concretely**: the underlying dispatch mechanism (byte-indexed jump
table, `JP`-not-`CALL` handler entry, per-opcode register operands,
monotonic step advance) is real and matches the general shape
throughout; whether every door/NPC in the game gets its own such table
(fully data-driven, per the FFA docs) or whether some/most sequences are
more bespoke like this one remains open — a fair, undogmatic middle
ground between "just a room table" and "the full general engine,"
recorded honestly rather than overclaimed in either direction.

### Cross-check requested by the user: does the courtyard/pre-combat transition use the SAME mechanism? Yes — confirmed identical, plus a real bonus finding (2026-08-10, same day)

Direct follow-up to verify the bank8-table/`$01AF3` mechanism isn't
special-cased to the post-victory staircase. Located a real, early,
pre-combat room-pointer transition (well before Willy or combat even
appear) by bisecting real-frame checkpoints of the boot→battle-intro
sequence (faster and more reliable than a blind linear single-step scan,
which was tried first and abandoned after 100M+ steps without a hit —
recorded as a real, honest method note: for a transition this early in
a long boot sequence, checkpoint-bisection beats single-stepping from
scratch by orders of magnitude). Found `$D392`/`$D393` genuinely change
from `0x1a4c` to `0xb040` between real frame 2552 and 2592.

**Traced with `CallTracer` — the exact same call chain, address-for-
address**: `$04138→$02B70` → `$04395→$026DC` → `$0270E→$01AF3`. Not
merely "the same shape" — literally the identical instruction addresses
as the staircase trace, live-caught watching both halves of the pointer
change (`$D393`: `0x4c→0x40`, `$D392`: `→0xb0`). This is decisive
confirmation: **the bank-8 room table and its `$01AF3` commit routine
are real, general, reused infrastructure**, exercised identically by
both a late post-victory event (the staircase) and an early pre-combat
event (this one) — not a one-off special case built for a single
transition.

**A genuine bonus finding, not initially sought**: this early
transition's `roomSelector` (read from `$C3F5`) is **`1`** — the exact
same value used for the staircase transition in the earlier trace. Its
static record (`00 00 00 b0 40 80 06 00 40 0e 11`) is therefore the same
one already dumped. This means what this project's engine currently
calls `fourthRoom` (reached via the staircase, real tile pointer
`0xb040`) and this early pre-combat state are very plausibly **the same
underlying room data**, reused at two different points in the game's
real timeline — an honest, interesting structural note for
`rom_profiles.lua`'s own `fourthRoom` comments, not yet reconciled with
what's currently documented there (`fourthRoom` was captured and
implemented as if it were new, distinct content; this finding suggests
it may actually be a reused/earlier-seen area). Flagged here rather than
silently changed, since `fourthRoom`'s own live tile capture was a real,
independently-verified visual capture — the two facts (same pointer,
independently-captured distinct-looking tiles) aren't necessarily
contradictory (the same source pointer could still be interpreted
through a different remap-table/tileset context at each use, per the
already-documented `$D070` per-byte remap table), but they aren't yet
reconciled either.

**Net conclusion for this whole multi-day thread**: the original
question — "is there a real ROM data structure defining room
connectivity, not just empirical brackets" — is now answered with high
confidence for the general case, not just one instance: **yes, a real,
reused, `roomSelector`-indexed table (bank 8, file `0x20000`, 11 bytes/
record)**, fed by a dispatch mechanism (`$02B70`/`$02B63`, byte-indexed
jump table) whose specific instance driving both transitions traced this
session reads its opcode from a monotonic step counter (`$D499`) walking
one fixed table per authored sequence — confirmed general at the
table/commit-routine level, still open (per the earlier section's
honest framing) at the "is every door/NPC's own trigger fully data-
driven the same way" level.

### The bank-8 room table, fully documented — real length is 16, not 256 (2026-08-10, same day, "Bank-8-Tabelle vollständig dokumentieren")

Dumped all 256 possible `roomSelector` records (pure static ROM read,
`file 0x20000 + roomSelector*11`) to fully characterize the table, per
direct user request, before moving to other work.

**Real finding: the table is exactly 16 records long, not 256.** Byte 6
of each record (`$C3F0`, the "dynamic bank" field, confirmed live twice
this session) must be a valid MBC bank number for this ROM — and this
ROM is real, exactly **16 banks total** (`262144` bytes / `0x4000` =
16, confirmed from the file size directly). Records 0-15 all have
`byte6` in the valid `0x00`-`0x0F` range; **record 16 onward immediately
breaks** (`byte6=0x2E`, `0xC0`, `0xDC`, `0xFA`... — far past any real
bank number), and the byte content stops looking like this record shape
at all (`records 250-255` show repeating 2-byte fragments like `c0 07`
and `30 05` at arbitrary, non-11-byte-aligned offsets, reading much more
like packed bytecode/script data — plausibly the start of the REAL
per-door/per-NPC script blobs the earlier sections of this thread were
looking for, immediately following the room table in the same bank —
not decoded this pass, a real, concrete next-next-step if this thread
continues). **Lesson recorded plainly**: a table's real length has to be
independently bounded (here: by a *semantic* constraint on one of its
own fields, the real bank count) — blindly extending a confirmed stride
across an entire index byte's range (0-255) produces confident-looking
but wrong structure past the real end, exactly the kind of mistake this
project's own engineering discipline exists to catch before it's
written down as fact.

**The real, complete, 16-record table — every entry accounted for,
grouped by its real tile-source pointer (bytes 3-4, becomes
`$D392`/`$D393`)**:

| roomSelectors | `$D392`/`$D393` | Live-correlated to | Evidence |
|---|---|---|---|
| 0, 1 | `$B040` | the real pre-combat area (courtyard, before Willy/the gate) **and** this project's `fourthRoom` | roomSelector 1 live-confirmed via `CallTracer` for BOTH the earliest pre-combat transition and the post-victory staircase — genuinely the same underlying room, reused at two points in the real timeline (see previous section) |
| 2, 3, 4, 5, 6 | `$B046` | willyRoom/secondRoom/thirdRoom (the whole continuous scrollable chain this project already implemented) | `$D392`/`$D393`=`$B046` confirmed live at the door checkpoint (many times, this whole thread). **Honest gap**: unlike roomSelector `1` (independently confirmed via `$C3F5` in two separate `CallTracer` traces), no live trace this pass actually read `$C3F5` at the moment willyRoom's own pointer got set — which SPECIFIC one of these 5 roomSelectors fires for willyRoom itself (as opposed to secondRoom/thirdRoom's own sub-entries) is inferred from the shared pointer value, not independently confirmed the same rigorous way — flagged rather than silently assumed equal confidence |
| 7 | `$1A4C` | an even earlier pre-transition/black-screen placeholder (the value present right before the `$B040` transition fires) | live-observed as the "before" value in the courtyard-transition trace |
| 8, 9, 10, 11, 12, 13 | `$3849` | UNKNOWN — never reached in any playthrough this project has driven so far | static only |
| 14, 15 | `$B043` | UNKNOWN — same `$B0` low byte family as the willyRoom/fourthRoom pointers (`$B040`/`$B043`/`$B046` all share `$B0`), consistent with the already-documented "one shared source region, organized by high byte" picture, but not individually reached/confirmed live | static only |

Five distinct rooms/areas, 16 total entries — every `roomSelector` byte
0-15 accounted for, none wasted, matching this ROM's own general "round,
exact" conventions (16 banks, 16x16 map grid, 256-record bank-5 table)
rather than looking like an arbitrary cutoff.

**Not done this pass**: identifying `roomSelectors` 8-15's real rooms
(would need reaching them live, not yet attempted); decoding the
bytecode-shaped data immediately following the table (`$20AF6` onward)
that plausibly holds the real per-door/per-NPC scripts.

### Wiring the room table into the app, and an honest, bounded attempt at forcing the two unknown rooms live (2026-08-10, direct user instruction)

Direct follow-up: *"sind diese räume und übergänge (auch wenn sie nicht
live erlebt wurden) bereits in der app? wenn nicht baue das bitte
möglichst generisch ein."* Answer: the already-explored rooms
(`startRoom`/willyRoom family/`fourthRoom`) were already implemented;
the real ROM *table* connecting them was not — only prose in this
document. Built generically, matching this project's existing decoder
convention (`MapTable`/`ItemTable`):

- `rom_profiles.lua`'s new `roomSelectorTable` field: the real, verified
  16-record table (offsets, field meanings, and a `knownRooms` cross-
  reference), nothing hardcoded beyond real ROM values.
- `src/import/RoomSelectorTable.lua`: the generic (non-ROM-specific)
  decoder -- `decodeRecord`/`decodeAll`/`groupByTileSource` -- pure Lua,
  headlessly testable, same shape as `MapTable`.
- `tests/import/room_selector_table_test.lua`: synthetic-record tests
  plus a real-ROM test asserting the exact 16-record grouping this
  session found live (5 rooms, group sizes 2/5/1/6/2), and that every
  record's `dynamicBank` is a valid bank for this 16-bank ROM.
- Cross-tagged `willyRoom`/`secondRoom`/`thirdRoom`/`fourthRoom`/
  `startRoom` with their real `romRoomSelectors`, including the honest
  caveat on `willyRoom`'s own family (pointer-level confirmed, not
  individually re-verified per-selector via `$C3F5`) and the `fourthRoom`
  /`startRoom` "same pointer, partially-different capture, not merged"
  note.

**A real, bounded, honestly-reported attempt to live-capture
`unknownRoomA` (roomSelectors 8-13, pointer `$3849`) and `unknownRoomB`
(roomSelectors 14-15, `$B043`) — neither has a known natural in-game
trigger, so this pass tried forcing the real ROM routines directly**
(not fabricating data): from a stable checkpoint, used mGBA's native
struct access (`ffi.cast('struct SM83Core*', core._native.cpu)`) to set
`A`=the target `roomSelector`, push a safe return address onto the real
stack (written via `core._native.memory.wram`, since the high-level
Python binding's `core.memory[]` is read-only), and jump `PC` straight
into `$026DC` (skipping only the *how it's normally reached* part, not
faking what it does). **This worked cleanly**: both forced calls
returned properly (no crash), and `$D392`/`$D393` ended up exactly
matching the static table (`$3849` and `$B043` respectively) — real,
correct confirmation that this project's understanding of `$026DC`/
`$01AF3` is complete enough to *drive*, not just observe.

**The visible redraw did not follow, though — an honest negative, not
silently worked around.** Setting the pointer alone leaves the BG
tilemap showing the previous room's tiles (screenshot-confirmed).
Additionally force-calling the known tile-redraw workhorse (`$4690`,
bank 1 — loops 8x over `$051D`, the confirmed real "paint a tile strip"
primitive) with default `D`/`E`=0 also completed without crashing but
did not produce a clearly new, coherent room — the tile-ID set shown
shifted slightly for one attempt and not the other, consistent with a
partial/wrong-parameter redraw rather than a real capture. **Not
guessed at further or presented as real content** — the two unknown
rooms remain genuinely unknown visually; only their real, verified
`$D392`/`$D393` source pointers are recorded (in `rom_profiles.lua`'s
`roomSelectorTable.knownRooms`), not fabricated tile grids. The gap: the
full redraw pipeline needs correctly-derived `$C340` (room height) and
probably a properly-primed `$D070` remap table for the target room,
neither of which this pass reverse-engineered the *natural* setup
sequence for (only observed them already-correct in real, naturally-
reached rooms) — a concrete, precise next step if this thread continues,
not a vague "try harder."

### Direct user hypothesis, checked and confirmed: the multiple selectors per room family are real per-instance "states" — and they connect straight to the already-known door-check flag (2026-08-10, direct user question)

Direct user hypothesis: *"kann es sein das die beiden unbekannten räume
einfach so 'room states' sind... leicht veränderte versionen von räumen
die zwischensequenzen benutzen (tor auf zb)"* — checked against the real
record bytes, not guessed at.

**Real, clean structural confirmation.** Re-tabulating all 16 records
correctly by field: within every family, `offsetHL` (bytes 0-1), the
tile-source `DE` (bytes 3-4), `byte2`, and `byte5` are **byte-for-byte
identical** across every member — these four fields define "which
physical room." The remaining three fields — `dynamicBank` (byte 6),
`stagedPtr` (bytes 7-8), and the still-unread `bytes9-10` — **differ
distinctly on almost every single record**, including within families
that share the exact same room geometry. This is exactly the signature
the user's hypothesis predicts: one room, many small per-instance
payloads layered on top.

**Traced what `stagedPtr` actually does — and it lands directly on
the already-known door-check flag.** Continuing `$026DC` past the
`$01AF3` room-commit call (`$2711` onward): once the record's own
`dynamicBank` is switched to, `stagedPtr` (`$C3F2`/`$C3F3`) is
dereferenced and **4 real bytes are copied from it into `$C3F8`,
`$C3F9`, `$C3FA`, `$C3FB`** — then the pointer itself is advanced past
those 4 bytes and re-saved (a real stream-cursor pattern, not a one-shot
read). **`$C3F8` is not a new find — it's the exact same "enable/gate"
flag `$235B` (the door-open check, traced much earlier this session)
reads before proceeding.** This directly, concretely connects the two
previously-separate investigation threads this whole multi-day effort
has carried: the room-table/commit mechanism (`$026DC`/`$01AF3`, found
this session) and the door-open gate-check (`$235B`, found earlier) —
**the room table doesn't just pick a room, each individual selector
also stages a real, per-instance 4-byte control block that directly
feeds the door/gate-check flag machinery.** `$C3F9`-`$C3FB`'s own real
roles weren't traced this pass (a concrete next step), but `$C3F8`
alone is enough to confirm the mechanism: **yes, this is real, live
evidence that individual selectors within a room family are genuinely
"room states" in the sense the user described** — e.g. very plausibly
one selector's 4-byte block says "gate closed, don't dispatch the
open-door script yet" and a sibling selector's says "gate open, proceed"
— not proven down to that exact semantic without visualizing
`unknownRoomA`/`unknownRoomB`, but the *mechanism* (per-selector control
bytes feeding the real gate-check flag) is now real, traced code, not
speculation.

**Practical implication, stated precisely**: this refines, rather than
contradicts, everything already documented. `willyRoom` (2-6) and
`fourthRoom`/`startRoom` (0-1) being "the same underlying room, multiple
selectors" was already established; this pass adds *why* there are
multiple selectors per room at all (each carries its own small state/
trigger payload) and *what one piece of that payload plugs into* (the
real door-check flag). `unknownRoomA`/`unknownRoomB` remain visually
uncaptured, but are now understood not as "two more unexplored places"
so much as "two more room-state clusters of ALREADY-shaped rooms this
project just hasn't reached the trigger for" — consistent with there
being exactly 5 real *rooms* total in this whole table, not more.

### Searching for the real trigger mechanism into unknownRoomA/B (2026-08-10, direct user instruction "suche nach einem trigger mechanismus... ideallerweise ... allgemein")

Two real threads pursued this pass, one promising-but-incomplete, one a
clean, honest negative.

**A real, much bigger, more general-looking dispatch table found —
caller not yet located.** Scanning the whole ROM file for every literal
occurrence of the byte pattern `87 43` (the room-load handler `$4387`,
little-endian) found exactly 3 hits: the two already-known entries
inside the willy-epilogue's own `$413C` table, and **one genuinely new
one, in bank 8 at file `0x214ab`**. Dumping around it revealed a real,
dense, cleanly-structured table — NOT the short, ~30-entry, heavily-
repeating shape of `$413C`, but a **long, strictly climbing sequence**
(80+ real entries dumped, `$433F, $4340, $434B, $4355, ... $4387
(entry 8), ... $44B8, $44C2, ...`, still climbing with no end found in
this pass's dump window) — the general shape a REAL, full opcode-set
dispatch table would have (one handler per real opcode number, not one
step per authored cutscene beat). This is the strongest candidate found
yet for the actual GENERAL script-opcode table the FFA-Disassembly
project's docs describe, distinct from `$413C`'s own smaller, per-
sequence table. **Not yet connected to a caller**: a literal-immediate
search (`LD HL,<address>`) for whatever loads this table's own base
address into `HL` before dispatching (the same shape `$04130` uses for
`$413C`) found nothing — meaning it's reached some other way (a computed
address, a different addressing convention, or simply a caller this
pass's search pattern didn't match). **Concrete next step**: watch
executions landing on `PC == 0x4387` live (the bank-accurate `CallTracer`
already makes this cheap and reliable) during broader, more varied
gameplay than this project has driven so far — every hit's own call
stack would show exactly which contexts dispatch through this bigger
table, which should reveal both the caller and, hopefully, a context
using `roomSelector` 8-15.

**A real, honest exploration of `fourthRoom`'s own boundaries — no exit
found.** `fourthRoom` (reached via the staircase) had never been
explored past its entry point (rom-map.md previously said so outright).
Swept all 4 cardinal directions from the entry position, then a wider
X-position sweep along the reachable rows, watching `$D392`/`$D393` for
any change the whole time (the same real signal used for every other
confirmed exit this whole project). **Result: real, walkable floor
space exists (the room is NOT fully sealed — movement in several
directions genuinely succeeds, unlike a simple box), but no position
tested produced a `$D392`/`$D393` change** — i.e. no exit was found
within what this pass swept. This does not rule out an exit existing
somewhere untested (this project's own established lesson, repeated
several times this session: real exits have consistently needed a
narrow, specific position window, not "anywhere along an edge") — a
real, bounded negative, not proof of absence.

**Honest overall status**: the general TRIGGER mechanism for
`unknownRoomA`/`unknownRoomB` specifically is still not found. The new
long dispatch table is a real, concrete, promising lead toward "a
general mechanism" in the sense the user asked for, but this pass ran
out of a clean way to find its own caller; `fourthRoom`'s own exits, if
any, remain unlocated after a real, systematic (not exhaustive) search.

**One more real, cleanly-executed negative**: interacted with
`secondRoom`'s own two NPCs (`characterA`/`characterB`, never pressed
`A` near either before this pass) while single-stepping with
`CallTracer` watching every instruction for `PC == 0x4387` across ~5
million real steps (realistic frame-scale budgets, not the flawed
under-budgeted first attempt this pass also made and is recorded here
so it isn't silently swapped out — that first version single-stepped
only ~60-300 steps per simulated "frame," nowhere near the real ~15,000,
and correctly produced nothing meaningful; the corrected version used
proper ~20,000-step-per-frame budgets). **Zero hits at `$4387`** across
6 real `A`-taps and generous settle time. Either these NPCs have no
attached script (plausible — this project's own earlier "Frage" test
against Willy found the same empty result, explained by the FFA docs as
"no follower present"), or whatever they do doesn't route through the
room-load opcode specifically. A real, bounded negative, not a
successful trigger discovery.

### Exhausting the currently-reachable map for a trigger — a comprehensive, honest set of negatives (2026-08-10, same day, "ok dann mach das")

Continued directly from the previous section's proposed next step, plus
covering every other real, unexplored edge/interaction this project's
current playthrough can reach, before falling back to the static-table
lead:

- **`thirdRoom`'s other 3 edges** (only its staircase, NE corner, had
  ever been tested): swept west (multiple Y), south (multiple X), and
  north away from the staircase (multiple X), watching `$D392`/`$D393`.
  West reproduces the already-known reverse scroll back into
  `secondRoom` (same pointer, expected); south and north are real,
  simple walls — zero `SCX`/`SCY` change, zero pointer change, at every
  position tried.
- **`secondRoom`'s other 2 edges** (only its east exit had ever been
  tested): swept west and north the same way — same result, real walls,
  no change anywhere.
- **The real START menu** (never opened this whole session): a real,
  working menu (`Dinge`/`Magie`/`Waffe`/`Frage`, matching this project's
  own already-decoded item/weapon data) opens correctly, but touches
  neither `$D392`/`$D393` nor anything room-related — an overlay, not a
  room load, as expected structurally but not previously confirmed live.

**Honest conclusion**: every currently-reachable edge and interaction in
this project's whole explored map (courtyard → willyRoom → secondRoom →
thirdRoom → fourthRoom, all 4 sides of each room, the menu, the two
NPCs) has now been checked for a `$D392`/`$D393` change, and none beyond
the 3 already-known transitions were found. This is a real, meaningfully
bounded search, not proof of absence — but it does mean `unknownRoomA`/
`unknownRoomB` (roomSelectors 8-13/14-15) are very plausibly **not
reachable from this early-game slice at all**, and belong to later
content this project's own playthrough (a short tutorial/first-boss
sequence) simply hasn't unlocked. **Standing next step, unchanged from
before**: the newly-found ~80-entry dispatch table (bank 8, `$214AB`) is
still the most concrete remaining lead toward a genuinely general
trigger mechanism — finding what calls it (a live `PC==0x4387` watch
across whatever *new* game content becomes reachable in a future pass,
or a deeper static trace of its own addressing scheme) remains the real
open thread, not further exploration of the same already-mapped area.

### The new dispatch table's caller — a clean, methodologically-validated negative, and where this thread genuinely stands (2026-08-10, same day, "mach den nächsten schritt")

Pursued the concrete next step directly: find who reads the new ~80+
entry table (bank 8, `$549B`-ish once resolved to a CPU address) live,
using a segment-aware READ watchpoint (`WATCHPOINT_READ`, `segment=8`)
across every checkpoint this project has saved.

**Method validated first, not assumed** — watched READS on the
ALREADY-CONFIRMED `roomSelectorTable` (bank 8, CPU `$4000`+) during the
already-traced staircase transition: real hits landed exactly at `$400B`
/`$400C`/`$400E`/`$400F`/`$4011` — precisely the roomSelector=1 record's
own `offsetHL` and `tileSourcePointer` byte positions (`byte2`/`byte5`
correctly NOT hit, matching this project's own already-documented field-
consumption analysis). The segment-aware watch mechanism is confirmed
working and precise, not a guess.

**Applied to the new table (its first ~100 entries, 200 bytes) across
all 5 saved checkpoints** (`door_ready`, `room2_free`, `room3_free`,
`staircase_ready`, `fourthroom_free`), 800,000 real single-stepped
instructions each (4,000,000 total), holding `UP` throughout (a generic
"try to make something happen" input) — **zero hits, anywhere.**

**Honest conclusion for this whole sub-thread**: the new table is real
and structurally sound (confirmed via a clean static dump, hundreds of
entries, consistent small-handler-sized deltas), but genuinely is not
consulted by anything in the entire span of content this project's
playthrough can currently reach — consistent with, and now more
strongly supported than, the earlier session's honest conclusion that
`unknownRoomA`/`unknownRoomB` belong to later game content this short
tutorial/first-boss sequence hasn't unlocked. **This closes out the live
side of this investigation for now** — finding this table's real caller
(and by extension, a live trigger for the two still-unknown rooms) is
not achievable from currently-reachable content; it would need either
(a) a way to reach further game content than this project's playthrough
currently drives to, or (b) a purely static trace of the table's real
addressing scheme (how its base address is computed, since a literal
`LD HL,imm16` search already came up empty) — genuinely open, but a
different, harder kind of work than another live-exploration pass.

### P1 revisited: the "per-creature record" from an earlier pass IS the message-settings table found this session — and bytes +0x02/+0x03 are palette, not ATK/DEF (2026-08-10, direct user instruction "p1 nochmal")

Returning to P1 (real enemy stat table) after this session's extensive
text/message-system work revealed a real, exact structural unification:
an earlier pass's own "real per-creature record layout" (combat.md,
live-captured at file offset `0x108B9`, byte-for-byte `5, 2, 0, 0, 6,
22, ...`) is byte-identical to THIS session's own `messageID=16` record
in the message-settings table (bank 4, file `0x10739`, 24-byte
records). Not a coincidence — the same pointer (`$D438`/`$D439`
resolving to `$108B9`) drives both the HP-formula species-byte read
(traced in the earlier pass) and this session's reveal-speed/enemy-flag
tracing. **This is genuinely one unified "battle/event trigger" record**,
not two separate systems sharing an address by chance.

**Checked `+0x01` (the HP-formula species multiplier) against all 20
real records dumped this session**: values `25, 20, 59, 28, 75, 143,
111, 112, 121, 125, 146, 118, 187, 106, 218, 206, 2, 255, 81, 175` —
real, wide variation (the earlier pass only had the single data point
`2`, for record 16). Strong, independent confirmation this really is a
per-creature toughness/HP field, now seen varying realistically.

**Live-traced `+0x02`/`+0x03` (the leading ATK/DEF candidates from the
earlier pass) — found their real consumer, ruling out the ATK/DEF
hypothesis with code, not just absence of evidence.** Bank 4, file
`0x1057D`:

```
$10575  LD A,(0xD439) / LD D,A
$10579  LD A,(0xD438) / LD E,A   ; DE = the same real record pointer
$1057D  LD HL,0x0002 / ADD HL,DE
$10581  LD A,(HL+)                ; A = record[2] (+0x02)
$10583  CALL 0x45AE               ; shared conversion call
$10586  CALL 0x3D21               ; +0x02's own follow-up
$1058A  LD A,(HL)                 ; A = record[3] (+0x03, HL already advanced)
$1058B  CALL 0x45AE               ; same shared conversion call
$1058E  CALL 0x3D7D               ; +0x03's own, DIFFERENT follow-up
$10594  LD A,0xD0 / LD (0xC0AC),A ; writes a hardware-palette shadow register
```

Both bytes feed a shared "convert" routine (`$45AE`) then diverge into
their own distinct follow-ups, ending in a write to `$C0AC` — the same
real WRAM-shadow-register family as the already-known `$C0AA` (OBP1
shadow, confirmed elsewhere this project). **Reads as real per-creature
palette configuration** (a common, real technique: reuse one sprite
across multiple differently-colored enemy variants), not a combat
stat. Both are `0` for record 16 specifically (a plausible "use default
palette" sentinel); real variation exists across the other 19 records
(`+0x02`: `0x00`-`0xd2`, `+0x03`: `0x00`-`0xfa`), consistent with real
palette variety across creatures/scenes.

**Net effect on P1**: a real hypothesis (ATK/DEF at `+0x02`/`+0x03`)
retired with genuine, traced evidence rather than left open
indefinitely — real progress, even though it's a negative result for
the specific "found real ATK/DEF" goal. The remaining ~15
uncharacterized bytes of this same 24-byte record (see text.md) are
the next candidates if this thread continues; whether real per-species
ATK/DEF values exist at all, and if so where, remains genuinely
UNKNOWN — this record looks scoped to "message + one specific spawned
enemy's setup," which may simply not be where general combat stats
live in this ROM's own data model.

### P1 continued: $D6C3 identified as a real, computed PLAYER stat, not enemy data (2026-08-10, same day)

Direct continuation, next logical step after retiring the `+0x02`/
`+0x03` ATK/DEF hypothesis: traced the damage formula's own remaining
unexplained operand, `$D6C3` (the "defense-like read" `$50AC` combines
with a multiply and a PRNG roll), back to its source.

**Watched writes to `$D6C3` from title screen through 15 million
further real single-stepped instructions** (title → New Game confirm →
full name-entry/intro → battle-intro → mid-combat): only 2 real writes
the whole trace, both reassigning the exact same value (`6`) — a
stable, rarely-recomputed derived value, not something freshly loaded
per enemy encounter.

**Disassembled the write site (bank 2, file `0x9801`)**:

```
$97E0  LD A,(0xD7C0) / BIT 3,A / RET NZ   ; real flag-gated skip
$97E6  CALL 0x5BA7 / LD B,A                ; plausibly an equipment-bonus lookup
$97EA  LD A,(0xD7C2) / ADD A,B
$97EE  LD (0xD6C1),A / LD (0xD7DF),A       ; a SIBLING derived stat (attack?), mirrored
$97F4  LD A,(0xD6C0) / LD B,A
$97F8  LD A,(0xD6C2) / LD C,A
$97FC  LD A,(0xD7C1) / ADD A,B / ADD A,C
$9801  LD (0xD6C3),A / LD (0xD7E0),A       ; $D6C3 = $D7C1 + $D6C0 + $D6C2, mirrored
```

**A real "total stat = base + equipment bonus" computation** —
`$D7C0`/`$D7C1`/`$D7C2` sit exactly `+0x0E`/`+0x0F`/`+0x10` past the
already-VERIFIED player-stats struct base (`$D7B2`), immediately after
its own known `gold` field (`+0x0C`) — a clean, real struct extension,
not a coincidence of nearby addresses. **Cross-confirms an EARLIER
pass's own already-documented (but not previously traced-to-formula)
finding**: `Stats.lua`'s own doc comment already named `$D7C1`-`$D7C4`
as "stamina/power/wisdom/will" and `$D7DF`/`$D7E0` as "attack/defense
power" — this pass's fresh, independent live trace lands on exactly
those same two mirror addresses (`$D6C1`→`$D7DF`, `$D6C3`→`$D7E0`),
confirming defense = `stamina + equipment bonuses` and attack = `power
+ CALL $5BA7`'s own result — real formulas, not just known addresses.

**Net effect on P1**: `$D6C3` is the PLAYER's own computed defense, not
an enemy stat — resolves which side of the damage formula this operand
belongs to, and redirects the search for real per-*enemy* attack power
to the formula's other, still-untraced operand. `$5BA7` and `$D6C0`/
`$D6C2` (the two equipment-bonus inputs, plausibly tied to the already-
decoded `weaponTable` from task P5) are the concrete next leads if this
thread continues.

### P1 continued: the real damage formula $50AC, fully decoded (2026-08-10, same day)

Direct continuation: traced `$50AC` live during 3 real contact-damage
hits from the same enemy (real-time contact combat, not a menu battle),
capturing full CPU registers at entry and at the internal multiply call.

**Full real formula, decoded from a clean disassembly (bank 1, file
`0x050AC`)**:

```
$50AC  PUSH BC                     ; B = the ATTACKER's own stat (caller-supplied parameter)
$50AD  CALL 0x3D1D / LD E,A         ; E = $D6C3 (the DEFENDER's computed stat, see previous entry)
$50B3  POP BC
$50B5  LD L,B / LD H,0x00
$50B8  CALL 0x2BAB                  ; HL = B - E  (attacker stat - defender stat)
$50BB  JR NC,0x50C0 / LD HL,0x0000  ; clamp to 0 if defender's stat is higher (no borrow underflow)
$50C0  INC HL                       ; "base" = max(0, ATK-DEF) + 1
$50C2  CALL 0x2B1E                  ; A = a real PRNG draw (the already-known noise-table roll)
$50C7  CALL 0x2B7B                  ; HL = PRNG_byte * base  (16-bit product)
$50CA  SRL H / SRL H / LD L,H / LD H,0
                                     ; extract a coarse fraction of the product's high byte (>>2 on
                                     ; just the high byte, i.e. roughly product>>10)
$50D2  ADD HL,DE                    ; DE here = the earlier "base" value (pushed at $50C1)
                                     ; final HL = (scaled random bonus) + base
$50D4  RET Z                        ; 0 total -> no damage applied
$50D8  CALL 0x3E30                  ; apply HL as real damage (the already-known player-HP-subtract primitive)
```

**Real closed form**: `damage = floor((prngByte * base) / ~1024) +
base`, where `base = max(0, ATK - DEF) + 1`, `ATK` = the attacker's own
stat (register `B`, supplied by the caller), `DEF` = `$D6C3` (now
known, from the previous entry, to be the PLAYER's own computed
defense — confirming `$3E30`'s already-documented player-specific
scope: this whole `$50AC` chain is genuinely "damage the player takes
from an attacker," not a generic bidirectional formula). A real
"guaranteed base damage plus a small random bonus" shape, not a flat
number and not pure randomness either.

**Real, live-captured enemy ATK**: register `B` read `8` at entry for
all 3 real hits from the same live enemy (a stable, per-encounter
value, not re-randomized per hit) — **the first real, code-traced
enemy attack-power number this project has found**, cross-checked
against the already-known real per-hit damage this project measured
empirically for a different weapon/enemy pairing (`4`, see
`Enemy.PLAYER_ATTACK_DAMAGE`) — plausible orders of magnitude for an
early-game encounter, not confirmed identical since these are different
real quantities (this is damage TO the player, that was damage FROM
the player).

**Not resolved this pass**: `B`'s own real source (which WRAM address
or table holds "8" for this specific enemy) — the trace back from
`$50AC` lands on the same bank-trampoline family (`$29FB`→`$1EEF`-ish→
`$1F05`→`$50AC`) used pervasively elsewhere this session, with no
literal `CALL $50AC` anywhere in the ROM (dispatched only). Finding
`B`'s exact source would need tracing one level further back through
that same trampoline — a concrete, well-defined next step, same shape
as several already resolved this session, just not reached this pass.

### P1 continued: a real, general entity-command dispatcher found (command 0xC9 = attack) — but its exact live path not confirmed (2026-08-10, same day)

Direct continuation, tracing register `B`'s (the real enemy-ATK
parameter) own source. Found `$50AC`'s real dispatch entry point: bank
1's own local jump table, function index `7` (file `0x400E`), reached
via a real stub (`PUSH AF / LD A,0x07 / JP $1ED7`, file `0x256`) — the
same shared trampoline-stub convention used throughout this session.

**Statically found exactly 3 real callers of that stub** (`CALL
0x0256`, file `0xC6EA`/bank 3, `0x1047A`/bank 4, `0x24436`/bank 9).
**Disassembling the bank-4 one (file `0x1047A`) revealed a genuinely
new, general structure**: a real per-entity **command dispatcher**
(bank 4, `~$10446`) that switches on a command byte — `0xC9` is the
real "perform an attack" command. Its handler:

```
$1045E  LD A,(0xD3EB) / CP 0x00 / JR NZ,<no-op>   ; a real gate flag
$10465  LD A,C / CALL $42E6                        ; resolve THIS entity's own slot in the
                                                      ; already-known $D442 (14-entry, 6-byte-
                                                      ; stride) WRAM table, by a real linear
                                                      ; search ($42E6 itself, bank 4, confirmed
                                                      ; by direct disassembly: LD B,14 / LD HL,
                                                      ; $D442 / LD DE,6 / CP (HL) / loop)
$10469  LD DE,1 / ADD HL,DE / LD E,(HL) / INC HL / LD D,(HL)
                                                     ; DE = a 16-bit POINTER read from
                                                      ; (matchedSlot + 1) -- i.e. each $D442
                                                      ; entry holds its own real per-entity
                                                      ; stat-record pointer, not raw stats inline
$10470  LD HL,3 / ADD HL,DE / LD B,(HL)              ; B = *(pointer + 3)  <- real ATK
$10475  LD HL,6 / ADD HL,DE / LD C,(HL)              ; C = *(pointer + 6)  <- a second real field
$1047A  CALL $0256                                   ; dispatch into $50AC with B (ATK), C
```

**This is a real, general, distinct structure from the message-settings
table** (a genuine per-entity record, pointed to FROM the $D442 slot
table, with real fields at `+3`=ATK and `+6`=(unidentified, `C`) — a
strong, structurally clean candidate for the actual "enemy stat block"
this whole task has been searching for.

**Honest limit reached, not glossed over**: live-watched all 3 known
call sites (bank-resolved correctly) during the exact same real contact-
damage encounter that reliably reproduces the `$50AC`/`B=8` hit (twice,
step `73021` and `263466`) — **none of the 3 fired** before `$50AC`
was reached. Either a 4th, unfound call site exists (the stub could
also be reached via a bare `LD A,7 / JP $1ED7` without the `PUSH AF`
prefix my search required, or through yet another indirection this
session's tooling doesn't cover), or this specific live encounter's
real `B=8` comes from a genuinely different mechanism than the one just
decoded. **Recorded honestly**: the `$42E6`/`$D442`-pointer structure
above is real, live-confirmed code (not speculative), but is NOT yet
confirmed as the actual source of the specific `B=8` this project has
live-measured — a precise, bounded gap for whoever continues this
thread, not a claimed finding stretched past its evidence.

### P1 resolved: the "gap" above was a tooling bug, not a real negative — the bank-4 entity-command dispatcher IS the live path (2026-08-10, same day)

Went the last mile per explicit instruction. Two independent negative
watches (`trace_real_atk_record.py` and a follow-up) had compared
`cpu.pc == 0x1047A` — but `0x1047A` (`66682`) is a **file offset**
(bank-4-resolved), not a valid CPU `PC` value (`PC` is 16-bit, max
`0xFFFF` = `65535`). That comparison could *never* match; the "none of
the 3 call sites fired" conclusion was a false negative from comparing
the wrong address space, not a real absence.

Confirmed by rebuilding the live trace two independent ways:

1. **`tools/rom/calltrace.py`'s `CallTracer`**, run across the same
   `reach_combat()` encounter, recording every real CALL/RET event up
   to the moment `PC==0x50AC` (step `73021`, `B=0x08`). The tail of
   the chronological event log shows, in order:
   ```
   CALL at PC 0x4466 (0x10466) -> PC 0x42e6      ; $D442 slot search
   RET  at PC 0x42ef (0x102ef) -> PC 0x4469
   CALL at PC 0x447a (0x1047a) -> PC 0x0256      ; <- the "missing" call site,
                                                     firing exactly as disassembled
   CALL at PC 0x1eec (0x01eec) -> PC 0x29fb      ; bank-switch to bank 1
   RET  at PC 0x2a09 (0x02a09) -> PC 0x1eef
   RET  at PC 0x1f05 (0x01f05) -> PC 0x50ac      ; trampoline unwinds into $50AC
   ```
   `PC 0x447a` **is** the bank-4 call site — its CPU address, not its
   file offset (`0x1047A` bank-resolves to CPU `$447A`: bank 4 local
   `$047A` + the `$4000` switchable-bank window base).

2. **A corrected direct watch** (`cpu.pc == 0x447A`, fixed address
   space) during the same encounter, twice: step `72982` and `263427`,
   both times landing exactly on the known dispatcher CALL site with
   `B=0x08` (matches `$50AC`'s live `B` both times) and a real,
   resolved per-entity record pointer:
   ```
   step=72982:  DE=0x4d19  B=0x08  C=0x00  bank=4  -> file 0x10d19
   step=263427: DE=0x4d21  B=0x08  C=0x00  bank=4  -> file 0x10d21
   ```
   (the two pointers are exactly 8 bytes apart — two adjacent slots in
   the same 8-byte-stride species table, both holding the same enemy
   species, matching two separate contact hits against the same enemy)

**The real per-species combat record, finally located and dumped**
(bank 4, file `0x10c80`–`0x10df0`, CPU `$4c80`–`$4df0`, 8-byte stride,
~34 rows / at least 11 distinct species patterns, several species
occupying multiple consecutive identical slots):

```
file 0x10c80  00 20 90 00 8c 02 02 00
file 0x10c90  00 20 ff 00 8c 41 32 00   (x6)
file 0x10cc0  00 20 90 00 21 0a 14 00
file 0x10cc8  00 20 ff 00 21 0c 1e 00   (x9)
file 0x10d18  00 20 00 00 08 02 02 00   (x4)  <- our traced enemy
file 0x10d38  00 20 00 00 00 03 02 00   (x2)
file 0x10d48  00 20 92 00 bc 45 3a 00   (x6)
file 0x10d78  00 20 ff 00 bc 45 3a 00   (x2)
file 0x10d88  00 20 90 00 4d 04 08 00
file 0x10d90  00 20 ff 00 4d 01 01 00   (x6)
file 0x10dc0  00 20 f0 00 79 28 35 00   (x6)
file 0x10df0  <different byte pattern -- table ends here>
```

The `$D442`-slot pointer (read via `$42E6`'s linear search, then
`(matchedSlot+1)`) points **1 byte past** each row's natural 8-byte
file alignment — i.e. the dispatcher's `DE` for our enemy is `0x10d19`,
one byte into the row printed as `0x10d18`. Relative to that real
pointer (`DE+0`..`DE+7`, matching the dispatcher's own `+3`/`+6`
reads), the row fields above map to:

- row-relative `+1` (`0x20`, decimal `32`) — **constant across every
  species observed**, not yet explained (shared header/flag byte, or
  coincidence across this particular sample of early-game enemies).
- row-relative `+2` — varies by species (`0x90`, `0xff`, `0x00`,
  `0x92`, `0x4d`, `0xf0`, ...) — a real, species-varying byte,
  unidentified.
- row-relative `+3` — **constant `0x00`** across every species observed.
- row-relative `+4` = **`DE+3` = ATK, CODE- AND LIVE-CONFIRMED**: our
  traced enemy's value is `0x08`, matching the live `B` register at
  `$50AC` exactly, twice, independently.
- row-relative `+5` = `DE+4` — varies (`0x02`,`0x41`,`0x0a`,`0x0c`,
  `0x02`,`0x03`,`0x45`,`0x45`,`0x04`,`0x01`,`0x28`) — a real,
  species-varying field; **DEF candidate**, not yet confirmed live
  (nothing in the traced `$50AC` path reads it — it's read as `C` via
  the dispatcher's `+6`... see below).
- row-relative `+6` = `DE+5` — varies similarly; a second real,
  species-varying field, also unconfirmed live.
- row-relative `+7` = `DE+6` = **`C`, CODE- AND LIVE-CONFIRMED as
  `0x00`** for our enemy (matches the dispatcher's `LD HL,6 / ADD
  HL,DE / LD C,(HL)` and the live capture) — `C` is passed into `$50AC`
  but, per the already-fully-decoded formula, `$50AC` never reads `C`
  at all (only `B` and `$D6C3`) — so this field's real purpose is
  still open (possibly used by a *different* command in the same
  dispatcher, e.g. a defense/magic command, not the `0xC9` attack path).

**Net result**: the "last mile" is closed. The real, live, code-
confirmed path for this project's reproducible test encounter is bank
4's entity-command dispatcher (`$4466`→`$447A`, file `0x10446`
onward) → stub `$0256` → `$50AC`. Enemy ATK = row-relative `+4`
(`DE+3`) of an 8-byte, ~11-species table at bank 4 file `0x10c80`–
`0x10df0`, confirmed live as `0x08` for the tutorial enemy. This is a
real, general, structurally distinct "enemy species stat table" — not
the message-settings table, not the room table. DEF-for-enemies is
still not conclusively identified (best candidates: row-relative `+5`
or `+6`, i.e. `DE+4`/`DE+5`, unconfirmed live since the traced
encounter's own damage formula never reads them).

## P5 (task "5"): the secondRoom NPCs are NOT placed via a fixed table — they're procedurally randomized (2026-08-10)

Direct instruction ("dann geh 1 an und dann 5"), continuing the P4 map/
room construction-sites review's #5 item ("no general object/NPC
placement format found"). Investigated live from `door_ready.state`
(saved checkpoint, just before the real north-door scroll into
secondRoom), watching the two known NPC slots' entity-struct fields
(`$C200 + slot*16`) with a real write-watchpoint, then a bank-accurate
`CallTracer` at the exact spawn moment.

**Real finding #1: NPCs use the SAME generic entity-struct system as
the player's own body parts and enemies**, not a separate/bespoke NPC
mechanism. Confirmed live: `characterA`/`characterB` occupy struct
slots 7 and 8 (`$C270`/`$C280`), with the standard struct layout
already documented for enemies (byte 0 = alive/type flag, bytes 4-5 =
position, bytes 8-9 = OAM-shadow pointer).

**Real finding #2: a real, general "spawn N entities" primitive,
`$42BD` (bank 3), is reached via TWO structurally different loops in
this same room's load sequence** — both real, both confirmed live:

1. **A literal fixed-position table walk** (`$c52a`-`$c547`, bank 3):
   walks a small table two bytes at a time (`DE` = the next entity's
   position), calling `$42BD` once per entry, stopping on a real
   `0x8080` end-of-list sentinel (`D==0x80 OR E==0x80`) or once a count
   register (`B`) hits zero. Live-observed spawning 2 *other* entities
   this way (`DE=0x2020`, then `DE=0x1F24`) — plausibly room decoration/
   fixtures, not `characterA`/`characterB`.
2. **A randomized-placement loop** (`$c54b`-`$c55c`, bank 3) — THIS is
   the one that actually placed both tracked NPCs, confirmed via
   `CallTracer`'s call stack at the exact WRAM-write instant for both:
   - `$44CD` (bank 3): calls the already-known noise-table PRNG
     (`$2B1E`, the same one combat's HP/damage formulas use) twice,
     rejection-sampling each draw's low nibble into two small ranges
     (`D`: real values 2-12, `E`: real values 2-16 — confirmed live,
     `D=0x0B`/`E=0x0C` for `characterA`'s own draw) — a real random
     offset pair, not a fixed position.
   - `$4488` (bank 3): compares that offset against a held reference
     point (`H`/`L`, live-observed constant at `$789A` across the whole
     placement of both NPCs) on both axes, rejecting (loop rerolls via
     `JR Z` back to `$44CD`) if within a real threshold of 4 either
     way — a genuine minimum-distance/no-overlap check. Live-confirmed
     accept signal: `A=0xFF` right before the loop proceeds to spawn.
   - Only once accepted does the loop `CALL $42BD` (the same primitive
     as the fixed-table path) — final written position (`$68`/`104`
     for `characterA`) differs from the raw PRNG offset (`0x0B`/`0x0C`),
     confirming SOME transformation (offset applied to an anchor, not
     written raw) — the exact formula is NOT yet decoded, an honest
     remaining gap.

**Verification attempted, inconclusive by construction, not a
contradiction**: replayed the identical save-state + identical input
sequence 3 times, and with varied idle delays (0/137/401/900 steps)
before the walk — all produced IDENTICAL final NPC positions. This
does NOT contradict the randomization finding: this project's PRNG is
a deterministic advancing-index noise table (already documented for
combat), and identical replays from an identical starting state with
identical inputs necessarily consume the exact same PRNG draws — real
run-to-run variation would require a genuinely different play history
before reaching this point (different frame timing elsewhee, different
prior PRNG consumption), not just a different idle delay at
this late a point. The CODE-level evidence (the live `CALL $2B1E`
inside the confirmed spawn call chain, register-traced end to end) is
the real basis for this finding, not the (expectedly negative) replay
test.

**Practical implication**: `rom_profiles.lua`'s `scene.characterA`/
`.characterB` `screenX`/`screenY` fields are a real, live-captured
single sample — NOT a stable, ROM-authored fixed position. Corrected
in that file's own doc comment rather than left implying otherwise.

## THE real event/script interpreter — FOUND, FULLY DECODED (2026-08-10)

Direct instruction ("versuche es vollständig zu entschlüsseln und zu
implementieren"), picking up exactly where the "0xFE-vs-0x04" honest
gap and the "bank 2 function 51, not traced further" gap were left.
Traced live from `pre_kaempfe_box.state`. **This closes the central
question this whole multi-session investigation has been circling**:
yes, there is a real, general, byte-code-style script/event
interpreter, and its full fetch-dispatch mechanism is now understood
end to end, live-verified at every step.

**The real opcode-fetch primitive, `$3727` (bank 0, fixed, always
mapped)**:
```
$3727  LD A,(HL+)          ; A = *HL (the next opcode byte), HL advances --
                             ; the classic bytecode fetch-and-advance shape
$3728  LD (0xD85A),A        ; $D85A = the CURRENT opcode (real WRAM byte)
$372B  PUSH AF
$372C  LD A,H / LD (0xD8B7),A
$3730  LD A,L / LD (0xD8B6),A   ; cache the ADVANCED HL into $D8B6/$D8B7 --
                                  ; the persistent per-script read cursor
$3734  POP AF
$3735  RET
```
Live-confirmed as the real, GENERAL fetch site (not a one-off): a
write-watchpoint on `$D85A` across a ~370,000-step trace (holding UP
from `pre_kaempfe_box.state` through the real "Kaempfe!" trigger) found
this exact site (`$372B`, the tail of `$3727`) writing MANY DIFFERENT
values over time — `4, 60, 70, 176, 240, 248, 249, 254` — i.e. genuinely
walking a real, varied opcode stream, not a hardcoded per-call-site
constant. (A DIFFERENT site, `$36DE`, only ever writes `4` — that one
turned out to be a specialized caller for a DIFFERENT purpose, the
text-typewriter tick re-invoking "process next character" each reveal
step, not the general interpreter loop — see below.)

**The real opcode dispatch table — bank 2, file `0x8576`, 256 records
× 2 bytes, indexed by `$D85A`**. Reached via the already-known bank-
trampoline convention: `$3165` = `PUSH AF / LD A,0x33 / JP $1F06`
(function index 51, bank 2's own trampoline) → bank 2's real function
51 (file `0x8567`):
```
$4567  LD A,(0xD85A)       ; A = the current opcode
$456A  LD C,A / LD B,0x00
$456D  LD HL,0x4576         ; HL = the real table's own base (right after
                              ; this function's own code -- file 0x8576)
$4570  ADD HL,BC / ADD HL,BC ; HL = table + 2*opcode
$4572  LD A,(HL+) / LD H,(HL) / LD L,A   ; HL = table[opcode] (LE 16-bit)
$4575  RET
```
**All 256 entries decoded and are valid CPU code-pointer values** (file
`0x8776` onward transitions cleanly to ordinary, sensible-looking code
— confirming the table's real length is exactly 256, not a guess).
Live-verified TWICE, exactly: `$D85A=0x04` → `table[4]=0x333D` (matches
the live-captured `HL` at function 51's own `RET`, sampled 5 times);
`$D85A=0xFE` (the real "Kaempfe!" trigger opcode) → `table[0xFE]
=0x0E69` — **exactly** this project's own already-known messageID-read
handler address. This is the concrete, live-verified resolution of the
long-standing "0xFE-vs-0x04" open question from text.md: **`0xFE` genuinely
is the real "display message" opcode** — the earlier `0x04` guess (from
the credits-screen's own positional evidence) was a different,
unrelated convention, now retired with real evidence, not forced to
agree.

**Real decoded opcode semantics, several found this pass** (handler
addresses resolved via the table above, each independently
disassembled):
- **`0xFE` = display message** (`$0E69`) — `LD A,(HL+)` fetches the
  real messageID operand byte from the stream, `CALL $04E2` dispatches
  into the already-known message-settings table (text.md), then `CALL
  $3727` fetches the NEXT opcode and returns — i.e. the interpreter
  does NOT block/halt on a message; whatever makes the player wait for
  a textbox dismissal lives elsewhere (the textbox's own display state
  machine), not in this fetch-dispatch loop itself.
- **The DEFAULT/unassigned-opcode handler, `$3F0C`** (the single most
  common table entry, by far): `CALL $3727 / RET` — literally "fetch
  the next opcode and continue," i.e. a real, genuine **no-op** for
  reserved/unused opcode values. This single 4-byte routine appears as
  the table target for roughly a third of all 256 entries, arranged in
  a structured, repeating pattern (not scattered randomly) — reads as
  a deliberately sparse, hand-authored opcode set with real gaps left
  open for future content, not noise.
- **`0xFF` = a real SECOND-LEVEL sub-dispatch** (`$38E6`): reads
  ANOTHER WRAM byte (`$D86B`), looks IT up in a SECOND 256-entry-style
  table (file `0x3BAC` region, not yet fully bounded/dumped), and `JP
  HL`s (a direct tail-jump, not a `CALL`) into the resolved sub-handler
  — a real two-level opcode hierarchy, not flat. Live-observed as the
  single most frequently dispatched opcode (130 hits in one ~900,000-
  step idle window) — plausibly a "meta/system tick" or "continue
  current sub-process" opcode, not investigated to its own sub-table's
  full semantics this pass.
- **A real "heal to max" opcode family** — handler `$394F` (and its
  neighbor `$3968`, structurally identical at a different WRAM offset):
  ```
  $394F  LD A,(0xD7B5) / LD D,A
         LD A,(0xD7B4) / LD E,A      ; DE = $D7B4/$D7B5 (real player maxLP)
         LD A,D / LD (0xD7B3),A
         LD A,E / LD (0xD7B2),A      ; $D7B2/$D7B3 (real player curLP) = DE
         CALL $310B                   ; the already-known HUD-refresh/
                                        ; death-check hook
         CALL $3727                   ; fetch next opcode
         RET
  ```
  Copies the real, already-VERIFIED player `maxLP` WRAM field directly
  into `curLP` — a genuine "restore HP to full" script command. `$3968`
  is the same shape at `$D7B8`/`$D7B9` → `$D7B6`/`$D7B7`, i.e. very
  plausibly the equivalent MP-restore opcode (matching the already-
  known struct layout exactly: `+4`=curMP, `+6`=maxMP). This single
  shared handler is the table's target for MANY distinct opcode values
  (at least 18/19/34/35/50/51/66/67/82/83/98/99/114/115/130/131 in the
  dump — one instance per some other dimension, e.g. per-room or
  per-NPC "give this specific full heal" variants all routing to the
  same generic underlying command).
- **`0x04`'s own handler, `$333D`**: NOT reached via the general fetch
  loop in the one live path traced — its own caller (`$36D0`, called
  from `$34F0`) hardcodes `LD A,0x04` rather than fetching it from a
  stream, and separately advances a DIFFERENT HL (the real text-
  typewriter's own per-character stream), live-observed firing
  periodically (~every 2000 steps) during idle/dialogue-reveal time.
  `$333D`'s own body classifies a byte read from `(HL)` against several
  thresholds (`0x20`,`0x70`,`0x80`,`0x99`) — reads as real text/
  character-class dispatch logic (the typewriter's own "how do I
  render/advance for this character" decision), a DIFFERENT real
  mechanism layered on the SAME `$D85A`/dispatch-table plumbing, not
  the general script interpreter's own opcode 4.

**What's still open**: the exact instruction sequence that takes the
dispatch-resolved `HL` (cached via `$3274`, a sibling of `$326A` reached
by a deliberate return-address-hijack trick — `$3260` manually pushes
`$3274` before calling the dispatch stub, so the stub's own `RET`
lands there instead of back at the real caller, the same "avoid a
literal JP/CALL target" style pervasive throughout this ROM) and
actually jumps execution into the handler was not itself single-
stepped instruction-by-instruction to its very last hop (a `CALL
$2A0A` bank-restore follows the cache-store, and $2A0A's own internals
weren't re-disassembled this pass) — functionally proven regardless,
since `$0E69` (opcode `0xFE`'s real handler) WAS live-observed actually
executing at the right moment with the right operand. The remaining
~250 primary table entries' individual semantics are undecoded — real,
honest, bounded remaining scope, not claimed as solved.

**UPDATE (2026-08-11)**: the second-level `0xFF` sub-table is no longer
"full contents undecoded" — see `events.md`'s own "The 0xFF sub-
dispatch table — bounded and disassembled" section: it's a real,
bounded 11-entry table (file `0x3BAC`, fixed bank 0), not 256 entries
as originally hedged, with 2/11 handlers' actual semantics decoded
(a real conditional interpreter-halt, and a plain WRAM-copy handler).
9/11 handlers still open.

**Implemented**: `src/import/ScriptOpcodeTable.lua` (generic decoder
for the real 256-entry table) and `src/scripting/ScriptInterpreter.lua`
(a real, tested port of the fetch-dispatch core: `$3727`'s exact
semantics, `$D85A`/cursor bookkeeping, and the real table lookup) — see
`docs/reverse-engineering/events.md` for the wiring/scope summary.

## Real player landing positions after room transitions — corrected (2026-08-10)

Direct user report ("die spawn positionen des players nach einem
raumwechsel... da stimmt was nicht"). All 3 real room-transition exits
had a `landingX`/`landingY` — 2 of the 3 were EXPLICITLY flagged in
their own doc comments as "NOT independently pixel-verified", i.e.
placeholder guesses, not measured. Live-traced all 3 from real saved
checkpoints (`door_ready.state`, `room2_free.state`,
`staircase_ready.state`), reading the real player OAM position
(`$C244`/`$C245`) directly, not visually.

**Method, and a real methodological trap caught along the way**: the
first attempt at each transition held the movement key for a long,
arbitrary duration and read the position afterward -- this produces a
WRONG, misleadingly-precise-looking number, because the player keeps
walking under continued input well past the real transition's own
landing spot (confirmed directly: willyRoom's first attempt read
`(80,24)`, a real wall the player had continued into, not the landing
itself). The real technique: release input at the EXACT frame the
transition's own real completion signal fires (`SCY`/`SCX` reaching
its real settled value for a scroll, or the room pointer `$D392`/
`$D393` changing for a cut), then confirm the position stays constant
for 50+ further frames with zero input -- only that is a genuine
landing spot, not a snapshot mid-continued-walk.

**Real, live-confirmed values** (replacing the old `rom_profiles.lua`
entries):
- **willyRoom -> secondRoom** (vertical door-scroll): real `(80,136)`,
  was `(72,104)` -- wrong on both axes. Released input the instant
  `SCY` first reached its real settled `128`; position then held
  exactly at `(80,136)` for 60+ frames with zero input.
- **secondRoom -> thirdRoom** (horizontal scroll): real `(80,64)`, was
  `(24,64)` -- Y coincidentally already correct, X was not (the old
  comment's own "enters from the west edge" assumption was wrong).
  Released input only once `SCX` genuinely reached its real, CODE-
  VERIFIED settled value (`160`, confirming that already-known constant
  itself); an earlier, too-early release (before `SCX` reached 160)
  produced a misleading, still-drifting `(0,64)` that was caught and
  discarded, not used.
- **thirdRoom -> fourthRoom** (instant cut): real `(120,112)`, was
  `(72,96)` -- wrong on both axes. Released input the exact frame
  `$D392`/`$D393` changed from the thirdRoom to the fourthRoom pointer;
  position stayed at the OLD room's coordinates for 8 more frames (a
  real sequencing detail: the room pointer changes before the player's
  own OAM position gets updated to the new spawn point, not simultaneous)
  before jumping to `(120,112)` and staying there.

## Real NPC dialogue trigger — investigated, found to already match real ROM behavior (2026-08-10)

Direct user report ("die speach trigger für die npc sind nicht richtig,
die werden ausgelöst wenn der player den raum betritt"). Live-traced
the one real dialogue trigger this project has (the "Amanda" text,
`willyRoom`'s exit into `secondRoom`) to check whether tying it to the
room transition itself (rather than a separate proximity/interaction
check) is really a bug or matches the ROM.

**Finding**: this project's own earlier trace (see "ANSWERED: the real
Willy-room north door DOES open" above) already documented that the
real ROM shows this exact textbox "partway through what's now visible"
DURING the door-scroll -- i.e. the real ROM's own trigger genuinely IS
the room transition, not a separate walk-up-to-Amanda interaction (the
`characterA`/`characterB` sprites in `secondRoom` are decorative --
their real position isn't what gates the dialogue). Re-confirmed this
pass with a real write-watchpoint on the box's own tilemap row: the
real box content is written at `SCY=144`, i.e. only ~4 real frames (of
the scroll's real 32-frame duration) before the scroll's own natural
completion -- close enough to "on arrival" that this project's current
implementation (which shows the dialogue once the scroll fully
completes, not 4 frames early) is a negligible, sub-visible timing
difference, not a wrong trigger CONDITION. No code change made here --
recorded as a real, checked, honest finding that didn't turn up the bug
the report suspected, rather than forcing an unsupported redesign.

## Real sprite/animation loading gaps found and fixed (2026-08-10)

Direct user reports ("alle NPC und sprites... richtig geladen werden";
"die charakter animation soll bitte ueberall funktionieren"). Two real,
concrete bugs found by reading `VictorySequence.lua` (the state driving
the whole post-boss willyRoom/secondRoom/thirdRoom/fourthRoom room
chain) against `Field.lua`'s own, already-correct pattern:

1. **The player used a STATIC sprite in this whole state, not the real
   walk-cycle animation.** `Field.lua` uses `PlayerSprite.lua` (the
   real, VERIFIED per-direction animation, `profile.graphics
   .playerAnimation`); `VictorySequence.lua` instead built a plain,
   single-pose `CreatureSprite` for the player and never updated it --
   meaning the player's own sprite never animated ANYWHERE in the
   cutscene or the whole subsequent room chain, only in the very first
   room (`Field.lua`'s own `startRoom`). Fixed: now uses the same real
   `PlayerSprite`, driven by the same real `:update(dt, moving,
   facing)` call each interactive frame.
2. **`VictorySequence.lua` never set the real hardware sprite palette
   itself**, silently depending on `Field.lua` having already set it
   earlier in the same app session (true in the actual game flow this
   project drives today, so not an observed failure, but not
   self-sufficient/robust either -- every OTHER state that creates a
   `CreatureSprite` sets it explicitly). Fixed: added the same real
   `CreatureSprite.setDefaultPalette(...)` call every other state
   already has.

Willy's own sprite stays a plain `CreatureSprite` (not "fixed" to
animate) -- no ROM-side animation data has ever been captured for him,
only a single static pose, so animating him would be a guess, not a
real fix.

## Real black-screen bug during the post-boss Willy exchange -- found and fixed (2026-08-10)

Direct user report ("wärend des boss fights hatte ich plötzlich einen
schwarten screen"). This is a bug in this project's own LÖVE2D
`VictorySequence.lua`, not a ROM behavior gap, so the investigation
surface was the actual Lua source plus this project's own scripted
live-verification hooks, rather than mGBA/ROM tracing.

`VictorySequence:draw()`'s "top"-page branch (the 6-line Willy
exchange right after the boss falls) only draws willyRoom's real
background/scene when `self:backgroundFor("willyRoom")` is non-nil.
That was populated exclusively by `ensureRoomLoaded`, which the
constructor never called for willyRoom itself -- only
`beginTransition`/`completeTransition`/`enterGameplay` did, and all
three run only AFTER the whole cutscene page list (Willy exchange
included) finishes. Every "top" page therefore silently fell into the
`else` branch (the real full-screen black wipe, meant only for
"bottom" pages), showing the dialogue box correctly but with solid
black behind it for the room/player/Willy art -- exactly the "sudden
black screen" the user reported, live-reproduced and confirmed via a
scripted F6-kill + `MYSTICQUEST_SCREENSHOT` run before and after the
fix (see docs/progress.md's matching dated entry for the screenshots
and the fix's own ordering note).

## Full live re-trace of the post-boss sequence -- 6 real findings (2026-08-10)

Direct instruction to re-verify the whole start->boss->Willy->secondRoom
sequence against the real ROM and track every map/sprite change. Full
writeup lives in docs/progress.md's matching dated entry (courtyard
story-text correction, Willy exchange correction, the willyRoom->
secondRoom landing-position bug and its root cause, the real per-NPC
proximity dialogue trigger replacing a wrong room-entry one, a newly-
exposed secondRoom east-exit zone bug, and confirmation that the two
secondRoom NPCs render with wrong -- font-region -- tile data). Kept
here as a pointer rather than duplicated in full.

## Bank 5, revisited: an exhaustive STATIC answer, no live play needed (2026-08-11)

Direct instruction to crack Milestone 3/bank 5, then a direct, correct
course-correction mid-investigation: *"ich glaube nicht das das ein
guter weg ist die bank zu entschluesseln... du versuchst ja quasi
dahin zu spielen... das schaffst du doch nicht... finde einen anderen
besseren weg."* Right — the first attempt here (and, in spirit, the
original 2026-08-10 `$C3F0` investigation too) was "extend real play
coverage and hope to catch bank 5 being switched in," which does not
scale and can never produce a real negative proof, only an
ever-growing pile of inconclusive coverage. Abandoned that approach
entirely in favor of pure static analysis, which turns out to answer
the question completely.

**Exhaustive static proof: bank 5 has exactly ONE real entry point in
the whole ROM, and it's already fully mapped.** Two ROM-wide byte-
pattern scans (no emulator, no play session):

1. Every `LD A,n` immediately followed (within a few bytes) by a
   `CALL $29FB` (the already-known hardcoded trampoline convention) --
   re-confirms the 2026-08-10 finding (banks 1/2/3/4/8/9/15, never 5)
   via a direct independent re-scan, not trust in the old result alone.
2. Every `LD A,5` followed directly by a raw `LD ($2100),A` (a
   non-trampoline, direct MBC bank-select write) anywhere in the whole
   256KB ROM: **zero hits**.

Combined with the already-known fact that the only OTHER bank-switch
mechanism in this ROM is the dynamic one (`$C3F0`, fed by the
`roomSelectorTable`'s own byte-6 field -- see rom_profiles.lua's
`roomSelectorTable` doc comment) -- this is now an exhaustive case
analysis, not an inductive "still hasn't shown up": **bank 5 can ONLY
ever be reached through the `roomSelectorTable`, and nothing else in
this ROM can switch to it.**

**Decoded ALL 16 roomSelectorTable records' dynamic-bank field directly
from the ROM file** (the existing `rom_profiles.lua` doc only recorded
each record's `targetPointer`, not its `dynamicBank` -- this fills a
real, previously-unfilled gap in already-committed data, not new
territory):

```
index:   0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
bank:    5  6  7  7  7  7  7  7  6  5  6  7  7  7  6  6
```

**Bank 5 appears at exactly 2 of the 16 real indices: 0 and 9.** Both
resolve to real, already-relevant bytes:

- **Index 0** (`targetPointer=0x40B0`, the startRoom/fourthRoom family
  -- shares this pointer with index 1, which uses bank 6 instead): its
  OWN separate `ptr` field (bytes 7-8 of the 11-byte record, distinct
  from the `targetPointer`/`DE` field -- see the corrected field-index
  table below) is `0x4000`. With dynamic bank 5 active, `0x4000`
  resolves to real file offset **`0x14000`** -- **exactly the
  already-cracked bank-5 map table's own 4-byte header**
  (`00 03 10 10`, i.e. `[encodingMode=0, rleLength=3, gridHeight=16,
  gridWidth=16]`).
- **Index 9** (`targetPointer=0x4938`, the already-documented
  `unknownRoomA` family, roomSelectors 8-13, "never reached in any
  playthrough" per `rom_profiles.lua`'s own existing honesty note):
  its own `ptr` field is `0x7CD7`, resolving with bank 5 active to
  real file offset **`0x17CD7`** -- inside the SAME "past the last
  bounded RLE record" region this pass's own earlier disassembly
  attempt (checking bank 5's tail for resident code, a dead end --
  see below) already dumped and found still data-shaped, not code.

**What this does and does NOT prove, stated precisely.** The
already-known purpose of this `ptr`+dynamic-bank mechanism (see
rom_profiles.lua's own `roomSelectorTable` doc comment, "a real,
live-confirmed direct user hypothesis") is a **state/flag read**: 4
bytes get copied from `ptr` into WRAM `$C3F8-$C3FB`, and `$C3F8`
specifically feeds the already-known gate/door-enable check (`$235B`).
So this is solid, direct, static proof that **bank 5 genuinely is
switched in and read by real, live-used game code** -- not proof that
the already-cracked 256-record RLE table is rendered as an on-screen
room this way. The coincidence of index 0's flag-read landing exactly
on the RLE table's own header address is likely NOT random (a
completely unrelated 2-byte flag source landing on file offset
`0x14000` out of a 256KB ROM by pure chance would be a roughly 1-in-
1600 coincidence, once one already knows the pointer's own value has
to be a plausible small CPU offset), but it does not by itself explain
HOW/WHETHER the rest of the 512-entry pointer table + 255 RLE blobs
ever gets walked and drawn as a room. **That remains the real open
question** -- but it is now a much narrower one: "does anything ever
read PAST `$14004` (the pointer table itself, not just its 4-byte
header) while bank 5 is switched in" -- and per the exhaustive scan
above, the ONLY way to get bank 5 switched in at all is roomSelector
index 0 or 9, so the search space for that remaining question is now
fully bounded (trace forward from `$C3F8`'s own two known consumers
after either of these two exact roomSelector indices fire, a concrete,
finite next step, not open-ended play).

**Dead end recorded so it isn't retried the same way**: checked bank
5's own tail (past the last RLE-bounded blob, file offset `0x17CA1`
onward) for resident code (a plausible place for a bank to keep its
own reader routine, alongside its data) -- disassembling all the way
to bank end (`0x17FFF`) never leaves data-shaped bytes (heavy `0xFF`
density, small-integer runs matching the already-known header/RLE
byte conventions) and produces no coherent instruction stream at any
point. Bank 5 is pure data, cover to cover -- confirms this project's
own prior "record 255's blob extends further than assumed, not
bounded by a next-pointer" open question, rather than resolving it,
and rules out "bank 5 has its own resident decompressor" as a lead.

**Also checked and ruled out this pass**: cross-referenced all 255
RLE-decoded bank-5 records (real tile PATTERNS, not ID numbers, so the
comparison is meaningful across the two systems' different ID
namespaces) against the 4 real, ground-truth rooms found since the
original courtyard-only negative test (willyRoom/secondRoom/
thirdRoom/fourthRoom) -- every one comes back at chance level (6-10%
best match out of 80 tiles), extending the original single-room
negative to every currently-known real room. The bank-5 table's 255
RLE blobs are still not known to correspond to any specific
on-screen room this project has ever captured.

**Corrected roomSelectorTable field-index detail** (rom_profiles.lua's
own doc comment already had this right; recorded here because this
pass's own first attempt at re-deriving it from scratch, without
checking the existing doc first, got the byte index wrong on the first
try -- a real process lesson: check already-committed data before
re-disassembling from zero): within each 11-byte record, byte 6 is the
dynamic bank (not byte 8), and bytes 7-8 are the `ptr` field (not
bytes 9-10) -- `rom_profiles.lua`'s existing comment already stated
this correctly; this pass's live disassembly independently re-derived
the same layout after an initial off-by-two slip, which is recorded
as a caught, non-shipped mistake, not a correction to the file itself.

## Following `$C3F8`'s consumers: the real render path found, bank 5 reframed (2026-08-11, same day, "ja mach das")

Direct follow-up to the exhaustive static proof above. The obvious next
static step (named at the end of the previous section) was to trace
forward from `$C3F8`'s own two known consumers instead of guessing --
`$235B` (the already-known gate/enable check) turned out to be exactly
one of them, and disassembling it and its callees end to end produced a
real, mostly-complete call chain from "dynamic bank switched in" all
the way to "tiles hit VRAM." Still pure static disassembly, no
emulator.

**`$235B(A=direction)` -- the real per-exit gate/reveal dispatcher.**
Full body:
```
0x235b  PUSH AF
0x235c  LD A,($C3F8) / CP 0 / JR Z,+skip   ; the already-known gate flag
0x2363  LD A,($C3F0) / CALL $29FB          ; switch to the roomSelector's OWN dynamic bank (e.g. 5!)
0x2369  POP AF / LD C,A                    ; C = the real incoming argument (direction/exit id)
0x236b  LD A,($C3F4) / OR C / LD ($C3F4),A ; OR the arg into a running WRAM bitmask -- plausibly "which exits have been revealed"
0x2373  LD A,C / CALL $225D                ; dispatch on C (see below)
0x2376..0x237c  (builds HL=C*2, DE=result of $225D) / CALL $2281
0x237f  CALL $2A0A (restore bank) / RET
  (skip:) POP AF / RET                     ; C3F8==0 -> no-op, arg untouched
```
So `$235B` is called with an argument once per real event (very likely
once per screen-edge/exit reached), and does nothing at all unless the
CURRENT roomSelector's own `$C3F8` flag (the byte already tied to the
door-open check) is set -- exactly the "per-instance state" gate this
project's docs already predicted. When it IS set, it switches to
**exactly the dynamic bank named by that roomSelector's own byte 6**
-- i.e. for roomSelector 0 or 9, this really does switch bank 5 in.

**`$225D(A)` -- selects 1 of 4 fixed (WRAM-target, screen-cursor)
tables by which single bit of `A` is set:**
`BIT 0 -> table $2235, C=0`; `BIT 1 -> table $222D, C=1`; `BIT 2 ->
table $2225, C=2`; none set -> table `$221D`, C=3. All 4 tables live in
fixed bank 0 (real ROM constants, dumped directly):
```
$221D: [0xC39B, 0xC39A, 0x0705, 0x0704]
$2225: [0xC355, 0xC354, 0x0005, 0x0004]
$222D: [0xC378, 0xC36E, 0x0400, 0x0300]
$2235: [0xC381, 0xC377, 0x0409, 0x0309]
```
Entries 0-1 of each are real WRAM addresses (all in the `$C3xx`
range); entries 2-3, read as separate (D,E) byte pairs rather than one
16-bit number (confirmed by how `$056C` consumes them), are small
constants -- most plausibly a fixed screen-cursor row/col offset per
exit, though not proven against a live screenshot this pass.

**`$2281(HL=C*2, DE=one of the 4 tables above)` -- the real dynamic-
bank READ.** With the dynamic bank (from `$235B`) still switched in,
computes address = `ptr + 2 + C*2` (where `ptr` = the SAME `$C3F2`/
`$C3F3` field the roomSelectorTable dispatch already staged -- i.e.
this reads from the roomSelector's own `ptr` field, just past the
already-documented 4-byte `$C3F8-$C3FB` header, at a small per-
direction offset), reads 2 raw bytes from THAT address in the ACTIVE
DYNAMIC BANK, writes them verbatim into the table's own WRAM
entries 0-1 (a real, dedicated pointer pair, analogous to the
already-known `$D392`/`$D393`), then calls `$056C` twice -- once per
byte, each paired with one of the table's entries 2-3 as `DE`.

**`$056C(A=one raw byte from the dynamic bank, DE=small cursor
constant)` -- confirmed as ANOTHER real caller of the project's
already-fully-traced room-tile pipeline, not a new mechanism:**
```
0x056c  CALL $05BB(A)         ; the ALREADY-KNOWN source-address formula: HL = ($D392:$D393) + A*6
0x0571  LD A,0x08 / CALL $29FB  ; HARDCODED switch to bank 8 (the already-known tile-patch-blob library bank)
0x0578..0x057d  DE *= 2 (each byte independently)
0x057e..0x05b6  read 4 bytes from the $05BB-resolved bank-8 address, remap each through the
                ALREADY-KNOWN $D070 WRAM table, pack into 2 tile-ID pairs, CALL $0495 twice
                (INC D between the two calls) -- $0495 is the ALREADY-DOCUMENTED "$045D-style
                cursor-blit wrapper" (rom-map.md's own "Real, VERIFIED finding" section, the
                gate-open-animation trace) that ultimately writes VRAM via $1D87/$1D88.
0x05b7  CALL $2A0A (restore bank) / RET
```

**What this proves, precisely.** This is a real, mostly disassembled,
end-to-end chain from "roomSelectorTable says dynamic bank 5" through
to "bytes land in VRAM as visible tiles," reusing -- not duplicating --
every already-documented piece of the tile pipeline (`$05BB`'s address
formula, the `$D070` remap table, the `$045D`/`$048C`/`$1D87`/`$1D88`
cursor-blit-and-safe-VRAM-write machinery already proven for the
Willy-room load, the black-screen wipe, and the courtyard's 4x4
gate-open animation). It is called once per exit/direction, gated by
the already-known per-roomSelector `$C3F8` flag, and only touches the
dynamic bank (5, 6, 7...) for a single 16-bit READ used as an INDEX,
not as the actual tile source.

**This reframes what bank 5's data most likely IS.** The byte(s) read
from bank 5 at this call site are fed into `$05BB` purely as an index
argument (`HL = $D392:$D393 + A*6`) -- the real tile bytes drawn always
come from the HARDCODED bank 8, via the pre-existing `$D392`/`$D393`
room-source pointer, exactly like every other confirmed use of this
pipeline. So what lives in bank 5 (at least at the two roomSelector
entries that ever switch it in) reads as **small per-exit reference/
index metadata that selects which of bank 8's own tile-patch blocks to
reveal**, not raw pixel/tile-ID map data. This is a plausible, evidence-
grounded explanation for the earlier comprehensive negative result
(bank 5's 255 RLE-decoded records never matching any of the 5 known
real rooms' pixel patterns) -- not because the comparison was flawed,
but because bank 5's data most likely was never meant to BE room tile
art in the first place.

**Honest scope -- what remains open.** (a) This chain was NOT verified
live this pass (deliberately, per the standing "static over play"
guidance) -- it is a real disassembly-derived reconstruction, same
confidence level as this project's other disassembly-only findings,
not a watchpoint-confirmed one. (b) `$1B74` (called once per `$2281`
invocation, alongside the two `$056C` calls) was disassembled far
enough to see it also hardcodes bank 8 and loops 80 times from a fixed
WRAM base `$C350` -- plausibly a per-room 80-entry (20x4) event/reveal-
state array reset, matching the project's own record-width convention
elsewhere, but not traced to a firm conclusion. (c) Which physical
exit/direction each of the 4 `$225D` bit-cases corresponds to (north/
south/east/west, or something else) was not determined. (d) The
original "what real game state selects roomSelector index 0 vs 9"
question is now sharper but still open: even confirming this whole
chain, it only fires once `$235B` is actually called with `$C3F8`
already nonzero for whichever roomSelector is currently loaded --
the trigger for THAT is a separate, still-untraced question.

## Resolving the 3 open ends (2026-08-11, same day, "löse die offenen Fragen")

All three, purely via static disassembly and two more exhaustive whole-
ROM byte-pattern scans (no emulator).

### 1. Which physical exit each `$225D` bit-case is -- RESOLVED

Exhaustively searched the whole ROM for `CALL $235B` (`0xCD 0x5B 0x23`):
**exactly 4 hits, real ROM file offsets `0xF8B/0xFA1/0xFB7/0xFCD`**, each
immediately preceded by a hardcoded `LD A,n` with `n = 0x01, 0x02, 0x04,
0x08` respectively -- a clean one-hot 4-direction encoding, matching
`$225D`'s own `BIT 0/1/2` tests exactly (`0x08` sets none of bits 0-2,
landing on the `$221D`/`C=3` default case).

Cross-checked against the real screen position each case's fixed
cursor-offset table resolves to (via `$045D`'s already-documented
`row=($C343+D)&0x1F`, `col=($C342+E)&0x1F` formula, `$056C` doubling
each table entry before use, drawing 2-tile pairs with `D` incremented
between the two internal blits per call):

| `A` (opcode arg) | `$225D` table | resolved rows | resolved cols | reads as |
|---|---|---|---|---|
| `0x04` (bit2) | `$2225` | 0-1 | 8-11 | **North** (top-center) |
| `0x02` (bit1) | `$222D` | 6-9 | 0-1 | **West** (left-center) |
| `0x01` (bit0) | `$2235` | 6-9 | 18-19 | **East** (right-center) |
| `0x08` (none) | `$221D` | 14-16 | 8-11 | **South** (bottom-center) |

All 4 land at plausible screen-edge exit positions, horizontally
centered for N/S and vertically centered for E/W -- internally
consistent, not a coincidence.

**Bonus, unplanned find while searching**: the exact same file region
(`$0F2C-$0FDF`) turns out to be a contiguous block of **10 script-
opcode handlers** (the project's own already-tested `ScriptOpcodeTable`
system) -- 4 for a `$0232`(check)+`$049E`(trigger) combo, 4 for `$235B`
(one per direction, the "open exit" opcode), and **4 for `$22FE`** (the
already-known sibling "door/gate closed" check from much earlier in
this project, at the SAME 4 direction constants `1/2/4/8`) -- i.e.
`$235B`/`$22FE` are a real, confirmed **matched "open exit N/E/S/W" /
"close exit N/E/S/W" opcode pair**, not just a vaguely-related "family"
as previously phrased. This means the whole mechanism traced in the
previous section is **entirely script-driven** -- it only ever runs
when a room's own script bytecode explicitly executes one of these 8
opcodes, not from generic per-frame collision/movement code.

### 2. `$1B74`'s 80-entry loop -- RESOLVED

`$1B19` computes `HL = ($D392:$D393) + A*6` -- **byte-for-byte the same
formula as `$05BB`**. `$1B2B` (called from `$1B74`) loops 80 times over
the current room's own tile-source table (the same 80-record/20x4
convention already used elsewhere in this project), and for each
record's 4 sub-indices, marks a byte in a 256-entry WRAM table
(`$D170`, cleared to `0xFF` by `$1B00` at room-load time) as "used"
(writes `0x10`). `$1B4E` (also called from `$1B74`) scans that same
`$D170` table for entries left at the sentinel value and finalizes
them. **Reads as the project's already-suspected generic tile/VRAM-
slot allocator** (previously flagged in this doc as "Chased Block A...
reads as a generic tile/OAM-slot allocator, not obviously room-
specific") -- confirmed here as a real, general per-room tile-slot
bookkeeping pass, re-run whenever an exit gets revealed to keep the
shared VRAM-slot table consistent. Not bank-5-specific, not part of
the "what does bank 5's data mean" question -- general infrastructure.

### 3. What real game state selects roomSelector index 0/9 -- PARTIALLY RESOLVED

Exhaustively searched the whole ROM for `CALL $26DC` (the
roomSelectorTable dispatch entry itself): **exactly 5 hits**, real file
offsets `0x4261, 0x42A0, 0x434F, 0x4395, 0xBB81` (the first four inside
bank 1's own resident code, the fifth inside bank 2's). Checked each
site's own immediately-preceding instructions for the index value
loaded into `A`:

- **3 of 5 sites hardcode index = 7** (`0x4261`, `0x42A0`, `0xBB81`) --
  roomSelector 7 is the already-documented "pre-transition placeholder,
  not explorable" entry (`targetPointer=0x4C1A`).
- **2 of 5 sites load the index DYNAMICALLY**, not as a literal
  constant: `0x434F`'s enclosing routine (`$433E`+) sets `A` from raw
  WRAM `$D49D`, itself written by a small helper (`$4331`) that does
  `LD A,(BC) / LD ($D49D),A` -- i.e. **reads the index byte from
  whatever a `BC`-pointed data/script cursor currently points at**.
  `0x4395`'s enclosing routine (`$4387`+) similarly uses an incoming
  register `C` (an argument from ITS OWN caller) directly as the index.

**Searched for callers of both dynamic-index routines** (`CALL $433E`,
`CALL $4387`, and their `JP` forms): **zero hits anywhere in the ROM**
-- both are reached only indirectly (almost certainly via the same
bank-trampoline convention this whole project has documented
extensively, from code resident in some OTHER bank), not via a literal
`CALL`/`JP` this scan's byte pattern could catch.

**Honest conclusion**: this proves, exhaustively, that **index 0/9 are
never selected by a hardcoded branch anywhere in the ROM** -- the only
two real paths that could ever produce them are genuinely **data/
script-driven** (a byte read from a live cursor into a stream, or an
argument threaded in from an indirect caller), not fixed code. This is
a real, evidenced answer to "what triggers it" at the mechanism level
(script/event data, not code), but tracing the exact byte stream back
to its ultimate source (which specific room script, under which
specific condition, actually contains a literal `0x00` or `0x09`) was
not completed -- the indirect-call boundary here is a legitimate, well-
defined stopping point for a further pass (find the trampoline-based
callers of `$433E`/`$4387`), not chased further this session.

**UPDATE 2026-08-14** (task #85, direct follow-up): there is no
trampoline to find -- both `$433E` and `$4387` turned out to be step-
table entries of the SAME already-known `$D499`-indexed dispatch
pattern this project already had a name for (`$413C`, reached via
script opcode `0xF4`), not independently-called routines. `$4387` =
`$413C`'s own step-index 3 (and 16); `$433E` = step-index 3 of a
SECOND, previously-undocumented sibling table at `$418C` (found this
same pass, same `$4130`-style generic dispatcher shape). See events.md's
own dated entry for the full disassembly, including a real correction
this same pass turned up: both tables' own valid-looking entries stop
at index 7 -- the real step-table length is very likely 8, not 30.

## Live validation of the traced exit mechanism (2026-08-11, same day, "Exit-Mechanismus live validieren")

Direct follow-up: rather than hunting for unreachable content, validated
the newly-traced static chain (`$235B`/`$225D`/`$2281`/`$056C`, direction
tables) against ALREADY-REACHABLE, already-implemented content
(`tools/rom/checkpoints.py`'s real willyRoom -> secondRoom -> thirdRoom
chain) -- a bounded, low-risk live check, not a search for something
unknown.

**Watched `$C3F8`, `$C3F4`, `$C3F0` (via `Watcher`) across two real
sessions:**

1. **In-room exploration** (`second_room_free()` -> ~21,000 real frames
   of full 4-direction wandering through secondRoom/thirdRoom, NPC
   interaction, and backtracking): **zero writes to any of the 3
   addresses.** `$C3F8` was already `0x01` (nonzero) at the start --
   i.e. the "gate" precondition IS satisfied for this room family --
   but `$235B`'s own body (and its `$C3F4` side-effect) never fired
   during ordinary walking/exploring/talking. Consistent with the
   static finding that this whole mechanism is script-opcode-driven,
   not generic per-frame code -- none of this room family's own script
   content happens to invoke it during normal play.

2. **The real door-scroll transition itself** (`door_ready()` -> hold
   `UP` through the actual willyRoom -> secondRoom scroll): **a real
   hit.** `$C3F4` was written twice, `0x04` at frame 10476 then `0x08`
   at frame 10497 (21 frames later) -- **the first live, non-
   disassembly-only confirmation that this traced machinery genuinely
   participates in real observed gameplay**, not just a plausible
   static reconstruction. `$C3F0`/`$C3F8` themselves stayed silent
   throughout the scroll -- a clean cross-check confirming the
   already-documented "willyRoom/secondRoom/thirdRoom are one
   continuous scrollable chain" characterization (no fresh
   `roomSelectorTable` dispatch happens mid-scroll).

**Honest complication found while confirming this.** A fresh exhaustive
scan for every direct `LD ($C3F4),A` in the ROM turned up **5 real
write sites, not the 2 (`$235B`/`$22FE`) already known**:
- `$2314` (already known: `$22FE`, clears bits -- `CPL`/`AND`)
- `$236F` (already known: `$235B`, sets bits -- `OR`)
- `$2573` -- part of a THIRD, more general routine (`~$2560-$25C0`):
  resets `$C3F4` to `0x00`, then loops 4 times over a real per-
  direction data stream, for each of the 4 slots either writing a
  resolved value into the SAME 4 fixed direction-pointer tables
  `$221D` et al. (i.e. a second, independent producer for those
  tables, not just `$2281`) or calling `$299A(directionIndex)` and
  OR-ing its result into `$C3F4` -- reads as the real general "load
  this room's per-direction exit/connection descriptors" routine,
  plausibly what runs once per room/scroll load to decide which exits
  start open.
- `$25B7` -- the OR-write inside that same loop (paired with `$2573`'s
  reset).
- `$4366` -- inside the already-traced roomSelector-index-7 ("pre-
  transition placeholder") loader: a direct, non-OR copy `$C3F4 =
  ($D4A4)` -- a per-transition reset/seed from a separate WRAM byte.

So the 2 real values seen live (`0x04` then `0x08`) come from AT LEAST
3 possible real writers, not a single clean witness as first assumed
-- attributing each specific observed write to exactly one of them
would need PC-level capture at the moment of the hit (not attempted
this pass: the `Watcher` here is driven via `session.run(1)`, which
does not reliably expose the triggering instruction's own PC without
switching to slower single-`step()`-driven capture -- a legitimate,
named, cheap next step if the exact attribution ever matters, not
chased further this session since the actual validation goal -- "does
this traced machinery show up in real play" -- already has a clear,
positive answer).

**What this establishes, precisely**: the exit/direction-table
machinery traced earlier this session is REAL, ACTIVE, engaged during
real, already-implemented gameplay (not just a disassembly-only
reconstruction) -- and it's part of a broader, more general "per-room
connection descriptor" subsystem than first scoped (at least 3 real
producers share the same 4 fixed direction-pointer tables). It does
NOT confirm anything new about bank 5 specifically (this room family
uses dynamicBank=7, not 5) -- it validates the SHARED, general parts of
the mechanism ($225D/$2281's direction tables, $056C's tile-draw tail,
the C3F4 bitmask idiom) that bank 5's own roomSelector 0/9 entries also
rely on, which is the part that most needed live grounding.

## A stricter, reusable search for a broader room list (2026-08-11, same day)

Direct follow-up after the naive byte-scan produced a false positive
(compressed text, see progress.md). Built a structural filter instead
of a raw value match, mirroring the REAL `roomSelectorTable`'s own
confirmed record shape: for every 11-byte-aligned window in every
bank's own `$4000-$7FFF` file region, require byte 6 to be a plausible
MBC2 bank (`0-15`) AND bytes 3-4 AND bytes 7-8 to each be a plausible
switchable-bank CPU pointer (`$4000-$7FFF`) -- then look for RUNS of 3+
consecutive such records at exact 11-byte stride (a single lucky match
happens by chance reasonably often; a run of 3+ is `~(1/256)^3` per
starting position, i.e. genuinely rare).

**Sanity check passed**: this filter correctly re-finds the known real
`roomSelectorTable` itself (bank 8, file `0x20000`, the full real
run-length of 16) with no extra tuning -- a real, validated search tool
now, not just a one-off script (worth keeping for future ROM-structure
hunts, since it directly avoids the text-collision trap the naive
2-byte-value scan fell into).

**3 further candidates found, all real signal (not random chance) but
NONE confirmed**:
- bank 4, file `0x11D8E` (CPU `$5D8E`), run of 6 (only the first 4
  passed the strict filter; 2 more inspected by eye afterward look
  similar)
- bank 4, file `0x11E77` (CPU `$5E77`), run of 6 -- **structurally
  near-identical to the one above** (same bank-byte sequence
  `12,12,12,2`, same repeating small-byte shape `0x69/0x6D-0x6E`
  scattered through both), 233 bytes later in the SAME bank
- bank 1, file `0x06ECC` (CPU `$6ECC`), run of 6, visually different
  (very regular descending-by-8 byte runs: `0x18,0x10,0x08,0x00`) --
  reads more like coordinate/countdown data than either a room table
  or text

**Searched for direct code references** (`LD HL/DE/BC,<addr>`
immediates) to all 3 candidate addresses anywhere in the ROM: **zero
hits** for all three. Does not disprove them -- the real
`roomSelectorTable` itself is never referenced by a literal full
address either (it's reached by computing `bank_base + index*11` from
a small index, same as this project's other confirmed dispatch
tables) -- but means no cheap confirmation was available this pass.

**Cross-checked against this project's own already-documented bank 4
structures** (the real enemy-stat table at file `0x10C80-0x10DF0`, the
message-settings table): neither candidate's file offset falls inside
an already-mapped region, so they are not simply re-discoveries of
known bank-4 tables under a different name -- but that alone doesn't
confirm what they ARE either.

**Honest status**: this is real, calibrated progress -- a validated,
reusable structural-search tool, and 3 statistically-significant
candidates that a plain byte scan would have missed real filtering for
-- but none is confirmed as a genuine "broader room list," and further
work here (tracing indirect/trampoline-based references to bank 1/4,
or manually characterizing what else lives in those specific regions)
is open-ended with no guaranteed payoff. A deliberate stopping point,
not a completed answer.

## MILESTONE 3 SOLVED: the full room-layout decompression pipeline, found and cross-verified end to end (2026-08-11, same day, "löse die map komplett")

Direct instruction: don't stop until Milestone 3 is solved; if one
approach fails, try the next; report progress step by step. This
section is the payoff of that instruction -- a complete, code-verified,
cross-checked pipeline from raw ROM bytes to the exact known-correct
willyRoom pixel grid, closing the single biggest open item in this
project's whole roadmap.

### The chase, in order (several dead ends, each recorded so they aren't re-walked)

1. **External reference match**: the FFA-Disassembly project (US ROM)
   documents 6-byte "metatiles" -- 4 GFX-tile indices + collision class +
   interaction type. Checking the ROM bytes at willyRoom's own known
   tile-source pointer (`$D392:$D393=0x46B0`, bank 8, file `0x206B0`)
   against this shape: the first record's 4 bytes (`1b 1c 1d 1e`), fed
   through the live `$D070` remap table, decode to `97 98 99 9a` --
   **exactly a real 2x2 pixel block from willyRoom's known grid.**
   Confirmed: **bank 8 @ `0x206B0` is a real metatile TABLE** (a palette
   of reusable 16x16 tile definitions), not per-cell room data directly.
2. **Wrong turn**: hypothesized the roomSelectorTable's `BC` field
   (committed to WRAM `$D390`/`$D391` via `$01AF3`) was the room's
   layout-stream pointer. Disassembling `$01AF3`'s real readers showed
   it's actually **sprite/tile-pattern data** (an OAM/VRAM sprite-tile
   loader, `0x8000`-based addressing) -- unrelated to the floor layout.
   Dead end, recorded so it isn't retried.
3. **Found the real per-room WRAM layout array**: `$23F1` computes
   `HL = $C350 + row*10 + col` -- a real, code-verified 2D array index,
   stride 10 -- meaning willyRoom's floor layout lives in WRAM
   `$C350-$C39F` as an **8-row x 10-col array of metatile indices**
   (matching `$1B74`'s already-known "loop 80 times" exactly: 8*10=80).
4. **Found the bulk populator**: `$242B` is a **real RLE decompressor**:
   loops until 80 output bytes are written; a source byte with bit 7
   SET means "write `byte & 0x7F`, repeated **`$C3F9`** times" (the
   already-known "flag byte" `$C3F9`, previously only characterized as
   part of a vague per-roomSelector "state" block -- now identified as
   the **real per-room RLE run-length constant**, live-confirmed = 4 for
   willyRoom); a byte with bit 7 clear is a literal metatile index.
5. **Found the real source pointer, live**: single-step tracing (via
   `calltrace.py`'s `CallTracer`, watching WRAM `$C350` for its real
   populating write) resolved the exact live call stack, then a second,
   PC-targeted single-step pass captured the real `DE` register at
   `$242B`'s own decode-loop entry: **`DE=$5A50`, MBC bank 7** -- real
   ROM file offset **`0x1DA50`**. Bank 7, not bank 8 -- the layout
   stream and the metatile table it indexes into live in **different
   banks**, switched at different points in the same load sequence
   (metatile table read while bank 8 is hardcoded-switched for the
   draw, per `$056C`'s already-known `LD A,0x08 / CALL $29FB`; the
   layout stream itself is read earlier, while whatever bank the
   roomSelector's own dynamic dispatch had switched in was active).

### The decode, verified against ground truth

RLE-decoding the real bytes at file `0x1DA50` with `rleLength=4` (live
`$C3F9` value) produces the exact 80-value metatile-index array WRAM
`$C350` itself holds (verified byte-for-byte against a live dump, not
inferred). Rendering that array through the bank-8 metatile table (each
index's 4 GFX-tile bytes, `$D070`-remapped) reproduces willyRoom's full
20x16 pixel grid with **288/320 tiles matching exactly** using nothing
but mechanistic, code-derived rules -- no hand-tuning, no guessing.

**The remaining 32/320 "mismatches" are not errors.** Checked
precisely: they fall in EXACTLY 4 rectangular zones -- rows0-1/cols8-11,
rows6-9/cols0-1, rows6-9/cols18-19, rows14-15/cols8-11 -- and those are
**exactly the same 4 zones** this session's earlier, independently-
traced exit/door-reveal mechanism (`$235B`/`$225D`/`$2281`/`$056C`,
see "Following `$C3F8`'s consumers" above) draws North/West/East/South
door art into. **8+8+8+8 = 32, matching the mismatch count exactly.**
This is a real, precise, cross-system confirmation: the base RLE layout
stream deliberately encodes blank/placeholder metatiles at the 4 door
positions, because the door art is drawn by a SEPARATE, already-fully-
traced subsystem, not by the floor decompressor. Two independently
found and independently traced mechanisms, discovered hours apart in
this same session, click together with zero remaining discrepancy.

### The complete, closed-loop pipeline (this project's own real answer to Milestone 3's core question)

```
roomSelectorTable (bank 8, 16 records)
  -> per-record: dynamicBank, targetPointer (metatile-table base), ptr (exit/state data)
  -> roomSelector dispatch (bank-specific, e.g. $2740's own C3F8-gated $25F6/$25D1 resolvers)
       resolves the room's REAL layout-stream pointer (a distinct ROM location,
       potentially in yet another bank -- bank 7 for willyRoom)
  -> $242B: RLE-decode 80 (or N) bytes using $C3F9 as run-length -> WRAM $C350 (8x10 array)
  -> for each of the 80 cells: metatile-table lookup (targetPointer + index*6) -> 4 raw GFX-tile bytes
  -> $D070 remap (a live WRAM table, not ROM-static) -> final real tile IDs
  -> $045D/$048C cursor-blit + $1D87/$1D88 safe-VRAM-write -> the actual on-screen room
  -> SEPARATELY: $235B/$22FE (per-direction script opcodes) overlay the 4 door/exit graphics
     on top, gated by $C3F8, using the SAME metatile-table+D070 pipeline
```

Every stage of this is now real, disassembled, code-verified -- most of
it live-cross-checked against willyRoom's own known-correct pixel grid,
not just plausible-looking. **This directly answers Milestone 3's real
DoD** ("a general, ROM-driven way to load ANY room") at the mechanism
level: any roomSelectorTable record (not just the 4 hand-captured
rooms) can in principle be run through this exact same pipeline.

### What's still needed to call Milestone 3 fully shipped (honest, concrete remainder)

1. **A real Lua/Python implementation of this pipeline** (RLE decode +
   metatile table + `$D070` remap) -- this pass verified the ALGORITHM
   against live ROM state, but did not yet port it into
   `src/import/MapTable.lua` or an equivalent new module. This is now a
   well-specified, mechanical porting task, not a research question.
2. **`$D070`'s own population is still not derived statically** -- this
   pass used a live dump (a single, targeted, bounded WRAM read, not
   exploratory play) as a known input. Generic extraction of an
   UNREACHED room (one this project has never loaded live) needs either
   (a) tracing what writes `$D070` and reproducing it statically per
   room, or (b) accepting a live dump as part of the generation
   pipeline for every room a future extractor targets (a legitimate,
   lesser-effort option, since `$D070` is small and per-tileset, not
   per-room).
3. **The per-room layout-stream pointer's own resolution chain**
   (`$2740`'s `$25F6`/`$25D1`, indexed by `$C3FB` and the roomSelector's
   own `ptr` field) was traced for willyRoom specifically but not yet
   generalized/tested against a second room -- the concrete next
   validation step before trusting this for arbitrary rooms.
4. Bank 5's OWN 256-record table (the very original mystery) still has
   an unconfirmed relationship to this pipeline -- plausibly it's
   ANOTHER room's (or several rooms') own metatile table and/or layout
   stream, given this pass just proved metatile tables and layout
   streams are real, per-room, bank-scattered structures. Worth
   revisiting now with this session's cracked format in hand, as a
   concrete, well-specified follow-up (not a fresh mystery).

## `$D070`'s real populator, found (2026-08-11, "löse die offenen Fragen")

Direct follow-up on the biggest named gap from the Lua port. Searched
the whole ROM for literal `LD HL,$D070` (and DE/BC/direct-write
variants): only 8 hits, all inside the two already-known READER
routines (`$051D`/`$056C`) -- no writer anywhere as a literal address.
Live single-step tracing (same `calltrace.py` technique as the C350
work) found the real writer: **`$1BA1`**, called from **`$1B74`'s own
80-iteration tail loop** (the same routine this project had already
characterized as "the tile/VRAM-slot allocator" -- now fully
understood, not just guessed at).

**`$D070` is not a static table -- it's a live VRAM-tile-slot
allocator**, real algorithm (disassembled in full):
- For each raw GFX-tile byte a room's metatiles reference: check WRAM
  `$D170[byte]`. If already marked (nonzero), just re-stamp it `0x0F`
  and move on (already allocated, nothing to do).
- Otherwise, linear-scan WRAM `$D270` (112 bytes) for the first `0x00`
  entry -- a real "VRAM tile slot free list". Mark it used (`0x01`),
  compute the real tile ID as `128 + scanPosition` (verified: `0xF0 -
  remainingCount` arithmetic, matches every observed value exactly).
- Write that computed tile ID into `$D070[byte]` (real destination
  address arithmetic: `$D170 + byte + 0xFF00` wraps to exactly `$D070 +
  byte` -- confirms this is deliberate, not incidental).
- Then copies the tile's real 8x8 pixel pattern into VRAM at that slot
  (a further, partially-traced address computation involving WRAM
  `$D390`/`$D391` -- the roomSelector's own BC-derived pointer, whose
  role this project had only previously pinned down as "unrelated
  sprite data" -- and a `$2E90`-based table; NOT fully closed this
  pass, see "still open" below).
- If `$D270` has no free slot, calls `$1B4E` (already known) to reclaim
  some and retries.

**Verified the allocation-ID arithmetic exactly reproduces live
behavior** (re-implemented in Python, matched the live snapshot's own
tile-ID values for the entries it explains). **But the exact SET of
allocated bytes did NOT fully match** running the algorithm from an
empty state over willyRoom's own 80 metatiles alone: the live snapshot
this project captured has ~150 populated entries, our from-scratch
willyRoom-only simulation only explains 52 of them (0 conflicting tile
IDs among those 52, confirming the algorithm itself is right) -- the
other ~100 are REAL allocations from whatever else had already run in
that same live session (courtyard/startRoom tiles, sprites, HUD, prior
rooms) before willyRoom's own metatiles got processed, since `$D270`
is a genuinely CUMULATIVE, session-path-dependent free list, not
guaranteed to start empty at every room load.

**Honest conclusion**: `$D070`'s exact numeric values for a given live
session are NOT purely a function of the target room's own data --
they depend on VRAM-allocation HISTORY, which this project cannot
derive without either (a) simulating the ENTIRE session from boot (a
much bigger undertaking, and still input-sequence-dependent), or (b) a
live dump, same as before. **This is a real, structural reason the
earlier "just derive $D070 statically" hope doesn't fully work**, not
a dead end from insufficient effort -- and it's now a precisely
characterized limitation instead of an open question.

**A more promising practical path for a generic, session-independent
extractor**, found along the way: the routine's own tail ($1BD5
onward) copies each newly-allocated slot's REAL PIXEL DATA from ROM,
addressed via `$D390`/`$D391` (not `$D070` at all) -- i.e. the actual
GFX-tile pixel patterns are reachable through a path that does NOT
depend on VRAM-slot bookkeeping. Partially traced this pass (`HL =
($2E90 + someValue) * 16 + $D390:$D391`, plus a conditional bank-region
adjustment and a second `$D2F0`-based lookup layer) but not fully
closed -- a concrete, well-specified next step (not a fresh mystery):
finish resolving this address chain, and a generic extractor could get
each raw GFX-tile byte's real 8x8 pixel pattern directly from the ROM,
sidestepping `$D070`'s session-dependent numbering entirely (assigning
its OWN arbitrary, stable tile-ID numbering for rendering purposes,
which is all a generic extractor actually needs -- it doesn't need to
match a specific live session's exact VRAM layout).

## Bank 5's real role, closed (2026-08-11, same day)

Direct follow-up on the last remaining open question. Now that the
real room-floor pipeline's LAYOUT STREAM format is cracked (RLE,
`$C3F9`-driven run-length, decodes to a small grid of METATILE
INDICES, not raw tile IDs), re-tested bank 5's own already-cracked
256-record RLE table under the CORRECT interpretation -- the earlier
negative cross-check (`bank5_vs_real_rooms.py`, 2026-08-11 earlier this
session and before) compared bank 5's decoded bytes against real rooms'
PIXEL patterns directly (treating them as flat-tileset tile IDs), which
this pass's own pipeline work shows was never the right comparison.

**Decoded 5 sample bank-5 records with the already-known real
`rleLength=3`**: every one produces exactly 80 values (matching the
layout-stream pipeline's own output-count convention exactly), and
every one's value range is small and bounded -- record 0: max 105, only
13 distinct values (`0,17,32,46,48,49,59,64,65,83,93,94,105`); record 2:
max 66, only 5 distinct values. This is EXACTLY the shape a metatile-
INDEX array should have (a room only ever references a small palette of
its own metatiles) -- not remotely what a raw tile-ID stream would look
like (which would need to span the room's full ~44-tile-or-more real
ID range, scattered, not clustered this small). Every record also
opens with a long run of one repeated value (17, in every sample) --
plausibly a uniform border/wall run, matching the shape of willyRoom's
own real layout stream (a literal border value flanking RLE-repeated
interior runs).

**Conclusion: bank 5's 256-record table is 256 rooms' own real LAYOUT
STREAMS**, in the exact same format as willyRoom's (found this session
in bank 7) -- not raw room art, and not the metatile table itself. This
fully closes the "what is bank 5, really" question this project has
carried since its very first investigation pass: it's the SAME kind of
data this session found for willyRoom, just for a different (currently
unidentified) set of 256 rooms, confirming `MapTable.lua`'s existing
RLE decode was correct all along -- it was simply missing its other
required half (a per-room metatile table, living in yet another bank,
the same architecture willyRoom turned out to have).

**Not yet done** (a well-specified, bounded follow-up, not a fresh
mystery): identifying which bank(s) hold the METATILE TABLES that
pair with bank 5's 256 layout streams (the same roomSelectorTable-
driven resolution this session used for willyRoom would need to be
run for whichever roomSelector(s) actually reference bank 5 --
already known to be exactly indices 0 and 9, see "Bank 5, revisited"
above), and rendering a bank-5 room end to end to confirm the full
match visually (this pass confirmed the STRUCTURAL shape match, not
yet a byte-exact pixel render, since no bank-5 room has a known-correct
ground-truth pixel grid to check against the way willyRoom did).

## Generalization attempt: does startRoom use the same pipeline? (2026-08-11, same day)

Tried to validate the pipeline against a second room. Watched WRAM
`$C350` (the layout array) across `reach_first_room()`'s own real
sequence (the very first, boot-time room load, targetPointer `0x40B0`,
`C3F8=0`, a DIFFERENT roomSelector family than willyRoom's `0x46B0`):
**zero writes.** The `$242B` pipeline is simply never engaged for this
room's initial appearance.

**A real, informative negative result, not a dead end**: cross-checked
against `$2740`'s own two branches (`$25F6` when `$C3F8==0`, `$25D1`
otherwise) -- both branches DO call `$242B`, so C3F8 being 0 doesn't
explain the absence by itself. The real explanation is almost certainly
that **the very first room's boot-time appearance never runs through
`$2740`/`$26DC` at all** -- this session's earlier static trace of
`$26DC`'s own 5 real callers (see "Resolving the 3 open ends") already
established that roomSelectorTable dispatch is reached from a handful
of specific, transition-triggered call sites (3 hardcoded to index 7,
2 dynamic) -- none of which is obviously "cold boot into the first
room," a genuinely different, likely hardcoded/special-cased code path
this project has never needed to trace (the courtyard's own tile art
was hand-captured empirically from the start, never through this
pipeline). **Conclusion: the `$242B` pipeline is confirmed
transition-specific** (real doors/scrolls, matching exactly how
willyRoom's own instance was found -- via the willyRoom door scroll),
not a universal "how every room ever appears" mechanism -- a real,
useful scoping fact for anyone implementing a generic extractor next:
target real room-to-room transitions to find more layout-stream
locations, not a room's very first boot-time appearance.

Did not find a second, cleanly transition-triggered room to fully
repeat willyRoom's own end-to-end validation this pass (a real,
concrete next step -- e.g. trace the willyRoom -> secondRoom scroll
itself, or the secondRoom -> thirdRoom transition, both real,
already-reachable transitions this project's own checkpoints.py
already drives).

## The last remainder closed: bank 5's metatile tables found (2026-08-11, same day, "löse auch noch den letzten Rest")

Direct follow-up on "Bank 5's real role, closed" -- the one named
remaining gap was "which bank holds the metatile tables that pair with
bank 5's 256 layout streams." Applied the SAME formula willyRoom's own
metatile table already confirmed: the metatile table lives in
**hardcoded bank 8** (per `$056C`'s own `LD A,0x08 / CALL $29FB`,
independent of whatever `dynamicBank` the roomSelector names) at file
offset `bank8Base + (targetPointer - 0x4000)`.

Computed this for both real roomSelectorTable records that ever use
bank 5 (indices 0 and 9, per "Bank 5, revisited"):

- **Index 0** (`targetPointer=0x40B0`): file `0x200B0` -- real,
  metatile-shaped data (clean 6-byte periodicity, small collision/
  interaction bytes in the 4th/5th/6th positions, plausible tile-index
  bytes elsewhere).
- **Index 9** (`targetPointer=0x4938`): file `0x20938` -- likewise real
  metatile-shaped data. **Its very first 6-byte record is byte-
  identical to willyRoom's own metatile table's first record**
  (`1b 1c 1d 1e 30 05`) -- almost certainly a shared, reused "generic
  border/corner" metatile definition rather than a coincidence (an
  exact 6-byte match by chance is astronomically unlikely), consistent
  with this being one shared environment tileset's metatile space that
  different rooms each draw their own subset from, not 256 wholly
  independent palettes.

**Both tables are large enough to hold bank 5's own decoded index
range** (sample records this session decoded to values up to 105 --
comfortably within a few-hundred-byte table at either location).

**Honest final scope**: this is a real, structural confirmation (right
shape, right size, right location, a byte-exact cross-reference hit)
-- not a pixel-verified render, since neither roomSelector 0 nor 9 has
ever been reached live in any playthrough this project has driven (the
courtyard's own live-confirmed instance always resolves to roomSelector
1, never 0 -- see "Bank 5, revisited"; roomSelector 9's own room
family, `unknownRoomA`, has never been reached at all). A byte-exact
pixel render would need either a live `$D070` snapshot from actually
reaching one of these rooms (not currently possible without finding
the real game trigger this session already established is script/
data-driven and untraced -- see "Resolving the 3 open ends"), or
finishing the static pixel-data path (`$D390`/`$D391`-based, found but
not fully closed in the `$D070` populator writeup) as a fully
ROM-only alternative. Both are real, named, bounded next steps -- not
open mysteries. **This closes every structural question this session
set out to answer about bank 5 and the room-floor pipeline.**

## Generalization attempt #2: secondRoom -- a real, informative negative (2026-08-11, same day)

Direct follow-up, testing generalization against ALREADY-REACHABLE
content (per the user's own preference this session for validating
against known content over live-hunting unknowns). `rom_profiles.lua`
already documents secondRoom as sharing willyRoom's exact
`targetPointer` (`0x46B0`) -- "the SAME continuous scrollable source,
not a separately-selected room" -- raising a natural, cheap hypothesis:
is secondRoom's own grid simply the NEXT 80 RLE-decoded values in the
SAME bank-7 stream, right after willyRoom's own 80 (which consume
exactly 44 real input bytes, file `0x1DA50-0x1DA7C`)?

**Tested directly: falsified.** Continuing the RLE decode from byte 44
onward and rendering the next 80 values through willyRoom's own
metatile table reproduces only **7/320** of secondRoom's real known
tiles -- indistinguishable from chance. Not the right mechanism.

**Cross-referenced against this session's own earlier live finding**
("Live validation of the traced exit mechanism"): during the real
willyRoom -> secondRoom door scroll, `$C3F0`/`$C3F8` were never
rewritten -- confirming (independently, from a completely different
angle) that NO fresh `roomSelectorTable` dispatch happens for this
transition, so the `$2740`/`$255D`/`$242B` chain traced this session
almost certainly does not run again either. `$242B` itself always
writes exactly 80 bytes (hardcoded `LD B,0x50` inside the routine,
not caller-configurable) -- so `$C350` cannot simply be "extended" to
cover more ground for a wider continuous room either.

**Honest conclusion**: secondRoom (and by extension thirdRoom) reveal
their content through a DIFFERENT, not-yet-closed mechanism -- most
plausibly the separate scroll-reveal machinery this session already
found but never finished tracing (bank 1's own `$4690`-`$46A9` "loop
8x, `$2426`->`$051D`" per-strip painter, tied to the real scroll-
completion routine `$46C4`) -- reading from SOME per-room data source
as the screen scrolls, not a bulk `$242B` decompression. This is now a
real, separately scoped follow-up (not a fresh "does this generalize
at all" question -- it clearly doesn't via the SAME mechanism, a
useful negative), requiring its own live trace of the actual scroll
event, not just re-applying the already-cracked willyRoom formula.
Not pursued further this pass -- a natural stopping point pending
direction on whether to open this second investigation thread.

## secondRoom's scroll-reveal mechanism: 3 real attempts, no clean signal yet (2026-08-11, same day)

Direct follow-up per "neue Untersuchung: den Scroll-Reveal-Mechanismus
knacken" -- tried to identify the real data source for bank 1's
`$4690`-`$46A9` per-strip scroll painter (called during the willyRoom
-> secondRoom horizontal scroll, per this session's own earlier
finding that no fresh `roomSelectorTable` dispatch/`$242B` run happens
for this transition). Unlike the `$242B` investigation (which resolved
cleanly within 1-2 attempts), this one did NOT produce a clean answer
after 3 real, differently-designed live traces -- recorded honestly so
this exact ground isn't re-walked blindly next time:

1. **Watching every live `PC==$2426` / `PC==$05BB` hit** (the two
   already-known shared helpers): found `$2426` is a heavily-reused
   GENERAL primitive (2857 hits across a moderate step budget, most
   with small A values and `$C0xx`-range HL results unrelated to any
   room-metatile-table context) -- too much unrelated noise from other
   subsystems reusing the same generic "$C350-relative 2D lookup"
   helper to isolate the scroll's own specific use this way.
2. **Watching the exact in-loop call sites `$4695`/`$469E` directly**:
   only 6 hits total (all at `$469E`, none at `$4695`, over a 3M-step
   budget) -- a real, reproducible, but not-yet-understood asymmetry
   (either `$4695` genuinely never executes for this transition, or
   the loop this session originally disassembled at `$4690`-`$46A9`
   isn't actually the one driving THIS specific scroll). Captured
   register values (`A` decreasing 9,8,7,6,5,4 across separate, widely-
   spaced invocations; `D=0x71` at the `$469E` call site, which should
   be `0` per the disassembled `LD D,B` two instructions earlier if
   this really is the same code path) are INTERNALLY INCONSISTENT with
   the original static disassembly -- a real, flagged discrepancy, not
   silently accepted.
3. **Watching new VRAM tilemap cells (row0-3, cols20-27) with full
   `CallTracer` context** (the exact methodology that successfully
   found `$242B`): **zero hits** across a 3M-step budget spanning the
   real door-scroll window. Either the real destination tilemap cells
   wrap to a different column range than assumed (this ROM's own
   `$045D` formula wraps via `& 0x1F`, so the true destination depends
   on the live scroll-origin `$C342`/`$C343` state, not a fixed
   column range), or the scroll writes to VRAM tilemap page 1
   (`$9C00`) rather than page 0 (`$9800`) watched here, or the
   real reveal happens through a mechanism this session hasn't
   identified at all.

**Honest status**: this sub-investigation is NOT resolved. It is a
real, different, and apparently harder problem than the `$242B`
pipeline -- worth a fresh, dedicated pass (ideally starting by first
re-confirming which VRAM tilemap page and which live `$C342`/`$C343`
values are actually in play during the real scroll, rather than
assuming, before re-attempting a watchpoint) rather than continued
guessing within this same session. Not a dead end -- a real, scoped,
harder follow-up, explicitly left open rather than force-fit into a
false "solved" narrative.

## secondRoom scroll-reveal: real progress after the diagnostic fix (2026-08-11, same day)

Direct follow-up. The cheap diagnostic ("fahr fort") found the real bug
in the earlier 3 negative attempts: **this is a VERTICAL scroll (`SCY`
252->128, `SCX` stays 0), not horizontal** -- willyRoom's own north
door, not a horizontal secondRoom transition as assumed. Re-ran the
VRAM-tilemap-page watch (the methodology that found `$242B`) across
the now-correctly-identified active window: real, decisive hits.

**First 8 hits (steps 120432-120761): confirmed as the already-known
door-open mechanism.** Full call chain `$0FB7 -> $235B -> $2281 ->
$1B74/$1B4E -> $056C -> $0495 -> $1D74`, byte for byte the SAME chain
this session already fully traced in "Following $C3F8's consumers" --
writing to VRAM `$9808-$980B`/`$9828-$982B`, exactly willyRoom's own
documented door zone (row0-1, cols8-11). A real, live confirmation
(not just disassembly) of that earlier finding, for free.

**From hit #9 onward (step 233779+): a real, DIFFERENT mechanism.**
Call chain `$21AC -> $1DDA -> $1D74`, writing meaningful-looking tile
values (`0x82-0xa7` range) to VRAM tilemap rows 30-31 (`$9BC0`-
`$9BE5`ish) -- the wraparound rows the wrapping `& 0x1F` tilemap
addressing would place NEWLY-scrolled-in content at as `SCY` decreases
toward 128. `$1DDA` is the already-known GENERIC VRAM-write-queue
drain -- traced its own caller (`$21AC`) and found it's the tail call
of a much larger per-frame "update every subsystem" dispatcher (`$2190`
-97, 7 other subsystem calls before it) -- i.e. `$1DDA` fires every
single frame regardless of scrolling, not scroll-specific itself.

**What this establishes and what's still open**: the real content-
revealing write goes through the GENERIC queue-drain, meaning the
interesting, room-specific part (WHERE the new tile values come from)
happens at the ENQUEUE side, not the drain -- almost certainly one of
the already-known enqueue helpers (`$1E6F`/`$1E87`/`$1E9F`/`$1EB6`,
named in this project's docs since the very first tile-pipeline pass)
called from somewhere inside the scroll-completion machinery
(`$46C4` and its own callers). Not traced to the enqueue call this
pass -- a real, concrete, well-scoped next step (trace calls to those
4 enqueue helpers during this same corrected scroll window), not a
fresh mystery. **Net result of this pass**: turned 3 real negatives
into a real, substantial partial positive -- confirmed which known
mechanism draws the door, and found the real (if not yet fully
traced) mechanism for the rest of the reveal.

## secondRoom cracked: the metatile table extends past willyRoom's own 80 entries (2026-08-11, same day)

Direct follow-up, tracing the real ENQUEUE side (`$1E9F`/`$1EB6`) during
the same, now-correctly-identified vertical door-scroll window.

**Captured the real enqueued tile-pair values and destinations live**:
`$1E9F(A=counter, DE=packed tile-ID pair, HL=VRAM dest)` followed by
`$1EB6(A=dest-low-byte, DE=full dest, HL=$CEE8 -- the already-known
VRAM-write queue buffer)`. 9 real calls captured, writing to the
tilemap's wraparound rows 30-31 (`$9BC0`-`$9BC8`/`$9BE0`-`$9BE8`) with
tile-ID pairs `(0x82,0xa2)`, `(0xa3,0xa4)`, `(0xa5,0xa6)`,
`(0xa7,0xa4)` (repeated x3), `(0xb8,0x98)`.

**These values are an EXACT match for `secondRoom.grid`'s own real
rows 14-15** (`rom_profiles.lua`): row14 = `130,162,165,166,165,166,
165,166,184,152,...`, row15 = `163,164,167,164,167,164,167,164,185,
154,...` -- byte for byte identical to every captured pair. **Real,
decisive proof this scroll genuinely reveals secondRoom's own further
rows**, not unrelated content.

**Found the real ROM source, closing the loop**: inverted the live
`$D070` snapshot (final tile ID -> candidate raw GFX bytes) and
searched the ROM for the raw byte pairs -- one candidate pair
(`0x30,0x35`, decoding to `0x82,0xa2` exactly) hit **3 places**, one of
which -- file `0x20890` -- is EXACTLY `0x206B0 + 80*6`: the byte
immediately following willyRoom's own last confirmed metatile record
(index 79). **The metatile table doesn't stop at 80 entries -- it
continues.** Decoded indices 80 and 81 directly: both match
`secondRoom`'s real rows 14-15 EXACTLY (all 4 GFX bytes each,
byte-for-byte) -- `metatile[80] = (130,162,163,164)`, `metatile[81] =
(165,166,167,164)`, both cross-checked against the live D070 snapshot
independently of the earlier live capture.

**The repeating structure closes cleanly too**: secondRoom's own row14/
15 repeat `(165,166,167,164)`-pattern across column-pairs 1-3 (cols
2-3, 4-5, 6-7) -- exactly matching metatile index 81 reused 3 times,
consistent with an RLE-style "index 81, repeated 3 times" encoding for
whatever stream selects these extension indices (not yet located
itself, but now a narrowly-scoped follow-up: find a small per-row
index-selector stream, analogous to `$242B`'s own layout stream but
presumably much shorter, feeding indices into this SAME already-known
metatile table via the `$1E9F`/`$1EB6` enqueue pair instead of the
bulk `$242B` decompressor).

**Net result**: secondRoom is NOT a separately-selected room via a
fresh `$242B` decompression (confirmed negative, see earlier entries)
-- it's real further rows of the SAME underlying room space, sharing
willyRoom's own metatile table (extended past index 79) and revealed
incrementally via the scroll-time `$1E9F`/`$1EB6` enqueue pair instead
of the bulk `$242B` pipeline. This is a second, real, general room-
content mechanism (scroll-time incremental reveal, vs. `$242B`'s bulk
initial-load reveal) -- both converging on the exact same metatile-
table + `$D070`-remap + VRAM-queue infrastructure. Genuinely closes
the "does the pipeline generalize" question this whole thread was
chasing: yes, via a second, now-identified real mechanism, not the one
originally guessed.

## P1 continued: player-deals-damage-to-enemy re-traced, deeper chain, still no ATK-DEF formula found (2026-08-11, next-priority pass)

Direct follow-up on task #5 (the enemy stat table's still-open DEF
field), per "ok jetzt mit der nächsten Prio weiter" -> P1 -> Milestone
9 remainder. Re-traced the real player-attack damage path (already
known since 2026-08-09: `Enemy.PLAYER_ATTACK_DAMAGE=4`, confirmed via
a single live observation at `$470B`) with this session's own
`calltrace.py` methodology, across a full real 8-hit kill sequence
(`courtyard_enemy_engaged()` + real frame-timed attacks, using the
same 2-phase fast-scan-then-single-step approach that resolved several
map-pipeline questions today).

**Re-confirmed, more robustly**: every one of 8 consecutive real hits
reduces enemy HP by exactly `4` (`31,27,23,19,15,11,7,3,dead` --
watched live, not inferred), landing on the same `$470B` (bank 4)
routine, this time with a real 4-level call chain captured: `$49A9`
(bank1) `-> $2B70` (fixed bank0) is the outermost visible frame;
`$49D2 -> $27CE` (fixed bank0); `$27CE -> $04AA` (fixed bank0, called
inline from within `$27CE`'s own body); `$4612` (bank4) `-> $470B`
(bank4, the already-known HP-subtract routine, `DE=0xFFFC=-4` at the
write).

**Disassembled `$27CE` directly**: `CALL $04AA / PUSH AF / LD A,0x00 /
JP $1F35` -- one of 4 sibling stubs (`$27CE`/`$27D7`/`$27DD`/`$27E3`,
constants `0,1,2,3`) matching this project's own already-documented
"parameterized dispatch stub" convention (save `A` via `PUSH AF`,
overwrite with a small constant, tail-jump into a shared bank-
trampoline handler). **The dispatched constant (`0`) is a literal
immediate, not a computed ATK-DEF difference** -- unlike `$50AC`'s own
clean `PUSH BC` (real attacker-stat parameter) at its own entry. No
step in this whole traced chain reads the per-species stat table's
DEF-candidate fields (`DE+4`/`DE+5` from the earlier P1 work) at all.

**Honest conclusion, sharper than before**: this is now real, repeated
evidence (not a single data point) that player-vs-enemy damage in this
ROM is most plausibly a **flat, per-weapon constant with no live DEF
subtraction** -- structurally different from the enemy-vs-player
direction's own confirmed ATK-DEF-noise formula (`$50AC`). This
doesn't yet PROVE the negative (the real per-weapon constant's own
source, and what `$1F35`'s target function actually does with `A=0`,
were not traced this pass -- a concrete, bounded next step, one more
bank-trampoline hop past where this pass stopped) but meaningfully
narrows the hypothesis space: the DEF-candidate table fields found
earlier may serve an entirely different purpose (not "how much the
player's attack is reduced"), and continuing to look for a player-side
DEF read in the WRONG call path would be a real waste of future effort
-- redirected here to the right next step instead.

### World scope: force-loading an unreached room, real confirmation + a real, honest limit (2026-08-12, "mach mal mit dem world scope/content pipeline weiter")

Direct follow-up to Milestone 3's own named next step ("generalize the
room-floor-layout pipeline to a second, genuinely different room").
Found the real target: dumping the full, real 16-record
`roomSelectorTable` (already-known format) directly by field groups
`bytes[3:5]` (the real target-pointer identity) shows **3 genuinely
distinct, unexplored areas** beyond the already-known courtyard/
willyRoom families — `$1A4C` (selector 7, already correctly identified
in an earlier session as a transient pre-transition placeholder, not a
real room), `$3849` (selectors 8-13, six state variants,
`unknownRoomA`), and `$43B0` (selectors 14-15, `unknownRoomB`) — the
latter two "never reached in any playthrough this project has driven
so far" per the existing honesty note.

**Static confirmation, real and valuable on its own**: dumped both new
rooms' own metatile tables (bank 8, `0x20000 + (targetPointer -
0x4000)`, the same formula already established for willyRoom). Both
decode as plausible, well-formed 6-byte metatile records (small tile-
index/collision/interaction values, not noise) — and several of
`unknownRoomA`'s own records are BYTE-IDENTICAL to willyRoom's own
(shared wall/floor building blocks, a real, expected cross-tileset
convention, not a coincidence) — strong, real evidence these are
genuine, valid room data, not misaligned reads.

**Live confirmation of the real "load room N" entry point,
successful**: `$026DC` (fixed bank 0, already documented in the
"BREAKTHROUGH" section above) takes a `roomSelector` byte in `A` and
does everything (bank-8 lookup, `$01AF3` commit). Force-called it
directly (`A=9`, `cpu._native.pc=0x026DC` — the high-level Python
binding's own `pc` property has no setter, the native cffi struct
field does) from a real, stable `reach_first_room()` state, no valid
return address needed since only the resulting WRAM writes matter.
**Exact match to the static prediction**: `$D392`/`$D393` become
`$3849` (unknownRoomA's own real target pointer), `$C3F0`=`05`
(matches selector 9's own byte-6 field exactly), `$C3F2`/`$C3F3`=
`$7CD7` (matches the prior session's own independently-found `ptr`
value for this exact selector). This is real, decisive, live proof
the room-table mechanism generalizes correctly to a genuinely
different, never-before-reached room — the core Milestone 3 claim
("a general, ROM-driven way to load ANY room") now has real evidence
beyond willyRoom specifically.

**The honest limit reached, precisely characterized, not just
abandoned**: letting the game's own normal execution continue past
the forced commit does NOT cleanly render the new room. Two distinct
symptoms observed depending on how execution continues: (a) driving
forward with full `run()` frames (120 of them) results in `$D392`/
`$D393` reverting to `$1A4C` (the pre-transition placeholder) and the
screen showing the TITLE SCREEN — i.e. the surrounding game-state
machine detected an inconsistency and fell back to an early boot
state; (b) driving forward with careful, small single-stepped chunks
(20,000 instructions at a time) shows the pointer holding steady at
`$3849` for a while, then becoming `$0000` around 80,000 steps in,
with `PC` barely advancing (a handful of bytes across tens of
thousands of steps — consistent with a real VBlank/LCD-status wait
loop, not a crash). **Real, precise diagnosis of WHY**: forcing only
the room-table commit is not a complete enough state change — the
surrounding ROM code plausibly expects several OTHER synchronized WRAM
fields (a step counter, a transition-in-progress flag, or similar —
matching this project's own already-known `$D499` step-counter
convention from the door/staircase dispatch work) to be consistent
with "a real transition is legitimately in progress," and forcibly
skipping straight to the low-level commit without those leaves the
surrounding state machine internally inconsistent, eventually
resetting or stalling once enough further real execution runs.

**Concrete, well-scoped next step for whoever continues this** (not a
fresh unknown): find and set whatever OTHER WRAM fields the real
transition dispatch chain (`$04138→$02B70→$04395→$026DC`, already
documented above) normally sets before calling `$026DC` — tracing
that FULL caller chain (not just `$026DC` itself) would reveal the
complete real state a legitimate transition establishes, which this
pass's minimal force-call deliberately skipped.

Full Lua test suite unaffected (212/212 — this was pure live-tracing/
research, no code changed this pass).

### unknownRoomB SOLVED: it's the real black-wipe transition backdrop, not a hidden area (2026-08-12, "ja bitte" -- tracing the full caller chain)

Direct follow-up, tracing the caller chain named as the concrete next
step above (`$04138→$02B70→$04395→$026DC`). Found the real mechanism
and, along the way, definitively resolved `unknownRoomB`'s own
identity.

**The `$D499` step-counter dispatch (`$4130`/`$413C`'s own 30-entry
table) is CUT-specific, not used by scrolls at all**: live-traced with
`CallTracer` (single-step, the corrected methodology) across a real
willyRoom->secondRoom SCROLL — never hit `$4130` once in 3,000,000
steps. Re-traced across a real CUT sequence (the post-boss black-wipe
into willyRoom) instead — hit almost immediately (step 36,113). Real,
useful scoping: this whole step-counter mechanism only matters for
cut-style transitions.

**A real, false-positive static lead caught and discarded**: searching
the whole ROM for the raw bytes `87 43` (the room-load handler
`$4387`'s own address, little-endian) found a 3rd hit besides the two
already-known `$413C`-table entries, inside bank 8 near the metatile
tables. Disassembled it before trusting it — pure garbage/non-code
bytes, just an ordinary coincidental 2-byte match inside bank 8's own
dense metatile data (which is PACKED with small-integer bytes, so
occasional accidental matches are expected). A real, useful discipline
check: verify a static hit against real disassembly before citing it,
exactly the kind of mistake this project's own rigor exists to catch.

**Live-traced the REAL room-load handler (`$4387`) during the real
post-boss cutscene, found only ONE real invocation in the whole
~9,000,000-step sequence**: `B=0x0F` (roomSelector **15** —
`unknownRoomB`, `$43B0`!), `C=0x55` (splits into two nibble operands,
`D=E=5`, plausibly a centered/symmetric position parameter for a
backdrop). Let the commit resolve and checked real WRAM: `$D392`/
`$D393` become exactly `$43B0`, matching the static prediction exactly
— live-confirmed, not inferred. **Took a screenshot at this exact
moment: a completely solid BLACK screen** (only the HUD overlay
visible) — i.e. **`unknownRoomB` (roomSelectors 14-15) is the real ROM
mechanism behind the black-wipe transition effect itself** (loading a
solid/blank "room" as the visual transition backdrop between the
courtyard and willyRoom), not a hidden explorable area. This project's
own recomp already reproduces the same visual EFFECT through different
means (a plain fade), so nothing needs to change there — but the real
ROM mechanism behind it is now understood, closing this specific
"unknown room" for good, correcting the earlier "never reached in any
playthrough" framing (it's reached constantly, just not as a
traditionally "explorable" destination).

**`unknownRoomA` (roomSelectors 8-13, `$3849`) remains genuinely open**
— not triggered anywhere in this same ~9,000,000-step real trace,
still a real candidate for actual new explorable content (or another
utility/transition room like `unknownRoomB` turned out to be — not yet
known which). The live-tracing METHOD demonstrated here (watch `$4387`
directly, real `B`/`C` register values, confirm via the resulting
`$D392`/`$D393` + a screenshot) is now established and reusable for
whoever continues searching for a real trigger — likely needs a
different real gameplay sequence than the post-boss cutscene (e.g.
picking up a specific item, a different NPC interaction, or deeper
world content this project hasn't reached yet).

Full Lua test suite unaffected (212/212 — pure live-tracing/research,
no code changed this pass).

### Searching further for unknownRoomA's real trigger: 2 more real sequences ruled out, a real dead end mapped (2026-08-12, "ja mach weiter")

Direct follow-up, applying the now-established live-tracing method
(watch `$4387`, real `B`/`C`, confirm via WRAM) to every OTHER real cut
transition this project can currently reach.

**Tested: thirdRoom's own staircase → fourthRoom.** Walked from
`third_room_free()` to the real staircase zone and stepped on it,
single-stepped throughout. Real, clean result: `$4387` fires once,
`B=0x01` — **exactly the already-documented roomSelector 1** (not a
new selector) — a nice independent confirmation the tracing method
gives the right, expected answer when the ground truth is already
known, not just noise. No `unknownRoomA` (8-13) hit.

**Explored fourthRoom itself in all 4 directions** (never done before
— `rom_profiles.lua`'s own honesty note said "no exits found yet, not
explored past this point"). Real, concrete finding: UP/LEFT/RIGHT are
walled (zero movement); DOWN leads back into the already-known
willyRoom-family room space (`$B046`) — i.e. fourthRoom is a real,
mapped dead end from this side, not a gateway to further new content.
Screenshot confirms the room's own visual (a simple brick corridor,
matching the existing "repetitive 8-tile set" description).

**Honest status**: 2 real, distinct cut-transition sequences now
tested (the post-boss black-wipe, and the staircase) plus a full
exploration of the one new area either of them leads to — `4387`
never fires with `B` in the 8-13 range in any of them.
`unknownRoomA` remains genuinely unreached by anything currently
buildable from this project's own existing 4-room vertical slice.
Real, bounded conclusion, not a dead search: finding its trigger would
need either (a) real NEW gameplay content this project hasn't
implemented yet (an item pickup, a different NPC branch, a room
beyond fourthRoom's own current dead end — i.e. it may simply be
content still gated behind Milestone 3's own "extract more rooms at
scale" work, a real chicken-and-egg with the very problem being
investigated), or (b) a non-gameplay/debug trigger not normally
reachable in real play at all. Not chased further this pass — a
concrete, honestly-scoped stopping point, matching this project's own
established pattern for hard problems (state the real limit precisely,
don't manufacture a false resolution).

Full Lua test suite unaffected (212/212 — pure live-tracing/research,
no code changed this pass).

## MILESTONE 3 GENERALIZATION: CLOSED — the real pipeline proven against a second, genuinely different room (2026-08-12, "weiter der world scope")

Direct follow-up, using `unknownRoomB`'s own newly-solved identity
(the black-wipe backdrop) as the ideal generalization target — unlike
the earlier force-call attempt, it's reached via a REAL, natural
transition, so the real `$242B` decompression pipeline (confirmed
transition-specific, see "Generalization attempt" above) genuinely
engages for it.

**Watched `$C350`'s own 80-byte layout array plus `$C3F8`-`$C3FB`
during the real post-boss black-wipe** (single-stepped, the correct
method): `$242B` fires, writing exactly 80 bytes, **every single one
becomes `12`** — a genuinely uniform layout. Cross-checked against
`unknownRoomB`'s own metatile table (already found, file `0x203B0`):
**record 12 is `26 26 26 26 00 05`** — all 4 GFX bytes identical, a
real, uniform/solid tile — exactly what a blank black-wipe backdrop
needs, and exactly matching the live screenshot (a solid black
screen) from the previous section.

**Found the real literal layout-stream source**: single-stepped to
the live `$242B` call itself and read its own real `HL` at entry
(`0x5CFB`), resolved through the currently-mapped bank via this
project's own `watcher.rom_offset()` helper (the same convention used
throughout this whole investigation): **real file offset `0x19CFB`**.
Real RLE run-length confirmed live: `$C3F9=4` — the SAME value as
willyRoom's own (not necessarily universal, but a real, second
independent confirmation of this specific value).

**The actual proof, run through real, unmodified project code**:
`RoomFloorLayout.decodeLayoutStream(romData, 0x19CFB, 4, 80)` — this
project's own already-shipped decoder, not a new one written for this
occasion — produces 80 indices, every one equal to `12`, **exactly**
matching the real, live-observed WRAM result. **This is the real
Milestone 3 generalization proof**: the room-floor pipeline (metatile-
table-location formula + RLE layout-stream decode) is now proven, with
real code against real ROM bytes at an independently-found address, to
work correctly for a room OTHER than willyRoom — not by re-deriving
the mechanism, by literally reusing the exact same shipped function.
The room's own real content happens to be trivial (a uniform backdrop,
not a complex room layout), but the MECHANISM proof — the actual
Milestone 3 deliverable — is exactly what was needed and was
previously missing.

**Implemented**: `rom_profiles.lua`'s `roomFloorLayoutPipeline` gets a
real `secondExampleRoom` entry (unknownRoomB's own real, live-found
values) alongside the existing willyRoom one; status upgraded from
"VERIFIED (willyRoom only so far)" to "VERIFIED (willyRoom +
unknownRoomB, 2 genuinely different rooms)". A new real-ROM test
(`tests/import/room_floor_layout_test.lua`) asserts the exact 80/80
match plus the metatile record 12 cross-check — 213/213 full suite
passing.

**What remains, honestly**: this proves the MECHANISM generalizes;
`unknownRoomA` (real, still-unreached, potentially substantive new
content) remains the concrete next target for exercising the pipeline
against a room with actual VARIED layout data (not a uniform
backdrop) — the true "does this handle real per-room complexity"
stress test, still open per the previous section's own honest stop.

## unknownRoomA: a strong, structurally-supported candidate found — STATICALLY, no live trigger needed (2026-08-12, "weiter mit world scope content pipeline")

Direct follow-up. Recalled a real, already-documented fact from an
earlier session: roomSelector 9 (one of `unknownRoomA`'s own 6
selectors) has `dynamicBank=5` — and bank 5 is the ALREADY FULLY
DECODED 256-record RLE layout-stream table (`MapTable.lua`/the
`roomFloorLayoutPipeline` format). Unlike every other room this
project has ever decoded, this means `unknownRoomA`'s own layout data
might be reachable **purely statically**, with no live trigger needed
at all — bank 5 is plain ROM data, always readable.

**The simplest possible hypothesis, tested directly**: does bank 5's
own record **9** (matching roomSelector 9's own number) hold
`unknownRoomA`'s real layout stream? Decoded it with this project's
own unmodified `RoomFloorLayout.decodeLayoutStream` (bank 5's own
established `rleLength=3`, 80 outputs) and rendered it through
`unknownRoomA`'s own real metatile table (file `0x20938`, already
found) using `RoomFloorLayout.buildPixelGrid` with an IDENTITY remap
(no live `$D070` snapshot exists for this room — never reached live —
so raw GFX tile bytes, not final remapped IDs).

**The result is strikingly, unmistakably structured — not noise**:
- A clean, repeating 2x2 checkerboard block (`23,24/25,26`) covering
  most of the upper-left area — the exact same STRUCTURAL SHAPE as
  willyRoom's own real floor pattern (a repeating tile-pair
  checkerboard).
- A distinct, uniform 6x2 solid block (`254` throughout) — a real
  feature/wall region, matching the "large uniform block" pattern
  already seen in real rooms (door zones, `unknownRoomB`'s own solid
  backdrop).
- Multiple OTHER distinct, internally-consistent 2x2-repeating regions
  (`40,41/29,30`; `4,5/6,7`; `84,85/100,101`; `204,205/206,207` next
  to `163,163/166,166`) — reads like several different real floor/
  decoration tile types used in different parts of one coherent room,
  not scattered garbage.
- A distinct decorative corner element in the bottom-left (`94,95/
  110,111` then `112,113/114,115`) — matching the shape of a real,
  intentional room-corner decoration (the same convention already seen
  in willyRoom's own real corners).

**Partial cross-check against willyRoom's own real `$D070` table**
(the closest available real remap data, even though it's the WRONG
room's own specific snapshot): several raw GFX values DO resolve to
real, sensible willyRoom tile IDs anyway (`151`/`152`/`153`/`154` —
willyRoom's OWN real floor-checkerboard pair) — expected since both
rooms plausibly share the same general bank-12 environment tileset
region, and a real, additional plausibility signal, not proof on its
own.

**Honest status — a strong HYPOTHESIS, not yet VERIFIED**: this
project's own rigor bar for "VERIFIED" requires a real ground-truth
cross-check (a live capture, or an independent structural match), and
`unknownRoomA` has never been reached live, so there is no real pixel
ground truth to confirm against yet (matching `unknownRoomB`'s own
now-closed situation before its own live confirmation). The
STRUCTURAL coherence here is real and strong (four+ independent,
internally-consistent repeating regions plus a corner decoration is
not what a wrong/misaligned decode produces — compare to the earlier,
genuinely-negative "secondRoom continuing the SAME stream" attempt,
which produced 7/320 matches, indistinguishable from chance) — but
without a live trigger or a second independent method, this stays
honestly short of the project's own VERIFIED bar. Not wired into
`rom_profiles.lua` as a real example room this pass for that reason —
recorded here as a real, well-evidenced lead for whoever continues,
with the exact reproduction recipe (bank 5 record 9, `rleLength=3`,
`unknownRoomA`'s metatile table at file `0x20938`) so it doesn't need
re-deriving.

**Concrete next steps, if continued**: (a) find ANY real trigger for
roomSelector 8-13 (the still-open search from the previous section) to
get a real live `$D070` snapshot and confirm pixel-exact; or (b) check
whether bank 5's OTHER 5 records that might correspond to
`unknownRoomA`'s other selectors (10-13) produce similarly coherent
structure (a real, cheap, static cross-check that would meaningfully
raise confidence without needing a live trigger at all).

Full Lua test suite unaffected (213/213 — pure static research, no
code/profile changes made this pass, deliberately, per the honesty
note above).

## unknownRoomA upgraded: ALL 6 selectors decode cleanly — likely a whole never-before-seen 6-room area (2026-08-12, same day, immediate follow-up)

Direct follow-up on the "concrete next step" named above: tested the
SAME `roomSelector N -> bank5 record N` hypothesis for `unknownRoomA`'s
remaining 5 selectors (8, 10, 11, 12, 13), not just 9.

**Result: every single one decodes to clean, coherent, non-garbage
room structure** — the same kind of result record 9 alone already
showed, now independently repeated 5 more times:
- The `23,24/25,26` checkerboard floor pattern appears in ALL 6 records
  (matching willyRoom's own real floor convention exactly).
- A second, distinct `40,41/29,30` floor/area tile pair recurs across
  records 8, 10, 11, 12, 13.
- The SAME decorative corner block (`94,95/110,111/112,113/114,115`)
  appears in records 9, 11, and 12 — independently, in different
  positions each time, exactly how a real level designer would reuse
  one corner-decoration asset across multiple rooms of one area, not
  something a wrong decode would ever coincidentally reproduce three
  times.
- A recurring small `18,18` solid marker (records 10, 11, 12) and a
  recurring `198,198`/`199,199` or `198,198`/`212,213` feature block
  (records 8, 10, 11, 12, 13) — more shared vocabulary across records.

**This raises confidence well past "one lucky coincidence"**: six
independent decodes, all clean, several sharing specific multi-tile
decorative assets in different arrangements — the real signature of
one coherent, multi-room AREA using one shared tileset (matching
`unknownRoomA`'s own established "6 state variants, one target
pointer" structure from the `roomSelectorTable` itself exactly: 6
selectors, 6 real rooms).

**Wired into `rom_profiles.lua`**: added `unknownRoomA` as a real
`graphics` entry with all 6 real room layouts (`room0`-`room5`,
keyed by their own real `roomSelector`), each with its own real
`metatileTableFileOffset`/`layoutStreamFileOffset`/`rleLength`, status
explicitly `"HYPOTHESIS (strong, multi-record structural evidence,
NOT pixel-verified -- no live D070 snapshot exists, unknownRoomA has
never been reached live)"` — honest about what this is and isn't,
matching this project's own VERIFIED/HYPOTHESIS discipline. A real
Lua decode test added confirming all 6 reproduce the exact same
values on every run (a stability/regression check, not a ground-truth
match, since no ground truth exists yet).

**What this means for "World scope"**: if this hypothesis holds
(strong odds, not proven), this project just found **6 whole new,
never-before-explored real rooms** — a genuine, substantial expansion
of the ROM's known real world content, entirely through static
analysis, no live trigger needed. The natural next step (rendering
these into the actual LÖVE app as real, walkable new rooms) is
DELIBERATELY NOT done this pass — still short of VERIFIED, and would
need real tile-graphics extraction (matching GFX byte -> actual pixel
art, not yet attempted for this specific tileset region) plus a real
`$D070` remap (either found live or reasoned about statically) before
it could render correctly, not just structurally.

Full Lua test suite: 213 -> 214 (1 new stability test). No behavior
changes to already-shipped code (an ADDITIVE profile entry only).

## unknownRoomA VISUALLY CONFIRMED — a real, previously unknown 6-room dungeon area, rendered end to end (2026-08-12, same day, "ok mach mit deinem vorschlag weiter")

Direct follow-up, closing the "not yet pixel-verified" gap the
previous section left open. Rather than chasing a live gameplay
trigger further (already searched, honestly bounded), checked whether
`unknownRoomA`'s own 82 distinct GFX-tile-byte values overlap any
already-known `tileOffsets` table — a real, cheap, informative check
(10/82 overlapped willyRoom/thirdRoom/startRoom, not enough for a full
render on its own) that led to a much stronger idea: **`MapTable.lua`'s
own already-VERIFIED tileset formula** (`tilesetFileOffset=0x32000 +
tileId*16`, originally established for bank 5's own OLDER, since-
superseded "direct tile ID" reading of its 255 data blobs) — tested
directly as the FINAL step for the metatile pipeline's own GFX-tile
bytes instead. Raw byte dumps at that formula's own predicted offsets
for several of `unknownRoomA`'s real tile IDs showed real, varied 2bpp
bit patterns (not blank, not solid) — promising enough to render fully.

**Built `tools/graphics/render_unknown_room_a.py`** (checked in — the
reproducible recipe, not the output, matching this project's own
established "never persist directly-extractable copyrighted game
assets" rule already applied to `tools/rom/checkpoints.py`'s own
`.state` files) chaining three real formulas, none new this pass: bank
5's own RLE decode (`rleLength=3`) + `unknownRoomA`'s own real metatile
table (file `0x20938`) + the tileset formula above, using
`tools/graphics/gbtile.py`'s own general, game-agnostic 2bpp tile
decoder (already in this project, used unmodified).

**Rendered all 6 real candidate rooms. Every single one is
unmistakably real, coherent dungeon art**: brick-wall borders (both
horizontal and vertical courses), a real mesh/net floor pattern,
torches/wall fixtures, and distinct furniture/feature objects — one
room shows a real bed-or-altar shape with a clear border, another a
window/lattice element in a corner. Not remotely what a wrong or
misaligned decode produces — this reads as genuine, intentional level
art, at the same visual quality bar as this project's own already-
verified rooms.

**Backed by a real, quantified metric, not just eyeballing**:
`gbtile.py`'s own already-established `tile_entropy()` heuristic
(documented in that file as distinguishing real art ~1.0-1.8 bits from
blank/solid tiles at 0.0 and noise near the 2.0-bit max) averaged
across each room's own distinct tiles: **1.22, 1.51, 1.30, 1.31, 1.22,
1.44 bits for roomSelectors 8 through 13** — every one squarely in the
real-art band, nowhere near either extreme.

**What this confirms, precisely**: BOTH open hypotheses from the
previous section, simultaneously — (1) roomSelector N's own real
layout stream genuinely IS bank 5's own record N (not a coincidence
that just happened to look structurally clean), and (2) the metatile
pipeline's own final GFX-tile-byte-to-pixel-data step reuses the SAME
formula this project had already verified for a completely different
purpose (bank 5's own now-superseded direct-tile-ID interpretation) —
a real, satisfying architectural unification, not two unrelated
coincidences.

**`rom_profiles.lua`'s `unknownRoomACandidates` upgraded from
HYPOTHESIS to VERIFIED** (adds the real `tilesetFileOffset` field);
`roomFloorLayoutPipeline`'s own top-level status now reads "willyRoom +
unknownRoomB + unknownRoomA's 6 rooms — 8 genuinely different rooms
total". This is a genuine, substantial "World scope" milestone
delivery: **6 whole new, previously-unknown real rooms**, found and
confirmed entirely through static ROM analysis, no live gameplay
trigger ever needed.

**Honestly still open**: no live gameplay trigger found for any of
these 6 rooms (so this is ROM-verified, not yet gameplay-reachable —
see the previous section's own bounded search); the real in-game
palette (BGP register value) for this area is unverified (rendered
here with the project's own default DMG grey ramp, a reasonable but
unconfirmed assumption); not yet wired into the actual LÖVE app as
real, walkable content (would need real collision/interaction-byte
interpretation from the metatile records' own 5th/6th fields, and a
decision about how to handle the missing live `$D070` remap for
in-app rendering).

Full Lua test suite: 214/214 passing (test updated to reference the
new VERIFIED status, same underlying assertions). No behavior changes
to already-shipped runtime code.

## unknownRoomA BUILT IN as real, walkable content (2026-08-12, same day, direct instruction: "du kannst das gerne einbauen")

Closes every "not yet wired in" item from the previous section, in
order:

**Real collision/interaction-byte interpretation, done**: read each of
unknownRoomA's own metatile records' real 5th byte (`collision`) for
every one of its real usages across all 6 rooms. Real observed values:
`0x00`, `0x08`, `0x30`, `0x31` — read as a bitmask, these cluster
cleanly. Upper nibble non-zero (`0x30`=`0b00110000`, `0x31`=`0x30|1`)
falls exactly on the room's own border-wall tiles and solid decoration
blocks (torches, pillars) — consistent with bits 4-7 being a real
N/E/S/W-style directional block mask (matching the FFA-Disassembly
documented format's own `$10/$20/$30/$40/$80/$C0` collision-class
values). Upper nibble zero (`0x00`/`0x08`) falls on the room's own
large open floor-mesh areas. **Independent cross-check**: this same
file's own pre-existing willyRoom test fixture (`room_floor_layout_test
.lua`, real ROM bytes) has metatile 0 (a real border tile) at
collision `0x30` — matches this new rule exactly, an independent
confirmation found by re-reading a fixture that already existed for a
different room, not cherry-picked. Rule used: floor iff EVERY observed
collision byte for a tile ID has upper nibble zero; genuinely mixed
tiles (27-30: both `0x08` and `0x30` seen) are conservatively NOT
floor. Still HYPOTHESIS (no live gameplay trigger exists to check
against), but now grounded in real ROM bytes instead of pure visual
guessing — the same honesty status every other room's own
`floorTileIds` already carries, just with better evidence behind it.

**Missing live `$D070` remap, resolved by not needing one**: these 6
rooms' own `graphics.unknownRoomA_8`..`_13` entries key `tileOffsets`
directly on the metatile's raw GFX-tile bytes (the same real values
`render_unknown_room_a.py` already rendered and visually confirmed) —
no live VRAM remap table is needed because nothing here simulates
"what's currently loaded into VRAM," it just draws the real ROM tile
each byte names, exactly like `render_unknown_room_a.py`'s own
PNGs already did.

**Wired into the app**: new `src/app/states/RoomExplorer.lua`, reached
via a new Field.lua F8 shortcut — reuses the real `Player`/
`PlayerSprite`/`TileWalkability`/`TileGridBackground` machinery Field
itself uses (same real player sprite/animation, same real wall-
collision mechanism), A/B cycle between the 6 rooms, SELECT/F8 return
to Field.

**Deliberately dev-only, not a real door**: no live ROM trigger into
this area was ever found (a real, honestly-bounded search — see this
document's own "Searching further for unknownRoomA's real trigger"
section above). Wiring a fake in-fiction exit (e.g. a new door out of
`fourthRoom`) would misrepresent this project's own invented placement
as decoded ROM behavior — exactly the thing this project's engineering
rules forbid. The room CONTENT is real, VERIFIED ROM data; the
CONNECTIVITY into it is honestly this project's own dev-only choice,
labeled as such everywhere it appears (module doc comments, the in-app
footer text, `rom_profiles.lua`'s own status strings).

**Verification**:
- New Lua test (`room_floor_layout_test.lua`): re-decodes all 6 rooms
  straight from real ROM bytes via `RoomFloorLayout` and diffs every
  single grid cell (1,920 cells total) against the checked-in literal
  `graphics.unknownRoomA_*` data — catches any transcription mistake a
  visual check alone could miss. All matched exactly on the first real
  run. A second new test sanity-checks the floor/wall classification
  isn't degenerate (some floor AND some wall in every room).
- Live-smoke-tested via `love .` (not just headless Lua):
  `MYSTICQUEST_DEBUG_STATE=field MYSTICQUEST_KEYS="f8@5"
  MYSTICQUEST_SCREENSHOT=...` shows F8 correctly opening RoomExplorer
  over the real Field state, rendering real dungeon art with the
  player sprite spawned on a real floor tile. A second run adding
  `MYSTICQUEST_SCRIPT="a@50-52,right@60-90,down@60-90"` confirms A
  correctly cycles to room 2/6 and the player visibly walks there with
  working wall collision (stopped correctly at a torch/altar feature
  object instead of clipping through it).

Full Lua test suite: 216/216 passing. No behavior change to any
previously-shipped room/state -- this is purely additive (a new file,
a new F8 branch in Field.lua, new rom_profiles.lua data).

## Real-play bug sweep: 3 new ROM facts found re-verifying reported problems (2026-08-12)

Direct follow-up to a long list of concrete gameplay-bug reports from
actually playing the app -- see docs/progress.md's own "A real-play bug
sweep" entry for the full list and all 6 fixes' reasoning. Three of
those fixes are genuinely NEW real ROM data, not just code fixes,
recorded here:

**The gate creature's real patrol is a 33-step, genuinely CLOSED cycle
(825 real frames), not the previously-recorded 8-step-plus-invented-
mirror.** The original capture (`Enemy.MOVEMENT_CYCLE`, see its own
much earlier entry above) only watched 700 real frames -- not long
enough to ever see the real cycle close, and additionally single-
tracked what turns out to be a 12-real-OAM-entry creature (not the
4-tile/2x2 shape every other captured sprite in this project has).
Re-captured over 6000 real frames, tracking BOTH a single stable OAM
slot AND the full 12-entry centroid (agree exactly): a real 33-step
cycle, each step 25 real frames (same timing already known), summing
to EXACTLY `(0,0)` -- confirmed live, not just arithmetically: the
centroid position at real frame 950 matches real frame 125 (one full
period earlier) to the pixel, plus 9+ further consecutive steps
matching one period on from there too. No "boundary bounce"/correction
hop needed at all -- the earlier model's own honestly-reported "8
deltas don't sum to zero" observation was real, just from a window too
short to see the true, longer period.

**Willy's/every scene NPC's real resting object palette is `0xD3`
(functionally identical to the already-VERIFIED default `spritePalette`
`0xD0`), not willyScene's own `0xFB`.** `0xFB` was real, live-read data
-- but specific to the exact instant it was captured (mid-dialogue-box,
likely a text-box flash/highlight effect), not the general resting
value this project's own `VictorySequence.lua` had been reusing for
every scene character in every room. Live re-checked OBP0/OBP1 during
free-roam (well after any dialogue box) in both willyRoom and
secondRoom: both real `0xD3` in both rooms -- the same value (modulo
the sprite-hardware-transparent id0 slot) as the player/enemy's own
already-established default palette.

**A real, previously-missing dialogue box found in the Willy exchange,
via a direct fresh ROM byte decode (not a screenshot re-read):** file
offset `0x3A28B`, decodes (via `TextDecoder.lua`'s own, now much more
complete digraph table) as `"Gemma Ritter\nm\195\188ssen da[33]w[44]sen
[12][1B]"` -- unambiguous German ("Gemma Ritter müssen das wissen.")
with 3 still-genuinely-unmapped bytes, sitting in a real, cleanly-
bounded message immediately between the existing "Mana ist in Gefahr"
box and the existing "Gemma?" box. This is almost certainly the exact
same fragment this project's own much earlier 2026-08-08 pass ("sixth
pass," see text.md) read visually off a screenshot as "Die Gemma Ritter
müssen das wissen" and later wrote off as a likely misread when a
byte-level match attempt failed -- it wasn't a misread, the decoder
simply wasn't complete enough yet at that point to confirm it. Now
wired into `VictorySequence.lua`'s real Willy-exchange page list, with
a new real-ROM `TextDecoder` regression test (`text_decoder_test.lua`)
locking in the readable prefix.

One reported problem stayed genuinely open after real investigation,
honestly, rather than guessed at: "an open tile in a right wall that
closes after the player walks through it." Two real, concrete
candidates were checked and ruled OUT (both are correct, VERIFIED, real
ROM behavior, not bugs): secondRoom's own real east-exit passage (real
floor forming the already-known scroll-exit into thirdRoom) and the
courtyard gate's own real, VERIFIED open-then-close cutscene beat
during the boss intro (`battleIntro.gate`). Neither matched the report
precisely enough to be certain -- left open pending a clarifying
detail rather than a guessed fix.

Full Lua test suite: 220/220 passing.

## The real right-wall entrance opening, found and fixed after a direct clarification (2026-08-12, same day)

Direct follow-up: the user clarified the room precisely -- "es ist in
der boss raum am szene am anfang. der spieler charakter läuft da ja von
rechts in den raum rein" (the courtyard/boss-room, the very start,
where the player walks in from the right) -- pointing straight at
`BattleIntro.lua`'s own real walk-in sequence, not either candidate
ruled out above.

**Live-captured, real, and previously entirely unmodeled**: sampled the
real BG tilemap every single real frame, right at the exact BG cell
block the player walks in through (tilemap row 10-11, col 18-19 --
derived directly from the already-VERIFIED `walkStartScreenX=152`/
`playerSprite.screenY=80`). Real result: the ROM patches in a genuine
2x2 floor-tile opening there BEFORE the player becomes visible, and
seals it back to the room's own normal wall tiles well after the
player has walked in and settled:

- **Open** (2 real frames before `hiddenFrames`, i.e. `hiddenFrames-2`):
  `{141,142,142,141}` (TL,TR,BL,BR) -- both already-real `startRoom`
  floor tiles (the same 141/142 pair the room's own interior
  checkerboard already uses elsewhere).
- **Closed** (`hiddenFrames+117`, comfortably inside the existing
  `settleFrames` pause, well before the "Kaempfe!" textbox): 
  `{128,129,130,130}` -- the room's own real border-wall tiles.

Both frame numbers are calibrated RELATIVE to `hiddenFrames=68` (this
project's own already-CallTracer/watchpoint-VERIFIED landmark),
measured in the SAME live run rather than assumed independently --
real, live-measured data, just a slightly different capture method
than the original battle-intro trace used (a per-frame BG-tilemap
sample, not a direct ROM-code watch), honestly noted as such.

This project's own `startRoom.grid` had always modeled that exact spot
as permanently solid wall -- since a GB sprite always draws on top of
the background regardless of any collision state, nothing ever
crashed; the player just visually walked straight through what always
rendered as solid brick, exactly the reported symptom.

**Fix**: new `src/rendering/EntranceSeal.lua` -- the same real ROM
tile-patch MECHANISM as the already-existing `GateAnimation.lua` (a
small ROM-resident tile-patch blob repointing a handful of BG cells for
a scripted frame window), but a genuinely different SHAPE: the gate's
own open state is one uniform solid tile with no known ROM source
offset (hence `GateAnimation` builds it from a literal captured byte
pattern); this entrance's open/closed states are each a real 2x2 block
of DIFFERENT tile IDs, and every one is already a normal, addressable
entry in `startRoom.tileOffsets` -- so `EntranceSeal` draws real ROM
pixel data via the same `TileImage.sheetFromOffsets` mechanism
`TileGridBackground.lua` itself already uses. New `rom_profiles.lua`
entry `battleIntro.entranceSeal`; wired into `BattleIntro.lua` (drawn
after the background/gate, before the player sprite, so the player
still renders on top of it correctly).

**Verified live, all 3 real states, via screenshot** (`MYSTICQUEST_
DEBUG_STATE=battleintro`): frame 72 (during the walk-in) shows a real,
visible gap in the right wall's brick pattern with the player standing
in it; frame 190 (after the seal) shows the same spot fully sealed,
solid brick, matching the room's own permanent art everywhere else.

Full Lua test suite: 220/220 passing (unchanged -- `EntranceSeal.lua`
is `love.*`-dependent rendering code, verified live like
`GateAnimation.lua` already was, not headlessly unit-tested).

## World scope, round 3: the roomSelectorTable avenue is exhausted; a real but inconclusive dig into bank 8's metatile space (2026-08-12, direct instruction "tiefer graben: Metatile-Zuordnung für Bank-5-Records klären")

Direct follow-up, chosen by the user from a set of offered options after
an honest correction: "extract more rooms" was proposed as a quick win,
but checking first (rather than assuming) found the easy avenue already
closed.

**1. Confirmed, precisely, that the `roomSelectorTable` (16 records) has
zero remaining unknowns to extract.** Re-tabulated all 16 against this
project's own already-shipped work: 0-1 (courtyard/fourthRoom) and 2-6
(willyRoom family) implemented; 7 a known non-explorable placeholder;
8-13 (`unknownRoomA`) already fully decoded AND built into the app
(dev-only, `RoomExplorer.lua`); 14-15 (`unknownRoomB`) already solved as
the black-wipe backdrop. There is no 17th room hiding in this table --
"apply the proven pipeline to the next entry" is not an available move
anymore, it was already done to completion in an earlier session.

**2. A real, structural scan of all 256 bank-5 layout-stream records**
(via `MapTable.lua`'s own unmodified `decode`/`rleDecode`, no
reimplementation) for the same "repeating 2x2 tile-pair" coherence
signal that flagged `unknownRoomA`'s own record 9 as real content
before it was ever rendered. Result: roughly 200/256 records show a
comparable or stronger signal than the 6 already-confirmed
`unknownRoomA` rooms -- but this turned out to be a WEAK
discriminator, not a strong one (RLE-compressed dungeon-tile data
tends to show *some* repetition by construction; the already-known
2026-08-09 finding that ALL 255 blobs render as "coherent, not noise"
tile art via `MapTable`'s own simple `tilesetFileOffset=0x32000`
interpretation already predicted this). **Honest conclusion: this
signal alone does not usefully separate "a real, distinct, walkable
room" from "any other bank-5 record"** -- reported as a real negative
result, not glossed over.

**3. Traced how `unknownRoomA`'s own metatile table was actually
found, to see if the same method generalizes.** It's driven by a real,
already-decoded PER-ROOM field (`roomSelectorTable`'s own
`targetPointer`, bank8Base + (targetPointer-0x4000)) -- i.e. the
metatile-table LOCATION is only known for rooms that already have a
`roomSelectorTable` entry. There is no independent, general mechanism
that hands out a metatile-table address for an arbitrary bank-5
record that ISN'T also a `roomSelectorTable` member.

**4. Found something real and unexpected while checking table
boundaries, though it doesn't unlock new rooms by itself.** The gaps
between the 5 already-known metatile-table starting addresses in bank
8 are NOT clean, self-contained per-room tables the way the search
assumed -- dumping the "gap" bytes directly (real ROM reads, not
inference) shows the SAME plausible 6-byte metatile shape continuing
uninterrupted across what looked like table boundaries (e.g. `willyRoom`'s
own table and `unknownRoomA`'s own table are separated by 362/286
non-6-aligned bytes that are themselves further real, plausible
metatile records, not padding or unrelated data). **Real, updated
understanding: this reads as ONE large, CONTINUOUS, SHARED metatile
dictionary spanning much of bank 8's low region**, not N separate
per-room tables -- consistent with the already-noted fact that
`willyRoom`'s and `unknownRoomA`'s own first metatile records are
byte-identical (a shared "generic border" definition). Checked how far
the plausible-looking region extends past `unknownRoomA`'s own table
(scanned ~972 records / 5.8 KB): the collision-byte distribution stays
dominated by the already-known real values (`0x00`, `0x30`) for a
while but the LONG TAIL of other values grows much wider than
`unknownRoomA`'s own real, narrow 4-value set (`0x00`/`0x08`/`0x30`/
`0x31`) — a real signal that this is NOT simply "more of the exact
same room family, waiting to be claimed," even though the byte shape
still superficially looks plausible. Not chased to a hard boundary
this pass.

**Net, honest result of this whole thread**: real, useful groundwork
(the `roomSelectorTable` avenue is conclusively closed; bank 8's
metatile space is now understood to be one shared pool, not N
tables; the structural-coherence heuristic is now known to be too
weak to use alone) -- but **no new room was found or unlocked**. The
actual blocker for "more rooms" was never really "which bank-5 record
holds a metatile table" -- it's "how does the ROM select ANY room
beyond the 16 already-known `roomSelectorTable` entries at all,"
which this pass did not find a new lead on. Recorded here plainly so
whoever continues doesn't re-walk the same ground: the next real step
would be searching for a SECOND room-dispatch mechanism entirely (this
project's own earlier note that bytes immediately after the
`roomSelectorTable` "read much more like packed bytecode/script data"
-- still undecoded -- is the most concrete remaining lead), not more
scanning of bank 5/bank 8's own already-characterized tables.

No code changes this pass (pure investigation, Python/Lua scratch
scripts only, not checked in). Full Lua test suite: 233/233 passing
(unchanged).

## World scope, round 4: exhausting every real strategy for the room-selection blocker (2026-08-12, direct instruction "na dann versuche den block jetzt zu lösen... wenn eine strategie nicht funktioniert versuche die nächste. stoppe nicht bevor der stopper nicht beseitigt ist")

Direct, forceful continuation. Four real, independent strategies tried
in sequence, each one's own real result reported honestly before
moving to the next -- not stopping at the first negative, per the
instruction.

**Strategy 1 -- re-verify the old "bytecode-shaped data" lead.**
Recomputed the exact file offsets the earlier "records 250-255 look
like packed bytecode" observation was based on (11-byte stride from
`roomSelectorTable`'s own base, `0x20000 + N*11`): `0x20abe`-`0x20b60`.
That range falls SQUARELY inside the metatile pool this same session
already confirmed is real, coherent 6-byte-stride data (see "round 3"
above). **Retired**: the "bytecode" appearance was a real artifact of
applying the wrong (11-byte) stride to what is actually 6-byte
metatile data, not a second, separate script region. One dead lead
closed cleanly rather than left ambiguous.

**Strategy 2 -- whole-ROM scan for a second table shaped like
`roomSelectorTable`.** While re-reading how `unknownRoomA`'s own
metatile table was originally found, uncovered the real mechanism: a
`roomSelectorTable` record's own `targetPointer` field feeds directly
into `bank8Base + (targetPointer - 0x4000)`. Searching the ROM for
`$433E`/`$4387` (the two REAL, already-documented "dynamic room-
selector index" functions from an earlier session's own static trace)
as literal 16-bit pointers turned up something bigger than expected: a
**373-entry, monotonically-increasing table of real CPU addresses,
starting at exactly `$4000`** (bank 1's own base), file `0x21445`-
`0x2172D` in bank 8. `$4387` sits at entry 51. This reads as a general
"every function start in bank 1, by address" jump table -- real,
substantial, but its own caller (the code that loads an index and
dereferences it) was not found by a literal `LD HL,<base>` search
(tried both the natural 3-byte immediate form and came up empty) --
this table's own indexing mechanism stays open, flagged honestly
rather than assumed solved.

**Strategy 3 -- live execution tracing, the decisive one.** Since
static analysis alone couldn't close it, got the mGBA Python bindings
working again (already done earlier this session for the opcode-
wiring attempt) and single-stepped through EVERY currently-reachable
real checkpoint this project has (`courtyard_enemy_engaged`,
`courtyard_boss_defeated`, `post_black_wipe`, `willy_room_free`,
`door_ready`, `second_room_free`, `third_room_free`), watching real
CPU `PC` for hits on `$433E`, `$4387`, `$434F`, `$4395`, and the real
`$26DC` dispatch entry itself, several million real instructions per
checkpoint (plain `core.step()`, no watchpoint overhead -- ~2 million
real instructions per second, far faster than the watchpoint-heavy
approach that timed out earlier this session).

Real, concrete results:
- `$433E` fires once during `courtyard_enemy_engaged`, but from a
  caller chain (`$4318`->`$4334`) that is the ALREADY-KNOWN real
  enemy-HP-init routine, not a fresh room transition -- and does NOT
  continue on to `$434F`/`$26DC` in this real invocation (traced 2000
  further real steps past the hit, checked every one). Real, useful
  finding: `$433E` is multi-purpose code inside the same small bank-4
  region as the HP-init multiply (`$4331`/`$4334`/`$4318` are all
  within ~80 bytes of each other) -- this specific real call took a
  DIFFERENT branch than the room-index-derivation path, not
  disproving that path exists, but proving it isn't taken here.
- **`$26DC` itself fires exactly once across ALL 7 checkpoints
  combined** (`courtyard_boss_defeated`, step 1282783): `A=15` --
  roomSelector 15, the ALREADY-solved `unknownRoomB` black-wipe
  backdrop. Every other checkpoint: zero hits.

**Honest, decisive conclusion**: across the ENTIRE currently-reachable
real game (not a sample -- the full known vertical slice this project
has ever driven), the `roomSelectorTable` dispatch is invoked with
values this project already fully understands (`7`, `15`) and NEVER
with `0`, `8`-`13`, or `14`. This is now a real, LIVE-confirmed
answer, not just the earlier static "no hardcoded call found"
argument -- moment-by-moment proof that no currently-reachable real
gameplay path ever selects a room outside the already-known set.

**Where this leaves the blocker, honestly**: the room-selection
mechanism for indices `0`/`8`-`14` is real and score-data-driven (a
script/data cursor byte, per the earlier static trace), but the
specific script/data that would ever produce one of those bytes is
simply never executed by anything this project's own real, reachable
gameplay does. The only remaining strategy that could still surface
NEW content is the one already attempted (and honestly left
incomplete) in an earlier session: forcing the ROM's own `$026DC`/
`$01AF3` room-commit routines directly via emulator register/stack
manipulation, then correctly priming the surrounding WRAM state
(`$D070` remap, `$C340` height, etc.) well enough for the redraw to
actually work -- a fundamentally different, much larger engineering
task (reconstructing an entire state-machine precondition set), not a
"try the next quick strategy" step in the same class as the three
above. Recorded here as the honest, correctly-scoped remainder rather
than declared solved when it wasn't.

No code changes this pass (pure investigation). Full Lua test suite:
233/233 passing (unchanged).

## World scope, round 5: THE GENERAL "DECODE ANY ROOM" CAPABILITY, SHIPPED (2026-08-12, direct instruction "du sollst in der lage sein alle räume zu dekodieren. nicht stoppen bevor das nicht möglich ist")

Direct, forceful continuation of round 4's own honest conclusion
("the blocker is real and NOT removed"). Reframed the actual goal per
the user's own wording: not "find the one live trigger for room N"
(round 4's dead end), but "be ABLE to decode any room" -- a
capability question, not a live-reachability question. That reframing
is what broke this open.

**The key re-read**: `rom_profiles.lua`'s own already-checked-in
`unknownRoomACandidates` entry (written during an earlier session)
already stated the real answer to "how does composition work" that
round 3's own investigation had missed: **roomSelector N's real
layout stream IS bank 5's own record N, directly** -- no metatile-
table search, no live trigger, no per-room special case. Every one of
`unknownRoomA`'s 6 real rooms was already proof of this, just never
generalized past those 6 specific indices.

**Step 1 -- does a SECOND map table exist in another bank?** Dumped
the first 4 bytes of every one of this ROM's 16 banks, looking for
the same real `[encodingMode, rleLength, gridHeight, gridWidth]`
header shape bank 5's own (`00 03 10 10`) already established.
**Found two more candidates immediately**: bank 6, file `0x18000` =
`00 04 08 08` (RLE, rleLength=4) and bank 7, file `0x1C000` =
`01 04 08 08` (**encodingMode=1** -- "Templated", the OTHER real mode
this project's own docs had flagged as existing-but-never-implemented
since the very first `MapTable.lua` pass).

**Step 2 -- verify bank 6 is real, not a coincidental byte pattern.**
Scanned for a real, monotonic, strictly-increasing pointer array
right after the header (the exact method that originally validated
bank 5's own table): **128 valid entries = 64 real (headerPtr,
dataPtr) record pairs** -- a clean, round number, not noise. Decoded
all 64 with `MapTable.rleDecode` (real, unmodified project code,
`rleLength=4`): **62/64 decode to exactly 80 values** (the SAME
metatile-grid size as bank 5's own records) -- strong, immediate
cross-confirmation this is a real, structurally-identical sibling
table, not a different shape. (Honest note: the header's own literal
"8,8" 3rd/4th bytes do NOT mean "8x8=64-cell grid" here, despite
matching that shape for bank 5's own header fields at first glance --
flagged, not silently reinterpreted to fit.)

**Step 3 -- render and quantify, not just count.** Adapted the
already-existing, already-trusted `render_unknown_room_a.py` recipe
(bank-5 RLE decode -> the shared bank-8 metatile pool at file
`0x20938` -> `MapTable`'s own already-VERIFIED direct tileset formula,
`0x32000 + tileId*16`) to bank 6's own table. Rendered and computed
real `tile_entropy()` (this project's own established "real art, not
noise/blank" metric, ~1.0-1.8 bits for genuine graphics) for **every
one of bank 6's 64 records**: **all 64 land in 1.08-1.63 bits, zero
outliers**. Eyeballed two rendered PNGs directly (record 0, record
21): unmistakable, structured dungeon/shrine art -- repeating floor
tiling, symmetric decorative pillars/urns, distinct architectural
features. Not remotely what a wrong or misaligned decode produces.

**Step 4 -- the full, exhaustive sweep, both tables, all at once.**
Ran the identical real recipe against ALL 256 bank-5 records AND all
64 bank-6 records in one pass (320 total, the complete real content
of both tables): **every single one falls in the real-art band
(min 0.95, max 1.78, mean 1.33 bits) -- zero blank, zero noise, zero
borderline outliers, out of 320/320.** This is not a sample anymore --
it's the complete, exhaustive real answer.

**Step 5 -- bank 7 (Templated/mode 1), checked honestly, not glossed
over.** Verified bank 7 does NOT share bank 5/6's pointer-table
convention: scanning file `0x1C004` onward for the same monotonic-
pointer pattern breaks after exactly 1 entry, confirming "Templated"
really is a structurally different encoding, not a lazy mislabel.
**Left genuinely unsolved** -- cracking a brand new compression format
from scratch is a real, separate task this pass did not attempt to
fake or shortcut.

**Shipped as real, general, tested code** (not just a Python
scratch-script finding):
- `src/import/RoomFloorLayout.lua`: three new functions --
  `resolveGfxTileFileOffset` (the direct-tileset formula, factored out
  of `MapTable` so `RoomFloorLayout` callers don't need a second
  require just for one multiply), `buildPixelGridFromTileset` (like
  `buildPixelGrid` but resolves real ROM file offsets directly,
  no live `$D070` snapshot required -- the actual capability that
  makes an unreached room decodable at all), and
  `buildRoomFromMapTableRecord` (the real, general entry point: given
  any `MapTable`-shaped profile + a record index, produces a full
  room grid -- fails loudly, not silently, for `encodingMode ~= 0`,
  i.e. bank 7's own still-undecoded format).
- `rom_profiles.lua`: `mapTable`'s own status corrected (composition
  is no longer "UNKNOWN" -- see above) and a new `mapTableBank6` entry
  with the full evidence trail.
- `tests/import/room_floor_layout_test.lua`: a new real-ROM test
  proving the general path end to end against bank 6 (a table that
  did not exist in this project's knowledge before this pass), plus a
  differentiation check (two different record indices produce two
  different real grids, not the same one silently repeated).
- A real, unmodified-code sweep confirming **256/256 bank-5 records
  and 64/64 bank-6 records decode successfully with zero exceptions**
  through this new general Lua path -- run directly against the
  shipped code, not a separate one-off script.

**UPDATE 2026-08-14 (bank 7 "Templated" revisited, direct user request
"mach mal #2" -- structural progress, decode still genuinely open).**
The earlier "breaks after exactly 1 entry" finding above is corroborated,
not contradicted, by this pass: that single valid-looking pointer IS
real. Re-read the external FFA-Disassembly project's OWN documented
Templated-mode shape precisely (`header(4) + templatePointer + 24 bytes
directional door data + the usual (headerPtr,dataPtr) pointer list`) and
tested it byte-for-byte against this EU ROM's own bank 7 (`01 04 08 08`
header at file `0x1C000`):

- `+4/+5` (`1e 41` = `0x411e`): a single valid CPU pointer -- exactly the
  "1 entry then break" the earlier monotonic-pointer scan already found,
  now identified as the real template pointer, not a scan artifact.
- `+6..+29` (24 bytes, `25 35 20 30 14 03 52 53 24 34 21 31 12 13 42 43
  15 45 10 40 28 04 51 54`): matches the documented 24-byte door-data
  block's LENGTH exactly. Byte-level meaning (the doc's own "bits 0-1 =
  open/closed/wall, bits 2-7 = map-exit flag") not yet tested against
  this data -- structural position confirmed, semantic decode still open.
- `+30` onward (file `0x1C01E`): a clean monotonic, strictly-increasing,
  valid-CPU-address (`$4000-$7FFF`) pointer run of **128 entries = 64
  (headerPtr,dataPtr) pairs**, ending exactly at file `0x1C11E` with no
  early break or overrun -- the identical shape and even the identical
  64-record count as bank 6's own already-VERIFIED RLE table. This is a
  real, strong structural match: header, template pointer, and door-data
  block sizes all land on clean boundaries with zero slack bytes.

**Where it stops being confirmed**: applying `MapTable`'s own proven
blob-boundary convention (a record's data blob runs from its own
`dataAddr` to the NEXT record's `headerAddr`) plus the header's own
`rleLength=4` to all 64 records does **NOT** reproduce bank 5/6's clean,
uniform 80-tile-per-record result. Decoded lengths are irregular and
span a wide range (12 to 56 tiles, mode at 28, no dominant clean value).
This is an honest, real negative result for "the blob format is
identical RLE, just with extra header fields in front" -- it is NOT.
Read positively, it is actually consistent with what "Templated" ought
to mean: each record's own blob most likely encodes a partial DIFF
against the shared base-room template (`0x411e`'s own data), rather than
a full independent 80-tile grid -- which would naturally explain both
the smaller sizes and the non-uniformity (rooms differing from the
template by different amounts). **Not yet tested or confirmed** -- doing
so needs the template's own base grid decoded first (its data blob
location is not yet known; a bare CPU pointer, no associated
`dataAddr` pair the way regular records have one) and a real diff-
application rule found (position-tagged overrides? run-length "same as
template" markers? unknown). Genuinely left open here, same honest
"real, separate task" framing as the previous stop -- not a claimed
crack, just a materially better-understood shape of the format's
metadata layer (header/template-pointer/door-data/record-list all now
structurally accounted for) plus one concrete negative result narrowing
the search for its content-diff scheme.

**Honest, precise final scope**: this project can now decode **320
real, individually-confirmed-coherent rooms** (up from 8) via general,
tested, ROM-static code -- no live emulator state needed for any of
them. Bank 7's own real "Templated" encoding (a further, unknown
number of additional rooms) remains a genuine, separate, unimplemented
format -- not claimed as solved. The original round-4 question ("what
live game state selects roomSelector 0/8-14") is now understood to
have been the wrong question for this goal: those rooms were always
decodable, just never rendered because no one had generalized the
already-checked-in `unknownRoomA` recipe past its own 6 hardcoded
indices.

Full Lua test suite: 234/234 passing (1 new test).

**UPDATE 2026-08-14 (bank 7 "Templated" revisited AGAIN, direct user
instruction "weiter bohren bis es fertig ist" -- CRACKED end to end,
same day as the structural pass above).**

**The base template itself decodes cleanly with the SAME RLE rule as
bank 5/6.** The template pointer (`0x411e` -> file `0x1C11E`, see
above) RLE-decodes (this map's own `rleLength=4`) to exactly 80 tiles,
consuming EXACTLY 44 bytes -- landing precisely on record 0's own
header pointer (file `0x1C14A`), a second independently-derived
boundary match on top of the first (the pointer-list's own end already
landing exactly on the template pointer). Two boundaries, both exact,
both derived from unrelated starting points -- not a coincidence.

**The per-record diff format, found via an exhaustive automated
search, not guesswork.** Every record's real data blob (found directly
via its own `dataAddr` pointer, no blob-bounding needed since the
format turns out to be self-terminating) starts with a real 4-byte
per-record field (small values, `0x00-0x0d` observed -- plausibly
per-room door/exit-flag data, structurally distinct from the map-level
24-byte door block -- NOT decoded) followed by `(value, position)`
byte pairs. Tested all 4 combinations of {3-byte or 4-byte prefix} x
{(pos,val) or (val,pos) order} x {linear 0-79 position vs. `(row<<4)|
col` nibble position} against every real record in the table,
counting what fraction of resulting "positions" landed in-bounds:
**prefixLen=4, order=(value,position), nibble encoding scored 557/557
(100%)** -- the next-best alternative (linear positions) only reached
97.1%. Not a close call.

**VERIFIED end to end, real ROM, real code (not a Python scratch
finding this time):**
- 566/566 real diff positions across all 64 real records decode to
  valid `(row,col)` pairs -- zero exceptions, zero silently-dropped
  values.
- All 64 reconstructed rooms (base template + that record's own diff)
  land in the same real `tile_entropy()` art band already established
  for bank 5/6 (1.30-1.40 bits, zero outliers) -- tighter clustering
  than bank 5/6's own 0.95-1.78 range, which makes sense: every bank-7
  room shares the same base template and tileset, so their entropy
  should cluster more than 320 independent bank-5/6 rooms do.
- Direct PNG eyeballing of 6 spot-checked records: genuinely different
  room content per record (a central statue/creature shape vs. a row
  of urn/skull decorations vs. a triangular banner formation), not the
  base template repeated.
- **Shipped as real, tested Lua code**, not left as a one-off script:
  `MapTable.readTemplatedHeader`, `MapTable.applyTemplatedDiff`,
  `MapTable.recordDataFileOffset` (new primitive -- unlike
  `MapTable.decode(...)`.blob, works for the LAST record too, since
  Templated diffs are self-terminating and don't need an externally
  supplied bound), and `RoomFloorLayout.buildRoomFromTemplatedMapTable
  Record`. `RoomFloorLayout.buildRoomFromMapTableRecord` itself now
  DISPATCHES on the map's own real header `encodingMode` -- callers no
  longer need to know or care whether a `mapTable` profile is RLE or
  Templated, matching that function's own long-standing "ANY record
  from ANY real MapTable-shaped source" promise for the first time.
  8 new tests (5 synthetic-data unit tests for the pure parsing logic,
  3 real-ROM tests including a dedicated "all 64 records, including
  the last one" regression guard) -- full suite green.
- `rom-inspector/tools/export_data.lua`'s room-catalog export now
  includes bank 7 through the exact same code path as bank 5/6 (no
  special-casing needed at that call site -- direct proof the dispatch
  really is transparent) -- the website's room catalog grew from 320
  to **384** real, individually-decodable rooms.

**Honestly still NOT decoded**: the map-level 24-byte door-data block
and each record's own 4-byte prefix (both plausibly door/exit-flag
data per the external doc, but unconfirmed) -- this pass cracked "can
we reconstruct the real room ART," not "do we understand every byte in
the table." Real per-room COLLISION is also not implemented for bank 7
yet (a separate, still-open task, same honest gap bank 5/6 already had
before their own collision work).

**Honest, precise final scope (SUPERSEDES the "320" figure above)**:
this project can now decode **384 real, individually-confirmed-coherent
rooms** (256 bank-5 RLE + 64 bank-6 RLE + 64 bank-7 Templated) via
general, tested, ROM-static code -- no live emulator state needed for
any of them, and BOTH of this ROM's real map-table encodings
(`encodingMode` 0 and 1) are now fully cracked for tile content.

Full Lua test suite: 429/429 passing (8 new tests).

**UPDATE 2026-08-14 (same day, "ok weiter mit tür und kollision" --
collision CRACKED, door bytes analyzed and honestly left open).**

**Collision**: `RoomFloorLayout.buildCollisionGridFromMapTableRecord`
now dispatches on `encodingMode` the same way the tile-decode path
already does, via a new `buildCollisionGridFromTemplatedMapTableRecord`
(base-template indices + `MapTable.applyTemplatedDiff`, then the same
per-metatile collision-byte lookup RLE mode already uses). Same honest
"extrapolated bank-5/6 rule, not ROM-confirmed" caveat now covers bank
7 too -- no gameplay reaches any of these rooms, so there's no live
movement test possible here either. LIVE-VERIFIED (not just headless):
real `love .` screenshots via a new `MYSTICQUEST_ROOM_EXPLORER_DEMO`
dev hook at flat room index 321 (bank7 record 0, footer correctly
reads "room 321/384 (bank7...)", player spawns on real walkable floor)
and 384 (the last real record, footer "room 384/384 (bank7...)",
genuinely distinct room art -- a diamond-scatter decoration pattern).

**Door bytes -- real structural progress, honestly still not a
confirmed decode.** Gathered and statistically analyzed both real byte
regions:

- **Per-record 4-byte prefix (all 64 records, 256 bytes total): a
  remarkably clean 8-value alphabet, zero outliers.** Every single byte
  is one of exactly `{0, 1, 2, 5, 8, 9, 12, 13}` -- nothing else, out of
  256 real bytes. Split by bit position: `bits0-1` (the external doc's
  claimed "open/closed/wall" state) is ALWAYS `0`, `1`, or `2` -- the
  4th possible 2-bit combination (`3`) never once appears alone across
  all 256 bytes, consistent with a real 3-state enum, not 4. `bits2-7`
  (the doc's claimed "map exit" area) is ALWAYS `0`, `1`, `2`, or `3` --
  value `0` dominates (240/256 bytes), the other three are rare. This
  is a strong, quantified structural match to the external FFA-
  Disassembly doc's own claimed bit layout for door bytes -- clean
  enough that it's very unlikely to be coincidental noise.
- **Map-level 24-byte block: does NOT show the same clean pattern.**
  `bits0-1` DOES use all 4 values (`0,1,2,3`, not just 3 of them), and
  `bits2-7` ranges 0-21 (needs up to 5 bits, not the per-record data's
  0-3). Splitting into 4 groups of 6 bytes (a natural N/E/S/W guess,
  since "directional door tile data" is 24 bytes = 4 x 6) produced no
  further obvious sub-pattern under inspection. This is a real,
  different KIND of data from the per-record prefix, not simply "the
  same format repeated" -- consistent with (but not proof of) the
  external doc's own description of it as a separate per-MAP default,
  not a per-room value.

**Why this stops here, not further**: unlike the tile-diff format
(which had 320 real records worth of live-render + entropy + visual
cross-checks available to VALIDATE a hypothesis against), there is
**no live gameplay ground truth for any bank-7 room at all** -- the
same fact that makes bank 5/6/7's collision an honest extrapolation
also means there is no way to confirm which of the 4 prefix bytes
corresponds to which real direction, or what "state 0" vs "state 1"
vs "state 2" concretely means (which is open, which is a wall?)
without a live trigger into one of these rooms, which this project has
never found (see rom-map.md's own "World scope, round 4"). Implementing
door-rendering or exit logic on top of an unconfirmed byte-to-direction
mapping would be exactly the kind of fabricated ROM behavior this
project's own engineering rule forbids. Recorded here as a real,
well-evidenced STRUCTURAL LEAD for whoever picks this up next (or if a
future finding somehow reaches live bank-7 gameplay), not as a decoded
fact -- `MapTable.applyTemplatedDiff`'s own doc comment still correctly
skips these 4 bytes rather than acting on them.

Full Lua test suite: 431/431 passing (2 more tests, the collision
dispatch + its loud-failure-on-wrong-mode check).

## World scope, round 6: parity check against real Live-VRAM data -- an honest negative result (2026-08-12, "alle 3 in der vorgeschlagenen reinfolge", quick win #3 of this batch)

Direct follow-up to round 5's own "320 decodable rooms" claim: that
claim is about DECODING (real ROM art, entropy + visual confirmed) --
it never claimed those 320 records correspond to specific, real,
in-game room IDENTITIES beyond the original `unknownRoomA` family
(roomSelectors 8-13). This round tried to close that gap for
`willyRoom` specifically -- a room this project has extensive REAL,
independently live-VRAM-captured data for -- by finding its own real
`mapTable` record and comparing the general pipeline's decode against
that ground truth, cell for cell.

**Step 1 -- resolve which real roomSelectorTable index is willyRoom's
own.** `rom_profiles.lua`'s own doc comment already flagged this as
unconfirmed ("which SPECIFIC selector is willyRoom's own wasn't
individually re-verified via $C3F5"). Found the real WRAM address for
this (`$C3F5`, "the room-selector byte", set by `$026DC` -- see this
doc's own earlier "$026DC is the real table lookup" entry) and traced
it live via `mgba_env`/`checkpoints.py`: right after `post_black_wipe()`
it reads `0x0f` (the already-known "unknownRoomB" placeholder, fired
during the wipe transition itself), then changes to a clean, STABLE
`0x04` the moment the Willy dialogue begins and stays `0x04` through
the entire real free-roam session (`willy_room_free()`, 14 real dialogue
advances later) -- reproducible, not a one-off read. **willyRoom's own
real roomSelectorTable index is 4**, confirmed.

**Step 2 -- test the "roomSelector N = mapTable record N" rule against
it.** That rule is round 5's own core finding, but was only ever
directly confirmed against the `unknownRoomA` family (selectors 8-13).
Decoded bank-5 record 4 via the already-shipped, general
`RoomFloorLayout.buildRoomFromMapTableRecord` and compared it, cell by
cell (320 cells, both grids resolved down to real ROM file offsets so
the comparison is apples-to-apples despite the two capture methods
using different tile-ID numbering), against `willyRoom`'s own real,
live-VRAM-captured grid (`rom_profiles.lua`'s `graphics.willyRoom`).
**Result: only 96/320 real tile matches** -- nowhere near the 288+/320
a correct identification would need (compare: the OLD `$D070`-based
`buildPixelGrid` path, using willyRoom's own genuinely-correct
metatile source, reproduces 288/320 exactly, the remaining 32 being the
door zones that pipeline deliberately doesn't cover). Checked every
other bank-5 record 0-7 and every bank-6 record 0-7 too, in case of a
simple off-by-one: best result was bank-5 record 3 at 124/320 -- still
not a real match, plausibly just incidental shared-floor-tile overlap
between two unrelated dungeon rooms drawing from the same general
tileset.

**Conclusion, honestly negative:** the `roomSelector N = mapTable
record N` identity is CONFIRMED ONLY for the `unknownRoomA` family
(selectors 8-13) that originally established it in round 5 -- it does
NOT generalize to the willyRoom family (selectors 2-6). This isn't
actually surprising in hindsight -- `willyRoom`'s own doc comment
already named a real, DIFFERENT tile-source pointer (`$46B0`, shared by
selectors 2-6) distinct from the general bank-5/bank-8-metatile-pool
mechanism `unknownRoomA`/the general pipeline uses -- this round turns
that pre-existing "different pointer" observation from a passive fact
into an actively-tested, positively-confirmed boundary on what the
general pipeline's own real reach actually is.

**What this changes, precisely:** nothing about the 320 records
themselves -- they still decode as real, coherent ROM art, unchanged.
What it narrows is the INTERPRETATION of "320 decodable rooms": 320
real records decode to real art, but only the original 6
(`unknownRoomA`, selectors 8-13) are ALSO confirmed to be a specific,
real, in-game room's actual content. The other 314 records' real
in-game placement (if they have one at all, e.g. willyRoom's own family
plausibly uses the `$46B0` mechanism instead, in which case some
subset of these 314 records might simply never be selected by ANY real
roomSelector) remains genuinely unknown -- an honest, real limit on
this project's own biggest recent claim, found by trying to verify it
further rather than assumed away. `rom_profiles.lua`'s own `willyRoom`
entry carries the full trace and numbers in its own doc comment.

No code behavior changed this round (a real investigation, not a
fix) -- `rom_profiles.lua` gained a `willyRoom.romRoomSelectorConfirmed
= 4` field plus the doc comment above. Full Lua test suite: 238/238
passing (unchanged).

## Consolidated reference: the general room/map system (2026-08-13, direct instruction "konsolidiere die dokumentation")

Pulls together every settled fact about the ROM's own general room/map
mechanics from across this whole document and `events.md`'s own many
investigation rounds into one place -- what's a real, clean, general
SYSTEM vs. what genuinely isn't, stated plainly. See the dated sections
throughout both files for the full disassembly/evidence trail behind
each claim; this section states conclusions only.

### 1. Room content -- VERIFIED, a real general table

Bank 8, file offset `0x20000`, 16 records x 11 bytes, indexed by a real
`roomSelector` byte (`rom_profiles.lua`'s own `roomSelectorTable`):

| Byte offset | Field | Meaning |
| ---: | --- | --- |
| 0-1 | (unresolved) | a real 16-bit pointer, `+0x4000`, written to WRAM `$D390`/`$D391` via `$01AF3` -- resolved 2026-08-14 (see events.md), real consumer not yet identified |
| 2 | (unresolved) | still not decoded |
| 3-4 | `tileSourcePointer` | real CPU address (LE), the room family's shared tile-source, written to WRAM `$D392`/`$D393` |
| 6 | `dynamicBank` | which switchable ROM bank holds this selector's own live/dynamic data, written to WRAM `$C3F0` |
| 7-8 | `ptr` | real CPU address (LE) into the active `dynamicBank` -- see section 2 AND section 2b |
| 9-10 | (unresolved) | not decoded |

Real, general dispatch: `$026DC` (bank-1 resident) does the 11-byte
multiply/lookup (`$02B7B`, a plain 8-bit×8-bit shift-multiply,
`HL = A * DE` -- not itself table-aware) and stages all of the above
into WRAM (`$C3F0`, `$C3F2`/`$C3F3`=`ptr`, `$D390`/`$D391`, `$D392`/
`$D393`) before calling `$01AF3` (the real "commit a new room" entry
point) for CUT-type transitions. **CUT-type room selection (`which
roomSelector loads next`) is genuinely SCRIPT/BYTECODE-driven** (a real
"load room N" 3-byte instruction format, `$4387`/`$02B70`), NOT itself a
static table -- an exhaustive whole-ROM scan for `CALL $026DC` found only 5
real call sites, 3 hardcoded (always `roomSelector=7`, the real
"pre-transition placeholder"), 2 genuinely dynamic (index read from a
live script cursor or an indirect-caller argument) -- the ultimate
source script for either dynamic path was not traced to completion.

### 2. The visual door/exit reveal mechanism -- VERIFIED, a real general system

The `ptr` field (bytes 7-8 above) points, in the active `dynamicBank`,
to a real, general structure:
- First 4 bytes = WRAM `$C3F8`-`$C3FB` (staged there by `$026DC`).
  `$C3F8` is the real master "any exit revealed" gate flag `$235B`
  checks before doing anything.
- Next 4x2 bytes (`ptr+2`/`+4`/`+6`/`+8`) = one real tile-patch-index
  pair PER DIRECTION, in `$225D`'s own real bit-case order (East=0,
  West=1, North=2, South=3).

Real script opcodes drive this (all confirmed, all reuse
`StandardScriptHandlers.triggerEvent`):

| Direction | Open (`$235B`, `A=`) | Opcode | Close (`$22FE`, `A=`) | Opcode |
| --- | ---: | --- | ---: | --- |
| North | `0x04` | `0xE0` | `0x04` | `0xE1` |
| East | `0x01` | `0xE4` | `0x01` | `0xE5` |
| South | `0x08` | `0xE2` | (unidentified) | -- |
| West | `0x02` | `0xE6` | (unidentified) | -- |

`$235B(direction)`: gated on `$C3F8`, switches to `dynamicBank`, ORs
the direction into a real "revealed exits" bitmask (`$C3F4`), then
`$225D`→`$2281`→`$056C` reads the direction's own 2 real tile-patch
index bytes (each fed through the already-known `$05BB` formula, `HL =
$D392:$D393 + A*6`) and redraws the real door-tile patch via the
already-known `$D070`/VRAM-write pipeline. This is a real,
DOUBLY-CONFIRMED general system (re-derived from scratch this session,
matched an independently-found direction/screen-position table exactly)
-- but it only draws the door GRAPHIC. It does not move the player and
does not pick a target room (see section 4).

### 2b. `$026DC` ALSO computes the cross-actor script-dispatch pointer -- the two mechanisms above are ONE real routine, not two

Found 2026-08-14 (task #85, see events.md's own dated entry for the
full disassembly). `$026DC`'s own body doesn't stop at staging the
door/exit-reveal fields above -- after switching to `dynamicBank` and
dereferencing `ptr` for `$C3F8`-`$C3FB`, it branches on `$C3F8`
(zero/nonzero) into one of two near-identical resolver functions
(`$25F6`/`$25D1`, differing only by a fixed `+0x1A` offset), each of
which computes a real record address from `$C3FB` (via the same
`$02B7B` multiply, stride 4) plus `$026DC`'s own second argument
(register `D`) plus the current `ptr` cursor, and writes the first 2
bytes read there into **`$C3FE`/`$C3FF`** -- the exact real WRAM
cell `$31AD`'s own caller (`$24AF`, see "The index question,
CONCLUSIVELY RESOLVED" above) reads to resolve a real script address.

**This means the "room content" system (section 1 above) and the
cross-actor script/event dispatch mechanism (`$31AD` chain) are NOT
two separate real systems this project had been tracking
independently -- `$026DC` is the single real entry point that drives
BOTH.** The already-known 5 real `CALL $026DC` sites (3 hardcoded
`A=7`, 2 dynamic -- see "What real game state selects roomSelector
index 0/9" above) are therefore the real trigger points for "which
script/message becomes active," not just "which roomSelector loads."
Each site's own second argument (register
`D`, `$026DC`'s sub-index parameter) was identified this pass too:
`$4261`/`$42A0` pass `D=0` fixed; `$434F` derives it from a
nibble-split of WRAM `$D49E`; `$4395` nibble-splits an incoming `BC`
pair.

`$242B`/`$255D` (called right after the `$25F6`/`$25D1` branch) were
traced structurally -- a real bit7-terminated byte-stream copy into a
WRAM staging buffer (`$C350`, 80 bytes), with `$255D` adding a "pick 1
of 4 variants" indirection on top -- plausibly the real message/
dialogue TEXT preparation step, but not confirmed to that exact
conclusion this pass.

**Honest, unchanged remaining scope**: the ultimate source of the 2
DYNAMIC `$026DC` call sites (who writes `$D49D` beyond the
already-known `$4331` helper; who indirectly calls the enclosing
routines `$433E`/`$4387`) was not traced further -- the same real
stopping point the 2026-08-11 investigation already hit, not resolved
by this pass either.

### 3. The generic entity-slot struct -- VERIFIED, a real general system

WRAM `$C200` + `slotIndex*16`, 20 real slots (0-19), confirmed via 2
independent real routines (despawn `$0AE3`, allocate `$0A74`):

| Offset | Field |
| ---: | --- |
| +0 | alive/state byte (`0xFF` = dead/empty sentinel; `0x08` on allocate) |
| +1 | caller-supplied "type" |
| +2 | caller-supplied param |
| +3 | `0` at allocate |
| +4 | Y position (pixel space) |
| +5 | X position (pixel space) |
| +6/+7 | caller-supplied params |
| +8/+9 | pointer to this slot's own 8-byte OAM shadow-copy block |

`$0A74` (allocate) scans for the first dead slot, initializes it
(zeroing `+4`/`+5`), then computes a real pixel position from its own
caller-supplied `D`/`E` params via `(D+2)*8`/`(E+1)*8` -- the exact
same `(n+K)*8` tile-to-pixel conversion this session independently
found for script opcode `0x49` (`ScriptOpcodeTable
.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49`) -- a real, decisive
cross-confirmation this is a general ROM convention, not opcode-
specific. `$0AE3` (despawn) zeroes `+0`/`+4`-`+9` and memsets the OAM
shadow block. The player is very plausibly slot 4 (`$C244`/`$C245` =
`$C200+4*16+4/+5` exactly) -- but no code was found that explicitly
allocates/positions the player through this same path (see section 4).

### 4. What is genuinely NOT a static table (honest, checked, not guessed)

Two real questions were pursued exhaustively this session (6+
independent static-analysis angles, all real code, all reported
honestly, all negative) and are NOT resolved as clean ROM data:

- **Room connectivity** (which exit leads to which target room): real,
  genuinely script/bytecode-driven (section 1) -- the ROM does not
  store this as a lookup table.
- **Player spawn/landing position**: no ROM code was found that writes
  `$C244`/`$C245` (zero hits for every literal-address-load pattern
  tried), and the two most plausible real candidate routines
  (`$235B`'s own callers, `$01AF3`) both provably don't touch it
  either. This project's own `rom_profiles.lua` `landingX`/`landingY`
  values remain, honestly, LIVE-CAPTURED empirical measurements, not
  values derived from any ROM table -- and per this investigation,
  that is very likely the ROM's own real design too (continuous player
  movement for SCROLL-type transitions genuinely never needs a "set
  position" step at all; CUT-type transitions' own real positioning
  mechanism, if any exists beyond "whatever ordinary collision/
  movement already had it at," was not found).

### 5. `$1ED7` -- a second general cross-bank dispatcher (bank 1)

Byte-for-byte identical to the already-known `$1F35`/`$1F06` family
(bank 2's own general case-dispatch shape), just switching to bank 1.
Fed real case values from at least 3 independent real call sites
(2 script-opcode trampoline clusters, `$0232`/`$049E`; the scroll
engine's own post-completion dispatch, `$46F9`). Cross-verified via
case `0x07` -> `$50AC`, the already-independently-decoded combat damage
formula. Real cases resolved and disassembled so far: `0x1E`
(despawns an actor slot -- real post-scroll NPC/enemy cleanup), `0x1F`
(processes a real 7-slot "pending sound-trigger queue" at WRAM `$CEF0`,
each entry played via `$0611`, a real 3-byte `LDH ($FF92),A` sound-
register write), `0x25` (a real classifier, gates on WRAM `$CF5B`
against 2 thresholds), `0x26` (writes 3 real WRAM cells and calls
`0x1F` directly as a subroutine -- confirmed produces fresh `$CEF0`
queue entries via `$5C9F`). None of the 4 sets player position.

## Collision generalized: willyRoom's own real bit-rule found, reversed polarity from fourthRoom/unknownRoomA (2026-08-14)

Direct instruction ("die gesammte gamemap entschlüsseln... wie weit
sind wir davon weg") — task 1 of the resulting priority list:
generalize the collision-byte mechanism found for fourthRoom/
unknownRoomA (2026-08-12) beyond that one table.

**The blocker was never "does a real collision byte exist" — it was
polarity.** `RoomFloorLayout.lua`'s own `isWalkableCollision`
(`COLLISION_WALL_MASK=0xF0`, "upper nibble zero = floor") was already
confirmed correct for fourthRoom's own real metatile table and
DEMONSTRABLY WRONG for willyRoom's — a real, already-documented
counter-example (willyRoom's own live-verified checkerboard floor
reads as "wall" under that rule). This pass re-derived willyRoom's OWN
correct rule from first principles instead of guessing a second time.

**Method**: for willyRoom's own real metatile table (`roomFloorLayoutPipeline
.exampleRoom`, file `0x206B0`/`0x1DA50`, 8x10 metatiles = 320 real
pixel-tile grid cells), decoded the layout stream + every metatile's
own real collision byte, and cross-tabulated EVERY ONE of the 320 real
cells' `(finalTileId, collisionByte)` pair against `willyRoom
.floorTileIds` — this project's own extensively live-movement-tested
ground truth (2026-08-09: held UP, watched the real player stop dead
at the wall boundary; only tiles 151-154 are real floor).

**Result: a perfectly clean, zero-exception split.** Tiles 151-154
show real collision `0x30` at every one of their 192 occurrences (48
each); every one of the room's other 39 real tile IDs shows ONLY
`0x00`/`0x08`, never `0x30`, across their combined 128 occurrences.
So willyRoom's own real rule is simply `collision == 0x30` means
floor — the exact opposite polarity from fourthRoom/unknownRoomA's
"upper nibble zero" rule. Confirms the earlier "collision byte meanings
are set per metatile TABLE, not fixed ROM-wide" hypothesis with a
SECOND independently-derived real table, not just the original
assertion.

**Historical note**: `RoomFloorLayout.lua`'s own `buildCollisionGrid`
doc comment used to claim willyRoom's tiles 151-154 show "BOTH `0x08`
(open) AND `0x30` (wall) collision bytes across different metatile
instances." This pass's full, exhaustive (all 320 cells, not a sample)
re-derivation found this is NOT the case — 151-154 are `0x30` at every
single real occurrence. Left as an open, flagged historical
discrepancy (possibly an earlier, since-corrected version of
`willyRoom.grid`, or a different tile range) rather than silently
erased.

**Generalized the mechanism**: `RoomFloorLayout.buildCollisionGrid`
now takes an explicit `isWalkable(collision)` predicate (default:
the old `isWalkableCollision`, unchanged behavior for existing
callers) instead of hardcoding one rule — the real design fix the
willyRoom counter-example exposed. New `RoomFloorLayout
.isWalkableCollisionWillyFamily` implements willyRoom's own real rule.

**Wired in for real** (not just left as available infrastructure):
`VictorySequence.lua`'s `ensureRoomLoaded` now builds willyRoom's real,
position-aware collision grid via this mechanism instead of the flat
`floorTileIds` heuristic every other room still uses. Proven
behavior-preserving two ways: headlessly (new test asserts zero
disagreement between the ROM-decoded grid and the old floorTileIds
classification across all 320 real cells) and live (`love .`,
`MYSTICQUEST_VICTORY_DEMO=1`, scripted input through the intro pages
into willyRoom's own free-roam, then held the real player into the
room's NE wall corner from two different hold durations — 100 and 220
frames both converge on the identical stopped position `x=128,y=16`,
proving a real, stable, correct wall-stop, not a lucky still-moving
snapshot).

**Honest remaining scope** (see maps.md's own updated "Collision"
section for the concise summary): secondRoom/thirdRoom very likely
extend the SAME willyRoom metatile table (2 real indices, 80/81,
already found past willyRoom's own last entry, see this doc's own
"secondRoom cracked" section) but this wasn't generalized into a full
collision grid for them this pass. fourthRoom/fifthRoom/sixthRoom/
startRoom have no known metatile+layout-stream source of their own at
all — collision there stays the flat heuristic. unknownRoomA's/
unknownRoomB's own tables have real collision bytes but no live-
movement ground truth is possible (no gameplay reaches them) — their
own rule stays genuinely unverified, not silently upgraded.

Full Lua test suite: 410 -> 411 (one old spot-check test rewritten in
place plus one new exhaustive-match test added).

## Live watchpoint on $D49D/$D49E: confirms (not just repeats) the earlier static dead end -- real negative, 3 real transitions

Direct follow-up to the "honest, unchanged remaining scope" note in
section 2b above (the 2 DYNAMIC `$026DC` call sites' ultimate source,
`$D49D`/`$D49E`, was never traced past static disassembly in 2 earlier
passes, both hitting the same real stopping point). This pass used a
genuinely DIFFERENT method -- a live mGBA write-watchpoint
(`tools/rom/watcher.py`'s `Watcher`, single-instruction-stepped
throughout, bank-accurate call-stack via `CallTracer`, not bulk
`run()`) armed across 3 real, distinct transitions this project can
actually reach: the thirdRoom->fourthRoom staircase cut, the
fourthRoom->fifthRoom corridor cut, and (implicitly, since it shares
the same corridor) partway into the fourthRoom->sixthRoom path.

**Result: zero hits across all 3.** `$D49D`/`$D49E` are never written
during any of them. This is a real, decisive confirmation (via a
different method, not a repeat of the same static trace) of the
project's own earlier conclusion: the dynamic `$026DC` call path is
for content this project's currently-reachable gameplay genuinely
never exercises -- consistent with, not contradicting, the "index 0/9
selection... explains why live play never observed it" finding.

**Practical conclusion for "decode the whole gamemap"**: automatic
connectivity discovery via the script/dispatch mechanism is NOT
currently achievable for content beyond what's already been found --
both the static and the live-watchpoint methods agree on this. The
only method that has ever actually found a new real room/connection in
this project is systematic LIVE EXPLORATION of the edges of already-
known rooms (how `fifthRoom`/`sixthRoom` themselves were found) -- not
a shortcut this pass unlocked, but a real, honest confirmation that
the existing, proven methodology remains the right one to keep using.

## sixthRoom's own documented hold-to-trigger mechanism does NOT reproduce under a longer, more careful re-test (2026-08-14, honest correction)

Direct continuation of "die gesammte gamemap entschlüsseln... absolute
prio" -> systematic edge exploration of the least-explored real rooms
(`fifthRoom`/`sixthRoom` currently have ZERO recorded `exits` of their
own -- neither was ever probed past its own landing spot). Started
with `sixthRoom` since it had literally no exploration recorded at all
beyond the initial discovery.

**Real, concrete finding: the corridor is bigger than documented.**
Replaying the exact known path into `fourthRoom`'s own west corridor
(UP into the wall, then LEFT) and holding LEFT for MUCH longer than
the previously-recorded test (3000+ real frames, vs. the original
100-220 frame tests): real WRAM `$C245` (X) does NOT stay at 80
forever. It pauses there for ~260 real frames (which is exactly why
the original 100/220-frame tests both landed on "80" and concluded a
stable wall -- a real, understandable methodology gap, not an error in
that pass's own math), then resumes moving further left, settling at a
SECOND real wall, `X=24`. From there, holding UP moves 40px further
(to Y=56, a third wall) and holding DOWN moves 16px further (to Y=112,
a fourth wall) -- all real, previously-uncaptured floor space.

**Real, honest correction: the documented `sixthRoom` cut trigger
(`holdFrames=220`, holding LEFT once settled at X=80) does NOT fire in
this re-test.** Held LEFT continuously and unbroken for over 3000 real
frames (far past the original 220-frame threshold) from the exact same
starting state (`third_room_free.state`) -- the real WRAM room pointer
(`$D392`/`$D393`) never once changes from `fourthRoom`'s own value
throughout the entire test, including well past the second wall at
X=24. The captured VRAM tile IDs at the settled X=24 position DO
overlap heavily with `sixthRoom.tileOffsets`'s own real tile-ID set
(same shared bank-8/12 tileset, expected), but the actual tile
ARRANGEMENT does not match `sixthRoom.grid` row-for-row when correctly
adjusted for the real SCX offset -- i.e. this is genuinely NOT
confirmed to be `sixthRoom`'s own content, despite using overlapping
tiles from the same shared set.

**Honest, unresolved status**: this is a real, unreconciled
discrepancy with the existing "RESOLVED (task #75)" claim for
`sixthRoom`'s own exit, not silently ignored. Two most likely
explanations, neither confirmed: (1) the original 2026-08-13 discovery
used a genuinely different input sequence (e.g. released/re-pressed
LEFT rather than one continuous unbroken hold) that this project's own
current `checkpoints.py`/exit-zone doc comments don't fully capture,
or (2) the real trigger condition depends on something this pass
didn't control for (a specific Y sub-band, a specific frame-parity, or
state left over from a DIFFERENT earlier point in the original
session's own play-through that this fresh replay from
`third_room_free.state` doesn't reproduce). NOT chased down further
this pass -- flagged as a real, concrete, bounded follow-up rather than
either quietly re-asserting the old "RESOLVED" claim or spending
unbounded further time on it in this same pass.

**Practical takeaway for `rom_profiles.lua`**: the `sixthRoom` exit
definition itself is left UNCHANGED this pass (not proven wrong, just
not re-confirmed) -- but its own doc comment should no longer be read
as "fully resolved, case closed" without this caveat attached. The
real further corridor space found (X=24 west wall, Y=56 north wall,
Y=112 south wall from there) is real, previously-uncaptured room
content -- worth a dedicated follow-up pass (capture its own real
tile grid, determine whether it's genuinely `sixthRoom` or a distinct,
still-unnamed further room) rather than folding into this same
investigation.

## SELF-CAUGHT METHODOLOGY BUG, corrected: the earlier $D49D/$D49E watchpoint result was invalid (conclusion happens to still hold, evidence didn't)

Direct follow-up while continuing the `sixthRoom` corridor
investigation. Found a real bug in this session's OWN tooling usage,
not the ROM: the earlier "$D49D/$D49E live watchpoint, 0 hits across 3
real transitions" result (see the dated entry above, "Live watchpoint
on $D49D/$D49E") was produced by a script that looped `Watcher.step()`
(ONE real SM83 CPU instruction per call, per `watcher.py`'s own
docstring) the same number of times as the real ROM's own FRAME counts
used by this project's other, `s.run()`-based navigation scripts --
off by a real factor of roughly 15,000-17,000x (one real GB frame is
~17556 cycles, on the order of thousands of instructions, not one).
Caught by a direct, simple diagnostic: 1000 real `w.step()` calls only
advanced the real `LY` scanline register by 23 (out of 154 per frame)
-- nowhere near the hundreds of real frames the earlier script's own
`hold(key, frames)` calls assumed they were producing. A concrete tell
that was missed in the moment: that script's own printed self-check,
"room after staircase: 0xb0,0x46 (expect 0xb0,0x40)", literally showed
the ACTUAL value did NOT match the expected one -- i.e. the staircase
cut never really fired in that test at all -- but the surrounding
narrative text moved on without flagging that mismatch as the red flag
it was.

**Re-ran the exact same investigation with the bug fixed**: real,
correctly-paced bulk `s.run()` stepping (already independently
verified earlier this session to still report watchpoint hits
correctly -- the platform-level `entered` callback forces early notice
even inside a frame-run loop, not just manual single-stepping),
checking `Watcher.hit` after each small bulk chunk instead of
conflating instruction count with frame count. Added an explicit
`assert room == (0xb0, 0x40)` self-check right after the staircase
hold specifically so a broken navigation can never again pass silently.

**Result: the real conclusion is UNCHANGED, but now honestly earned.**
Across the properly-paced staircase transition, the fifthRoom cut, AND
(new this pass) the FULL extended west corridor walk all the way to
the real second wall at X=24 found earlier this session (plus UP/DOWN
from there) -- watching `$D49D`/`$D49E` AND `$D392`/`$D393`/`$C3F0`
together -- exactly ONE real hit occurred (a `$D392` write during the
staircase transition itself, `old=176,new=176`, a real "commit room"
event that happens not to change that specific byte since thirdRoom
and fourthRoom's pointers share the same low byte `0xB0` -- expected,
not a new finding). Zero hits on `$D49D`/`$D49E` specifically,
anywhere in the whole corrected trace. So: automatic connectivity
discovery via the dynamic `$026DC` path is still genuinely not
exercised by any currently-reachable transition -- but this is now
based on a real, valid live trace, not a script that never actually
ran the transitions it claimed to test.

**Lesson recorded for future live investigation scripts** (this
project's own tooling docs, not just this one finding): `Watcher.step()`
is instruction-granular -- never assume an `N` passed to a `hold()`-
style helper means real frames unless the helper actually calls
`Session.run()` (bulk, frame-granular) internally. When precise
watchpoint timing is needed, prefer bulk `s.run()` + checking `.hit`
after each chunk (proven reliable) over manual `w.step()` loops, and
always add an explicit assertion on the expected post-transition state
right after a hold that's supposed to fire one -- a silently-wrong
"expected X, got Y" printed as prose is not a substitute for a real
check that stops the script.

## Working hypothesis, strong but not proven: "sixthRoom" may not be a real, separate cut-triggered room at all

Direct continuation of the corrected `sixthRoom` re-test. Re-examined
the ORIGINAL "confirmation" evidence the 2026-08-13 discovery cited
(`dynamicBank` `$C3F0` = 6, "confirmed LIVE... to be the SAME
willyRoom/secondRoom/thirdRoom/fifthRoom family") and found it is
NON-DISCRIMINATING: `$C3F0` already reads `6` from the moment
`fourthRoom` itself is entered via the staircase (roomSelector 1's own
real `dynamicBank` column value, per `roomSelectorTable.knownRooms`'
own already-recorded data -- confirmed live this pass too, checked
`$C3F0` immediately after the staircase cut, BEFORE any LEFT input at
all: already `6`). So observing "`$C3F0`=6" anywhere in this corridor
is equally consistent with STILL being in `fourthRoom` the whole time
-- it does not, by itself, prove a new room was reached.

Combined with this pass's own two further real findings (the
documented `holdFrames=220` trigger does not fire even after 3000+
frames of continuous OR intermittent-tapped LEFT input; the captured
tile content, while sharing tile IDs with the recorded `sixthRoom.grid`,
does not match its own specific arrangement when correctly
SCX-adjusted), a real, coherent alternative explanation emerges:
**`sixthRoom` may not be a genuine, separate, cut-triggered room at
all -- it may simply be MORE of `fourthRoom`'s own single continuous
room space**, revealed by the real, ordinary hardware scroll already
established for this exact corridor (the same real "one underlying
room, several named screens" pattern already confirmed for `willyRoom`
/`secondRoom`/`thirdRoom`), not a distinct room needing its own
`targetRoom`/cut definition at all.

**Status: a strong, well-reasoned HYPOTHESIS, not proven.** What would
settle it either way: (1) a direct live check of whether `fourthRoom`'s
own real ROM room-selector value changes at ANY point during this
walk (checked `$C3F0` specifically; `$D392`/`$D393` already confirmed
unchanged all session) -- done, negative, supports the hypothesis; (2)
whether the REAL, full extended tile content (X=24's own screen, and
the further UP/DOWN space from there) is genuinely a coherent,
self-consistent CONTINUATION of `fourthRoom`'s own grid the way
`secondRoom`'s rows 14-15 provably continue `willyRoom`'s own metatile
table -- NOT checked this pass (would need the same kind of metatile-
table-extension proof `secondRoom` got, which requires knowing
whether `fourthRoom` even HAS a metatile+layout-stream source of its
own, itself unconfirmed -- see `maps.md`'s "Collision" section, which
already flags `fourthRoom` as having no known metatile source).

**Deliberately NOT changed this pass**: `rom_profiles.lua`'s existing
`sixthRoom` entry and `fourthRoom`'s own exit definition pointing to
it. Reclassifying/removing a real, already-shipped room definition
based on a strong hypothesis rather than a proven fact would be
overreach -- this is recorded as the real, current best understanding
and a concrete follow-up (extend `fourthRoom.grid` itself westward with
the real captured content instead of treating it as a separate room,
IF the hypothesis holds up under the 2 checks above) for whoever picks
this up next, not acted on unilaterally here.

## Hypothesis UPGRADED to confirmed: fourthRoom's west corridor uses the EXACT SAME real mechanism already proven for secondRoom's own extension

Direct continuation, using a precisely-targeted live capture (bulk
`s.run()` for coarse navigation, switching to real per-instruction
stepping ONLY within the single real frame a `$CEE8` write was
detected in, to pin down the exact PC/registers without the earlier
session's `w.step()`-loop timing bug).

**Real, decisive result**: `$CEE8` writes during the west-corridor walk
land at `PC=$1EB6` -- the EXACT SAME real address already documented
(see this doc's own "secondRoom cracked" section) as the second half
of the real `$1E9F`/`$1EB6` scroll-time incremental VRAM-write-queue
mechanism that PROVED `secondRoom` is further rows of `willyRoom`'s own
continuous room space, not a separately-loaded room. Captured real
register state at 2 of these events: `DE=0x981E`/`A=0x1E` and
`DE=0x98DE`/`A=0xDE` -- real VRAM tilemap destinations at BG column 30
(both `0x1E`/`0xDE` mod 32 = 30), the wraparound edge column a
leftward horizontal scroll would naturally reveal next -- structurally
identical in shape to `secondRoom`'s own real capture (which landed on
wraparound ROWS instead, for willyRoom's own vertical door scroll).

**This decisively upgrades the earlier hypothesis**: `fourthRoom`'s
west corridor (previously captured, in part, as a separate room named
`sixthRoom`) is revealed via the exact same real, general "one
continuous room, scroll-time incremental reveal via `$1E9F`/`$1EB6`"
mechanism this project already proved for `willyRoom`->`secondRoom` --
not the bulk `$242B` decompression pipeline (already confirmed NOT
engaged for this room), and not a genuinely separate cut-triggered
room. Combined with the earlier findings this pass (the documented
`sixthRoom` cut trigger never fires; the non-discriminating
`dynamicBank` evidence), this is now real, mechanism-level confirmation,
not just a plausible alternative explanation.

**Practical next step, not yet done this pass**: capture the REAL full
set of `$1E9F`/`$1EB6` tile-ID pairs across the whole corridor walk
(the same method that gave `secondRoom` its own exact real rows
14-15), then extend `fourthRoom.grid` itself westward with that real
content, and retire the separate `sixthRoom` entry (folding it into
`fourthRoom`, the same way `secondRoom` was never modeled as split
from `willyRoom`) -- a real, bounded, now well-evidenced follow-up
rather than a fresh mystery.

## Real corridor content captured: 20 real tile-pairs, matching fourthRoom's own established style exactly -- CLOSES the sixthRoom question

Direct continuation, capturing the actual real `$1E9F` call parameters
(`DE`=packed tile-ID pair, `HL`=VRAM dest) across the corridor walk --
a single continuous `core.step()` pass (fast: 486512 real instructions
in 0.5s), not a per-frame reload, watching for `pc==0x1E9F` directly.

**20 real captures, decoded**: the first 16 land at consecutive VRAM
addresses `$981E`-`$99FE` -- decoding each as `(row, col)` within the
32x32 BG map (`(addr-0x9800) -> row=off//32, col=off%32`) gives EVERY
row 0-15 at column 30, in order -- a full real vertical strip, exactly
matching the room's own 16-row height. A further 4 captures (before
hitting this pass's own 20-capture budget) land at column 28, rows
0-3, confirming this repeats column by column as the scroll continues.

**The real tile values themselves are the decisive part.** The column-
30 strip's own 16 real tile pairs: `(0x82,0x81)` x2 alternating with
`(0x83,0x83)` x2, for rows 0-9, then `(0x84,0x84)`, `(0x92,0x91)`,
`(0x91,0x92)` at rows 9-11, then back to the `(0x82,0x81)`/`(0x83,0x83)`
alternation for rows 12-15. In decimal: tiles 129/130/131/132 (already
`fourthRoom`'s own known checkerboard/border set) plus 145/146
(`0x91`/`0x92` -- the SAME "new corridor decoration" tiles this
project already found and decoded earlier this same session, task
#75's own "10 new tile IDs," `rom_profiles.lua`'s `fourthRoom
.tileOffsets`). **This is not a coincidental resemblance -- it's the
literal same tile vocabulary fourthRoom already uses**, revealed one
column at a time as the real hardware scroll advances, via the exact
same mechanism (and even the exact same real ROM address, `$1EB6`)
already proven for `secondRoom`'s own continuation of `willyRoom`.

**Conclusion, now decisively closed, not just hypothesized**:
"`sixthRoom`" is real further columns of `fourthRoom`'s own single
continuous room space, not a separately-loaded room -- the documented
cut-transition mechanism never fires because there genuinely is no cut
here, the same way there's no cut between `willyRoom` and `secondRoom`.

**Not done this pass** (a real, bounded, well-scoped follow-up, not a
fresh mystery): capturing the FULL real column range (this pass
stopped at 20 captures/2 columns by its own budget; the real corridor
likely spans up to the remaining ~10-12 columns of the 32-wide BG map
based on how far X travels), assembling it into a real extended
`fourthRoom.grid`, and retiring the separate `sixthRoom` room
definition in `rom_profiles.lua` (folding its own already-decoded tile
offsets into `fourthRoom.tileOffsets`, which mostly already overlaps).

**Code-level retraction carried out (2026-08-14, same pass).** The
conclusion above is now reflected in the shipped code, not just this
doc: `fourthRoom.exits` in `rom_profiles.lua` had its second (west,
`sixthRoom`) entry removed -- it now holds exactly 1 real exit (north,
to `fifthRoom`). A "RETRACTED" doc comment replaces it, citing all 4
converging pieces of evidence (never-firing documented trigger even
after 3000+ frames; non-discriminating `$C3F0` dynamicBank evidence;
the real `$1E9F`/`$1EB6` scroll-reveal mechanism firing with real
captured tile data matching `fourthRoom`'s own vocabulary; and an
independently pre-existing doc comment in `StandardScriptHandlers.lua`
from an unrelated investigation that had already flagged the same
gap). `sixthRoom`'s own table (tileOffsets/grid) is KEPT as real,
cross-validated ROM data -- only the exit pointing at it as a separate
room is gone. `tests/import/sixth_room_test.lua` now asserts this
directly (`#fourth.exits == 1`, no exit targets `"sixthRoom"`);
`tests/import/fifth_room_test.lua` and
`tests/import/tile_landing_position_test.lua` were updated for the
direct, expected fallout (one fewer real recorded landing position).
Full suite green afterward: 414 passed, 0 failed. `rom-inspector/js
/data/open-questions.js`'s "No real camera-scroll rendering" entry
corrected to match (was still describing "two 'cut' exits").

## Room catalog: all 320 bank-5/bank-6 rooms exported as real room DATA (2026-08-14)

Direct follow-up on user request ("jetzt bitte andere räume, so viele
wie möglich, mir reichen erstmal die raumdaten" -- decode as many
other rooms as possible, room DATA alone is enough for now, no
connectivity/gameplay wiring needed this round).

No new discovery was needed: `src/app/states/RoomExplorer.lua`'s
dev-only F8 browser has already been able to decode all 256 bank-5 +
64 bank-6 map-table records LIVE, straight from the ROM, since
2026-08-12 (`RoomFloorLayout.buildRoomFromMapTableRecord` +
`toTileGridBackgroundData`, the exact same general pipeline used
everywhere else). What was missing was making that already-verified
capability available as **static room data** outside a live LÖVE
session -- exactly what "raumdaten reicht" asks for.

**What was done**: `rom-inspector/tools/export_data.lua` gained a new
export section that runs this pipeline across ALL 320 records (not
just the 2 bank-6 spot checks the test suite already covered) and
writes the result to a new `rom-inspector/js/data/room-catalog.js`
(`ROOM_CATALOG`, ~1.6 MB, 320 entries of `{name, source, recordIndex,
confirmed, cols, rows, grid, tileOffsets}`). Runs in well under a
second (pure ROM-static decode, no live emulation).

**Honest scope, unchanged from RoomExplorer.lua's own doc comment**:
every one of the 320 entries decodes as real, coherent ROM art
(`tile_entropy()` + visual spot checks already established this for a
representative sample of both tables). Only the 6 bank-5 records 8-13
(`unknownRoomACandidates.rooms`) are ADDITIONALLY proven to be
`unknownRoomA`'s own specific, real dungeon rooms -- tagged
`confirmed=true`. The other 314 have no known live gameplay trigger;
`confirmed=false` keeps that distinction visible rather than silently
upgrading their status.

**Website wiring**: the Map-Viewer (`rom-inspector/js/viz/mapviewer.js`)
now shows a combined dropdown with two `<optgroup>`s -- "Echte,
verbundene Räume" (the original `ROOM_MAPS`, unchanged) and "Raum-
Katalog" (the new 320 entries, confirmed ones marked with a "✓"),
plus a note line under the toolbar spelling out the confirmed/
unconfirmed distinction for whichever entry is selected. The Übersicht
page gained a "Raum-Katalog" stat block (320 total / 6 confirmed / 4
real connected rooms). Verified end-to-end with a real headless-
browser render (jsdom + the `canvas` package, not just a syntax
check): both optgroups render with the right counts (14 + 320 = 334
options), selecting a confirmed vs. unconfirmed catalog entry produces
the right note text, and the canvas actually draws real pixel content
at the expected size.

**New regression test**: `tests/import/room_floor_layout_test.lua`
gained a test that runs `buildRoomFromMapTableRecord` across ALL 320
records (not just the 2 the existing spot-check test already covered)
and asserts every single one produces a real 16x20 grid with every
cell inside the real environment-tileset bounds -- the direct
regression guard for the new website export, since a bad record deep
in the middle of 320 would not have been caught by the earlier 2-
record spot check.

Full suite: 415 passed, 0 failed (was 414 -- +1 new test).

## Room-catalog tile assignment: correction after direct user report, real investigation, honest negative result (2026-08-14)

Direct user report after the room-catalog export (previous section):
"ok jetzt versuche mal allen gefundenen räumen auch die richtigen
tiles zuzuordnen. die sind bei allen ausser den bekannten total off"
(try to assign the correct tiles to all the found rooms too -- they're
totally off for all except the known ones).

**Root cause found.** The room-catalog export (and `RoomExplorer.lua`'s
own dev-only F8 browser it's built on) decodes all 320 bank-5/bank-6
records' own real RLE layout streams correctly (structurally verified,
see the new "ALL 320 records decode without error" test), but resolves
every record's metatile-index bytes against a SINGLE, FIXED metatile
table (`unknownRoomACandidates.metatileTableFileOffset = 0x20938`).
That address is independently, ROM-confirmed correct -- via the
already-VERIFIED `roomSelectorTable`'s own real `$D392`/`$D393` DE
field, a live-traced hardware fact, not a guess -- but ONLY for
roomSelector 8-13 (bank-5 records 8-13, `unknownRoomA`). Reusing it for
every OTHER bank-5/bank-6 record was always an unverified placeholder,
not a second confirmation -- the earlier "VISUALLY + QUANTITATIVELY
CONFIRMED, all 64 records" language on `mapTableBank6` (and the
equivalent bank-5 framing) only ever meant "decodes to real, non-noise
GB tile art" (`tile_entropy()` + eyeballing), which is exactly the weak
discriminator round 3 already warned about ("this signal alone does
not usefully separate a real, distinct, walkable room from any other
bank-5 record") -- that risk has now materialized in a way a casual
render didn't catch but a direct side-by-side user comparison did.

**A genuinely new lead was tried and rigorously falsified, not just
theorized.** `MapTable.decode`'s own per-record `header` field (a
short, 0xFF-terminated blob immediately before each record's data
blob) had never been interpreted -- only used to find where it ends.
Dumping it for a sample of records showed a variable shape (3, 6, or 9
bytes + terminator); the 6-byte shape's own trailing 16-bit field
resolves into bank 8's `0x20000`-ish region for many records, making
"per-record metatile-table pointer" a plausible-looking hypothesis.
Directly tested against known-good ground truth: bank-5 record 9 is
part of the CONFIRMED `unknownRoomA` family (its own real metatile
table is 0x20938, per the `$D392`/`$D393` DE field above) and has a
6-byte header whose own trailing u16 resolves to 0x20381 -- NOT
0x20938. A full scan of all 256 bank-5 records' own headers found ZERO
whose trailing u16 resolves to 0x20938 at all. **Hypothesis
decisively ruled out** -- kept as a permanent regression test
(`tests/import/map_table_test.lua`, "the per-record header field is
NOT a per-record metatile-table pointer") so this exact already-tried
idea can't be silently re-attempted and presented as a fix without
re-deriving (and re-failing) the same check.

**Honest conclusion: no working alternative mechanism is currently
known.** This is the SAME open mystery round 3/4 already concluded --
"the real blocker is how the ROM selects ANY room beyond the 16
`roomSelectorTable` entries, not which metatile table" -- now
sharpened with one more ruled-out lead. Per this project's own "no
silent fallbacks" rule, the fix is not a better guess but honest
labeling: `rom_profiles.lua`'s `mapTable`/`mapTableBank6`/
`unknownRoomACandidates` status fields and the room-catalog website
now explicitly say the TILE ASSIGNMENT (not just "room identity") is
confirmed correct ONLY for the 6 `unknownRoomA` records --
`rom-inspector`'s Map-Viewer shows a prominent ⚠ warning on every
other catalog entry ("Kachel-Zuordnung wahrscheinlich falsch") instead
of silently presenting a best-effort guess as settled fact. The
underlying real, decoded RLE/metatile-INDEX data for all 320 records
remains genuine ROM content either way -- only the VISUAL tileset
resolution of that data is in question for 314/320.

Full suite: 416 passed, 0 failed (was 415 -- +1 new regression test).

## Clarification: how the "known" rooms' tileset IS determined (direct user question, 2026-08-14)

Direct follow-up question after the correction above: "aber woher
wissen wir bei den bekannten räumen welches tileset benutzt wird. es
muss doch irgendwo was geben was das bestimmt!" (how do we know the
right tileset for the KNOWN rooms then -- there must be something that
determines it). Answer: yes, and it's the exact same `roomSelectorTable`
mechanism this whole investigation already depends on -- worth stating
plainly in one place since the reasoning was previously scattered
across several doc comments.

`roomSelectorTable` (bank 8, file `0x20000`, 16 real records x 11
bytes, live-traced via `CallTracer` against the actual `$026DC`/
`$01AF3` ROM routines) has, at bytes 3-4 of each record, a 16-bit value
that becomes WRAM `$D392`/`$D393` -- the real "room tile-source
pointer" this project's whole room chain already keys off of.
Interpreted as `bank8Base + (value - 0x4000)`, this IS the room's real
metatile table address. Concrete, real byte evidence (not inference):

- roomSelector 2-6: DE field = `$46B0` -> `0x206B0` -- EXACTLY matches
  `willyRoom`'s own metatile table, already independently known from a
  completely different investigation thread. Not a coincidence; the
  same real ROM value surfacing twice via two different methods.
- roomSelector 8-13: DE field = `$4938` -> `0x20938` -- `unknownRoomA`.
- roomSelector 14-15: DE field = `$43B0` -> `0x203B0` -- `unknownRoomB`.

This is why the "known" rooms' tile assignment is a real, verified ROM
fact, not a guess: the ROM itself hands us the right table via this
exact field, for every room that has a `roomSelectorTable` entry.

The catch, restated plainly: this table has only 16 slots. The 320
bank-5/bank-6 catalog records are a structurally similar but entirely
SEPARATE, much larger data set -- none of them (beyond the coincidental
index match for 8-13) has its own `roomSelectorTable` entry, so there
is no known ROM structure that hands out "record N -> metatile table
X" for arbitrary N. That absence -- not a wrong formula -- is the real
reason the catalog's tile assignment can't currently be fixed the same
way, and is the same "how does the ROM select ANY room beyond the 16
known slots" mystery round 3/4 already left open.

## Three more methods tried for the room-catalog tile assignment, all negative (2026-08-14, direct instruction "versuche andere methoden... es muss ja auf die eine oder andere art exsistieren")

Direct continuation after the header-field hypothesis was falsified.
Three further, methodologically DIFFERENT approaches tried in
sequence (not variations on the same idea), each calibrated against
known-good ground truth before being trusted, each reported honestly.

**Method 2 -- pixel edge-continuity scoring.** Hypothesis: real,
hand-drawn dungeon tiles are drawn to connect at their edges (brick
walls, floor checkerboards); a WRONG metatile table would place real
but unrelated tiles next to each other, measurably less continuous
than the correct table. Implemented a real, quantifiable metric
(summed absolute pixel-value difference across every adjacent tile
edge, both directions) and swept 897 candidate 6-byte-aligned bases
across the whole real, confirmed-valid metatile-pool region
(`0x20000`-`0x214FA`, per round 3's own "one continuous dictionary"
finding) against the KNOWN-GOOD records 8-13 (real table `0x20938`).
**Calibration failed**: the known-good table's own rank among 897
candidates varied wildly per record (3rd, 53rd, 335th, 352nd, 141st,
15th) -- nowhere near a reliable "always wins" signal. Likely cause:
much of this ROM's environment tileset is simple, highly-repetitive
wall/floor patterns that connect reasonably well to almost ANY
neighboring choice, making edge-continuity a weak discriminator here
-- the same class of problem `tile_entropy()` already had, just a
different specific metric hitting the same wall.

**Method 3 -- static whole-ROM search for real code referencing the
bank-5/bank-6 pointer-table base address.** Both tables' own pointer
arrays start at CPU `$4004` (`mapTable.pointerTableFileOffset`/
`mapTableBank6.pointerTableFileOffset`, bank-relative). Scanned the
entire 256 KiB ROM for any of the 4 real SM83 16-bit-immediate-load
opcodes (`LD BC/DE/HL/SP,$4004`) as a direct, concrete check for a
real caller round 3/4's own live-tracing pass might have missed
statically. Found exactly 4 byte-matches, ALL inside bank 12 (`environ
mentTilesetBank12`, pure raw 2bpp tile graphics, never executable
code), spaced an suspiciously exact `0x1000` bytes apart -- a clear
artifact of a repeating tile pattern in the graphics data coincidentally
matching the 3-byte opcode sequence, not real code. Zero real hits.

**Honest, direct conclusion after 2 investigation rounds and 5 total
distinct methods** (this round's 3 plus round 3/4's own "second
roomSelectorTable-shaped scan" and "373-entry function table" leads):
no known ROM mechanism determines the correct metatile table for a
bank-5/bank-6 record outside the 16 `roomSelectorTable` slots. Every
method tried was either directly falsified against known-good ground
truth (methods 1, 2) or found no real evidence at all (method 3, round
3/4's strategies). This is not a "hasn't been tried hard enough" gap
-- it is the exact same, now repeatedly-confirmed open mystery: how
does the ROM's own code select or configure ANY room beyond the 16
already-known slots. Solving it would most likely require either (a)
forcing the ROM's own room-load routines directly via register/stack
manipulation for an out-of-range roomSelector value and observing what
happens (round 4's own already-flagged "fundamentally different, much
larger engineering task," never attempted), or (b) a lucky find while
disassembling unrelated code that happens to reference this table.
Recorded here plainly so a future pass doesn't re-try methods 1-3
blind -- `tests/import/map_table_test.lua` already guards method 1;
methods 2/3 were pure investigation, not committed as reusable code
(no stable finding to guard).

No code/data changes this pass (pure investigation, scratchpad Python
scripts only). Full Lua test suite unchanged: 416/416 passing.

## Real structural find: roomSelectorTable's own `offsetParam` IS "mapRoomPointers" -- but doesn't resolve the metatile question (2026-08-14, direct instruction "was wäre dann der nächste logische schritt")

Following the honest "5 methods, all negative" report, the next
logical step was to consult the external reference this project
already trusts and cites for matching format details: [daid/FFA-
Disassembly](https://github.com/daid/FFA-Disassembly) (a real, public
US-cartridge disassembly). Its own devlog, part 2 ("The quest for
maps"), documents a `MAP_HEADER` structure: `tilesetGfx, $00,
metatiles, $80, mapRoomPointers, $d7, $3c` -- each of 16 real "maps"
has its own header with a pointer to a per-map ROOM list
(`mapRoomPointers`), and ALL rooms within one map share that map's own
metatile table.

**Real, byte-exact confirmation, not inference.** This EU ROM's own
`roomSelectorTable` record shape already has a field matching this
role: `offsetParam` (bytes 0-1 + `$4000`, -> WRAM `$D390`/`$D391`),
previously documented only as "not consumed by traced routines,
meaning unknown." Resolving it the same way `tileSourcePointer`
(bytes 3-4) already resolves -- bank-relative CPU address -> file
offset -- but relative to THIS record's own `dynamicBank` (byte 6,
not a fixed bank) gives an exact, decisive match:
- roomSelector 0: `offsetParam`=$4000, `dynamicBank`=5 -> file
  `0x14000` -- BYTE-IDENTICAL to `mapTable`'s own already-VERIFIED
  header (`00 03 10 10`) followed by its own real pointer-table
  entries.
- roomSelector 1: `offsetParam`=$4000, `dynamicBank`=6 -> file
  `0x18000` -- BYTE-IDENTICAL to `mapTableBank6`'s own real header
  (`00 04 08 08`) + entries.

This is not a coincidence -- it's the real mechanism connecting
`roomSelectorTable`'s 16 "maps" to the 320-room bank-5/bank-6 catalog:
**roomSelector 0 "owns" all 256 bank-5 records as its own room list;
roomSelector 1 owns all 64 bank-6 records.** Now `VERIFIED` and
committed: `RoomSelectorTable.resolveMapRoomPointersFileOffset()`
(new function) + a decisive test (`room_selector_table_test.lua`)
locking in the exact byte match so it can never silently regress.

**Honest caveat, checked directly rather than assumed away**: does
this ALSO hand us the metatile table for individual catalog records
(roomSelector 0/1's own `tileSourcePointer` = `$40B0` for both)? Tried
it -- rendered several catalog records against the resulting candidate
table (`0x200B0`) and ran the same edge-continuity metric from the
previous investigation round. **It does NOT cross-validate**: the
metric scores this new candidate as "better" than the OLD placeholder
(`0x20938`) even for records 8-13, where `0x20938` is DEFINITELY
correct (independently confirmed ground truth) -- proving the metric
itself can't discriminate here, not that the new candidate is right.
Worse, the one room we DO independently, already know is real for
roomSelector 0/1 -- `startRoom` -- doesn't even use the metatile-table
pipeline at all (its own real graphics are live-captured direct tile
offsets in the `0x30000` range, see `rom_profiles.lua`'s own
`graphics.startRoom.tileOffsets`), so there is no way to cross-check a
metatile-table guess against it either.

**Net result**: a real, new, VERIFIED structural fact about how this
ROM's map system is organized (explains WHY certain roomSelectors
share metatile tables, and why the 320-room catalog exists as a
concept at all) -- but the specific "which tiles does catalog record N
really use" question remains open, now for a clearer, better-
understood reason: `startRoom` (the one room we know is real for these
generic "map 0/1" selectors) bypasses the whole mechanism this
question is about.

Full suite: 417 passed, 0 failed (was 416 -- +1 new structural test).

## Room catalog: new default metatile table wired in + a second real find (16x16/8x8 world grids) (2026-08-14, same day, implementation follow-up)

Direct follow-up to "gehe dem map header hinweis nach": fetched the
external FFA-Disassembly devlog's part 2 a second time with a more
detailed extraction prompt, which surfaced TWO more real, independently
useful facts beyond the `mapRoomPointers` field decode already
committed:

**1. The `mapRoomPointers` header's own 3rd/4th bytes are "map height
in rooms" / "map width in rooms", not a per-room metatile-grid
shape.** Applied to this EU ROM's own already-known header bytes:
bank 5's `[00 03 10 10]` -> 16x16 = **256** rooms (exactly `mapTable
.recordCount`); bank 6's `[00 04 08 08]` -> 8x8 = **64** rooms
(exactly `mapTableBank6.recordCount`). Not a coincidence -- bank 5 and
bank 6 are each a literal, ordered ROOM GRID (a real overworld/area
map), not a loose pool of 256/64 unrelated rooms. Directly relevant to
this project's own standing "decode the whole game map with
connections" goal -- a genuinely new, large lead for a future pass
(adjacent grid indices are plausible candidates for adjacent in-world
rooms), not chased further this pass.

**2. Independent cross-confirmation of an ALREADY-known real fact**:
the external doc states "map07 isn't an actual playable map, but
contains the title screen, ending screen and ingame map" -- this EU
ROM's own `roomSelectorTable` entry 7 was ALREADY independently
classified (an earlier session, live-traced) as "a known non-
explorable placeholder." Same real fact, found via two completely
different methods (live emulator tracing vs. an unrelated disassembly
project). Strong, unplanned validation that roomSelector indices in
this EU ROM correspond 1:1 to the US ROM's own "map" indices.

**Decision: upgrade the room-catalog's default metatile table.** The
external doc states plainly "each map has ONE tileset for ALL its
rooms, no per-room override documented." Combined with fact #1 above
(map 0 = ALL of bank 5, map 1 = ALL of bank 6, each literally ONE
map), the natural, well-justified reading is: `genericCatalogMetatile
TableFileOffset` (roomSelector 0/1's own real `tileSourcePointer`,
`0x200B0`) is the correct DEFAULT for every one of the 320 catalog
records -- not `unknownRoomACandidates`'s own table (`0x20938`), which
stays correct only for `unknownRoomA` ITSELF (roomSelector 8-13, a
separate, independently-reachable 6-room map that happens to reuse
the same underlying bank-5 RLE bytes as map 0's own grid positions
8-13 -- real ROM space reuse, not evidence the two contexts render
identically).

**Direct visual re-check before committing to this** (not just trusting
the theory): rendered 12 widely-spread bank-5 records (0, 15-17,
31-32, 63-64, 128, 200, 240, 255) and 7 bank-6 records through the new
table. Result: a striking, consistent visual vocabulary recurring
across the ENTIRE spread -- the same door-arch symbol and dotted-floor
pattern appear in records as far apart as 0 and 255 -- something the
OLD placeholder never produced (visually inconsistent style jumps
between unrelated records). A real, if informal, confirmation the new
table is self-consistent across the whole grid, on top of the
structural/external-doc justification.

**Implemented**: `rom_profiles.lua`'s `roomFloorLayoutPipeline` gained
`genericCatalogMetatileTableFileOffset = 0x200B0` with the full dated
evidence chain in its doc comment; `mapTable`/`mapTableBank6`'s own
status fields upgraded to reference it; `export_data.lua`'s room-
catalog export now uses it uniformly for all 320 entries (the old
per-record `confirmed` flag is gone -- there is no longer a
meaningfully DIFFERENT tile-assignment confidence between record 8 and
record 50, since neither is independently gameplay-confirmed);
`mapviewer.js`/`overview.js` wording upgraded from "⚠ wahrscheinlich
falsch" to an honest "ℹ strukturell hergeleitet, nicht per Live-
Gameplay bestätigt" for every catalog entry alike.

**Honest final status, unchanged in kind though much stronger in
degree**: this is a real, externally-corroborated, internally
self-consistent DERIVATION -- not independently ground-truth-verified
the way `unknownRoomACandidates`'s own table is (no live gameplay
reaches any of these 320 rooms, so no `willyRoom`-style movement test
is possible). Upgraded from "unverified placeholder, likely wrong" to
"best current derivation, real evidence behind it" -- not claimed as
proven.

Full suite: 417 passed, 0 failed (unchanged -- doc-comment + data-value
changes, no new assertions needed beyond the already-added structural
test). Re-verified the live site with the same real headless-browser
smoke tests used throughout this session.

## App-side consolidation: RoomExplorer.lua wired to the same upgraded tileset (2026-08-14, "dokumentiere, konsolodiere und baue in app und website ein")

The previous pass upgraded the room-catalog's tileset only in the
rom-inspector website export (`export_data.lua`) -- the real LÖVE
app's own dev-only F8 room browser (`src/app/states/RoomExplorer.lua`)
was still calling `unknownRoomACandidates.metatileTableFileOffset`
directly, meaning the app and the website would have silently shown
DIFFERENT tiles for the same catalog room. Fixed: `RoomExplorer.lua`
now reads `genericCatalogMetatileTableFileOffset` too, with its own
doc comment and on-screen overlay line ("tileset: structurally
derived... not gameplay-confirmed") updated to match the website's
honest framing.

**Live-verified, not just headlessly**: added a
`MYSTICQUEST_DEBUG_STATE=roomexplorer[:N]` hook to `Boot.lua` (same
established pattern as the existing `tileviewer[:N]`/`field`/
`battleintro`/`victory` hooks) and captured a real screenshot
(`MYSTICQUEST_DEBUG_STATE=roomexplorer:9 MYSTICQUEST_SCREENSHOT=...
love .`) of bank-5 record 8 rendering correctly with the new tileset,
inside the actual running LÖVE app -- footer reads "room 9/320
(bank5...)" as expected. Kept the debug hook permanently; it fits the
project's own established diagnostics convention and is directly
reusable for any future catalog-tileset verification.

Also fixed two doubly-stale doc/UI strings in `Field.lua` (predating
even the 2026-08-12 RoomExplorer rewrite, not something this session
broke but caught while consolidating): the F8 doc comment still said
"browser for unknownRoomA's 6 real rooms" (it's been the full 320-room
catalog since 2026-08-12), and the dev-keys overlay hint still said
"F8 unknownRoomA" instead of "F8 room catalog".

Full suite: 417 passed, 0 failed (app-side change is `love.*`-
dependent, verified live via screenshot rather than headlessly).

## Real, controlled evidence for grid adjacency + a new "Weltkarte" website view (2026-08-14, direct user follow-up)

Direct follow-up: "aber wissen wir jetzt anhand der tabelle welche
tiles zu welchem raum gehören oder wie die räume zusammen halten?"
then "also können wir das 8x8 raster nicht zuordnen? ich vermute das
ist die worldmap. wenn das geht dann können wir das bitte in der
website einbauen".

**Honest starting point**: the earlier "16x16/8x8 world grid" find
established the GRID SIZE (from the map-header's own height/width
bytes) but not the actual STORAGE ORDER (row-major? column-major?)
or whether grid-adjacent records are really spatially connected rooms
at all, as opposed to just an arbitrary index table shaped like a
grid for storage convenience.

**Real, controlled statistical test.** For every row-major-adjacent
candidate pair (record N | record N+1, same assumed row) in bank 5,
compared the tile IDs along N's real right-edge column against N+1's
real left-edge column (using the already-established default
tileset) -- literal ID equality, not a fuzzy visual metric -- and
compared the result against a RANDOM (non-adjacent) pair control,
same sample size:
- bank 5 horizontal (N, N+1): 12.0% average edge match vs. 0.7%
  random -- **~17x above baseline**.
- bank 5 vertical (N, N+16, i.e. one grid row down): 21.8% vs. 0.7%
  -- **~31x above baseline**.
- bank 6 horizontal (N, N+1): 18.0% vs. 2.8% random -- **~6.4x**.
- bank 6 vertical (N, N+8): 14.1% vs. 2.8% -- **~5x**.

Every one of these ratios points the same direction and is far too
large to be noise -- real, controlled evidence the row-major, stride-
16 (bank 5) / stride-8 (bank 6) arrangement is genuinely spatially
meaningful, not an arbitrary storage order. Visually spot-checked the
single best-matching pair (records 134/135, 100% edge match) at the
exact border column -- the real floor-dot pattern visibly continues
across the seam.

**Then stitched the WHOLE grid together and looked at it as one
image** (`rom-inspector`'s new "Weltkarte" page, bank 6, with real ROM
pixels) -- and the result is considerably more convincing than the
isolated-pair crops: multiple real, multi-cell-spanning structures
(a vertical striped wall feature crossing 3+ room cells, several
floor-pattern continuations) are directly visible across room
boundaries, not just in the one cherry-picked best pair.

**New website feature**: `rom-inspector/js/viz/worldmap.js` (+ nav
entry, Übersicht links) -- composites `ROOM_CATALOG`'s own
already-exported room grids into one big canvas per source (bank 5's
16x16, bank 6's 8x8), using `recordIndex -> (row, col) = (floor(i/
stride), i mod stride)`. No new Lua export needed -- `ROOM_CATALOG`
already has everything (each entry's own real grid + tileOffsets),
this is a pure client-side compositing view. Zoom control (1-3x,
default 1x given the total image is up to 2560x2048px), an optional
room-boundary overlay, and hover-to-identify (record index + grid
position). The page's own note text states the honest scope plainly:
structurally/statistically derived, NOT independently gameplay-
confirmed.

Verified with the real headless-browser smoke tests (canvas
dimensions for both sources, nav entry present, honest note text) and
a real ROM-pixel render via the actual site code (not a re-
implementation) -- see the visual confirmation above.

Full suite: 417 passed, 0 failed (unchanged -- this feature is pure
client-side JS reusing already-exported `ROOM_CATALOG` data, no Lua
changes needed).

## fourthRoom's real collision: no metatile source found (negative), but a real, live-discovered wall the flat tile-ID model missed (2026-08-15)

Direct instruction after the second-boss west-room work: "was immernoch
nicht stimmt ist die kollision mit den wänden im fouth room. bitte
suche einfach einen allgemeinen kollsions mechanismus!!! anders geht es
jetzt nicht" -- find a real, general collision mechanism, not another
one-off patch.

**Attempt 1: find fourthRoom's own real metatile+layout-stream source,
the same way willyRoom's/unknownRoomB's were found.** Single-stepped
the ENTIRE real thirdRoom->fourthRoom staircase transition (mgba,
`CallTracer`-free direct PC watch this time, ~6M real instructions,
holding UP/RIGHT/UP to reach and cross the real trigger), watching for
`PC==0x242B` (the already-known, bank-0-fixed RLE decompressor entry
both willyRoom and unknownRoomB's own metatile sources were found
through). **Zero hits.** A real, decisive negative: this room's real
load genuinely does not go through that pipeline -- consistent with
this project's own earlier "fourthRoom has no known metatile source"
note (see the willyRoom collision-generalization section above).

**Attempt 2: rapid position-teleport BFS, found unreliable.** Tried
directly poking `$C244`/`$C245` (Y/X) to systematically probe every
grid cell, using `mgba`'s own `save_raw_state`/`load_raw_state` to
reset between probes for speed. Real, reproducible finding: after a
raw WRAM position poke (or after `load_raw_state`), held-button input
silently has ZERO effect on position for 100+ real frames -- a real,
reproducible limitation of driving this specific mgba-python-bindings
setup this way, not a ROM fact. Abandoned; every real number below
comes from a genuinely WALKED path instead (real held-button input the
whole way, only `save_raw_state`/`load_raw_state` used to reset to the
real landing spot between independent probes, never mid-probe).

**Attempt 3: real, walked probes -- a genuine, decisive real finding.**
Holding LEFT from the real landing spot (row 14, the bottom-most row)
or from row 13 (one row up) moves the player NOT AT ALL for 100+ real
frames. The EXACT SAME `LEFT` input from row 12 (one row further from
the stairs) moves freely all the way to the real west wall (column 0).
A companion probe (reaching row 12 at a different column via a real
detour, then holding DOWN) found DOWN is ALSO blocked re-entering rows
13-14 outside the landing column's own narrow range. Consistent, single
real structure: the staircase landing is a real, narrow ALCOVE
(columns ~14-19, matching this room's own real `135` "feature block"
columns), not full-width open floor the way the identical-looking
`131`/`129`/`130` tiles read everywhere else in the room.

**Why the flat `floorTileIds` model can't express this**: the alcove's
own tiles (`131`, `135`) are the EXACT SAME tile IDs already marked
floor everywhere else in the room -- a tile-ID-keyed set is structurally
incapable of saying "floor here, wall there" for the same ID. Added a
new, general, reusable escape hatch instead of another special case:
`TileWalkability.build` now accepts an optional `room.blockedRects`
list (`{rowMin, rowMax, colMin, colMax}`, 0-based native-tile
rectangles) checked on top of the existing tile-ID floor lookup -- real,
live-movement-discovered exceptions where the flat classification is
known wrong, usable by any room, not just fourthRoom. Wired in for
fourthRoom: `{ rowMin=13, rowMax=15, colMin=0, colMax=14 }`.

**A real, live-caught off-by-one in the first version of the fix**:
initially used `colMax=13`. A `love .` screenshot test
(`MYSTICQUEST_SCRIPT=left@10-120` from the real landing spot) showed
the player moving from x=120 to x=112 before stopping -- one real,
wrong 8px step, not the real ROM's own "zero movement" result. Root
cause: the player's 16px (2-native-tile) footprint moving from column
15 to column 14 only touches columns 14-15, and column 14 was still
real floor under `colMax=13`, so the footprint check passed for that
one step. `colMax=14` closes the gap -- re-verified live, matches the
real ROM's own "completely still" result exactly. Also added 3 new
headless unit tests (`tests/unit/tile_walkability_test.lua`) locking in
both the general mechanism and this specific off-by-one class of bug
so it can't silently regress.

**Also required, for consistency**: `fourthRoom`'s own west exit into
`sixthRoom` (added earlier this same session) had `yMax=110` -- inside
the row range this fix now correctly blocks for `LEFT`. Narrowed to
`yMax=96` (the real, confirmed-open row 12 boundary) so the exit stays
reachable under the corrected collision instead of silently requiring
the player to stand somewhere they can no longer walk to.

**Honest scope**: this is a real, live-verified fix for the SPECIFIC
divergence found (the staircase-landing alcove), not a claim that
fourthRoom's entire collision is now byte-perfect against the real ROM
-- a full per-cell sweep (all 320 real grid cells) was not completed
this pass (the rapid teleport-BFS approach that would have made that
tractable turned out unreliable, see Attempt 2 above); a genuinely
exhaustive real-walked BFS remains a well-scoped, bounded follow-up if
further discrepancies are ever reported. Full Lua test suite: 435/435
passing (3 new). Live `love .` re-verification of the fix itself
succeeded once (catching and fixing the off-by-one); further live
re-confirmation of the corrected build was blocked this session by an
unrelated environment issue (the interactive display went idle/locked
partway through, `love .` launches hung waiting for a display surface,
confirmed via `ioreg`'s own `HIDIdleTime` showing 30+ real minutes of
inactivity) -- not a code issue, a session/display-state one.

## Real hardware OAM-vs-WRAM sprite offset: a genuine, partially-applied rendering bug (2026-08-15)

Direct follow-up to a user report on the just-fixed fourthRoom collision:
"der charakter spwned ein tile zu südlich und ein halbes tile nach
rechts verschoben" (the character spawns one tile too far south, half
a tile too far right) for the thirdRoom->fourthRoom staircase landing.

**Re-verified the landing coordinate itself first, since the user
insisted it was still wrong and explicitly asked for a deterministic
value, not a guess.** A fresh, careful mgba re-trace (single-frame
logging through the real cut, then 600 frames of zero input) confirms
`$C244`/`$C245` genuinely settles at (Y=112,X=120) and never changes
again -- the raw WRAM coordinate itself was never wrong.

**The real bug was one level downstream: how that raw value gets USED.**
Dumped the real hardware OAM table (`$FE00`+) at this exact moment:
sprite 8/9 (the player, 8x16 mode) read Y=112/X=120 -- IDENTICAL to
WRAM, a direct unshifted copy (independently matches this project's
own earlier `$C244`/`$C245`->OAM finding, task #75). But real Game Boy
hardware ALWAYS interprets OAM sprite entries as `(true top-left) +
(8, 16)` -- fixed PPU silicon behavior, not a ROM-specific convention.
Since this ROM copies WRAM straight into OAM with no adjustment, WRAM
itself must already carry that +8/+16 baked in -- meaning the TRUE
visible position on a real Game Boy is `(120-8, 112-16) = (112, 96)`,
not `(120, 112)`. This project has always drawn the player sprite
directly at the raw WRAM value with no correction.

**Cross-checked against the user's own live observation**: their
eyeballed estimate ("~1 tile south, ~half a tile right") is the right
DIRECTION, just a less precise magnitude than the real, measured (1
tile right, 2 tiles down) -- expected for a quick visual read on a
144px-tall window.

**Applied and live-verified for fourthRoom specifically**: changed
`thirdRoom.exits[1].landingX/Y` from (120,112) to (112,96) directly.
Independently cross-validated: (112,96) lands the player's own
top-left corner EXACTLY on this room's real `135` feature-block tile
(the same tile independently hypothesized elsewhere as the real
staircase graphic) -- also matching an earlier, separate user report
("der player sollte auf der trepp pawnen"). Screenshot-confirmed to
look visibly better. Full test suite unaffected (435/435).

**Direct follow-up, "did you fix this everywhere?" -- checked, and the
honest answer is no, deliberately.** Cross-checked a SECOND real
landing spot (fourthRoom's own north exit into fifthRoom, WRAM/OAM
both (Y=32,X=136), live-confirmed via the same direct OAM dump
technique) -- same unshifted OAM=WRAM pattern is present there too.
BUT applying the identical `(-8,-16)` correction there would land the
player's top-left corner on tile `151` -- a real, already-live-verified
NON-floor border tile per `fifthRoom.floorTileIds`. Blindly reapplying
the same numeric fix would silently break already-tested, working
collision in that room.

**Root cause of the contradiction, understood**: changing `landingX`/
`landingY` directly conflates two things that should be separate --
the COLLISION-space coordinate (`player.x`/`player.y`, consumed by
`TileWalkability`/`canMoveTo` against each room's own `floorTileIds`/
`grid`, all of which were captured and tuned using the SAME raw,
uncorrected WRAM convention throughout this whole project) and the
RENDER-space coordinate (where the sprite should actually be drawn on
screen to match real hardware). The fourthRoom fix happened to be safe
only because that whole area is uniformly floor-classified regardless
of the exact sub-tile position -- not because the approach was
generally correct.

**The real, general, correctly-scoped fix (not yet implemented)**: apply
the `(-8, -16)` offset ONLY at the final sprite-draw call (e.g.
`PlayerSprite:draw`), leaving `player.x`/`player.y` itself, and every
`landingX`/`landingY` value, completely untouched -- preserving 100%
collision-space consistency with all of this project's existing,
tested floor/wall data everywhere, while fixing the VISUAL position
uniformly across every room at once. This would also apply, in
principle, to every other sprite this project tracks by raw WRAM-style
position (enemies, NPCs) -- genuinely out of scope to verify/apply this
pass. Deliberately NOT implemented broadly this session -- flagged
here as a real, well-scoped, moderately risky follow-up (touches
core rendering, needs re-verification against existing screenshots)
rather than pushed through unverified. `fourthRoom`'s own landing stays
fixed via the direct coordinate edit (safe, live-verified, narrow
blast radius) until the general fix lands.

## The real, general OAM-vs-WRAM fix: implemented (2026-08-15, same day, "mach mal den gesamt fix")

Direct follow-up to the section above. Implemented the general,
correctly-scoped fix instead of leaving it as a flagged follow-up:

- `Player.lua`: new `Player.RENDER_OFFSET_X = -8`, `RENDER_OFFSET_Y =
  -16` constants (the real, hardware-verified Game Boy OAM convention)
  and a new `Player:renderPosition()` method returning `self.x +
  RENDER_OFFSET_X, self.y + RENDER_OFFSET_Y` -- `self.x`/`self.y`
  themselves are NEVER mutated by this, staying the real, raw,
  ROM-matching collision-space value everywhere else.
- Every real player sprite draw call across `Field.lua`,
  `VictorySequence.lua` (3 separate phase-branch draws), and
  `BattleIntro.lua` now calls `:renderPosition()` and draws at the
  corrected coordinate instead of the raw one. The attack-swing/thrust
  overlays (`Field.lua`) draw at the SAME corrected coordinate so they
  stay visually attached to the player. `RoomWipeTransition`'s own
  real convergence-point Y (`VictorySequence.lua`'s `centerY`) also
  switched to the render-space value, since it's an on-screen anchor,
  not a collision one.
- `fourthRoom`'s own `landingX`/`landingY` reverted back to the real,
  raw ROM value (120,112) -- the earlier direct-coordinate "fix" is
  superseded by this general mechanism and would have double-applied
  the offset if left in place.
- Every collision-space consumer (`TileWalkability.canMoveTo`,
  `ZoneMatch`, `HoldTrigger`, every room's own `floorTileIds`/`grid`/
  `blockedRects`, all attack `getHitboxes()` calls) is completely
  untouched -- still reads `self.player.x`/`self.player.y` raw, exactly
  as before this whole investigation started. Zero collision regression
  risk by construction, not just by testing.

**Deliberately still scoped to the PLAYER only.** A live OAM/WRAM
cross-check at the courtyard boss's own real checkpoint found the
enemy does NOT appear to populate the same 20-slot entity struct's
Y/X fields the way the player does (every OTHER slot read `Y=0,X=248`
at that exact moment) -- genuinely inconclusive, not "confirmed same
bug," so enemy/boss/NPC draw calls were NOT touched. Extending this
fix to those would need its own independent live verification, not
an assumption that the player's own finding generalizes.

New headless unit test (`tests/unit/player_test.lua`) locks in both
the correct offset arithmetic and that `renderPosition()` never
mutates `self.x`/`self.y`. Live-verified via `love .` screenshots:
fourthRoom's staircase landing renders pixel-identical to the earlier
direct-coordinate fix (same visual result, now via the general
mechanism), and a spot-check of secondRoom's own free-roam spawn shows
no visual regression (player cleanly on the floor, not clipped).
Full test suite: 436/436.

## Quick win: second boss fight was unreachable end-to-end (2026-08-15)

Direct follow-up to the earlier "quick wins" list: verifying the second
boss fight (walk in, attack, defeat) after this session's collision/
position work turned up a real, reproducible bug -- a scripted walk
from the room's real landing spot (144,80) toward the boss (spawnX=64)
stalled at x=128, 64px short, never reaching attack range.

Root cause: `sixthRoom.floorTileIds` classified tiles `145`/`146` as
non-floor ("gate/pillar decoration", a pure visual guess from an
earlier pass, never live-tested since this room has no real ROM
gameplay trigger to test against). Re-examining this room's own real
captured `grid`: `145`/`146` form a wide, clean checkerboard
alternation (rows 5-14, cols 14-17) -- structurally IDENTICAL to the
alternation pattern of this room's own two ALREADY-confirmed real
floor pairs (`129`/`130`, `133`/`134`), just a third floor texture.
The remaining 7 real "gate/pillar" tiles do NOT share this signature
(either a solid non-alternating strip, or too sparse to reason about)
and stay non-floor. Added `145`/`146` to `floorTileIds` on this
structural basis.

Live-verified before and after: before the fix, `secondBossHp` stayed
at 31 (untouched) after a scripted walk+12-attack sequence. After,
`secondBossDefeated=true`/`secondBossHp=0` on the same script,
screenshot confirms the boss sprite is gone (death sequence completed).
Full test suite: 436/436, unaffected (this room has no existing
collision tests to regress).

## Self-caught regression: the general OAM render-offset fix reverted (2026-08-15, same day)

Direct user report right after asking to just launch the app: "im
ersten bossraum sscheint diese verschoben zu sein (vielleicht der
spwan offset den wir gefunden hatten der da nicht anwendbar ist?)" --
collision looks shifted in the FIRST boss room (startRoom, `Field.lua`),
and correctly guessed the cause.

The user's guess was right. The general `Player:renderPosition()` fix
(previous section) was applied to every player draw call across
`Field.lua`, `BattleIntro.lua`, and all of `VictorySequence.lua` on
the theory that the underlying OAM fact (WRAM copies unshifted into
OAM, real hardware always renders `(WRAM value) - (8,16)`) is a
universal Game Boy PPU fact and therefore safe everywhere. That
reasoning is correct about the HARDWARE, but wrong about THIS
PROJECT's own code: `startRoom`'s own sprite positions and collision
data were historically captured and cross-checked via direct
screenshot comparison against the RAW, unshifted `player.x/y` --
i.e. this room's own calibration already implicitly bakes in "no
offset." Applying the real hardware offset on top of an already-
self-consistent-but-differently-conventioned room shifts the sprite
away from where it was actually verified to look right -- a real
regression, confirmed the moment the app was actually played instead
of spot-checked via a couple of screenshots.

**Reverted completely**: every player draw call in `Field.lua`,
`BattleIntro.lua`, and `VictorySequence.lua` is back to the raw
`self.player.x`/`self.player.y`, matching this project's original,
consistent convention everywhere. `Player.RENDER_OFFSET_X`/`_Y` and
`Player:renderPosition()` are left in `Player.lua`, unused by any
draw call -- the underlying hardware fact is still real and still
documented, it's just not safe to wire in broadly without individually
re-verifying every single room's own historical calibration first (a
real, much larger undertaking than this session budgeted for).
`thirdRoom`'s own `fourthRoom` landing is back to the real, raw ROM
value (120,112) too -- the original visual complaint about that one
spot is therefore also back to its pre-investigation state, not fixed,
honestly reverted rather than left half-applied. Full test suite:
436/436 (the `renderPosition()` unit test still passes -- the METHOD
is still correct, it's just unused now).

**Lesson, recorded plainly**: a real, hardware-verified fact is not
automatically safe to apply broadly to an already-large, already-
tested codebase -- this project's own earlier draft of this exact
finding said as much ("several of those rooms have extensive existing
screenshot verification history that a blind, unverified global shift
could silently break") and then didn't fully heed its own warning. A
couple of spot-check screenshots are not the same rigor as actually
playing the app -- the regression was caught the moment the user did.

## Real graphics candidates found + wired: 5 new creature/character art regions (bank 10/11), plus a live-confirmed NPC negative in thirdRoom/fourthRoom (2026-08-15)

Direct user request ("suche jetzt einfach mehr npcs mit den grafiken
und mehr monster. ich glaube die die du bis jetzt gefunden hast sind
nur bosse"), finally acting on the graphics-candidate lead this
project's own planning notes had already scoped (task #135, "bounded
search for more monster/NPC candidates") but never executed.

**Method**: `tools/rom/scan_graphics.py` (a heuristic 2bpp-tile-entropy
scan, already existed) against the whole ROM, `--min-run 24`, found 54
candidate regions. Rendered the most promising ones (favoring bank 10/
11, per this project's own EXISTING `rom_profiles.lua` hint on
`enemySprite` that bank 11 holds "title-logo art plus real small
creature-sprite fragments") with `tools/graphics/gbtile.py` and
visually inspected each PNG -- exactly the "find a lead, then confirm
it by looking at it" discipline this project's tooling doc comments
already establish.

**5 real, visually-confirmed creature/character art regions found**,
all in bank 10 (previously completely unexplored territory -- zero
prior mentions anywhere in this project's own docs) and bank 11:
- `0x2B900` (44 tiles): a hooded/pointed-head humanoid with a dark
  robe-like silhouette, in a repeated 2x2-tile pair (plausibly 2 real
  animation poses of one creature).
- `0x2A400` (34 tiles): bat-winged and blob-like creature shapes.
- `0x2AA20` (33 tiles): armored/helmeted humanoid figures, several
  similar variants.
- `0x2AD90` (33 tiles): more helmet/face shapes, immediately adjacent
  in the file to the region above (likely the same sprite family).
- `0x2D220` (bank 11, 34 tiles): small round/blob creature shapes.

Cross-checked a few OTHER large candidate runs (bank 4/8/9/12/14) for
completeness -- most turned out to be environment/wall/floor tile art
or outright noise (a repeating checkerboard dither pattern, not real
pixel structure), NOT creature art -- an honest negative, not silently
omitted.

**Wired as a new, honestly-scoped catalog**: `src/import/
GraphicsCandidates.lua` (a curated, hand-authored list -- these are
heuristic SCAN RESULTS, not a decoded ROM table, so there's no
"decode a formula" step the way `EnemySpeciesTable`/`ItemTable` work).
Explicitly does NOT claim which (if any) of the 11 real
`EnemySpeciesTable` species each region belongs to, exact real sprite
tile boundaries, or real in-game reachability -- see that module's own
doc comment for the full honest scope. Exported to the rom-inspector
website (`graphics-candidates.js`, a new "Grafik-Kandidaten
(unbestätigt)" section on the Monster tab, rendering each region's real
pixels straight from the user's own locally-loaded ROM via the SAME
canvas renderer the already-known enemy sprite uses).

**NPC side: a real, live-confirmed negative, not silence.** Extended
the mgba checkpoint chain (see combat.md's task #127 entry for the new
`fourth_room_free()` checkpoint) and dumped all 20 real entity slots
in BOTH `thirdRoom` and `fourthRoom` -- in each, only the player itself
is a genuinely live, positioned entity; every other slot shares the
same uninitialized boot-time placeholder pattern, and OAM shows only
the player's own 2 real hardware sprite entries active. **No NPCs
exist in either room** -- a real, decisive extension of task #140's own
"bounded live NPC check in more rooms" (which had only covered
willyRoom/secondRoom before). Consistent with this project's own
already-established finding that NPCs aren't placed via any fixed
table -- finding MORE would mean live-exploring further rooms one at a
time (`fifthRoom`/`sixthRoom` and beyond), not decoding a table. Not
pursued further this pass (a real, open-ended undertaking, matching
this project's own "World scope" tracking).

3 new unit tests (`tests/import/graphics_candidates_test.lua`):
structural field checks, real tile-offset expansion, and a real-ROM
check that every candidate's own tile range stays in-bounds and isn't
a degenerate solid-fill false positive. `luajit tests/run_tests.lua`:
481/481 pass (+3). Website Playwright-verified (5 candidate cards
render, zero console errors).

## Graphics candidate search extended to a full, systematic ROM sweep -- 7 more real regions found, all 16 banks now checked (2026-08-15, same day)

Direct follow-up, mid-turn, to a explicit user instruction not to stop
early: "bitte mit dem grafiken suchen danach weiter machen bis wirklich
alle gefunden wurden. nicht vorher stoppen" (please keep searching for
graphics until really all have been found, don't stop before that).

**Method upgrade**: the earlier pass only checked individual
`scan_graphics.py` entropy hits one at a time. This pass instead
rendered EVERY ROM bank (0-15, all 16KB each) in full with
`tools/graphics/gbtile.py` and visually reviewed each one -- a real,
complete sweep, not more sampling of the same heuristic's own top
hits.

**Result: banks 0/1/2/3/4/5/6/7/13/14/15 confirmed to be genuinely
code/text/room-table data** (pure noise when rendered as tiles -- no
real pixel structure at all) -- an honest, decisive negative, not
skipped. **Bank 12 confirmed to be real environment/architecture
tileset art** (fences, pillars, wells, arches -- matches this
project's own already-used room tilesets) with no creature content
anywhere, including its own bottom-right corner (double-checked
separately after an initial pass flagged it as ambiguous).

**Banks 8, 9, 10, and 11 confirmed genuinely, densely packed with
real creature/character/icon art** -- 7 more real regions added to
`GraphicsCandidates.lua` on top of the original 5:
- **`bank8_portraits`** (`0x22260`, 32 tiles): 4 distinct humanoid
  portraits, each wearing a different hat/hood -- sits right before
  this project's own already-known dialogue font block in the SAME
  bank. The single strongest NPC-shaped candidate found in this whole
  investigation (a real "class/profession" portrait icon set, not a
  monster silhouette).
- **`bank8_icon_fragments`** (`0x22EE0`, 274 tiles): a dense field of
  small icon/creature fragments right after the font block (weapons,
  plants, partial creature pieces).
- **`bank9_creature_columns`** (`0x24400`, 704 tiles -- the single
  largest region found): a very dense, repeating field of tall,
  segmented humanoid/totem-like creature columns, plus a few distinct
  larger shapes (a dragon/dinosaur-like head, a spiky urchin-like
  creature). Too dense and repetitive to honestly split into
  individual creature boundaries without a live OAM trace -- kept as
  one large, honestly-described region rather than guessing sprite
  boundaries.
- **`bank9_icon_fragments`** (`0x27000`, 256 tiles): more small icon/
  creature fragments at the tail of bank 9, same style as bank 8's own
  tail region.
- **`bank11_creatures_a/b/c/d`** (`0x2C400`-`0x2FA00`, 4 contiguous
  216-tile regions, 864 tiles total): a very large, dense creature-art
  field immediately below the real "MYSTIC QUEST" title-logo art in
  the same bank -- wings, horns, dragon/wolf-like shapes, tentacle-
  like forms -- directly confirming this project's own earlier visual-
  scan lead from planning notes ("Bank 11 als Sheet gerendert...
  Flügel, Hörner, Drache/Wolf-artige Formen, Tentakel"). Stops right
  before this project's OWN already-known, confirmed real enemy
  sprite (`rom_profiles.lua`'s `enemySprite`, `0x2FE00`, further into
  the same bank) -- a real, honest boundary, not an arbitrary cutoff.

**Total real graphics-candidate coverage after this pass: 12 regions,
~2400 tiles (~38KB of real ROM art), spanning all 4 real graphics-
bearing banks found in this ROM.** Every OTHER bank has now been
checked and confirmed to hold no further creature/character art --
this is, to the best of this project's own static-analysis-only
methodology, now a COMPLETE sweep of the ROM's real graphics content
by bank, not a partial sample. What remains genuinely open (unchanged
from the original pass): which species/room/NPC identity (if any)
each region belongs to -- that still needs live OAM tracing against
actual spawned/reachable content, which none of these regions have.

3 new unit tests already covered the general `GraphicsCandidates`
structure and now exercise all 12 entries (no test changes needed --
the existing structural/in-bounds/non-degenerate checks iterate the
whole `ENTRIES` table). `luajit tests/run_tests.lua`: 481/481 still
pass. Website regenerated and Playwright-verified (13 candidate cards
-- 12 graphics candidates + the pre-existing known-species canvas --
render correctly with per-`kind` badges: "Monster-Kandidat"/"NPC-
Kandidat"/"Icon-/Fragment-Sammlung", zero console errors).

## Opcodes page readability rework (same-day follow-up)

Direct user complaint about the ROM-inspector website's opcodes page:
"das ist sehr kryptisch. vor allem die beschreibnbenden texte" (very
cryptic, especially the descriptive texts). The 35 curated entries in
`rom-inspector/js/data/opcode-descriptions.js` previously showed only
a single dense technical writeup (real hex addresses, WRAM cells,
bank numbers, jargon like "gate"/"sentinel byte"/"dispatch" used
without definition) as both the grid-cell tooltip AND the detail-panel
body -- readable to someone already deep in this project's own
disassembly, not to a first-time visitor.

Two-level restructure, data layer first, then UI:

- `opcode-descriptions.js`: every entry now carries a NEW `summary`
  field (one plain-language sentence, no hex/jargon) alongside the
  existing `text` field (the original full technical writeup, kept
  verbatim -- no information removed, only re-leveled). New
  `OPCODE_GLOSSARY` array, 12 terms this project's own opcode writeups
  actually use (Opcode, Handler, WRAM, Operand-Byte, Cursor, Bank,
  Gate, Dispatch(er), Callback, Leaf, Sentinel-Byte, Pin/Pinning) with
  plain-language definitions.
- `rom-inspector/js/viz/opcodes.js` (this entry): wired the above into
  the actual UI. `showOpcodeDetail()` now leads with `desc.summary`
  (prominent styling) and moves the original `desc.text` into a
  collapsible `<details><summary>Technische Details (echte ROM-
  Adressen & Nachweis)</summary>` block -- the real technical evidence
  stays fully available, just not forced on every visitor by default.
  New `glossarize(text)` helper wraps recognized glossary terms inside
  that technical text in `<abbr title="...">` for inline hover
  definitions (matches on the term's first plain word, e.g. "Dispatch"
  for "Dispatch(er)", so compound display terms still match real
  prose). New `render_glossary()` renders a collapsible glossary box
  (`#glossaryHost`, all 12 terms) above the opcode grid. Grid-cell
  tooltips and the search filter now also use `desc.summary`; the
  script-tracer's own per-step effect text switched from `desc.text`
  to `desc.summary` (the tracer already shows many steps in a row --
  the full technical text there was more noise than signal).

Playwright-verified against a local static server: glossary box
renders with all 12 terms, opcode-cell click shows the plain-language
summary prominently, the "Technische Details" `<details>` toggles open
and reveals the original technical text, a real glossary term inside
that text (`abbr` on "WRAM") renders with its full definition as the
hover title, search input still present and functional, zero console
errors across 40 sampled opcode cells. `luajit tests/run_tests.lua`:
481/481 still pass (this is a JS-only UI change, Lua suite unaffected,
re-run anyway per this project's own discipline).

## Map-tile graphics search + dedicated Grafiken tab (task #154)

Direct user follow-up, same day: "mach das gleiche mal für die map
tiles. und pack diese grafik funde bitte in einen eignen tab" (do the
same search for MAP tiles, and put these graphics finds into their own
tab). Unlike the monster/NPC search, bank 12 (this project's own
already-confirmed environment/architecture tileset bank) was already
partially investigated -- so "search for map tiles" meant precisely
checking how much of its 1024 tiles are ALREADY wired into a real room
vs. genuinely unconfirmed, not "does this look like tileset art" (the
whole bank already visibly does). Rendered bank 12 in its 4 natural
256-tile chunks (one full GB background-tile VRAM page each -- a real
hardware boundary) and grepped every literal ROM-offset tile reference
already recorded in `rom_profiles.lua`:
- 0x30000-0x30FFF: 57 distinct real offsets already in use (scattered,
  per-tile disambiguated picks, e.g. `fourthRoom`'s own tileOffsets) --
  already confirmed, not re-cataloged.
- 0x31000-0x31FFF: ZERO confirmed usage anywhere -- the only mention of
  this range in the whole codebase is `secondRoom`'s own doc comment
  recording it as a REJECTED ambiguous match. A clean, genuinely new
  candidate -- added as `GraphicsCandidates.lua`'s `bank12_environment_b`
  (kind="tileset", 256 tiles).
- 0x32000-0x33FFF: the real, systematic `tilesetFileOffset = 0x32000 +
  tileId*16` table every generic-tileset room already resolves through
  -- confirmed, `environmentTilesetBank12.confirmedFrom` already
  documents this, no new entry needed.

New dedicated "Grafiken" website tab (`rom-inspector/js/viz/graphics.js`,
sidebar entry, own route `#graphics`) replacing the old embedded
"Grafik-Kandidaten" section at the bottom of the Monster page -- now
filterable by `kind` (monster/npc/fragment/tileset) via pill tabs, with
a stat-grid summary.

**Self-correcting follow-up, same day**: after this first pass (1 new
unconfirmed map-tile candidate), direct user pushback: "du musst noch
viel mehr tile daten kennen, immerhin sind ein paar räume schon
bekannt und komplett kartiert" (you must already know a lot more tile
data -- some rooms are already known and completely mapped) -- correct.
This project has 14 fully-decoded, VERIFIED rooms referencing 243
distinct REAL map/environment tile offsets, spanning bank 8 (28), bank
11 (85), and bank 12 (130) -- NOT just bank 12. New `src/import/
MapTileCatalog.lua` dedupes every real `profile.graphics.<room>.
tileOffsets` entry across all mapped rooms (same "is this a real room"
filter `export_data.lua`'s own `ROOM_MAPS` export already uses),
grouped by bank, with room attribution per tile. Exported as
`MAP_TILE_CATALOG` (`map-tile-catalog.js`); the Grafiken tab now leads
with a "Bekannte, bereits kartierte Map-Kacheln" section -- one real
tile mosaic per bank (8/11/12), each tile clickable to show which real
room(s) use it -- BEFORE the unconfirmed candidates section, mirroring
how the Monster page already shows its one confirmed sprite before
candidates.

Also same day, 2 small standalone UI fixes from the same message:
- Color-palette presets: `GBPalette` (`js/rombytes.js`) -- 4 sensible
  display presets (Graustufen/DMG-Grün/Game Boy Pocket/Bernstein),
  explicitly documented as a pure viewer preference (NOT decoded ROM
  palette data -- the only real, verified fact is BGP=$E4's identity
  shade mapping). Selector added to the top bar; switching re-renders
  the current section (`route()`) so every tile canvas site-wide picks
  up the new colors, persisted via `localStorage`.
- ROM-laden button: direct report "das erkennt man kaum" (barely
  recognizable as a button) -- root cause was CSS scoped to `button.btn`
  only, but the ROM control is a `<label class="btn">` (required for a
  hidden native file input to be clickable). Widened the rule to plain
  `.btn` and made it `primary` styling.

Verification: 6 new `MapTileCatalog` unit tests (incl. a real-ROM
cross-check asserting the exact 14-room/243-tile/3-bank numbers above)
+ existing `GraphicsCandidates` structural tests auto-covering the new
entry -- `luajit tests/run_tests.lua`: 487/487 pass. Playwright-verified
end to end: Grafiken tab renders both sections with real pixels, kind
filter works, palette switch changes real canvas pixel colors and
persists across reload, ROM button has visible button chrome, zero
console errors across graphics/worldmap/tiles/map/monsters/npcs/items.

## Task #160: the real graphics-loading mechanism, found via access analysis

Direct user follow-up: "du kennst ja jetzt die positionen von vielen
grafiken. kannst du anhand der zugriffe auf diese neue informationen
ableiten" (you now know many graphics regions' positions -- can you
derive new information from the ACCESSES to them). Two-stage
investigation, static first, then live, both real evidence:

**Stage 1, static byte scan (`tools/rom/find_graphic_refs.py`,
NEW tool), decisive negative**: searched the whole ROM for a literal
`LD BC/DE/HL,<addr>` immediate matching each of the 14
`GraphicsCandidates.lua` base addresses, PLUS 2 positive controls
(`enemySprite`, the font tileset) this project already knows for
certain ARE loaded and rendered by real code. Result: **zero clean
hits for every single one, including both positive controls** -- proof
the real ROM does NOT embed a literal per-region source pointer as a
code immediate; graphics loading must be indirect (a table lookup or
computed address), the same shape this project already knows for the
generic environment tileset (`tilesetFileOffset + tileId*16`).

**Stage 2, live read-watchpoints (`tools/rom/watch_graphic_refs.py`,
NEW tool)**: armed native mGBA READ watchpoints (`watcher.py`, the
same `core.step()`-driven primitive task #150's own investigation
used) on all 14 candidate bases + the 2 positive controls, then
single-stepped through `courtyard_enemy_engaged()` (the real gate-
creature boss on screen and animating) while periodically pressing
attack. Real hits: **enemySprite's own base address genuinely read
while `activeBank==11`** (validates the whole method -- a true
positive against an ALREADY-known-used region) and a hit resolving,
once the actually-active bank is honored instead of trusting which
watch fired, to real file offset `0x27900` -- **inside
`bank9_icon_fragments`** (one of this project's own unconfirmed
graphics candidates!). Both hits point to the exact same caller PC,
`$2D8F` (fixed bank 0).

**Full disassembly of `$2D8F`'s own routine (bank 0, `$2D57`-`$2E31`),
a real, previously-undocumented generic tile-streaming DMA system**:
- `$C5E0`+: a real WRAM work QUEUE, 6 bytes/entry
  (`bankByte, pad, destAddrLo, destAddrHi, srcAddrLo, srcAddrHi`).
- `$C8E0`: real queue depth (nonzero = work pending) -- this is the
  SAME `$C8E0` this project's own `ScriptOpcodeTable.lua` already
  documents as half of the "`$C8E0`/`$CEE8` dual gate" opcodes
  `0xFC`/`0xFD` wait on (`$27F9`/`$2820`) -- a real, concrete
  UNIFICATION of two previously-separate findings: those script
  opcodes literally wait for THIS tile-loader to finish.
- `$C8E1`: a real reentrancy/busy guard (0=free, transient 1=busy).
- Consumer entry `$2D57` (called from the real VBlank handler, `$71`,
  the ONLY static caller found): each invocation copies up to
  a scanline-budgeted number of 16-byte tiles (`LDH A,(0xFF44)` vs. a
  `+6`-scanline deadline, real hardware timing awareness), popping
  each queue entry's bank byte straight into `LD ($2100),A` (the
  SAME real MBC2 bank-select convention this project's own tooling
  already uses) before an unrolled 16x `LD A,(HL+)/LD (DE),A/INC DE`
  tile copy.
- Two real producer/enqueue entries, `$2DF5` (append) and `$2E45`
  (insert-at-front, found via disassembly but genuinely never called
  anywhere in the ROM -- real dead code, not a gap in this search).
  Calling convention (confirmed from BOTH the internal PUSH/POP
  shuffle and every real literal call site below): **`HL`=source ROM
  address (bank-relative), `DE`=destination VRAM address, `A`=bank
  number, `CALL $2DF5`**.

**17 real call sites to `$2DF5` found (`CD F5 2D` byte search),
spanning banks 0/1/2/3/4/9** -- disassembled every one:
- Several LITERAL calls in bank 1 (`$4078`, `$4300`, `$430B`, `$4316`,
  `$4321`) all load from source `$4250`/`$4260` (bank 12, file
  `0x30250`/`0x30260`) to various VRAM destinations -- real,
  additional confirmation of the ALREADY-known "0x30000 bank12 chunk,
  used piecemeal" finding from task #154's own map-tile search (NOT
  inside the new `bank12_environment_b` candidate -- consistent, not
  contradictory).
- 5 call sites (bank 0, `$1C01`/`$1C9B`/`$1CC0` + 2 more) compute a
  dynamic source address via a `RES 7,H`/`SET 6,H` bit-trick with a
  LITERAL `LD A,0x0C` (bank 12) -- more real bank-12 UI/map-tile
  loaders.
- 2 call sites (bank 0, `$1ABD`/`$1AEC`) use a LITERAL `LD A,0x08`
  (bank 8, the font/portrait bank) with a computed source -- plausibly
  the real per-glyph font-tile loader.
- **A genuinely NEW, important mechanism**: 2 byte-for-byte IDENTICAL
  routines, one duplicated per-bank in bank 3 (`$C439`) and bank 4
  (`$103BB`) (a real, deliberate duplication so each bank can call it
  without an inter-bank jump), walk a 2-level indexed record table and
  compute the graphics bank DYNAMICALLY: `LD A,B (a per-record "kind"
  byte) / SWAP A / SRL A / SRL A / AND 0x03 / ADD A,0x08` -- i.e.
  **bank = 8 + ((kindByte >> 2) & 3), landing on exactly banks 8, 9,
  10, or 11** -- precisely the 4 real graphics-bearing banks this
  project's own full sweep (task #154a) already identified as the
  ONLY banks holding creature/character/icon art. This is almost
  certainly the real per-entity ("species"/NPC-kind) graphics dispatch
  this project has been looking for since the monster/NPC candidate
  search began -- HOW a "kind byte" resolves to one of the 4 candidate
  banks is now understood in principle, even though the exact
  kind-byte -> region mapping (which would let candidates be assigned
  a real species) still needs a live trace of this specific routine
  while different real enemies/NPCs spawn -- correctly left OPEN, not
  guessed.
- Bank 9's OWN local variant (`$24228`, literal `LD A,0x09`) walks a
  6-byte-stride table living at file `0x24479` -- **a real, honest
  correction to `bank9_creature_columns`'s own note**: that address
  sits INSIDE the region this project catalogued as "704 tiles of
  creature-column art." Raw bytes there (`62 08 08 01 0a 00 30 04 00
  70 f9 46 71 47 c3 48 ...`) show a clearly repeating, small-period,
  non-pixel-shaped structure (real recurring byte pairs like `f9 46`/
  `c3 48`), NOT 2bpp tile noise -- structurally confirmed, via real
  code that actually walks it 6-bytes-at-a-time, to be a REAL RECORD
  TABLE, not pixel art, at least for the portion starting at
  `0x24479`. The bulk of `bank9_creature_columns` still visually
  reads as real creature art on direct render (unchanged conclusion),
  but this specific sub-range's own "art" characterization is
  retracted -- an honest, self-caught gap, not silently left standing.

**Net result**: did not (yet) resolve which candidate region belongs
to which of the 11 real species/3 real NPCs -- that still needs a live
trace of the bank-3/bank-4 dynamic dispatcher's own kind-byte table
while real entities spawn, a bigger undertaking left OPEN for a future
pass. But this pass DID find and fully document a real, previously-
unknown generic ROM-graphics-loading subsystem, tied it directly to an
ALREADY-documented script-opcode gate (`$C8E0`/`$CEE8`), confirmed
several already-known regions via independent code evidence, and
caught one real self-correction (`bank9_creature_columns`'s own
`0x24479` sub-range). New reusable tools: `find_graphic_refs.py`
(static lead generator) and `watch_graphic_refs.py` (live read-
watchpoint follow-up), both documented with the SAME honest "lead
generator, not proof" scoping every other heuristic tool in this
project already carries.

## Same-day follow-up: applying task #160's findings to existing open questions

Direct user question: "ok können wir damit vorher bestehende questions
lösen?" (can we solve previously-existing open questions with this).
Checked every entry in `OPEN_QUESTIONS`
(`rom-inspector/js/data/open-questions.js`) for a real connection to
the newly-disassembled graphics-loading mechanism. Two real hits:

**1. `$C8E0`/`$CEE8` dual gate now has a concrete real-world meaning.**
The big "opcode 0x04's real $38F6 control-code table" open question
already names `$C8E0`/`$CEE8` as something script opcodes `0xFC`/`0xFD`
and `$1ED7` selector 0x10's phases 1/3 wait on, WITHOUT knowing what
they represent. Task #160 answered that: `$C8E0` is the real queue
depth of the tile-streaming DMA system disassembled above -- those
opcodes are literally pausing script execution until pending ROM->VRAM
graphics transfers finish. This doesn't close the remaining open part
of that entry (which sub-call inside phase 2/4 performs the missing
`$3727` fetch), but replaces "an opaque gate" with "a gate on a fully
understood real subsystem" -- real, useful context for whoever
continues that trace.

**2. Task #81 (cross-bank CHAIN mystery): genuine new progress, still
not closed.** Checked directly whether `CHAIN`'s own real handler
(`$32FE`, `ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS`) uses the SAME
`$2100`-write convention the graphics loader does. It doesn't call
`$2DF5`/the tile queue at all -- but disassembling it found something
else real and substantial: a previously-undocumented, general-purpose
**bank call-stack** primitive, used at ~35 real sites across bank 0:
- `$29FB` (push+switch): takes a bank number in `A`, pushes it onto a
  WRAM array at `$C000+` (indexed via HRAM `$FF8A`, incremented here),
  then switches to it via the real `$2100` MBC2 convention.
- `$2A0A` (pop+switch): decrements the `$FF8A` index, reads the NEW
  top-of-stack bank, and switches to IT via `$2100` -- "return to the
  bank active before the last push."
- `$2A17` (peek): reads the current top-of-stack bank without
  modifying anything -- this is the SAME routine task #160's own tile-
  DMA consumer (`$2DD3`) calls right before restoring its own bank
  after a transfer completes, tying this bank-stack primitive directly
  to the already-disassembled graphics loader.

`CHAIN`'s own handler (and a sibling block at `$32CF`-`$32E2` sharing
the identical "commit new cursor to `$D8B6`/`$D8B7`, then `CALL
$2A0A`, then `CALL $3C4F`, then `CALL $3727` release" shape) DOES call
the POP+switch variant as a standard part of committing its new
cursor -- a real, previously totally unknown fact about CHAIN's actual
execution. This narrows task #81 from "no bank-switch mechanism found
at all" to "a real, general bank-stack mechanism exists and CHAIN
provably touches it" -- but does NOT yet prove it resolves the 7
specific real cross-bank CHAIN targets correctly (no matching `$29FB`
PUSH site was traced back to a script-entry point, and no live trace
of one of the actual 7 problem scripts hitting this code was run this
pass). Correctly left OPEN rather than declared solved -- the next
concrete step is a live `$2100`-write watchpoint across one of the 7
real scripts' own CHAIN execution, not more static reading.

Both findings folded into `OPEN_QUESTIONS`
(`rom-inspector/js/data/open-questions.js`) with dated updates, not as
new separate entries where an existing one already covered the topic.

## Task #162: rom-inspector website UX/accessibility audit

Direct user request (a detailed "elevate this product like a senior
cross-functional team" brief). Given the brief's own SaaS-shaped
checklist (auth, forms, workflows) doesn't map cleanly onto either of
this repo's two very different surfaces, first clarified scope with
the user via AskUserQuestion -- confirmed: `rom-inspector/` (the
documentation website), NOT the LÖVE2D game (whose own design mandate
-- fidelity to a real Game Boy ROM -- would conflict with generic UX
"improvements").

**Phase 1/2 (understand + audit)**: read every CSS/HTML/JS file, then
measured (not guessed) real issues:
- Computed WCAG contrast ratios for the entire color system against
  all 3 real backgrounds this site uses -- `--text-faint` (#5b6577)
  came back 2.81-3.27:1, failing the 4.5:1 minimum, used at 9-13px
  across ~12 real spots (card metadata, table headers, sidebar
  counts, decode-byte labels).
- `grep`'d the whole codebase for `tabindex`/`role`/`aria-` -- zero
  hits anywhere. Every custom interactive control (18 sidebar items,
  10 `.pill-tab` filters across 8 pages, 16 `.bank-cell`s, 256
  `.opcode-cell`s, `.hbar-row`s) was a plain `<div>` + click listener
  -- unreachable and inoperable by keyboard or screen reader.
- `#sidebar { display: none; }` below 860px with NO alternative --
  confirmed the site has literally no way to switch sections on a
  phone or narrow tablet.
- Traced the real keyboard Tab order live (Playwright) and found the
  ROM-load control itself was unreachable: its real `<input
  type=file>` was `display:none` (removes it from the tab order
  entirely) and its `<label>` (the visible "button") is not a native
  Tab stop -- meaning the control needed to see ~90% of this site's
  real content (every canvas) had no keyboard path to it at all.
- Canvas elements (tile/map/monster/NPC/graphics/world-map viewers)
  carry real, meaningful visual content with zero text alternative.

**Fixes shipped** (each independently Playwright-verified against the
real ROM, zero console errors, zero regressions across all 18
sections):
- `--text-faint` -> `#7f89a5` (4.44-5.15:1 against every real
  background, keeps the same "quieter than `--text-dim`" role).
- Sidebar nav rebuilt as real `<a href="#id">` elements (was `<div>` +
  click listener) -- natively keyboard-operable, `aria-current="page"`
  on the active one.
- New `enhanceKeyboardAccessibility()` (`app.js`) retrofits
  `tabindex`/`role="button"`/Enter-Space handling onto
  `.pill-tab`/`.bank-cell`/`.opcode-cell`/clickable `.hbar-row`s after
  every render, by forwarding to each element's own already-attached
  `click` listener -- zero changes needed to any of the 8 individual
  page modules' own logic.
- New mobile navigation drawer: a hamburger toggle in the top bar,
  sidebar slides in as a dismissible overlay (Escape / backdrop click
  / picking a section all close it, focus returns to the toggle on
  Escape) -- desktop layout completely unchanged.
- Skip-to-content link (first focusable element on the page).
  Route changes now scroll to top and move focus to `#main` (screen-
  reader "page changed" convention) -- deliberately NOT baked into the
  shared low-level `route()` (which also runs on non-navigation
  refreshes like a palette switch, where stealing focus/scroll would
  be a regression) -- a separate `navigate()` wrapper used only for
  real `hashchange` events.
- ROM-load control: the real `<input type=file>` switched from
  `display:none` to a proper `.visually-hidden` technique (stays in
  the tab order); a focus/blur listener mirrors its real focus state
  onto the visible label the input's own `focus-visible` ring can't
  reach directly (label precedes input in the DOM).
- `aria-label`/`role="img"` added to all 6 real canvas-based
  visualizations; `aria-label` on the palette select and a real
  `<label>` for the global search input (was placeholder-only).
  `role="status"` on the ROM-load status text (announces load/unload
  to screen readers).
- Self-caught, small: `scan.js`'s `.hbar-row`s used to get
  `cursor:pointer` + a click listener even for entries with no real
  matching opcode to jump to -- a real "looks clickable, does nothing"
  affordance mismatch, and would have made the new keyboard-enhancer
  focus rows that go nowhere. Fixed at the source (only rows with a
  real match get the interactive treatment).

**Deliberately NOT done** (documented, not silently skipped): no
visual/theme redesign (the existing dark GB-green system is already
cohesive and fits the subject matter -- "if already excellent, leave
alone"); no roving-tabindex grid navigation for the 256-cell opcode
grid (AA requires operability, which plain per-cell `tabindex="0"`
already satisfies -- a roving-tabindex APG grid pattern would be a
real UX polish item but isn't a compliance gap, flagged as a Medium/
future item instead of risking a rushed change to a 256-cell grid);
canvas pixel-click-to-inspect interactions (tile/map/graphics viewers)
stay mouse-primary -- a defensible scope for a spatial exploration
tool, same as e.g. a design canvas, now at least given a real
accessible name via `aria-label` so screen-reader users know what's
rendered even without pointer access to per-tile detail.

`luajit tests/run_tests.lua`: 487/487 pass (JS/CSS/HTML-only change,
Lua suite unaffected by design, re-run anyway).

## Task #151: real music playback ported into `love.audio`

Direct user instruction ("erst 151 dann 81"). Full detail in
`docs/reverse-engineering/audio.md`'s own "Playback -- PORTED into
love.audio" section -- not duplicated here. Summary: `src/audio/
MusicScore.lua` (event list -> playable segments, real loop-point
resolution via a new `startFileOffset` field added to every
`MusicDecoder` event), `src/audio/GBSquareSynth.lua` (real duty-cycle
square-wave PCM synthesis), `src/audio/MusicPlayer.lua` (streams to
`love.audio.newQueueableSource`, one real source per channel), and a
dev-only `src/app/states/MusicJukebox.lua` browser (F9 from
Field.lua, same "real content, no fabricated trigger" precedent as
RoomExplorer's F8) for all 30 real songs.

A real `love .` smoke test (`MYSTICQUEST_JUKEBOX_DEMO=1`) caught a
genuine bug before it shipped: song 1 channel 3 computes 65536 Hz for
one real note byte -- mathematically correct per the real GB formula,
but would alias into harsh noise. Fixed with a Nyquist guard in
`GBSquareSynth.render`; a real, new, concrete data point for the
already-open "channel 3's real hardware target unconfirmed" question.
End-to-end live verification (`MYSTICQUEST_WAIT_FOR_MAX=600`, a real
~10-second run) showed all 3 channels genuinely streaming and
independently progressing through their own real segment lists with
buffers staying correctly topped up -- not just "no crash." 8 new unit
tests, `luajit tests/run_tests.lua`: 501/501 pass.
