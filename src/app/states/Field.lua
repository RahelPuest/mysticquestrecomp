-- The starting-room vertical slice: real input, real FixedStep timing,
-- a VERIFIED movement speed (see src/entities/Player.lua), a real
-- enemy blocking a chokepoint with real collision and contact combat
-- (see src/entities/Enemy.lua), and the real dialogue sequence this
-- project found live past it (docs/reverse-engineering/rom-map.md
-- "Breakthrough").
--
-- The room background, player sprite, and enemy sprite/position all draw
-- REAL, live-ground-truth-verified content (src/rendering
-- /TileGridBackground.lua, rom_profiles.lua's `startRoom`/`playerSprite`
-- /`enemySprite` entries) -- a real barred-gate courtyard with a real
-- enemy, not a generic placeholder or a guessed arrangement. See
-- rom_profiles.lua's `startRoom` doc comment for the correction history
-- (an earlier capture this same project session was mistakenly the
-- pause menu, not the room -- caught and fixed). Combat numbers (enemy HP,
-- player attack damage) remain reasonable stand-ins, not decoded ROM
-- values -- see Enemy.lua's doc comment for exactly which parts of the
-- combat model are VERIFIED vs. a placeholder.
--
-- The boss-defeat dialogue now fires through a real, reusable event/
-- trigger system (src/scripting/EventSystem.lua -- see FIELD_EVENTS
-- below), not an inline `if` check -- a direct fix for this project's
-- own master brief calling that pattern out by name. The dialogue
-- *text* itself is still hardcoded, not decoded live from ROM bytes --
-- see DialogueBox.lua's provenance note; general dialogue compression
-- remains unsolved (docs/reverse-engineering/text.md).
--
-- Controls: arrows move, A attacks the enemy while adjacent, START
-- opens the real menu (Menu.lua), SELECT pops back to whatever pushed
-- this state.

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

local Field = { opaque = true }
Field.__index = Field

-- VERIFIED (see module doc comment / docs/progress.md): a real Mystic
-- Quest room is exactly one 160x144 GB screen, HUD taking the bottom 2
-- tile-rows (16px), leaving a 160x128 playable area, no camera scroll.
local ROOM_W, ROOM_H = 160, 144
local HUD_H = 16
local PLAY_H = ROOM_H - HUD_H

-- REMOVED (2026-08-09): a fixed ATTACK_REACH circle used to approximate
-- attack range -- replaced by real per-phase swing hitboxes
-- (AttackSwing:getHitboxes) now that the real swing animation itself is
-- implemented, so hit detection checks the actual displayed sword
-- rectangles against the enemy instead of a guessed radius. Direct fix
-- for a user report that the enemy "seems to take no damage" -- the old
-- circle check ran once at press time, before the swing had visually
-- moved anywhere near the enemy.

