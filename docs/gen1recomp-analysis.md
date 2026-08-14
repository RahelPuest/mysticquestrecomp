# Gen1Recomp Architecture Analysis

Source studied: a clean clone of
[bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp), kept
untouched in `../gen1recomp-reference/` (sibling to this project, `.git`
stripped, read-only reference — not part of this repo). Findings below are
drawn from its `README.md`, `docs/architecture.md`, `src/import/*.lua`,
`src/world/Map.lua`, `src/script/Commands.lua`, `src/core/FixedStep.lua`,
and its top-level directory layout. gen1recomp targets US Pokémon Red/Blue/
Yellow specifically — Mystic Quest is a different genre (action-RPG, not
menu-driven turn-based battles) on different hardware assumptions (DMG-only,
MBC2, no SGB/GBC) with a completely different disassembly ecosystem (no
`pret`-grade project exists for it, see [references.md](references.md)). The
value here is architectural pattern-matching, not code reuse.

## 1. The core separation: ROM stays out of the shipped product

```
packaged first boot
user-provided ROM
        |
        v
RomImporter + RomExtractor (Lua)
        |
        +--> private data/generated/*.lua
        +--> private assets/generated/**/*.png
        +--> private assets/generated/audio/programs.bin
        |
        v
LÖVE2D engine
```

- `RomImporter` (3700+ lines — most of it UI/platform plumbing: file
  pickers per OS, Android/iOS/Switch inbox scanning, launcher chrome) does
  ROM acquisition, SHA-1 verification against a hardcoded table of known
  hashes (`GameVersion.info(version).sha1`), and cache lifecycle
  (`CACHE_FORMAT` version tag + per-ROM-hash marker file so a format bump or
  a swapped ROM both force re-extraction).
- `RomExtractor` does the actual decode: reads a `manifest` (JSON,
  `tools/rom_manifest*.json`) that maps *symbol names* to `{bank, address}`
  pairs, pulls bytes out of a `Rom` byte-reader by symbol, and writes
  normalized Lua tables (`data/generated/*.lua`) and PNGs
  (`assets/generated/**/*.png`) through `LuaWriter`/`ImageWriter`.
- The ROM is held in memory only for the duration of import, then released.
  It is never copied into the cache. Every subsequent boot reads only the
  generated files — `RomImporter.isReady(version)` checks a marker + a list
  of `REQUIRED_FILES` rather than re-touching the ROM at all.
- **This exact separation is what we adopt.** It is the whole point of a
  "recomp": copyrighted content in, normalized non-executable data out,
  engine code never contains or requires the original bytes to be present
  at build time.

**Adopt as-is for MysticQuestRecomp:** import → generated cache → runtime
never re-reads the ROM. Verify-by-hash before doing anything with a ROM.
Release ROM bytes from memory after import.

**Must be redesigned:** gen1recomp's manifest is *symbol-name-addressed*
(`Music_GymLeaderBattle`, `CryData`, ...) because `pret/pokered`'s
disassembly hands it complete, named, bank:address symbol tables for the
exact canonical ROM. We have no equivalent disassembly for Mystic Quest.
Our importer's profile format (`src/import/rom_profiles.lua`) has to carry
whatever offsets *our own* reverse engineering discovers, cited to how they
were found (see `docs/reverse-engineering/rom-map.md`'s VERIFIED/HYPOTHESIS/
UNKNOWN convention), not to a pre-existing symbol file we can cite as
ground truth.

## 2. Runtime layering

