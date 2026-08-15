-- Whole-corpus shadow-run: every real scriptPointerTable entry, through
-- the CURRENT ScriptRuntime opcode coverage, to find which undecoded
-- handler addresses block the most real scripts -- this project's own
-- standard way of measuring real, honest progress on "make everything
-- interpreter-based" (see docs/reverse-engineering/events.md's own
-- dated "whole-corpus scan" entries for the history).
--
-- CHECKED IN 2026-08-14 ("konsolidiere unsere Entdeckungen und baue sie
-- ein"): earlier passes rebuilt this same tool from scratch in the
-- scratchpad each session (it doesn't survive between sessions there) --
-- consolidated here so it's a permanent, reusable artifact instead of
-- being reconstructed every time.
--
-- Usage: from the repo root,
--   MYSTICQUEST_ROM=/path/to/rom.gb luajit scripts/scan_all_scripts.lua
-- (or drop a ROM at one of the fallback locations below -- same
-- resolution convention as `tests/dev_rom_locator.lua`, duplicated
-- rather than required from `tests/` since that module is explicitly
-- scoped "test-only helper").
package.path = "./?.lua;" .. package.path

local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local RomScriptStream = require("src.scripting.RomScriptStream")
local ScriptRuntime = require("src.scripting.ScriptRuntime")

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
assert(romData, "scan_all_scripts.lua: no ROM found -- set MYSTICQUEST_ROM or place one at a fallback location (see this file's own doc comment)")
io.stderr:write(string.format("using ROM: %s\n", romPath))

local report = RomIdentity.identify(romData)
local profile = RomProfiles.match(report)
local spt = profile.scriptPointerTable
local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

-- Generic stub ctx: every unset field resolves to a function returning
-- `true` -- a safe default for gate/predicate callbacks (matches this
-- project's own already-established "always ready"/"always clear"
-- conventions), harmless no-op for fire-and-forget callbacks whose
-- return value is ignored.
--
-- FIXED (2026-08-15, direct follow-up to the 2026-08-14 "KNOWN
-- LIMITATION" note this replaces -- "beende jetzt mal den full corpus
-- scan"): a full audit of `error_other`'s own first-line breakdown
-- found the blanket `true` stub was NOT just leaking into
-- `onRunListExhausted0B`/`0C` (opcodes `0x0B`/`0x0C`) as originally
-- scoped -- the EXACT SAME "return value IS the next cursor" contract
-- (`StandardScriptHandlers.zeroTerminatedFlagList`'s own `onExhausted`)
-- is shared by `ctx.onFlagListExhausted` (opcode `0x08`) and
-- `ctx.onTimerListExhausted09`/`0A` (opcodes `0x09`/`0x0A`) -- 5 real
-- opcodes total, not 2. Together these accounted for 148/308 (48%) of
-- this scan's own `error_other` bucket, ALL surfacing as the same
-- confusing "cursor true out of stream bounds" message that gives no
-- hint which real opcode or ROM address was actually involved.
-- `ctx.onControlCode` (opcode `0x04`'s own control-code path,
-- `StandardScriptHandlers.tick`) has a similar but distinct bug: its
-- own honest default (when the FIELD IS ABSENT) is "not a known
-- control code, cursor+1, no pin" (see that function's own `if not
-- onControlCode then ... end` guard) -- but the blanket stub makes the
-- field ALWAYS PRESENT (a callable returning `true`), which then flows
-- into `cursor + 1 + extraBytes` as `cursor + 1 + true`, a genuine Lua
-- type error (14/308, 4.5%). Both fixed the same way: give these
-- fields explicit, real entries here so the blanket `__index` fallback
-- never has to guess a type for them. The exhausted-list family gets a
-- clearly-labeled `error()` (still counted as `error_other`, since this
-- project genuinely has no honest way to fabricate the real, data-
-- dependent resume cursor without live WRAM -- see rom-map.md's own
-- "$1ED7" section -- but now self-explanatory instead of a mystery
-- "cursor true" crash). `onControlCode = false` (a real, present,
-- falsy value, same trick already used for `queue` below) makes
-- `StandardScriptHandlers.tick`'s own `if not onControlCode` guard see
-- it as genuinely unset, so it takes its own honest, already-correct
-- default path instead of calling a bogus stub at all.
local function exhaustedListStub(opcodeLabel)
  return function(cursorAfterTerminator)
    error(string.format(
      "scan_all_scripts.lua stub: opcode %s's real 'list exhausted' resume cursor " ..
      "(from real ROM cursor %#x) is genuine, data-dependent ROM content this " ..
      "scan tool has no live WRAM to derive -- not a bug in the opcode's own " ..
      "handler (see StandardScriptHandlers.zeroTerminatedFlagList's own doc comment)",
      opcodeLabel, cursorAfterTerminator))
  end
end

local stubCtx = setmetatable({
  stats = { curLP = 19, maxLP = 19, curMP = 6, maxMP = 6 },
  flags = { byte = 0 },
  wramBitFlags = { byte = 0 },
  actorStateFlags = { byte = 0 }, -- real WRAM $C4D4 shadow, added 2026-08-14
                                    -- for opcodes 0xA3/0xA5/0xA6 -- MUST be a
                                    -- real table like the two above, not the
                                    -- generic function-returning __index
                                    -- fallback below (that fallback is only
                                    -- safe for callback-shaped ctx fields).
  isTriggerEventGateClear = function() return true end,
  onTimerListTest09 = function() return true end,
  onTimerListTest0A = function() return true end,
  runListMatchByte = function() return 0 end, -- generous stub: "matches" the first candidate byte seen (0 never appears as a real candidate, but keeps this deterministic)
  isRunListGateSet = function() return true end,
  onFlagListExhausted = exhaustedListStub("0x08"),
  onTimerListExhausted09 = exhaustedListStub("0x09"),
  onTimerListExhausted0A = exhaustedListStub("0x0A"),
  onRunListExhausted0B = exhaustedListStub("0x0B"),
  onRunListExhausted0C = exhaustedListStub("0x0C"),
  onControlCode = false, -- see this block's own doc comment -- makes
                          -- StandardScriptHandlers.tick treat it as
                          -- genuinely unset (honest cursor+1/no-pin
                          -- default) instead of calling a bogus stub.
  queue = false, -- real raw key (falsy, not nil) so the __index stub below
                 -- never shadows it -- ScriptRuntime.new's own `ctx.queue or
                 -- ScriptContinuationQueue.new()` needs a real falsy value
                 -- here, not a bogus function, to build its real queue.
}, { __index = function() return function() return true end end })

local FILLER, CLEAN, HALT_UNDECODED, ERROR_OTHER = "filler", "clean", "halt_undecoded", "error_other"

local haltCounts = {}      -- handlerAddress (hex string) -> count
local errorCounts = {}     -- first line of error message -> count
local statusCounts = { [FILLER] = 0, [CLEAN] = 0, [HALT_UNDECODED] = 0, [ERROR_OTHER] = 0 }
local stepBudget = 500

local total = spt.recordCount
for index = 0, total - 1 do
  local resolved, note = ScriptPointerTable.resolve(romData, spt, index)
  if not resolved then
    statusCounts[FILLER] = statusCounts[FILLER] + 1
  else
    local stream = RomScriptStream.forFileOffset(romData, resolved.bank * 0x4000)
    local runtime = ScriptRuntime.new(opcodeEntries, stubCtx)
    local ok, err = pcall(function()
      runtime:run(stream, resolved.cpuAddress, stepBudget)
    end)
    if not ok then
      statusCounts[ERROR_OTHER] = statusCounts[ERROR_OTHER] + 1
      local firstLine = tostring(err):match("^[^\n]*") or tostring(err)
      errorCounts[firstLine] = (errorCounts[firstLine] or 0) + 1
    elseif runtime.stopped then
      local addr = tostring(runtime.stopError):match("real ROM handler (0x%x+)")
      if addr then
        statusCounts[HALT_UNDECODED] = statusCounts[HALT_UNDECODED] + 1
        haltCounts[addr] = (haltCounts[addr] or 0) + 1
      else
        statusCounts[ERROR_OTHER] = statusCounts[ERROR_OTHER] + 1
        local firstLine = tostring(runtime.stopError):match("^[^\n]*") or tostring(runtime.stopError)
        errorCounts[firstLine] = (errorCounts[firstLine] or 0) + 1
      end
    else
      statusCounts[CLEAN] = statusCounts[CLEAN] + 1
    end
  end
end

print(string.format("total real table entries: %d", total))
for _, k in ipairs({ FILLER, CLEAN, HALT_UNDECODED, ERROR_OTHER }) do
  print(string.format("  %-16s %d", k, statusCounts[k]))
end

print("\ntop undecoded handler addresses blocking real scripts (address -> script count):")
local haltList = {}
for addr, count in pairs(haltCounts) do
  haltList[#haltList + 1] = { addr = addr, count = count }
end
table.sort(haltList, function(a, b) return a.count > b.count end)
for i, entry in ipairs(haltList) do
  print(string.format("  %2d. %-8s %d scripts", i, entry.addr, entry.count))
  if i >= 40 then break end
end

print("\nother real errors (first line -> count):")
local errList = {}
for msg, count in pairs(errorCounts) do
  errList[#errList + 1] = { msg = msg, count = count }
end
table.sort(errList, function(a, b) return a.count > b.count end)
for i, entry in ipairs(errList) do
  print(string.format("  %3d  %s", entry.count, entry.msg))
  if i >= 20 then break end
end
