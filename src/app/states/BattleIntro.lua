-- The first-battle intro: hero walks in from the right, a "Kaempfe!"
-- ("Fight!") textbox appears and types itself out, then the boss
-- creature appears -- direct implementation of a detailed user-supplied
-- reference description, traced against the actual ROM code per direct
-- request (rather than inferring purely from observed OAM/tilemap side
-- effects). See rom_profiles.lua's `battleIntro` entry for the full
-- capture and the ROM addresses (`$0659`/`$065B` spawn init,
-- `$0961-$09BE`/`$09A6` the same generic entity-movement routine this
-- project already found driving ordinary player/enemy movement -- this
-- cutscene reuses it with a synthetic held-left input, not special-cased
-- code, so this state does the same).
--
-- Hands off to the real Field.lua once the sequence finishes -- Field
-- itself is unchanged; this state exists purely to play the real,
-- scripted lead-in first.

local TileGridBackground = require("src.rendering.TileGridBackground")
local PlayerSprite = require("src.rendering.PlayerSprite")
local HudBar = require("src.rendering.HudBar")
local Font = require("src.rendering.Font")
local Player = require("src.entities.Player")
local Stats = require("src.entities.Stats")
local CreatureSprite = require("src.rendering.CreatureSprite")
local Enemy = require("src.entities.Enemy")
local TextDecoder = require("src.import.TextDecoder")
local GBTile = require("src.rendering.GBTile")
local TileImage = require("src.rendering.TileImage")
local TextBox = require("src.rendering.TextBox")
local TilePatch = require("src.rendering.TilePatch")
local EnemyMovementInterpreter = require("src.entities.EnemyMovementInterpreter")
local CombatNoise = require("src.entities.CombatNoise")
local NoiseTable = require("src.import.NoiseTable")

local BattleIntro = { opaque = true }
BattleIntro.__index = BattleIntro

local ROOM_W, ROOM_H = 160, 144
local PLAY_H = 128

-- A synthetic src.core.Input-shaped object: Player:update only needs
-- `:isDown`, so the movement code (collision-free here -- see module
-- doc comment) drives this cutscene the same way it drives ordinary
-- play, rather than a separately-hand-rolled position tween.
local function heldLeftInput()
  return { isDown = function(_, b) return b == "left" end }
end

