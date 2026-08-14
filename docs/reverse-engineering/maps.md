# Maps — status summary

Required by the project's master brief as a maintained, topic-focused
doc. This is a current-status summary; the full evidence trail (methods,
raw data, dead ends, corrections) lives in
[rom-map.md "Maps"](rom-map.md) and is NOT duplicated here — update
both when new findings land, this file with the summary, rom-map.md
with the full writeup.

## The real room-connectivity table — VERIFIED (2026-08-10), a DIFFERENT table from bank-5 below

**Bank 8, file offset `0x20000`, 16 records × 11 bytes**, indexed by a
`roomSelector` byte (0-15 — the table's real length, confirmed by a
semantic bound: one record field must be a valid MBC bank number, and
this ROM has exactly 16 banks; record 16 onward immediately produces
impossible bank numbers). This is NOT the bank-5 table described below
— different bank, different record size, different real consumer,
found completely independently.

Feeds a real "commit new room" routine (`$01AF3`, bank 0) that sets the
already-known room tile-source pointer (`$D392`/`$D393`) plus a second,
previously-unnamed pointer (`$D390`/`$D391`). **Confirmed live, twice,
via a bank-accurate `CallTracer`, address-for-address identical**, for
two completely unrelated real transitions: the post-victory staircase
(`thirdRoom`→`fourthRoom`) and an early pre-combat courtyard
transition. The table resolves to exactly **5 distinct real rooms**
across its 16 selectors — multiple selectors per room are real,
confirmed per-instance "states" (each selector's own record also
stages a real 4-byte control block into WRAM `$C3F8`-`$C3FB`, and
`$C3F8` is the already-known real door/gate-check flag `$235B` reads —
direct user hypothesis, checked and confirmed).

Cross-referenced against this project's own already-implemented rooms
(`rom_profiles.lua`'s `willyRoom`/`secondRoom`/`thirdRoom` share one
selector-family; `startRoom`/`fourthRoom` share another — the latter
pair's real tile pointer is IDENTICAL, though their own independently-
captured tile sets only partially overlap, an honest, unreconciled
note). Two selector-families (6 selectors total) point to rooms never
reached live — real pointers recorded, no tile data. A real, bounded
attempt to force-reach one of the unreached rooms (direct register/
stack manipulation to invoke the real ROM routine with an unused
selector, not fabricating anything) successfully set the real pointer
but did not produce a visible, correct redraw — an honest negative, not
worked around.

Implemented as `src/import/RoomSelectorTable.lua` (generic decoder) +
`rom_profiles.lua`'s `roomSelectorTable` field (real reference data) —
see [events.md](events.md) for how this connects to the wider script-
system picture.

## Bank-5 pointer table — VERIFIED to exist; encoding VERIFIED; in-game usage still UNKNOWN

- **VERIFIED**: a 256-record pointer table at file offset `0x14004`
  (bank 5), each record a `(header, data)` pointer pair.
- **VERIFIED**: the table's own 4-byte per-map header (`0x14000-0x14003`
  = `[0, 3, 16, 16]`) and the RLE decompression scheme it describes —
  every one of the 255 data blobs decodes to an exact, uniform 80 tiles
  (20x4) using the header-derived `rleLength=3`, confirmed both
  structurally (0/255 clean matches for every other tested length) and
  visually (coherent recognizable tile art, not noise). See
  `src/import/MapTable.lua`.
- **UNKNOWN, and now more confidently NOT the room-connectivity
  mechanism**: this project spent 10+ passes searching for this table's
  real in-game consumer and never found one; the real, live-traced
  room-connectivity table (above) turned out to be a completely
  different bank-8 structure. The bank-5 table's real purpose remains
  open — it is NOT the room table, and (per events.md) also confirmed
  NOT the FFA-Disassembly-documented script-pointer table.
- **HYPOTHESIS, untested**: the even-indexed "header" entries' extended
  (6/9/15-byte) variants may encode warp/exit triplets
  `[targetRecordIndex, unknown, bank]`.

## The real room chain — VERIFIED, live-traced, NOT table-driven at the Lua-engine level

Five real, live-captured, connected rooms (`startRoom`/courtyard →
`willyRoom` → `secondRoom` → `thirdRoom` → `fourthRoom`), each with a
real tile grid + real ROM tile offsets, connected by a real, general,
data-driven room-graph engine (`RoomChain.lua`/`VictorySequence.lua`):
each room's `exits` entry names a `zone`, a `transition` (`scroll`
on either axis, or an instant `cut`), a `targetRoom`, and landing
coordinates — one shape covering every real transition mechanism found
live this whole investigation (see rom-map.md for the full room-by-room
trace). The underlying ROM-side mechanism driving these same
transitions is now understood (see the room-connectivity table above),
though the Lua engine itself still reads empirical/captured data, not
the live ROM table, at runtime.

## Collision — HYPOTHESIS, not a decoded ROM table

`rom_profiles.lua`'s `floorTileIds` fields (one per room) are this
project's own classification of the real captured tile IDs into floor
vs. wall/gate, used for real per-tile player movement collision
(`src/entities/Player.lua`'s `canMoveTo`). No decoded ROM collision-flag
table has been found — this is a reasonable approximation from visually
inspecting each real layout (with one real bug caught and fixed this
session: `thirdRoom`'s own staircase tiles weren't marked walkable,
making its own exit zone physically unreachable), not a verified ROM
fact.

## Map objects, NPCs — the secondRoom NPCs are procedurally placed, not table-driven (2026-08-10)

Real NPC sprites exist in `secondRoom` (two unidentified characters) and
`willyScene` (the player/Willy pair) — still captured as static scene
data (`rom_profiles.lua`'s `scene`/`willyScene` fields) for rendering
purposes, but their real ROM placement mechanism is no longer fully
unknown. Live-traced (write-watchpoint + `CallTracer`, see rom-map.md
"P5: the secondRoom NPCs are NOT placed via a fixed table"): a real,
general spawn primitive (`$42BD`, bank 3) is shared by two different
loops — one walks a literal fixed-position table (real `0x8080`
end-sentinel, spawns *other*, non-tracked entities this way), the
other **procedurally randomizes** each of the two known NPCs' spawn
offset via the same noise-table PRNG combat already uses, with a real
minimum-distance reroll check against a reference point. So: **not a
static per-room object-placement table** for these two NPCs
specifically — a real, code-driven randomized-placement system
instead. The exact offset-to-final-position transformation is not yet
decoded (an honest remaining gap), and whether this randomized path is
general (used for other rooms' NPCs too) or specific to secondRoom is
untested. `characterA`/`characterB`'s captured `screenX`/`screenY`
values are one real sample, not a stable ROM-authored constant — see
`rom_profiles.lua`'s own corrected doc comment. See
`docs/roadmap.md` Milestone 5.
