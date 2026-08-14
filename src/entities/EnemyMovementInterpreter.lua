-- A real, ROM-data-driven interpreter for the courtyard gate
-- creature's own movement AI (2026-08-13, direct user instruction:
-- "der boss kampf an sich... der ist hard coded. der soll aus den
-- romdaten raus interpretiert werden"). Replaces `Enemy.MOVEMENT_CYCLE`
-- -- a hand-captured, 33-step REPLAY of one specific live observation
-- -- with a real interpreter over the actual ROM data structure this
-- session found by tracing real writes to the creature's own live
-- position (WRAM `$C200+7*16+4/+5`, the entity struct already known
-- from `EntityStructLayout.lua`) back to their real source, bank 4:
--
-- **Level 1 ("top"), 10-byte rows** at a per-creature base pointer
-- (`$D43A/$D43B` live), indexed by WRAM `$D3EC`. Each row holds 4 real
-- 16-bit pointers (`row[0..1]`, `row[2..3]`, `row[4..5]`, `row[6..7]`
-- -- "choices" 0-3) plus 2 more bytes (`row[8]`, `row[9]`) fed into an
-- unmodeled leaf (`$4188`, transforms them via `(byte+1)*8`/`(byte+2)*8`
-- and stores into a per-slot WRAM cache `$D3F6` -- almost certainly a
-- real sound/animation cue, NOT position -- HONEST SCOPE, not
-- reproduced here). A row whose first TWO bytes are BOTH `0xFF` is a
-- real "wrap" marker (`$102C5`/`$102D8`): re-loads the top-level base
-- from a per-creature "anchor" pointer (`$D438/$D439`, the SAME real
-- per-creature record this project's own rom-map.md "P1 resolved"
-- section already found for enemy ATK -- record file offset `0x108B9`
-- for this creature) plus a fixed `+0x12` byte field, and resets to
-- row 0. Otherwise (`$425F`'s own real body): draws a REAL PRNG value
-- (`$2B1E`, this project's own already-ported `CombatNoise` -- see
-- that module's own doc comment for the exact ported algorithm), takes
-- it mod 4, and picks ONE of the row's 4 pointers as the new level-2
-- base -- a real, genuinely NON-DETERMINISTIC choice, not a fixed
-- sequence baked into the ROM.
--
-- **Level 2 ("mid"), 5-byte rows** at the level-2 base, indexed by an
-- index that resets to 0 on every level-1 pick (`$4222`/`$42B0`). Each
-- row is `{countdown, moveTablePtr(2 bytes), secondPtr(2 bytes)}` --
-- `secondPtr`'s own real purpose is unmodeled (HONEST SCOPE, not
-- chased this pass). A row whose first byte is `0xFF` means this
-- level-2 table is exhausted (`$4222`'s own `CALL Z,$425F`) -- go back
-- to level 1 for a fresh PRNG-driven pick. Otherwise: read the real
-- delta at `moveTablePtr` (level 3, below), and apply it once per real
-- TICK (see `TICK_FRAMES` below) for exactly `countdown` real ticks
-- before advancing to the next level-2 row -- confirmed by directly
-- disassembling `$100A4`'s own real per-tick body, which unconditionally
-- re-applies whatever `moveTablePtr` currently holds every tick it
-- runs, decrementing `countdown` (WRAM `$D3F0`) once per tick via
-- `$4209` until it reaches 0.
--
-- **Level 3 ("delta"), 2 bytes** at `moveTablePtr`. Byte 0 is an
-- unmodeled leaf argument (`$419E`, decodes into a real sound/facing
-- selector via bitfield extraction -- HONEST SCOPE, not reproduced).
-- Byte 1 packs two SIGNED 4-bit nibbles: high nibble = dx, low nibble
-- = dy (real range -8..+7, matching two's-complement 4-bit values).
--
-- **Decisive cross-check**: the first 7 real (dx,dy) deltas this
-- interpreter decodes straight from the live ROM --
-- `(4,7),(6,7),(7,5),(7,0),(7,-5),(6,-8),(4,-8)` -- match
-- `Enemy.MOVEMENT_CYCLE`'s own first 7 entries BYTE-FOR-BYTE (that
-- table was captured completely independently, via 6000 real frames
-- of live OAM/pixel tracing, months before this ROM-data trace found
-- the actual mechanism) -- decisive proof this is the real mechanism,
-- not a coincidental pattern match.
--
-- **HONEST SCOPE, IMPORTANT**: real hardware's own exact PRNG state at
-- the moment any specific real encounter begins depends on the ENTIRE
-- preceding real execution history since power-on -- this project has
-- no way to reproduce that exactly (the same documented limitation
-- `CombatNoise` itself already carries). This interpreter is faithful
-- to the real ALGORITHM and real DATA TABLES, not to one specific
-- captured playthrough's own exact move sequence -- the creature's real
-- patrol is genuinely non-deterministic (a real ROM fact only found by
-- tracing this deep), so this is a MORE faithful port than a fixed
-- replay, not a less faithful one. The exact spawn-time algorithm that
-- first populates `$D43A/$D43B`/`$D3EC` was not traced (this project
-- observed its real, live OUTPUT -- `topBase=$4E00` -- but not the
-- code that computes it); `START_TOP_BASE` below is that real,
-- empirically-read value, used as a verified starting constant, same
-- precedent as `BossSequenceInterpreter`'s own `START_BANK`/
-- `START_CPU_ADDRESS`.
--
-- Real ROM code for ALL of this (levels 1-3, the wrap mechanism) lives
-- in bank 4's own switchable window for this creature -- confirmed by
-- every single live read/write this session captured. `BANK` below is
-- a real, but creature-specific, verified fact -- not claimed to
-- generalize to every other ROM creature without re-verification.
--
-- Pure Lua, no love.* calls -- headlessly testable, same convention as
-- `BossSequenceInterpreter`/`ScriptRuntime`.

local EnemyMovementInterpreter = {}
EnemyMovementInterpreter.__index = EnemyMovementInterpreter

local BANK = 4

local function romByte(romData, cpuAddress)
  local fileOffset = BANK * 0x4000 + (cpuAddress - 0x4000)
  return romData:byte(fileOffset + 1) -- Lua strings are 1-indexed
end

local function romWord(romData, cpuAddress)
  local lo = romByte(romData, cpuAddress)
  local hi = romByte(romData, cpuAddress + 1)
  return lo + hi * 256
end

-- Signed 4-bit nibble -> Lua integer (-8..7).
local function signedNibble(n)
  if n >= 8 then
    return n - 16
  end
  return n
end

-- Real, empirically-verified constants for the courtyard gate creature
-- (see this module's own doc comment for how each was captured live).
EnemyMovementInterpreter.ANCHOR_CPU_ADDRESS = 0x48B9
EnemyMovementInterpreter.ANCHOR_FIELD_OFFSET = 0x12
-- CORRECTED (2026-08-13, same pass): an earlier live capture of this
-- constant (`read_initial_state2.py`, scratchpad) raced its own two
-- separate byte-watchpoints ($D43A low, $D43B high -- real hardware
-- writes the high byte first, per `$42D8`'s own disassembly) and
-- stopped at the FIRST of the two writes, reading the still-stale low
-- byte alongside the freshly-written high byte -- a real, self-caught
-- tooling bug (Watcher-level race, not a ROM fact), not a second
-- possible real value. The corrected capture (watching $D3EC's own
-- reset instead, which fires strictly AFTER both bytes commit) gives
-- the real value below, independently cross-confirmed: `topBase +
-- 0x12` (the real "wrap" formula, `$42C5`) resolves to `$4F4D`,
-- matching a DIRECT static read of the per-creature record (file
-- `0x108CB`) exactly -- the corrected value is consistent both ways,
-- the earlier one was not.
EnemyMovementInterpreter.START_TOP_BASE = 0x4E15
-- Real, live-measured tick rate: exactly 5 real GB frames between
-- consecutive real dispatches of this creature's own movement-apply
-- routine (`trace_ptr_writes.py`/`measure_tick_cadence.py`, scratchpad,
-- 2026-08-13) -- 29 consecutive real measurements, every single delta
-- exactly 5, no exceptions. A `countdown=1` real "move" row plus a
-- `countdown=4` real "pause" row (the two ALWAYS alternate in the real
-- data this project has decoded) together span exactly `5*(1+4)=25`
-- real frames -- matching `Enemy.MOVEMENT_STEP_SECONDS`'s own
-- independently-verified 25-frame/step figure exactly.
EnemyMovementInterpreter.TICK_FRAMES = 5

--- `romData`: the raw ROM byte string. `noise`: a real `CombatNoise`
-- instance (this project's own `$2B1E` port) -- REQUIRED, not
-- optional, since the real level-1 choice is genuinely PRNG-driven;
-- guessing a fixed choice here would misrepresent real, non-
-- deterministic ROM behavior as fixed. Share the SAME `CombatNoise`
-- instance combat damage already uses (`Field.lua`'s own
-- `self.combatNoise`) if you want this to draw from the real ROM's
-- single, shared PRNG stream rather than an independent one -- either
-- is a defensible choice (the real ROM's own `$C0B0`/`$C0B1` counters
-- ARE genuinely shared/global), but sharing is closer to real hardware.
function EnemyMovementInterpreter.new(romData, noise, ctx)
  assert(type(romData) == "string", "EnemyMovementInterpreter.new expects a byte string")
  assert(noise, "EnemyMovementInterpreter.new requires a real CombatNoise instance -- " ..
    "the real level-1 choice is genuinely PRNG-driven, not guessable")
  ctx = ctx or {}
  local self = setmetatable({
    romData = romData,
    noise = noise,
    topBase = ctx.topBase or EnemyMovementInterpreter.START_TOP_BASE,
    topIndex = 0,
    midBase = nil,
    midIndex = 0,
    countdown = 0,
    pendingDelta = { dx = 0, dy = 0 },
  }, EnemyMovementInterpreter)
  self:pickTopLevel()
  self:loadMidRow()
  return self
end

--- Real level-1 dispatch (`$425F`'s own body): follows real `0xFF,0xFF`
-- wrap markers (via the real per-creature anchor field) until landing
-- on a real, non-terminator row, then draws the real PRNG and commits
-- one of its 4 real pointers as the new level-2 (`midBase`).
function EnemyMovementInterpreter:pickTopLevel()
  while true do
    local rowBase = self.topBase + self.topIndex * 10
    local b0 = romByte(self.romData, rowBase)
    local b1 = romByte(self.romData, rowBase + 1)
    if b0 == 0xFF and b1 == 0xFF then
      self.topBase = romWord(self.romData,
        EnemyMovementInterpreter.ANCHOR_CPU_ADDRESS + EnemyMovementInterpreter.ANCHOR_FIELD_OFFSET)
      self.topIndex = 0
    else
      local choice = self.noise:draw() % 4
      self.midBase = romWord(self.romData, rowBase + choice * 2)
      self.topIndex = self.topIndex + 1
      self.midIndex = 0
      return
    end
  end
end

--- Real level-2 row load (`$4222`'s own body): follows the real level-2
-- table forward, chasing back up to level 1 (`pickTopLevel`) the
-- instant a real `0xFF` terminator row is hit, then decodes the real
-- level-3 packed-nibble delta for the freshly-loaded row.
function EnemyMovementInterpreter:loadMidRow()
  while true do
    local rowBase = self.midBase + self.midIndex * 5
    local countdown = romByte(self.romData, rowBase)
    if countdown == 0xFF then
      self:pickTopLevel()
    else
      local movePtr = romWord(self.romData, rowBase + 1)
      -- `movePtr`'s own byte 0 is an unmodeled leaf argument (real
      -- sound/facing selector, `$419E`) -- HONEST SCOPE, not read here.
      local packed = romByte(self.romData, movePtr + 1)
      self.pendingDelta.dx = signedNibble(math.floor(packed / 16))
      self.pendingDelta.dy = signedNibble(packed % 16)
      self.countdown = countdown
      self.midIndex = self.midIndex + 1
      return
    end
  end
end

--- Advance exactly ONE real tick (`TICK_FRAMES` real GB frames -- the
-- caller is responsible for the real frame-accumulation, same
-- convention as `Enemy:updateMovement`'s own `MOVEMENT_STEP_SECONDS`
-- accumulator). Returns the real `(dx, dy)` to apply this tick --
-- confirmed live: `$100A4`'s own real body unconditionally re-applies
-- whatever the current level-2 row's delta is on EVERY tick it runs
-- (not just the row's first tick), so a real `countdown=4` "pause" row
-- (always real delta `(0,0)` in the data this project has decoded)
-- visually holds still for its own 4 real ticks, and a real
-- `countdown=1` "move" row applies its own nonzero delta exactly once.
function EnemyMovementInterpreter:tick()
  local dx, dy = self.pendingDelta.dx, self.pendingDelta.dy
  self.countdown = self.countdown - 1
  if self.countdown <= 0 then
    self:loadMidRow()
  end
  return dx, dy
end

--- Advance `n` real ticks WITHOUT returning/applying their deltas --
-- for a caller that needs to fast-forward through real ticks a
-- DIFFERENT system has already visibly played (see the real, decisive
-- reason this exists below), while still advancing this interpreter's
-- own real internal state exactly as if each tick had happened
-- normally.
--
-- WHY THIS EXISTS (2026-08-13, direct user report: "die interpretierte
-- [Bewegung] hat die [Einlaufbewegung] aber auch drin, so das er sich
-- 2 mal süden bewegt"): this interpreter's own first 4 real ticks
-- decode to `(0,7),(0,7),(0,7),(0,7)` -- and `rom_profiles.lua`'s own
-- `enemyDescent.path` (found completely independently, months earlier,
-- via live OAM tracing of the creature's real gate-entry walk) is
-- FOUR steps of `y+7`, 5 real frames each -- an EXACT, decisive
-- byte-for-byte match (`TICK_FRAMES=5` too). These are NOT two
-- different real mechanics that happen to look similar -- they are the
-- SAME real event, found independently by two different investigations
-- at two different times. `BattleIntro.lua`'s own `updateDescent`
-- already plays this real motion visibly (via its own separate,
-- hardcoded path) BEFORE `Field.lua` ever exists -- a fresh
-- interpreter, with no knowledge of that, would visibly re-play the
-- exact same 4 ticks a second time. The real fix: skip exactly
-- `#enemyDescent.path` real ticks (silently, matching how real
-- hardware's own AI state would already have advanced this far by the
-- time the descent animation finishes) before `Field.lua` starts
-- applying this interpreter's own ticks to the visible sprite.
function EnemyMovementInterpreter:skipTicks(n)
  for _ = 1, n do
    self:tick()
  end
end

return EnemyMovementInterpreter
