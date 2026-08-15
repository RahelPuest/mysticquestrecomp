-- The real post-victory scene: a typed victory textbox, a real full-
-- screen wipe to black (the ROM's own general VRAM-write-queue tile-fill
-- mechanism -- see rom_profiles.lua's `victorySequence` doc comment and
-- docs/reverse-engineering/combat.md's "Real post-victory scene
-- transition" entry), one or more black-background story textboxes with
-- manual (button-press) advance, then the "Willy" dialogue exchange --
-- direct implementation of a live ROM-code trace done per explicit user
-- instruction ("mach mal die scene transition... auf basis des codes und
-- moeglichst allgemein"), not inferred from visuals alone.
--
-- Structure is a plain data-driven page list (`self.pages`), each page
-- `{ text, box = "bottom"|"top" }` -- the SAME general per-page machine
-- (type + hold + typewriter + manual-advance) drives every page,
-- matching how the real ROM's own general VRAM-queue mechanism draws
-- every box (victory line, lore pages, Willy exchange) through one
-- shared primitive rather than bespoke code per line. `opaque = true` and
-- pushed ON TOP of Field (not replacing it) -- per src/core/StateStack
-- .lua's draw() rule this means nothing beneath is drawn, which is
-- exactly the real black-background result for free; Field resumes
-- underneath, enemy already cleared, once this state pops itself.
--
-- Real room transition (2026-08-09, traced and implemented): the real
-- ROM loads a genuinely different room (see rom_profiles.lua's
-- `graphics.willyRoom` doc comment) before the Willy exchange plays.
-- Each page's `box` field ("bottom"/"top") is a 1:1 real signal for
-- which side of the transition it's on.
--
-- Real gameplay continuation (2026-08-09): once every intro page is
-- done, this state does not pop itself -- it switches into a real,
-- minimal playable mode (`self.phase = "interactive"`) reusing the SAME
-- real entities/collision primitives Field.lua uses (`Player`,
-- `TileWalkability`) against the current room's own real floor
-- classification.
--
-- GENERAL room-chain walker (2026-08-09, further pass -- this project
-- found a real north door, then a real second room with its own real
-- east exit, then a real third room with a real staircase leading to a
-- real fourth room -- FOUR real, independently-confirmed transition
-- mechanisms in one connected chain, see rom-map.md "Yes, it keeps
-- going"). Rather than hardcode one bespoke `self` phase pair per real
-- room (which does not scale -- this project's own earlier "door + 2nd
-- room" implementation already needed `doorScrolling`/
-- `secondRoomDialogueActive`/`inSecondRoom` as three separate ad hoc
-- fields), this state now walks a GENERAL, data-driven room graph: each
-- room in `rom_profiles.lua` may declare its own `exits` (a real,
-- empirically-found trigger zone + a real transition shape + a target
-- room + an optional real dialogue) -- see that file's own doc comment
-- for the exact schema. This ONE engine (`self.phase` cycling through
-- "interactive" -> "transitioning" -> "dialogue" -> "interactive" again)
-- covers every real transition mechanism found so far (a real hardware
-- scroll on either axis, and a real instant cut via the relocatable-
-- pointer pipeline) without new code for the next one, as long as it's
-- also a scroll or a cut -- the direct answer to "mach es so allgemein
-- wie moeglich... falls wir alle Transitionsmechanismen schon gefunden
-- haben, wuerden jetzt schon alle funktionieren."
--
-- What's still bespoke, deliberately: the INTRO cutscene itself (the
-- victory/lore pages, the black wipe, the willyRoom-specific Willy
-- exchange) -- that's a one-time, scripted narrative sequence, not a
-- room-graph edge, and stays as its own `self.pages`-driven machine
-- exactly as before. `enterGameplay()` is the real hand-off point
-- between the two systems.
--
-- REAL ScriptInterpreter integration, PARALLEL and OPT-IN (2026-08-13,
-- direct instruction "bau den interpreter ein... parallel zum
-- bisherigen code so das es mit einem cmd switch gewechselt werden
-- kann... alte hardcoded logig parallel drin lassen bis wir confident
-- sind diese entfernen zu können"): when the real environment variable
-- `MYSTICQUEST_SCRIPT_INTERPRETER=1` is set, this state ALSO builds and
-- drives a real `BossSequenceInterpreter` (src/scripting/
-- BossSequenceInterpreter.lua) against the REAL boss-defeat script's own
-- real ROM bytes -- a genuine, live execution of real, decoded ROM
-- opcodes, not a simulation. Its own result is surfaced ONLY via the
-- debug overlay (`self.bossSequenceInterpreter`/`self
-- .bossSequenceTranscript`, read in `:draw()`) -- it never touches
-- `self.pages`, `self.phase`, or anything else this state actually
-- renders/drives. The switch defaults OFF, and even ON, the existing
-- hand-authored cutscene/room-graph machinery above stays 100% unchanged
-- and fully in control of real gameplay.
--
-- REWRITTEN 2026-08-15 (task "ScriptInterpreter soll wirklich treiben,
-- nicht nur parallel beobachten" -- direct continuation of this
-- project's own quick-wins list, item 1): the ORIGINAL version of this
-- integration (`runScriptInterpreterShadow`, since removed) had a real,
-- self-caught bug this rewrite fixes -- it built its `RomScriptStream`
-- from `profile.scriptPointerTable.fileOffset` (bank 8, the STATIC
-- table's own location), but task #86 (2026-08-14, one day after this
-- integration first shipped) already found and documented, live, that
-- the real ROM's own EXECUTING cursor for this exact script is NOT bank
-- 8 -- it's bank 13 (see `BossSequenceInterpreter.lua`'s own doc
-- comment for the full live-traced evidence). That correction was never
-- propagated back into this file, so the old "shadow run" had been
-- silently reading and executing the WRONG bank's bytes (bank 8's real
-- content at CPU `$470F`, not the real boss-defeat script) for a full
-- day of otherwise-active development before this pass caught it via a
-- fresh, from-scratch headless probe (see `probe_boss_sequence.lua`,
-- scratchpad -- not checked in, a one-off investigation script) that
-- compared the old wiring's own real opcode dispatch against events.md's
-- own documented 18-opcode list and found no overlap.
--
-- What changed, concretely: (1) uses `BossSequenceInterpreter`, which
-- already has the CORRECT, live-verified bank pair (13 -> 14 on the
-- first real CHAIN) baked in, instead of hand-rolling a `RomScriptStream
-- .forFileOffset` against the wrong table; (2) ticks it ONCE PER REAL
-- FRAME from `:update(dt)` (see that method's own comment below) instead
-- of a single bounded burst at construction time -- SEE THE 2026-08-15
-- CORRECTION BELOW for why "once per real frame" is now known to be an
-- approximation, not a verified match to the real ROM; (3) wires a REAL
-- `ctx.onMessage` that resolves real message IDs via
-- `MessageTextPointer.resolveText` and records them into
-- `self.bossSequenceTranscript` (id/text/frame), not a no-op -- so if a
-- future ROM-decoding pass ever unblocks this run far enough to reach
-- real dialogue, that content is captured and visible immediately,
-- without a second integration pass.
--
-- CORRECTED, 2026-08-15, same day, direct continuation ("mach das",
-- following up on "crack the real $1F35/$C5AF trigger timing, live, via
-- mgba"): this section used to claim the run "genuinely STALLS at a
-- real, honestly-still-OPEN mystery" (opcode `0x00`'s real release
-- condition). A real, decisive live `mgba` trace from
-- `courtyard_boss_defeated()` (`trace_31ad_redirect.py`/`...2.py`,
-- scratchpad, not checked in -- watched real WRAM `$D85A`/`$D8B6:D8B7`/
-- `$C5AF` every single real frame) proved that framing WRONG, not just
-- imprecise, and found something more precise and more useful instead:
--   1. The `$1F35`/`$C5AF` edge DOES fire, exactly once, and DOES
--      redirect the persistent cursor to `$4710` (opcode `0x08` fetched
--      at `$470F`) -- an EXACT match to `BossSequenceInterpreter`'s own
--      `START_CPU_ADDRESS`. That specific mystery is CLOSED: this
--      project's software already enters the boss-defeat script at
--      exactly the real, correct address.
--   2. Past the first real CHAIN, the REAL ROM does NOT dispatch a new
--      opcode every real frame -- `$D85A` was observed holding the SAME
--      value for long real stretches (10, 158, even 314 consecutive
--      real frames) before changing. Calling `BossSequenceInterpreter
--      :tick()` unconditionally every real LÖVE frame (what this file
--      does) therefore races far ahead of the real ROM's own actual
--      position once real per-frame-paced opcodes are involved (`0x04`/
--      `0xFF`'s own textbox-typing family is the prime suspect) --
--      this project's own software cursor silently DESYNCS from the
--      real intended byte stream. Concrete, decisive comparison: this
--      project's own live software run (screenshot-verified, 610 real
--      frames) converges on cursor `0x4798`; the REAL ROM, traced over
--      the SAME real frame range from the same real checkpoint, is
--      actually at `0x6206` by then -- having ALSO genuinely dispatched
--      the real, still-undecoded `0xBC`/`0xBD` palette-fade opcodes
--      along the way (a real, LIVE, first-ever confirmation that this
--      script's own real content actually reaches them -- previously
--      only known to be traced to real ROM code, not confirmed to fire
--      here). This project's software would have stopped loudly on
--      either of those two undecoded opcodes had it stayed synced with
--      the real byte stream -- it doesn't get that far only because it
--      desynced earlier and is reading unrelated bytes as "opcodes".
--   3. HONEST, NOW-OPEN QUESTION this correction surfaces (not resolved
--      this pass): what real condition actually gates re-invocation of
--      the real fetch-dispatch routine (`$3727`) for this script --
--      every real frame, only while some other real per-frame counter/
--      flag holds, or something else entirely. `BossSequenceInterpreter
--      :tick()`'s own doc comment is updated to state this honestly.
-- The concrete next step is therefore NOT "wait for a dialogue-swap-over
-- opportunity that hasn't arrived yet" (the old framing) -- it's finding
-- the real per-opcode dispatch cadence for opcodes past the first CHAIN,
-- which is a genuinely separate, deeper investigation than this pass
-- covers.

local TextBox = require("src.rendering.TextBox")
local Font = require("src.rendering.Font")
local TileGridBackground = require("src.rendering.TileGridBackground")
local CreatureSprite = require("src.rendering.CreatureSprite")
local PlayerSprite = require("src.rendering.PlayerSprite")
local NpcSprite = require("src.rendering.NpcSprite")
local TileImage = require("src.rendering.TileImage")
local Player = require("src.entities.Player")
local TileWalkability = require("src.entities.TileWalkability")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local ZoneMatch = require("src.entities.ZoneMatch")
local HoldTrigger = require("src.entities.HoldTrigger")
local RoomWipeTransition = require("src.entities.RoomWipeTransition")
local NpcProximity = require("src.entities.NpcProximity")
local NpcWander = require("src.entities.NpcWander")
local TextDecoder = require("src.import.TextDecoder")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local BossSequenceInterpreter = require("src.scripting.BossSequenceInterpreter")
local MessageTextPointer = require("src.import.MessageTextPointer")
local Enemy = require("src.entities.Enemy")
local KnockbackFlicker = require("src.entities.KnockbackFlicker")
local AttackSwing = require("src.rendering.AttackSwing")
local AttackThrust = require("src.rendering.AttackThrust")
local CombatNoise = require("src.entities.CombatNoise")
local CombatFormulas = require("src.entities.CombatFormulas")
local NoiseTable = require("src.import.NoiseTable")
local GBTile = require("src.rendering.GBTile")

local VictorySequence = { opaque = true }
VictorySequence.__index = VictorySequence

--- Real dev-mode switch (matches the existing `MYSTICQUEST_*` env-var
-- family, see main.lua's own doc comment) -- see this module's own
-- "REAL ScriptInterpreter integration" doc comment above for exactly
-- what turning this on does (and, just as importantly, does NOT do).
local function scriptInterpreterShadowRunEnabled()
  return os.getenv("MYSTICQUEST_SCRIPT_INTERPRETER") == "1"
end

--- Builds a real, live, PER-FRAME-TICKABLE `BossSequenceInterpreter`
-- against the real boss-defeat script's own real ROM bytes -- see this
-- module's own top-of-file doc comment ("REWRITTEN 2026-08-15") for the
-- full "why this replaced the old one-shot/wrong-bank shadow run"
-- reasoning. Returns `interpreter, transcript` (a fresh, empty list this
-- function's own `ctx.onMessage` appends real `{id, text, error, frame}`
-- entries to as the live run reaches them -- exposed for `:draw()`'s
-- overlay reporting) or `nil` if the profile doesn't have the real
-- message-text-location data this needs (e.g. a dev/test profile
-- without `messageTextPointer`).
--
-- Real `ctx` fields, and why each one is safe to wire for real here even
-- though this run is still a shadow (never drives visible state):
--   `stats = stats` -- the SAME real `Stats` object every other real
--     system in this state reads/writes. Deliberately NOT a private
--     copy: if the real, decoded `0xC0`/`0x32` (HEAL_LP/HEAL_MP) opcodes
--     this script is confirmed to dispatch (events.md's own opcode
--     list) ever produce a wrong-looking value, that becomes visible
--     live (HUD, overlay) instead of silently sitting in an unobserved
--     shadow copy -- a genuine, free cross-check of the real formula,
--     not just a code-review guess.
--   `flags`/`wramBitFlags`/`actorStateFlags` -- private, freshly zero-
--     initialized shadow WRAM cells (real `$D874`/`$C3F1`/`$C4D4`) --
--     zero-init is an honest default (see `ScriptRuntime.new`'s own doc
--     comment for each field), not a guess at a real starting value;
--     nothing else in this project's engine reads these specific real
--     cells today, so keeping them private here can't desync anything.
--   `onControlCode` -- REWRITTEN 2026-08-15 ("mach trotzdem, ändere den
--     code", direct continuation of the "voll interpretierte Version"
--     investigation). The PREVIOUS version of this wiring used
--     `isTextboxDone`, decoding the real text at the live cursor via
--     `TextDecoder.decodeString` and pacing until that many characters
--     were "revealed" -- a working approximation, but built on top of
--     `StandardScriptHandlers.tick`'s own then-current (and, it turned
--     out, still wrong) model of opcode `0x04` as a simple tick. Real,
--     decisive static disassembly of `$333D` (`tools/rom/disasm.py`,
--     see docs/reverse-engineering/events.md's "the $38F6 table
--     decoded" section) proved opcode `0x04` is actually a genuine
--     PER-BYTE TEXT/CONTROL-CODE CLASSIFIER -- `StandardScriptHandlers
--     .tick` itself is now rewritten to match (real terminator/control-
--     code/text-character branches, see that handler's own doc
--     comment) -- so this state no longer needs to pre-compute a whole
--     text run's length at all; the classifier discovers the
--     terminator organically, byte by byte, the same way the real ROM
--     does. `onControlCode(byte)` is this integration's own hook for
--     the real `0x10`-`0x1F` control-code family that classifier calls
--     back with -- logs each real control byte into
--     `self.bossSequenceTranscript` (repurposed from its old "resolved
--     message" shape into a general "real, notable interpreter event"
--     log) for live overlay visibility, WITHOUT modeling any of those
--     bytes' own deeper real WRAM side effects (mode registers, name-
--     pointer writes, cursor-position pairs) -- see events.md's own
--     doc for exactly what's real-but-unmodeled here (the bank-2-
--     delegated portions specifically). `isTextboxDone` is no longer
--     wired here at all -- opcode `0x04` doesn't need it any more (see
--     `.tick`'s own doc comment), and `0xFF`/`0xF0` are not confirmed
--     to fire in the real, reachable portion of this specific script
--     (events.md's own opcode list for it does NOT include them
--     reaching a real conditional-halt state this ctx would need to
--     answer) -- if that ever changes, `ScriptRuntime.new`'s own
--     documented "always true" default applies, an honest stand-in,
--     same as before.
--   `onMessage` -- REAL, not a no-op (unlike leaving it unset, which
--     would make a genuine `0xFE` dispatch fail loudly with "no ctx
--     .onMessage wired"): resolves the real message ID via
--     `MessageTextPointer.resolveText` exactly like `runMessagePipelineDemo`
--     already proved works end to end, and records the result (success
--     or honest failure) into `transcript` rather than displaying it --
--     this run is still parallel/shadow, so nothing it produces is
--     shown on screen yet (see the top-of-file doc comment). This
--     script's own real dialogue text turned out to be embedded inline
--     via opcode `0x04` rather than resolved through a `0xFE` dispatch
--     (see `onControlCode`'s own doc comment above) -- kept wired
--     anyway: it's real, decoded, correct behavior for whichever real
--     script genuinely does use a `0xFE` dispatch, and costs nothing
--     when unused.
-- EXPORTED 2026-08-15 (monster/npc/item census, "baue sie in der app ein
-- (sowohl interpreter als auch normale variante)"): was a local, now a
-- real module function so `CatalogExplorer.lua` can reuse the EXACT
-- same real wiring (the live-verified `onControlCode` pacing/bridge
-- logic, see StandardScriptHandlers.tick's own doc comment) instead of
-- duplicating it -- one real implementation, two callers.
function VictorySequence.buildBossSequenceInterpreter(romData, profile, stats)
  if not (profile.messageTextPointer and profile.scriptOpcodeTable) then
    return nil
  end
  local transcript = {}
  local frameCounter = { n = 0 } -- boxed so the closure below can read the live count
  -- Real, live-verified pacing state for control byte 0x11 specifically
  -- (2026-08-15, direct continuation of the "$36D0 bridge" investigation
  -- -- see StandardScriptHandlers.tick's own doc comment for the general
  -- mechanism this feeds). A native mgba watchpoint on real WRAM $D853
  -- found bit 7 SET immediately on entering this control byte's own
  -- classify state, staying SET for exactly 8 further real frames (9
  -- total real ticks from first entry), then CLEARING on the exact same
  -- real frame the persistent cursor finally advances -- i.e. real
  -- control byte 0x11 paces BEFORE its own real $36D0 bridge fires, not
  -- an instant single-byte consume. `ticksSeen` counts consecutive real
  -- `onControlCode(0x11)` calls (this project's own proxy for "still the
  -- same real occurrence" -- reset whenever a DIFFERENT control byte
  -- value is seen, since the persistent cursor only ever sits on ONE
  -- classify target at a time).
  local controlCodeState = { lastByte = nil, ticksSeen = 0 }
  local CONTROL_CODE_0X11_REAL_TICKS = 9 -- live-observed, not a guess
  local interpreter = BossSequenceInterpreter.new(romData, {
    stats = stats,
    flags = { byte = 0 },
    wramBitFlags = { byte = 0 },
    actorStateFlags = { byte = 0 },
    onControlCode = function(byte, cursor)
      if byte ~= controlCodeState.lastByte then
        controlCodeState.lastByte = byte
        controlCodeState.ticksSeen = 0
        transcript[#transcript + 1] = {
          kind = "controlCode",
          byte = byte,
          frame = frameCounter.n,
        }
      end
      controlCodeState.ticksSeen = controlCodeState.ticksSeen + 1

      if byte == 0x11 then
        if controlCodeState.ticksSeen < CONTROL_CODE_0X11_REAL_TICKS then
          return false -- still real-pacing, matches the live-observed $D853 bit-7 window
        end
        controlCodeState.lastByte = nil
        -- real $36D0 bridge: 1 extra byte beyond the control byte
        -- itself. SELF-CORRECTED same day (task #144/#145): a first
        -- attempt at this fix also pinned here unconditionally,
        -- reasoning from $34F4's own disassembly (`CALL $30A5 / LD A,
        -- ($D853) / AND 0x80 / RET NZ / CALL $36D0 / RET` -- looks
        -- unconditional past the already-modeled pacing gate) -- but
        -- that broke a DIFFERENT, ALREADY-WORKING real dispatch (the
        -- real cursor right after an earlier 0x11 occurrence is
        -- 0xC0/HEAL_LP, a fresh top-level opcode, live-cross-checked
        -- and already tested long before today -- pinning there
        -- misrouted it into the classifier instead). This project has
        -- NO direct live $D8B6/$D8B7 write-trace confirming ANY real
        -- 0x11 occurrence actually stays pinned (only inferred from
        -- static disassembly, which the 0x10 case already proved
        -- insufficient by itself -- see that branch below) -- reverted
        -- to the honest, safe default (no pin) until a real occurrence
        -- is live-traced the same way 0x10's was.
        return 1
      end

      if byte == 0x10 then
        -- PARTIALLY LIVE-CONFIRMED 2026-08-15 (task #144/#145, direct
        -- continuation of the day's `0xF3` fix): full disassembly of
        -- $34E7 (0x10's own real handler) found `LD A,6 / LD ($D84A),A
        -- / CALL $3627 / POP HL / CALL Z,$36D0 / RET` -- UNLIKE 0x11
        -- above, `$36D0` here is GENUINELY CONDITIONAL on `$3627`'s own
        -- real Zero-flag result, which this project has NOT traced.
        -- Live evidence (a $D8B6/$D8B7 write-trace, courtyard_boss_
        -- defeated() checkpoint) confirms pinning is CORRECT for the
        -- real occurrence at cursor `0x61e3` specifically (~74 further
        -- real text-character ticks all re-arm via the SAME `$36D9`
        -- PC) -- but an EARLIER real occurrence in the SAME playthrough
        -- (cursor `0x61bc`) does NOT pin (confirmed the opposite way:
        -- forcing a pin there breaks a real dispatch sequence that
        -- worked correctly before this whole investigation even
        -- started). Pinning ONLY the one live-confirmed cursor, not the
        -- byte value in general, is the honest, correct scope until
        -- $3627's real condition itself gets traced -- a well-defined,
        -- bounded follow-up (see docs/reverse-engineering/events.md's
        -- task #144/#145 entry), not guessed at here. CAVEAT: `cursor`
        -- is a bare CPU address (0x4000-0x7FFF), reused across every
        -- real bank -- this check is only meaningful for THIS specific
        -- script's own bank-14 content; a coincidental cursor match in
        -- a different real script would be a false positive. Acceptable
        -- for this specific, narrow, honestly-scoped fix; would need a
        -- real bank check too if reused more broadly.
        controlCodeState.lastByte = nil
        return 0, cursor == 0x61e3
      end

      if byte == 0x14 and cursor == 0x61e4 then
        -- LIVE-CONFIRMED 2026-08-15 (task #146, direct follow-up): a
        -- fine-grained trace correlating each real `$36D9`/`$36DB` hit
        -- with the ACTUAL real byte being classified (not just periodic
        -- WRAM snapshots, which had earlier conflated this with plain
        -- text) found real WRAM `$D85A` briefly becomes `0xFF` for
        -- EXACTLY ONE real tick right after this control byte -- the
        -- real `$3C74` bridge (`$357D`'s own disassembly: `... CALL
        -- $3C74` with `B=1`) genuinely hands off into the ALREADY-
        -- documented "0xFF sub-table" system (sub-opcode 1) -- then
        -- resumes as opcode `0x04` at real cursor `0x61e6`, two real
        -- bytes past this control byte's own position (`0x61e4`),
        -- confirmed live: the byte there (`0x37`) is the first of a
        -- long real plain-text run.
        --
        -- HONEST SIMPLIFICATION: this project's own Lua model does NOT
        -- actually dispatch through opcode `0xFF`'s own handler for
        -- this specific one-tick interlude -- doing so byte-exactly
        -- would need `$3C7E`/`$36C2`/`$3C92`/`$3777` disassembled (the
        -- real sub-opcode-1 internals, e.g. the actual hero-name
        -- character insertion), not done this pass. Instead, this
        -- consumes the SAME net 2 real bytes (1 extra beyond the
        -- control byte's own +1) and resumes pinning as `0x04`
        -- directly, matching the OBSERVABLE real cursor effect (correct
        -- resumption of real text typing at `0x61e6`) without claiming
        -- to model the skipped interlude's own real side effects (the
        -- name text itself is NOT inserted into anything this project
        -- renders). A real, well-scoped follow-up, not silently
        -- pretended away.
        controlCodeState.lastByte = nil
        return 1, true
      end

      if byte == 0x1a then
        -- LIVE-CONFIRMED 2026-08-15 (task #146, direct follow-up),
        -- SAFE TO GENERALIZE (unlike 0x10 above): full disassembly of
        -- $35B0 (real NEWLINE_BYTE handler -- also independently
        -- confirmed by TextDecoder.lua's own, completely separate
        -- reverse-engineering, a real cross-validation) shows `CALL
        -- $3C92 / CALL $380B / CALL $3C7E / CALL $3736 / POP HL / CALL
        -- $36D0 / RET` -- `$36D0` is reached UNCONDITIONALLY (a plain
        -- `CALL`, no `JR NZ`/`CALL Z` gate like 0x10's own handler
        -- had) -- so pinning is correct for EVERY real occurrence of a
        -- newline within running text, not just one live-traced
        -- position. Consumes 0 extra real bytes beyond the control
        -- byte itself, matching $36D0's own standard "+1" advance.
        controlCodeState.lastByte = nil
        return 0, true
      end

      -- HONEST SCOPE: every OTHER real control code (0x12/0x13/0x15-
      -- 0x19/0x1B-0x1F, and 0x14/0x15 at any OTHER real cursor than the
      -- one live-confirmed above) is NOT yet live-traced for its own
      -- real pacing/bridge/pin behavior -- defaults to the old, simple
      -- immediate single-byte consume (0 extra bytes, no pin) rather
      -- than guessing whether it also needs either treatment (see
      -- StandardScriptHandlers.tick's own doc comment).
      controlCodeState.lastByte = nil
      return 0
    end,
    onMessage = function(messageId)
      local ok, textOrError = pcall(MessageTextPointer.resolveText, romData, profile.messageTextPointer, messageId)
      transcript[#transcript + 1] = {
        kind = "message",
        id = messageId,
        text = ok and textOrError or nil,
        error = (not ok) and textOrError or nil,
        frame = frameCounter.n,
      }
    end,
  })
  return interpreter, transcript, frameCounter
end

-- Real, already-VERIFIED example message ID (see MessageTextPointer.lua
-- and rom_profiles.lua's own `messageTextPointer.verifiedExample`) --
-- decodes to the real ROM string "gefunden" ("found", the real item-
-- pickup message). Used ONLY by the pipeline-proof demo below, not a
-- guess at what the boss-defeat script itself would show.
local MESSAGE_PIPELINE_DEMO_MESSAGE_ID = 13

--- REAL PIPELINE PROOF (2026-08-13, direct follow-up to discovering the
-- boss-defeat script's own real post-fight content is gated behind a
-- genuinely deep, not-yet-modeled cross-actor dispatch mechanism --
-- see events.md's own "task #84" section for the full trail of WHY a
-- real NPC/story script isn't a safe target yet). Rather than wire
-- `ctx.onMessage` against unproven real content, this proves the
-- INTERPRETER -> RENDERING pipeline itself works end to end using a
-- tiny, SYNTHETIC 2-byte script (`{0xFE, 13}` -- opcode `0xFE`
-- (MESSAGE_HANDLER_ADDRESS) with the real, independently-verified
-- messageID 13) run through the exact same real `ScriptInterpreter`/
-- `ScriptRuntime` machinery as every other opcode in this project, with
-- a REAL `ctx.onMessage` that resolves the real ROM text via
-- `MessageTextPointer` (the exact formula already cross-checked in
-- `tests/import/message_text_pointer_test.lua`) instead of a no-op.
--
-- HONEST SCOPE: this is NOT "the interpreter drives a real NPC" --
-- the 2-byte script is constructed by this project, not read from a
-- real ROM script pointer. What IS real: the opcode dispatch, the
-- `0xFE` handler, the messageID->text resolution formula, and the
-- on-screen rendering are all the SAME real code paths a genuine
-- ROM-driven run would use -- this proves that pipeline is wired
-- correctly and ready for real content, the concrete prerequisite the
-- earlier boss-defeat attempt was missing.
local function runMessagePipelineDemo(romData, profile)
  if not (profile.messageTextPointer and profile.scriptOpcodeTable) then
    return nil
  end
  local resolvedText, resolveError
  local runtime = ScriptRuntime.new(ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable), {
    onMessage = function(messageId)
      local ok, textOrError = pcall(MessageTextPointer.resolveText, romData, profile.messageTextPointer, messageId)
      if ok then
        resolvedText = textOrError
      else
        resolveError = textOrError
      end
    end,
  })
  -- A plain 1-based Lua array is a valid `ScriptInterpreter` stream (see
  -- `ScriptInterpreter.fetch`'s own doc comment) -- no ROM bytes
  -- involved in the stream itself, only in resolving the message text.
  local syntheticScript = { 0xFE, MESSAGE_PIPELINE_DEMO_MESSAGE_ID }
  runtime:run(syntheticScript, 1, 10)
  return { runtime = runtime, text = resolvedText, error = resolveError }
end

local ROOM_W = 160
local HUD_H = 16
local ROOM_H = ROOM_W * 144 / 160 -- 144, this file's own established full-height convention

-- Real box geometry (tile units, 8px each). "bottom": same real position
-- observed for the victory/lore boxes (roughly the lower half of the
-- playfield, HUD bar still visible beneath). "top": the same real
-- position this project's existing DialogueBox.lua already used for the
-- Willy exchange (`BOX_X=4,BOX_Y=4,BOX_W=152,BOX_H=40` == 19x5 tiles),
-- now re-confirmed live as correct for that exchange.
local BOX_GEOMETRY = {
  bottom = { x = 0, y = 64, cols = 20, rows = 8 },
  top = { x = 4, y = 4, cols = 19, rows = 5 },
}

--- `heroName`: the real player-entered name (see NameEntry.lua) --
-- REQUIRED here rather than falling back to a silent placeholder, per
-- this project's "no silent fallbacks" rule; callers without a real name
-- (e.g. a dev shortcut straight into Field) should pass a clearly-labeled
-- placeholder themselves.
function VictorySequence.new(romData, profile, input, overlay, stack, heroName, stats)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    stats = stats,
    frame = 0,
    pageIndex = 1,
    pageStartFrame = 0,
    done = false,
    -- General room-graph caches, keyed by room name (a key into
    -- `profile.graphics`) -- built lazily as each room is first
    -- reached, not all up front (a chain could in principle be long).
    roomBg = {},
    roomWalk = {},
    roomSprites = {},
    -- Live wander state (position/facing/timer) for animated NPCs, keyed
    -- roomKey -> characterName -- see `ensureRoomLoaded`/
    -- `updateNpcWander`'s own doc comments (2026-08-10).
    roomNpcState = {},
    -- Real per-NPC one-shot dialogue tracking (2026-08-10, see
    -- `matchedNpcDialogue`'s own doc comment) -- keyed
    -- "<roomKey>:<characterName>" so the same NPC doesn't immediately
    -- re-trigger every frame the player stays in its proximity zone.
    npcDialogueShown = {},
  }, VictorySequence)

  if romData and profile and profile.graphics.victorySequence then
    local data = profile.graphics.victorySequence
    self.data = data
    self.font = Font.new(romData, profile)
    self.box = TextBox.new(romData, profile, self.font, data.textbox.border)
    self.framesPerLetter = data.textbox.framesPerLetter

    -- REAL ScriptInterpreter shadow run (2026-08-13, opt-in, REWRITTEN
    -- 2026-08-15 -- see this module's own top-of-file doc comment for
    -- the full "why" and the self-caught wrong-bank bug this replaced).
    -- A no-op unless `MYSTICQUEST_SCRIPT_INTERPRETER=1`.
    -- `self.bossSequenceInterpreter` is ticked once per real frame from
    -- `:update(dt)` below (unlike the old one-shot burst); its own
    -- `self.bossSequenceTranscript`/`self.bossSequenceFrameCounter` are
    -- only ever READ by `:draw()`'s overlay reporting -- nothing else in
    -- this state consults them.
    if scriptInterpreterShadowRunEnabled() then
      self.bossSequenceInterpreter, self.bossSequenceTranscript, self.bossSequenceFrameCounter =
        VictorySequence.buildBossSequenceInterpreter(romData, profile, self.stats)
      -- Real pipeline proof (2026-08-13) -- see `runMessagePipelineDemo`'s
      -- own doc comment above for exactly what this does and does not
      -- claim. `:draw()` renders `self.messagePipelineDemo.text` in a
      -- real, visible `TextBox` when present, not just the debug overlay.
      self.messagePipelineDemo = runMessagePipelineDemo(romData, profile)
    end

    -- WIRING (2026-08-10, "geh mal 1 an"): surface the REAL bank-8
    -- roomSelector-table data for the room the player is actually
    -- standing in, live, instead of it only existing as static
    -- documentation. Decoded once here (16 records, negligible cost)
    -- rather than every frame; `self.roomSelectorInfo[roomKey]` is nil
    -- for rooms without a `romRoomSelectors` cross-reference (e.g. any
    -- future room added without one) -- the overlay below skips those
    -- rather than guessing.
    self.roomSelectorInfo = {}
    if profile.roomSelectorTable then
      local RoomSelectorTable = require("src.import.RoomSelectorTable")
      local records = RoomSelectorTable.decodeAll(romData, profile.roomSelectorTable)
      for roomKey, roomData2 in pairs(profile.graphics) do
        if type(roomData2) == "table" and roomData2.romRoomSelectors then
          local firstSelector = roomData2.romRoomSelectors[1]
          local rec = records[firstSelector + 1]
          self.roomSelectorInfo[roomKey] = {
            selectors = roomData2.romRoomSelectors,
            tileSourcePointer = rec.tileSourcePointer,
            dynamicBank = rec.dynamicBank,
          }
        end
      end
    end

    -- Real door-open state for willyRoom specifically (see
    -- rom_profiles.lua's `willyRoom.door`): a SECOND background,
    -- sharing every tile except the door's own cells (patched to their
    -- real open tile IDs) -- built once here (not general -- only
    -- willyRoom is known to have a tile-patch-before-scroll precursor;
    -- a future room needing the same thing would extend this, not
    -- fight it, since it only affects which background image
    -- `:currentBackground()` returns for this one room).
    if profile.graphics.willyRoom then
      local door = profile.graphics.willyRoom.door
      if door then
        local openRoom = {}
        for k, v in pairs(profile.graphics.willyRoom) do openRoom[k] = v end
        local grid = {}
        for r, row in ipairs(profile.graphics.willyRoom.grid) do
          local newRow = {}
          for c, tileId in ipairs(row) do newRow[c] = tileId end
          grid[r] = newRow
        end
        for dr, doorRow in ipairs(door.openGrid) do
          for dc, tileId in ipairs(doorRow) do
            grid[door.bgRow + dr][door.bgCol + dc] = tileId
          end
        end
        openRoom.grid = grid
        self.willyRoomDoorOpenBg = TileGridBackground.new(romData, openRoom)
        self.door = door
      end
    end

    -- ADDED (2026-08-15, second-boss feature -- see rom_profiles.lua's
    -- `sixthRoom.secondBoss` doc comment for the full evidence trail
    -- and honesty caveat: an evidence-based implementation choice, NOT
    -- a claimed ROM-confirmed trigger. CORRECTED twice same day, direct
    -- user reports: first moved from `fourthRoom` to `fifthRoom` (the
    -- room reached through `fourthRoom`'s own real NORTH exit), then
    -- moved AGAIN to `sixthRoom` -- the room reached by walking WEST out
    -- of `fourthRoom`'s own corridor, confirmed via live back-and-forth
    -- with the user in this exact app -- see `sixthRoom.secondBoss`'s
    -- own doc comment for the full correction history). Reuses the
    -- exact same real entities/combat modules
    -- Field.lua's own first-boss fight uses (Enemy/KnockbackFlicker/
    -- AttackSwing/AttackThrust/CombatNoise/CombatFormulas) rather than
    -- a second, parallel implementation -- and the SAME real sprite/
    -- species ROM data (`enemySprite`/`enemyHitFlash`/`enemyDeath`),
    -- matching the user's own "gleiche Grafik" observation.
    -- `self.secondBossDefeated` is real, tracked state (surfaced via
    -- `:debugState()`/the HUD) -- HONEST GAP: `sixthRoom` has no
    -- further real exit recorded at all yet (see that room's own doc
    -- comment), so there is currently no gate for this flag to open.
    --
    -- HONEST SCOPE, simplifications vs. Field.lua's own first-boss
    -- fight: this creature does not move (Field.lua's own
    -- `EnemyMovementInterpreter`/`Enemy.MOVEMENT_CYCLE` patrol is real
    -- ROM-decoded behavior FOR THE FIRST BOSS specifically -- porting
    -- it here would imply the same real per-tick AI drives this second,
    -- unconfirmed encounter too, which this project has no evidence
    -- for) -- it stands at `spawnX`/`spawnY` and fights on contact/
    -- attack exactly like the first boss otherwise does.
    if profile.graphics.sixthRoom and profile.graphics.sixthRoom.secondBoss
        and profile.graphics.enemySprite then
      local sb = profile.graphics.sixthRoom.secondBoss
      local es = profile.graphics.enemySprite
      self.secondBoss = Enemy.new(sb.spawnX, sb.spawnY)
      self.secondBoss.width = es.cols * GBTile.TILE_W
      self.secondBoss.height = es.rowSpacing and ((es.rows - 1) * es.rowSpacing + GBTile.TILE_H)
        or (es.rows * GBTile.TILE_H)
      self.secondBossSprite = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows, nil, es.rowSpacing)
      local flash = profile.graphics.enemyHitFlash
      if flash then
        self.secondBossSpriteFlash = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows,
          TileImage.paletteFromShadeIndices(flash.shadeIndices))
        self.secondBossFlashFrames = flash.frames
      end
      self.secondBossFlashTimer = 0
      local deathData = profile.graphics.enemyDeath
      if deathData then
        self.secondBossDeathSpriteA = CreatureSprite.fromOffsets(romData, deathData.frameA, 2, 1)
        self.secondBossDeathSpriteB = CreatureSprite.fromOffsets(romData, deathData.frameB, 2, 1)
      end
      self.secondBossKnockback = KnockbackFlicker.new()
      self.secondBossDefeated = false
      if profile.graphics.attackSwing then
        self.secondBossAttackSwing = AttackSwing.new(romData, profile)
      end
      if profile.graphics.attackThrust then
        self.secondBossAttackThrust = AttackThrust.new(romData, profile)
      end
      -- Shared real combat PRNG (ROM $2B1E, see Field.lua's own
      -- `combatNoise` doc comment) -- built here too (not shared with
      -- Field.lua's own instance, which belongs to a different state
      -- object entirely by the time this fight is reachable) so the
      -- real damage formula has a genuine noise source instead of
      -- falling back to the fixed placeholder.
      if profile.noiseTable then
        self.combatNoise = CombatNoise.new(NoiseTable.decode(romData, profile.noiseTable))
      end
    end

    -- CORRECTED (2026-08-10, direct user report: "alle NPC und sprites
    -- ... richtig geladen werden"): every OTHER state that creates a
    -- `CreatureSprite` (TitleScreen/NameEntry/BattleIntro/Field) sets
    -- the real hardware sprite palette first (`CreatureSprite
    -- .setDefaultPalette`, real DMG OBP0/OBP1, both $D0 -- see
    -- rom_profiles.lua's `spritePalette` doc comment) -- this state
    -- never did, silently relying on Field.lua having already set it
    -- earlier in the SAME app session (true in the real game flow this
    -- project drives today, TitleScreen->NameEntry->BattleIntro->
    -- Field->VictorySequence, so not an observed failure yet) rather
    -- than being self-sufficient. `PlayerSprite.new` below reads this
    -- exact default (`CreatureSprite.getDefaultPalette()`), so a wrong
    -- pixel index 1 rendering isn't just theoretical for the player
    -- sprite either.
    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end

    -- Real player + Willy sprites for the INTRO cutscene specifically
    -- (see rom_profiles.lua's `graphics.willyScene` doc comment). The
    -- shared palette below is reused for every OTHER room's own `scene`
    -- characters too (same real OBP1 register, not a separate guess
    -- per room).
    --
    -- CORRECTED (2026-08-12, direct user report: "die npc sprites
    -- stimmen nicht"): this used to build `sharedPalette` from
    -- `scene.paletteShadeIndices` (`willyScene`'s own real `0xFB`
    -- capture) -- real bytes, but from the exact instant of a dialogue
    -- box (live re-check found it does NOT hold outside that moment --
    -- see rom_profiles.lua's own corrected doc comment on that field
    -- for the full live re-trace). Every scene character in every room
    -- (Willy at rest, secondRoom's two NPCs) was rendered through this
    -- one-off, dialogue-specific value instead of the real resting
    -- palette. Now uses the SAME already-VERIFIED `spritePalette
    -- .shadeIndices` the player/enemy sprites use (confirmed live to
    -- match secondRoom's and willyRoom's own real free-roam OBP1
    -- exactly, modulo the hardware-transparent id0 slot sprites never
    -- paint anyway).
    -- CORRECTED (2026-08-10, direct user report: "die charakter
    -- animation soll bitte ueberall funktionieren"): the player used a
    -- STATIC `CreatureSprite` here (a single fixed pose) instead of the
    -- real, VERIFIED walk-cycle animation (`PlayerSprite.lua`,
    -- `profile.graphics.playerAnimation`) Field.lua already uses --
    -- meaning the player's own sprite never animated anywhere in this
    -- state (the cutscene, or the whole willyRoom/secondRoom/thirdRoom/
    -- fourthRoom interactive room-chain that follows it). Now uses the
    -- SAME real animation data/logic as Field.lua -- see `:update()`'s
    -- own `self.playerSprite:update(...)` call below for the per-frame
    -- driving half of this fix. Willy himself has no known ROM-side
    -- animation data (only ever captured as a single static pose) so
    -- stays a plain `CreatureSprite`, not a claimed-but-unverified one.
    local scene = profile.graphics.willyScene
    local sharedPalette
    if scene then
      self.sceneData = scene
      self.playerSprite = PlayerSprite.new(romData, profile)
      sharedPalette = profile.graphics.spritePalette
        and TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices)
      self.willySprite = CreatureSprite.fromOffsets(romData, scene.willy.tileOffsets, 2, 2, sharedPalette)
      -- Real, playable continuation -- the live player entity that
      -- takes over once dialogue ends, spawned at the same real
      -- position it stood at during the dialogue.
      self.player = Player.new(scene.player.screenX, scene.player.screenY, 16, 16)
    end
    self.sharedPalette = sharedPalette

    -- willyRoom's own persistent NPC (Willy) is stored under the
    -- separate `willyScene.willy` key (an existing, pre-general-system
    -- convention -- kept as-is rather than duplicated into
    -- `willyRoom.scene`) -- bridge it into the SAME general per-room
    -- scene shape every other room uses, so the general sprite-drawing
    -- code below doesn't need a willyRoom-specific special case.
    if scene and scene.willy and profile.graphics.willyRoom then
      self.roomSceneData = self.roomSceneData or {}
      self.roomSceneData.willyRoom = { willy = scene.willy }
    end

    self.currentRoomKey = "willyRoom"
    self.phase = "cutscene" -- cutscene -> interactive -> transitioning -> dialogue -> interactive ...

    -- FOUND AND FIXED (2026-08-10, direct user report: "wärend des boss
    -- fights hatte ich plötzlich einen schwarten screen"): `:draw()`'s
    -- "top" page branch (the whole 6-line Willy exchange, see `self
    -- .pages` below) shows `willyRoom`'s real background/scene ONLY when
    -- `self:backgroundFor("willyRoom")` returns non-nil -- but
    -- `self.roomBg.willyRoom` was previously populated ONLY by
    -- `ensureRoomLoaded`, which this constructor never called for
    -- willyRoom itself (only `beginTransition`/`completeTransition`/
    -- `enterGameplay` call it, all of which run AFTER every cutscene
    -- page, including the Willy exchange, per this state's own
    -- `phase` doc comment above). So every "top" page silently fell
    -- into the "else" branch (the real black-wipe rectangle, meant only
    -- for "bottom" pages) instead of showing willyRoom -- live-
    -- reproduced via a scripted F6-kill + MYSTICQUEST_SCREENSHOT run:
    -- the Willy dialogue box appeared correctly, but the room art/
    -- player/Willy sprites behind it were solid black the whole time,
    -- matching exactly what the user described. Loading the room here
    -- (AFTER the roomSceneData bridging just above, so Willy's own
    -- sprite scene entry exists in time -- `ensureRoomLoaded` reads it
    -- if present, and only falls back to `room.scene`, which willyRoom
    -- doesn't have, on a first call) fixes both the background AND the
    -- Willy/player sprites for the whole cutscene, not just the later
    -- interactive phase.
    self:ensureRoomLoaded("willyRoom")

    self.pages = {}
    -- CORRECTED (2026-08-10, direct user report: "die gesammte start
    -- boss sequence ist noch nicht komplett... der willy dialog ist
    -- nicht vollstaendig"): `data.victoryLine` is REAL text but a fresh
    -- live re-trace found it does NOT open this sequence (see that
    -- field's own doc comment in rom_profiles.lua) -- no longer inserted
    -- here. `data.storyPages` used to be the real, complete 3-page
    -- sequence AS A HAND-TRANSCRIPTION (was 1 page, silently truncated
    -- mid-sentence, with an honestly-flagged-but-unfilled gap after it
    -- -- both closed on 2026-08-10, but still by hand-typing what a
    -- screenshot showed, same status as the old Willy-exchange lines).
    --
    -- LIVE-DECODED (2026-08-12, "ja bitte alles in dieser reinfolge",
    -- direct continuation of the SAME session's Willy-exchange work
    -- above): these 3 pages sit in the exact same bank-14 dialogue
    -- block the Willy-exchange offsets do, immediately BEFORE them
    -- (file `0x3A1E5`-`0x3A24F`, vs. the Willy exchange's own
    -- `0x3A268` onward) -- found as a direct side effect of that same
    -- full-ROM scan, not a fresh investigation. Each offset confirmed
    -- via `TextDecoder.decodeString` decoding cleanly end to end, same
    -- bar every other live-wired line here has to clear.
    --
    -- Real, honest differences from the old hand-transcription, kept
    -- as the real bytes decode (same "the real bytes win" rule as the
    -- Willy exchange above), NOT reconciled to match the old guesses:
    --   * Page 1's real ROM text uses actual mid-word HYPHENATION at
    --     its own line breaks ("an-\ndere", "ge-\nzwungen" -- the real
    --     `HYPHEN_BYTE`, see `TextDecoder.lua`) where the old hand-
    --     wrap broke at word boundaries instead ("viele\nandere",
    --     "jeden\nTag"). This project's own `TextBox.lua` doesn't
    --     implement general word-wrap/hyphenation (see that module's
    --     own doc comment) -- the real ROM's own line breaks are used
    --     literally here instead, which is MORE correct, not less
    --     (this project reproducing the ROM's own actual wrap points,
    --     rather than inventing a readable substitute, whenever the
    --     real bytes are available for a specific line -- see
    --     `TextBox.lua`'s doc comment for why that's not done
    --     automatically everywhere yet).
    --   * Page 2's real ROM text wraps as "des Dark Lord, zu\nkämpfen."
    --     -- the old hand-transcription had "des Dark Lord,\nzu
    --     kaempfen." (a different, plausible-looking wrap point, and
    --     the old ASCII "ae" instead of the real "ä").
    --   * Page 3's real ROM text is "Viele ließen\ndabei unnötig ihr\n
    --     Leben" -- confirmed via the raw bytes immediately following
    --     (a real `[0x12][0x11]` box-close marker, not a period byte)
    --     that the real ROM box has NO trailing period here at all --
    --     the old hand-transcription's "...Leben." period is not real
    --     ROM data, so it's dropped, not kept.
    --
    -- Only page 1 needs the real player-entered `heroName` (see
    -- NameEntry.lua) prefixed on -- its own real ROM bytes start with
    -- a literal SPACE_BYTE (" und viele an-...") right where the name
    -- belongs, i.e. the real ROM's own name-insertion mechanism (a
    -- `[0x14]`-style control byte immediately before this offset, the
    -- same still-not-reverse-engineered family as the Willy exchange's
    -- own `[14][2c]` speaker tags above -- not decoded here either)
    -- sits OUTSIDE this decoded range, so simple string concatenation
    -- reproduces the real result without needing to understand that
    -- byte. Pages 2/3 are Willy/narration continuing, no name needed.
    local STORY_PAGE_OFFSETS = { 0x3A1E5, 0x3A208, 0x3A234 }
    for i, offset in ipairs(STORY_PAGE_OFFSETS) do
      local text = TextDecoder.decodeString(romData, offset)
      if i == 1 then
        text = heroName .. text
      end
      self.pages[#self.pages + 1] = { text = text, box = "bottom" }
    end
    -- CORRECTED (2026-08-10, same re-trace): this project's own earlier
    -- Willy exchange was built from an incomplete/misremembered capture.
    -- Re-walked the whole exchange live, one real `A` tap at a time, with
    -- generous typewriter-reveal waits between each so no page's content
    -- was missed (the same trap rom-map.md already documents: mashing
    -- too fast skips real box content). Real corrections found, in
    -- order: (1) the real ROM shows "<name>: WILLY!" and "Willy: Mana
    -- ist in Gefahr." together in ONE box (this project previously split
    -- them into two separate pages); (2) a whole real line was missing
    -- between the "Bogard"/waterfalls hint and the "Gemma? -- Mana?"
    -- panic line: "Er ist ein Gemma Ritter. Er weiss, was zu tun ist."
    -- (Willy explaining who Bogard is); (3) the panic line itself was
    -- truncated -- the real box continues "...WILLY!?" with a second,
    -- louder "WILLY!!!"; (4) the real sequence ends with a genuinely new
    -- line, "Willy entschlaeft" ("Willy falls still/asleep" -- the game's
    -- own real, gentle phrasing for his death), immediately followed by
    -- real free movement -- this project's own previous closing line,
    -- "<name>: Willy... Ich raeche Dich!", never appeared anywhere in
    -- this fresh trace and is REMOVED as a fabrication, not kept as a
    -- stylistic addition.
    --
    -- CORRECTED AGAIN (2026-08-12, direct user report: "die texte
    -- scheinen in fast allen dialogen nicht 100% korrekt"): a whole real
    -- box was STILL missing, between "Mana ist in Gefahr." and "Gemma?"
    -- -- found this time by decoding the real ROM bytes directly (not
    -- live-watching a screenshot), now that `TextDecoder.lua`'s own
    -- digraph table is far more complete than it was during the
    -- 2026-08-10 re-trace: file offset `0x3A287`-ish (bank 14, the same
    -- ~26KB dialogue region `storyPages` was independently found in)
    -- decodes as `"Gemma Ritter\nm[81]ssen da[59]w[54]sen[12][1B]"` --
    -- fully unambiguous German with 3 still-genuinely-unmapped bytes
    -- (this project's own "2+ independent occurrences" bar isn't
    -- cleared for them yet, so they're not added to `TextDecoder.lua`'s
    -- digraph table from this alone) -- "Gemma Ritter müssen das
    -- wissen." ("The Gemma Knights must know this"), real bytes, a real
    -- `[0x12][0x1B]` box-close-continue immediately after, sitting
    -- directly between the two already-VERIFIED boxes either side of
    -- it. This is almost certainly the exact SAME fragment this
    -- project's own much earlier 2026-08-08 pass ("sixth pass", see
    -- text.md) read visually off a screenshot as "Die Gemma Ritter
    -- müssen das wissen" -- back then a byte-level match attempt failed
    -- and it was written off as a likely misread; it wasn't a misread,
    -- the decoder just wasn't complete enough yet to confirm it. Left
    -- as "Willy:" (matching the surrounding boxes' own speaker, and the
    -- narrative -- Willy explaining, the hero replying "Gemma?" in
    -- confusion right after) -- the raw bytes decoded here don't
    -- themselves carry a `[14][0x2C]`/named-speaker tag the way the
    -- neighboring boxes do, so the speaker attribution is this
    -- project's own reasonable inference, not directly decoded.
    --
    -- LIVE-DECODED (2026-08-12, quick win #3, "1 dann 2 dann 3 dann 4"):
    -- this line used to be the hand-transcribed literal string above
    -- (kept in the doc comment history above for the record) -- now that
    -- every byte in this specific sentence has a real, 2+-occurrence-
    -- verified `DIGRAPH_PARTIAL` entry (see `tests/import/
    -- text_decoder_test.lua`'s own "the real missing Willy-exchange box"
    -- test, which locks in this exact offset/output), it's decoded LIVE
    -- from the real ROM bytes at file offset `0x3A28B` instead of typed
    -- by hand. Real, honest difference from the old hand-transcription:
    -- the decoded text has no trailing period and wraps after "Ritter"
    -- (not after "das") -- the real ROM bytes end in a `[0x12][0x1B]`
    -- box-close-continue control pair, not a punctuation byte, and the
    -- real ROM's own single embedded newline lands there, not where the
    -- old hand-wrap guessed. Not silently "corrected" to match the old
    -- text -- the real bytes win. The "Willy:" speaker prefix stays a
    -- reasonable inference (see the doc comment above), not itself
    -- decoded.
    --
    -- The prefix gets its OWN line (`"Willy:\n" .. decoded`, not
    -- `"Willy: " .. decoded`) rather than sharing a line with "Gemma
    -- Ritter" -- caught live (2026-08-12, `love .` smoke screenshot,
    -- per this project's own "look at the screenshot" rule): the "top"
    -- box (`BOX_GEOMETRY.top`, 19 tiles wide, 8px padding each side) has
    -- real room for only 17 characters per line (`(19*8 - 16) / 8`),
    -- and "Willy: Gemma Ritter" is 19 -- two characters past the edge,
    -- silently clipped off-screen instead of erroring. A real, general
    -- box-width bug (not specific to live-decoded text -- the OLD
    -- hand-typed line was the exact same 19-character string and would
    -- have overflowed identically; it just never got its own live
    -- screenshot check before now). This is a display-only rewrap
    -- (moving where the SPEAKER PREFIX breaks, which was never itself
    -- decoded ROM data) -- it does not touch the real decoded sentence's
    -- own internal newline between "Ritter" and "müssen das wissen".
    local gemmaRitterLine = "Willy:\n" .. TextDecoder.decodeString(romData, 0x3A28B)

    -- LIVE-DECODED, the rest of the Willy exchange (2026-08-12, "alle 3
    -- in der vorgeschlagenen reinfolge", quick win #2 of this batch --
    -- direct continuation of the `gemmaRitterLine` method above).
    -- Found all 5 remaining real ROM offsets in one pass: fixed
    -- `tools/rom/dump_strings.py`'s own `UMLAUT_PARTIAL` table first
    -- (it had silently drifted out of sync with `TextDecoder.lua`'s
    -- real UTF-8-umlaut correction from 2026-08-10 -- was still
    -- emitting the old "ae"/"oe"/"ue"/"ss" 2-letter substitutions,
    -- which made a few of these lines LOOK like they might have a
    -- real ROM spelling quirk worth double-checking, and didn't --
    -- see that file's own doc comment), then re-ran a full-ROM scan
    -- and grepped for keywords from each hardcoded line ("Bogard",
    -- "Wasserfaellen", "entschlaeft", ...) -- every one of them turned
    -- up in the SAME bank-14 dialogue region `gemmaRitterLine` above
    -- already lives in (file `0x3A1E5`-`0x3A416`), confirming this is
    -- one continuous, fully real, fully decodable block, not isolated
    -- lucky finds.
    --
    -- Cross-checked every fragment against `TextDecoder.decodeString`
    -- directly (not just the scan's own maximal-run output) to confirm
    -- each one decodes CLEANLY end to end with a real stop point (a
    -- `[0x12]` box-close marker or a clean NUL terminator), the same
    -- bar `gemmaRitterLine` above already had to clear. Two of the five
    -- decode to text that's honestly, materially DIFFERENT from the
    -- old hand-transcription -- kept as the real bytes decode, not
    -- silently reconciled to match the old guess (same "the real bytes
    -- win" rule as `gemmaRitterLine` above):
    --   * "Willy: Geh zu\nBogard bei den\nWasserfaellen." (old) vs. the
    --     real "Geh zu\nBogard beiden\nWasserfällen." (file 0x3A2AE) --
    --     "beiden" is genuinely one word in the real ROM text (not "bei
    --     den"), and "Wasserfällen" has its real umlaut (the old ASCII
    --     "ae" substitution was this project's own earlier best-effort
    --     transcription, not a real ROM spelling).
    --   * "Er ist ein Gemma\nRitter. Er weiß,..." (old) vs. the real
    --     "Er ist ein Gemma\nRitter! Er weiß,..." (file 0x3A2C9) -- an
    --     exclamation mark, not a period.
    -- The third and fourth boxes below (`gemmaQuestionLine`, real file
    -- offsets 0x3A2A3/0x3A2AE/0x3A2C9) need no box-width rewrap (all
    -- their real lines measure under the "top" box's own 17-char
    -- limit, see `gemmaRitterLine`'s own doc comment for where that
    -- limit comes from) -- unlike `gemmaRitterLine`, the "Willy: "/
    -- speaker prefix can stay on the same line as the real text here.
    --
    -- The panic-line box (`willyPanicLine` below, heroName..": Gemma?
    -- --\nMana? Was ...\nWILLY!? WILLY!!!") is real ROM text spread
    -- across FOUR separate `decodeString` runs (files 0x3A2ED/0x3A2F8/
    -- 0x3A306/0x3A312), each separated by a real, consistent 3-byte gap
    -- (`f0 1e 04` or `f0 3c 04`) that does NOT decode as text under
    -- this project's own `TextDecoder` -- honestly NOT reverse-
    -- engineered further this pass (this looks like a distinct,
    -- context-dependent script-control grammar, reusing byte VALUES
    -- `TextDecoder` otherwise treats as digraph text, e.g. `0x1e`/
    -- `0x3c` -- a real, separate investigation, not solved here; see
    -- rom-map.md's honest note). The four clean fragments concatenate,
    -- with their own real embedded newlines, to the intended sentence
    -- with zero manual rewrapping needed. One small, honest, real-bytes
    -- difference from the old hand-transcription found here too: real
    -- ROM has "Mana?Was ..." with NO space after "Mana?" (old
    -- hand-transcription had "Mana? Was ..." with a space).
    --
    -- The closing box (`willySleepsLine` below, file 0x3A322) decodes
    -- to `"\nWilly entschläft"` -- WITH a real leading newline the old
    -- hand-transcription never had, i.e. the real ROM box shows a
    -- blank first line before "Willy entschläft" appears on line 2.
    -- Kept as the real bytes decode (same rule as above) rather than
    -- trimmed to match the old single-line version.
    local gemmaQuestionLine = heroName .. ": " .. TextDecoder.decodeString(romData, 0x3A2A3)
    local bogardLine = "Willy: " .. TextDecoder.decodeString(romData, 0x3A2AE)
    local gemmaKnightLine = TextDecoder.decodeString(romData, 0x3A2C9)
    local willyPanicLine = heroName .. ": " ..
      TextDecoder.decodeString(romData, 0x3A2ED) ..
      TextDecoder.decodeString(romData, 0x3A2F8) ..
      TextDecoder.decodeString(romData, 0x3A306) ..
      TextDecoder.decodeString(romData, 0x3A312)
    local willySleepsLine = TextDecoder.decodeString(romData, 0x3A322)

    for _, line in ipairs({
      heroName .. ": WILLY!\nWilly: Mana ist\nin Gefahr.",
      gemmaRitterLine,
      gemmaQuestionLine,
      bogardLine,
      gemmaKnightLine,
      willyPanicLine,
      willySleepsLine,
    }) do
      self.pages[#self.pages + 1] = { text = line, box = "top" }
    end
  end

  -- Dev/CI-only: MYSTICQUEST_VICTORY_START_ROOM=<roomKey> (2026-08-14,
  -- added directly to investigate a batch of user-reported bugs in
  -- fourthRoom without replaying the whole willyRoom->secondRoom->
  -- thirdRoom cutscene/movement chain first every single launch).
  -- Jumps straight to `<roomKey>` in the real "interactive" phase,
  -- reusing the SAME real commit path every ordinary transition uses
  -- (`switchToTargetRoom`, so `landingX`/`landingY` and room-loading
  -- stay byte-for-byte identical to a real playthrough reaching that
  -- room) -- found by looking up the first real `exits` entry, from
  -- ANY room in `profile.graphics`, whose own `targetRoom` matches.
  -- Fails loudly (not a silent no-op) if no such exit exists, so a
  -- typo'd room name doesn't just quietly leave the player in
  -- willyRoom -- this project's own "no silent fallbacks" rule.
  -- Never armed unless the env var is set.
  local debugStartRoom = os.getenv("MYSTICQUEST_VICTORY_START_ROOM")
  if debugStartRoom and self.data then
    local foundExit
    for _, roomData3 in pairs(profile.graphics) do
      if type(roomData3) == "table" and roomData3.exits then
        for _, exit in ipairs(roomData3.exits) do
          if exit.targetRoom == debugStartRoom then
            foundExit = exit
            break
          end
        end
      end
      if foundExit then break end
    end
    assert(foundExit, "MYSTICQUEST_VICTORY_START_ROOM: no real exit targets room '" ..
      debugStartRoom .. "' -- check the room key against rom_profiles.lua's own graphics table")
    self:switchToTargetRoom(foundExit)
    self.phase = "interactive"
  end

  return self
end

function VictorySequence:currentPage()
  return self.pages and self.pages[self.pageIndex]
end

--- Lazily builds (and caches) the real background/collision/sprites for
-- `roomKey` -- called the first time the room graph reaches a room, so
-- a long chain doesn't need to build every room up front.
function VictorySequence:ensureRoomLoaded(roomKey)
  if self.roomBg[roomKey] then return end
  local room = self.profile.graphics[roomKey]
  if not room then return end
  self.roomBg[roomKey] = TileGridBackground.new(self.romData, room)
  -- UPGRADED (2026-08-14, task "Kollision generalisieren"): willyRoom
  -- specifically now uses real, ROM-decoded, POSITION-AWARE collision
  -- (`RoomFloorLayout.buildCollisionGrid` against its own real metatile
  -- table, with its own ground-truth-derived `isWalkableCollisionWillyFamily`
  -- rule -- see that function's own doc comment for the full exhaustive
  -- derivation: matches the room's previous, live-tested `floorTileIds`
  -- classification exactly, cell for cell, all 320 real grid cells, zero
  -- disagreement -- see tests/import/room_floor_layout_test.lua) instead
  -- of the flat, heuristic `floorTileIds` set every other room still
  -- uses. Provably behavior-preserving (same test), so this is a real
  -- "guess -> decoded ROM fact" upgrade, not a gameplay change -- every
  -- other room keeps the flat approach until it gets its own real
  -- metatile-table ground truth the same way.
  if roomKey == "willyRoom" then
    local layout = self.profile.roomFloorLayoutPipeline.exampleRoom
    local collisionGrid = RoomFloorLayout.buildCollisionGrid(
      self.romData, layout, RoomFloorLayout.isWalkableCollisionWillyFamily)
    self.roomWalk[roomKey] = TileWalkability.buildFromCollisionGrid(collisionGrid, 16, 16)
  else
    self.roomWalk[roomKey] = TileWalkability.build(room, 16, 16)
  end

  local sceneData = (self.roomSceneData and self.roomSceneData[roomKey]) or room.scene
  if sceneData then
    self.roomSceneData = self.roomSceneData or {}
    self.roomSceneData[roomKey] = sceneData
    self.roomSprites[roomKey] = {}
    -- ADDED (2026-08-10, see rom_profiles.lua's `secondRoom.scene
    -- .characterA/B.animation` doc comment): a scene character with a
    -- real `animation` table (secondRoom's two NPCs) gets a real,
    -- animated `NpcSprite` AND its own live wander state instead of the
    -- old static `CreatureSprite.fromOffsets(..., 2, 2, ...)` build --
    -- which used real bytes from the WRONG region (this project's own
    -- font graphics) through the WRONG shape (2x2, not the real 8x16
    -- single-column layout) for these two specifically. Characters with
    -- no `animation` table (Willy) are untouched -- still a plain static
    -- 2x2 `CreatureSprite`, matching this module's own doc comment on
    -- why Willy stays that way (no real ROM animation data for him).
    self.roomNpcState[roomKey] = self.roomNpcState[roomKey] or {}
    for name, char in pairs(sceneData) do
      if char.animation then
        self.roomSprites[roomKey][name] = NpcSprite.new(
          self.romData, char.animation, self.sharedPalette)
        self.roomNpcState[roomKey][name] = self.roomNpcState[roomKey][name] or {
          x = char.screenX, y = char.screenY, facing = "down",
          wanderDir = nil, wanderTimer = 0,
        }
      else
        self.roomSprites[roomKey][name] = CreatureSprite.fromOffsets(
          self.romData, char.tileOffsets, 2, 2, self.sharedPalette)
      end
    end
  end
end

--- Advances one real frame of the room's own wandering NPCs (see
-- rom_profiles.lua's own doc comment for the real animation-tile
-- evidence vs. this project's own honestly-approximate random-walk
-- movement -- direct user report: "diese [npcs] haben animationen und
-- bewegungspattern"). A no-op for a room with no animated NPCs (most
-- rooms -- `self.roomNpcState[roomKey]` is only ever populated for
-- characters that have a real `animation` table). The actual per-frame
-- decision (`NpcWander.step`) is a pure, headlessly-tested module (see
-- src/entities/NpcWander.lua) -- this method is just the love-side
-- plumbing (iterating this room's live states, driving each one's
-- `NpcSprite`).
function VictorySequence:updateNpcWander(dt, roomKey)
  local states = self.roomNpcState[roomKey]
  local sprites = self.roomSprites[roomKey]
  if not states then return end
  local canMoveTo = self.roomWalk[roomKey]
  for name, st in pairs(states) do
    local moving = NpcWander.step(st, dt, canMoveTo)
    local sprite = sprites and sprites[name]
    if sprite then
      sprite:update(dt, moving, st.facing)
    end
  end
end

--- The real background image currently shown for `roomKey` -- almost
-- always just the room's own plain background, except willyRoom, which
-- has a real second (door-open) state once its door has been triggered
-- (see `willyRoomDoorOpenBg` above).
function VictorySequence:backgroundFor(roomKey)
  if roomKey == "willyRoom" and self.doorOpened and self.willyRoomDoorOpenBg then
    return self.willyRoomDoorOpenBg
  end
  return self.roomBg[roomKey]
end

--- Checks the current room's real `exits` (rom_profiles.lua) against
-- the player's current position -- returns the first matching exit, or
-- nil. A `zone` field may omit any of xMin/xMax/yMin/yMax, meaning
-- "unbounded on that side." The actual matching (`ZoneMatch.first`) is
-- a pure, headlessly-tested module (see src/entities/ZoneMatch.lua,
-- extracted 2026-08-10 -- this exact logic is where the same-day
-- secondRoom east-exit regressions lived, undetected by the test suite
-- because this whole file needs love.graphics to even require()).
--
-- EXTENDED (2026-08-13, "fourthRoom->fifthRoom-Lücken schließen"): an
-- exit MAY declare a real `holdFrames`/`holdDirection` pair (see
-- `fourthRoom.exits`'s own doc comment in rom_profiles.lua for the real
-- ROM evidence: a real cut-transition that needs the player held
-- against a wall for ~64 real frames, not firing the instant the zone
-- is entered) -- an exit WITHOUT these fields behaves exactly as
-- before, firing the instant `ZoneMatch` matches (every other real exit
-- found so far). The actual hold-tracking decision (`HoldTrigger.step`)
-- is, same as `ZoneMatch`, a pure, headlessly-tested module --
-- `self.holdTriggerState` is the only love-side state this method owns,
-- keyed by the real exit table itself (stable identity across frames,
-- reset to `{}` the instant the player isn't standing in ANY zone, so a
-- partial hold doesn't silently carry over into an unrelated exit).
function VictorySequence:matchedExit()
  local room = self.profile.graphics[self.currentRoomKey]
  if not room then return nil end
  local exit = ZoneMatch.first(room.exits, self.player.x, self.player.y)
  if not exit then
    self.holdTriggerState = nil
    return nil
  end
  -- ADDED (2026-08-15, second-boss feature): a real, general capability
  -- for "gate this exit behind some state flag" (an exit naming a real
  -- field on `self` via `requiresFlag` simply never matches while that
  -- field isn't true yet, same as standing outside the zone entirely --
  -- no partial hold progress accumulates while gated), mirroring
  -- willyRoom's own real door-after-boss pattern in general shape.
  -- HONEST STATUS: no `exits` entry in rom_profiles.lua actually sets
  -- `requiresFlag` right now -- `sixthRoom` (where the second boss
  -- actually lives, see that room's own `secondBoss` doc comment) has
  -- no further real exit recorded at all yet to gate -- so this is
  -- real, tested infrastructure ready for whenever one is found, not
  -- something currently wired to a live gate.
  if exit.requiresFlag and not self[exit.requiresFlag] then
    self.holdTriggerState = nil
    return nil
  end
  if not exit.holdFrames then
    return exit
  end
  self.holdTriggerState = self.holdTriggerState or {}
  local state = self.holdTriggerState[exit]
  if not state then
    state = { frames = 0 }
    self.holdTriggerState[exit] = state
  end
  -- No `exit.holdDirection` means "any input satisfies the hold" (not
  -- currently a real case this project has evidence for, but a
  -- reasonable default); WITH one, real confirmation requires
  -- `self.input` to actually report it held -- a missing `self.input`
  -- (a dev/test construction with no real input) never satisfies a
  -- required direction, rather than silently treating it as held.
  local directionHeld = not exit.holdDirection or (self.input and self.input:isDown(exit.holdDirection))
  if HoldTrigger.step(state, directionHeld, exit.holdFrames) then
    return exit
  end
  return nil
end

--- Checks the current room's named scene characters (rom_profiles.lua's
-- `scene.<name>.dialogue`) for a real, one-shot proximity trigger --
-- returns `(lines, name)` for the first matched, not-yet-shown NPC, or
-- nil. ADDED 2026-08-10 (direct user report: "der dialog wird beim
-- betreten des raums getriggert"): the general room-graph engine's
-- existing `exits.dialoguePages` mechanism (room-ENTRY-triggered) was
-- being reused for NPC dialogue too, but a fresh live re-trace disproved
-- that entirely for `secondRoom`'s own two NPCs -- idling 900 real
-- frames with zero input right after landing produced no dialogue at
-- all, while walking up to one of the NPCs did, instantly, with no
-- button press needed. This is a genuinely different trigger shape
-- (per-character proximity, not a room-wide zone), so it's its own
-- method rather than bent to fit `matchedExit`'s. The proximity box
-- (`pad` below) is a reasonable approximation, same "not independently
-- pixel-verified" honesty status as KnockbackFlicker.lua's own
-- knockback-direction extrapolation -- the real trigger radius wasn't
-- separately bracketed this pass.
-- The actual matching (`NpcProximity.match`) is a pure, headlessly-
-- tested module (see src/entities/NpcProximity.lua) -- this method is
-- just the love-side plumbing (this room's live scene/wander-state
-- tables, the one-shot `npcDialogueShown` set).
function VictorySequence:matchedNpcDialogue()
  local sceneData = self.roomSceneData and self.roomSceneData[self.currentRoomKey]
  local wanderState = self.roomNpcState[self.currentRoomKey]
  local roomKey = self.currentRoomKey
  return NpcProximity.match(sceneData, wanderState, self.player, function(name)
    return self.npcDialogueShown[roomKey .. ":" .. name] == true
  end)
end

--- Starts a real transition along `exit` -- a hardware scroll (real
-- per-frame pixel rate, either axis) or a real "cut" (jump-cut) --
-- see rom_profiles.lua's `exits` schema doc comment for what each real
-- transition type means.
--
-- CORRECTED (2026-08-14, direct user instruction: "bei jump cut
-- übergängen gibt es entweder einen wipecut von oben und unten oder
-- eine blende auf schwarz. bitte suche im rom nach den algorithmen
-- dafür und implementiere es"): a real "cut" used to complete
-- INSTANTLY, with zero visual effect -- a real gap, since a live trace
-- of the real thirdRoom->fourthRoom staircase cut found a genuine,
-- real, ROM-timed visual (the old room closing to a thin horizontal
-- band, symmetric top+bottom, then the new room reopening the same
-- way) -- see `RoomWipeTransition.lua`'s own doc comment for the full
-- live-trace evidence. `"cutClosing"`/`"cutOpening"` are the two new
-- real phases driving this.
function VictorySequence:beginTransition(exit)
  self:ensureRoomLoaded(exit.targetRoom)
  if self.currentRoomKey == "willyRoom" then
    -- Real tile-patch precursor (the door itself flipping open) --
    -- willyRoom-specific, see `backgroundFor`. CORRECTED (2026-08-10):
    -- used to be additionally gated on `exit.dialoguePages` (true for
    -- willyRoom's only exit at the time) -- that field is now removed
    -- (see this room's own `exits` doc comment in rom_profiles.lua, a
    -- real, unrelated dialogue-trigger correction), so the door-opening
    -- itself is now keyed on the room alone, matching what it actually
    -- represents (a real visual precursor to willyRoom's own exit, not
    -- something that should depend on whether that exit happens to also
    -- carry dialogue).
    self.doorOpened = true
  end
  self.pendingExit = exit
  if exit.transition.type == "cut" then
    self.phase = "cutClosing"
    self.cutFrame = 0
  else
    self.phase = "transitioning"
    self.transitionFrame = 0
  end
end

--- Switches the current room and places the player at `exit`'s real
-- (or reasonably-placed, see rom_profiles.lua) landing spot -- the
-- real "commit" moment shared by every transition kind, factored out
-- so the scroll path (`completeTransition`, unchanged) and the cut
-- path (`update`'s own `"cutClosing"` handling, below) can each call
-- it at their own real correct moment (immediately for a scroll;
-- only once the closing wipe has fully covered the screen for a cut,
-- matching the real ROM's own room-pointer commit timing).
function VictorySequence:switchToTargetRoom(exit)
  self.currentRoomKey = exit.targetRoom
  self:ensureRoomLoaded(self.currentRoomKey)
  if self.player then
    if exit.landingX then self.player.x = exit.landingX end
    if exit.landingY then self.player.y = exit.landingY end
  end
end

--- Starts whatever real phase should follow `exit` once its own
-- transition (scroll or cut) has fully finished -- its own real
-- dialogue, or straight back to free movement.
function VictorySequence:enterPostExitPhase(exit)
  if exit.dialoguePages then
    self.phase = "dialogue"
    self.dialoguePages = exit.dialoguePages
    self.dialoguePageIndex = 1
    self.dialogueStartFrame = self.frame
  else
    self.phase = "interactive"
  end
end

--- Finishes a real hardware-scroll transition (the SCROLL path only --
-- a real cut goes through `switchToTargetRoom`/`enterPostExitPhase`
-- directly from `update`, see above).
function VictorySequence:completeTransition()
  local exit = self.pendingExit
  self:switchToTargetRoom(exit)
  self.pendingExit = nil
  self:enterPostExitPhase(exit)
end

function VictorySequence:update(dt)
  if self.done or not self.pages then return end

  -- REAL ScriptInterpreter, ticked once per real frame (2026-08-15, see
  -- this module's own top-of-file "REWRITTEN" doc comment) -- runs
  -- BEFORE the `self.phase` dispatch below (deliberately unconditional
  -- on `self.phase`, matching the real ROM's own boss-defeat script,
  -- which is a fully separate mechanism from this state's own hand-
  -- authored phase machine, not gated by it). A genuine per-frame
  -- dispatch attempt, exactly matching `BossSequenceInterpreter:tick`'s
  -- own doc comment ("meant to be called once per real game frame") --
  -- replaces the OLD one-shot construction-time burst, which could never
  -- pace real per-frame effects (the typewriter tick, a real conditional
  -- halt) correctly even in principle. Still pure observation -- see
  -- `self.bossSequenceInterpreter`'s own doc comment for why nothing
  -- here reads its result.
  if self.bossSequenceInterpreter and not self.bossSequenceInterpreter.done then
    self.bossSequenceFrameCounter.n = self.bossSequenceFrameCounter.n + 1
    self.bossSequenceInterpreter:tick()
  end

  -- Dev-only escape hatch (same convention as BattleIntro.lua's SELECT
  -- skip) -- not real ROM behavior.
  if self.input and self.input:pressed("select") then
    self:finish()
    return
  end

  if self.phase == "interactive" then
    local room = self.profile.graphics[self.currentRoomKey]
    local bounds = { 0, 0, ROOM_W - 16, ROOM_H - HUD_H - 16 }
    local inSecondBossRoom = self.currentRoomKey == "sixthRoom" and self.secondBoss ~= nil
      and not self.secondBossDefeated
    if self.player and self.roomWalk[self.currentRoomKey] then
      local prevX, prevY = self.player.x, self.player.y
      self.player:update(dt, self.input, bounds, self.roomWalk[self.currentRoomKey])
      -- Real "blocked against a living enemy" collision (same rule
      -- Field.lua's own first-boss fight uses) -- only checked in
      -- sixthRoom while its own second boss is alive, so every other
      -- room's movement is completely unaffected.
      if inSecondBossRoom and self.secondBoss:isAlive() and
          self.secondBoss:overlaps(self.player.x, self.player.y, self.player.width, self.player.height) then
        self.player.x, self.player.y = prevX, prevY
      end
      -- Real walk-cycle animation (see this state's own `playerSprite`
      -- doc comment above) -- same per-frame drive as Field.lua's own.
      if self.playerSprite then
        self.playerSprite:update(dt, self.player.moving, self.player.facing)
      end
    end

    -- ADDED (2026-08-15, second-boss feature -- see rom_profiles.lua's
    -- `sixthRoom.secondBoss` doc comment). Direct port of Field.lua's
    -- own first-boss combat loop (contact damage + knockback, real A-
    -- button attack with the real swing-vs-thrust choice, real per-
    -- phase hitbox detection, real death "explosion") against this
    -- room's own second `Enemy` instance -- see that file's own
    -- `:update()` for the original, more heavily-commented version this
    -- mirrors line for line. Entirely gated on `inSecondBossRoom` so it
    -- never runs (and never even reads `self.secondBoss*` fields) in
    -- any other room.
    if inSecondBossRoom then
      -- Deliberately NOT calling `self.secondBoss:updateMovement(dt)`
      -- (unlike Field.lua's own first-boss fight) -- without a real
      -- `movementInterpreter`, `Enemy:updateMovement` falls back to the
      -- OLD `MOVEMENT_CYCLE` patrol step, which would make this second
      -- boss visibly walk a real pattern that was live-derived FOR THE
      -- FIRST boss specifically -- this project has no evidence that
      -- pattern applies here too, so this creature stays still instead
      -- of silently inheriting unrelated real ROM behavior.
      if self.secondBossFlashTimer > 0 then
        self.secondBossFlashTimer = self.secondBossFlashTimer - 1
      end
      if self.secondBoss:isAlive() and
          self.secondBoss:overlaps(self.player.x, self.player.y, self.player.width, self.player.height) then
        if self.secondBoss:tickContactCooldown(dt) and not self.secondBossKnockback:isInvincible() then
          local damage
          if self.combatNoise then
            damage = CombatFormulas.rollDamage(Enemy.ATK, self.stats.defense, self.combatNoise:draw())
          else
            damage = Enemy.CONTACT_DAMAGE
          end
          self.stats:damage(damage)
          self.secondBossKnockback:trigger(
            self.secondBoss.x + self.secondBoss.width / 2, self.secondBoss.y + self.secondBoss.height / 2,
            self.player.x + self.player.width / 2, self.player.y + self.player.height / 2)
        end
      end
      local kdx, kdy = self.secondBossKnockback:update(dt)
      if self.secondBossKnockback:isKnockbackActive() then
        local newX, newY = self.player.x + kdx, self.player.y + kdy
        local canMoveTo = self.roomWalk[self.currentRoomKey]
        if kdx ~= 0 and (not canMoveTo or canMoveTo(newX, self.player.y)) then self.player.x = newX end
        if kdy ~= 0 and (not canMoveTo or canMoveTo(self.player.x, newY)) then self.player.y = newY end
        self.player.x = math.max(bounds[1], math.min(bounds[3], self.player.x))
        self.player.y = math.max(bounds[2], math.min(bounds[4], self.player.y))
      end

      if self.input and self.input:pressed("a") then
        local attack = self.player.moving and self.secondBossAttackThrust or self.secondBossAttackSwing
        if attack then
          attack:trigger(self.player.facing)
          self.secondBossAttackHasHit = false
        end
      end
      if self.secondBossAttackSwing then self.secondBossAttackSwing:update(dt) end
      if self.secondBossAttackThrust then self.secondBossAttackThrust:update(dt) end

      local activeAttack = (self.secondBossAttackSwing and self.secondBossAttackSwing:isActive() and self.secondBossAttackSwing)
        or (self.secondBossAttackThrust and self.secondBossAttackThrust:isActive() and self.secondBossAttackThrust)
      if activeAttack and not self.secondBossAttackHasHit and self.secondBoss:isAlive() then
        for _, box in ipairs(activeAttack:getHitboxes(self.player.x, self.player.y)) do
          if self.secondBoss:overlaps(box.x, box.y, box.w, box.h) then
            self.secondBossAttackHasHit = true
            if self.secondBossSpriteFlash then
              self.secondBossFlashTimer = self.secondBossFlashFrames
            end
            if self.secondBoss:hit() then
              self.secondBoss:startDeath(self.profile)
            end
            break
          end
        end
      end

      if self.secondBoss.death and not self.secondBossDefeated then
        self.secondBoss:updateDeath(dt)
        if self.secondBoss:deathComplete() then
          self.secondBossDefeated = true
        end
      end
    end

    -- ADDED (2026-08-10, direct user report: "diese [npcs] haben
    -- animationen und bewegungspattern" -- see `updateNpcWander`'s own
    -- doc comment): a no-op for any room without animated NPCs.
    self:updateNpcWander(dt, self.currentRoomKey)
    -- ADDED (2026-08-10, see `matchedNpcDialogue`'s own doc comment):
    -- checked BEFORE `matchedExit` -- a room's own NPCs sit well inside
    -- its exit zones, never overlapping them in practice, so the order
    -- doesn't matter for correctness today, but dialogue is the more
    -- specific/local trigger of the two, so it takes priority on
    -- principle if a future room ever did overlap them.
    local npcLines, npcName = self:matchedNpcDialogue()
    if npcLines then
      self.npcDialogueShown[self.currentRoomKey .. ":" .. npcName] = true
      self.phase = "dialogue"
      self.dialoguePages = npcLines
      self.dialoguePageIndex = 1
      self.dialogueStartFrame = self.frame
      return
    end
    local exit = self:matchedExit()
    if exit then
      self:beginTransition(exit)
    end
    return
  end

  if self.phase == "transitioning" then
    self.transitionFrame = self.transitionFrame + 1
    local t = self.pendingExit.transition
    local totalFrames = t.totalPixels / t.pixelsPerFrame
    if self.transitionFrame >= totalFrames then
      self:completeTransition()
    end
    return
  end

  -- Real "cut" wipe -- see `RoomWipeTransition.lua`'s own doc comment
  -- for the live-traced timing this real-frame-counted state machine
  -- reproduces. The room actually switches at the CLOSING/OPENING
  -- boundary (screen is fully covered by the black band right then),
  -- matching the real ROM's own room-pointer commit happening while
  -- the screen is fully wiped, not before or after.
  if self.phase == "cutClosing" then
    self.cutFrame = self.cutFrame + 1
    if self.cutFrame >= RoomWipeTransition.CLOSE_FRAMES then
      self:switchToTargetRoom(self.pendingExit)
      self.phase = "cutOpening"
      self.cutFrame = 0
    end
    return
  end

  if self.phase == "cutOpening" then
    self.cutFrame = self.cutFrame + 1
    if self.cutFrame >= RoomWipeTransition.OPEN_FRAMES then
      local exit = self.pendingExit
      self.pendingExit = nil
      self:enterPostExitPhase(exit)
    end
    return
  end

  if self.phase == "dialogue" then
    self.frame = self.frame + 1
    local text = self.dialoguePages[self.dialoguePageIndex] or ""
    local elapsed = self.frame - self.dialogueStartFrame
    local revealed = TextBox.revealedCount(text, elapsed, self.framesPerLetter)
    local fullyTyped = revealed >= #text
    if fullyTyped and self.input and (self.input:pressed("a") or self.input:pressed("start")) then
      self.dialoguePageIndex = self.dialoguePageIndex + 1
      self.dialogueStartFrame = self.frame
      if not self.dialoguePages[self.dialoguePageIndex] then
        self.phase = "interactive"
        self.dialoguePages = nil
      end
    end
    return
  end

  -- self.phase == "cutscene": the original intro page machine.
  self.frame = self.frame + 1

  local page = self:currentPage()
  if not page then
    self:enterGameplay()
    return
  end

  local elapsed = self.frame - self.pageStartFrame
  local revealed = TextBox.revealedCount(page.text, elapsed, self.framesPerLetter)
  local fullyTyped = revealed >= #page.text

  if fullyTyped and self.input and (self.input:pressed("a") or self.input:pressed("start")) then
    self.pageIndex = self.pageIndex + 1
    self.pageStartFrame = self.frame
    if not self:currentPage() then
      self:enterGameplay()
    end
  end
end

--- Real gameplay continuation once every intro page is done -- hands
-- off from the scripted cutscene machine to the general room-chain
-- walker (see this module's doc comment). Does NOT pop this state --
-- the real ROM keeps the player in this same room, not an immediate
-- cut back to the starting room.
function VictorySequence:enterGameplay()
  if self.phase == "interactive" then return end
  self:ensureRoomLoaded(self.currentRoomKey)
  self.phase = "interactive"
end

function VictorySequence:finish()
  if self.done then return end
  self.done = true
  self.stack:pop()
end

--- Draws every named character in `roomKey`'s own real `scene` (see
-- `ensureRoomLoaded`), each offset by `(dx, dy)` -- used both at rest
-- (dx=dy=0) and mid-transition (offset to slide with their own room).
function VictorySequence:drawRoomScene(roomKey, dx, dy)
  local sprites = self.roomSprites[roomKey]
  local sceneData = self.roomSceneData and self.roomSceneData[roomKey]
  if not sprites or not sceneData then return end
  local wanderState = self.roomNpcState[roomKey]
  for name, sprite in pairs(sprites) do
    local char = sceneData[name]
    if char then
      -- ADDED (2026-08-10): an animated NPC (see `updateNpcWander`) draws
      -- at its own LIVE wandered position, not the static scene spawn
      -- point -- and `NpcSprite:draw` takes no `flipX` (its own pose
      -- table already bakes in the real per-direction flip, see
      -- rom_profiles.lua's `animation` doc comment), unlike the plain
      -- `CreatureSprite` every other scene character (Willy) still uses.
      local live = wanderState and wanderState[name]
      if live then
        sprite:draw(live.x + dx, live.y + dy)
      else
        sprite:draw(char.screenX + dx, char.screenY + dy, char.flipX)
      end
    end
  end
end

--- A plain, `love.*`-free snapshot of key fields -- for automated
-- scripted verification (`MYSTICQUEST_WAIT_FOR`, see main.lua's own doc
-- comment), added 2026-08-11 after this exact class of guesswork
-- ("how many frames until the player reaches the door?") repeatedly
-- wasted real verification time this same session. Deliberately a
-- separate method from the overlay's own `:draw()`-time
-- `self.overlay:addLine(...)` calls -- this one has no love dependency
-- at all and is meant to be called from `love.update`, before draw.
function VictorySequence:debugState()
  return {
    room = self.currentRoomKey,
    phase = self.phase,
    x = self.player and self.player.x,
    y = self.player and self.player.y,
    page = self.pageIndex,
    -- ADDED (2026-08-15, second-boss feature) -- nil in every room
    -- other than sixthRoom (no `self.secondBoss` built at all when
    -- `rom_profiles.lua`'s own `sixthRoom.secondBoss` is absent).
    secondBossAlive = self.secondBoss and self.secondBoss:isAlive(),
    secondBossHp = self.secondBoss and self.secondBoss.stats.curLP,
    secondBossDefeated = self.secondBossDefeated,
  }
end

--- Draws `sixthRoom`'s own second boss (see rom_profiles.lua's
-- `sixthRoom.secondBoss` doc comment) -- a no-op in every other room,
-- or once it's been defeated for good. Direct port of Field.lua's own
-- first-boss draw branch (death explosion / hit-flash / normal pose),
-- see that state's own `:draw()` for the more heavily-commented
-- original this mirrors.
function VictorySequence:drawSecondBoss()
  if self.currentRoomKey ~= "sixthRoom" or not self.secondBoss then return end
  local boss = self.secondBoss
  if boss.death and self.secondBossDeathSpriteA and not boss:deathComplete() then
    -- Real death-explosion shape (see rom_profiles.lua's `enemyDeath`
    -- doc comment) -- part offsets are relative to the creature's own
    -- REST position; unlike Field.lua's own first boss (which reads
    -- that from `enemySprite.screenX/screenY`, its one fixed spot),
    -- this boss's rest position is its own `spawnX`/`spawnY` (it never
    -- moves, see the doc comment above), used directly here instead.
    local d = self.profile.graphics.enemyDeath
    local sb = self.profile.graphics.sixthRoom.secondBoss
    local elapsed = boss.death.elapsedFrames
    local t = math.min(1, elapsed / d.totalFrames)
    local sprite = (math.floor(elapsed / 4) % 2 == 0) and self.secondBossDeathSpriteA or self.secondBossDeathSpriteB
    for _, part in ipairs(d.parts) do
      sprite:draw(sb.spawnX + part.dx * t, sb.spawnY + part.dy * t)
    end
  elseif boss:isAlive() then
    local flipX = boss:isFlipped()
    if self.secondBossFlashTimer > 0 and self.secondBossSpriteFlash then
      self.secondBossSpriteFlash:draw(boss.x, boss.y, flipX)
    elseif self.secondBossSprite then
      self.secondBossSprite:draw(boss.x, boss.y, flipX)
    end
  end

  if not (self.overlay and self.overlay.visible) then return end
  love.graphics.setColor(1, 0.3, 0.3, 1)
  if boss:isAlive() then
    love.graphics.rectangle("line", boss.x, boss.y, boss.width, boss.height)
  end
  for _, attack in ipairs({ self.secondBossAttackSwing, self.secondBossAttackThrust }) do
    if attack then
      love.graphics.setColor(1, 1, 0, 0.8)
      for _, box in ipairs(attack:getHitboxes(self.player.x, self.player.y)) do
        love.graphics.rectangle("line", box.x, box.y, box.w, box.h)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- A plain, minimal LP readout while the second-boss fight is live --
-- deliberately NOT Field.lua's own decorated `HudBar` (real ROM HUD-bar
-- tile art, see that file's own `hudBar` doc comment) -- an honest
-- scope simplification for this evidence-based, non-ROM-confirmed
-- encounter, not a claim this is how the real HUD would look during it.
function VictorySequence:drawSecondBossHud()
  if self.currentRoomKey ~= "sixthRoom" or not self.secondBoss or self.secondBossDefeated then return end
  if not self.font then return end
  self.font:print(string.format("LP %d/%d", self.stats.curLP, self.stats.maxLP), 2, ROOM_H - HUD_H + 4, { 1, 1, 1, 1 })
end

function VictorySequence:draw()
  local page = self:currentPage()

  if self.phase == "interactive" or self.phase == "dialogue" then
    local bg = self:backgroundFor(self.currentRoomKey)
    if bg then bg:draw(0, 0) end
    self:drawRoomScene(self.currentRoomKey, 0, 0)
    self:drawSecondBoss()
    if self.playerSprite and self.player then
      -- REVERTED (2026-08-15, same day, direct user report of shifted
      -- collision in the FIRST boss room -- see Field.lua's own
      -- matching revert note for the full reasoning): every room this
      -- project already renders here was historically calibrated the
      -- OLD, unshifted way -- applying the real OAM-vs-WRAM offset
      -- broadly regressed at least one of them. Back to the raw
      -- position everywhere in this file too, not just Field.lua.
      self.playerSprite:draw(self.player.x, self.player.y, self.player.facing == "right")
    end
    self:drawSecondBossHud()
  elseif self.phase == "transitioning" then
    -- Real hardware-scroll pan (see rom_profiles.lua's `exits.
    -- transition` doc comment): the current room slides toward one
    -- side of the real axis, the target room slides in from the other
    -- side (`totalPixels` away) -- the classic GB "camera pans, player
    -- stays screen-fixed" technique, generalized to either axis instead
    -- of hardcoding "vertical, north."
    --
    -- CORRECTED (2026-08-12, direct user report: "der wipe vom willy
    -- raum ist von unten nach oben anstatt anders herrum"): which side
    -- is "toward" vs "away" depends on the exit's own real direction,
    -- not just its axis. `secondRoom`'s real EAST exit wants the target
    -- entering from the POSITIVE X side -- correct under the plain
    -- formula below. `willyRoom`'s real NORTH exit is also on an axis
    -- (`y`), but wants the OPPOSITE sign: the target should enter from
    -- the NEGATIVE Y side (new area revealed ABOVE, sliding down), not
    -- the positive side the old unconditional formula always used. A
    -- single global sign convention can only ever be right for one real
    -- direction per axis; `transition.reverse` (see that field's own
    -- doc comment) flips it for exits where the default guess was
    -- wrong, rather than special-casing "north" by name.
    local exit = self.pendingExit
    local t = exit.transition
    local scroll = math.min(self.transitionFrame * t.pixelsPerFrame, t.totalPixels)
    local sign = t.reverse and -1 or 1
    local dx1, dy1, dx2, dy2
    if t.axis == "y" then
      dx1, dy1 = 0, sign * -scroll
      dx2, dy2 = 0, sign * (t.totalPixels - scroll)
    else
      dx1, dy1 = sign * -scroll, 0
      dx2, dy2 = sign * (t.totalPixels - scroll), 0
    end
    local curBg = self:backgroundFor(self.currentRoomKey)
    if curBg then curBg:draw(dx1, dy1) end
    local targetBg = self.roomBg[exit.targetRoom]
    if targetBg then targetBg:draw(dx2, dy2) end
    self:drawRoomScene(self.currentRoomKey, dx1, dy1)
    self:drawRoomScene(exit.targetRoom, dx2, dy2)
    -- Real behavior: the player's own on-screen position stays fixed
    -- throughout the pan (their real world position advances in
    -- lockstep with the scroll instead).
    if self.playerSprite and self.player then
      self.playerSprite:draw(self.player.x, self.player.y, self.player.facing == "right")
    end
  elseif self.phase == "cutClosing" or self.phase == "cutOpening" then
    -- Real "cut" wipe -- see `RoomWipeTransition.lua`'s own doc
    -- comment for the live-traced evidence this reproduces (the real
    -- visual RESULT, via `setScissor`, not the real ROM's own
    -- VRAM-tile-pattern-rewrite mechanism -- same "same effect,
    -- different means" precedent as the black-backdrop cut style
    -- below). `self.currentRoomKey` is already the OLD room while
    -- closing and the NEW room while opening (the switch happens in
    -- `update`, at the fully-covered boundary between the two).
    local closing = self.phase == "cutClosing"
    local total = closing and RoomWipeTransition.CLOSE_FRAMES or RoomWipeTransition.OPEN_FRAMES
    -- Real, live-confirmed convergence point: the player's own on-
    -- screen Y (where the door/exit actually is), NOT the room's
    -- geometric middle -- see RoomWipeTransition.lua's own doc comment
    -- for the live `love .` screenshot comparison that found a fixed
    -- room-center convergence rendering visibly wrong. REVERTED the
    -- brief render-offset use here too (2026-08-15, same revert as the
    -- player draw calls above) -- back to the raw `self.player.y`.
    local centerY = self.player and self.player.y or (ROOM_H - HUD_H) / 2
    local bandTop, bandHeight = RoomWipeTransition.visibleBand(
      closing and "closing" or "opening", self.cutFrame, total, ROOM_H - HUD_H, centerY)

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, ROOM_W, ROOM_H)
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setScissor(0, bandTop, ROOM_W, bandHeight)
    local bg = self:backgroundFor(self.currentRoomKey)
    if bg then bg:draw(0, 0) end
    self:drawRoomScene(self.currentRoomKey, 0, 0)
    if self.playerSprite and self.player then
      self.playerSprite:draw(self.player.x, self.player.y, self.player.facing == "right")
    end
    love.graphics.setScissor()
  else
    -- self.phase == "cutscene": every "top" page plays over willyRoom;
    -- every "bottom" page plays on the real black wipe.
    local willyBg = self:backgroundFor("willyRoom")
    local showRoom = willyBg and (page and page.box == "top")
    if showRoom then
      willyBg:draw(0, 0)
      self:drawRoomScene("willyRoom", 0, 0)
      if self.playerSprite and self.sceneData then
        self.playerSprite:draw(self.sceneData.player.screenX, self.sceneData.player.screenY,
          self.sceneData.player.flipX)
      end
    else
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, ROOM_W, ROOM_H)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)

  if self.stats and self.font then
    local hudText = string.format("LP %d MP %d G %d", self.stats.curLP, self.stats.curMP, self.stats.gold)
    self.font:print(hudText, 2, ROOM_H - HUD_H + 4, { 1, 1, 1, 1 })
  end

  if self.overlay then
    self.overlay:addLine("state", "VictorySequence")
    if self.phase == "interactive" then
      self.overlay:addLine("mode", "gameplay (" .. self.currentRoomKey .. ")")
    elseif self.phase == "dialogue" then
      self.overlay:addLine("mode", string.format("dialogue (%s, %d/%d)", self.currentRoomKey,
        self.dialoguePageIndex, #self.dialoguePages))
    elseif self.phase == "transitioning" then
      local t = self.pendingExit.transition
      self.overlay:addLine("mode", string.format("transition %s->%s (%d/%d)",
        self.currentRoomKey, self.pendingExit.targetRoom, self.transitionFrame,
        math.floor(t.totalPixels / t.pixelsPerFrame)))
    elseif self.phase == "cutClosing" or self.phase == "cutOpening" then
      local total = self.phase == "cutClosing" and RoomWipeTransition.CLOSE_FRAMES or RoomWipeTransition.OPEN_FRAMES
      self.overlay:addLine("mode", string.format("%s %s->%s (%d/%d)",
        self.phase, self.currentRoomKey, self.pendingExit.targetRoom, self.cutFrame, total))
    elseif page then
      self.overlay:addLine("page", string.format("%d/%d", self.pageIndex, #self.pages))
    end
    if self.player and (self.phase == "interactive" or self.phase == "transitioning"
        or self.phase == "cutClosing" or self.phase == "cutOpening") then
      self.overlay:addLine("player x,y", string.format("%d,%d", self.player.x, self.player.y))
    end
    -- Real ROM roomSelector data for the current room (see
    -- self.roomSelectorInfo's own doc comment) -- makes the bank-8
    -- table's real connectivity data visible during actual play, not
    -- just in static docs/tests.
    local info = self.roomSelectorInfo[self.currentRoomKey]
    if info then
      self.overlay:addLine("rom roomSelector",
        string.format("{%s} -> tileSrc %#06x, bank %d",
          table.concat(info.selectors, ","), info.tileSourcePointer, info.dynamicBank))
    end
    -- Real ScriptInterpreter shadow run (2026-08-13, REWRITTEN
    -- 2026-08-15 -- see this module's own top-of-file doc comment) --
    -- observational only, never drives anything drawn/played above; only
    -- present at all when `MYSTICQUEST_SCRIPT_INTERPRETER=1`. Reports
    -- the REAL, LIVE, per-frame state of `BossSequenceInterpreter`
    -- (bank, cursor, ticks, and whether it's genuinely stopped/done),
    -- not a one-shot burst summary the way the old shadow run's overlay
    -- line did.
    if self.bossSequenceInterpreter then
      local bsi = self.bossSequenceInterpreter
      local rt = bsi.runtime
      local status
      if rt.stopped then
        -- `rt.stopError` is a full Lua error string (file:line prefix
        -- included) -- just the first line is plenty for the overlay.
        local firstLine = tostring(rt.stopError):match("^[^\n]*") or tostring(rt.stopError)
        status = string.format("stopped after %d real frames, bank %d, cursor %#06x: %s",
          self.bossSequenceFrameCounter.n, bsi.bank, bsi.cursor, firstLine)
      elseif rt.finished then
        status = string.format("finished cleanly after %d real frames",
          self.bossSequenceFrameCounter.n)
      else
        -- The real, honest, current boundary (see the top-of-file doc
        -- comment's "HONEST SCOPE" section): this run reaches real,
        -- decoded content, then stalls indefinitely at opcode 0x00's own
        -- still-unmodeled real release condition -- reported here as a
        -- live, running frame count, not a fake "done" or "error".
        status = string.format("running: %d real frames, bank %d%s, cursor %#06x, %d real events logged",
          self.bossSequenceFrameCounter.n, bsi.bank, bsi.bankSwitched and " (post-CHAIN)" or "",
          bsi.cursor, #self.bossSequenceTranscript)
      end
      self.overlay:addLine("script interpreter (live shadow run)", status)
      -- Real opcode dispatch histogram (top 6 by count) -- lets a
      -- developer confirm live, without re-running the standalone probe
      -- script, that this is genuinely dispatching the real 18-opcode
      -- family events.md documents for this script, not stuck on
      -- garbage bytes the way the OLD wrong-bank version silently was.
      local histogram = {}
      for opcode, count in pairs(rt.opcodeCounts) do
        histogram[#histogram + 1] = { opcode = opcode, count = count }
      end
      table.sort(histogram, function(a, b) return a.count > b.count end)
      local parts = {}
      for i = 1, math.min(6, #histogram) do
        parts[#parts + 1] = string.format("%#04x x%d", histogram[i].opcode, histogram[i].count)
      end
      if #parts > 0 then
        self.overlay:addLine("  opcode histogram (top 6)", table.concat(parts, ", "))
      end
    end
    -- Real pipeline-proof demo (2026-08-13, see `runMessagePipelineDemo`'s
    -- own doc comment) -- overlay line always present when the switch is
    -- on; the actual VISIBLE on-screen textbox is drawn unconditionally
    -- below (outside this `debug` gate) so a plain `love .` launch with
    -- the switch on shows real, rendered proof, not just a debug label.
    if self.messagePipelineDemo then
      local demo = self.messagePipelineDemo
      self.overlay:addLine("script interpreter (message pipeline demo)",
        demo.text and string.format("resolved: %q", demo.text)
          or string.format("FAILED: %s", tostring(demo.error)))
    end
  end

  -- Real, VISIBLE proof the interpreter->rendering pipeline works (see
  -- `runMessagePipelineDemo`'s own doc comment) -- drawn regardless of
  -- `debug`/overlay state (only present at all behind
  -- `MYSTICQUEST_SCRIPT_INTERPRETER=1`), in a thin strip that doesn't
  -- overlap `BOX_GEOMETRY.top`/`.bottom`'s own real dialogue boxes.
  if self.messagePipelineDemo and self.messagePipelineDemo.text and self.box then
    -- A real screenshot check (see events.md's own dated "task #84"
    -- section) caught TWO real layout bugs in this exact spot before
    -- landing here: a 2-line label+text overflowed the box's own
    -- 156px usable width, and a taller box (to fit 2 lines) overlapped
    -- `BOX_GEOMETRY.bottom`'s own real story-text box (`y=64`,
    -- `rows=8` -> `y=64..128`). `y=128, rows=2` is the one real gap
    -- below that box that fits within the real `ROOM_H=144` screen
    -- without overlapping it -- single short line only (the overlay's
    -- own "script interpreter (message pipeline demo)" line already
    -- carries a full label for anyone checking F1 debug info).
    local geo = { x = 0, y = 128, cols = 20, rows = 2 }
    self.box:drawBorder(geo.x, geo.y, geo.cols, geo.rows)
    self.box:drawText(self.messagePipelineDemo.text, geo.x, geo.y, 2)
  end

  if self.phase == "dialogue" then
    local geo = BOX_GEOMETRY.top
    if self.box then
      local text = self.dialoguePages[self.dialoguePageIndex] or ""
      -- Real line height CORRECTED (2026-08-14, see TextBox.lua's own
      -- `LINE_HEIGHT` doc comment): `geo.rows` is `BOX_GEOMETRY`'s own
      -- static, OLD-8px-spacing-era guess -- computing the real row
      -- count THIS text needs at the now-correct 16px spacing avoids
      -- a multi-line message (e.g. the real 3-line Willy exchange
      -- pages) overflowing a box sized for the old, wrong spacing.
      local rows = math.max(geo.rows, TextBox.rowsNeeded(text, 8))
      self.box:drawBorder(geo.x, geo.y, geo.cols, rows)
      local elapsed = self.frame - self.dialogueStartFrame
      local shown = TextBox.revealedCount(text, elapsed, self.framesPerLetter)
      self.box:drawText(text:sub(1, shown), geo.x, geo.y, 8)
    end
    return
  end

  if self.phase ~= "cutscene" or not page or not self.box then
    return
  end

  local geo = BOX_GEOMETRY[page.box]
  -- Same real-line-height correction as the dialogue box above.
  local rows = math.max(geo.rows, TextBox.rowsNeeded(page.text, 8))
  self.box:drawBorder(geo.x, geo.y, geo.cols, rows)
  local elapsed = self.frame - self.pageStartFrame
  local shown = TextBox.revealedCount(page.text, elapsed, self.framesPerLetter)
  self.box:drawText(page.text:sub(1, shown), geo.x, geo.y, 8)
end

return VictorySequence
