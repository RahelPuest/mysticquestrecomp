local Harness = require("tests.harness")
local EntityStructLayout = require("src.import.EntityStructLayout")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("EntityStructLayout.address: real $C200 + slotIndex*16 + field arithmetic", function()
  Harness.assertEqual(EntityStructLayout.address(0, EntityStructLayout.FIELD.ALIVE), 0xC200)
  Harness.assertEqual(EntityStructLayout.address(4, EntityStructLayout.FIELD.POSITION_Y), 0xC244)
  Harness.assertEqual(EntityStructLayout.address(4, EntityStructLayout.FIELD.POSITION_X), 0xC245)
  Harness.assertEqual(EntityStructLayout.address(19, EntityStructLayout.FIELD.OAM_SHADOW_PTR), 0xC338)
end)

Harness.test("EntityStructLayout: the player-slot hypothesis address matches the already-known real $C244/$C245", function()
  local y = EntityStructLayout.address(EntityStructLayout.PLAYER_SLOT_INDEX_HYPOTHESIS, EntityStructLayout.FIELD.POSITION_Y)
  local x = EntityStructLayout.address(EntityStructLayout.PLAYER_SLOT_INDEX_HYPOTHESIS, EntityStructLayout.FIELD.POSITION_X)
  Harness.assertEqual(y, 0xC244)
  Harness.assertEqual(x, 0xC245)
end)

-- --- ROM-dependent: cross-check the real disassembly this layout is
-- distilled from, byte for byte -- both routines live in fixed bank 0,
-- so file offset == CPU address directly.
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "EntityStructLayout: real $0AE3 (despawn) bytes confirm BASE, STRIDE, and the POSITION_Y field offset",
  romData ~= nil,
  "no development ROM found",
  function()
    RomProfiles.match(RomIdentity.identify(romData)) -- fails loudly if this isn't the expected ROM
    local h = EntityStructLayout.DESPAWN_ROUTINE_ADDRESS
    Harness.assertEqual(h, 0x0AE3)

    -- $0AEB-$0AEE: 4x `ADD HL,HL` (0x29) -- the real C*16 stride doubling.
    for i = 0, 3 do
      Harness.assertEqual(romData:byte(0x0AEB + i + 1), 0x29)
    end
    -- $0AEF: `LD BC,0xC200` (01 00 C2) -- the real struct BASE.
    Harness.assertEqual(romData:byte(0x0AEF + 1), 0x01)
    Harness.assertEqual(romData:byte(0x0AF0 + 1) + romData:byte(0x0AF1 + 1) * 256, EntityStructLayout.BASE)
    -- $0AFB: `LD HL,0x0004` (21 04 00) -- the real POSITION_Y field offset.
    Harness.assertEqual(romData:byte(0x0AFB + 1), 0x21)
    Harness.assertEqual(romData:byte(0x0AFC + 1) + romData:byte(0x0AFD + 1) * 256, EntityStructLayout.FIELD.POSITION_Y)
  end
)

Harness.testIfAvailable(
  "EntityStructLayout: real $0A74 (allocate) bytes confirm BASE, STRIDE, SLOT_COUNT, and the real ALIVE value",
  romData ~= nil,
  "no development ROM found",
  function()
    local h = EntityStructLayout.ALLOCATE_ROUTINE_ADDRESS
    Harness.assertEqual(h, 0x0A74)

    -- $0A77: `LD HL,0xC200` (21 00 C2) -- the real struct BASE.
    Harness.assertEqual(romData:byte(0x0A77 + 1), 0x21)
    Harness.assertEqual(romData:byte(0x0A78 + 1) + romData:byte(0x0A79 + 1) * 256, EntityStructLayout.BASE)
    -- $0A7A: `LD DE,0x0010` (11 10 00) -- the real 16-byte STRIDE.
    Harness.assertEqual(romData:byte(0x0A7A + 1), 0x11)
    Harness.assertEqual(romData:byte(0x0A7B + 1) + romData:byte(0x0A7C + 1) * 256, EntityStructLayout.STRIDE)
    -- $0A7F: `LD B,0x14` (06 14) -- the real 20-slot scan count.
    Harness.assertEqual(romData:byte(0x0A7F + 1), 0x06)
    Harness.assertEqual(romData:byte(0x0A80 + 1), EntityStructLayout.SLOT_COUNT)
    -- $0A91: `LD (HL),0x08` (36 08) -- the real ALIVE value written on allocate.
    Harness.assertEqual(romData:byte(0x0A91 + 1), 0x36)
    Harness.assertEqual(romData:byte(0x0A92 + 1), 0x08)
  end
)
