local Harness = require("tests.harness")
local ItemTable = require("src.import.ItemTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("ItemTable.decode: parses a synthetic 2-record table", function()
  -- record0: name "Lebe" (0x00-padded to 8), then 8 stat/trailer bytes,
  -- id byte (byte 15) = 1.
  local rec0 = "\197\216\213\216\0\0\0\0" .. "\66\16\20\0\0\0\0\1"
  -- record1: name "Salb", category byte differs, id = 2.
  local rec1 = "\204\212\223\213\0\0\0\0" .. "\65\16\0\0\0\0\0\2"
  local rom = rec0 .. rec1
  local itemTable = { fileOffset = 0, recordLength = 16, nameLength = 8, recordCount = 2 }

  local records = ItemTable.decode(rom, itemTable)
  Harness.assertEqual(#records, 2)
  Harness.assertEqual(records[1].name, "Lebe")
  Harness.assertEqual(records[1].id, 1)
  Harness.assertEqual(records[1].categoryByte, 0x42)
  Harness.assertEqual(records[2].name, "Salb")
  Harness.assertEqual(records[2].id, 2)
end)

Harness.test("ItemTable.decode: name decoding never reads past the 8-byte name field into stat bytes (found 2026-08-18, real bug -- direct user report 'buchstabensalat')", function()
  -- A synthetic record whose name is exactly 8 bytes ("Testname" has no
  -- terminator before the field boundary), immediately followed by a
  -- stat byte (0xC5 = 'L' in the real glyph table) that decodes to a
  -- valid character too. Before the fix, TextDecoder.decodeString was
  -- given the FULL 16-byte record and had no reason to stop at the real
  -- 8-byte name boundary, so it kept reading into that stat byte and
  -- beyond -- producing an overlong, garbled name. After the fix, the
  -- name must stop at exactly 8 characters.
  local name8 = "\197\216\213\216\197\216\213\216" -- "LebeLebe": 8 real letter bytes, no embedded terminator
  local rec = name8 .. "\197\65\16\0\0\0\0\1" -- byte 9 (0xC5, 'L') would decode to a letter too if not bounded
  local itemTable = { fileOffset = 0, recordLength = 16, nameLength = 8, recordCount = 1 }

  local records = ItemTable.decode(rec, itemTable)
  Harness.assertEqual(#records[1].name, 8,
    "name must be exactly nameLength characters, never longer")
end)

Harness.test("ItemTable.decode: price is bytes 13-14 (0-based), little-endian u16", function()
  -- byte13=0x28, byte14=0x00 -> 40 (record 8's real "Cure" price).
  local rec0 = "\197\216\213\216\0\0\0\0" .. "\128\160\16\0\0\40\0\1"
  -- byte13=0x40, byte14=0x01 -> 320 (record 10's real "Ether" price) --
  -- exercises the little-endian high byte, not just a single-byte value.
  local rec1 = "\204\212\223\213\0\0\0\0" .. "\0\144\0\8\0\64\1\3"
  local rom = rec0 .. rec1
  local itemTable = { fileOffset = 0, recordLength = 16, nameLength = 8, recordCount = 2 }

  local records = ItemTable.decode(rom, itemTable)
  Harness.assertEqual(records[1].price, 40)
  Harness.assertEqual(records[2].price, 320)
end)

Harness.test("ItemTable.decode: mpCost is categoryByte AND 0x1F (found 2026-08-19, live-disassembled MP-deduction routine)", function()
  -- categoryByte=0x42 (record0) -> masked 0x02; categoryByte=0xA3
  -- (record1, exercises the upper bits being set/ignored) -> masked 0x03.
  local rec0 = "\197\216\213\216\0\0\0\0" .. "\66\16\20\0\0\0\0\1"
  local rec1 = "\204\212\223\213\0\0\0\0" .. "\163\16\0\0\0\0\0\2"
  local rom = rec0 .. rec1
  local itemTable = { fileOffset = 0, recordLength = 16, nameLength = 8, recordCount = 2 }

  local records = ItemTable.decode(rom, itemTable)
  Harness.assertEqual(records[1].mpCost, 2)
  Harness.assertEqual(records[2].mpCost, 3)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ItemTable.decode: real ROM decodes the known item/spell name sequence",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)
    Harness.assertEqual(#records, 59) -- extended 2026-08-15, see rom_profiles.lua's own doc comment

    -- Cross-check against docs/reverse-engineering/text.md's documented
    -- item list (first 8 slots -- consumable items).
    local expectedNames = {
      "Lebe", "Salb", "Blok", "Ruhe", "Flam", "Eis ", "Bliz", "Bomb",
    }
    for i, name in ipairs(expectedNames) do
      Harness.assertEqual(records[i].name, name,
        "record " .. (i - 1) .. " name")
    end

    -- The per-category ID byte (byte 15) is VERIFIED to reset to 0 right
    -- at the item/spell category boundary (rom-map.md "Item/spell table").
    -- categoryBoundaryRecord is the 0-based index of the first spell
    -- record; records[] is 1-based, so +1 to convert.
    Harness.assertEqual(records[profile.itemTable.categoryBoundaryRecord + 1].id, 1,
      "first spell record's id should restart the per-category counter at 1")
    Harness.assertEqual(records[profile.itemTable.categoryBoundaryRecord].id, 0,
      "last item record's id is the documented 0 boundary marker")
  end
)

Harness.testIfAvailable(
  "ItemTable.decode: real spell records (8-19) decode via the offset-1 fallback, found 2026-08-15",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)

    -- Real, live-verified spell names (see ItemTable.lua's own doc
    -- comment for the full disassembly trail) -- byte 0 of each of
    -- these records is a real, still-unexplained prefix byte, not
    -- part of the name, which is why the primary offset-0 decode
    -- comes back empty and the offset-1 fallback is needed.
    local expectedSpellNames = {
      [9] = "Lebe", [10] = "S-Lebe", [11] = "Magi", [12] = "S-Magi",
      [13] = "Elixier", [14] = "Salbe", [15] = "Auge", [16] = "Bewege",
      [17] = "Spruch", [18] = "Allheil", [19] = "Stille", [20] = "Schlaf",
    }
    for recordIndex1Based, name in pairs(expectedSpellNames) do
      Harness.assertEqual(records[recordIndex1Based].name, name,
        "record " .. (recordIndex1Based - 1) .. " spell name")
      Harness.assertTrue(records[recordIndex1Based].namePrefixByte ~= nil,
        "record " .. (recordIndex1Based - 1) .. " should report a real namePrefixByte")
    end

    -- Real, further elemental spells found past the previous 20-record
    -- boundary (also offset-1 decoded).
    Harness.assertEqual(records[23].name, "Flamme")
    Harness.assertEqual(records[24].name, "Lava")
    Harness.assertEqual(records[25].name, "Eis")
    Harness.assertEqual(records[26].name, "Frost")
    Harness.assertEqual(records[27].name, "Blitz")
    Harness.assertEqual(records[28].name, "Donner")

    -- Real, further consumable/treasure items found past the old
    -- boundary (offset-0 this time, same shape as records 0-7).
    Harness.assertEqual(records[29].name, "Bonbon")
    Harness.assertEqual(records[52].name, "Rubin")
    Harness.assertEqual(records[55].name, "Diamant")

    -- Real-ROM regression for the 2026-08-18 field-overrun fix: these
    -- two used to read " Spiegelne"/"OR-MdwDCne" (real name + 2 garbled
    -- characters bled in from the record's own categoryByte/stat
    -- bytes) before the name decode was bounded to the real 8-byte
    -- field. Both are now exactly 8 characters, matching the field
    -- width, with no trailing bleed-through.
    Harness.assertEqual(records[39].name, " Spiegel")
    Harness.assertEqual(records[41].name, "OR-MdwDC")
  end
)

Harness.testIfAvailable(
  "ItemTable.decode: real price field, 8 external gold-cost matches (found 2026-08-18)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)

    -- Cross-checked against a real, fetched Final Fantasy Adventure
    -- walkthrough (gamesurge.com, see docs/references.md and this
    -- module's own top-of-file 2026-08-18 doc comment) -- 8 of 8
    -- checkable records match exactly. Records 13-16 also form a clean
    -- +30g arithmetic progression, independent corroboration beyond the
    -- external source.
    local expectedPrices = {
      [9] = 40,   -- "Lebe" (Cure)
      [10] = 160, -- "S-Lebe" (X-Cure)
      [11] = 320, -- "Magi" (Ether) -- exercises the LE high byte
      [12] = 640, -- "S-Magi" (X-Ether) -- exercises the LE high byte
      [14] = 30,  -- "Salbe" (Pure)
      [15] = 60,  -- "Auge" (Eyedrop)
      [16] = 90,  -- "Bewege" (Soft)
      [17] = 120, -- "Spruch" (Moogle)
    }
    for recordIndex1Based, price in pairs(expectedPrices) do
      Harness.assertEqual(records[recordIndex1Based].price, price,
        "record " .. (recordIndex1Based - 1) .. " (" .. records[recordIndex1Based].name .. ") price")
    end

    -- Records 0-7 are the real castable Magic-menu spells (see this
    -- module's own 2026-08-19 doc comment -- NOT "found/thrown combat
    -- items" as this project's own earlier docs assumed), so they're
    -- never gold-priced -- price=0 is consistent with that real
    -- category, not a contradiction.
    for i = 1, 8 do
      Harness.assertEqual(records[i].price, 0,
        "record " .. (i - 1) .. " (" .. records[i].name .. ") should be unpriced")
    end
  end
)

Harness.testIfAvailable(
  "ItemTable.decode: real mpCost field, 8/8 external MP-cost matches for the castable spell records (found 2026-08-19)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)

    -- Cross-checked against the SAME external walkthrough this
    -- project's own price-field pass already used (gamesurge.com's
    -- Final Fantasy Adventure guide, "8 magic spells with MP cost":
    -- Cure 2/Heal 1/Sleep 1/Mute 1/Fire 1/Ice 2/Lightning 2/Nuke 3) --
    -- 8 of 8 records match exactly, in order. See this module's own
    -- top-of-file 2026-08-19 doc comment for the full live-
    -- disassembled ROM trace (bank 2 $718F-$71AB / $6660-$667E) this
    -- field is derived from.
    local expectedMpCost = {
      [1] = 2, -- "Lebe" (Cure)
      [2] = 1, -- "Salb" (Heal)
      [3] = 1, -- "Blok" (Sleep)
      [4] = 1, -- "Ruhe" (Mute)
      [5] = 1, -- "Flam" (Fire)
      [6] = 2, -- "Eis " (Ice)
      [7] = 2, -- "Bliz" (Lightning)
      [8] = 3, -- "Bomb" (Nuke)
    }
    for recordIndex1Based, mpCost in pairs(expectedMpCost) do
      Harness.assertEqual(records[recordIndex1Based].mpCost, mpCost,
        "record " .. (recordIndex1Based - 1) .. " (" .. records[recordIndex1Based].name .. ") mpCost")
    end

    -- Every non-spell record's masked byte reads 0 -- consistent with
    -- "this field doesn't apply here," not contradicting the read.
    for i = 9, #records do
      Harness.assertEqual(records[i].mpCost, 0,
        "record " .. (i - 1) .. " (" .. records[i].name .. ") should have no real mpCost")
    end
  end
)

Harness.testIfAvailable(
  "ItemTable.decode: a record that decodes at neither known offset honestly reports an empty name, not a guess",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)
    -- Real, live-confirmed unresolved gap (see rom_profiles.lua's own
    -- doc comment) -- record 33 (0-based) decodes empty at BOTH offset
    -- 0 and offset 1, so ItemTable.decode must NOT fabricate a name
    -- for it (unlike record 20, which decodes non-empty-but-garbled at
    -- offset 1 -- honestly returned as-is, not further filtered, since
    -- this project doesn't judge "looks like a real word" -- only
    -- "did a recognized byte sequence decode at all").
    Harness.assertEqual(records[34].name, "")
    Harness.assertEqual(records[34].namePrefixByte, nil)
  end
)

Harness.testIfAvailable(
  "ItemTable.groupByCategory: real categoryByte groups from the ROM (catalog plan Phase 2, 2026-08-15)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = ItemTable.decode(romData, profile.itemTable)
    local groups = ItemTable.groupByCategory(records)

    -- Real, live-decoded counts (see ItemTable.lua's own
    -- `groupByCategory` doc comment) -- locks in the exact grouping so
    -- a future table-boundary extension shows up as a clear, honest
    -- test failure instead of silently drifting.
    local expected = {
      [0] = 22, [64] = 13, [65] = 4, [66] = 3, [67] = 1, [128] = 16,
    }
    local totalRecords = 0
    for _, g in ipairs(groups) do
      Harness.assertEqual(g.count, expected[g.categoryByte],
        "categoryByte " .. g.categoryByte .. " count")
      Harness.assertEqual(#g.records, g.count)
      totalRecords = totalRecords + g.count
    end
    Harness.assertEqual(#groups, 6)
    Harness.assertEqual(totalRecords, #records, "every real record must land in exactly one group")

    -- sizeClass is a plain size threshold (>=5), not a claimed real
    -- category name -- see the doc comment for why.
    Harness.assertEqual(groups[1].sizeClass, "group") -- categoryByte 0, count 22
    Harness.assertEqual(groups[3].sizeClass, "single") -- categoryByte 65, count 4
    Harness.assertEqual(groups[5].sizeClass, "single") -- categoryByte 67, count 1
    Harness.assertEqual(groups[6].sizeClass, "group") -- categoryByte 128, count 16

    -- Groups come back sorted ascending by the real categoryByte.
    for i = 2, #groups do
      Harness.assertTrue(groups[i].categoryByte > groups[i - 1].categoryByte)
    end
  end
)

if romData then
  print("(ItemTable ROM-dependent tests ran against a real dev ROM)")
end
