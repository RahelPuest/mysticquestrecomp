local Harness = require("tests.harness")
local MapTable = require("src.import.MapTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
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

Harness.testIfAvailable(
  "MapTable.decode: the per-record header field is NOT a per-record metatile-table pointer (2026-08-14, falsified hypothesis, kept as a regression guard)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- NOW UNDERSTOOD WHY (2026-08-14, same day, direct follow-up
    -- question "findest du in den headern auch informationen dazu
    -- welche tiles zu den räumen gehören"): this "header" field is
    -- itself a MISNOMER -- decoding it as real script bytecode (this
    -- project's own already-built ScriptInterpreter/ScriptOpcodeTable)
    -- shows it resolves to real, already-catalogued ROM handler
    -- addresses (the documented "~70-opcode actor action" family,
    -- events.md's "Back to the primary table" section) -- i.e. it's a
    -- genuine per-room EVENT SCRIPT, not tileset metadata at all. See
    -- MapTable.lua's own "NAMING CORRECTED" doc comment for the full
    -- trace. This test's own conclusion (not a metatile pointer)
    -- stands, now with a real, understood root cause instead of just
    -- an empirical negative.
    --
    -- Direct follow-up to a real user report ("die sind bei allen
    -- ausser den bekannten total off") that the room-catalog export's
    -- tile assignment looks wrong for every bank-5/bank-6 record
    -- except the 6 already-confirmed unknownRoomA ones (roomSelector
    -- 8-13, all real-confirmed to share metatile table file 0x20938
    -- via the ALREADY-VERIFIED roomSelectorTable's own $D392/$D393 DE
    -- field -- a live-traced hardware fact, not a guess).
    --
    -- A genuinely new lead was tried: `MapTable.decode`'s own per-
    -- record `header` field (a short, 0xFF-terminated blob before each
    -- data blob) had never been interpreted before. Record 9 is part
    -- of the CONFIRMED unknownRoomA family (known-good metatile table
    -- 0x20938) and happens to have a 6-byte header -- if its own
    -- trailing 16-bit field were a per-record metatile-table pointer,
    -- it MUST resolve to 0x20938. It does NOT (resolves to 0x20381
    -- instead) -- and a full scan of all 256 bank-5 records' own
    -- headers found ZERO whose trailing u16 resolves to 0x20938 at
    -- all. This decisively RULES OUT that hypothesis.
    --
    -- Kept as a permanent regression test, not just a doc note: if
    -- someone re-derives this exact same (wrong) idea in the future,
    -- this test fails loudly and points straight at this record's own
    -- already-confirmed ground truth, instead of silently re-shipping
    -- the same already-falsified guess as a "fix".
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local KNOWN_GOOD_METATILE_TABLE = profile.roomFloorLayoutPipeline.unknownRoomACandidates.metatileTableFileOffset
    Harness.assertEqual(KNOWN_GOOD_METATILE_TABLE, 0x20938)

    local records = MapTable.decode(romData, profile.mapTable)
    local record9 = records[9 + 1] -- roomSelector 9, part of the confirmed unknownRoomA family
    Harness.assertEqual(#record9.header, 6,
      "record 9's own real header shape changed -- re-check this test's own assumptions before trusting its conclusion")
    local trailingU16 = record9.header:byte(4) + record9.header:byte(5) * 256
    local candidateTable = 0x20000 + trailingU16
    Harness.assertTrue(candidateTable ~= KNOWN_GOOD_METATILE_TABLE,
      "record 9's header-derived candidate now MATCHES the known-good metatile table -- " ..
      "the 'header = per-record metatile pointer' hypothesis may no longer be falsified, " ..
      "re-investigate rather than trusting this test's own stale conclusion")

    -- The broader claim from the same investigation: scan every bank-5
    -- record with a long-enough header and confirm NONE resolve to the
    -- known-good table (a full negative result, not just record 9).
    local hits = 0
    for i = 0, profile.mapTable.recordCount - 1 do
      local r = records[i + 1]
      if #r.header >= 6 then
        local u16 = r.header:byte(#r.header - 2) + r.header:byte(#r.header - 1) * 256
        if 0x20000 + u16 == KNOWN_GOOD_METATILE_TABLE then
          hits = hits + 1
        end
      end
    end
    Harness.assertEqual(hits, 0,
      "expected zero bank-5 records whose header resolves to the known-good metatile table " ..
      "(if this changes, the header-as-metatile-pointer hypothesis may be worth re-examining)")
  end
)

-- Synthetic tests: exercise MapTable.tryDecodeActorAction against
-- hand-built bytes, independent of any real ROM, per this project's
-- own "headlessly testable" rule.
Harness.test("MapTable.tryDecodeActorAction: extracts group/action from a real-shaped handler at the first opcode", function()
  -- Real bytes, real shape (bank5 record 0's own actual handler at
  -- $152C, live-verified 2026-08-14): CALL $28C2 / ADD A,6 / LD C,A /
  -- LD A,$1C / CALL $2879 / RET, placed at a synthetic handler address.
  local HANDLER_ADDR = 0x0100
  local rom = string.rep("\0", HANDLER_ADDR) ..
    "\xCD\xC2\x28\xC6\x06\x4F\x3E\x1C\xCD\x79\x28\xC9"
  local opcodeEntries = {}
  for i = 1, 256 do opcodeEntries[i] = 0x3FFF end -- filler, never DEFAULT
  opcodeEntries[0x76 + 1] = HANDLER_ADDR
  local header = "\x76\x00\xFF"
  local result = MapTable.tryDecodeActorAction(rom, header, opcodeEntries)
  Harness.assertTrue(result ~= nil, "expected a real (group,action) match")
  Harness.assertEqual(result.group, 0x06)
  Harness.assertEqual(result.action, 0x1C)
end)

Harness.test("MapTable.tryDecodeActorAction: falls through to the SECOND byte when the first is the real confirmed no-op", function()
  local HANDLER_ADDR = 0x0200
  local rom = string.rep("\0", HANDLER_ADDR) ..
    "\xCD\xC2\x28\xC6\x04\x4F\x3E\x04\xCD\x79\x28\xC9"
  local opcodeEntries = {}
  for i = 1, 256 do opcodeEntries[i] = 0x3FFF end
  opcodeEntries[0x7C + 1] = ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS
  opcodeEntries[0x00 + 1] = HANDLER_ADDR
  local header = "\x7C\x00\xFF"
  local result = MapTable.tryDecodeActorAction(rom, header, opcodeEntries)
  Harness.assertTrue(result ~= nil, "expected a real (group,action) match via the second byte")
  Harness.assertEqual(result.group, 0x04)
  Harness.assertEqual(result.action, 0x04)
end)

Harness.test("MapTable.tryDecodeActorAction: returns nil (not a fabricated default) when neither byte matches the real pattern", function()
  local opcodeEntries = {}
  for i = 1, 256 do opcodeEntries[i] = 0x3FFF end
  local rom = string.rep("\0", 0x4000) -- $3FFF's own bytes: all zero, never matches
  local header = "\x00\xFF" -- opcode 0 -> handler $3FFF, not DEFAULT, doesn't match
  local result = MapTable.tryDecodeActorAction(rom, header, opcodeEntries)
  Harness.assertTrue(result == nil, "expected nil, not a guessed/fabricated match")
end)

Harness.testIfAvailable(
  "MapTable.tryDecodeActorAction: real bank-5 record 0 resolves to the SAME (group,action) already live-verified this pass",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    local records = MapTable.decode(romData, profile.mapTable)
    local record0 = records[0 + 1]
    local result = MapTable.tryDecodeActorAction(romData, record0.header, opcodeEntries)
    Harness.assertTrue(result ~= nil, "expected bank-5 record 0's own real header to resolve")
    Harness.assertEqual(result.group, 0x06)
    Harness.assertEqual(result.action, 0x1C)
  end
)

if romData then
  print("(MapTable ROM-dependent tests ran against a real dev ROM)")
end