function BattleIntro.new(romData, profile, input, overlay, stack, heroName)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    heroName = heroName,
    frame = 0,
    done = false,
  }, BattleIntro)

  if romData and profile then
    self.background = TileGridBackground.new(romData, profile.graphics.startRoom)
    self.font = Font.new(romData, profile)
    self.hudBar = profile.graphics.hudBar and HudBar.new(romData, profile)
    self.stats = Stats.new({ curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, level = 1, gold = 50 })

    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end

    local data = profile.graphics.battleIntro
    self.data = data
    if data then
      local ps = profile.graphics.playerSprite
      self.playerSprite = PlayerSprite.new(romData, profile)
      self.player = Player.new(data.walkStartScreenX, ps.screenY, ps.cols * GBTile.TILE_W, ps.rows * GBTile.TILE_H)
      self.player.facing = "left"

      -- Textbox border, same tileset as NameEntry (see rom_profiles.lua
      -- -- one contiguous ROM block) -- now built via the shared TextBox
      -- component (see that module's doc comment for why this replaced
      -- this state's original box-drawing code, including a fill-gap
      -- fix that code had).
      local tb = data.textbox
      self.box = TextBox.new(romData, profile, self.font, tb.border)

      self.text = TextDecoder.decodeString(romData, tb.fileOffset)

      -- Scripted tile-patch openings (see `src/rendering/TilePatch.lua`'s
      -- doc comment): the courtyard gate (a VERIFIED uniform-tile patch)
      -- and the right-wall entrance the player walks in through (a
      -- VERIFIED multi-tile-ID patch -- direct fix for a user report
      -- found by playing the app: the player previously appeared to
      -- walk straight through solid wall here). Both are instances of
      -- the same general ROM mechanism, so both are built the same way
      -- now instead of two separate near-identical modules.
      self.tilePatches = {}
      if data.gate then
        self.tilePatches[#self.tilePatches + 1] = TilePatch.new(romData, data.gate)
      end
      if data.entranceSeal then
        self.tilePatches[#self.tilePatches + 1] =
          TilePatch.new(romData, data.entranceSeal, profile.graphics.startRoom.tileOffsets)
      end

      -- Gate-to-patrol boss walk-in (direct user report that the boss
      -- doesn't just appear -- it walks in from the north through the
      -- gate) -- see rom_profiles.lua's `enemyDescent` doc comment for
      -- the live-traced evidence (the creature spawns at the
      -- courtyard's barred gate, descends straight down using a
      -- separate tile block, then joins the same patrol `Field.lua`
      -- already drives via `Enemy.MOVEMENT_CYCLE`). Built here (not
      -- just in Field.lua) so this cutscene can render/drive it during
      -- its own `postBoxFrames` window, matching the ROM's timing (the
      -- gate open/close frames, `data.gate.openFrame`/`closeFrame`,
      -- land inside that exact window -- see that field's doc comment).
      local es = profile.graphics.enemySprite
      if es and profile.graphics.enemyDescent then
        local enemyHeight = es.rowSpacing and ((es.rows - 1) * es.rowSpacing + GBTile.TILE_H) or (es.rows * GBTile.TILE_H)
        self.enemy = Enemy.new(0, 0, es.cols * GBTile.TILE_W, enemyHeight)
        self.enemySprite = CreatureSprite.fromOffsets(romData, es.tileOffsets, es.cols, es.rows, nil, es.rowSpacing)
        local ed = profile.graphics.enemyDescent
        -- CORRECTED (direct user pushback on an earlier, wrongly-
        -- reverted attempt -- a fresh, from-scratch OAM re-capture
        -- found the actual bug: `screenX` was 16px off and the 16px
        -- row gap is genuine, confirmed live at every one of the 4
        -- descent frames -- see `rom_profiles.lua`'s `enemyDescent` doc
        -- comment for the full re-verification and the honest account.
        self.enemyDescentSprite = CreatureSprite.fromOffsets(romData, ed.tileOffsets, ed.cols, ed.rows, nil, ed.rowSpacing)
        self.enemyStarted = false
        -- WIRED (direct user instruction to interpret the whole start
        -- sequence from beginning to end): one interpreter, ticking
        -- continuously from the moment the gate opens (see `:update`'s
        -- trigger below) -- the same instance `advanceToField` hands to
        -- `Field.lua`, so the per-tick AI state carries seamlessly
        -- across the whole cutscene->gameplay transition, same as real
        -- hardware's single, uninterrupted execution. Not `skipTicks`'d
        -- here (unlike `Field.lua`'s dev-shortcut fallback path) --
        -- this state IS the "entrance," so its first 4 ticks
        -- (independently confirmed byte-for-byte identical to
        -- `enemyDescent.path`, see `Enemy.lua`'s removal note above)
        -- are exactly what should play here.
        if profile.noiseTable then
          self.movementNoise = CombatNoise.new(NoiseTable.decode(romData, profile.noiseTable))
          self.enemy.movementInterpreter = EnemyMovementInterpreter.new(romData, self.movementNoise)
        end
      end
    end
  end

  return self
end

--- Cumulative frame boundaries for each real phase (see rom_profiles
-- .lua's `battleIntro` doc comment for the capture behind each number).
function BattleIntro:phaseBounds()
  local d = self.data
  local hidden = d.hiddenFrames
  local walkEnd = hidden + d.walkFrames
  local settleEnd = walkEnd + d.settleFrames
  local tb = d.textbox
  local typingStart = settleEnd + tb.preDelayFrames
  local typingEnd = typingStart + tb.framesPerLetter * #self.text
  local boxEnd = typingEnd + tb.holdFrames
  local enemyEnd = boxEnd + d.postBoxFrames
  return hidden, walkEnd, settleEnd, typingStart, typingEnd, boxEnd, enemyEnd
end

function BattleIntro:update(dt)
  if self.done or not self.data then return end

  if self.input and self.input:pressed("select") then
    self:advanceToField()
    return
  end

  self.frame = self.frame + 1
  local hidden, walkEnd = self:phaseBounds()

  if self.frame > hidden and self.frame <= walkEnd then
    self.player:update(dt, heldLeftInput(), nil, nil)
  end
  if self.playerSprite then
    self.playerSprite:update(dt, self.frame > hidden and self.frame <= walkEnd, "left")
  end
  -- Player facing, corrected (direct user report that the player
  -- should orient north afterward): live OAM traced the player sprite
  -- through the whole gate/boss-walk-in window and found its tile
  -- stays on the "up"/north idle pose (matching
  -- `Player.DEFAULT_FACING="up"`) the entire time after the walk-in
  -- finishes -- this state used to leave `facing="left"` (set for the
  -- walk-in animation above) unchanged for the rest of the cutscene,
  -- which never matched the ROM. Reset exactly once, right as the
  -- walk-in phase ends.
  --
  -- FIXED FOR REAL (direct user report the player still doesn't
  -- visibly face north here): the line above only ever touched
  -- `self.player.facing`, a plain data field `:draw()` never reads for
  -- this state's player sprite (see below) -- `PlayerSprite`'s
  -- rendered pose is driven entirely by `self.playerSprite.animGroup`/
  -- `.phase`, which `:update()` only touches while `moving` is true
  -- (see that module's doc comment: it deliberately freezes on the
  -- last walk pose once movement stops, a separately-verified general
  -- gameplay fact -- not a bug, and not something to change). So the
  -- walk-in's last "left" pose kept rendering forever after, unaffected
  -- by the facing assignment. This one moment is a scripted cutscene
  -- event with its own direct OAM evidence (the doc comment above),
  -- genuinely different from "the player just stopped walking" --
  -- forcing the render state to the idle (up-facing) pose here matches
  -- that specific trace without contradicting the general
  -- freeze-on-last-pose rule anywhere else.
  if self.frame == walkEnd + 1 then
    self.player.facing = "up"
    if self.playerSprite then
      self.playerSprite.animGroup = nil
    end
  end

  -- Boss walk-in (see rom_profiles.lua's `enemyDescent` doc comment) --
  -- starts exactly at the gate's live-traced `openFrame`, matching the
  -- ROM's timing.
  --
  -- WIRED (direct user instruction to interpret the whole start
  -- sequence): the live pre-tick seed position (`80, 0`) is the same
  -- `enemyDescent.screenX`/an initial Y=0 the old hardcoded path
  -- implied (its first entry, `y=7`, is the position after one
  -- interpreter tick, not before) -- from here, this is just the
  -- ordinary `updateMovement` (no separate descent branch), since the
  -- interpreter's first ticks already reproduce the entrance motion.
  if self.enemy and self.data.gate and self.frame == self.data.gate.openFrame then
    self.enemy.x, self.enemy.y = self.profile.graphics.enemyDescent.screenX, 0
    self.enemyStarted = true
  end
  if self.enemyStarted then
    self.enemy:updateMovement(dt)
  end

  local _, _, _, _, _, _, enemyEnd = self:phaseBounds()
  if self.frame > enemyEnd then
    self:advanceToField()
  end
end

--- True while the enemy should still show its small "peeking through
-- the gate" tile block (`enemyDescentSprite`) instead of the full
-- settled sprite -- replaces the old `descentComplete()` (see
-- `Enemy.lua`'s removal note): since the interpreter's first
-- `#enemyDescent.path` ticks are the entrance motion (no separate
-- descent state anymore), this just checks elapsed frames since the
-- gate opened against that same tick count -- the boundary is grounded
-- in the decisive delta cross-check, not an arbitrary guess.
function BattleIntro:enemyInDescentPhase()
  if not self.enemyStarted then return false end
  local ed = self.profile.graphics.enemyDescent
  local elapsed = self.frame - self.data.gate.openFrame
  return elapsed <= #ed.path * EnemyMovementInterpreter.TICK_FRAMES
end

--- A plain, `love.*`-free snapshot -- for automated scripted
-- verification (`MYSTICQUEST_WAIT_FOR`, see main.lua's own doc
-- comment), added 2026-08-12 alongside the real boss walk-in.
function BattleIntro:debugState()
  return {
    frame = self.frame,
    enemyX = self.enemy and self.enemy.x,
    enemyY = self.enemy and self.enemy.y,
    enemyInDescentPhase = self.enemy and self:enemyInDescentPhase(),
    playerFacing = self.player and self.player.facing,
  }
end

function BattleIntro:advanceToField()
  if self.done then return end
  self.done = true
  local Field = require("src.app.states.Field")
  -- Real seamless patrol handoff (see Field.new's own `enemyState` doc
  -- comment) -- only when this cutscene actually built a real enemy
  -- (i.e. a real ROM/profile was loaded).
  local enemyState = self.enemy and {
    x = self.enemy.x, y = self.enemy.y, movementIndex = self.enemy.movementIndex,
    -- Real, continuously-advanced interpreter (see this state's own
    -- construction site above) -- `Field.lua` reuses this SAME
    -- instance rather than building a fresh one, so the real per-tick
    -- AI state carries over seamlessly instead of restarting.
    movementInterpreter = self.enemy.movementInterpreter,
  }
  self.stack:replace(Field.new(self.romData, self.profile, self.input, self.overlay, self.stack,
    self.heroName, nil, enemyState))
end

function BattleIntro:draw()
  if not self.background then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("(no ROM loaded -- battle intro unavailable)", 4, 4)
    return
  end

  self.background:draw(0, 0)

  for _, patch in ipairs(self.tilePatches) do
    if patch:isOpen(self.frame) then
      patch:draw()
    end
  end

  local hidden, walkEnd, settleEnd, typingStart, typingEnd, boxEnd = self:phaseBounds()

  if self.frame > hidden and self.playerSprite then
    -- REVERTED (2026-08-15, same day, see Field.lua's own matching
    -- revert note): this walk-in leads straight into `startRoom`'s own
    -- courtyard fight, calibrated the same OLD (unshifted) way -- the
    -- real OAM-vs-WRAM offset is real, but not safe to apply here.
    self.playerSprite:draw(self.player.x, self.player.y, false)
  end

  -- Real boss walk-in (see rom_profiles.lua's `enemyDescent` doc
  -- comment) -- descent uses its own real, separate tile block; once
  -- handed off to the normal patrol, the SAME real X-flip toggle
  -- Field.lua's own gameplay uses applies here too (`Enemy:isFlipped`,
  -- CORRECTED same day: was wired into `flipY`, a real bits-5/6 mixup).
  if self.enemyStarted then
    if self:enemyInDescentPhase() then
      if self.enemyDescentSprite then
        self.enemyDescentSprite:draw(self.enemy.x, self.enemy.y)
      end
    elseif self.enemySprite then
      self.enemySprite:draw(self.enemy.x, self.enemy.y, self.enemy:isFlipped())
    end
  end

  if self.frame > settleEnd and self.frame <= boxEnd and self.box then
    self.box:drawBorder(0, 0, 20, 8)
    local shown = 0
    if self.frame > typingStart then
      shown = math.min(#self.text, math.ceil((math.min(self.frame, typingEnd) - typingStart) / self.data.textbox.framesPerLetter))
    end
    if shown > 0 then
      self.box:drawText(self.text:sub(1, shown), 0, 0, 8)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, PLAY_H, ROOM_W, ROOM_H - PLAY_H)
  local hudText = string.format("LP %d MP %d G %d", self.stats.curLP, self.stats.curMP, self.stats.gold)
  if self.font then
    self.font:print(hudText, 2, PLAY_H + 4, { 0, 0, 0, 1 })
  end
  if self.hudBar then
    self.hudBar:draw()
  end
  love.graphics.setColor(1, 1, 1, 1)

  if self.overlay then
    self.overlay:addLine("state", "BattleIntro")
    self.overlay:addLine("frame", tostring(self.frame))
    self.overlay:addLine("dev keys", "SELECT skip")
  end
end

return BattleIntro
