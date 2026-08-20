local Harness = require("tests.harness")
local NpcSpawnTable = require("src.import.NpcSpawnTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

--- Builds a synthetic bank-3 ROM byte string containing exactly one row
-- (1 column, to keep the fixture small) whose pointer resolves to a
-- record placed right after the pointer table itself.
local function syntheticOneColumnRom(recordBytes)
  local CPU_TABLE_BASE = 0x4000 -- an arbitrary, easy-to-reason-about bank-3 base
  local fileTableOffset = CPU_TABLE_BASE + 0x8000 -- bank3FileOffset(CPU_TABLE_BASE)
  local recordCpuAddress = CPU_TABLE_BASE + 2 -- right after the 1 column's own 2-byte pointer
  local ptrLo = recordCpuAddress % 256
  local ptrHi = math.floor(recordCpuAddress / 256)
  -- Pad with zero bytes from file offset 0 up to fileTableOffset, then
  -- the pointer, then the record itself.
  local padding = string.rep("\0", fileTableOffset)
  local rom = padding .. string.char(ptrLo, ptrHi) .. recordBytes
  return rom, { fileOffset = fileTableOffset, rowCount = 1, colsPerRow = 1 }
end

Harness.test("NpcSpawnTable.decode: parses a synthetic fixed-count, explicit-position record", function()
  -- minSpawn=1 maxSpawn=1 ids={0x12,0x12,0x12,0x12} (NPC_GOBLIN) then one
  -- real Y,X pair (8,10) then the $80,$80 terminator.
  local record = string.char(1, 1, 0x12, 0x12, 0x12, 0x12, 8, 10, 0x80, 0x80)
  local rom, tableSpec = syntheticOneColumnRom(record)
  local rows = NpcSpawnTable.decode(rom, tableSpec)
  Harness.assertEqual(#rows, 1)
  local col = rows[1][1]
  Harness.assertEqual(col.minSpawn, 1)
  Harness.assertEqual(col.maxSpawn, 1)
  Harness.assertEqual(col.candidateIds[1], 0x12)
  Harness.assertEqual(col.candidateIds[4], 0x12)
  Harness.assertEqual(col.isRandomPosition, false)
  Harness.assertEqual(#col.positions, 1)
  Harness.assertEqual(col.positions[1].y, 8)
  Harness.assertEqual(col.positions[1].x, 10)
end)

Harness.test("NpcSpawnTable.decode: an immediate $80,$80 terminator means 'spawn at a random position'", function()
  -- Real shape row1/col0 (NPC_GOBLIN) is actually decoded as in this ROM:
  -- minSpawn=1 maxSpawn=2, no explicit positions at all.
  local record = string.char(1, 2, 0x12, 0x12, 0x12, 0x12, 0x80, 0x80)
  local rom, tableSpec = syntheticOneColumnRom(record)
  local rows = NpcSpawnTable.decode(rom, tableSpec)
  local col = rows[1][1]
  Harness.assertEqual(col.minSpawn, 1)
  Harness.assertEqual(col.maxSpawn, 2)
  Harness.assertEqual(col.isRandomPosition, true)
  Harness.assertEqual(#col.positions, 0)
end)

Harness.test("NpcSpawnTable.resolve: 0-based (row, col) lookup matches the real script-opcode operand convention", function()
  local record = string.char(1, 1, 0x61, 0x61, 0x61, 0x61, 0x80, 0x80) -- NPC_WILLY
  local rom, tableSpec = syntheticOneColumnRom(record)
  local rows = NpcSpawnTable.decode(rom, tableSpec)
  local col = NpcSpawnTable.resolve(rows, 0, 0)
  Harness.assertEqual(col.candidateIds[1], 0x61)
  Harness.assertEqual(NpcSpawnTable.resolve(rows, 5, 0), nil, "out-of-range row should return nil, not error")
  Harness.assertEqual(NpcSpawnTable.resolve(rows, 0, 5), nil, "out-of-range col should return nil, not error")
end)

Harness.test("NpcSpawnTable.NAMES_BY_ID: the 4 real, live-confirmed IDs from this session's own investigation resolve to the right external names", function()
  Harness.assertEqual(NpcSpawnTable.NAMES_BY_ID[0x61], "NPC_WILLY")
  Harness.assertEqual(NpcSpawnTable.NAMES_BY_ID[0x79], "NPC_GLADIATOR_FRIEND")
  Harness.assertEqual(NpcSpawnTable.NAMES_BY_ID[0x63], "NPC_AMANDA_1")
  Harness.assertEqual(NpcSpawnTable.NAMES_BY_ID[0x12], "NPC_GOBLIN")
end)

Harness.test("NpcSpawnTable.looksLikeMonsterName: excludes doors/chests/followers/story characters, keeps field monsters", function()
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_GOBLIN"), true)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_MUSHROOM"), true)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_INV_OPEN_NORTH"), false)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_CHEST_1"), false)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_MIMIC_CHEST"), false)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_FUJI_FOLLOWING"), false)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_GUY_TOPPLE_HOUSE"), false)
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName("NPC_WILLY"), true, "named story characters aren't excluded by this heuristic -- it only screens obvious non-monster SHAPES")
  Harness.assertEqual(NpcSpawnTable.looksLikeMonsterName(nil), false)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "NpcSpawnTable.decode: real ROM's 109-row table resolves the 4 live-confirmed (row,col) examples exactly",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local rows = NpcSpawnTable.decode(romData, profile.npcSpawnPointerTable)
    Harness.assertEqual(#rows, 109)
    Harness.assertEqual(#rows[1], 3, "each row should have 3 columns")

    for _, example in ipairs(profile.npcSpawnPointerTable.verifiedExamples) do
      local col = NpcSpawnTable.resolve(rows, example.row, example.col)
      Harness.assertEqual(col.candidateIds[1], example.id,
        string.format("row %d col %d: expected id %#04x (%s)", example.row, example.col, example.id, example.name))
      Harness.assertEqual(NpcSpawnTable.NAMES_BY_ID[col.candidateIds[1]], example.name)
    end
  end
)

Harness.testIfAvailable(
  "NpcSpawnTable.decode: the real ROM has at least one row whose candidate ID looks like a field monster, not just NPCs",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local rows = NpcSpawnTable.decode(romData, profile.npcSpawnPointerTable)
    local foundMonster = false
    for _, row in ipairs(rows) do
      for _, col in ipairs(row) do
        local name = NpcSpawnTable.NAMES_BY_ID[col.candidateIds[1]]
        if NpcSpawnTable.looksLikeMonsterName(name) then
          foundMonster = true
          break
        end
      end
      if foundMonster then break end
    end
    Harness.assertEqual(foundMonster, true, "expected at least one real row to resolve to a monster-shaped NPC_* name")
  end
)
