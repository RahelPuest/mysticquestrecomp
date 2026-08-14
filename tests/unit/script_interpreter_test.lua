local Harness = require("tests.harness")
local ScriptInterpreter = require("src.scripting.ScriptInterpreter")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local StandardScriptHandlers = require("src.scripting.StandardScriptHandlers")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

local function makeOpcodeTable(overrides)
  -- 256 entries, all real-shaped default handler addresses unless
  -- overridden -- mirrors the real ROM's own "mostly default, a few
  -- real opcodes" shape without needing the actual ROM for pure tests.
  local entries = {}
  for i = 1, 256 do
    entries[i] = ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS
  end
  for opcode, addr in pairs(overrides or {}) do
    entries[opcode + 1] = addr
  end
  return entries
end

Harness.test("ScriptInterpreter.fetch: real $3727 port -- reads the byte at cursor, advances by 1", function()
  local stream = { 0xFE, 0x10, 0x04 }
  local opcode, nextCursor = ScriptInterpreter.fetch(stream, 1)
  Harness.assertEqual(opcode, 0xFE)
  Harness.assertEqual(nextCursor, 2)
  local opcode2, nextCursor2 = ScriptInterpreter.fetch(stream, nextCursor)
  Harness.assertEqual(opcode2, 0x10)
  Harness.assertEqual(nextCursor2, 3)
end)

Harness.test("ScriptInterpreter.fetch: fails loudly when the cursor runs off the end of the stream", function()
  local stream = { 0x01 }
  Harness.assertTrue(not pcall(ScriptInterpreter.fetch, stream, 2))
end)

-- CORRECTED (2026-08-13, "bau den interpreter ein"): `fetch`'s own bounds
-- check used to be `cursor <= #stream`, which only works for a plain
-- 1-based array -- see RomScriptStream.lua, which returns a sparse proxy
-- table keyed by real CPU address (e.g. 0x470F), where `#stream` is
-- always 0 regardless of real content. This regression test uses a
-- SPARSE, non-1-based table directly (no RomScriptStream dependency
-- needed to prove the point) to lock in that `fetch` now works correctly
-- against one.
Harness.test("ScriptInterpreter.fetch: works against a sparse, non-1-based table (e.g. a live ROM-backed stream)", function()
  local sparseStream = { [0x470F] = 0x3C, [0x4710] = 0xFE }
  local opcode, nextCursor = ScriptInterpreter.fetch(sparseStream, 0x470F)
  Harness.assertEqual(opcode, 0x3C)
  Harness.assertEqual(nextCursor, 0x4710)
  local opcode2 = ScriptInterpreter.fetch(sparseStream, nextCursor)
  Harness.assertEqual(opcode2, 0xFE)
end)

Harness.test("ScriptInterpreter.fetch: still fails loudly on a sparse table when the address is genuinely missing", function()
  local sparseStream = { [0x470F] = 0x3C }
  Harness.assertTrue(not pcall(ScriptInterpreter.fetch, sparseStream, 0x4710))
end)

Harness.test("ScriptInterpreter.new: fails loudly on a table that isn't exactly 256 entries", function()
  Harness.assertTrue(not pcall(ScriptInterpreter.new, { 1, 2, 3 }))
end)

Harness.test("ScriptInterpreter:step: a real default (unassigned) opcode is a genuine no-op that just advances", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable())
  local stream = { 0x05, 0x99 } -- opcode 5, no handler registered, no operands consumed
  local nextCursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0x05)
  Harness.assertEqual(kind, "default")
  Harness.assertEqual(nextCursor, 2) -- only the opcode byte itself was consumed
end)

Harness.test("ScriptInterpreter:step: fails loudly on a real, decoded-address-but-unregistered opcode", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFE] = 0x0E69 }))
  local stream = { 0xFE, 0x10 }
  local ok, err = pcall(function() interp:step(stream, 1) end)
  Harness.assertTrue(not ok, "expected step() to raise for an unregistered real handler")
  Harness.assertTrue(tostring(err):find("0xfe") ~= nil or tostring(err):find("0xFE") ~= nil,
    "expected the error message to name the real opcode")
end)

