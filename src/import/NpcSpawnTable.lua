-- Decodes the real regular-monster/NPC spawn table found in the Mystic
-- Quest (EU) ROM -- bank 3, file `0xF142` (CPU `$7142`), 109 rows x 3
-- columns. THE real mechanism this project's `Bestiary` roadmap item
-- was blocked on: every placed monster or NPC in the game (not just
-- the one, already-known scripted courtyard boss) spawns through this
-- one table.
--
-- FOUND, 2026-08-20 (direct user instruction, "wir brauchen bessere
-- strategien um die blocker zu lösen. bitte sei kreativ..."): the
-- public FFA-Disassembly project for the US cartridge (daid/
-- FFA-Disassembly, `src/data/npc/spawn.asm` -- see docs/references.md)
-- had already been used ONCE, much earlier, to cross-check boss STAT
-- values (see EnemyStatTable.lua) -- but never mined for its
-- encounter/spawn CODE specifically. It documents a real
-- `NPCSpawnPointers` table (CPU `$7142`) driven by two script opcodes,
-- `sSET_NPC_TYPES <row>` (stages a row) / `sSPAWN_NPC <col>` (spawns
-- from one of that row's 3 columns) -- which turned out to be this
-- project's own already-traced (but, until this point, misidentified
-- as a generic "selector group 5/4" trigger-event pair) opcodes
-- `0xFC`/`0xFD`. See `ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC`/
-- `_FD`'s own doc comment for the opcode-level story, and
-- `src/scripting/ScriptRuntime.lua`'s `ctx.onSetNpcTypes`/
-- `ctx.onSpawnNpc` for how a script fires this live.
--
-- VERIFIED BYTE-FOR-BYTE IDENTICAL in this EU ROM: disassembling this
-- ROM's own `$1F35` selector 5 (`$444A`, bank 3, `0xFC`'s real target)
-- shows `HL = row*6 + $7142` -- the literal CPU address matches the US
-- disassembly's own source exactly, not just a structurally similar
-- shape. Selector 4 (`$44ED`, `0xFD`'s target) resolves
-- `NPCSpawnPointers[row][col]`, rolls a real spawn count via the
-- already-known PRNG (`$2B1E`) and 8x8->16 multiply (`$2B7B`, the same
-- routine `EnemyStatTable`'s own HP formula uses), then walks the
-- Y/X position list, calling a per-position spawn leaf (`$1F35`
-- selector 2, `$42BD`) for each. A raw whole-ROM byte-pattern census
-- for `CALL $0A74` (the already-known entity-allocate primitive) found
-- exactly 7 real direct call sites total, one of them right inside
-- selector 2's own body -- closing the chain from script opcode to
-- live entity end to end.
--
-- LIVE-CONFIRMED: a scratchpad-only, 2-byte-patched ROM copy
-- redirected an already-organically-firing real `0xFC`/`0xFD` pair
-- (willyRoom's own real Willy-spawn trigger, row 36/col 2) from
-- `NPC_WILLY` to `NPC_GOBLIN` (row 1/col 0) -- the full real chain
-- fired live (`$27F9`->`$2820`->`$42BD`->`$0A74`) and produced a
-- second, visually distinct, stable creature on screen with real
-- player LP loss from contact. See docs/reverse-engineering/events.md's
-- 2026-08-20 "SOLVED" entry for the complete trace.
--
-- Record shape per column (real bytes, verified structure):
--   +0      minSpawn -- real, how many instances to spawn at minimum
--   +1      maxSpawn -- real; when equal to minSpawn, no random roll
--                       happens (a fixed count)
--   +2..+5  4 candidate species/NPC IDs -- one is picked at random per
--           spawn (the real ROM mechanism); in the large majority of
--           real rows observed, all 4 are IDENTICAL (a fixed choice
--           dressed up as a random one) -- exposed as `candidateIds`
--           regardless, since collapsing them would silently drop
--           real ROM bytes for the handful of rows where they DO
--           differ (not independently confirmed either way this pass).
--   +6..    real Y,X position byte pairs, terminated by `$80,$80`
--           (the external reference's own documented meaning: "spawn
--           at a random position instead" once reached with no real
--           position pairs consumed yet, or "list exhausted" if
--           reached after some real pairs already were).
--
-- Species/NPC ID VALUES are real, decoded ROM bytes. `NAMES_BY_ID`
-- below is the external US disassembly's own `NPC_*` constant table --
-- a SOURCED EXTERNAL CROSS-REFERENCE, not decoded from this ROM's own
-- text, same status as `EnemyStatTable.lua`'s `externalReferenceNames`.
-- Confirmed correct for the 3 IDs this project has actually
-- live-observed firing naturally (0x61 NPC_WILLY in willyRoom, 0x79
-- NPC_GLADIATOR_FRIEND / 0x63 NPC_AMANDA_1 in secondRoom) plus the one
-- reached via the live ROM patch above (0x12 NPC_GOBLIN) -- the other
-- 187 names are real, sourced data, NOT independently re-verified
-- against this EU ROM's own in-game content.
--
-- Pure Lua, no love.* calls, same convention as EnemyStatTable/
-- EnemySpeciesTable.
--
-- HONEST SCOPE: this decoder resolves the table's own real POINTERS
-- and RECORDS; it does not itself know which real script(s) call
-- `sSET_NPC_TYPES`/`sSPAWN_NPC` with which row/col beyond the 4
-- examples above (see `verifiedExamples` in `rom_profiles.lua`'s own
-- `npcSpawnPointerTable` entry) -- finding every real trigger in the
-- ROM is a separate, not-yet-attempted follow-up (this session's own
-- corpus-wide shadow-run of the trusted 1357-script table found ZERO
-- real hits, meaning the real callers live outside that corpus,
-- reached some other way not yet identified).

local NpcSpawnTable = {}

NpcSpawnTable.COLS_PER_ROW = 3
NpcSpawnTable.POINTER_STRIDE = 2 -- bytes per column pointer
NpcSpawnTable.ROW_STRIDE = NpcSpawnTable.COLS_PER_ROW * NpcSpawnTable.POINTER_STRIDE -- 6

-- Safety bound on the Y/X position list scan -- real rows observed
-- top out well under this; exists only so a hypothetically malformed
-- record can't spin forever, not because any real row needs it.
local MAX_POSITIONS = 32

--- Convert a bank-3 CPU address (`$4000`-`$7FFF`) to its real ROM file
-- offset. Bank 3 occupies file `[0xC000, 0x10000)`, mapped to CPU
-- `[0x4000, 0x8000)` -- `fileOffset = cpuAddress + 0x8000`.
local function bank3FileOffset(cpuAddress)
  return cpuAddress + 0x8000
end

--- Read one real spawn record (the target of one column's own 2-byte
-- pointer): `{minSpawn, maxSpawn, candidateIds={4}, positions={{y,x},...},
-- isRandomPosition}`. `isRandomPosition` is true when the position list
-- is empty (the very first Y byte read is already the `$80,$80`
-- terminator) -- the real ROM's own "pick a random spot" case.
local function decodeRecord(romData, fileOffset)
  local minSpawn = romData:byte(fileOffset + 1)
  local maxSpawn = romData:byte(fileOffset + 2)
  local candidateIds = {
    romData:byte(fileOffset + 3),
    romData:byte(fileOffset + 4),
    romData:byte(fileOffset + 5),
    romData:byte(fileOffset + 6),
  }

  local positions = {}
  local cursor = fileOffset + 7 -- 1-based next byte after the 6-byte header
  local isRandomPosition = false
  for i = 1, MAX_POSITIONS do
    local y = romData:byte(cursor)
    local x = romData:byte(cursor + 1)
    if y == 0x80 and x == 0x80 then
      if i == 1 then isRandomPosition = true end
      break
    end
    positions[#positions + 1] = { y = y, x = x }
    cursor = cursor + 2
  end

  return {
    minSpawn = minSpawn,
    maxSpawn = maxSpawn,
    candidateIds = candidateIds,
    positions = positions,
    isRandomPosition = isRandomPosition,
  }
end

--- Decode the full real table from `romData` per `npcSpawnPointerTable`
-- (`profile.npcSpawnPointerTable`, `{fileOffset, rowCount, colsPerRow}`).
-- Returns a plain 1-based array of `rowCount` rows, each row a plain
-- 1-based array of `colsPerRow` columns, each column
-- `{targetCpuAddress, minSpawn, maxSpawn, candidateIds, positions,
-- isRandomPosition}`.
function NpcSpawnTable.decode(romData, npcSpawnPointerTable)
  assert(type(romData) == "string", "NpcSpawnTable.decode expects a byte string")
  assert(npcSpawnPointerTable and npcSpawnPointerTable.fileOffset and npcSpawnPointerTable.rowCount,
    "NpcSpawnTable.decode expects a profile.npcSpawnPointerTable")

  local colsPerRow = npcSpawnPointerTable.colsPerRow or NpcSpawnTable.COLS_PER_ROW
  local rows = {}
  for rowIndex = 0, npcSpawnPointerTable.rowCount - 1 do
    local rowBase = npcSpawnPointerTable.fileOffset + rowIndex * (colsPerRow * NpcSpawnTable.POINTER_STRIDE)
    local cols = {}
    for colIndex = 0, colsPerRow - 1 do
      local ptrOffset = rowBase + colIndex * NpcSpawnTable.POINTER_STRIDE
      local lo = romData:byte(ptrOffset + 1)
      local hi = romData:byte(ptrOffset + 2)
      assert(lo and hi, "NpcSpawnTable.decode: row " .. rowIndex .. " col " .. colIndex .. " pointer ran past the end of romData")
      local targetCpuAddress = lo + hi * 256
      local targetFileOffset = bank3FileOffset(targetCpuAddress)
      local record = decodeRecord(romData, targetFileOffset)
      record.targetCpuAddress = targetCpuAddress
      cols[colIndex + 1] = record
    end
    rows[rowIndex + 1] = cols
  end
  return rows
end

--- Convenience accessor: resolve a real `(row, col)` pair -- the same
-- 0-based values a script's own `sSET_NPC_TYPES`/`sSPAWN_NPC` operand
-- bytes carry -- against an already-`decode()`d table. Returns nil if
-- out of range rather than erroring, since a malformed/forced (row,
-- col) is a real possibility this project's own live-injection
-- experiments have already run into (see events.md).
function NpcSpawnTable.resolve(rows, row, col)
  local r = rows[row + 1]
  if not r then return nil end
  return r[col + 1]
end

-- The external US disassembly's own `NPC_*` constant table (daid/
-- FFA-Disassembly, `src/include/constants.inc`) -- see this module's
-- own doc comment for sourcing/confirmation status.
NpcSpawnTable.NAMES_BY_ID = {
  [0] = "NPC_SNOWMAN_STILL",
  [1] = "NPC_FUJI_FOLLOWING",
  [2] = "NPC_MYSTERYMAN_FOLLOWING",
  [3] = "NPC_WATTS_FOLLOWING",
  [4] = "NPC_BOGARD_FOLLOWING",
  [5] = "NPC_AMANDA_FOLLOWING",
  [6] = "NPC_LESTER_FOLLOWING",
  [7] = "NPC_MARCIE_FOLLOWING",
  [8] = "NPC_CHOCOBOT_FOLLOWING",
  [9] = "NPC_CHOCOBO_FOLLOWING",
  [10] = "NPC_WEREWOLF_1",
  [11] = "NPC_INV_CURE",
  [12] = "NPC_CHEST_1",
  [13] = "NPC_CHEST_2",
  [14] = "NPC_CHEST_3",
  [15] = "NPC_CHEST_4",
  [16] = "NPC_CHIBIDEVIL",
  [17] = "NPC_RABBITE",
  [18] = "NPC_GOBLIN",
  [19] = "NPC_MUSHROOM",
  [20] = "NPC_JELLYFISH",
  [21] = "NPC_SWAMPMAN",
  [22] = "NPC_LIZARDMAN",
  [23] = "NPC_FLOWER",
  [24] = "NPC_FACEORB",
  [25] = "NPC_SKELETON",
  [26] = "NPC_EVIL_PLANT",
  [27] = "NPC_FLYING_FISH",
  [28] = "NPC_ZOMBIE",
  [29] = "NPC_MOUSE",
  [30] = "NPC_PUMPKIN",
  [31] = "NPC_OWL",
  [32] = "NPC_BEE",
  [33] = "NPC_CLOUD",
  [34] = "NPC_PIG",
  [35] = "NPC_CRAB",
  [36] = "NPC_SPIDER",
  [37] = "NPC_INV_OPEN_NORTH",
  [38] = "NPC_INV_OPEN_SOUTH",
  [39] = "NPC_INV_OPEN_EAST",
  [40] = "NPC_INV_OPEN_WEST",
  [41] = "NPC_MIMIC_CHEST",
  [42] = "NPC_HOPPING_BUG",
  [43] = "NPC_PORCUPINE",
  [44] = "NPC_CARROT",
  [45] = "NPC_EYE_SPY",
  [46] = "NPC_WEREWOLF_2",
  [47] = "NPC_GHOST",
  [48] = "NPC_BASILISK",
  [49] = "NPC_SCORPION",
  [50] = "NPC_SAURUS",
  [51] = "NPC_MUMMY",
  [52] = "NPC_PAKKUN_LIZARD",
  [53] = "NPC_SNAKE",
  [54] = "NPC_SHADOW",
  [55] = "NPC_BLACK_WIZARD",
  [56] = "NPC_FLAME",
  [57] = "NPC_GARGOYLE",
  [58] = "NPC_MONKEY",
  [59] = "NPC_MOLEBEAR",
  [60] = "NPC_OGRE",
  [61] = "NPC_BARNACLEJACK",
  [62] = "NPC_PHANTASM",
  [63] = "NPC_MINOTAUR",
  [64] = "NPC_GLAIVE_MAGE",
  [65] = "NPC_GLAIVE_KNIGHT",
  [66] = "NPC_DARK_LORD",
  [67] = "NPC_MEGA_FLYTRAP",
  [68] = "NPC_DRAGONFLY",
  [69] = "NPC_ARMADILLO",
  [70] = "NPC_SNOWMAN_MOVING",
  [71] = "NPC_SABER_CAT",
  [72] = "NPC_WALRUS",
  [73] = "NPC_DUCK_SOLDIER",
  [74] = "NPC_POTO_RABBIT",
  [75] = "NPC_CYCLONE",
  [76] = "NPC_BEHOLDER_EYE",
  [77] = "NPC_MANTA_RAY",
  [78] = "NPC_JUMPING_HAND",
  [79] = "NPC_TORTOISE",
  [80] = "NPC_FIRE_MOTH",
  [81] = "NPC_EARTH_DIGGER",
  [82] = "NPC_DENDEN_SNAIL",
  [83] = "NPC_DOPPEL_MIRROR",
  [84] = "NPC_GUARDIAN",
  [85] = "NPC_EVIL_SWORD",
  [86] = "NPC_GAUNTLET",
  [87] = "NPC_GARASHA_DUCK",
  [88] = "NPC_FUZZY_WONDER",
  [89] = "NPC_ELEPHANT",
  [90] = "NPC_NINJA",
  [91] = "NPC_JULIUS",
  [92] = "NPC_DEMON_HEAD",
  [93] = "NPC_INV_DESSERT_CAVE_STONE",
  [94] = "NPC_WATER_DEMON",
  [95] = "NPC_SEA_DRAGON",
  [96] = "NPC_GALL_FISH",
  [97] = "NPC_WILLY",
  [98] = "NPC_MYSTERYMAN_1",
  [99] = "NPC_AMANDA_1",
  [100] = "NPC_AMANDA_ILL",
  [101] = "NPC_AMANDA_DEAD",
  [102] = "NPC_FUJI_1",
  [103] = "NPC_FUJI_WINDOW",
  [104] = "NPC_MOTHER",
  [105] = "NPC_BOGARD_1",
  [106] = "NPC_BOGARD_2",
  [107] = "NPC_KETTS_WEREWOLF",
  [108] = "NPC_INV_FUJI_COFFIN",
  [109] = "NPC_CIBBA",
  [110] = "NPC_GUY_WENDEL",
  [111] = "NPC_WATTS",
  [112] = "NPC_MINECART",
  [113] = "NPC_CHOCOBO_EGG",
  [114] = "NPC_DAVIAS",
  [115] = "NPC_LESTER_1",
  [116] = "NPC_LESTER_PARROT",
  [117] = "NPC_BOWOW",
  [118] = "NPC_SARAH",
  [119] = "NPC_MARCIE_1",
  [120] = "NPC_KING_OF_LORIM",
  [121] = "NPC_GLADIATOR_FRIEND",
  [122] = "NPC_INV_INN",
  [123] = "NPC_GIRL_TOPPLE",
  [124] = "NPC_GUY_TOPPLE",
  [125] = "NPC_GUY_TOPPLE_HOUSE",
  [126] = "NPC_GIRL_TOPPLE_HOUSE",
  [127] = "NPC_OLDMAN_TOPPLE",
  [128] = "NPC_GUY_KETTS",
  [129] = "NPC_GIRL_KETTS",
  [130] = "NPC_GIRL_CIBBA",
  [131] = "NPC_GUY_WENDEL2",
  [132] = "NPC_GUY_WENDEL_HOUSE",
  [133] = "NPC_WOMAN_CIBBA",
  [134] = "NPC_OLDMAN_WENDEL",
  [135] = "NPC_DWARF_1",
  [136] = "NPC_DWARF_2",
  [137] = "NPC_DWARF_3",
  [138] = "NPC_DWARF_4",
  [139] = "NPC_DWARF_5",
  [140] = "NPC_GUY_AIRSHIP_1",
  [141] = "NPC_GUY_AIRSHIP_2",
  [142] = "NPC_GUY_AIRSHIP_3",
  [143] = "NPC_GUY_AIRSHIP_4",
  [144] = "NPC_OLDMAN_MENOS_1",
  [145] = "NPC_GUY_MENOS",
  [146] = "NPC_GIRL_MENOS_1",
  [147] = "NPC_OLDMAN_MENOS_2",
  [148] = "NPC_GIRL_MENOS",
  [149] = "NPC_WOMAN_MENOS_2",
  [150] = "NPC_GIRL_JADD_1",
  [151] = "NPC_OLDMAN_JADD",
  [152] = "NPC_GIRL_JADD_2",
  [153] = "NPC_GUY_JADD",
  [154] = "NPC_DWARF_JADD",
  [155] = "NPC_SALESMAN_JADD",
  [156] = "NPC_GIRL_JADD_3",
  [157] = "NPC_BOY_JADD",
  [158] = "NPC_OLDMAN_ISH",
  [159] = "NPC_GUY_ISH_1",
  [160] = "NPC_GUY_ISH_2",
  [161] = "NPC_GIRL_ISH",
  [162] = "NPC_GUY_ISH_3",
  [163] = "NPC_GUY_ISH_4",
  [164] = "NPC_INV_STONE_1",
  [165] = "NPC_INV_STONE_2",
  [166] = "NPC_INV_STONE_3",
  [167] = "NPC_INV_STONE_4",
  [168] = "NPC_INV_STONE_5",
  [169] = "NPC_INV_STONE_6",
  [170] = "NPC_INV_STONE_7",
  [171] = "NPC_INV_STONE_8",
  [172] = "NPC_GUY_LORIM_FROZEN",
  [173] = "NPC_GUY_LORIM_1",
  [174] = "NPC_GUY_LORIM_2",
  [175] = "NPC_SALESMAN",
  [176] = "NPC_INV_SALESMAN_1",
  [177] = "NPC_FUJI_2",
  [178] = "NPC_INV_SALESMAN_2",
  [179] = "NPC_MYSTERYMAN_2",
  [180] = "NPC_BOGARD_3",
  [181] = "NPC_AMANDA_2",
  [182] = "NPC_LESTER_2",
  [183] = "NPC_MARCIE_2",
  [184] = "NPC_CHOCOBOT",
  [185] = "NPC_CHOCOBO_1",
  [186] = "NPC_CHOCOBO_2",
  [187] = "NPC_PRISION_BARS",
  [188] = "NPC_MUSIC_NOTES",
  [189] = "NPC_MAGIC_SALESMAN",
  [190] = "NPC_LAST_GUY",
}

--- REMOVED, 2026-08-20 (direct user correction, "der goblin ist kein
-- npc das ist ein gegner und das was du als monster auf der website
-- klassifizierst sind eigentlich bosse"): the earlier
-- `looksLikeMonsterName` here CLAIMED to exclude "named story
-- characters" but its own implementation didn't -- `NPC_WILLY` passed
-- it as a real, tested "monster-shaped" result (see this project's own
-- git history), which is exactly backwards: Willy is this game's
-- primary friendly NPC, not a hostile creature. This project has NO
-- real, decoded ROM fact that distinguishes "hostile field monster"
-- from "friendly NPC" from "story boss" within this table's own
-- NPC_*-ID space -- inventing that distinction from name-shape alone
-- was a guess this project's own discipline doesn't allow. Kept
-- narrowly to what IS real: `isEnvironmentalTrigger` below excludes
-- names that are decoded, non-creature ROM triggers (a door doesn't
-- "spawn" in any hostile-vs-friendly sense at all), nothing more.

--- True for NAMES_BY_ID entries that are decoded, non-creature
-- environmental triggers (door-open triggers, chests, other inventory
-- fixtures) rather than any kind of placed character -- a real,
-- narrow, name-shape fact (`NPC_INV_`/`CHEST` prefixes are the
-- external reference's own naming for these), NOT a claim about
-- which REMAINING entries are hostile, friendly, or a story boss --
-- this project has no decoded ROM fact for that distinction.
function NpcSpawnTable.isEnvironmentalTrigger(name)
  if not name then return false end
  if name:match("^NPC_INV_") then return true end
  if name:match("CHEST") then return true end
  return false
end

return NpcSpawnTable
