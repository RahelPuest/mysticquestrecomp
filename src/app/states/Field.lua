-- The starting-room vertical slice: input, FixedStep timing, a VERIFIED
-- movement speed (see src/entities/Player.lua), an enemy blocking a
-- chokepoint with collision and contact combat (see
-- src/entities/Enemy.lua), and the dialogue sequence this project found
-- live past it (docs/reverse-engineering/rom-map.md "Breakthrough").
--
-- The room background, player sprite, and enemy sprite/position all
-- draw live-ground-truth-verified content (src/rendering
-- /TileGridBackground.lua, rom_profiles.lua's `startRoom`/`playerSprite`
-- /`enemySprite` entries) -- a barred-gate courtyard with an enemy, not
-- a generic placeholder or a guessed arrangement. See rom_profiles.lua's
-- `startRoom` doc comment for the correction history (an earlier
-- capture was mistakenly the pause menu, not the room -- caught and
-- fixed). Combat numbers (enemy HP, player attack damage) remain
-- reasonable stand-ins, not decoded ROM values -- see Enemy.lua's doc
-- comment for exactly which parts of the combat model are VERIFIED vs.
-- a placeholder.
--
-- The boss-defeat dialogue fires through a reusable event/trigger
-- system (src/scripting/EventSystem.lua -- see FIELD_EVENTS below), not
-- an inline `if` check -- a direct fix for this project's master brief
-- calling that pattern out by name. The dialogue *text* itself is still
-- hardcoded, not decoded live from ROM bytes -- see DialogueBox.lua's
-- provenance note; general dialogue compression remains unsolved
-- (docs/reverse-engineering/text.md).
--
-- Controls: arrows move, A attacks the enemy while adjacent, START
-- opens the menu (Menu.lua), SELECT pops back to whatever pushed this
-- state.

local Player = require("src.entities.Player")
local Enemy = require("src.entities.Enemy")
local Stats = require("src.entities.Stats")
local Inventory = require("src.entities.Inventory")
local KnockbackFlicker = require("src.entities.KnockbackFlicker")
local TileWalkability = require("src.entities.TileWalkability")
local Font = require("src.rendering.Font")
local TileGridBackground = require("src.rendering.TileGridBackground")
local CreatureSprite = require("src.rendering.CreatureSprite")
local PlayerSprite = require("src.rendering.PlayerSprite")
local AttackSwing = require("src.rendering.AttackSwing")
local AttackThrust = require("src.rendering.AttackThrust")
local HudBar = require("src.rendering.HudBar")
local TileImage = require("src.rendering.TileImage")
local GBTile = require("src.rendering.GBTile")
local EventSystem = require("src.scripting.EventSystem")
local NoiseTable = require("src.import.NoiseTable")
local CombatNoise = require("src.entities.CombatNoise")
local EnemyMovementInterpreter = require("src.entities.EnemyMovementInterpreter")
local CombatFormulas = require("src.entities.CombatFormulas")
local MusicPlayer = require("src.audio.MusicPlayer")

local Field = { opaque = true }
Field.__index = Field

-- VERIFIED (see module doc comment / docs/progress.md): a Mystic Quest
-- room is exactly one 160x144 GB screen, HUD taking the bottom 2
-- tile-rows (16px), leaving a 160x128 playable area, no camera scroll.
local ROOM_W, ROOM_H = 160, 144
local HUD_H = 16
local PLAY_H = ROOM_H - HUD_H

-- REMOVED: a fixed ATTACK_REACH circle used to approximate attack
-- range -- replaced by per-phase swing hitboxes (AttackSwing
-- :getHitboxes) now that the swing animation itself is implemented, so
-- hit detection checks the actual displayed sword rectangles against
-- the enemy instead of a guessed radius. Direct fix for a user report
-- that the enemy "seems to take no damage" -- the old circle check ran
-- once at press time, before the swing had visually moved anywhere
-- near the enemy.