| gen1recomp area | Files | Role | Applicability to Mystic Quest |
| --- | --- | --- | --- |
| import | `src/import/RomImporter.lua`, `RomExtractor.lua` | first-boot UI, verify, extract, cache | Same shape, our own profile format |
| core | `Game.lua`, `Data.lua`, `FixedStep.lua`, `Input.lua`, `StateStack.lua`, `SaveData.lua` | service owner, generated-data loader, 60Hz fixed step, input abstraction, state stack, save I/O | **Directly reusable pattern.** Fixed-step + StateStack + Input abstraction are genre-agnostic engine plumbing, not Pokémon-specific. |
| render | `Renderer.lua`, `TileRenderer.lua`, `SpriteRenderer.lua`, `Font.lua`, `TextBox.lua`, `Camera.lua`, `Transition.lua` | 160x144 canvas + integer scaling, tile batching, sprite sheets, glyph rendering, dialogue box, camera/warp fades | Reusable pattern (GB output resolution, integer-scale nearest filtering, tile batch rendering) — Mystic Quest's actual tile/sprite geometry, palette count (DMG 4-shade, not GBC), and text box behavior are unknowns to establish independently. |
| world | `Map.lua`, `MapLoader.lua`, `Player.lua`, `NPC.lua`, `Collision.lua`, `Warp.lua`, `Encounter.lua`, `OverworldController.lua` | grid-based overworld: cell (16x16) walk grid, block (32x32) layout unit, tile (8x8) graphics unit, "bottom-left-tile decides cell behavior" collision rule, wild-encounter roll | The **coordinate model concept** (tile/cell/block hierarchy, one canonical rule for which tile governs a cell's behavior) is worth carrying over as a pattern, but Mystic Quest is an action-RPG (real-time attack swings, enemy AI, no random encounter table triggering a menu battle) — `Encounter.lua`'s whole reason to exist doesn't transfer. Our own grid unit sizes must come from decoding actual MQ map data, not assumed to match Pokémon's. |
| script | `ScriptRunner.lua`, `Commands.lua`, `Flags.lua` | coroutine-driven command list interpreter (`show_text`, `warp`, `wait`, flag branches...), each hand-ported script cites its pokered source file | **Concept directly reusable**: a coroutine-based command interpreter with blocking commands is a clean, engine-agnostic way to express game scripting, and doesn't assume anything about Pokémon specifically. What *cannot* transfer is the command vocabulary (`start_battle`, `play_cry`, "TEXT_* constants from object events") — that vocabulary must be derived from whatever event/script representation Mystic Quest's ROM actually uses, once found. |
| pokemon/battle | `src/pokemon/*`, `src/battle/*` | Gen 1 stat/growth formulas, turn-based battle flow, type chart, trainer AI | **Not applicable.** Mystic Quest's combat is real-time action combat (weapon swings, ranges, invulnerability frames, knockback) — none of this subsystem's *shape* applies. What transfers is only the discipline: formulas backed by verified data, ruleset-style toggles for "faithful vs modernized" behavior if MQ turns out to have its own quirks worth preserving/optionally-fixing. |
| ui | `src/ui/*` | menus, party/bag lists | Reusable as a UI-widget pattern (menu cursor, list scrolling), not as menu *content* — MQ's actual menu structure (inventory/equipment/magic per the master brief) is unknown until decoded. |

## 3. Startup flow (traced from `RomImporter.new` / README)

1. App launches, opens a launcher/importer screen if no cache is ready.
2. Player supplies a ROM (drag-drop, native file picker per OS, or a
   `baseroms`/`imports` inbox folder scan on platforms without a picker).
3. SHA-1 checked against a table of known-good hashes; only exact matches
   proceed (`GameVersion.forSha1`). No "best effort" import of unknown
   ROMs.
4. `RomExtractor` runs a sequence of *named stages* (`STAGE_COUNT = 17`;
   `beginStage("Game constants")`, etc.) each writing one or more
   `data/generated/*.lua` / `assets/generated/**` files, driven by a
   `progress(stage, total, name, current, total)` callback the UI uses for
   a progress bar.
5. A completion marker (`rom-cache.complete`, containing a cache-format tag
   + the ROM's own SHA-1) is written last. Its presence — plus every file in
   a `REQUIRED_FILES` list actually existing — is what `isReady()` checks
   on the next boot; either check failing means "re-import."
6. Game boots reading only generated files; `Game.lua`/`Data.lua` never
   touch ROM bytes again.

This stage-list + progress-callback + completion-marker shape is worth
copying outright for our importer: it's how you make "first run does real
work, every run after is instant" observable and testable rather than an
implicit side effect.

## 4. Coordinates and the "one governing tile" collision rule

gen1recomp's `Map.lua` documents a three-level coordinate hierarchy: 8x8 px
*tile* (raw graphics unit) → 16x16 px *cell* (2x2 tiles, the walk grid, unit
of all object/warp coordinates) → 32x32 px *block* (2x2 cells / 4x4 tiles,
the unit of the original `.blk` map layout format). A cell's walkability/
grass/door/warp behavior is decided by a single rule — "the bottom-left 8x8
tile of the cell" — matching Pokémon's actual "check the tile at the
sprite's feet" engine behavior.

This is a *pattern*, not a fact about Mystic Quest: Game Boy action-RPGs
commonly use a similar multi-level tile/metatile hierarchy for exactly the
same memory-density reasons Pokémon does (an 8-bit console can't afford a
byte per 8x8 tile for a whole overworld), but MQ's actual grid unit sizes,
metatile arrangement, and which tile (if any) governs collision are
UNKNOWN until we decode real MQ map data (`docs/reverse-engineering/
rom-map.md`). The takeaway for our architecture is: **have exactly one
documented, testable rule for "which byte decides this cell's behavior,"**
whatever that rule turns out to be for this game.

## 5. Fixed-step timing

`FixedStep.lua`: accumulator-based fixed update at `1/60` s per step,
independent of render framerate, with:
- a clamp (`MAX_ACCUM`) against a "spiral of death" after a stall,
- a `discardCatchup`/`suppressCatchup` mechanism so a single-frame hitch
  (e.g. a map-seam load) is absorbed as one step instead of releasing a
  burst of queued steps that would visibly "slide" the player across
  several tiles at once.

Directly adoptable: this is genre-agnostic game-loop hygiene, and the
master brief explicitly calls for simulation timing independent of host
FPS. The GB's real hardware step rate (~59.7275 Hz, from its 4.194304 MHz
clock — see `docs/gameboy-hardware-limitations.md` in the reference repo if
present) should be measured/confirmed for accuracy rather than assumed to
be exactly 60 Hz, since gen1recomp's own comment says "~60Hz."

## 6. Testing strategy

- `tests/run_tests.lua` under `luajit`: a headless suite exercising real
  generated data against a stubbed `love` API (`tests/love_stub.lua`) —
  collision, warps, text, stats, damage, growth, encounters, a full
  scripted battle, save round-trip.
- `tests/parity_*.lua`: one file per specific, named behavior bug/feature
  (hundreds of them), each testing one observed discrepancy against the
  original game. This is a strong pattern: a regression test *per specific
  behavioral finding*, named after the finding, rather than one giant
  "battle system" test.
- `POKEPORT_AUTOPILOT=1 love .`: a scripted end-to-end driver that plays a
  fixed opening sequence and captures screenshots — a golden-image-style
  regression check on real gameplay flow.
- ROM-dependent tests must be skippable when no dev ROM is present (our
  master brief states this explicitly too).

**Adopt:** headless test runner against generated data + a `love` stub so
tests don't need a display; one test file per specific reverse-engineered
behavior, named for that behavior; an end-to-end autopilot/screenshot mode
for whole-flow regression once there's a flow worth protecting.

## 7. Modding architecture (deferred concept, not deferred design awareness)

gen1recomp's mod system (content registries, event hooks, per-mod save/
options namespacing — see `modFieldOwner`/`mod:` field convention in
`Commands.lua`) is far more mature than anything needed for our early
milestones. The master brief is explicit: don't build this now, but don't
architect ourselves out of it either. The concrete, cheap thing to borrow
early is the *namespacing convention* — e.g. don't let hand-written,
map-specific logic and imported ROM-derived data collide in the same
table/key space — so a future mod layer has somewhere to hook in without a
rewrite.

