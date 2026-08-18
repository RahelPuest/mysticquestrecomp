-- Player inventory/equipment data model, backed by the already-decoded
-- ItemTable/WeaponTable catalogs (src/import/ItemTable.lua,
-- src/import/WeaponTable.lua) -- wiring that data into Menu/inventory.
-- Those two modules only decode the ROM's static *catalog* (every
-- item/spell/weapon that exists in the game, by name); this module is
-- the missing piece between that catalog and a *specific character's*
-- actual held items/equipped weapon -- Menu.lua previously called
-- WeaponTable.decode itself just to find one name, with nowhere for a
-- granted item to go once milestone-7 event data exists (item grants,
-- shop purchases, etc.).
--
-- Also wires `WeaponStatTable` (power/price data found via external-
-- reference byte matching, see that module's doc comment) as
-- `weaponStatCatalog` -- kept as its own, separate catalog rather than
-- merged per-weapon into `weaponCatalog`, since the two tables' row
-- order correspondence isn't confirmed yet.
--
-- VERIFIED (rom-map.md "The in-game menu system"): a fresh character's
-- Dinge/Magie (items/spells) lists are empty, and Waffe shows exactly
-- one already-equipped weapon ("Breit") -- live-tested directly, not
-- assumed. So `Inventory.new` starts with correctly-empty items/spells
-- lists (matching that VERIFIED state, not a placeholder) and one
-- equipped weapon, looked up from the decoded catalog by the one
-- live-cross-checked anchor this project has (the name "Breit") -- see
-- WeaponTable.lua's doc comment for why that anchor, not a decoded WRAM
-- equipment-slot field, is still how the starting weapon is found (no
-- equip-slot WRAM address is verified yet).
--
-- What's real vs. not: the catalogs (`self.items`/`self.weapons`, and
-- the items/spells split via ItemTable's VERIFIED
-- `categoryBoundaryRecord`) are the decoded ROM data. A specific
-- character's held-items list, equip state, and mutation (add/remove/
-- equip) are this module's own data model -- real code, but with no ROM
-- struct backing it yet (no WRAM inventory-slot layout has been traced
-- -- see rom-map.md). Exists so that layer has one place to live once
-- that WRAM struct (or milestone-7 event data) is found, instead of
-- each caller (Menu.lua, a future shop/event system) inventing its own
-- ad hoc state.
--
-- Pure Lua, no love.* calls, so it's headlessly testable like Stats.lua.

local ItemTable = require("src.import.ItemTable")
local WeaponTable = require("src.import.WeaponTable")
local WeaponStatTable = require("src.import.WeaponStatTable")

local Inventory = {}
Inventory.__index = Inventory

-- Live-cross-checked anchor (see module doc comment): the one weapon
-- name this project independently confirmed against the real in-game
-- HUD readout. Used to find the real starting-weapon record in the
-- decoded catalog, not hardcoded as the displayed name itself.
Inventory.STARTING_WEAPON_NAME = "Breit"

local function findByName(records, name)
  for _, record in ipairs(records) do
    if record.name == name then
      return record
    end
  end
  return nil
end

