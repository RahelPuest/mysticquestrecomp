# Architecture

What is actually implemented, as of this writing. See
[gen1recomp-analysis.md](gen1recomp-analysis.md) for which of these patterns
were adopted from gen1recomp vs. designed fresh for Mystic Quest, and
[roadmap.md](roadmap.md) / [progress.md](progress.md) for what's not built
yet.

## Layering

```
main.lua / conf.lua            LÖVE2D entry point + window config
  |
  v
src/core/                      generic engine plumbing (no ROM/game knowledge)
  FixedStep      -- accumulator-based fixed update, decoupled from render FPS
  StateStack     -- push/pop/replace game states, opaque-aware draw
  Input          -- rebindable button abstraction over love.keyboard
  Sha1           -- pure-Lua SHA-1 (ROM identification, headlessly testable)
  |
  v
src/import/                    ROM-version-specific knowledge, centralized
  RomLocator     -- finds a candidate ROM file (env var or baseroms/)
  RomIdentity    -- parses the GB cartridge header + computes hashes
  rom_profiles   -- SHA-1 -> {verified offsets/regions} registry
  |
  v
src/rendering/                 ROM-agnostic Game Boy graphics decode + display
  GBTile         -- 2bpp tile decode (pure Lua, mirrors tools/graphics/gbtile.py)
  TileImage      -- decoded tiles -> love.graphics.Image sheet; checkerboard
                    backdrop helper for transparent0 debug views
  Renderer       -- 160x144 canvas, integer nearest-neighbor scale to window
  |
  v
src/app/states/                game states (StateStack entries)
  Boot           -- locate -> identify -> match profile -> hand off to
                    TitleScreen
  NoRom          -- shown when no supported ROM was found
  TitleScreen    -- the real title screen (default target after Boot,
                    since 2026-08-09) -- real logo/menu graphics, real
                    OAM cursor, up/down + A; confirming "Neues Spiel"
                    hands off to Field
  Field          -- the real playable starting-room slice -- movement,
                    contact combat, HUD, dialogue
  Menu           -- START from Field: the real in-game menu overlay
  DialogueBox    -- pushed by Field on enemy defeat; A/START advances lines
  TileViewer     -- debug only, reached via F2 from Field: page through
                    verified graphics regions
  MapBlockViewer -- debug only, reached via SELECT from TileViewer: page
                    through map-table records/reshape width
  |
  v
src/entities/                   pure-logic gameplay data (headlessly testable)
  Player, Enemy, Stats
  |
  v
src/debug/
  Overlay        -- F1 toggleable line-based debug HUD
```

Nothing under `src/core` or `src/rendering/GBTile.lua` touches ROM bytes or
`love.*` — see "Testing strategy" below for why that split exists.

## Startup flow (`Boot` state, `src/app/states/Boot.lua`)

1. `RomLocator.find()` — `MYSTICQUEST_ROM` env var, else first `.gb`/`.gbc`
   in `baseroms/` (gitignored, player-supplied). No ROM found → `NoRom` with
   a concrete reason. **No silent fallback to placeholder content.**
2. `RomIdentity.identify(data)` — parses the cartridge header, computes
   SHA-1/checksums. Malformed/undersized data → `NoRom` with the parse
   error.
3. `RomProfiles.match(identity)` — looks up the SHA-1 in the profile
   registry. Unrecognized ROM (wrong game, wrong revision, corrupt dump) →
   `NoRom` naming the SHA-1 and title found, never a best-effort import.
4. Match found → hand the raw ROM bytes + profile to `TitleScreen`, the
   real title screen (since 2026-08-09; previously Boot handed off
   straight to `Field`, skipping the title screen entirely — a real gap
   once the title screen itself became real, see progress.md). This is
   the app's actual boot target, not a debug view (per explicit project
   direction: launching the app should mean playing, not landing in a
   graphics browser). Confirming "Neues Spiel" on `TitleScreen` hands off
   to `Field`, the real playable starting-room state. The graphics/map
   debug viewers (`TileViewer`, `MapBlockViewer`) are still real, load-
   bearing developer tools — see "Debugging tools" below — just reached
   via F2 from `Field`, not the boot path itself.
   `MYSTICQUEST_DEBUG_STATE=field` skips straight to `Field`, bypassing
   the title screen, for this project's many existing Field-focused dev/
   screenshot workflows.