## 8. What we are explicitly NOT importing

- Pokémon-specific data shapes: species/move/type tables, Gen 1 damage
  formulas, growth curves, trainer AI, battle menu flow.
- The manifest's *symbol-name* addressing convention as a hard requirement
  — we adopt the *idea* of centralizing version-specific offsets away from
  runtime code (our own `src/import/rom_profiles.lua`), not the assumption
  that a `pret`-quality named symbol table exists for us to consume.
- Any UI chrome, launcher visuals, or platform-porting code (Switch/Xbox/
  iOS/Android build plumbing) — out of scope until a native desktop build
  is solid.
- gen1recomp's own code, beyond what's needed to cite specific patterns in
  this document. We are not vendoring or copy-pasting its Lua modules.

## 9. Re-check (2026-08-09): general mechanisms audit against this section's own recommendations

Direct user instruction after the post-victory scene shipped without its
two characters: *"schau dir den code nochmal an. suche nach allgemeinen
Mechanismen für Dinge wie Raumwechsel, Sprite Load, Gegner-Verhalten,
Dialog. schaue dir auch den romcode an sowie wie es in pokemon1recomp
gelöst ist."* Re-read this file's own §2 table against what actually
exists in `src/` today, plus fresh ROM-code tracing (see rom-map.md's
"Real room-tile decompression pipeline" entry) for a real MQ-side data
point to compare against gen1recomp's `Map.lua`/`Warp.lua`/`NPC.lua`.

**Sprite loading — CONFIRMED general, no work needed.**
`CreatureSprite.lua` already has exactly the shape gen1recomp's
`SpriteRenderer.lua` plays: `.fromOffsets` (explicit, individually-found
ROM tile offsets — used for the enemy, the field player, and now the
post-victory scene's player+Willy), `.static` (a fixed block of
sequential tiles), and a shared default-palette mechanism
(`setDefaultPalette`/`getDefaultPalette`) so callers don't each carry
their own fallback. Adding the Willy-scene sprites (this pass) needed
zero changes to this module — a real, positive signal that it was
already general enough, not a coincidence.

