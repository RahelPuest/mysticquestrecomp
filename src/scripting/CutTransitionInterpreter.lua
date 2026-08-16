-- A real, per-real-frame driver for the "cut"-style room-transition
-- mechanism (opcode `0xF4`, ROM `$11B7`) -- direct response to the
-- user's own explicit instruction ("es soll alles komplett über den
-- interpreter laufen") after being told room transitions run entirely
-- through hand-authored Lua logic (`VictorySequence.lua`'s room-graph
-- walker) despite the underlying real ROM mechanism already being
-- fully reverse-engineered (see `src/import/CutTransitionTable.lua`).
--
-- WHY A DEDICATED MODULE, not just more code in `VictorySequence.lua`:
-- same reasoning as `BossSequenceInterpreter.lua` (its own structural
-- template) -- needs its own real state (which bank/stream is live,
-- the persistent cursor, what's been captured so far) surviving across
-- many real `love.update` calls, headlessly testable, no `love.*`
-- calls.
--
-- HONEST, DELIBERATELY NARROW SCOPE (2026-08-16, direct continuation,
-- "Ehrliches MVP" chosen by the user after live investigation revealed
-- more real structure than expected -- see
-- docs/reverse-engineering/events.md's own dated entry for the full
-- live-trace evidence this module is built on):
--
-- 1. A real, live single-step trace (`third_room_free()` + the real
--    RIGHT/UP hold trigger, single-stepped with a native mGBA
--    watchpoint on PC `$11B7`) found the real ROM does NOT reach this
--    opcode via bank 1 (this project's own earlier, WRONG assumption,
--    from reading `$11B7`'s own STATIC disassembly without checking
--    which bank is live-mapped) -- it fires 74 real times across the
--    transition, EVERY time with bank 14 mapped in at `$4000`-`$7FFF`
--    (matching `CutTransitionTable.lua`'s own already-known fact that
--    all 186 real landing records live in bank 14).
-- 2. Those 74 hits resolve to exactly 3 distinct `HL` values as the
--    real ROM's own `$D499` step counter advances -- `$42F7` (D499
--    0-3), `$42F9` (D499 4-5), `$42FB` (D499 6-7) -- and the real
--    peeked `(B,C)` bytes at each are BYTE-EXACT matches to the
--    already-known static record `00 05 F4 01 57 0E 0C 00 0B` (file
--    `0x382F4`-`0x382FC`, bank 14): `(1,87)` = roomSelector/
--    subIndexByte, `(14,12)` = the landing tile, `(0,11)` = the
--    record's own trailing terminator.
-- 3. DECISIVE, NARROWING finding: only the FIRST of these three (`HL
--    =$42F7`, reached from opcode byte `$F4` at `$42F6`) is reached
--    via the real, genuine TOP-LEVEL script-dispatch loop (`$3727`,
--    the same fetch-decode-dispatch `ScriptRuntime`/`ScriptInterpreter`
--    already model). The other two are NOT -- the ROM bytes at their
--    own preceding positions (`$382F8`=`0x57`, `$382FA`=`0x0C`) are
--    directly, live-confirmed NOT `0xF4`, so a literal top-level fetch
--    could never have dispatched there. The real `$413C` step-table
--    machine must be jumping DIRECTLY into the same shared peek leaf
--    (`$11B7`) with `HL` pre-positioned by its own internal control
--    flow -- a lower-level mechanism this project's `ScriptRuntime`
--    (whose whole abstraction is "one real opcode dispatch per
--    `:step()`, via the top-level fetch loop") does not model and
--    would need a SEPARATE, dedicated decode of the `$413C` automaton
--    itself to cover (not attempted this pass -- a real, substantial,
--    separately-scoped follow-up, not a quick addition).
--
-- WHAT THIS MODULE THEREFORE DOES, HONESTLY: drives the real
-- `ScriptRuntime` from the real, live-confirmed entry point (bank 14,
-- `$42F6`) through the ONE peek this project can honestly claim goes
-- through genuine top-level dispatch -- capturing the real
-- roomSelector/subIndexByte pair -- then DELIBERATELY halts itself
-- (`self.done = true`, a documented, intentional stop, not a crash or
-- an undecoded-opcode error). It does NOT capture the landing tile
-- (that peek is real, but not reached the way this module's own
-- abstraction can honestly claim credit for) -- `VictorySequence.lua`
-- keeps using the pre-baked `landingX`/`landingY` constants for that
-- half, clearly labeled as such at the call site.
--
-- Pure Lua, no `love.*` calls, headlessly testable like every other
-- `src/scripting/*` module.
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local RomScriptStream = require("src.scripting.RomScriptStream")

local CutTransitionInterpreter = {}
CutTransitionInterpreter.__index = CutTransitionInterpreter

--- Real, live-traced entry points, keyed by transition. ONLY populated
-- with transitions this project has actually live-confirmed via the
-- methodology described in this module's own doc comment above --
-- `.new` fails loudly for any other key, matching this project's own
-- "no fabricated ROM behavior" rule: the other ~184 real
-- `CutTransitionTable` records (including the already-known
-- fourthRoom->fifthRoom transition, whose own live entry point has
-- NOT yet been separately traced) simply have no entry here yet, on
-- purpose, not by oversight.
CutTransitionInterpreter.ENTRY_POINTS = {
  thirdRoomToFourthRoom = {
    bank = 14,
    -- Real opcode `0xF4` byte itself, file `0x382F6` -- the byte
    -- immediately preceding the already-known landing-record's own
    -- `A1`/`A2` (roomSelector/subIndexByte) pair at file `0x382F7`.
    cpuAddress = 0x42F6,
  },
}

--- `ctx` fields (all optional, passed straight through to the real
-- `ScriptRuntime`): same contract as `BossSequenceInterpreter.new`.
-- This constructor adds its own `ctx.onPeekTwoByteGate`/
-- `ctx.isPeekGateClear` (a caller-supplied one would be OVERWRITTEN,
-- not composed -- only this module has the real, empirical knowledge
-- of what to do with opcode `0xF4` in this specific context).
function CutTransitionInterpreter.new(romData, transitionKey, ctx)
  assert(type(romData) == "string", "CutTransitionInterpreter.new expects a byte string")
  local entry = CutTransitionInterpreter.ENTRY_POINTS[transitionKey]
  assert(entry, ("CutTransitionInterpreter.new: %q has no real, live-confirmed entry point yet " ..
    "-- this project does not fabricate one (see this module's own doc comment for exactly " ..
    "which transitions are covered and why)"):format(tostring(transitionKey)))

  local RomIdentity = require("src.import.RomIdentity")
  local RomProfiles = require("src.import.rom_profiles")
  local profile = RomProfiles.match(RomIdentity.identify(romData))
  assert(profile and profile.scriptOpcodeTable, "CutTransitionInterpreter.new: no matching ROM profile")

  local self = setmetatable({
    romData = romData,
    profile = profile,
    transitionKey = transitionKey,
    cursor = entry.cpuAddress,
    bank = entry.bank,
    stream = RomScriptStream.forBank(romData, entry.bank),
    done = false,
    captured = nil, -- { roomSelector = <byte>, subIndexByte = <byte> } once the real peek fires
  }, CutTransitionInterpreter)

  ctx = ctx or {}
  ctx.onPeekTwoByteGate = function(byte1, byte2)
    -- Real peeked bytes -- see this module's own doc comment: the
    -- FIRST (and, this pass, only) real top-level-dispatched `0xF4`
    -- for this transition peeks `(roomSelector, subIndexByte)`.
    if not self.captured then
      self.captured = { roomSelector = byte1, subIndexByte = byte2 }
    end
  end
  ctx.isPeekGateClear = function()
    -- HONEST SIMPLIFICATION: the real ROM re-peeks the SAME bytes
    -- across several real `$D499` step values before its own gate
    -- condition clears (74 real hits total, only the first 4 sharing
    -- this specific peek -- see this module's own doc comment). This
    -- project does not model the real `$D499` step machine (that is
    -- exactly the "not reached via top-level dispatch" gap this
    -- module's own doc comment names) -- accepting immediately still
    -- captures the CORRECT real byte values (confirmed byte-exact
    -- against the already-known static record), it just does not
    -- reproduce the real retry cadence/timing.
    return true
  end

  local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
  self.opcodeEntries = opcodeEntries
  self.ctx = ctx
  self.runtime = ScriptRuntime.new(opcodeEntries, ctx)
  return self
end

--- The real, captured `(roomSelector, subIndexByte)` pair, or `nil`
-- if the interpreter hasn't reached the real peek yet. Never
-- fabricated -- only ever set from `ctx.onPeekTwoByteGate` above,
-- itself only ever called by real `ScriptRuntime` execution of real
-- ROM bytes.
function CutTransitionInterpreter:capturedRoomSelector()
  return self.captured and self.captured.roomSelector
end

--- Advance exactly ONE real opcode dispatch per call, same shape as
-- `BossSequenceInterpreter:tick`. Once the real peek has fired
-- (`self.captured` set), this module DELIBERATELY halts itself --
-- see this module's own doc comment for exactly why it does not (yet)
-- continue past this point. This is an intentional stop, not an
-- error: `self.done` becomes `true` the same way it would for a
-- genuine `runtime.finished`/`runtime.stopped` condition, so callers
-- (`VictorySequence.lua`) don't need to special-case it.
function CutTransitionInterpreter:tick()
  if self.done then
    return
  end
  local runtime = self.runtime
  self.cursor = runtime:step(self.stream, self.cursor)
  if runtime.stopped or runtime.finished then
    self.done = true
    return
  end
  if self.captured then
    self.done = true
  end
end

return CutTransitionInterpreter
