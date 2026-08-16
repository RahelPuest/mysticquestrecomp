# Combat — status summary

Required by the project's master brief as a maintained, topic-focused
doc. Full evidence trail in
[rom-map.md "Player stats struct and combat"](rom-map.md) — not
duplicated here.

## Confirmed real-time action combat — VERIFIED

Mystic Quest's combat is real-time contact/action combat (the genre's
actual Seiken Densetsu 1 design), not a separate turn-based battle
screen — damage applies directly during normal field movement, no mode
switch observed.

## Player stats struct — VERIFIED

WRAM `$D7B2`: `curLP`(u16) `maxLP`(u16) `curMP`(u16) `maxMP`(u16)
`level`(u8) ... `gold`(u16 at `+12`) — exact match against the live HUD
at every field, cross-checked against Data Crystal's independently-
derived US-cartridge RAM map (zero address shift). Implemented in
`src/entities/Stats.lua`.

## Damage application primitive (`$3E30`) — VERIFIED, player-specific

A clean 16-bit subtract-current-HP-clamped-at-zero routine, confirmed
this session (2026-08-09) to be hardcoded to the player's own `$D7B2` —
NOT a generic routine reusable for enemy HP (2 live hits caught via
watchpoint both targeted the player, matching contact damage exactly).
Implemented in `Stats:damage()`.

## Damage formula (`$50AC`) — PARTIALLY TRACED, one operand now identified

Combines a defense-like read (`$D6C3`), a real multiply routine
(`$2B7B`), and a pseudo-RNG roll through a fixed ROM noise table
(`$2A1E`) before calling `$3E30`. `Enemy.PLAYER_ATTACK_DAMAGE = 1`
remains an UNVERIFIED placeholder.

**`$D6C3` identified (2026-08-10, P1 revisited): it's a real, COMPUTED
PLAYER-side stat, not enemy data.** Traced its only write site (bank 2,
file `0x09801`) live from title screen through 15 million further
steps (only 2 real writes the whole trace, both reassigning the exact
same value `6` — i.e. genuinely a stable, rarely-recomputed derived
stat, not something read fresh per-enemy):

```
$97E0  LD A,(0xD7C0) / BIT 3,A / RET NZ   ; a real flag-gated skip
$97E6  CALL 0x5BA7 / LD B,A                ; likely an equipment-bonus lookup
$97EA  LD A,(0xD7C2) / ADD A,B
$97EE  LD (0xD6C1),A / LD (0xD7DF),A       ; a SIBLING derived stat, mirrored
$97F4  LD A,(0xD6C0) / LD B,A
$97F8  LD A,(0xD6C2) / LD C,A
$97FC  LD A,(0xD7C1) / ADD A,B / ADD A,C
$9801  LD (0xD6C3),A / LD (0xD7E0),A       ; $D6C3 = base($D7C1) + $D6C0 + $D6C2
```

**`$D6C3 = a base stat (WRAM `$D7C1`) + two equipment/bonus values
(`$D6C0`, `$D6C2`)`** — a real "total stat = character base + gear
bonus" computation, mirrored to `$D7E0` (plausibly for HUD display).
`$D7C0`/`$D7C1`/`$D7C2` sit exactly `+0x0E`/`+0x0F`/`+0x10` past the
already-VERIFIED player-stats struct base (`$D7B2`), right after the
struct's own known `gold` field (`+0x0C`, a u16) — reads as a real,
clean extension of that struct (a flag byte, then two base-stat bytes),
not a coincidence of nearby addresses.

**Net effect on P1**: `$D6C3` is very likely the PLAYER's own computed
defense (reducing damage the player takes), not an enemy stat — this
resolves half of the original "which operand is attacker vs. defender"
question (this operand is the defender/player side specifically), and
redirects the search for real per-*enemy* ATK/DEF away from this
address. `$5BA7` (the likely equipment-bonus lookup) and `$D6C0`/
`$D6C2` (the two bonus inputs, very plausibly tied to the already-
decoded `weaponTable`/armor data from task P5) are concrete next steps
if this thread continues.

## `$50AC`, the real damage formula — FULLY DECODED and WIRED INTO GAMEPLAY (2026-08-10)

**Wired into actual gameplay (2026-08-10, later same day)**, closing a
real gap this project's own audit found ("wie weiter? sind alle neuen
Funde schon implementiert und dokumentiert?" — the formula below was
documented but `Field.lua` still used a fixed `Enemy.CONTACT_DAMAGE=3`
constant, not the real formula). Now implemented for real:
- `src/entities/CombatFormulas.lua` — the pure closed-form formula
  itself (`rollDamage(atk, def, noiseByte)`), unit tested directly.
- `src/import/NoiseTable.lua` — extracts the real 256-byte noise table
  (`$2A1E`, fixed bank 0) `$2B1E` reads from.