**Room background rendering — was duplicated, now generalized this
pass.** `StartRoomBackground.lua` (the courtyard) and the post-victory
scene's room background had independently converged on the identical
real shape ("a captured tile-ID grid, each ID resolved through an
explicit per-tile ROM offset dict") — the same lesson gen1recomp's
`Map.lua` already encodes as one module. Extracted into
`src/rendering/TileGridBackground.lua`; both call sites (`Field.lua`,
`BattleIntro.lua`, `VictorySequence.lua`) now pass a plain `{cols, rows,
grid, tileOffsets}` data table rather than each owning a bespoke
wrapper module. `RoomBackground.lua` (the still-not-fully-understood
bank-5 RLE table renderer) is deliberately NOT merged into this — it
uses a flat `base + id*16` stride, a structurally different assumption
this pass's own room-tileset mistake (see rom-map.md) showed does NOT
generalize across every real room.

**Dialogue — already close to gen1recomp's `ScriptRunner`/`Commands`
shape, real gap is content not architecture.** `EventSystem.lua`
(trigger → actions, data-driven, `state.stack`-agnostic dispatch) plus
`DialogueBox.lua`/`TextBox.lua` (rendering) is architecturally the same
idea as gen1recomp's coroutine command interpreter, just without
coroutines (not needed yet — no action type has required suspending
mid-execution across frames the way gen1recomp's `wait`/`show_text`
commands do; `VictorySequence.lua`'s own page-advance loop is currently
a bespoke state machine playing that same "blocking command" role for
one specific event only). **Real gap**: `Field.lua`'s `dispatchEvent`
today only implements two action types (`"dialogue"`, `"victorySequence"`)
against the master brief's full named vocabulary ("movement, flags,
conditional branches, item grants, map changes, NPC visibility, boss
triggers, cutscenes, transitions") — every other type still `error()`s
loudly (correct behavior, not a bug) rather than being implemented, since
no second real scripted sequence has been decoded yet to design against.

**Room transitions/warps — NOT general, confirmed and now precisely
scoped.** This pass's own room-swap in `VictorySequence.lua` (`if
page.box == "top" then draw the room`) is a one-off special case for
exactly one scripted transition, not a reusable warp system — same
honest gap this file's §2 table already flagged for `Warp.lua` before
any MQ-side data existed to design against. **What changed this pass**:
real ROM-side data now exists to design against, for the first time.
rom-map.md's "Real room-tile decompression pipeline" entry traced a
real, general-looking mechanism: a per-room-relocatable source pointer
(WRAM `$D392`/`$D393`) plus a 256-entry remap table staged per room
(WRAM `$D070-$D16F`), drawn through the same tile-blit-queue primitive
used everywhere else in this ROM. **Not yet confirmed** whether this is
literally "the" general warp/room-load routine every door/exit in the
game uses (only exercised once, for this one scripted cutscene
transition) or another special case — same open status rom-map.md
already gives it. Concrete next step, informed by gen1recomp's
`Warp.lua` (a data table of `{fromMap, toMap, x, y}` triples consumed by
one generic warp-executor): once a second, ordinary (non-cutscene) room
transition is reachable and traceable, check whether ITS `$D392`/`$D393`
and `$D070` values are populated by the SAME calling pattern as this
session's traced one — if so, that caller is the real generic "load room
N" entry point, and a `Warp.lua`-shaped table (whatever real per-door
data the bank-5 header records turn out to encode — see rom-map.md's
still-open `[targetRecordIndex, unknown, bank]` triplet hypothesis) could
finally be tested against it. Tracked as task #2's concrete next action,
not attempted this pass (needs a second live transition to compare
against, which this session's own reachable content doesn't yet have).

**Enemy behavior — confirmed NOT general, correctly so for now.**
`Enemy.lua` is one hand-captured movement cycle for one specific
creature (see its own doc comment's honesty notes on `MOVEMENT_CYCLE`).
No `EnemyType`/behavior-script abstraction exists, matching gen1recomp's
own Gen-1-specific battle/AI code being explicitly marked "not
applicable" in §2 above — until a second enemy is decoded, generalizing
this would mean guessing the shape of a pattern from a sample size of
one, the same mistake the room-tileset bug this pass just corrected
was made from. Left as `Enemy.lua`'s single concrete instance, not
prematurely abstracted.