-- The real post-victory scene (victory line, real black-screen wipe,
-- lore pages, "WILLY" exchange) now lives in VictorySequence.lua -- see
-- that module's doc comment for the full real ROM-code trace this
-- replaced the old flat WILLY_DIALOGUE/DialogueBox pairing with
-- (2026-08-09, "mach mal die scene transition... auf basis des codes und
-- moeglichst allgemein").
--
-- Real, reusable event data (see src/scripting/EventSystem.lua's doc
-- comment for why this replaced an inline `if self.dialogueQueued`
-- check -- a direct fix for this project's own master brief calling out
-- exactly that pattern as something to avoid). `state` here is the
-- Field instance itself (see Field:update's `self.events:update(self,
-- ...)` call) -- the trigger only reads `state.enemyDefeated`, a real
-- boolean this state sets the instant the boss-clearing hit lands, not
-- a queued/deferred flag.
local FIELD_EVENTS = {
  {
    id = "victory_sequence_on_boss_defeat",
    trigger = function(state) return state.enemyDefeated end,
    actions = { { type = "victorySequence" } },
  },
}

--- `savedStats`: optional plain table of Stats fields from a real,
-- loaded save (see SaveFile.load()/SaveData.deserialize) -- used by
-- TitleScreen.lua's real "Weiterspielen" path instead of the fresh-
-- character defaults below. Absent for every other entry point (a new
-- game, dev shortcuts, tests), which is not a fallback -- those
-- genuinely have no save to restore from.
--
-- `enemyState`: optional `{x=, y=, movementIndex=}` (2026-08-12, direct
-- user report: "der boss intro sequenz stimmt noch nicht") -- lets
-- `BattleIntro.lua` hand off its own already-in-progress real patrol
-- (see `Enemy.MOVEMENT_CYCLE`) seamlessly instead of this state
-- silently resetting the creature back to its own static rest position
-- the instant the cutscene ends (a real, visible position "jump" the
-- old code had). Absent for every other entry point (dev shortcuts,
-- tests, a hypothetical future "reload mid-game" path) -- those fall
-- back to the same real rest position (`enemySprite.screenX/screenY`)
-- as before, unchanged.
function Field.new(romData, profile, input, overlay, stack, heroName, savedStats, enemyState)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    -- The real player-entered name (see NameEntry.lua), threaded through
    -- BattleIntro -- used by VictorySequence's real captured text
    -- ("<name> ist ein tapferer Kaempfer.", etc). A clearly-labeled
    -- fallback for dev shortcuts that construct Field directly without
    -- going through NameEntry (e.g. tests, F-key dev entry points), not
    -- a silent default for the real flow.
    heroName = heroName or "HELD",
    -- VERIFIED spawn position (2026-08-09, corrected same day -- see
    -- docs/progress.md): a live mGBA ground-truth capture of the REAL
    -- starting room (not the earlier-mistaken pause-menu capture) read
    -- the player's actual OAM position and converted it to screen space
    -- (Pan Docs OAM offset convention) -- see rom_profiles.lua's
    -- `playerSprite.screenX/screenY`.
    player = Player.new(0, 0),
    -- VERIFIED fresh-character stats (see module doc comment) -- a real
    -- data model, not placeholder numbers; the same fields this
    -- project's own dynamic tracing read live out of a fresh save.
    -- Overridden by `savedStats` (task P6, "Weiterspielen") when given.
    stats = Stats.new(savedStats or { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, level = 1, gold = 50 }),
    -- Real inventory/equipment data model (task P5, see Inventory.lua's
    -- own doc comment) -- built once here (not by Menu.lua, which used
    -- to decode WeaponTable itself just to find one name) so equip/item
    -- state persists across opening and closing the real menu.
    inventory = Inventory.new(romData, profile),
    -- Real contact-hit reaction: knockback + invincibility flicker
    -- (task #12, see KnockbackFlicker.lua's own doc comment for the
    -- precise live-captured schedule this reproduces).
    knockback = KnockbackFlicker.new(),
    -- VERIFIED position (2026-08-09, corrected -- see rom_profiles.lua's
    -- `enemySprite.screenX/screenY`): the real creature blocking the
    -- gate, read from the same corrected live capture as the player.
    -- Real size set below once the profile's sprite data is available;
    -- Enemy.new's own default (see Enemy.DEFAULT_WIDTH/HEIGHT) applies
    -- otherwise. Drawn by default now (see enemyConfirmedVisible below)
    -- -- this is the real thing, not a placeholder.
    enemy = Enemy.new(0, 0),
    enemyConfirmedVisible = true,
    -- Real hit-flash countdown (see rom_profiles.lua's `enemyHitFlash`)
    -- -- real GB frames remaining to show the flashed palette sprite,
    -- 0 = normal. Decremented once per Field:update (one real GB frame).
    enemyFlashTimer = 0,
    -- Real event/trigger system (see FIELD_EVENTS/EventSystem.lua) --
    -- `enemyDefeated` is real state this instance owns and updates, not
    -- a one-off queued flag; the event system reads it every step.
    enemyDefeated = false,
    events = EventSystem.new(FIELD_EVENTS),
  }, Field)
  -- Bounds/collision fallback for when no real ROM is loaded (see the
  -- `if romData and profile` block below for the real, profile-derived
  -- values) -- uses the player's own generic single-tile default size,
  -- not a guessed creature size.
  self.playerBounds = { 0, 0, ROOM_W - self.player.width, PLAY_H - self.player.height }
  if romData and profile then
    self.font = Font.new(romData, profile)
    self.background = TileGridBackground.new(romData, profile.graphics.startRoom)
    -- WIRED (2026-08-10): the real combat PRNG (ROM $2B1E, see
    -- CombatNoise.lua's own doc comment for the exact ported algorithm)
    -- -- one shared, persistent instance so its internal counter/cap
    -- state advances across the whole session like the real hardware's
    -- own $C0B0/$C0B1 WRAM bytes would, not a fresh draw sequence every
    -- contact hit.
    if profile.noiseTable then
      self.combatNoise = CombatNoise.new(NoiseTable.decode(romData, profile.noiseTable))
      -- WIRED (2026-08-13, direct user instruction: "der boss kampf an
      -- sich... soll aus den romdaten raus interpretiert werden"): the
      -- real, ROM-data-driven movement AI (see EnemyMovementInterpreter's
      -- own doc comment for the full 3-level decoded mechanism).
      --
      -- CORRECTED (2026-08-13, same day, direct user report: "der
      -- einlauf durch das tor sieht immernoch komisch aus"): a real
      -- interpreter already exists by the time `Field.lua` runs
      -- whenever this room was reached through `BattleIntro.lua` (see
      -- that state's own construction site) -- building a SECOND, fresh
      -- one here (as this code used to) discards its real, already-
      -- advanced internal state and restarts the whole real AI system
      -- from scratch, a genuine discontinuity at the cutscene->gameplay
      -- boundary. Reuse the handed-off instance when present;
      -- otherwise (dev shortcuts/tests reaching Field directly, with no
      -- real BattleIntro run first) build + `skipTicks` a fresh one,
      -- same as before.
      if enemyState and enemyState.movementInterpreter then
        self.enemy.movementInterpreter = enemyState.movementInterpreter
      else
        self.enemy.movementInterpreter = EnemyMovementInterpreter.new(romData, self.combatNoise)
        -- See `EnemyMovementInterpreter:skipTicks`'s own doc comment:
        -- the interpreter's first `#enemyDescent.path` real ticks are
        -- the SAME real event as the (here, unplayed -- no BattleIntro
        -- ran) descent animation -- skip them so THIS entry point's own
        -- starting position/behavior still matches the real, settled
        -- patrol point instead of the real "entrance" ticks.
        if profile.graphics.enemyDescent then
          self.enemy.movementInterpreter:skipTicks(#profile.graphics.enemyDescent.path)
        end
      end
    end
    -- Real DMG sprite palette (OBP0/OBP1, both $D0 -- VERIFIED live, see
    -- rom_profiles.lua's `spritePalette` entry): raw pixel index 1
    -- renders as white (same as background), not a mid-grey -- set once
    -- so every CreatureSprite (here and future ones) renders with the
    -- real hardware palette instead of an arbitrary identity grey ramp.
    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end
    -- Player sprite AND size: size still derived from `playerSprite`
    -- (real ROM cols/rows, see Player.lua's DEFAULT_WIDTH/HEIGHT doc
    -- comment -- direct user correction, 2026-08-09: "bitte hardcode die
    -- sprite sizes nicht, nimm sie aus dem rom"). The sprite itself is
    -- now real, animated (PlayerSprite.lua, rom_profiles.lua's
    -- `playerAnimation`) -- CORRECTED 2026-08-09 (same day): this used
    -- to be a static CreatureSprite because "no walk-cycle animation was
    -- ever observed live," which turned out to be wrong (see
    -- `playerAnimation`'s doc comment for the real capture that
    -- disproved it -- direct user pushback: "es muss doch irgendwo im
    -- ROM eine tabelle... geben").
    local ps = profile.graphics.playerSprite
    self.playerSprite = PlayerSprite.new(romData, profile)
    self.player.x, self.player.y = ps.screenX, ps.screenY
    self.player.width, self.player.height = ps.cols * GBTile.TILE_W, ps.rows * GBTile.TILE_H
    self.playerBounds = { 0, 0, ROOM_W - self.player.width, PLAY_H - self.player.height }
    -- Enemy sprite AND size: same reasoning as the player above --
    -- rom_profiles.lua's `enemySprite` entry, 8 real tiles at
    -- individually-confirmed ROM offsets (not a regular stride, hence
    -- CreatureSprite.fromOffsets rather than .new/.static). `rowSpacing`
    -- (2026-08-13 correction, see that entry's own doc comment): the
    -- real row-to-row gap is 16px, not flush -- both the visual sheet
    -- AND the real collision height below need to account for it.
    local es = profile.graphics.enemySprite
    self.enemySprite = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows, nil, es.rowSpacing)
    self.enemy.x, self.enemy.y = es.screenX, es.screenY
    self.enemy.width = es.cols * GBTile.TILE_W
    self.enemy.height = es.rowSpacing and ((es.rows - 1) * es.rowSpacing + GBTile.TILE_H) or (es.rows * GBTile.TILE_H)
    -- Real handoff from BattleIntro's own already-in-progress patrol
    -- (see Field.new's own `enemyState` doc comment) -- overrides the
    -- static rest position above only when the caller actually has a
    -- real in-progress position to hand off.
    if enemyState then
      self.enemy.x, self.enemy.y = enemyState.x, enemyState.y
      self.enemy.movementIndex = enemyState.movementIndex
    end
    -- Real hit-flash (2026-08-09, see rom_profiles.lua's `enemyHitFlash`
    -- doc comment) -- direct fix for a named gap: "der Gegnersprite
    -- flasht kurz, wenn er von einem Angriff getroffen wird." A second
    -- real sprite instance sharing the exact same tile art, built with
    -- the real flashed OBP1 palette instead of the normal one --
    -- CreatureSprite bakes its palette in at construction, so the flash
    -- is a real palette-swapped image, not a runtime tint/shader.
    local flash = profile.graphics.enemyHitFlash
    if flash then
      self.enemySpriteFlash = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows,
        TileImage.paletteFromShadeIndices(flash.shadeIndices))
      self.enemyFlashFrames = flash.frames
    end
    -- Real death "explosion" sprite (2026-08-12, see rom_profiles.lua's
    -- own `enemyDeath` doc comment) -- the same 4 real body-part tiles
    -- drawn once per scattered position in :draw() below, not a
    -- dedicated 6-tile sheet (the real capture shows 6 OAM PAIRS
    -- reusing this same 4-tile set in different combinations frame to
    -- frame -- one shared 2x2 image, drawn 6 times at 6 real
    -- interpolated positions, reproduces the real "parts flying apart"
    -- look without needing to track which exact pair used which exact
    -- 2 of the 4 tiles at every real frame, see that field's own
    -- "honest simplification" note).
    local deathData = profile.graphics.enemyDeath
    if deathData then
      self.enemyDeathSprite = CreatureSprite.fromOffsets(romData, deathData.tileOffsets, 2, 2)
    end
    -- Real per-tile wall collision (2026-08-09) -- see Player.lua's
    -- `canMoveTo` doc comment and rom_profiles.lua's `startRoom
    -- .floorTileIds` for exactly what "real" means here (a real
    -- captured tile grid, classified into floor/wall by this project,
    -- not a decoded ROM collision table).
    self.canMoveTo = Field.buildWalkabilityCheck(
      profile.graphics.startRoom, self.player.width, self.player.height)
    -- Real attack visuals (2026-08-09, see AttackSwing.lua/AttackThrust
    -- .lua) -- direct fix for a named gap: attacking previously applied
    -- damage with zero visual feedback (direct user report: "es gibt
    -- noch keine attacke"). Two real, distinct attacks exist -- standing
    -- still swings, moving thrusts (direct user report, same
    -- investigation round: "wenn sich der Spieler nach vorne bewegt und
    -- dabei angreift, wird das Schwert nach vorne gestochen").
    if profile.graphics.attackSwing then
      self.attackSwing = AttackSwing.new(romData, profile)
    end
    if profile.graphics.attackThrust then
      self.attackThrust = AttackThrust.new(romData, profile)
    end
    -- Real HUD bar decoration (2026-08-09, see HudBar.lua) -- direct fix
    -- for a named gap (user report: "Poweranzeige fehlt im HUD").
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
-- `src/entities/TileWalkability.lua` (extracted 2026-08-09 once a
-- second real room, the post-victory scene, needed the exact same
-- mechanism -- see that module's doc comment).
function Field.buildWalkabilityCheck(startRoom, footprintW, footprintH)
  return TileWalkability.build(startRoom, footprintW, footprintH)
end

-- F2 opens the graphics-region debug viewer (TileViewer -- see its own
-- doc comment) on top of the field, without disturbing field state
-- underneath (StateStack:push, not :replace) -- part of "debugging
-- tools are a first-class feature." Only wired when this Field was
-- built with real ROM data/profile, matching every other ROM-dependent
-- feature in this state.
--
-- F3/F4/F5/F6: developer shortcuts, per the master brief's own explicit
-- request ("Developer shortcuts may include: reload map, teleport,
-- encounter/enemy spawner, give item, set HP... Debug tools will
-- significantly accelerate reverse engineering"). None of these claim
-- to be verified ROM behavior -- they're development aids, same spirit
-- as the F1 overlay and F2 viewer.
--
-- F7 (2026-08-10, task P6): save the real game state (Stats + heroName)
-- via SaveFile.write -- the real, VERIFIED nibble-packed/magic-byte/
-- duplicate-copy container format (see src/save/SaveFormat.lua), this
-- project's own field layout on top of it (SaveData.lua). WHEN a real
-- save happens is a dev-only choice, not a reproduced ROM trigger --
-- the original ROM's own trigger condition is UNKNOWN (see rom-map.md
-- "Save RAM"'s own honest note). Loading happens via the title
-- screen's real "Weiterspielen" option (TitleScreen.lua), not a
-- second dev key here.
--
-- F8 (2026-08-12): opens RoomExplorer.lua -- a dev-only browser for
-- `unknownRoomA`'s 6 real, VERIFIED rooms (see that module's own doc
-- comment for the full "why dev-only, not a real door" reasoning: no
-- live ROM trigger into that area was ever found, so wiring it in as a
-- real in-fiction exit would fabricate ROM behavior this project
-- doesn't actually have evidence for).
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
  end
end

function Field:update(dt)
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
  if self.enemy.death and self.enemyDeathSprite and not self.enemy:deathComplete() then
    -- Real death "explosion" (2026-08-12, see rom_profiles.lua's own
    -- `enemyDeath` doc comment for the live-traced evidence): the real
    -- creature's six body-part tile pairs scatter outward over
    -- `totalFrames` real frames -- linear interpolation between the
    -- real captured start (its own resting pose) and end (frame 81,
    -- the last real sample before the frame-86 vanish) positions, per
    -- part, matching that field's own "honest simplification" note.
    local d = self.profile.graphics.enemyDeath
    local es = self.profile.graphics.enemySprite
    local t = math.min(1, self.enemy.death.elapsedFrames / d.totalFrames)
    for _, part in ipairs(d.parts) do
      local px = es.screenX + part.dx * t
      local py = es.screenY + part.dy * t
      self.enemyDeathSprite:draw(px, py)
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
    self.overlay:addLine("dev keys", "F2 tiles, F3 teleport, F4 invuln, F5 heal, F6 kill enemy, F7 save, F8 unknownRoomA")
  end
end

return Field
