local Harness = require("tests.harness")
local SpriteTileFormula = require("src.import.SpriteTileFormula")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ActorDefinitionTable = require("src.import.ActorDefinitionTable")
local MonsterDefinitionTable = require("src.import.MonsterDefinitionTable")
local DevRomLocator = require("tests.dev_rom_locator")

-- Pure-math regression lock for the real formula found 2026-08-17 (see
-- this module's own doc comment for the full disassembly/derivation):
-- characterA's own live-confirmed real kindByte=0x51, C=0x00, rawByte=0
-- must resolve to EXACTLY characterA's own already-independently-known
-- real tileOffset 0x25100.
Harness.test("SpriteTileFormula.resolveFileOffset: exact-matches characterA's own known-good pixel (kindByte=0x51, rawByte=0 -> 0x25100, bank 9)", function()
  local off, bank = SpriteTileFormula.resolveFileOffset(0, 0x51, 0x00)
  Harness.assertEqual(off, 0x25100)
  Harness.assertEqual(bank, 9)
end)

Harness.test("SpriteTileFormula.reconstructPoseOrder: swaps the middle two of every 4-tile group, leaves a trailing partial group untouched", function()
  local reordered = SpriteTileFormula.reconstructPoseOrder({ "a", "b", "c", "d", "e", "f", "g", "h", "x", "y" })
  Harness.assertEqual(table.concat(reordered, ","), "a,c,b,d,e,g,f,h,x,y")
end)

Harness.test("SpriteTileFormula.resolveFileOffset: bank = 8 + floor(kindByte/64), covering all 4 real graphics banks", function()
  local _, bank0 = SpriteTileFormula.resolveFileOffset(0, 0x00, 0x00)
  local _, bank1 = SpriteTileFormula.resolveFileOffset(0, 0x51, 0x00) -- 0x51 = 0b01010001 -> top 2 bits 01
  local _, bank2 = SpriteTileFormula.resolveFileOffset(0, 0x92, 0x00) -- 0b10010010 -> top 2 bits 10
  local _, bank3 = SpriteTileFormula.resolveFileOffset(0, 0xFE, 0x00) -- 0b11111110 -> top 2 bits 11
  Harness.assertEqual(bank0, 8)
  Harness.assertEqual(bank1, 9)
  Harness.assertEqual(bank2, 10)
  Harness.assertEqual(bank3, 11)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

-- Rebuild the exact per-pose tile list order rom_profiles.lua's own
-- characterA/characterB `animation` tables use (down, up, left-frame1,
-- left-frame2 -- see that module's own doc comment on why this order,
-- not OAM screen position, is the real ROM order).
local function flatPoseOffsets(character)
  local a = character.animation
  local offs = {}
  for _, group in ipairs({ a.down[1], a.up[1], a.left[1], a.left[2] }) do
    for _, o in ipairs(group.tileOffsets) do offs[#offs + 1] = o end
  end
  return offs
end

--- The real ROM->VRAM DMA copies each pose's 4 tiles in a real,
-- live-confirmed "0,2,1,3" interleaved order (see
-- `trace_npc_sprite_dispatch2.py`'s own captured HL sequence,
-- 0x5100,0x5120,0x5110,0x5130,... -- NOT plain 0,1,2,3) -- a DIFFERENT
-- real ordering from `rom_profiles.lua`'s own `animation` table, which
-- groups tiles by their final LOGICAL pose/on-screen-arrangement order
-- (see that room's own doc comment on why sequential, not OAM-position,
-- order was used there). Both orderings are real, they just answer
-- different questions (raw DMA copy order vs. final logical grouping)
-- -- comparing as a SET, not a sequence, is the correct invariant: the
-- formula must produce EXACTLY the same 16 real file offsets, in
-- whatever order the ROM's own DMA record actually lists them.
local function assertSameOffsetSet(offsets, expected, label)
  Harness.assertEqual(#offsets, #expected)
  local expectedSet = {}
  for _, o in ipairs(expected) do expectedSet[o] = (expectedSet[o] or 0) + 1 end
  for _, o in ipairs(offsets) do
    Harness.assertTrue(expectedSet[o] ~= nil and expectedSet[o] > 0,
      string.format("%s: formula-resolved offset %s not found in the already-known real set", label, tostring(o)))
    expectedSet[o] = expectedSet[o] - 1
  end
  for o, remaining in pairs(expectedSet) do
    Harness.assertEqual(remaining, 0,
      string.format("%s: already-known real offset %s never produced by the formula", label, tostring(o)))
  end
end

Harness.testIfAvailable(
  "ActorDefinitionTable.resolveSpriteTileOffsets: characterA (index 121) exactly reproduces all 16 already-known real tileOffsets, IN THE REAL ON-SCREEN POSE ORDER",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local record = ActorDefinitionTable.readRecord(romData, 121)
    Harness.assertEqual(record.spriteSource.arrangementFamily, "humanoid4pose")
    local offsets = ActorDefinitionTable.resolveSpriteTileOffsets(romData, record)
    local expected = flatPoseOffsets(profile.graphics.secondRoom.scene.characterA)
    -- Now a STRICT ordered match, not just a set: `resolveSpriteTileOffsets`
    -- auto-reorders `humanoid4pose` records into the real logical pose
    -- order (see SpriteTileFormula.reconstructPoseOrder's own doc
    -- comment) -- position-for-position identical to rom_profiles.lua's
    -- own already-known real down/up/left/left2 tile grouping.
    Harness.assertEqual(#offsets, #expected)
    for i = 1, #expected do
      Harness.assertEqual(offsets[i], expected[i],
        string.format("characterA tile %d: formula=%s known=%s", i, tostring(offsets[i]), tostring(expected[i])))
    end
  end
)

Harness.testIfAvailable(
  "ActorDefinitionTable.resolveSpriteTileOffsets: characterB (index 99) exactly reproduces all 16 already-known real tileOffsets, IN THE REAL ON-SCREEN POSE ORDER",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local record = ActorDefinitionTable.readRecord(romData, 99)
    Harness.assertEqual(record.spriteSource.arrangementFamily, "humanoid4pose")
    local offsets = ActorDefinitionTable.resolveSpriteTileOffsets(romData, record)
    local expected = flatPoseOffsets(profile.graphics.secondRoom.scene.characterB)
    Harness.assertEqual(#offsets, #expected)
    for i = 1, #expected do
      Harness.assertEqual(offsets[i], expected[i],
        string.format("characterB tile %d: formula=%s known=%s", i, tostring(offsets[i]), tostring(expected[i])))
    end
  end
)

Harness.testIfAvailable(
  "ActorDefinitionTable: the real humanoid4pose family has exactly 91 distinct real NPC sprite designs (172 records share it, the other 18 sharing the same innerPtr have count=1 -- a single icon, no pose structure -- and are correctly excluded)",
  romData ~= nil,
  "no development ROM found",
  function()
    local records = ActorDefinitionTable.scanTable(romData)
    local familyCount, distinctKindBytes = 0, {}
    for _, record in ipairs(records) do
      if record.spriteSource.arrangementFamily == "humanoid4pose" then
        familyCount = familyCount + 1
        distinctKindBytes[record.spriteSource.kindByte] = true
      end
    end
    local distinctCount = 0
    for _ in pairs(distinctKindBytes) do distinctCount = distinctCount + 1 end
    Harness.assertEqual(familyCount, 172)
    Harness.assertEqual(distinctCount, 91)
  end
)

Harness.testIfAvailable(
  "MonsterDefinitionTable.resolveSpriteTileOffsets: row 16 exactly reproduces enemySprite (16) + enemyDescent (16), all 32 already-known real tileOffsets, IN THE REAL ON-SCREEN 4x4 POSE ORDER",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local record = MonsterDefinitionTable.readRecord(romData, 16)
    local offsets, bank, chunksReordered, chunksTotal = MonsterDefinitionTable.resolveSpriteTileOffsets(romData, record)
    Harness.assertEqual(chunksReordered, 2)
    Harness.assertEqual(chunksTotal, 2)

    local expected = {}
    for _, o in ipairs(profile.graphics.enemySprite.tileOffsets) do expected[#expected + 1] = o end
    for _, o in ipairs(profile.graphics.enemyDescent.tileOffsets) do expected[#expected + 1] = o end
    -- STRICT ordered match now (this record's permutation was DERIVED
    -- from this exact ground truth, see SpriteTileFormula
    -- .CREATURE_4X4_POSE_PERMUTATION's own doc comment) -- not just a set.
    Harness.assertEqual(#offsets, #expected)
    for i = 1, #expected do
      Harness.assertEqual(offsets[i], expected[i],
        string.format("boss tile %d: formula=%s known=%s", i, tostring(offsets[i]), tostring(expected[i])))
    end
  end
)

Harness.testIfAvailable(
  "MonsterDefinitionTable.scanTable: the real measured extent is exactly 21 records",
  romData ~= nil,
  "no development ROM found",
  function()
    local records = MonsterDefinitionTable.scanTable(romData)
    Harness.assertEqual(#records, MonsterDefinitionTable.TABLE_COUNT)
    Harness.assertEqual(#records, 21)
    for _, record in ipairs(records) do
      Harness.assertTrue(not record.anomalous, "expected every one of the 21 measured rows to be plausible")
    end
  end
)

Harness.testIfAvailable(
  "MonsterDefinitionTable IS enemyStatTable (2026-08-17): same file base, same stride, row 16 is 'Jackal' in both",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local EnemyStatTable = require("src.import.EnemyStatTable")

    Harness.assertEqual(MonsterDefinitionTable.fileOffset(MonsterDefinitionTable.BANK, 0x4739), profile.enemyStatTable.fileOffset)
    Harness.assertEqual(MonsterDefinitionTable.TABLE_COUNT, profile.enemyStatTable.rowCount)

    local bossRows = EnemyStatTable.decode(romData, profile.enemyStatTable)
    Harness.assertEqual(profile.enemyStatTable.externalReferenceNames[17], "Jackal") -- 1-based row 17 = 0-based index 16

    -- Cross-check via actual raw bytes: MonsterDefinitionTable's own
    -- row 16 raw bytes[0..3] (0-based -- bytes[2..3] of THIS pair are
    -- live-confirmed written to real WRAM $D3F4/$D3F5, see
    -- MonsterDefinitionTable.lua's own doc comment) must equal
    -- enemyStatTable's own row 16 speed/hpBase/xp/gold exactly -- same
    -- raw ROM bytes, decoded by two independent modules.
    local monsterRow16 = MonsterDefinitionTable.readRecord(romData, 16)
    local bossRow16 = bossRows[17]
    Harness.assertEqual(monsterRow16.raw:byte(1), bossRow16.speed)
    Harness.assertEqual(monsterRow16.raw:byte(2), bossRow16.hpBase)
    Harness.assertEqual(monsterRow16.raw:byte(3), bossRow16.xp)
    Harness.assertEqual(monsterRow16.raw:byte(4), bossRow16.gold)
  end
)

Harness.test("SpriteTileFormula.matchesCreature4x4Shape: pure-math check against the reference shape, relative to the chunk's own first byte", function()
  Harness.assertTrue(SpriteTileFormula.matchesCreature4x4Shape({ 0x40, 0x42, 0x41, 0x43, 0x44, 0x46, 0x45, 0x47, 0x48, 0x4A, 0x49, 0x4B, 0x4C, 0x4E, 0x4D, 0x4F }))
  -- same relative shape, different base -- still matches (the rule is relative, not absolute)
  Harness.assertTrue(SpriteTileFormula.matchesCreature4x4Shape({ 0x10, 0x12, 0x11, 0x13, 0x14, 0x16, 0x15, 0x17, 0x18, 0x1A, 0x19, 0x1B, 0x1C, 0x1E, 0x1D, 0x1F }))
  -- a plain sequential 0..15 chunk (the NPC family's OWN shape) must NOT match -- these are genuinely different real patterns
  local sequential = {}
  for i = 0, 15 do sequential[i + 1] = i end
  Harness.assertTrue(not SpriteTileFormula.matchesCreature4x4Shape(sequential))
  Harness.assertTrue(not SpriteTileFormula.matchesCreature4x4Shape({ 1, 2, 3 })) -- wrong length
end)

Harness.testIfAvailable(
  "MonsterDefinitionTable: at least 6 of the 21 monster/boss records have EVERY 16-tile chunk matching the real creature-pose shape",
  romData ~= nil,
  "no development ROM found",
  function()
    local fullyReconstructed = 0
    local anyReconstructed = 0
    for index = 0, MonsterDefinitionTable.TABLE_COUNT - 1 do
      local record = MonsterDefinitionTable.readRecord(romData, index)
      local _, _, chunksReordered, chunksTotal = MonsterDefinitionTable.resolveSpriteTileOffsets(romData, record)
      if chunksTotal > 0 and chunksReordered == chunksTotal then fullyReconstructed = fullyReconstructed + 1 end
      if chunksReordered > 0 then anyReconstructed = anyReconstructed + 1 end
    end
    -- Real, measured counts (2026-08-17, direct instruction "versuche
    -- daraus die tatsächlichen monster... rekonstruieren"): rows 2, 3,
    -- 5, 7, 12, 16, 19 have every chunk matching (7 total, including
    -- the already-known row 16); most of the other 14 have at least one
    -- matching chunk. Asserted as lower bounds (>=), not exact counts,
    -- since a ROM revision with a genuinely different table shouldn't
    -- make this test flaky over an incidental exact number.
    Harness.assertTrue(fullyReconstructed >= 6,
      "expected at least 6 fully-reconstructed monster/boss records, got " .. fullyReconstructed)
    Harness.assertTrue(anyReconstructed >= 15,
      "expected at least 15 monster/boss records with at least one reconstructed pose, got " .. anyReconstructed)
  end
)

if romData then
  print("(SpriteTileFormula ROM-dependent tests ran against a real dev ROM)")
end
