-- The real hero/heroine name-entry screens, reached right after the
-- intro scroll finishes -- direct implementation of a detailed user-
-- supplied reference description, verified live under mGBA at every
-- step (see rom_profiles.lua's `nameEntry` entry for the full capture:
-- real window chrome, real on-screen keyboard grid, real cursor sprite
-- reused from the title screen, real name-accumulation display, real
-- START-confirm gating).
--
-- Real, VERIFIED mechanics this state reproduces:
-- * A on a grid cell appends that glyph to the current name (max 4
--   characters -- confirmed live: a 5th/6th selection is a silent
--   no-op, not an overflow or a replace).
-- * The typed name is displayed live, appended after the box's own
--   label ("Held"/"Frau") with a real 2-tile blank gap.
-- * START confirms and advances ONLY once at least one character has
--   been entered (confirmed: pressing START on an empty name does
--   nothing).
-- * Hero confirmed -> heroine screen (box label switches "Held"->
--   "Frau", cursor resets to the grid's first cell) -> confirmed ->
--   this state hands off to BattleIntro.lua (the real first-battle
--   intro sequence, 2026-08-09).
--
-- HONEST LIMIT: B/backspace-to-delete-a-character was not tested this
-- pass (not implemented here either -- no real behavior to match yet).
-- The grid's real column count varies per row (8 or 9 -- see
-- rom_profiles.lua) -- cursor column is clamped when moving into a
-- shorter row, a reasonable engineering choice, not itself a confirmed
-- real behavior (untested).

local TileImage = require("src.rendering.TileImage")
local CreatureSprite = require("src.rendering.CreatureSprite")
local TextDecoder = require("src.import.TextDecoder")
local GBTile = require("src.rendering.GBTile")

local NameEntry = { opaque = true }
NameEntry.__index = NameEntry

local COLS = 16 -- sheet layout, matches the font's own 16-per-row convention
local VISIBLE_ROWS = 6 -- real: all of A-Z/a-z fits without scrolling
local CELL_W, CELL_H = 16, 16 -- real px spacing between grid cells
local GRID_TOP_Y = 48 -- real px, window row 6
local GRID_LEFT_X = 16 -- real px, first letter's column (tilemap col 2)
local CURSOR_OFFSET_X = -16 -- real: cursor sits 2 tiles left of the selected letter
local MAX_NAME_LENGTH = 4

-- Same white-ink-then-tint approach as Font.lua/HudBar.lua (see their
-- own doc comments for why: this project already hit, and documented,
-- the "dark palette index invisible against a black clear" failure
-- once and standardized on this pattern to avoid repeating it).
local INK_PALETTE = {
  { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 },
}

function NameEntry.new(romData, profile, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    stage = "hero", -- "hero" -> "heroine" -> done
    heroTiles = {},
    heroineTiles = {},
    cursorRow = 1,
    cursorCol = 1,
  }, NameEntry)

  if romData and profile then
    local data = profile.graphics.nameEntry
    assert(data, "NameEntry.new expects profile.graphics.nameEntry")
    self.data = data

    local sheet, sheetW, sheetH = TileImage.sheetFromBytes(
      romData, data.tileset.fileOffset, data.tileset.count, COLS, INK_PALETTE, true)
    self.sheet = sheet
    self.quads = {}
    for i = 0, data.tileset.count - 1 do
      local tileId = data.tileset.tileBase + i
      local tx = (i % COLS) * GBTile.TILE_W
      local ty = math.floor(i / COLS) * GBTile.TILE_H
      self.quads[tileId] = love.graphics.newQuad(tx, ty, GBTile.TILE_W, GBTile.TILE_H, sheetW, sheetH)
    end

    if profile.graphics.spritePalette then
      CreatureSprite.setDefaultPalette(
        TileImage.paletteFromShadeIndices(profile.graphics.spritePalette.shadeIndices))
    end
    local cs = profile.graphics.titleScreen and profile.graphics.titleScreen.cursorSprite
    if cs then
      self.cursorSprite = CreatureSprite.fromOffsets(romData, cs.tileOffsets, cs.cols, cs.rows)
    end
  end

  return self
end

function NameEntry:currentTiles()
  return self.stage == "hero" and self.heroTiles or self.heroineTiles
end

function NameEntry:currentLabel()
  return self.stage == "hero" and self.data.labels.hero or self.data.labels.heroine
end

