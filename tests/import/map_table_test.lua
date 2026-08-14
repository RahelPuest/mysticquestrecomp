local Harness = require("tests.harness")
local MapTable = require("src.import.MapTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

-- Synthetic-data tests: exercise the table-shape decoder against
-- hand-built bytes so the parsing logic itself is verified independent of
-- any real ROM, per the "headlessly testable" rule.
Harness.test("MapTable.decode: parses a 2-record synthetic table", function()
  -- Build a tiny fake "bank" (bankFileStart = 0) with:
  --   pointer table at file offset 0: 4 pointers (2 records)
  --   record 0 header @ $4010 (3 bytes: 0x05 0x00 0xFF)
  --   record 0 data   @ $4013 (4 bytes: 0x01 0x02 0x03 0x04)
  --   record 1 header @ $4017 (3 bytes: 0x09 0x00 0xFF)
  --   record 1 data   @ $401A (2 bytes: 0xAA 0xBB) -- length unknown (last record)
  local function u16le(v) return string.char(v % 256, math.floor(v / 256)) end
  local ptrTable = u16le(0x4010) .. u16le(0x4013) .. u16le(0x4017) .. u16le(0x401A)
  -- Pad from end of pointer table (file offset 8) out to file offset 0x10
  -- (where header 0 starts) with filler bytes.
  local padding = string.rep("\0", 0x10 - #ptrTable)
  local body = "\5\0\255" .. "\1\2\3\4" .. "\9\0\255" .. "\170\187"
  local rom = ptrTable .. padding .. body

  local mapTable = {
    pointerTableFileOffset = 0,
    recordCount = 2,
    bankFileStart = 0,
    tilesetFileOffset = 0,
  }
  local records = MapTable.decode(rom, mapTable)
  Harness.assertEqual(#records, 2)

  Harness.assertEqual(records[1].header, "\5\0\255")
  Harness.assertEqual(records[1].blob, "\1\2\3\4")

  Harness.assertEqual(records[2].header, "\9\0\255")
  Harness.assertEqual(records[2].blob, nil, "last record's blob end is unknown")
end)

Harness.test("MapTable.decode: fails loudly on a missing header terminator", function()
  local function u16le(v) return string.char(v % 256, math.floor(v / 256)) end
  local ptrTable = u16le(0x4004) .. u16le(0x4004 + 70)
  local rom = ptrTable .. string.rep("\1", 100) -- no 0xFF anywhere
  local mapTable = {
    pointerTableFileOffset = 0,
    recordCount = 1,
    bankFileStart = 0,
  }
  local ok = pcall(MapTable.decode, rom, mapTable)
  Harness.assertTrue(not ok, "expected decode to raise on an unterminated header")
end)

Harness.test("MapTable.blobToTileIndices: converts bytes to a plain index array", function()
  local indices = MapTable.blobToTileIndices("\0\1\254\255")
  Harness.assertEqual(#indices, 4)
  Harness.assertEqual(indices[1], 0)
  Harness.assertEqual(indices[2], 1)
  Harness.assertEqual(indices[3], 254)
  Harness.assertEqual(indices[4], 255)
end)

-- Real room-decompression scheme (VERIFIED this pass -- see MapTable.lua's
-- module doc comment): high-bit-set byte = "repeat byte&0x7F, rleLength
-- times"; anything else is one literal tile index.
Harness.test("MapTable.rleDecode: literal bytes (no high bit) pass through 1:1", function()
  local indices = MapTable.rleDecode("\1\2\3", 3)
  Harness.assertEqual(#indices, 3)
  Harness.assertEqual(indices[1], 1)
  Harness.assertEqual(indices[2], 2)
  Harness.assertEqual(indices[3], 3)
end)

Harness.test("MapTable.rleDecode: high-bit byte expands to rleLength copies of byte&0x7F", function()
  local indices = MapTable.rleDecode("\145", 3) -- 0x91 = 0x80 | 0x11
  Harness.assertEqual(#indices, 3)
  Harness.assertEqual(indices[1], 0x11)
  Harness.assertEqual(indices[2], 0x11)
  Harness.assertEqual(indices[3], 0x11)
end)

Harness.test("MapTable.rleDecode: mixes literal and repeated runs in one blob", function()
  -- 0x91 0x91 0x91 0x11 (record 0's real first 4 blob bytes, see the test
  -- below) should RLE-decode to three 0x11s (from the two 0x91 runs) then
  -- one literal 0x11.
  local indices = MapTable.rleDecode("\145\145\145\17", 3)
  Harness.assertEqual(#indices, 10)
  for i = 1, 9 do
    Harness.assertEqual(indices[i], 0x11, "index " .. i)
  end
  Harness.assertEqual(indices[10], 0x11)
end)

Harness.test("MapTable.readMapHeader: parses the 4-byte per-map header", function()
  local rom = "\0\3\16\16" -- encodingMode=0 (RLE), rleLength=3, 16x16 grid
  local header = MapTable.readMapHeader(rom, { bankFileStart = 0 })
  Harness.assertEqual(header.encodingMode, 0)
  Harness.assertEqual(header.rleLength, 3)
  Harness.assertEqual(header.gridHeight, 16)
  Harness.assertEqual(header.gridWidth, 16)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "MapTable.decode: real ROM's 256 records all have valid 0xFF-terminated headers",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = MapTable.decode(romData, profile.mapTable)
    Harness.assertEqual(#records, 256)
    for i, rec in ipairs(records) do
      Harness.assertTrue(rec.header:byte(#rec.header) == 0xFF,
        "record " .. i .. " header should end in 0xFF")
      if i < #records then
        Harness.assertTrue(rec.blob ~= nil and #rec.blob >= 32 and #rec.blob <= 74,
          "record " .. i .. " blob length should be in the observed 32-74 range, got " ..
          tostring(rec.blob and #rec.blob))
      end
    end
  end
)

Harness.testIfAvailable(
  "MapTable.decode: first record's blob matches the documented reverse-engineering finding",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local records = MapTable.decode(romData, profile.mapTable)
    -- Cross-check against docs/reverse-engineering/rom-map.md's worked
    -- example (record 0: header 76 00 33 80 03 ff, blob starts 91 91 91 11...).
    Harness.assertEqual(records[1].header, "\118\0\51\128\3\255")
    local blob = records[1].blob
    Harness.assertEqual(blob:byte(1), 0x91)
    Harness.assertEqual(blob:byte(2), 0x91)
    Harness.assertEqual(blob:byte(3), 0x91)
    Harness.assertEqual(blob:byte(4), 0x11)
    Harness.assertEqual(#blob, 50)
  end
)

Harness.testIfAvailable(
  "MapTable.readMapHeader: real ROM's per-map header is the RLE breakthrough's [0,3,16,16]",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local header = MapTable.readMapHeader(romData, profile.mapTable)
    Harness.assertEqual(header.encodingMode, 0)
    Harness.assertEqual(header.rleLength, 3)
    Harness.assertEqual(header.gridHeight, 16)
    Harness.assertEqual(header.gridWidth, 16)
    -- The whole reason this header mattered: gridHeight*gridWidth should
    -- equal the independently-discovered 256-record count exactly.
    Harness.assertEqual(header.gridHeight * header.gridWidth, profile.mapTable.recordCount)
  end
)

Harness.testIfAvailable(
  "MapTable.decodeRoomTiles: with the real header's rleLength, ALL 255 records decode to exactly 80 tiles (20x4)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    for i = 1, 255 do
      local tiles, header = MapTable.decodeRoomTiles(romData, profile.mapTable, i)
      Harness.assertEqual(#tiles, 80,
        "record " .. i .. " should RLE-decode to exactly 80 tiles with rleLength=" ..
        tostring(header.rleLength))
    end
  end
)

if romData then
  print("(MapTable ROM-dependent tests ran against a real dev ROM)")
end
