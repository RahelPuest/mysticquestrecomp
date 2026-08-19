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

**2026-08-15 refresh**: Bank 7's own "Templated" room format (64 more
rooms, encodingMode=1) is fully CRACKED for both tile content and
per-metatile collision (base-template RLE + per-record diff-overlay
scheme, 566/566 real diff positions valid, live-verified via real
screenshots) -- 384 total decodable rooms now, up from 320. Its
per-record door-data bytes show a real, clean 8-value statistical
structure but stay honestly undecoded (no live bank-7 gameplay exists
to confirm byte-to-direction meaning). A second boss encounter (direct
user request, matching the first boss's own real sprite/species data
and a real, non-coincidental species-byte match found via a full
1357-record static census) was implemented as an evidence-based, NOT
ROM-confirmed, feature -- see `docs/reverse-engineering/events.md`'s
own "Second boss investigation" section for the complete trail,
including three live room-placement corrections working through
`fourthRoom` -> `fifthRoom` -> `sixthRoom` before landing on the room
reached by walking west out of `fourthRoom`'s own corridor.
`sixthRoom` itself was real, already-captured ROM tile data that a
2026-08-14 pass had retracted as an exit target (the real ROM never
"cuts" there, it's one continuous scrolling canvas) -- re-wired back in
as an honestly-labeled engineering choice once the user confirmed live
that reaching it matters more than strict ROM-transition fidelity,
pending real scroll-camera support as the more complete future fix.

**Same-day follow-up, direct user demand ("suche einfach einen
allgemeinen kollisions mechanismus")**: a dedicated hunt for
fourthRoom's own real metatile+layout-stream source came back a
genuine, decisive negative (single-stepped the entire real staircase
transition, 6M+ instructions, zero hits on the known RLE-decompressor
entry point) -- this room's real load simply doesn't use that
pipeline. Fell back to real, live-walked mgba probing instead and found
a real, position-specific wall (a narrow staircase alcove) that a flat,
tile-ID-keyed `floorTileIds` set structurally cannot express. Added a
new, general, reusable mechanism instead of another one-off:
`TileWalkability.build` now accepts an optional `room.blockedRects`
list -- real, live-discovered rectangular exceptions layered on top of
the tile-ID check, usable by any room. Caught and fixed a real
off-by-one in the first version via a live `love .` screenshot before
shipping (see `docs/reverse-engineering/rom-map.md`'s own dated
section for the full trace). 3 new headless tests, 435/435 total.

**Same-day follow-up #2**: re-verifying the staircase landing position
(direct user report it still looked wrong) led to a genuinely new,
general finding: this project has always drawn the player sprite at
the raw WRAM position with no adjustment, but a live dump of the real
hardware OAM table shows that value is already pre-offset by the
standard Game Boy `(+8, +16)` sprite convention -- the true rendered
position is 1 tile left / 2 tiles up from what this project has always
shown. First fixed by editing the one reported landing coordinate
directly; caught the same pass (checking a second landing spot) that
this conflates collision-space with render-space and would break other
rooms' already-tuned floor data if reapplied blindly elsewhere.

**Same-day follow-up #3, direct instruction ("mach mal den gesamt
fix")**: implemented a general fix -- `Player.lua`'s new
`RENDER_OFFSET_X`/`RENDER_OFFSET_Y` + `:renderPosition()`, applied at
the final sprite-draw call across every state that draws the player.
Spot-checked via a couple of `love .` screenshots (fourthRoom's
landing, secondRoom's free-roam spawn) and looked fine.

**Same-day follow-up #4, self-caught regression, direct user report
after actually playing the app**: "im ersten bossraum sscheint diese
verschoben zu sein" -- the general fix broke `startRoom`'s own
rendering (`Field.lua`), whose sprite positions/collision were
historically calibrated the OLD, unshifted way -- a couple of
screenshot spot-checks aren't the same rigor as real play, and this
regression only surfaced once the user actually launched and looked.
**Fully reverted**: every player draw call in `Field.lua`,
`BattleIntro.lua`, `VictorySequence.lua` back to the raw
`self.player.x/y`; `fourthRoom`'s own landing back to the real raw ROM
value (120,112) -- the underlying hardware fact stays real and
documented in `Player.lua`, just not applied anywhere, since safely
wiring it in would need re-verifying every single room's own
historical calibration individually, a real, much larger undertaking.
436/436 tests (the now-unused `renderPosition()` method's own unit
test still passes). See `rom-map.md`'s own dated sections ("Real
hardware OAM-vs-WRAM sprite offset", its "implemented" follow-up, and
the "self-caught regression... reverted" section) for the full trail.

**2026-08-15, Same-day follow-up #5** ("mach mal 1" from a fresh
project-quick-wins list -- "wire the ScriptInterpreter to actually
DRIVE gameplay, not just shadow-run"): rewired `VictorySequence.lua`'s
whole `MYSTICQUEST_SCRIPT_INTERPRETER=1` integration around
`BossSequenceInterpreter` (`src/scripting/BossSequenceInterpreter.lua`),
ticked ONCE PER REAL FRAME from `:update(dt)` instead of a one-shot
construction-time burst -- matching how the real ROM's own interpreter
is actually driven. Found and fixed a real, self-caught bug in the
process: the OLD integration (`runScriptInterpreterShadow`, since
removed) built its `RomScriptStream` from
`profile.scriptPointerTable.fileOffset` (bank 8, the STATIC pointer
table's own location) -- but task #86 (2026-08-14, one day earlier) had
already found and documented, live, that the real ROM's own EXECUTING
cursor for this exact script is bank 13 (switching to 14 on the first
real CHAIN), not bank 8. That correction was never propagated back into
this file, so the OLD "shadow run" had been silently executing the
WRONG bank's bytes -- confirmed via a fresh, from-scratch headless probe
(`probe_boss_sequence.lua`, scratchpad) that found zero overlap with
events.md's own documented opcode list for this script.
The new, live, per-frame run is CORRECTLY banked, wires a REAL
`ctx.onMessage` (resolves via `MessageTextPointer`, same formula
`runMessagePipelineDemo` already proved), and reaches real, decoded ROM
content (confirmed identically by both the headless probe AND a live,
in-app `love .` run converging on the exact same real cursor, `0x4798`,
bank 14). This is NOT a full swap-over -- the hand-authored `self.pages`
dialogue stays 100% authoritative and visually unchanged (live-verified
via screenshot, both switch-on and switch-off) -- but it IS the
concrete, correctly-banked, per-frame infrastructure the eventual
swap-over needs, and a genuine bug fix in its own right. 2 new
regression tests added (`tests/unit/boss_sequence_interpreter_test.lua`);
437/437 tests pass.

**Same-day CORRECTION** (direct continuation, "mach das", following the
"find the real `$1F35`/`$C5AF` trigger condition, live, via mgba" step
above): a real, decisive live `mgba` trace (`courtyard_boss_defeated()`
checkpoint, watching `$D85A`/cursor/`$C5AF` every real frame) found the
original write-up above was WRONG about where this run actually stalls.
The `$1F35`/`$C5AF` edge DOES fire exactly once and DOES land the
cursor at the real, correct `$470F` entry point -- that specific
mystery is CLOSED. But the REAL ROM does NOT dispatch a new opcode
every real frame past the first CHAIN (`$D85A` was observed holding for
10-314 consecutive real frames at a stretch) -- so this project's own
per-frame `:tick()` cadence races ahead and silently DESYNCS from the
real byte stream well before reaching opcode `0x00` at all. Live proof:
over the identical real frame range from the identical checkpoint, the
REAL ROM reaches cursor `0x6206` (having genuinely dispatched the real,
still-undecoded `0xBC`/`0xBD` palette-fade opcodes along the way -- the
first live confirmation these actually fire in this script) while this
project's own software is stuck at the unrelated cursor `0x4798`. The
"stalls on opcode 0x00" symptom is this project's own software artifact
from that desync, not a faithful reproduction of a real ROM mystery.
`BossSequenceInterpreter:tick`'s own doc comment, `VictorySequence.lua`'s
top-of-file doc comment, and the regression tests are all corrected to
state this honestly.

**Same-day, FOUND AND FIXED** ("ja mach das", continuing straight from
the correction above): a native `mgba` write-watchpoint on WRAM `$D85A`
found the answer -- opcode `0x04` (the typewriter tick) self-reschedules
from its own real handler (`PC $36DB`) at an exact, clean, real 5-FRAME
interval (dozens of consecutive observations, every delta exactly +5),
sharing opcode `0xFF`'s own already-known real pacing gate exactly (this
project's own `StandardScriptHandlers.textboxWait` doc comment already
said the two share "the identical typewriter mechanism" -- now proven
true in practice, not just structurally). `StandardScriptHandlers.tick`
's own Lua implementation was WRONG (claimed "always advances
immediately," contradicted by this evidence) -- rewritten to share
`.textboxWait`'s exact pacing+gating shape. 3 tests updated to match;
437/437 pass. HONEST, decisive scope note: `BossSequenceInterpreter`'s
own `ctx.isTextboxDone` is STILL a deliberate, ALREADY-DOCUMENTED
"always true" stand-in (2026-08-13's own original design, "no real
display state to gate on in a shadow run") -- so this fix, while a real
and valuable standalone correctness improvement, does NOT change this
specific shadow run's own desync from the real ROM. That desync is now
understood NOT as a separate, crackable mystery, but as the direct,
expected consequence of that already-honest limitation (genuinely
modeling it would need a real per-character count this project has
nowhere to source without guessing) -- left as a named limitation, not
pursued further.

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
| P0 | **3 — Map/room extraction** | 🟢 pipeline GENERALIZED (2026-08-12); **9 real, walkable rooms now wired (2026-08-16)**, up from 8 | willyRoom/secondRoom/thirdRoom/fourthRoom/fifthRoom/sixthRoom/seventhRoom, plus the 2 unrelated dev-only `unknownRoomA` clusters. `seventhRoom` (2026-08-16, direct user report) is the first room wired WITHOUT a live gameplay capture -- picked from the already-decoded 384-room catalog by real collision-byte walkability instead, behind a real `requiresFlag`-gated exit (secondBoss defeat). Remaining work is "extract/wire more real rooms with this proven pipeline," not "prove the pipeline works." |
| P0 | **NEW — World scope / content pipeline** | 🟢 384 real, decodable rooms (2026-08-14); 9 rooms actually explorable via a real, normal play path -- an attempted 2026-08-19 push to 15 (via `unknownRoomA`'s 6 rooms) was built, live-"verified", reported done, then RETRACTED same day after a direct user report | A real, general "decode any room" capability exists; actually WIRING a new room as walkable content is a well-practiced, repeatable process. **2026-08-19, direct "voll spielbare Version" push, then retracted same day**: `unknownRoomA`'s own 6 real, fully-decoded rooms (previously only reachable via the F8 dev browser) were briefly connected via a deliberate, honestly-labeled ENGINEERING-CHOICE door chain (`seventhRoom -> unknownRoomA_8..13`). It was pulled back after a direct, blunt user report ("alles nach dem 7. raum ist müll") triggered a full re-audit: the `floorTileIds` every landing spot depended on mismatched this project's own stated collision-byte classification rule for 42 of 82 tiles actually used, and even a fully mechanical, rule-consistent rebuild produced a checkerboard artifact with almost no real 2x2-footprint-walkable area in most of the 6 rooms (2 of 6 had zero connected walkable footprint at all). The original single-cell landing check never caught this because it didn't test the real footprint `TileWalkability.build` actually uses, and no in-game walk test happened before the feature was reported done -- both gaps now recorded as a concrete process lesson, see events.md's own 2026-08-19 retraction entry. Room content stays 100% real ROM data, untouched; only the invented doors were withdrawn, back to none, until a trustworthy floor source exists for this metatile table. Bank 7's own "Templated" encoding is CRACKED for tile content AND collision (2026-08-14) -- 64 more decodable, collision-aware rooms, still unconnected. Connectivity for the remaining 80/82 real transitions stays script-driven and genuinely unknown (see the room-connectivity blocker's own dedicated history). |
| P1 | **7 — Script/event system** | 🟢 **all 256 opcode values now classified (2026-08-16)** — 201 decoded/wired, 49 confirmed no-op, 6 known-hard by design, **0 genuinely undecoded** (up from 187/256 covered, ~50 still-open addresses); whole-corpus scan `clean` at 883/1357 (up from 871). The real interpreter now also drives 2 real transitions' room selection live in actual gameplay (2026-08-16, `thirdRoom→fourthRoom` and `fourthRoom→fifthRoom`, see below), not just a shadow run | 6+ census rounds plus a new whole-corpus scan tool (shadow-runs all 1357 real scripts, not just one) found and wired most of the actor-flag/queued-action/trigger-event/actorSlotPosition/actorAction-family opcodes; a `ScriptRuntime` actually RUNS real, decoded scripts against live ROM bytes (behind `MYSTICQUEST_SCRIPT_INTERPRETER=1`, reported via the debug overlay), and (2026-08-13/14, task #84) has driven its first real, VISIBLE output. Still parallel to, not replacing, `Field.lua`'s hand-authored `FIELD_EVENTS`/`VictorySequence` room-graph for anything beyond that one live-wired transition. "0 undecoded" means every opcode VALUE has a real, verified classification (decoded/no-op/known-hard) — it does NOT mean every opcode has gameplay-ready behavior: the 6 known-hard ones are traced but deliberately left unwired. UPDATE 2026-08-19: the 2026-08-16 "bank-call-stack eviction" diagnosis turned out to rest on an injection technique that never actually worked -- it poked mGBA's own cached `currentBank` display field, which a direct test this pass proved has ZERO effect on real memory reads or CPU fetches. The CORRECT primitive (a real `$2100` bus write, verified byte-for-byte) plus a correctly-disciplined stack push (fully disassembling `$29FB`/`$2A0A` for the first time) gets meaningfully further: the first bank-stack pop now correctly restores the real, pre-existing organic bank rather than an arbitrary default, disproving "random concurrent churn" as the root cause. Still doesn't reach `0xBA`'s real handler though -- SAME-DAY FOLLOW-UP found the precise reason: the real dispatch cycle unwinds 3 nested `RET`s (using the genuine, untouched Z80 `SP`) before reaching code that deliberately relocates the stack (`LD SP,HL`) and then `RET`s from it -- landing in WRAM's echo-RAM mirror because `HL`'s value at that exact point was never under our control. FURTHER SAME-DAY FOLLOW-UP tested a "filter by bank-stack depth" fix empirically (3,000,000-step real scan) -- REVISED: depth is constant (194) across all 39 real `$3727` hits observed, not a usable signal, and all 11 distinct real callers found share the identical `CALL $3727`/`RET` shape -- ordinary opcode-dispatch tails, not "unrelated subsystems" as the previous entry framed it. The real gap is narrower and sharper still: `$49AC` isn't `0xBA`'s own documented handler (`$0EB2`) at all -- the opcode-table LOOKUP machinery itself computed the wrong target, meaning it depends on more real input than bank+HL alone. **BREAKTHROUGH, SAME DAY, 5th round**: studying a clean (non-injected) reference trace of the identical natural moment found the real remaining bug -- the "disciplined push" adds an EXTRA stack level, shifting the real subsequent pop UP by one. Fix: overwrite the EXISTING top slot in place instead of pushing a new one. With that + the already-fixed bus-write bank switch + starting the injection from an ALREADY-ACTIVE real script context (not an arbitrary early-boot moment) -- **live execution reached the real `0xBA` handler (`$0EB2`) for the first time in this project's history**, and ran it: confirmed byte-for-byte against `ScriptOpcodeTable.lua`'s own existing static analysis (a real entity-slot allocation via `$0A74`, a genuine 20-slot live scan, populating a real slot with real data). The methodology is now general and reusable -- a working live-injection primitive (verified bank switch + verified stack overwrite + verified starting context) that can be pointed at the other 5 known-hard opcodes or any other unreached script. Not yet wired into the Lua interpreter, and the full entity-struct field semantics + independent confirmation of the despawn half aren't fully closed -- honest, well-scoped follow-up. Five real rounds deep into this thread, each honestly reported, the last one a genuine, historic payoff. See events.md's own 2026-08-19 entries (4 dated passes) for the full trace. |
| P1 | **9 — Combat (remainder)** | 🟢 both directions' real formulas now understood (2026-08-16); weapon-power question now DECISIVELY, empirically CLOSED negative (2026-08-16, same day) | Real per-species ATK fully extracted (11 species); player-attacks-enemy MAJOR CORRECTION 2026-08-16 -- real PRNG-driven formula found (same shape/PRNG as `$50AC`), the earlier "flat, no formula" read was a floor-rounding coincidence at the only testable base value, see combat.md. Live WRAM-poke experiment (`$D6E9`, the equip-slot cell `$5BA7` already, decisively reads) found the damage-formula base is unaffected by any of the other 5 real class/kit index values -- byte-exact identical combat outcome across all 5, and even `$D6C1`'s own attack-stat readout doesn't react to the poke. Working conclusion: the base (`4`) is most plausibly a fixed per-attack-type constant, not per-weapon power -- see combat.md's own dated entry. |
| P1 | **NEW — Bestiary (multiple enemy types)** | 🟡 real stat DATA now available (2026-08-12), still exactly 1 SPAWNABLE enemy | `EnemySpeciesTable.lua` has real ATK for all 11 real species — ready for wiring once P0's room work surfaces a real spawn trigger for any of the other 10 (this project does not fabricate a species-to-room mapping without ROM evidence). **2026-08-18: shares its exact root blocker with Level/XP below** — `EnemyStatTable.lua`'s own `xp`/`gold` fields are real and non-zero for 15 of 21 species; reaching a second enemy unblocks both at once. |
| P2 | **6 — Text/dialogue (remainder)** | 🟢 digraph table effectively closed (2026-08-12): 30 → 91 confirmed entries, ~66% real-region coverage, full sentences now decode end to end; **live-decoder wiring CONFIRMED DONE (2026-08-16)** | Stale claim corrected: `VictorySequence.lua`'s entire story-page/Willy-exchange text (all 3 story pages + the full Willy exchange, 10+ real lines) already resolves via `TextDecoder.decodeString(romData, offset)` directly against real ROM bytes, and both known real NPCs' dialogue (`secondRoom`'s characterA/characterB) already resolve via `DialogueTextResolver`. No hand-authored dialogue string remains in the live runtime path (a couple of literal speaker-tag prefixes like `"Willy:\n"` are hardcoded, honestly documented as the still-undecoded real name-insertion control byte, not dialogue content). Needed for every new dialogue P0 content brings in; not a blocker. |
| P2 | **8 — Menu/inventory (remainder)** | 🟢 items/equipment now usable (2026-08-16); item heal-amount investigated (2026-08-16, same day), genuinely inconclusive | Real Dinge/Waffe interactivity shipped (use/equip), gated behind a real, non-empty inventory (F12 dev-only grant, since no real ROM item-granting trigger is known). A static pass over `ItemTable`'s own undecoded stat bytes found a real candidate ("power" byte, offset 10) but it does NOT cleanly resolve (looks like a status bitmask for cure spells, a scalar for attack items) -- genuinely blocked on no live item-use trigger existing (the real WRAM held-item struct itself is unfound), not on more staring at bytes. See combat.md/ItemTable.lua's own dated entries. `Inventory:useItem` still applies no numeric effect, by design (no fabricated formula). |
| P2 | **NEW — Magic/spell system** | 🟢 which record is which spell + its real MP cost + the real ROM deduction code: CLOSED (2026-08-19); 🟢 **full FIELD/MENU 8-category effect-dispatch chain mapped, and shown to be field-only, not universal** (same day); 🔴 the real BATTLE-context spell-effect code (where Ice's own effect, and Fire's/Lightning's/Nuke's real damage, most likely live) genuinely not yet located; a real spell-learning trigger also still unfound | The 8 MP-costed castable spells (Cure/Heal/Sleep/Mute/Fire/Ice/Lightning/Nuke) are `ItemTable` records 0-7 — found by live-disassembling the real ROM's own MP-deduction routine (bank 2 CPU `$718F`-`$71AB`, menu; `$6660`-`$667E`, battle). Mapped the COMPLETE real post-deduction dispatch reachable from the menu path: 8 chained effect-category tables (`$7B29`→`$7B31`→`$7B38`→`$7B46`→`$7B3D`→`$7B40`→`$7B43`→`$7B48`), each a real null-terminated membership list. Decisive design finding: items AND spells share this dispatch (e.g. Cure and the shop potions Lebe/S-Lebe/Magi/S-Magi/Elixier funnel through the same LP-restore code) — but $7B38/$7B43/$7B46 turned out to be a genuine treasure/key-item "add to a real 16-slot inventory at `$D7E1`" category, unrelated to combat. Self-caught correction: Sleep/Mute were guessed backwards from walkthrough order (both cost 1 MP) — real table membership (Blok+"Stille"=Mute, Ruhe+"Schlaf"=Sleep) resolves it the other way. **Real, evidence-grounded reframe of the Ice anomaly**: traced the battle-context MP-deduction routine's own real continuation (`$71AC`) and found it returns IMMEDIATELY for any spell index (1-8) — the whole `$7B29`-`$7B48` chain is FIELD/MENU-only, not something battle-cast spells go through at all. So Ice's (and very possibly Fire/Lightning/Nuke's own real damage) effect lives in a genuinely separate, not-yet-located battle-context code path. **WIRED INTO THE APP, same day**: found and fixed a second, live-affecting instance of the same backwards item/spell split bug (`Inventory.lua`'s own `itemCatalog`/`spellCatalog` split, the interpreted app's own copy of the website's already-fixed `isSpell` bug) plus a genuine second gap (`Menu.lua`'s `Magie` option had no branch at all, unlike `Dinge`/`Waffe`) — `Magie` now opens a real sub-list once spells are granted, showing each one's real name + real `mpCost` (e.g. "Salb 1MP"); selecting one is a deliberate no-op (no fabricated MP deduction/effect). Live-verified via 3 real `love .` screenshots, a fresh character's behavior unaffected. See events.md's own 2026-08-19 entries (5 dated passes). |
| P2 | **NEW — Level/XP system** | 🟡 **reward VALUES now real and mostly decoded (2026-08-18)**, WRAM accumulator + growth formula still open | No real WRAM address for a per-kill XP write is known yet, and the 2 (then 3) real search angles run 2026-08-16 came back negative — but only because the ONE currently-reachable fight (row 16 of `EnemyStatTable`) genuinely has `xp=0`, `gold=0`, now CONFIRMED by real ROM data, not just a live-tracing gap. 15 of the other 20 species/bosses have real, non-zero, cross-verified `xp` values (10-210) sitting ready. Same root blocker as Bestiary above — reach a second enemy, then re-run the already-proven live-diff method against THAT fight to find the real WRAM accumulator. |
| P3 | **2 — Graphics extraction (remainder)** | 🟡 partial | On-demand extraction is already working practice; a full sweep only pays off once P0 delivers more content to render. |
| P3 | **Generated-cache pipeline** (task #34) | 🔴 deliberately deferred | Architecture decision already made 2026-08-11: build once enough normalized data exists to cache — depends on P0. |
| P3 | **Audio** | 🟢 format DECODED + `love.audio` PLAYBACK shipped (2026-08-16, task #151); **real background music now plays during actual field gameplay** (2026-08-16, same day) | Song table, note/duration/octave encoding, and frequency table all real and verified; `src/audio/` plays all 30 real songs through `love.audio` (dev-only `MusicJukebox.lua`, F9, still available). `Field.lua` now also starts real song 1 automatically on entering the field, stops cleanly on F9/victory transition -- an honest, clearly-labeled ENGINEERING CHOICE for *which* song plays *when* (no ROM trigger for that is known), not a claimed ROM fact; every note played is still real, decoded ROM audio data. |
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
      **STORY-CONTEXT CORRECTION, 2026-08-17** (direct user pushback,
      "marsch cave ist was anderes als die start sequenz! weiter
      schauen"): this project's own `startRoom`-through-`ninthRoom`
      room chain was misidentified as Marsh Cave (this game's first
      dungeon) in an earlier same-day pass — corrected and decisively
      confirmed instead as the real GLAIVE CASTLE PRISON ARENA intro
      sequence (rendered `startRoom` live and compared it directly
      against the real game's own first screenshot: identical room,
      monster, gate, and HUD values — see docs/references.md's own
      dated entry for the full trail). Doesn't change any decoded ROM
      data, only which real story moment this project's rooms
      represent.
      **ROOM-IDENTITY CORRECTION, 2026-08-17** (same day, direct user
      claim "ich bin mir sehr sicher das er übergang von fourth in den
      fith room einfach nur ein übergang zurück in den third room
      ist"): confirmed live and correct — `fifthRoom`'s real WRAM
      room-identity registers (`$D392`/`$D393` tile-source pointer,
      `$C3F0` dynamicBank, `$C3F5` roomSelector) are byte-identical to
      willyRoom/secondRoom/thirdRoom's own. Not a genuinely separate
      ROM room, just a different (per-cut) scroll section of the same
      shared canvas — full register table, screenshots, and grid-
      overlap numbers in `events.md`'s own dated entry; surfaced on
      the rom-inspector website's Room-System graph (violet badge on
      `fifthRoom`'s own node) and `rom_profiles.lua`'s `fifthRoom.
      sameRomIdentityAs`/`sameRomIdentityNote` fields.
      **SECOND ROOM-IDENTITY CORRECTION, 2026-08-17** (same day, direct
      user claim "und der sixth raum muss ganz klar der startraum
      sein. das habe ich 1000 mal im rom beobachtet"): also confirmed
      live and correct — `sixthRoom`'s real WRAM identity registers are
      byte-identical to `startRoom`/`fourthRoom`'s own, forming a
      SECOND real "one continuous canvas" chain. This one also caught
      a real, previously-wrong claim already sitting in this project's
      own data: `sixthRoom.romRoomSelectors` said the wrong family
      (`{2,3,4,5,6}`, willyRoom's own) with no live confirmation ever
      done, and an "HONEST CAVEAT" paragraph had explicitly (and
      wrongly) dismissed an EARLIER user's own "sieht aus wie der
      Start-Raum" observation as an imprecise recollection — both
      retracted this pass. Independent corroboration beyond the
      registers: `sixthRoom`'s own screenshot shows the real ROM's
      "Kämpfe!" battle-intro textbox, the same real UI `startRoom`'s
      own boss-encounter script drives. Fixed a stale test
      (`tests/import/sixth_room_test.lua` used to assert the wrong
      family). Same website mechanism as the fifthRoom finding (generic
      `sameRomIdentityAs` rendering, no rom-inspector code changes
      needed beyond re-exporting).
      **CAPTURE-BUG FIX, 2026-08-17, immediate direct follow-up**
      ("der raum sieht wie eine kombination aus dem startraum und dem
      fourth room aus... als ob da was beim lesen verschoben wurde
      oder so. prüfe erstmal ob das vielleicht das problem ist" —
      exactly right): `sixthRoom`'s own STORED `grid`/`tileOffsets`
      turned out to be a real, reproduced capture bug — a raw VRAM
      tilemap read that never corrected for the room's own real,
      nonzero hardware SCX (96), producing a "half brick corridor,
      half courtyard" combination that never appears on real hardware.
      A correctly SCX-windowed read of the same live moment shows only
      real `startRoom` content (the "Kämpfe!" textbox over ordinary
      courtyard floor). Fixed by pointing `sixthRoom.grid`/
      `tileOffsets`/`floorTileIds` at `startRoom`'s own real tables
      directly (a Lua table reference, not a copy). 4 tests across 3
      files had baked-in assumptions from the buggy data — fixed, one
      retired outright as circular. Full suite 560/560 green. See
      `events.md`'s own dated follow-up entry for the full trace.
      **REAL VRAM TILE-COPY PIPELINE FOUND AND CLOSED, 2026-08-17,
      same day** (direct user report "raum 7 8 und 9 haben die
      falschen tilesets", then "bleib dran" after a first pass came up
      short): closed a previously-explicit open item
      (`rom-map.md`'s own 2026-08-11 "$D070's real populator" section
      had disassembled the VRAM-slot allocator but left its own tail
      unfinished) by live single-step tracing the real allocation
      burst, then fully disassembling the whole chain (`$01AF3`->
      `$1B74`->`$1B19`/`$1B2B`->`$1BA1`->`$2DF5`->`$2D57`) down to the
      real MBC bank-select write (`LD (0x2100),A`, bank 12/11) and the
      real per-frame LY-budgeted VRAM-write queue-drain routine. Exact-
      matched the resulting formula against willyRoom's own known-good
      pixel (`0x321b0`, byte-for-byte). Applying it to the 384-room
      catalog's own real family found a genuine, previously-
      undiagnosed bug: the catalog's own `tilesetFileOffset` (`0x32000`)
      was actually willyRoom's own real pixel-pool base, mismatched
      against the catalog's own correct metatile-table base -- two
      different real ROM "maps"' own halves mixed together. Corrected
      to the real `0x30000` (all 384 catalog rooms, not just the 3
      disputed ones) -- re-rendered every sanity-check + disputed
      record, dramatic improvement across the board (generic reused
      dungeon corridors -> real, distinct outdoor scenes: a wooden
      gate, trees, a lake, a road). `seventhRoom`/`eighthRoom`/
      `ninthRoom`'s own dispute is RESOLVED, not just flagged, this
      time. `unknownRoomACandidates`'s own tileset base was also
      re-tested but genuinely inconclusive -- left unchanged, honestly
      flagged as a separate open question. 2 new regression tests lock
      the formula down; full suite 562/562 green. See `events.md`'s
      own dated entry for the complete disassembly/trace.
      **startRoom AND fourthRoom CONFIRMED ON THE 8x8 WORLD-MAP
      CATALOG, 2026-08-17, same day, direct follow-up** (direct user
      report: "Der Bossraum sowie der Raum vorm Boss sind jeweils auf
      der Weltmap... 7-4... 7-5"): decoded `mapTableBank6` records 60
      ((row=7,col=4)) and 61 ((row=7,col=5)) via the now-corrected
      `0x30000` pipeline and compared them cell-by-cell (by real ROM
      file offset, not local tile ID) against `startRoom`/`fourthRoom`'s
      own live-captured data — 316/320 (98.8%) and 216/320 (67.5%)
      exact matches respectively, both far above this project's own
      ~15-17% "coincidental tileset overlap" baseline: a real identity,
      confirmed. (7,4) sits directly west of (7,5) on the map, matching
      the already-confirmed real `fourthRoom->sixthRoom`(=`startRoom`)
      exit direction — independent corroboration. A 10-record neighbor
      sweep found no further identity matches (user-confirmed: "die
      anderen räume sind nicht auf der weltmap") — `startRoom.
      worldMapCatalogRecord`/`fourthRoom.worldMapCatalogRecord` added to
      `rom_profiles.lua`. **What this changes**: these two rooms were
      previously flagged as isolated/disconnected (see the Room-System
      graph's "⚠ isoliert" badge on `startRoom`) — they are now known to
      be genuine entries in the real ROM's own world-map catalog, not
      hand-authored fabrications. Still an open question whether any of
      the surrounding 382 catalog records connect to anything else this
      project has live-confirmed; this is the second (after willyRoom)
      concrete data point. See `events.md`'s own dated entry for the
      complete trace, including the comparison-script bug hit and fixed
      along the way.
      **seventhRoom REPLACED WITH THE REAL WORLD-MAP LANDING SPOT,
      2026-08-17, same day, direct follow-up** ("und ja nach dem
      zweiten boss nachdem sich das tor geöffnet hat und der player
      durchgegangen ist kommt er auf der kleinen weltmap an 6.3 raus"):
      `seventhRoom` used to be a pure heuristic pick (bank5 record 220,
      "reasonable walkable %", no spatial basis) — replaced with the
      real bank6 world-map record 51, (row=6,col=3), decoded via the
      same corrected pipeline: a coherent outdoor scene (castle-wall
      exterior, trees, open path) sharing exact wall/floor file offsets
      with `fourthRoom`'s own already-classified tiles. Only 17.5%
      overlap against the old data — confirms a genuinely different
      room, not a re-derivation. Honest limit: no independent live-VRAM
      cross-check exists for this one (unlike startRoom/fourthRoom's
      98.8%/67.5%) — rests on the user's direct testimony + a coherent
      decode. Cascading retraction: the old `seventhRoom->eighthRoom`
      exit was byte-matched against the now-replaced data, so it no
      longer holds — removed rather than left stale; `eighthRoom`'s own
      data and its independent exit into `ninthRoom` are untouched, just
      no longer reachable from the known chain. Also fixed the SAME
      pass: `startRoom`'s own Room-System display was showing a plain
      amber "isoliert" badge despite already being known (same session)
      as byte-identical to the connected `sixthRoom` — added the
      reciprocal `sameRomIdentityAs` and reordered the website's own
      border-priority so the stronger same-identity finding wins the
      primary visual slot. `seventh_room_test.lua` rewritten,
      `map_tile_catalog_test.lua` numbers updated (300 entries, bank12
      187). 564/564 tests pass, Playwright-verified live.
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
      **UPDATE 2026-08-16 (room connectivity + landing position, both
      CLOSED for wipe-style cut transitions)**: a live hardware
      watchpoint on WRAM `$C244`/`$C245` found the real record format
      -- a 186-record, bank-14 table (`CutTransitionTable.lua`) that
      encodes BOTH the target room selector AND the real landing tile
      in one place, generalized via static byte-pattern search to 82
      genuinely distinct real transitions (36 targeting the
      long-mysterious `unknownRoomA` family -- real intended content,
      not dead data). Shipped in the app (`TransitionExplorer.lua`,
      F10) and the website (`Raum-Übergänge` tab). Honest scope: only
      2 of the 82 have a known in-game trigger; the other 80's real
      story/dialog trigger is still unknown (time-boxed live search
      found nothing new).
      **UPDATE 2026-08-16 (same day, "unknownRoomA-Trigger erneut
      suchen"): a new, static strategy enumerated ALL 5 real
      `CALL $026DC` sites in the whole ROM** (previously only 1 was
      known) and fully decoded each one's own real roomSelector
      source -- 3 hardcode the unrelated placeholder value 7, 1 is the
      already-known register-C path behind the 2 live transitions
      (confirmed reached only via the already-documented `$413C`
      computed jump table, never a literal call), and 1 NEW site reads
      the CURRENTLY ACTIVE room's own real `$C3F5` state (a
      "return-to-current-room-after-dialogue" utility, not a room-
      selector). This DECISIVELY RULES OUT a hidden static dispatch
      table as the missing mechanism -- the real remaining path to
      `unknownRoomA` is finding WHICH of the 1357 real scripts
      literally contains one of the 36 already-catalogued landing byte
      sequences in its own body, likely blocked on whole-corpus-scan
      opcode coverage or live story progression, not a further static
      search.
      **UPDATE 2026-08-16 (NPC placement mechanism, direct
      continuation, "NPC-Platzierungstabelle suchen")**: the first
      concrete, live-traced mechanism behind this milestone's own
      "PRNG-placed" note above. A real chain (bank 3): a proximity
      check calls the already-known combat PRNG (`$2B1E`) to compute an
      index into a REAL 24-byte-stride table (bank 3, CPU `0x5f5a`),
      whose record embeds a pointer to a SECOND 24-byte sub-record of
      small, tile-ID-shaped bytes, before finally calling the
      already-known `$0A74` entity allocator
      (`ActorDefinitionTable.lua`). The two live-captured indices (99,
      121) produce sub-records whose every varying byte differs by
      EXACTLY `+0x20` -- a byte-exact match, via a totally independent
      method, to this project's own already-confirmed "characterB's
      OAM tile IDs are characterA's own `+0x20`" fact. Honest scope:
      this is NOT a static per-room placement table -- the index is
      computed at runtime (RNG-influenced), which is exactly why no
      such table was ever found by static search alone; the full
      24-byte record semantics remain undecoded.
      **UPDATE 2026-08-16 (same day, "Tabelle voll ausmessen")**: the
      table's real total extent is now MEASURED, not undecoded --
      exactly 218 records (indices 0-217), 5 of them anomalous
      (bank-0-pointing, not the normal bank-3 window). Shipped as a
      new "Akteur-Tabelle" website tab (all 218 rows, filterable) and
      `ActorDefinitionTable.scanTable`. Still open: the 24-byte field
      semantics beyond the 2 already-decoded fields, and the exact
      RNG-roll -> index derivation.
      **UPDATE 2026-08-16 (same day, "alles konsolidieren ... in app
      und website einbauen")**: app parity shipped -- new
      `ActorExplorer.lua` (F11 from `Field`), matching
      `TransitionExplorer.lua`'s own precedent exactly. A real
      overflow bug (long `LIVE_CONFIRMED` labels + control text
      exceeding the native 160px canvas) caught and fixed via actual
      `love .` screenshots, not guessed.

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
      angetan, Julius?"* (name corrected 2026-08-17; see below).
      **UPDATE (2026-08-17)**: the real ROM digraph lookup table itself
      was found by disassembly (ROM `$3F3F`) and used to resolve
      almost all of the previously-open range, including both bytes
      this paragraph used to call genuinely contradictory (`0x82`="me",
      `0x63`="ng") and 20 more previously-unmapped bytes (`0x27`,
      `0x70`-`0x7F`, punctuation tiles `0x71`-`0x74` identified by
      direct font-tile-bitmap inspection). One real, disassembly-
      confirmed conflict against a strong 25+-occurrence dynamic
      finding surfaced along the way: `0x5B` really decodes to "us",
      not "a" — the character previously read as "Julia" is really
      "Julius" (independently corroborated by `namedCharacters`'s own
      pre-existing "wird König", grammatically masculine, description
      of that same character). See
      `docs/reverse-engineering/text.md`'s own "FOUND: the real
      digraph lookup table" and follow-up sections for the full
      evidence trail. Still genuinely open: ~30 low-frequency byte
      values remain unmapped (real, bounded); the single-letter-code
      question (does a technically-encoded 2nd character actually
      render for `0x30`/`0x3D`/`0x43`/`0x5E`/`0x60`?) needs a live
      trace this pass's own injection attempt couldn't cleanly settle;
      still no general word-wrap/hyphenation (hand-wrapped strings
      throughout
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
      **UPDATE 2026-08-16 (direct user instruction, "es soll alles
      komplett über den interpreter laufen"): the real interpreter now
      drives ACTUAL, VISIBLE GAMEPLAY for the first time** — not
      another opt-in shadow run. A live single-step trace (native
      mGBA, PC watchpoint on `$11B7`, opcode `0xF4`'s real handler)
      found the real entry point for the thirdRoom→fourthRoom cut
      transition (bank 14, `$42F6`) and, decisively, that the real
      `$413C` step automaton reaches its FIRST real peek
      (roomSelector/subIndexByte) via genuine top-level script
      dispatch, but its SECOND (the landing tile) via the automaton's
      own internal jump, NOT top-level dispatch — a lower-level
      mechanism this project's `ScriptRuntime` doesn't model yet. New
      `CutTransitionInterpreter.lua` (modeled on `BossSequenceInterpreter
      .lua`) now genuinely, live-captures roomSelector for this one
      transition and cross-checks it (fails loudly on any mismatch or
      missing capture) — `VictorySequence.lua`'s own `switchToTargetRoom`
      wires this in UNGATED (not behind `MYSTICQUEST_SCRIPT_INTERPRETER`).
      Honest scope: only 1 of ~186 known real landing records has a
      live-confirmed entry point, and only ITS OWN room-selection half
      is interpreter-driven — the landing position stays the pre-baked,
      already ROM-table-verified constant. Live-verified via `love .`:
      zero regression (real gameplay path reaches fourthRoom at the
      exact same real position as before), 4 new tests. See events.md's
      own dated entry for the full live-trace evidence.
      **UPDATE 2026-08-16, discovered while updating README.md/roadmap
      numbers against `rom-inspector`'s live-generated data (this
      project's own docs had quietly drifted out of date, not a new
      finding from fresh reverse-engineering): opcode classification
      for the primary 256-entry table is now COMPLETE.** 201 of 256
      values have a real, tested Lua handler (`status = "decoded"`,
      checked by actually building a `ScriptRuntime` and confirming a
      handler is registered — never hand-classified), 49 more are
      confirmed real no-ops (`status = "default"`), and the remaining
      6 are `status = "known-hard"` — traced to a real, understood ROM
      mechanism but deliberately left unwired because each one's own
      real effect depends on a live player-entity/OAM simulation this
      project doesn't have (the `$02AB` "player facing byte" family:
      `0x0E73`/`0x0E77`/`0x0E7B`/`0x01C1`/`0x15FB`, plus `0x0EB2`'s own
      `$D499`-driven entity-lifecycle state machine gated on the
      untraced `$52CD` sub-table). **This means 0 opcode VALUES are
      genuinely undecoded any more** — a real milestone this project's
      own roadmap/README hadn't caught up with (both still said
      "187/256" and "133/256" respectively going into this session).
      Important honest caveat this number does NOT claim: "0 undecoded"
      is about classification completeness, not gameplay completeness
      — most "decoded" opcodes have only ever been exercised within the
      one boss-defeat script and the one live-wired room transition;
      running the interpreter against a genuinely new script would very
      plausibly still surface a real gap in how a decoded handler
      behaves outside the narrow context it's been tested in so far.
      The whole-corpus shadow-run number moved with it: `clean` is now
      883/1357 (up from 871), `haltUndecoded` correspondingly down.
      **UPDATE 2026-08-16, continuation ("was als nächstes" -> the
      best-prepared remaining candidate): a SECOND real "cut" transition
      now runs through the real interpreter.** Same live methodology as
      thirdRoom->fourthRoom above, applied to fourthRoom->fifthRoom: 79
      real `$11B7` hits, all bank 14, same 3-peek/only-first-is-
      top-level-dispatch shape, decisively confirmed via the same
      preceding-byte check (entry point: bank 14, `$4C84`). Two
      independent cross-checks agreed: the peeked `(16,2)` landing tile
      matches the already-known static record, and a live `$026DC` PC
      watch resolved fifthRoom's own previously-ambiguous
      `romRoomSelectors={2,3,4,5,6}` down to the real, confirmed `4` --
      byte-identical to the peeked roomSelector. No `VictorySequence.lua`
      code changes were needed (`beginTransition`/`switchToTargetRoom`
      were already written generically against
      `exit.scriptEntry.transitionKey`) -- purely a `rom_profiles.lua`
      data addition plus 3 new tests. Live-verified via `love .` both as
      a dev-teleport and via the FULL real button-hold trigger (reaches
      fifthRoom at frame 290, exact real landing position). See
      events.md's own dated entry for the full trace. Now 2 of ~186
      known real landing records are interpreter-driven; scope
      otherwise unchanged from the statement above.
      **UPDATE 2026-08-16, continuation ("decode all missing opcodes"):
      the 6 remaining known-hard opcodes are now CONFIRMED, not just
      suspected, to be architecturally blocked.** 5 of the 6
      (`0x8A`/`0xA4`/`0xEC`/`0xED`/`0xEE`) already had a decisive
      characterization on file: each needs the real `$C3FE`/`$C3FF`
      cross-actor pointer's value, which is genuinely different LIVE
      runtime state for each of 132 real affected scripts, not
      derivable from ROM bytes. The 6th (`0xBA`) looked more tractable
      (a real, bounded `$52CD` jump table, not per-script state) --
      found the 34 real scripts that hit it (all bank 8/9, none with a
      known live trigger) and attempted the SAME single-instruction
      injection technique an earlier pass (task #150) already built for
      a different goal (reaching unreached dialogue text). Result: the
      injection technically worked for a few real steps (confirmed
      register-level, not just hoped) but got evicted by the exact same
      bank-call-stack-eviction mechanism task #150 already found -- new,
      concrete confirmation that this blocker is GENERAL, not specific
      to dialogue text. Closing any of the 6 needs a substantially
      bigger "puppeteering" driver (sustained, multi-level-stack-aware
      re-injection), not more disassembly or a narrower live experiment.
      See events.md's own dated entry for the full trace.

- [~] **Milestone 8 — Menu/inventory/equipment.** Data Crystal's US RAM
      map cross-checked live and matches with zero offset (HP/MP/level/
      gold/stats/atk-def/name buffers). Real `Stats`/`Inventory` data
      models; the real in-game menu (`Dinge`/`Magie`/`Waffe`/`Frage`)
      renders real decoded item/weapon/spell names (`ItemTable.lua`/
      `WeaponTable.lua`, VERIFIED against live ROM bytes, including the
      live-cross-checked "Breit" weapon name).
      **UPDATE 2026-08-16 (direct user selection, "Item/Ausrüstung
      nutzbar machen"): items and equipment are now real, usable
      gameplay, not just a static readout.** `Inventory.lua` gained
      `heldWeapons` (a real "what this character actually owns" list,
      seeded with the real starting weapon — `equip()` now correctly
      requires a weapon be held first, rather than accepting any
      catalog name), `addWeapon()`, and `useItem()` (consumes a held
      consumable item — HONEST SCOPE: applies no numeric effect, since
      `ItemTable.lua`'s own doc comment already states the likely
      heal-amount/effect bytes aren't decoded — this project has no
      real formula to apply without fabricating one). `Menu.lua`'s
      `Dinge`/`Waffe` options now open a real sub-list (reusing the
      same box/cursor convention as the main menu) when their real
      list is non-empty; selecting an item uses it, selecting a weapon
      equips it. The real, VERIFIED empty-inventory behavior (every
      option closes the menu) is UNCHANGED and still exactly
      reproduced for a fresh, un-modified game — no real ROM trigger
      for granting items has ever been found (see combat.md's own
      "Real equip-swap test attempted, blocked" entry), so `Field.lua`
      gained a new F12 dev-only shortcut (matching the established
      F8-F11 "real content, no fabricated trigger" precedent) that
      grants a few real catalog items/weapons purely to make the new
      interactivity reachable and testable. A real, previously-
      invisible layout bug (the sub-list's own label ran off the top
      of the native 160x144 canvas) was caught and fixed via an actual
      `love .` screenshot, not guessed. 5 new/updated `Inventory.lua`
      tests; live-verified via 6 real screenshots (`MYSTICQUEST_MENU_
      DEMO=1`, a new dev-only shortcut skipping the fragile-to-script
      full Boot->Intro->NameEntry->BattleIntro flow): empty state
      unchanged, granting works, the Dinge submenu opens and an item
      use correctly consumes it and returns to the main menu, the
      Waffe submenu shows both held weapons, and equipping a different
      one updates the real equipped-weapon readout. **Remaining:**
      weapon/item stat-byte fields still UNKNOWN (no real value to
      compare a formula against yet — same open item as combat.md's
      own `$3DF4`/table-semantics follow-up); whether equipping a
      different weapon changes real combat damage is honestly still
      open (see combat.md's own MAJOR CORRECTION entry).
      **UPDATE 2026-08-17**: the "weapon stat-byte fields UNKNOWN" gap
      above is now partially closed for POWER/PRICE specifically —
      `WeaponStatTable.lua` (a real, SEPARATE table, file `0xA1FD`)
      found via external-reference byte matching against the US
      cartridge's own public disassembly, all 16 weapons confirmed
      byte-for-byte, cross-checked again independently against a real
      walkthrough capture. Wired into `Inventory.lua` as its own
      `weaponStatCatalog` (deliberately NOT merged per-weapon into the
      existing name catalog — the two tables' real row-order
      correspondence isn't confirmed, a genuine open sub-question, not
      glossed over). Real combat-damage-per-weapon still open.

- [~] **Milestone 9 — Combat.** Real-time contact/action combat,
      confirmed (not a separate turn-based battle mode). **The real
      damage formula (`$50AC`) is now fully decoded and wired into
      actual gameplay** (2026-08-10): `base = max(0,ATK-DEF)+1`,
      `damage = floor(noiseByte*base/1024)+base`, with a bit-exact
      ported real PRNG (`$2B1E`, cross-checked byte-for-byte against a
      live ROM trace) and the real enemy ATK (8, code- and live-
      confirmed). Real attack visuals (swing/thrust, hit-flash), real
      knockback + invincibility flicker (with a 2026-08-10 fix: no
      longer ignores wall collision).
      **UPDATE 2026-08-16 (MAJOR CORRECTION, direct user request to
      try a fresh angle -- "ob die Waffe selbst einen variablen
      Schadenswert beiträgt"): the player-attacks-enemy direction is
      real, PRNG-driven, and fully traced end to end** -- it uses the
      SAME real combat PRNG (`$2B1E`) and the SAME
      `floor(noise*base/1024)+base` formula shape as `$50AC`, with a
      real base value (`4`, read from a real bank-4 ROM table plus
      WRAM `$CF63`). The prior "flat, no formula" conclusion (5 leads
      chased and closed) correctly found no enemy-side DEF term, but
      never reached this machinery -- its output is numerically
      indistinguishable from a flat constant here only because
      `255*4=1020 < 1024`, so the noise term floors to 0 for every
      possible roll at this specific base (the exact same coincidence
      already known for the enemy formula's own base=3 case). See
      combat.md's own dated "MAJOR CORRECTION" entry for the full
      disassembly. **Remaining:** whether the base value is genuinely
      weapon-power (untestable — only one weapon exists) or a fixed
      per-attack-type constant; no weapon-power TABLE wired into the
      Lua implementation (the value 4 stays hardcoded, now with a
      correct explanation instead of an incomplete one); no magic/
      spell casting at all despite a real MP stat existing; and,
      starkly, exactly ONE enemy exists in the whole game today — see
      the new Bestiary entry below.

- [~] **Audio.** Format DECODED (2026-08-15, task #6/P7, direct user
      request). Driver location VERIFIED (100% of sound-hardware-
      register writes during boot + title music traced to ROM bank
      15) since 2026-08-08; this pass added the real song table (30
      songs, file `0x3CA12`), the real per-channel event-stream format
      (note/duration/octave encoding, 13 real driver commands, all
      operand lengths confirmed), the real frequency table
      (CPU `$41A0`, ready-to-write GB hardware register pairs), and a
      real, working decoder (`tools/rom/decode_music.py`) that
      produces genuinely coherent, singable music transcripts as
      decisive proof. See rom-map.md's own "Audio format — DECODED"
      section for the full disassembly trail.
      **UPDATE 2026-08-16 (task #151, "port the decoded music format
      into src/audio/ + love.audio playback"): DONE.** Real
      `src/audio/` module (`GBSquareSynth`/`MusicScore`/`MusicPlayer`)
      actually plays all 30 real songs through `love.audio`, plus a
      dev-only `MusicJukebox.lua` browser (F9 from `Field`). Still
      open: the auxiliary vibrato/pitch-delta layer, a few commands'
      exact musical intent, and no known real ROM trigger ties a
      specific song to a specific real game moment (`MusicJukebox`
      stays dev-only for that reason) -- format AND playback are no
      longer the blocker; only "which song plays when" is.

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
      **UPDATE 2026-08-16 ("World scope: weitere Räume erschließen"):
      fifthRoom flood-filled live (8 real probes: all 4 directions from
      the landing spot + 2 reached corners) -- exactly ONE real
      connection exists (the already-known, bidirectional link back to
      fourthRoom); every other wall is a genuine dead end, zero new
      tile-source-pointer changes anywhere. sixthRoom's other 3
      directions (UP/DOWN/RIGHT) re-checked too, reconfirming its own
      already-closed 2026-08-14 finding (one continuous fourthRoom
      canvas, no real cut). New reusable `fifth_room_free()`/
      `sixth_room_free()` checkpoints shipped (`tools/rom/
      checkpoints.py`) -- neither existed before despite both rooms
      being wired since 2026-08-13. Honest conclusion: this session's
      earlier `CutTransitionTable` finding (80 real, ROM-decoded
      transitions with no known in-game trigger, 36 to `unknownRoomA`)
      remains the real, larger opportunity for "more rooms" -- not
      further walls of these 2 already-fully-explored leaf rooms.

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

- [x] **NEW — Magic/spell system.** SUPERSEDED 2026-08-19 -- see the
      "Priority order" table's own P2 row above for the current,
      accurate status: which record is which spell + its real MP cost
      + the deduction code are CLOSED; the full field/menu effect-
      dispatch chain is mapped; `Magie` is now a real, browsable
      sub-menu in `Menu.lua`. Still open: the real battle-context
      spell-effect code, and a real spell-learning trigger.

- [ ] **NEW — Level/XP system.** `Stats.level` is real (Data Crystal
      cross-check, `$D7BA`) but read-only today — no XP gain, no
      level-up logic, no stat growth curve decoded.
      **CORRECTED 2026-08-16 (direct user selection, "Level/XP-
      System" — the claim below this line used to say "well-scoped,"
      that was stale)**: the `experience` WRAM address this entry
      used to cite (`$D7BB`-`$D7BD`) was only ever weakly "plausible"
      (a fresh character's all-zero state proves nothing distinctive)
      and this SAME session already, independently, decisively
      re-identified that exact address as the real 24-bit GOLD counter
      (see events.md's own dated entry). **There is currently NO known
      real WRAM address for experience.** 2 real search angles this
      session (a live snapshot-diff across the one real, reachable
      fight; a static search for a sibling "word-counter" opcode
      targeting a different cell) both came back genuinely negative —
      see events.md's own dated entry for the full trace. Building
      this feature now would mean fabricating both the WRAM location
      and the growth formula — explicitly not done. Real, well-scoped
      next steps for whoever continues: (a) find a real spawn trigger
      for one of the other 10 enemy species first (this project's own
      Bestiary blocker) to get a second, non-tutorial fight to test
      against; (b) trace deeper into the interpreter-reachable
      boss-defeat script for a not-yet-modeled reward branch.

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
      **UPDATE 2026-08-17** (direct user instruction, "in app und
      website einbauen"): re-ran the export after this whole session's
      text-decode/name-correction/new-table work — `story.js`
      automatically picked up the `Julia`->`Julius` correction and
      every new digraph decode with zero manual edits (confirms the
      "auto-generated, re-run don't hand-edit" design actually holds
      up). Also EXTENDED the exporter and the site's own Monster-/
      Items-pages with the two new real tables found this session:
      `EnemyStatTable` (21 named bosses, own `Bosse` section on the
      Monster page) and `WeaponStatTable` (16 weapons' real power/
      price, own `Waffen-Stats` tab on the Items page) — both kept
      visibly SEPARATE from the existing name catalogs, same honesty
      stance as the Lua side. Live-verified via a headless-Chrome DOM
      dump (not just "the JS has no syntax errors") that both new
      sections render real data and that the story page shows
      "Julius", not "Julia", anywhere.
      **UPDATE 2026-08-17, later same day** (direct user requests, in
      order): (1) rewrote the Room-System graph to render real,
      live-decoded room-map thumbnails instead of generic boxes, with
      connection arrows anchored at each exit's real, empirically-
      bracketed trigger zone and real landing point (both newly
      exported from `rom_profiles.lua`'s own `exits[].zone`/
      `landingX`/`landingY`) instead of a generic node-edge midpoint —
      root-caused and fixed a real render bug along the way (a leftover
      CSS rule from the old single-`<svg>`-graph design was painting an
      opaque background over the new HTML node cards; DOM/layout/hit-
      testing were correct the whole time, only the paint layer was
      wrong). (2) Added Google-Maps-style pan/zoom to the same graph
      (reusing `js/viz/worldmap.js`'s own established Pointer-Events
      convention). (3) Added `startRoom` (the real first-boss-fight
      room) as its own honestly-disconnected node, previously silently
      omitted because the exporter only ever included rooms with a
      live-traced `exits` field. (4) Live re-traced and fixed a real,
      live-gameplay-affecting bug in `secondRoom`'s own `landingX`
      (was 80 — the room's visual middle, actually a methodology
      artifact from a checkpoint script that over-walks after the real
      scroll settles — corrected to the real, code-verified 0, the
      door threshold) — CODE-verified via a live `Watcher`+`CallTracer`
      write-watchpoint trace, not just re-measured. (5) Confirmed a
      direct user claim that `fifthRoom` is real ROM-wise the SAME room
      as willyRoom/secondRoom/thirdRoom (byte-identical `$D392`/
      `$D393`/`$C3F0`/`$C3F5`), now surfaced on the graph as a violet-
      bordered node with a real cross-reference badge/tooltip. (6) Same
      for `sixthRoom`=`startRoom`/`fourthRoom` — this one also caught
      and fixed a real capture bug (raw VRAM read never SCX-corrected)
      and a stale, wrong `romRoomSelectors` claim. (7) Investigated
      then FULLY RESOLVED (not just flagged) a direct user report that
      `seventhRoom`/`eighthRoom`/`ninthRoom`'s own tileset was wrong —
      found and closed a previously-open item in `rom-map.md` (the
      real VRAM tile-copy pipeline, `$01AF3`->...->`$2D57`, exact-
      matched against willyRoom's own known pixel), which turned up a
      genuine bug affecting the ENTIRE 384-room catalog's own tileset
      base, not just the 3 reported rooms — corrected, re-rendered
      (generic reused dungeon corridors -> real, distinct outdoor
      scenes), 2 new regression tests added. All 7 re-exported/re-
      verified live via Playwright screenshots against a real loaded
      ROM; 562/562 Lua tests green throughout.

- [~] **"Voll interpretierte Version" (task list, 2026-08-15).**
      5-item priority list toward a real dialogue swap-over for the
      boss-defeat sequence: (1) real `isTextboxDone` — DONE, see
      `events.md`'s own dated entry: found the real dialogue text is
      embedded inline in the script stream (not messageID-resolved),
      built a real character-count pacer, disproved a plausible-looking
      player-input gate with direct live evidence, removed it. Tested
      live twice (with and without simulated input) — **both converge
      on the exact same cursor (`0x4798`, stuck on opcode `0x00`) the
      ORIGINAL unpaced version reached**, proving the pacing bug was
      NOT the cause of the desync from the real ROM's own path — a
      genuinely separate, still-unlocated cursor-consumption bug exists
      somewhere between the CHAIN landing and this point. (2) decode
      opcodes `0xBC`/`0xBD` — not started (real ROM confirmed to reach
      them; this project's software doesn't get that far yet). (3)
      bridge interpreter → phase machine, (4) name-insertion control
      byte, (5) TextDecoder digraph gaps — not started.

      **Same-day continuation, root cause of the `0x4798` desync FOUND**
      (static disassembly, `tools/rom/disasm.py`): opcode `0x04`'s real
      handler (`$333D`) is NOT the "no operand bytes" tick this project
      always modeled it as — it's a genuine per-byte TEXT CLASSIFIER
      that reads the byte right after itself and dispatches via real
      thresholds (`$3356`/`$3480`/`$34A4`) into a real jump table at
      `$38F6`. Byte `0x00` inside this classifier means "text run done,
      recursively re-fetch the next real opcode" — a DIFFERENT real
      meaning than opcode `0x00`'s own top-level `QUEUE_GATE` semantics.
      This project's software, lacking this model, reads a stray `0x00`
      byte as a genuine top-level opcode dispatch instead, which then
      pops a real, legitimately-queued-but-stale CHAIN "resume" entry
      (opcode `0x02`'s own real, confirmed `$36DF` push) and redirects
      the cursor back near the original bank-13 CHAIN site — exactly
      matching `0x4798`. This single finding directly SUPERSEDES the
      original list's items 2 (`0xBC`/`0xBD`) and 4 (name-insertion
      `[0x14]` byte) — both are almost certainly entries in this SAME
      real `$38F6` jump table, not separate mechanisms. Real, substantial,
      well-scoped next step: decode `$38F6`'s own real entry table. Not
      attempted this pass (a genuine new reverse-engineering task, not a
      quick fix) — precisely located and documented instead of guessed
      at. 437/437 tests pass throughout every step of this whole
      investigation; zero regression to the hand-authored, currently-
      authoritative `self.pages` dialogue.

      **Same-day continuation, `$38F6` decoded**: all 16 real table
      slots disassembled (`tools/rom/disasm.py`) — the BIG reframing
      find is that this is NOT a new mechanism at all: it's the SAME
      real "multi-line textbox driver" this project's own much earlier
      "0xFF sub-table" investigation (see events.md, several sessions
      ago) already disassembled in full, just never connected to opcode
      `0x04`'s own dispatch. `$36D0` (the shared "continue" call several
      table entries reach) is exactly the self-rearm site this session's
      own live watchpoint trace already found at `$36DB`. Bytes `0x14`/
      `0x15` are the real NAME-INSERTION mechanism (two distinct real
      WRAM string-pointer slots) — very likely the mechanism behind the
      long-flagged, never-decoded `[0x14]`-style speaker tag. Bytes
      `0x1C`-`0x1F` are LITERALLY the same real code the earlier 0xFF
      sub-table work already named a "cursor-delta dispatcher" (real up/
      down/left/right text-cursor moves). Byte `0x1A` matches
      `TextDecoder.lua`'s own, completely independently-derived
      `NEWLINE_BYTE = 0x1A` exactly — a decisive cross-validation from
      two unrelated investigation paths. New HYPOTHESIS-status doc
      comments added to `TextDecoder.lua` for the whole `0x10`-`0x1F`
      family (informational only, not wired into the decode path).
      **Honest, well-scoped remaining work**: build a byte-exact Lua
      port of this UNIFIED system (opcode `0x04`'s 16-entry table + the
      already-documented `0xFF` 11-entry sub-table + their shared real
      WRAM cells), replacing the current "outer behavior approximation"
      `StandardScriptHandlers.tick`/`.textboxWait`/`.startTextboxWait`
      use — a genuine, substantial, multi-session undertaking, not
      attempted this pass. No code changed this pass (pure disassembly/
      documentation); 437/437 tests unaffected.

      **Same-day continuation, real code change shipped**: `opcode 0x04`
      rewritten as a genuine byte-exact classifier
      (`StandardScriptHandlers.tick`), matching `$333D`'s real
      disassembly exactly (terminator/control-code/text-character
      branches). The one remaining gap was precisely narrowed to the
      real `$36D0` "consume one more byte, re-enter the classifier"
      bridge, gated on real WRAM `$D853` bit 7 for control byte `0x11`.

      **Same-day continuation, the desync mystery is FULLY, DECISIVELY
      RESOLVED**: a live mGBA write-watchpoint trace of `$D853` bit 7
      found the exact real timing (SET on entry, stays set for 9 real
      frames total, clears exactly when the real cursor advances) —
      confirmed the flag is a real "still pacing" signal, not a guess.
      `ctx.onControlCode`'s contract extended to support both pacing
      (return `false`/`nil`) and the real extra-byte bridge (return a
      number of extra real bytes to consume); `VictorySequence.lua`
      wires the real, live-confirmed `CONTROL_CODE_0X11_REAL_TICKS = 9`
      behavior for control byte `0x11`. Re-ran the headless cursor probe:
      the interpreter's cursor now tracks the real ROM byte-for-byte all
      the way to `bank=14 cursor=0x61d8`, correctly dispatching real
      opcode `0xC0` (HEAL_LP, an exact match to the live-traced ROM),
      then HONESTLY stops on the real, already-known-undecoded opcode
      `0xBD` — the correct, expected boundary, not a new mystery. Item
      (1) of the 5-item list is DONE; the desync that blocked it for the
      whole day is closed. Items (2) `0xBC`/`0xBD` and (4) name-insertion
      are now clearly scoped, reachable next steps (no longer blocked by
      an unrelated cursor bug); (3) interpreter→phase-machine bridging
      and (5) TextDecoder digraph gaps remain not started. New
      regression test locks in the resolved trajectory
      (`boss_sequence_interpreter_test.lua`); 442/442 tests pass.

      **Same-day continuation, "Interpreter->Phasenmaschine-Brücke
      bauen"**: reversed the 2026-08-14 "genuinely known-hard" call on
      opcodes `0xBC`/`0xBD`/`0xBE` (palette-fade family) -- fresh
      disassembly of their shared leaf `$1142` found a small, fully
      real, deterministic 6x11=66-tick pacing gate (same kind of
      mechanism as the already-modeled control-byte-`0x11` pacing, not
      a dead end). All 3 wired (`StandardScriptHandlers.paletteFadeCycle`,
      `ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BC/BD/BE`,
      `ScriptRuntime.lua` registration) -- the interpreter now correctly
      dispatches `0xBD` all 66 real times and continues into real opcode
      `0xF3`, genuine forward progress past the previous entry's own
      honest stopping point. **But a NEW, real, precisely-identified gap
      surfaces immediately after**: `0xF3`'s own real handler
      unconditionally calls a real `$1ED7` selector-`0x10` dispatch this
      project's existing `.peekTwoByteGate` doesn't model, causing the
      two peeked bytes to misdispatch as top-level opcodes and converge
      back on the SAME historical `0x4798` landing spot via a DIFFERENT
      root cause than before. Not yet reaching the real literal text at
      `0x61e5`. Honest, well-scoped next step: disassemble `$1ED7`
      selector `0x10`. 446/446 tests pass (regression test updated to
      assert the new, real, further-but-incomplete trajectory).

      **Same-day continuation**: `$1ED7` selector `0x10` disassembled
      and WIRED (`StandardScriptHandlers.paletteFadeCompletionGate`,
      a real 6-phase state machine gated on the already-modeled
      `$C8E0`/`$CEE8` dual gate) -- opcode `0xF3` now genuinely paces
      for 6 real ticks (verified) instead of releasing instantly. Still
      converges on the same `0x4798` landing spot, though -- traced the
      exact divergence to 4 single-byte "opcodes" dispatching cleanly
      right after `0xF3` releases, strongly suggesting one of the
      state machine's own 2 untraced sub-calls (phase 2/4, several
      routines into bank-2-delegated code) ALSO advances the real
      script cursor internally, which this pass's model doesn't
      account for. Three layers deep now -- an open-ended sub-
      investigation, not attempted further this pass. 451/451 tests
      pass, zero regressions; real, verified, standalone progress
      (both new mechanisms are individually correct and tested) even
      though the ultimate goal isn't reached yet.

      **Same-day continuation, task #126 CLOSED**: the "3 layers deep"
      sub-call theory above was a red herring -- a fresh live mGBA
      single-step trace (native breakpoints found silently
      non-functional and abandoned in favor of direct `cpu.pc`
      checking after every `core.step()`; ~1.6M steps/sec, so a
      multi-thousand-frame full trace runs in seconds) plus a direct
      read of the real ROM bytes at cursor `0x61d8` (bank 14, file
      offset `0x3a1d8`: `bd f3 0f 55 14 00 bc f0 ...`) proved the real
      root cause is much simpler: **`0xF3`'s real total instruction is
      5 bytes**, not a net-zero 2-byte peek -- it consumes 2 further
      real bytes on release beyond the 2 peeked ones (confirmed via
      disassembly of its real release trampoline at `$11de`). Fixed by
      adding an `extraBytesOnRelease` parameter to `.peekTwoByteGate`
      (default `0`, so `0xF4` is unaffected), wired to `2` for `0xF3`
      specifically. Verified decisively: the interpreter now tracks the
      real ROM cursor byte-for-byte straight through `0xBC` at `0x61de`
      and beyond, past the OLD `0x4798` desync entirely (gone for
      good), reaching real cursor `0x61f9` before honestly stopping on
      real opcode `0xed` (real ROM handler `$0e77`) -- the run going
      FURTHER and hitting a real, honest boundary is exactly the proof
      the fix is correct. 460/460 tests pass, zero regressions (the
      pre-existing regression test's own stale `0x4798`-convergence
      expectation was updated to the new, further, correct trajectory).

      **SELF-CORRECTION, same day ("weiter"):** this entry originally
      called `0xed`/`$0e77` "genuinely new" and proposed disassembling
      it next -- WRONG. `ScriptOpcodeTable.lua`'s own existing doc
      comments (2026-08-14) already fully disassembled it as the THIRD
      confirmed sibling of the already-known-hard `$02AB` family
      (alongside `0x80` and `0xEC`/`0xEE`): it dereferences the
      task-#85 cross-actor pointer then calls `$02AB` (a masked read of
      the player entity's own facing byte, itself fully understood),
      but the WRAM content staged for that dereference is genuinely
      DATA-DEPENDENT and this project has no live player-entity WRAM
      simulation to compute it -- explicitly documented as "EXPECTED to
      remain ... permanently, not a sign of unfinished work". So the
      `0xF3` fix's real, correct outcome is that the interpreter now
      tracks the real ROM losslessly all the way to the project's own
      pre-existing, permanent ceiling for this opcode family -- there
      is no further "disassemble `$0e77`" step; that's already done.
      Real further progress here needs either live player-entity WRAM
      simulation (a substantial separate undertaking) or this script
      hitting a genuinely different, still-unexplored opcode elsewhere.

      **Consolidation pass, same day ("konsolidieren, dokumentieren und
      in die app (interpretierte variante) und die website
      einbauen")**: found and fixed a real, stale website bug while
      wiring the fix in -- `export_data.lua`'s curated `KNOWN_HARD`
      table never got the 4 addresses (`0xEC`/`0xED`/`0xEE`/`0xBA`)
      this project itself already documented as "traced, deliberately
      unwired" back on 2026-08-14, so the website showed them as plain
      "undecoded" (implying unexplored) instead of the accurate
      "known-hard" (traced, deliberately deferred, real reason given).
      Also removed 2 stale notes on `0xBC`/`0xBD` left over from before
      task #125 wired them (a "decoded" badge next to a "not yet
      decoded" note is a real, visible self-contradiction). Fixed;
      Playwright-verified live (sidebar "17 offen" -> "13 offen",
      legend "known-hard 0->4", opcode `0xED`'s own detail panel shows
      the correct badge+note). App side (`CatalogExplorer.lua`,
      "interpretierte Variante") needed no code change for the fix
      itself (same real `VictorySequence.buildBossSequenceInterpreter`
      -> `ScriptRuntime.lua` path) -- added a `debugState()` (matching
      `Field`/`VictorySequence` convention, none existed before) and
      confirmed live via a scripted `love .` run + `MYSTICQUEST_WAIT_FOR`:
      the real interpreter mode reaches `bank=14 cursor=0x61f9`,
      identical to the headless trace, through the unmodified
      production code path. 462/462 tests pass.

      **Tasks #141-146, same day ("weiter arbeiten bis das spiel zu
      100% durchläuft")**: full-scope live trace mapped the ENTIRE
      remaining real script path (27 real jumps / 67 dispatches),
      ending in a genuine, live-confirmed STALL at real cursor `0x472e`
      -- likely the real, intended destination, not a bug. Found and
      fixed a real architectural gap: opcode `0x04`'s classifier needs
      to stay "pinned" as the active opcode across many real per-
      character ticks while the persistent cursor moves underneath it
      -- this project's interpreter had no way to express that,
      misdispatching raw text bytes as fresh top-level opcodes once one
      character finished (succeeding by coincidence until landing on a
      genuinely undecoded one). Shipped real opcode pinning in
      `ScriptInterpreter:step` (fully backward-compatible, 462/462
      pass), with TWO self-caught corrections along the way (a first,
      broader "pin unconditionally" attempt broke two DIFFERENT,
      already-working real dispatches once tested -- narrowed to only
      the ONE live-confirmed real occurrence). Also disassembled a
      whole 13-fragment real CHAIN cluster the classifier eventually
      reaches (`0x622c`-`0x6337`) and found EVERY opcode in it already
      decoded -- zero new opcode work needed there. **Honest net
      result**: the pinning architecture is real, tested, general-
      purpose infrastructure, but this script's own practical
      interpreter reach is UNCHANGED (`bank=14 cursor=0x61f9`, the same
      pre-existing `$02AB`-family ceiling) -- the one confirmed pin
      point gets immediately followed by another real control code
      this project hasn't traced yet. A genuine discrepancy between the
      live WRAM trace and a static byte read remains open (task #146),
      documented precisely rather than declared solved prematurely.

      **Task #146, same day, direct continuation ("ja")**: a
      fine-grained live trace (correlating each real `$36D9` hit with
      the ACTUAL classified byte, resolving the earlier discrepancy)
      found two more real control-code behaviors and fixed them:
      `0x14` (name insertion) bridges through opcode `0xFF` for exactly
      one real tick then resumes `0x04` two bytes later (modeled as an
      honest net-2-byte simplification, not a full dispatch of `0xFF`'s
      own sub-opcode-1 internals); `0x1A` (NEWLINE, already
      independently confirmed by `TextDecoder.lua`) unconditionally
      pins via `$36D0` (safe to generalize, per `$35B0`'s own
      unconditional disassembly, unlike `0x10`). With both wired, the
      interpreter tracks a real further multi-line text run and reaches
      cursor `0x6208` -- genuinely PAST the old `0x61f9` stop (462/462
      pass). **Important correction along the way**: the OLD `0x61f9`
      "permanent `$02AB`-family ceiling" claim was itself wrong -- that
      stop was a coincidental numeric collision from the SAME
      un-modeled-control-code bug class, not a real dispatch (the real
      ROM never executes `$0E77` at that cursor -- it's real text data,
      not an opcode there). The new `0x6208` stop hits the identical
      opcode value again via a NEW un-modeled control byte (`0x12`,
      bridging into `0xFF` sub-opcode 4, a real bank-2-delegated
      conditional halt at `$1ED1`/`$350F`) -- honestly flagged as
      UNCERTAIN for the exact same reason, not re-claimed as confirmed.
      Task #146 stays open; real next step is disassembling
      `$1ED1`/`$350F`.

      **Task #146 CLOSED, same day, direct continuation ("go on")**:
      `$1ED1`/`$350F` disassembled -- control byte `0x12` conditionally
      bridges into `0xFF` sub-opcode 4 via a real bank-2 function-call
      trampoline (a family this project has repeatedly found and
      deferred tracing into); a live tick-count trace found this real
      occurrence paces for exactly 156 real ticks before unconditionally
      resuming `0x04` (wired the same way as `CONTROL_CODE_0X11_REAL_
      TICKS`). This made the `0x6208` stop vanish -- as suspected, ANOTHER
      coincidental collision, this time from control byte `0x1B`
      (bridges into `0xFF` sub-opcode 2 for one real tick, same shape as
      `0x14`) -- disassembled and wired too. **With all 6 real
      control-code fixes now in place (`0x10`/`0x11`/`0x12`/`0x14`/
      `0x1A`/`0x1B`), the interpreter runs the ENTIRE remaining real
      script cleanly and reaches real cursor `0x4798` (bank 14), where it
      correctly, HONESTLY HALTS -- confirmed via a 300,000-tick headless
      run, the real production `VictorySequence` wiring, AND a live
      `love .` screenshot, all three identical.** Real byte at `0x4798`
      is `0x00` -- `QUEUE_GATE_HANDLER_ADDRESS` -- THE SAME landmark
      this entire day's investigation started from at its very
      beginning. Full circle: the interpreter now tracks the real ROM
      losslessly, byte-for-byte, from the script's own real start all
      the way to this project's own pre-existing, already-understood
      real limitation (the queue-gate needs real content pushed into
      `self.queue` by an earlier real script event this project doesn't
      yet produce -- a genuinely separate, well-scoped follow-up, not a
      new mystery). 462/462 tests pass.

- [~] **NEW -- Monster/NPC/Item catalog (2026-08-15, direct user request
      "versuche mal alle monster, npcs und items zu extrahieren").**
      Real, honestly-scoped extraction across all 3 categories, since
      they turned out to be mechanically very different in what's
      actually extractable: **Monster** -- `enemySpeciesTable`
      boundary re-confirmed (46 rows/11 species, no more real data
      past it); only 1 of 11 species has a known real sprite (no
      per-species sprite index table found near it, checked and
      documented as a real negative). **Items/weapons** -- both real
      tables turned out to extend FAR past their previously-documented
      boundaries (`itemTable` 20->59 records, `weaponTable` 20->48),
      found via the same "does a real name decode here" scan method
      already proven on `enemySpeciesTable`; also found spell records
      need a second real name offset (`ItemTable.lua`'s own doc
      comment) -- a genuine, decisive extension, not just re-
      documentation. **NPCs** -- confirmed (again) there's no static
      placement table; `NpcCatalog.lua` normalizes the 3 already-known
      NPCs (Willy, secondRoom x2) from `rom_profiles.lua`'s own
      verified scene data instead of duplicating it.
      **Website**: 3 new rom-inspector tabs (Monster/Items &amp; Waffen/
      NPCs), each honest about what's known vs. not (e.g. "Sprite
      unbekannt" badges for the 10 monster species without a known
      graphic) -- `export_data.lua` extended, live-verified via
      Playwright (all 3 tabs render, zero console errors).
      **App**: new `CatalogExplorer.lua` dev browser
      (`MYSTICQUEST_CATALOG_DEMO=1`, same pattern as `RoomExplorer
      .lua`'s own F8 shortcut) -- a "normal" mode showing the static
      catalog data, and a real "interpreter" mode that runs the
      already-built `BossSequenceInterpreter` live (via
      `VictorySequence.buildBossSequenceInterpreter`, exported so both
      callers share one real implementation) for the ONE monster this
      project has a real script for, honestly saying "kein echtes
      Skript bekannt" for every other entry rather than fabricating
      output. A live `love .` test caught and fixed a real crash (a
      field-access bug reading `m.atk` instead of `m.row.atk` on the
      grouped species records) and a real text-overlap/overflow bug
      (LÖVE's default font is far too large for the native 160x144 GB
      canvas at 1x scale -- fixed with an explicit small print scale)
      -- neither would have been caught by unit tests alone, both
      confirmed fixed via re-screenshotting. 458/458 tests pass.
      **Honest remaining scope**: 10 of 11 monster species and all
      items/weapons have no known graphic or real script -- finding
      more would need either new live OAM-tracing sessions (monsters)
      or discovering a real trigger/spawn mechanism this project
      hasn't found (items); NOT attempted further this pass, per the
      same "characterize, don't fabricate" discipline as everywhere
      else in this project.

      **Follow-up, Phase 1 (2026-08-15, direct instruction "bitte alle
      monster und npcs suchen und ... sprites mit animationsphasen ...
      und die items ... in auswählbare kategorien unterteilen")**:
      `NpcCatalog.lua`/`export_data.lua`/the website's Monster+NPC tabs
      now expose the FULL real per-direction/per-phase animation data
      (not just the resting pose) -- monster's real hardware X-flip
      toggle and secondRoom NPCs' real 4-direction/2-phase walk cycle
      are both selectable (Pose A/B pill-tabs; direction+phase
      pill-tabs), same real primitives (`NpcSprite.lua`) actual
      gameplay uses. `CatalogExplorer.lua`'s own NPC/monster views
      wired to the same real animation (A button cycles NPC facing,
      monster pose auto-toggles on a dev-browser timer). Along the way,
      caught and fixed a real, silent website bug: `drawSpriteGrid`
      only ever applied X-flip, never the real `flipY` down/up's own
      phase-2 frame uses -- generalized to a real `{x=,y=}` flip
      descriptor.

      **Follow-up, real bug found + fixed (2026-08-15, direct user
      report "die npc sprites a und b jeweils 16x16 gross sind und der
      dialog von b ist falsch", live re-verified via a fresh mGBA OAM
      trace, NOT taken on faith either way)**: secondRoom's
      `characterA`/`characterB` are real 16x16 (2x2-tile, 4-tile)
      sprites -- this project's own 2026-08-10 "single 8x16-OBJ-mode
      column" finding was wrong (it only ever captured the physically-
      upper tile of each of the 2 real side-by-side OAM entries,
      silently dropping the entire bottom row). Real fix, cross-
      validated against 2 independent fresh live captures with zero
      discrepancy: `rom_profiles.lua`'s animation table now stores a
      real 4-tile row-major 2x2 block per pose; `NpcSprite.lua`/
      `NpcCatalog.lua`/the website updated to match; live-verified via
      both `love .` (`CatalogExplorer.lua`, same real `NpcSprite.lua`
      code path `VictorySequence.lua` uses for actual gameplay) and
      Playwright -- a correctly-proportioned 16x16 humanoid now
      renders, matching a fresh direct mGBA screenshot of the real,
      unmodified ROM. Full detail (including the exact formula and its
      cross-validation) in `docs/progress.md`'s own dated entry.
      `characterB`'s dialogue text, by contrast, could NOT be
      independently confirmed or corrected this pass -- 3 real live
      re-verification attempts never reproduced the real dialogue box
      opening at all, despite reaching visually-confirmed adjacency to
      the NPC; left in `rom_profiles.lua` but doc-flagged UNCONFIRMED/
      disputed rather than silently kept as settled (task #137).
      458/458 tests pass throughout both follow-ups.

      **Second correction, SAME DAY (direct user report "die linke und
      rechte haelfte der npc sprites a und b sind vertauscht")**: the
      16x16 fix above's own tile ORDER was itself wrong -- reordering
      the 4 real tiles by their live-captured OAM screen X position
      (reasoning "smaller X = drawn further left, so put it in the
      image's left column") produced 2 visibly disconnected blobs, not
      a character. Verified directly (decoded the same captured tile
      bytes in plain Python, rendered both candidate orderings as
      PNGs, compared by eye) rather than guess-swapped: the ROM simply
      stores each pose's 4 tiles consecutively in real row-major file
      order already (`{T,T+0x10,T+0x20,T+0x30}`) -- no OAM-position
      reordering needed at all; that extra step was the bug. Fixed in
      `rom_profiles.lua` (both characters, all 16 poses); re-verified
      via both `love .` and Playwright -- a single coherent
      16x16 humanoid now renders. 458/458 tests pass.

      **`characterB`'s dialogue -- RESOLVED (direct user follow-up
      "das ist amanda die hat einen ganz anderen dialog ueber ihren
      bruder")**: found the real line via a targeted `dump_strings.py`
      text search (no live capture needed) -- she's Amanda, a real
      major story character, and the real secondRoom line is a
      first-person 3-page monologue mentioning Willy and her own
      little brother (real file offset `0x03783e`). Fixed in
      `rom_profiles.lua` (real 3-page `dialogue` + `realName =
      "Amanda"`); `VictorySequence.lua`'s real gameplay trigger needed
      no code change (already supports multi-page dialogue). One word
      stays an honest, unresolved oddity ("raa!" where "raus!" was
      expected) rather than silently guessed. A real side-finding
      while decoding it (byte `0x82`) was checked against this
      project's own prior "genuinely contradictory" finding for that
      byte and deliberately NOT force-added to the shared digraph
      table -- resolved locally for just this one string instead.
      458/458 tests pass.

      **Second correction, SAME DAY (direct user pushback "raa! müsste
      ... raus heißen" then "es muss ja ganz klar ausrüstung
      heißen")**: the "raa!" reading above was itself wrong -- a
      whole-ROM search for the same 2-byte pattern found `0x5B` is
      ALSO genuinely contradictory (same shape as the already-known
      `0x82`, just never flagged before): "a" was airtight for "Julia"
      (25+ occurrences) but 5 OTHER real words -- "Ausrüstung",
      "Daraus", "raus!" (this line), "grausamer", "grausam!" -- all
      need "us" instead. Fixed in `rom_profiles.lua` (locally, the
      shared default stayed "a" at the time); full evidence in
      `TextDecoder.lua`'s own updated doc comment and `progress.md`.
      458/458 tests pass. Task #137 closed. **RESOLVED 2026-08-17**:
      the real ROM digraph table settled this in favor of "us" -- the
      shared default now reads "us" directly, and "Julia" was itself
      corrected to "Julius" (see this milestone's own 2026-08-17 update
      above).

      **Full ROM-wide search, same investigation thread (direct user
      request "suchen alle monster und npcs mit allen daten, texten
      und grafiken aus dem rom")**: a whole-ROM text census
      (`tools/rom/dump_strings.py`) found 7 new real monster names
      (Zyklop/Garuda/Golem/Chimäre/Metallkrabbe/Gottesanbeterin/
      Zombie-Drachen/Roter Drache, each with a real "bezwungen/
      besiegt" message + byte offset) and 14 named story characters
      total (only Willy/Amanda have a known live position; the other
      12 are text-only, honestly flagged) -- new `rom_profiles.lua`
      `storyText` field, new website tab ("Story &amp; Charaktere"),
      new regression test. Along the way, a direct user correction
      ("Lester ist NICHT der Held") was verified against real dialogue
      and confirmed: Lester is Amanda's own brother, not the hero.
      Graphics candidate scan (banks 9-11) re-confirmed real creature
      art exists but honestly did NOT catalog specific "candidate
      species" -- boundaries are too ambiguous without live OAM ground
      truth to avoid fabricating precision. Bounded live NPC check
      (thirdRoom, willyRoom re-check) found 0 additional NPCs -- a
      real, honest negative result. 460/460 tests pass.

      **Catalog plan Phase 2 CLOSED (2026-08-15, direct user request
      "Katalog-Plan fortsetzen" -> "Items in mehr auswählbare
      Kategorien unterteilen")**: real `categoryByte` grouping for
      both `ItemTable.lua` (6 groups: `0`/`64`/`65`/`66`/`67`/`128`,
      counts 22/13/4/3/1/16) and `WeaponTable.lua` (13 groups, incl. 3
      real material/elemental TIER PROGRESSIONS with &ge;5 records
      each -- `160`/`161`/`162`, counts 9/7/9, e.g. Bronze&rarr;
      Eisen&rarr;Silber&rarr;Gold&rarr;...) -- new `groupByCategory`
      function on both modules, honestly `sizeClass`-labeled
      (`"group"`/`"single"`, a plain size threshold, NOT a claimed
      real slot name like weapon/armor/helm -- that's still
      unconfirmed, see task #128). New locked-in regression tests on
      the exact real counts (462/462 total). Wired into BOTH real UIs:
      the rom-inspector website's Items-&amp;-Waffen tab gets real,
      clickable categoryByte filter pills (Playwright-verified: filter
      narrows 59&rarr;13 rows for `categoryByte=64`, weapon tier
      `162`&rarr;9 correct rows, zero console errors); `CatalogExplorer
      .lua` gets a real B-button categoryByte cycle for items/weapons
      (`love .` screenshot-verified live: both the item-category and
      2-deep weapon-category cycles land on the exact expected real
      categoryByte/name/count). Phase 1 (full animation data) turned
      out to already be complete from an earlier pass this same day
      (task #133) -- verified present in `NpcCatalog.lua`,
      `export_data.lua`, both website viz files, AND `CatalogExplorer
      .lua` before starting Phase 2, avoiding duplicate work.
      **Phase 3 CLOSED (2026-08-16, direct user request "Katalog-Plan
      fortsetzen")**: the graphics sweep (`GraphicsCandidates.lua`, 12
      real candidate regions across banks 8-12) was already shipped;
      the one remaining gap was `fourthRoom`'s own live NPC check
      (thirdRoom/willyRoom were already covered same-day 2026-08-15).
      A real walking pass (all 4 directions, 150 frames each, from
      `fourth_room_free()`) plus an idle-vs-movement control check
      found ZERO new NPC spawns -- matching the plan's own realistic
      "0-2 new NPCs" expectation. Cross-checking the 6 already-alive
      entity slots at room entry against `secondRoom`'s own known-NPC
      checkpoint found byte-IDENTICAL values across all 3 rooms --
      generic engine scaffolding, not room-specific NPCs. **The entire
      saved Katalog-Erweiterung plan (Phases 1-3) is now complete.**

- **2026-08-15**: consolidated the day's script-interpreter findings
  (real opcode "pinning" architecture + 6 real control-code fixes,
  tasks #141-147: the interpreter now runs the ENTIRE remaining real
  boss-defeat script and reaches the real `0x00` queue-gate) into both
  user-facing surfaces (task #148): `CatalogExplorer.lua`'s
  interpreter-mode display now distinguishes a genuine understood halt
  from still-running from an actual error (live `love .`-verified);
  the rom-inspector website gained a new `control-codes.js` export +
  a new panel on the Skript-Opcode-Explorer page documenting the real
  `$36D0`/`$D85A` pinning mechanism and all 6 control codes with their
  live-confirmed status (Playwright-verified, zero console errors).

- **2026-08-15, task #147 corrected + closed**: the queue-gate halt at
  bank=14 cursor=0x4798 is a real, PERMANENT, correct stop for the
  boss-defeat script specifically -- `self.queue` never gains new
  content again, so "model queue content" was the wrong framing.
  Two live mgba traces (frame-level, then PC-filtered instruction-
  level via `tools/rom/watcher.py`) found the real continuation
  instead comes from the SAME already-understood `$31AD` cross-actor
  dispatcher (tasks #85/#111) firing again for a different real
  trigger, overwriting the same shared cursor cells with a fresh
  script entry that turns out to drive the real courtyard-story +
  Willy-exchange dialogue through the exact same opcode-0x04 machinery
  this project built last session. New task #149 created, correctly
  scoped: generalize the boss's one-shot `$31AD` trigger into a
  re-armable one so this project's own interpreter can drive that
  dialogue too. No production code changed -- investigation only.

- **2026-08-15, "beende jetzt mal den full corpus scan"**: found and
  fixed 2 real scan-TOOL stub bugs (duplicated independently in both
  `scripts/scan_all_scripts.lua` and `rom-inspector/tools/
  export_data.lua`) that were inflating the whole-corpus scan's own
  `errorOther` bucket with confusing, mislabeled crashes (a blanket
  stub fallback leaking `true` into fields with a real "return value
  is a cursor/byte-count" contract, opcodes `0x04`/`0x08`-`0x0C`) --
  53% of `errorOther` was this, not real ROM gaps. Fixed both copies;
  regenerated the website's own scan data. Honest remaining breakdown
  of the corrected 304 `errorOther`: 49% genuinely known-hard (same
  `$02AB`-family category as the existing topBlockers), 46% a real,
  substantial, still-open gap (the already-documented, only-partially-
  decoded digraph/low-byte text range below `0xB0` -- new task #150,
  needs the same live dynamic-tracing methodology `text.md` used
  originally, scaled up), 5% a small unexplained bank-4 cursor-drift
  cluster folded into the same task. `clean` 821->832,
  `haltUndecoded` 218->221. 462/462 tests pass (scan tooling only, no
  production runtime code touched).

- **2026-08-15, task #150 continued ("na dann entschluessel mal")**: a
  purely STATIC technique (`tools/rom/dump_strings.py --gaps`, this
  project's own tool from the original digraph investigation) found
  the classifier's error-byte set splits into real structural/opcode
  bytes (`0x04`/`0x0F`/`0xF9`, bleeding across opcode/text boundaries
  in the naive static scan, not real glyph gaps -- needs real opcode
  disassembly, left open) and one genuine, closeable text byte:
  `SPEAKER_COLON_BYTE = 0x2C` (a dialogue-box "SpeakerName:" tag
  delimiter, DIFFERENT from the pre-existing `COLON_BYTE`/`0xF5`),
  confirmed via 20 independent named speakers plus 4 grammatically
  perfect real German sentence decodes. Wired into `TextDecoder.lua`;
  463/463 tests pass. Honest note: the corpus scan's own aggregate
  numbers did NOT move from this fix (most affected scripts already
  fail on a different, more common byte earlier in the same script) --
  real, verified, permanent progress regardless, reported plainly
  rather than oversold. Task #150 stays open for the remaining
  higher-frequency bytes and the structural opcode question.

- **2026-08-15, "ok dann mal die fehlenden opcodes dekodieren"**: 9 of
  the primary opcode table's last 13 "undecoded" entries closed (7
  newly wired -- `0xA1`/`0xA2`/`0xAA`/`0xAB`/`0xB6` reuse the existing
  `chainedOpaqueEffectCommand` factory via the already-mapped `$1ED7`
  dispatcher; `0xD2`/`0xD3` are a real ADD/SUBTRACT sibling pair of the
  known `WORD_COMMAND` opcode, operating on a 24-bit WRAM counter
  capped at decimal 999999 -- very likely the real gold counter -- 2
  more, `0xA4`/`0x8A`, correctly recategorized as known-hard, a 5th and
  6th sibling of the already-documented `$02AB` family). Primary
  opcode table: 197 decoded / 49 default / 6 known-hard / 4 undecoded
  (was 190/49/4/13). Real, measured corpus-scan impact: `clean`
  832->853, `haltUndecoded` 221->185. 469/469 tests pass; website
  regenerated and Playwright-verified.

- **2026-08-15, "ok die restlichen bitte auch noch"**: `0xAD` (`$0DBC`)
  fully closed -- a real, classic GB joypad-polling routine (via
  `$1ED1`->`$1F06` selector `0x01`, including the real A+B+Select+Start
  soft-reset combo check) revealed a genuine "wait for any button
  press" gate; new `StandardScriptHandlers.waitForAnyButtonCommand`,
  wired via `ctx.isAnyButtonPressed`/`ctx.onWaitForAnyButtonIdleTick`.
  Self-caught bug during test-writing: the first draft signaled "halt"
  by returning the unchanged cursor instead of `nil` (the real
  `ScriptInterpreter:step` halt convention) -- caught by 2 failing unit
  tests before trusting the implementation, fixed. `0x8B` and
  `0xAC`/`0xAE` further characterized (new `$0C99`/`$2C27` 4-way
  sub-dispatch findings for `0x8B`; new `$D3A0` converging-marker phase-2
  mechanism for `0xAC`/`0xAE`) but honestly left open -- concrete next
  leads documented, not guessed at. Primary opcode table: 198 decoded /
  49 default / 6 known-hard / 3 undecoded (was 197/49/6/4). Real,
  measured corpus-scan impact: `clean` 853->856, `halt_undecoded`
  185->182. 470/470 tests pass; website regenerated and
  Playwright-verified. Task #152 narrowed to `0x8B`/`0xAC`/`0xAE`.

- **2026-08-15, "Die letzten 2 Opcodes fertig dekodieren (Task
  #152)"**: `0x8B` (`$0D1B`) fully closed -- a real waypoint-table-walk
  ("play back a pre-baked step sequence, one step every ~8 frames,
  until a real `0x80` terminator"), reached via `$1ED7` selector `0x1C`
  (`$76AB`). Self-caught correction of this SAME day's earlier
  characterization: the prior entry's "4-way sub-dispatch to
  `$2C43`/`$2C57`/`$2C6B`/`$2C7F`" was wrong -- those addresses turned
  out to be real but UNRELATED code (2 different, uninvestigated real
  callers elsewhere), not reachable from `0x8B` at all; caught by
  reading `$1ED7`'s own table directly and whole-ROM-searching for real
  callers of `$2C2D` before trusting the earlier claim. New
  `StandardScriptHandlers.waypointStepCommand`, wired via
  `ctx.advanceWaypointStep`. `0xAC`/`0xAE` untouched this pass. Primary
  opcode table: 199 decoded / 49 default / 6 known-hard / 2 undecoded
  (was 198/49/6/3) -- 99.2% decoded-or-classified. Real, measured
  corpus-scan impact: `clean` 856->859, `halt_undecoded` 182->178.
  472/472 tests pass; website regenerated and Playwright-verified.
  Task #152 narrowed to `0xAC`/`0xAE` only.

- **2026-08-15, "laut website sind noch 2 offen. beende die auch"**:
  `0xAC`/`0xAE` fully closed -- a real 8-phase `$D499` state machine
  (NOT 6 like the sibling `paletteFadeCompletionGate` family, confirmed
  by reading both real `$1ED7` selector `0x11`/`0x12` jump tables as
  raw bytes). Self-caught correction of this SAME day's earlier "phase
  0 is byte-identical in shape" claim -- it does substantial extra real
  palette/effect work the sibling family's own phase 0 doesn't. Found
  a real, elegant, decisively-confirmed symmetric design: phase 2's
  real "2 markers converging" wait and phase 6's real countdown share
  ONE WRAM tick counter (`$D49A`) -- the wipe closes over N ticks and
  reopens over the exact same N ticks. New
  `StandardScriptHandlers.wipeCompletionGate` (the 8-phase machine) +
  `.completionPredicateCommand` (a new, reusable generic "predicate
  each tick, release via `$3727` once true" outer shape), wired via
  `ctx.isWipeMarkerConverged`/`ctx.onWipeCompletionPhaseAC`/`AE`.
  Primary opcode table: **201 decoded / 49 default / 6 known-hard / 0
  undecoded** (was 199/49/6/2) -- **the primary 256-entry opcode table
  has ZERO undecoded entries for the first time.** Real, measured
  corpus-scan impact: `clean` 859->875 (+16, the largest single-pass
  jump of the whole arc), `halt_undecoded` 178->162 -- the remaining
  halted scripts are now entirely accounted for by the 6 already-known
  `$02AB`-family known-hard entries. 478/478 tests pass (+6); website
  regenerated and Playwright-verified. **Task #152 CLOSED** -- this
  closes the entire multi-session "decode the remaining primary script
  opcodes" arc.
  **UPDATE 2026-08-16 ("Whole-Corpus-Scan-Abdeckung erhöhen")**: the
  top 3 real `$02AB`-family handlers (`$0E73`/`$0E77`/`$0E7B`, 132/163
  = 81% of the current `halt_undecoded` bucket) fully disassembled --
  a real 3-way sibling family, each pushing the current MBC bank
  (`$29FB`), dereferencing the `$C3FE`/`$C3FF` actor pointer offset by
  0/1/2 bytes, reading the player's real facing nibble (`$02AB`), then
  calling a still-undecoded leaf (`$3213`) before popping the bank
  back (`$2A0A`). Real, incremental progress -- the entry sequence is
  now fully mapped, but `$3213`'s own release condition (and `$0EB2`'s
  separate `$D499`-indexed `$0ECA` table) stay undecoded, so corpus-
  scan numbers are unchanged (884/163/310) -- honestly reported as
  groundwork, not a closed opcode.
  **UPDATE 2026-08-16 (same day, "$3213 weiterverfolgen"): DECISIVE
  structural finding, closing the "what mechanism is this" question
  even though the corpus-scan count itself stays unchanged.** `$3213`'s
  own real completion (`$31C7`) is not a separate leaf at all -- it IS
  `$31AD`'s own already-mapped internal completion/dispatch tail (same
  3 special-case WRAM fallback buffers, same `$3282`/`$3c4f`/`$3727`
  resolve-and-dispatch chain, same `$C0A1`/`$C0A2` bit-1+2 re-arm this
  project's own task #149 already found `$31AD` itself performing).
  I.e. these top-3 blocking handlers are genuinely, decisively
  confirmed to be ALTERNATE ENTRY POINTS into the same long-studied
  cross-actor dispatch mechanism, not an unrelated new system. What
  remains is exclusively DATA (which real actor/WRAM value each of the
  132 affected scripts resolves at runtime) -- the SAME honest,
  structural "can't derive from a static ROM-only shadow-run" category
  this project's own `scan_all_scripts.lua` already accepts for opcodes
  `0x08`-`0x0C`. Further static disassembly of this family is
  genuinely exhausted; closing more of it needs live per-script
  WRAM-tracing, matching this session's own `unknownRoomA` investigation
  in scale.

- **2026-08-15, task #150 continuation**: refined the remaining 154
  `tick`-error bytes' static classification -- 10/12 top values fail
  MID-run (after 1-20 real characters already decoded), matching real,
  still-unidentified embedded digraph/control bytes rather than
  scan-tool artifacts; 2/12 (`0x07`/`0x0C`) fail as the first character
  of their own run, a separate, less certain shape. Confirmed the
  `tools-external/mgba` Python tooling still works on this machine with
  no rebuild needed. Tried one live-injection shortcut (force a
  not-yet-reached script to render via direct WRAM/bank poking from a
  known idle checkpoint) -- the real game's own per-frame logic reset
  the forced bank before the dispatch could read it; honestly reported
  as not working rather than forced into a false result. Task #150
  stays open; no production code changed.

- **2026-08-15, task #150, "weiterverfolgen"**: refined the injection
  to single-instruction precision (found the real MBC2 bank-switch
  convention, `core.memory.u8[0x2100]=bank`; found `$3727`, the real
  fetch primitive, genuinely does NOT run during plain overworld idle
  time -- 5M steps across 2 idle contexts never hit it -- but DOES run
  richly during active scripted sequences, e.g. the post-boss heal/
  black-wipe, hit within 108k steps there). The injection technically
  worked for exactly one real tick (independently confirmed table index
  213 starts with the TICK opcode, matching the earlier static trace),
  but the real boss-sequence's OWN concurrent script reclaimed the
  shared `$D85A`/`HL` dispatch state within ~1 more real per-frame
  cycle -- a genuine, decisive finding: the SAME cross-actor dispatch
  mechanism this project already documented (task #85) means multiple
  real scripts genuinely TIME-SHARE the per-frame interpreter, so a
  single foreign injection survives only until the next real script's
  own turn. Closing this further needs either a genuinely quiet moment
  (not yet found) or neutralizing concurrent scripts on purpose -- a
  real, deeper research question, explicitly time-boxed rather than
  pursued indefinitely. Task #150 stays open; no production code
  changed.

- **2026-08-15, task #128 continuation**: `$5BA7` (the attack-side
  equipment-bonus lookup) fully disassembled -- a real indexed
  table-pick (`$2E99`/`$2EB1`, selected via `$CF5C`) feeding the
  already-known numbered-effect dispatcher `$297D`, returning `7-C`.
  Self-caught correction via a live write-watchpoint: the total-stats
  recompute at `$97E0` runs CONTINUOUSLY every real frame, not once at
  boot as the previous entry concluded (retracts that specific claim;
  the underlying class-kit lookup may still be one-shot). A real
  equip-swap test was attempted but blocked on a genuine precondition
  -- the player starts with exactly one weapon and no alternate to
  swap to; needs the checkpoint chain extended to a real shop/item
  pickup, not yet built. Task #128 stays open; no production code
  changed.

- **2026-08-15, task #127 ("zweiter boss")**: decisive correction --
  the Lua port's own `secondBoss` placement (fourthRoom) has NO real
  ROM trigger, live-confirmed (not just re-read from prior docs) by
  building a new, permanent `fourth_room_free()` mgba checkpoint (the
  first to reach past `thirdRoom`) and dumping all 20 real entity
  slots at that location: only the player is a genuinely live,
  positioned entity; the rest are uninitialized boot-time
  placeholders. The underlying real evidence (species byte `0x16` --
  the SAME species as the FIRST boss) and its 3 real, reachable but
  room-unidentified trigger scripts were already exhausted via static
  analysis in an earlier session. Testing DEF against a genuinely
  different real encounter still needs one of two known, harder paths
  (find the real triggering room, or force one of the 3 scripts via
  live injection -- the same concurrent-script obstacle task #150 hit).
  Time-boxed at this decisive negative result.

- **2026-08-16, task #127 CLOSED**: re-assessed the two remaining
  "harder paths" (live injection to force one of the 3 real trigger
  scripts; find their real triggering room) against this same
  session's own task #150 deep dive, which root-caused exactly why
  live injection is hard (the real bank call-stack is shared by many
  legitimate subsystems -- any one-off injection gets swept away
  within ~1 real frame regardless of technique). But the decisive
  reason to close is independent of that cost: the "second boss" is
  the EXACT SAME species (`0x16`) as the already-live-tested first
  boss, so reaching it -- however achieved -- would only re-confirm an
  ALREADY-established conclusion (DEF is confirmed absent for species
  `0x16`), not add a new data point. Closed rather than left
  perpetually open pending infrastructure with no marginal value. A
  genuinely different-species creature (10 of 11 known real species
  are still never-confirmed-spawnable) would be the real next DEF
  target, not this one.

- **2026-08-15, task #135 (bounded monster/NPC graphics search)**: 5
  new, real, visually-confirmed creature/character art regions found
  (bank 10 -- previously totally unexplored -- and bank 11), via
  `scan_graphics.py` + manual `gbtile.py` visual confirmation. New
  `src/import/GraphicsCandidates.lua` catalog, honestly scoped (no
  species/room/spawn-trigger claims), wired into the rom-inspector
  website's Monster tab as a new "Grafik-Kandidaten (unbestätigt)"
  section. NPC side: a real, live-confirmed NEGATIVE -- dumped all 20
  entity slots in both `thirdRoom` and `fourthRoom` via mgba, found
  zero NPCs in either (only the player is a live entity) -- extends
  task #140's own bounded NPC check beyond willyRoom/secondRoom. 3 new
  tests, 481/481 pass; website Playwright-verified.

- **2026-08-15, task #135 continuation ("nicht vorher stoppen")**:
  extended to a full, systematic sweep -- rendered EVERY ROM bank
  (0-15) in full and visually reviewed each, not just individual
  entropy-scan hits. Confirmed banks 0/1/2/3/4/5/6/7/13/14/15 are
  genuinely code/text/room-data (no graphics) and bank 12 is real
  environment/architecture tileset art (no creatures, double-checked
  including its own ambiguous-looking corner). Banks 8/9/10/11
  confirmed densely packed with real art -- 7 more regions added: a
  4-portrait NPC/class-icon set (bank 8, the strongest NPC-shaped find
  of the whole investigation), 2 icon-fragment sheets, a single very
  large 704-tile creature-column field (bank 9, the richest region
  found), and 4 contiguous 216-tile regions covering bank 11's own
  dense creature-art field below the title logo. 12 total real
  candidate regions now cataloged, spanning all 4 real graphics-
  bearing banks -- every other bank confirmed to hold none. 481/481
  tests still pass; website re-verified (13 cards, per-kind badges,
  zero console errors).
- **2026-08-16, task #153, opcodes page readability rework**: direct
  user complaint that the rom-inspector opcodes page is "sehr
  kryptisch, vor allem die beschreibnbenden texte". Data layer:
  `opcode-descriptions.js`'s 35 curated entries each got a new
  plain-language `summary` field alongside the original dense `text`
  writeup (kept in full, not trimmed), plus a new 12-term
  `OPCODE_GLOSSARY`. UI layer: `opcodes.js`'s detail panel now leads
  with `summary` and tucks the original technical writeup into a
  collapsible "Technische Details" block whose glossary terms render
  as hoverable `<abbr>` tooltips; a new collapsible glossary box sits
  above the grid; grid tooltips, search, and the script-tracer's own
  step text switched to `summary`. Playwright-verified end to end
  (glossary box renders, summary shown prominently, details toggle
  reveals the technical text, a real glossary term's `<abbr>` carries
  its full definition, zero console errors across 40 sampled cells).
  481/481 tests still pass (JS-only change, Lua suite unaffected).
- **2026-08-16, task #154, map-tile search + Grafiken tab + palette +
  ROM button**: same-day follow-up ("mach das gleiche mal für die map
  tiles... pack diese grafik funde bitte in einen eignen tab..."
  color-palette presets... "ROM laden" button barely recognizable).
  Bank 12 (already-confirmed environment tileset bank) checked chunk
  by chunk against every literal ROM-offset already used by a real
  room -- found exactly ONE genuinely unconfirmed 256-tile region
  (0x31000, `bank12_environment_b`), the rest already wired (0x30000
  piecemeal, 0x32000+ via the systematic table). New dedicated
  "Grafiken" tab/section replaces the old embedded Monster-page
  subsection, filterable by kind. Direct user correction the same day
  ("du musst noch viel mehr tile daten kennen, immerhin sind ein paar
  räume schon bekannt und komplett kartiert") led to `src/import/
  MapTileCatalog.lua`: dedupes all 243 real, ALREADY-VERIFIED map tiles
  across this project's 14 fully-mapped rooms (banks 8/11/12, not just
  12), now the Grafiken tab's own lead section with per-bank mosaics
  and per-tile room attribution. Plus: 4 GB-palette display presets in
  the top bar (viewer preference only, not ROM data) that re-render
  every tile canvas site-wide; ROM-laden control restyled with real
  button chrome (`.btn` widened from `button.btn`-only). 6 new
  MapTileCatalog tests (incl. a real-ROM 14-room/243-tile/3-bank
  cross-check) -- 487/487 tests pass. Playwright-verified end to end,
  zero console errors.
- **2026-08-16, task #160, real graphics-loading mechanism found via
  access analysis**: direct follow-up ("du kennst ja jetzt die
  positionen von vielen grafiken. kannst du anhand der zugriffe auf
  diese neue informationen ableiten"). Static byte scan (new
  `find_graphic_refs.py`) found ZERO literal `LD HL,<addr>` references
  to any candidate OR to 2 known-used positive controls -- a decisive
  negative proving graphics load indirectly. Live mGBA read-
  watchpoints (new `watch_graphic_refs.py`) during real active combat
  caught real hits, leading to a full disassembly of a previously-
  undocumented generic ROM->VRAM tile-streaming DMA system (bank 0,
  `$2D57`-`$2E31`): a real WRAM work queue (`$C5E0`, 6 bytes/entry),
  gated by `$C8E0` (queue depth) -- the SAME `$C8E0` this project's
  own `$C8E0`/`$CEE8` dual-gate script opcodes (`0xFC`/`0xFD`) already
  wait on, now understood as literally waiting for this loader.
  Confirmed calling convention (HL=source, DE=dest VRAM, A=bank,
  `CALL $2DF5`) against 17 real call sites spanning banks 0/1/2/3/4/9.
  Found a genuinely new mechanism: 2 identical routines (banks 3 & 4)
  compute the graphics bank DYNAMICALLY as `8 + ((kindByte>>2)&3)` --
  landing on exactly the 4 real graphics-bearing banks (8-11) this
  project's own full sweep already found -- almost certainly the real
  per-species/NPC-kind graphics dispatch, though the exact kind-byte
  mapping is still open (needs a live trace while entities spawn).
  Self-caught correction: bank 9's own local loader (`$24228`) walks a
  real 6-byte record table at file `0x24479`, INSIDE the
  `bank9_creature_columns` candidate -- that sub-range is real
  structured data, not pixel art; the candidate's own note corrected,
  not silently left standing. 487/487 tests still pass (docs +
  GraphicsCandidates.lua note change only, no code-behavior change).
- **2026-08-16, same-day follow-up, applying task #160 to existing
  open questions ("können wir damit vorher bestehende questions
  lösen?")**: checked every `OPEN_QUESTIONS` entry against the new
  graphics-loading finding. Two real hits, both folded into existing
  entries (not new ones): (1) the `$C8E0`/`$CEE8` dual gate the
  opcode-0x04/`$1ED7` selector-0x10 investigation already named now
  has a concrete meaning -- it's the tile-streaming DMA's own queue
  depth, so those gates are provably waiting for pending graphics
  transfers, not an opaque flag. (2) Task #81 (cross-bank CHAIN
  mystery) got genuine new progress: disassembling `CHAIN`'s own
  handler ($32FE) found a previously-undocumented, general bank
  call-stack primitive (`$29FB` push, `$2A0A` pop, `$2A17` peek --
  ~35 real call sites) that CHAIN provably calls (the pop variant) as
  part of committing its new cursor -- narrowed from "no mechanism
  found" to "a real mechanism exists and CHAIN touches it," but NOT
  proven to correctly resolve the actual 7 cross-bank targets (needs a
  live `$2100`-write trace next, honestly left open). 487/487 tests
  still pass (docs + open-questions.js text only).
- **2026-08-16, task #161, consolidate task #160 into the interpreted
  app + website ("bitet das wissen konsolidieren, dokumentieren,
  cleanen, und in interpretierte app und website einbauen")**: no
  runtime behavior change (this project's own rendering has no VRAM-
  transfer-latency concept to model, so the existing "always ready"
  gate defaults stay correct) -- pure documentation + tooling
  consolidation. `rom-inspector/js/data/wram-map.js` (the "Speicherkarte"
  page) gets 5 new/updated entries: `$C8E0`/`$CEE8` upgraded from
  "opaque gate" to VERIFIED (the tile-DMA queue depth), plus new
  entries for `$C5E0+` (the queue itself), `$C8E1` (its reentrancy
  guard), HRAM `$FF8A` and `$C000+` (the bank call-stack). `src/
  scripting/StandardScriptHandlers.lua`'s own `.oneShotTriggerGate`/
  0xE8-0xE9 handler/`isDualGateClear` doc comments and `src/import/
  ScriptOpcodeTable.lua`'s `CHAIN_HANDLER_ADDRESS` doc comment enriched
  with the concrete real meaning, each explicitly noting the recomp's
  own simplification stays correct. Cleanup: `tools/rom/
  find_graphic_refs.py` and `watch_graphic_refs.py` had two silently-
  divergible copies of the same 16-entry candidate list -- factored
  into a new shared `graphics_candidates_addresses.py` (now also
  carrying each candidate's real `tileCount`, enabling a proper
  `resolve()`-by-range-containment). Fixed a real, previously-manual
  bug in `watch_graphic_refs.py`'s own hit reporting: it used to label
  a hit by whichever candidate's watch fired, not by which candidate
  the real, active-bank-resolved file offset actually belongs to (the
  exact confusion that required manual recomputation to catch the real
  `bank9_icon_fragments` finding during task #160's own live run) --
  now resolved automatically and correctly on every run. Re-verified:
  487/487 tests pass, both Python tools re-run against the real ROM
  with identical (find_graphic_refs) or now-auto-correct
  (watch_graphic_refs) output, Playwright-verified the Speicherkarte
  page renders all 5 new entries with zero HTML-escaping artifacts and
  zero console errors.
- **2026-08-17, the real NPC/monster/boss sprite-PIXEL-SOURCE formula,
  found and live-validated 3 independent ways** (direct user
  instruction: "versuche mal über einen ähnlichen hebel wie bei den
  tiles alle npc, boss und monstersprites zu extrahieren", then "schau
  in die vram zugriffe wenn sprites zu sehen sind, leite daraus was
  ab"): picked back up task #160's own explicitly-left-open thread
  ("which candidate region belongs to which real species/NPC" -- the
  kind-byte -> bank8-11 dispatcher was found but never traced to a real
  table). Static disassembly of both dispatch routines (bank3 `$c400`,
  bank4 `$1039c`) found they fall through from a real "process one
  entity-definition record" function reading a fixed 6-byte "outer
  sprite record" (`dest0,count,C,kindByte,innerPtr`) embedded directly
  in each entity's own bigger row -- `ActorDefinitionTable`'s own
  bytes[2..7] for the already-known 218 NPC rows, and a genuinely NEW
  24-byte-stride monster/boss table (bank4, 21 real rows, found because
  its own bytes[2..5] write straight to this project's ALREADY-known
  real HP-populate WRAM cells, `$D3F4`/`$D3F5`). Formula:
  `sourceCpuAddr = rawByte*16 + kindByte*256 + C` (fixed up, same
  bit-trick style as the room-tile pipeline), `bank = 8 +
  floor(kindByte/64)`, same `$2DF5`/`$2D57` DMA entry the room-tile
  pipeline already fully documented -- ONE real ROM->VRAM graphics
  subsystem serving both. Live single-stepped 2 real spawn windows
  (secondRoom's NPCs, the real first-boss encounter), watching every
  `CALL $2df5`: EXACT match, 3 independent ways, against every one of
  this project's own already-known real tileOffsets (characterA's 16,
  characterB's 16, the boss's 32) -- the same standard of evidence the
  room-tile pipeline fix used. Shipped `SpriteTileFormula.lua` (shared
  formula), `ActorDefinitionTable.lua` extended, new
  `MonsterDefinitionTable.lua`. **Honest scope**: closes the
  PIXEL-SOURCE half for all 218 NPC + 21 monster/boss rows (real,
  computable pixel data, zero further live capture needed) -- does NOT
  close the on-screen ARRANGEMENT half beyond the 3 already-known ground
  truths; a first attempt at a generic grid render for the other 18
  monster rows produced correctly-decoded but visibly scrambled tile
  blobs, retracted rather than shipped as a real layout. 570/570 Lua
  tests pass (new `sprite_tile_formula_test.lua`, including a pure-math
  regression lock independent of any ROM).
- **2026-08-17, same day, direct follow-up ("du sollst mehr npcs
  suchen"): the real on-screen pose ARRANGEMENT for 91 more NPCs**:
  grouping all 218 `ActorDefinitionTable` records by their own sprite
  identity found 190 share the EXACT SAME `innerPtr` as characterA/
  characterB (172 of those with an even `count`, i.e. real pose
  structure) -- 91 DISTINCT `kindByte` values among them, i.e. 91 real,
  individually different NPC sprite designs, not just repeats of the 2
  already known. The shared list's own real copy order (`0,2,1,3,4,6,
  5,7,...`) compared against characterA's/characterB's own already-known
  real pose grouping revealed the exact reconstruction rule (swap the
  middle two of every 4-tile group) -- applied to a sample of brand-new
  designs, rendered coherent, individually distinct, clearly humanoid
  sprite sheets (confirmed both in a scratchpad render and live on the
  actual website). Honest confidence tier kept explicit throughout (NOT
  claimed as strong as the 2 individually live-OAM-verified ones):
  `arrangementFamily="humanoid4pose"` field, a 3-tier website badge
  ("bestätigt" / "wahrscheinlich (Familie)" / "unbekannt"). Strengthened
  the characterA/characterB tests from set- to strict ordered-equality
  now that the real order is known. 572/572 Lua tests pass, Playwright-
  verified live (170 family-badged NPC cards render as coherent 4-pose
  sheets).
- **2026-08-17, same day, direct instruction "die müssen nicht
  verified sein, bau auch die grafiken in die website ein": all 21
  named story bosses get a real sprite**: found, while wiring this up,
  that `MonsterDefinitionTable` (this session's own new sprite table)
  and `EnemyStatTable` (found earlier the same day via external
  US-disassembly name matching) are THE EXACT SAME real table -- same
  bank/file base/stride/row count, found independently by two
  investigations the same day. Byte-for-byte cross-checked (row 16's
  speed/hpBase/xp/gold match exactly between both decoders). Every one
  of the 21 named bosses (Vampire...Dragon (Final)) now shows its own
  real ROM sprite on the Monster page, regardless of arrangement-
  confirmation status (only "Jackal", row 16, is individually live-
  verified -- honestly badged per-boss, not hidden for the other 20).
  New regression test locks the table-identity finding. 573/573 Lua
  tests pass, Playwright-verified (21 boss cards, each with a real
  sprite canvas, zero console errors).
- **2026-08-17, same day, direct instruction "versuche daraus die
  tatsächlichen monster mit den animationsphasen zu rekonstruieren wie
  du es bei spezies 4 gemacht hast": real monster/boss pose
  arrangement reconstructed**: species 4 (row 16, "Jackal") is the ONE
  monster with both a live-verified pixel source AND a live-verified
  real 4x4 arrangement -- comparing the raw-DMA-order formula output
  against that already-known real order found a clean, checkable
  16-tile permutation (more complex than the NPC family's own "swap
  the middle two", consistent with `enemySprite`'s own doc comment
  describing a genuinely different hardware layout for creatures).
  Applied PER-CHUNK (not per-record) to all 21 monster/boss records,
  only where a chunk's own raw bytes structurally match the reference
  shape -- 7 records fully reconstructed, most of the rest partially,
  a few not at all, all honestly counted (`chunksReordered`/
  `chunksTotal`, not one boolean). Rendered and visually confirmed:
  Golem renders as an unmistakable rock humanoid, Garuda as an
  unmistakable bird creature (wings, talons, beak), both live on the
  actual website too. Honest confidence kept explicitly WEAKER than
  the NPC family tier (one ground truth here, not two) -- 3-state
  website badges ("Alle Posen rekonstruiert (N/N)" / "Teilweise
  rekonstruiert (N/M)" / "Anordnung unbekannt"), never collapsed into a
  false blanket claim. Strengthened the row-16 regression test to
  strict ordered equality. 575/575 Lua tests pass, Playwright-verified
  live.
- **2026-08-17, same day, direct instruction "wenn die posen
  rekonstruiert sind dann bitte auch so einbauen wie bei spezies 4":
  fully-reconstructed monsters get species 4's own UI**: the 7 fully-
  reconstructed bosses (rows 2/3/5/7/12/16/19) were still shown as one
  tall concatenated strip -- species 4's own card shows one 4x4 canvas
  with switchable pose tabs instead. `export_data.lua` now builds
  `spritePoses` (one real 4x4 pose per array entry) only when EVERY
  chunk is confidently reconstructed; `monsters.js` renders the exact
  same "Pose 1"/"Pose 2"/... tab UI species 4's own card already used
  -- and species 4 itself (Jackal) now gets this treatment on its own
  boss card too, for consistency. Live-verified: Garuda's card switches
  between 3 real, individually coherent poses (a full bird silhouette,
  two creature-head poses) on one clean canvas. 575/575 tests pass.
- **2026-08-17, same day, honest negative: re-checked every other
  reachable room for further real NPC spawns**: direct instruction
  "verfolge die vram zugriffe und leite darus ab wo die restlichen
  liegen könnten" -- used the now-known real NPC/monster dispatch
  destination address (`0x8400`-`0x84FF`) to instrument every other
  currently-reachable room transition (thirdRoom, fourthRoom,
  fifthRoom, sixthRoom). Zero hits across all four. One hit during
  willyRoom's own dialogue sequence turned out to be the ALREADY-
  documented, unrelated font/glyph loader (task #160's own bank-8
  finding), not a creature spawn -- confirmed via a real Watcher
  tooling gotcha caught and fixed along the way (`run_frame()`-based
  polling needs an explicit `.resume()` or the debugger stays stuck on
  the first-ever hit). Honest conclusion: characterA/characterB remain
  the only 2 live-triggerable real NPC spawns this project can reach;
  the other 89 `humanoid4pose` designs are real, statically-present ROM
  data with no known live trigger. No code change, pure investigation.
- **2026-08-17, same day, direct follow-up "ok jetzt mach das gleiche
  für alle npcs": pose-tab UI extended to all 172 humanoid4pose NPC
  records**: same treatment species 4's boss card and the 7 fully-
  reconstructed monsters just got, now for every NPC whose own real
  pose order is known (`arrangementFamily=="humanoid4pose"`).
  `export_data.lua` builds `spritePoses` (4-tile pose chunks, already
  reordered by `resolveSpriteTileOffsets`) for these; `graphics.js`'s
  sprite catalog renders the SAME "Pose 1"/"Pose 2"/... tab UI, per-
  entry state persisted across palette-switch redraws. Live-verified:
  every one of the 218 NPC cards on the Grafiken page shows a small,
  individually distinct, coherent 16x16 character, switchable pose by
  pose. 575/575 tests pass (pure export/website wiring).
- **2026-08-16, task #162, rom-inspector UX/accessibility audit**:
  full "elevate this product" brief, scoped to the website (confirmed
  via AskUserQuestion, not the ROM-fidelity-bound LÖVE2D game). Real,
  measured findings: `--text-faint` failed WCAG AA contrast (2.81-
  3.27:1, needs 4.5:1) across ~12 real usages; zero `tabindex`/`role`/
  `aria-` anywhere in the codebase, so every custom control (sidebar,
  10 pill-tab filters, bank-cells, the 256-cell opcode grid) was
  keyboard-unreachable; `#sidebar{display:none}` below 860px had no
  mobile alternative at all; a live Playwright tab-order trace found
  the ROM-load control itself was unreachable by keyboard (hidden
  native file input + non-tabbable label). Fixed: contrast token,
  sidebar rebuilt as real `<a>` links, a shared
  `enhanceKeyboardAccessibility()` retrofit for pill-tabs/bank-cells/
  opcode-cells (zero changes to the 8 pages' own click logic), a real
  mobile nav drawer (hamburger + backdrop + Escape/click-away, focus
  returns to the toggle), a skip link, route-change scroll/focus
  management (kept out of the shared low-level `route()` so a palette
  switch doesn't steal focus), the ROM input's own keyboard path,
  `aria-label`s on all 6 canvas visualizations, and a self-caught
  `scan.js` "clickable-looking row that does nothing" papercut. No
  visual/theme redesign (already cohesive, left alone). 487/487 tests
  pass; every fix independently Playwright-verified, zero regressions
  across all 18 sections.

- **2026-08-16, task #151, real music playback ported into `love.audio`**:
  the decoded music format (song table/note events/frequency table,
  DECODED 2026-08-15) is now real, playing engine code, not just a
  standalone Python proof. New `src/audio/MusicScore.lua` (event list
  -> playable segments, real loop-point resolution),
  `src/audio/GBSquareSynth.lua` (real GB duty-cycle square-wave PCM
  synthesis), `src/audio/MusicPlayer.lua` (streams to
  `love.audio.newQueueableSource`, one real source per channel), and a
  dev-only `src/app/states/MusicJukebox.lua` (F9 from Field.lua, same
  "real content, no fabricated trigger" precedent as RoomExplorer's
  F8) covering all 30 real songs. A real `love .` smoke test caught a
  genuine bug before it shipped: song 1 channel 3 computes 65536 Hz
  for one real note byte, mathematically correct per the real GB
  formula but far above human hearing/this synth's own Nyquist limit
  -- fixed with a silencing guard, itself a new concrete data point for
  the still-open "channel 3 hardware target unconfirmed" question.
  Live-verified over a real ~10-second run: all 3 channels genuinely
  streaming and independently progressing through their own segment
  lists, buffers staying correctly topped up. 8 new unit tests,
  `luajit tests/run_tests.lua`: 501/501 pass. Full detail in
  `docs/reverse-engineering/audio.md`.

- **2026-08-16, task #81, real 7-script cross-bank CHAIN mystery,
  substantially resolved**: direct continuation ("erst 151 dann 81").
  Found a real, decisive split into two cases. Script 489 was never
  actually cross-bank at all -- the already-known `$3c4f` correction
  resolves it in-bank; re-shadow-running it dispatches 41 distinct,
  richly varied real opcodes before an ordinary, unrelated,
  already-known-hard blocker -- a decisive confirmation this one was a
  false alarm predating that correction. The other 6 genuinely overflow
  the CPU's own 16-bit address space -- a new, wired CANDIDATE
  hypothesis reuses `ScriptPointerTable.resolve`'s own already-proven
  "roll into a later real bank" formula for `CHAIN`'s operand bytes
  too, resolving all 6 with zero interpreter crashes (weaker
  confirmation than script 489's case -- plausible, not proven). Real
  code shipped: `StandardScriptHandlers.chain()` implements the full
  hybrid rule (`onChainTarget` gained a `bankOffset` argument),
  `scripts/scan_all_scripts.lua` updated to follow it (avoiding a real
  silent-wrong-bank-data risk the fix would otherwise have introduced).
  Corpus-scan impact: `clean` 875->884, `error_other` 320->310. A real
  prerequisite gap surfaced for the originally-planned live
  `$2100`-write watchpoint: no known live trigger reaches any of these
  7 script-table entries in normal gameplay. 10 new/updated tests,
  `luajit tests/run_tests.lua`: 506/506 pass. Full detail in
  `docs/reverse-engineering/rom-map.md`.

- **2026-08-16, task #163, rom-inspector second deep audit pass**:
  the same "elite product team" brief re-run against everything added
  since task #162 (Grafiken/Weltkarte/Katalog/Musik tabs, 18 sections
  total). Real, measured, Playwright-verified findings: 11 form
  controls with no accessible name across 8 pages (fixed via
  `aria-label`/`<label for>`); one real WCAG AA contrast failure
  specific to a highlighted entity-struct box's background tint
  (fixed, 4.83:1); the overview page's own 17-card navigation grid was
  completely keyboard-unreachable (`<div onclick>`, same class of bug
  #162 already fixed for the sidebar -- converted to real `<a href>`
  elements); and a real, page-wide mobile horizontal-scroll bug
  affecting every one of the 18 pages (topbar's own `scrollWidth` was
  783px at a 390px viewport), root-caused to three compounding causes
  (an unconstrained palette `<select>`, un-contained wide data tables,
  an unconstrained script-example `<select>`) and fixed generally
  (topbar wraps, tables scroll themselves, all inputs cap at
  `max-width:100%`) rather than chasing pixel budgets. Zero
  regressions: 18/18 pages clean on console errors, contrast, missing
  accessible names, and horizontal overflow, both desktop and mobile,
  independently re-verified after every fix. Full detail in
  `docs/reverse-engineering/rom-map.md`.

- **2026-08-16, task #149, `$31AD` fully disassembled + a real, tested
  `:rearm()` mechanism**: closes the "one-shot trigger" gap task #147
  scoped. Full byte-level disassembly of `$3297` (opcode 0x00's real
  handler) and `$31AD` together, for the first time -- found a real,
  previously undocumented WRAM cell (`$D865`, real queue-empty flag)
  and the real self-gating scheme (`$31AD` checks/sets bit 1 of
  `$C0A1`/`$C0A2`; `$3297`'s own genuine-idle path clears it). Decisive
  correction: `$31AD` is not hardware-one-shot -- it fires at most once
  per busy period, auto-re-armed by the SAME real event this project's
  own `queueGate` already models. A live trace caught a real SECOND
  firing (matching task #86's own `$C5AF` timing almost exactly) and
  found it commits the exact same real entry point as the first
  invocation -- honestly left open WHY. New `BossSequenceInterpreter
  :rearm()`, 2 new tests, `luajit tests/run_tests.lua`: 508/508 pass.

- **2026-08-16, task #127 CLOSED**: the "second boss" is the exact same
  species as the already-tested first boss, so the two remaining paths
  to a live encounter (harder now that task #150's own bank-call-stack
  work priced out live injection precisely) would not add any new DEF
  evidence even if built. Closed rather than left open by default.

- **2026-08-16, task #150, 4th pass -- decisive scope reduction**: the
  corpus scan's own "154 script-hits across 30 byte values" collapses
  to only **63 genuinely distinct real failure locations** once
  measured by real ROM file offset instead of by failing script --
  `scriptPointerTable` indices pointing into overlapping/adjacent byte
  regions (the same phenomenon task #81 found for CHAIN) inflate the
  count massively (e.g. `0x05`, the top blocker at "20 scripts", is
  really only 3 distinct locations). One word-solve attempt on the top
  real location stayed inconclusive, reported honestly rather than
  guessed at. Real remaining scope is now much smaller and better
  understood; still blocked on the same live-injection wall for
  actually reaching this content. Task #150 stays open.

- **2026-08-16, task #34 -- generated-cache pipeline write half built and
  running**: `src/import/LuaWriter.lua` (pure Lua, deterministic
  diff-stable serializer, 9 tests) and `src/import/RomExtractor.lua`
  (orchestrates `EnemySpeciesTable`/`ItemTable`/`WeaponTable`/
  `NpcCatalog` into one data table + a real SHA-1-stamped manifest,
  cross-checked against calling each importer directly on the real
  ROM). `scripts/extract_rom_cache.lua` (thin CLI glue, matching
  `SaveFile.lua`'s established pure-core/thin-shell split) actually
  runs it end to end: `data/generated/{monsters,items,weapons,npcs,
  manifest}.lua` written from the real ROM, verified deterministic
  (byte-identical besides the manifest's own timestamp) across repeat
  runs. Honestly scoped: no `ImageWriter`/pixel-data stage yet, and the
  runtime switch (states/importers actually reading generated files
  instead of live-decoding `romData`) is a deliberate, separate
  follow-up -- nothing consumes these files yet. `luajit
  tests/run_tests.lua`: 519/519 pass.

- **2026-08-16, task #128 CLOSED -- decisive self-caught correction**: the
  2026-08-15 `$5BA7` disassembly was reading the WRONG BANK (assumed
  bank 5 via a naive `bank*0x4000` guess instead of the caller's own
  currently-mapped bank 2) -- proof: file `0x15BA7` disassembles to
  pure garbage, while the CORRECT file `0x9BA7` (bank 2, no bank-switch
  between caller and callee) disassembles to a clean, complete 7-
  instruction routine. The real `$5BA7` is trivially understood: it's
  the exact same `$A200`/`$768C` "class/kit record byte +1" lookup the
  already-verified `$D6C0`/`$D6C2` defense bonus uses, just reading a
  different slot (`$D6E9`, index `0x01`). Byte-exact live cross-check:
  ROM file `0xA201 = 4`, an exact match to the already-known
  `$D6C1=6, $D7C2=2` live state. This retracts the whole
  `$0C86`/`$0CBA`/`$297D`/`$2E99`-vs-`$2EB1`/`SUB C` narrative from the
  prior entry (never real code) and closes every "genuinely still
  open" item from that entry except the live equip-CHANGE test, which
  stays blocked on a real, unchanged precondition (no shop/item pickup
  reachable yet). No production code changed; `luajit
  tests/run_tests.lua`: 519/519 pass.

- **2026-08-16, task #150 CLOSED**: a 5th pass tried the one untried
  static angle -- decoding a full byte-window (before AND after, not
  just up to) around each of a fresh 48 distinct shadow-run failure
  locations. Found essentially none of them sit inside real German
  prose: one cluster (bank 8) is a systematic font/glyph enumeration
  TEST table, another (bank 9) is tightly-repetitive non-text binary
  data (likely misaligned-cursor landings, same root-cause class as
  task #81's own CHAIN-target findings). A second check -- searching
  the real, already-confirmed dialogue region for the same 25 byte
  values in legible context -- also came back empty; every hit was
  either an already-known opcode byte a pure text scanner can't
  recognize, or more non-text garbage. This project's own original
  digraph-closing methodology (find a clean word-fragment, solve it)
  is now genuinely exhausted against the current corpus from two
  independent angles. Closed with the same honest reasoning as task
  #127/#128 today: the one real remaining path (deep live injection to
  reach genuinely unreached dialogue) is a separately-scoped, known,
  substantial tooling investment, not pursued further this pass.
  `luajit tests/run_tests.lua`: 519/519 pass.

- **2026-08-16, "komplett autark interpretiert" gap analysis, first
  concrete step -- real NPC dialogue now live-decoded from ROM at
  runtime**: found real, static ROM offsets (via `dump_strings.py`) for
  3 dialogue lines that were only ever hand-transcribed before
  (`secondRoom.characterA`'s line, `characterB`/Amanda's 3-page
  monologue, `victoryLine`) -- 2 of them hit exactly the already-
  documented `0x5B`/`0x82` per-occurrence digraph exceptions this
  project's own `TextDecoder.lua` already flagged, confirming them
  precisely. New `src/import/DialogueTextResolver.lua` (pure Lua,
  general "decode real ROM ranges + splice documented literal
  overrides" primitive) + `VictorySequence:resolveSceneDialogue`
  wires this live into actual gameplay (shallow-copies scene data,
  never mutates the shared profile table `NpcCatalog` also reads with
  no `romData`). Self-caught 2 real bugs while wiring (an off-by-one
  terminator-offset mistake; a hand-transcribed string with a space the
  real ROM bytes never produce). Live-verified via a real `love .`
  launch + screenshot, not just the test suite. 7 new tests, `luajit
  tests/run_tests.lua`: 524/524 pass. Honest scope: 2 NPCs' worth of
  dialogue, not "all dialogue now generalized" -- a proven, reusable
  pattern for whoever continues finding more real offsets. The other
  concretely-actionable item from the same gap analysis (cache-pipeline
  read-side) is still open.

- **2026-08-16, "komplett autark interpretiert" gap analysis, second
  concrete step -- generated-cache pipeline's READ side wired for
  real**: `src/import/GeneratedCache.lua` (pure Lua) -- `tryLoad`
  wraps `require("data.generated.<name>")` in `pcall` (matching
  `RomLocator.lua`'s own convention for content bundled in the app's
  source tree); `verifyManifest` refuses a cache whose recorded SHA-1
  doesn't match the current ROM; `loadAll` reuses `RomExtractor
  .STAGES` directly, all-or-nothing. Wired into `CatalogExplorer.lua`
  (the one consumer whose 4 data sources exactly match `RomExtractor`'s
  4 stages) -- tries the cache first, falls back to the unchanged live
  decode when absent/stale. Live-verified via a real `love .` launch +
  screenshot with a freshly-generated cache present: confirmed the
  cache path actually ran and rendered correct real data. 6 new tests
  (gated on the cache actually existing -- honest skip, not fail, on a
  fresh checkout). `luajit tests/run_tests.lua`: 528/528 pass. Honest
  scope: one real, working, tested slice of the runtime switch --
  every other state (`Field`, `VictorySequence`, `Menu`, ...) still
  live-decodes `romData` for everything else; that migration is real,
  much larger, separate follow-up work.

- **2026-08-16, "then do those blockers... try another strategy" --
  player spawn/landing position substantially closed, room
  connectivity narrowed with a real lead**: a live hardware watchpoint
  on `$C244`/`$C245` (the exact indirect-write blind spot 6+ earlier
  static-analysis passes couldn't cover) found the real write site and
  its FULL live call chain back to the script cursor. Static pattern
  search then found the real, general, 186-record landing-position
  table this mechanism reads from (bank 14 exclusive, zero false
  positives anywhere else in the ROM, byte-exact cross-validated
  against both already-known real transitions). New
  `src/import/CutTransitionTable.lua` (4 new tests). Room connectivity
  itself stays open, but with a real, structurally strong,
  `roomSelectorTable`-range-matching lead (a 36-record companion
  table) not yet live-cross-validated. `rom_profiles.lua`'s 2 known
  landing citations updated with real ROM-table file offsets;
  rom-map.md's stale 2026-08-13 "Consolidated reference" section 4
  corrected in place. `luajit tests/run_tests.lua`: 532/532 pass.

- **2026-08-16, direct continuation -- room connectivity DECISIVELY
  CLOSED too**: live-traced the real `$4395` (`CALL $026DC`) call site
  for thirdRoom->fourthRoom directly -- found the SAME already-decoded
  landing record's own first operand byte (`A1`) is the real target
  `roomSelector`, fed to `$026DC` unmodified. Confirmed statistically
  across all 186 records (ranges exactly 1-15, zero gaps, matching
  `roomSelectorTable`'s real 16-entry size). Resolves fourthRoom's own
  long-standing "roomSelector 0 or 1?" ambiguity as a real bonus
  (`romRoomSelectorConfirmed=1`). Self-caught and corrected an earlier
  same-day hypothesis (a different sibling record type) that turned
  out to be a coincidence, not the real mechanism -- reported and fixed
  in place, not silently dropped. **Both of the two original blockers
  ("was fehlt für komplett autark interpretiert") are now closed for
  wipe-style cut transitions** -- the ROM's own dominant transition
  mechanism within a connected dungeon area; the genuinely-unconnected
  jump-cut and continuous-scroll styles remain separate, already-
  documented mechanisms outside this table's scope. `luajit
  tests/run_tests.lua`: 533/533 pass.

- **2026-08-16, direct continuation -- new-transition scope catalogued,
  live trigger-search time-boxed and honestly negative**: the 186
  landing records collapse to 82 genuinely distinct real transitions;
  36 of them (19%) target the `unknownRoomA` family this project has
  never found a live trigger for despite multiple earlier dedicated
  searches -- real, ROM-verified proof it's genuine intended content,
  not dead data. 9 more target roomSelector `14`, matching no
  currently-known room family at all -- a second, brand-new open
  mystery. 2 static angles for finding a real trigger both came back
  clean-negative (no coincidental table reference, no dialogue
  proximity). A time-boxed live exploration (every wall of willyRoom/
  secondRoom/thirdRoom/fourthRoom, correctly-scaled 300-frame holds,
  plus Amanda's full dialogue) found zero new `$D499` activity --
  self-caught and fixed a real methodology bug first (an
  instruction-count budget that only covered ~17 real frames, far
  short of the 64-220-frame real hold thresholds already established).
  Honest conclusion: real, valuable scope information, but the actual
  in-game trigger for anything beyond the 2 already-known transitions
  remains open -- likely gated behind story/quest progression past this
  project's own current checkpoint chain. No production code changed.

- **2026-08-16, direct continuation -- CutTransitionTable consolidated
  into the app and the website**: `CutTransitionTable.lua` gained
  shared, reusable logic (`distinctLandings`, `FAMILY_BY_ROOM_SELECTOR`)
  so both new consumers call the same real function. New rom-inspector
  tab "Raum-Übergänge" (filterable by target room family, Playwright-
  verified zero console errors) plus a consolidated `open-questions.js`
  entry telling the whole blocker-closure story for site visitors. New
  dev-only `TransitionExplorer.lua` (F10 from `Field`, plus
  `MYSTICQUEST_TRANSITIONS_DEMO`) browses all 82 real distinct
  transitions live in the actual LÖVE app, live-verified via 3 real
  `love .` screenshots. `rom-inspector/README.md`'s own stale section
  lists (missing 8 already-shipped tabs) refreshed to match reality
  while in there. Purely additive, no behavior change to shipped code.
  `luajit tests/run_tests.lua`: 535/535 pass.

**2026-08-18** ("dann unknownRoomA", direct follow-up to a milestone-
status review): the one static angle the 2026-08-16 entries above named
but never ran -- whole-corpus reachability of the 36 `unknownRoomA`
landing-record byte sequences through the now-complete interpreter --
was built and run for real (new `scripts/scan_unknown_room_a_trigger.lua`).
**Decisive structural negative, sharper than "not found"**: every one of
the 1357 known scripts starts in bank 8 or 9; the furthest any script's
cursor is ever observed to reach, corpus-wide, is **bank 12** (15 real
cross-bank `CHAIN`s, all landing in bank 11/12, none further) -- `unknownRoomA`'s
own records all live in **bank 14**, two banks past reach. All 15
bank-11/12 arrivals are accounted for: 1 halts on known-hard opcode
`0xEC`, 5 halt on an already-honestly-flagged synthetic-only stub
limitation (opcode `0x0C`'s data-dependent resume cursor), the other 9
hit a real, deterministic loop within 4-33 steps (not a budget limit --
confirmed via new per-script loop detection, which also surfaced a
side finding: `scan_all_scripts.lua`'s own `clean` bucket likely
conflates genuine completion with these same undetected idle loops).
**Narrows, not closes**: those 9 scripts' own real loop-exit conditions
are now the concrete next static target -- a short, specific list,
not the whole corpus. See `events.md`'s own 2026-08-18 entry for the
full trail. No production code changed; `luajit tests/run_tests.lua`:
575/575 pass.

**2026-08-18, same day** ("überlege neue Strategien für die größten
Blocker"): before opening new live-tracing work, cross-referenced this
project's own already-existing, disconnected findings first -- closed
two open items for free. **`roomSelector 14`'s own "second, entirely
new open mystery"** (flagged just above, 2026-08-16) turns out to
already be solved by a completely separate, earlier investigation
thread: `rom-map.md`'s own `roomSelectorTable` DE-field trace already
shows selectors 14 and 15 point at the exact same real metatile table --
`unknownRoomB`'s own already-resolved black-wipe backdrop, just via a
second index nobody had cross-checked against `CutTransitionTable`'s
own family table. Fixed in `CutTransitionTable.FAMILY_BY_ROOM_SELECTOR`,
website re-exported, 575/575 tests still pass. **Level/XP and Bestiary
turn out to share their exact root blocker**: `EnemyStatTable.lua`
(found 2026-08-17, a separate session, for an unrelated boss/room-story
question) has a real, cross-verified `xp` field, non-zero for 15 of 21
species -- the ONE currently-reachable enemy (row 16) is confirmed to
be one of the 6 genuine zero-reward rows, which is WHY the 2026-08-16
live-diff/opcode-audit searches above never found an XP write (a real
ROM fact, not a tooling gap). See `events.md`'s own 2026-08-18 entry for
the full trail. Both priority-table rows above updated.

**2026-08-18, direct continuation** ("die 9 schleifenden unknown room a
skripte, fahr fort"): disassembled each of the 9 loop points before
live-tracing anything. Found and fixed 2 real bugs in the scan's own
synthetic stub (`isFadeActive`/`isQueueBlocked` were defaulting the
wrong direction per their own handlers' doc comments) -- real, measured
effect (23 more scripts progress further, a 16th cross-bank CHAIN
appears), but the headline finding is UNCHANGED: still bank 12 is the
furthest reached, still zero hits. All 16 real candidates now cleanly
classified into 3 already-understood causes: 1 hits known-hard opcode
`0xEC`; 5 hit the already-flagged `0x0C` list-exhaustion limit; the
other 10 ALL hit the exact same handler (`$3297`, `queueGate`'s "queue
empty" branch) -- confirmed, per that handler's own doc comment, to be
THE single largest blocker in the whole 1357-script corpus, unblockable
by any single-script synthetic run by construction (needs a separate,
external cross-actor dispatcher). **Static angle genuinely exhausted for
unknownRoomA** -- live re-exploration would repeat the already-negative
2026-08-16 time-boxed search, not a new strategy. Recommending this
thread be set aside for now in favor of other open blockers. See
`events.md`'s own 2026-08-18 entry for the full trail. `luajit
tests/run_tests.lua`: 575/575 pass, no production code changed.

## Superseded by this file

`gen1recomp-analysis.md`, `architecture.md`'s own "What's deliberately
not built yet" section, and this file's own pre-2026-08-11 version all
listed several of the above as "not started" when they were, by
2026-08-10, actually finished (map transitions, the event system's
discovery, save, the real damage formula). Cross-reference
`progress.md`'s dated entries for the authoritative blow-by-blow if
this file and that one ever disagree again — `progress.md` is the
living log, this file is a periodically-refreshed summary of it.
