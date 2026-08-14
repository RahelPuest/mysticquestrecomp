local Harness = require("tests.harness")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local DevRomLocator = require("tests.dev_rom_locator")

Harness.test("ScriptOpcodeTable.decode: parses a synthetic 3-entry table", function()
  -- LE pairs: 0x1234, 0x5678, 0x0e69
  local rom = "\52\18\120\86\105\14"
  local scriptOpcodeTable = { fileOffset = 0, recordCount = 3 }
  local entries = ScriptOpcodeTable.decode(rom, scriptOpcodeTable)
  Harness.assertEqual(#entries, 3)
  Harness.assertEqual(entries[1], 0x1234)
  Harness.assertEqual(entries[2], 0x5678)
  Harness.assertEqual(entries[3], 0x0E69)
end)

-- --- ROM-dependent tests -------------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "ScriptOpcodeTable.decode: real ROM's 256-entry table, live-verified opcodes 0x04 and 0xFE",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(#entries, 256)

    -- Real, live-confirmed values (see rom-map.md's own writeup): a
    -- write-watchpoint on $D85A caught function 51 (bank 2) returning
    -- these EXACT addresses for these EXACT opcodes, live, twice.
    Harness.assertEqual(entries[0x04 + 1], 0x333D)
    Harness.assertEqual(entries[0xFE + 1], ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS)
    Harness.assertEqual(ScriptOpcodeTable.MESSAGE_HANDLER_ADDRESS, 0x0E69)

    -- Real, live-confirmed: opcode 0xFF's own primary-table entry is
    -- the real `$38E6` sub-dispatch entry point (independently
    -- cross-checked against the disassembly, see
    -- SUBTABLE_DISPATCH_HANDLER_ADDRESS's own doc comment).
    Harness.assertEqual(entries[0xFF + 1], ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS)
    Harness.assertEqual(ScriptOpcodeTable.SUBTABLE_DISPATCH_HANDLER_ADDRESS, 0x38E6)

    -- Real, live-confirmed: opcode 0xF0's own primary-table entry is
    -- the real `$3C04` "hands off into 0xFF's own sub-opcode 3"
    -- shortcut (see START_TEXTBOX_WAIT_HANDLER_ADDRESS's own doc
    -- comment for the full byte-for-byte disassembly).
    Harness.assertEqual(entries[0xF0 + 1], ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS)
    Harness.assertEqual(ScriptOpcodeTable.START_TEXTBOX_WAIT_HANDLER_ADDRESS, 0x3C04)

    -- Real, live-confirmed (2026-08-12, opcode-frequency-scan follow-up):
    -- the sound/timing-parameter pair, the fixed trigger-event opcode,
    -- and the typewriter-cursor-command opcode -- each cross-checked
    -- against the real primary table's own entries.
    Harness.assertEqual(entries[0xF8 + 1], ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS)
    Harness.assertEqual(entries[0xF9 + 1], ScriptOpcodeTable.SOUND_PARAM_2_HANDLER_ADDRESS)
    Harness.assertEqual(entries[0xE0 + 1], ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS)
    Harness.assertEqual(entries[0x03 + 1], ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS)
    Harness.assertEqual(ScriptOpcodeTable.SOUND_PARAM_1_HANDLER_ADDRESS, 0x119B)
    Harness.assertEqual(ScriptOpcodeTable.SOUND_PARAM_2_HANDLER_ADDRESS, 0x1194)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS, 0x0FB4)
    Harness.assertEqual(ScriptOpcodeTable.TYPEWRITER_COMMAND_HANDLER_ADDRESS, 0x332F)

    -- Real, live-confirmed: the 7-opcode "actor flag/state" family
    -- (see ACTOR_ACTION_HANDLER_ADDRESS_*/QUEUED_ACTION_HANDLER_ADDRESS_*'s
    -- own doc comments for the full disassembled chain).
    local actorActionOpcodes = {
      [0x10] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10,
      [0x20] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_20,
      [0x25] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_25,
      [0x30] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_30,
      [0x7B] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_7B,
      [0x38] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_38,
      [0x78] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_78,
    }
    for opcode, addr in pairs(actorActionOpcodes) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_10, 0x125C)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_20, 0x12D0)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_25, 0x130C)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_30, 0x1344)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_7B, 0x157C)
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_38, 0x138C)
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_78, 0x155C)

    -- Real, live-confirmed: opcode 0x00's own real "script continuation
    -- queue gate" handler (see QUEUE_GATE_HANDLER_ADDRESS's own doc
    -- comment for the full disassembled chain -- this session's own
    -- single largest resolved blocker, 275/1357 real scripts).
    Harness.assertEqual(entries[0x00 + 1], ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS)
    Harness.assertEqual(ScriptOpcodeTable.QUEUE_GATE_HANDLER_ADDRESS, 0x3297)

    -- Real, live-confirmed (round 2, "mach erstmal 2"): 9 more real
    -- opcodes found using the EXACT SAME already-solved actor-flag/
    -- state family, plus one more real trigger-event opcode reusing
    -- the already-solved 0xE0 shape.
    local round2 = {
      [0x11] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_11,
      [0x14] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_14,
      [0x18] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_18,
      [0x1B] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1B,
      [0x3A] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3A,
      [0x40] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_40,
      [0x48] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_48,
      [0x60] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_60,
      [0x70] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_70,
      [0xE4] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E4,
    }
    for opcode, addr in pairs(round2) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_11, 0x1268)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_14, 0x128C)
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_18, 0x12A4)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1B, 0x12C4)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3A, 0x13A0)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_40, 0x13B8)
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_48, 0x1400)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_60, 0x14A0)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_70, 0x1514)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E4, 0x0F88)

    -- Real, live-confirmed: opcodes 0x80/0x85, a third real shape
    -- (a different gate, $1588, see ACTOR_ACTION_HANDLER_ADDRESS_80/
    -- _85's own doc comment).
    Harness.assertEqual(entries[0x80 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80)
    Harness.assertEqual(entries[0x85 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_85)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_80, 0x15A4)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_85, 0x15EF)

    -- Real, live-confirmed: opcode 0xDE, a genuinely always-continuing
    -- opcode (no conditional halt anywhere in its own real routine).
    Harness.assertEqual(entries[0xDE + 1], ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_DE)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_DE, 0x3B81)

    -- Round 3, same day: 5 more actor-flag opcodes, 2 more trigger-
    -- event opcodes, and 2 genuinely new always-continuing shapes.
    local round3 = {
      [0x21] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_21,
      [0x3B] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3B,
      [0x47] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_47,
      [0x71] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_71,
      [0x77] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_77,
      [0xE2] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E2,
      [0xE5] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E5,
      [0xB0] = ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS,
      [0xD0] = ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS,
    }
    for opcode, addr in pairs(round3) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_21, 0x12DC)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_3B, 0x13AC)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_47, 0x13DC)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_71, 0x1520)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_77, 0x1538)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E2, 0x0FCA)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E5, 0x0F93)
    Harness.assertEqual(ScriptOpcodeTable.BYTE_WORD_COMMAND_HANDLER_ADDRESS, 0x0F1E)
    Harness.assertEqual(ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS, 0x3A4F)

    -- Round 4, same day: 4 more actor-flag opcodes, 3 more trigger-
    -- event opcodes, 1 more wordCommand reuse, 1 new two-byte shape.
    local round4 = {
      [0x15] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_15,
      [0x17] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_17,
      [0x56] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_56,
      [0x65] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_65,
      [0xE1] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E1,
      [0xB9] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_B9,
      [0xC3] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_C3,
      [0xEF] = ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_EF,
      [0xF6] = ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS,
    }
    for opcode, addr in pairs(round4) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_15, 0x1298)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_17, 0x1280)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_56, 0x1444)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_65, 0x14DC)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E1, 0x0FBF)
    -- CORRECTED 2026-08-14 (whole-corpus scan): 0xB9 was originally
    -- registered as a plain triggerEvent here; superseded by the more
    -- precise WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9 (see
    -- ScriptOpcodeTable.lua's own doc comment for the real correction).
    Harness.assertEqual(ScriptOpcodeTable.WRAM_BIT_COMMAND_HANDLER_ADDRESS_B9, 0x1186)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_C3, 0x3A09)
    Harness.assertEqual(ScriptOpcodeTable.WORD_COMMAND_HANDLER_ADDRESS_EF, 0x0E7F)
    Harness.assertEqual(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS, 0x3CA2)

    -- Round 5, same day: 6 more actor-flag opcodes, 1 more $1588-gated
    -- opcode, 1 more trigger-event opcode.
    local round5 = {
      [0x16] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_16,
      [0x1A] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1A,
      [0x26] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_26,
      [0x2A] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2A,
      [0x44] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_44,
      [0x57] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_57,
      [0x84] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_84,
      [0xA0] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_A0,
    }
    for opcode, addr in pairs(round5) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_16, 0x1274)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_1A, 0x12B8)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_26, 0x12E8)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2A, 0x132C)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_44, 0x13E8)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_57, 0x1450)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_84, 0x15E3)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_A0, 0x0194)

    -- Round 6, same day: the final long-tail batch this pass.
    local round6 = {
      [0x28] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_28,
      [0x46] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_46,
      [0x58] = ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_58,
      [0xC4] = ScriptOpcodeTable.SOUND_PARAM_HANDLER_ADDRESS_C4,
    }
    for opcode, addr in pairs(round6) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_28, 0x1318)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_46, 0x13D0)
    Harness.assertEqual(ScriptOpcodeTable.QUEUED_ACTION_HANDLER_ADDRESS_58, 0x1474)
    Harness.assertEqual(ScriptOpcodeTable.SOUND_PARAM_HANDLER_ADDRESS_C4, 0x39A3)

    -- Round 7 (2026-08-14, whole-corpus scan's own `$1350` blocker):
    -- 5 more real Family-A `actorAction` members, found in the SAME
    -- `$1338`-`$1380` neighborhood as the already-known `0x30`/`0x35`.
    local round7 = {
      [0x2B] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2B,
      [0x31] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_31,
      [0x34] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_34,
      [0x36] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_36,
      [0x37] = ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_37,
    }
    for opcode, addr in pairs(round7) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_2B, 0x1338)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_31, 0x1350)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_34, 0x1374)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_36, 0x135C)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_37, 0x1368)

    -- Round 8 (2026-08-14, whole-corpus scan's own `$0FA9` blocker):
    -- the missing sibling of the already-wired `0xE0`-`0xE3` trigger-
    -- event family, plus the real `0xC8` soft-reset and `0xCC`
    -- opcode-byte-mirror finds from the same pass.
    local round8 = {
      [0xE7] = ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E7,
      [0xC8] = ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8,
      [0xCC] = ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC,
    }
    for opcode, addr in pairs(round8) do
      Harness.assertEqual(entries[opcode + 1], addr)
    end
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E7, 0x0FA9)
    Harness.assertEqual(ScriptOpcodeTable.SOFT_RESET_HANDLER_ADDRESS_C8, 0x3BA9)
    Harness.assertEqual(ScriptOpcodeTable.OPCODE_BYTE_MIRROR_HANDLER_ADDRESS_CC, 0x3AA3)

    -- Real, structurally-confirmed facts: every entry is a valid CPU
    -- address, and the table's own default/unassigned-opcode handler
    -- ($3F0C) is genuinely the single most common entry (real, sparse,
    -- hand-authored opcode set, not noise).
    local defaultCount = 0
    for _, addr in ipairs(entries) do
      Harness.assertTrue(addr >= 0 and addr <= 0x7FFF, "handler address out of valid CPU range: " .. addr)
      if addr == ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS then
        defaultCount = defaultCount + 1
      end
    end
    Harness.assertTrue(defaultCount > 40, "expected the real default handler to be common, got " .. defaultCount)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable.decode: real ROM's 0xFF sub-dispatch table (2026-08-11, bounded + disassembled)",
  romData ~= nil,
  "no development ROM found",
  function()
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeSubTable)
    Harness.assertEqual(#entries, 11)

    -- Real, live-disassembled values (see rom-map.md's "The 0xFF
    -- sub-dispatch table -- bounded and disassembled") -- every entry
    -- is a genuine fixed-bank code address, each individually
    -- disassembled to confirm it's real code, not a coincidence.
    local expected = {
      0x3547, 0x3597, 0x3675, 0x3C1B, 0x350F, 0x3CDC,
      0x3AF6, 0x3B18, 0x3B2C, 0x39AF, 0x3BD6,
    }
    for i, addr in ipairs(expected) do
      Harness.assertEqual(entries[i], addr)
    end

    -- The byte immediately after the table's real end (file 0x3BC2)
    -- decodes as 0x21 -- SM83's real LD HL,nn opcode, i.e. genuine CPU
    -- code, not more table data. This is the actual boundary proof
    -- (not just "11 looked plausible") -- byte-exact against the ROM.
    Harness.assertEqual(romData:byte(0x3BC2 + 1), 0x21)
  end
)

Harness.testIfAvailable(
  "rom_profiles.lua's scriptPointerTable: real formula reproduces the live-traced boss-defeat script address (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Locks in the real chain events.md's "The index question,
    -- CONCLUSIVELY RESOLVED" section traced end to end: a real WRAM
    -- actor-record index (232, live-observed for the boss-defeat
    -- story trigger) resolves through this table to the exact real
    -- script address the live interpreter cursor actually jumped to
    -- (0x470F) -- verified here purely from static ROM bytes, no
    -- emulator needed to re-check it.
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local t = profile.scriptPointerTable
    local ex = t.verifiedExample

    local entryOffset = t.fileOffset + ex.index * 2
    local lo, hi = romData:byte(entryOffset + 1, entryOffset + 2)
    local tableValue = lo + hi * 256
    Harness.assertEqual(tableValue, ex.tableValue)
    Harness.assertEqual(tableValue + t.cpuBankOffsetBase, ex.scriptCpuAddress)

    -- Also locks in the real WRAM-pointer-chase that PRODUCED index
    -- 232 in the first place (live-read: $C3F0=bank 6, $C3FE/$C3FF=
    -- CPU pointer 0x5019 -> file 0x19019 -> real bytes there, +2):
    -- bank 6, file offset = 6*0x4000 + (0x5019-0x4000).
    local chaseFileOffset = 6 * 0x4000 + (0x5019 - 0x4000)
    local plo, phi = romData:byte(chaseFileOffset + 1, chaseFileOffset + 2)
    local secondPointer = plo + phi * 256
    Harness.assertEqual(secondPointer + 2, ex.index)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0xE6 (open WEST exit, $235B(A=0x02)) -- table entry + real prologue bytes (2026-08-13, direct response to a secondRoom west-wall bug report)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0xE6 + 1], ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E6)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_E6, 0x0F9E)

    -- Real bytes: PUSH HL / LD A,0x02 / CALL $235B / POP HL / CALL
    -- $3727 / RET -- fixed bank 0, file offset == CPU address.
    local h = 0x0F9E
    Harness.assertEqual(romData:byte(h + 1), 0xE5) -- PUSH HL
    Harness.assertEqual(romData:byte(h + 2), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h + 3), 0x02) -- n=2 (WEST, per rom-map.md's direction table)
    Harness.assertEqual(romData:byte(h + 4), 0xCD) -- CALL $235B
    Harness.assertEqual(romData:byte(h + 5) + romData:byte(h + 6) * 256, 0x235B)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x49's full chain -- table entry, real prologue bytes, and the $1F35 selector 0x0D resolution (2026-08-13, live shadow-run find)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x49 + 1], ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_49, 0x140A)

    -- Real prologue bytes at $140A: `CALL $28C2 / ADD A,3 / LD C,A /
    -- CALL $123E / RET` -- fixed bank 0, file offset == CPU address.
    local h = 0x140A
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x03)
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0xCD) -- CALL $123E
    Harness.assertEqual(romData:byte(h + 8) + romData:byte(h + 9) * 256, 0x123E)

    -- Real $123E body: the SAME $289B (WRAM $C5A0 OR-reduce) gate the
    -- queued-action family shares, checked BEFORE any operand byte is
    -- read (`RET NZ` at file $1245, before the first `LD A,(HL+)`).
    local body = 0x123E
    Harness.assertEqual(romData:byte(body + 3), 0xCD) -- CALL $289B, after PUSH HL/PUSH BC
    Harness.assertEqual(romData:byte(body + 4) + romData:byte(body + 5) * 256, 0x289B)
    Harness.assertEqual(romData:byte(0x1245 + 1), 0xC0) -- RET NZ
    Harness.assertEqual(romData:byte(0x1246 + 1), 0x2A) -- LD A,(HL+) -- operand byte 1

    -- Real selector 0x0D resolution: the already-mapped $1F35 dispatch
    -- table (bank 3, CPU $4000 base) resolves selector 0x0D to $4AF9 --
    -- the same real target $123E's own `CALL $28AA` trampoline
    -- (`LD A,0x0D / JP $1F35`) tail-dispatches into.
    local selectorTableFileBase = 3 * 0x4000
    local entryOffset = selectorTableFileBase + 0x0D * 2
    local lo, hi = romData:byte(entryOffset + 1, entryOffset + 2)
    Harness.assertEqual(lo + hi * 256, 0x4AF9)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x19 reuses the exact 0x49 $123E chain, just via a different trampoline base (2026-08-13, Milestone 7 continuation)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x19 + 1], ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_19)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_19, 0x12AE)

    -- Real prologue bytes at $12AE: `CALL $28C2 / ADD A,0x00 / LD C,A /
    -- CALL $123E / RET` -- fixed bank 0, file offset == CPU address.
    local h = 0x12AE
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x00) -- base 0 (vs 0x49's base 3)
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0xCD) -- CALL $123E
    Harness.assertEqual(romData:byte(h + 8) + romData:byte(h + 9) * 256, 0x123E)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x27's Family-A actorAction chain, group 0x1D (2026-08-13, found scanning the $12A0-$1300 cluster)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x27 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_27)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_27, 0x12F4)

    -- Real bytes at $12F4: `CALL $28C2 / ADD A,0x01 / LD C,A / LD
    -- A,0x1D / CALL $2879 / RET` -- fixed bank 0, file offset == CPU
    -- address. Byte-for-byte the same Family-A shape as 0x16/0x1A/0x26/
    -- 0x2A/0x44/0x57 above, just base=1 and fixed group=0x1D.
    local h = 0x12F4
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x01) -- base 1
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h + 8), 0x1D) -- group 0x1D
    Harness.assertEqual(romData:byte(h + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h + 10) + romData:byte(h + 11) * 256, 0x2879)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x51's Family-A actorAction chain, group 0x05 (2026-08-13, immediate live shadow-run follow-up to 0x50)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x51 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_51)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_51, 0x1438)

    -- Real bytes at $1438: `CALL $28C2 / ADD A,0x04 / LD C,A / LD
    -- A,0x05 / CALL $2879 / RET` -- fixed bank 0, file offset == CPU
    -- address.
    local h = 0x1438
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x04) -- base 4
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h + 8), 0x05) -- group 0x05
    Harness.assertEqual(romData:byte(h + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h + 10) + romData:byte(h + 11) * 256, 0x2879)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: opcodes 0x35/0x39/0x75 -- 3 more confirmed matches from task #82's census (2026-08-13)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

    local function assertActorAction(opcode, constant, addr, base, group)
      Harness.assertEqual(entries[opcode + 1], constant)
      Harness.assertEqual(constant, addr)
      Harness.assertEqual(romData:byte(addr + 1), 0xCD) -- CALL $28C2
      Harness.assertEqual(romData:byte(addr + 2) + romData:byte(addr + 3) * 256, 0x28C2)
      Harness.assertEqual(romData:byte(addr + 4), 0xC6) -- ADD A,n
      Harness.assertEqual(romData:byte(addr + 5), base)
      Harness.assertEqual(romData:byte(addr + 6), 0x4F) -- LD C,A
      Harness.assertEqual(romData:byte(addr + 7), 0x3E) -- LD A,n
      Harness.assertEqual(romData:byte(addr + 8), group)
      Harness.assertEqual(romData:byte(addr + 9), 0xCD) -- CALL $2879
      Harness.assertEqual(romData:byte(addr + 10) + romData:byte(addr + 11) * 256, 0x2879)
    end

    assertActorAction(0x35, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_35, 0x1380, 0x02, 0x1F)
    assertActorAction(0x75, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_75, 0x1550, 0x06, 0x1F)

    Harness.assertEqual(entries[0x39 + 1], ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_39)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_39, 0x1396)
    local h = 0x1396
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x02) -- base 2
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0xCD) -- CALL $123E
    Harness.assertEqual(romData:byte(h + 8) + romData:byte(h + 9) * 256, 0x123E)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0xCB's two-operand-byte shape, distinct real target from TWO_BYTE_COMMAND_HANDLER_ADDRESS (2026-08-13, task #82)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0xCB + 1], ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB)
    Harness.assertEqual(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB, 0x392C)
    Harness.assertTrue(ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS_CB ~= ScriptOpcodeTable.TWO_BYTE_COMMAND_HANDLER_ADDRESS)

    -- Real bytes at $392C: `LD A,(HL+) / LD D,A / LD A,(HL+) / LD E,A /
    -- LD BC,0xD633 / CALL $3937 / RET` -- fixed bank 0, file offset ==
    -- CPU address.
    local h = 0x392C
    Harness.assertEqual(romData:byte(h + 1), 0x2A) -- LD A,(HL+)
    Harness.assertEqual(romData:byte(h + 2), 0x57) -- LD D,A
    Harness.assertEqual(romData:byte(h + 3), 0x2A) -- LD A,(HL+)
    Harness.assertEqual(romData:byte(h + 4), 0x5F) -- LD E,A
    Harness.assertEqual(romData:byte(h + 5), 0x01) -- LD BC,n
    Harness.assertEqual(romData:byte(h + 6) + romData:byte(h + 7) * 256, 0xD633)
    Harness.assertEqual(romData:byte(h + 8), 0xCD) -- CALL $3937
    Harness.assertEqual(romData:byte(h + 9) + romData:byte(h + 10) * 256, 0x3937)
    Harness.assertEqual(romData:byte(h + 11), 0xC9) -- RET
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x61's Family-A actorAction chain, group 0x05 (2026-08-13, live shadow-run's next real stopper after 0x50/0x51)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x61 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_61)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_61, 0x14AC)

    -- Real bytes at $14AC: `CALL $28C2 / ADD A,0x05 / LD C,A / LD
    -- A,0x05 / CALL $2879 / RET` -- fixed bank 0, file offset == CPU
    -- address.
    local h = 0x14AC
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x05) -- base 5
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h + 8), 0x05) -- group 0x05
    Harness.assertEqual(romData:byte(h + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h + 10) + romData:byte(h + 11) * 256, 0x2879)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcodes 0x64/0x87 -- found mapping the bank-accurate post-boss sequence (2026-08-13, task #86)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

    Harness.assertEqual(entries[0x64 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_64)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_64, 0x14D0)
    local h64 = 0x14D0
    Harness.assertEqual(romData:byte(h64 + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h64 + 2) + romData:byte(h64 + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h64 + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h64 + 5), 0x05) -- base 5
    Harness.assertEqual(romData:byte(h64 + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h64 + 7), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h64 + 8), 0x1E) -- group 0x1E
    Harness.assertEqual(romData:byte(h64 + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h64 + 10) + romData:byte(h64 + 11) * 256, 0x2879)

    -- Real bytes at $15D7: `CALL $1588 / RET NZ / LD A,0x02 / LD
    -- C,0xFF / CALL $2879 / RET` -- the same $1588-gated shape already
    -- known for 0x84/0x85.
    Harness.assertEqual(entries[0x87 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_87)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_87, 0x15D7)
    local h87 = 0x15D7
    Harness.assertEqual(romData:byte(h87 + 1), 0xCD) -- CALL $1588
    Harness.assertEqual(romData:byte(h87 + 2) + romData:byte(h87 + 3) * 256, 0x1588)
    Harness.assertEqual(romData:byte(h87 + 4), 0xC0) -- RET NZ
    Harness.assertEqual(romData:byte(h87 + 5), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h87 + 6), 0x02) -- group 0x02
    Harness.assertEqual(romData:byte(h87 + 7), 0x0E) -- LD C,n
    Harness.assertEqual(romData:byte(h87 + 8), 0xFF) -- C=0xFF
    Harness.assertEqual(romData:byte(h87 + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h87 + 10) + romData:byte(h87 + 11) * 256, 0x2879)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: opcodes 0x41/0x45/0x4B/0x55/0x59 -- the 5 confirmed matches from the full 1357-script census (2026-08-13, task #80)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

    -- Real bytes, fixed bank 0, file offset == CPU address for each.
    local function assertActorAction(opcode, constant, addr, base, group)
      Harness.assertEqual(entries[opcode + 1], constant)
      Harness.assertEqual(constant, addr)
      Harness.assertEqual(romData:byte(addr + 1), 0xCD) -- CALL $28C2
      Harness.assertEqual(romData:byte(addr + 2) + romData:byte(addr + 3) * 256, 0x28C2)
      Harness.assertEqual(romData:byte(addr + 4), 0xC6) -- ADD A,n
      Harness.assertEqual(romData:byte(addr + 5), base)
      Harness.assertEqual(romData:byte(addr + 6), 0x4F) -- LD C,A
      Harness.assertEqual(romData:byte(addr + 7), 0x3E) -- LD A,n
      Harness.assertEqual(romData:byte(addr + 8), group)
      Harness.assertEqual(romData:byte(addr + 9), 0xCD) -- CALL $2879
      Harness.assertEqual(romData:byte(addr + 10) + romData:byte(addr + 11) * 256, 0x2879)
    end

    assertActorAction(0x41, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_41, 0x13C4, 0x03, 0x05)
    assertActorAction(0x45, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_45, 0x13F4, 0x03, 0x1F)
    assertActorAction(0x4B, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_4B, 0x1420, 0x03, 0x0F)
    assertActorAction(0x55, ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_55, 0x1468, 0x04, 0x1F)

    -- 0x59 ($147E) is the OTHER real shape -- the $123E actorSlotPosition
    -- chain, same as 0x49/0x19.
    Harness.assertEqual(entries[0x59 + 1], ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_59)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_SLOT_POSITION_HANDLER_ADDRESS_59, 0x147E)
    local h = 0x147E
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x04) -- base 4
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0xCD) -- CALL $123E
    Harness.assertEqual(romData:byte(h + 8) + romData:byte(h + 9) * 256, 0x123E)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcode 0x50's Family-A actorAction chain, group 0x04 (2026-08-13, live shadow-run's next real stopper after 0x19/0x27)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)
    Harness.assertEqual(entries[0x50 + 1], ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_50)
    Harness.assertEqual(ScriptOpcodeTable.ACTOR_ACTION_HANDLER_ADDRESS_50, 0x142C)

    -- Real bytes at $142C: `CALL $28C2 / ADD A,0x04 / LD C,A / LD
    -- A,0x04 / CALL $2879 / RET` -- fixed bank 0, file offset == CPU
    -- address.
    local h = 0x142C
    Harness.assertEqual(romData:byte(h + 1), 0xCD) -- CALL $28C2
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0x28C2)
    Harness.assertEqual(romData:byte(h + 4), 0xC6) -- ADD A,n
    Harness.assertEqual(romData:byte(h + 5), 0x04) -- base 4
    Harness.assertEqual(romData:byte(h + 6), 0x4F) -- LD C,A
    Harness.assertEqual(romData:byte(h + 7), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(h + 8), 0x04) -- group 0x04
    Harness.assertEqual(romData:byte(h + 9), 0xCD) -- CALL $2879
    Harness.assertEqual(romData:byte(h + 10) + romData:byte(h + 11) * 256, 0x2879)
  end
)

