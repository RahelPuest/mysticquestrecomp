# Mystic Quest ROM Inspector

An interactive, in-browser reference for the real, reverse-engineered
structure of the *Mystic Quest* (Game Boy, EU release of *Final Fantasy
Adventure* / *Seiken Densetsu 1*) ROM — memory map, script interpreter,
opcode table, room system, and text encoding, with clickable
visualizations instead of plain prose.

Styled after [DeniseBischof/HLV](https://github.com/DeniseBischof/HLV)
("Hardware Inspector") — same idea (plain HTML/CSS/JS, dark theme,
sidebar navigation, live value decoders, no build step, no
dependencies), **different subject matter**: this project documents the
*Mystic Quest* ROM specifically, using this repository's own reverse-
engineering findings.

## Running it

No build step, no server-side code, no npm install required to view it:

```
open index.html
```

...or serve it with any static file server if your browser blocks
`file://` script loading:

```
python3 -m http.server 8000
# then open http://localhost:8000/
```

## What's real vs. curated

Every page ends with a note on this. Concretely:

- `js/data/*.js` (except `wram-map.js`, `open-questions.js`, and
  `opcode-descriptions.js`) are **auto-generated** by
  `tools/export_data.lua`, which requires this project's own already-
  verified Lua modules (`ScriptOpcodeTable`, `EntityStructLayout`,
  `rom_profiles`, `TextDecoder`, `ScriptRuntime`) and runs a real, live
  whole-corpus script scan against the ROM. Nothing in those files is
  hand-typed ROM content — including `room-maps.js`, which holds real
  tile IDs and ROM file offsets, but never the tile PIXEL data itself
  (see "Tile/Map viewers" below).
- `js/data/wram-map.js`, `js/data/open-questions.js`, and
  `js/data/opcode-descriptions.js` are **hand-curated summaries** of
  `docs/reverse-engineering/*.md` and this project's own
  `StandardScriptHandlers.lua`/`ScriptRuntime.lua` doc comments —
  clearly labeled as such in their own file headers, not derived data.

## Tile/Map viewers (need your own ROM file)

The **Tile-Viewer** and **Map-Viewer** pages decode real Game Boy 2bpp
tile graphics and compose real room tilemaps — but this repository
never embeds ROM bytes. Click **"ROM laden…"** in the top bar and pick
your own, legally-owned `.gb` file: it's read locally via `FileReader`
and never leaves the browser (no upload, no network request). Without
a loaded ROM, both pages still show the real grid/tileset structure,
just as empty outlines instead of pixels.

To refresh the generated files after future decoding work (from the
repo root, one level up):

```
MYSTICQUEST_ROM=/path/to/rom.gb luajit rom-inspector/tools/export_data.lua
```

## Structure

```
index.html              Shell (topbar + sidebar + #main mount point)
css/style.css            Dark theme, design tokens, component styles
js/app.js                 Hash router, sidebar rendering, cross-section search
js/data/*.js               Real ROM data (see above)
js/viz/*.js                One module per section (see "Sections" below --
                            each render_<id>() matches app.js's own SECTIONS list)
tools/export_data.lua      Regenerates js/data/*.js from the real ROM + this
                            project's own Lua modules
```

## Sections

- **Übersicht** — top-line stats (opcode coverage, whole-corpus scan result).
- **Speicherkarte** — clickable ROM bank grid + searchable WRAM cell reference.
- **Entity-Struktur** — slot-index slider over the real 20×16-byte entity struct.
- **ROM-Tabellen** — every named, verified/partially-verified ROM table.
- **Skript-Opcodes** — all 256 opcodes as a searchable/filterable grid, colored
  by real decode status (not hand-classified — built by actually constructing
  a `ScriptRuntime` and checking which handlers are registered), each with a
  human-readable description of what its real handler family actually does.
- **Whole-Corpus-Scan** — live shadow-run result across all 1357 real scripts.
- **Raum-System** — the known room graph (scroll vs. cut transitions) as an SVG.
- **Map-Viewer** — composes a real room's full tilemap into one image, decoded
  live from a ROM file you supply locally (never embedded, never uploaded).
- **Weltkarte** — statistical room-adjacency evidence across the 384 decodable
  bank-5/6 room-catalog records, rendered as a 16×16/8×8 world grid.
- **Raum-Übergänge** (2026-08-16) — the real, general cut-transition landing
  table (`CutTransitionTable.lua`): 186 raw ROM records collapsing to 82
  genuinely distinct real transitions, each with its target `roomSelector`
  AND real landing tile. Filterable by target room family; only 2 entries are
  currently live-verified AND wired into actual gameplay — the rest,
  including 36 targeting the long-mysterious `unknownRoomA` family, are real
  ROM data whose in-game trigger is honestly still unknown.
- **Tile-Viewer** — browse individual 8×8 tiles from any known tileset or a
  free-form ROM offset range, same local-only decoding.
- **Text-Encoding** — a live decoder for the real character/digraph/umlaut
  tables, with real ROM byte samples to try.
- **Musik & Sound** — the real 30-song table, decoded note/duration/octave
  event streams per channel, playable in-browser.
- **Monster** — the real 11-species stat table (`EnemySpeciesTable.lua`).
- **Items & Waffen** — the real item/spell and weapon/armor tables, grouped
  by their real `categoryByte`.
- **NPCs** — every real NPC this project has found and placed (no static ROM
  placement table exists — each found via live OAM tracing).
- **Story & Charaktere** — a full-ROM text census: monster defeat messages
  and every named story character found in dialogue text.
- **Grafiken** — candidate creature/map-tile graphics regions found via a
  systematic ROM sweep, rendered as tile sheets.
- **Offene Fragen** — every currently-unresolved real question this
  reverse-engineering effort has, with the concrete ROM addresses involved.