function NameEntry:drawTile(tileId, x, y)
  local quad = self.quads[tileId]
  if not quad then return end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.draw(self.sheet, quad, x, y)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw a real bordered box (see rom_profiles.lua's `nameEntry.border`)
-- `cols`/`rows` wide/tall in tiles, top-left at (x, y).
function NameEntry:drawBox(x, y, cols, rows)
  local b = self.data.border
  self:drawTile(b.topLeft, x, y)
  self:drawTile(b.bottomLeft, x, y + (rows - 1) * 8)
  for c = 1, cols - 2 do
    self:drawTile(b.top, x + c * 8, y)
    self:drawTile(b.bottom, x + c * 8, y + (rows - 1) * 8)
  end
  self:drawTile(b.topRight, x + (cols - 1) * 8, y)
  self:drawTile(b.bottomRight, x + (cols - 1) * 8, y + (rows - 1) * 8)
  for r = 1, rows - 2 do
    self:drawTile(b.left, x, y + r * 8)
    self:drawTile(b.right, x + (cols - 1) * 8, y + r * 8)
  end
end

function NameEntry:update(dt)
  if not self.input or not self.data then return end
  local grid = self.data.grid

  if self.input:pressed("right") then
    self.cursorCol = math.min(self.cursorCol + 1, #grid[self.cursorRow])
  elseif self.input:pressed("left") then
    self.cursorCol = math.max(self.cursorCol - 1, 1)
  elseif self.input:pressed("down") then
    self.cursorRow = math.min(self.cursorRow + 1, #grid)
    self.cursorCol = math.min(self.cursorCol, #grid[self.cursorRow])
  elseif self.input:pressed("up") then
    self.cursorRow = math.max(self.cursorRow - 1, 1)
    self.cursorCol = math.min(self.cursorCol, #grid[self.cursorRow])
  end

  if self.input:pressed("a") then
    local tiles = self:currentTiles()
    if #tiles < MAX_NAME_LENGTH then
      tiles[#tiles + 1] = grid[self.cursorRow][self.cursorCol]
    end
  end

  if self.input:pressed("start") then
    local tiles = self:currentTiles()
    if #tiles > 0 then
      if self.stage == "hero" then
        self.stage = "heroine"
        self.cursorRow, self.cursorCol = 1, 1
      else
        self:finish()
      end
    end
  end
end

function NameEntry:finish()
  if self.done then return end
  self.done = true
  -- Real dialogue-byte encoding (see rom_profiles.lua's `nameEntry` doc
  -- comment: WRAM name buffer bytes are `0xB0 + glyphIndex`, the same
  -- formula TextDecoder already implements) -- decoded back into a
  -- display string via the same decoder the rest of this project uses,
  -- not a separately-hardcoded name-formatting rule.
  local function decode(tiles)
    local bytes = {}
    for _, t in ipairs(tiles) do bytes[#bytes + 1] = string.char(t + 0x80) end
    return TextDecoder.decodeString(table.concat(bytes), 0)
  end
  self.heroName = decode(self.heroTiles)
  self.heroineName = decode(self.heroineTiles)

  -- Real flow (2026-08-09): heroine confirm -> the real first-battle
  -- intro (walk-in + "Kaempfe!" textbox + enemy appears), not straight
  -- to Field -- see BattleIntro.lua.
  local BattleIntro = require("src.app.states.BattleIntro")
  self.stack:replace(BattleIntro.new(self.romData, self.profile, self.input, self.overlay, self.stack,
    self.heroName))
end

function NameEntry:draw()
  if not self.data then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("(no ROM loaded -- name entry unavailable)", 4, 4)
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  -- Label box: 14 tiles wide, 4 tall (real, see rom_profiles.lua's capture).
  self:drawBox(0, 0, 14, 4)
  local label = self:currentLabel()
  for i = 1, #label do
    -- The label itself is plain font glyphs -- reuse the same sheet via
    -- the main-glyph tile IDs (tileBase + MAIN_BASE-relative index).
    local ch = label:sub(i, i)
    local idx = TextDecoder.MAIN_GLYPHS:find(ch, 1, true)
    if idx then
      self:drawTile(0x30 + idx - 1, 16 + (i - 1) * 8, 16)
    end
  end
  local tiles = self:currentTiles()
  for i, tileId in ipairs(tiles) do
    self:drawTile(tileId, 64 + (i - 1) * 8, 16)
  end

  -- Grid box: full 20-tile width, real interior height for VISIBLE_ROWS.
  self:drawBox(0, 32, 20, VISIBLE_ROWS * 2 + 2)
  local grid = self.data.grid
  local scrollRow = math.max(0, math.min(self.cursorRow - 1, #grid - VISIBLE_ROWS))
  for r = scrollRow + 1, math.min(scrollRow + VISIBLE_ROWS, #grid) do
    local y = GRID_TOP_Y + (r - 1 - scrollRow) * CELL_H
    for c, tileId in ipairs(grid[r]) do
      self:drawTile(tileId, GRID_LEFT_X + (c - 1) * CELL_W, y)
    end
  end

  if self.cursorSprite then
    local cy = GRID_TOP_Y + (self.cursorRow - 1 - scrollRow) * CELL_H
    local cx = GRID_LEFT_X + (self.cursorCol - 1) * CELL_W + CURSOR_OFFSET_X
    if self.cursorRow - 1 >= scrollRow and self.cursorRow - 1 < scrollRow + VISIBLE_ROWS then
      self.cursorSprite:draw(cx, cy)
    end
  end

  if self.overlay then
    self.overlay:addLine("state", "NameEntry (" .. self.stage .. ")")
    local bytes = {}
    for _, t in ipairs(tiles) do bytes[#bytes + 1] = string.char(t + 0x80) end
    self.overlay:addLine("name so far", TextDecoder.decodeString(table.concat(bytes), 0))
    self.overlay:addLine("cursor", string.format("row=%d col=%d", self.cursorRow, self.cursorCol))
    self.overlay:addLine("dev keys", "arrows move, A select, START confirm")
  end
end

return NameEntry
