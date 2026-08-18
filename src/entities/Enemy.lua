-- A stationary field enemy blocking a chokepoint -- models this
-- project's live-verified finding (docs/reverse-engineering/rom-
-- map.md "Breakthrough"): the starting room's creature is an enforced
-- collision blocker, not scenery, and deals contact damage while the
-- player is adjacent to it.
--
-- What's VERIFIED and modeled faithfully: real-time contact combat (no
-- separate battle screen), a hard collision block while alive, periodic
-- contact damage roughly once per second (CONTACT_TICK below), and the
-- attack button itself (A, not B -- re-verified by actually fighting
-- the boss live under mGBA with the corrected room/reach sequence, see
-- docs/progress.md; this project's rom-map.md "Breakthrough" entry had
-- already found this but the engine wasn't updated to match until this
-- pass).
--
-- What's a reasonable, clearly-labeled choice, not a decoded ROM fact:
-- the exact HP/damage numbers (the `$50AC` formula's operands are still
-- unknown, see rom-map.md "Player stats struct and combat"). HP_TO_CLEAR
-- is now grounded in a reproduced measurement, not a round-number
-- guess: fighting the boss with a fixed, steady press cadence (A held
-- 6 frames, released 10) took exactly 19 presses before its death
-- animation started. This is not necessarily "19 HP" in the ROM's own
-- terms (a press and a landed hit aren't provably 1:1 -- the attack
-- could have an animation lock this project hasn't measured against
-- press timing), but it's a falsifiable, reproduced number under a
-- stated methodology, replacing a plain guess.

local Stats = require("src.entities.Stats")
local FixedStep = require("src.core.FixedStep")
local GBTile = require("src.rendering.GBTile")
local EnemyMovementInterpreter = require("src.entities.EnemyMovementInterpreter")

local Enemy = {}
Enemy.__index = Enemy

-- VERIFIED real movement, not an invented/empirical pattern: this
-- project's earlier engine had the creature frozen in place, which real
-- live play does not match -- pointed out directly by a user report
-- that the boss should move based on ROM data. Traced the enemy's live
-- OAM position (screen = OAM - 8/-16, same convention as the player)
-- with no player input at all, sampling every single frame for 700
-- frames. Result: the position holds perfectly still, then jumps
-- directly to a new position (no interpolation) -- 32 such waypoints
-- captured. Independently cross-checked against actual rendered
-- pixels, not just memory reads (a user suspicion that this was a
-- sampling artifact of the screenshot interval): screenshotted every
-- individual frame across a hold-to-jump boundary and pixel-diffed
-- them. Result: 4 fully pixel-identical frames, then one frame whose
-- diff bounding box is exactly the enemy sprite's own box, then
-- pixel-identical again -- this is the literal displayed picture
-- holding still and jumping, not a gap between samples.
--
-- Frame-to-frame (dx, dy) deltas repeat as a clean 8-step cycle (a
-- flying/hovering patrol pattern), not noise or a random walk:
--   (+20,+7) (-30,+7) (+17,+5) (-31,0) (+17,-5) (-30,-7) (+20,-7) (-27,-3)
-- Per-step duration is itself measured data, not a single assumed
-- constant (a user insight that there might be a time delta too --
-- correct, and this project's earlier capture already contained the
-- answer, just oversimplified away)...
--
-- CORRECTED (direct user report that the boss movement pattern wasn't
-- 100% correct): the 8-step table below (and the whole "forward then
-- mirrored-negated return leg" model) turned out to be built from a
-- mis-tracked live capture -- re-verified fresh via mgba, this time
-- reading every OAM entry belonging to the creature (not assuming a
-- single 2x2/4-tile sprite the way the player/Willy are: the gate
-- creature uses twelve OAM entries, tracked here both by a single
-- stable slot and by the full 12-entry centroid, which agree exactly)
-- over a much longer 6000-frame window (the original pass only covered
-- 700 frames -- not long enough to ever see this cycle close). Result:
-- the creature's true patrol is a genuinely closed 33-step cycle (825
-- frames, each step 25 frames, same timing as before) -- summing to
-- exactly (0,0), confirmed by the centroid position at frame 950
-- matching frame 125 (one full period earlier) to the pixel, and by 9+
-- further consecutive steps matching one period later still. No
-- "boundary bounce"/correction hop and no invented mirror-return are
-- needed at all -- the cycle already returns to its own start on its
-- own; the previous model's "8 deltas don't sum to (0,0), so mirror
-- them back" reasoning was an honestly-reported observation at the
-- time, but from a 700-frame window that was simply too short to catch
-- the true, longer period. HONEST LIMIT UNCHANGED: the underlying ROM
-- routine/table was still not traced back to a ROM address this pass --
-- this is the now much more completely captured *output*, not the
-- decoded *algorithm*.
Enemy.MOVEMENT_CYCLE = {
  { dx = 4, dy = 7 }, { dx = 6, dy = 7 }, { dx = 7, dy = 5 }, { dx = 7, dy = 0 },
  { dx = 7, dy = -5 }, { dx = 6, dy = -8 }, { dx = 4, dy = -8 }, { dx = 1, dy = 2 },
  { dx = -4, dy = 7 }, { dx = -6, dy = 7 }, { dx = -7, dy = 5 }, { dx = -7, dy = 0 },
  { dx = -7, dy = -5 }, { dx = -6, dy = -7 }, { dx = -4, dy = -7 }, { dx = -7, dy = 0 },
  { dx = -4, dy = 7 }, { dx = -6, dy = 7 }, { dx = -7, dy = 5 }, { dx = -7, dy = 0 },
  { dx = -7, dy = -5 }, { dx = -6, dy = -7 }, { dx = -4, dy = -7 }, { dx = -1, dy = 0 },
  { dx = 4, dy = 7 }, { dx = 6, dy = 7 }, { dx = 7, dy = 5 }, { dx = 7, dy = 0 },
  { dx = 7, dy = -5 }, { dx = 6, dy = -8 }, { dx = 4, dy = -8 }, { dx = 3, dy = -3 },
  { dx = 4, dy = 5 },
}
-- VERIFIED: every one of the 33 real steps held for exactly 25 real GB
-- frames in the live capture (same timing this project already had
-- right).
Enemy.MOVEMENT_STEP_SECONDS = 25 * FixedStep.STEP

