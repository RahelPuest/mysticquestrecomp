# Roadmap

Milestone list per the project brief, plus milestones this project's own
work surfaced as real gaps not named in the original list. Status
reflects what's actually built and verified, not aspiration — see
[progress.md](progress.md) for the detailed, frequently-updated working
notes this table summarizes.

**2026-08-11 refresh**: the previous version of this file was last
substantively updated 2026-08-08/09 and had drifted badly out of date —
entire milestones it called "not built yet" (map transitions, the
event system, save, the real damage formula) were finished in the
sessions since. Rewritten end to end against `progress.md`'s actual
later entries and the live task tracker, not incrementally patched.

**2026-08-12 refresh** (direct user request: "nochmal alle milestones,
deren status, was fehlt zum abschluss und die prio"): the 2026-08-11
version above was itself already stale within the same day — a long
follow-on session (still 2026-08-11 continuing into 2026-08-12) made
real further progress on Milestone 3 (the secondRoom generalization
attempt — a genuine, informative result, though not quite what it
first looked like, see below), Milestone 6 (digraph table 16->30
entries, the control-byte question resolved), and especially
Milestone 7 (the `0xFF` sub-table fully bounded and mostly
disassembled; a real ~80-opcode "actor state" family traced all the
way into bank 3's own code). Updated below against `progress.md`'s
own dated entries from that stretch, not guessed.

**2026-08-13 refresh** (direct user request: "was ist der status der
milestones, was würdest du als nächstes vorschlagen"): a single, very
long session made substantial real progress on 3 fronts since the
above. Summary (full detail in the milestone entries below and in
`progress.md`/`docs/reverse-engineering/events.md`'s own dated
entries):
- **Milestone 7** — real opcode coverage went from 7/256 to **90/256
  wired Lua handlers** (across 6 census rounds run in an earlier part
  of this same multi-day stretch), AND the real `ScriptInterpreter` is
  now genuinely LIVE-INTEGRATED into gameplay for the first time — a
  new `ScriptRuntime`/`RomScriptStream` pair runs the real, decoded
  boss-defeat script directly against live ROM bytes, gated behind
  `MYSTICQUEST_SCRIPT_INTERPRETER=1` and reported via the debug
  overlay (a deliberate parallel "shadow run," not yet driving real
  rendering — see events.md's own "ScriptInterpreter wired into live
  gameplay" section). A real, serious bug was found and fixed along
  the way (non-portable bitwise-operator syntax that crashed the WHOLE
  app under real LÖVE, undetected by the headless test suite).
- **World scope** — 2 more real rooms found, decoded, and wired
  (`fifthRoom`, `sixthRoom` — both reached via corridors past
  `fourthRoom` that needed much longer real button-holds than earlier
  probes tried, a real, caught false-negative lesson). A new general,
  reusable `HoldTrigger.lua` mechanism now reproduces the real ROM's
  own hold-to-trigger delay for these "cut" transitions.
  `sixthRoom` was the direct answer to a real user bug report.
- **General room/map system** — a deep, explicitly-requested
  investigation into how rooms are encoded/connected/spawn-positioned,
  ROM-code-first per direct instruction. Real, settled, general
  systems found and consolidated (room-content table; the visual door/
  exit reveal mechanism, `$235B`/`$225D`/`$2281`/`$056C`; the generic
  20-slot WRAM entity struct, `$0AE3`/`$0A74`) — now written up as one
  authoritative reference in `rom-map.md`'s own new "Consolidated
  reference" section, AND built into real, tested Lua data
  (`src/import/EntityStructLayout.lua`). Equally real, equally
  important NEGATIVE result, reached via 6+ independent, exhausted
  static-analysis angles: room CONNECTIVITY and player SPAWN POSITION
  are demonstrably NOT static ROM tables in this game — genuinely
  script/bytecode-driven at a depth this project's own opcode decoding
  hasn't reached yet. Not a project gap; an honest finding about the
  ROM's own real design.
**2026-08-13 continuation** (direct user request: "ok dann mach bitte
7 und kommentiere alles"): kept working Milestone 7 opcode-by-opcode
against the live shadow run's own next real stopper each time —
`0x19`, `0x27`, `0x50`, `0x51`, `0x61` all decoded and wired (95/256
now). Result: the boss-defeat script shadow run no longer halts on ANY
undecoded opcode — it runs its full probe budget legitimately waiting
on opcode `0x00`'s real "queue empty" gate, which only drains across
real game frames this single-shot probe doesn't simulate. This is a
real, honest stopping point for THIS script, not a claim the whole
opcode space is covered (see the Milestone 7 detail entry below).

**2026-08-13, task #80** ("ja mach das" -- shadow-run the WHOLE real
1357-script census, not just the boss-defeat script): found and wired
5 more real opcodes (exact matches for already-known shapes). More
importantly, computed the TRUE opcode-coverage number directly instead
of counting named constants (several handler addresses are shared by
dozens of real opcode values) — **real total: 150/256**.

**CORRECTED same day** (direct user question: "kann der bug
auswirkungen auf anderen informationen gehabt haben? bitte nochmal
nachprüfen"): the scan tool that surfaced task #80's numbers had a
SECOND bug beyond the one already fixed — it assumed every script
lives in the same fixed bank as the boss-defeat one, when the raw
table actually rolls a script's start address into later banks past
table index 666. This means the originally-reported "48% of scripts
(653) hit a real CHAIN-to-VRAM mystery" was mostly a scan-tool
artifact, not a real ROM phenomenon — re-scanning with the corrected
per-script bank math shrank that to a real, much smaller **7 scripts**,
and raised "clean/known-halt" from 303 to **427**. Nothing already
WIRED into the codebase was affected (independently ROM-byte-verified,
passing tests); only the scan tool's own diagnostic numbers were wrong.
See events.md's own dated "CORRECTION" section for the full trail.

**Same day, direct follow-up** ("ändere auch den code entsprechend"):
turned the confirmed bank-rollover finding into real, tested,
checked-in code -- new `src/import/ScriptPointerTable.lua`
(`.resolve()`, the real formula) plus `RomScriptStream.forScriptIndex`,
the correct general way to start any script by its own table index.
`StandardScriptHandlers.chain()` deliberately left unchanged -- the
same rollover applying to mid-script `CHAIN` targets is still only a
plausible, unconfirmed hypothesis (task #81), and this project doesn't
bake unconfirmed mechanisms into production interpreter behavior.

Full Lua test suite: 240 (2026-08-08) -> 327 today.

**2026-08-14 refresh** (consolidation pass after several further
sessions: task #82's opcode families, #83's deep-family tracing, #84's
first real interpreter->rendering proof, #85's cross-actor dispatch
mechanism, #86's `BossSequenceInterpreter`, #87's `rom-inspector/`
website, and a final long "work through all remaining whole-corpus
scan blockers" pass -- full detail in `progress.md`'s own dated
entries and `docs/reverse-engineering/events.md`): **real opcode
coverage is now 186/256** (up from 150/256 above), with the
whole-corpus scan's own `clean` count at 871/1357 (up from 427). The
single longest-standing known-hard opcode in this project's history
(`0x80`, present in every scan since the first session) is now
genuinely closed -- its real "unmodelable" leaf (`$02AB`) turned out to
be a plain read of the player's own real facing-direction byte, which
this project already tracks. `0x81`/`0xEC`/`0xED`/`0xEE` (the rest of
that same `$02AB` family) remain open, now precisely narrowed to a
separate, still-real blocker (`0x81`'s further leaf, and `0xEC`-`0xEE`'s
shared dependency on the cross-actor `$C3F0` staging mechanism). The
interpreter also produced its first real, visible, end-to-end output
this stretch (task #84: a synthetic script renders real ROM text via
the real `TextBox` component) and the boss-defeat sequence's own real
blocking condition is now understood down to a specific actor-command
barrier (task #86), not just "gets stuck." A new interactive website
(`rom-inspector/`, task #87) now presents this project's own decoded
ROM data browsable and searchable, regenerated from the live code
after every session (task #88, ongoing).

## Priority order

Compiled directly from a milestone-by-milestone status review (direct
user request, 2026-08-11: "füge die neuen milestones auch noch mit in
die tabelle und priorisiere"). Reasoning per tier below the table.

| Prio | Milestone | Status | Why this priority |
|---|---|---|---|
| P0 | **3 — Map/room extraction** | 🟢 pipeline GENERALIZED (2026-08-12); **8 real, walkable rooms now wired (2026-08-13)**, up from 6 | willyRoom/secondRoom/thirdRoom/fourthRoom/fifthRoom/sixthRoom, plus the 2 unrelated dev-only `unknownRoomA` clusters. Remaining work is "extract/wire more real rooms with this proven pipeline," not "prove the pipeline works." |
| P0 | **NEW — World scope / content pipeline** | 🟢 384 real, decodable rooms (2026-08-14, up from 320); 2 more real ones found live and wired this session (`fifthRoom`, `sixthRoom`, 2026-08-13) | A real, general "decode any room" capability exists; actually WIRING a new room as walkable content is now a well-practiced, real, repeatable process (tile-offset search + floor classification + `HoldTrigger`-based exit), demonstrated twice more this session. Bank 7's own "Templated" encoding is now CRACKED for tile content (2026-08-14, base-template + per-record diff, see rom-map.md) -- 64 more decodable rooms; its door-data bytes and per-room collision remain undecoded. Connectivity/spawn position are still KNOWN to be script-driven, not table-driven (see the "general room/map system" investigation). |
| P1 | **7 — Script/event system** | 🟢 **186/256 real opcode values covered (2026-08-14, true count)**, whole-corpus scan `clean` at 871/1357, the longest-standing known-hard opcode (`0x80`) finally closed | 6+ census rounds plus a new whole-corpus scan tool (shadow-runs all 1357 real scripts, not just one) found and wired most of the actor-flag/queued-action/trigger-event/actorSlotPosition/actorAction-family opcodes; a `ScriptRuntime`/`RomScriptStream` pair actually RUNS real, decoded scripts against live ROM bytes (behind `MYSTICQUEST_SCRIPT_INTERPRETER=1`, reported via the debug overlay), and (2026-08-13/14, task #84) has driven its first real, VISIBLE output. Still parallel to, not replacing, `Field.lua`'s hand-authored `FIELD_EVENTS`/`VictorySequence` room-graph — 186/256 is closing in on 3/4 but the remaining ~50 addresses are mostly non-trivial control flow (the cross-actor `$C3F0` dispatch mechanism, task #85's own subject), not a quick follow-up. |
| P1 | **9 — Combat (remainder)** | 🟡 partial, real progress 2026-08-12 | Close to done, high player-facing impact — real per-species ATK now fully extracted (11 species), DEF still genuinely open (one more lead chased and ruled out, see combat.md) — real, honest, bounded remaining scope. |
| P1 | **NEW — Bestiary (multiple enemy types)** | 🟡 real stat DATA now available (2026-08-12), still exactly 1 SPAWNABLE enemy | `EnemySpeciesTable.lua` has real ATK for all 11 real species — ready for wiring once P0's room work surfaces a real spawn trigger for any of the other 10 (this project does not fabricate a species-to-room mapping without ROM evidence). |
| P2 | **6 — Text/dialogue (remainder)** | 🟢 digraph table effectively closed (2026-08-12): 30 → 91 confirmed entries, ~66% real-region coverage, full sentences now decode end to end | Needed for every new dialogue P0 content brings in; not a hard blocker today. Remaining gap is wiring the now-solid decoder into actual gameplay text (still hand-authored `FIELD_EVENTS`/`VictorySequence` strings today), not more decoding work. |
| P2 | **8 — Menu/inventory (remainder)** | 🟡 partial | Visible gameplay gap (items/equipment aren't usable yet), but independently addressable. |
| P2 | **NEW — Magic/spell system** | 🔴 not started | Core Seiken Densetsu genre feature; depends on P1's event system and P2/8's item plumbing. |
| P2 | **NEW — Level/XP system** | 🔴 not started | Well-scoped, not a blocker for anything else. |
| P3 | **2 — Graphics extraction (remainder)** | 🟡 partial | On-demand extraction is already working practice; a full sweep only pays off once P0 delivers more content to render. |
| P3 | **Generated-cache pipeline** (task #34) | 🔴 deliberately deferred | Architecture decision already made 2026-08-11: build once enough normalized data exists to cache — depends on P0. |
| P3 | **Audio** | 🔴 not started | Explicitly lowest priority since before this file existed (format totally unknown). |
| P4 | **Parity-check process** (expand on task #33) | 🟡 proof of concept exists | Valuable alongside every new finding, not a standalone deliverable. |
| P4 | **NEW — Interactive ROM documentation** (`rom-inspector/`) | 🟢 built 2026-08-14, all 9 sections working, verified live in-browser | Not a blocker for anything — a documentation/presentation artifact. Ongoing cost is small (rerun `export_data.lua`) but real: keep it in mind whenever opcode coverage, room count, or WRAM findings change, so it doesn't quietly go stale. |
| Deferred | **Modding architecture** | 🔴 not started | Per the brief, deliberately deferred until core gameplay is stable. |
| Deferred | **Packaging/release** | 🔴 not discussed | Only worth doing once there's enough real content to release — depends on P0/P1. |

## Milestone detail

- [x] **Milestone 1 — Bootable native application.** Done early, still
      solid: LÖVE app launches, 160x144 canvas integer-scaled, `Input`/
      `StateStack`/`FixedStep` core, F1 debug overlay, `Boot` identifies
      the ROM (SHA-1) and rejects unsupported ones with a concrete
      reason, hands off to a real title screen -> name entry -> field.

- [~] **Milestone 2 — Graphics extraction.** 2bpp tile decode done and
      unit tested (`GBTile`, cross-checked against an independent
      Python implementation, `tools/graphics/gbtile.py`). Every region
      this project's own vertical slice actually needed has been found
      and centralized in `rom_profiles.lua` — font, player/enemy/NPC
      sprites (including the two secondRoom NPCs' real 4-direction walk
      cycles, found 2026-08-11 via exact ROM byte search), room
      tilesets, attack-swing/thrust art, HUD bar, title/intro art.
      **Remaining:** no systematic full-ROM sweep of every bank has
      been done — extraction is still purely on-demand, driven by what
      a specific feature needed. Revisit once Milestone 3 delivers more
      rooms/content to render (see priority table).

- [~] **Milestone 3 — Map extraction.** **UPDATE 2026-08-12: the
      generalization proof is CLOSED** — see rom-map.md "MILESTONE 3
      GENERALIZATION: CLOSED". `unknownRoomB` (the real black-wipe
      transition backdrop, itself only identified this same day) was
      reached via a genuine, real transition and single-stepped to
      find its own real layout-stream address; this project's own
      ALREADY-SHIPPED, UNMODIFIED `RoomFloorLayout.decodeLayoutStream`
      reproduces the real, live-observed WRAM result exactly against
      that real address. The pipeline mechanism (metatile-table-
      location formula + RLE layout decode) is now proven, with real
      code, to generalize beyond willyRoom — closing the specific gap
      that kept this milestone (and the whole "World scope" milestone
      behind it) at P0. **Remaining, now cleanly scoped**: extract
      real, VARIED-content rooms at scale (the pipeline has only been
      exercised against a uniform/blank backdrop for its 2nd case;
      `unknownRoomA`, real substantive content, is still unreached —
      see rom-map.md's own honest stop on that search) — this is now
      "do more of the proven thing," not "prove the thing works."
      **UPDATE 2026-08-11 (major):
      the real, general room-floor decompression pipeline is now found
      and cross-verified end to end** (see rom-map.md "MILESTONE 3
      SOLVED"), closing out a chain of sub-investigations this same day
      (bank 5's own mystery resolved via static disassembly; the exit/
      door-reveal mechanism traced and live-validated; finally the
      floor-layout pipeline itself). Full pipeline, every stage code-
      verified, most of it live-cross-checked against willyRoom's own
      known-correct pixel grid: `roomSelectorTable` (bank 8) record ->
      metatile table (6-byte records: 4 GFX-tile bytes + collision +
      interaction, matching the FFA-Disassembly project's documented
      US-ROM format) -> a SEPARATE compressed layout stream (bank 7 for
      willyRoom, a different bank than the metatile table) -> RLE
      decode (bit7-set byte = "repeat `byte&0x7F`, WRAM `$C3F9` times",
      a real per-room constant, not fixed) into an 8x10 WRAM array ->
      combined with the metatile table + the live `$D070` remap ->
      288/320 of willyRoom's real tiles reproduced exactly, with the
      remaining 32 falling precisely inside the 4 already-traced door/
      exit zones (drawn by a separate, already-documented overlay
      mechanism, not a decode error). **UPDATE, same day ("ja mach das
      bitte"): ported to a real Lua decoder**, `src/import
      /RoomFloorLayout.lua`, cross-checked end to end in
      `tests/import/room_floor_layout_test.lua` against a fresh, real
      ROM load (not just the investigation's own scratch scripts) —
      asserts the exact real numbers (288 matches, 32 door-zone
      placeholders, 0 unexplained mismatches), full suite 202/202.
      **What this changes**: Milestone 3's real DoD (a general,
      ROM-driven way to load ANY room) now has a concrete, verified,
      SHIPPED mechanism behind it for willyRoom — but still not fully
      general: `$D070`'s own population still needs a live dump per
      room (or its populator traced statically), and the pipeline has
      only been verified against willyRoom — generalizing to a second
      room is the concrete next validation step. Bank 5's original
      256-record table's role in this picture is still unconfirmed
      (plausibly another room's own metatile table and/or layout
      stream — worth a focused revisit now that the format is cracked).
      **Still blocks real world scope until generalized past one room**,
      hence still P0, but the remaining work is now "generalize a
      working, tested decoder" rather than "solve an open mystery."
      **UPDATE 2026-08-11 (the generalization attempt, a real, useful,
      if not fully conclusive result)**: attempted to validate the
      pipeline against a second, genuinely different room. Found
      instead — via two independent methods (a live capture matching
      `secondRoom.grid` exactly, and statically discovering the
      metatile table simply extends past index 79) — that "secondRoom"
      is not a separate `roomSelectorTable` entry at all: it's further
      ROWS of willyRoom's own continuous space, revealed by a real,
      SECOND mechanism (a scroll-time tile-enqueue routine, `$1E9F`/
      `$1EB6`) rather than a fresh `$242B` decompression call. Real,
      valuable new knowledge (how this ROM's own room-scroll engine
      populates newly-revealed rows without re-running the whole
      decoder), but it means the decode pipeline itself has still only
      ever been exercised against ONE real `roomSelectorTable` record
      (willyRoom's). **The actual generalization proof — decoding a
      second, independent room selector's own metatile+layout data
      end-to-end — remains the concrete next step**, now with a
      clearer picture of what does and doesn't count as "a different
      room" in this ROM's own terms.
      **UPDATE 2026-08-12**: real further progress on exactly this
      step (see rom-map.md's own "World scope: force-loading an
      unreached room" section). Found 2 genuinely new, never-reached
      target rooms (`unknownRoomA`/`unknownRoomB`) via the already-
      decoded 16-record `roomSelectorTable`; their own metatile tables
      dump as real, plausible data (several records byte-identical to
      willyRoom's own shared tileset blocks). Live force-called the
      real "load room N" entry point (`$026DC`) and got an EXACT match
      to the static prediction — real, decisive proof the room-commit
      mechanism itself generalizes correctly. **Still not fully
      closed**: rendering the room after the forced commit doesn't
      work cleanly yet (the surrounding game-state machine expects
      more synchronized WRAM fields than the minimal force-call sets;
      precisely diagnosed, not just hit and abandoned) — a concrete,
      named next step (trace the full real caller chain, not just
      `$026DC`) remains.
      **UPDATE 2026-08-12 (same day)**: traced that full caller chain
      and **solved `unknownRoomB` for good** — it's the real black-wipe
      transition backdrop (live-confirmed: `B=0x0F`/roomSelector 15 at
      the real room-load handler during the real post-boss cutscene,
      WRAM matches exactly, screenshot shows a solid black screen), not
      a hidden area. `unknownRoomA` (`$3849`) remains the one real,
      still-open candidate for genuinely new content — not triggered
      by this same real trace, needs a different real gameplay
      sequence to find its trigger. The live-tracing method is now
      established and reusable for whoever continues.
      **UPDATE 2026-08-12 (same day, "ja mach weiter")**: tested 2 more
      real cut sequences (the staircase → fourthRoom transition, which
      correctly confirmed the ALREADY-known roomSelector 1 — validating
      the method — and a full 4-direction exploration of fourthRoom
      itself, previously never explored). Real, honest dead end: UP/
      LEFT/RIGHT walled, DOWN loops back into already-known space —
      `unknownRoomA` not triggered anywhere reachable from this
      project's own current 4-room vertical slice. Deliberately stopped
      here rather than searching unboundedly — a real chicken-and-egg
      with Milestone 3's own broader "extract more content" work, not a
      dead investigation.

- [x] **Milestone 4 — Player movement.** VERIFIED 1px/frame walk speed
      (no acceleration), real per-tile wall collision
      (`TileWalkability`), real facing/animation (`PlayerSprite`,
      4-direction), real diagonal-movement rule. Solid, not revisited
      recently because it hasn't needed to be.

- [~] **Milestone 5 — Map objects and transitions.** Far along: a real,
      general, data-driven room-graph engine (`VictorySequence.lua`)
      covers every real transition mechanism found so far (hardware
      scroll on either axis, instant cut via the relocatable-pointer
      pipeline) — **8 connected rooms** (2026-08-13, up from 4), real
      per-room NPCs with real dialogue (proximity-triggered, not
      room-entry — corrected 2026-08-10), real animation, and
      (2026-08-10) a real, honestly-approximate wander/movement AI.
      A new general `HoldTrigger.lua` mechanism (2026-08-13) reproduces
      the real ROM's own hold-to-trigger delay for "cut" transitions.
      **Remaining:** no general NPC/object *placement format* has been
      found in the ROM (secondRoom's two NPCs are individually
      hand-captured, PRNG-placed, transform undecoded); this only
      covers the 8 rooms Milestone 3 already unlocked. **UPDATE
      2026-08-13 (a real, honest architectural finding, not a project
      gap)**: a deep, explicitly-requested investigation (6+ independent
      static-analysis angles, all real code, all reported honestly)
      found that room CONNECTIVITY and player SPAWN/LANDING POSITION
      are genuinely NOT static ROM tables in this game -- both are
      script/bytecode-driven at a depth this project's own opcode
      decoding hasn't reached yet (see `rom-map.md`'s own new
      "Consolidated reference: the general room/map system" section).
      Every `landingX`/`landingY` value in `rom_profiles.lua` will
      keep being a real, live-captured empirical measurement, not a
      formula, until that opcode depth is reached -- an honest,
      bounded, now well-understood limitation, not an open question
      about WHETHER a table exists.

- [~] **Milestone 6 — Text and dialogue.** Real in-ROM font rendering,
      a real bordered textbox component with typewriter reveal, real
      umlaut/eszett glyphs (found and fixed 2026-08-10). **UPDATE
      2026-08-11 (major)**: the digraph compression table grew from 16
      to 30 confirmed entries (a systematic full-ROM re-scan found the
      real dialogue region is ~26KB, not the originally-known ~1KB
      window). The long-standing "0xFE-vs-0x04 display-message opcode"
      question is fully, independently RESOLVED (0xFE, via the real
      script-interpreter dispatch table itself — see Milestone 7).
      **The dialogue control-byte question is also resolved**: `0x12`
      VERIFIED (live execution-trace, not inference) as the real
      "halt the reveal and wait for player input" byte; a static
      cross-reference across 24+ real contexts found `0x11`=close
      dialogue entirely vs. `0x1B`=advance to the next page in the
      same conversation; `0x14`=the real hero-name substitution token;
      `0x2C`=a real speaker-name delimiter.
      **UPDATE 2026-08-12 (major, 3 passes same day)**: the "no
      dialogue pointer table located" gap above is CLOSED — the real
      messageID→text formula was found via the `$1F64` dispatcher
      (`0x34800 + u16le(messageSettingsRecord + 20)`, now in
      `rom_profiles.lua`'s `messageTextPointer`), ending this project's
      own multiple-times-failed earlier search for it. Immediately
      followed by a systematic close of the digraph table itself: a
      reusable "fill-in-the-blank word" extractor (found real words
      with exactly one still-unknown byte across the whole ~26KB
      dialogue region, solved each against real German, cross-checked
      by re-decoding the whole region for coherent prose) took
      `DIGRAPH_PARTIAL` from **30 → 91 confirmed entries** across 3
      rounds. Whole-region real-byte coverage: ~66%. Full multi-
      sentence passages now decode completely, e.g. *"Was hast du ihr
      angetan, Julia?"*. **Remaining, honestly**: 2 bytes (`0x82`,
      `0x63`) are genuinely CONTRADICTORY across their own occurrences,
      not just unconfirmed — left open rather than guessed; ~55 low-
      frequency byte values in the digraph range still unmapped (real,
      bounded, not worth chasing without more data); still no general
      word-wrap/hyphenation (hand-wrapped strings throughout
      `rom_profiles.lua` instead); and — the actual remaining gap for
      this milestone now — none of this real, decoded ROM text is
      wired into actual gameplay yet (`FIELD_EVENTS`/`VictorySequence`
      still use hand-authored strings, not `TextDecoder` output).

- [~] **Milestone 7 — Script/event system.** **Major breakthrough
      2026-08-10**: the real event/script interpreter is FOUND and
      FULLY DECODED at the mechanism level — the real opcode-fetch
      primitive (`$3727`), the real 256-entry dispatch table (bank 2,
      `$8576`), several real opcode semantics (display message, heal-
      to-max family, the real no-op default handler). This closes a
      question this project chased since Milestone 3/7's very first
      framing.
      **UPDATE 2026-08-11/12 (substantial, multi-pass depth added)**:
      - The `0xFF` opcode's own second-level sub-dispatch table is now
        real, BOUNDED (exactly 11 entries, file `0x3BAC` — previously
        only hedged as "256-entry-style"), and its own dispatch
        mechanism fully disassembled. 7 of the 11 sub-handlers carry a
        real, stated conclusion, including a genuine 4-member
        "conditional interpreter halt" family and the real
        "reschedule the sub-dispatch on the next tick" primitive
        (`$3C74`). Reframed with real evidence as the driver for a
        more elaborate MULTI-LINE textbox variant (cursor bookkeeping,
        line-wrap, blanking), layered on top of the already-known
        single-line reveal — not an NPC-movement system as first
        guessed.
      - A real, systematic ~80-opcode family (`0x10`-`0x8A`, gaps
        exactly matching the already-known HEAL_LP opcodes — a clean
        cross-confirmation) was found, structurally resolved, and
        followed all the way across a real bank-3 trampoline into
        bank 3's own code (function 0x0A, file `0xCB70`). Real finds
        there: a general 8-slot "known/active ID" list at WRAM
        `$C5A0`, and a third distinct WRAM actor/object array at
        `$C4E0` (24-byte stride). Live-tracing (after fixing a real
        script bug and a significant tooling-reliability lesson — wide
        multi-address `Watcher` sweeps can undercount real hits; a
        narrow watch is needed to trust a "zero hits" result) found
        `$C4E0` is read constantly (every 10-30 frames) in EVERY
        tested context, reframing it as a routine, ambient "active
        actor slot" bookkeeping structure rather than a rare,
        specifically quest-flag-only trigger.
      - **UPDATE 2026-08-12**: real opcode wiring finally started —
        7 of 256 real opcodes now have an actual WIRED Lua handler
        (`message`, `healToMax`, `skip`, `chain`, `setFlagBit`,
        `clearFlagBit`, and the newly-added `tick` for opcode `0x04`,
        the typewriter reveal), all tested against the real boss-
        defeat script's own decoded semantics (up from 2 — see
        events.md's "Wiring more real opcodes" section). Still real,
        honest, bounded remaining scope: 11 more of THIS ONE script's
        own opcodes are structurally traced but not yet distilled to a
        plain-language meaning precise enough to implement (the `0xFF`
        sub-table hand-off, the actor-flag family, palette fade, a
        conditional loop, sound/timing params, an event/sound trigger,
        the conditional halt) — this project's own discipline is still
        to wire a handler only once an opcode's real effect is fully
        understood, not guessed. Deliberately NOT wired to replace
        `Field.lua`'s own hand-authored `FIELD_EVENTS`/
        `VictorySequence`'s room-graph (see events.md's own "scope
        boundary" note) — not enough of even this one real script's
        own opcodes are covered yet to responsibly replace hand-
        authored event code with it. Every additional room Milestone 3
        unlocks will need either more real opcodes decoded, or will keep
        accumulating hand-authored event code — hence P1.
      **UPDATE 2026-08-13 (major): 90/256 opcodes wired (up from 7),
      AND the interpreter is LIVE-INTEGRATED for the first time.** 6
      census rounds decoded and wired most of the actor-flag/queued-
      action/trigger-event opcode families (`StandardScriptHandlers
      .lua` grew to 17 distinct real handlers across ~90 opcode
      values). Separately, a new `ScriptRuntime.lua`/
      `RomScriptStream.lua` pair (plus a corrected `ScriptInterpreter
      .fetch`, which used to assume a plain 1-based array) lets a real
      `ScriptInterpreter` instance run DIRECTLY against live ROM bytes
      for the first time — wired into `VictorySequence.lua` as an
      opt-in "shadow run" (`MYSTICQUEST_SCRIPT_INTERPRETER=1`, reported
      via the debug overlay, never controlling real rendering/state).
      Live-verified: 7 real opcodes execute in sequence against the
      actual boss-defeat script before honestly stopping at the next
      undecoded one — the interpreter's real, current reach, not a
      simulation. A real, serious crash was found and fixed along the
      way: `StandardScriptHandlers.lua`'s bitwise-operator syntax
      (Lua 5.3-style, tolerated by the local dev `luajit` CLI but NOT
      by real LÖVE's own bundled LuaJIT) broke the WHOLE app's boot the
      moment this new code entered the real require chain — caught
      only by an actual `love .` launch, not by the headless test
      suite; a real, concrete lesson that a passing test suite plus a
      clean module-load check are NOT sufficient proof the real app
      boots. Still parallel to, not replacing, the hand-authored
      room-graph — same real reasoning as before, now with a
      genuinely live, growing interpreter behind the switch instead of
      a purely static one.
      **UPDATE 2026-08-13 (continuation, "mach bitte 7"): 95/256
      opcodes wired, and the boss-defeat shadow run now completes with
      zero undecoded-opcode halts.** Picked up exactly at the shadow
      run's own next real stopper, opcode `0x19`, and kept following
      it: `0x19` ($12AE, reuses `0x49`'s own `$123E` chain via a
      different trampoline base), `0x27` ($12F4, standard `actorAction`
      group 0x1D), then `0x50`/`0x51`/`0x61` (three more `actorAction`
      family members found back-to-back in the same dense trampoline
      cluster). Each addition re-ran the shadow-run probe immediately
      (batch-verified per this project's own testing discipline) —
      stepCount climbed 7 -> 9 -> 10 -> 12, and the run then completed
      its full 5000-step budget with NO further undecoded-opcode halt,
      legitimately parked on opcode `0x00`'s own real "queue empty"
      wait gate (already-modeled, correct behavior — that queue only
      drains across real game frames this single-shot probe doesn't
      simulate, not a bug). **Honest scope**: this is real completion
      for THIS ONE script, not the whole opcode space — 95/256 is
      still under half; the next concrete step is shadow-running other
      real scripts from the project's 1357-script census to find
      further real stoppers. Full Lua test suite: 313 -> 318 this pass
      (+5 new real-ROM-cross-check tests, one per newly-wired opcode).
      **UPDATE 2026-08-13 (task #80, "ja mach das"): shadow-ran the
      WHOLE real 1357-script census, not just the boss-defeat script.**
      Built `scan_all_scripts_shadow_run.lua` (scratchpad, not checked
      in) — runs every real `scriptPointerTable` entry through a fresh
      `ScriptRuntime`, 500-step budget each. Caught and fixed a real
      bug in the tool ITSELF first: aggregating by `runtime.lastOpcode`
      is wrong, since that field only updates on a SUCCESSFUL step and
      is stale after a real stop — fixed by parsing the real failing
      opcode out of `stopError`'s own message text. Cross-referencing
      the ~99 distinct new undecoded handler addresses this surfaced
      against already-known handler shapes found 5 exact matches
      (`0x41`/`0x45`/`0x4B`/`0x55`/`0x59`, all either standard Family-A
      `actorAction` members or another `actorSlotPosition`/`$123E`
      instance) — wired all 5 reusing existing factories, zero new Lua
      handler code. Re-scanned: the "clean/known-halt" script count
      rose 279 -> 303 (+24), real corpus-wide progress. Computed the
      TRUE "opcodes covered" number by iterating all 256 real opcode
      values directly (not by counting named constants, which
      undercounts badly since several shared handler addresses cover
      dozens of real opcode values each) — **real total: 150/256**.
      Also surfaced what LOOKED LIKE a genuinely unresolved
      architectural question: 48% of all real scripts (653/1357) hit a
      real `CHAIN` jump computing a target inside Game Boy VRAM address
      space (`$9303`), outside this project's modeled `$4000`-`$7FFF`
      ROM bank window.
      **CORRECTED same day** (direct user question: "kann der bug
      auswirkungen auf anderen informationen gehabt haben? bitte
      nochmal nachprüfen"): re-checking found the scan tool had a
      SECOND, separate bug beyond the `lastOpcode` one — it assumed
      every script starts in the SAME bank as the boss-defeat one
      (bank 8), generalized from the one VERIFIED example, which
      happens to have a small `tableValue`. The raw table actually
      rolls a script's own start address into LATER banks once
      `tableValue` exceeds `0x3FFF` (a clean, deliberate split
      starting exactly at table index 666) — confirmed decisively by
      re-decoding with the correct per-script bank math and finding
      the resulting bytes are sensible, already-known real opcodes
      (e.g. index 667 -> opcode `0x19` -> handler `$12AE`, wired this
      very session), not garbage. Re-scanning with the fix: "clean/
      known-halt" rose 303 -> **427**, and the real residual "cursor
      out of bounds" mystery shrank from 653 scripts down to a real
      **7** (indices 489/530/703/879/1141/1324/1325) — each runs
      several successful real steps before hitting what's now most
      plausibly (though not fully proven) a genuine CROSS-BANK `CHAIN`
      target, the same rollover mechanism applied to a jump instead of
      a script start. `RomScriptStream.lua`'s own doc comment already
      hedged this exact possibility ("a real cross-bank script jump,
      if one exists, is not modeled here") — now concretely confirmed
      to exist, still not modeled, left honestly open (task #81).
      Nothing already WIRED was affected — all 5 new opcodes remain
      independently verified via absolute, fixed-bank-0 ROM byte
      disassembly + passing tests. Opcode frequency ranking DID change
      substantially with the fix (`0x08`: 29->107 scripts, `0xFC`:
      13->65, `0x0B`: 15->37) — task #82 updated with the corrected
      numbers. See events.md's own dated "CORRECTION" section for the
      full trail. ~90 handler addresses remain undecoded, mostly
      non-trivial control flow (WRAM bit tests, conditional calls, a
      nested sub-dispatch table found at opcode `0xBA`) rather than the
      simple, already-familiar shapes — real further work, left
      honestly open. Full Lua test suite: 318 -> 319 this pass (no
      further wiring changes during the correction itself, which was
      pure re-verification).

- [~] **Milestone 8 — Menu/inventory/equipment.** Data Crystal's US RAM
      map cross-checked live and matches with zero offset (HP/MP/level/
      gold/stats/atk-def/name buffers). Real `Stats`/`Inventory` data
      models; the real in-game menu (`Dinge`/`Magie`/`Waffe`/`Frage`)
      renders real decoded item/weapon/spell names (`ItemTable.lua`/
      `WeaponTable.lua`, VERIFIED against live ROM bytes, including the
      live-cross-checked "Breit" weapon name). **Remaining:** items and
      equipment are visible in the menu but not actually usable/
      equippable in gameplay yet — no item-granting, no equipment-
      swapping logic; weapon/item stat-byte fields still UNKNOWN (no
      real value to compare a formula against yet).

- [~] **Milestone 9 — Combat.** Real-time contact/action combat,
      confirmed (not a separate turn-based battle mode). **The real
      damage formula (`$50AC`) is now fully decoded and wired into
      actual gameplay** (2026-08-10): `base = max(0,ATK-DEF)+1`,
      `damage = floor(noiseByte*base/1024)+base`, with a bit-exact
      ported real PRNG (`$2B1E`, cross-checked byte-for-byte against a
      live ROM trace) and the real enemy ATK (8, code- and live-
      confirmed). Real attack visuals (swing/thrust, hit-flash), real
      knockback + invincibility flicker (with a 2026-08-10 fix: no
      longer ignores wall collision). **Remaining:** the enemy DEF
      value for the reverse direction (player attacking an enemy) is
      still not conclusively identified (task #5/P1); no weapon-power
      table wired; no magic/spell casting at all despite a real MP
      stat existing; and, starkly, exactly ONE enemy exists in the
      whole game today — see the new Bestiary entry below.

- [~] **Audio.** Format still entirely UNKNOWN. Driver location
      VERIFIED (100% of sound-hardware-register writes during boot +
      title music traced to ROM bank 15). Explicitly lowest ordinary
      priority (task #6/P7) — no work beyond the original location
      trace has happened.

- [x] **Save system.** Fully implemented and wired end to end
      (2026-08-10, task P6): the real MBC2 nibble-packed format
      (`WriteNibblePair`/`ReadNibblePair`, VERIFIED), the real `0x6C`
      magic byte, the real primary+backup duplicate-copy scheme —
      `src/save/*.lua`, a real save (F7 dev key) and load
      ("Weiterspielen" on the title screen) round-trip tested end to
      end including real file I/O and corruption detection. **Only
      open item:** the real ROM's own save TRIGGER condition (what
      player action actually saves in the original game) is still
      unknown — irrelevant to this project's own dev-key-driven save
      flow, but an honest gap if full ROM-behavior parity is ever
      wanted here.

- [ ] **Modding architecture.** Deliberately deferred by design until
      core gameplay is stable (per the original brief) — still true,
      still not attempted, still the right call: every milestone above
      is still missing real content to mod. Namespacing discipline
      (ROM-derived vs. hand-written data never sharing a table/key
      space) is being kept in mind already (see
      gen1recomp-analysis.md SS7) so this won't need a disruptive
      retrofit later.

- [~] **NEW — World scope / content pipeline.** Not previously named as
      its own milestone, but it's the real gap between "solid vertical
      slice" (what exists today: 4 rooms, 1 enemy, 3 NPCs) and
      "the game." Was directly blocked on Milestone 3's own
      generalization proof. **UPDATE 2026-08-12**: that blocker is
      closed (see Milestone 3 above), and this milestone's own first
      real find followed the same day — `unknownRoomA` (real
      roomSelectors 8-13), a strong, structurally-evidenced candidate
      for a whole new 6-room area, found entirely through static
      analysis (bank 5's own already-decoded RLE table, re-used via a
      simple, now-tested `roomSelector N = bank5 record N` hypothesis
      — see rom-map.md's own "unknownRoomA upgraded" section).
      **UPDATE 2026-08-12 (same day)**: pixel-verified for real — all 6
      rooms rendered end to end (`tools/graphics/
      render_unknown_room_a.py`) and confirmed as genuine, coherent
      dungeon art (brick walls, floor mesh, torches, real furniture/
      feature objects), backed by a quantified tile-entropy check
      landing squarely in the real-art band for all 6.
      **UPDATE 2026-08-12 (same day, "du kannst das gerne einbauen")**:
      BUILT IN as real, walkable content — `rom_profiles.lua`'s new
      `graphics.unknownRoomA_8..13` entries (real grid/tileOffsets, plus
      a real-collision-byte-grounded `floorTileIds`, see that file's own
      `UNKNOWN_ROOM_A_*` doc comments for the bitmask reasoning) and a
      new dev-only `RoomExplorer.lua` state (reached via F8 from Field)
      let a player actually walk all 6 rooms with real collision, room
      art, and the real player sprite/animation — smoke-tested live via
      `love .` (F8 opens it, A/B cycle rooms, arrows move with working
      wall collision; screenshots confirm real, correct dungeon art
      rendering in-app, not just in the standalone Python tool).
      Deliberately dev-only, not a real in-fiction door: no live ROM
      trigger into this area was ever found, so this project does not
      fabricate connectivity that would misrepresent invented placement
      as decoded ROM behavior (see `RoomExplorer.lua`'s own doc comment).
      **Remaining, honestly**: the floor/wall classification is real-
      data-grounded (metatile collision byte, bitmask-interpreted) but
      still HYPOTHESIS, not independently confirmed against live
      gameplay; the real in-app palette is still the project's default
      grey ramp, not confirmed BGP; no real in-fiction path into the
      area exists or is planned to be fabricated.
      **UPDATE 2026-08-12 (same day, "du sollst in der lage sein alle
      räume zu dekodieren"): the real breakthrough — 8 → 320 decodable
      rooms.** Generalized the exact `unknownRoomA` recipe past its own
      6 hardcoded indices: found a SECOND, independent 64-record map
      table (bank 6, same real header-driven RLE format as bank 5,
      just `rleLength=4`), then shipped `RoomFloorLayout
      .buildRoomFromMapTableRecord` — a real, general, ROM-static
      decoder needing no live emulator state. Exhaustively swept BOTH
      tables (320 records total): every single one lands in the real
      "coherent art" `tile_entropy()` band, zero blank/noise outliers.
      See rom-map.md's own "World scope, round 5" for the full trace.
      **What this does NOT yet include**: none of the other 312 rooms
      (beyond the original 6) are wired into the app as walkable
      content yet — that's real, concrete, well-scoped next work, now
      unblocked rather than open-ended. Bank 7's own "Templated"
      encoding (mode 1) is a real, separate, still-undecoded
      compression format — an unknown further number of rooms remain
      genuinely out of reach until that's cracked.
      **UPDATE 2026-08-12 (same day, parity-check quick win, honest
      negative result): the "roomSelector N = mapTable record N" rule
      does NOT generalize past `unknownRoomA`'s own family.** Live-
      traced willyRoom's own real roomSelectorTable index (WRAM `$C3F5`
      = 4, stable) and compared bank-5 record 4 against willyRoom's own
      real captured grid cell-by-cell: only 96/320 real matches (best
      of any bank-5/6 record 0-7 checked: 124/320) — nowhere near a
      real identification. So "320 decodable rooms" means 320 records
      decode as real ROM ART, not that all 320 have a confirmed real
      in-game IDENTITY — only the original 6 do. See rom-map.md's
      "World scope, round 6" for the full trace.
      **UPDATE 2026-08-13: 2 more real, in-fiction rooms found, decoded,
      and wired** — `fifthRoom` (found via a corridor north of
      `fourthRoom`, needing a real ~64-frame hold-to-trigger delay an
      earlier probe's own 10-frame stall timeout had missed) and
      `sixthRoom` (found the same way, west of `fourthRoom`, the direct
      resolution of a real user bug report). Both reuse the
      willyRoom/secondRoom/thirdRoom family's own shared tile source,
      decoded via the exact same live exact-16-byte-VRAM-pattern ROM
      search this whole pipeline has used throughout. The room chain is
      now 8 rooms deep (up from 4 at the start of this stretch).
      **UPDATE 2026-08-14 ("weiter bohren bis es fertig ist"): bank 7's
      own "Templated" (mode 1) encoding, called out as still-undecoded
      just above, is now CRACKED end to end.** Real base-room RLE
      template + per-record `(value,position)` diff overlay, found via
      an exhaustive automated search over the plausible byte-layout
      combinations (the winning combination scored 100% valid diff
      positions vs. 97.1% for the next-best alternative). VERIFIED:
      566/566 real diff positions across all 64 records valid, all 64
      reconstructed rooms land in the real `tile_entropy()` art band
      (zero outliers), 6 spot-checked records visually confirmed as
      genuinely distinct room content. Shipped as real, tested code
      (`MapTable.readTemplatedHeader`/`applyTemplatedDiff`/
      `recordDataFileOffset`, `RoomFloorLayout.buildRoomFromTemplated
      MapTableRecord`) — `buildRoomFromMapTableRecord` now dispatches
      transparently on the map's own header `encodingMode`, so callers
      never need to know which encoding a room table uses. Decodable
      room count: **320 → 384**. See rom-map.md's "bank 7 Templated
      revisited, CRACKED" for the full evidence. Still open: the
      map-level 24-byte door-data block and each record's own 4-byte
      prefix remain undecoded (plausibly door/exit-flag data), and
      real per-room collision is not yet implemented for bank 7.

- [ ] **NEW — Bestiary (multiple real enemy types).** Exactly one
      enemy is actually SPAWNABLE in the implementation today.
      Milestone 9's combat formula is real and correctly wired, but
      "combat" as a finished feature needs more than one thing to
      fight. **UPDATE 2026-08-12**: the real stat-data half of the
      blocker is closed — `src/import/EnemySpeciesTable.lua` extracts
      the real, full 11-species ATK table (bank 4, file `0x10c80`-
      `0x10df0`, 46 rows), tested against the real ROM byte dump. What
      remains: DEF for enemies is still genuinely unresolved (see
      combat.md's own 2026-08-12 entry — one more real lead chased and
      ruled out, not merely "not looked at"), and — the bigger
      remaining blocker — no OTHER real spawn trigger pointing at any
      of the other 10 species has been found yet, so wiring more than
      the one already-playable enemy still depends on Milestone 3's
      world-scope work surfacing rooms that contain them.

- [ ] **NEW — Magic/spell system.** `Stats.curMP`/`maxMP` are real,
      VERIFIED fields (Data Crystal cross-check), and the in-game menu
      already has a real `Magie` option — but no casting mechanic, spell
      list, or spell-effect logic exists. Depends on Milestone 7 (an
      event/script system real spell effects would plug into) and
      Milestone 8 (the item/inventory plumbing spells would share with
      usable items).

- [ ] **NEW — Level/XP system.** `Stats`' real `experience`/`level`
      fields are VERIFIED (Data Crystal cross-check) but read-only
      today — no XP gain, no level-up logic, no stat growth curve
      decoded. Well-scoped and independent of other open work; lower
      priority only because nothing else depends on it.

- [ ] **NEW — Generated-cache pipeline.** Confirmed 2026-08-11 as a
      real, committed target architecture (not just inspiration) —
      adopt gen1recomp's ROM-in -> `data/generated/*.lua` +
      `assets/generated/**/*.png` -> runtime-never-touches-the-ROM-again
      shape (see architecture.md's own dated entry for the full design).
      Deliberately not started yet (explicit user decision, same
      session) — building it now, before Milestone 3 delivers enough
      normalized content to justify a cache, would be premature
      plumbing. Tracked as task #34.

- [ ] **NEW — Parity-check process.** `tools/parity/check_door_zone.py`
      (2026-08-11) is a real, working proof of concept — an automated
      comparison of real ROM behavior against the recomp's own data,
      not a manual screenshot-eyeball session. `check_fresh_stats.py`
      (2026-08-12, quick win #4) is a second, independent check (real
      WRAM `$D7B2` fresh-character struct vs `Field.lua`'s own
      hardcoded default, both PASS for all 6 fields) — proves the
      approach generalizes past the one door-zone case, still not yet
      a general framework or a habit applied to every new finding;
      worth growing alongside whatever Milestone 3/5/7 work happens
      next rather than building out in isolation.

- [ ] **NEW — Packaging/release.** How an end user actually obtains and
      runs this app (an installer, an itch.io-style page, bundling
      instructions for supplying their own ROM) has never been
      discussed. Not worth any effort until there's enough real,
      playable content (Milestone 3's world-scope work) to make
      releasing something meaningful.

- [~] **NEW — Interactive ROM documentation (`rom-inspector/`).** Built
      2026-08-14 (direct user request: "erstelle... eine interaktive
      dokumentation des mystic quest roms", styled after
      [DeniseBischof/HLV](https://github.com/DeniseBischof/HLV) in
      presentation, not content) — a standalone, dependency-free static
      site (plain HTML/CSS/JS, `rom-inspector/index.html`) documenting
      this project's own real reverse-engineering findings: memory map
      (ROM banks + a curated WRAM cell reference), the entity struct
      (interactive slot visualizer), all 256 script opcodes (searchable/
      filterable, colored by REAL decode status — built by actually
      constructing a `ScriptRuntime` and checking registered handlers,
      not hand-classified — each with a curated human-readable
      description), a live whole-corpus scan result, the room graph,
      a Tile-Viewer and Map-Viewer (decode real Game Boy 2bpp graphics
      client-side from a user-supplied ROM file — never embedded,
      never uploaded), a live text-encoding decoder against real ROM
      byte samples, and an open-questions page. Data is either
      **auto-generated** by `rom-inspector/tools/export_data.lua`
      (requires this project's own already-verified Lua modules, e.g.
      `ScriptOpcodeTable`/`EntityStructLayout`/`TextDecoder`) or
      explicitly **hand-curated** and labeled as such (`wram-map.js`,
      `open-questions.js`, `opcode-descriptions.js`).
      **Ongoing obligation, not a one-off**: this site's `js/data/*.js`
      files are a SNAPSHOT — they go stale the moment new opcodes get
      decoded, new rooms get wired, or new WRAM cells get identified
      elsewhere in this project. From now on, treat "does this change
      the rom-inspector's own data?" as a standing question on any real
      decoding-progress work, and re-run
      `MYSTICQUEST_ROM=<path> luajit rom-inspector/tools/export_data.lua`
      (regenerates the auto part) plus update the relevant hand-curated
      file by hand where needed. Tracked as an ongoing task in the live
      tracker (see task list) rather than a single completed item.

## Superseded by this file

`gen1recomp-analysis.md`, `architecture.md`'s own "What's deliberately
not built yet" section, and this file's own pre-2026-08-11 version all
listed several of the above as "not started" when they were, by
2026-08-10, actually finished (map transitions, the event system's
discovery, save, the real damage formula). Cross-reference
`progress.md`'s dated entries for the authoritative blow-by-blow if
this file and that one ever disagree again — `progress.md` is the
living log, this file is a periodically-refreshed summary of it.