-- The post-victory scene (victory line, black-screen wipe, lore pages,
-- "WILLY" exchange) now lives in VictorySequence.lua -- see that
-- module's doc comment for the full ROM-code trace this replaced the
-- old flat WILLY_DIALOGUE/DialogueBox pairing with.
--
-- Reusable event data (see src/scripting/EventSystem.lua's doc comment
-- for why this replaced an inline `if self.dialogueQueued` check -- a
-- direct fix for this project's master brief calling out exactly that
-- pattern as something to avoid). `state` here is the Field instance
-- itself (see Field:update's `self.events:update(self, ...)` call) --
-- the trigger only reads `state.enemyDefeated`, a boolean this state
-- sets the instant the boss-clearing hit lands, not a queued/deferred
-- flag.
-- Background music during actual gameplay (picking a concrete,
-- achievable win after several blocked/inconclusive investigations:
-- `MusicPlayer`/`love.audio` playback already shipped, but only
-- reachable via the dev-only F9 Jukebox until now). HONEST SCOPE, same
-- "real content, no fabricated trigger" precedent as `sixthRoom`'s
-- static-exit engineering choice: no live ROM trigger for "which song
-- plays during ordinary field exploration" has been found (see
-- MusicPlayer.lua's doc comment) -- `FIELD_MUSIC_SONG_INDEX` is a
-- deliberate, clearly-labeled engineering choice (an arbitrary song
-- from the decoded table, picked for being pleasant to loop, not a
-- claimed ROM fact), not a reverse-engineered fact. Every note played
-- is decoded ROM audio data -- only the "when" is this project's own
-- choice.
local FIELD_MUSIC_SONG_INDEX = 1

local FIELD_EVENTS = {
  {
    id = "victory_sequence_on_boss_defeat",
    trigger = function(state) return state.enemyDefeated end,
    actions = { { type = "victorySequence" } },
  },
}

--- `savedStats`: optional plain table of Stats fields from a loaded
-- save (see SaveFile.load()/SaveData.deserialize) -- used by
-- TitleScreen.lua's "Weiterspielen" path instead of the fresh-character
-- defaults below. Absent for every other entry point (a new game, dev
-- shortcuts, tests), which is not a fallback -- those genuinely have no
-- save to restore from.
--
-- `enemyState`: optional `{x=, y=, movementIndex=}` -- lets
-- `BattleIntro.lua` hand off its already-in-progress patrol (see
-- `Enemy.MOVEMENT_CYCLE`) seamlessly instead of this state silently
-- resetting the creature back to its static rest position the instant
-- the cutscene ends (a visible position "jump" the old code had).
-- Absent for every other entry point (dev shortcuts, tests, a
-- hypothetical future "reload mid-game" path) -- those fall back to the
-- same rest position (`enemySprite.screenX/screenY`) as before,
-- unchanged.
function Field.new(romData, profile, input, overlay, stack, heroName, savedStats, enemyState)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    -- The player-entered name (see NameEntry.lua), threaded through
    -- BattleIntro -- used by VictorySequence's captured text ("<name>
    -- ist ein tapferer Kaempfer.", etc). A clearly-labeled fallback for
    -- dev shortcuts that construct Field directly without going through
    -- NameEntry (e.g. tests, F-key dev entry points), not a silent
    -- default for the real flow.
    heroName = heroName or "HELD",
    -- VERIFIED spawn position (see docs/progress.md): a live mGBA
    -- ground-truth capture of the starting room (not the earlier-
    -- mistaken pause-menu capture) read the player's actual OAM
    -- position and converted it to screen space (Pan Docs OAM offset
    -- convention) -- see rom_profiles.lua's
    -- `playerSprite.screenX/screenY`.
    player = Player.new(0, 0),
    -- VERIFIED fresh-character stats (see module doc comment) -- a
    -- data model, not placeholder numbers; the same fields dynamic
    -- tracing read live out of a fresh save. Overridden by
    -- `savedStats` ("Weiterspielen") when given.
    stats = Stats.new(savedStats or { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, level = 1, gold = 50 }),
    -- Inventory/equipment data model (see Inventory.lua's doc comment)
    -- -- built once here (not by Menu.lua, which used to decode
    -- WeaponTable itself just to find one name) so equip/item state
    -- persists across opening and closing the menu.
    inventory = Inventory.new(romData, profile),
    -- Contact-hit reaction: knockback + invincibility flicker (see
    -- KnockbackFlicker.lua's doc comment for the precise live-captured
    -- schedule this reproduces).
    knockback = KnockbackFlicker.new(),
    -- VERIFIED position (see rom_profiles.lua's
    -- `enemySprite.screenX/screenY`): the creature blocking the gate,
    -- read from the same corrected live capture as the player. Size
    -- set below once the profile's sprite data is available;
    -- Enemy.new's default (see Enemy.DEFAULT_WIDTH/HEIGHT) applies
    -- otherwise. Drawn by default now (see enemyConfirmedVisible below)
    -- -- this is the real thing, not a placeholder.
    enemy = Enemy.new(0, 0),
    enemyConfirmedVisible = true,
    -- Hit-flash countdown (see rom_profiles.lua's `enemyHitFlash`) --
    -- frames remaining to show the flashed palette sprite, 0 = normal.
    -- Decremented once per Field:update (one GB frame).
    enemyFlashTimer = 0,
    -- Event/trigger system (see FIELD_EVENTS/EventSystem.lua) --
    -- `enemyDefeated` is state this instance owns and updates, not a
    -- one-off queued flag; the event system reads it every step.
    enemyDefeated = false,
    events = EventSystem.new(FIELD_EVENTS),
  }, Field)
  -- Bounds/collision fallback for when no ROM is loaded (see the
  -- `if romData and profile` block below for the profile-derived
  -- values) -- uses the player's generic single-tile default size, not
  -- a guessed creature size.
  self.playerBounds = { 0, 0, ROOM_W - self.player.width, PLAY_H - self.player.height }
  if romData and profile then
    self.font = Font.new(romData, profile)
    self.background = TileGridBackground.new(romData, profile.graphics.startRoom)
    -- Background music (see FIELD_MUSIC_SONG_INDEX's doc comment above
    -- for the honest "real audio, chosen trigger" scope).
    -- `MusicPlayer.new` itself is love.*-free (headlessly testable,
    -- same as every other constructor here) -- only `:play()` touches
    -- `love.audio`, guarded below for the headless test suite.
    self.musicPlayer = MusicPlayer.new(romData)
    if love and love.audio then
      self.musicPlayer:play(FIELD_MUSIC_SONG_INDEX)
    end
    -- The combat PRNG (ROM $2B1E, see CombatNoise.lua's doc comment for
    -- the exact ported algorithm) -- one shared, persistent instance so
    -- its internal counter/cap state advances across the whole session
    -- like the hardware's $C0B0/$C0B1 WRAM bytes would, not a fresh
    -- draw sequence every contact hit.
    if profile.noiseTable then
      self.combatNoise = CombatNoise.new(NoiseTable.decode(romData, profile.noiseTable))
      -- The ROM-data-driven movement AI (see EnemyMovementInterpreter's
      -- doc comment for the full 3-level decoded mechanism).
      --
      -- CORRECTED: an interpreter already exists by the time
      -- `Field.lua` runs whenever this room was reached through
      -- `BattleIntro.lua` (see that state's construction site) --
      -- building a second, fresh one here (as this code used to)
      -- discards its already-advanced internal state and restarts the
      -- whole AI system from scratch, a genuine discontinuity at the
      -- cutscene->gameplay boundary. Reuse the handed-off instance when
      -- present; otherwise (dev shortcuts/tests reaching Field
      -- directly, with no BattleIntro run first) build + `skipTicks` a
      -- fresh one, same as before.
      if enemyState and enemyState.movementInterpreter then
        self.enemy.movementInterpreter = enemyState.movementInterpreter
      else
        self.enemy.movementInterpreter = EnemyMovementInterpreter.new(romData, self.combatNoise)
        -- See `EnemyMovementInterpreter:skipTicks`'s doc comment: the
        -- interpreter's first `#enemyDescent.path` ticks are the same
        -- event as the (here, unplayed -- no BattleIntro ran) descent
        -- animation -- skip them so this entry point's starting
        -- position/behavior still matches the settled patrol point
        -- instead of the "entrance" ticks.
        if profile.graphics.enemyDescent then
          self.enemy.movementInterpreter:skipTicks(#profile.graphics.enemyDescent.path)
        end
      end
    end
    -- DMG sprite palette (OBP0/OBP1, both $D0 -- VERIFIED live, see
    -- rom_profiles.lua's `spritePalette` entry): raw pixel index 1
    -- renders as white (same as background), not a mid-grey -- set once
    -- so every CreatureSprite (here and future ones) renders with the
    -- hardware palette instead of an arbitrary identity grey ramp.
    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end
    -- Player sprite AND size: size still derived from `playerSprite`
    -- (ROM cols/rows, see Player.lua's DEFAULT_WIDTH/HEIGHT doc comment
    -- -- direct user correction to not hardcode sprite sizes and take
    -- them from the ROM). The sprite itself is animated (PlayerSprite
    -- .lua, rom_profiles.lua's `playerAnimation`) -- CORRECTED: this
    -- used to be a static CreatureSprite because "no walk-cycle
    -- animation was ever observed live," which turned out to be wrong
    -- (see `playerAnimation`'s doc comment for the capture that
    -- disproved it -- direct user pushback that the ROM must have such
    -- a table somewhere).
    local ps = profile.graphics.playerSprite
    self.playerSprite = PlayerSprite.new(romData, profile)
    self.player.x, self.player.y = ps.screenX, ps.screenY
    self.player.width, self.player.height = ps.cols * GBTile.TILE_W, ps.rows * GBTile.TILE_H
    self.playerBounds = { 0, 0, ROOM_W - self.player.width, PLAY_H - self.player.height }
    -- Enemy sprite AND size: same reasoning as the player above --
    -- rom_profiles.lua's `enemySprite` entry, 8 tiles at individually-
    -- confirmed ROM offsets (not a regular stride, hence
    -- CreatureSprite.fromOffsets rather than .new/.static). `rowSpacing`
    -- (see that entry's doc comment): the row-to-row gap is 16px, not
    -- flush -- both the visual sheet and the collision height below
    -- need to account for it.
    local es = profile.graphics.enemySprite
    self.enemySprite = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows, nil, es.rowSpacing)
    self.enemy.x, self.enemy.y = es.screenX, es.screenY
    self.enemy.width = es.cols * GBTile.TILE_W
    self.enemy.height = es.rowSpacing and ((es.rows - 1) * es.rowSpacing + GBTile.TILE_H) or (es.rows * GBTile.TILE_H)
    -- Handoff from BattleIntro's already-in-progress patrol (see
    -- Field.new's `enemyState` doc comment) -- overrides the static
    -- rest position above only when the caller actually has an
    -- in-progress position to hand off.
    if enemyState then
      self.enemy.x, self.enemy.y = enemyState.x, enemyState.y
      self.enemy.movementIndex = enemyState.movementIndex
    end
    -- Hit-flash (see rom_profiles.lua's `enemyHitFlash` doc comment) --
    -- direct fix for a named gap: the enemy sprite should flash briefly
    -- when hit by an attack. A second sprite instance sharing the exact
    -- same tile art, built with the flashed OBP1 palette instead of the
    -- normal one -- CreatureSprite bakes its palette in at construction,
    -- so the flash is a palette-swapped image, not a runtime
    -- tint/shader.
    local flash = profile.graphics.enemyHitFlash
    if flash then
      self.enemySpriteFlash = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows,
        TileImage.paletteFromShadeIndices(flash.shadeIndices))
      self.enemyFlashFrames = flash.frames
    end
    -- Death "explosion" sprite (see rom_profiles.lua's `enemyDeath` doc
    -- comment for the live-OAM re-trace this is based on): used to
    -- combine all 4 tile offsets into one static 2x2 (16x16) image,
    -- always fully shown -- the ROM never draws all 4 together; each of
    -- the 6 flying pieces is a 2-tile-wide, 1-tile-tall sprite that
    -- alternates between 2 captured frames. Two separate 2x1 sprites
    -- built here; `:draw()` below alternates between them (a
    -- live-confirmed 2-frame debris flap/spin, not a guess).
    local deathData = profile.graphics.enemyDeath
    if deathData then
      self.enemyDeathSpriteA = CreatureSprite.fromOffsets(romData, deathData.frameA, 2, 1)
      self.enemyDeathSpriteB = CreatureSprite.fromOffsets(romData, deathData.frameB, 2, 1)
    end
    -- Per-tile wall collision -- see Player.lua's `canMoveTo` doc
    -- comment and rom_profiles.lua's `startRoom.floorTileIds` for
    -- exactly what "real" means here (a captured tile grid, classified
    -- into floor/wall by this project, not a decoded ROM collision
    -- table).
    self.canMoveTo = Field.buildWalkabilityCheck(
      profile.graphics.startRoom, self.player.width, self.player.height)
    -- Attack visuals (see AttackSwing.lua/AttackThrust.lua) -- direct
    -- fix for a named gap: attacking previously applied damage with
    -- zero visual feedback. Two distinct attacks exist -- standing
    -- still swings, moving thrusts (direct user report from the same
    -- investigation round that the sword should thrust forward when
    -- attacking while moving).
    if profile.graphics.attackSwing then
      self.attackSwing = AttackSwing.new(romData, profile)
    end
    if profile.graphics.attackThrust then
      self.attackThrust = AttackThrust.new(romData, profile)
    end
    -- HUD bar decoration (see HudBar.lua) -- direct fix for a named gap
    -- (the HUD was missing its power/status bar).
    if profile.graphics.hudBar then
      self.hudBar = HudBar.new(romData, profile)
    end
  end
  return self
end

--- Build a `canMoveTo(x, y)` predicate (see Player.lua) from a
-- `startRoom`-shaped profile entry. Thin wrapper kept for backward
-- compatibility (existing callers/tests reference `Field
-- .buildWalkabilityCheck`) -- the real logic now lives in
-- `src/entities/TileWalkability.lua` (extracted once a second room,
-- the post-victory scene, needed the exact same mechanism -- see that
-- module's doc comment).
function Field.buildWalkabilityCheck(startRoom, footprintW, footprintH)
  return TileWalkability.build(startRoom, footprintW, footprintH)
end

-- F2 opens the graphics-region debug viewer (TileViewer -- see its own
-- doc comment) on top of the field, without disturbing field state
-- underneath (StateStack:push, not :replace) -- part of "debugging
-- tools are a first-class feature." Only wired when this Field was
-- built with ROM data/profile, matching every other ROM-dependent
-- feature in this state.
--
-- F3/F4/F5/F6: developer shortcuts, per the master brief's explicit
-- request for reload/teleport/spawner/give-item/set-HP dev tools to
-- accelerate reverse engineering. None of these claim to be verified
-- ROM behavior -- they're development aids, same spirit as the F1
-- overlay and F2 viewer.
--
-- F7: save the game state (Stats + heroName) via SaveFile.write -- the
-- VERIFIED nibble-packed/magic-byte/duplicate-copy container format
-- (see src/save/SaveFormat.lua), this project's field layout on top of
-- it (SaveData.lua). WHEN a save happens is a dev-only choice, not a
-- reproduced ROM trigger -- the original ROM's trigger condition is
-- unknown (see rom-map.md "Save RAM"'s honest note). Loading happens
-- via the title screen's "Weiterspielen" option (TitleScreen.lua), not
-- a second dev key here.
--
-- F9: opens MusicJukebox.lua -- a dev-only browser for all 30 songs
-- this project's MusicDecoder/MusicScore/MusicPlayer pipeline can now
-- actually play through `love.audio`. Same "real content, no
-- fabricated trigger" reasoning as F8 below: no live ROM trigger for
-- "which song plays at which game moment" has been found yet.
--
-- F8 (see RoomExplorer.lua's doc comment): opens RoomExplorer.lua -- a
-- dev-only browser, originally for just `unknownRoomA`'s 6 rooms, now
-- for the whole room catalog (see that module's doc comment for the
-- full "why dev-only, not a real door" reasoning: no live ROM trigger
-- into any of these rooms was ever found, so wiring one in as an
-- in-fiction exit would fabricate ROM behavior this project doesn't
-- actually have evidence for). Still gated on
-- `profile.graphics.unknownRoomA_8` existing -- a real, still-present
-- field, just no longer itself rendered by this path (RoomExplorer
-- decodes everything live from the ROM instead).
--
-- F10: opens TransitionExplorer.lua -- a dev-only browser for the
-- general cut-transition landing table this project found
-- (CutTransitionTable.lua). Same "real content, no fabricated trigger"
-- reasoning as F8/F9: 82 genuinely distinct transitions are fully
-- decoded (target roomSelector + landing tile), but only 2 have a
-- known in-game trigger and are actually wired as ordinary exits --
-- the other 80 (including 36 targeting the long-mysterious
-- `unknownRoomA` family) are ROM data with an honestly-unknown
-- trigger, not fabricated new doors.
--
-- F11: opens ActorExplorer.lua -- a dev-only browser for the RNG-gated
-- actor-definition table this project found (ActorDefinitionTable
-- .lua). Same "real content, no fabricated trigger" reasoning as
-- F8-F10: 218 records are fully decoded (measured full extent), but
-- only 2 have a confirmed live spawn behind them -- the index actually
-- used at runtime is computed via the combat PRNG, not a fixed
-- per-room constant, so most entries' in-game relevance stays honestly
-- unknown.
--
-- F12: grants a few catalog items/weapons into `self.inventory` -- not
-- a screen, just inventory-state mutation. Exists only to make
-- Menu.lua's Dinge/Waffe interactivity reachable: the ROM's
-- item-granting trigger (shop? chest?) is honestly still unknown, so a
-- fresh, un-F12'd game still shows the exact same VERIFIED
-- empty-inventory menu as before.
function Field:keypressed(key)
  if key == "f2" and self.romData and self.profile and self.stack then
    local TileViewer = require("src.app.states.TileViewer")
    self.stack:push(TileViewer.new(self.romData, self.profile, self.input, self.overlay, self.stack))
  elseif key == "f3" then
    -- Teleport: reset the player to its real verified spawn position.
    local ps = self.profile and self.profile.graphics.playerSprite
    self.player.x, self.player.y = ps and ps.screenX or 0, ps and ps.screenY or 0
  elseif key == "f4" then
    self.debugInvulnerable = not self.debugInvulnerable
  elseif key == "f5" then
    self.stats:heal(self.stats.maxLP)
  elseif key == "f6" then
    -- Debug-only instant kill (a stand-in "encounter/enemy spawner"-
    -- adjacent shortcut for this project's single enemy -- clears it
    -- immediately without needing real combat, useful for testing what
    -- comes after: the real event system, docs/progress.md).
    if self.enemy:isAlive() then
      self.enemy.stats:damage(self.enemy.stats.curLP)
      -- Real death "explosion" (2026-08-12) -- same real animation a
      -- landed attack triggers (see the `Enemy:hit()` call site above),
      -- not an instant cut, so this dev shortcut shows real ROM
      -- behavior too instead of skipping past it.
      self.enemy:startDeath(self.profile)
    end
  elseif key == "f7" then
    local SaveFile = require("src.save.SaveFile")
    local ok, err = SaveFile.write(self.stats, self.heroName)
    self.saveStatusMessage = ok and "gespeichert" or ("Fehler: " .. tostring(err))
  elseif key == "f8" and self.romData and self.profile and self.stack
      and self.profile.graphics.unknownRoomA_8 then
    local RoomExplorer = require("src.app.states.RoomExplorer")
    self.stack:push(RoomExplorer.new(self.romData, self.profile, self.input, self.overlay, self.stack))
  elseif key == "f9" and self.romData and self.stack then
    -- Task #151 (2026-08-16, "port the decoded music format into src/
    -- audio/ + love.audio playback"): a dev-only jukebox for all 30
    -- real songs, same "real content, no fabricated trigger" precedent
    -- as F8's RoomExplorer -- see MusicJukebox.lua's own doc comment.
    -- Stop the real field background music first (added same day,
    -- direct continuation) -- Field:update stops running the instant
    -- Jukebox is pushed on top (StateStack:update only drives the top
    -- state), but the already-queued love.audio buffers would otherwise
    -- keep playing underneath/overlapping the Jukebox's own playback
    -- for up to ~1.2s (BUFFER_COUNT*BUFFER_SECONDS) until they drain.
    if self.musicPlayer then self.musicPlayer:stop() end
    local MusicJukebox = require("src.app.states.MusicJukebox")
    self.stack:push(MusicJukebox.new(self.romData, self.input, self.overlay, self.stack))
  elseif key == "f10" and self.romData and self.stack then
    -- 2026-08-16, task "komplett autark interpretiert"/blocker
    -- resolution: a dev-only browser for the real, general cut-
    -- transition landing table (CutTransitionTable.lua) -- same "real
    -- content, no fabricated trigger" precedent as F8/F9 above: 82
    -- genuinely distinct real transitions are fully decoded, but only
    -- 2 have a known real in-game trigger (see TransitionExplorer.lua's
    -- own doc comment).
    local TransitionExplorer = require("src.app.states.TransitionExplorer")
    self.stack:push(TransitionExplorer.new(self.romData, self.input, self.overlay, self.stack))
  elseif key == "f11" and self.romData and self.stack then
    -- 2026-08-16, direct continuation, "Tabelle voll ausmessen" ->
    -- "alles konsolidieren dokumentieren und in app und website
    -- einbauen": a dev-only browser for the real, RNG-gated actor-
    -- definition table (ActorDefinitionTable.lua) -- same "real
    -- content, no fabricated trigger" precedent as F8-F10 above: 218
    -- real records are fully decoded, but only 2 have a confirmed
    -- live spawn (see ActorExplorer.lua's own doc comment).
    local ActorExplorer = require("src.app.states.ActorExplorer")
    self.stack:push(ActorExplorer.new(self.romData, self.input, self.overlay, self.stack))
  elseif key == "f12" and self.inventory then
    -- 2026-08-16, task "Item/Ausrüstung nutzbar machen" (direct user
    -- selection): a dev-only shortcut granting a few real catalog
    -- items/weapons -- exists ONLY to make the new real Dinge/Waffe
    -- interactivity (Menu.lua) reachable and testable. NOT a claimed
    -- ROM trigger: the real ROM's own item-granting condition (shop?
    -- chest?) is honestly still unknown (see combat.md's own "Real
    -- equip-swap test attempted, blocked" entry) -- same "dev-only
    -- browser, no fabricated gameplay trigger" precedent as F8-F11
    -- above, just for inventory state instead of a new screen. Grants
    -- real, named catalog entries (not guessed placeholders); repeated
    -- presses keep granting items (a real pickup would too) but the
    -- weapon grant is a real no-op once already held (Inventory
    -- .addWeapon's own duplicate guard).
    local inv = self.inventory
    if inv.itemCatalog[1] then inv:addItem(inv.itemCatalog[1].name) end
    if inv.spellCatalog[2] then inv:addItem(inv.spellCatalog[2].name) end
    for _, w in ipairs(inv.weaponCatalog) do
      if w.index ~= inv.equippedWeaponIndex then
        inv:addWeapon(w.name)
        break
      end
    end
  end
end

function Field:update(dt)
  -- Real background music: feeds the next few love.audio buffers every
  -- real frame (see MusicPlayer.lua's own doc comment) -- unconditional,
  -- same "always advance regardless of other branches" pattern
  -- self.knockback:update below already uses. A no-op when never
  -- started (headless construction, or love.audio unavailable).
  if self.musicPlayer then self.musicPlayer:update(dt) end
  if self.stack and self.input:pressed("select") then
    self.stack:pop()
    return
  end
  -- VERIFIED live (docs/reverse-engineering/rom-map.md "The in-game
  -- menu system"): START opens a real menu during field control.
  if self.stack and self.input:pressed("start") then
    local Menu = require("src.app.states.Menu")
    self.stack:push(Menu.new(self.romData, self.profile, self.input, self.stack, self.inventory))
    return
  end

  -- Real, live-captured movement cycle (VERIFIED 2026-08-09 -- see
  -- Enemy.MOVEMENT_CYCLE's doc comment) -- the creature was frozen in
  -- place before this pass, which real play does not match.
  self.enemy:updateMovement(dt)
  if self.enemyFlashTimer > 0 then
    self.enemyFlashTimer = self.enemyFlashTimer - 1
  end

  -- Real contact-hit reaction (task #12, KnockbackFlicker.lua): advance
  -- it every frame regardless of whether a hit is currently active (a
  -- no-op returning (0,0) when it isn't).
  local kdx, kdy = self.knockback:update(dt)

  if self.knockback:isKnockbackActive() then
    -- Real knockback motion frames: forced movement, no player input
    -- (see KnockbackFlicker.lua's doc comment -- a reasonable
    -- implementation choice, not itself independently verified).
    --
    -- CORRECTED (2026-08-10, direct user report: "der pushback pusht
    -- den player in Waende (keine Kollision) und der pushback wirkt
    -- auch sehr weit"): this used to add kdx/kdy unconditionally,
    -- clamped only against the room's OUTER bounds (self.playerBounds)
    -- -- unlike every other real movement in this state, which checks
    -- the real per-tile wall collision (self.canMoveTo, same predicate
    -- Player:update uses) before committing a move. A knockback aimed
    -- at a wall therefore shoved the player straight through it instead
    -- of stopping there like normal walking does -- almost certainly
    -- also the real cause of "wirkt sehr weit" (32px, the real VERIFIED
    -- distance from KnockbackFlicker.lua's own live capture, looks/feels
    -- much larger than intended once it carries the player through a
    -- wall into space that should have been unreachable). Now checked
    -- per-axis against canMoveTo, same as Player:update, so knockback
    -- can't cross a wall the player couldn't otherwise walk through --
    -- the 32px distance/speed itself is untouched (still the real,
    -- live-captured value), only wall-crossing is fixed.
    local newX = self.player.x + kdx
    local newY = self.player.y + kdy
    if kdx ~= 0 and (not self.canMoveTo or self.canMoveTo(newX, self.player.y)) then
      self.player.x = newX
    end
    if kdy ~= 0 and (not self.canMoveTo or self.canMoveTo(self.player.x, newY)) then
      self.player.y = newY
    end
    local minX, minY, maxX, maxY = self.playerBounds[1], self.playerBounds[2],
      self.playerBounds[3], self.playerBounds[4]
    self.player.x = math.max(minX, math.min(maxX, self.player.x))
    self.player.y = math.max(minY, math.min(maxY, self.player.y))
  else
    -- Try the move, then reject it if it would walk into a living enemy
    -- (VERIFIED: this project traced a real, hard collision block
    -- against the creature -- see rom-map.md "Breakthrough"). Real
    -- movement stays player-controlled outside the knockback frames
    -- themselves, including while still flickering/invincible.
    local prevX, prevY = self.player.x, self.player.y
    self.player:update(dt, self.input, self.playerBounds, self.canMoveTo)
    if self.enemy:isAlive() and
        self.enemy:overlaps(self.player.x, self.player.y, self.player.width, self.player.height) then
      self.player.x, self.player.y = prevX, prevY
    end
  end

  -- Contact damage while blocked against a living enemy. F4
  -- (self.debugInvulnerable) is a dev-only shortcut, not real ROM
  -- behavior -- see Field:keypressed's doc comment. Real invincibility
  -- (KnockbackFlicker:isInvincible) additionally blocks re-triggering
  -- while the previous hit's reaction is still playing out -- the
  -- actual real mechanic, not just the enemy's own cooldown timer.
  --
  -- WIRED (2026-08-10): the real, fully-decoded ROM damage formula
  -- ($50AC, see CombatFormulas.lua) with the real enemy ATK (Enemy.ATK
  -- = 8, code- and live-confirmed, see Enemy.lua) and the real player
  -- DEF (self.stats.defense, live-captured $D6C3, see Stats.lua) --
  -- not the old fixed Enemy.CONTACT_DAMAGE constant. `self.combatNoise`
  -- is absent when no ROM is loaded (dev/test fallback, see Field.new)
  -- -- falls back to the old constant rather than erroring, since a
  -- love-free/no-ROM context still needs SOME contact damage to work.
  if self.enemy:isAlive() and
      self.enemy:overlaps(self.player.x, self.player.y, self.player.width, self.player.height) then
    if self.enemy:tickContactCooldown(dt) and not self.debugInvulnerable
        and not self.knockback:isInvincible() then
      local damage
      if self.combatNoise then
        damage = CombatFormulas.rollDamage(Enemy.ATK, self.stats.defense, self.combatNoise:draw())
      else
        damage = Enemy.CONTACT_DAMAGE
      end
      self.stats:damage(damage)
      self.knockback:trigger(
        self.enemy.x + self.enemy.width / 2, self.enemy.y + self.enemy.height / 2,
        self.player.x + self.player.width / 2, self.player.y + self.player.height / 2)
    end
  end

  -- Attack: A (VERIFIED, corrected 2026-08-09 -- see docs/progress.md)
  -- while within reach of a living enemy. This project's own rom-map.md
  -- "Breakthrough" entry already documented "A, not B" clears the
  -- creature; this pass re-verified it directly (fought the real boss
  -- live under mGBA with the corrected room -- see progress.md) and
  -- finally wired the engine to match, rather than leaving a known,
  -- already-documented discrepancy in place.
  --
  -- VERIFIED (2026-08-09): the real attack plays on EVERY A press,
  -- standalone, whether or not an enemy is anywhere nearby (confirmed
  -- live -- see rom_profiles.lua's `attackSwing` doc comment) -- so the
  -- visual trigger below is unconditional.
  --
  -- VERIFIED (2026-08-09, same investigation round): which real attack
  -- plays depends on whether the player is moving at the instant A is
  -- pressed -- `self.player.moving` is already real, per-frame state
  -- (Player.lua), so this is a direct read, not new tracking. Standing
  -- still -> the swing (arc); moving -> the thrust (see AttackThrust.lua).
  if self.input:pressed("a") then
    local attack = self.player.moving and self.attackThrust or self.attackSwing
    if attack then
      attack:trigger(self.player.facing)
      self.attackHasHit = false
    end
  end
  if self.attackSwing then self.attackSwing:update(dt) end
  if self.attackThrust then self.attackThrust:update(dt) end

  -- CORRECTED (2026-08-09, same day): hit detection used to be a single
  -- static distance check at the instant A was pressed (ATTACK_REACH,
  -- below) -- direct user report that the enemy "seems to take no
  -- damage" traced to exactly that: the real swing animates outward
  -- over the following 16 real frames, so a press that visually swings
  -- into the enemy a few frames later never actually registered. Now
  -- checked every frame either real attack is active, against its own
  -- real per-phase hitboxes (`getHitboxes`) -- one hit per attack
  -- (`attackHasHit`, reset on each new trigger), same real
  -- `Enemy:overlaps` AABB test already used for contact damage above.
  local activeAttack = (self.attackSwing and self.attackSwing:isActive() and self.attackSwing)
    or (self.attackThrust and self.attackThrust:isActive() and self.attackThrust)
  if activeAttack and not self.attackHasHit and self.enemy:isAlive() then
    for _, box in ipairs(activeAttack:getHitboxes(self.player.x, self.player.y)) do
      if self.enemy:overlaps(box.x, box.y, box.w, box.h) then
        self.attackHasHit = true
        if self.enemySpriteFlash then
          self.enemyFlashTimer = self.enemyFlashFrames
        end
        if self.enemy:hit() then
          -- Real death "explosion" (2026-08-12, direct user correction
          -- -- see rom_profiles.lua's own `enemyDeath` doc comment for
          -- the full live-traced evidence): the real creature's own
          -- six body-part tiles scatter apart for a real ~86 frames
          -- before vanishing -- `enemyDefeated` (which fires the real
          -- `victory_sequence_on_boss_defeat` event, replacing this
          -- whole screen) is deliberately NOT set yet here; it's set
          -- once `Enemy:deathComplete()` below, so the player actually
          -- sees the real scatter instead of an instant cut.
          self.enemy:startDeath(self.profile)
        end
        break
      end
    end
  end

  if self.enemy.death and not self.enemyDefeated then
    self.enemy:updateDeath(dt)
    if self.enemy:deathComplete() then
      self.enemyDefeated = true
    end
  end

  -- Real event/trigger system tick (see FIELD_EVENTS/EventSystem.lua) --
  -- replaces the old inline "if self.dialogueQueued" check. Overlay line
  -- is added from :draw (not here) -- Overlay:clearLines() runs right
  -- before :draw each real frame (see main.lua), so a line added during
  -- :update would already be wiped by the time it could ever show.
  local firedIds = self.events:update(self, function(action, state)
    self:dispatchEvent(action, state)
  end)
  if #firedIds > 0 then
    self.lastFiredEvent = table.concat(firedIds, ", ")
  end

  if self.playerSprite then
    self.playerSprite:update(dt, self.player.moving, self.player.facing)
  end
  if self.enemySprite then
    self.enemySprite:update(dt, false) -- stationary enemy; no walk cycle to drive it
  end
end

--- Format the VERIFIED "LP <n> MP <n> G <n>" HUD string (see
-- docs/reverse-engineering/text.md) from a real Stats instance.
function Field.formatHud(stats)
  return string.format("LP %d MP %d G %d", stats.curLP, stats.curMP, stats.gold)
end

--- A plain, `love.*`-free snapshot of key fields -- for automated
-- scripted verification (`MYSTICQUEST_WAIT_FOR`, see main.lua's own doc
-- comment and VictorySequence.lua's own matching method), added
-- 2026-08-11.
function Field:debugState()
  return {
    room = "startRoom",
    x = self.player.x,
    y = self.player.y,
    enemyAlive = self.enemy:isAlive(),
    enemyDefeated = self.enemyDefeated,
    curLP = self.stats.curLP,
    -- ADDED (2026-08-16, real field background music) -- live-verify
    -- actual love.audio playback the same way MusicJukebox.lua's own
    -- debugState already does (segIndex only climbs once real audio is
    -- genuinely synthesized/queued, not just "no crash happened").
    musicPlaying = self.musicPlayer and self.musicPlayer:isPlaying(),
    musicSongIndex = self.musicPlayer and self.musicPlayer.songIndex,
  }
end

--- Execute one EventSystem action (see src/scripting/EventSystem.lua's
-- doc comment for the overall design). Action *types* are named after
-- the master brief's own list; only "dialogue" has a real handler so
-- far -- an unimplemented type fails loudly (this project's "no silent
-- fallbacks" rule) instead of being silently skipped, so a future event
-- definition that names a type nothing handles yet is caught immediately
-- rather than quietly doing nothing.
function Field:dispatchEvent(action, state)
  if action.type == "dialogue" then
    if state.font then
      local DialogueBox = require("src.app.states.DialogueBox")
      state.stack:push(DialogueBox.new(action.lines, state.font, state.input, state.stack))
    end
  elseif action.type == "victorySequence" then
    -- Same reasoning as the F9 Jukebox branch above: stop field music
    -- explicitly rather than letting already-queued buffers bleed into
    -- the boss-defeat sequence.
    if state.musicPlayer then state.musicPlayer:stop() end
    local VictorySequence = require("src.app.states.VictorySequence")
    state.stack:push(VictorySequence.new(state.romData, state.profile, state.input,
      state.overlay, state.stack, state.heroName, state.stats))
  else
    error("Field:dispatchEvent: no handler implemented for action type '" ..
      tostring(action.type) .. "'")
  end
end

-- Real collision/hitbox visualization -- master brief, "debugging tools
-- are a first-class feature": "F1... collision display, hitbox
-- display." Draws outlines only (no fill), only while the F1 overlay is
-- visible, so it never affects the normal play view.
local DEBUG_PLAYER_COLOR = { 0, 1, 1, 1 }
local DEBUG_ENEMY_COLOR = { 1, 0.3, 0.3, 1 }
local DEBUG_SWING_COLOR = { 1, 1, 0, 0.8 }

function Field:drawDebugOverlay()
  if not (self.overlay and self.overlay.visible) then return end

  love.graphics.setLineWidth(1)
  love.graphics.setColor(DEBUG_PLAYER_COLOR)
  love.graphics.rectangle("line", self.player.x, self.player.y, self.player.width, self.player.height)

  if self.enemy:isAlive() then
    love.graphics.setColor(DEBUG_ENEMY_COLOR)
    love.graphics.rectangle("line", self.enemy.x, self.enemy.y, self.enemy.width, self.enemy.height)
  end

  -- Real attack hitboxes (see AttackSwing/AttackThrust:getHitboxes) --
  -- replaces the old static reach circle (2026-08-09): hit detection
  -- itself now uses these same real per-phase rectangles, so this is
  -- what actually determines a landed hit, not an approximation of it.
  love.graphics.setColor(DEBUG_SWING_COLOR)
  for _, attack in ipairs({ self.attackSwing, self.attackThrust }) do
    if attack then
      for _, box in ipairs(attack:getHitboxes(self.player.x, self.player.y)) do
        love.graphics.rectangle("line", box.x, box.y, box.w, box.h)
      end
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function Field:draw()
  if self.background then
    self.background:draw(0, 0)
  end

  -- Enemy: VERIFIED real and visible (see constructor comment) --
  -- `enemyConfirmedVisible` defaults true now, kept as a named flag
  -- (rather than removed) so a future room that genuinely doesn't have
  -- a visible enemy yet can still say so explicitly instead of drawing
  -- an unverified guess.
  if self.enemy.death and self.enemyDeathSpriteA and not self.enemy:deathComplete() then
    -- Real death "explosion" (2026-08-12, CORRECTED 2026-08-14, see
    -- rom_profiles.lua's own `enemyDeath` doc comment for the full
    -- live-traced re-check): the real creature's six body-part tile
    -- pairs scatter outward over `totalFrames` real frames -- linear
    -- interpolation between the real captured start (its own resting
    -- pose) and end (frame 81, the last real sample before the
    -- frame-86 vanish) positions, per part, matching that field's own
    -- "honest simplification" note. Each part now alternates between
    -- the 2 real captured debris frames (`frameA`/`frameB`) instead of
    -- showing both stacked together as one static double-height block
    -- -- the alternation CADENCE itself (every 4 real frames here) is
    -- an honest approximation, not independently re-verified to the
    -- exact real frame boundary (the live trace that found the real
    -- 2-frame shape sampled every 8 frames, coarser than the real
    -- period) -- same "not frame-exact, real shape not real timing"
    -- honesty bar as the position interpolation already documented.
    local d = self.profile.graphics.enemyDeath
    local es = self.profile.graphics.enemySprite
    local elapsed = self.enemy.death.elapsedFrames
    local t = math.min(1, elapsed / d.totalFrames)
    local sprite = (math.floor(elapsed / 4) % 2 == 0) and self.enemyDeathSpriteA or self.enemyDeathSpriteB
    for _, part in ipairs(d.parts) do
      local px = es.screenX + part.dx * t
      local py = es.screenY + part.dy * t
      sprite:draw(px, py)
    end
  elseif self.enemy:isAlive() and self.enemyConfirmedVisible then
    -- Real hit-flash (2026-08-09, see rom_profiles.lua's
    -- `enemyHitFlash`): a real OBP1 palette swap for a couple real
    -- frames right when a hit lands, not an invented tint.
    --
    -- Real X-flip patrol flap (2026-08-12, see rom_profiles.lua's
    -- `enemySprite.flipXTogglesPerStep` doc comment and
    -- `Enemy:isFlipped()` -- CORRECTED same day, this used to be wired
    -- into `flipY`, a real bits-5/6 mixup): applies to all three draw
    -- paths below (flash/normal/fallback-rect all show the same real
    -- creature).
    local flipX = self.enemy:isFlipped()
    if self.enemyFlashTimer > 0 and self.enemySpriteFlash then
      self.enemySpriteFlash:draw(self.enemy.x, self.enemy.y, flipX)
    elseif self.enemySprite then
      self.enemySprite:draw(self.enemy.x, self.enemy.y, flipX)
    else
      love.graphics.setColor(0.5, 0.15, 0.55, 1)
      love.graphics.rectangle("fill", self.enemy.x, self.enemy.y, self.enemy.width, self.enemy.height)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- Real invincibility flicker (task #12, KnockbackFlicker.lua): the
  -- player sprite itself is skipped on real "invisible" frames, exactly
  -- reproducing the live-captured on/off schedule rather than a dimmed/
  -- tinted placeholder.
  if self.playerSprite and self.knockback:isVisible() then
    -- VERIFIED real facing mechanism (2026-08-09 -- see CreatureSprite
    -- .draw's doc comment): X-flip only while facing right, same art
    -- otherwise. Direct user prompt: "ich glaube er müsste sich auch
    -- drehen" -- re-checked live rather than guessing, and confirmed:
    -- not a 4-direction sprite set, just a real mirror for one facing.
    -- REVERTED (2026-08-15, same day, direct user report: "im ersten
    -- bossraum scheint die kollision verschoben zu sein" -- collision
    -- looks shifted in the first boss room). This briefly called
    -- `self.player:renderPosition()` (the real, OAM-verified `(-8,-16)`
    -- hardware offset, see Player.lua's own doc comment) here too --
    -- WRONG for this specific room: `startRoom`'s own real
    -- `floorTileIds`/sprite positions were historically captured and
    -- cross-checked via direct screenshot comparison against the RAW,
    -- unshifted `self.player.x/y` -- this whole room's own visual
    -- calibration already implicitly assumes that convention. Applying
    -- the render offset here shifts the sprite 8px left/16px up
    -- relative to that already-correct calibration -- a real, self-
    -- inflicted regression, not a fix. The underlying OAM finding
    -- itself is still real (confirmed via live hardware OAM dump) --
    -- it just isn't safe to apply blindly to every room this project
    -- already calibrated the OLD way. Back to the raw, untouched
    -- position here; see `rom_profiles.lua`'s own `thirdRoom.exits`
    -- doc comment for where this offset DOES apply (one specific,
    -- individually-verified landing spot, not a global draw-time rule).
    self.playerSprite:draw(self.player.x, self.player.y, self.player.facing == "right")
    -- Real attack visuals, drawn on top of the player (see AttackSwing
    -- .lua/AttackThrust.lua) -- a no-op draw while inactive; at most one
    -- of the two is ever active at once (Field:update only triggers
    -- one per A press).
    if self.attackSwing then self.attackSwing:draw(self.player.x, self.player.y) end
    if self.attackThrust then self.attackThrust:draw(self.player.x, self.player.y) end
  else
    -- No ROM loaded -- fall back to a plain rectangle at the player's
    -- own current size (the generic single-tile default when no real
    -- ROM sprite data is available -- see Player.DEFAULT_WIDTH/HEIGHT)
    -- rather than crash.
    love.graphics.setColor(0.9, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", self.player.x, self.player.y,
      self.player.width, self.player.height)
    love.graphics.setColor(1, 1, 1, 1)
  end

  self:drawDebugOverlay()

  -- VERIFIED (2026-08-09, corrected -- see docs/progress.md): the real
  -- HUD strip is WHITE with black text, not a solid black bar -- caught
  -- comparing against the (also newly-corrected) real ground-truth
  -- screenshot.
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, PLAY_H, ROOM_W, HUD_H)
  local hudText = Field.formatHud(self.stats)
  if self.font then
    self.font:print(hudText, 2, PLAY_H + 4, { 0, 0, 0, 1 })
  else
    -- No ROM loaded (e.g. this state constructed without romData/profile)
    -- -- fall back to love's own font rather than crash, but say so.
    love.graphics.setColor(0.5, 0.4, 0, 1)
    love.graphics.print(hudText .. " (no ROM font loaded)", 2, PLAY_H + 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
  if self.hudBar then
    self.hudBar:draw()
  end

  if self.overlay then
    self.overlay:addLine("map/room id", "startRoom (the only room this project has ground-truthed)")
    self.overlay:addLine("player x,y", string.format("%d, %d (%dx%d)",
      self.player.x, self.player.y, self.player.width, self.player.height))
    self.overlay:addLine("facing", self.player.facing)
    self.overlay:addLine("attack", (self.attackSwing and self.attackSwing:isActive()
        and ("swing, phase " .. self.attackSwing.phaseIndex))
      or (self.attackThrust and self.attackThrust:isActive()
        and ("thrust, frame " .. self.attackThrust.frameIndex))
      or "idle")
    self.overlay:addLine("player stats", string.format("LP %d/%d MP %d/%d lvl %d gold %d",
      self.stats.curLP, self.stats.maxLP, self.stats.curMP, self.stats.maxMP,
      self.stats.level, self.stats.gold))
    self.overlay:addLine("enemy", self.enemy:isAlive() and
      string.format("alive, %d/%d hp, pos %d,%d (%dx%d)", self.enemy.stats.curLP,
        self.enemy.stats.maxLP, self.enemy.x, self.enemy.y, self.enemy.width, self.enemy.height)
      or "cleared")
    self.overlay:addLine("room", "VERIFIED real starting room (live ground-truth capture)")
    self.overlay:addLine("hud", hudText .. (self.font and " (real font)" or " (fallback font)"))
    self.overlay:addLine("last event fired", self.lastFiredEvent or "(none yet)")
    self.overlay:addLine("invulnerable (F4)", self.debugInvulnerable and "ON" or "off")
    if self.saveStatusMessage then
      self.overlay:addLine("save (F7)", self.saveStatusMessage)
    end
    self.overlay:addLine("dev keys", "F2 tiles, F3 teleport, F4 invuln, F5 heal, F6 kill enemy, F7 save, F8 room catalog")
  end
end

return Field
