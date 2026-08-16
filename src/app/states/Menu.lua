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
-- REWORKED AGAIN (2026-08-16, task "Item/Ausrüstung nutzbar machen",
-- direct user selection): `Dinge`/`Waffe` now actually DO something
-- when the (real, VERIFIED-empty-by-default) inventory isn't empty --
-- previously every option was an unconditional no-op close, matching
-- ONLY the fresh-character state. That VERIFIED behavior is still
-- exactly reproduced whenever the lists really are empty (no ROM
-- trigger for granting items has ever been found -- see combat.md's
-- own "Real equip-swap test attempted, blocked" entry -- so a fresh
-- game still behaves identically to before); Field.lua's own F12
-- dev-only shortcut is what makes these lists non-empty for testing.
-- `Dinge`: selecting a held item consumes it (`Inventory:useItem`) --
-- HONEST SCOPE: no numeric effect is applied (no real heal-amount
-- formula is decoded, see `Inventory.lua`'s own `useItem` doc
-- comment) -- this is real inventory management, not a claimed combat
-- effect. `Waffe`: selecting a held weapon equips it
-- (`Inventory:equip`) -- whether this changes real combat damage is
-- honestly still open (see combat.md's own "MAJOR CORRECTION" and its
-- own follow-up entry). `Magie`/`Frage` are UNCHANGED (still close
-- immediately) -- no MP-cost/casting formula and no follower/NPC
-- system exist yet, so building interactivity there would be
-- fabricated, not real.

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
    -- "options" (the 4-line main menu) | "items" | "weapons" (a real
    -- sub-list, only entered when the corresponding real list is
    -- non-empty -- see this file's own top-of-file doc comment).
    mode = "options",
    subCursor = 1,
  }, Menu)
  if romData and profile then
    self.font = Font.new(romData, profile)
  end
  return self
end

--- The real list backing the current sub-mode, or nil in "options" mode.
function Menu:_currentSubList()
  if self.mode == "items" then return self.inventory.items end
  if self.mode == "weapons" then return self.inventory.heldWeapons end
  return nil
end

function Menu:update(dt)
  if self.mode ~= "options" then
    self:_updateSubMenu()
    return
  end

  if self.input:pressed("select") or self.input:pressed("b") then
    self.stack:pop()
    return
  end
  if self.input:pressed("down") then
    self.cursor = self.cursor % #Menu.OPTIONS + 1
  elseif self.input:pressed("up") then
    self.cursor = (self.cursor - 2) % #Menu.OPTIONS + 1
  elseif self.input:pressed("a") then
    local option = Menu.OPTIONS[self.cursor]
    if option == "Dinge" and #self.inventory.items > 0 then
      self.mode, self.subCursor = "items", 1
    elseif option == "Waffe" and #self.inventory.heldWeapons > 0 then
      self.mode = "weapons"
      -- Start the cursor on the currently-equipped weapon, if held --
      -- a real, small usability touch, not just always index 1.
      self.subCursor = 1
      for i, w in ipairs(self.inventory.heldWeapons) do
        if w.index == self.inventory.equippedWeaponIndex then
          self.subCursor = i
          break
        end
      end
    else
      -- VERIFIED (module doc comment): every option is a no-op for a
      -- fresh character with no items/spells/follower -- close either
      -- way, matching this project's own live-tested behavior exactly
      -- rather than opening a placeholder submenu that doesn't exist.
      self.stack:pop()
    end
  end
end

function Menu:_updateSubMenu()
  local list = self:_currentSubList()
  local n = list and #list or 0

  if self.input:pressed("select") or self.input:pressed("b") then
    self.mode = "options"
    return
  end
  if n == 0 then return end -- honest guard; shouldn't normally happen (only entered when non-empty)
  if self.input:pressed("down") then
    self.subCursor = self.subCursor % n + 1
  elseif self.input:pressed("up") then
    self.subCursor = (self.subCursor - 2) % n + 1
  elseif self.input:pressed("a") then
    local record = list[self.subCursor]
    if self.mode == "items" then
      self.inventory:useItem(record.name)
      -- The list just shrank (or emptied) -- keep the cursor in range,
      -- fall back to the main menu once nothing's left to show.
      local newN = #self.inventory.items
      if newN == 0 then
        self.mode = "options"
      elseif self.subCursor > newN then
        self.subCursor = newN
      end
    elseif self.mode == "weapons" then
      self.inventory:equip(record.name)
      self.mode = "options" -- equip is instant; no reason to linger in the sub-list
    end
  end
end

local BOX_X, BOX_Y = 8, 8
local BOX_W, BOX_H = 72, 40
local LINE_H = 8

function Menu:_drawOptions()
  for i, option in ipairs(Menu.OPTIONS) do
    local y = BOX_Y + 4 + (i - 1) * LINE_H
    local prefix = (i == self.cursor) and ">" or " "
    self.font:print(prefix .. option, BOX_X + 4, y, { 0, 0, 0, 1 })
  end
end

--- Shared draw for both real sub-lists (items/weapons) -- same box,
-- same cursor convention as the main options list, just a different
-- backing array and label. FIXED (2026-08-16, caught via an actual
-- `love .` screenshot, not guessed -- the same "no invisible/off-
-- screen text" discipline this project's other dev browsers already
-- learned the hard way): the label used to draw ABOVE the box
-- (`BOX_Y - LINE_H - 2`), which runs off the top of the native 144px
-- canvas given `BOX_Y=8` -- now a real header ROW inside the box,
-- with the list itself starting one row lower.
function Menu:_drawSubMenu(list, label)
  self.font:print(label, BOX_X + 4, BOX_Y + 3, { 0, 0, 0, 1 })
  for i, record in ipairs(list) do
    local y = BOX_Y + 4 + LINE_H + (i - 1) * LINE_H
    if y > BOX_Y + BOX_H - LINE_H then break end -- honest clip, no overflow past the box
    local prefix = (i == self.subCursor) and ">" or " "
    self.font:print(prefix .. record.name, BOX_X + 4, y, { 0, 0, 0, 1 })
  end
end

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
    if self.mode == "options" then
      self:_drawOptions()
    elseif self.mode == "items" then
      self:_drawSubMenu(self.inventory.items, "Dinge")
    elseif self.mode == "weapons" then
      self:_drawSubMenu(self.inventory.heldWeapons, "Waffe")
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