-- SUPERSEDED (2026-08-09, later pass) -- kept only as a dated note of
-- what this project used to reproduce empirically before the real
-- values below were found by direct ROM code trace (task P1, "real
-- enemy/monster stat table"), per explicit user instruction ("bearbeite
-- die großen Milestones jetzt" -> P1 was the highest-priority pending
-- item). 19 A-presses (hold 6f, wait 10f) landed the killing blow in a
-- live mGBA fight -- not proven to be exactly 19 landed hits 1:1, and
-- now known to be neither: real HP is 31, real damage/hit is 4 (see
-- HP_INIT_TRACE_NOTE / PLAYER_ATTACK_DAMAGE below) -- ceil(31/4) = 8
-- real landed hits, with the rest of those 19 presses being real misses
-- (the swing/thrust hitbox only overlaps the enemy for part of each
-- animation's real frame window -- see AttackSwing.lua/AttackThrust
-- .lua), not a formula mismatch.
Enemy.HITS_TO_CLEAR_METHOD_NOTE = "SUPERSEDED -- see HP_INIT_TRACE_NOTE."

-- VERIFIED (2026-08-09, direct ROM code trace, not empirical): the real
-- starting enemy's initial HP, watched live at WRAM `$D3F4`/`$D3F5`
-- (the same real 16-bit HP field this project's death investigation
-- found earlier the same session -- see docs/reverse-engineering
-- /combat.md's "Enemy HP" entry) from the very first write at spawn.
-- Real ROM routine, bank 4 file offset `0x10340-0x10372`: computes a
-- product via the same real 8-iteration shift-add multiply primitive
-- already found driving the player damage formula (`$2B7B`), then
-- divides the 16-bit product by 16 (a real `ADD A,A`/`RL C`/`RL B` x4
-- shift-right-by-4 idiom, confirmed by hand-tracing the exact captured
-- register values: product `$01F0` (496) -> final `$001F` (31), and
-- `496 >> 4 == 31` exactly).
--
-- UPGRADED (2026-08-09, further pass, task P1 continued): the multiply's
-- own two operands are now decoded too, by re-running the same live
-- trace with a watchpoint set BEFORE the enemy-spawn stretch (a first
-- attempt reused `reach_combat()` as-is and found the spawn write had
-- already happened before the watchpoint was even installed -- fixed by
-- installing it right before the battle-intro block instead). Real
-- result, both operands read straight off live CPU registers:
--   * `HL=2` at the `CALL $2B7B` site -- this is a real per-species byte
--     read from `(recordPtr+1)`, where `recordPtr` (`$48B9` in this live
--     capture) is itself a real per-creature record pointer, statically
--     confirmed against the ROM file (record base file offset `0x108B9`
--     -- see rom-map.md's enemy-record entry for the other identified
--     fields at this same offset).
--   * `A=0xF8` (248) at the same site -- NOT a fixed constant: it is
--     `NEG(x >> 4)` of a value `x` returned by a *different* subroutine
--     (`$2B1E`) that reads-and-increments a persistent WRAM counter
--     (`$C0B0`, clamped against a cap at `$C0B1`) and uses it to index a
--     real, genuinely noise-shaped 256-byte table living at fixed-bank
--     ROM offset `0x2A1E` -- i.e. this is a real PRNG-via-noise-table
--     mechanism, and enemy HP has a small but real random component,
--     not a single fixed value. `x=0x88` (136) was this live capture's
--     actual draw; `136 >> 4 == 8`, `NEG(8) == 248` (two's-complement,
--     matches the captured `A`).
-- Full formula (species byte = 2 for this one real creature): for
-- `n = randomByte >> 4` (0-15, uniform over the noise table), real HP
-- is `((256-n) * 2) >> 4` for `n >= 1` (31 for `n=1..8`, 30 for
-- `n=9..15` -- i.e. 31 with real probability 8/16, 30 with 7/16), or a
-- degenerate `species_byte >> 4 == 0` for the `n=0` case (1/16) via a
-- real conditional skip of the multiply entirely (`JR Z` in the ROM
-- routine) -- this last case is UNEXPLAINED (possibly dead code for
-- this creature, possibly a real "can spawn with 0 HP" edge case) and
-- NOT implemented here; `HP_TO_CLEAR` below stays pinned to 31, the
-- single most-common real draw, rather than guessing at the edge case.
-- Real per-species multiplier byte and PRNG mechanism are now decoded;
-- what remains open is a second creature's own species-byte value (to
-- confirm the *record layout*, not just this one instance, generalizes)
-- -- see docs/reverse-engineering/rom-map.md for the full trace,
-- the real per-creature record dump, and the open next step.
--
-- IMPLEMENTED (2026-08-14, task #5 continuation): the real formula
-- above (`n=1..15` case) is now a real, tested Lua function --
-- `CombatFormulas.rollHP(speciesByte, noiseByte)` -- exhaustively
-- cross-checked against every real noiseByte in every real n's own
-- 16-byte range, matching this project's own live-verified 31/30
-- split exactly. The genuinely unexplained `n=0` case (1/16 odds)
-- fails loudly there rather than guessing, per this project's own "no
-- silent fallbacks" rule -- see that function's own doc comment.
-- `HP_TO_CLEAR` below is DELIBERATELY left as the fixed modal value
-- (31), not wired to call `rollHP` at spawn time -- doing so would
-- introduce real, live 1/16-odds crashes for the unexplained n=0
-- case in actual gameplay, a live-availability regression this
-- project isn't willing to make for an edge case that's still
-- genuinely open. `rollHP` is available, correct, and tested for a
-- future caller once the `n=0` case is resolved (or a caller that
-- deliberately wants to accept that risk).
--
-- UPDATED (2026-08-10): this "per-creature record" turned out to be the
-- SAME real 24-byte struct as the message-settings table found
-- independently the same day (see docs/reverse-engineering/text.md) --
-- a genuinely unified "battle/event trigger" record combining message-
-- display settings AND enemy-spawn setup, not two coincidentally-
-- overlapping systems. The species byte (+0x01) now confirmed varying
-- realistically (2-255) across 20 real records, not just this one
-- instance. `+0x02`/`+0x03` (the earlier "ATK/DEF?" candidates) were
-- live-traced this pass to a real hardware-palette-shadow-register
-- write ($C0AC) -- real per-creature PALETTE config, NOT combat stats;
-- that specific hypothesis is retired. Real ATK/DEF, if it exists
-- separately, is not at this position -- see rom-map.md's own entry
-- for the full trace.
--
-- RESOLVED (2026-08-10, later same day): real enemy ATK found -- NOT
-- in this 24-byte record at all, but in a separate, dedicated 8-byte-
-- stride "entity command dispatcher" table (bank4 file 0x10c80-
-- 0x10df0). Live-confirmed: the bank-4 command dispatcher (command
-- byte 0xC9 = "attack") resolves this entity's slot in $D442, reads a
-- record pointer, and loads B=*(pointer+3) before dispatching into the
-- real damage formula ($50AC) -- B live-matched the enemy's own ATK
-- (8) exactly, twice, independently. See rom-map.md's "P1 resolved"
-- section and combat.md's "$50AC" section for the full trace, byte
-- dump, and field map. DEF for enemies still open (two other varying
-- fields in the same record, unconfirmed).
--
-- WIRED (2026-08-10, further same day): real enemy ATK, plus the now
-- fully-decoded $50AC formula itself, are wired into actual gameplay
-- -- see CONTACT_DAMAGE's own doc comment below.
Enemy.ATK = 8
Enemy.HP_INIT_TRACE_NOTE = "Real WRAM $D3F4/$D3F5 spawn-time write, " ..
  "bank4 ROM $10340-$10372 -- HP = ((256-n)*speciesByte)>>4 where n is " ..
  "a real PRNG-table draw (0-15) and speciesByte=2 for this creature " ..
  "(record+1, file offset 0x108ba) -- 31 with real probability 8/16, " ..
  "30 with 7/16. See rom-map.md."

-- NOT the real sprite size -- a generic single-tile fallback, same
-- reasoning as Player.DEFAULT_WIDTH/HEIGHT (see that doc comment): real
-- gameplay code always derives the actual size from `profile.graphics
-- .enemySprite.cols/rows * GBTile.TILE_W/TILE_H`, not a second,
-- independently-hardcoded number (direct user correction, 2026-08-09:
-- "bitte hardcode die sprite sizes nicht, nimm sie aus dem rom").
Enemy.DEFAULT_WIDTH = GBTile.TILE_W
Enemy.DEFAULT_HEIGHT = GBTile.TILE_H

-- VERIFIED (rom-map.md "Player stats struct and combat"): contact
-- damage was traced at exactly 3 points per tick, from an EARLIER pass
-- before the full `$50AC` formula was decoded.
--
-- WIRED (2026-08-10): `Field.lua`'s real contact-damage now calls
-- `CombatFormulas.rollDamage(Enemy.ATK, playerDefense, noise:draw())`
-- directly instead of this constant -- the actual ROM formula, not a
-- fixed number. Kept here (not deleted) as a real, live cross-check:
-- `rollDamage(8, Stats.DEFAULT_DEFENSE=6, anyNoiseByte)` == `3` for
-- EVERY possible noise byte (base=3 keeps the PRNG term's contribution
-- below the formula's own /1024 rounding threshold for this specific
-- ATK/DEF pairing -- real, not a bug: the formula genuinely has no
-- visible variance for this particular starting encounter, only for
-- larger ATK/DEF gaps). Still used by `boss_encounter_test.lua`'s own
-- minimal, love-free simulation, which doesn't need noise-level
-- precision.
Enemy.CONTACT_DAMAGE = 3
-- VERIFIED: roughly one contact tick per second in the original trace.
Enemy.CONTACT_TICK_SECONDS = 1.0
-- VERIFIED (2026-08-09, direct ROM code trace; RE-CONFIRMED 2026-08-11
-- with a deeper call chain): real per-hit damage, read directly off the
-- CPU's own `HL`/`DE` registers at the exact instant it entered the
-- real damage-subtract routine (bank 4, ROM `$470B`, see combat.md's
-- "Enemy HP" entry) during real landed swings -- exactly `-4` every
-- time, across 8 consecutive real hits in a fresh 2026-08-11 trace
-- (HP sequence `31,27,23,19,15,11,7,3,dead`, every step exactly 4).
--
-- MAJOR CORRECTION (2026-08-16, combat.md's own dated "MAJOR
-- CORRECTION" entry has the full disassembly): the earlier "flat
-- per-weapon damage, no live DEF subtraction" framing UNDERSOLD this.
-- The real chain (`$4495`->`$466E`[real bank-4 table lookup, file
-- `0x10d31`]->`$469B`[reads WRAM `$CF63`]->`$46F6`) genuinely calls
-- **`$2B1E`, the SAME real combat PRNG `CombatFormulas.lua` already
-- uses for the enemy-attacks-player direction**, through the SAME
-- `floor(noise*base/1024)+base` formula shape as `$50AC`. `4` really
-- is the live, real base value for the only currently-equippable
-- weapon ("Breit") -- but the reason every observed hit looks flat is
-- that `255*4=1020 < 1024`, so the noise term mathematically floors
-- to 0 for every possible real PRNG byte at this base -- the EXACT
-- same floor-rounding coincidence already documented for the enemy
-- formula's own base=3 case, not evidence of "no formula." Genuinely
-- still open: whether this base is really weapon-power (would need a
-- second weapon to test -- blocked, see combat.md) or a fixed
-- per-attack-type constant. `4` stays numerically correct either way.
Enemy.PLAYER_ATTACK_DAMAGE = 4
-- VERIFIED (see HP_INIT_TRACE_NOTE above): the real starting enemy's
-- own initial HP, found by direct ROM code trace, not reproduced by
-- button-mash counting. The real ROM value has a small random
-- component (31 with probability 8/16, 30 with 7/16, see
-- HP_INIT_TRACE_NOTE) -- 31 is the single most common real draw, not
-- an average; this project does not yet reproduce the randomness
-- itself, only the modal value.
Enemy.HP_TO_CLEAR = 31

--- `width`/`height`: real sprite pixel size (see DEFAULT_WIDTH/HEIGHT's
-- doc comment) -- omit only when no real ROM profile is available.
function Enemy.new(x, y, width, height)
  return setmetatable({
    x = x,
    y = y,
    width = width or Enemy.DEFAULT_WIDTH,
    height = height or Enemy.DEFAULT_HEIGHT,
    stats = Stats.new({ curLP = Enemy.HP_TO_CLEAR, maxLP = Enemy.HP_TO_CLEAR }),
    contactCooldown = 0,
    -- Real captured movement cycle state (see MOVEMENT_CYCLE above).
    -- `x, y` at construction time is real, VERIFIED-live waypoint 0
    -- (rom_profiles.lua's enemySprite.screenX/screenY) -- movement is
    -- applied as real relative deltas from there, not an absolute path.
    -- Just loops forward through the real 33-step cycle repeatedly (see
    -- MOVEMENT_CYCLE's own doc comment -- it closes on its own now, no
    -- forward/backward direction flag needed).
    movementIndex = 1,
    movementTimer = 0,
    -- Separate accumulator for the cosmetic X-flip cadence (see
    -- `updateMovement`'s own doc comment) -- decoupled from the real
    -- interpreter's own finer `TICK_FRAMES` cadence.
    flipTimer = 0,
    -- Real, ROM-data-driven interpreter (see `EnemyMovementInterpreter`
    -- own doc comment) -- attached by `Field.lua` when a real ROM +
    -- `CombatNoise` instance are available; nil falls back to
    -- `MOVEMENT_CYCLE`'s own replay (see `updateMovement`).
    movementInterpreter = nil,
  }, Enemy)
end

--- Advance the real captured movement cycle (see MOVEMENT_CYCLE's own
-- doc comment for the 2026-08-12 re-verification). No-op once defeated
-- -- matches the real creature disappearing on death rather than
-- continuing to animate.
--
-- SIMPLIFIED (2026-08-12, same re-verification pass): the real cycle
-- now genuinely closes on its own (sums to (0,0) over its real 33
-- steps), so this just loops forward through it repeatedly -- the old
-- forward-then-mirrored-negated-return-leg logic (and the ~5-frame
-- "correction hop" it needed to justify) is gone, not because it was
-- bad code, but because the real data it was built to reconcile no
-- longer needs reconciling.
-- WIRED (2026-08-13, direct user instruction: "der boss kampf an
-- sich... der ist hard coded. der soll aus den romdaten raus
-- interpretiert werden"): when a real `EnemyMovementInterpreter` is
-- attached (`self.movementInterpreter`, set by `Field.lua` once a real
-- ROM + `CombatNoise` instance are available), `updateMovement` drives
-- REAL per-tick ROM interpretation (real 3-level behavior tables, real
-- PRNG-driven choice -- see that module's own doc comment for the full
-- decoded mechanism) instead of replaying the captured `MOVEMENT_CYCLE`
-- table. `MOVEMENT_CYCLE`/`MOVEMENT_STEP_SECONDS` stay as the fallback
-- for callers with no ROM available (e.g. headless tests) -- see this
-- project's own "no ROM, no real data" convention elsewhere
-- (Player/Enemy defaults).
function Enemy:updateMovement(dt)
  if not self:isAlive() then return end
  self.movementTimer = self.movementTimer + dt
  if self.movementInterpreter then
    local tickSeconds = EnemyMovementInterpreter.TICK_FRAMES * FixedStep.STEP
    while self.movementTimer >= tickSeconds do
      self.movementTimer = self.movementTimer - tickSeconds
      local dx, dy = self.movementInterpreter:tick()
      self.x = self.x + dx
      self.y = self.y + dy
    end
    -- CORRECTED (2026-08-13, direct user report: "die animation des
    -- sprites ist zu schnell"): `movementIndex`'s own real cadence
    -- (driving `isFlipped`'s own parity toggle) was independently
    -- verified against the OLD, coarser `MOVEMENT_CYCLE` model at
    -- `MOVEMENT_STEP_SECONDS` (25 real frames/step) -- incrementing it
    -- once per the interpreter's own finer `TICK_FRAMES` (5 real
    -- frames) made the real flip toggle 5x too fast, a genuine bug, not
    -- a re-verified faster real cadence. Kept on its own, separate
    -- `MOVEMENT_STEP_SECONDS` accumulator so the cosmetic flip stays at
    -- its own independently-verified real rate regardless of how finely
    -- the interpreter itself ticks.
    self.flipTimer = (self.flipTimer or 0) + dt
    while self.flipTimer >= Enemy.MOVEMENT_STEP_SECONDS do
      self.flipTimer = self.flipTimer - Enemy.MOVEMENT_STEP_SECONDS
      self.movementIndex = self.movementIndex + 1
    end
    return
  end
  local n = #Enemy.MOVEMENT_CYCLE
  while self.movementTimer >= Enemy.MOVEMENT_STEP_SECONDS do
    self.movementTimer = self.movementTimer - Enemy.MOVEMENT_STEP_SECONDS
    local step = Enemy.MOVEMENT_CYCLE[self.movementIndex]
    self.x = self.x + step.dx
    self.y = self.y + step.dy
    self.movementIndex = self.movementIndex % n + 1
  end
end

--- Real hardware X-flip toggle for the patrol/hover pose (2026-08-12,
-- direct user report: "die animationen der sprites nicht richtig, der
-- boss sollte zb animationen haben"). Live OAM trace found the real
-- creature's own attribute byte flips bit 5 (X-flip -- CORRECTED same
-- day, this function originally wired the finding into `flipY`,
-- transposing bits 5/6; see rom_profiles.lua's
-- `enemySprite.flipXTogglesPerStep` doc comment for the full evidence
-- and the correction note) every single real movement step, using the
-- SAME `enemySprite.tileOffsets` art both ways. `movementIndex`
-- already advances exactly once per real step (see `updateMovement`
-- above), so its own parity is a direct, real proxy for "which of the
-- two real flip states this step is in" -- no separate timer needed.
-- The starting phase (whether index 1 is flipped or not) was not
-- independently pinned down to a specific real waypoint; an arbitrary
-- consistent choice here only shifts which half-step the flap starts
-- on, not whether the flap itself is real.
function Enemy:isFlipped()
  return self.movementIndex % 2 == 0
end

-- REMOVED (2026-08-13, direct user instruction: "mach die gesamte
-- startsequenz von anfang bis ende interpretiert"): this used to be a
-- real, but entirely HAND-CAPTURED, one-time "gate-to-patrol descent"
-- tween (`startDescent`/`updateDescent`/`descentComplete`, driven by
-- `rom_profiles.lua`'s own hardcoded `enemyDescent.path` table). Task
-- #86 (this same day) found, independently, that
-- `EnemyMovementInterpreter`'s own first 4 real ticks -- sourced live
-- from the actual ROM behavior-tree data, not captured/replayed -- are
-- BYTE-FOR-BYTE the same real deltas as `enemyDescent.path` (both:
-- 4 steps of `y+7`, 5 real frames each). This is not a coincidence --
-- it's the SAME real event, found independently by two different
-- investigations. The separate descent tween is now genuinely
-- redundant: `BattleIntro.lua` runs the real interpreter (via the
-- ordinary `updateMovement`) continuously from the moment the gate
-- opens, with no separate "descent phase" state at all -- see that
-- state's own doc comment for the real "which sprite to draw" boundary
-- this removal needed to replace.

-- Real death "explosion" (2026-08-12, direct user correction: "es gibt
-- diese explosion ohne jeden zweifel" -- an earlier same-session pass
-- wrongly trusted a stale, incomplete negative result before re-
-- tracing and finding this). See rom_profiles.lua's own `enemyDeath`
-- doc comment for the full live evidence (the creature's own six real
-- body-part tile pairs scatter outward over `totalFrames` real frames,
-- then vanish). `Field.lua` starts this the instant `Enemy:hit()`
-- reports the kill and keeps drawing/advancing it (instead of the
-- normal enemy sprite) until `deathComplete()`.
--
-- CROSS-REFERENCE (2026-08-14, task #86, unrelated investigation that
-- independently arrived at the same real neighborhood): a separate,
-- WRAM-side live trace of the real boss-defeat SCRIPT (not this visual
-- scatter, a different ROM mechanism entirely) found the story script
-- itself waits for its own edge-triggered "has the defeated entity's
-- own actor slot finished despawning" signal before proceeding --
-- confirmed to take ~100 real GB frames in that trace, close to (not
-- identical to, and not claimed to be the exact same underlying timer
-- as) this `totalFrames = 86` scatter duration. Both are real,
-- independently live-verified delays in the same real "boss just
-- died" window -- corroborating, not requiring any code change here.
-- See `ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS`'s own doc comment
-- and events.md's dated task-#86 entries for the full WRAM-side trace.
function Enemy:startDeath(profile)
  local d = profile.graphics.enemyDeath
  self.death = { profile = d, elapsedFrames = 0, doneFrames = d.totalFrames }
end

--- Advance the real death timer. No-op once finished or never started.
function Enemy:updateDeath(dt)
  local st = self.death
  if not st or self:deathComplete() then return end
  st.elapsedFrames = st.elapsedFrames + dt / FixedStep.STEP
end

--- True once the real `totalFrames`-long scatter has finished (the
-- creature should no longer be drawn at all past this point, matching
-- the real ROM's own final "all six parts vanish" result).
function Enemy:deathComplete()
  return not self.death or self.death.elapsedFrames >= self.death.doneFrames
end

function Enemy:isAlive()
  return not self.stats:isDead()
end

--- Axis-aligned bounding-box overlap against a rectangle (x, y, w, h).
function Enemy:overlaps(x, y, w, h)
  return x < self.x + self.width and x + w > self.x and
    y < self.y + self.height and y + h > self.y
end

--- Advance the contact-damage cooldown; returns true the instant this
-- step should apply a contact-damage tick (caller is responsible for
-- checking adjacency/overlap first).
function Enemy:tickContactCooldown(dt)
  self.contactCooldown = self.contactCooldown - dt
  if self.contactCooldown <= 0 then
    self.contactCooldown = Enemy.CONTACT_TICK_SECONDS
    return true
  end
  return false
end

--- Take a hit from the player's attack (see PLAYER_ATTACK_DAMAGE's
-- UNVERIFIED caveat above). Returns true if this hit just cleared it.
function Enemy:hit()
  local wasAlive = self:isAlive()
  self.stats:damage(Enemy.PLAYER_ATTACK_DAMAGE)
  return wasAlive and not self:isAlive()
end

return Enemy
