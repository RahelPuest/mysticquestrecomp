local Harness = require("tests.harness")
local CutTransitionInterpreter = require("src.scripting.CutTransitionInterpreter")
local DevRomLocator = require("tests.dev_rom_locator")

local romData = DevRomLocator.find()

Harness.test("CutTransitionInterpreter.new: fails loudly for a transition with no real, live-confirmed entry point", function()
  -- fifthRoomToSixthRoom is a plausible-sounding real transition name
  -- that has genuinely NOT been live-traced (sixthRoom is only reached
  -- via fourthRoom's own west corridor, and even that one is an
  -- engineering-choice static exit, not a real ROM cut -- see
  -- rom_profiles.lua's own doc comment on fourthRoom.exits[2]) --
  -- deliberately NOT in ENTRY_POINTS, on purpose.
  local ok, err = pcall(CutTransitionInterpreter.new, "fake-rom-bytes", "fifthRoomToSixthRoom", {})
  Harness.assertTrue(not ok)
  Harness.assertTrue(tostring(err):match("no real, live%-confirmed entry point") ~= nil,
    "expected a clear error naming the missing entry point, got: " .. tostring(err))
end)

Harness.testIfAvailable(
  "CutTransitionInterpreter.new: thirdRoomToFourthRoom starts at the real, live-traced bank 14, CPU $42F6",
  romData ~= nil,
  "no development ROM found",
  function()
    local interp = CutTransitionInterpreter.new(romData, "thirdRoomToFourthRoom", {})
    Harness.assertEqual(interp.bank, 14)
    Harness.assertEqual(interp.cursor, 0x42F6)
    Harness.assertEqual(interp.done, false)
    Harness.assertEqual(interp.captured, nil)
  end
)

Harness.testIfAvailable(
  "CutTransitionInterpreter:tick: a single real tick captures the exact real (roomSelector, subIndexByte) pair, then deliberately halts",
  romData ~= nil,
  "no development ROM found",
  function()
    local interp = CutTransitionInterpreter.new(romData, "thirdRoomToFourthRoom", {})
    interp:tick()

    -- Real, live-confirmed values (see this module's own doc comment):
    -- the static record at bank 14 file 0x382f4 is
    -- `00 05 F4 01 57 0E 0C 00 0B` -- roomSelector=1, subIndexByte=87
    -- (0x57) -- CutTransitionTable.lua's own already-tested decode of
    -- this exact record independently agrees.
    Harness.assertTrue(interp.captured ~= nil, "expected the real peek to have fired on the first tick")
    Harness.assertEqual(interp.captured.roomSelector, 1)
    Harness.assertEqual(interp.captured.subIndexByte, 87)
    Harness.assertEqual(interp:capturedRoomSelector(), 1)

    -- Deliberate, documented halt -- not a crash, not an undecoded-opcode error.
    Harness.assertEqual(interp.done, true)
    Harness.assertEqual(interp.runtime.stopped, false)
    Harness.assertEqual(interp.runtime.stopError, nil)

    -- Further ticks are safe no-ops (matches BossSequenceInterpreter's
    -- own "self.done -> return" convention).
    local cursorBefore = interp.cursor
    interp:tick()
    Harness.assertEqual(interp.cursor, cursorBefore)
  end
)

Harness.testIfAvailable(
  "CutTransitionInterpreter: cross-checks byte-exact against CutTransitionTable's own independently-decoded static record",
  romData ~= nil,
  "no development ROM found",
  function()
    local CutTransitionTable = require("src.import.CutTransitionTable")
    local records = CutTransitionTable.scanLandingRecords(romData)
    local thirdToFourth
    for _, r in ipairs(records) do
      if r.pixelX == 120 and r.pixelY == 112 and r.roomSelector == 1 and r.subIndexByte == 87 then
        thirdToFourth = r
        break
      end
    end
    Harness.assertTrue(thirdToFourth ~= nil, "expected CutTransitionTable's own already-tested thirdRoom->fourthRoom record")

    local interp = CutTransitionInterpreter.new(romData, "thirdRoomToFourthRoom", {})
    interp:tick()
    -- Two completely independent real methods (a static byte-pattern
    -- scan of the whole ROM vs. a live ScriptRuntime execution from a
    -- live-traced entry point) land on the exact same real values --
    -- the decisive cross-check this whole module exists to provide.
    Harness.assertEqual(interp.captured.roomSelector, thirdToFourth.roomSelector)
    Harness.assertEqual(interp.captured.subIndexByte, thirdToFourth.subIndexByte)
  end
)

Harness.testIfAvailable(
  "CutTransitionInterpreter.new: fourthRoomToFifthRoom starts at the real, live-traced bank 14, CPU $4C84",
  romData ~= nil,
  "no development ROM found",
  function()
    local interp = CutTransitionInterpreter.new(romData, "fourthRoomToFifthRoom", {})
    Harness.assertEqual(interp.bank, 14)
    Harness.assertEqual(interp.cursor, 0x4C84)
    Harness.assertEqual(interp.done, false)
    Harness.assertEqual(interp.captured, nil)
  end
)

Harness.testIfAvailable(
  "CutTransitionInterpreter:tick: fourthRoomToFifthRoom captures the exact real (roomSelector, subIndexByte) pair, then deliberately halts",
  romData ~= nil,
  "no development ROM found",
  function()
    local interp = CutTransitionInterpreter.new(romData, "fourthRoomToFifthRoom", {})
    interp:tick()

    -- Real, live-traced values (see ENTRY_POINTS.fourthRoomToFifthRoom's
    -- own doc comment): the peek at bank 14 file 0x38c85 read (B,C) =
    -- (4,80) -- roomSelector=4 (independently cross-confirmed via the
    -- shared $026DC subroutine), subIndexByte=80.
    Harness.assertTrue(interp.captured ~= nil, "expected the real peek to have fired on the first tick")
    Harness.assertEqual(interp.captured.roomSelector, 4)
    Harness.assertEqual(interp.captured.subIndexByte, 80)
    Harness.assertEqual(interp:capturedRoomSelector(), 4)

    Harness.assertEqual(interp.done, true)
    Harness.assertEqual(interp.runtime.stopped, false)
    Harness.assertEqual(interp.runtime.stopError, nil)

    local cursorBefore = interp.cursor
    interp:tick()
    Harness.assertEqual(interp.cursor, cursorBefore)
  end
)

Harness.testIfAvailable(
  "CutTransitionInterpreter: fourthRoomToFifthRoom cross-checks byte-exact against CutTransitionTable's own independently-decoded static record",
  romData ~= nil,
  "no development ROM found",
  function()
    local CutTransitionTable = require("src.import.CutTransitionTable")
    local records = CutTransitionTable.scanLandingRecords(romData)
    local fourthToFifth
    for _, r in ipairs(records) do
      if r.pixelX == 136 and r.pixelY == 32 and r.roomSelector == 4 and r.subIndexByte == 80 then
        fourthToFifth = r
        break
      end
    end
    Harness.assertTrue(fourthToFifth ~= nil, "expected CutTransitionTable's own already-tested fourthRoom->fifthRoom record")

    local interp = CutTransitionInterpreter.new(romData, "fourthRoomToFifthRoom", {})
    interp:tick()
    Harness.assertEqual(interp.captured.roomSelector, fourthToFifth.roomSelector)
    Harness.assertEqual(interp.captured.subIndexByte, fourthToFifth.subIndexByte)
  end
)

if romData then
  print("(CutTransitionInterpreter ROM-dependent tests ran against a real dev ROM)")
end