- `src/entities/CombatNoise.lua` — a real, faithful port of `$2B1E`'s
  own counter/cap/double-lookup-sum algorithm (disassembled fresh to
  get it exactly right — it's NOT a plain single-counter table walk,
  see that file's own doc comment), **bit-exact validated against a
  live mGBA trace**: captured 8 consecutive real draws (register `A`
  at `$2B1E`'s own `RET`, alongside the real WRAM counter/cap bytes)
  and fed the same real noise-table bytes + starting state into the
  Lua port — all 8 values matched exactly (see
  `combat_noise_test.lua`'s own ROM-dependent regression test).
- `Stats.defense` (default `6`, the real live-captured `$D6C3` value
  for a fresh level-1 character) and `Enemy.ATK` (`8`, this session's
  own P1 finding) feed the formula's two operands.
- `Field.lua`'s contact-damage code now calls
  `CombatFormulas.rollDamage(Enemy.ATK, self.stats.defense,
  self.combatNoise:draw())` instead of the old fixed constant.

**A real, reassuring cross-check, not a coincidence**: for THIS specific
pairing (ATK=8, DEF=6), `base=3` and the noise term always rounds to 0
(the formula's own `/1024` floor never clears for `base` this small,
even at the maximum possible noise byte) — so real contact damage stays
exactly `3` regardless of the PRNG draw, reproducing the OLD,
independently-traced `Enemy.CONTACT_DAMAGE=3` constant exactly. The
noise term genuinely does matter for larger ATK/DEF gaps (see
`combat_formulas_test.lua`) — it just happens to be invisible for this
project's one currently-reachable starting encounter.

Direct continuation of the entry above: traced `$50AC` live during 3
real contact-damage hits from the same live enemy, capturing full CPU
registers. **Real closed-form formula**:

```
base   = max(0, ATK - DEF) + 1        ; ATK = register B (attacker's own stat)
damage = floor((prngByte * base) / ~1024) + base   ; DEF = $D6C3 (player's own, see above)
```

A real "guaranteed base + small random bonus" shape — `$3E30` (already
documented as player-HP-specific) confirms this whole chain computes
damage TO the player, not a generic bidirectional formula. **Real,
live-captured enemy ATK = `8`**, stable across all 3 hits from the same
enemy (register `B`, read fresh at `$50AC`'s own entry each time) — the
first real, code-traced enemy attack-power number this project has
found.

**`B`'s exact source — resolved (2026-08-10, same day)**: a bank-4
"entity command dispatcher" (`$4446`, command byte `0xC9` = "attack")
resolves the attacking entity's slot in the `$D442` table, reads a
real per-entity stat-record pointer from `(slot+1)`, and loads
`B = *(pointer+3)`, `C = *(pointer+6)`, before calling into `$50AC`.
The pointer resolves to a real, general **8-byte-stride per-species
combat table** at bank 4, file `0x10c80`–`0x10df0` (~11 distinct
species patterns). ATK sits at record offset `+3` relative to the
pointer, live-confirmed `0x08` for the tutorial enemy, matching `$50AC`'s
`B` exactly across two independent contact hits. Full byte dump, field
map, and the live-trace evidence (plus the tooling bug in the earlier
"none of the 3 call sites fire" negative — a file-offset-vs-CPU-PC
comparison mistake, not a real absence) are in rom-map.md's
"P1 resolved" section. DEF-for-enemies is still not conclusively
identified; best candidates are two other varying fields in the same
record (offsets `+4`/`+5`), neither read by this specific damage
formula.

## Contact damage — VERIFIED

3 points per tick, roughly once per second. `Enemy.CONTACT_DAMAGE = 3`,
`Enemy.CONTACT_TICK_SECONDS = 1.0`.

## Attack button — VERIFIED

`A`, not `B` — confirmed twice: once live in an earlier pass, re-
confirmed this session by actually fighting the real boss under mGBA.

## Attack-swing visual — VERIFIED real, now implemented (2026-08-09)

Direct fix for a real, named gap (user report: "es gibt noch keine
attacke") — attacking previously applied damage with zero on-screen
feedback. Live OAM tracing during an A-press found 2 OAM slots (10/11),
otherwise permanently parked off-screen while idle, activate and sweep
through **exactly 4 real phases (4 real GB frames each, 16 total)**
using just 2 real ROM tile blocks (`0x08`/`0x09` and `0x0A`/`0x0B`,
found in bank 8 near the player's own tiles) repositioned and reflipped
each phase — real hardware faking a swing arc from minimal art, not an
animation this project invented. Captured independently per facing
direction (4 real, distinct sequences: up/down/left/right — left and
right are mirror images of each other, up and down are not). A single
A-press plays the full swing once; holding A for 180 real frames
straight only played it once — **no charge/power-gauge mechanic exists
on the attack button**. Implemented in `src/rendering/AttackSwing.lua`,
data in `rom_profiles.lua`'s `attackSwing` entry, wired into
`Field.lua` (swing triggers on every A press, independent of the
existing distance-based damage/reach check, matching that the real
swing plays standalone with no enemy nearby too).

**UPDATE (2026-08-09, later same day)**: hit detection now DOES use
this real swing geometry, not just its visual — see "Hit detection"
below. The static `ATTACK_REACH` circle this note originally left
unchanged is gone.

**CORRECTED (2026-08-09, second investigation round)**: "just 2 real
ROM tile blocks" above was wrong — that capture sampled OAM position
every frame but only checked VRAM tile *content* at 2 points. A full
per-frame content-offset re-trace (direct user request: "wieder bitte
die punkte im rom code finden anstatt das empirisch zu machen") found
**3 distinct real content blocks** (X/Y/Z), e.g. UP's 4 phases are
X,Y,X,Z, not two blocks alternating. `attackSwing`'s data and
`AttackSwing.lua` corrected. A real lesson: thoroughly sampling
*position* doesn't guarantee *content* was sampled thoroughly too.

## Thrust attack — VERIFIED real, distinct from the swing (2026-08-09)

Direct fix for a named gap (user report: "wenn sich der Spieler nach
vorne bewegt und dabei angreift, wird das Schwert nach vorne gestochen.
Wenn der Spieler im Stehen angreift, wird das Schwert normal
geschwungen"). This project had only ever tested "release direction,
then attack" — confirmed live that attacking WHILE still holding a
direction (moving) produces a real, different animation: shorter (12
real frames, not 16), a single fixed pose (no flip-cycling) moved
through 3 real motions on one axis — a real 4-frame gradual retract,
then an instant jump-and-hold thrust out, then an instant jump-and-hold
return — not a rotating arc. Captured every single real frame (the
motion isn't uniform) for all 4 directions. Reuses the swing's own real
block "Z" verbatim (byte-for-byte identical VRAM content) — the real
ROM's own art reuse. `src/rendering/AttackThrust.lua`, data in
`rom_profiles.lua`'s `attackThrust` entry. `Field.lua` selects swing vs.
thrust from `self.player.moving` (already-real, per-frame state) at the
instant A is pressed.

## Enemy hit-flash — VERIFIED real (2026-08-09)

Direct fix for a named gap (user report: "der Gegnersprite flasht kurz,
wenn er von einem Angriff getroffen wird"). Traced live: `OBP1` (the
enemy's own real sprite palette register — OAM attribute bit 4 confirms
the enemy uses OBP1, not OBP0) briefly changes from `$D0` to `$BF` for
about 1 real frame right as a hit lands, then reverts. Decoded: raw
indices 1/2 (normally white/light-gray) both flash to black, index 3
(normally black) flashes to dark gray — an almost-solid black
silhouette flash, not a color inversion. Implemented as a second real
`CreatureSprite` built with the flashed palette, swapped in for a couple
real frames on a landed hit — `rom_profiles.lua`'s `enemyHitFlash`
entry. HONEST LIMIT: getting a screenshot of the exact 1-2-frame flash
proved impractical with this project's existing screenshot harness (its
settle margin is longer than the flash itself) — verified at the logic
level (flash timer set exactly when hit detection fires) instead.

## Action meter — investigated, NOT found (2026-08-09)

User description: "unten im Screen... ein Action-Meter, das sich im
Zusammenhang mit den Angriffen verhält." Watched the real HUD bar
(`hudBar`) through real approach-and-attack sequences — it never
changes in response to movement or attacks; its only real activity is
one tile cycling through 5 patterns on a fixed ~75-frame period,
completely decoupled from gameplay (a decorative shimmer). Consistent
with the earlier 180-frame charge-hold negative result. No fillable
action meter found anywhere this project can currently reach.

## Hit detection — CORRECTED to use the real swing's own hitboxes (2026-08-09)

Direct fix for a real bug (user report: "es scheint als ob der Gegner
keinen Schaden nimmt"). The original implementation checked player-to-
enemy center distance once, at the exact instant A was pressed, against
a static `ATTACK_REACH` radius — but the real swing (see above) animates
outward over the *following* 16 real frames, so a press that visually
swings into the enemy a moment later never registered a hit; the check
had already run. Replaced with `AttackSwing:getHitboxes(px, py)` —
real per-phase rectangles at the swing's own captured `dx`/`dy`/size,
checked every frame the swing is active against the enemy's real AABB
(`Enemy:overlaps`, the same test contact damage already uses), one hit
per swing. Verified live: a single landed swing now drops enemy HP
19->18. Still no confirmed enemy-HP RAM address exists (see "Enemy HP"
below) — this is about *when* a hit is checked, not a new way to read
the real HP value itself.

## Idle/spawn facing — CORRECTED to UP (2026-08-09)

The attack-swing capture above incidentally answered a question the
idle sprite alone can't (see "Player facing" below — left/up/down all
render identically): a never-moved fresh spawn's swing exactly matches
the swing captured after deliberately holding UP, not the one captured
after holding DOWN. The real idle/spawn facing is **UP**, not "down" as
this project had assumed without ever actually verifying it.
`Player.DEFAULT_FACING` corrected accordingly.

## Power/charge gauge — no fillable gauge found; a real static HUD bar was (2026-08-09)

Direct user report of a missing "Poweranzeige" in the HUD, raised twice
across two feedback rounds. First round: investigated the field HUD's
own captured *background* tilemap (text-only) and the menu screen
(text-only), and a sustained 180-real-frame attack-button hold (no
charge indicator) — no fillable gauge found in any of those.

**Root cause found, second round**: this project had only ever dumped
the background map for the HUD strip. Live `LCDC` at the real room has
bit 6 set — the **WINDOW layer** is active with its OWN separate
tilemap (`$9C00`), never checked before this pass. Real `WY`/`WX`
(128/7) place the window exactly over the HUD strip. Its row 1 (screen
row 17, just below the `LP`/`MP`/`G` text) is a real static horizontal
rule with an arrowhead — start-cap tile, 16x repeating line-segment
tile, end-cap tile — confirmed by direct visual comparison against a
live mGBA screenshot (a solid black line spanning the HUD width).
**Always the same 16 segments in every capture** — no evidence this is
a value-driven gauge rather than a fixed decoration, consistent with
the first round's charge-hold negative result. Implemented as a static
element (`src/rendering/HudBar.lua`, `rom_profiles.lua`'s `hudBar`
entry) — a real, previously-completely-missing HUD element is now
drawn, even though it isn't literally a "power" meter.

**Still open**: window row 0 (the actual `LP`/`MP`/`G` text row) uses a
different, not-yet-decoded tile set from the regular dialogue font this
project's `Font.lua` reuses to draw readable-but-not-literal HUD text —
real icon/label tiles (the "HPMSGLE/" note, a real candidate gauge/bar
graphic near `~0x22300-0x22900` in bank 8) remain unplaced/
unimplemented; may belong to a screen this project hasn't reached yet
(a level-up screen, the deathblow gauge tied to WRAM `$D858`, etc.).

## Enemy HP — VERIFIED real ROM value, found via direct code trace (2026-08-09)

Per explicit user instruction ("keine Vermutungen. Schaue was im Code
passiert, wenn die HP des Gegners auf 0 gehen") this was traced with
execution/return-address breakpoints and disassembly, not empirically.
Method: single-step the CPU (`tools/rom/watcher.py`) through a live
kill, watch every WRAM write in the struct region, then walk the call
stack backwards from the routine that actually hides the enemy's
sprites to whoever decided to call it.

**Real 16-bit enemy HP: WRAM `$D3F4` (low byte) / `$D3F5` (high
byte)**, little-endian. Confirmed by disassembling the damage-subtract
routine directly (bank 4, ROM file offset `0x1070B`, local address
`$470B`):

```
$470B  LD D,H \ LD E,L        ; DE = damage amount (from caller)
$470D  LD A,($D3F5) \ LD H,A  ; HL = current HP, high:low = $D3F5:$D3F4
$4711  LD A,($D3F4) \ LD L,A
$4715  CALL $2BAB             ; HL -= DE (16-bit subtract, sets Z/C)
$4718  JR Z,$471C             ; result == 0            -> clamp dead
$471A  JR NC,$471F            ; no borrow (still > 0)   -> store real HL
$471C  LD HL,$FFFF            ; underflow or exact 0    -> DEAD sentinel
$471F  LD A,H \ LD ($D3F5),A
$4723  LD A,L \ LD ($D3F4),A
```

So HP is stored as a normal decrementing 16-bit counter, but "dead" is
represented as the sentinel `$FFFF` (not `0`) — reached either by
landing exactly on 0 or by any hit whose damage exceeds remaining HP.
This matches the earlier `$C2xx`-region entity "alive" bytes also using
`$FF` as their own dead sentinel (see the despawn trace below) — the
same convention reused at two different struct scales.

**Real starting HP and real per-hit damage, found (2026-08-09, later
pass) — direct answer to the P1 task ("real enemy/monster stat table"),
per explicit instruction to work the big milestones.** Two more real,
code-traced numbers, both now wired into `Enemy.lua` (superseding the
old `HP_TO_CLEAR=19`/`PLAYER_ATTACK_DAMAGE=1` button-mash-reproduced
placeholders):

- **Real starting enemy HP = `31`** (modal value — see the full
  probability breakdown below; this is not a fixed constant). Watched
  the very first write to `$D3F4`/`$D3F5` from a fresh spawn (not a
  mid-fight value). Real ROM routine, bank 4 file offset
  `0x10340-0x10372`: computes a product via the SAME real 8-iteration
  shift-add multiply primitive (`$2B7B`) already known to drive the
  player damage formula, then divides the 16-bit product by 16 via a
  real `ADD A,A`/`RL C`/`RL B` x4 idiom — hand-verified against the
  actual captured registers: product `$01F0` (496) in, `$001F` (31)
  out, and `496 >> 4 == 31` exactly, confirming the bit-shuffle is a
  plain right-shift-by-4 in disguise, not a second hidden operation.

  **The multiply's own two operands, decoded (2026-08-09, further
  pass)**: the caller (bank 4 ROM `0x10318`, local `$4318`, `CALL
  $4334`) passes `DE` = a real per-creature record pointer (a plain
  address into the currently-mapped bank, not a further indirection —
  live-captured as `$48B9`, statically confirmed against the ROM file
  at file offset `0x108B9`; see "Real per-creature record layout"
  below). Inside the HP-init routine:
  - `C`/`HL` = the byte at `(DE+1)` — a **real per-species multiplier
    byte**, `2` for this creature (file offset `0x108BA`).
  - `A` = the return value of a *different* subroutine, `CALL $2B1E`
    (bank 0, always mapped) — live-captured as `$88` (136). Disassembly
    of `$2B1E` shows it reads-and-increments a persistent WRAM counter
    at `$C0B0` (clamped against a cap byte at `$C0B1`, wrapping back
    instead of overrunning it) and uses that counter to index a real
    256-byte table at fixed-bank ROM offset `0x2A1E` — dumping that
    table's bytes shows genuinely noise-shaped data (`c6 7e 81 6b 4b fb
    e2 54 f6 bd df 7c 1c e1 87 01 bf 31 de 56 72 0f 47 67 66 59 aa 88
    3c ea 13 7b d2 85 a1 d8 55 2f 37 ae ...` — no visible structure),
    i.e. **this is a real pseudo-random-number generator implemented as
    an advancing index into a fixed noise table**, a standard GB-era
    technique. `A` is then right-shifted 4 times (`n = A >> 4`, so
    `n` is really just the table byte's own high nibble, 0-15) and
    two's-complement-negated (`NEG(n)`) before feeding the multiply —
    live-verified: `$88 >> 4 == 8`, `NEG(8) == $F8` (248), matching the
    exact `A` value captured right at the `CALL $2B7B` site.

  **Real closed-form formula** (for this one creature's species byte,
  2): `HP = ((256 - n) * 2) >> 4` for `n = 1..15` (uniform draw from
  the noise table's high nibble), giving **31 with real probability
  8/16** (`n=1..8`) and **30 with real probability 7/16** (`n=9..15`).
  For `n=0` (1/16 chance) the ROM routine takes a real conditional
  branch that *skips* the multiply entirely, leaving the pre-multiply
  zero-extended species byte in place — working through the same
  right-shift-by-4 trick this degenerates to `2 >> 4 == 0`, i.e. a real
  code path exists for the enemy to spawn with **0 HP** on roughly 1/16
  of spawns. This specific edge case is recorded as found, not
  explained (dead code vs. a real rare-but-intended spawn state is
  UNKNOWN — no evidence either way yet), and is deliberately NOT
  reproduced in `Enemy.lua` (`HP_TO_CLEAR` stays pinned at 31, the
  modal draw) until it's better understood or a second creature's data
  confirms the pattern.

  **Real per-creature record layout, partially decoded** (file offset
  `0x108B9` in this live capture — this offset itself is per-spawn, not
  a fixed table location; only the *field offsets relative to the
  record pointer* are the reusable finding):

  | Offset | Value (this creature) | Role |
  |--------|------------------------|------|
  | `+0x00` | `5` | UNKNOWN |
  | `+0x01` | `2` | Real HP-formula species multiplier (see above) |
  | `+0x02`, `+0x03` | `0`, `0` | UNKNOWN (possibly ATK/DEF, but both zero here is inconclusive either way) |
  | `+0x04` | `6` | Real OAM body-part slot count — confirmed: the very next routine (ROM `0x10373` on) uses this as a loop counter over the already-known 14-slot `$D442` despawn table, writing `6` real per-part OAM entries |
  | `+0x05` | `22` (`0x16`) | Passed to a `CP $FF`-gated dispatcher (`$2BDD` → `$1F93`) — looks like an item-drop or special-ability config slot (the `$FF` sentinel reads as "no drop"/"none"), not confirmed as a combat stat |
  | `+0x08` | nibble-packed | Consumed by OAM/tile-index setup code (`SWAP A`/`AND 0x0F` idioms) — graphics config, not a stat |
  | `+0x0E` | 16-bit pointer (`$4E15`) | OAM template pointer (feeds the same `$D442` sprite-slot setup routine) |
  | `+0x14` | 16-bit pointer (`$4E15` also, in this capture) | Read by a separate caller (ROM `0x1031B`) into a WRAM slot, plausibly a script/event pointer — not traced further |

  **Major update (2026-08-10): this "per-creature record" is the SAME
  real ROM structure as the message-settings table found independently
  this same day (see [text.md](text.md) "The real message-settings
  table found").** The live-captured record pointer here (file
  `0x108B9`) is byte-for-byte identical to that table's `messageID=16`
  record (both sessions independently captured `5, 2, 0, 0, 6, 22, ...`
  at the exact same file offset) — this is genuinely one unified
  "battle/event trigger" record combining message-display settings
  (reveal speed, decoration-sprite list) AND enemy-spawn setup (the HP-
  formula species byte, an OAM-slot repeat count feeding the real
  enemy-alive flag `$D3E8`) in one 24-byte struct, not two separate
  systems that happen to share a pointer by coincidence. `+0x01`
  (species multiplier) is now confirmed to vary realistically across 20
  real records (`2` to `255`), not just one data point.

  **`+0x02`/`+0x03` — traced live, RULED OUT as ATK/DEF, real role
  found instead.** A real, distinct code path (bank 4 file `0x1057D`)
  reads both bytes — `record[2]` then `record[3]` — each individually
  passed through a shared conversion call (`$45AE`) and a distinct
  follow-up (`$3D21` for byte 2, `$3D7D` for byte 3), ending in a write
  of the literal constant `0xD0` to WRAM `$C0AC` (a hardware-palette
  shadow register, the same family as the already-known `$C0AA`=OBP1
  shadow). **Reads as real per-creature PALETTE configuration**, not a
  combat stat — a plausible, common technique for reusing one sprite
  across multiple differently-colored enemy variants. Both bytes are
  `0` for the one record this project has live-verified end-to-end
  (`messageID`/creature `16`, "0/0" plausibly meaning "use the default
  palette, no override") — real, substantial variation exists across
  the other 19 records (`+0x02` ranges `0x00`-`0xd2`, `+0x03` ranges
  `0x00`-`0xfa`), consistent with real per-enemy palette variety.

  **So: real ATK/DEF fields, if they exist as separate per-creature
  bytes at all, are NOT at `+0x02`/`+0x03`** — that hypothesis is now
  retired with real evidence, not left open indefinitely. The
  remaining ~15 undeciphered bytes of the 24-byte record (see text.md
  for the full byte-by-byte status) are the next candidates if this
  thread continues; a second creature's own record with a genuinely
  different species byte (rather than more fields of the same
  `messageID=16` record) is still the concrete next step for anything
  ATK/DEF-shaped specifically, since this record is fundamentally
  message/scene-scoped, not necessarily where per-species combat stats
  would live at all.

  **Resolved elsewhere, same day**: real per-species ATK *was* found —
  in a completely different, dedicated 8-byte-stride table (bank 4,
  file `0x10c80`–`0x10df0`), not this 24-byte message/event record. See
  "`$50AC`, the real damage formula" above and rom-map.md's "P1
  resolved" section for the full trace. That table's own DEF-shaped
  candidate fields (`+4`/`+5` relative to the record pointer) remain
  unconfirmed, same as this record's.
- **Real per-hit player damage = `4`.** Simply read directly off the
  live CPU's `HL` register at the exact instant execution entered the
  damage-subtract routine (`$470B` above) during a real landed swing —
  no inference needed, `HL` *is* the damage operand by that routine's
  own calling convention (see the disassembly above: `LD D,H \ LD E,L`
  reads it straight into the subtrahend). Real ROM damage formula
  itself (`$50AC`, see "Damage formula" above) still not decoded to the
  operand level — this is the one real *result* it produced for this
  weapon/enemy pairing, live-observed, not derived.
- **Reconciles the old empirical `HP_TO_CLEAR=19` finding, doesn't
  contradict it**: `ceil(31 / 4) = 8` real landed hits are needed, not
  31 and not 19 — the originally-reproduced "19 A-presses" count was
  real button presses, most of which were real *misses* (the swing/
  thrust hitbox only overlaps the enemy for part of each real animation
  window — see AttackSwing.lua/AttackThrust.lua), not a formula
  mismatch. 8 landed hits out of ~19 presses (~42% real connect rate)
  is a plausible number for a narrow, timing-sensitive hitbox.

**Real death-dispatch check**, bank 4 ROM offset `0x1025F` (local
`$425F`): once per event-dispatch tick, the game reads `$D3F5` (the HP
high byte) and does `BIT 7,A` — since `$FFFF`'s high byte is `$FF`, bit
7 is set exactly (and only) once HP has hit the dead sentinel. If set,
it jumps straight to `CALL $4575` (ROM `0x10575`) instead of the normal
per-tick enemy-AI/event list processing; if clear, HP is still positive
and normal processing continues.

**Real death routine, `$4575`→`$4425`→`$0AE3`** — traced by breaking on
each call and reading the return address off the stack (`tools/rom/
watcher.py`'s `.step()` + a live `cpu.sp` peek), not by reading a
disassembly listing cold:
- `$4575` (ROM `0x10575`) is called unconditionally once bit 7 is seen
  set; it does no further HP check, meaning by the time anything calls
  it the outcome is already decided.
- It calls `$4425` (ROM `0x10425`), which walks a 14-entry table at
  WRAM `$D442` (built at enemy spawn time, listing that enemy's own
  OAM body-part slot indices — the same six part-slots visually
  confirmed earlier as tiles 56/58/60/62 in the hit-reaction pose) and,
  for each non-`$FF` entry, calls the generic single-slot despawn
  routine at `$0AE3` with that slot index in `C`.
- `$0AE3` (ROM `0xAE3`) operates on the generic entity struct at
  `$C200 + slotIndex*16`: zeroes the position pair at struct+4/+5,
  zeroes the entity's own 8-byte OAM shadow-copy block (pointed to by
  a pointer stored at struct+8/+9, via a real memset-style loop at
  `$2B5D`), then writes `$FF` to struct+0 (that slot's own "alive"
  sentinel) so re-entry is a no-op.
- Live-captured for this enemy: six calls with `C = 7..12`, i.e. struct
  bases `$C270`,`$C280`,`$C290`,`$C2A0`,`$C2B0`,`$C2C0` — matches the
  six body-part OAM pairs seen going blank simultaneously.

**Explicit negative result on the "fireball explosion" claim**: this
entire traced code path — from the `$D3F5` bit-7 read through both
despawn routines down to the final zero-fill loop — only ever *clears*
existing position/OAM-shadow bytes to 0 or `$FF`. No instruction in
this chain writes a new OAM entry, loads new tile IDs, or calls
anything resembling a sprite-spawn routine. If a real fireball/
explosion effect exists on enemy defeat, it is not part of *this* call
chain (the generic per-monster "hide all my parts" cleanup) — it would
have to be triggered from wherever `$D3F5` gets read/acted on
elsewhere, or from a higher-level battle-end/story-event routine not
yet traced. Not re-asserting the earlier (user-corrected) "it's just an
instant vanish, no effect at all" conclusion either — this only rules
out the specific despawn chain traced here, not other parts of the ROM.
**Forward trace done (2026-08-09, same day)**: followed `$D3F5` from the
moment it's set forward to the visual despawn, both in code and live.

- **Code**: the HP-subtract routine (`$470B`) is itself called from
  `$4612` (ROM `0x10612`); its caller checks the *result* (`JR
  Z,$10618` / `RET NC`) and, only on death, falls into a real
  "on-death hook" at ROM `0x105C9` (local `$45C9`). That hook: reads
  the enemy's own type byte at `$D3E8`, calls two small accessors
  (`$0C3E`/`$0C2D`, both `struct[$C200+idx*16 + {4,5}]` reads — the
  enemy's own position), passes them through `$4188` which stores that
  DE pair into a small table at `$D3F6 + ($D446)*2`, forces `$D3F0`
  and `$D3E9` to `1` (short-circuits the normal per-attack cooldown so
  the next dispatch tick runs almost immediately — this is *why* the
  despawn was observed a few attacks later rather than instantly: the
  dispatcher itself only runs on the next attack-processing event, not
  every raw frame), then `CALL $42B0` (queues an event: saves HL to
  `$D43C`/`$D43D`, increments the `$D3EC` pending-event counter) and
  `CALL $4209` (clears two more flags). **None of this writes a new
  OAM entry or loads a new tile ID either** — the `$D3F6` table write
  looks like it's recording the enemy's death *position* for whatever
  consumes `$D3EC`'s event queue (a plausible candidate for triggering
  victory text/item-drop logic at that recorded spot), not for a
  sprite.
- **Live/runtime**: captured a full 40-slot OAM snapshot every single
  frame from the instant `$D3F5` became the dead sentinel through the
  actual visual despawn (~87-140 real frames across repeated captures).
  No slot outside the already-known player (8-13ish) / enemy (14-25)
  ranges ever went active, and no already-active slot's tile ID ever
  changed to a value not already part of the normal walk/swing/hit-
  reaction set. Confirms the code-level finding at the pixel level: for
  this enemy, in this encounter, nothing resembling a fireball/
  explosion sprite is ever drawn on death.

Both checks agree, so this is now a settled negative **for this specific
enemy/encounter** — not a claim about every enemy type in the ROM (a
boss or a different monster bank could plausibly hook `$D3EC`'s event
queue differently). If the user has seen fireballs on a *different*
enemy or room, that would need its own trace.

Superseded: `Enemy.HP_TO_CLEAR = 19` (a reproduced button-mash count,
not a decoded stat) and the previous "not found, `$C254`/`$C255` is a
lead" entry — both replaced by the verified struct above. See
`docs/progress.md`'s P1 task.

## Enemy movement — VERIFIED real, not invented

Not a fixed enemy in earlier passes' sense — the real creature patrols
via a genuine 8-step repeating delta cycle (25 real GB frames per step)
plus a real ~5-frame "correction" hop once per lap, captured by sampling
live OAM position every single frame with no player input. Cross-checked
against actual rendered pixels (not just memory) to rule out a sampling
artifact — 4 pixel-identical frames, then exactly one frame that changes
by the enemy's own bounding box, confirming genuine discrete jumps with
no interpolation on real hardware. See `Enemy.MOVEMENT_CYCLE`/
`MOVEMENT_CORRECTION` in `src/entities/Enemy.lua`.

## Player facing — VERIFIED real X-flip; walk animation CORRECTED

Moving right sets the real OAM X-flip attribute bit and swaps the
sprite's tile column order; left/up/down share the same unflipped art.
Re-confirmed with fresh per-direction OAM captures this session
(2026-08-09), same result: only RIGHT ever flips — this specific claim
holds up.

**CORRECTED (2026-08-09, later same day)**: this section used to also
claim "no animation exists at all," based on 400 frames of sampling the
OAM tile *index* (confirmed unchanging). Direct user pushback ("es muss
doch irgendwo im ROM eine tabelle... mit den animationsphasen sein
oder?") prompted checking the raw VRAM *byte content* at that same
index instead — it changes every few frames while moving, a real DMA
content-swap animation the index-only check structurally could not see.
Found a real, clean, steady-state 2-phase leg cycle (4 real GB frames
per phase) for DOWN and for LEFT/RIGHT independently; UP showed no
confirmed change in any window this project could test without
contaminating the result with the real contact-hit reaction (see below)
— left as an honest "not found," not re-claimed as a settled negative.
Implemented in `src/rendering/PlayerSprite.lua`, data in
`rom_profiles.lua`'s `playerAnimation` entry. See `CreatureSprite
:draw`'s `flipX`/`flipY` params and the "Idle/spawn facing" entry above
for the earlier, still-standing correction (the *default* facing).

## Real contact-hit reaction: knockback + invincibility flicker — VERIFIED real, IMPLEMENTED (2026-08-09, task #12)

Found while isolating UP's walk animation (2026-08-09): real contact
with the living enemy triggers the player being knocked back and
becoming invisible/flickering. Originally only approximately captured
("~6 real frames" knockback, "~8 further real frames" invisible).

**Re-captured precisely this pass**, frame by frame from the exact
instant `$D7B2` (current LP) drops, watching both the player's OAM Y
and whether its OAM tile *content* (not just index) matches its own
known-good ROM bytes. First attempt at this re-capture wrongly applied
`LCDC` bit 4's BG-tile signed/unsigned addressing rule to sprite tiles
and got "always invisible" as a false reading — caught and fixed:
**OAM/sprite tiles always use unsigned `$8000` addressing on real GB
hardware, regardless of `LCDC` bit 4** (that bit only affects BG/window
tiles). With that fixed, the real schedule (frame offset from the hit):

```
0-1    visible    (settling)
2-9    INVISIBLE  -- real knockback motion: OAM Y moves exactly 4px
                      every real frame, 8 frames, 32px total, always
                      away from the enemy along the approach axis
10-14  visible    (5 frames -- a real, not-smoothed-away irregularity;
                    every other visible run is a clean 8 frames)
15-22  invisible  (8 frames)
23-30  visible    (8 frames)
31-38  invisible  (8 frames)
39-46  visible    (8 frames)
47-54  invisible  (8 frames)
55+    normal     -- real invincibility window is exactly 55 frames,
                      just under the already-VERIFIED 60-frame
                      `Enemy.CONTACT_TICK_SECONDS` contact-damage
                      cadence, i.e. by design the player becomes
                      re-hittable almost immediately once invincibility
                      ends, not with a long safe margin
```

**Implemented** in `src/entities/KnockbackFlicker.lua` (pure Lua,
headlessly unit tested against the exact schedule above) and wired into
`Field.lua`: real knockback motion freezes player input for its 8
frames (a reasonable implementation choice, not itself independently
verified — the real ROM might still honor held input during knockback);
the player sprite is skipped entirely on real "invisible" frames;
contact damage is blocked for the real 55-frame window, not just the
existing `CONTACT_TICK_SECONDS` cooldown. Knockback direction is
computed as the dominant axis from the enemy's box center to the
player's, snapped to one cardinal direction — only the one real,
directly-tested case (approaching from the south, the only direction
the actual room's layout allows) is independently verified; see
`KnockbackFlicker.lua`'s own doc comment for a real edge case found
during this pass's own screenshot testing (an aggressively-held approach
against the enemy's own patrol movement can compute a knockback
direction that points toward a wall instead of open floor).

Not independently ROM-code-traced (no WRAM knockback-timer/velocity
field or ROM routine address is known) — real, precise, live-captured
behavior reproduced faithfully, the same evidentiary standing as
`Enemy.MOVEMENT_CYCLE`'s own real captured-not-decoded data. A genuine
ROM-code trace remains a reasonable future upgrade.

## Movement speed — VERIFIED both axes, no diagonal

1px/frame both horizontal and vertical (measured independently, not
assumed). Diagonal movement is NOT allowed — holding two directions
simultaneously moves only vertically (verified for the simultaneous-
fresh-press case; a stateful/sticky nuance around release order was
observed but not fully characterized — see `src/entities/Player.lua`).

## Debug tools (Milestone 9's explicit request) — real, implemented

F1 overlay shows player/enemy stats, position, size, last fired event.
F4 toggles invulnerability, F5 heals, F6 instantly clears the enemy. F1
overlay also draws real hitbox/collision outlines (player, enemy,
attack-reach circle) when visible. See `Field:drawDebugOverlay`.

## Enemy DEF + the real per-species stat table — the ATK half CLOSED, DEF still genuinely open (2026-08-12)

Direct continuation of P1 ("Gegner-DEF-Formel + Bestiary" chosen from
a set of user-offered next steps). Two real, separate results:

**1. The real per-species ATK table, fully dumped and extracted as
reusable data.** The 8-byte-stride, ~11-species table already located
in rom-map.md's "P1 resolved" section (bank 4, file `0x10c80`-
`0x10df0`) turns out to have EXACTLY **46 rows / 11 distinct species
patterns** (byte-exact dump confirms both the row count and the table's
real boundary — the byte immediately after `0x10df0` is a completely
different, non-matching pattern). Real ATK per species (row order):
`140, 140, 33, 33, 8, 0, 188, 188, 77, 77, 121` — the `8` is this
project's own already-live-verified tutorial-enemy value, now
confirmed to sit at row 19 (0-based) alongside 10 real siblings never
previously dumped in full. Implemented as `src/import/
EnemySpeciesTable.lua` (generic decoder + a `groupBySpecies` helper),
wired into `rom_profiles.lua`'s new `enemySpeciesTable` entry, and
locked in by a real-ROM regression test that checks the full byte dump
against the ROM, not just the count.

**2. Enemy DEF — one more real lead chased and RULED OUT, still
genuinely unresolved.** `Enemy.lua`'s own `PLAYER_ATTACK_DAMAGE` doc
comment had left one thread open: a bank-trampoline dispatch with a
hardcoded `A=0` argument, "one hop further, not yet followed," inside
the real player-hits-enemy call chain (`$27CE`). Followed it by static
disassembly: `$27CE` calls `$04AA` (an invincibility-timer/`$D3E8`-
alive-flag check, unrelated to damage math) and THEN dispatches through
`$1F35` (a real case/bank-N-table indirect-call, the SAME shape as the
`$1F64` text-system dispatcher from this session's earlier work) with
the hardcoded case `0`. That resolves to bank 3's own table, entry 0,
file `0xC02C` — which turned out to be the ALREADY-KNOWN general
"iterate the 8-slot `$C4E0` actor array, run one ambient per-frame tick
for each live entry" routine from the earlier script-system
investigation (see events.md). **A real, useful NEGATIVE result**:
this specific trampoline call is an unrelated ambient housekeeping
tick that happens to fire near the damage code, not part of the damage
chain at all — it CANNOT be where a DEF read happens, closing off this
specific lead for good rather than leaving it as a stale "not yet
followed" note.

**Net, honest state of enemy DEF**: still not found. Real per-hit
player-to-enemy damage stays the already-documented flat, live-traced
`4` (`Enemy.PLAYER_ATTACK_DAMAGE`) — no code path in either direction
this project has now traced (player→enemy OR the fully-decoded
enemy→player `$50AC` formula) reads the two DEF-candidate fields in
the new species table (row-relative `+5`/`+6`, `EnemySpeciesTable
.lua`'s own `defCandidate1`/`defCandidate2`). Real possibilities left
standing, not chosen between: (a) enemy DEF genuinely doesn't exist as
a stat in this direction — player damage may just be flat-per-weapon
by design (not unusual for this genre); (b) DEF is read by a different
entity-dispatcher command this project hasn't traced yet (the same
`$4466` dispatcher handles more than the `0xC9` "attack" command, per
a static skim this pass — not followed further); (c) the two candidate
fields are something else entirely (an elemental type, a variant flag)
the way the 24-byte message/event record's own early "ATK/DEF?"
candidates turned out to be palette config, not stats.

## Not yet implemented

~~Invulnerability *frames* (a real i-frame window after taking damage,
distinct from the F4 dev toggle), knockback~~ — DONE (2026-08-09, task
#12, see "Real contact-hit reaction" above). Still not implemented:
projectiles, real enemy AI beyond the one replayed movement cycle,
status effects, XP/leveling, boss-specific logic beyond the one
encounter. Real enemy stat table: HP formula (task P1), ATK (task P1,
now extracted for all 11 real species, see above) both real and
decoded; DEF remains genuinely open, not merely unimplemented.

## Task #5 continued (2026-08-14): the $4466 dispatcher's other 3 commands checked for DEF -- another real negative, plus the real HP formula now implemented in Lua

Direct instruction ("mach 11, 12, 5, 10, 75 in dieser Reihenfolge, stoppe nicht"). Picked up the one concrete, previously-untried lead from the 2026-08-12 entry above: "the same `$4466` dispatcher handles more than the `0xC9` 'attack' command ... not followed further."

**Corrected a real bank-resolution mistake made while re-investigating**: the dispatcher's own real CPU address `$4466` is bank 4 -- its real FILE offset is `4*0x4000 + (0x4466-0x4000) = 0x10466`, not `0x4466` directly. An initial disassembly attempt at the raw file offset `0x4466` (bank 1, unrelated code) was caught and discarded before drawing any conclusion from it.

**Disassembled the real command-switch table** (file `0x10446` onward): after the already-known `CP 0xC9` (attack) check, the real dispatcher ALSO handles 3 more real command RANGES via `AND 0xF0` + range compares: `0x40-0x4F` -> `$4480`, `0x50-0x5F` -> `$44D3`, `0x30-0x3F` -> `$450E` (any other command byte falls through to `LD A,0x00 / RET`, a real no-op). **Disassembled all 3 real handlers in full.** All three share a near-identical real structure (resolve the entity slot, `CALL $461C`/`$4636`, several more real sub-calls, ending in `SET 7,H` + writes to real WRAM `$D3F2`/`$D3F3`, then `CALL $4728`) -- this is a real, coherent **positioning/movement command family** (writing what this project's own established convention already treats as a real X/Y position pair), NOT a stat-reading family. **None of the 3 real handlers reads the per-entity record's own `+5`/`+6` DEF-candidate fields** (no `LD HL,5/6 / ADD HL,DE` pattern anywhere in any of the three, unlike the `0xC9` handler's own confirmed `+3`(ATK)/`+6` reads).

**Net, honest result**: this closes off the last concretely-named lead from the 2026-08-12 entry. Real enemy DEF (in the player-attacks-enemy direction) remains genuinely not found after now 3 separate, real, static-analysis passes (the `$27CE`/`$1F35` ambient-tick dead end, and now all 3 alternate `$4466`-dispatcher command families). Hypothesis (a) from that entry ("enemy DEF genuinely doesn't exist as a stat in this direction -- player damage may just be flat-per-weapon by design") is now the best-supported reading, though still not proven by a positive finding (only by exhausting every concretely-named negative lead this project has produced so far).

**The real HP roll formula (the `n=1..15` case, already fully decoded 2026-08-09) is now implemented as a real, tested Lua function**: `CombatFormulas.rollHP(speciesByte, noiseByte)` (`src/entities/CombatFormulas.lua`), using the project's own already-ported `bit` library for exact `>>4` shifts (matching the real Z80 `SRL`/`ADD`/shift sequence, not float rounding). Exhaustively tested against every real `noiseByte` value in every real `n`'s own 16-byte range (`combat_formulas_test.lua`), confirming the live-verified 31 (prob 8/16) / 30 (prob 7/16) split exactly. The real, still-UNEXPLAINED `n=0` case (odds 1/16, a genuinely different ROM code path this project has never traced) fails loudly (`assert`) rather than fabricating a value, per this project's own "no silent fallbacks" rule -- verified by a dedicated test that every `noiseByte` 0-15 raises. `Enemy.HP_TO_CLEAR` is DELIBERATELY left un-wired to this new function (stays the fixed modal value `31`) -- wiring it in would introduce a real, live 1/16-odds crash in actual gameplay for the still-open edge case, a live-availability regression this project isn't willing to accept for an edge case that's still genuinely open. The function is real, correct, and ready for a future caller once `n=0` is resolved.

New tests: `combat_formulas_test.lua` (+2: the full 31/30 split, and the honest n=0 failure). Full Lua test suite: 403 -> 405.

**Honest remaining gaps for task P1/#5**: (1) enemy DEF (player→enemy direction) -- 3 separate real leads now exhausted, still not found; (2) `n=0`'s own real HP-formula behavior -- traced structurally (a real conditional skip) but not followed to its own real destination; (3) a second real creature's own live record never confirmed (the STATIC per-species table dump already generalizes structurally across all 11 species, but no second creature's OWN live `B`/`C` register capture exists to confirm the record layout holds beyond the one already-fought tutorial enemy).

## Task #5 continued (2026-08-15): a 4th real DEF lead closed via a self-caught off-by-one correction -- the "C register" lead was reading the wrong byte all along

Direct continuation (P1/#5 chosen again from a milestone-status review). Re-disassembled the `$4466`/`0xC9` "attack" dispatcher (file `0x10466`) fresh, byte-exact, to double-check the one thread the 2026-08-12/08-14 entries above left as "confirmed read but its real consumer was never found" -- the dispatcher's own `C` register, previously summarized as reading row `+6`/`DE+5` (`defCandidate2`).

**Self-caught correction**: the real bytes are unambiguous -- `LD HL,0x0006 / ADD HL,DE / LD C,(HL)`, i.e. `C = *(DE+6)`, which is row `+7` (the byte every previous pass already logged as "constant `0x00` in every real row observed"), NOT row `+6`/DE+5 (`defCandidate2`). The earlier summary was off by one byte. `defCandidate2` (row `+6`) is, per this corrected read, never touched by this dispatcher at all.

**`C`'s own real destination, also closed this pass** (the genuinely new part, not just a correction): the call immediately after loading `B`/`C` (`$0256`) is a real `$1ED7` selector `0x07` dispatch -- the exact same selector `0x07` -> `$50AC` mapping this project independently re-derived the SAME day while decoding selector `0x10` for the script-interpreter investigation (see events.md's own dated entry and `ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3`'s doc comment) -- a genuine, unplanned cross-validation between two completely separate investigation threads landing on the same real table entry. `$1ED7`'s own dispatch mechanism doesn't touch `B`/`C` at all (only `A`/`HL` are cached/restored), so both registers reach `$50AC` untouched -- and `$50AC`'s own, already-fully-decoded real formula (`CombatFormulas.lua`) simply never reads `C` (DEF comes from real WRAM `$D6C3`, the player's own defense, not a register). So `C` genuinely is a boring, always-`0` padding byte reaching an already-understood formula that ignores it -- a real, now airtight closure, not a "still not found" gap.

**Data-only observation, not itself decisive**: dumping all 11 real species rows (`EnemySpeciesTable.decode`/`.groupBySpecies` against the live ROM) shows a consistent pattern -- most ATK tiers appear as TWO variants sharing the same real ATK but different `flagVariant` (typically `144`/`146` vs `255`), with the `255` variant usually showing equal-or-higher `defCandidate1`/`defCandidate2` values (e.g. ATK=140: `flagVariant=144` -> `defCandidate1/2=2/2`; `flagVariant=255` -> `65/50`). Suggestive of a "regular vs. elite/palette-swap" monster pairing with the def-candidates scaling as part of that, but this is a STATIC correlation only -- no live code path that actually reads either field has been found despite now 4 separate, real, independently-exhausted leads.

**Net, updated assessment**: with this 4th lead closed (and the "C register" lead specifically now shown to have been chasing the wrong byte the whole time), the honest conclusion shifts from "genuinely open, more leads to chase" to "very strongly evidenced negative result" -- no code path in either combat direction this project has traced reads `defCandidate1` or `defCandidate2` as a stat. Real combat damage is flat per-weapon (player→enemy, `Enemy.PLAYER_ATTACK_DAMAGE=4`) and flat-per-species-ATK-vs-player-DEF (enemy→player, `$50AC`) -- this project's own already-implemented `CombatFormulas`/`Enemy` behavior already matches this conclusion exactly, so no code change follows from this pass, only a documentation correction and a strengthened, better-evidenced conclusion. The one remaining, NOT-yet-exhausted angle (per gap 3 above, still open) is a live trace against a genuinely different creature -- the second boss (see task #119/#96, `sixthRoom`) -- which would need new room-navigation tooling this pass didn't build (no existing checkpoint reaches that room; only the first, tutorial "gate creature" has a live-testable path via `checkpoints.py`).

## Player-side equipment bonus (`$D6C0`/`$D6C2`) FOUND -- a real, table-driven "class/kit" system (2026-08-15)

Direct, correct user challenge to the framing above ("es gibt beim spieler verschiedene rüstungen und waffen... das muss auch einen einfluss haben") -- the "flat damage" conclusion above is specifically about ENEMY-side DEF (does an enemy resist player attacks); it says nothing about whether the PLAYER's own equipped gear affects their stats. That's a real, separate, previously-flagged-but-unchased thread (`Stats.lua`'s own doc comment: `$D6C0`/`$D6C2`, "plausibly equipment/weapon bonus lookups... not confirmed").

**Live-traced with native mGBA write-watchpoints** (`tools/rom/watcher.py`, single-stepping from real cartridge power-on -- a full boot-to-first-room span, ~20M real SM83 instructions) against `$D6C0`-`$D6C4`/`$D7DF`/`$D7E0`. First, memory snapshots at each stage of the boot sequence narrowed the real write window to somewhere inside the very first 600 real frames (before "Neues Spiel" is even selected) -- then single-stepping that exact window found the real site.

**Real mechanism, bank 2, ROM `0xAE42`-`0xAE67`** (all offsets/values below are real, live-verified, byte-exact):
1. Copies 6 real "class/kit slot" index bytes from a fixed ROM table (file `0xAF1A`: `01 27 AF 11 B0 1C`) into WRAM `$D6E9`-`$D6EE`.
2. For each of those 6 bytes (masked `AND 0x7F`, 1-based), indexes into a SECOND real ROM table (file `0xA200`, 16-byte stride) via the real helper `$768C` (`recordPtr = tableBase + 1 + (index-1)*16` -- the `+1` offset is real, confirmed after an initial off-by-one misread was self-caught by cross-checking against the live capture) and reads that record's own byte `+1`.
3. Writes the 6 results, in order, to `$D6BF`-`$D6C4`.

**Byte-exact live confirmation**: index `0x27` (feeding `$D6C0`) and index `0x11` (feeding `$D6C2`) both resolve to real record byte `+1` = `2` -- an EXACT match to the value the already-decoded `defense = $D7C1 + $D6C0 + $D6C2` formula needs to produce the already-live-verified `6`. All 4 directly-watched slots (`$D6C0`/`$D6C1`/`$D6C2`/`$D6C3`) matched this record-lookup formula byte-for-byte at the moment of their FIRST write (before `$D6C1`/`$D6C3` get overwritten again by the separate, already-known "total" formula at `$97E0`-`$9801`).

**What this DOES confirm**: the player's own attack/defense sub-terms are NOT flat, hardcoded constants -- they come from a real, structured, per-slot table lookup (a genuine "class/kit template" system), exactly the kind of mechanism the user's own intuition expected. `Stats.DEFAULT_DEFENSE = 6` was already correct; this pass explains WHY, with real ROM bytes, instead of leaving it as an unexplained live capture.

**What this does NOT (yet) confirm -- honest, narrower scope**: this exact site runs ONCE, unconditionally, before the player has made any choice (not gated on hero/heroine selection in this trace, not re-run when the menu is opened) -- i.e. it's a fixed "new character" initialization, not yet proven to be REACTIVE to the player equipping a *different* weapon/armor mid-game. The more likely candidate for that is `$5BA7` (the separate, still-undisassembled call feeding the ATTACK side of the formula, `attack = $D7C2 + CALL $5BA7`) -- attack and defense clearly use two different real mechanisms here, and `$5BA7` was never traced this pass. Concrete next steps, not attempted yet: (1) disassemble `$5BA7` itself; (2) live-trace an actual in-game equip-change (open the menu, switch weapons, watch `$D6C1`/`$D7DF` for a NEW write); (3) decode the rest of each 16-byte "class/kit" record (only byte `+1` is understood so far -- the other 15 bytes, including what look like real embedded pointers, are unread) and cross-reference the 6 index values (`01`/`27`/`AF`/`11`/`B0`/`1C`) against `WeaponTable`/`ItemTable`'s own real indices to see if they correspond to actual equippable items or a separate "class" concept. No code changed this pass (the live-confirmed value already matches the existing implementation) -- pure disassembly/documentation.

## Task #128 continuation (2026-08-15): `$5BA7` disassembled; self-caught correction -- the total-stats recompute is NOT a one-shot init, it runs every real frame

Direct continuation, picking up exactly the 3 concrete next steps the entry above named.

**`$5BA7` disassembled in full** (file `0x15BA7`). Byte-for-byte: writes real per-index flags into two WRAM tables (`$CF00`/`$CEF8`, indexed by the caller's own `BC`), calls two untraced leaves (`$0C86`, `$0CBA`), then does a real 2-way table pick (`$2E99` vs `$2EB1`, selected by comparing a byte against `2`) indexed by real WRAM `$CF5C`, resolving a POINTER that gets cached into `$CF18` (indexed by `BC`), calls the ALREADY-known numbered-effect dispatcher `$297D` (the SAME real leaf opcodes `0xAC`/`0xAE`'s own phase 0/5 use, and `0x5BA7`'s own sibling scene-setup call), and finally returns `A = 7 - C` in the caller-visible register. Cross-checked against the real live state at `willy_room_free()`: `$D6C1` (the live total-attack byte) reads `6`, `$D7C2` (the base term) reads `2` -- so `$5BA7()` must currently return `4`, meaning `C=3` at its own final `SUB C`. Not yet independently confirmed via a live breakpoint at `$5BA7`'s own entry (see "still open" below) -- a real, consistent, but not fully closed cross-check.

**Self-caught correction, found via a live write-watchpoint on `$D6C1`/`$D7C0` through `willy_room_free()`** (holding `START`, navigating the menu, selecting `Waffe`): the write to `$D6C1` (CPU `$57EE`, matching file `$97EE` exactly under bank 2's real mapping) fires CONTINUOUSLY, roughly once per real frame, across the WHOLE session -- not "once, before any choice" as the entry above concluded. The computed VALUE stayed `6` throughout (matching that nothing about the player's actual gear changed), but the RECOMPUTE itself is clearly live and ongoing, not a boot-time one-shot. This retracts that specific claim from the entry above (the underlying `$D6C0`/`$D6C2` class-kit LOOKUP may still be one-shot at boot -- only the entry ABOVE $97E0 in the call chain, gated by `$D7C0` bit 3, was mischaracterized). `BC` at the write site varied between real invocations (`$042B`, then `$0404`) -- not a fixed per-player-slot constant, consistent with this routine servicing more than one real entity/context per frame (plausibly shared with enemy stat upkeep too, not confirmed).

**Real equip-swap test attempted, blocked on a real, honest precondition**: opening the in-game `Waffe` menu (via `checkpoints.willy_room_free()` + `START`/`DOWN`/`DOWN`/`A`) shows an EMPTY submenu -- the player starts with exactly one weapon ("Breit", already equipped, matching rom-map.md's own already-documented "empty starting inventory" finding at `$D6C5-$D6D4`/`$D6DD-$D6E8`) and no alternate weapon to swap TO. A genuine live equip-CHANGE test needs the player to first ACQUIRE a second real weapon (a shop purchase or a found item) -- neither reachable from the currently-built checkpoint chain (`willy_room_free` is the furthest point with a proven navigation script). Time-boxed here rather than pursued further this pass; a concrete, well-scoped next step (extend the checkpoint chain to a real shop or item pickup) for whoever continues, not a dead end.

**Genuinely still open**: (1) `$0C86`/`$0CBA`/`$297D`'s own real effects (all untraced further); (2) the real MEANING of the `$2E99`-vs-`$2EB1` table pick and what `$CF5C` represents; (3) an actual, positive equip-CHANGE observation (blocked as above); (4) live-confirming `C=3` at `$5BA7`'s own real entry via a breakpoint (the cross-check above is consistent but derived, not directly observed). No code changed this pass -- pure disassembly + live observation; `Stats.lua`'s existing implementation is unaffected (nothing found here contradicts it).

## Task #128 CLOSED (today): the 2026-08-15 `$5BA7` disassembly above was reading the WRONG BANK -- correct disassembly found, closes the mechanism question decisively

Direct continuation of task #128, picking up its own last-named "genuinely still open" items. Before live-tracing anything, re-derived `$5BA7`'s own real file offset from first principles, using the exact same `fileOffset = bank*0x4000 + (cpuAddr-0x4000)` formula this project's own `ScriptPointerTable.lua`/`RomScriptStream.lua` already codify -- and immediately found a real, self-caught bug in the entry above.

**The bug**: the entry above computed `$5BA7`'s file offset as `0x15BA7` (implying bank 5), but the call site (`$97E6  CALL 0x5BA7`, confirmed via `tools/rom/disasm.py` to be the literal 3 raw bytes `CD A7 5B` at file `0x97E6`) executes entirely inside bank 2 (file `0x8000`-`0xBFFF`) with **no bank-switch write anywhere in the routine** (`$97E0`-`$9804`, the whole already-disassembled `$D6C3` block) -- a Game Boy `CALL` never changes which ROM bank is mapped at `$4000`-`$7FFF`, so the real target of `CALL 0x5BA7` is bank 2's OWN `$5BA7`, file `2*0x4000 + (0x5BA7-0x4000) = 0x9BA7`, not bank 5's.

**Proof this is the real fix, not just a plausible alternative**: disassembling file `0x15BA7` (`tools/rom/disasm.py`) produces 150 bytes of pure garbage -- dozens of back-to-back `POP BC`/`LD B,C`/`RST 0x38` fragments with no coherent control flow, obviously graphics/data bytes being misread as code. Disassembling the CORRECT file `0x9BA7` instead produces exactly 7 clean, complete, self-consistent instructions ending in a real `RET`:

```
0x9ba7  PUSH HL
0x9ba8  LD A,($D6E9)
0x9bab  LD HL,0x6200      ; = file 0xA200 -- the SAME "class/kit" record table
0x9bae  CALL 0x768c       ; the SAME real helper the $D6C0/$D6C2 lookup already uses
0x9bb1  LD A,(HL)
0x9bb2  POP HL
0x9bb3  RET
```

**This means the ENTIRE "multi-step, `$CF00`/`$CEF8`/`$0C86`/`$0CBA`/`$2E99`-vs-`$2EB1`/`$297D`/`SUB C`" routine the 2026-08-15 entry described was never real** -- it was a coherent-sounding narrative built from disassembling the wrong bank's bytes. Every item in that entry's own "genuinely still open" list -- `$0C86`/`$0CBA`/`$297D`'s effects inside `$5BA7`, the `$2E99`-vs-`$2EB1` table pick, `$CF5C`'s meaning, live-confirming `C=3` via a breakpoint -- is now moot, not open: none of that code is actually part of `$5BA7`. (`$0C86`/`$0CBA` themselves are real, and were independently, correctly identified elsewhere the SAME day, one day earlier, by task #108's own `EntityStructLayout` accessor-family work -- `$0C86` is the real `PARAM2` setter, `$0CBA` the real paired `+6`/`+7` setter -- they just don't get called from `$5BA7`.)

**The real `$5BA7` is trivially, decisively understood**: it reads WRAM `$D6E9` (the FIRST of the already-known 6 "class/kit slot" index bytes, `$D6E9`-`$D6EE`, ROM table `01 27 AF 11 B0 1C`), resolves it through the exact SAME `$A200`/`$768C` mechanism the already-verified `$D6C0`/`$D6C2` defense-bonus lookup uses (`recordPtr = tableBase+1+(index-1)*16`), and returns that record's own byte `+1` in `A` -- i.e. `$5BA7` is not a separate, novel mechanism at all, it's the exact same "class/kit record byte `+1`" lookup pattern, just reading slot 0 (index value `0x01`) instead of slots 1/3 (index values `0x27`/`0x11`, which feed `$D6C0`/`$D6C2`).

**Byte-exact live cross-check, now airtight**: `$D6E9`'s own ROM-table index value is `0x01`; resolving that through the real table gives file `0xA200 + 1 + (1-1)*16 = 0xA201`. Reading that byte directly from the ROM: **`0xA201 = 4`** -- an EXACT match to what the already-live-verified state requires (`$D6C1=6` total, `$D7C2=2` base, so the equip-bonus term the routine at `$97E6` adds must be `4`). This is a stronger confirmation than a live breakpoint would have been: a deterministic ROM byte read, not a single live snapshot -- closing "genuinely still open" item (4) outright (there is no `C` register or `SUB C` in the real routine to confirm in the first place).

**Item (3) (a positive, live equip-CHANGE observation) attempted again, still genuinely blocked, same real reason as before**: re-ran a fresh live single-step search (2,000,000 SM83 steps, ~114 real frames, from the `willy_room_free()` checkpoint) watching for `$D6C1`'s own write site (file `0x97ee`) -- zero hits. Consistent with, not contradicting, the 2026-08-10 entry's own original finding that this whole recompute only fires rarely (2 real writes across a full 15-million-step boot-to-field trace) -- catching a third live occurrence from an arbitrary later checkpoint within a small step budget was never likely to work, and isn't needed now that the mechanism itself is closed by the static byte-exact proof above. The actual blocker for a POSITIVE equip-swap test is unchanged from the 2026-08-15 entry: the player only ever has one weapon ("Breit") with nothing to swap TO, and no checkpoint reaches a real shop or item pickup yet -- confirmed still true (no "shop"/"Laden"/"kaufen" room has been found or wired anywhere in this project's own docs). A real, well-scoped follow-up for whoever extends the checkpoint chain that far, not attempted further this pass.

**Data-only, inconclusive follow-up attempted**: cross-referenced the 6 class-kit index values (`01`/`27`/`AF`/`11`/`B0`/`1C`) against `WeaponTable`/`ItemTable`'s own real `id` fields (the 2026-08-15 entry's own suggested next step #3). No clean structural link found -- `id` bytes collide across many unrelated records in both tables (e.g. `id=0x01` matches 2 different real items, `"Lebe"` at two different `categoryByte`s), the same kind of ambiguous, non-unique `id` space this project already found and reported honestly for `EnemySpeciesTable`'s own species-name cross-reference. Reported as attempted-and-inconclusive rather than forced into a claim.

**Task #128 CLOSED**: the equip-lookup mechanism itself (`$5BA7`, and by extension the whole `$D6C0`-`$D6C4` "class/kit table" system) is now fully, byte-exactly understood and cross-checked against live ROM state -- no further disassembly work is warranted. The one remaining thread (a live, POSITIVE equip-CHANGE observation) is a real, separately-scoped, well-understood blocker (needs new room-navigation tooling to reach a shop/item pickup), not a mechanism gap -- same honest closure shape as task #127. No production code changed (nothing found here contradicts `Stats.lua`'s existing implementation); this pass is pure disassembly correction + documentation. `luajit tests/run_tests.lua`: 519/519 pass (unaffected, no Lua code touched).

## Task #127 ("zweiter boss"), decisive correction: the "second boss" has NO real ROM trigger at its in-game location -- live-confirmed, not just inferred from prior static docs

Direct continuation of task #127 ("Live-trace second boss to fully confirm enemy DEF is absent"). Before attempting any live tracing, re-read `rom-map.md`'s own already-complete "Second boss investigation" section end to end -- it already states, in `rom_profiles.lua`'s own `secondBoss` doc comment, that this placement is "IMPLEMENTATION CHOICE, evidence-based... NOT an independently ROM-confirmed spawn trigger for this specific room", and that the underlying real evidence (5 message-settings records sharing species byte `0x16` -- the SAME species as the FIRST boss, not a different one -- with 3 real, reachable scripts confirmed to trigger it somewhere, room unknown) was already exhausted via static analysis.

**Built a new, permanent, reusable checkpoint** (`tools/rom/checkpoints.fourth_room_free()`) since none previously reached past `thirdRoom` -- the real `thirdRoom`->`fourthRoom` "cut" transition (per `rom_profiles.lua`'s own `thirdRoom.exits`) needed `RIGHT` first (40 frames, `third_room_free()`'s own resting X=112 sits outside the real `x=128-143` exit band) before `UP` (250 frames) actually triggers it; real landing settles at Y=88,X=120 (X matches the documented `landingX=120` exactly). Live-caught building this: holding `DOWN` to "walk clear" (every earlier checkpoint's own convention) instead walks the player back through the SAME real cut in reverse (confirmed via `$D392`/`$D393` reverting to `thirdRoom`'s own pointer) -- `LEFT` used instead, a horizontal move that doesn't re-trigger the north-south staircase.

**Live-confirmed, decisively, that no real creature exists anywhere in this room.** Walked `LEFT` all the way to the real west wall (X=0, ~120 frames from the landing spot, room pointer staying `fourthRoom`'s own the whole way -- a plain wall, not a further real transition) and dumped all 20 real entity slots (`$C200`+slot*16). Exactly one slot (4) shows a genuinely live, positioned entity -- the player itself (`ALIVE=0x12`, `POSY=0x58`/88, `POSX=0x00`/0, matching the live player position exactly). The other 6 non-dead-sentinel slots (0,1,2,3,5,6) all share the SAME default `ALIVE=0x08`/`TYPE=1`/`POSY=0`/`POSX=248` pattern -- an uninitialized boot-time placeholder, not a real positioned creature (confirmed by their total absence from the actual rendered screen). **This directly, independently confirms `rom_profiles.lua`'s own honest "not an independently ROM-confirmed spawn trigger" caveat -- not just by re-reading the docs, but by live-inspecting the real ROM's own entity table and finding it genuinely empty here.**

**What this means for task #127's own goal**: walking to the Lua port's own `secondBoss` location in the REAL ROM (via mgba) would show nothing to fight -- there's no live-testable DEF here because there's no real creature here at all. Testing DEF against a genuinely different real ROM encounter still needs one of the two already-identified, not-yet-closed paths: (a) find which real room triggers one of the 3 confirmed real scripts (533/1092/1240) -- already exhausted via static CALL-address search per the rom-map.md entry; or (b) force one of those 3 scripts to run via live injection -- the SAME real concurrent-script-interference obstacle task #150's own injection work ran into this same day, not attempted here. Time-boxed at this decisive negative result rather than pursued further -- a genuine, useful confirmation (this project's own `secondBoss` feature is correctly labeled, and the underlying species is confirmed to be the SAME as the first boss, not a new one -- so even a successful live trace here would NOT have added new DEF evidence beyond what's already established for species `0x16`), not a dead end disguised as one. No production code changed except the new, permanent `fourth_room_free()` checkpoint (a real, reusable asset for whoever continues either path above, or any other fourthRoom investigation).

## Task #127 CLOSED (2026-08-16): the remaining "harder paths" would not add real DEF evidence even if built -- closing rather than leaving perpetually open

Direct continuation ("mach in folgender reihenfolge 143, 149, 127, 150 und dann 34"). Re-read the entry above end to end before doing anything new, per this project's own established discipline of not re-investigating a question a prior session already answered.

**Re-assessed the two remaining "harder paths" against knowledge gained THIS session, specifically task #150's own deep dive into the real bank call-stack** (see events.md's own dated entry): path (b) above (force one of the 3 real trigger scripts, 533/1092/1240, via live WRAM injection) was explicitly named as blocked by "the same real concurrent-script-interference obstacle task #150's own injection work ran into." Task #150's OWN continuation this same session went further and root-caused that obstacle precisely: the real bank call-stack is shared by many unrelated, legitimate real subsystems, so any one-off injected state is swept away within about one real frame REGARDLESS of technique -- closing it for real would need a sustained, per-instruction "puppeteering" driver, a substantially bigger undertaking than a bounded experiment (see events.md's own "task #150... precise mechanism, still blocked" entry). Path (b) is therefore not just "harder" as the 2026-08-15 entry already said -- it now has a concrete, understood cost (the SAME large investment #150 itself is parked pending), not a vaguely-larger one.

**The decisive reason to close, though, is independent of that cost.** Both remaining paths exist ONLY to reach a live encounter against the "second boss" -- but that creature's own species byte (`0x16`) was ALREADY established (same session, 2026-08-15) to be the EXACT SAME species as the first, already-live-tested boss. Reaching it, however achieved, would re-confirm DEF-absence for a species this project has ALREADY confirmed DEF-absent for (`combat.md`'s own "very strongly evidenced negative result" -- no code path in either combat direction reads a DEF stat) -- not produce a single new data point. Investing in a substantially bigger live-injection driver (or an exhaustive room-by-room search for the 3 scripts' own real trigger) to re-derive an ALREADY-KNOWN conclusion is not a good use of further effort, regardless of how much smaller task #150's own work made that cost look.

**Task #127 is CLOSED** with this reasoning, not left open by default. If a genuinely NEW, different-species creature is ever found in this ROM (the roadmap's own Bestiary status already notes 11 real species exist in `EnemySpeciesTable.lua` with only 1 ever confirmed spawnable), THAT would be the real, valuable target for a fresh DEF live-trace -- not this specific already-same-species "second boss." No production code changed this pass; `luajit tests/run_tests.lua` unaffected by design (documentation-only), re-run anyway: 508/508 pass.

## MAJOR CORRECTION (2026-08-16): player-attacks-enemy damage is NOT flat -- it's the SAME real noise formula as $50AC, and the "flat 4" was a floor-rounding coincidence all along

Direct continuation, per direct user request to try a fresh angle on the (previously closed, "very strongly evidenced negative") enemy-DEF question specifically: "ob die WAFFE selbst einen variablen Schadenswert beiträgt". This DOES supersede part of the prior conclusion -- read this entry, not the "very strongly evidenced negative result" text above, as the current, decisive state of player-attacks-enemy damage.

**Method**: live single-stepped (`courtyard_enemy_engaged()`, real `A`-tap attack cadence matching `courtyard_boss_defeated()`'s own proven pattern) capturing full PC/bank history at the exact moment the real "pending damage" WRAM cell (`$D3F2`/`$D3F3`, newly identified this pass) gets written -- then walked the chain backward via `tools/rom/disasm.py`, register-capturing at each real hop instead of guessing.

**The real chain, fully disassembled and live-register-confirmed, bank 4 throughout**:
1. `$4495`: `LD BC,0x0004` -- a literal immediate, but used as a TABLE INDEX (`$466E`, `ADD HL,BC`), not the damage value itself. The indexed real ROM table lives at bank 4, file `0x10d31` (`02 02 00 00 20 00 00 08 | 02 02 00 00 20 00 00 00 | 03 02 00 00 20 00 00...`, a real, structured, repeating-period record shape) -- `table[+4] = 2`, further transformed by an untraced leaf (`$3DF4`) this pass didn't fully chase.
2. `$469B`: calls `$2BAB` (returns `HL=4`, live-confirmed), reads WRAM **`$CF63`** (live value `10` at the moment of a real landed hit -- a genuinely new, previously undocumented WRAM cell), multiplies them via `$2B7B` (a real 8-bit x 16-bit shift-add multiply routine, structurally the SAME primitive `$50AC`'s own formula uses), then rotates/shifts the product -- for THIS specific live value pair (`4 x 10`), the scaled contribution lands entirely in the discarded low byte, netting zero extra.
3. `$46F6`: **calls `$2B1E` -- THE ALREADY-KNOWN REAL COMBAT PRNG** (`CombatFormulas.lua`'s own PRNG, previously only known to feed the enemy-attacks-player direction) -- then `$2B7B` again (multiplies the PRNG byte by the real base, `4`), then `SRL H / SRL H` (keeps only the product's high byte, shifted right 2 -- an effective `/1024`-shaped scale, structurally identical to `$50AC`'s own `floor(noise*base/1024)`), adds the base back in.
4. `$44A6`-`$44CB`: takes the result (live-confirmed `HL=4`), forces bit 7 of the high byte set (a real "pending" marker), writes it to `$D3F2`/`$D3F3`.
5. `$4612` (already known from the 2026-08-11/14 entries above) later reads `$D3F2`/`$D3F3`, masks bit 7 back off, and applies it to enemy HP via `$470B` -- exactly the already-documented final step.

**The decisive correction**: this is the SAME real formula SHAPE as `$50AC` (`floor(noise*base/1024)+base`) -- player-attack damage is genuinely PRNG-driven and base-value-driven, not a flat hardcoded constant. **Why every prior live observation (8/8 consecutive hits, always exactly -4) looked flat**: for base `4`, the maximum possible product (`255 * 4 = 1020`) is still `< 1024`, so the noise term's own contribution mathematically floors to `0` for EVERY possible real PRNG byte -- an exact structural parallel to this project's own already-documented enemy-attacks-player finding that `rollDamage(8, 6, anyNoiseByte) == 3` for every byte, for the same reason. **The "flat, no formula" conclusion in the entries above was real, honest science given the leads chased at the time (no ATK-DEF subtraction was ever found, and that part is still correct -- no enemy-side DEF term exists anywhere in this chain), but it stopped one level too early**: it never reached the real noise-formula machinery, because that machinery's own output is numerically indistinguishable from a flat constant for this specific, only-ever-tested base value.

**Honest, explicitly open ends, not resolved this pass**:
- Whether the base `4` (and the real bank-4 `0x10d31` table it's read from) is genuinely tied to the player's CURRENTLY EQUIPPED weapon (varying if a different weapon were equipped) or is a fixed per-"attack type" constant independent of equipment -- `$3DF4`'s own real transform of the table byte, and the table's own full real semantics, were not traced further this pass. A real, testable, falsifiable prediction follows either way: if this base ever exceeds ~64 for some other real weapon/context (`64*4=256`, still `<1024` -- the real threshold where noise becomes visible is base `>256`), live combat against that weapon would show REAL, visible per-hit damage variance for the first time -- a concrete, well-scoped verification for whoever eventually reaches a second weapon (still blocked on the same "Breit is the only equipment, no shop/pickup reachable yet" precondition already documented above).
- `$CF63`'s own real meaning (live value `10` during this trace) is newly found but not yet identified against any other known stat/table.
- `$3DF4`, and the bank-4 `0x10d31` table's own remaining byte fields, are real but untraced.

No production code changed this pass -- `Enemy.PLAYER_ATTACK_DAMAGE = 4` remains numerically correct (it IS the real, live-confirmed value for the only currently-equippable weapon), but its own doc comment is corrected separately (see `src/entities/Enemy.lua`) to state the real mechanism instead of the now-superseded "flat, no formula" framing. Pure live disassembly/investigation this pass; `luajit tests/run_tests.lua`: 540/540 pass (unaffected, no Lua code touched).

## Direct continuation ("$3DF4/Tabellen-Semantik weiterverfolgen"): the base value's own proximate source mapped further, genuinely deeper than expected -- bounded here, honestly incomplete

Direct continuation, per the user's own explicit choice, chasing the previous entry's own named open thread (`$3DF4`, the bank-4 `0x10d31` table's remaining fields).

**Method**: rather than hand-simulate 8-bit rotate/shift arithmetic from static disassembly alone (a real, recognized error risk at this depth -- this pass caught itself making exactly that mistake once, misreading a table byte offset), built a single live trace with 19 named checkpoint addresses spanning the WHOLE chain (`$4495` through `$4708`), each live-capturing `A`/`HL`/`DE`/`BC` by direct register read rather than inference. All 19 checkpoints hit in one real attack.

**What this confirms, byte-exact, no ambiguity**: the LATTER half of the chain (from `$469B` onward: `A=10` at the real `$CF63` read, `HL=4`/`DE=4` arriving at `$46F6`, the real `$2B1E` PRNG call producing a live byte `A=145`, final `HL=4` at the RET) is now independently re-confirmed register-by-register -- the MAJOR CORRECTION above stands, strengthened, not weakened, by this closer look.

**What this pass found is genuinely MORE complex than assumed, and does NOT close cleanly**: the EARLIER half (how `$466E`'s own table lookup, `$3DF4`, and `$4685` combine to actually produce the `4` that reaches `$469B`) involves a real, previously-unknown gate this pass newly found: `$4685` reads WRAM **`$C0A0`** and only applies a real `3x/4` scaling transform if it equals `5` (`RET NZ` otherwise, per static disassembly) -- live-confirmed the branch actually taken varies between real invocations. A further leaf, `$2BAB`, is called from `$469B` and was NOT disassembled this pass. The live register captures across this earlier segment are real and correctly recorded, but this pass's own attempt to hand-derive a clean "table byte -> final base" formula from them did not converge to a confident, honest conclusion within a reasonable time-box -- reported as attempted-and-inconclusive rather than forced into a plausible-sounding but unverified narrative.

**Honest bottom line**: the DECISIVE part of the correction (a real PRNG-driven formula exists, explains the "flat" observation as floor-rounding) is unaffected and stands on its own solid, independently-confirmed evidence. The SPECIFIC question this pass set out to answer ("is the `4` base genuinely weapon-power, and what does the table represent") remains open -- now with more real, mapped structure (`$C0A0`'s own gate, `$2BAB` as the next concrete leaf) than before, but not resolved. A well-scoped, honestly-bounded follow-up for whoever continues: disassemble `$2BAB` and cross-check `$C0A0`'s own real meaning against already-known WRAM cells first, before attempting further hand-arithmetic.

No production code changed. `luajit tests/run_tests.lua`: 540/540 pass (unaffected).

## 2026-08-16, continuation ("Item-/Waffen-Effektformeln", per the user's own prioritized list): a decisive real negative result on weapon power, and an honestly-bounded item-stat-byte pass

Direct continuation of the user's own explicit priority order ("ok in der reihenfolge die du vorgeschlagen hast"): first of the two remaining `docs/roadmap.md` "Milestone 8/9 remainder" items -- whether player-attack damage's own `base` value (currently `4`, see the MAJOR CORRECTION entry above) is genuinely tied to the equipped weapon, the SPECIFIC open question named at the end of the entry directly above this one.

### Weapon power: a real, falsifiable, decisively negative empirical result

Rather than continue the `$2BAB`/`$C0A0` static-disassembly chase two prior passes already could not converge on (and which, this pass found, doesn't even lead anywhere weapon-specific: `$2BAB` disassembles to a completely generic 16-bit `HL = HL - DE` subtract-with-underflow-check primitive, not weapon-specific code at all -- `tools/rom/disasm.py` on file `0x2bab`-`0x2bbb`), this pass ran a direct, falsifiable, live experiment instead: **poke the real WRAM class/kit slot-0 index byte (`$D6E9`, the exact cell `$5BA7` is already, decisively known to read -- task #128, closed) to each of the other 5 real index values (`0x27`/`0xAF`/`0x11`/`0xB0`/`0x1C`) and observe real, actual combat outcome**, sidestepping the "no shop/pickup reachable yet" navigation blocker entirely (a live WRAM write is the same already-established technique this whole investigation relies on for reads, just applied write-side).

**Method**: `courtyard_enemy_engaged()`, poke `$D6E9`, then 40 real attack taps using `courtyard_boss_defeated()`'s own exact proven cadence (`hold=4, then_wait=6`), logging real enemy HP (`$D3F4`/`$D3F5`) after every single tap.

**Result, byte-exact and 100% reproducible across all 5 alternative values**: the real HP trajectory (`31 -> 27 -> 23`, i.e. 4 damage per landed hit, matching the already-known base) is **IDENTICAL** to the unmodified baseline for every one of the 5 pokes, with the poked `$D6E9` value itself confirmed still in place afterward (not silently reverted mid-session). A second, independent check confirmed `$D6C1` (the total-attack stat byte) and `$D7C2` (its base term) ALSO stay flat at `6`/`2` regardless of the poke, within 2 real frames of writing it -- meaning even the already-"closed" `$5BA7`-driven attack-stat recompute does not visibly react to a live `$D6E9` edit either (a real, mildly surprising finding on its own: whatever DOES drive `$D6C1`'s real value, it is not simply "re-read `$D6E9` every frame" the way task #128's own investigation assumed, OR it only recomputes on a specific triggering EVENT -- e.g., opening the equip menu -- not on every frame regardless of a raw memory poke).

**Honest scope of this negative result**: this decisively shows changing `$D6E9` (the mechanism `$5BA7` reads) does NOT change either the attack-stat readout or real per-hit combat damage in this live test. It does NOT prove weapon power doesn't exist anywhere in the ROM -- only that it isn't reached via this specific, previously-most-promising pathway. Given `$4495`'s own literal `LD BC,0x0004` (a hardcoded immediate table index, not read from any register that could reflect equipment) already suggested the damage-formula's own base-value table lookup is independent of weapon identity, this result is consistent with, not contradictory to, that earlier static read. **Working conclusion, held provisionally**: the currently-known damage-formula base (`4`) most plausibly represents a fixed per-ATTACK-TYPE constant (e.g. "physical melee hit"), not a per-weapon power value -- but this remains open until the real bank-4 `0x10d31` table's OTHER records (indices 0-3, 5+, never read for THIS attack type) are cross-referenced against something concretely equipment-related, which this pass did not attempt.

### Item heal amount: an honestly inconclusive static-byte pass, no live verification possible yet

Second half of the same priority item. **No live item-use trigger currently exists** to test this the same decisive way weapon power was just tested: a fresh character's items/spells lists are real, verifiably empty (`Inventory.lua`'s own doc comment), and the real WRAM struct backing a character's actual held-item inventory has never been traced (a genuinely separate, unsolved problem from the static `ItemTable` catalog this project already decodes) -- so there is no known way to grant a real item and observe a real `curLP` change via live mGBA tracing yet, the way `courtyard_boss_defeated()`'s own proven attack-tap loop made the weapon-power test possible.

**Static pass attempted instead**: dumped all 20 clean-named item/spell records' (indices 0-19; records 20+ have real but currently garbled/undecoded names, a known, already-documented `TextDecoder` limitation, not new) own 6 real "unknown" bytes (offsets 9-14, 0-based -- i.e. immediately after the already-understood `categoryByte`/before the trailing `id` byte). Byte offset 9 (the first of these 6) turns out to just mirror the record's own tier (`0x10` for basic items, `0xA0`/`0xB0`/`0x90` for the 3 real spell tiers) -- a real, minor, confirmable finding, but redundant with `categoryByte`, not a new discovery.

Byte offset 10 (the second) is genuinely suggestive but **does not converge to one confident, honest reading, and is reported as such rather than forced**:
- The 4 real status-cure spells (`Salbe`/`Auge`/`Bewege`/`Spruch`) show a clean bitmask progression (`01`/`02`/`04`/`08`) -- strongly suggestive of "which status ailment this cures," ONE bit per spell.
- The elemental attack items (`Flam`/`Eis`/`Bliz`/`Bomb`) show `08`/`12`/`20`/`40` -- plausibly a POWER progression (8/18/32/64), but `0x12` (18) sets 2 bits, breaking the clean-bitmask reading that fits the cure-spell group.
- The pure LP-restoring items (`Lebe`=20, spell-tier `Lebe`=16, `S-Lebe`=32) look like plausible round heal amounts; `Elixier`=`0xFF` (255, or "all bits set") fits EITHER "heals 255" OR "cures every status" equally well thematically (a real Seiken Densetsu elixir traditionally does both).

**Honest conclusion**: this byte's real meaning most plausibly differs BY ITEM TYPE (a bitmask for status-effect items, a scalar for damage/heal items) rather than being one uniform "power" field across the whole table -- or this reading is simply premature. Genuinely inconclusive from static analysis alone; NOT wired into `Inventory:useItem` (which continues to apply no numeric effect, exactly as before -- `ItemTable.lua`'s own doc comment updated to record this pass's specific, still-unconfirmed byte-offset candidate rather than leaving the field completely uncharacterized). A well-scoped, concrete follow-up for whoever continues: find the real WRAM held-item struct FIRST (the same kind of live, systematic search this project already used for the entity struct/room system), since without it there is no way to trigger a real item use and observe its real effect -- static byte-pattern-matching alone cannot responsibly close this.

`luajit tests/run_tests.lua`: 549/549 pass (unaffected -- no production code changed this pass, pure live/static investigation).