Harness.test("ScriptInterpreter:step: a registered handler runs and its returned cursor is used", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFE] = 0x0E69 }))
  local seen = {}
  interp:registerHandler(0x0E69, function(stream, cursor)
    seen[#seen + 1] = stream[cursor]
    return cursor + 1 -- consumed one real operand byte
  end)
  local stream = { 0xFE, 0x10, 0x99 }
  local nextCursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0xFE)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(seen[1], 0x10)
  Harness.assertEqual(nextCursor, 3)
end)

Harness.test("ScriptInterpreter: a real multi-step run walks a whole stream (default opcodes + one real handler)", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFE] = 0x0E69 }))
  local messages = {}
  interp:registerHandler(0x0E69, function(stream, cursor)
    messages[#messages + 1] = stream[cursor]
    return cursor + 1
  end)
  -- A real-shaped mini "script": no-op, no-op, display-message(16), no-op.
  local stream = { 0x01, 0x02, 0xFE, 16, 0x03 }
  local cursor = 1
  while cursor <= #stream do
    cursor = interp:step(stream, cursor)
  end
  Harness.assertEqual(#messages, 1)
  Harness.assertEqual(messages[1], 16)
end)

Harness.test("ScriptInterpreter:step: a handler returning nil halts -- cursor unchanged, kind 'halted'", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = 0x38E6 }))
  local calls = 0
  interp:registerHandler(0x38E6, function(_stream, _cursor)
    calls = calls + 1
    return nil -- real "not ready yet" signal
  end)

  local stream = { 0xFF, 0x99 }
  local nextCursor, opcode, kind = interp:step(stream, 1)
  Harness.assertEqual(opcode, 0xFF)
  Harness.assertEqual(kind, "halted")
  Harness.assertEqual(nextCursor, 1) -- unchanged: the ORIGINAL cursor, not past the opcode byte
  Harness.assertEqual(calls, 1)
end)

Harness.test("ScriptInterpreter:step: a halted opcode re-dispatches the same handler on the next call", function()
  local interp = ScriptInterpreter.new(makeOpcodeTable({ [0xFF] = 0x38E6 }))
  local ticks = 0
  interp:registerHandler(0x38E6, function(_stream, cursor)
    ticks = ticks + 1
    if ticks < 3 then
      return nil -- halt twice
    end
    return cursor -- then release on the 3rd real tick
  end)

  local stream = { 0xFF, 0xFE }
  local cursor = 1
  local kind
  for _ = 1, 3 do
    cursor, _, kind = interp:step(stream, cursor)
  end
  Harness.assertEqual(ticks, 3)
  Harness.assertEqual(kind, "handled")
  Harness.assertEqual(cursor, 2) -- finally advanced past the 0xFF opcode byte
  Harness.assertEqual(stream[cursor], 0xFE)
end)

-- --- ROM-dependent: the real interpreter walking REAL ROM bytes -----------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ScriptInterpreter: the real, decoded interpreter correctly walks the ACTUAL 'Kaempfe!' opcode+operand bytes from the ROM",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local opcodeEntries = require("src.import.ScriptOpcodeTable").decode(romData, profile.scriptOpcodeTable)
    local interp = ScriptInterpreter.new(opcodeEntries)

    local received = nil
    interp:registerHandler(ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS,
      StandardScriptHandlers.message(function(id) received = id end))

    -- Real ROM bytes at file offset 0x346F7-0x346F8 (live-confirmed:
    -- opcode 0xFE immediately followed by the real messageID operand
    -- 0x10/16, see rom-map.md). Read directly from the ROM, not
    -- transcribed by hand, so a future ROM/offset drift would fail
    -- this test rather than silently going stale.
    local fileOffset = 0x346F7
    local stream = { romData:byte(fileOffset + 1), romData:byte(fileOffset + 2) }
    Harness.assertEqual(stream[1], 0xFE)
    Harness.assertEqual(stream[2], 0x10)

    local nextCursor, opcode, kind = interp:step(stream, 1)
    Harness.assertEqual(opcode, 0xFE)
    Harness.assertEqual(kind, "handled")
    Harness.assertEqual(received, 16)
    Harness.assertEqual(nextCursor, 3)
  end
)
