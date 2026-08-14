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
-- `MYSTICQUEST_SCRIPT_INTERPRETER=1` is set, this state ALSO builds a
-- real `ScriptRuntime` (src/scripting/ScriptRuntime.lua) and runs it,
-- once, synchronously, against the REAL boss-defeat script's own real
-- ROM bytes (`profile.scriptPointerTable`'s verified address, bank 8) --
-- a genuine, live execution of real, decoded ROM opcodes, not a
-- simulation. This is a SHADOW run: its own result is surfaced ONLY via
-- the debug overlay (`self.scriptRuntime`, read in `:draw()`) -- it
-- never touches `self.pages`, `self.phase`, or anything else this state
-- actually renders/drives. The switch defaults OFF, and even ON, the
-- existing hand-authored cutscene/room-graph machinery above stays 100%
-- unchanged and fully in control of real gameplay.
--
-- HONEST SCOPE, why a shadow run and not a real swap-over yet: the
-- boss-defeat script's own real opcode list (events.md's "every opcode
-- it actually uses, decoded") originally included several this project
-- had traced to real ROM code but not yet given a Lua implementation
-- (`0x5A`, `0x08`, `0x88`, `0xBF`/`0xBC`/`0xBD`/`0xF3`, the palette-fade
-- family). UPDATED 2026-08-14 ("konsolidiere unsere Entdeckungen und
-- baue sie ein"): `0x5A`/`0x08`/`0xF3` were closed in earlier passes,
-- and `0x88`/`0xBF` were closed this session -- see `ScriptOpcodeTable
-- .lua`'s own dated entries for each. The ONLY remaining real gaps in
-- this ONE script's own opcode list are `0xBC` (`$10DC`) and `0xBD`
-- (`$1046`), both real, traced, but genuinely DEEPER members of the
-- SAME palette-fade family (real `$D499`/`$D49A`-indexed lookups into
-- two shared gradient tables, `$101A`/`$1030`, not yet decoded to an
-- exact fade curve) -- deliberately left unwired rather than a forced,
-- unverified guess, matching this project's "no silent fallbacks"
-- rule. A real, live run WILL genuinely stop the first time it reaches
-- one of those two (`ScriptRuntime:step`'s own "no silent fallbacks"
-- capture, not a crash), which is exactly the honest, current state of
-- decoding, surfaced live rather than guessed at. Once real coverage is
-- complete enough that a shadow run consistently reaches the end of a
-- real script cleanly, swapping specific rendering decisions (e.g.
-- dialogue pacing) over to be DRIVEN by the runtime, rather than just
-- observed alongside it, is the natural next step -- not done here.

local TextBox = require("src.rendering.TextBox")
local Font = require("src.rendering.Font")
local TileGridBackground = require("src.rendering.TileGridBackground")
local CreatureSprite = require("src.rendering.CreatureSprite")
local PlayerSprite = require("src.rendering.PlayerSprite")
local NpcSprite = require("src.rendering.NpcSprite")
local TileImage = require("src.rendering.TileImage")
local Player = require("src.entities.Player")
local TileWalkability = require("src.entities.TileWalkability")
local ZoneMatch = require("src.entities.ZoneMatch")
local HoldTrigger = require("src.entities.HoldTrigger")
local RoomWipeTransition = require("src.entities.RoomWipeTransition")
local NpcProximity = require("src.entities.NpcProximity")
local NpcWander = require("src.entities.NpcWander")
local TextDecoder = require("src.import.TextDecoder")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local RomScriptStream = require("src.scripting.RomScriptStream")
local MessageTextPointer = require("src.import.MessageTextPointer")

local VictorySequence = { opaque = true }
VictorySequence.__index = VictorySequence

--- Real dev-mode switch (matches the existing `MYSTICQUEST_*` env-var
-- family, see main.lua's own doc comment) -- see this module's own
-- "REAL ScriptInterpreter integration" doc comment above for exactly
-- what turning this on does (and, just as importantly, does NOT do).
local function scriptInterpreterShadowRunEnabled()
  return os.getenv("MYSTICQUEST_SCRIPT_INTERPRETER") == "1"
end

-- Bounded burst size for the one-shot shadow run below -- the real
-- boss-defeat script's own full real dialogue sequence live-traced at
-- 625 real opcode dispatches (events.md, "Opcode 0xFF wired"); this
-- leaves ample headroom while still guaranteeing the run can never hang
-- the constructor on a real script that loops far longer than expected
-- (see ScriptRuntime:run's own doc comment).
local SCRIPT_RUNTIME_SHADOW_MAX_STEPS = 5000

--- Builds and runs (once, synchronously, bounded) a real `ScriptRuntime`
-- against the real boss-defeat script's own real ROM bytes -- see this
-- module's own top-of-file doc comment for the full "why a shadow run"
-- reasoning. Returns the runtime (for `:draw()`'s overlay reporting) or
-- nil if the profile doesn't have the real script-location data this
-- needs (e.g. a dev/test profile without `scriptPointerTable`).
local function runScriptInterpreterShadow(romData, profile, stats)
  local spt = profile.scriptPointerTable
  if not (spt and spt.verifiedExample and profile.scriptOpcodeTable) then
    return nil
  end
  local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
  local stream = RomScriptStream.forFileOffset(romData, spt.fileOffset)
  local runtime = ScriptRuntime.new(opcodeEntries, {
    stats = stats,
    flags = { byte = 0 },
    -- Real WRAM $C3F1 shadow for opcodes 0xB8/0xB9 (added 2026-08-14,
    -- "konsolidiere unsere Entdeckungen") -- a private, zero-
    -- initialized cell, same honest default as `flags` just above (no
    -- other real script this shadow run has actually reached needs a
    -- specific starting value).
    wramBitFlags = { byte = 0 },
    -- No real display state to gate on in a shadow run -- always
    -- releases immediately (see ScriptRuntime.new's own doc comment on
    -- `ctx.isTextboxDone`'s "clearly-flagged stand-in" honesty note),
    -- so this run explores real CONTROL FLOW as far as decoding goes,
    -- not real on-screen pacing.
    isTextboxDone = function() return true end,
  })
  runtime:run(stream, spt.verifiedExample.scriptCpuAddress, SCRIPT_RUNTIME_SHADOW_MAX_STEPS)
  return runtime
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

    -- REAL ScriptInterpreter shadow run (2026-08-13, opt-in, see this
    -- module's own top-of-file doc comment) -- a no-op unless
    -- `MYSTICQUEST_SCRIPT_INTERPRETER=1`. `self.scriptRuntime` is only
    -- ever READ by `:draw()`'s overlay reporting below -- nothing else
    -- in this state consults it.
    if scriptInterpreterShadowRunEnabled() then
      self.scriptRuntime = runScriptInterpreterShadow(romData, profile, self.stats)
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
  self.roomWalk[roomKey] = TileWalkability.build(room, 16, 16)

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

  -- Dev-only escape hatch (same convention as BattleIntro.lua's SELECT
  -- skip) -- not real ROM behavior.
  if self.input and self.input:pressed("select") then
    self:finish()
    return
  end

  if self.phase == "interactive" then
    local room = self.profile.graphics[self.currentRoomKey]
    local bounds = { 0, 0, ROOM_W - 16, ROOM_H - HUD_H - 16 }
    if self.player and self.roomWalk[self.currentRoomKey] then
      self.player:update(dt, self.input, bounds, self.roomWalk[self.currentRoomKey])
      -- Real walk-cycle animation (see this state's own `playerSprite`
      -- doc comment above) -- same per-frame drive as Field.lua's own.
      if self.playerSprite then
        self.playerSprite:update(dt, self.player.moving, self.player.facing)
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
  }
end

function VictorySequence:draw()
  local page = self:currentPage()

  if self.phase == "interactive" or self.phase == "dialogue" then
    local bg = self:backgroundFor(self.currentRoomKey)
    if bg then bg:draw(0, 0) end
    self:drawRoomScene(self.currentRoomKey, 0, 0)
    if self.playerSprite and self.player then
      self.playerSprite:draw(self.player.x, self.player.y, self.player.facing == "right")
    end
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
    -- room-center convergence rendering visibly wrong.
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
    -- Real ScriptInterpreter shadow run (2026-08-13, see this module's
    -- own top-of-file doc comment) -- observational only, never drives
    -- anything drawn/played above; only present at all when
    -- `MYSTICQUEST_SCRIPT_INTERPRETER=1`.
    if self.scriptRuntime then
      local rt = self.scriptRuntime
      local status
      if rt.stopped then
        -- `rt.stopError` is a full Lua error string (file:line prefix
        -- included) -- just the first line is plenty for the overlay.
        local firstLine = tostring(rt.stopError):match("^[^\n]*") or tostring(rt.stopError)
        status = string.format("stopped after %d real steps at opcode %#04x: %s",
          rt.stepCount, rt.lastOpcode or -1, firstLine)
      elseif rt.finished then
        status = string.format("finished cleanly after %d real steps", rt.stepCount)
      else
        status = string.format("%d real steps run (burst limit reached)", rt.stepCount)
      end
      self.overlay:addLine("script interpreter (shadow run)", status)
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
      self.box:drawBorder(geo.x, geo.y, geo.cols, geo.rows)
      local text = self.dialoguePages[self.dialoguePageIndex] or ""
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
  self.box:drawBorder(geo.x, geo.y, geo.cols, geo.rows)
  local elapsed = self.frame - self.pageStartFrame
  local shown = TextBox.revealedCount(page.text, elapsed, self.framesPerLetter)
  self.box:drawText(page.text:sub(1, shown), geo.x, geo.y, 8)
end

return VictorySequence
