-- Decodes the real script/event interpreter's opcode dispatch table --
-- see docs/reverse-engineering/rom-map.md "THE real event/script
-- interpreter -- FOUND, FULLY DECODED" for the full trace.
--
-- Real, VERIFIED table: bank 2, file offset `0x8576`, 256 records x 2
-- bytes, indexed by the real WRAM "current opcode" byte (`$D85A`).
-- Each entry is a real CPU code address (little-endian) -- the REAL
-- ROM's own handler routine for that opcode, resolved by bank 2's own
-- function 51 (`LD HL,tableBase / ADD HL,BC / ADD HL,BC / LD A,(HL+) /
-- LD H,(HL) / LD L,A`, i.e. byte-index * 2 into a 16-bit-pointer
-- array -- the same generic dispatch shape reused throughout this
-- whole ROM). Confirmed to be exactly 256 real entries: the byte
-- immediately after the 256th entry (file `0x8776`) decodes as
-- ordinary, sensible SM83 code, not more table data.
--
-- Live-verified against two real, independently-traced opcodes:
-- `$D85A=0x04` -> `table[4]=0x333D` (5 live samples, exact HL match at
-- function 51's own RET); `$D85A=0xFE` (the real "Kaempfe!" message
-- trigger) -> `table[0xFE]=0x0E69`, exactly this project's own
-- already-known messageID-read handler address.
--
-- Pure Lua, no love.* calls -- headlessly testable, same convention as
-- MapTable/RoomSelectorTable/NoiseTable.

local ScriptOpcodeTable = {}

