-- General-purpose driver tying `ScriptInterpreter` + `StandardScriptHandlers`
-- + `ScriptContinuationQueue` together against a live gameplay context --
-- registers every currently-decoded handler this project has (see
-- StandardScriptHandlers.lua), so any caller driving any of the 1357 ROM
-- scripts (rom_profiles.lua's `scriptPointerTable`) gets the full, current
-- opcode coverage without re-wiring the registration boilerplate itself.
-- See VictorySequence.lua's doc comment for the actual gameplay wiring
-- (a parallel, opt-in "shadow run" that never controls real
-- rendering/state -- the existing hand-authored cutscene logic stays
-- fully in charge either way).
--
-- HONEST SCOPE: only wires the opcodes this project has actually decoded
-- a Lua handler for (currently ~90/256, see ScriptOpcodeTable.lua's
-- running tally, though one concrete script -- the boss-defeat sequence
-- -- is known to use several not among them: opcodes `0x5A`, `0x08`,
-- `0x88`, `0xBF`/`0xBC`/`0xBD`/`0xF3`, see events.md's "boss-defeat
-- script: every opcode it actually uses, decoded" section). Any script
-- that reaches a still-undecoded opcode genuinely, loudly fails the
-- moment it's reached (`ScriptInterpreter:step`'s "no silent fallbacks"
-- error) -- `:step()` below catches that one failure per run and reports
-- it as inspectable state instead of throwing again on every subsequent
-- call, so a caller driving this once per game tick (or once in a
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

--- `opcodeEntries`: the decoded 256-entry table (`ScriptOpcodeTable
-- .decode(romData, profile.scriptOpcodeTable)`).
--
-- `ctx`: a plain table of live callbacks/state this runtime's
-- registered handlers read/write. Every field is OPTIONAL -- an absent
-- one just means that opcode family's side effect never fires and its
-- handler is never registered at all (so a script that actually needs
-- it fails loudly at that opcode, same "no silent fallbacks" rule as
-- everywhere else in this project, rather than silently no-op-ing).
--   ctx.stats             -- a Stats-shaped table (curLP/maxLP/curMP/
--                             maxMP) for the 0xC0/0x32 heal-to-max
--                             opcodes.
--   ctx.flags              -- a `{ byte = <int> }` shadow of WRAM
--                             `$D874`, for the 0xDC/0xDD set/clear-
--                             bit-1 opcodes (bit 1 is fixed by the ROM
--                             instruction itself, not a parameter).
--   ctx.wramBitFlags       -- a `{ byte = <int> }` shadow of a
--                             different WRAM cell (`$C3F1`), for the
--                             0xB8/0xB9 set/clear-bit-0 opcodes.
--   ctx.onWramBitCommandLeafB8/B9() -- opaque per-opcode leaf callbacks
--                             for those same 2 opcodes' self-contained
--                             side effects (fixed sound-parameter WRAM
--                             writes this project doesn't otherwise
--                             model) -- see
--                             `StandardScriptHandlers.wramBitCommand`'s
--                             doc comment.
--   ctx.actorStateFlags     -- a `{ byte = <int> }` shadow of a third
--                             different WRAM cell (`$C4D4`), for the
--                             `0xA3`/`0xA5`/`0xA6` bit-SET opcodes
--                             (bits 4/5/6 respectively) -- see
--                             `StandardScriptHandlers
--                             .fixedWramBitSetSkipCommand`'s doc
--                             comment. Optional, same "only register
--                             if the caller wants to track this cell"
--                             convention as `ctx.flags`/
--                             `ctx.wramBitFlags` above.
--   ctx.queue               -- a ScriptContinuationQueue (built fresh
--                             here if omitted) for CHAIN/
--                             typewriterCommand/queueGate's WRAM-FIFO
--                             side effects.
--   ctx.onMessage(id)       -- opcode 0xFE.
--   ctx.onTick()            -- the per-CHARACTER pacing callback, fired
--                             once per 5-frame tick while opcode 0x04
--                             reveals a text byte, and also inside
--                             0xF0/0xFF's pacing.
--   ctx.onControlCode(byte) -- opcode 0x04's own control-code family
--                             (see StandardScriptHandlers.tick's doc
--                             comment): fires with the raw control byte
--                             (0x10-0x1F) every tick while the
--                             text-reveal classifier is sitting on one
--                             instead of a printable character. Return
--                             a NUMBER (0 or more) once processing is
--                             done -- "consume 1 control byte plus this
--                             many extra bytes" (some control codes
--                             bridge through the already-documented
--                             `$36D0` primitive, which advances the
--                             cursor one more byte beyond the control
--                             byte itself) -- or return `false`/`nil`
--                             to signal "still pacing, not done yet"
--                             (a halt, re-dispatched next tick, exactly
--                             like the classifier's own text-character
--                             pacing). Optional -- a caller that
--                             doesn't supply this keeps the old,
--                             simpler "immediate single-byte consume"
--                             behavior, an honest default for any
--                             control code this project hasn't
--                             live-traced the exact pacing/bridge
--                             behavior of yet -- see that handler's
--                             "HONEST SCOPE" note for what's not
--                             modeled even for the traced ones (the
--                             deeper bank-2-delegated WRAM side
--                             effects).
--   ctx.isTextboxDone()     -- the release condition for 0xF0/0xFF --
--                             required in spirit if either is ever
--                             reached; defaults to an always-true stub
--                             (releases immediately, i.e. never
--                             actually halts) when omitted -- a
--                             clearly-flagged stand-in for "no display
--                             state wired up," not a guess about ROM
--                             behavior.
--   ctx.onTriggerEvent()    -- the whole TRIGGER_EVENT family (opcode
--                             0xE0 and every `_XX` variant, e.g.
--                             0xE1/0xE2/0xE4/0xE5/0xA0/0xB9/0xC3/0xDE),
--                             registered generically -- see
--                             `:registerStandardHandlers`'s doc comment
--                             below.
--   ctx.onSoundParam(v)     -- the whole SOUND_PARAM family (opcodes
--                             0xF8/0xF9/0xC4), registered generically,
--                             same shape as `onTriggerEvent`.
--   ctx.onWordCommand(v)    -- the WORD_COMMAND family (opcode 0xD0
--                             and its `_EF` variant), registered
--                             generically.
--   ctx.onByteWordCommand(byteValue, wordValue) -- opcode 0xB0.
--   ctx.onTwoByteCommand(byte1, byte2)          -- opcode 0xF6.
--   ctx.onActorAction(group) -- the whole ACTOR_ACTION family (14
--                             opcodes across this project's running
--                             tally, e.g. 0x10/0x11/0x14/...),
--                             registered generically -- `group` is
--                             always `nil` here (see
--                             `:registerStandardHandlers`'s "HONEST
--                             LIMIT" note: the per-opcode group value
--                             isn't machine-readable yet).
--   ctx.onQueuedAction()     -- the QUEUED_ACTION family (opcodes
--                             0x18/0x28/0x38/0x48/0x58/0x78).
--   ctx.onActorActionOrSkip(group) -- the `$1606` cluster's
--                             actor-action-shaped members (opcodes
--                             `0x90`/`0x91`/`0x94`-`0x97`) -- a
--                             different not-ready behavior from
--                             `onActorAction` above (soft skip, not
--                             halt -- see `StandardScriptHandlers
--                             .actorActionOrSkip`'s doc comment).
--                             `group` is the per-opcode value here
--                             (explicit registration, not the generic
--                             loop's `nil`-group limit).
--   ctx.onQueuedActionOrSkip() -- the `$1606` cluster's
--                             queued-action-shaped member (opcode
--                             `0x98`) -- see `StandardScriptHandlers
--                             .queuedActionOrSkip`'s doc comment.
--   ctx.isActorReady()       -- the halt condition shared by the
--                             actor-action, queued-action, and opcode
--                             0x49's gate (same underlying `$289B`
--                             WRAM-$C5A0 check as queued-action) -- no
--                             live WRAM actor-record state modeled,
--                             defaults to "always ready."
--   ctx.getPlayerFacing()    -- opcode `0x80` -- the player's current
--                             facing direction (`"up"`/`"down"`/
--                             `"left"`/`"right"`, matching `Player.lua`'s
--                             `self.facing` representation directly) --
--                             feeds `0x80`'s dynamic group computation
--                             (see `EntityStructLayout.PLAYER_FACING_BIT`'s
--                             doc comment for the live-trace evidence
--                             this is built on). Optional, defaults to
--                             `"up"` (matching this project's already-
--                             independently-verified
--                             `Player.DEFAULT_FACING`). Also feeds
--                             opcode `0x81` -- same callback, combined
--                             through `EntityStructLayout.OPPOSITE_FACING`
--                             first (0x81's formula reads the opposite
--                             of the player's current facing, see
--                             `ScriptOpcodeTable
--                             .ACTOR_ACTION_HANDLER_ADDRESS_81`'s doc
--                             comment for the full disassembly).
--   ctx.onSetActorSlotPosition(byte1, byte2) -- opcodes 0x49 and 0x19
--                             (the `$123E`-family members that consume
--                             operand bytes -- same handler reused for
--                             both, since neither's actor-slot index is
--                             threaded through to `ctx` yet) -- see
--                             StandardScriptHandlers.actorSlotPosition's
--                             doc comment for why these are the raw
--                             bytes, not the `*8`-transformed values.
--   ctx.onTwoByteCommandCB(byte1, byte2) -- opcode 0xCB -- structurally
--                             the same "2 operand bytes, opaque leaf
--                             callback, always continues" shape as
--                             `ctx.onTwoByteCommand` above, but a
--                             genuinely different ROM target ($392C vs
--                             $3CA2) -- kept as its own, separate
--                             callback rather than conflated.
--   ctx.onSetNpcTypes(row)   -- opcode `0xFC` (real `sSET_NPC_TYPES`,
--                             see `ScriptOpcodeTable
--                             .TRIGGER_EVENT_HANDLER_ADDRESS_FC`'s doc
--                             comment) -- fires once per activation with
--                             the real `NpcSpawnTable` row index to
--                             stage. NOT the generic `ctx.onTriggerEvent`
--                             above -- see `StandardScriptHandlers
--                             .oneShotTriggerGate`'s doc comment and this
--                             function's own `_FC$`/`_FD$` exclusion
--                             below for why sharing that name was a real,
--                             live bug.
--   ctx.onSpawnNpc(col)      -- opcode `0xFD` (real `sSPAWN_NPC`) --
--                             fires once per activation with the column
--                             to spawn from the row `onSetNpcTypes` most
--                             recently staged. Resolve `(row, col)`
--                             against `NpcSpawnTable.decode()`'s own
--                             output to get the real species IDs/count/
--                             positions -- this runtime intentionally
--                             does not do that resolution itself (same
--                             "raw values out, resolution is the
--                             caller's job" convention as every other
--                             `ctx.on*` callback here).
--   ctx.isTriggerEventGateClear() -- optional gate for the same two
--                             opcodes' dual-WRAM-cell check; defaults
--                             to "always clear" (matches the one case
--                             this project has actually observed live).
--                             Also reused by `0xE8`/`0xE9` below -- the
--                             WRAM cells are identical.
--   ctx.onDualGateLeafE8/E9/EA/EB() -- opcodes `0xE8`/`0xE9`/`0xEA`/
--                             `0xEB` -- each fires its own distinct
--                             VRAM-tile-pattern-update leaf once the
--                             shared dual gate above clears -- see
--                             `StandardScriptHandlers
--                             .dualGateLeafCommand`'s doc comment.
--   ctx.onWaveOffsetUpdate(value) -- opcode `0xFB` -- optional observer
--                             for the `$C0A6` wave-offset oscillator's
--                             running byte value -- see
--                             `StandardScriptHandlers
--                             .waveOffsetEffect`'s doc comment.
--   ctx.onColorPulseDim/Bright(r, g, b) -- opcode `0xBF` -- optional
--                             observers for the `$C0AA`-`$C0AC`
--                             dim/bright color-pulse triples -- see
--                             `StandardScriptHandlers
--                             .colorPulseEffect`'s doc comment.
--   ctx.onPlayerEntityTypeWrite(fixedValue) -- opcodes `0x88`/`0x89` --
--                             optional observer for the player entity's
--                             "TYPE" field write (WRAM `$C241`) -- see
--                             `StandardScriptHandlers
--                             .playerEntityTypeWrite`'s doc comment.
--   ctx.isActorCommandQueueEmpty() -- opcode `0x8F` -- conditional halt
--                             on the same `$C5A0` 8-slot actor-command
--                             table opcode `0x00` reads (see
--                             `StandardScriptHandlers
--                             .actorCommandQueueEmptyGate`'s doc
--                             comment) -- optional, defaults to
--                             "always empty" (no live WRAM
--                             actor-command simulation exists here).
--   ctx.onTileCursorSet(byte1, byte2) -- opcode `0xEF` (`$0E73`
--                             neighborhood) -- fires on every dispatch
--                             with the 2 raw operand bytes, before the
--                             3rd-byte `$3727` stream-skip -- the leaf
--                             (`$0454`) is a plain, branchless store
--                             into WRAM `$C344`(byte1)/`$C345`(byte2),
--                             no computation -- see `StandardScriptHandlers
--                             .tileCursorSet`'s doc comment. `0xEC`/
--                             `0xED`/`0xEE` (the same neighborhood's
--                             siblings) are deliberately NOT registered
--                             -- confirmed via disassembly to be a
--                             third sibling of the already-known-hard
--                             `0x80`/`$15A4` family (shared `$02AB`
--                             dependency) -- see `ScriptOpcodeTable.lua`'s
--                             doc comment at that address.
--   ctx.onActorActionWithReadinessParam(group, param) -- opcodes `0x7A`/
--                             `0x7B`/`0x5A`/`0x5B`/`0x6A` -- the same
--                             Family-A shape as `ctx.onActorAction`
--                             (byte-for-byte identical, no outer `JR NZ`
--                             for either family -- see
--                             `StandardScriptHandlers
--                             .actorActionWithReadinessParam`'s doc
--                             comment for the self-caught correction),
--                             gated the same way via `ctx.isActorReady()`
--                             -- fires only on the ready path, with the
--                             fixed `group` and computed `param` (always
--                             `offset+1` on the reachable path).
--   ctx.onOpcodeByteMirror(ownOpcodeByte) -- opcode `0xCC` -- fires on
--                             every dispatch with the byte value 0xCC
--                             itself (read back via a legitimate
--                             `stream[cursor-1]` lookback, not
--                             fabricated) -- see `StandardScriptHandlers
--                             .opcodeByteMirror`'s doc comment; purely
--                             observational, never affects the returned
--                             cursor (zero-operand-byte opcode).
--   ctx.onSoftReset() -- opcode `0xC8` -- fires on EVERY dispatch.
--                             REQUIRED, not optional (no default) --
--                             see `StandardScriptHandlers.softReset`'s
--                             doc comment: the ROM jumps to its own
--                             cartridge boot vector here (`$0100`/
--                             `$0150`/`$1FCA`, byte-for-byte confirmed),
--                             a genuine "restart the whole game" command
--                             this project's interpreter model can't
--                             represent any other way. A caller's
--                             `onSoftReset` should trigger an actual
--                             game restart (reload the title screen /
--                             reset game state) -- the returned cursor
--                             after this call is a scan-classification
--                             convenience only, not a real continuation
--                             point.
--   ctx.isAnyButtonPressed() -- opcode `0xAD` -- optional predicate for
--                             the "wait for any button" gate -- defaults
--                             to `true` (never blocks) when unset, same
--                             "unwired gate defaults open" convention as
--                             `ctx.isActorReady` -- see
--                             `StandardScriptHandlers
--                             .waitForAnyButtonCommand`'s doc comment.
--   ctx.onWaitForAnyButtonIdleTick(elapsedFrames) -- optional observer
--                             for the same opcode `0xAD`'s idle-leaf
--                             calls (2 opaque leaves this project
--                             doesn't distinguish -- see that same
--                             handler's doc comment).
--   ctx.advanceWaypointStep(operand, stepIndex) -- opcode `0x8B` --
--                             optional evaluator for the untraced
--                             waypoint-table walk ($776F/$78EF/$08D4/
--                             $2889); returns `(done, nextStepIndex)`.
--                             Defaults to "always done immediately"
--                             (never blocks) when unset, same "unwired
--                             gate defaults open" convention as
--                             `ctx.isActorReady` -- see
--                             `StandardScriptHandlers
--                             .waypointStepCommand`'s doc comment.
--   ctx.isWipeMarkerConverged() -- opcodes `0xAC`/`0xAE` -- optional
--                             predicate for the phase-2 "have the 2
--                             $D3A0/$D3A3 markers met/crossed yet"
--                             check; defaults to "always converged
--                             immediately" (never blocks) when unset,
--                             same "unwired gate defaults open"
--                             convention as `ctx.isActorReady` -- see
--                             `StandardScriptHandlers
--                             .wipeCompletionGate`'s doc comment.
--   ctx.onWipeCompletionPhaseAC(phase)/onWipeCompletionPhaseAE(phase) --
--                             optional observers for the same opcodes'
--                             8-phase state machine (0-7) -- separate
--                             per opcode since phases 3/5's side effects
--                             genuinely differ between `0xAC` and `0xAE`
--                             -- see that same handler's doc comment.
--   ctx.hasSufficientBudget(amount) -- opcode `0xD1` -- optional
--                             predicate for the `$D7BE`/`$D7BF` 16-bit
--                             counter vs. the operand `amount`; defaults
--                             to "always sufficient" (no live counter
--                             WRAM modeled) -- see `StandardScriptHandlers
--                             .budgetFlagCommand`'s doc comment.
--   ctx.onBudgetSufficient(amount)/onBudgetExhausted(amount) -- the 2
--                             mutually-exclusive branches of the same
--                             opcode -- fire the SET/CLEAR of WRAM
--                             flag-array bit 6 respectively.
--   ctx.onRawByteLeaf(rawByte) -- opcodes `0x9C`/`0x9D` -- fires with
--                             the unmodified operand byte (no `+1`,
--                             unlike `ctx.onByteLeaf` for the
--                             `0xD5`/`0xD7`/`0xD9` family) -- see
--                             `StandardScriptHandlers
--                             .rawByteLeafCommand`'s doc comment. Both
--                             opcodes share this same callback (same
--                             leaf, `$2895`, neither opcode's own
--                             distinction threaded through yet -- same
--                             honest limit as `ctx.onSetActorSlotPosition`'s
--                             reuse across `0x49`/`0x19`).
--   ctx.onSceneInit(operandByte) -- opcode `0xC6` -- fires with the
--                             single operand byte on every dispatch --
--                             see `StandardScriptHandlers
--                             .sceneInitCommand`'s doc comment; the many
--                             WRAM writes this opcode performs are NOT
--                             individually modeled (HYPOTHESIS-scoped,
--                             same as `0xF6`'s sibling initializer).
--   ctx.getTwoBitFieldValue()/ctx.onTwoBitFieldWrite(value) -- opcode
--                             `0xC7` -- `getTwoBitFieldValue` is an
--                             optional value provider (defaults to 0,
--                             no live `$C0B0`/`$C0B1` wrapping counter
--                             modeled); `onTwoBitFieldWrite` fires with
--                             the already-masked (`AND 0x03`) 2-bit
--                             value on every dispatch -- see
--                             `StandardScriptHandlers
--                             .twoBitFieldCommand`'s doc comment.
--   ctx.onDynamicFlagBit(bitIndex, setBit) -- opcodes `0xDA`/`0xDB` --
--                             fires with the raw operand byte (the bit
--                             index) and whether this is the SET
--                             (`0xDA`, `setBit=true`) or CLEAR (`0xDB`,
--                             `setBit=false`) variant -- see
--                             `StandardScriptHandlers
--                             .dynamicFlagBitCommand`'s doc comment.
--   ctx.onBitmaskDispatch(bitIndex) -- opcode `0xC2` -- fires once per
--                             SET bit (0-4) of the operand byte, in
--                             ascending order -- see
--                             `StandardScriptHandlers
--                             .bitmaskDispatchCommand`'s doc comment.
--   ctx.onChainedOpaqueEffect() -- opcode `0xAF` -- fires with no
--                             parameters on every dispatch (4 chained
--                             opaque leaves, no single meaningful value
--                             to report) -- see `StandardScriptHandlers
--                             .chainedOpaqueEffectCommand`'s doc comment.
--   ctx.onSixBitFieldWrite(value) -- opcode `0xC5` -- fires with the
--                             already-masked (`AND 0x3F`) 6-bit value on
--                             every dispatch -- see `StandardScriptHandlers
--                             .sixBitFieldCommand`'s doc comment.
--   ctx.onActorSlotPositionWithReadinessParam(param, byte1, byte2) --
--                             opcode `0x79` -- gated the same way as
--                             `ctx.onActorActionWithReadinessParam`
--                             above (`ctx.isActorReady()`, halt without
--                             consuming the 2 position bytes) -- fires
--                             only on the ready path, with the computed
--                             slot `param` (always `offset+1`) and the
--                             raw position operand bytes -- see
--                             `StandardScriptHandlers
--                             .actorSlotPositionWithReadinessParam`'s
--                             doc comment.
--   ctx.onQueuedActionWithReadinessParam(param) -- opcode `0x68` -- the
--                             `$2859`-leaf sibling of
--                             `ctx.onActorActionWithReadinessParam`,
--                             same gate/param convention -- see
--                             `StandardScriptHandlers
--                             .queuedActionWithReadinessParam`'s doc
--                             comment.
--   ctx.getFlagBitClassifyValue()/ctx.onFlagBitSet()/onFlagBitClear()
--                             -- opcode `0xA9` -- optional value
--                             provider (defaults to 0, no live `$220A`
--                             leaf modeled) classified against 3 fixed
--                             constants; fires SET or CLEAR accordingly
--                             -- see `StandardScriptHandlers
--                             .threeWayFlagBitCommand`'s doc comment.
--   ctx.onChainTarget(newCursor, bankOffset) -- fires on every opcode
--                             `0x02` (CHAIN) dispatch, with the computed
--                             jump target -- see `StandardScriptHandlers
--                             .chain`'s doc comment for why: the ROM's
--                             cross-bank CHAIN targets aren't derivable
--                             from a formula with full confidence, only
--                             from empirically knowing the ambient bank
--                             for a specific scene (or, for the
--                             `bankOffset ~= 0` CANDIDATE case, a
--                             plausible-but-unconfirmed relative-bank
--                             hypothesis -- see that doc comment) --
--                             this lets a caller swap which
--                             `RomScriptStream` it feeds the next
--                             `:step()` call when that's needed.
--   ctx.onTypewriterCommand(v) -- opcode 0x03.
--   ctx.isQueueBlocked()    -- opcode 0x00's WRAM `$D874` bit-0 gate.
--                             RETRACTED (re-verified with a direct
--                             `$D874` watchpoint): the "actor-command
--                             queue" story above does NOT hold -- bit 0
--                             never changes across a reproduced
--                             ~200,000-step boss-defeat block, and the
--                             `$C5A0` table it depended on stays
--                             all-zero throughout. CLOSED: that block
--                             turned out to be a completely separate
--                             mechanism -- a periodic edge detector
--                             (`$1F35` selector `0x13` -> `$4BE0`,
--                             cached at `$C5AF`) that fires only once
--                             an entity's actor slot finishes
--                             despawning, which then directly
--                             overwrites the persistent script cursor
--                             (via `$24A7` -> `$31AD`) rather than
--                             going through this queue at all. Bit 0
--                             itself is still real and presumably
--                             gates something else -- just not this.
--                             `isQueueBlocked` still defaults to "never
--                             blocked" -- an honest gap, now for a
--                             different, still-unmodeled reason than
--                             originally documented. See
--                             `StandardScriptHandlers.queueGate`'s doc
--                             comment and events.md's entries for the
--                             complete live trace.
--   ctx.onQueueIdle()       -- opcode 0x00's "queue empty" side effect.
--   ctx.onFlagTest(byte) -- opcode 0x08's per-item leaf (see
--                             `StandardScriptHandlers
--                             .zeroTerminatedFlagList`'s doc comment)
--                             -- defaults to "always NZ", matching the
--                             one case this project has actually
--                             observed live.
--   ctx.onGatedByteLeaf(incrementedByte) -- opcodes 0xD4/0xD6/0xD8 --
--                             see `StandardScriptHandlers
--                             .gatedByteLeafCommand`'s doc comment.
--   ctx.isFadeActive() -- optional gate for the same 3 opcodes'
--                             `$D86F` bit-1 check; defaults to "never
--                             active" (matches every occurrence this
--                             project has observed live).
--   ctx.onFlagListExhausted(cursorAfterTerminator) -- opcode 0x08's
--                             "force next opcode to 1" leaf effect --
--                             REQUIRED in practice (asserts loudly if
--                             reached without it): this project
--                             decisively disproved its own earlier
--                             guess at this continuation, so a caller
--                             needs live-traced knowledge of where it
--                             lands (see `BossSequenceInterpreter` for
--                             the one scene this project has that
--                             knowledge for).
--   ctx.onPaletteFadeCompletionPhase(phase) -- opcode `0xF3` (replaces
--                             the old generic `ctx.isPeekGateClear`
--                             default) -- optional observer for the
--                             `$1ED7` selector-`0x10` 6-phase state
--                             machine that gates `0xF3`'s release --
--                             see `StandardScriptHandlers
--                             .paletteFadeCompletionGate`'s doc
--                             comment. `0xF3` also reuses
--                             `ctx.isTriggerEventGateClear` directly
--                             for its own 2 dual-gate phases (same
--                             `$C8E0`/`$CEE8` cells as
--                             `0xFC`/`0xFD`/`0xE8`-`0xEB`).
--   ctx.onPaletteFadeStep(outer, inner) -- opcodes `0xBC`/`0xBD`/`0xBE`
--                             (a genuine conditional-halt family, wired
--                             once the shared pacing leaf `$1142` was
--                             fully disassembled) -- optional observer,
--                             fires on every call (halting or
--                             releasing) with the current `$D499`/
--                             `$D49A` counter pair -- see
--                             `StandardScriptHandlers.paletteFadeCycle`'s
--                             doc comment for the full 6x11=66-tick
--                             pacing gate this models. All 3 opcodes
--                             share one private `{inner, outer}` state
--                             table (WRAM `$D499`/`$D49A` are genuinely
--                             shared across all 3 handlers).
function ScriptRuntime.new(opcodeEntries, ctx)
  ctx = ctx or {}
  local self = setmetatable({
    interp = ScriptInterpreter.new(opcodeEntries),
    queue = ctx.queue or ScriptContinuationQueue.new(),
    ctx = ctx,
    stepCount = 0,
    opcodeCounts = {}, -- per-opcode dispatch histogram, keyed by opcode byte
    finished = false, -- true once a fetch runs off the stream's own end
    stopped = false, -- true once a genuinely undecoded opcode halted this run for good
    stopError = nil,
    -- Opcode-pinning state (see ScriptInterpreter:step's "PINNING" doc
    -- comment for the full evidence/mechanism this models). `nil` =
    -- normal dispatch (read the next opcode from the stream, the
    -- overwhelming majority case); an opcode byte = "keep
    -- re-dispatching this same opcode's handler regardless of what raw
    -- byte now sits at cursor" -- set/cleared automatically from each
    -- `interp:step`'s own `pin` return value, never touched directly
    -- by callers.
    pinnedOpcode = nil,
  }, ScriptRuntime)
  self:registerStandardHandlers()
  return self
end

--- Registers every currently-decoded handler this project has against
-- `self.interp`, wired to `self.ctx`'s callbacks -- see
-- `ScriptRuntime.new`'s doc comment for the full field list. Kept as
-- its own method (not inlined into `.new`) so a caller could, in
-- principle, build a runtime with a different handler set (e.g. a
-- future test double) without duplicating this whole registration list.
function ScriptRuntime:registerStandardHandlers()
  local ctx = self.ctx
  local interp = self.interp
  local isDone = ctx.isTextboxDone or function() return true end
  -- Per-opcode gate for the actor-flag/state and queued-action families
  -- (see StandardScriptHandlers.actorAction/.queuedAction's doc
  -- comments): the real condition is a live WRAM actor-record check
  -- this project has no runtime model of yet -- defaults to "always
  -- ready" (never blocks), the same explicitly-flagged simplification
  -- those handlers already describe as honest, not a claim about real
  -- timing.
  local isActorReady = ctx.isActorReady or function() return true end
  -- Gate for `0xAD`'s "wait for any button" opcode (see
  -- StandardScriptHandlers.waitForAnyButtonCommand's doc comment) --
  -- defaults to "always pressed" (never blocks) when the caller hasn't
  -- wired real Input.lua awareness yet, same "unwired gate defaults
  -- open" convention as `isActorReady` above.
  local isAnyButtonPressed = ctx.isAnyButtonPressed or function() return true end
  -- Evaluator for `0x8B`'s "waypoint step" opcode (see
  -- StandardScriptHandlers.waypointStepCommand's doc comment) --
  -- defaults to "always done immediately" (never blocks, step index
  -- irrelevant) when the caller hasn't wired the untraced waypoint-
  -- table walk, same "unwired gate defaults open" convention as
  -- `isActorReady`/`isAnyButtonPressed` above.
  local advanceWaypointStep = ctx.advanceWaypointStep or function() return true, 0 end
  -- Evaluator for `0xAC`/`0xAE`'s phase-2 "2 markers converged" check
  -- (see StandardScriptHandlers.wipeCompletionGate's doc comment) --
  -- defaults to "always converged immediately" (never blocks) when the
  -- caller hasn't wired the untraced $D3A0/$D3A3 marker WRAM state,
  -- same "unwired gate defaults open" convention as
  -- `isActorReady`/`isAnyButtonPressed` above.
  local isWipeMarkerConverged = ctx.isWipeMarkerConverged or function() return true end

  -- `0x80` (cracking the whole-corpus scan's longest-standing
  -- known-hard opcode): `$02AB` (the leaf this opcode's group depends
  -- on) turned out to be a plain read of the player's facing-direction
  -- byte (`$C240`'s low nibble -- see `EntityStructLayout.lua`'s
  -- `PLAYER_FACING_BIT` doc comment for the complete live-trace
  -- evidence), not an unmodelable leaf. Registered here explicitly
  -- (still excluded from the generic sweep below, but for a different
  -- reason now -- it needs this specific dynamic-group wiring, not a
  -- blanket skip) using `.actorAction`'s existing dynamic-`group`-
  -- as-function support: `ctx.getPlayerFacing()` (optional, defaults
  -- to `"up"`, matching this project's already-independently-verified
  -- `Player.DEFAULT_FACING`) is looked up in the
  -- `EntityStructLayout.PLAYER_FACING_BIT` table and combined with the
  -- fixed `+0x90` offset the ROM's code applies.
  -- Shared by 0x80 and 0x81 below (0x81 needs the same safe facing
  -- lookup, just combined differently afterward): resolves
  -- `ctx.getPlayerFacing()` to a facing string, coercing anything
  -- missing/unrecognized to the documented `"up"` default (matching
  -- `Player.DEFAULT_FACING`) rather than asserting. Guards against a
  -- generic caller (e.g. this project's whole-corpus scan tool)
  -- supplying a stub `ctx.getPlayerFacing` that returns a non-facing
  -- placeholder (its generic `__index` stub returns `true` for every
  -- unset callback, regardless of that callback's real return type --
  -- the same crash class already caught and fixed twice earlier for
  -- `twoBitFieldCommand`/`threeWayFlagBitCommand`).
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

  -- `0x81` (continuation of the same $02AB investigation): same leaf
  -- (`$02AB`, via `resolvePlayerFacing`
  -- above) but combined through `$29E4`'s "opposite facing" bit trick
  -- before the fixed `OR 0xB0` -- see `ScriptOpcodeTable
  -- .ACTOR_ACTION_HANDLER_ADDRESS_81`'s doc comment for the full
  -- disassembly and truth table. `EntityStructLayout.OPPOSITE_FACING`
  -- is this project's Lua-side equivalent of `$29E4` (a plain lookup,
  -- exactly as correct as the real bit trick since every input is
  -- one-hot). Falls back through the same `"up"`-default path as 0x80
  -- when facing is missing/unrecognized -- `OPPOSITE_FACING.up =
  -- "down"`, so the honest default resolves to `PLAYER_FACING_BIT
  -- .down | 0xB0` here, deliberately different from 0x80's default
  -- result (a correct consequence of the two opcodes' different
  -- formulas, not an inconsistency).
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
  -- `0x09`/`0x0A`: structurally identical to `0x08` just above (same
  -- "REQUIRED, no guessing" exhausted contract) -- but each targets a
  -- different WRAM array, so each gets its own distinctly-named ctx
  -- callback triple rather than sharing `0x08`'s -- see
  -- `StandardScriptHandlers.timerListSearch`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_09,
    StandardScriptHandlers.timerListSearch(ctx.onAdjustTimers09, ctx.onTimerListTest09, ctx.onTimerListExhausted09))
  interp:registerHandler(ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_0A,
    StandardScriptHandlers.timerListSearch(ctx.onAdjustTimers0A, ctx.onTimerListTest0A, ctx.onTimerListExhausted0A))
  -- `0x0B`/`0x0C`: both opcodes read the same 2 WRAM cells (`$D871`/
  -- `$D873` bit 7), so `ctx.runListMatchByte`/`ctx.isRunListGateSet`
  -- are shared -- only the gate polarity (`searchWhenGateSet`) and
  -- each opcode's own `onExhausted` differ -- see
  -- `StandardScriptHandlers.runListSearch`'s doc comment. Both are
  -- required ctx fields (no safe default for a byte comparison) --
  -- only registered if both are supplied.
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
  -- `0xB8`/`0xB9`: a different WRAM cell ($C3F1) than `ctx.flags`'s
  -- $D874, so a separate `ctx.wramBitFlags` table -- same "only
  -- register if the caller actually wants to track this cell"
  -- convention.
  if ctx.wramBitFlags then
    interp:registerHandler(ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B8,
      StandardScriptHandlers.wramBitCommand(ctx.wramBitFlags, 0, true, ctx.onWramBitCommandLeafB8))
    interp:registerHandler(ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9,
      StandardScriptHandlers.wramBitCommand(ctx.wramBitFlags, 0, false, ctx.onWramBitCommandLeafB9))
  end
  -- `0xA3`/`0xA5`/`0xA6`: a third different WRAM cell ($C4D4) -- yet
  -- another separate `{byte=int}` proxy, same "only register if the
  -- caller actually wants to track this cell" convention as
  -- `ctx.flags`/`ctx.wramBitFlags` above.
  if ctx.actorStateFlags then
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A3,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 4))
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A5,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 5))
    interp:registerHandler(ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A6,
      StandardScriptHandlers.fixedWramBitSetSkipCommand(ctx.actorStateFlags, 6))
  end
  -- Per the disassembly of $333D (see StandardScriptHandlers.tick's
  -- doc comment for the full evidence): `0x04` is a per-byte
  -- text/control-code classifier, not a simple tick --
  -- `ctx.onControlCode(byte)` is this project's hook for the 0x10-0x1F
  -- control-code family (see that handler's doc comment for what's
  -- modeled and what's an honestly-named gap).
  interp:registerHandler(ScriptOpcodeTable.TICK_HANDLER_ADDRESS,
    StandardScriptHandlers.tick(ctx.onTick, ctx.onControlCode))
  interp:registerHandler(ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS,
    StandardScriptHandlers.startTextboxWait(ctx.onTick, isDone))
  interp:registerHandler(ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS,
    StandardScriptHandlers.textboxWait(ctx.onTick, isDone))
  interp:registerHandler(ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS,
    StandardScriptHandlers.typewriterCommand(ctx.onTypewriterCommand, self.queue))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0xFC`/`0xFD` -- REAL identity found 2026-08-20 (mining the external
  -- FFA-Disassembly's own `src/data/npc/spawn.asm` for its encounter/
  -- spawn code specifically, not just boss stats): these are this ROM's
  -- real `sSET_NPC_TYPES <row>` / `sSPAWN_NPC <col>` opcodes, staging a
  -- row into (then spawning a column from) the real `NpcSpawnTable`
  -- (CPU `$7142`, bank 3, byte-identical to the US cartridge -- see that
  -- module's own doc comment). Live-confirmed end to end: a 2-byte ROM
  -- patch redirecting an already-firing real `0xFC`/`0xFD` pair from
  -- `NPC_WILLY` to `NPC_GOBLIN` produced a second, visible, distinct
  -- creature on screen with real contact damage (see docs/reverse-
  -- engineering/events.md's 2026-08-20 "SOLVED" entry). Named
  -- `ctx.onSetNpcTypes`/`ctx.onSpawnNpc` instead of reusing the generic
  -- `ctx.onTriggerEvent` name both opcodes were previously (and, for a
  -- real live period, INCORRECTLY -- see the generic sweep's own
  -- `_FC$`/`_FD$` exclusion below) registered under -- sharing one
  -- ambiguous name across a 0-arg family and this 2-arg family is
  -- exactly what let that bug hide from every existing test.
  --
  -- Both handlers share the same WRAM latch (`$D499`) -- they're
  -- mutually-exclusive alternatives of one state machine, not
  -- independent state, so this project's Lua port shares one
  -- closure-local latch between their two registrations (matching the
  -- ROM's single shared byte) rather than exposing it via `ctx` -- no
  -- caller outside this runtime instance has a legitimate reason to
  -- inspect or override it. `ctx.isTriggerEventGateClear` (optional,
  -- defaults to "always clear" -- see `StandardScriptHandlers
  -- .oneShotTriggerGate`'s doc comment for why that matches the one
  -- case this project has actually observed) models the `$C8E0`/
  -- `$CEE8` dual gate both opcodes also share.
  do
    local triggerLatch = { resumeCursor = false }
    local function getLatch() return triggerLatch.resumeCursor end
    local function setLatch(v) triggerLatch.resumeCursor = v end
    local function callWithRow(row) if ctx.onSetNpcTypes then ctx.onSetNpcTypes(row) end end
    local function callWithCol(col) if ctx.onSpawnNpc then ctx.onSpawnNpc(col) end end
    interp:registerHandler(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC,
      StandardScriptHandlers.oneShotTriggerGate(5, getLatch, setLatch,
        ctx.isTriggerEventGateClear, callWithRow))
    interp:registerHandler(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FD,
      StandardScriptHandlers.oneShotTriggerGate(4, getLatch, setLatch,
        ctx.isTriggerEventGateClear, callWithCol))
  end
  -- `0xE8`/`0xE9` (see `StandardScriptHandlers.dualGateLeafCommand`'s
  -- doc comment): same `$C8E0`/`$CEE8` dual gate as `0xFC`/`0xFD` just
  -- above (reuses the same `ctx.isTriggerEventGateClear`, the WRAM
  -- cells are identical), but no operand byte and no one-shot latch --
  -- each fires its own distinct VRAM-tile-pattern-update leaf every
  -- time it dispatches, not once per activation.
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E8,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafE8))
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E9,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafE9))
  -- `0xEA`/`0xEB`: completes the 4-direction family alongside
  -- `0xE8`/`0xE9` (North/South) above -- East/West, same shared gate,
  -- same factory, no new Lua code.
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EA,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafEA))
  interp:registerHandler(ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EB,
    StandardScriptHandlers.dualGateLeafCommand(ctx.isTriggerEventGateClear, ctx.onDualGateLeafEB))
  -- `0xFB`/`0xBF`: both "periodic cosmetic WRAM-effect" leaves with a
  -- fully self-contained private phase counter (WRAM `$D499` is
  -- shared/global in the ROM, but nothing else in this project's model
  -- reads it back) -- unconditional, no `ctx` gating needed, since
  -- `onUpdate`/`onDim`/`onBright` are all genuinely optional observers,
  -- not required state -- see `StandardScriptHandlers
  -- .periodicWramEffect`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB,
    StandardScriptHandlers.waveOffsetEffect(ctx.onWaveOffsetUpdate))
  interp:registerHandler(ScriptOpcodeTable.COLOR_PULSE_EFFECT_HANDLER_ADDRESS_BF,
    StandardScriptHandlers.colorPulseEffect(ctx.onColorPulseDim, ctx.onColorPulseBright))
  -- `0xBC`/`0xBD`/`0xBE` (see `ScriptOpcodeTable.lua`'s
  -- `PALETTE_FADE_HANDLER_ADDRESS_BC/BD/BE` doc comment for the full
  -- disassembly of the shared `$1142` pacing leaf this models). Unlike
  -- `0xFB`/`0xBF` just above, this family genuinely halts (see
  -- `StandardScriptHandlers.paletteFadeCycle`'s doc comment) -- all 3
  -- opcodes share one private `sharedPaletteFadeState` table (the WRAM
  -- `$D499`/`$D49A` cells they all read/write are genuinely shared
  -- across these 3 specific handlers, unlike `0xFB`/`0xBF`'s unrelated,
  -- per-handler-private use of the same cell number).
  local sharedPaletteFadeState = {}
  interp:registerHandler(ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BC,
    StandardScriptHandlers.paletteFadeCycle(sharedPaletteFadeState, ctx.onPaletteFadeStep))
  interp:registerHandler(ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BD,
    StandardScriptHandlers.paletteFadeCycle(sharedPaletteFadeState, ctx.onPaletteFadeStep))
  interp:registerHandler(ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BE,
    StandardScriptHandlers.paletteFadeCycle(sharedPaletteFadeState, ctx.onPaletteFadeStep))
  -- `0x88`/`0x89` (both live-confirmed boss-defeat script opcodes):
  -- fixed per-opcode constant, unconditional, `onWrite` is a genuinely
  -- optional observer -- see `StandardScriptHandlers
  -- .playerEntityTypeWrite`'s doc comment. Both share one `ctx`
  -- callback (`ctx.onPlayerEntityTypeWrite`) since the fixed value
  -- itself already tells a caller which opcode fired.
  interp:registerHandler(ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_88,
    StandardScriptHandlers.playerEntityTypeWrite(2, ctx.onPlayerEntityTypeWrite))
  interp:registerHandler(ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_89,
    StandardScriptHandlers.playerEntityTypeWrite(1, ctx.onPlayerEntityTypeWrite))
  -- `0x8F`: conditional halt on the same `$C5A0` actor-command table
  -- an earlier `$4B70` finding documents (its own read, independent of
  -- opcode `0x00` -- a later re-trace found opcode `0x00`'s bit-0 gate
  -- does NOT actually read `$C5A0` the way an earlier comment implied;
  -- `0x8F`'s `$C5A0` read stands on its own, unaffected by that
  -- retraction) -- unconditional registration since
  -- `ctx.isActorCommandQueueEmpty` is optional (defaults to "always
  -- empty," same honest gap as `ctx.isActorReady`/`ctx.isQueueBlocked`
  -- -- no live WRAM actor-command simulation exists in this project).
  interp:registerHandler(ScriptOpcodeTable.ACTOR_COMMAND_QUEUE_EMPTY_GATE_HANDLER_ADDRESS_8F,
    StandardScriptHandlers.actorCommandQueueEmptyGate(ctx.isActorCommandQueueEmpty))
  -- `0x90`/`0x91`/`0x94`-`0x99`: the `$1606` cluster -- explicit
  -- registration (not the generic `ACTOR_ACTION_HANDLER_ADDRESS_`/
  -- `QUEUED_ACTION_HANDLER_ADDRESS_` loop below, deliberately excluded
  -- by this constant family's different name prefix, since these have
  -- a different not-ready behavior -- see `StandardScriptHandlers
  -- .actorActionOrSkip`'s doc comment). Reuses the same `isActorReady`
  -- local (the `$28C2` gate is identical to the sibling family's).
  -- Unlike the generic loop, explicit registration lets each opcode's
  -- own group value reach `ctx.onActorActionOrSkip` for real -- not
  -- lost to `nil` the way the generic family's "HONEST LIMIT" note
  -- describes.
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
  -- `0xEF` ($0E73's neighborhood): a simple "store 2 operand bytes
  -- into WRAM $C344/$C345" primitive. `0xEC`/`0xED`/`0xEE` (the same
  -- neighborhood's siblings) are deliberately NOT registered -- see
  -- `ScriptOpcodeTable.lua`'s doc comment: a third confirmed member of
  -- the `0x80`/`$15A4` known-hard family (`$02AB`).
  interp:registerHandler(ScriptOpcodeTable.TILE_CURSOR_SET_HANDLER_ADDRESS_EF,
    StandardScriptHandlers.tileCursorSet(ctx.onTileCursorSet))
  -- `0x7A`/`0x7B`: a "readiness-as-parameter" actor-action family,
  -- unconditional (no not-ready path at all) -- see
  -- `StandardScriptHandlers.actorActionWithReadinessParam`'s doc
  -- comment for the full disassembly. Explicit registration (not the
  -- generic `^ACTOR_ACTION_HANDLER_ADDRESS_` loop -- this constant
  -- family deliberately uses a different name so it isn't picked up
  -- there) so each opcode's fixed group/offset reach `ctx` intact.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x5A`/`0x5B`: 2 more `actorActionWithReadinessParam` members, offset `0x04`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x6A`/`0x6B`: 2 more `actorActionWithReadinessParam` members, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6B,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0F, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x24`: 1 more `actorActionWithReadinessParam` member, offset `0x01`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_24,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x01, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x68`: a queued-action, readiness-as-parameter command.
  interp:registerHandler(ScriptOpcodeTable.QUEUED_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_68,
    StandardScriptHandlers.queuedActionWithReadinessParam(0x05, isActorReady, ctx.onQueuedActionWithReadinessParam))
  -- `0x74`: 1 more `actorActionWithReadinessParam` member, offset `0x06`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_74,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x54`: 1 more `actorActionWithReadinessParam` member, offset `0x04`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_54,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1E, 0x04, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0xA9`: a "3-way classified flag-bit SET/CLEAR" command -- see
  -- `StandardScriptHandlers.threeWayFlagBitCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.THREE_WAY_FLAG_BIT_COMMAND_HANDLER_ADDRESS_A9,
    StandardScriptHandlers.threeWayFlagBitCommand(ctx.getFlagBitClassifyValue, ctx.onFlagBitSet, ctx.onFlagBitClear))
  -- `0x67`: 1 more `actorActionWithReadinessParam` member, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_67,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1D, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x4A`/`0x66`: 2 more `actorActionWithReadinessParam` members.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_4A,
    StandardScriptHandlers.actorActionWithReadinessParam(0x0E, 0x03, isActorReady, ctx.onActorActionWithReadinessParam))
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_66,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1C, 0x05, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0x76`: 1 more `actorActionWithReadinessParam` member, offset `0x06`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_76,
    StandardScriptHandlers.actorActionWithReadinessParam(0x1C, 0x06, isActorReady, ctx.onActorActionWithReadinessParam))
  -- `0xCC`: a zero-operand-byte "re-mirror my own opcode byte"
  -- primitive -- see `StandardScriptHandlers.opcodeByteMirror`'s doc
  -- comment.
  interp:registerHandler(ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC,
    StandardScriptHandlers.opcodeByteMirror(ctx.onOpcodeByteMirror))
  -- `0xC8`: a decisive "soft reset the whole game" command -- see
  -- `StandardScriptHandlers.softReset`'s doc comment. `ctx
  -- .onSoftReset` is REQUIRED (no honest default exists for restarting
  -- the game) -- this handler registers unconditionally (most scripts
  -- never reach `0xC8`, so a `ScriptRuntime` shouldn't be forced to
  -- supply this just to exist), but fails loudly, at dispatch time,
  -- the first time `0xC8` actually runs without a `ctx.onSoftReset`
  -- provided -- see `.softReset`'s doc comment for why the assertion
  -- is deferred to dispatch time instead of construction time.
  interp:registerHandler(ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8,
    StandardScriptHandlers.softReset(ctx.onSoftReset))
  -- `0xD1`: a "budget countdown, SET/CLEAR flag bit 6" command -- see
  -- `StandardScriptHandlers.budgetFlagCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.BUDGET_FLAG_COMMAND_HANDLER_ADDRESS_D1,
    StandardScriptHandlers.budgetFlagCommand(ctx.hasSufficientBudget, ctx.onBudgetSufficient, ctx.onBudgetExhausted))
  -- `0x9C`/`0x9D`: a "raw single-byte leaf command" family, same leaf
  -- (`$2895`) -- see `StandardScriptHandlers.rawByteLeafCommand`'s doc
  -- comment.
  interp:registerHandler(ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9C,
    StandardScriptHandlers.rawByteLeafCommand(ctx.onRawByteLeaf))
  interp:registerHandler(ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9D,
    StandardScriptHandlers.rawByteLeafCommand(ctx.onRawByteLeaf))
  -- `0xC6`: a "scene/textbox init" command, the same 5 WRAM cells as
  -- opcode `0xF6`'s already-hypothesized initializer -- see
  -- `StandardScriptHandlers.sceneInitCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.SCENE_INIT_COMMAND_HANDLER_ADDRESS_C6,
    StandardScriptHandlers.sceneInitCommand(ctx.onSceneInit))
  -- `0xC7`: a "2-bit WRAM field write" command -- see
  -- `StandardScriptHandlers.twoBitFieldCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.TWO_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C7,
    StandardScriptHandlers.twoBitFieldCommand(ctx.getTwoBitFieldValue, ctx.onTwoBitFieldWrite))
  -- `0xDA`/`0xDB`: a dynamic-index flag-bit SET/CLEAR family -- see
  -- `StandardScriptHandlers.dynamicFlagBitCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DA,
    StandardScriptHandlers.dynamicFlagBitCommand(true, ctx.onDynamicFlagBit))
  interp:registerHandler(ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DB,
    StandardScriptHandlers.dynamicFlagBitCommand(false, ctx.onDynamicFlagBit))
  -- `0xC2`: a "bitmask dispatch" command -- see `StandardScriptHandlers
  -- .bitmaskDispatchCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.BITMASK_DISPATCH_COMMAND_HANDLER_ADDRESS_C2,
    StandardScriptHandlers.bitmaskDispatchCommand(ctx.onBitmaskDispatch))
  -- `0xAF`: a "chained opaque effect" command, 4 sequential untraced
  -- leaves -- see `StandardScriptHandlers.chainedOpaqueEffectCommand`'s
  -- doc comment.
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AF,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  -- `0xB7`: `$1ED7` selector `0x17` trampoline -- same shape as `0xAF`,
  -- reuses the same factory and callback (this project's established
  -- "reuse the same callback when neither opcode's distinction is
  -- threaded through yet" convention).
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_B7,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  -- `0xA1`/`0xA2`/`0xB6`/`0xAA`/`0xAB`: same shape as `0xAF`/`0xB7`
  -- above (zero operand bytes, unconditional) -- see
  -- `ScriptOpcodeTable.lua`'s doc comments at each address for the
  -- complete disassembly. Same established convention: reuse the same
  -- factory and callback since neither opcode's distinction is
  -- threaded through yet.
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_A1,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_A2,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_B6,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AA,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  interp:registerHandler(ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AB,
    StandardScriptHandlers.chainedOpaqueEffectCommand(ctx.onChainedOpaqueEffect))
  -- `0xAD`: a "wait for any button" gate -- see `StandardScriptHandlers
  -- .waitForAnyButtonCommand`'s doc comment for the complete
  -- disassembly.
  interp:registerHandler(ScriptOpcodeTable.WAIT_FOR_ANY_BUTTON_COMMAND_HANDLER_ADDRESS_AD,
    StandardScriptHandlers.waitForAnyButtonCommand(isAnyButtonPressed, ctx.onWaitForAnyButtonIdleTick))
  -- `0x8B`: a "play back a pre-baked waypoint/step sequence" gate --
  -- see `StandardScriptHandlers.waypointStepCommand`'s doc comment for
  -- the complete disassembly.
  interp:registerHandler(ScriptOpcodeTable.WAYPOINT_STEP_COMMAND_HANDLER_ADDRESS_8B,
    StandardScriptHandlers.waypointStepCommand(advanceWaypointStep))
  -- `0xC5`: a "6-bit WRAM field write" command -- see
  -- `StandardScriptHandlers.sixBitFieldCommand`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.SIX_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C5,
    StandardScriptHandlers.sixBitFieldCommand(ctx.onSixBitFieldWrite))
  -- `0x79`: an actor-slot-position command, readiness used as the slot
  -- parameter -- see `StandardScriptHandlers
  -- .actorSlotPositionWithReadinessParam`'s doc comment.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_79,
    StandardScriptHandlers.actorSlotPositionWithReadinessParam(0x06, isActorReady, ctx.onActorSlotPositionWithReadinessParam))
  -- `0x69`: 1 more `actorSlotPositionWithReadinessParam` member, offset `0x05`.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_69,
    StandardScriptHandlers.actorSlotPositionWithReadinessParam(0x05, isActorReady, ctx.onActorSlotPositionWithReadinessParam))
  -- `0x19` ($12AE): the same `$123E` mechanism as `0x49` above (see
  -- ScriptOpcodeTable's doc comment for the disassembly proving it),
  -- just reached via a different trampoline base -- that base only
  -- changes the derived actor-slot index, which this project doesn't
  -- thread through to `ctx` yet (see `0x49`'s "HONEST LIMIT" note
  -- above), so it's honest to reuse the same `ctx.onSetActorSlotPosition`
  -- callback here rather than inventing a second one this codebase
  -- can't yet distinguish by actor slot.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_19,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x59` ($147E): the same `$123E` mechanism yet again -- see
  -- 0x49/0x19's doc comments above.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_59,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x39` ($1396): the same `$123E` mechanism yet again -- see
  -- 0x49/0x19/0x59's doc comments above.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_39,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0x29` ($1322): the same `$123E` mechanism yet again -- see
  -- 0x49/0x19/0x59/0x39's doc comments above -- found live against the
  -- boss-defeat sequence itself (past the newly-wired 0x08), not the
  -- earlier whole-corpus census.
  interp:registerHandler(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_29,
    StandardScriptHandlers.actorSlotPosition(isActorReady, ctx.onSetActorSlotPosition))
  -- `0xD4`/`0xD6`/`0xD8`: all 3 share the same `$D86F` bit-1 gate --
  -- see `StandardScriptHandlers.gatedByteLeafCommand`'s doc comment
  -- for the honest scope of what's not modeled (the bit-SET path).
  -- `ctx.isFadeActive` defaults to "never active", matching every
  -- occurrence this project has actually observed live.
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D4,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D6,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  interp:registerHandler(ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D8,
    StandardScriptHandlers.gatedByteLeafCommand(ctx.onGatedByteLeaf, ctx.isFadeActive))
  -- `0xD5`/`0xD7`/`0xD9`: the ungated sibling family -- see
  -- `StandardScriptHandlers.byteLeafCommand`'s doc comment.
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
  -- `0xCB` ($392C): the same 2-operand-byte "read into DE, call a
  -- leaf, always continue" shape as `TWO_BYTE_COMMAND_HANDLER_ADDRESS`
  -- above, but a genuinely different target ($3937, untraced) -- gets
  -- its own `ctx` callback rather than sharing `ctx.onTwoByteCommand`,
  -- since conflating two different leaf routines under one callback
  -- would misrepresent them as the same action.
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandCB))
  -- `0xC9`/`0xCA`: same family as `0xCB` above, own dedicated callbacks
  -- (different fixed `BC` each -- see ScriptOpcodeTable's doc comment).
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_C9,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandC9))
  interp:registerHandler(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CA,
    StandardScriptHandlers.twoByteCommand(ctx.onTwoByteCommandCA))
  -- `0xF3` (replacing the old generic `ctx.isPeekGateClear` default
  -- with the fully-disassembled release condition -- `$1ED7` selector
  -- `0x10`'s 6-phase `$D499` state machine, see
  -- `ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3`'s doc
  -- comment). Reuses `ctx.isTriggerEventGateClear` directly for the 2
  -- dual-gate phases (the same `$C8E0`/`$CEE8` cells `0xFC`/`0xFD`/
  -- `0xE8`-`0xEB` already model) -- a fresh private `{phase=0}` state
  -- table per registration (this mechanism is genuinely per-occurrence,
  -- unlike the palette-fade family's shared-across-occurrences state).
  -- `extraBytesOnRelease=2`: a live mGBA execution-address trace found
  -- 0xF3's total instruction length is 5 bytes (2 peeked + 2 more,
  -- bytes `14 00` right after the peek, both silently consumed by
  -- `$1ED7` selector-0x10's internal work, never re-entering the
  -- top-level dispatch) -- see `.peekTwoByteGate`'s doc comment for the
  -- full byte-exact evidence. This is what resolves the long-standing
  -- `0x4798` desync.
  interp:registerHandler(ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3,
    StandardScriptHandlers.peekTwoByteGate(ctx.onPeekTwoByteGate,
      StandardScriptHandlers.paletteFadeCompletionGate({}, ctx.isTriggerEventGateClear, ctx.onPaletteFadeCompletionPhase),
      2))
  -- `0xF4`: selector `0x0F` (not `0x10`) remains untraced -- keeps the
  -- old, honestly-unwired `ctx.isPeekGateClear` generic default (see
  -- `StandardScriptHandlers.peekTwoByteGate`'s doc comment) rather than
  -- guessing it shares `0xF3`'s sequence.
  interp:registerHandler(ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F4,
    StandardScriptHandlers.peekTwoByteGate(ctx.onPeekTwoByteGate, ctx.isPeekGateClear))
  -- `0xAC`/`0xAE`: 8-phase `$D499` state machines -- see
  -- `StandardScriptHandlers.wipeCompletionGate`'s doc comment for the
  -- complete disassembly. Each gets its own private `{}` state table
  -- (per-occurrence state, same precedent as `0xF3`'s
  -- `paletteFadeCompletionGate` registration above) and its own
  -- `onPhase` observer, but share `ctx.isTriggerEventGateClear` for
  -- their dual-gate phases (the same `$C8E0`/`$CEE8` cells) and
  -- `isWipeMarkerConverged` for their phase-2 marker check
  -- (structurally identical between `0xAC`/`0xAE`; the one difference,
  -- phase 3/5's opaque leaf work, doesn't affect this gate's shape).
  interp:registerHandler(ScriptOpcodeTable.WIPE_COMPLETION_COMMAND_HANDLER_ADDRESS_AC,
    StandardScriptHandlers.completionPredicateCommand(
      StandardScriptHandlers.wipeCompletionGate({}, ctx.isTriggerEventGateClear, isWipeMarkerConverged, ctx.onWipeCompletionPhaseAC)))
  interp:registerHandler(ScriptOpcodeTable.WIPE_COMPLETION_COMMAND_HANDLER_ADDRESS_AE,
    StandardScriptHandlers.completionPredicateCommand(
      StandardScriptHandlers.wipeCompletionGate({}, ctx.isTriggerEventGateClear, isWipeMarkerConverged, ctx.onWipeCompletionPhaseAE)))

  -- Found via a live shadow-run against the actual boss-defeat script
  -- bytes: the first opcode this project's hand-picked registration
  -- list above didn't cover turned out to be `0x48`, an already-named
  -- `QUEUED_ACTION_HANDLER_ADDRESS_48` constant -- i.e. this runtime
  -- was stopping on opcodes this project has already decoded the
  -- dispatch shape for, just because nothing had registered them here
  -- yet, not because they're genuinely undecoded. Opcode families
  -- sharing one handler shape (actor-action, queued-action,
  -- trigger-event, sound-param, word-command) are now registered
  -- generically, by scanning every matching
  -- `ScriptOpcodeTable.*_HANDLER_ADDRESS*` constant -- picks up every
  -- opcode this project has currently decoded into that family (and
  -- any future addition) without a hand-maintained, easily-stale list
  -- here.
  --
  -- HONEST LIMIT: the specific "group" value each actor-action
  -- opcode's ROM code bakes in (see ScriptOpcodeTable.lua's
  -- per-constant `-- group 0xNN` comments) is only recorded there as a
  -- Lua comment, not machine-readable data -- this generic pass has no
  -- way to look it up per-address, so `onActorAction`/`onQueuedAction`
  -- fire with `group = nil` here (an honest "unknown" marker, not a
  -- fabricated placeholder value) rather than reproducing a specific
  -- opcode's group. A caller that needs the per-opcode group should
  -- register that one address directly (see `:registerHandler`,
  -- exposed via `self.interp`) with a specific
  -- `StandardScriptHandlers.actorAction(<group>, ...)` call instead.
  for key, addr in pairs(ScriptOpcodeTable) do
    if type(addr) == "number" then
      if key:match("^ACTOR_ACTION_HANDLER_ADDRESS_80$") then
        -- Already explicitly registered above with its live, dynamic
        -- group (the player's facing direction, see that
        -- registration's doc comment) -- excluded here only so this
        -- generic sweep doesn't overwrite that more precise
        -- registration with a group-less generic one, same pattern as
        -- the `_7B$`/`WORD_COMMAND_HANDLER_ADDRESS_EF$` exclusions
        -- below.
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_81$") then
        -- Already explicitly registered above with its live, dynamic
        -- group (opposite-facing | 0xB0, see that registration's doc
        -- comment) -- excluded here for the same reason as the `_80$`
        -- exclusion right above: so this generic sweep doesn't
        -- overwrite it with a group-less generic registration.
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_7B$") then
        -- Self-caught bug: opcode `0x7B` was originally discovered
        -- twice, in two separate sessions -- first as a plain Family-A
        -- member (this old constant, `$157C`, registered generically
        -- with a fixed, discarded group and no real `param`), then
        -- again as part of the `actorActionWithReadinessParam` family
        -- (`ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7B`,
        -- same address, exposing the computed `param` -- see that
        -- function's doc comment). This loop used to also match the
        -- old constant and silently overwrite the newer, more precise
        -- explicit registration (which runs earlier in this same
        -- function) -- live-verified: before this fix, dispatching
        -- opcode `0x7B` fired `ctx.onActorAction` (the generic,
        -- information-losing callback), never `ctx
        -- .onActorActionWithReadinessParam` (the correct, already-
        -- wired one). Excluded here (same pattern as the `_80$`/
        -- `WORD_COMMAND_HANDLER_ADDRESS_EF$` exclusions above) so the
        -- explicit, more precise registration wins. The old constant
        -- is kept, not deleted (existing tests assert it against the
        -- opcode-table bytes).
      elseif key:match("^ACTOR_ACTION_HANDLER_ADDRESS_") then
        interp:registerHandler(addr, StandardScriptHandlers.actorAction(nil, isActorReady, ctx.onActorAction))
      elseif key:match("^QUEUED_ACTION_HANDLER_ADDRESS_") then
        interp:registerHandler(addr, StandardScriptHandlers.queuedAction(isActorReady, ctx.onQueuedAction))
      elseif key:match("^TRIGGER_EVENT_HANDLER_ADDRESS_FC$") or key:match("^TRIGGER_EVENT_HANDLER_ADDRESS_FD$") then
        -- Same precedent bug as the `_80$`/`_81$`/`_7B$`/
        -- `WORD_COMMAND_HANDLER_ADDRESS_EF$` exclusions above, found live
        -- 2026-08-20 (a whole-corpus shadow-run kept returning suspicious,
        -- uniformly-`nil` operands for every real `0xFC`/`0xFD` hit): these
        -- two constants also match the generic `^TRIGGER_EVENT_HANDLER_
        -- ADDRESS` pattern below, and this sweep runs AFTER the explicit,
        -- more precise `oneShotTriggerGate` registration further up --
        -- silently overwriting it with the generic, WRONG, zero-arg
        -- `StandardScriptHandlers.triggerEvent` handler the whole time.
        -- Real, live-confirmed impact: opcodes `0xFC`/`0xFD` are this
        -- ROM's actual `sSET_NPC_TYPES`/`sSPAWN_NPC` mechanism (see
        -- `ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC`/`_FD`'s own
        -- doc comment) -- with the bug, this runtime silently ran the
        -- wrong, argument-dropping handler for both, never actually
        -- staging a row or resolving a spawn. Excluded here so the
        -- explicit registration (now split into `ctx.onSetNpcTypes`/
        -- `ctx.onSpawnNpc`, see below) wins.
      elseif key:match("^TRIGGER_EVENT_HANDLER_ADDRESS") then
        interp:registerHandler(addr, StandardScriptHandlers.triggerEvent(ctx.onTriggerEvent))
      elseif key:match("^SOUND_PARAM") then
        interp:registerHandler(addr, StandardScriptHandlers.soundParam(ctx.onSoundParam))
      elseif key:match("^WORD_COMMAND_HANDLER_ADDRESS_EF$") then
        -- Self-caught bug: this generic sweep used to also pick up
        -- `WORD_COMMAND_HANDLER_ADDRESS_EF` and silently overwrite the
        -- more precise, explicit `TILE_CURSOR_SET_HANDLER_ADDRESS_EF`
        -- registration above (same address, `$0E7F`) with the less
        -- precise generic `wordCommand` handler, since this loop runs
        -- after that explicit call -- meaning the new handler was dead
        -- code the whole time it existed. Excluded here (same pattern
        -- as the `ACTOR_ACTION_HANDLER_ADDRESS_80` exclusion above) so
        -- the explicit registration actually wins. See
        -- `ScriptOpcodeTable.lua`'s `WORD_COMMAND_HANDLER_ADDRESS_EF`
        -- doc comment for the full story.
      elseif key:match("^WORD_COMMAND_HANDLER_ADDRESS") then
        interp:registerHandler(addr, StandardScriptHandlers.wordCommand(ctx.onWordCommand))
      end
    end
  end
end

--- One per-tick step. Safe to call every game frame (or in a tight
-- burst, see `:run()`) -- once a still-undecoded opcode is reached (or
-- any other Lua error), captures it into `self.stopped`/
-- `self.stopError` and becomes a permanent no-op from then on (never
-- re-throws), so a caller doesn't need its own pcall boilerplate. The
-- failure is inspectable state, not swallowed -- see this module's
-- "no silent fallbacks" note above.
function ScriptRuntime:step(stream, cursor)
  if self.stopped or self.finished then
    return cursor
  end
  local ok, newCursorOrErr, opcode, kind, pin = pcall(function()
    return self.interp:step(stream, cursor, self.pinnedOpcode)
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
  -- Opcode-pinning (see ScriptInterpreter:step's doc comment):
  -- `pin==true` keeps this same opcode active for the next dispatch;
  -- anything else releases back to normal stream-driven opcode
  -- selection.
  self.pinnedOpcode = pin and opcode or nil
  return newCursorOrErr
end

--- Steps up to `maxSteps` times (or until this run stops/finishes,
-- whichever comes first) -- a bounded burst, so a caller running this
-- synchronously (e.g. VictorySequence.lua's shadow-run at construction
-- time, not per game frame) can never hang on a script that happens to
-- loop far longer than expected. Returns the final cursor.
function ScriptRuntime:run(stream, cursor, maxSteps)
  for _ = 1, maxSteps do
    if self.stopped or self.finished then break end
    cursor = self:step(stream, cursor)
  end
  return cursor
end

return ScriptRuntime
