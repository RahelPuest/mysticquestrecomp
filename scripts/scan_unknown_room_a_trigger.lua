-- Whole-corpus reachability scan for the `unknownRoomA` trigger (task:
-- "was sind offene milestones... dann unknownRoomA").
--
-- HYPOTHESIS (see docs/reverse-engineering/events.md's own 2026-08-16
-- "unknownRoomA-Trigger erneut suchen" entry, and
-- `src/import/CutTransitionTable.lua`'s doc comment): the real trigger
-- for any of the 36 `unknownRoomA`-family (`roomSelector` 8-13) landing
-- records is NOT a hidden static dispatch table (that hypothesis is
-- already decisively ruled out -- all 5 real `CALL $026DC` sites are
-- enumerated and understood). The only remaining candidate is: some
-- specific real script, among the 1357-entry `scriptPointerTable`
-- corpus, contains one of the 36 already-catalogued landing-record byte
-- sequences directly in its own body and actually reaches it during
-- normal control flow.
--
-- This has NOT been tried yet as of the 2026-08-16 entries: the static
-- angles tried were (a) searching for 2-byte LE pointer references to a
-- record's address in some OTHER table (came back coincidental), and
-- (b) live, time-boxed dialogue-proximity exploration. Neither actually
-- ran the now-complete (256/256 classified) opcode interpreter across
-- the whole corpus checking whether a script's own natural dispatch
-- cursor ever reaches one of these record byte spans.
--
-- METHOD: reuses scan_all_scripts.lua's exact per-script step loop
-- (same stub ctx, same cross-bank CHAIN following via
-- `stubCtx.onChainTarget`) but instruments it: before every
-- `runtime:step`, convert the about-to-be-dispatched `cursor` (a CPU
-- address in the current `bank`'s $4000-$7FFF window) back to a file
-- offset and check it against a precomputed set covering every byte of
-- all 36 unknownRoomA-family landing-record bodies (the full 9-byte
-- span, not just the leading 0x00, since it's not yet known whether a
-- caller's control flow lands exactly on the leading byte or jumps
-- straight to the 0xF4 opcode partway through -- see
-- CutTransitionTable.lua's own doc comment for the record shape).
--
-- Usage: from the repo root,
--   MYSTICQUEST_ROM=/path/to/rom.gb luajit scripts/scan_unknown_room_a_trigger.lua
package.path = "./?.lua;" .. package.path

local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local RomScriptStream = require("src.scripting.RomScriptStream")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local CutTransitionTable = require("src.import.CutTransitionTable")

local CANDIDATES = {}
CANDIDATES[#CANDIDATES + 1] = os.getenv("MYSTICQUEST_ROM")
CANDIDATES[#CANDIDATES + 1] = "baseroms/Mystic Quest (G) [!].gb"
CANDIDATES[#CANDIDATES + 1] = "../roms/extracted_mq/Mystic Quest (G) [!].gb"
CANDIDATES[#CANDIDATES + 1] = "../baseroms/Mystic Quest (G) [!].gb"

local function findRom()
  for _, path in ipairs(CANDIDATES) do
    if path then
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        return data, path
      end
    end
  end
  return nil
end

local romData, romPath = findRom()
assert(romData, "scan_unknown_room_a_trigger.lua: no ROM found -- set MYSTICQUEST_ROM or place one at a fallback location")
io.stderr:write(string.format("using ROM: %s\n", romPath))

local report = RomIdentity.identify(romData)
local profile = RomProfiles.match(report)
local spt = profile.scriptPointerTable
local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

-- Build the target set: every byte of every unknownRoomA-family
-- (roomSelector 8-13) landing record's 9-byte body, keyed by absolute
-- file offset -> the owning record (for reporting which one was hit).
local UNKNOWN_ROOM_A_SELECTORS = { [8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [13] = true }
local allRecords = CutTransitionTable.scanLandingRecords(romData)
local targetRecords = {}
for _, r in ipairs(allRecords) do
  if UNKNOWN_ROOM_A_SELECTORS[r.roomSelector] then
    targetRecords[#targetRecords + 1] = r
  end
end
io.stderr:write(string.format("unknownRoomA-family landing records: %d (of %d total)\n", #targetRecords, #allRecords))

local targetFileOffsets = {} -- fileOffset -> recordIndex (1-based into targetRecords)
for idx, r in ipairs(targetRecords) do
  for b = 0, CutTransitionTable.LANDING_RECORD_BODY_LENGTH - 1 do
    targetFileOffsets[r.fileOffset + b] = idx
  end
end

-- Same generic stub ctx as scan_all_scripts.lua -- see that file's own
-- doc comment for why each field is shaped the way it is. Duplicated
-- rather than required from that module since it's a script, not a
-- library (matches this project's own established convention of
-- scripts/ files being standalone, per scan_all_scripts.lua's own doc
-- comment about scratchpad tools being consolidated here).
local function exhaustedListStub(opcodeLabel)
  return function(cursorAfterTerminator)
    error(string.format(
      "stub: opcode %s's real 'list exhausted' resume cursor (from real ROM cursor %#x) " ..
      "is genuine, data-dependent ROM content this scan has no live WRAM to derive",
      opcodeLabel, cursorAfterTerminator))
  end
end

local function freshStubCtx()
  return setmetatable({
    stats = { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6 },
    flags = { byte = 0 },
    wramBitFlags = { byte = 0 },
    actorStateFlags = { byte = 0 },
    isTriggerEventGateClear = function() return true end,
    onTimerListTest09 = function() return true end,
    onTimerListTest0A = function() return true end,
    runListMatchByte = function() return 0 end,
    isRunListGateSet = function() return true end,
    onFlagListExhausted = exhaustedListStub("0x08"),
    onTimerListExhausted09 = exhaustedListStub("0x09"),
    onTimerListExhausted0A = exhaustedListStub("0x0A"),
    onRunListExhausted0B = exhaustedListStub("0x0B"),
    onRunListExhausted0C = exhaustedListStub("0x0C"),
    onControlCode = false,
    queue = false,
    -- Two explicit, evidence-backed fixes (2026-08-18, found while tracing
    -- this scan's own 9 loop points): the generic `__index` fallback below
    -- answers EVERY unset ctx field with "true", which is only the
    -- project's own documented "unwired gate defaults open" convention for
    -- READY/CLEAR/DONE-shaped predicates (isActorReady, isAnyButtonPressed,
    -- isTextboxDone, ...). It is WRONG for these two, which this project's
    -- own doc comments/live traces establish default the other way:
    --   isFadeActive: StandardScriptHandlers.gatedByteLeafCommand's own doc
    --     comment states plainly "isFadeActive defaults to 'never active'
    --     (the happy path)" -- the blanket "true" fallback was making every
    --     0xD4/0xD6/0xD8 dispatch halt on the UNMODELED $3ADE path instead
    --     of falling through to the real, modeled continue.
    --   isQueueBlocked (queueGate's own `isBlocked`): the ONE real,
    --     live-traced case this project has (the boss-defeat script, see
    --     StandardScriptHandlers.queueGate's own doc comment's "RETRACTED"
    --     paragraph) found WRAM $D874 bit 0 "never changes at all across a
    --     reproduced ~200,000-step boss-defeat block" -- i.e. genuinely
    --     false the whole time in the one case anyone has actually checked.
    isFadeActive = false,
    isQueueBlocked = false,
  }, { __index = function() return function() return true end end })
end

local FILLER, CLEAN, HALT_UNDECODED, ERROR_OTHER, LOOP = "filler", "clean", "halt_undecoded", "error_other", "loop_detected"
local statusCounts = { [FILLER] = 0, [CLEAN] = 0, [HALT_UNDECODED] = 0, [ERROR_OTHER] = 0, [LOOP] = 0 }
-- Raised well past scan_all_scripts.lua's 500: this scan cares about DEEP
-- reachability, not opcode-coverage breadth. Combined with the real,
-- per-(bank,cursor) LOOP DETECTION below (not just a step counter), a
-- higher budget costs nothing extra for a script that turns out to loop
-- deterministically -- it exits the instant a (bank,cursor) pair repeats,
-- not after burning the whole budget. Only a script that's still making
-- genuine forward progress at 500 steps benefits from the higher ceiling.
local stepBudget = 20000
local hits = {} -- array of { scriptIndex, recordIndex, bank, cursor, fileOffset, stepAt }
local haltLog = {} -- array of { scriptIndex, bank, cursor } for every halted script
local chainLog = {} -- array of { scriptIndex, fromBank, toBank } for every real cross-bank CHAIN observed
local maxBankReached = 0 -- highest ROM bank any script's cursor ever actually occupied

local total = spt.recordCount
for index = 0, total - 1 do
  local resolved, note = ScriptPointerTable.resolve(romData, spt, index)
  if not resolved then
    statusCounts[FILLER] = statusCounts[FILLER] + 1
  else
    local bank = resolved.bank
    local stream = RomScriptStream.forFileOffset(romData, bank * 0x4000)
    local stubCtx = freshStubCtx()
    stubCtx.onChainTarget = function(_target, bankOffset)
      if bankOffset ~= 0 then
        local fromBank = bank
        bank = bank + bankOffset
        chainLog[#chainLog + 1] = { scriptIndex = index, fromBank = fromBank, toBank = bank }
        stream = RomScriptStream.forFileOffset(romData, bank * 0x4000)
      end
    end
    local runtime = ScriptRuntime.new(opcodeEntries, stubCtx)
    local cursor = resolved.cpuAddress
    local scriptHitCount = 0
    local cursorSeen = {} -- "bank:cursor" -> true, this script's own visited set
    local looped = false
    local ok, err = pcall(function()
      for step = 1, stepBudget do
        if runtime.stopped or runtime.finished then break end
        if bank > maxBankReached then maxBankReached = bank end
        -- Real loop detection: if this exact (bank, cursor) pair was
        -- already the about-to-dispatch state once this run, the
        -- interpreter is in a genuine deterministic cycle (this stub ctx
        -- always answers gates the same way, so a repeat state can never
        -- diverge) -- stop immediately rather than burning the rest of
        -- the budget. Distinguishing this from "still exhausting a large
        -- but finite budget" matters for the final report below.
        local key = bank .. ":" .. cursor
        if cursorSeen[key] then looped = true; break end
        cursorSeen[key] = true
        -- Check BEFORE stepping: `cursor` here is the address about to
        -- be dispatched (ScriptRuntime:step dispatches at exactly this
        -- value) -- the real "does this script's own control flow ever
        -- reach this byte" question.
        local fileOffset = bank * 0x4000 + (cursor - 0x4000)
        local recordIdx = targetFileOffsets[fileOffset]
        if recordIdx then
          scriptHitCount = scriptHitCount + 1
          hits[#hits + 1] = {
            scriptIndex = index,
            recordIndex = recordIdx,
            bank = bank,
            cursor = cursor,
            fileOffset = fileOffset,
            stepAt = step,
          }
        end
        cursor = runtime:step(stream, cursor)
      end
    end)
    if not ok then
      statusCounts[ERROR_OTHER] = statusCounts[ERROR_OTHER] + 1
    elseif runtime.stopped then
      statusCounts[HALT_UNDECODED] = statusCounts[HALT_UNDECODED] + 1
      -- Follow-up instrumentation: record where in the ROM each halt
      -- actually stopped, so a bank-14 halt sitting shortly BEFORE one
      -- of the 36 target bytes (same linear stream, cursor increasing)
      -- can be flagged as a real lead -- "this script would plausibly
      -- have reached the target if not for the known-hard-opcode halt"
      -- -- rather than treating every halt as an undifferentiated dead
      -- end.
      haltLog[#haltLog + 1] = { scriptIndex = index, bank = bank, cursor = cursor }
    elseif looped then
      statusCounts[LOOP] = statusCounts[LOOP] + 1
    else
      statusCounts[CLEAN] = statusCounts[CLEAN] + 1
    end
  end
end

print(string.format("total real table entries: %d", total))
for _, k in ipairs({ FILLER, CLEAN, HALT_UNDECODED, LOOP, ERROR_OTHER }) do
  print(string.format("  %-16s %d", k, statusCounts[k]))
end

print(string.format("\nunknownRoomA-family target bytes covered: %d records (%d bytes)",
  #targetRecords, #targetRecords * CutTransitionTable.LANDING_RECORD_BODY_LENGTH))

print(string.format("\nreal cross-bank CHAIN jumps observed: %d", #chainLog))
for _, c in ipairs(chainLog) do
  print(string.format("  script #%d: bank %d -> bank %d", c.scriptIndex, c.fromBank, c.toBank))
end
print(string.format("\nfurthest ROM bank any script's cursor ever actually occupied: %d " ..
  "(unknownRoomA's own bank 14 landing records need to be reached AT LEAST here)", maxBankReached))

if #hits == 0 then
  print("\nRESULT: zero scripts reached any unknownRoomA-family landing-record byte")
  print("across the whole 1357-entry corpus within a " .. stepBudget .. "-step budget each.")
  print("This is a real, decisive negative for THIS method at THIS step budget --")
  print("either the trigger script halts on a still-undecoded/known-hard opcode before")
  print("reaching it (see halt_undecoded count above), needs a larger step budget, or")
  print("genuinely lives behind runtime state (a WRAM-dependent branch) this synthetic")
  print("stub context can't reproduce.")
else
  print(string.format("\nRESULT: %d hit(s) found across %d script(s):", #hits, total))
  for _, h in ipairs(hits) do
    local r = targetRecords[h.recordIndex]
    print(string.format(
      "  script #%d (bank %d) reaches file offset %#x (cursor %#x) at step %d -- " ..
      "record roomSelector=%d pixel=(%d,%d) [record fileOffset %#x]",
      h.scriptIndex, h.bank, h.fileOffset, h.cursor, h.stepAt,
      r.roomSelector, r.pixelX, r.pixelY, r.fileOffset))
  end
end

-- Follow-up: is any halted script's own stopping point a real, plausible
-- lead -- bank 14, cursor BELOW some target's cpuAddress, close enough
-- that the halt (not a genuine dead end) is what actually kept it from
-- reaching the target? "Close enough" is deliberately generous (any
-- earlier same-bank cursor) since a halted opcode's own real operand
-- length is unknown -- report every bank-14 halt and let a human/live
-- trace judge real proximity, don't silently filter by an assumed
-- distance.
local PROXIMITY_TARGET_BANK = 14
local nearMisses = {}
for _, h in ipairs(haltLog) do
  if h.bank == PROXIMITY_TARGET_BANK then
    nearMisses[#nearMisses + 1] = h
  end
end
print(string.format("\nHalted scripts that stopped inside bank %d (the unknownRoomA target bank): %d of %d total halts",
  PROXIMITY_TARGET_BANK, #nearMisses, #haltLog))
if #nearMisses > 0 then
  table.sort(nearMisses, function(a, b) return a.cursor < b.cursor end)
  for _, h in ipairs(nearMisses) do
    local fo = h.bank * 0x4000 + (h.cursor - 0x4000)
    -- distance to the nearest target record (by file offset)
    local nearest, nearestDist = nil, math.huge
    for idx, r in ipairs(targetRecords) do
      local d = math.abs(r.fileOffset - fo)
      if d < nearestDist then nearestDist = d; nearest = idx end
    end
    print(string.format("  script #%d halts at bank %d cursor %#x (file %#x) -- nearest unknownRoomA record #%d is %d bytes away (file %#x)",
      h.scriptIndex, h.bank, h.cursor, fo, nearest, nearestDist, targetRecords[nearest].fileOffset))
  end
end