**This is a real, committed target architecture, not just a loose
inspiration** (confirmed 2026-08-11, direct user instruction: "das es
bei uns so funktioniert ist das ziel" — that gen1recomp's own
ROM-in/generated-cache-out/runtime-never-touches-the-ROM-again shape is
explicitly the goal for this project too, not merely a pattern worth
knowing about). The full pipeline (see gen1recomp-analysis.md SS1/SS3):

```
user-provided ROM
   -> RomExtractor (Lua) reads rom_profiles.lua's own offsets, decodes
      once
        --> data/generated/*.lua   (normalized game data: rooms, text,
                                     stats, ...)
        --> assets/generated/**/*.png  (decoded tile/sprite sheets)
   -> ROM bytes released from memory
   -> every subsequent boot (and every state within it) reads ONLY the
      generated files; nothing in src/app/states or src/rendering
      touches raw romData bytes again
```

`rom_profiles.lua` already plays the role gen1recomp's
symbol-addressed manifest does (WHERE real data lives in the ROM,
cited to a VERIFIED/HYPOTHESIS/UNKNOWN rom-map.md entry) — that part of
the adoption is real and already in place.

**Write half BUILT and tested (2026-08-16, task #34)**: the
`LuaWriter`/`RomExtractor` half of the pipeline is real and running —
`src/import/LuaWriter.lua` (pure Lua, serializes any plain decoded
table into deterministic, diff-stable, loadable Lua source; see its own
doc comment and `tests/import/lua_writer_test.lua`'s 9 round-trip
tests) and `src/import/RomExtractor.lua` (orchestrates a bounded, real
set of this project's own already-existing importers —
`EnemySpeciesTable`, `ItemTable`, `WeaponTable`, `NpcCatalog` — into one
data table plus a manifest recording the real ROM SHA-1; see
`tests/import/rom_extractor_test.lua`, which cross-checks every stage
against calling the underlying importer directly on the real ROM).
`scripts/extract_rom_cache.lua` is the thin, untested CLI glue (matching
`SaveFile.lua`'s own established "pure logic module + thin I/O shell"
split) that actually runs this against the real ROM and writes
`data/generated/{monsters,items,weapons,npcs,manifest}.lua` — verified
to run cleanly and reproduce deterministic output (byte-identical
except the manifest's own timestamp) on repeated runs.

**Read side started (2026-08-16)**: `src/import/GeneratedCache.lua`
(pure Lua) — `tryLoad(name)` wraps `require("data.generated." ..
name)` in `pcall` for graceful absence (matching `RomLocator.lua`'s own
established convention: content bundled inside the app's own source
tree goes through LÖVE's filesystem-aware `require`, not a bespoke
reader); `verifyManifest(romSha1)` refuses a cache whose recorded
SHA-1 doesn't match the currently-loaded ROM (never silently serves a
stale cache from a different ROM revision); `loadAll(romData)` reuses
`RomExtractor.STAGES` directly to load every stage all-or-nothing.
**Wired into exactly one real consumer so far**: `CatalogExplorer.lua`
(its 4 data sources are precisely `RomExtractor.STAGES`' 4 stages) —
tries the cache first, falls back to the unchanged live-decode path
when absent/stale. Live-verified via a real `love .` launch with a
freshly-generated cache present: confirmed the cache path (not the
fallback) actually renders correct real data.

**Still explicitly NOT done** (a deliberate, separate follow-up, not an
oversight): no `ImageWriter`/`assets/generated/**/*.png` step yet (no
importer this pipeline wires produces pixel data — `MapTileCatalog`/
`GraphicsCandidates` are real candidates for a later pass, see
`RomExtractor.lua`'s own doc comment); no `RoomFloorLayout` stage
(needs a per-room selector argument, not a single "decode everything"
entry point — a different shape than the stages wired so far); and
**every OTHER consumer still decodes `romData` live** — `Field`,
`VictorySequence`, `TileViewer`, `MapBlockViewer`, `Menu` all still
read raw ROM bytes on every run, exactly as before (most of what they
need — room floor layouts, sprite graphics, dialogue text — isn't even
in `RomExtractor.STAGES` yet). One real, working, tested slice of the
runtime switch exists now; migrating the rest is real, valuable,
much larger follow-up work, deliberately scoped out here — matching
this project's own "note the goal, don't build it all at once"
discipline.

## ROM-version-specific knowledge is centralized

Per the project rule (see root instructions / gen1recomp-analysis.md SS1),
no bank number or byte offset for a specific ROM revision may appear outside
`src/import/rom_profiles.lua`. Every offset recorded there must trace back
to a VERIFIED or PARTIALLY VERIFIED entry in
[reverse-engineering/rom-map.md](reverse-engineering/rom-map.md). Looked up
by SHA-1, so importing an unsupported revision fails loudly (`RomProfiles
.match` returns `nil, reason`) instead of silently misreading bytes under a
wrong layout assumption.

## Rendering

- `Renderer` owns a fixed 160x144 canvas (the real Game Boy resolution).
  States draw into it via `Renderer:renderTo(fn)`; `Renderer:present()`
  blits it to the actual window at the largest integer scale that fits,
  centered, nearest-neighbor filtered — crisp pixel art at any window size,
  never non-uniformly stretched.
- `GBTile.decodeTile`/`decodeTiles` implement the DMG 2bpp tile format
  (Pan Docs "VRAM Tile Data") exactly, with no game-specific assumptions;
  `tools/graphics/gbtile.py` is a byte-for-byte-matching Python
  implementation used for independent, out-of-engine verification of the
  same ROM bytes (see rom-map.md's method notes).
- `TileImage.buildSheet` lays decoded tiles into a grid `love.Image`, with
  an optional `transparent0` flag (palette index 0 -> alpha 0, for sprite-
  style art meant to composite over a background).
- **Known gotcha, fixed once (2026-08-08):** `Renderer:renderTo` clears its
  canvas to opaque black, and `TileImage.DEFAULT_PALETTE`'s index 3 is also
  pure black. Combined with `transparent0 = true`, index-3 ink pixels became
  literally indistinguishable from the cleared canvas — a correctly decoded
  region (proven correct independently via `gbtile.py` and a headless
  `love.image`-only reproduction) rendered as *empty* in the actual app, no
  error, nothing visibly wrong to trigger suspicion. Root cause: two
  unrelated modules (`Renderer`'s clear color, `TileImage`'s default
  palette) each individually reasonable, colliding only in combination.
  Fixed by `TileImage.buildCheckerboard` + `TileViewer` drawing it as a
  backdrop behind any `transparent0` sheet, matching standard image-editor
  treatment of transparency. Verified by screenshot before/after. **Lesson
  for future rendering code:** never assume a decode is wrong just because
  it "looks empty" on screen — this project's engineering rule 9 ("no
  silent fallbacks") cuts both ways: a *renderer* silently agreeing with a
  black background is just as dangerous as a parser silently fabricating
  data. Verify decode correctness independently of the LÖVE rendering path
  before concluding a region doesn't have real art.

## Timing

`FixedStep.HZ = 4194304 / 70224` (~59.7275 Hz) — the DMG's real PPU refresh
rate (VERIFIED against Pan Docs' hardware clock constants), not an assumed
60 Hz. Game simulation runs on this fixed step; rendering is decoupled
(`love.draw` runs at whatever rate LÖVE presents frames, `love.update`
drains as many fixed steps as have accumulated). This matters once real
gameplay timing (movement speed, animation frames, attack windows) needs to
match the original hardware rather than "look about right" at 60 Hs.

## Testing strategy

- `tests/run_tests.lua` under plain `luajit` (no LÖVE runtime needed) — see
  `tests/harness.lua`. This works with zero `love.*` stub because
  `src/core`, `src/import`, and `src/rendering/GBTile.lua` are deliberately
  pure Lua (no `love.*` calls) — contrast gen1recomp's `love_stub.lua`,
  which exists because its equivalent modules DO touch
  `love.filesystem`/`love.data` directly.
- ROM-dependent tests (`tests/import/rom_identity_test.lua`) use
  `tests/dev_rom_locator.lua` to find a real development ROM copy outside
  the repo (`MYSTICQUEST_ROM` env var, or `../roms/extracted_mq/...`) and
  skip gracefully — never fail — when none is present, per the "no
  copyrighted ROM required for the suite to pass" rule. **Bug found and
  fixed 2026-08-08:** the candidate list was originally built as
  `{ os.getenv("MYSTICQUEST_ROM"), "path1", "path2" }` — when the env var is
  unset that is a table with `nil` at index 1, and `ipairs` stops at the
  first `nil` slot, so *every* candidate silently went unchecked and the
  ROM-dependent tests always skipped even with a ROM present on disk. Fixed
  by appending candidates with explicit `#CANDIDATES + 1` indices instead of
  a table constructor. All 3 previously-skipped tests now run and pass.
- No LÖVE-level integration test harness yet (nothing like gen1recomp's
  `POKEPORT_AUTOPILOT` screenshot driver). `main.lua` has a
  `MYSTICQUEST_SCREENSHOT` env-var hook (captures a screenshot a few frames
  after boot, then quits) used manually so far for visual verification —
  worth formalizing into an automated visual-regression test once there's
  a stable screen worth protecting.

## Debugging tools

Per the project's "debugging tools are a first-class feature" principle:

- **F1** (`src/debug/Overlay.lua`) — toggleable line-based HUD; any state
  can call `overlay:addLine(label, value)` from its own `draw()`.
- **F2** (from `Field`, see `Field:keypressed`) — pushes `TileViewer`, the
  graphics-region browser (LEFT/RIGHT switch region, UP/DOWN scroll); F2
  again pops back to `Field`.
- **SELECT** (from `TileViewer`) — pushes `MapBlockViewer`, the map-table
  record browser (LEFT/RIGHT page records, UP/DOWN adjust live reshape
  width); SELECT again pops back.
- **F8/F9/F10/F11** (from `Field`) — `RoomExplorer` (the whole decoded
  room catalog), `MusicJukebox` (all 30 real songs via `love.audio`),
  `TransitionExplorer` (2026-08-16, the real cut-transition landing
  table — 82 genuinely distinct real transitions, target roomSelector +
  landing tile, only 2 of which have a known real in-game trigger),
  `ActorExplorer` (2026-08-16, the real RNG-gated actor-definition
  table — 218 fully-decoded records, only 2 with a confirmed live
  spawn behind them). Same "real content, no fabricated trigger"
  precedent throughout — see each state's own doc comment.
- `MYSTICQUEST_SCREENSHOT`/`MYSTICQUEST_SCRIPT` env vars (`main.lua`) —
  scripted, OS-automation-free screenshot capture for manual/CI visual
  verification (see "Testing strategy" above).

## What's deliberately not built yet

**Refreshed 2026-08-11** — this section had drifted badly stale (it
still called several finished systems "not built yet"). See
[roadmap.md](roadmap.md) for the full, priority-ordered milestone table
this section now just points to instead of duplicating.

Genuinely still open, highest to lowest priority: general (non-hand-
captured) map/room extraction at scale (milestone 3 — still the single
biggest gap); real world content beyond today's 4 rooms/1 enemy/3 NPCs;
the other 254 of 256 real script-interpreter opcodes (the mechanism
itself IS found and decoded, see events.md); a bestiary (one enemy
type exists); a magic/spell system (`MP` is real, casting isn't);
a level/XP system (`experience`/`level` are real fields, read-only);
general dialogue-compression coverage; usable/equippable items; the
generated-data cache writer (a confirmed real target, deliberately not
started — see this file's own "Startup flow" section); audio (format
still unknown, explicitly lowest ordinary priority); modding
architecture (deferred by design until core gameplay is stable);
packaging/release (not yet worth discussing).

Finished since this section was last accurate: map transitions/warps
(a real, general, data-driven room-graph engine, 4 connected rooms);
the event/script interpreter's real dispatch mechanism (found and
decoded, if not yet fully wired); a real inventory/menu data model with
real decoded item/weapon names; the save system (full round-trip,
real MBC2 nibble format); the real combat damage formula, bit-exact
PRNG, and contact-knockback mechanics.

See [roadmap.md](roadmap.md) (priority-ordered milestone table) and
[progress.md](progress.md) (the living, dated log both summarize).