Harness.testIfAvailable(
  "ScriptOpcodeTable: real opcodes 0xFC/0xFD's full disassembly, including the real $2819/$2840 selector trampolines (2026-08-13, task #86)",
  romData ~= nil,
  "no development ROM found",
  function()
    local profile = RomProfiles.match(RomIdentity.identify(romData))
    local entries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

    Harness.assertEqual(entries[0xFC + 1], ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FC, 0x27F9)
    Harness.assertEqual(entries[0xFD + 1], ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FD)
    Harness.assertEqual(ScriptOpcodeTable.TRIGGER_EVENT_HANDLER_ADDRESS_FD, 0x2820)

    -- Real bytes at $27F9 (0xFC): `LD A,(0xD499) / CP 0 / CALL
    -- Z,0x2819 / LD A,1 / LD (0xD499),A / LD A,(0xC8E0) / CP 0 / RET
    -- NZ / LD A,(0xCEE8) / CP 0 / RET NZ / LD (0xD499),A / CALL
    -- $3727 / RET` -- fixed bank 0, file offset == CPU address.
    local h = 0x27F9
    Harness.assertEqual(romData:byte(h + 1), 0xFA) -- LD A,(nn)
    Harness.assertEqual(romData:byte(h + 2) + romData:byte(h + 3) * 256, 0xD499)
    Harness.assertEqual(romData:byte(h + 4), 0xFE) -- CP n
    Harness.assertEqual(romData:byte(h + 5), 0x00)
    Harness.assertEqual(romData:byte(h + 6), 0xCC) -- CALL Z,nn
    Harness.assertEqual(romData:byte(h + 7) + romData:byte(h + 8) * 256, 0x2819)

    -- $2819: `LD A,(HL+) / PUSH AF / LD A,0x05 / JP $1F35` -- real
    -- selector-group-5 trampoline, the operand-consuming path.
    local sel5 = 0x2819
    Harness.assertEqual(romData:byte(sel5 + 1), 0x2A) -- LD A,(HL+)
    Harness.assertEqual(romData:byte(sel5 + 2), 0xF5) -- PUSH AF
    Harness.assertEqual(romData:byte(sel5 + 3), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(sel5 + 4), 0x05) -- selector group 5
    Harness.assertEqual(romData:byte(sel5 + 5), 0xC3) -- JP nn
    Harness.assertEqual(romData:byte(sel5 + 6) + romData:byte(sel5 + 7) * 256, 0x1F35)

    -- $2820 (0xFD): the same shape, `CALL Z,0x2840`.
    local h2 = 0x2820
    Harness.assertEqual(romData:byte(h2 + 1), 0xFA)
    Harness.assertEqual(romData:byte(h2 + 2) + romData:byte(h2 + 3) * 256, 0xD499)
    Harness.assertEqual(romData:byte(h2 + 6), 0xCC)
    Harness.assertEqual(romData:byte(h2 + 7) + romData:byte(h2 + 8) * 256, 0x2840)

    -- $2840: same trampoline shape, selector group 4.
    local sel4 = 0x2840
    Harness.assertEqual(romData:byte(sel4 + 3), 0x3E) -- LD A,n
    Harness.assertEqual(romData:byte(sel4 + 4), 0x04) -- selector group 4
  end
)
