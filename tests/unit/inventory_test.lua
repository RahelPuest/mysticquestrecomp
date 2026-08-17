local Harness = require("tests.harness")
local Inventory = require("src.entities.Inventory")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("Inventory.new: with no ROM/profile, starts real-empty and has no equipped weapon", function()
  local inv = Inventory.new(nil, nil)
  Harness.assertEqual(#inv.items, 0)
  Harness.assertEqual(#inv.spells, 0)
  Harness.assertEqual(#inv.itemCatalog, 0)
  Harness.assertEqual(#inv.weaponCatalog, 0)
  Harness.assertEqual(#inv.weaponStatCatalog, 0)
  Harness.assertEqual(#inv.heldWeapons, 0)
  Harness.assertEqual(inv:equippedWeapon(), nil)
end)

Harness.test("Inventory:equip/addItem/addWeapon/has: fail loudly (return false) against an empty catalog, never fake success", function()
  local inv = Inventory.new(nil, nil)
  Harness.assertTrue(not inv:equip("Breit"))
  Harness.assertTrue(not inv:addItem("Portion"))
  Harness.assertTrue(not inv:addWeapon("Breit"))
  Harness.assertTrue(not inv:useItem("Portion"))
  Harness.assertTrue(not inv:has("Portion"))
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()
local profile
if romData then
  local report = RomIdentity.identify(romData)
  profile = RomProfiles.match(report)
end

Harness.testIfAvailable(
  "Inventory.new: fresh character is real-empty (items/spells) with the real 'Breit' weapon equipped",
  romData ~= nil,
  "no development ROM found",
  function()
    local inv = Inventory.new(romData, profile)

    -- VERIFIED fresh-character state (rom-map.md "The in-game menu
    -- system") -- Dinge/Magie are empty, Waffe shows exactly one
    -- already-equipped, already-HELD weapon (2026-08-16: heldWeapons
    -- is seeded with the real starting weapon, not left empty).
    Harness.assertEqual(#inv.heldWeapons, 1)
    Harness.assertEqual(inv.heldWeapons[1].name, "Breit")
    Harness.assertEqual(#inv.items, 0)
    Harness.assertEqual(#inv.spells, 0)

    local weapon = inv:equippedWeapon()
    Harness.assertTrue(weapon ~= nil, "a fresh character should have a real equipped weapon")
    Harness.assertEqual(weapon.name, "Breit")

    -- Real WeaponStatTable catalog (2026-08-17, see that module's own
    -- doc comment) -- 16 real weapons, own separate catalog from
    -- weaponCatalog above (not merged, real row-order correspondence
    -- between the two tables not yet confirmed).
    Harness.assertEqual(#inv.weaponStatCatalog, 16)
    Harness.assertEqual(inv.weaponStatCatalog[1].power, 4) -- Broad Sword, real external-reference-confirmed value
    Harness.assertEqual(inv.weaponStatCatalog[1].price, 60)
  end
)

Harness.testIfAvailable(
  "Inventory.new: real ItemTable catalog splits into items/spells at the VERIFIED categoryBoundaryRecord",
  romData ~= nil,
  "no development ROM found",
  function()
    local inv = Inventory.new(romData, profile)
    local boundary = profile.itemTable.categoryBoundaryRecord

    Harness.assertEqual(#inv.itemCatalog, boundary)
    Harness.assertEqual(#inv.spellCatalog, profile.itemTable.recordCount - boundary)

    -- Every catalog entry's own index should land on the correct side
    -- of the boundary -- catches an off-by-one in the split, not just
    -- the totals.
    for _, record in ipairs(inv.itemCatalog) do
      Harness.assertTrue(record.index < boundary, "itemCatalog entry should be before the boundary")
    end
    for _, record in ipairs(inv.spellCatalog) do
      Harness.assertTrue(record.index >= boundary, "spellCatalog entry should be at/after the boundary")
    end
  end
)

Harness.testIfAvailable(
  "Inventory:equip/addItem/has: real catalog lookups round-trip by name",
  romData ~= nil,
  "no development ROM found",
  function()
    local inv = Inventory.new(romData, profile)

    -- Equipping a real catalog weapon the character doesn't OWN yet
    -- must fail (2026-08-16: equip() now requires it be held first).
    Harness.assertTrue(not inv:equip("Axt"))
    Harness.assertEqual(inv:equippedWeapon().name, "Breit")

    -- Grant it, then equip it -- a different real weapon than the starting one.
    Harness.assertTrue(inv:addWeapon("Axt"))
    Harness.assertTrue(inv:equip("Axt"))
    Harness.assertEqual(inv:equippedWeapon().name, "Axt")

    -- Unknown name: no silent fallback, no partial state change.
    Harness.assertTrue(not inv:equip("Not A Real Weapon"))
    Harness.assertEqual(inv:equippedWeapon().name, "Axt")

    -- Grant a real item from the catalog.
    local firstItemName = inv.itemCatalog[1].name
    Harness.assertTrue(not inv:has(firstItemName))
    Harness.assertTrue(inv:addItem(firstItemName))
    Harness.assertTrue(inv:has(firstItemName))
    Harness.assertEqual(#inv.items, 1)
    Harness.assertEqual(#inv.spells, 0)

    -- Grant a real spell from the catalog -- files under spells, not items.
    -- NOTE (2026-08-15, item/spell table extended -- see ItemTable.lua's
    -- own doc comment): `spellCatalog[1].name` is now the real, live-
    -- decoded "Lebe" -- which genuinely, honestly COLLIDES with
    -- `itemCatalog[1].name` (also "Lebe", a different real ROM record
    -- that happens to decode to the same shortened name). `addItem`
    -- checks `itemCatalog` first (see its own doc comment), so granting
    -- that exact name would resolve against the ALREADY-held item, not
    -- a distinct spell -- a real, honest ambiguity in the ROM's own
    -- data, not a bug in this test or in `addItem`. Uses
    -- `spellCatalog[2]` ("S-Lebe") instead, a real spell name with no
    -- such collision, to keep testing what this test actually intends
    -- (a DISTINCT item + spell round-trip).
    local firstSpellName = inv.spellCatalog[2].name
    Harness.assertTrue(inv:addItem(firstSpellName))
    Harness.assertTrue(inv:has(firstSpellName))
    Harness.assertEqual(#inv.items, 1)
    Harness.assertEqual(#inv.spells, 1)
  end
)

Harness.testIfAvailable(
  "Inventory:addWeapon: real catalog weapons can be granted, no duplicates, unknown names fail loudly",
  romData ~= nil,
  "no development ROM found",
  function()
    local inv = Inventory.new(romData, profile)
    Harness.assertEqual(#inv.heldWeapons, 1) -- just the starting weapon

    Harness.assertTrue(inv:addWeapon("Axt"))
    Harness.assertEqual(#inv.heldWeapons, 2)

    -- Granting the SAME weapon again is a no-op failure, not a duplicate entry.
    Harness.assertTrue(not inv:addWeapon("Axt"))
    Harness.assertEqual(#inv.heldWeapons, 2)

    -- Unknown name: no silent fallback.
    Harness.assertTrue(not inv:addWeapon("Not A Real Weapon"))
    Harness.assertEqual(#inv.heldWeapons, 2)
  end
)

Harness.testIfAvailable(
  "Inventory:useItem: consumes a held item (removes it), never touches spells, fails loudly if not held",
  romData ~= nil,
  "no development ROM found",
  function()
    local inv = Inventory.new(romData, profile)
    local itemName = inv.itemCatalog[1].name
    local spellName = inv.spellCatalog[2].name -- see the collision note above -- avoids itemCatalog[1]'s own name clash

    Harness.assertTrue(not inv:useItem(itemName), "not held yet")

    Harness.assertTrue(inv:addItem(itemName))
    Harness.assertTrue(inv:addItem(spellName))
    Harness.assertEqual(#inv.items, 1)
    Harness.assertEqual(#inv.spells, 1)

    Harness.assertTrue(inv:useItem(itemName))
    Harness.assertEqual(#inv.items, 0) -- consumed
    Harness.assertEqual(#inv.spells, 1) -- untouched -- spells are known, not consumed

    -- Using it again (already consumed) fails loudly, no silent no-op success.
    Harness.assertTrue(not inv:useItem(itemName))

    -- useItem never operates on spells, even if the name happens to match.
    Harness.assertTrue(not inv:useItem(spellName))
    Harness.assertEqual(#inv.spells, 1)
  end
)

if romData then
  print("(Inventory ROM-dependent tests ran against a real dev ROM)")
end
