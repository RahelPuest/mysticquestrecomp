-- A real, general-purpose driver tying `ScriptInterpreter` +
-- `StandardScriptHandlers` + `ScriptContinuationQueue` together against
-- a live gameplay context -- registers every REAL, currently-decoded
-- handler this project has (see StandardScriptHandlers.lua), so any
-- caller driving any of the real 1357 ROM scripts
-- (rom_profiles.lua's `scriptPointerTable`) gets the full, current real
-- opcode coverage without re-wiring the registration boilerplate
-- itself. Built 2026-08-13, direct instruction "bau den interpreter
-- ein... parallel zum bisherigen code... mit einem cmd switch
-- gewechselt werden" -- see VictorySequence.lua's own doc comment for
-- the actual gameplay wiring (a parallel, opt-in "shadow run" that
-- never controls real rendering/state -- the existing hand-authored
-- cutscene logic stays fully in charge either way).
--
-- HONEST SCOPE: only wires the opcodes this project has ACTUALLY
-- decoded a real Lua handler for (currently ~90/256 across the whole
-- opcode table, see ScriptOpcodeTable.lua's own running tally, though
-- ONE concrete real script -- the boss-defeat sequence -- is known to
-- use several NOT among them: opcodes `0x5A`, `0x08`, `0x88`, `0xBF`/
-- `0xBC`/`0xBD`/`0xF3`, see events.md's "boss-defeat script: every
-- opcode it actually uses, decoded" section). Any script that reaches a
-- still-undecoded opcode will genuinely, loudly fail the moment it's
-- reached (`ScriptInterpreter:step`'s own "no silent fallbacks" error)
-- -- `:step()` below catches that ONE failure per run and reports it as
-- real, inspectable state instead of throwing again on every subsequent
-- call, so a caller driving this once per real game tick (or once in a
-- bounded burst, see `:run()`) doesn't need its own error-handling
-- boilerplate -- but the failure itself is never hidden, only reported.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local ScriptInterpreter = require("src.scripting.ScriptInterpreter")
local StandardScriptHandlers = require("src.scripting.StandardScriptHandlers")
local ScriptContinuationQueue = require("src.scripting.ScriptContinuationQueue")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local EntityStructLayout = require("src.import.EntityStructLayout")

local ScriptRuntime = {}
ScriptRuntime.__index = ScriptRuntime

--- `opcodeEntries`: the real, decoded 256-entry table (`ScriptOpcodeTable
-- .decode(romData, profile.scriptOpcodeTable)`).
--
-- `ctx`: a plain table of real, live callbacks/state this runtime's
-- registered handlers read/write. Every field is OPTIONAL -- an absent
-- one just means that opcode family's own real side effect never fires
-- and its handler is never registered at all (so a script that actually
-- NEEDS it fails loudly at that opcode, same "no silent fallbacks" rule
-- as everywhere else in this project, rather than silently no-op-ing).
--   ctx.stats             -- a Stats-shaped table (curLP/maxLP/curMP/
--                             maxMP) for the real 0xC0/0x32 heal-to-max
--                             opcodes.
--   ctx.flags              -- a `{ byte = <int> }` shadow of real WRAM
--                             `$D874`, for the real 0xDC/0xDD set/clear-
--                             bit-1 opcodes (bit 1 is fixed by the real
--                             ROM instruction itself, not a parameter).
--   ctx.wramBitFlags       -- a `{ byte = <int> }` shadow of a real,
--                             DIFFERENT WRAM cell (`$C3F1`), for the
--                             real 0xB8/0xB9 set/clear-bit-0 opcodes
--                             (added 2026-08-14, whole-corpus scan).
--   ctx.onWramBitCommandLeafB8/B9() -- opaque per-opcode leaf callbacks
--                             for those same 2 opcodes' own real,
--                             self-contained side effects (fixed
--                             sound-parameter WRAM writes this project
--                             doesn't otherwise model) -- see
--                             `StandardScriptHandlers.wramBitCommand`'s
--                             own doc comment.
--   ctx.actorStateFlags     -- a `{ byte = <int> }` shadow of a real,
--                             THIRD different WRAM cell (`$C4D4`), for
--                             the real `0xA3`/`0xA5`/`0xA6` bit-SET
--                             opcodes (bits 4/5/6 respectively, added
--                             2026-08-14, whole-corpus scan) -- see
--                             `StandardScriptHandlers
--                             .fixedWramBitSetSkipCommand`'s own doc
--                             comment. Optional, same "only register
--                             if the caller wants to track this real
--                             cell" convention as `ctx.flags`/
--                             `ctx.wramBitFlags` above.
--   ctx.queue               -- a real ScriptContinuationQueue (built
--                             fresh here if omitted) for CHAIN/
--                             typewriterCommand/queueGate's own real
--                             WRAM-FIFO side effects.
--   ctx.onMessage(id)       -- opcode 0xFE.
--   ctx.onTick()            -- opcode 0x04, and the real per-tick pacing
--                             callback inside 0xF0/0xFF.
--   ctx.isTextboxDone()     -- the real release condition for 0xF0/0xFF
--                             -- required in spirit if either is ever
--                             reached; defaults to an always-true stub
--                             (releases immediately, i.e. never actually
--                             halts) when omitted -- a clearly-flagged
--                             stand-in for "no real display state wired
--                             up," not a guess about real ROM behavior.
--   ctx.onTriggerEvent()    -- the whole real TRIGGER_EVENT family
--                             (opcode 0xE0 and every real `_XX` variant,
--                             e.g. 0xE1/0xE2/0xE4/0xE5/0xA0/0xB9/0xC3/
--                             0xDE), registered generically -- see
--                             `:registerStandardHandlers`'s own doc
--                             comment below.
--   ctx.onSoundParam(v)     -- the whole real SOUND_PARAM family
--                             (opcodes 0xF8/0xF9/0xC4), registered
--                             generically, same shape as
--                             `onTriggerEvent`.
--   ctx.onWordCommand(v)    -- the real WORD_COMMAND family (opcode
--                             0xD0 and its `_EF` variant), registered
--                             generically.
--   ctx.onByteWordCommand(byteValue, wordValue) -- opcode 0xB0.
--   ctx.onTwoByteCommand(byte1, byte2)          -- opcode 0xF6.
--   ctx.onActorAction(group) -- the whole real ACTOR_ACTION family
--                             (14 real opcodes across this project's own
--                             running tally, e.g. 0x10/0x11/0x14/...),
--                             registered generically -- `group` is
--                             always `nil` here (see
--                             `:registerStandardHandlers`'s own "HONEST
--                             LIMIT" note: the real per-opcode group
--                             value isn't machine-readable yet).
--   ctx.onQueuedAction()     -- the real QUEUED_ACTION family (opcodes
--                             0x18/0x28/0x38/0x48/0x58/0x78).
--   ctx.onActorActionOrSkip(group) -- the `$1606` cluster's own
--                             actor-action-shaped members (opcodes
--                             `0x90`/`0x91`/`0x94`-`0x97`, added
--                             2026-08-14) -- a real, DIFFERENT
--                             not-ready behavior from `onActorAction`
--                             above (soft skip, not halt -- see
--                             `StandardScriptHandlers
--                             .actorActionOrSkip`'s own doc comment).
--                             `group` is the REAL per-opcode value
--                             here (explicit registration, not the
--                             generic loop's own `nil`-group limit).
--   ctx.onQueuedActionOrSkip() -- the `$1606` cluster's own
--                             queued-action-shaped member (opcode
--                             `0x98`, added 2026-08-14) -- see
--                             `StandardScriptHandlers
--                             .queuedActionOrSkip`'s own doc comment.
--   ctx.isActorReady()       -- the real halt condition shared by the
--                             actor-action, queued-action, AND opcode
--                             0x49's own real gate (SAME underlying
--                             `$289B` WRAM-$C5A0 check as queued-action)
--                             -- no live WRAM actor-record state
--                             modeled, defaults to "always ready."
--   ctx.getPlayerFacing()    -- opcode `0x80` (updated 2026-08-14, task
--                             10, "$02AB wirklich lösen") -- the real
--                             PLAYER's own current facing direction
--                             (`"up"`/`"down"`/`"left"`/`"right"`,
--                             matching `Player.lua`'s own `self.facing`
--                             representation directly) -- feeds `0x80`'s
--                             own real dynamic group computation (see
--                             `EntityStructLayout.PLAYER_FACING_BIT`'s
--                             own doc comment for the live-trace
--                             evidence this is built on). Optional,
--                             defaults to `"up"` (matching this
--                             project's own already-independently-
--                             verified `Player.DEFAULT_FACING`). ALSO
--                             feeds opcode `0x81` (CRACKED 2026-08-14,
--                             same session, direct continuation) --
--                             SAME callback, combined through
--                             `EntityStructLayout.OPPOSITE_FACING`
--                             first (0x81's own real formula reads the
--                             OPPOSITE of the player's current facing,
--                             see `ScriptOpcodeTable
--                             .ACTOR_ACTION_HANDLER_ADDRESS_81`'s doc
--                             comment for the full disassembly).
--   ctx.onSetActorSlotPosition(byte1, byte2) -- opcodes 0x49 AND 0x19
--                             (the real `$123E`-family members that
--                             consume operand bytes -- same handler
--                             reused for both, since neither's actor-
--                             slot index is threaded through to `ctx`
--                             yet) -- see
--                             StandardScriptHandlers.actorSlotPosition's
--                             own doc comment for why these are the RAW
--                             real bytes, not the real `*8`-transformed
--                             values.
--   ctx.onTwoByteCommandCB(byte1, byte2) -- opcode 0xCB (added
--                             2026-08-13, task #82) -- structurally the
--                             SAME "2 operand bytes, opaque leaf
--                             callback, always continues" shape as
--                             `ctx.onTwoByteCommand` above, but a
--                             genuinely different real ROM target
--                             ($392C vs $3CA2) -- kept as its own,
--                             separate callback rather than conflated.
--   ctx.onTriggerEvent(operand, selectorGroup) -- opcodes `0xFC`/`0xFD`
--                             (added 2026-08-13, task #86) -- fires
--                             once per real activation with the real
--                             operand byte and the real `$1F35`
--                             selector group (5 for `0xFC`, 4 for
--                             `0xFD`) -- see
--                             `StandardScriptHandlers
--                             .oneShotTriggerGate`'s own doc comment.
--   ctx.isTriggerEventGateClear() -- optional gate for the same two
--                             opcodes' own real dual-WRAM-cell check;
--                             defaults to "always clear" (matches the
--                             one real case this project has actually
--                             observed live). ALSO reused by `0xE8`/
--                             `0xE9` below (added 2026-08-14) -- the
--                             real WRAM cells are identical.
--   ctx.onDualGateLeafE8/E9/EA/EB() -- opcodes `0xE8`/`0xE9`/`0xEA`/
--                             `0xEB` (E8/E9 added 2026-08-14, whole-
--                             corpus scan; EA/EB added the same day,
--                             the family's own remaining 2 directions)
--                             -- each fires its own real, distinct
--                             VRAM-tile-pattern-update leaf once the
--                             shared dual gate above clears -- see
--                             `StandardScriptHandlers
--                             .dualGateLeafCommand`'s own doc comment.
--   ctx.onWaveOffsetUpdate(value) -- opcode `0xFB` (added 2026-08-14,
--                             whole-corpus scan) -- optional observer
--                             for the real `$C0A6` wave-offset
--                             oscillator's running byte value -- see
--                             `StandardScriptHandlers
--                             .waveOffsetEffect`'s own doc comment.
--   ctx.onColorPulseDim/Bright(r, g, b) -- opcode `0xBF` (added
--                             2026-08-14, whole-corpus scan) --
--                             optional observers for the real
--                             `$C0AA`-`$C0AC` dim/bright color-pulse
--                             triples -- see `StandardScriptHandlers
--                             .colorPulseEffect`'s own doc comment.
--   ctx.onPlayerEntityTypeWrite(fixedValue) -- opcodes `0x88`/`0x89`
--                             (added 2026-08-14, "konsolidiere unsere
--                             Entdeckungen") -- optional observer for
--                             the real player entity's own "TYPE"
--                             field write (real WRAM `$C241`) -- see
--                             `StandardScriptHandlers
--                             .playerEntityTypeWrite`'s own doc
--                             comment.
--   ctx.isActorCommandQueueEmpty() -- opcode `0x8F` (added 2026-08-14,
--                             whole-corpus scan rank-3 blocker) -- real
--                             conditional halt on the SAME `$C5A0`
--                             8-slot actor-command table opcode `0x00`
--                             reads (see `StandardScriptHandlers
--                             .actorCommandQueueEmptyGate`'s own doc
--                             comment) -- optional, defaults to
--                             "always empty" (no live WRAM
--                             actor-command simulation exists here).
--   ctx.onTileCursorSet(byte1, byte2) -- opcode `0xEF` (added 2026-08-14,
--                             whole-corpus scan, `$0E73` neighborhood) --
--                             fires on every real dispatch with the 2 raw
--                             operand bytes, BEFORE the real 3rd-byte
--                             `$3727` stream-skip -- the real leaf
--                             (`$0454`) is a plain, branchless store into
--                             WRAM `$C344`(byte1)/`$C345`(byte2), no
--                             computation -- see `StandardScriptHandlers
--                             .tileCursorSet`'s own doc comment. `0xEC`/
--                             `0xED`/`0xEE` (the SAME neighborhood's own
--                             siblings) are deliberately NOT registered --
--                             confirmed via real disassembly to be a
--                             THIRD sibling of the already-known-hard
--                             `0x80`/`$15A4` family (shared `$02AB`
--                             dependency) -- see `ScriptOpcodeTable.lua`'s
--                             own doc comment at that address.
--   ctx.onActorActionWithReadinessParam(group, param) -- opcodes `0x7A`/
--                             `0x7B`/`0x5A`/`0x5B`/`0x6A` (added
--                             2026-08-14, whole-corpus scan) -- the
--                             SAME real Family-A shape as
--                             `ctx.onActorAction` (byte-for-byte
--                             identical, no outer `JR NZ` for EITHER
--                             family -- see `StandardScriptHandlers
--                             .actorActionWithReadinessParam`'s own
--                             doc comment for the same-day self-caught
--                             correction), gated the SAME way via
--                             `ctx.isActorReady()` -- fires only on the
--                             real ready path, with the real fixed
--                             `group` and the real, computed `param`
--                             (always `offset+1` on the reachable
--                             path).
--   ctx.onOpcodeByteMirror(ownOpcodeByte) -- opcode `0xCC` (added
--                             2026-08-14, whole-corpus scan) -- fires
--                             on every real dispatch with the real
--                             byte value 0xCC itself (read back via a
--                             legitimate `stream[cursor-1]` lookback,
--                             not fabricated) -- see
--                             `StandardScriptHandlers
--                             .opcodeByteMirror`'s own doc comment;
--                             purely observational, never affects the
--                             returned cursor (real, zero-operand-byte
--                             opcode).
--   ctx.onSoftReset() -- opcode `0xC8` (added 2026-08-14, whole-corpus
--                             scan) -- fires on EVERY real dispatch.
--                             REQUIRED, not optional (no default) --
--                             see `StandardScriptHandlers.softReset`'s
--                             own doc comment: the real ROM jumps to
--                             its own cartridge boot vector here
--                             (`$0100`/`$0150`/`$1FCA`, byte-for-byte
--                             confirmed), a genuine "restart the whole
--                             game" command this project's own
--                             interpreter model can't represent any
--                             other way. A real caller's own
--                             `onSoftReset` should trigger an ACTUAL
--                             game restart (reload the title screen /
--                             reset game state) -- the returned cursor
--                             after this call is a scan-classification
--                             convenience only, not a real continuation
--                             point.
--   ctx.hasSufficientBudget(amount) -- opcode `0xD1` (added 2026-08-14,
--                             whole-corpus scan) -- optional predicate
--                             for the real `$D7BE`/`$D7BF` 16-bit
--                             counter vs. the real operand `amount`;
--                             defaults to "always sufficient" (no live
--                             counter WRAM modeled) -- see
--                             `StandardScriptHandlers
--                             .budgetFlagCommand`'s own doc comment.
--   ctx.onBudgetSufficient(amount)/onBudgetExhausted(amount) -- the 2
--                             real, mutually-exclusive branches of the
--                             same opcode -- fire the real SET/CLEAR
--                             of WRAM flag-array bit 6 respectively.
--   ctx.onRawByteLeaf(rawByte) -- opcodes `0x9C`/`0x9D` (added
--                             2026-08-14, whole-corpus scan) -- fires
--                             with the real, UNMODIFIED operand byte
--                             (no `+1`, unlike `ctx.onByteLeaf` for the
--                             `0xD5`/`0xD7`/`0xD9` family) -- see
--                             `StandardScriptHandlers
--                             .rawByteLeafCommand`'s own doc comment.
--                             Both opcodes share this SAME callback
--                             (same real leaf, `$2895`, neither's own
--                             per-opcode distinction threaded through
--                             yet -- same honest limit as
--                             `ctx.onSetActorSlotPosition`'s own reuse
--                             across `0x49`/`0x19`).
--   ctx.onSceneInit(operandByte) -- opcode `0xC6` (added 2026-08-14,
--                             whole-corpus scan) -- fires with the
--                             real single operand byte on every real
--                             dispatch -- see `StandardScriptHandlers
--                             .sceneInitCommand`'s own doc comment;
--                             the many real WRAM writes this opcode
--                             performs are NOT individually modeled
--                             (HYPOTHESIS-scoped, same as `0xF6`'s own
--                             sibling initializer).
--   ctx.getTwoBitFieldValue()/ctx.onTwoBitFieldWrite(value) -- opcode
--                             `0xC7` (added 2026-08-14, whole-corpus
--                             scan) -- `getTwoBitFieldValue` is an
--                             optional real-value provider (defaults
--                             to 0, no live `$C0B0`/`$C0B1` wrapping
--                             counter modeled); `onTwoBitFieldWrite`
--                             fires with the real, already-masked
--                             (`AND 0x03`) 2-bit value on every real
--                             dispatch -- see `StandardScriptHandlers
--                             .twoBitFieldCommand`'s own doc comment.
--   ctx.onDynamicFlagBit(bitIndex, setBit) -- opcodes `0xDA`/`0xDB`
--                             (added 2026-08-14, whole-corpus scan) --
--                             fires with the real, raw operand byte
--                             (the bit index) and whether this is the
--                             SET (`0xDA`, `setBit=true`) or CLEAR
--                             (`0xDB`, `setBit=false`) variant -- see
--                             `StandardScriptHandlers
--                             .dynamicFlagBitCommand`'s own doc
--                             comment.
--   ctx.onBitmaskDispatch(bitIndex) -- opcode `0xC2` (added 2026-08-14,
--                             whole-corpus scan) -- fires once per
--                             real SET bit (0-4) of the real operand
--                             byte, in ascending order -- see
--                             `StandardScriptHandlers
--                             .bitmaskDispatchCommand`'s own doc
--                             comment.
--   ctx.onChainedOpaqueEffect() -- opcode `0xAF` (added 2026-08-14,
--                             whole-corpus scan) -- fires with no
--                             parameters on every real dispatch (4
--                             chained opaque leaves, no single
--                             meaningful value to report) -- see
--                             `StandardScriptHandlers
--                             .chainedOpaqueEffectCommand`'s own doc
--                             comment.
--   ctx.onSixBitFieldWrite(value) -- opcode `0xC5` (added 2026-08-14,
--                             whole-corpus scan) -- fires with the
--                             real, already-masked (`AND 0x3F`) 6-bit
--                             value on every real dispatch -- see
--                             `StandardScriptHandlers
--                             .sixBitFieldCommand`'s own doc comment.
--   ctx.onActorSlotPositionWithReadinessParam(param, byte1, byte2) --
--                             opcode `0x79` (added 2026-08-14,
--                             whole-corpus scan) -- gated the SAME way
--                             as `ctx.onActorActionWithReadinessParam`
--                             above (`ctx.isActorReady()`, real halt
--                             WITHOUT consuming the 2 position bytes)
--                             -- fires only on the real ready path,
--                             with the real computed slot `param`
--                             (always `offset+1`) and the real, raw
--                             position operand bytes -- see
--                             `StandardScriptHandlers
--                             .actorSlotPositionWithReadinessParam`'s
--                             own doc comment.
--   ctx.onQueuedActionWithReadinessParam(param) -- opcode `0x68`
--                             (added 2026-08-14, whole-corpus scan) --
--                             the `$2859`-leaf sibling of
--                             `ctx.onActorActionWithReadinessParam`,
--                             same gate/param convention -- see
--                             `StandardScriptHandlers
--                             .queuedActionWithReadinessParam`'s own
--                             doc comment.
--   ctx.getFlagBitClassifyValue()/ctx.onFlagBitSet()/onFlagBitClear()
--                             -- opcode `0xA9` (added 2026-08-14,
--                             whole-corpus scan) -- optional real-
--                             value provider (defaults to 0, no live
--                             `$220A` leaf modeled) classified against
--                             3 real fixed constants; fires SET or
--                             CLEAR accordingly -- see
--                             `StandardScriptHandlers
--                             .threeWayFlagBitCommand`'s own doc
--                             comment.
--   ctx.onChainTarget(newCursor) -- fires on EVERY real opcode `0x02`
--                             (CHAIN) dispatch, with the real computed
--                             jump target -- see
--                             `StandardScriptHandlers.chain`'s own doc
--                             comment (added 2026-08-13, task #86) for
--                             why: the real ROM's own cross-bank CHAIN
--                             targets aren't derivable from a formula,
--                             only from empirically knowing the real
--                             ambient bank for a specific real scene --
--                             this lets a caller swap which
--                             `RomScriptStream` it feeds the next
--                             `:step()` call when that's needed.
--   ctx.onTypewriterCommand(v) -- opcode 0x03.
--   ctx.isQueueBlocked()    -- opcode 0x00's own real WRAM `$D874`
--                             bit-0 gate. LIVE-CONFIRMED 2026-08-14
--                             (task #86, real trace of the boss-defeat
--                             script): this is a real SYNCHRONIZATION
--                             BARRIER, not an arbitrary timer -- bit 0
--                             gets set whenever real queued actor
--                             commands (the `$C5A0` 8-slot table
--                             `ScriptOpcodeTable`'s `actorAction`
--                             family enqueues into, see task #85's
--                             `$4B70` finding) are still genuinely
--                             pending, and clears once they finish.
--                             No live actor-command-completion
--                             simulation exists in this project, so
--                             this defaults to "never blocked" --
--                             a known, honest gap (same shape as
--                             `ctx.isActorReady`), not a guess.
--   ctx.onQueueIdle()       -- opcode 0x00's own real "queue empty" side
--                             effect.
--   ctx.onFlagTest(byte) -- opcode 0x08's own real per-item leaf (see
--                             `StandardScriptHandlers
--                             .zeroTerminatedFlagList`'s own doc
--                             comment) -- defaults to "always NZ",
--                             matching the one real case this project
--                             has actually observed live.
--   ctx.onGatedByteLeaf(incrementedByte) -- opcodes 0xD4/0xD6/0xD8 (added
--                             2026-08-13, task #86) -- see
--                             `StandardScriptHandlers
--                             .gatedByteLeafCommand`'s own doc comment.
--   ctx.isFadeActive() -- optional gate for the same 3 opcodes' real
--                             `$D86F` bit-1 check; defaults to "never
--                             active" (matches every real occurrence
--                             this project has observed live).
--   ctx.onFlagListExhausted(cursorAfterTerminator) -- opcode 0x08's own
--                             real "force next opcode to 1" leaf effect
--                             (added 2026-08-13, task #86) -- REQUIRED
--                             in practice (asserts loudly if reached
--                             without it): this project decisively
--                             disproved its own earlier guess at this
--                             continuation this same pass, so a caller
--                             needs real, live-traced knowledge of
--                             where it lands (see `BossSequenceInterpreter`
--                             for the one scene this project has that
--                             knowledge for).
function ScriptRuntime.new(opcodeEntries, ctx)
  ctx = ctx or {}
  local self = setmetatable({
    interp = ScriptInterpreter.new(opcodeEntries),
    queue = ctx.queue or ScriptContinuationQueue.new(),
    ctx = ctx,
    stepCount = 0,
    opcodeCounts = {}, -- real per-opcode dispatch histogram, keyed by opcode byte
    finished = false, -- true once a real fetch runs off the stream's own end
    stopped = false, -- true once a genuinely undecoded opcode halted this run for good
    stopError = nil,
  }, ScriptRuntime)
  self:registerStandardHandlers()
  return self
end

--- Registers every currently-decoded real handler this project has
-- against `self.interp`, wired to `self.ctx`'s own callbacks -- see
-- `ScriptRuntime.new`'s own doc comment for the full field list. Kept
-- as its own method (not inlined into `.new`) so a caller could, in
-- principle, build a runtime with a DIFFERENT handler set (e.g. a
-- future test double) without duplicating this whole registration list.
function ScriptRuntime:registerStandardHandlers()
  local ctx = self.ctx
  local interp = self.interp
  local isDone = ctx.isTextboxDone or function() return true end
  -- Real per-opcode gate for the actor-flag/state and queued-action
  -- families (see StandardScriptHandlers.actorAction/.queuedAction's own
  -- doc comments): the real condition is a live WRAM actor-record check
  -- this project has no runtime model of yet -- defaults to "always
  -- ready" (never blocks), the same explicitly-flagged simplification
  -- those handlers' own doc comments already describe as honest, not a
  -- claim about real timing.
  local isActorReady = ctx.isActorReady or function() return true end

  -- `0x80` (added 2026-08-14, task 10, "die 6 $02AB-Geschwister
  -- wirklich lösen" -- CRACKING the whole-corpus scan's own longest-
  -- standing known-hard opcode): `$02AB` (the leaf this opcode's own
  -- real group depends on) turned out to be a plain read of the
  -- PLAYER's own real facing-direction byte (`$C240`'s low nibble --
  -- see `EntityStructLayout.lua`'s own `PLAYER_FACING_BIT` doc
  -- comment for the complete live-trace evidence), NOT an unmodelable
  -- leaf. Registered here explicitly (still excluded from the generic
  -- sweep below, but for a DIFFERENT reason now -- it needs this
  -- specific dynamic-group wiring, not a blanket skip) using
  -- `.actorAction`'s own existing dynamic-`group`-as-function support:
  -- `ctx.getPlayerFacing()` (optional, defaults to `"up"`, matching
  -- this project's own already-independently-verified
  -- `Player.DEFAULT_FACING`) is looked up in the real
  -- `EntityStructLayout.PLAYER_FACING_BIT` table and combined with
  -- the real fixed `+0x90` offset the ROM's own code applies.
  -- Shared by 0x80 and 0x81 below (factored out 2026-08-14 when 0x81
  -- turned out to need the SAME safe facing lookup, just combined
  -- differently afterward): resolves `ctx.getPlayerFacing()` to a real
  -- facing STRING, coercing anything missing/unrecognized to the
  -- documented `"up"` default (matching `Player.DEFAULT_FACING`) rather
  -- than asserting. SELF-CAUGHT BUG this guards against: a generic
  -- caller (e.g. this project's own whole-corpus scan tool) may supply
  -- a stub `ctx.getPlayerFacing` that returns a non-facing placeholder
  -- (its own generic `__index` stub returns `true` for every unset
  -- callback, regardless of that callback's own real return type -- the
  -- SAME crash class already caught and fixed twice earlier this same
  -- session for `twoBitFieldCommand`/`threeWayFlagBitCommand`).
  local function resolvePlayerFacing()
    local facing = ctx.getPlayerFacing and ctx.getPlayerFacing()
    if not EntityStructLayout.PLAYER_FACING_BIT[facing] then
      facing = "up"
    end
    return facing
  end

  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80,
    StandardScriptHandlers.actorAction(function()
      return EntityStructLayout.PLAYER_FACING_BIT[resolvePlayerFacing()] + 0x90
    end, isActorReady, ctx.onActorAction))

  -- `0x81` (CRACKED 2026-08-14, direct continuation of the same $02AB
  -- investigation): SAME real leaf (`$02AB`, via `resolvePlayerFacing`
  -- above) but combined through `$29E4`'s own real "opposite facing"
  -- bit trick before the fixed `OR 0xB0` -- see `ScriptOpcodeTable
  -- .ACTOR_ACTION_HANDLER_ADDRESS_81`'s own doc comment for the full
  -- disassembly and truth table. `EntityStructLayout.OPPOSITE_FACING`
  -- is this project's own Lua-side equivalent of `$29E4` (a plain
  -- lookup, exactly as correct as the real bit trick since every real
  -- input is one-hot). Falls back through the SAME `"up"`-default path
  -- as 0x80 when facing is missing/unrecognized -- `OPPOSITE_FACING
  -- .up = "down"`, so the honest default resolves to `PLAYER_FACING_BIT
  -- .down | 0xB0` here, deliberately different from 0x80's own default
  -- result (a real, correct consequence of the two opcodes' different
  -- real formulas, not an inconsistency).
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_81,
    StandardScriptHandlers.actorAction(function()
      local opposite = EntityStructLayout.OPPOSITE_FACING[resolvePlayerFacing()]
      return EntityStructLayout.PLAYER_FACING_BIT[opposite] + 0xB0
    end, isActorReady, ctx.onActorAction))

  interp:registerHandler(ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS,
    StandardScriptHandlers.message(ctx.onMessage or function() end))
  if ctx.stats then
    interp:registerHandler(ScriptOpcodeTable.HEAL_LP_HANDLER_ADDRESS,
      StandardScriptHandlers.healToMax(ctx.stats, "curLP", "maxLP"))
    interp:registerHandler(ScriptOpcodeTable.HEAL_MP_HANDLER_ADDRESS,
      StandardScriptHandlers.healToMax(ctx.stats, "curMP", "maxMP"))
  end
  interp:registerHandler(ScriptOpcodeTable.SKIP_HANDLER_ADDRESS, StandardScriptHandlers.skip())
  interp:registerHandler(ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS,
    StandardScriptHandlers.chain(self.queue, ctx.onChainTarget))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_FLAG_LIST_HANDLER_ADDRESS,
    StandardScriptHandlers.zeroTerminatedFlagList(ctx.onFlagTest, ctx.onFlagListExhausted))
  -- `0x09`/`0x0A` (added 2026-08-14, whole-corpus scan): structurally
  -- identical to `0x08` just above (same "REQUIRED, no guessing"
  -- exhausted contract) -- but each targets a real, DIFFERENT WRAM
  -- array, so each gets its own distinctly-named ctx callback triple
  -- rather than sharing `0x08`'s own -- see `StandardScriptHandlers
  -- .timerListSearch`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_09,
    StandardScriptHandlers.timerListSearch(ctx.onAdjustTimers09, ctx.onTimerListTest09, ctx.onTimerListExhausted09))
  interp:registerHandler(ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_0A,
    StandardScriptHandlers.timerListSearch(ctx.onAdjustTimers0A, ctx.onTimerListTest0A, ctx.onTimerListExhausted0A))
  -- `0x0B`/`0x0C` (added 2026-08-14, whole-corpus scan): both real
  -- opcodes read the SAME 2 real WRAM cells (`$D871`/`$D873` bit 7),
  -- so `ctx.runListMatchByte`/`ctx.isRunListGateSet` are shared -- only
  -- the real gate POLARITY (`searchWhenGateSet`) and each opcode's own
  -- `onExhausted` differ -- see `StandardScriptHandlers.runListSearch`'s
  -- own doc comment. Both are REQUIRED ctx fields (no safe default for
  -- a real byte comparison) -- only registered if BOTH are supplied.
  if ctx.runListMatchByte and ctx.isRunListGateSet then
    interp:registerHandler(ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0B,
      StandardScriptHandlers.runListSearch(false, ctx.runListMatchByte, ctx.isRunListGateSet, ctx.onRunListExhausted0B))
    interp:registerHandler(ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0C,
      StandardScriptHandlers.runListSearch(true, ctx.runListMatchByte, ctx.isRunListGateSet, ctx.onRunListExhausted0C))
  end
  if ctx.flags then
    interp:registerHandler(ScriptOpcodeTable.FLAG_SET_HANDLER_ADDRESS,
      StandardScriptHandlers.setFlagBit(ctx.flags, 1))
    interp:registerHandler(ScriptOpcodeTable.FLAG_CLEAR_HANDLER_ADDRESS,
      StandardScriptHandlers.clearFlagBit(ctx.flags, 1))
  end
  -- `0xB8`/`0xB9` (added 2026-08-14, whole-corpus scan): a real,
  -- DIFFERENT WRAM cell ($C3F1) than `ctx.flags`'s own $D874, so a
  -- separate `ctx.wramBitFlags` table -- same "only register if the
  -- caller actually wants to track this real cell" convention.
  if ctx.wramBitFlags then
    interp:registerHandler(ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B8,
      StandardScriptHandlers.wramBitCommand(ctx.wramBitFlags, 0, true, ctx.onWramBitCommandLeafB8))
    interp:registerHandler(ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9,
      StandardScriptHandlers.wramBitCommand(ctx.wramBitFlags, 0, false, ctx.onWramBitCommandLeafB9))
  end
  -- `0xA3`/`0xA5`/`0xA6` (added 2026-08-14, whole-corpus scan): a
  -- real, THIRD different WRAM cell ($C4D4) -- yet another separate
  -- `{byte=int}` proxy, same "only register if the caller actually
  -- wants to track this real cell" convention as `ctx.flags`/
  -- `ctx.wramBitFlags` above.
  if ctx.actorStateFlags then
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A3,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 4))
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A5,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 5))
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A6,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 6))
  end
  interp:registerHandler(ScriptOpcodeTable.TICK_HANDLER_ADDRESS,
    StandardScriptHandlers.tick(ctx.onTick))
  interp:registerHandler(ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS,
    StandardScriptHandlers.startTextboxWait(ctx.onTick, isDone))
  interp:registerHandler(ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS,
    StandardScriptHandlers.textboxWait(ctx.onTick, isDone))
  interp:registerHandler(ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS,
    StandardScriptHandlers.typewriterCommand(ctx.onTypewriterCommand, self.queue))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0xFC`/`0xFD` (added 2026-08-13, task #86): both real handlers
  -- share the SAME real WRAM latch (`$D499`) -- they're mutually-
  -- exclusive alternatives of one real state machine, not independent
  -- state, so this project's own Lua port shares ONE closure-local
  -- latch between their two registrations (matching the real ROM's own
  -- single shared byte) rather than exposing it via `ctx` -- no caller
  -- outside this runtime instance has a legitimate reason to inspect
  -- or override it. `ctx.isTriggerEventGateClear` (optional, defaults
  -- to "always clear" -- see `StandardScriptHandlers
  -- .oneShotTriggerGate`'s own doc comment for why that matches the
  -- one real case this project has actually observed) models the real
  -- `$C8E0`/`$CEE8` dual gate both opcodes also share.
  do
    local triggerLatch = { resumeCursor = false }
    local function getLatch() return triggerLatch.resumeCursor end
    local function setLatch(v) triggerLatch.resumeCursor = v end
    interp:registerHandler(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC,
      StandardScriptHandlers.oneShotTriggerGate(5, getLatch, setLatch,
        ctx.isTriggerEventGateClear, ctx.onTriggerEvent))
    interp:registerHandler(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FD,
      StandardScriptHandlers.oneShotTriggerGate(4, getLatch, setLatch,
        ctx.isTriggerEventGateClear, ctx.onTriggerEvent))
  end
  -- `0xE8`/`0xE9` (added 2026-08-14, whole-corpus scan -- see
  -- `StandardScriptHandlers.dualGateLeafCommand`'s own doc comment):
  -- real, SAME `$C8E0`/`$CEE8` dual gate as `0xFC`/`0xFD` just above
  -- (reuses the SAME `ctx.isTriggerEventGateClear`, the real WRAM
  -- cells are identical), but no operand byte and no one-shot latch --
  -- each fires its own real, distinct VRAM-tile-pattern-update leaf
  -- every time it dispatches, not once per activation.
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E8,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafE8))
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E9,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafE9))
  -- `0xEA`/`0xEB` (added 2026-08-14, whole-corpus scan rank-3 blocker):
  -- completes the real 4-direction family alongside `0xE8`/`0xE9`
  -- (North/South) above -- East/West, SAME shared gate, SAME factory,
  -- no new Lua code.
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EA,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafEA))
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EB,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafEB))
  -- `0xFB`/`0xBF` (added 2026-08-14, whole-corpus scan): both real
  -- "periodic cosmetic WRAM-effect" leaves with a fully self-contained
  -- private phase counter (real WRAM `$D499` is shared/global in the
  -- ROM, but nothing else in this project's model reads it back) --
  -- unconditional, no `ctx` gating needed, since `onUpdate`/`onDim`/
  -- `onBright` are all genuinely optional observers, not required
  -- state -- see `StandardScriptHandlers.periodicWramEffect`'s own doc
  -- comment.
  interp:registerHandler(ScriptOpcodeTable.WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB,
    StandardScriptHandlers.waveOffsetEffect(ctx.onWaveOffsetUpdate))
  interp:registerHandler(ScriptOpcodeTable.COLOR_PULSE_EFFECT_HANDLER_ADDRESS_BF,
    StandardScriptHandlers.colorPulseEffect(ctx.onColorPulseDim, ctx.onColorPulseBright))
  -- `0x88`/`0x89` (added 2026-08-14, "konsolidiere unsere Entdeckungen"
  -- -- both real, live-confirmed boss-defeat script opcodes): fixed
  -- per-opcode constant, unconditional, `onWrite` is a genuinely
  -- optional observer -- see `StandardScriptHandlers
  -- .playerEntityTypeWrite`'s own doc comment. Both share ONE `ctx`
  -- callback (`ctx.onPlayerEntityTypeWrite`) since the fixed value
  -- itself already tells a caller which opcode fired.
  interp:registerHandler(ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_88,
    StandardScriptHandlers.playerEntityTypeWrite(2, ctx.onPlayerEntityTypeWrite))
  interp:registerHandler(ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_89,
    StandardScriptHandlers.playerEntityTypeWrite(1, ctx.onPlayerEntityTypeWrite))
  -- `0x8F` (added 2026-08-14, whole-corpus scan rank-3 blocker): real
  -- conditional halt on the SAME `$C5A0` actor-command table opcode
  -- `0x00`'s own gate reads (tasks #85/#86) -- unconditional
  -- registration since `ctx.isActorCommandQueueEmpty` is optional
  -- (defaults to "always empty," same honest gap as
  -- `ctx.isActorReady`/`ctx.isQueueBlocked` -- no live WRAM
  -- actor-command simulation exists in this project).
  interp:registerHandler(ScriptOpcodeTable.ACTOR_COMMAND_QUEUE_EMPTY_GATE_HANDLER_ADDRESS_8F,
    StandardScriptHandlers.actorCommandQueueEmptyGate(ctx.isActorCommandQueueEmpty))
  -- `0x90`/`0x91`/`0x94`-`0x99` (added 2026-08-14, whole-corpus scan
  -- rank-3 blocker after `0x8F`'s own closure): the `$1606` cluster --
  -- explicit registration (NOT the generic `ACTOR_ACTION_HANDLER_
  -- ADDRESS_`/`QUEUED_ACTION_HANDLER_ADDRESS_` loop below, deliberately
  -- excluded by this constant family's own different name prefix,
  -- since these have a real, different not-ready behavior -- see
  -- `StandardScriptHandlers.actorActionOrSkip`'s own doc comment).
  -- Reuses the SAME `isActorReady` local (the real `$28C2` gate is
  -- identical to the sibling family's own). Unlike the generic loop,
  -- explicit registration lets each real opcode's own group value
  -- reach `ctx.onActorActionOrSkip` for real -- not lost to `nil` the
  -- way the generic family's own "HONEST LIMIT" note describes.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_90,
    StandardScriptHandlers.actorActionOrSkip(0x04, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_91,
    StandardScriptHandlers.actorActionOrSkip(0x05, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_96,
    StandardScriptHandlers.actorActionOrSkip(0x1C, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_97,
    StandardScriptHandlers.actorActionOrSkip(0x1D, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_94,
    StandardScriptHandlers.actorActionOrSkip(0x1E, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_95,
    StandardScriptHandlers.actorActionOrSkip(0x1F, isActorReady, ctx.onActorActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.QUEUED_ACTION_OR_SKIP_HANDLER_ADDRESS_98,
    StandardScriptHandlers.queuedActionOrSkip(isActorReady, ctx.onQueuedActionOrSkip))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_OR_SKIP_HANDLER_ADDRESS_99,
    StandardScriptHandlers.actorSlotPositionOrSkip(isActorReady, ctx.onSetActorSlotPosition))
  -- `0xEF` (added 2026-08-14, whole-corpus scan -- $0E73's own
  -- neighborhood): a real, simple "store 2 operand bytes into WRAM
  -- $C344/$C345" primitive. `0xEC`/`0xED`/`0xEE` (the SAME
  -- neighborhood's own siblings) are deliberately NOT registered --
  -- see `ScriptOpcodeTable.lua`'s own doc comment: a third confirmed
  -- member of the `0x80`/`$15A4` known-hard family (`$02AB`).
  interp:registerHandler(ScriptOpcodeTable.TILE_CURSOR_SET_HANDLER_ADDRESS_EF,
    StandardScriptHandlers.tileCursorSet(ctx.onTileCursorSet))
  -- `0x7A`/`0x7B` (added 2026-08-14, whole-corpus scan -- next real
  -- untouched blocker after the `$0E73` neighborhood): a real
  -- "readiness-as-parameter" actor-action family, unconditional (no
  -- not-ready path at all) -- see `StandardScriptHandlers
  -- .actorActionWithReadinessParam`'s own doc comment for the full
  -- disassembly. Explicit registration (not the generic
  -- `^ACTOR_ACTION_HANDLER_ADDRESS_` loop -- this constant family
  -- deliberately uses a different name so it isn't picked up there)
  -- so each opcode's own real fixed group/offset reach `ctx` intact.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x5A`/`0x5B` (added 2026-08-14, whole-corpus scan): 2 more
  -- `actorActionWithReadinessParam` members, offset `0x04`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x6A`/`0x6B` (added 2026-08-14, whole-corpus scan): 2 more
  -- `actorActionWithReadinessParam` members, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x24` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorActionWithReadinessParam` member, offset `0x01`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_24,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x01, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x68` (added 2026-08-14, whole-corpus scan): a real queued-
  -- action, readiness-as-parameter command.
  interp:registerHandler(ScriptOpcodeTable.QUEUED_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_68,
    StandardScriptHandlers.queuedActionWithReadinessParam(0x05, isActorReady, ctx.onQueuedActionWithReadinessParam))
  -- `0x74` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorActionWithReadinessParam` member, offset `0x06`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_74,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x54` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorActionWithReadinessParam` member, offset `0x04`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_54,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0xA9` (added 2026-08-14, whole-corpus scan): a real "3-way
  -- classified flag-bit SET/CLEAR" command -- see
  -- `StandardScriptHandlers.threeWayFlagBitCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.THREE_WAY_FLAG_BIT_COMMAND_HANDLER_ADDRESS_A9,
    StandardScriptHandlers.threeWayFlagBitCommand(ctx.getFlagBitClassifyValue, ctx.onFlagBitSet, ctx.onFlagBitClear))
  -- `0x67` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorActionWithReadinessParam` member, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_67,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1D, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x4A`/`0x66` (added 2026-08-14, whole-corpus scan): 2 more
  -- `actorActionWithReadinessParam` members.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_4A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x03, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_66,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1C, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x76` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorActionWithReadinessParam` member, offset `0x06`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_76,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1C, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0xCC` (added 2026-08-14, whole-corpus scan): a real, zero-
  -- operand-byte "re-mirror my own opcode byte" primitive -- see
  -- `StandardScriptHandlers.opcodeByteMirror`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC,
    StandardScriptHandlers.opcodeByteMirror(ctx.onOpcodeByteMirror))
  -- `0xC8` (added 2026-08-14, whole-corpus scan): a real, decisive
  -- "SOFT RESET the whole game" command -- see
  -- `StandardScriptHandlers.softReset`'s own doc comment. `ctx
  -- .onSoftReset` is REQUIRED (no honest default exists for
  -- restarting the game) -- this handler REGISTERS unconditionally
  -- (most real scripts never reach `0xC8`, so a `ScriptRuntime`
  -- shouldn't be forced to supply this just to exist), but fails
  -- loudly, at real dispatch time, the first time `0xC8` actually
  -- runs without a real `ctx.onSoftReset` provided -- see
  -- `.softReset`'s own doc comment for why the assertion is deferred
  -- to dispatch time instead of construction time.
  interp:registerHandler(ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8,
    StandardScriptHandlers.softReset(ctx.onSoftReset))
  -- `0xD1` (added 2026-08-14, whole-corpus scan): a real "budget
  -- countdown, SET/CLEAR flag bit 6" command -- see
  -- `StandardScriptHandlers.budgetFlagCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.BUDGET_FLAG_COMMAND_HANDLER_ADDRESS_D1,
    StandardScriptHandlers.budgetFlagCommand(ctx.hasSufficientBudget, ctx.onBudgetSufficient, ctx.onBudgetExhausted))
  -- `0x9C`/`0x9D` (added 2026-08-14, whole-corpus scan): a real "raw
  -- single-byte leaf command" family, same real leaf (`$2895`) --
  -- see `StandardScriptHandlers.rawByteLeafCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9C,
    StandardScriptHandlers.rawByteLeafCommand(ctx.onRawByteLeaf))
  interp:registerHandler(ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9D,
    StandardScriptHandlers.rawByteLeafCommand(ctx.onRawByteLeaf))
  -- `0xC6` (added 2026-08-14, whole-corpus scan): a real "scene/
  -- textbox init" command, the SAME 5 WRAM cells as opcode `0xF6`'s
  -- own already-hypothesized initializer -- see
  -- `StandardScriptHandlers.sceneInitCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.SCENE_INIT_COMMAND_HANDLER_ADDRESS_C6,
    StandardScriptHandlers.sceneInitCommand(ctx.onSceneInit))
  -- `0xC7` (added 2026-08-14, whole-corpus scan): a real "2-bit WRAM
  -- field write" command -- see `StandardScriptHandlers
  -- .twoBitFieldCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.TWO_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C7,
    StandardScriptHandlers.twoBitFieldCommand(ctx.getTwoBitFieldValue, ctx.onTwoBitFieldWrite))
  -- `0xDA`/`0xDB` (added 2026-08-14, whole-corpus scan): a real
  -- dynamic-index flag-bit SET/CLEAR family -- see
  -- `StandardScriptHandlers.dynamicFlagBitCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DA,
    StandardScriptHandlers.dynamicFlagBitCommand(true, ctx.onDynamicFlagBit))
  interp:registerHandler(ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DB,
    StandardScriptHandlers.dynamicFlagBitCommand(false, ctx.onDynamicFlagBit))
  -- `0xC2` (added 2026-08-14, whole-corpus scan): a real "bitmask
  -- dispatch" command -- see `StandardScriptHandlers
  -- .bitmaskDispatchCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.BITMASK_DISPATCH_COMMAND_HANDLER_ADDRESS_C2,
    StandardScriptHandlers.bitmaskDispatchCommand(ctx.onBitmaskDispatch))
  -- `0xAF` (added 2026-08-14, whole-corpus scan): a real "chained
  -- opaque effect" command, 4 sequential untraced leaves -- see
  -- `StandardScriptHandlers.chainedOpaqueEffectCommand`'s own doc
  -- comment.
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AF,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  -- `0xB7` (added 2026-08-14, whole-corpus scan): real `$1ED7`
  -- selector `0x17` trampoline -- SAME shape as `0xAF`, reuses the
  -- same factory and callback (this project's own established
  -- "reuse the same callback when neither opcode's own distinction is
  -- threaded through yet" convention).
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_B7,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  -- `0xC5` (added 2026-08-14, whole-corpus scan): a real "6-bit WRAM
  -- field write" command -- see `StandardScriptHandlers
  -- .sixBitFieldCommand`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.SIX_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C5,
    StandardScriptHandlers.sixBitFieldCommand(ctx.onSixBitFieldWrite))
  -- `0x79` (added 2026-08-14, whole-corpus scan): a real actor-slot-
  -- position command, readiness used as the slot parameter -- see
  -- `StandardScriptHandlers.actorSlotPositionWithReadinessParam`'s
  -- own doc comment.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_79,
    StandardScriptHandlers.actorSlotPositionWithReadinessParam(0x06, isActorReady, ctx.onActorSlotPositionWithReadinessParam))
  -- `0x69` (added 2026-08-14, whole-corpus scan): 1 more
  -- `actorSlotPositionWithReadinessParam` member, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_69,
    StandardScriptHandlers.actorSlotPositionWithReadinessParam(0x05, isActorReady, ctx.onActorSlotPositionWithReadinessParam))
  -- `0x19` ($12AE, added 2026-08-13): the SAME real `$123E` mechanism as
  -- `0x49` above (see ScriptOpcodeTable's own doc comment for the
  -- disassembly proving it), just reached via a different trampoline
  -- base -- that base only changes the derived actor-slot index, which
  -- this project doesn't thread through to `ctx` yet (see `0x49`'s own
  -- "HONEST LIMIT" note above), so it's honest to reuse the SAME
  -- `ctx.onSetActorSlotPosition` callback here rather than inventing a
  -- second one this codebase can't yet distinguish by actor slot.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_19,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x59` ($147E, added 2026-08-13, task #80's all-script census):
  -- the SAME real $123E mechanism yet again -- see 0x49/0x19's own doc
  -- comments above.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_59,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x39` ($1396, added 2026-08-13, task #82): the SAME real $123E
  -- mechanism yet again -- see 0x49/0x19/0x59's own doc comments above.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_39,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x29` ($1322, added 2026-08-13, task #86): the SAME real $123E
  -- mechanism yet again -- see 0x49/0x19/0x59/0x39's own doc comments
  -- above -- found live against the real boss-defeat sequence itself
  -- (past the newly-wired 0x08), not the earlier whole-corpus census.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_29,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0xD4`/`0xD6`/`0xD8` (added 2026-08-13, task #86): all 3 share the
  -- SAME real `$D86F` bit-1 gate -- see `StandardScriptHandlers
  -- .gatedByteLeafCommand`'s own doc comment for the honest scope of
  -- what's not modeled (the real bit-SET path). `ctx.isFadeActive`
  -- defaults to "never active", matching every real occurrence this
  -- project has actually observed live.
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D4,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D6,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D8,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  -- `0xD5`/`0xD7`/`0xD9` (added 2026-08-13, task #86): the ungated
  -- sibling family -- see `StandardScriptHandlers.byteLeafCommand`'s
  -- own doc comment.
  interp:registerHandler(ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D5,
    StandardScriptHandlers.byteLeafCommand(ctx.onGatedByteLeaf))
  interp:registerHandler(ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D7,
    StandardScriptHandlers.byteLeafCommand(ctx.onGatedByteLeaf))
  interp:registerHandler(ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D9,
    StandardScriptHandlers.byteLeafCommand(ctx.onGatedByteLeaf))
  interp:registerHandler(ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS,
    StandardScriptHandlers.queueGate(self.queue, ctx.isQueueBlocked, ctx.onQueueIdle))
  interp:registerHandler(ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS,
    StandardScriptHandlers.byteWordCommand(ctx.onByteWordCommand))
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommand))
  -- `0xCB` ($392C, added 2026-08-13, task #82): the SAME real 2-operand-
  -- byte "read into DE, call a leaf, always continue" SHAPE as
  -- `TWO_BYTE_COMMAND_HANDLER_ADDRESS` above, but a genuinely DIFFERENT
  -- real target ($3937, untraced) -- gets its OWN `ctx` callback rather
  -- than sharing `ctx.onTwoByteCommand`, since conflating two different
  -- real leaf routines under one callback would misrepresent them as
  -- the same real action.
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandCB))
  -- `0xC9`/`0xCA` (added 2026-08-13, task #86): same family as `0xCB`
  -- above, own dedicated callbacks (different fixed `BC` each -- see
  -- ScriptOpcodeTable's own doc comment).
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_C9,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandC9))
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CA,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandCA))
  -- `0xF3`/`0xF4` (added 2026-08-13, task #86): share the SAME real
  -- `$D499` gate this project's own `isPeekGateClear` models -- see
  -- `StandardScriptHandlers.peekTwoByteGate`'s own doc comment.
  interp:registerHandler(ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3,
    StandardScriptHandlers.peekTwoByteGate(ctx.onPeekTwoByteGate, ctx.isPeekGateClear))
  interp:registerHandler(ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F4,
    StandardScriptHandlers.peekTwoByteGate(ctx.onPeekTwoByteGate, ctx.isPeekGateClear))

  -- CORRECTED/EXTENDED (2026-08-13, direct follow-up to a real, live
  -- shadow-run against the actual boss-defeat script bytes: the FIRST
  -- opcode this project's own hand-picked registration list above
  -- didn't cover turned out to be `0x48`, a real, already-NAMED
  -- `QUEUED_ACTION_HANDLER_ADDRESS_48` constant -- i.e. this runtime was
  -- stopping on opcodes this project HAS already decoded the dispatch
  -- shape for, just because nothing had registered them here yet, not
  -- because they're genuinely undecoded). Real opcode FAMILIES sharing
  -- one handler shape (actor-action, queued-action, trigger-event, sound
  -- -param, word-command) are now registered GENERICALLY, by scanning
  -- every matching `ScriptOpcodeTable.*_HANDLER_ADDRESS*` constant --
  -- picks up every opcode this project has currently decoded into that
  -- family (and any future addition) without a hand-maintained,
  -- easily-stale list here.
  --
  -- HONEST LIMIT: the real, specific "group" value each actor-action
  -- opcode's own real ROM code bakes in (see ScriptOpcodeTable.lua's own
  -- per-constant `-- group 0xNN` comments) is only recorded there as a
  -- Lua COMMENT, not machine-readable data -- this generic pass has no
  -- way to look it up per-address, so `onActorAction`/`onQueuedAction`
  -- fire with `group = nil` here (a real, honest "unknown" marker, not a
  -- fabricated placeholder value) rather than reproducing a specific
  -- opcode's own real group. A caller that needs the real per-opcode
  -- group should register that one address directly (see
  -- `:registerHandler`, exposed via `self.interp`) with a real, specific
  -- `StandardScriptHandlers.actorAction(<real group>, ...)` call instead.
  for key, addr in pairs(ScriptOpcodeTable) do
    if type(addr) == "number" then
      if key:match("^ACTOR_ACTION_HANDLER_ADDRESS_80$") then
        -- UPDATED 2026-08-14 (task 10, "$02AB wirklich lösen"):
        -- already explicitly registered above with its real, live,
        -- dynamic group (the player's own real facing direction, see
        -- that registration's own doc comment) -- excluded here only
        -- so this generic sweep doesn't overwrite that more precise
        -- registration with a group-less generic one, same pattern as
        -- the `_7B$`/`WORD_COMMAND_HANDLER_ADDRESS_EF$` exclusions
        -- below. No longer "documented-dynamic, unmodelable" -- that
        -- was the OLD, since-corrected reasoning.
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_81$") then
        -- CRACKED 2026-08-14 (direct continuation of the 0x80 fix,
        -- same session, "gamemap absolute prio" pass): already
        -- explicitly registered above with its real, live, dynamic
        -- group (opposite-facing | 0xB0, see that registration's own
        -- doc comment) -- excluded here for the SAME reason as the
        -- `_80$` exclusion right above: so this generic sweep doesn't
        -- overwrite it with a group-less generic registration.
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_7B$") then
        -- SELF-CAUGHT BUG, fixed 2026-08-14 (task-11 quality pass, "kommentiere
        -- alles"): opcode `0x7B` was originally discovered TWICE, in two
        -- separate sessions -- first as a plain Family-A member (this old
        -- constant, `$157C`, registered generically with a FIXED, discarded
        -- group and NO real `param`), then again the SAME day as part of the
        -- `actorActionWithReadinessParam` family (`ACTOR_ACTION_WITH_
        -- READINESS_PARAM_HANDLER_ADDRESS_7B`, same real address, exposing
        -- the real computed `param` -- see that function's own doc comment).
        -- This loop used to ALSO match the old constant and silently
        -- OVERWRITE the newer, more precise explicit registration (which
        -- runs earlier in this same function) -- LIVE-VERIFIED: before this
        -- fix, dispatching opcode `0x7B` fired `ctx.onActorAction` (the
        -- generic, information-losing callback), never `ctx
        -- .onActorActionWithReadinessParam` (the correct, already-wired
        -- one). Excluded here (same pattern as the `_80$`/`WORD_COMMAND_
        -- HANDLER_ADDRESS_EF$` exclusions above) so the explicit, more
        -- precise registration wins. The old constant is kept, not deleted
        -- (existing tests assert it against the real opcode-table bytes).
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_") then
        interp:registerHandler(addr, StandardScriptHandlers.actorAction(nil, isActorReady, ctx.onActorAction))
      elseif key:match("^QUEUED_ACTION_HANDLER_ADDRESS_") then
        interp:registerHandler(addr, StandardScriptHandlers.queuedAction(isActorReady, ctx.onQueuedAction))
      elseif key:match("^TRIGGER_EVENT_HANDLER_ADDRESS") then
        interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(ctx.onTriggerEvent))
      elseif key:match("^SOUND_PARAM") then
        interp:registerHandler(addr, StandardScriptHandlers.soundParam(ctx.onSoundParam))
      elseif key:match("^WORD_COMMAND_HANDLER_ADDRESS_EF$") then
        -- SELF-CAUGHT BUG, fixed 2026-08-14 (whole-corpus scan
        -- follow-up): this generic sweep used to also pick up
        -- `WORD_COMMAND_HANDLER_ADDRESS_EF` and silently OVERWRITE the
        -- more precise, explicit `TILE_CURSOR_SET_HANDLER_ADDRESS_EF`
        -- registration above (same real address, `$0E7F`) with the
        -- less precise generic `wordCommand` handler, since this loop
        -- runs AFTER that explicit call -- meaning the new handler was
        -- dead code the whole time it existed. Excluded here (same
        -- pattern as the `ACTOR_ACTION_HANDLER_ADDRESS_80` exclusion
        -- above) so the explicit registration actually wins. See
        -- `ScriptOpcodeTable.lua`'s own `WORD_COMMAND_HANDLER_ADDRESS_EF`
        -- doc comment for the full story.
      elseif key:match("^WORD_COMMAND_HANDLER_ADDRESS") then
        interp:registerHandler(addr, StandardScriptHandlers.wordCommand(ctx.onWordCommand))
      end
    end
  end
end

--- One real per-tick step. Safe to call every real game frame (or in a
-- tight burst, see `:run()`) -- once a real, still-undecoded opcode is
-- reached (or any other Lua error), captures it into `self.stopped`/
-- `self.stopError` and becomes a permanent no-op from then on (never
-- re-throws), so a caller doesn't need its own pcall boilerplate. The
-- failure is real, inspectable state, not swallowed -- see this
-- module's own "no silent fallbacks" note above.
function ScriptRuntime:step(stream, cursor)
  if self.stopped or self.finished then
    return cursor
  end
  local ok, newCursorOrErr, opcode, kind = pcall(function()
    return self.interp:step(stream, cursor)
  end)
  if not ok then
    self.stopped = true
    self.stopError = newCursorOrErr
    return cursor
  end
  self.stepCount = self.stepCount + 1
  self.opcodeCounts[opcode] = (self.opcodeCounts[opcode] or 0) + 1
  self.lastOpcode = opcode
  self.lastKind = kind
  self.lastCursor = newCursorOrErr
  return newCursorOrErr
end

--- Steps up to `maxSteps` times (or until this run stops/finishes,
-- whichever comes first) -- a bounded burst, so a caller running this
-- synchronously (e.g. VictorySequence.lua's own shadow-run at
-- construction time, not per real game frame) can never hang on a real
-- script that happens to loop far longer than expected. Returns the
-- final cursor.
function ScriptRuntime:run(stream, cursor, maxSteps)
  for _ = 1, maxSteps do
    if self.stopped or self.finished then break end
    cursor = self:step(stream, cursor)
  end
  return cursor
end

return ScriptRuntime