--- Decodes the real ItemTable/WeaponTable catalogs (if `romData`/
-- `profile` are given) and builds a fresh character's real, correctly-
-- empty inventory over them. Safe to call with neither (e.g. a headless
-- unit test, or no ROM loaded yet) -- catalogs are then empty arrays and
-- `equippedWeapon()` returns nil, never a fake weapon.
function Inventory.new(romData, profile)
  local self = setmetatable({
    items = {}, -- held consumable items, real-empty for a fresh character
    spells = {}, -- known spells, real-empty for a fresh character
    itemCatalog = {}, -- every real ItemTable record whose categoryByte marks it a consumable
    spellCatalog = {}, -- every real ItemTable record whose categoryByte marks it a spell
    weaponCatalog = {}, -- every real WeaponTable record (the full in-ROM catalog, not what the player owns)
    weaponStatCatalog = {}, -- every real WeaponStatTable record (power/price, see below) -- a SEPARATE catalog, not merged into weaponCatalog
    heldWeapons = {}, -- the weapons this character actually HAS -- starts with just the real starting weapon
    equippedWeaponIndex = nil,
  }, Inventory)

  if romData and profile then
    if profile.itemTable then
      local records = ItemTable.decode(romData, profile.itemTable)
      local boundary = profile.itemTable.categoryBoundaryRecord
      for _, record in ipairs(records) do
        -- VERIFIED split (ItemTable.lua doc comment): records before the
        -- boundary are consumable items, from the boundary on are spells.
        if boundary and record.index >= boundary then
          self.spellCatalog[#self.spellCatalog + 1] = record
        else
          self.itemCatalog[#self.itemCatalog + 1] = record
        end
      end
    end

    if profile.weaponTable then
      self.weaponCatalog = WeaponTable.decode(romData, profile.weaponTable)
      local starting = findByName(self.weaponCatalog, Inventory.STARTING_WEAPON_NAME)
      if starting then
        self.equippedWeaponIndex = starting.index
        self.heldWeapons[1] = starting
      end
    end

    -- Not merged into `weaponCatalog`/`heldWeapons` records: the two
    -- tables' row orders are not confirmed to correspond 1-for-1 (see
    -- WeaponStatTable.lua's doc comment -- e.g. `weaponCatalog`'s
    -- German "Streit" sitting right where a naive shared-order guess
    -- would expect "Were Axe" doesn't obviously fit that name, an open
    -- discrepancy, not silently papered over). Exposed as its own
    -- honestly-separate catalog instead of guessing a per-weapon merge
    -- that could misattribute power/price to the wrong named weapon.
    if profile.weaponStatTable then
      self.weaponStatCatalog = WeaponStatTable.decode(romData, profile.weaponStatTable)
    end
  end

  return self
end

--- The real decoded weapon record currently equipped, or nil if none
-- (no ROM/profile was given, or the starting-weapon anchor wasn't found
-- in the decoded catalog -- never a fake/placeholder record).
function Inventory:equippedWeapon()
  if not self.equippedWeaponIndex then return nil end
  for _, record in ipairs(self.weaponCatalog) do
    if record.index == self.equippedWeaponIndex then
      return record
    end
  end
  return nil
end

--- Equip the weapon named `name` -- must already be held (see
-- `addWeapon`), matching "you can only wield what you own" game logic
-- (changed from the earlier "any catalog weapon" semantics, which let
-- a caller equip a weapon the character never actually acquired).
-- Returns true on success, false (no silent fallback/partial state) if
-- `name` isn't currently held.
function Inventory:equip(name)
  local record = findByName(self.heldWeapons, name)
  if not record then return false end
  self.equippedWeaponIndex = record.index
  return true
end

--- Grant weapon `name` from the catalog into `heldWeapons`. Returns
-- true on success, false if `name` isn't a catalog entry or is already
-- held (no duplicate held-weapon entries). Same "real content only,
-- fail loudly on an unknown name" discipline as `addItem` below --
-- this is general inventory-management code; the ROM's item-granting
-- trigger (a shop, a found chest) is honestly still unknown (see
-- combat.md's "equip-swap test attempted, blocked" entry) -- callers
-- decide when to grant (see `Field.lua`'s F12 dev-only shortcut), this
-- method only decides whether a grant is valid against the decoded
-- catalog.
function Inventory:addWeapon(name)
  if findByName(self.heldWeapons, name) then return false end
  local record = findByName(self.weaponCatalog, name)
  if not record then return false end
  self.heldWeapons[#self.heldWeapons + 1] = record
  return true
end

--- Add item `name` (an ItemTable catalog entry, consumable or spell)
-- to the held/known list. Returns true on success, false if `name`
-- isn't in either catalog. Checks the item catalog first --
-- the two catalogs are index-range-partitioned by `categoryBoundaryRecord`
-- so a name collision across them isn't expected, but resolving from a
-- single lookup (rather than two independent ones) avoids a real class
-- of bug if one ever occurred: picking a match from one catalog while
-- filing it under the other's list.
function Inventory:addItem(name)
  local record = findByName(self.itemCatalog, name)
  local list = self.items
  if not record then
    record = findByName(self.spellCatalog, name)
    list = self.spells
  end
  if not record then return false end
  list[#list + 1] = record
  return true
end

--- Whether `name` is currently held/known (an item or a spell).
function Inventory:has(name)
  return findByName(self.items, name) ~= nil or findByName(self.spells, name) ~= nil
end

--- Consume one held instance of consumable item `name`, removing it
-- from `self.items`. Returns true on success, false if not currently
-- held. HONEST SCOPE: this is general inventory-management code (using
-- an item really does remove it), but applies no numeric effect --
-- `ItemTable.lua`'s doc comment already states bytes 9-14 (the likely
-- heal-amount/effect fields) are not decoded, so this project has no
-- ROM-derived formula to apply without fabricating one. Deliberately
-- does not operate on `self.spells` -- spells are known, not consumed
-- on cast (matching this genre's MP-cost convention, not an item-stock
-- convention); no MP-cost formula is wired either, so casting isn't
-- modeled here at all yet.
function Inventory:useItem(name)
  for i, record in ipairs(self.items) do
    if record.name == name then
      table.remove(self.items, i)
      return true
    end
  end
  return false
end

return Inventory