--- Real, VERIFIED handler addresses for the few opcodes this project
-- has actually decoded the SEMANTICS of (not just the table entry) --
-- see rom-map.md's own writeup for each. `ScriptInterpreter.lua` uses
-- these to decide real behavior vs. "genuinely undecoded, fail loudly."
ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS = 0x3F0C -- real no-op: `CALL $3727 / RET`
ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS = 0x0E69 -- real "display message" (opcode 0xFE)
-- Real "restore to max" family (curLP<-maxLP at $394F; very plausibly
-- the MP equivalent at $3968, structurally identical at the MP struct
-- offset -- not independently live-verified as MP specifically, see
-- rom-map.md's own honesty note).
ScriptOpcodeTable.HEAL_LP_HANDLER_ADDRESS = 0x394F
ScriptOpcodeTable.HEAL_MP_HANDLER_ADDRESS = 0x3968

-- Handlers found live-tracing the actual boss-defeat script byte by
-- byte (see events.md's "Every remaining open question, resolved" --
-- opcode 0x01 -> $32F3, 0x02 -> $32FE, 0xDC -> $3B5B, 0xDD -> $3B66;
-- the ROM disassembly for each is quoted there). Simple, fully-pinned
-- semantics: a relative skip, a pointer-chain (the same "show next
-- page" shape already known from the [0x12][0x1B] control-byte pair),
-- and a matched flag-set/flag-clear pair on WRAM $D874 bit 1.
ScriptOpcodeTable.SKIP_HANDLER_ADDRESS = 0x32F3
ScriptOpcodeTable.CHAIN_HANDLER_ADDRESS = 0x32FE
-- CHAIN's own handler ($32FE), disassembled directly (task #160/#81
-- follow-up, direct user question whether this could resolve prior
-- open questions): computes its target the already-verified way
-- (byte1*256+byte2+0x4000), writes it to the persistent-cursor cache
-- ($D8B6/$D8B7, WRAM_MAP's own entry), then calls a previously-
-- undocumented, general-purpose bank call-stack primitive found this
-- same pass: $2A0A ("pop" -- decrement HRAM $FF8A's own stack index,
-- switch to whatever MBC2 bank is now on top via the $2100
-- convention). The matching "push" ($29FB) and "peek" ($2A17, the same
-- routine the graphics-DMA consumer at $2DD3 calls to restore its own
-- bank after a transfer -- see rom-map.md's "the real graphics-loading
-- mechanism" section) are both disassembled, but no live trace has yet
-- confirmed this stack is what correctly resolves the 7 cross-bank
-- CHAIN targets task #81 is about -- genuine narrowing, not a closure.
-- A sibling block at $32CF shares the identical "commit cursor, pop
-- bank, release" shape, byte for byte.
ScriptOpcodeTable.FLAG_SET_HANDLER_ADDRESS = 0x3B5B
ScriptOpcodeTable.FLAG_CLEAR_HANDLER_ADDRESS = 0x3B66

-- Opcode 0x04's own handler ($333D) -- the typewriter reveal-tick,
-- confirmed live as part of the same boss-defeat script trace (~110
-- re-invocations, see events.md). No operand bytes; the interpreter
-- doesn't block on it (unlike the 0x00 conditional halt).
ScriptOpcodeTable.TICK_HANDLER_ADDRESS = 0x333D

-- Opcode 0xFF's own handler ($38E6) -- the "textbox driver" sub-
-- dispatch: LD A,($D86B) / LD HL,$3BAC / ... / JP HL, a second, byte-
-- indexed, 2-bytes/entry table (11 entries, rom_profiles.lua's own
-- scriptOpcodeSubTable) keyed by a separate WRAM cell ($D86B, not the
-- primary opcode cell $D85A). All 11 sub-handlers were fully
-- disassembled in a prior pass (events.md's "0xFF sub-table"
-- sections). Two independent live traces of the boss-defeat script (a
-- corrected, single-instruction-stepped re-verification covering the
-- first dialogue box, and a fresh, frame-counter-bounded trace
-- covering the full 14-box dialogue sequence) agree the sub-opcodes
-- actually exercised are 1 ($3597), 2 ($3675), 3 ($3C1B), and 4
-- ($350F). Sub-opcode 1 is the per-tick "advance the draw cursor,
-- paced (a 5-tick/frame pacing gate matching this project's already-
-- verified 5-frames-per-letter typewriter cadence), hand off to the
-- typewriter" routine; 3 and 4 are conditional halts whose exact WRAM
-- trigger conditions aren't pinned down (HYPOTHESIS, not VERIFIED)
-- but which are confirmed to eventually fall through to a CALL $3727
-- (release, continue) once their condition holds; 2 blanks a run of
-- tile positions (a line-clear/wrap rendering step). This project does
-- not reproduce this exact multi-sub-opcode state machine (see
-- StandardScriptHandlers.textboxWait's own doc comment for the
-- honestly-scoped, functionally-equivalent replacement wired here).
ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS = 0x38E6

-- Opcode 0xF0's own handler ($3C04) -- confirmed live via the boss-
-- defeat script trace and a full byte-for-byte static disassembly:
--   CALL $3727           ; fetch: consumes one operand byte into A
--                           (the interpreter's own general fetch
--                           primitive, reused here as a plain "read the
--                           next stream byte" helper -- its side effect
--                           of also writing $D85A is harmless, since
--                           $D85A is about to be overwritten below
--                           anyway)
--   PUSH HL
--   LD H,0x00 / LD L,A    ; HL = the operand byte, zero-extended
--   CALL $2F9E             ; helper, not further decoded (HYPOTHESIS
--                            re: exact purpose)
--   LD ($D84D),A           ; writes into WRAM $D84D -- the same cell
--                            events.md documents sub-opcode 3 ($3C1B)
--                            itself tests as part of its own
--                            conditional-halt logic -- this opcode's
--                            job is setting up the condition sub-
--                            opcode 3 later checks
--   CALL $2FD4             ; helper, not further decoded
--   LD B,0x03               ; B = 3 (the sub-opcode value)
--   CALL $3C74              ; the already-known "reschedule" primitive
--                             ($D86B=B, $D85A=0xFF) -- hands off
--                             directly into the 0xFF sub-dispatch
--                             family's own sub-opcode 3, confirming
--                             (not just structurally implying) that
--                             opcode 0xF0 is a dedicated "shortcut"
--                             entry point into the same textbox-wait
--                             mechanism opcode 0xFF itself uses.
--   POP HL / RET
ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS = 0x3C04

-- "Sound/timing parameter" opcode pair (0xF8/0xF9, ROM $119B/$1194 --
-- found this session's opcode-frequency scan, confirmed live as part
-- of the boss-defeat script's disassembly too). Byte-for-byte
-- identical shape, one operand byte each, writing to a different DMG
-- HRAM I/O register, always continuing (no conditional branch at all):
--   $119B (0xF8): LD A,(HL+) / LDH ($FF90),A / LD ($D49B),A /
--                 LD ($D4A3),A / CALL $3727 / RET
--   $1194 (0xF9): LD A,(HL+) / LDH ($FF92),A / CALL $3727 / RET
-- HRAM $FF90/$FF92 are DMG sound-channel-adjacent registers (not
-- independently mapped to a specific PAPU register -- this project has
-- no real sound emulation at all, see audio.md's "format totally
-- unknown" status) -- the exact musical/timing effect is HYPOTHESIS,
-- but the structure (1 operand byte, unconditional continue) is fully
-- verified.
ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS = 0x119B
ScriptOpcodeTable.SOUND_PARAM_2_HANDLER_ADDRESS = 0x1194

-- No-operand "trigger fixed event" opcode (0xE0, ROM $0FB4, found this
-- session's opcode-frequency scan):
--   PUSH HL / LD A,0x04 / CALL $235B / POP HL / CALL $3727 / RET
-- No operand bytes -- the 0x04 is a fixed constant baked into this
-- specific opcode's handler code (structurally identical sibling
-- handlers exist nearby with different fixed constants, e.g. 0x08, at
-- least one seen in passing during this disassembly -- not themselves
-- decoded/wired this pass). Always continues. $235B's own effect is
-- HYPOTHESIS -- the structure (no operand, unconditional continue) is
-- fully verified.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS = 0x0FB4

-- "Typewriter cursor command" opcode (0x03, ROM $332F, found this
-- session's opcode-frequency scan):
--   CALL $3727        ; fetch: consumes operand byte 1 into A
--   LD B,0x03          ; B = 3, a fixed constant (this opcode's own ID)
--   LD C,A              ; C = operand byte 1
--   INC HL               ; skips operand byte 2 (never read into any
--                          register -- a deliberate skip, not an
--                          omission in this disassembly)
--   CALL $36DF            ; the already-known typewriter-continuation
--                           site (see events.md's $331E note: "the
--                           real 'chain to the next page of this same
--                           message' mechanism") with BC set as above
--   CALL $3727             ; fetch: continues the script
--   RET
-- Always continues. The precise meaning of "B=3, C=operand byte 1" to
-- $36DF is HYPOTHESIS -- the structure (2 operand bytes, one used, one
-- skipped, unconditional continue) is fully verified.
ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS = 0x332F

-- The "actor flag/state" opcode family -- 7 opcodes (0x10/0x20/0x25/
-- 0x30/0x7B and 0x38/0x78), found via this session's opcode-frequency
-- scan as the largest remaining block of undecoded scripts (~145
-- combined) and traced end to end via static disassembly. All 7 share
-- one of two near-identical shapes; both ultimately reduce to "halt
-- until a WRAM condition holds, then perform an action and continue"
-- -- see StandardScriptHandlers.actorAction/.queuedAction for the
-- implementation, and events.md's "The actor flag/state family,
-- resolved" section for the full byte-for-byte chain.
--
-- Family A (0x10/0x20/0x25/0x30/0x7B): each opcode's handler does
-- CALL $28C2 (computes a 0-or-1 "action code adjustment" by checking
-- WRAM actor-record #7's own state field -- $C200 + 7*16 + 2 = $C272
-- -- against high-nibble 0xD0) / ADD A,<opcode-specific base> / LD
-- C,A / LD A,<opcode-specific fixed "group" value> / CALL $2879.
-- $2879 itself (PUSH HL / CALL $2883 / POP HL / RET NZ / CALL $3727 /
-- RET) tail-dispatches through $2883 -> the general cross-bank
-- dispatcher $1F35 (staged selector 0x0A) -> bank-3 handler $4B70
-- (not $4C38 -- see the correction below), which itself reads a
-- shared 24-byte-stride "actor slot" table ($C4E0, the same one
-- $4AF9 below indexes) and conditionally calls a second selector
-- (0x12, $4B62, which searches an 8-byte table at $C5A0 for a
-- matching value) -- $2879 genuinely halts (no $3727 anywhere in the
-- whole chain) while that multi-table lookup doesn't succeed, and
-- only performs its payload once it does. Per-opcode "group" constants
-- (the fixed A value each passes to $2879): 0x10/0x20/0x30 -> group
-- 0x04; 0x25 -> group 0x1F; 0x7B -> group 0x0F.
--
-- $4B70 DECODED (task #85, direct follow-up to a question about what's
-- still missing for full room interpretation, chasing whether room-
-- connectivity/spawn data hides behind this dispatch chain): PUSH AF
-- (save the incoming "group" value) / LD A,C (the $28C2-derived
-- action-code-adjustment becomes the active value) / CP 0xFF -> a
-- special "clear" path if the action code is the 0xFF sentinel / else
-- HL = $C4E0 + actionCode*24 (this table is indexed by the action
-- code, not by "group" -- a correction to this doc's earlier
-- phrasing, which conflated the two) / POP AF / LD B,A (group now
-- lives in B) / LD C,(HL) (reads that action-code slot's own stored
-- byte) / HL = DE+4 (a second field, 4 bytes into the same 24-byte
-- record) / if that field is zero: writes B (the group value) into
-- it, then does a "search-or-insert" dance against selector 0x12's
-- own $C5A0 8-byte table (via 2 more CALL $4B62 calls, one with A=0,
-- one with the group's own ID) -- if nonzero already: does the same
-- search-or-insert without the write. Decisive conclusion: this is a
-- general-purpose "enqueue a (group, actionCode) pair into a shared
-- actor-action table, deduplicated against an 8-slot pending-set"
-- mechanism -- structurally an actor command queue, not room-
-- selection or spawn-coordinate data. No room ID, no X/Y pair, no
-- tile/pixel-shaped value appears anywhere in this routine. This
-- decisively rules out the Family-A actorAction chain as the source
-- of room-connectivity/spawn-position data (a useful negative result
-- narrowing task #85's search, not a final answer to where that data
-- actually lives -- see events.md's own dated entry for the door-
-- transition script this was chased from).
--
-- CORRECTED (disassembling the rest of $1F35's own dispatch table):
-- an earlier pass here had an indexing bug -- it treated CPU $4014 as
-- the table's own index-0 base, when $1F35's code (LD H,0x40 / LD
-- L,<selector*2>) actually bases the table at $4000 (so selector 0x0A
-- really lands at $4000+0x0A*2=$4014, not at the table's own start).
-- This silently mis-resolved every selector past a few coincidental
-- low ones, including wrongly claiming selector 0x0A (this family's
-- own trampoline target) resolves to $4C38 -- it actually resolves
-- to `$4B70` (confirmed above). `$4C38` is real and IS the handler for
-- a DIFFERENT real selector (`0x14`) that also starts with `CALL
-- $4BE0` and does contain the real `$C272` check -- but `0x14` is NOT
-- what `$2883`'s own fixed `LD A,0x0A` reaches. Whether `$C272` is
-- STILL the real condition gating Family A (perhaps reached
-- indirectly, further down `$4B70`'s or `$4B62`'s own call chain, not
-- yet traced to a stopping RET) is now genuinely OPEN again -- this
-- project's own earlier "live-observed $C272 correlates with this
-- family's own real halt/release timing" claim was based on live
-- WRAM watching, not this static chain, so it isn't itself
-- invalidated -- but the STATIC PROOF above (which used to cite
-- `$4C38` specifically) no longer holds and needs a fresh re-trace.
-- See events.md's "The $1F35 dispatcher, fully mapped" section for
-- the complete, corrected 22-entry table and this honest retraction.
--
-- READ-SIDE CONSUMER FOUND (task to keep following the bank-3 function
-- table): selector 0x0E ($4B4F) is the periodic scanner that consumes
-- what selector 0x0A/$4B70 writes. It walks all 8 bytes of the $C5A0
-- known-list and, for each nonzero entry, calls a per-entry helper
-- $4B19, which resolves the entry's value back to its $C4E0 record
-- (via $429B, a linear 8-slot search by ID byte) and, if that record's
-- state field (+4, the same field $4B70 writes the group value into)
-- is still nonzero, calls a per-record "tick" handler, $404A. $404A
-- decrements a countdown field (+1); once it reaches 0, it reloads it
-- from a fixed reload value (+2), conditionally calls a further helper
-- ($4107, gated by field +8), then branches on whether the group field
-- (+4) is zero (a LD A,(DE) / CALL $29BA path -- untraced further this
-- pass) or nonzero (calls $4247, then CALL $2B70 on a fixed address
-- $4C55 -- confirmed via $2B70's own disassembly, CALL $2B63 / JP HL,
-- to be a generic cross-bank "call through HL" trampoline, not a
-- group-indexed table lookup). If $404A's tick re-zeroes the state
-- field, $4B19 clears the $C5A0 slot (the flag is "consumed");
-- otherwise it stays pending for the next scan.
--
-- Cross-check: selector 0x15's own code confirms (independently) that
-- $C4E0 records embed a further pointer at +0x12, itself dereferenced
-- a second time at a +0x14 offset from its own target -- a two-level
-- indirection (record -> sub-structure -> sub-sub-structure),
-- structurally consistent with a per-actor animation/effect state
-- chain rather than a flat "story flag" registry.
--
-- Net effect: this refines (doesn't overturn) the "actor command
-- queue" framing -- it's a periodic, per-record tick system (countdown/
-- reload timers, an embedded nested-pointer field) layered on top of
-- the queue, reading more like a scripted visual/behavior-effect
-- ticker than a discrete quest-flag store. The real-world meaning of
-- the 8 action-code values is still open (the $4107/$29BA/$4247 leaves
-- and the 0x0C/0x0D/0x0B/0x0F selectors' own further helpers weren't
-- traced this pass) -- a bounded next step would be finding who writes
-- the record's own +0x12 pointer field, or live-watching that field
-- plus +8 during a known visual effect. See events.md's dated entry.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10 = 0x125C -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_20 = 0x12D0 -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_25 = 0x130C -- group 0x1F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_30 = 0x1344 -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_7B = 0x157C -- group 0x0F
-- SUPERSEDED (task-11 quality pass): opcode 0x7B's handler is now more
-- precisely modeled by ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_
-- ADDRESS_7B (same address, $157C -- see that constant's own doc
-- comment, and StandardScriptHandlers.actorActionWithReadinessParam's
-- doc comment, for the full disassembly and why it's more precise than
-- this generic-family entry). This constant is kept only because
-- existing tests assert it against the opcode-table bytes, and
-- ScriptRuntime.lua's own generic sweep now explicitly excludes it (a
-- self-caught dead-code bug: this constant's generic registration used
-- to silently overwrite the newer, more precise one -- see that file's
-- own matching exclusion comment for the full story).

-- Family B (0x38/0x78): each opcode's handler does CALL $28C2 / ADD
-- A,<base> / LD C,A / CALL $2859 (no fixed "group" this time). $2859
-- (PUSH BC / PUSH HL / CALL $289B / POP HL / POP BC / RET NZ / ...)
-- halts via a different condition: $289B OR-reduces 8 WRAM bytes at
-- $C5A0 and sets the tested flag from the result -- $2859 genuinely
-- halts while any of those 8 bytes is nonzero, and only once all 8 are
-- zero does it read a WRAM table at $C4E0 (8 bytes/record, indexed by
-- the action code) and call $27E3 (not decoded further) before
-- continuing via $3727. ($C5A0/$C4E0 are the same two addresses this
-- project's own earlier "honest negatives" re-verification -- see
-- events.md -- already found genuinely zero-hit during the boss-
-- defeat script's execution window, consistent with these 2 opcodes
-- not appearing in that script's 18-opcode list at all.)
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_38 = 0x138C
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_78 = 0x155C

-- Round 2 (direct instruction to do "2" first -- a fresh re-scan of
-- all 1357 scripts, now that opcode 0x00's own halt no longer masks
-- scripts that walk past it, found 9 more opcodes using this exact
-- same already-solved family, previously hidden behind other, now-
-- resolved blockers). Same two shapes as Family A/B above, just
-- different fixed constants -- each verified byte-for-byte:
--   0x11 ($1268): base 0x00, group 0x05   (Family A)
--   0x14 ($128C): base 0x00, group 0x1E   (Family A)
--   0x18 ($12A4): base 0x00               (Family B)
--   0x1B ($12C4): base 0x00, group 0x0F   (Family A)
--   0x3A ($13A0): base 0x02, group 0x0E   (Family A)
--   0x40 ($13B8): base 0x03, group 0x04   (Family A)
--   0x48 ($1400): base 0x03               (Family B)
--   0x60 ($14A0): base 0x05, group 0x04   (Family A)
--   0x70 ($1514): base 0x06, group 0x04   (Family A)
-- (The "base" constant, same as Family A/0x10 etc above, is not
-- separately modeled -- see this project's reasoning above for why it
-- carries no additional observable information for this project's
-- purposes.)
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_11 = 0x1268 -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_14 = 0x128C -- group 0x1E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1B = 0x12C4 -- group 0x0F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3A = 0x13A0 -- group 0x0E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_40 = 0x13B8 -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_60 = 0x14A0 -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_70 = 0x1514 -- group 0x04
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_18 = 0x12A4
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_48 = 0x1400

-- No-operand "trigger fixed event" opcode 0xE4 (ROM $0F88) -- found the
-- same re-scan, byte-for-byte identical shape to 0xE0
-- (TRIGGER_EVENT_HANDLER_ADDRESS) above, just a different fixed
-- constant passed to the same $235B helper (A=1 here vs. A=4 for
-- 0xE0): PUSH HL / LD A,0x01 / CALL $235B / POP HL / CALL $3727 / RET.
-- Reuses StandardScriptHandlers.triggerEvent directly -- no new Lua
-- implementation needed.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E4 = 0x0F88

-- Opcodes 0x80 (ROM $15A4) and 0x85 (ROM $15EF) -- a third shape found
-- this round, reusing the actor-flag family's own $2879 dispatch but
-- gated by a different condition (a shared helper, $1588, byte-for-
-- byte disassembled):
--   $1588  PUSH HL / CALL $02AB / POP HL   ; $02AB: LD C,4 / CALL $0C99
--                                          ;  / RET -- a general
--                                          ; actor-array read ($C200 +
--                                          ; index*16, the same base
--                                          ; $0C6D itself uses), field
--                                          ; +0 (no "+2"/no 0xFF-empty
--                                          ; check this time), fixed
--                                          ; index 4 -- reads actor-
--                                          ; record #4's own type/
--                                          ; presence byte,
--                                          ; $C200+4*16 = $C240
--   $158D  BIT 7,A / RET Z                 ; release: if $C240's own
--                                          ; bit 7 is clear, return
--                                          ; with Z set (the caller's
--                                          ; RET NZ doesn't fire ->
--                                          ; continues)
--   ; bit 7 set: a further sub-check ($2938, not decoded) either skips
--   ; straight to, or first triggers a nested $2879 call (fixed
--   ; C=0xFF, group = a second, fresh $02AB read) before reaching, a
--   ; final XOR A / DEC A / RET that always forces NZ -- every bit-7-
--   ; set path halts the caller, whether or not that nested dispatch
--   ; fired.
-- Net observable effect from 0x80/0x85's perspective: halt while WRAM
-- $C240 (actor-record #4's type byte) has bit 7 set. The nested $2879
-- trigger that sometimes fires while still halting is a further
-- behavior this project doesn't reproduce (HYPOTHESIS on its purpose,
-- and it never affects the caller's observable release timing anyway,
-- since every path that reaches it also forces a halt regardless).
--
-- 0x80's own "group" (the value passed to its own, un-nested $2879
-- call once released) is not a fixed constant like every other opcode
-- in this family -- it's computed live, ($02AB result) AND 0x0F, +
-- 0x90 -- a dynamic value depending on actor #4's current low nibble
-- at release time (see StandardScriptHandlers.actorAction's own
-- extended doc comment for how this project models that: group may be
-- a plain function, called fresh on release). 0x85's group is a fixed
-- constant (0x08, with C=0xFF fixed too, not computed via the usual
-- $28C2 base-adjustment).
--
-- CRACKED (task 10, direct instruction to actually solve the 6 $02AB
-- siblings): "actor #4" here is exactly EntityStructLayout.lua's own
-- already-live-confirmed PLAYER_SLOT_INDEX_HYPOTHESIS = 4 -- WRAM
-- $C240 is the player's own entity-state byte, and $02AB (previously
-- treated as an opaque, "needs live WRAM simulation" leaf) is nothing
-- more than a plain read of it. Live-traced its low-nibble values
-- across idle/movement/attack: a one-hot facing-direction bitmask
-- (1=right/2=left/4=up/8=down, decisively confirmed via the idle
-- value 0x04 exactly matching this project's own independently-
-- verified Player.DEFAULT_FACING = "up"). 0x80's dynamic group is
-- therefore purely a function of the player's current facing
-- direction -- see EntityStructLayout.PLAYER_FACING_BIT's own doc
-- comment for the complete live-trace data, and ScriptRuntime.lua's
-- own 0x80 registration for the implementation (now wired, not left
-- unmodeled -- this opcode is no longer part of the known-hard family
-- in any meaningful sense, even though it stays visible near the top
-- of the whole-corpus scan's ranking for a different reason: $1588's
-- bit-7 gate, approximated the same way every other $1588-gated
-- opcode already is).
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80 = 0x15A4 -- group: dynamic, see above (CRACKED)
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_85 = 0x15EF -- group 0x08

-- No-operand, unconditionally-continuing opcode 0xDE (ROM $3B81) --
-- byte-for-byte disassembled: WRAM housekeeping on a cooldown counter
-- ($D6F0) and a 24-entry table ($D6C5, LD B,0x18) -- resets $D6EF/
-- $D6F1 to 0x80 and clears/finds a matching table slot once the
-- cooldown expires, no-ops otherwise. Every branch (cooldown active,
-- cooldown just expired, table slot found, table slot not found)
-- converges on the same POP HL / CALL $3727 / RET tail -- genuinely no
-- conditional halt anywhere, confirmed by tracing every branch to that
-- same ending. PUSH HL at entry / POP HL right before CALL $3727
-- cleanly brackets the routine's own internal (unrelated) use of HL
-- for the table scan, confirming it never touches the script cursor.
-- Reuses StandardScriptHandlers.triggerEvent directly -- same shape as
-- 0xE0/0xE4 above (no operand, no halt, WRAM side effect this project
-- doesn't reproduce, always continues).
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_DE = 0x3B81

-- Round 3 (same "do 2 first" pass -- a second re-scan, now with round
-- 2's opcodes also known, found these): 5 more Family-A actor-flag/
-- state opcodes (verified byte-for-byte, same shape as every other
-- Family-A member above) plus 2 more trigger-event opcodes (same
-- shape as 0xE0/0xE4/0xDE above, one calling a different fixed helper,
-- $22FE instead of $235B -- irrelevant to this project's own
-- implementation, which never models the payload for any of these
-- anyway).
--   0x21 ($12DC): base 0x01, group 0x05
--   0x3B ($13AC): base 0x02, group 0x0F
--   0x47 ($13DC): base 0x03, group 0x1D
--   0x71 ($1520): base 0x06, group 0x05
--   0x77 ($1538): base 0x06, group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_21 = 0x12DC -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3B = 0x13AC -- group 0x0F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_47 = 0x13DC -- group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_71 = 0x1520 -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_77 = 0x1538 -- group 0x1D
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E2 = 0x0FCA -- group 0x08, via $235B (same helper as 0xE0)
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E5 = 0x0F93 -- group 0x01, via $22FE (a different helper)

-- Real opcode `0xB0` (ROM `$0F1E`) -- byte-for-byte disassembled:
--   LD A,(HL+) / LD E,(HL) / INC HL / LD D,(HL) / INC HL   ; real: 1
--                                          operand byte -> A, then a
--                                          real 16-bit LITTLE-endian
--                                          operand word -> DE (byte
--                                          N+1 = low/E, byte N+2 =
--                                          high/D -- a plain, direct
--                                          `LD E,(HL)/LD D,(HL)` read,
--                                          NOT the PUSH/POP byte-swap
--                                          trick CHAIN uses, so this
--                                          one really is little-endian)
--   PUSH HL / CALL $2400 / POP HL          ; real helper, not decoded
--                                            further (HYPOTHESIS)
--   CALL $3727 / RET                        ; ALWAYS continues -- no
--                                            conditional branch
--                                            anywhere in this routine
ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS = 0x0F1E

-- Opcode 0xD0 (ROM $3A4F) -- byte-for-byte disassembled:
--   LD E,(HL) / INC HL / LD D,(HL) / INC HL   ; 16-bit little-
--                                             endian operand word -> DE
--   LD HL,($D7BE)/($D7BF) [as a 16-bit WRAM counter] / ADD HL,DE
--   JR NC,<skip> / LD HL,0xFFFF                ; clamp-at-0xFFFF
--                                              on overflow
--   <write the (possibly clamped) HL back to $D7BE/$D7BF>
--   CALL $3117 / POP HL / CALL $3727 / RET      ; always continues --
--                                              no conditional branch
-- Plausible role (HYPOTHESIS, not confirmed): a saturating 16-bit WRAM
-- counter add -- gold/experience/step-counter shaped, but not
-- independently verified. This project doesn't reproduce the WRAM
-- counter itself -- onCommand receives the raw operand word, what to
-- do with it is the caller's business.
ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS = 0x3A4F

-- Opcodes 0xD2/0xD3 (ROM $3A0D/$3A1C) -- CLOSED (direct user request
-- to decode the missing opcodes): a sibling pair of WORD_COMMAND_
-- HANDLER_ADDRESS above -- same shape (2-byte little-endian operand,
-- CALL $3727 / RET, always continues), but operating on a different
-- WRAM counter, with a specific decoded meaning this pass:
--   0xD2 ($3A0D): LD E,(HL)/INC HL/LD D,(HL)/INC HL (operand word) /
--     PUSH HL / PUSH DE / POP HL / CALL $3D21 / POP HL / CALL $3727 /
--     RET -- delegates the add to $3D21.
--   $3D21: reads the 24-bit WRAM counter $D7BB(low)/$D7BC(mid)/$D7BD
--     (high, only ever 0 or a small carry) and does HL,A =
--     ($D7BC:$D7BB) + DE, A += carry, then clamps to a specific
--     ceiling: high==0x0F and mid==0x42 and low==0x3F (the 24-bit
--     value 0x0F423F = decimal 999999) -- writes the clamped result
--     back to the same 3 cells ($3D48 onward, not shown here).
--   0xD3 ($3A1C): the exact mirror -- HL,C = ($D7BC:$D7BB:$D7BD) - DE
--     (subtract instead of add), clamps to 0 on underflow instead of
--     to the ceiling, writes back to the same 3 cells.
-- Well-evidenced role (still HYPOTHESIS -- inferred from the exact cap
-- value, not independently live-verified via gameplay): the 24-bit
-- gold counter ($D7BB-$D7BD) -- a classic RPG "999999 max gold"
-- ceiling is a much more specific signal than a generic 0xFFFF/0xFF
-- overflow clamp, and this project's own decoded shop dialogue ("Du
-- hast nicht genug Goldstuecke!" = "You don't have enough gold!", see
-- rom-map.md's text-decoding section) independently confirms a gold
-- system exists in this game. 0xD2 = ADD gold, 0xD3 = SUBTRACT gold
-- (shop purchase). This project doesn't reproduce the WRAM counter
-- itself (same honest scope as WORD_COMMAND_HANDLER_ADDRESS above) --
-- onCommand receives the raw operand word, what to do with it (and
-- which direction) is the caller's business; both share the same
-- generic ctx.onWordCommand callback via ScriptRuntime.lua's own
-- existing ^WORD_COMMAND_HANDLER_ADDRESS sweep, same as 0xD0.
ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_D2 = 0x3A0D -- ADD (24-bit gold counter, capped at 999999)
ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_D3 = 0x3A1C -- SUBTRACT (same counter, clamped to 0)

-- Opcode 0xE8 (ROM $0F5A) -- CLOSED (the $1ED7 dispatcher this session
-- separately, fully mapped while tracing the cut-transition tile-
-- coordinate mechanism is exactly what this note's earlier "condition
-- not characterized" was waiting on). See StandardScriptHandlers
-- .dualGateLeafCommand's own doc comment for the complete chain
-- ($0232/$049E are $1ED7-selector trampolines; the halt is the same
-- $C8E0/$CEE8 dual gate already modeled for 0xFC/0xFD).
--   PUSH HL / LD B,0 / LD A,0x88 / CALL $0232 / LD D,4 / LD A,4 /
--   CALL $049E / POP HL / CP 0x00 / RET NZ / CALL $3727 / RET
ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E8 = 0x0F5A

-- Opcode 0xE9 (ROM $0F71) -- FOUND, direct response to a request to
-- follow all the threads one after another (the "spawn position/
-- trigger zones" investigation): sits immediately before the already-
-- known 0xE4 handler ($0F88) -- structurally byte-identical to 0xE8
-- above, just different literal parameters:
--   PUSH HL / LD B,0 / LD A,0x84 / CALL $0232 / LD D,4 / LD A,0x08 /
--   CALL $049E / POP HL / CP 0x00 / RET NZ / CALL $3727 / RET
-- (0xE8's own parameters are A=0x88 then A=0x04; 0xE9's are A=0x84
-- then A=0x08.) A correction to how $0232/$049E were first read: they
-- aren't case-selector dispatchers indexed by the incoming A -- each
-- is itself one of a cluster of 6-byte PUSH AF / LD A,<fixed case> /
-- JP $1ED7 trampolines ($1ED7, a sibling of the already-fully-mapped
-- $1F35/$1F06 cross-bank dispatcher family, switching to bank 1
-- instead of bank 2 -- see events.md's "spawn position + trigger
-- zones" section for the full trace) -- CALL $0232 always reaches the
-- same case (1, $48BE) regardless of caller; the incoming A (0x88/
-- 0x84 here) is a genuine parameter passed through to that case's
-- handler, preserved across the trampoline via PUSH AF/POP AF, not a
-- selector. CLOSED, same chain as 0xE8 above -- see
-- StandardScriptHandlers.dualGateLeafCommand's own doc comment.
ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_E9 = 0x0F71

-- Opcodes 0xEA/0xEB (ROM $0F2C/$0F43) -- CLOSED (continuing with the
-- top blockers -> whole-corpus scan's own rank-3 blocker after 0x8F's
-- closure, 32 scripts): structurally byte-identical to 0xE8/0xE9
-- above, completing a coherent 4-direction family -- 0xEA's parameters
-- are A=0x82 then A=0x01; 0xEB's are A=0x81 then A=0x02 (vs.
-- 0xE8=0x88/0x04, 0xE9=0x84/0x08) -- the same direction-bit convention
-- already known from the door/exit-reveal family (North=4, East=1,
-- South=8, West=2): 0xE8=North, 0xE9=South, 0xEA=East, 0xEB=West. Same
-- shared gate ($44D8's own $C8E0/$CEE8 check, reached via $049E), same
-- unconditional $48BE/$02AB leaf work first -- see
-- StandardScriptHandlers.dualGateLeafCommand's own doc comment,
-- unchanged, for the full chain (no new Lua code needed, these reuse
-- the exact same factory as 0xE8/0xE9).
ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EA = 0x0F2C
ScriptOpcodeTable.DUAL_GATE_LEAF_COMMAND_HANDLER_ADDRESS_EB = 0x0F43

-- Round 4 (same "do 2 first" pass, a 3rd re-scan): 4 more Family-A
-- actor-flag opcodes, 1 more triggerEvent-shaped opcode, and 3 more
-- genuinely new always-continuing shapes.
--   0x15 ($1298): base 0x00, group 0x1F
--   0x17 ($1280): base 0x00, group 0x1D
--   0x56 ($1444): base 0x04, group 0x1C
--   0x65 ($14DC): base 0x05, group 0x1F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_15 = 0x1298 -- group 0x1F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_17 = 0x1280 -- group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_56 = 0x1444 -- group 0x1C
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_65 = 0x14DC -- group 0x1F

-- 0xE1 ($0FBF): byte-identical shape to 0xE5 above (PUSH HL / LD
-- A,0x04 / CALL $22FE / POP HL / CALL $3727 / RET) -- same helper
-- ($22FE), different fixed constant (A=4 vs 0xE5's A=1).
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E1 = 0x0FBF -- group 0x04, via $22FE

-- 0xB9 ($1186): PUSH HL / LD HL,0xC3F1 / SET 0,(HL) / CALL $0204 /
-- POP HL / CALL $3727 / RET -- no operand bytes, sets a fixed WRAM
-- flag bit ($C3F1 bit 0 -- not the same cell as opcode 0xDC/0xDD's own
-- $D874), always continues. CORRECTED (whole-corpus scan pass):
-- originally wired here via the coarser triggerEvent (which ignores
-- the bit-set and the $0204 leaf entirely) -- superseded by the more
-- precise WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9 below, which models
-- both. Kept as an honest record of the earlier, less-precise pass
-- rather than silently deleted.

-- 0xC3 ($3A09): CALL $3727 / RET -- byte-identical in effect to the
-- no-op default handler ($3F0C), just living at a separate table
-- entry/address (this ROM's own code reuse, not modeled further -- a
-- harmless duplication). Reuses triggerEvent with no callback
-- (equivalent to a genuine no-op).
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_C3 = 0x3A09

-- 0xE6 ($0F9E) -- FOUND, direct response to a user bug report that the
-- room after the meeting-room continues left but can't be walked into,
-- asking whether secondRoom's west side has an undiscovered exit,
-- derived from algorithms rather than empirically. $235B (the per-exit
-- "open" dispatcher, see TRIGGER_EVENT_HANDLER_ADDRESS/_E4/_E2 above
-- -- rom-map.md's "Which physical exit each $225D bit-case is" table)
-- is called with exactly 4 fixed arguments ROM-wide (0x01/0x02/0x04/
-- 0x08 = East/West/North/South respectively) -- 0xE0/0xE4/0xE2 above
-- already cover North/East/South; 0x02 (West) was the one direction
-- this project's opcode census had never matched to an actual script-
-- opcode byte. Found by computing the expected handler address
-- directly (the 4th CALL $235B call site, rom-map.md's exhaustive-scan
-- file offset 0xFA1, minus the 3-byte PUSH HL/LD A,n prologue = $0F9E)
-- and confirming its bytes match exactly:
--   $0F9E  PUSH HL / LD A,0x02 / CALL $235B / POP HL / CALL $3727 / RET
-- -- byte-identical shape to 0xE0/0xE4/0xE2/0xDE/0xB9/0xC3 above (no
-- operand, unconditional continue). Reuses triggerEvent directly, same
-- as every other member of this family.
--
-- HONEST, DIRECT ANSWER to the triggering bug report: a systematic,
-- conservative walk of all 1357 scripts (advancing only through
-- opcodes with an already-known operand width, stopping at the first
-- unknown one -- this project's established, non-guessing census
-- method) finds zero scripts that ever reach this opcode. Bounded,
-- honest limitation: this only searches each script's known-width
-- prefix (most scripts hit a still-undecoded opcode within their first
-- few bytes) -- it doesn't prove 0xE6 is categorically unused past
-- those points. Combined with a live confirmation (holding LEFT for
-- 200 frames at secondRoom's west wall, at 9 different Y rows spanning
-- the whole room, produced zero movement and zero scroll-register
-- change at every single one): secondRoom's west side is a genuine
-- wall in this project's currently-reachable, decoded content -- not
-- an app bug. The room's own "Der Monstereingang fuehrt nach
-- draussen" NPC hint most likely foreshadows still-unreached content
-- elsewhere (an honest open question, not resolved here), not a
-- currently-reachable exit this project simply failed to wire up.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E6 = 0x0F9E

-- 0xEF ($0E7F): LD A,(HL+) / LD E,A / LD A,(HL+) / LD D,A / PUSH HL /
-- CALL $0454 / POP HL / CALL $3727 / RET -- the same operand shape as
-- WORD_COMMAND_HANDLER_ADDRESS above (2 little-endian operand bytes ->
-- a 16-bit word), just calling a different, undecoded helper ($0454
-- instead of $3117). Reuses wordCommand directly.
--
-- CORRECTED/REFINED (whole-corpus scan follow-up): $0454 has since
-- been fully disassembled and isn't an opaque word-sized computation
-- -- it's a plain, branchless 2-byte store (LD (0xC345),A / LD
-- (0xC344),A, no arithmetic). Treating the operand as a combined
-- little-endian 16-bit "word" (this constant's original framing) is
-- technically harmless for stream-advancement purposes but throws
-- away the byte1/byte2 split a caller would want. Superseded by the
-- more precise TILE_CURSOR_SET_HANDLER_ADDRESS_EF constant below
-- (same address, StandardScriptHandlers.tileCursorSet) -- SELF-CAUGHT
-- BUG: this constant's name still matches the generic ^WORD_COMMAND_
-- HANDLER_ADDRESS sweep in ScriptRuntime.lua, which was silently
-- overwriting the more precise explicit registration every time
-- :registerStandardHandlers ran -- see that file's own generic-loop
-- exclusion for the fix. This constant is kept (not deleted) only
-- because existing tests assert the opcode-table entry against it;
-- new code should prefer TILE_CURSOR_SET_HANDLER_ADDRESS_EF.
ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_EF = 0x0E7F

-- `0xF6` ($3CA2) -- a real, LONGER always-continuing routine (many
-- real WRAM writes -- $D862/$D86D/$D86C/$D8D7-$D8DA cleared/$D876/
-- $D8D8/$D853/$D84A/$C0A0, several already-recognized dialogue-state
-- cells from the `0xFF` sub-table investigation, e.g. `$D853`/`$D84A`
-- -- a real, plausible "start a new textbox/scene" initializer,
-- HYPOTHESIS on the exact role). Consumes 2 REAL operand bytes, kept
-- SEPARATE (not combined into a word -- each is copied to its own,
-- different WRAM cell: `$D86D`, `$D86C`). Traced the ENTIRE routine
-- (~50 real bytes) end to end: NO conditional branch anywhere, always
-- reaches its own real `POP HL / RET` (the real `$3727` continuation
-- call happens one level deeper, inside the routine's own final
-- `CALL $3D10` -- the same "a shared helper calls $3727 on the
-- caller's behalf" pattern already confirmed for `$2879` itself).
ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS = 0x3CA2

-- Round 5 (same "do 2 first" pass, a 4th re-scan): 6 more Family-A
-- actor-flag opcodes, 1 more $1588-gated opcode (the same family as
-- 0x80/0x85), 1 more always-continuing triggerEvent-shaped opcode.
-- Script counts are now consistently small (10-15 each, down from the
-- 100+ counts round 1 found) -- a measurable sign this family is close
-- to fully mined.
--   0x16 ($1274): base 0x00, group 0x1C
--   0x1A ($12B8): base 0x00, group 0x0E
--   0x26 ($12E8): base 0x01, group 0x1C
--   0x2A ($132C): base 0x01, group 0x0E
--   0x44 ($13E8): base 0x03, group 0x1E
--   0x57 ($1450): base 0x04, group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_16 = 0x1274 -- group 0x1C
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1A = 0x12B8 -- group 0x0E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_26 = 0x12E8 -- group 0x1C
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2A = 0x132C -- group 0x0E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_44 = 0x13E8 -- group 0x1E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_57 = 0x1450 -- group 0x1D

-- 0x27 ($12F4) -- FOUND, direct continuation of Milestone 7: found
-- while investigating the dense opcode-handler cluster right around
-- 0x19's own handler (see that constant's own doc comment below) --
-- byte-for-byte identical shape to every other Family-A member above
-- (CALL $28C2 / ADD A,1 / LD C,A / LD A,0x1D / CALL $2879 / RET),
-- fixed group 0x1D.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_27 = 0x12F4 -- group 0x1D

-- 0x50 ($142C) -- FOUND: the live shadow-run's next stopper after
-- wiring 0x19/0x27 above (stepCount 7 -> 9, halted on this genuinely-
-- undecoded opcode next). Bytes: CALL $28C2 / ADD A,0x04 / LD C,A /
-- LD A,0x04 / CALL $2879 / RET -- another byte-for-byte Family-A
-- member, base=4, fixed group=0x04.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_50 = 0x142C -- group 0x04

-- 0x51 ($1438) -- FOUND, immediate live shadow-run follow-up to 0x50
-- above: the very next handler in the same dense run of Family-A
-- trampolines ($1438 immediately follows 0x50's own RET at $1437).
-- Bytes: CALL $28C2 / ADD A,0x04 / LD C,A / LD A,0x05 / CALL $2879 /
-- RET -- same base=4 as 0x50, fixed group=0x05.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_51 = 0x1438 -- group 0x05

-- 0x61 ($14AC) -- FOUND, live shadow-run's next stopper after wiring
-- 0x50/0x51 (opcode 0x60 itself was already known and stepped through
-- automatically). Bytes: CALL $28C2 / ADD A,0x05 / LD C,A / LD A,0x05
-- / CALL $2879 / RET -- Family-A again, base=5, fixed group=0x05.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_61 = 0x14AC -- group 0x05

-- 0x64 ($14D0) -- FOUND, task #86 (mapping the bank-accurate post-boss
-- sequence live). Bytes: CALL $28C2 / ADD A,5 / LD C,A / LD A,0x1E /
-- CALL $2879 / RET -- Family-A, base=5, fixed group=0x1E.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_64 = 0x14D0 -- group 0x1E

-- 0x87 ($15D7) -- FOUND, same pass. Bytes: CALL $1588 / RET NZ / LD
-- A,0x02 / LD C,0xFF / CALL $2879 / RET -- the same $1588-gated shape
-- already documented for 0x84/0x85 above (WRAM $C240 bit 7, not the
-- more common $C272 actor-ready gate) -- reuses the same generic
-- actorAction wiring/honest-limit as those two, fixed C=0xFF, group 0x02.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_87 = 0x15D7 -- group 0x02, $1588 gate

-- 0x86 ($15CB, whole-corpus scan -- found right next to 0x81's own
-- known-hard $02AB-dependent neighbor below): CALL $1588 / RET NZ /
-- LD A,0x01 / LD C,0xFF / CALL $2879 / RET -- the same $1588-gated
-- shape as 0x84/0x85/0x87 above, just group 0x01. Reuses the same
-- generic actorAction wiring/honest-limit as those three.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_86 = 0x15CB -- group 0x01, $1588 gate

-- 0x81 ($15B7) -- CRACKED for real (direct instruction to decode the
-- whole game map, absolute priority, continuing the whole-corpus-scan
-- sweep): CALL $1588 / RET NZ / PUSH HL / CALL $02AB / CALL $29E4 /
-- POP HL / OR 0xB0 / LD C,0xFF / CALL $2879 / RET -- the fourth
-- sibling of the $02AB family (0x80/0xEC/0xED/0xEE), and the second to
-- close for real (see EntityStructLayout.lua's own PLAYER_FACING_BIT
-- doc comment for 0x80's own earlier closure -- the same $02AB leaf
-- this one reuses).
--
-- $29E4, disassembled: AND 0x0F then a bit trick -- XOR 0x03 on the
-- low pair (bits 0-1) whenever it's not already zero, XOR 0x0C on the
-- high pair (bits 2-3) whenever it's not already zero. Worked out by
-- truth table against every one-hot input $02AB can produce (per the
-- 0x80 investigation, $02AB's low nibble is always one-hot):
-- 0x01<->0x02 (right<->left), 0x04<->0x08 (up<->down), 0x00->0x00 --
-- $29E4 is a general "flip to the opposite facing direction" helper.
-- 0x81's group is therefore flip(player's current facing) | 0xB0 --
-- an "opposite-facing" counterpart to 0x80's own "same-facing" ... +
-- 0x90 formula (both read the exact same $02AB leaf, just combined
-- differently afterward).
--
-- Same $1588 gate as 0x84-0x87 above (WRAM $C240 bit 7, already
-- approximated via ctx.isActorReady) -- note $1588 itself calls $02AB
-- internally as part of its own gate check (see 0x84's doc comment
-- above), a harmless double-read of the same byte, not a bug.
-- Implemented via EntityStructLayout.OPPOSITE_FACING (a plain lookup
-- table -- exactly as correct as reproducing $29E4's own bit trick,
-- since every input is one-hot) and an explicit dynamic-group
-- registration in ScriptRuntime.lua, same pattern as 0x80's own
-- (excluded from the generic ^ACTOR_ACTION_HANDLER_ADDRESS_ sweep for
-- the same reason).
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_81 = 0x15B7 -- group: dynamic, opposite-facing | 0xB0 (CRACKED)
--
-- 0xA4 ($01C1, TRACED, DELIBERATELY NOT WIRED, whole-corpus scan's
-- next untouched blocker after 0x86): PUSH HL / CALL $01CA / POP HL /
-- CALL $3727 / RET -- reaches the $02AB family through a new
-- indirection path: $01CA is PUSH AF / LD A,0x08 / JP $1ED7 (a
-- trampoline into the already-mapped $1ED7 bank-1 dispatcher,
-- selector 0x08), and selector 0x08's own code ($50F9) is a
-- substantial routine that eventually PUSH DE / CALL $02AB / CALL
-- $28F0 / POP DE / RET NZ -- a genuine conditional halt gated on
-- $02AB's result. A fifth confirmed sibling of the same known-hard
-- family, reached via yet another indirection layer -- needs the same
-- live player-entity WRAM state this project doesn't simulate. Left
-- deliberately unwired, no constant assigned.
--
-- 0x8A ($15FB, TRACED, DELIBERATELY NOT WIRED, direct user request to
-- decode the missing opcodes): CALL $1588 / RET NZ / CALL $120B /
-- CALL $3727 / RET -- a sixth confirmed sibling of the same $02AB
-- known-hard family, this time reached most directly of all of them:
-- $1588 itself is PUSH HL / CALL $02AB / POP HL / BIT 7,A / RET Z
-- (real halt gated straight on $02AB's own bit 7, no further
-- indirection) followed by a conditional leaf call ($2938-gated CALL
-- $02AB again then $2879, the same "queue an actor command" primitive
-- the actorAction family already uses) before returning NZ. The outer
-- wrapper's own RET NZ means: opcode 0x8A genuinely halts (never
-- reaches $3727) for as long as $02AB's own bit 7 stays set, only
-- continuing once it clears -- exactly the same shape (a live, per-
-- frame-reconfirmed gate on the player's own entity state) as
-- 0x80/0xEC/0xED/0xEE/0xA4 above. Left deliberately unwired for the
-- same reason as those -- no constant assigned.

-- 0xFC/0xFD ($27F9/$2820) -- structurally traced in task #83, the
-- "cursor commit" ambiguity resolved live in task #86 (same day) --
-- see StandardScriptHandlers.oneShotTriggerGate's own doc comment for
-- the full story and disassembly. Bytes:
--   $27F9: LD A,(0xD499) / CP 0 / CALL Z,$2819
--   $2801: LD A,0x01 / LD (0xD499),A
--   $2806: LD A,(0xC8E0) / CP 0 / RET NZ
--   $280C: LD A,(0xCEE8) / CP 0 / RET NZ
--   $2812: LD (0xD499),A / CALL $3727 / RET
--   $2819: LD A,(HL+) / PUSH AF / LD A,0x05 / JP $1F35   -- selector 5
--   $2820: (0xFD's own twin, identical shape, its own `CALL Z,$2840`
--     target uses `LD A,0x04 / JP $1F35` -- selector 4 instead of 5)
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC = 0x27F9 -- selector group 5
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FD = 0x2820 -- selector group 4

-- 0x41/0x45/0x4B/0x55/0x59 -- FOUND, direct follow-up to task #80
-- (shadow-run other scripts, not just the boss-defeat one, to find
-- further opcode stoppers). A full 1357-script census (every entry in
-- scriptPointerTable, 500-step budget each) surfaced ~99 distinct new
-- undecoded handler addresses across many scripts -- these 5 turned
-- out to be exact, byte-for-byte matches for already-known shapes
-- (verified by full disassembly, not guessed from the address alone):
--   $13C4 (0x41): CALL $28C2/ADD A,3/LD C,A/LD A,5/CALL $2879/RET
--   $13F4 (0x45): CALL $28C2/ADD A,3/LD C,A/LD A,0x1F/CALL $2879/RET
--   $1420 (0x4B): CALL $28C2/ADD A,3/LD C,A/LD A,0xF/CALL $2879/RET
--   $1468 (0x55): CALL $28C2/ADD A,4/LD C,A/LD A,0x1F/CALL $2879/RET
--   $147E (0x59): CALL $28C2/ADD A,4/LD C,A/CALL $123E/RET
-- The first 4 are standard Family-A `actorAction` members (auto-wired
-- by ScriptRuntime's generic loop); `0x59` is the SAME `$123E` chain
-- as `0x49`/`0x19` (reuses `actorSlotPosition`, wired explicitly like
-- those two).
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_41 = 0x13C4 -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_45 = 0x13F4 -- group 0x1F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_4B = 0x1420 -- group 0x0F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_55 = 0x1468 -- group 0x1F
ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_59 = 0x147E

-- 0x35/0x39/0x75 -- FOUND, direct continuation of task #82 (decode the
-- remaining opcodes from the whole-corpus census). Checked several
-- high-frequency stoppers from that census for shape before committing
-- to deep tracing -- these 3 turned out to be exact, byte-for-byte
-- matches for the already-fully-understood families (several other top
-- candidates from that same census -- 0x08/0x09/0x0A/0x0B/0xFC/0xFD --
-- turned out to be genuinely deep, multi-level mechanics instead; left
-- honestly undecoded, see events.md):
--   $1380 (0x35): CALL $28C2/ADD A,2/LD C,A/LD A,0x1F/CALL $2879/RET  (actorAction, group 0x1F)
--   $1396 (0x39): CALL $28C2/ADD A,2/LD C,A/CALL $123E/RET            (actorSlotPosition, same $123E chain)
--   $1550 (0x75): CALL $28C2/ADD A,6/LD C,A/LD A,0x1F/CALL $2879/RET  (actorAction, group 0x1F)
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_35 = 0x1380 -- group 0x1F
ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_39 = 0x1396
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_75 = 0x1550 -- group 0x1F

-- 5 more Family-A actorAction members (whole-corpus scan's next
-- untouched blocker, $1350) -- found right in the same $1338-$1380
-- neighborhood as 0x30/0x35 above, byte-for-byte the exact same shape
-- (CALL $28C2 / ADD A,<base> / LD C,A / LD A,<group> / CALL $2879 /
-- RET), just not previously given their own constants:
--   $1338 (0x2B): base 1, group 0x0F
--   $1350 (0x31): base 2, group 0x05
--   $135C (0x36): base 2, group 0x1C
--   $1368 (0x37): base 2, group 0x1D
--   $1374 (0x34): base 2, group 0x1E
-- No new Lua code needed -- the existing generic
-- ^ACTOR_ACTION_HANDLER_ADDRESS_ registration loop in ScriptRuntime
-- .lua picks these up automatically, same as every other Family-A member.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2B = 0x1338 -- group 0x0F
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_31 = 0x1350 -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_36 = 0x135C -- group 0x1C
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_37 = 0x1368 -- group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_34 = 0x1374 -- group 0x1E

-- `0xCB` ($392C) -- FOUND 2026-08-13, same census pass. Real bytes:
-- `LD A,(HL+) / LD D,A / LD A,(HL+) / LD E,A / LD BC,0xD633 / CALL
-- $3937 / RET` -- reads 2 real operand bytes (big-endian into DE, same
-- convention as `.chain()`), calls a leaf routine with a FIXED `BC`
-- and the operand pair, then unconditionally continues -- no branches,
-- no gating. Structurally IDENTICAL to the already-generic
-- `TWO_BYTE_COMMAND_HANDLER_ADDRESS`/`StandardScriptHandlers
-- .twoByteCommand` shape, just a DIFFERENT real target address (this
-- project's own `$3937` leaf is untraced -- HONEST SCOPE, same
-- "interpreter doesn't render, it calls back" convention as every
-- other opaque-leaf handler here). Reuses the `.twoByteCommand`
-- factory directly with its OWN dedicated `ctx` callback (NOT the same
-- callback as the real `TWO_BYTE_COMMAND_HANDLER_ADDRESS`, since that
-- targets a different real leaf routine with a different real effect).
ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB = 0x392C

-- 0x84 ($15E3): byte-identical shape to 0x85 above (CALL $1588 / RET
-- NZ / LD A,0x04 / LD C,0xFF / CALL $2879 / RET) -- same $1588 gate
-- (WRAM $C240 bit 7), fixed group 0x04 instead of 0x85's own 0x08.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_84 = 0x15E3 -- group 0x04, $1588 gate

-- 0xA0 ($0194): PUSH HL / CALL $019D / POP HL / CALL $3727 / RET -- no
-- operand bytes, an undecoded fixed helper call, always continues (no
-- conditional branch). Reuses triggerEvent directly.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_A0 = 0x0194

-- Two more structurally-traced, honestly not wired opcodes found this
-- round:
-- 0x90 ($1606): CALL $28C2 / JR NZ,+0x54 / ... -- unlike every other
-- Family-A member, this one branches directly on $28C2's result (a
-- conditional halt or alternate path, not just an action-code
-- adjustment) -- a genuinely different shape, not assumed to match
-- the rest of the family.
-- 0xBA ($0EB2): touches WRAM $D499 -- the same already-flagged
-- palette/fade-counter family behind 0xFC/0xFD/0xBA-adjacent opcodes
-- -- not re-investigated separately.
--
-- UPDATE (whole-corpus scan, a deeper re-investigation): the note
-- above was itself imprecise -- 0xBA's $D499 usage is unrelated to the
-- 0xBC/0xBD/0xBE palette-fade family (different WRAM role entirely).
-- Full re-trace: $0EB2 is a $D499-driven 2-step mini state machine
-- (step-table base $0ECA, the same $2B70-multiply-and-jump shape as
-- $4130/$4180): step0 ($0ECE) allocates an entity slot via the
-- already-known $0A74 primitive (slot hint C=7), stores it in $D49A,
-- calls $2F03, advances to step1; step1 ($0EEF) calls $2ED3 (RET NZ =
-- halt if not ready), else despawns the allocated slot via the
-- already-known $0AE3 primitive and resets. Both $2F03 and $2ED3 were
-- traced further this pass: both resolve to cases of the already-
-- mapped $1ED7 bank-1 dispatcher (see rom-map.md's "Consolidated
-- reference" section) -- $2F03 = case 0x26 (the already-understood
-- $CEF0 sound-trigger-queue producer, $5C9F); $2ED3 = case 0x1D, a
-- further $CEF0-queue scan with a per-value jump-table dispatch (CALL
-- $2B70 into a table at $52CD) whose individual targets remain
-- untraced. Final determination: genuinely known-hard, not because
-- the mechanism is opaque (it's traced, decodable ROM code, unlike
-- the $02AB/$1142 families) but because fully resolving "ready"
-- requires tracing the $52CD sub-table's targets and simulating an
-- entity/OAM lifecycle this project has no live model for. Left
-- deliberately unwired; a bounded, reusable next thread (trace
-- $52CD's targets) for whoever picks this back up.

-- Round 6 (same "do 2 first" pass, a 5th re-scan): 3 more Family-A/B
-- opcodes and 1 more always-continuing shape reusing soundParam.
-- Script counts now consistently 10-14 -- confirms the diminishing-
-- returns assessment below.
--   0x28 ($1318): Family B, base 0x01
--   0x46 ($13D0): Family A, base 0x03, group 0x1C
--   0x58 ($1474): Family B, base 0x04
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_28 = 0x1318
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_46 = 0x13D0 -- group 0x1C
ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_58 = 0x1474

-- 0x49 ($140A): FOUND live, direct instruction to start an interpreter
-- -> a live ScriptRuntime shadow run against the boss-defeat script
-- correctly halted on this exact opcode (a genuinely undecoded handler
-- address, per this project's "no silent fallbacks" rule) rather than
-- misreading past it -- the direct trigger for decoding it. Full
-- disassembly:
--   $140A: CALL $28C2 / ADD A,3 / LD C,A / CALL $123E / RET
--   $123E: PUSH HL / PUSH BC / CALL $289B (the already-known WRAM-
--     $C5A0 8-byte OR-reduce "any nonzero?" helper, see QUEUED_ACTION_
--     HANDLER_ADDRESS_38's own doc comment) / POP BC / POP HL / RET NZ
--     -- same halt gate as the queued-action family, checked before
--     any operand byte is read.
--   Once ready: LD A,(HL+) [[operand byte 1]] / INC A / ADD A,A x3
--     [[A = (byte1+1)*8]] / LD E,A -- then LD A,(HL+) [[operand byte
--     2]] / INC A / INC A / ADD A,A x3 [[A = (byte2+2)*8]] / LD D,A --
--     DE = the transformed pair. This is the first member of the
--     whole actor-action/queued-action opcode family found that
--     consumes any operand bytes -- every other sibling (0x10-0x85,
--     0x18-0x78) has zero.
--   CALL $28AA -- a $1F35 trampoline, LD A,0x0D / JP $1F35 -- tail-
--     dispatches to selector 0x0D's own already-mapped target, $4AF9
--     (see events.md's "system connectivity" writeup for how that
--     table was fully mapped), passing DE (the transformed operand
--     pair) and C (the $28C2-derived "actor slot index" from $140A's
--     prologue) as parameters.
--   $4AF9: computes HL = $C4E0 + C*24 (the same per-slot "actor table"
--     stride this whole subsystem shares -- see events.md), LD C,(HL)
--     [[reads that slot's first byte, a new C]], then CALL $0C99 with
--     DE/C, then OR 0x10 on the result and CALLs $0611 -- the same
--     low-level routine selector 0x0B's own trampoline calls ($0611 --
--     a concrete new cross-link between selectors 0x0D and 0x0B,
--     found as a side effect of this trace). RET.
--   Back in $123E: CALL $3727 (fetch next opcode) / RET.
-- CLOSED (task #85 follow-up, direct instruction to go ahead): $0C99
-- and $0611 -- the leaf action, left undecoded above -- are now both
-- disassembled. $0C99: HL = $C200 + C*16 (the already-known 20-slot
-- entity struct EntityStructLayout.lua already models), A = *(HL) --
-- reads that entity's struct byte 0. $0611: bounds-checks the slot
-- index against 20 (CP 0x14 / RET NC, an exact match to
-- EntityStructLayout.SLOT_COUNT), writes the new state byte (the OR
-- 0x10-modified value from $4AF9) into that same entity's struct byte
-- 0, clears bit 7, then continues into the already-traced OAM-commit
-- chain this project fully disassembled for the gate-creature sprite
-- investigation this same session ($0651 -> CALL $088A, see
-- rom_profiles.lua's enemyDescent doc comment and events.md's "root
-- cause of the 16px gap mystery" section). Decisive conclusion: opcode
-- 0x49/0x19's leaf action is "write a new state byte into entity slot
-- C's own struct, then commit its OAM/position" -- a genuine sprite/
-- position update primitive, strengthening (not just hypothesizing)
-- the (n+K)*8 tile-to-pixel transform's plausibility, though the
-- transform's exact consumer inside the OAM-commit chain still isn't
-- traced byte-for-byte. StandardScriptHandlers.actorSlotPosition is
-- unchanged (still correctly exposes the leaf as an opaque callback)
-- -- this is documentation-only, closing an honest gap.
ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49 = 0x140A

-- 0x19 ($12AE): FOUND, direct continuation of Milestone 7 -- a live
-- ScriptRuntime shadow run against the boss-defeat script halted here
-- next (opcode 0x19 genuinely undecoded), same "no silent fallbacks"
-- discipline as 0x49 above. Full disassembly:
--   $12AE: CALL $28C2 / ADD A,0x00 / LD C,A / CALL $123E / RET
-- This is the exact same $123E chain already fully decoded and
-- documented above for opcode 0x49 -- same WRAM-$C5A0 gate-before-
-- fetch, same 2-operand-byte (n+K)*8 transform, same $1F35 selector
-- 0x0D -> $4AF9 dispatch. The only difference from 0x49 is the
-- trampoline's base (ADD A,0x00 here vs ADD A,3 for 0x49), which only
-- changes the derived actor-slot index (C) passed into $123E -- not
-- the mechanism. Reuses StandardScriptHandlers.actorSlotPosition
-- directly, no new Lua handler needed.
ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_19 = 0x12AE

-- 0xC4 ($39A3): LD A,(HL+) / PUSH HL / CALL $312F / LD B,9 / CALL
-- $3D10 / POP HL / RET -- one operand byte, no conditional branch
-- visible, relies on $3D10 to call $3727 internally (the same pattern
-- already confirmed for opcode 0xF6 above). Reuses soundParam directly
-- (identical shape: 1 operand byte, callback, continue -- the specific
-- helper/HRAM register it invokes doesn't matter to this project's
-- implementation).
ScriptOpcodeTable.SOUND_PARAM_HANDLER_ADDRESS_C4 = 0x39A3

-- Three more opcodes found this round, structurally traced, honestly
-- not wired:
-- 0x39 ($1396): CALL $28C2 / ADD A,2 / LD C,A / CALL $123E / RET --
-- looks like the Family A/B shape but calls a third, different helper
-- ($123E, neither $2879 nor $2859) -- not assumed to share their same
-- gating condition without independent verification, not chased down
-- this pass.
-- 0xBC ($10DC): arithmetic on WRAM $D499/$D49A -- the same already-
-- flagged palette/fade-counter family behind 0xFC/0xFD.
-- 0xCB ($392C): reads a big-endian 16-bit operand (LD D,A ... LD E,A,
-- no byte-swap trick), then CALL $3937 / RET with no visible CALL
-- $3727 -- unlike 0xF6/0xC4 above, not confirmed whether $3937 calls
-- $3727 internally (making this either another always-continuing
-- opcode, or a genuine, undiscovered halt) -- left unresolved rather
-- than guessed.

-- Opcodes 0x09/0x0A (ROM $3390/$33B0) -- CLOSED (direct follow-up to
-- disassemble $33CF -- this session's top remaining combined blocker
-- on the whole-corpus scan, 72 scripts). Both share byte-for-byte the
-- same shape (LD DE,<fixed pointer> / cache into $D891/$D890 / LD
-- A,<fixed constant> / LD ($D870),A / CALL $33CF), just different
-- fixed constants -- 0x0A uses 0xD6C5/0x2B, 0x09 uses 0xD6E9/0x07. See
-- StandardScriptHandlers.timerListSearch's own doc comment for the
-- complete disassembly of $33CF/$3411/$3430/$343F -- the answer to
-- this project's long-standing open question of what $33CF does with
-- this WRAM-queued pointer+type pair: a WRAM-array increment/
-- decrement pair, then a zero-terminated list-search structurally
-- identical to opcode 0x08's own zeroTerminatedFlagList.
ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_09 = 0x3390
ScriptOpcodeTable.TIMER_LIST_SEARCH_HANDLER_ADDRESS_0A = 0x33B0

-- Opcode 0x00's own handler ($3297) -- resolved, direct instruction to
-- solve "1" (the single largest remaining blocker from this session's
-- opcode-frequency scan, 275/1357 scripts). Full byte-for-byte
-- disassembly (see events.md's "Opcode 0x00, resolved" section for
-- the complete chain):
--   LD A,($D874) / BIT 0,A / RET NZ        ; halt #1: a real, general
--                                            flag byte's bit 0 (bit 1
--                                            of the SAME byte is the
--                                            already-known 0xDC/0xDD
--                                            target). RESOLVED
--                                            2026-08-14 (task #86, a
--                                            real live trace of the
--                                            boss-defeat script): a
--                                            genuine actor-command
--                                            SYNCHRONIZATION BARRIER --
--                                            set by $3257 (part of the
--                                            already-known $31AD
--                                            script-activation cluster)
--                                            whenever the $C5A0 8-slot
--                                            actor-command table (see
--                                            task #85's own $4B70
--                                            finding) still has
--                                            genuinely-pending entries
--                                            (checked via $28B0 -> the
--                                            already-known $1F35
--                                            family's own selector
--                                            0x0E -> $4B4F). No live
--                                            actor-command-completion
--                                            simulation exists in this
--                                            project -- an honest,
--                                            known gap, not a guess.
--   LD A,($D865) / AND A / JR NZ,<queue-not-empty>
--   ; $D865 == 0 (queue empty):
--   XOR A / LD ($D85A),A                    ; re-arms opcode 0 itself
--                                            for the next tick (this
--                                            project's halt semantics
--                                            already do this
--                                            implicitly -- no explicit
--                                            $D85A write needed here)
--   <real $D86E -> $C0A0 copy, $C0A1/$C0A2 bit-clears>  ; HYPOTHESIS,
--                                            not modeled -- exposed as
--                                            an optional callback
--   RET                                      ; halt #2
--   ; $D865 != 0 (queue not empty):
--   CALL $3705                               ; pop -- see
--                                            ScriptContinuationQueue.lua
--   LD A,B / CP 3 / RET Z                    ; halt #3: popped B==3
--                                            (the exact value opcode
--                                            0x03's own pushes use)
--   CP 2 / JR NZ,<halt #4, bare RET>          ; halt #4: popped B is
--                                            neither 2 nor 3
--   ; B==2 (the exact value opcode 0x02 CHAIN's own pushes use):
--   ; redirect the persistent cursor to the popped DE, then continue
--   <persistent cursor = popped DE> / CALL $3727
--   RET
-- Confirmed producers of the queue this pops from: opcode 0x02 (CHAIN,
-- always pushes B=2 -- every CHAIN is a "jump away, remember to come
-- back here" bookmark) and opcode 0x03 (always pushes B=3 -- every use
-- just makes a later opcode-0x00 dispatch halt once, consuming the
-- entry, for a reason this pass didn't chase further).
--
-- RETRACTED (direct continuation of task #86, a direct live re-trace
-- of the exact same courtyard_boss_defeated block this doc comment's
-- "halt #1" claim above was based on): re-ran the live trace with a
-- direct watchpoint on $D874 itself (the earlier pass inferred the
-- bit-0 gate indirectly, from $D85A never being rewritten during the
-- block -- never actually watched $D874's own bit 0 changing).
-- Result: bit 0 of $D874 never changes at all across the entire
-- ~200,000-step block (only bits 1 and 7 do, both after the block
-- already starts releasing) -- so "halt #1" above isn't what gates
-- this specific occurrence. Also directly watched the $C5A0 8-slot
-- known-list this explanation depends on: it stays all-zero for the
-- entire window (before, during, and after) -- selector 0x0E's own
-- entry ($4B4F) is reached (103 times), but its per-entry helper
-- ($4B19) is never reached (0 times), because the scan never finds a
-- nonzero byte to act on. The whole $C5A0/actor-command-queue
-- explanation for "halt #1" doesn't hold up under direct live re-
-- verification.
--
-- What does correlate with the block's actual end (step 221345 of
-- 400,000, matching the original trace's ~200,000-step figure -- the
-- block duration itself is real and reproduced, just not this
-- specific cause): a write of $D874 bit 7, from $31AD -- this
-- project's own already-fully-understood (task #85) cross-actor
-- dispatch mechanism, not a new routine. $31AD's own gate (BIT
-- 1,(HL) on $C0A1 / RET NZ) was also live-watched: an unrelated
-- periodic flicker/tick pulses $C0A1 bit 1 on and off constantly
-- throughout (bank-0 $080C/$0818, plausibly a cosmetic animation
-- timer, not investigated further), but the pulse timing itself
-- doesn't explain why $31AD only succeeds once ~200,000 steps in --
-- a sharpened but still-open question (this project's own already-
-- published "genuinely depends on passage of game time" conclusion
-- still stands, just now pointing at $31AD's own trigger condition
-- instead of the $C5A0 queue). See events.md's own dated entry.
--
-- CLOSED FOR REAL (same day, direct continuation): traced $31AD's
-- single hit (there is exactly one across the whole 400,000-step
-- window) back through its call chain, live-verifying every link:
--   $31AD (step 221303) <- called from inside $24A7's own body (step
--   221259) -- a previously-untraced helper (an earlier "connecting
--   systems" pass had flagged $24A7 as one of the still-open $1F35-
--   selector leaf helpers) that reads the player's current facing
--   nibble (CALL $02AB / AND 0x0F, the same already-cracked accessor
--   from task 10) and combines it with a small per-block constant to
--   select which $C3F0/$C3FE/$C3FF-indexed script to activate via
--   $31AD -- a concrete structural clue for task #85's still-open
--   "what is that record's general schema" question (this specific
--   block reads a pointer from $C3FE/$C3FF, dereferences it, offsets
--   by 0-2 bytes depending on which of 5 sibling blocks runs, then
--   further indexes by the player's facing).
--   $24A7 <- called from exactly one static site, $1F35 selector
--   0x13's own body (file $CC30): CALL $4BE0 / RET NZ / CALL $24A7 /
--   RET.
--   Selector 0x13 itself fires 71 times across the trace, at regular
--   ~2500-3500-step intervals (a periodic background tick) -- but only
--   on the last of those 71 ticks does it proceed past RET NZ to
--   reach $24A7 at all.
--   $4BE0's own full tail, fully disassembled: it recomputes a
--   classified-actor count (the same PARAM2 high-nibble 0x90/0xB0/
--   0x10 scan already documented) and compares it against a cached
--   previous count at $C5AF. It returns "ready" (Z) only on the
--   specific tick where the count transitions from nonzero to exactly
--   0 (plus one further gate, CALL $28C2, not traced further) -- an
--   edge-triggered completion signal, not a level check; every other
--   tick returns "busy" (NZ) unconditionally.
--   Live-confirmed the transition directly: $C5AF sits at 0x01 from
--   the checkpoint through the entire block, then flips to 0x00 at
--   step 221251 -- immediately before $24A7/$31AD fire in sequence.
--   Exact match.
--
-- Decisive, now-closed conclusion: the boss-defeat block genuinely is
-- "wait for actor cleanup," as earlier sessions always suspected --
-- just via a different, previously-undocumented mechanism than either
-- prior hypothesis (not the $C5A0/$4B70 actor-command queue, not a
-- raw $D874-bit0 flag): a periodic ($1F35 selector 0x13, ~71 ticks)
-- edge-triggered "did my classified-actor count just drop to 0"
-- detector ($4BE0/$C5AF), gating a facing-driven story-activation
-- call ($24A7 -> $31AD). The ~1.7-second delay is the boss's own
-- entity slot genuinely taking that long to finish despawning after
-- its HP hits the dead sentinel -- not an arbitrary timer, and not
-- (contrary to this doc's own retracted claim above) the actor-
-- command queue.
--
-- $3297's own body, fully disassembled for the first time (task #149,
-- generalizing the one-shot $31AD trigger into a re-armable one): LD
-- A,($D874) / BIT 0,A / RET NZ (the already-modeled isBlocked gate) /
-- LD A,($D865) / AND A / JR NZ,<queue-has-content path>. $D865 is a
-- previously undocumented WRAM cell -- 0 means the queue is genuinely
-- empty (this project's own queue:isEmpty() already models the
-- observable effect correctly; this is the underlying byte). The
-- genuinely-empty path: XOR A / LD ($D85A),A (clears the current-
-- opcode byte) / LD A,($D86E) / LD ($C0A0),A (restores a saved value)
-- / then unconditionally clears bits 1, 2, and 3 of both $C0A1 and
-- $C0A2 / RET.
--
-- This is the "re-arm" event $31AD (this project's already-documented
-- cross-actor dispatcher, tasks #85/#111) depends on. Full
-- disassembly of $31AD itself: it opens with PUSH HL / LD HL,$C0A1 /
-- BIT 1,(HL) / POP HL / RET NZ -- $31AD self-gates against re-firing
-- via bit 1 of $C0A1, and is a genuine no-op while that bit is set.
-- Its own completion (after computing a new script cursor via a
-- 0x0B/0x04/0x08 special-case branch already independently decoded by
-- task #52, correcting it via the already-known $3c4f, committing it
-- to $D8B7/$D8B6, fetching via $3727, and popping the bank via $2a0a)
-- sets bits 2 and 1 of both $C0A1 and $C0A2 -- re-gating itself. So
-- $31AD isn't hardware one-shot in the sense of "fires at most once,
-- ever" -- it fires at most once per busy period, and the ROM itself
-- clears that gate at the exact same moment $3297's own "queue
-- genuinely empty" halt above already happens (matching
-- StandardScriptHandlers.queueGate's own already-modeled kind ==
-- "halted" state, opcode byte 0x00). src/scripting/
-- BossSequenceInterpreter.lua's own :rearm() method (task #149) uses
-- exactly this decisive precondition, not a guess.
--
-- Live cross-check: a $D8B6/$D8B7 write watchpoint across checkpoints
-- .courtyard_boss_defeated() found a second commit (PC $31f2/$31f6,
-- inside $31AD's own tail above, bank 0) at step 221397 -- matching
-- task #86's own already-documented $C5AF edge-transition timing
-- (step 221251) almost exactly, very likely the same event task #86
-- already found the trigger condition for, now with $31AD's internal
-- logic fully decoded too. It commits the exact same entry point
-- (bank=13, $470F) this module's own START_BANK/START_CPU_ADDRESS
-- already use for the first invocation -- honestly flagged as not yet
-- explained why the ROM reinvokes the exact same entry a second time
-- -- see events.md's own dated task #149 entry for the full trail.
ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS = 0x3297

-- 0x08 ($3370) -- structurally traced in task #83, its per-item leaf
-- ($35EF/$3602) fully live-confirmed the same day, and its "list
-- exhausted" continuation finally pinned down live in task #86 (this
-- was the concrete, immediate blocker for BossSequenceInterpreter).
-- See StandardScriptHandlers.zeroTerminatedFlagList's own doc comment
-- for the full disassembly, the corrected "not a WRAM block-clear"
-- finding, and the honest scope of what remains unmodeled.
ScriptOpcodeTable.ACTOR_FLAG_LIST_HANDLER_ADDRESS = 0x3370

-- 0x29 ($1322) -- FOUND, task #86, live shadow-run's next stopper
-- against BossSequenceInterpreter itself (the first opcode encountered
-- past the newly-wired 0x08, deep enough into the sequence that the
-- earlier whole-corpus census hadn't surfaced it at all). Bytes: CALL
-- $28C2 / ADD A,1 / LD C,A / CALL $123E / RET -- the same $123E
-- mechanism already known from 0x19/0x39/0x49/0x59, base=1.
ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_29 = 0x1322

-- 0xD4/0xD6/0xD8 ($3AA8/$3ABA/$3ACC) -- FOUND, task #86, live shadow-
-- run's next stopper past 0x29. See StandardScriptHandlers
-- .gatedByteLeafCommand's own doc comment for the full disassembly and
-- the honest scope of what's not modeled (the $D86F-bit-1-set path,
-- $3ADE).
ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D4 = 0x3AA8
ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D6 = 0x3ABA
ScriptOpcodeTable.GATED_BYTE_LEAF_HANDLER_ADDRESS_D8 = 0x3ACC

-- 0xD5/0xD7/0xD9 ($3B3A/$3B45/$3B50) -- FOUND, same pass, immediately
-- adjacent to 0xD4/0xD6/0xD8. See StandardScriptHandlers
-- .byteLeafCommand's own doc comment: the same shape, but without the
-- $D86F gate check.
ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D5 = 0x3B3A
ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D7 = 0x3B45
ScriptOpcodeTable.BYTE_LEAF_HANDLER_ADDRESS_D9 = 0x3B50

-- 0xE3 ($0FD5) -- FOUND, task #86, same live shadow-run. Bytes: PUSH
-- HL / LD A,0x08 / CALL $22FE / POP HL / CALL $3727 / RET -- byte-for-
-- byte the same "no operand, fixed constant to a helper, always
-- continues" shape as TRIGGER_EVENT_HANDLER_ADDRESS/_E0/_E4/_A0 above,
-- just a different helper ($22FE vs $235B) and constant (0x08).
-- Reuses StandardScriptHandlers.triggerEvent directly -- no new Lua
-- code needed.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E3 = 0x0FD5

-- 0xE7 ($0FA9, whole-corpus scan's next untouched blocker after 0xC8):
-- byte-for-byte the same shape as 0xE3 above (PUSH HL / LD A,0x02 /
-- CALL $22FE / POP HL / CALL $3727 / RET) -- the same $22FE helper
-- 0xE1 already uses, just its own fixed constant (0x02). Reuses
-- StandardScriptHandlers.triggerEvent directly via the existing
-- generic ^TRIGGER_EVENT_HANDLER_ADDRESS registration loop.
ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E7 = 0x0FA9 -- group 0x02, via $22FE

-- 0xC9/0xCA ($3916/$3921) -- FOUND, task #86, same live shadow-run,
-- immediately adjacent to the already-wired 0xCB ($392C). Byte-for-
-- byte the same shape (2 operand bytes read big-endian into DE, fixed
-- BC, CALL $3937, always continues), just a different fixed BC each:
-- 0xC9 -> BC=0xD613, 0xCA -> BC=0xD623 (0xCB's own is BC=0xD633) -- an
-- evenly-spaced 3-member family ($D613/$D623/$D633, stride 0x10).
-- Reuses .twoByteCommand with their own dedicated ctx callbacks, same
-- reasoning as 0xCB's own doc comment.
ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_C9 = 0x3916
ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CA = 0x3921

-- 0xF3/0xF4 ($11CE/$11B7) -- FOUND, task #86, same live shadow-run.
-- See StandardScriptHandlers.peekTwoByteGate's own doc comment for the
-- full, carefully-decoded disassembly (a genuinely unusual shape:
-- peeks 2 bytes without consuming them, gates on WRAM $D499, and
-- re-reads the same 2 bytes as the next opcode once clear).
--
-- 0xF3's own release condition fully decoded (direct continuation of
-- the palette-fade-family investigation -- 0xF3's handler
-- unconditionally calls a $1ED7 selector 0x10 dispatch every
-- invocation, gated or not, before its own $D499==0 check): selector
-- 0x10's own target, $414C, is another $D499-indexed jump table (same
-- $2B70 shape as opcode 0xBA's own already-documented $0EB2), table
-- base $4158, cross-validated the same way the outer $1ED7 table
-- itself was. Exactly 6 entries (index 6+ reads into unrelated code,
-- confirmed by nonsense target addresses) -- a finite 6-phase state
-- machine sharing $D499 as a phase counter, different semantics than
-- the palette-fade opcodes' own 0-10 outer-pacing use of the same
-- cell (same "one hardware byte, several unrelated consumers,
-- sequenced not concurrent" pattern already established for 0xFB/
-- 0xBF/0xBA):
--   phase 0 ($41CA): $D49A=0, $D499++ (0->1), unconditional.
--   phase 1 ($4477): checks the already-modeled dual gate $C8E0/$CEE8
--     (the same gate 0xFC/0xFD/0xE8-0xEB use -- see ctx
--     .isTriggerEventGateClear) -- only $D499++ (1->2) once both cells
--     read 0; otherwise returns without incrementing (halt, re-dispatches).
--   phase 2 ($4387): calls $26DC (the already-known transition-dispatch
--     entry, see rom-map.md's "$04138→$02B70→$04395→$026DC" chain) and
--     $04A4, then $D499++ (2->3) unconditional.
--   phase 3 ($4477 again): the same dual-gate check as phase 1,
--     $D499++ (3->4) once clear.
--   phase 4 ($43EE): OAM/sprite-position work (calls $0375/$44A5/
--     $28C2/$289B/$28AA, several already-known helpers from the
--     actor-readiness family), then $D499++ (4->5) unconditional.
--   phase 5 ($448C): final cleanup call, then $D499=0 (unconditional
--     reset) -- this call's own caller-side check ($D499==0, right
--     after $1ED7 returns) now succeeds immediately, releasing via
--     CALL $3727 on this exact tick.
-- Crucially for cursor tracking: none of these 6 phases ever touch the
-- script-stream HL (it's cached into $C0B4/$C0B5 by $1ED7's prologue
-- and restored verbatim in its epilogue, regardless of what any
-- individual phase does to its own local HL) -- so this state machine
-- is "script-stream-inert," just per-frame pacing plus currently
-- unmodeled, cosmetic OAM/transition side effects, matching the same
-- "paced correctly, cosmetic writes left optional" precedent as
-- 0xFB/0xBF/0xBC/0xBD/0xBE. See StandardScriptHandlers
-- .paletteFadeCompletionGate's own doc comment for the Lua port
-- (wired for 0xF3 specifically -- 0xF4's own selector, 0x0F, remains
-- untraced, so it keeps the old, honestly-unwired ctx
-- .isPeekGateClear default).
ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3 = 0x11CE
ScriptOpcodeTable.PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F4 = 0x11B7

-- 0xB8/0xB9 ($1178/$1186) -- FOUND, first pass of the newly-rebuilt
-- whole-corpus shadow-run scan (docs/reverse-engineering/events.md's
-- own dated entry has the full ranking): 0xB8 alone blocks 25 scripts,
-- the single highest-count clean structural match among the top 40
-- most-blocking undecoded handlers (0xB9 never independently halts a
-- script in this corpus -- checked, not assumed to match). See
-- StandardScriptHandlers.wramBitCommand's own doc comment for the
-- full disassembly.
ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B8 = 0x1178
ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9 = 0x1186

-- 0x0B/0x0C ($344E/$345B) -- CLOSED, direct follow-up to 0x09/0x0A --
-- this session's next-largest combined blocker (71 scripts). Verified
-- structure: genuinely different from every other "list" shape
-- decoded so far -- the list searched is an in-line sequence of
-- [idByte, payload..., 0] entries living directly in the script
-- stream itself, matched against an external WRAM byte ($D871), gated
-- by bit 7 of a second WRAM cell ($D873) with opposite polarity
-- between the two opcodes. See StandardScriptHandlers.runListSearch's
-- own doc comment for the complete disassembly.
ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0B = 0x344E
ScriptOpcodeTable.RUN_LIST_SEARCH_HANDLER_ADDRESS_0C = 0x345B

-- 0xFB/0xBF ($0E8C/$0FE0) -- CLOSED, direct follow-up to keep tackling
-- the remaining blockers: the next 2 highest-ranked genuinely
-- untouched blockers (33 and 29 scripts) after the known-hard
-- $15A4/$10DC pair. Both are "periodic cosmetic WRAM-effect" leaves
-- sharing one structural shape (a private phase counter driving a
-- per-call WRAM write, wrapping modulo a fixed period, consuming
-- exactly one extra script-stream byte via the already-known $3727
-- fetch primitive on wrap) -- see StandardScriptHandlers
-- .periodicWramEffect's own doc comment for the shared mechanism and
-- .waveOffsetEffect/.colorPulseEffect for each opcode's own per-tick
-- WRAM write. 0xBF is also one of the boss-defeat script's own
-- opcodes (see ScriptRuntime.lua's top-of-file "HONEST SCOPE" note).
ScriptOpcodeTable.WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB = 0x0E8C
ScriptOpcodeTable.COLOR_PULSE_EFFECT_HANDLER_ADDRESS_BF = 0x0FE0

-- 0x88/0x89 ($0153/$015E) -- CLOSED, direct follow-up to consolidate
-- discoveries and build them in -- closing the boss-defeat script's
-- remaining opcodes: 0x88 alone is the whole-corpus scan's rank-13
-- blocker (13 scripts), and 0x88/0x89 are both live-confirmed opcodes
-- of the boss-defeat script itself (events.md's "every opcode it
-- actually uses, decoded" section). Fully-traced shape: writes a
-- fixed per-opcode constant into the player entity's "TYPE" field via
-- a shared helper ($02A5/$02AC -> $0C5D), then consumes one (genuinely
-- unused) padding byte. See StandardScriptHandlers
-- .playerEntityTypeWrite's own doc comment for the complete disassembly.
ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_88 = 0x0153
ScriptOpcodeTable.PLAYER_ENTITY_TYPE_WRITE_HANDLER_ADDRESS_89 = 0x015E

-- 0x8F ($168E) -- CLOSED, direct follow-up asking for the biggest
-- quick win -> whole-corpus scan's rank-3 blocker, 33 scripts): a
-- conditional halt on the same $C5A0 8-slot actor-command table this
-- session already traced twice (task #85's $4B70 enqueue finding;
-- task #86's $4B4F "any pending entries" poll, opcode 0x00's own
-- condition) -- a plain "wait until the raw table is all-zero" gate,
-- then consumes one script-stream byte. See StandardScriptHandlers
-- .actorCommandQueueEmptyGate's own doc comment for the complete
-- disassembly.
ScriptOpcodeTable.ACTOR_COMMAND_QUEUE_EMPTY_GATE_HANDLER_ADDRESS_8F = 0x168E

-- 0x90/0x91/0x94-0x99 ($1606 cluster) -- CLOSED, direct follow-up to
-- keep going with the top blockers -> whole-corpus scan's new rank-3
-- blocker after 0x8F's closure, 31 scripts. A self-caught correction:
-- this cluster looks like more members of the already-known
-- actorAction/queuedAction/actorSlotPosition families (shares the
-- exact same $28C2 "actor-record-7 ready" gate and the exact same
-- $2879/$2859/$123E leaves) -- but a direct comparison against a
-- sibling routine ($28D5, CALL $28C2 / RET NZ, a true halt) found this
-- cluster's own not-ready behavior is genuinely different: a soft
-- skip-and-continue via the $3727/INC HL fetch-and-discard convention,
-- never a halt. See StandardScriptHandlers.actorActionOrSkip/
-- .queuedActionOrSkip/.actorSlotPositionOrSkip's own doc comments for
-- the complete disassembly and evidence this is a deliberate design
-- difference, not a modeling inconsistency.
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_90 = 0x1606 -- group 0x04
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_91 = 0x1613 -- group 0x05
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_96 = 0x1620 -- group 0x1C
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_97 = 0x162D -- group 0x1D
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_94 = 0x163A -- group 0x1E
ScriptOpcodeTable.ACTOR_ACTION_OR_SKIP_HANDLER_ADDRESS_95 = 0x1647 -- group 0x1F
ScriptOpcodeTable.QUEUED_ACTION_OR_SKIP_HANDLER_ADDRESS_98 = 0x1654
ScriptOpcodeTable.ACTOR_SLOT_POSITION_OR_SKIP_HANDLER_ADDRESS_99 = 0x1663

-- UPDATE 2026-08-14, task 10 ("$02AB wirklich lösen"): the `$02AB`
-- part of these 3 opcodes' own real dependency is NOW fully
-- understood (see `ACTOR_ACTION_HANDLER_ADDRESS_80`'s own doc
-- comment above and `EntityStructLayout.PLAYER_FACING_BIT` -- `$02AB`
-- is a plain read of the player's own facing-direction byte, and these
-- 3 opcodes mask it the same way (AND 0x0F) before use). Full re-
-- disassembly confirms the parameters $3213 (the downstream leaf)
-- receives: A = the player's facing bits (0-15, same computation 0x80
-- now uses), C = a fixed 0xC9 (the same "attack" command byte from the
-- bank-4 entity-command dispatcher, see combat.md's own P1 entries),
-- HL = the dereferenced cross-actor pointer (task #85's own $C3FE/
-- $C3FF finding, offset +0/+1/+2 for 0xEC/0xED/0xEE respectively).
-- Still genuinely not closed: unlike 0x80 (which never touches the
-- $C3F0-staged dynamic-bank/cross-actor mechanism at all), these 3
-- opcodes dereference it first, before ever reaching the now-
-- understood $02AB computation -- and that mechanism (which content
-- gets staged into $C3F0/$C3FE/$C3FF for a given scene) remains a
-- separate, still-unmodeled gap (task #85's own already-documented
-- scope). Left deliberately unwired for that reason now, not because
-- $02AB itself is unknowable -- a precise narrowing of the remaining
-- gap, not a full closure.
--
-- 0xEC/0xED/0xEE -- TRACED, DELIBERATELY NOT WIRED (task to
-- successively work through all remaining blockers -> whole-corpus
-- scan's rank-3 blocker). SELF-CAUGHT CORRECTION (same pass): this doc
-- comment originally recorded these 3 opcodes' handler addresses as
-- $24D4/$24F9/$251F -- wrong, one level of indirection off. Cross-
-- checked directly against ScriptOpcodeTable.decode's own output: the
-- real opcode-table addresses are $0E73/$0E77/$0E7B (immediately
-- before TILE_CURSOR_SET_HANDLER_ADDRESS_EF's own $0E7F, below) --
-- each a tiny, literal 3-byte CALL $24D4|$24F9|$251F / RET trampoline.
-- $24D4/$24F9/$251F are the trampolines' own call targets, not the
-- opcode-table entries themselves; this is exactly why $0E73 itself
-- (not $24D4) kept showing up as the whole-corpus scan's own undecoded
-- rank-3 blocker even after this family was first "closed" in an
-- earlier pass -- nothing had actually been registered at the real
-- address. The underlying finding is unaffected by the correction:
-- each of the 3 trampoline targets switches to $C3F0's dynamic bank,
-- dereferences the same $C3FE/$C3FF cross-actor pointer this session's
-- task #85 fully mapped, dereferences one more level (+0/+1/+2 bytes
-- respectively -- the only difference between the 3 opcodes), then
-- calls $02AB -- the exact same already-known-hard leaf behind opcode
-- 0x80/$15A4 (ACTOR_ACTION_HANDLER_ADDRESS_80 below), masking its
-- result with AND 0x0F just like 0x80's own group computation. A third
-- confirmed sibling of the same known-hard family: needs live player-
-- entity WRAM simulation this project doesn't have -- deliberately
-- left unwired rather than guessing, same reasoning as 0x80 itself
-- (and matching the $10DC/$15A4 precedent: these 3 addresses are
-- expected to remain at the top of the scan's blocker ranking
-- permanently, not a sign of unfinished work). $3213 (the leaf both
-- the computed value and the dereferenced pointer feed into) wasn't
-- traced further -- moot until the upstream $02AB dependency is resolved.
--
-- 0xEF ($0E7F) -- CLOSED same pass, immediate neighbor: a simple
-- "store 2 operand bytes into WRAM $C344/$C345" primitive (the leaf
-- $0454 has no branch, no computation) plus a 3rd byte consumed via
-- the standard $3727 skip convention. See StandardScriptHandlers
-- .tileCursorSet's own doc comment for the complete disassembly.
ScriptOpcodeTable.TILE_CURSOR_SET_HANDLER_ADDRESS_EF = 0x0E7F

-- 0xBD ($1046) / 0xBC ($10DC) / 0xBE ($10A7) -- the palette-fade
-- family. TRACED, DELIBERATELY LEFT UNWIRED (disassembly confirmed
-- each reads WRAM $D499/$D49A, indexes into palette-gradient data
-- tables $101A/$1030/$107B/$1091, and writes the result into the
-- pending-palette-write cell $C0AA-$C0AC or WRAM $D3A3 via a
-- $D3A0==0x7E mode check, before calling a further leaf $1142 --
-- deemed "genuinely known-hard" and left unwired).
--
-- REVERSED (direct continuation of the boss-defeat cursor-desync
-- investigation -- BossSequenceInterpreter's own shadow run reaches
-- cursor 0x61d8 and stops honestly on 0xBD, the next live-confirmed
-- boundary): the earlier assessment above was too pessimistic for
-- cursor-tracking purposes. $1142 -- previously "not traced" -- is now
-- fully disassembled and turns out to be a small, self-contained
-- 66-tick pacing gate, no different in kind from the control-byte-0x11
-- pacing this same investigation already modeled:
--   $1142: LD A,(0xD49A) / INC A / LD (0xD49A),A / CP 0x06 / RET C
--          ; -- $D49A (inner) counts 1..5 -> RET C (halt, no $3727)
--          LD A,0x00 / LD (0xD49A),A       ; on the 6th call: reset inner
--          LD A,(0xD499) / INC A / LD (0xD499),A / CP 0x0B / RET C
--          ; -- $D499 (outer) counts 1..10 -> RET C (halt, no $3727)
--          LD A,0x00 / LD (0xD499),A       ; on the 11th outer step: reset
--          CALL 0x3727                      ; RELEASE: fetch next opcode
--          RET
-- A genuine 6x11=66-call halt (~66 frames at this project's
-- established one-step()-per-frame cadence, matching the pacing shape
-- of every other per-frame-gated opcode already modeled). Crucially,
-- all three opcodes read zero operand bytes from the script stream
-- (each pushes/pops HL around its own WRAM computation, never
-- dereferences it) -- only the shared $D499/$D49A cells drive the
-- pacing length. Live byte-dump cross-check (file offset 0x3a1d7-
-- 0x3a1e5, bank 14, the exact boss-defeat script bytes this project's
-- interpreter is running): c0 bd f3 0f 55 14 00 bc f0 32 dd 04 10 14
-- ff -- 0xBD releasing resets $D499 to 0 exactly where the very next
-- opcode, 0xF3 (PEEK_TWO_BYTE_GATE_HANDLER_ADDRESS_F3, already wired),
-- gates on $D499==0 -- a decisive, unplanned cross-validation.
--
-- What's still not modeled: the fade curve itself (which exact color
-- the 4 lookup tables encode at each step) -- the same "paced
-- correctly, but the cosmetic write is an optional, unwired callback"
-- shape already established for 0xFB/0xBF (see COLOR_PULSE_EFFECT_
-- HANDLER_ADDRESS_BF/WAVE_OFFSET_EFFECT_HANDLER_ADDRESS_FB above) --
-- this project has no renderer hook for a live palette fade yet. See
-- StandardScriptHandlers.paletteFadeCycle's own doc comment for the
-- Lua port.
ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BC = 0x10DC
ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BD = 0x1046
ScriptOpcodeTable.PALETTE_FADE_HANDLER_ADDRESS_BE = 0x10A7

-- 0x7A/0x7B ($1570/$157C, whole-corpus scan's next untouched blocker
-- after the $0E73 neighborhood): an "actor action, readiness-as-
-- parameter" family -- see StandardScriptHandlers
-- .actorActionWithReadinessParam's own doc comment for the full
-- disassembly and the reasoning for why this is tractable (needs only
-- the same boolean ctx.isActorReady already models) despite
-- superficially resembling the known-hard dynamic-group family.
-- 0x0E/0x0F are the fixed groups; 0x06 is the fixed readiness-to-
-- parameter offset (both opcodes). CORRECTED same day (see that same
-- doc comment): this is byte-for-byte the exact same shape as the
-- already-established Family-A actorAction opcodes (0x10/0x30/0x70/
-- ... above) -- initially mis-described here as "genuinely different"
-- from that family; both are the same mechanism, now modeled
-- consistently (same approximate isActorReady gate), with this family
-- additionally exposing the $28C2-derived parameter Family-A's own
-- model discards.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7A = 0x1570 -- group 0x0E, offset 0x06
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_7B = 0x157C -- group 0x0F, offset 0x06

-- 0xCC ($3AA3, whole-corpus scan's next untouched blocker after
-- 0x7A/0x7B): DEC HL / CALL $3727 / RET -- a zero-operand-byte
-- "re-mirror my own opcode byte" primitive. See StandardScriptHandlers
-- .opcodeByteMirror's own doc comment for the full disassembly and why
-- the DEC HL / $3727-fetch pair cancels to a net-zero cursor effect.
ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC = 0x3AA3

-- 0xC8 ($3BA9, whole-corpus scan's next untouched blocker after 0xBE):
-- JP $0150 -- a byte-for-byte, decisively confirmed match against the
-- ROM's own cartridge entry vector ($0100: NOP / JP $0150, same 3
-- target bytes C3 50 01). A "soft reset the whole game" script command
-- -- see StandardScriptHandlers.softReset's own doc comment for the
-- complete chain ($0150 -> $1FCA, a cold-boot sequence) and the honest
-- modeling limit this requires.
ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8 = 0x3BA9

-- 0xD1 ($3A72, whole-corpus scan's next untouched blocker after 0xE7):
-- a "budget countdown, SET/CLEAR flag bit 6" command. Resolving this
-- also fully decoded the previously-untraced $3BEF/$3BF9 leaf pair
-- (see StandardScriptHandlers.budgetFlagCommand's own doc comment for
-- the complete disassembly, including the $3602 bit-index resolver and
-- the $1F06 selector-0x26 tail).
ScriptOpcodeTable.BUDGET_FLAG_COMMAND_HANDLER_ADDRESS_D1 = 0x3A72

-- 0x9C/0x9D ($0F0A/$0F14, whole-corpus scan's next untouched blocker
-- after 0xD1): a "raw single-byte leaf command" family, sharing the
-- same leaf ($2895) -- see StandardScriptHandlers.rawByteLeafCommand's
-- own doc comment for the complete disassembly and why this is a
-- genuinely different shape from .byteLeafCommand (no INC A).
ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9C = 0x0F0A
ScriptOpcodeTable.RAW_BYTE_LEAF_COMMAND_HANDLER_ADDRESS_9D = 0x0F14

-- 0xC6 ($39CF, whole-corpus scan's next untouched blocker after 0x9D):
-- a "scene/textbox init" command -- writes the same 5 WRAM cells
-- ($D862/$D86C/$D853/$D84A/$C0A0) opcode 0xF6's own doc comment
-- already hypothesized as a "start a new textbox/scene" initializer --
-- see StandardScriptHandlers.sceneInitCommand's own doc comment for
-- the complete disassembly.
ScriptOpcodeTable.SCENE_INIT_COMMAND_HANDLER_ADDRESS_C6 = 0x39CF

-- 0xC7 ($39BA, whole-corpus scan's next untouched blocker after 0xC6):
-- a "2-bit WRAM field write" command -- see StandardScriptHandlers
-- .twoBitFieldCommand's own doc comment for the complete disassembly
-- (including the self-contained $2B1E wrapping-counter leaf this
-- resolves, left HYPOTHESIS on its exact return value only -- the
-- opcode's stream behavior doesn't depend on it).
ScriptOpcodeTable.TWO_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C7 = 0x39BA

-- 0xDA/0xDB ($3BDB/$3BE5, whole-corpus scan's next untouched blocker
-- after 0xC7): a "dynamic-index flag-bit SET/CLEAR" family, reusing
-- the same $3BEF/$3BF9 primitives 0xD1 already resolved -- see
-- StandardScriptHandlers.dynamicFlagBitCommand's own doc comment for
-- the complete disassembly.
ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DA = 0x3BDB -- SET
ScriptOpcodeTable.DYNAMIC_FLAG_BIT_COMMAND_HANDLER_ADDRESS_DB = 0x3BE5 -- CLEAR

-- 0xC2 ($3981, whole-corpus scan's next untouched blocker after
-- 0xDA/0xDB): a "bitmask dispatch" command -- the low 5 bits of one
-- operand byte each independently gate a call to their own fixed leaf
-- -- see StandardScriptHandlers.bitmaskDispatchCommand's own doc
-- comment for the complete disassembly.
ScriptOpcodeTable.BITMASK_DISPATCH_COMMAND_HANDLER_ADDRESS_C2 = 0x3981

-- 0xAF ($2CE7, whole-corpus scan's next untouched blocker after 0xC2):
-- a "chained opaque effect" command -- 4 sequential opaque leaf calls,
-- zero explicit script-stream operand bytes -- see
-- StandardScriptHandlers.chainedOpaqueEffectCommand's own doc comment
-- for the complete disassembly.
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AF = 0x2CE7

-- 0xC5 ($3B71, whole-corpus scan's next untouched blocker after 0xAF):
-- a "6-bit WRAM field write" command -- see StandardScriptHandlers
-- .sixBitFieldCommand's own doc comment for the complete disassembly.
ScriptOpcodeTable.SIX_BIT_FIELD_COMMAND_HANDLER_ADDRESS_C5 = 0x3B71

-- `0xB7` ($0D9B, added 2026-08-14, whole-corpus scan's own next real
-- untouched blocker after `0x86`): `PUSH HL / CALL $0DA4 / POP HL /
-- CALL $3727 / RET`, where `$0DA4` (`PUSH AF / LD A,0x17 / JP $1ED7`)
-- trampolines into the already-mapped `$1ED7` dispatcher's selector
-- `0x17` -- UNLIKE `0xA4`'s own selector `0x08`, case `0x17`'s real
-- code (`$40A0`) is a simple, branchless routine (`LD A,0xE4 / LD
-- ($C0AA),A` -- the SAME real pending-palette-write cell this project
-- already knows -- `/ LD A,($C0A5) / OR 0x03 / LD ($C0A5),A / CALL
-- $0313 / RET`), no `$02AB` dependency at all. Byte-for-byte the SAME
-- real shape as `StandardScriptHandlers.chainedOpaqueEffectCommand`
-- (0 explicit operand bytes, 1 via the standard `$3727` skip,
-- unconditional) -- reuses that factory directly, no new Lua code.
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_B7 = 0x0D9B

-- `0xA1`/`0xA2` (`$01A3`/`$01B2`) -- CLOSED 2026-08-15 (direct user
-- request "ok dann mal die fehlenden opcodes dekodieren"): byte-for-
-- byte the same PUSH HL / CALL <helper> / POP HL / CALL $3727 / RET
-- shape as 0xB7 above, where <helper> is PUSH AF / LD A,<sel> / JP
-- $1ED7 -- 0xA1 uses selector 0x0A (target $5156), 0xA2 uses selector
-- 0x0B (target $5176). Both selector bodies are structurally identical
-- to each other (only 2 small immediate constants differ -- 0x0D/0xF1
-- for 0xA1 vs. 0x0E/0xF5 for 0xA2): LD A,<c1> / CALL $3E9A / LD C,4 /
-- CALL $29BA / LD C,4 / LD A,2 / CALL $0C5D / LD C,4 / LD A,<c2> /
-- CALL $0C86 / XOR A / LD ($C4D2),A / CALL $28D5 / RET -- an always-
-- unconditional multi-step actor sub-effect (resets the $C4D2 actor-
-- state flag, several opaque leaf calls with small baked-in
-- parameters -- plausibly a sound/animation trigger pair, not
-- independently confirmed further). Zero explicit operand bytes,
-- unconditional -- reuses StandardScriptHandlers
-- .chainedOpaqueEffectCommand directly, no new Lua code.
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_A1 = 0x01A3 -- selector 0x0A
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_A2 = 0x01B2 -- selector 0x0B

-- 0xB6 ($0D8C) -- CLOSED, same pass: same wrapper shape again,
-- selector 0x16 (target $4059). This one's body is substantially
-- larger (a VRAM tile-copy/animation-load sequence -- writes $C0AA/
-- $C0A5 pending-graphics flags, then copies tile data via $02F3/$2DF5
-- toward VRAM $8F00) but the wrapper's contract doesn't depend on what
-- the delegate does internally -- still zero operand bytes, still
-- unconditional. Leaf effect HYPOTHESIS (a graphics/animation trigger)
-- -- reuses the same factory.
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_B6 = 0x0D8C -- selector 0x16

-- 0xAA ($2F7F) -- CLOSED, same pass: PUSH HL / CALL $2EF7 / POP HL /
-- CALL $3727 / RET, where $2EF7 is itself another $1ED7 trampoline,
-- selector 0x1F -- the same selector rom-map.md's "$1ED7" section
-- already documents: processes a 7-slot "pending sound-trigger queue"
-- at WRAM $CEF0, each entry played via $0611. An already-understood
-- effect -- zero operand bytes, unconditional -- reuses the same factory.
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AA = 0x2F7F -- selector 0x1F (pending-sound-queue processor)

-- 0xAB ($0D83) -- CLOSED, same pass: PUSH HL / CALL $21B4 / POP HL /
-- CALL $3727 / RET -- unlike its siblings above, $21B4 doesn't go
-- through $1ED7 at all, it's a direct leaf: LD HL,$C400 / LD B,0x80 /
-- LD A,0xFF / CALL $2B5D / RET, where $2B5D is a generic "fill B bytes
-- starting at HL with A" primitive -- this opcode's effect is
-- unconditionally filling the entire 128-byte WRAM block $C400-$C47F
-- with 0xFF. $C400 is the same per-actor state-flag region this
-- project already tracks elsewhere (task #146's $C400+index bit-7
-- marker) -- plausibly a "reset all actor states" bulk operation. Zero
-- operand bytes, unconditional -- reuses the same factory (the fill
-- effect itself isn't reproduced).
ScriptOpcodeTable.CHAINED_OPAQUE_EFFECT_COMMAND_HANDLER_ADDRESS_AB = 0x0D83 -- 128-byte $C400 block fill (0xFF)

-- 0xAD ($0DBC) -- CLOSED, direct follow-up to decode the remaining
-- opcodes, task #152: PUSH HL / CALL $1ED1 / CP 0x00 / JR NZ,<release>,
-- where $1ED1 (PUSH AF / LD A,0x01 / JP $1F06) reaches selector 0x01
-- of the already-known bank-2 $1F35/$1F06 dispatcher family (rom-
-- map.md's "$1ED7" section already flags this as $1ED7's sibling, just
-- bank 2 instead of bank 1 -- confirmed here: passing A=2 instead of
-- A=1 to the shared $29FB bank-switch primitive lands on a completely
-- different table). Selector 0x01 ($4218) is a complete, classic Game
-- Boy joypad-polling routine ($FF00 D-pad/button hardware reads,
-- including the A+B+Select+Start soft-reset combo check) that returns
-- the current 8-bit button state in A. 0xAD itself: releases
-- immediately if any button is held; while nothing is held, halts,
-- incrementing an idle counter and calling one of 2 opaque leaves
-- every tick -- a "wait for any button press" gate. See
-- StandardScriptHandlers.waitForAnyButtonCommand's own doc comment for
-- the complete disassembly.
ScriptOpcodeTable.WAIT_FOR_ANY_BUTTON_COMMAND_HANDLER_ADDRESS_AD = 0x0DBC

-- 0x8B ($0D1B) -- CLOSED, direct follow-up to decode the remaining
-- opcodes, task #152, continuing straight from 0xAD above: a self-
-- contained "play back a pre-baked waypoint/step sequence" gate.
-- Byte-for-byte: LD A,($D499) / CP 0 / CALL Z,$0D51 / LD B,A / LD
-- A,($D49A) / DEC A / LD ($D49A),A / RET NZ / <else: PUSH HL / LD
-- C,0x04 / PUSH BC / CALL $0C99 / LD D,A / POP BC / LD A,($D498) / LD
-- E,A / LD A,B / LD B,0 / CALL $2C27 / POP HL / LD ($D499),A / CP 0 /
-- JR Z,<release> / LD A,0x08 / LD ($D49A),A / RET>.
--
-- Init ($0D51, fires exactly once, when $D499==0): reads one operand
-- byte (LD A,(HL+)), stores operand-0x20 into $D498 (a fixed "which
-- waypoint table" selector, unchanged for the rest of this opcode's
-- lifetime), and arms the wait counter $D49A=1.
--
-- Per-tick pacing: $D49A decrements every tick; while still nonzero,
-- halts (bare RET, no $3727, no further bytes consumed) -- 1 frame
-- after init, 8 frames after every subsequent step (LD A,0x08 on the
-- re-arm path).
--
-- Step-advance (once $D49A hits 0): $0C99 is the already-confirmed
-- entity-slot ALIVE-field getter (WRAM $C200 + slotIndex*16 + 0, see
-- EntityStructLayout.FIELD.ALIVE), called with a fixed C=4 -- this
-- project's already-confirmed player slot -- giving the player's
-- current ALIVE/state byte (D). $2C27 (PUSH AF / LD A,0x1C / JP
-- $1ED7) reaches $1ED7 selector 0x1C (target $76AB, cross-checked
-- against the already-known selector 0x08->$50F9 before trusting this
-- new selector read): a waypoint-table walk, indexing a 2-byte-per-
-- entry table at $776F by E (the fixed $D498 selector) to get a base
-- address, then reading the 16-bit entry at base + A*2 (A = the step
-- index, 0 on the first check, else the persisted previous $D499
-- result) as a (D,E) coordinate/delta pair. A 0x80 low-byte sentinel
-- means "sequence finished" -- returns A=0, released. Otherwise, a
-- second table ($78EF, indexed by E&0x1F) plus a C<7 branch ($08D4 vs
-- $2889, both untraced distance helpers) computes a per-step distance,
-- returned as A = 1+distance (always nonzero on this path) -- this
-- becomes the next step index, persisted into $D499, and the wait
-- counter re-arms to 8 frames.
--
-- Total consumption across the whole opcode's lifetime: opcode(1) +
-- operand(1, at init only) + zero bytes on every halting tick + the
-- standard $3727 trailing skip (1, at release) -- exactly 2 bytes
-- beyond the opcode itself, matching this project's generic
-- ScriptInterpreter.fetch-based tail convention.
--
-- The exact waypoint-table contents ($776F/$78EF) and the two distance
-- helpers ($08D4/$2889) are deliberately not reproduced --
-- advanceStep(operand, stepIndex) is the caller's own opaque evaluator
-- (same abstraction level as chainedOpaqueEffectCommand's untraced
-- leaves), returning (done, nextStepIndex) once per check. See
-- StandardScriptHandlers.waypointStepCommand's own doc comment.
ScriptOpcodeTable.WAYPOINT_STEP_COMMAND_HANDLER_ADDRESS_8B = 0x0D1B

-- 0xAC/0xAE ($11E5/$11F8) -- CLOSED, direct follow-up saying the
-- website still shows 2 open, close those too, task #152's final pair.
-- $1ED7 selectors 0x11/0x12 (targets $4164/$4180), each a LD D,H/LD
-- E,L / LD A,($D499) / LD HL,<table> / CALL $2B70 / RET jump-table
-- dispatch (the same $2B63-based "multiply by 2, read a 16-bit entry,
-- JP" shape already trusted for selector 0x10's own table). Reading
-- both tables' raw bytes directly (not disassembling them as code,
-- which would misread data as instructions) found an 8-phase state
-- machine (0-7, not 6 like the sibling paletteFadeCompletionGate
-- family -- confirmed by checking where each table degrades into
-- garbage addresses past index 7). See StandardScriptHandlers
-- .wipeCompletionGate's own doc comment for the complete, byte-exact
-- disassembly of all 8 phases (including a self-caught correction of
-- an earlier "phase 0 is byte-identical in shape to the sibling
-- family" claim -- it isn't; phase 0 does substantial extra palette/
-- effect work the sibling family's phase 0 doesn't) and the decisive
-- evidence for the phase-2/phase-6 symmetric-duration design (both
-- share one WRAM tick counter, $D49A).
--
-- The outer opcode itself ($11E5/$11F8): CALL <trampoline> / LD
-- A,($D499) / CP 0 / RET NZ / CALL $3727 / RET -- zero explicit
-- operand bytes; releases exactly when the 8-phase state machine
-- reports $D499==0 again. See StandardScriptHandlers
-- .completionPredicateCommand's own doc comment for this generic
-- outer shape.
ScriptOpcodeTable.WIPE_COMPLETION_COMMAND_HANDLER_ADDRESS_AC = 0x11E5
ScriptOpcodeTable.WIPE_COMPLETION_COMMAND_HANDLER_ADDRESS_AE = 0x11F8

-- 0x9A/0x9B ($1674/$1681, whole-corpus scan's next untouched blockers
-- after 0xB7, found right next to the already-known 0x8F/0x99 in the
-- same neighborhood): 2 more plain Family-A actorAction members (CALL
-- $28C2 / JR NZ,<halt> / LD A,<group> / LD C,0x00 / CALL $2879 / RET,
-- a true halt via JR NZ -- not the _OR_SKIP_ soft-skip family). Picked
-- up automatically by the existing generic ^ACTOR_ACTION_HANDLER_
-- ADDRESS_ loop.
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_9A = 0x1674 -- group 0x0E
ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_9B = 0x1681 -- group 0x0F

-- 0x5A/0x5B ($1488/$1494, same neighborhood sweep): 2 more
-- actorActionWithReadinessParam members (same shape as 0x7A/0x7B),
-- offset 0x04, groups 0x0E/0x0F.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5A = 0x1488 -- group 0x0E, offset 0x04
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_5B = 0x1494 -- group 0x0F, offset 0x04

-- 0x6A/0x6B ($14FC/$1508, same neighborhood sweep -- the pair that
-- triggered this session's self-caught Family-A/readiness-as-parameter
-- unification, see StandardScriptHandlers
-- .actorActionWithReadinessParam's own doc comment): 2 more
-- actorActionWithReadinessParam members, offset 0x05, groups 0x0E/0x0F.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6A = 0x14FC -- group 0x0E, offset 0x05
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_6B = 0x1508 -- group 0x0F, offset 0x05

-- 0x24 ($1300, whole-corpus scan's next untouched blocker after
-- 0x6B): 1 more actorActionWithReadinessParam member, offset 0x01,
-- group 0x1E. (Its immediate neighbor, 0x25/$130C, is bytes for this
-- same shape too -- but already closed under the plain ACTOR_ACTION_
-- HANDLER_ADDRESS_25 constant via the generic Family-A loop; left as-
-- is since it's already clean.)
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_24 = 0x1300 -- group 0x1E, offset 0x01

-- 0x68 ($14E8, whole-corpus scan's next untouched blocker after
-- 0x24): a "queued action, readiness-as-parameter" command (the
-- $2859-leaf sibling of actorActionWithReadinessParam) -- see
-- StandardScriptHandlers.queuedActionWithReadinessParam's own doc
-- comment.
ScriptOpcodeTable.QUEUED_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_68 = 0x14E8 -- offset 0x05

-- 0x74 ($1544, same neighborhood sweep): 1 more
-- actorActionWithReadinessParam member, offset 0x06, group 0x1E.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_74 = 0x1544 -- group 0x1E, offset 0x06

-- 0x54 ($145C, same neighborhood sweep): 1 more
-- actorActionWithReadinessParam member, offset 0x04, group 0x1E.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_54 = 0x145C -- group 0x1E, offset 0x04

-- 0xA9 ($0D5F, whole-corpus scan's next untouched blocker after
-- 0x74): a "3-way classified flag-bit SET/CLEAR" command -- reuses the
-- same $3BEF/$3BF9 bit primitives 0xD1/0xDA/0xDB already resolved --
-- see StandardScriptHandlers.threeWayFlagBitCommand's own doc comment.
ScriptOpcodeTable.THREE_WAY_FLAG_BIT_COMMAND_HANDLER_ADDRESS_A9 = 0x0D5F

-- 0x67 ($14C4, whole-corpus scan's next untouched blocker after
-- 0xA9): 1 more actorActionWithReadinessParam member, offset 0x05,
-- group 0x1D.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_67 = 0x14C4 -- group 0x1D, offset 0x05

-- 0x4A/0x66 ($1414/$14B8, whole-corpus scan's next untouched blockers
-- after 0x67): 2 more actorActionWithReadinessParam members.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_4A = 0x1414 -- group 0x0E, offset 0x03
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_66 = 0x14B8 -- group 0x1C, offset 0x05

-- 0x76 ($152C, whole-corpus scan's next untouched blocker after
-- 0x66): 1 more actorActionWithReadinessParam member, offset 0x06,
-- group 0x1C.
ScriptOpcodeTable.ACTOR_ACTION_WITH_READINESS_PARAM_HANDLER_ADDRESS_76 = 0x152C -- group 0x1C, offset 0x06

-- 0xA3/0xA5/0xA6 ($01D0/$01DC/$01E8, whole-corpus scan's next
-- untouched blockers after 0x76): a "fixed WRAM bit SET, then skip 1
-- byte" family -- the simplest handler shape found this whole pass (no
-- leaf, no branch, no live predicate) -- see StandardScriptHandlers
-- .fixedWramBitSetSkipCommand's own doc comment.
ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A3 = 0x01D0 -- bit 4
ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A5 = 0x01DC -- bit 5
ScriptOpcodeTable.FIXED_WRAM_BIT_SET_SKIP_COMMAND_HANDLER_ADDRESS_A6 = 0x01E8 -- bit 6

-- 0x69 ($14F2, whole-corpus scan's next untouched blocker after
-- 0xA6): 1 more actorSlotPositionWithReadinessParam member (the
-- $123E-leaf sibling of actorActionWithReadinessParam), offset 0x05.
ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_69 = 0x14F2 -- offset 0x05

-- 0xB6 ($0D8C, TRACED, DEFERRED, whole-corpus scan): a $1ED7 selector
-- 0x16 trampoline ($0D95 -> PUSH AF / LD A,0x16 / JP $1ED7) -- unlike
-- 0xB7's own simple selector 0x17, case 0x16's code ($4059) is a
-- substantial, deep, multi-step routine (loops, a DMA-shaped transfer
-- via $386E, several more untraced leaves) -- not a quick structural
-- win like 0xB7. No halt was found in the traced portion, so this may
-- still be tractable as an "always continues" opaque effect, but fully
-- verifying that needs more tracing time than this pass justifies (a
-- bounded, reusable further thread, not abandoned). Left deliberately
-- unwired, no constant assigned.

-- 0xA1 ($01A3, TRACED, DELIBERATELY NOT WIRED, whole-corpus scan):
-- PUSH HL / CALL $01AC / POP HL / CALL $3727 / RET, where $01AC is
-- PUSH AF / LD A,0x0A / JP $1ED7 -- a trampoline into the already-
-- fully-mapped $1ED7 dispatcher's selector 0x0A, which is $4B70 --
-- task #85's own decisively-understood "enqueue a (group, actionCode)
-- pair into the shared actor-command queue" mechanism (reads its
-- actionCode from C). A qualitatively different kind of hard case: C
-- is never set anywhere in this opcode's own code, nor in $1ED7's own
-- preamble (re-verified against its full disassembly) -- it's
-- whatever leftover CPU register state happened to survive from
-- whatever ran immediately before this opcode dispatched, not
-- something derivable from this opcode's own script bytes or a fixed
-- ROM constant. Unlike the $02AB family (an opaque, undecoded leaf),
-- this needs live CPU register-state tracking across opcode
-- boundaries -- a kind of state this project has never modeled and
-- has no honest way to approximate. Left deliberately unwired, no
-- constant assigned.

-- 0x79 ($1566, whole-corpus scan's next untouched blocker after
-- 0xC5): an "actor-slot-position, readiness-as-parameter" command --
-- the $123E-leaf sibling of 0x7A/0x7B's own already-resolved
-- actorActionWithReadinessParam family -- see StandardScriptHandlers
-- .actorSlotPositionWithReadinessParam's own doc comment.
ScriptOpcodeTable.ACTOR_SLOT_POSITION_WITH_READINESS_PARAM_HANDLER_ADDRESS_79 = 0x1566 -- offset 0x06

--- Decode the full 256-entry table from romData per scriptOpcodeTable
-- (profile.scriptOpcodeTable). Returns a plain 1-based array of 256
-- integers (CPU handler addresses) -- table[opcode + 1] is the
-- handler address for opcode byte opcode (0-255).
function ScriptOpcodeTable.decode(romData, scriptOpcodeTable)
  assert(type(romData) == "string", "ScriptOpcodeTable.decode expects a byte string")
  assert(scriptOpcodeTable and scriptOpcodeTable.fileOffset and scriptOpcodeTable.recordCount,
    "ScriptOpcodeTable.decode expects a profile.scriptOpcodeTable")

  local entries = {}
  for i = 0, scriptOpcodeTable.recordCount - 1 do
    local base = scriptOpcodeTable.fileOffset + i * 2
    local lo, hi = romData:byte(base + 1, base + 2)
    entries[i + 1] = lo + hi * 256
  end
  return entries
end

return ScriptOpcodeTable
