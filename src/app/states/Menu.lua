-- The real in-game menu -- VERIFIED live this project (see
-- docs/reverse-engineering/rom-map.md "The in-game menu system"):
-- pressing START during field control opens a real menu with four
-- options, `Dinge`/`Magie`/`Waffe`/`Frage` (Items/Magic/Weapon/Ask), and
-- a status readout next to it. The `Waffe` line is shown alongside the
-- player's actual equipped weapon name -- this project found that name
-- ("Breit") live in the ROM by cross-checking this exact HUD readout
-- against `src/import/WeaponTable.lua`'s decoded table (see rom-map.md).
--
-- FIXED (2026-08-09): the equipped-weapon name used to be a second,
-- independently-hardcoded Lua string ("Breit") sitting next to the real
-- decoder that already knows how to read it -- a real deviation from
-- this project's own master brief ("data should come from normalized
-- imported tables wherever possible"), and the same class of bug this
-- session already found and fixed once for sprite sizes (a value that
-- *happens* to match the ROM today but isn't structurally tied to it).
--
-- REWORKED (2026-08-09, task P5): Menu.lua used to call
-- `WeaponTable.decode` itself just to find that one name, with nowhere
-- real for a granted item/spell to go once milestone-7 event data
-- exists. Now uses `src.entities.Inventory` -- a real data model over
-- the decoded ItemTable/WeaponTable catalogs, shared with (and
-- constructed once by) Field.lua, not re-decoded here -- see
-- Inventory.lua's own doc comment for what it does and doesn't solve
-- yet. What's still NOT solved: *which* WRAM field names the currently-
-- equipped weapon (no equipment-slot address is verified yet -- rom-
-- map.md), so the "Breit" anchor Inventory.lua uses remains the known
-- anchor rather than a generally-read-from-save-state fact.
--
-- What IS real here: the four option strings, their order, the "Gut"
-- status word, and the equipped-weapon name -- all live-verified this
-- session. What's NOT verified: the exact on-screen pixel layout/box
-- style (this project only has a low-res reference screenshot, not
-- decoded VRAM tilemap coordinates for this specific screen) -- the
-- box position/size below is a reasonable approximation, not a
-- rom-map.md VERIFIED fact, and says so.
--
-- Selecting `Dinge`/`Magie`/`Waffe` opens nothing (VERIFIED: empty for
-- a fresh character in this project's own live testing -- see rom-
-- map.md) -- deliberately NOT wired to show the full ItemTable/
-- WeaponTable catalogs, which would misrepresent "every item this game
-- has" as "your inventory": `self.inventory.items`/`.spells` are the
-- real, correctly-EMPTY per-character lists (Inventory.lua), not the
-- catalogs themselves. Selecting `Frage` closes the menu immediately
-- (VERIFIED: this project found it does nothing without a follower/NPC
-- present). B or SELECT closes the menu, matching the same finding.

local Font = require("src.rendering.Font")
local Inventory = require("src.entities.Inventory")

local Menu = { opaque = false } -- drawn over Field, not replacing it
Menu.__index = Menu

Menu.OPTIONS = { "Dinge", "Magie", "Waffe", "Frage" }
Menu.STATUS_WORD = "Gut"

--- `inventory`: an optional already-constructed Inventory (Field.lua's
-- own, so equip/item state persists across opening/closing the menu) --
-- built fresh here only when a caller doesn't have one yet (e.g. a
-- standalone test/screenshot harness).
function Menu.new(romData, profile, input, stack, inventory)
  local self = setmetatable({
    input = input,
    stack = stack,
    cursor = 1,
    inventory = inventory or Inventory.new(romData, profile),
  }, Menu)
  if romData and profile then
    self.font = Font.new(romData, profile)
  end
  return self
end

function Menu:update(dt)
  if self.input:pressed("select") or self.input:pressed("b") then
    self.stack:pop()
    return
  end
  if self.input:pressed("down") then
    self.cursor = self.cursor % #Menu.OPTIONS + 1
  elseif self.input:pressed("up") then
    self.cursor = (self.cursor - 2) % #Menu.OPTIONS + 1
  elseif self.input:pressed("a") then
    -- VERIFIED (module doc comment): every option is a no-op for a
    -- fresh character with no items/spells/follower -- close either
    -- way, matching this project's own live-tested behavior exactly
    -- rather than opening a placeholder submenu that doesn't exist.
    self.stack:pop()
  end
end

local BOX_X, BOX_Y = 8, 8
local BOX_W, BOX_H = 72, 40
local LINE_H = 8

function Menu:draw()
  -- Dim the field state beneath so the menu reads as focused, without
  -- hiding it entirely (matching the real game drawing its menu box
  -- over a still-visible field).
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", BOX_X, BOX_Y, BOX_W, BOX_H)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", BOX_X, BOX_Y, BOX_W, BOX_H)

  -- Status box, to the right of the option list.
  local statusX = BOX_X + BOX_W + 8
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", statusX, BOX_Y, 40, 16)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", statusX, BOX_Y, 40, 16)

  if self.font then
    for i, option in ipairs(Menu.OPTIONS) do
      local y = BOX_Y + 4 + (i - 1) * LINE_H
      local prefix = (i == self.cursor) and ">" or " "
      self.font:print(prefix .. option, BOX_X + 4, y, { 0, 0, 0, 1 })
    end
    self.font:print(Menu.STATUS_WORD, statusX + 3, BOX_Y + 4, { 0, 0, 0, 1 })
    local weapon = self.inventory:equippedWeapon()
    if weapon then
      self.font:print(weapon.name, BOX_X + 4, BOX_Y + BOX_H + 6, { 1, 1, 1, 1 })
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Menu
