-- A real, per-real-frame driver for the boss-defeat post-fight
-- sequence -- the concrete next step after `VictorySequence.lua`'s
-- own one-shot "shadow run" (which only ever explored control flow at
-- construction time, never drove anything visible) and task #86's
-- own live-tracing work (2026-08-13, direct user instruction: "ich
-- will das die interpretierte boss sequenz mit allen grafik effekten
-- usw funktioniert").
--
-- WHY A DEDICATED MODULE, not just more code in VictorySequence.lua:
-- this needed its OWN real state (which bank/stream is currently
-- live, the persistent cursor, whether a real bank-switch just
-- happened) that has to survive across many real `love.update` calls
-- -- pure Lua, no `love.*` calls, so it stays headlessly testable like
-- every other `src/scripting/*` module.
--
-- THE REAL, EMPIRICAL BANK FACT this module is built on (see
-- events.md's own "task #86" section for the full live-tracing trail):
-- the real ROM's own script dispatch does NOT switch to a fixed bank
-- per script -- it reads the persistent cursor against whatever bank
-- is AMBIENTLY already selected (set by unrelated systems, not
-- derivable from any formula on the script's own bytes or the
-- `scriptPointerTable`'s own bank). For THIS one specific, real,
-- live-traced scene, the ambient bank is verified to be **13** at the
-- real start (`$470F`, matching the boss-defeat script's own already-
-- VERIFIED index-232 identification) and **14** after the FIRST real
-- CHAIN (an empirical fact, not a general rule -- a different real
-- scene could need a different real bank pair; this module does NOT
-- claim to generalize past this one scene).
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local RomScriptStream = require("src.scripting.RomScriptStream")

local BossSequenceInterpreter = {}
BossSequenceInterpreter.__index = BossSequenceInterpreter

-- Real, live-traced starting point (see this module's own doc comment
-- above): bank 13, CPU `$470F` -- NOT `scriptPointerTable`'s own
-- assumed bank 8, which is real, verified STATIC data for a DIFFERENT
-- real reading of the same CPU-address range, not what the live ROM
-- actually executes for this real trigger context.
local START_BANK = 13
local START_CPU_ADDRESS = 0x470F

-- Real, live-traced post-CHAIN bank (see events.md's own "task #86"
-- section: all 3 real CHAIN dispatches observed in a 500-dispatch
-- live trace either land in, or already stay in, bank 14 -- an
-- empirical fact about this one scene, wired via `ctx.onChainTarget`
-- rather than any general formula, since none was found to exist).
local POST_CHAIN_BANK = 14

-- Real, empirically-traced continuations for opcode `0x08`'s own "list
-- exhausted" leaf effect (see `StandardScriptHandlers
-- .zeroTerminatedFlagList`'s own doc comment for the full disassembly
-- and the corrected "NOT a WRAM block-clear" finding) -- keyed by
-- `bank..":"..cursorAfterTerminator` (the cursor RIGHT AFTER the real
-- zero terminator byte, matching `onExhausted`'s own parameter). Real
-- guessing here is KNOWN to be wrong (see that doc comment's own
-- decisive `$32F3` mismatch), so this table only ever contains
-- values this project has actually live-traced for THIS one scene --
-- an unknown key fails loudly (below) rather than silently guessing.
--   `13:0x4712 -> 0x472a` -- the boss-defeat script's own FIRST real
--   `0x08` dispatch (cursor `$470f`, loop-test byte `0x08` itself,
--   confirmed NZ), live-traced via `trace_08_singlestep.py`
--   (2026-08-13, task #86).
local FLAG_LIST_EXHAUSTED_TARGETS = {
  ["13:0x4712"] = 0x472a,
}

local function flagListExhaustedKey(bank, cursorAfterTerminator)
  return string.format("%d:0x%x", bank, cursorAfterTerminator)
end

-- Real, empirically-traced Z/NZ results for opcode `0x08`'s own
-- per-item `$35EF` leaf test (see `StandardScriptHandlers
-- .zeroTerminatedFlagList`'s own doc comment) -- keyed by the real
-- loop-test BYTE VALUE, not by bank/cursor: `$35EF`'s own real effect
-- is a WRAM flag test keyed by this byte (see `$3602`'s own real
-- `$D7C6`-table-offset formula), so for one short, deterministic real
-- scene replayed from a fixed save state, the same byte value
-- observed twice should produce the same real Z/NZ result regardless
-- of where in the script it's read from. Confirmed DECISIVELY wrong to
-- default uniformly (see `trace_08_second.py`, 2026-08-13, task #86):
-- byte `0x08` -> NZ (the boss-defeat script's own FIRST real `0x08`
-- dispatch); byte `0x88` -> Z (its SECOND, right after the real CHAIN
-- into bank 14) -- these two real, live-traced values genuinely
-- differ, so a single blanket default would have been wrong for one
-- of them. An unknown byte value fails loudly (below), matching this
-- project's own "no silent fallbacks" rule.
local FLAG_TEST_RESULTS = {
  [0x08] = false, -- NZ (confirmed via the real $32F3-mismatch trace)
  [0x88] = true,  -- Z (confirmed via the real subsequent-byte trace)
}

--- `ctx` fields (all optional, passed straight through to the real
-- `ScriptRuntime` -- see that module's own doc comment for the full
-- list): `stats`, `flags`, `isTextboxDone`, `onMessage`, `onTick`,
-- `onSetActorSlotPosition`, `onTriggerEvent`, `isTriggerEventGateClear`,
-- and any other real callback that module supports. This constructor
-- adds its own `ctx.onChainTarget` (the bank-switch wiring described
-- above) -- a caller-supplied `ctx.onChainTarget` would be
-- OVERWRITTEN, not composed, since only this module has the real,
-- empirical knowledge of which bank to switch to.
function BossSequenceInterpreter.new(romData, ctx)
  assert(type(romData) == "string", "BossSequenceInterpreter.new expects a byte string")
  local RomIdentity = require("src.import.RomIdentity")
  local RomProfiles = require("src.import.rom_profiles")
  local profile = RomProfiles.match(RomIdentity.identify(romData))
  assert(profile and profile.scriptOpcodeTable, "BossSequenceInterpreter.new: no matching ROM profile")

  local self = setmetatable({
    romData = romData,
    profile = profile,
    cursor = START_CPU_ADDRESS,
    bank = START_BANK,
    stream = RomScriptStream.forBank(romData, START_BANK),
    bankSwitched = false, -- true once the real, one-time 13->14 switch has happened
    done = false, -- true once the runtime genuinely finishes or stops
  }, BossSequenceInterpreter)

  ctx = ctx or {}
  ctx.onChainTarget = function(_newCursor)
    -- The real, empirically-verified switch (see this module's own
    -- doc comment) -- unconditional: every real CHAIN observed in the
    -- live trace either causes or confirms this exact bank, so always
    -- switching (even if already on bank 14) is harmless and correct
    -- for this one scene.
    self.bank = POST_CHAIN_BANK
    self.stream = RomScriptStream.forBank(romData, POST_CHAIN_BANK)
    self.bankSwitched = true
  end

  ctx.onFlagTest = function(byte)
    -- Real, empirically-traced Z/NZ result -- see this module's own
    -- `FLAG_TEST_RESULTS` doc comment. Fails loudly (not a silent
    -- fallback) on a real byte value this project hasn't live-traced
    -- yet.
    local result = FLAG_TEST_RESULTS[byte]
    if result == nil then
      error(("BossSequenceInterpreter: opcode 0x08's real flag-test result " ..
        "for byte 0x%x is NOT yet live-traced -- refusing to guess (see " ..
        "StandardScriptHandlers.zeroTerminatedFlagList's own doc comment)"):format(byte))
    end
    return result
  end

  ctx.onFlagListExhausted = function(cursorAfterTerminator)
    -- Real, empirically-traced continuation for opcode 0x08's own
    -- "list exhausted" leaf effect -- see this module's own
    -- `FLAG_LIST_EXHAUSTED_TARGETS` doc comment and
    -- `StandardScriptHandlers.zeroTerminatedFlagList`'s own doc
    -- comment for why a formula isn't used here. Fails loudly (not a
    -- silent fallback) on a real occurrence this project hasn't
    -- live-traced yet -- exactly the same honesty this project already
    -- applies to genuinely undecoded opcodes.
    local key = flagListExhaustedKey(self.bank, cursorAfterTerminator)
    local target = FLAG_LIST_EXHAUSTED_TARGETS[key]
    if not target then
      error(("BossSequenceInterpreter: opcode 0x08's real 'list exhausted' " ..
        "continuation for bank %d, cursor 0x%x is NOT yet live-traced -- " ..
        "refusing to guess (see StandardScriptHandlers.zeroTerminatedFlagList's " ..
        "own doc comment)"):format(self.bank, cursorAfterTerminator))
    end
    return target
  end

  local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
  self.runtime = ScriptRuntime.new(opcodeEntries, ctx)
  return self
end

--- Advance exactly ONE real opcode dispatch -- meant to be called once
-- per real game frame (matching how the actual ROM's own interpreter
-- is driven: one dispatch attempt per real frame, not a burst), so
-- real per-frame effects (the typewriter tick, a real conditional
-- halt waiting on a real external event) pace correctly. Safe to call
-- after `self.done` becomes true (a real no-op, matching
-- `ScriptRuntime:step`'s own "stays stopped" convention).
function BossSequenceInterpreter:tick()
  if self.done then
    return
  end
  local runtime = self.runtime
  self.cursor = runtime:step(self.stream, self.cursor)
  if runtime.stopped or runtime.finished then
    self.done = true
  end
end

return BossSequenceInterpreter
