-- Generates the plain, static `js/data/*.js` files the ROM Inspector
-- reads -- every number/string in those files comes directly from this
-- project's own real, already-verified Lua modules (ScriptOpcodeTable,
-- EntityStructLayout, rom_profiles, TextDecoder, ScriptRuntime) or from
-- a real, live run of the whole-corpus scan (see
-- `scripts/scan_all_scripts.lua`, same underlying method). Nothing here
-- is hand-typed ROM content -- re-run this after any future decoding
-- pass to refresh the site instead of hand-editing the generated files.
--
-- Usage (from the repo root):
--   MYSTICQUEST_ROM=/path/to/rom.gb luajit rom-inspector/tools/export_data.lua
--
-- The small amount of genuinely curated text in here (open questions,
-- "known-hard" reasons, the WRAM cell reference list) is clearly
-- separated below and cites the real docs/reverse-engineering/*.md
-- sections it's drawn from -- it does not claim to be code-derived.

package.path = "./?.lua;" .. package.path

local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")
local ScriptOpcodeTable = require("src.import.ScriptOpcodeTable")
local ScriptPointerTable = require("src.import.ScriptPointerTable")
local EntityStructLayout = require("src.import.EntityStructLayout")
local TextDecoder = require("src.import.TextDecoder")
local RomScriptStream = require("src.scripting.RomScriptStream")
local ScriptRuntime = require("src.scripting.ScriptRuntime")
local RoomFloorLayout = require("src.import.RoomFloorLayout")
local MapTable = require("src.import.MapTable")
local EnemySpeciesTable = require("src.import.EnemySpeciesTable")
local EnemyStatTable = require("src.import.EnemyStatTable")
local ItemTable = require("src.import.ItemTable")
local WeaponTable = require("src.import.WeaponTable")
local WeaponStatTable = require("src.import.WeaponStatTable")
local NpcCatalog = require("src.import.NpcCatalog")
local GraphicsCandidates = require("src.import.GraphicsCandidates")
local MapTileCatalog = require("src.import.MapTileCatalog")
local MusicDecoder = require("src.import.MusicDecoder")
local CutTransitionTable = require("src.import.CutTransitionTable")
local ActorDefinitionTable = require("src.import.ActorDefinitionTable")
local MonsterDefinitionTable = require("src.import.MonsterDefinitionTable")

-- Same ROM resolution convention as scripts/scan_all_scripts.lua.
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
assert(romData, "export_data.lua: no ROM found -- set MYSTICQUEST_ROM")
io.stderr:write(string.format("using ROM: %s\n", romPath))

local report = RomIdentity.identify(romData)
local profile = RomProfiles.match(report)
assert(profile, "export_data.lua: ROM not recognized by rom_profiles.lua")

----------------------------------------------------------------------
-- Tiny Lua -> JS literal serializer (arrays vs objects auto-detected).
----------------------------------------------------------------------
local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0 or next(t) == nil
end

local function jsString(s)
  return string.format("%q", s):gsub("\\\n", "\\n")
end

local function serialize(v, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local pad1 = string.rep("  ", indent + 1)
  local t = type(v)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "number" then
    if v ~= v then return "null" end -- NaN guard
    return tostring(v)
  elseif t == "string" then
    return jsString(v)
  elseif t == "table" then
    if isArray(v) then
      if #v == 0 then return "[]" end
      local parts = {}
      for i = 1, #v do
        parts[#parts + 1] = pad1 .. serialize(v[i], indent + 1)
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      if #keys == 0 then return "{}" end
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = pad1 .. jsString(tostring(k)) .. ": " .. serialize(v[k], indent + 1)
      end
      return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    end
  end
  error("serialize: unsupported type " .. t)
end

local function writeJs(filename, varName, value, headerComment)
  local outDir = "rom-inspector/js/data"
  local f = assert(io.open(outDir .. "/" .. filename, "w"))
  f:write("// AUTO-GENERATED by rom-inspector/tools/export_data.lua -- do not hand-edit.\n")
  if headerComment then
    f:write("// " .. headerComment:gsub("\n", "\n// ") .. "\n")
  end
  f:write("const " .. varName .. " = " .. serialize(value, 0) .. ";\n")
  f:close()
  io.stderr:write("wrote " .. outDir .. "/" .. filename .. "\n")
end

----------------------------------------------------------------------
-- 1. ROM basics
----------------------------------------------------------------------
writeJs("rom-basics.js", "ROM_BASICS", {
  displayName = profile.displayName,
  sha1 = profile.sha1,
  sizeBytes = profile.sizeBytes,
  cartridgeType = profile.cartridgeType,
  bankSize = profile.bankSize,
  bankCount = profile.bankCount,
}, "Real ROM identity, from RomIdentity.identify() + rom_profiles.lua's own PROFILES entry.")

----------------------------------------------------------------------
-- 2. ROM tables reference (bank/offset/status for every named table)
----------------------------------------------------------------------
local TABLE_ORDER = {
  "scriptOpcodeTable", "scriptPointerTable", "scriptOpcodeSubTable",
  "messageTextPointer", "enemySpeciesTable", "itemTable", "weaponTable",
  "noiseTable", "mapTable", "roomSelectorTable",
}
local romTables = {}
for _, key in ipairs(TABLE_ORDER) do
  local t = profile[key]
  if t then
    romTables[#romTables + 1] = {
      name = key,
      status = t.status,
      bank = t.bank,
      fileOffset = t.fileOffset,
      recordCount = t.recordCount or t.rowCount or t.length,
    }
  end
end
writeJs("rom-tables.js", "ROM_TABLES", romTables,
  "Every named, verified/partially-verified ROM table this project has located, read directly from rom_profiles.lua.")

----------------------------------------------------------------------
-- 3. Entity struct layout
----------------------------------------------------------------------
-- Curated (not code-derived, same convention this file's header
-- comment already flags): one short, honest summary per field, drawn
-- from EntityStructLayout.lua's own doc comments -- so the website
-- shows the real story (including retractions), not just raw offsets.
-- Fields with no entry here simply show no note.
local FIELD_NOTES = {
  ALIVE = "0xFF = dead/empty sentinel. Setter ($0CA6) is guarded: once dead, a write attempt is immediately forced back to 0xFF -- no revival through this path.",
  TYPE = "RETRACTED: looked attack-related from static disassembly (3 callers write slot 4 with small integers alongside PARAM2). Live mGBA-tested across a real attack: zero value changes, and the whole code region is never reached. The 3 static call sites are real: what they're actually for is still open.",
  PARAM2 = "The most heavily-used accessor found: 24 getter + 17 setter callers, spread across every ROM bank. The $C4E0 actor-command array's own slot-scan code ($4BE0, $278F) reads this field for each active $C4E0 slot's own ID byte (used as the $C200 index) and classifies its high nibble against 0x90/0xB0/0x10.",
  PARAM6 = "No standalone accessor found -- $0CBA treats offsets +6/+7 as one paired 16-bit value (guarded the same way as ALIVE's setter), not two independent bytes.",
  UNKNOWN_10 = "Field beyond the previously-documented 0-8 range. Cross-confirmed via $404A (this project's own $C4E0 per-record tick handler), which reads it using the $C4E0 record's own ID byte as the $C200 slot index -- independent confirmation of that indexing convention.",
  UNKNOWN_11 = "Field beyond the previously-documented 0-8 range. Only 1 setter call site found (bank 0); no getter callers found in the same block.",
}
local fieldList = {}
for name, offset in pairs(EntityStructLayout.FIELD) do
  local accessor = EntityStructLayout.FIELD_ACCESSOR_ADDRESS[offset]
  fieldList[#fieldList + 1] = {
    name = name,
    offset = offset,
    accessorGet = accessor and accessor.get,
    accessorSet = accessor and accessor.set,
    note = FIELD_NOTES[name],
  }
end
table.sort(fieldList, function(a, b) return a.offset < b.offset end)
writeJs("entity-struct.js", "ENTITY_STRUCT", {
  base = EntityStructLayout.BASE,
  stride = EntityStructLayout.STRIDE,
  slotCount = EntityStructLayout.SLOT_COUNT,
  playerSlotIndex = EntityStructLayout.PLAYER_SLOT_INDEX_HYPOTHESIS,
  despawnRoutine = EntityStructLayout.DESPAWN_ROUTINE_ADDRESS,
  allocateRoutine = EntityStructLayout.ALLOCATE_ROUTINE_ADDRESS,
  pairedSetterAddress = EntityStructLayout.FIELD_ACCESSOR_ADDRESS.PAIRED_6_7_SET,
  fields = fieldList,
}, "Real, VERIFIED WRAM entity-slot struct -- see src/import/EntityStructLayout.lua's own doc comment.")

----------------------------------------------------------------------
-- 4. Opcode table: real per-opcode decode status, derived by actually
--    building a ScriptRuntime (same stub ctx as scripts/scan_all_scripts
--    .lua) and checking which handler addresses got a real registered
--    Lua implementation -- not hand-classified.
----------------------------------------------------------------------
local opcodeEntries = ScriptOpcodeTable.decode(romData, profile.scriptOpcodeTable)

-- FIXED (direct follow-up to finish the full corpus scan -- see
-- scripts/scan_all_scripts.lua's own doc comment for the full
-- rationale, duplicated here since this stub was an independent copy
-- carrying the exact same bug): the blanket __index fallback below (a
-- function always returning true) is only a safe default for gate/
-- predicate-shaped ctx fields. Several fields have a "return value is
-- the next cursor" contract instead (onFlagListExhausted/
-- onTimerListExhausted09/0A/onRunListExhausted0B/0C, opcodes 0x08-0x0C)
-- or a "return value is an extra-byte count" contract (onControlCode,
-- opcode 0x04) -- the generic true stub leaked through as a bogus
-- non-number in both cases, producing confusing errors that were
-- really scan-tool stub artifacts, not ROM decoding gaps.
local function exhaustedListStub(opcodeLabel)
  return function(cursorAfterTerminator)
    error(string.format(
      "export_data.lua stub: opcode %s's real 'list exhausted' resume cursor " ..
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
  actorStateFlags = { byte = 0 }, -- real WRAM $C4D4 shadow (opcodes 0xA3/0xA5/0xA6) --
                                    -- MUST be a real table, not the generic
                                    -- function-returning __index fallback below.
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
  onControlCode = false, -- makes StandardScriptHandlers.tick treat it as
                          -- genuinely unset (honest cursor+1/no-pin default)
                          -- instead of calling a bogus stub.
  queue = false,
}, { __index = function() return function() return true end end })
local runtime = ScriptRuntime.new(opcodeEntries, stubCtx)

-- Reverse map: real handler address -> every ScriptOpcodeTable.lua
-- constant name pointing at it (there can be several, e.g. one per
-- sibling opcode in a family) -- this is how each decoded opcode gets
-- a real, code-derived label instead of a hand-typed one.
local addressToNames = {}
for key, value in pairs(ScriptOpcodeTable) do
  if type(value) == "number" and key:match("ADDRESS") then
    addressToNames[value] = addressToNames[value] or {}
    table.insert(addressToNames[value], key)
  end
end
for _, names in pairs(addressToNames) do
  table.sort(names)
end

-- Curated (not code-derived): the small set of handler addresses this
-- project has traced but deliberately left unwired, with why -- see
-- ScriptOpcodeTable.lua's own doc comments at each address for the
-- full disassembly this summarizes.
local KNOWN_HARD = {
  -- REMOVED (task #10, consolidation pass): 0x15A4 (opcode 0x80) used
  -- to live here ("group value is data-dependent, no live WRAM
  -- simulation to supply") -- no longer true. $02AB (the leaf behind
  -- it) was cracked this session (see EntityStructLayout.lua's own
  -- PLAYER_FACING_BIT doc comment and ScriptOpcodeTable.lua's
  -- ACTOR_ACTION_HANDLER_ADDRESS_80 entry): it's a plain read of the
  -- player's facing byte, which this project already tracks (Player
  -- .lua's self.facing) -- 0x80 is now a registered handler and
  -- correctly falls out as status = "decoded" below.
  --
  -- REMOVED (task #126 consolidation, request to consolidate, document,
  -- and build into the app/website): 0x10DC (0xBC) and 0x1046 (0xBD)
  -- used to live here with stale "not yet decoded" notes -- 0xBC/0xBD/
  -- 0xBE (the whole palette-fade family) were fully disassembled and
  -- wired (StandardScriptHandlers.paletteFadeCycle, task #125) -- they
  -- now correctly fall out as status = "decoded" below. Leaving the
  -- stale notes in would have been actively misleading: a "decoded"
  -- opcode showing a "not yet decoded" note is a visible self-
  -- contradiction on the website.
  --
  -- ADDED (same consolidation pass): 0xEC/0xED/0xEE ($0E73/$0E77/
  -- $0E7B) and 0xBA ($0EB2) were already fully traced and deliberately
  -- left unwired earlier (see ScriptOpcodeTable.lua's own doc comments
  -- at each address for the complete disassembly this summarizes) but
  -- were never added here -- so the website was showing them as plain
  -- "undecoded" instead of "known-hard" (traced, deliberately
  -- deferred, with a real reason). Found and fixed while consolidating
  -- task #126 (the 0xF3 5-byte-release fix, which made
  -- BossSequenceInterpreter progress far enough to land exactly on
  -- 0xED/$0E77 as its new honest stopping point -- concrete
  -- confirmation this family is real and reachable).
  [0x0E73] = "Third confirmed sibling of the known-hard $02AB family (with 0x80/0xEC/0xEE): dereferences the task-#85 cross-actor pointer ($C3FE/$C3FF) one further level (+0), then calls $02AB (a masked read of the player's own real facing byte -- itself fully understood). Left unwired because WHICH bank/pointer gets staged into $C3F0/$C3FE/$C3FF for a given real scene is genuinely DATA-DEPENDENT, and this project has no live player-entity WRAM simulation to compute it with -- expected to remain known-hard permanently, not a sign of unfinished work.",
  [0x0E77] = "Second confirmed sibling of the known-hard $02AB family (offset +1 instead of 0xEC's +0) -- same real mechanism/blocker as 0x0E73 above. Directly confirmed reachable 2026-08-15: BossSequenceInterpreter's own real boss-defeat script lands here as its new, further, honest stopping point once the 0xF3 5-byte-release fix (task #126) is wired.",
  [0x0E7B] = "Fourth confirmed sibling of the known-hard $02AB family (offset +2 instead of 0xEC's +0) -- same real mechanism/blocker as 0x0E73 above.",
  [0x0EB2] = "A real, fully-traced $D499-driven 2-step entity-lifecycle state machine (step0 allocates a real entity slot via the already-known $0A74 primitive, calls $2F03; step1 calls $2ED3 -- real halt if not ready -- else despawns the slot via $0AE3). Both $2F03/$2ED3 resolve to real cases of the already-mapped $1ED7 bank-1 dispatcher. Genuinely known-hard NOT because the mechanism is opaque (it's real, traced, decodable ROM code) but because fully resolving \"ready\" needs the $52CD sub-table's own untraced targets AND a live entity/OAM lifecycle simulation this project doesn't have.",

  -- ADDED (direct user request to decode the missing opcodes): 0xA4
  -- ($01C1) was already fully traced and deliberately left unwired
  -- earlier (see ScriptOpcodeTable.lua's own doc comment) but, like
  -- the entries above before task #126's consolidation pass, was
  -- never added here -- so it was showing as plain "undecoded"
  -- instead of "known-hard," and was in fact this project's single
  -- largest undecoded blocker by script count (17/1357) once this
  -- session's other opcode-family fixes cleared the earlier ones out
  -- of the way. 0x8A ($15FB) is a new find this same pass -- a sixth
  -- confirmed sibling of the same family, reached even more directly
  -- than 0xA4's own indirection.
  [0x01C1] = "Fifth confirmed sibling of the known-hard $02AB family (via a NEW indirection path: $01CA -> real $1ED7 selector 0x08 -> $50F9, which does PUSH DE / CALL $02AB / CALL $28F0 / POP DE / RET NZ -- a genuine real conditional halt gated on $02AB's own result). Same real mechanism/blocker as 0x0E73 above -- needs live player-entity WRAM simulation this project doesn't have.",
  [0x15FB] = "Sixth confirmed sibling of the known-hard $02AB family, reached MOST directly of all of them: $1588 is PUSH HL / CALL $02AB / POP HL / BIT 7,A / RET Z -- a real halt gated straight on $02AB's own bit 7, no further indirection. The outer opcode genuinely halts (never reaches $3727) for as long as that bit stays set. Same real mechanism/blocker as 0x0E73 above.",
}

local opcodes = {}
for opcodeIndex = 0, 255 do
  local addr = opcodeEntries[opcodeIndex + 1]
  local status
  if addr == ScriptOpcodeTable.DEFAULT_HANDLER_ADDRESS then
    status = "default"
  elseif runtime.interp.handlers[addr] then
    status = "decoded"
  elseif KNOWN_HARD[addr] then
    status = "known-hard"
  else
    status = "undecoded"
  end
  local names = addressToNames[addr]
  opcodes[#opcodes + 1] = {
    opcode = opcodeIndex,
    handler = addr,
    status = status,
    names = names,
    note = KNOWN_HARD[addr],
  }
end
writeJs("opcodes.js", "OPCODES", opcodes,
  "Real per-opcode decode status for all 256 primary script opcodes -- 'decoded' means ScriptRuntime actually has a registered Lua handler for that real ROM address (checked by building a live ScriptRuntime, not hand-classified); 'default' is the real ROM-confirmed no-op; 'known-hard' is traced but deliberately unwired (see the 'note' field); 'undecoded' is genuinely open.")

----------------------------------------------------------------------
-- 4c. Opcode 0x04's own control-code sub-system (tasks #141-147).
-- These are not entries in the primary 256-opcode table above --
-- they're byte values (0x10-0x1F) opcode 0x04's own classifier (see
-- StandardScriptHandlers.tick) reads directly from the live script
-- cursor while already dispatched, matching the ROM's own $38F6 jump
-- table (SUB $10 before lookup). Curated, not code-derived (this data
-- doesn't live in a Lua table this project can walk mechanically --
-- it's the direct product of live mgba tracing + static disassembly)
-- -- see docs/reverse-engineering/events.md's own dated task #141-147
-- entries for the full evidence trail behind every claim below.
----------------------------------------------------------------------
do
  local CONTROL_CODES = {
    {
      byte = 0x10, title = "Modus-Register setzen",
      handler = "$34E7",
      status = "occurrence-specific",
      note = "Setzt $D84A=6, dann CONDITIONAL `CALL Z,$36D0` -- die reale Bedingung ($3627, ein bank-2-Aufruf) ist nicht nachverfolgt. Live bestätigt: PINNT bei Cursor 0x61e3, PINNT NICHT bei einer früheren Vorkommnis (Cursor 0x61bc) im selben echten Durchlauf -- selbe Byte-Wert, unterschiedliches reales Verhalten.",
    },
    {
      byte = 0x11, title = "Pacing-Gate (echter $D853-Bit-7-Takt)",
      handler = "$34F4",
      status = "live-confirmed (pacing only)",
      note = "Pausiert für live bestätigte 9 echte Ticks ($D853 Bit 7), dann `CALL $36D0` unconditional. Ob das Pinnen (Rückkehr zu Opcode 0x04) für JEDE reale Vorkommnis gilt, ist NICHT bestätigt -- ein erster Versuch, das anzunehmen, brach eine andere, bereits funktionierende echte HEAL_LP-Dispatch -- zurückgesetzt auf den ehrlichen Standard (kein Pin).",
    },
    {
      byte = 0x12, title = "Bank-2-Bedingung -> 0xFF Sub-Opcode 4",
      handler = "$3502 -> $350F",
      status = "occurrence-specific (156 echte Ticks)",
      note = "Bedingt (`$1ED1`, ein realer Bank-2-Funktionsaufruf-Trampolin) Brücke in 0xFF Sub-Opcode 4. Live-getraced: genau 156 echte Ticks Pause für DIESE Vorkommnis (Cursor 0x6206), dann unconditional Rückkehr zu Opcode 0x04 via $36D0. Bank 2s eigene interne Berechnung nicht nachverfolgt (bewusst zurückgestellt, wie bei anderen $1F06-Aufrufen dieses Projekts).",
    },
    {
      byte = 0x14, title = "Namenseinfügung -> 0xFF Sub-Opcode 1",
      handler = "$357D",
      status = "occurrence-specific (1 echter Tick)",
      note = "Brücke in 0xFF Sub-Opcode 1 für GENAU EINEN echten Tick ($D85A kurzzeitig =0xFF, live bestätigt), dann Rückkehr zu Opcode 0x04 zwei echte Bytes weiter. Die echte Namenseinfügung selbst (Heldenname) wird NICHT modelliert -- nur die korrekte Cursor-Fortsetzung.",
    },
    {
      byte = 0x1a, title = "NEWLINE_BYTE (Zeilenumbruch)",
      handler = "$35B0",
      status = "generalisiert, sicher",
      note = "UNCONDITIONAL `CALL $36D0` (kein Gate, anders als 0x10) -- vollständige Disassemblierung bestätigt: sicher für JEDE reale Vorkommnis zu verallgemeinern. Bereits unabhängig durch TextDecoder.lua's eigene, komplett getrennte Reverse-Engineering bestätigt (echte Kreuzvalidierung).",
    },
    {
      byte = 0x1b, title = "Cursor-Setup -> 0xFF Sub-Opcode 2",
      handler = "$35C1 -> $3648",
      status = "occurrence-specific (1 echter Tick)",
      note = "Setzt reale $D8B2-$D8B5 Cursor-Position-Zellen, dann Brücke in 0xFF Sub-Opcode 2 für GENAU EINEN echten Tick (live bestätigt), dann Rückkehr zu Opcode 0x04. $3648 enthält selbst eine reale Bedingung ($D84A==0?) für einen weiteren, nicht verfolgten Pfad -- daher nur für DIESE Vorkommnis (Cursor 0x6207) übernommen, nicht verallgemeinert.",
    },
  }
  writeJs("control-codes.js", "CONTROL_CODES", CONTROL_CODES,
    "Control-code sub-system opcode 0x04's own classifier dispatches through (script byte values 0x10-0x1F, not separate top-level opcodes -- see StandardScriptHandlers.tick's own doc comment). Found and fixed (tasks #141-147) via live mgba tracing + static disassembly -- 'occurrence-specific' means this project only claims the behavior for the one live-traced cursor cited, not every occurrence of that byte value (two self-caught over-generalizations this session -- 0x10 and 0x11 -- both broke already-working dispatches when assumed universal). With all confirmed here wired, BossSequenceInterpreter now runs the entire remaining boss-defeat script and reaches the opcode 0x00 queue-gate (see docs/reverse-engineering/events.md) -- the same landmark this investigation started from.")
end

----------------------------------------------------------------------
-- 4b. Script-tracer EXAMPLES (direct user request to show the whole
--     script mechanism in the app more intuitively, maybe with an
--     example script to follow along). Two already-decoded, short
--     event scripts from the room catalog (MapTable
--     .tryDecodeActorAction's own examples this session) -- small
--     enough to walk through opcode-by-opcode without needing to port
--     ScriptRuntime to JS. Only file offsets are exported (never raw
--     ROM bytes, same "never ship ROM content" convention every other
--     page here follows) -- the client reads and decodes live from
--     the user's own locally loaded ROM file.
----------------------------------------------------------------------
local function headerFileOffsetFor(mapTable, recordIndex)
  local records = MapTable.decode(romData, mapTable)
  local record = records[recordIndex + 1]
  local headerAddr = record.headerAddr
  return mapTable.bankFileStart + (headerAddr - 0x4000)
end
local scriptExamples = {
  {
    id = "actor-action",
    title = "Bank-5-Raum 0: ein Actor-Action-Ereignis-Skript",
    scriptFileOffset = headerFileOffsetFor(profile.mapTable, 0),
    -- Real, already-verified this session (see MapTable.lua's own
    -- "NAMING CORRECTED" doc comment + events.md's dated writeup):
    -- opcode $76 resolves to handler $152C, matching the ALREADY-
    -- documented ACTOR_ACTION family shape byte for byte.
  },
  {
    id = "default-fallthrough",
    title = "Bank-5-Raum 1: ein Opcode ist No-Op, das Skript geht zum nächsten Byte weiter",
    scriptFileOffset = headerFileOffsetFor(profile.mapTable, 1),
    -- Real: opcode $7C resolves to the ROM-confirmed DEFAULT_HANDLER
    -- (a genuine no-op) -- the interpreter does NOT stop, it reads the
    -- next byte ($00) as the next real opcode, which resolves to the
    -- ALREADY fully-decoded QUEUE_GATE_HANDLER_ADDRESS ($3297, opcode
    -- 0x00 -- a real conditional halt on the script continuation
    -- queue, this project's own already-implemented mechanism). A
    -- complete, well-understood 2-opcode chain, not an open ending.
  },
}
writeJs("script-example.js", "SCRIPT_EXAMPLES", scriptExamples,
  "2 real, curated example event scripts for the Skript-Opcode-Explorer's own interactive step-tracer -- only real ROM file offsets, decoded live client-side from the user's own loaded ROM (never shipped ROM bytes). See MapTable.lua's own 'NAMING CORRECTED' doc comment and events.md's dated writeup for the full evidence these bytes really are script bytecode.")

----------------------------------------------------------------------
-- 5. Whole-corpus scan results (same method as scripts/scan_all_scripts.lua)
----------------------------------------------------------------------
local spt = profile.scriptPointerTable
local FILLER, CLEAN, HALT_UNDECODED, ERROR_OTHER = "filler", "clean", "halt_undecoded", "error_other"
local haltCounts = {}
local statusCounts = { [FILLER] = 0, [CLEAN] = 0, [HALT_UNDECODED] = 0, [ERROR_OTHER] = 0 }
local stepBudget = 500
for index = 0, spt.recordCount - 1 do
  local resolved = ScriptPointerTable.resolve(romData, spt, index)
  if not resolved then
    statusCounts[FILLER] = statusCounts[FILLER] + 1
  else
    local stream = RomScriptStream.forFileOffset(romData, resolved.bank * 0x4000)
    local shadowRuntime = ScriptRuntime.new(opcodeEntries, stubCtx)
    local ok, err = pcall(function()
      shadowRuntime:run(stream, resolved.cpuAddress, stepBudget)
    end)
    if not ok then
      statusCounts[ERROR_OTHER] = statusCounts[ERROR_OTHER] + 1
    elseif shadowRuntime.stopped then
      local addrHex = tostring(shadowRuntime.stopError):match("real ROM handler (0x%x+)")
      if addrHex then
        statusCounts[HALT_UNDECODED] = statusCounts[HALT_UNDECODED] + 1
        haltCounts[addrHex] = (haltCounts[addrHex] or 0) + 1
      else
        statusCounts[ERROR_OTHER] = statusCounts[ERROR_OTHER] + 1
      end
    else
      statusCounts[CLEAN] = statusCounts[CLEAN] + 1
    end
  end
end
local haltList = {}
for addrHex, count in pairs(haltCounts) do
  local addrNum = tonumber(addrHex)
  haltList[#haltList + 1] = { address = addrHex, count = count, names = addressToNames[addrNum], note = KNOWN_HARD[addrNum] }
end
table.sort(haltList, function(a, b) return a.count > b.count end)
local top = {}
for i = 1, math.min(30, #haltList) do top[i] = haltList[i] end
writeJs("scan-results.js", "SCAN_RESULTS", {
  totalScripts = spt.recordCount,
  stepBudget = stepBudget,
  clean = statusCounts[CLEAN],
  haltUndecoded = statusCounts[HALT_UNDECODED],
  errorOther = statusCounts[ERROR_OTHER],
  filler = statusCounts[FILLER],
  topBlockers = top,
}, "Real, live whole-corpus shadow-run result -- every real scriptPointerTable entry (all 1357), run through the CURRENT opcode coverage. Same method as scripts/scan_all_scripts.lua.")

----------------------------------------------------------------------
-- 6. Room graph
----------------------------------------------------------------------
local rooms = {}
for name, room in pairs(profile.graphics) do
  if type(room) == "table" and room.exits then
    local exits = {}
    for _, exit in ipairs(room.exits) do
      exits[#exits + 1] = {
        status = exit.status,
        targetRoom = exit.targetRoom,
        transitionType = exit.transition and exit.transition.type,
        axis = exit.transition and exit.transition.axis,
        totalPixels = exit.transition and exit.transition.totalPixels,
        reverse = exit.transition and exit.transition.reverse or false,
        -- Real, empirically-bracketed screen-space trigger rectangle
        -- (any bound may be nil -- "unbounded on that side", see
        -- rom_profiles.lua's own exits schema doc comment) and the
        -- real landing position in the target room, both already
        -- decoded upstream -- exported as-is so the website can draw
        -- an arrow from the actual trigger zone to the actual spawn
        -- point instead of a generic node-to-node line.
        zone = exit.zone,
        landingX = exit.landingX,
        landingY = exit.landingY,
      }
    end
    local widthTiles, heightTiles
    if room.grid then
      heightTiles = #room.grid
      widthTiles = room.grid[1] and #room.grid[1]
    end
    rooms[#rooms + 1] = {
      name = name, widthTiles = widthTiles, heightTiles = heightTiles, exits = exits,
      -- Structured cross-reference (currently only fifthRoom) -- see
      -- rom_profiles.lua's `sameRomIdentityAs`/`sameRomIdentityNote`
      -- doc comment: a live-confirmed byte-identical WRAM room-identity
      -- register match to another already-named room, not a generic
      -- "similar tileset" guess.
      sameRomIdentityAs = room.sameRomIdentityAs,
      sameRomIdentityNote = room.sameRomIdentityNote,
      -- Structured world-map catalog cross-reference (currently
      -- startRoom/fourthRoom) -- see rom_profiles.lua's
      -- `worldMapCatalogRecord` doc comment: this room's presence in
      -- the bank6 (8x8) world-map catalog at the given grid position,
      -- live-verified cell-by-cell against the ROM file offsets.
      worldMapCatalogRecord = room.worldMapCatalogRecord,
      -- Structured dispute flag (currently seventhRoom/eighthRoom/
      -- ninthRoom) -- see rom_profiles.lua's `tilesetDisputed`/
      -- `tilesetDisputedNote` doc comment: a credible user report that
      -- this room's catalog-derived tileset is wrong, investigated but
      -- unresolved -- distinct from the general "IMPLEMENTATION
      -- CHOICE, not independently confirmed" status every catalog room
      -- carries.
      tilesetDisputed = room.tilesetDisputed,
      tilesetDisputedNote = room.tilesetDisputedNote,
    }
  end
end
-- VERIFIED rooms that exist as genuine ROM screens but have no
-- live-traced `exits` field of their own and are never any other
-- room's `targetRoom` -- the exits-only loop above would otherwise
-- silently omit them from the graph. `startRoom` is the current case:
-- it's the room `Field.lua`/`BattleIntro.lua` use for the live FIRST
-- boss fight ("Kaempfe!" sequence, own gate/entranceSeal tile-patch
-- mechanics) -- a verified room, real tile grid + ROM offsets. Its
-- onward connection into the willyRoom -> ... -> ninthRoom exit chain
-- (reachable only via the separate VictorySequence/RoomExplorer debug
-- walker, not normal Field.lua play -- see main.lua's state wiring)
-- was never live-traced, so it has no `exits` entry. Exported here as
-- its own honestly DISCONNECTED node (empty `exits`, a `note`
-- explaining why) instead of being silently left off the map.
local ISOLATED_BUT_REAL_ROOMS = { "startRoom" }
local roomNamesSoFar = {}
for _, r in ipairs(rooms) do roomNamesSoFar[r.name] = true end
for _, name in ipairs(ISOLATED_BUT_REAL_ROOMS) do
  local room = profile.graphics[name]
  if room and not roomNamesSoFar[name] then
    local widthTiles, heightTiles
    if room.grid then
      heightTiles = #room.grid
      widthTiles = room.grid[1] and #room.grid[1]
    end
    rooms[#rooms + 1] = {
      name = name, widthTiles = widthTiles, heightTiles = heightTiles, exits = {},
      worldMapCatalogRecord = room.worldMapCatalogRecord,
      note = "Echter, VERIFIED Raum (rom_profiles.lua) -- hostet den echten ersten Bosskampf " ..
        "(BattleIntro.lua's reale \"Kaempfe!\"-Sequenz). Keine live entdeckte Verbindung zur " ..
        "willyRoom-Kette (die ihrerseits nur ueber den separaten VictorySequence/RoomExplorer-" ..
        "Debug-Walker erreichbar ist, nicht ueber den normalen Field.lua-Spielfluss) -- ehrlich " ..
        "als eigenstaendiger Knoten ohne Pfeile gezeigt, nicht weggelassen. Direkt bestaetigt " ..
        "(2026-08-17, direkter Nutzerhinweis) als echter Eintrag im 8x8-Weltkarten-Katalog " ..
        "(mapTableBank6, Position 7,4) -- isoliert im Raum-Graphen (keine bekannte " ..
        "Spielfluss-Verbindung), aber KEIN erfundener/losgeloester Raum.",
    }
  end
end
-- Attach per-room cross-reference/dispute flags (`sameRomIdentityAs`/
-- `sameRomIdentityNote` -- fifthRoom; `tilesetDisputed`/
-- `tilesetDisputedNote` -- seventhRoom/eighthRoom/ninthRoom;
-- `worldMapCatalogRecord` -- startRoom/fourthRoom; see rom_profiles.lua's
-- own doc comments) to their room's ROOMS[] entry -- generic over any
-- room carrying these fields, not a hardcoded name list. Also handles
-- LEAF rooms (fifthRoom/ninthRoom, no `exits` of their own, so never
-- went through the main loop above) so a flag doesn't disappear just
-- because its room has no outgoing exit.
for name, room in pairs(profile.graphics) do
  if type(room) == "table" and (room.sameRomIdentityAs or room.tilesetDisputed or room.worldMapCatalogRecord or room.bridgeNote or room.mergeInto) then
    local found = nil
    for _, r in ipairs(rooms) do
      if r.name == name then found = r end
    end
    if found then
      found.sameRomIdentityAs = room.sameRomIdentityAs
      found.sameRomIdentityNote = room.sameRomIdentityNote
      found.tilesetDisputed = room.tilesetDisputed
      found.tilesetDisputedNote = room.tilesetDisputedNote
      found.worldMapCatalogRecord = found.worldMapCatalogRecord or room.worldMapCatalogRecord
      found.bridgeNote = room.bridgeNote
      found.mergeInto = room.mergeInto
    else
      local widthTiles, heightTiles
      if room.grid then
        heightTiles = #room.grid
        widthTiles = room.grid[1] and #room.grid[1]
      end
      rooms[#rooms + 1] = {
        name = name, widthTiles = widthTiles, heightTiles = heightTiles, exits = {},
        sameRomIdentityAs = room.sameRomIdentityAs,
        sameRomIdentityNote = room.sameRomIdentityNote,
        tilesetDisputed = room.tilesetDisputed,
        tilesetDisputedNote = room.tilesetDisputedNote,
        worldMapCatalogRecord = room.worldMapCatalogRecord,
        bridgeNote = room.bridgeNote,
        mergeInto = room.mergeInto,
      }
    end
  end
end
table.sort(rooms, function(a, b) return a.name < b.name end)
writeJs("rooms.js", "ROOMS", rooms,
  "Every room with decoded exits -- read from rom_profiles.lua's graphics.<room>.exits (empirically-found trigger zones + transition shape + target room). A few VERIFIED rooms with no live-traced exits (currently: startRoom, the first-boss-fight room) are still included as their own honestly-disconnected node via ISOLATED_BUT_REAL_ROOMS below, rather than silently omitted. Rooms with a live-confirmed sameRomIdentityAs cross-reference (currently: fifthRoom, sixthRoom) carry that field regardless of their own exits. Rooms with a live-confirmed worldMapCatalogRecord (currently: startRoom at (7,4), fourthRoom at (7,5) -- see rom_profiles.lua's doc comment) carry the bank6 8x8 world-map grid position they were found at, independent of whether they're isolated in this play-flow graph. `bridgeNote` (currently: fourthRoom, 2026-08-18) flags a room whose own exits both terminate in already-known territory (via other rooms' sameRomIdentityAs) -- a junction, not a lead toward new content. `mergeInto` (currently: fifthRoom->thirdRoom, sixthRoom->startRoom, 2026-08-18, direct repeated user report the badge-only approach still showed them as separate boxes) tells the room-system graph renderer to redirect the room's own incoming edges to the named target and NOT render it as its own node at all -- a real merge, not just a visual flag.")

----------------------------------------------------------------------
-- 6b. Room MAPS (grid + tileOffsets) -- for the Tile/Map viewers. Only
--     tile IDs/offsets/grid are exported; the 16-byte tile PIXEL data
--     is never embedded -- the viewer decodes it live from a ROM file
--     the user supplies locally in their own browser (this project
--     never ships ROM bytes, same convention as RomLocator.lua).
----------------------------------------------------------------------
local roomMaps = {}
for name, room in pairs(profile.graphics) do
  if type(room) == "table" and room.grid and room.tileOffsets then
    local tileOffsets = {}
    for tileId, off in pairs(room.tileOffsets) do
      if type(off) == "string" then
        -- A handful of tiles are stored as a literal 16-byte pattern
        -- rather than a ROM file offset (e.g. fourthRoom/sixthRoom's
        -- tile 128, a known-solid tile with no single canonical ROM
        -- address) -- exported as raw byte VALUES so the viewer can
        -- render it without a ROM offset to dereference.
        assert(#off == 16, "export_data.lua: literal tile pattern must be exactly 16 bytes")
        local bytes = {}
        for i = 1, 16 do bytes[i] = off:byte(i) end
        tileOffsets[tostring(tileId)] = { literal = bytes }
      else
        tileOffsets[tostring(tileId)] = off
      end
    end
    roomMaps[#roomMaps + 1] = {
      name = name,
      cols = room.grid[1] and #room.grid[1] or 0,
      rows = #room.grid,
      grid = room.grid,
      tileOffsets = tileOffsets,
      floorTileIds = room.floorTileIds,
    }
  end
end
table.sort(roomMaps, function(a, b) return a.name < b.name end)
writeJs("room-maps.js", "ROOM_MAPS", roomMaps,
  "Every decoded room/screen tilemap (grid of tile IDs + tile ID -> ROM file offset lookup) -- read from rom_profiles.lua's graphics.<name>.grid/tileOffsets. No tile PIXEL data is embedded -- the Tile/Map viewer pages decode it live from a user-supplied ROM file, entirely client-side.")

----------------------------------------------------------------------
-- 6c. Room CATALOG -- all 320 individually-decodable bank-5/bank-6
--     map-table records, not just the 8 rooms real gameplay reaches.
--     Reuses the same pipeline `src/app/states/RoomExplorer.lua`'s
--     dev-only F8 browser already drives live in the LÖVE app
--     (`RoomFloorLayout.buildRoomFromMapTableRecord` +
--     `toTileGridBackgroundData`) -- no new discovery here, just
--     exporting an already-verified capability as static site data so
--     it's browsable without a live LÖVE session.
--
--     HONEST SCOPE: all 320 records render through
--     `genericCatalogMetatileTableFileOffset` -- a structurally-
--     justified default, not the earlier `unknownRoomACandidates`-
--     borrowed placeholder. Derivation: `roomSelectorTable`'s record
--     0/1 (bank5's and bank6's "map", verified via
--     `RoomSelectorTable.resolveMapRoomPointersFileOffset`'s exact
--     byte match to each table's header) share one `tileSourcePointer`,
--     cross-checked against the external FFA-Disassembly project's
--     documented "one tileset per map, no per-room override" US-ROM
--     architecture. Real, but not independently ground-truth-verified
--     -- no live gameplay reaches these 320 rooms. See rom_profiles.lua's
--     doc comments and rom-map.md's "World scope" sections for the
--     full evidence chain.
--
--     `actorAction` field: each record's "header" bytes are a per-room
--     EVENT SCRIPT (see MapTable.lua's "NAMING CORRECTED" doc comment)
--     -- `MapTable.tryDecodeActorAction` extracts the `(group, action)`
--     pair when a record's script matches the known "ACTOR_ACTION"
--     opcode family (`ScriptOpcodeTable.lua`'s `ACTOR_ACTION_HANDLER_
--     ADDRESS_*` constants -- an actor-command-queue mechanism,
--     `$C4E0`/`$C5A0` -- NOT room-selection, spawn-coordinate, or TILE
--     data). `nil` for records whose script doesn't match this family.
----------------------------------------------------------------------
local roomCatalog = {}
local catalogMetatileTableFileOffset =
  profile.roomFloorLayoutPipeline.genericCatalogMetatileTableFileOffset
local function exportCatalogSource(mapTable, sourceLabel)
  local opts = {
    metatileTableFileOffset = catalogMetatileTableFileOffset,
    tilesetFileOffset = mapTable.tilesetFileOffset,
    metatileGridRows = 8,
    metatileGridCols = 10,
  }
  local records = MapTable.decode(romData, mapTable)
  for recordIndex = 0, mapTable.recordCount - 1 do
    local fileOffsetGrid = RoomFloorLayout.buildRoomFromMapTableRecord(romData, mapTable, recordIndex, opts)
    local room = RoomFloorLayout.toTileGridBackgroundData(fileOffsetGrid, opts.tilesetFileOffset)
    local tileOffsets = {}
    for tileId, off in pairs(room.tileOffsets) do
      tileOffsets[tostring(tileId)] = off
    end
    local record = records[recordIndex + 1]
    local actorAction = record and record.header and
      MapTable.tryDecodeActorAction(romData, record.header, opcodeEntries)
    roomCatalog[#roomCatalog + 1] = {
      name = string.format("%s-record-%03d", sourceLabel, recordIndex),
      source = sourceLabel,
      recordIndex = recordIndex,
      cols = room.grid[1] and #room.grid[1] or 0,
      rows = #room.grid,
      grid = room.grid,
      tileOffsets = tileOffsets,
      actorAction = actorAction, -- {group=N, action=N} or nil, see doc comment above
    }
  end
end
exportCatalogSource(profile.mapTable, "bank5")
exportCatalogSource(profile.mapTableBank6, "bank6")
-- bank7: the Templated (mode 1) encoding is CRACKED end to end
-- (base-room RLE template + per-record (value,position) diff, see
-- MapTable.lua's `readTemplatedHeader`/`applyTemplatedDiff` and
-- rom-map.md's "bank 7 Templated revisited, CRACKED"). Exercised
-- through the same `exportCatalogSource` helper as bank5/6 --
-- `RoomFloorLayout.buildRoomFromMapTableRecord` dispatches on the
-- map's header `encodingMode` internally, so this call site needed no
-- changes.
exportCatalogSource(profile.mapTableBank7, "bank7")
writeJs("room-catalog.js", "ROOM_CATALOG", roomCatalog,
  "All 384 individually-decodable bank-5 (256 RLE records) + bank-6 (64 RLE records) + bank-7 (64 Templated records, CRACKED) map-table entries -- the same pipeline RoomExplorer.lua's dev-only F8 browser drives live in the LÖVE app, exported here as static data. Every entry renders through genericCatalogMetatileTableFileOffset, a structurally-derived default (roomSelectorTable's record 0/1, cross-checked against the external FFA-Disassembly project's documented 'one tileset per map' architecture) -- not the unverified unknownRoomA-borrowed placeholder used before. Still not independently ground-truth-verified (no live gameplay reaches these 384 rooms). bank7's per-record diff format (base template + (value,position) overrides) is separately VERIFIED against all 64 records (566/566 valid diff positions, tile_entropy 1.30-1.40 bits, zero outliers) -- see rom_profiles.lua's `mapTableBank7` doc comment. `actorAction`: the (group,action) pair a record's per-room event script enqueues, when it matches the documented ACTOR_ACTION opcode family -- an actor-command-queue mechanism, NOT tile/graphics data. See rom_profiles.lua's doc comments and rom-map.md's 'World scope' sections for the full evidence chain.")

writeJs("font-tileset.js", "FONT_TILESET", {
  fileOffset = profile.graphics.font.fileOffset,
  bank = profile.graphics.font.bank,
  tileCount = profile.graphics.font.tileCount,
  rowGlyphs = profile.graphics.font.rowGlyphs,
}, "The VERIFIED font tileset location -- rom_profiles.lua's graphics.font.")

----------------------------------------------------------------------
-- 7. Text decoder tables
----------------------------------------------------------------------
local umlauts = {}
for byte, ch in pairs(TextDecoder.UMLAUT_PARTIAL) do
  umlauts[#umlauts + 1] = { byte = byte, char = ch }
end
table.sort(umlauts, function(a, b) return a.byte < b.byte end)
local digraphs = {}
for byte, pair in pairs(TextDecoder.DIGRAPH_PARTIAL) do
  digraphs[#digraphs + 1] = { byte = byte, chars = pair }
end
table.sort(digraphs, function(a, b) return a.byte < b.byte end)

-- Byte samples straight from the ROM (not hand-typed) -- read until a
-- TERMINATOR_BYTE (or 40 bytes, as a safety cap) starting at each
-- already-VERIFIED text file offset.
local function readRealSample(fileOffset, label)
  local bytes = {}
  local i = fileOffset
  while i < #romData and #bytes < 40 do
    local b = romData:byte(i + 1)
    bytes[#bytes + 1] = b
    if b == TextDecoder.TERMINATOR_BYTE then break end
    i = i + 1
  end
  local decoded = TextDecoder.decodeString(romData, fileOffset)
  return { label = label, fileOffset = fileOffset, bytes = bytes, decoded = decoded }
end
local textSamples = {
  readRealSample(profile.messageTextPointer.verifiedExample.textFileOffset,
    "messageID 13 (\"gefunden\" item-pickup text)"),
  readRealSample(0x3A268, "the real dump this project's digraph table was built from (starts on a literal \"WILLY\")"),
  readRealSample(profile.graphics.introText.fileOffset, "intro scroll text"),
}

writeJs("text-decoder.js", "TEXT_DECODER", {
  samples = textSamples,
  mainGlyphs = TextDecoder.MAIN_GLYPHS,
  mainBase = TextDecoder.MAIN_BASE,
  spaceByte = TextDecoder.SPACE_BYTE,
  terminatorByte = TextDecoder.TERMINATOR_BYTE,
  periodByte = TextDecoder.PERIOD_BYTE,
  hyphenByte = TextDecoder.HYPHEN_BYTE,
  newlineByte = TextDecoder.NEWLINE_BYTE,
  exclamationByte = TextDecoder.EXCLAMATION_BYTE,
  questionByte = TextDecoder.QUESTION_BYTE,
  colonByte = TextDecoder.COLON_BYTE,
  umlauts = umlauts,
  digraphs = digraphs,
}, "TextDecoder.lua tables -- see that file's doc comment for how each byte was cross-checked against live-decoded ROM text.")

----------------------------------------------------------------------
-- 11. Monster catalog (EnemySpeciesTable -- 11 species, ATK VERIFIED,
-- defCandidate1/2 real but not confirmed as a consumed stat -- see
-- combat.md). Only ONE species has a known sprite location (the
-- tutorial "gate creature"); the rest are honestly flagged as
-- "graphic unknown", not guessed.
----------------------------------------------------------------------
local function bytesToArray(raw)
  local out = {}
  for i = 1, #raw do out[i] = raw:byte(i) end
  return out
end

do
  local rows = EnemySpeciesTable.decode(romData, profile.enemySpeciesTable)
  local species = EnemySpeciesTable.groupBySpecies(rows)
  local monsters = {}
  local KNOWN_SPRITE_ROW = profile.enemySpeciesTable.verifiedExample
    and profile.enemySpeciesTable.verifiedExample.rowIndex
  for i, s in ipairs(species) do
    monsters[i] = {
      speciesIndex = i - 1,
      firstRowIndex = s.firstRowIndex,
      rowCount = s.count,
      flagVariant = s.row.flagVariant,
      atk = s.row.atk,
      defCandidate1 = s.row.defCandidate1,
      defCandidate2 = s.row.defCandidate2,
      rawBytes = bytesToArray(s.row.raw),
      -- true only for the one species actually fought, with a live
      -- sprite location captured (see rom_profiles.lua's `enemySprite`
      -- field) -- every other species has no known graphic yet.
      knownSprite = (KNOWN_SPRITE_ROW ~= nil) and (s.firstRowIndex - 1 <= KNOWN_SPRITE_ROW)
        and (KNOWN_SPRITE_ROW < s.firstRowIndex - 1 + s.count) or false,
    }
  end
  local es = profile.graphics and profile.graphics.enemySprite

  -- Found via external-reference byte matching against the US "Final
  -- Fantasy Adventure" disassembly -- see EnemyStatTable.lua's doc
  -- comment for the full evidence trail. A SEPARATE table from the
  -- species table above (own file offset, own 24-byte stride) -- 21
  -- named bosses with speed/HP-formula-input/XP/gold, all confirmed
  -- byte-for-byte against the external reference.
  local bosses = {}
  if profile.enemyStatTable then
    local bossRows = EnemyStatTable.decode(romData, profile.enemyStatTable)
    local names = profile.enemyStatTable.externalReferenceNames or {}
    for i, r in ipairs(bossRows) do
      -- `MonsterDefinitionTable` (SpriteTileFormula.lua) is the exact
      -- same table as `enemyStatTable` here -- same bank, same file
      -- base (0x10739/CPU 0x4739), same 24-byte stride, same 21 rows,
      -- found independently (see EnemyStatTable.lua's "SAME TABLE" doc
      -- comment). So boss row `i-1` (0-based) IS MonsterDefinitionTable
      -- record `i-1` -- every one of these 21 named story bosses gets
      -- its own sprite tiles, not just the 1 (row 16, "Jackal")
      -- independently live-verified. Shown regardless of
      -- arrangementConfirmed status -- honestly badged, not hidden.
      --
      -- Pose arrangement: `resolveSpriteTileOffsets` reorders every
      -- 16-tile chunk that structurally matches species 4's already-
      -- known pose shape (see SpriteTileFormula.CREATURE_4X4_POSE_
      -- PERMUTATION's doc comment) -- `spriteChunksReordered`/
      -- `spriteChunksTotal` expose exactly how many of this boss's
      -- animation-phase chunks got a confident arrangement, so the
      -- website can show an honest per-boss confidence instead of one
      -- blanket claim.
      local monsterRecord = MonsterDefinitionTable.readRecord(romData, i - 1)
      local spriteOffsets, spriteBank, chunksReordered, chunksTotal
      if monsterRecord then
        spriteOffsets, spriteBank, chunksReordered, chunksTotal =
          MonsterDefinitionTable.resolveSpriteTileOffsets(romData, monsterRecord)
      end
      -- Pose-by-pose presentation: species 4's website card shows one
      -- 4x4 canvas with switchable "Pose A"/"Pose B" tabs, not a tall
      -- concatenated strip. `spritePoses` gives the same shape for
      -- every other boss whose chunks are ALL confidently reconstructed
      -- (chunksReordered==chunksTotal>0) -- one 4x4 pose per array
      -- entry, in chunk order. Left nil (falls back to the flat strip
      -- view) for anything only partially or not at all reconstructed
      -- -- showing tabs would imply confidence this project doesn't
      -- have for those chunks.
      local spritePoses = nil
      if spriteOffsets and chunksReordered == chunksTotal and chunksTotal > 0 then
        spritePoses = {}
        for c = 0, chunksTotal - 1 do
          local pose = {}
          for k = 1, 16 do pose[k] = spriteOffsets[c * 16 + k] end
          spritePoses[c + 1] = pose
        end
      end
      bosses[i] = {
        index = i - 1,
        name = names[i],
        speed = r.speed,
        hpBase = r.hpBase,
        xp = r.xp,
        gold = r.gold,
        numObjects = r.numObjects,
        speciesByte = r.speciesByte,
        defeatBehaviorId = r.defeatBehaviorId,
        rawBytes = bytesToArray(r.raw),
        spriteTileOffsets = spriteOffsets,
        spriteBank = spriteBank,
        spriteArrangementConfirmed = (i - 1 == 16), -- the one row this project independently live-verified (see MonsterDefinitionTable.LIVE_CONFIRMED)
        spriteChunksReordered = chunksReordered or 0,
        spriteChunksTotal = chunksTotal or 0,
        spritePoses = spritePoses,
      }
    end
  end

  writeJs("monsters.js", "MONSTERS", {
    species = monsters,
    knownSprite = es and {
      tileOffsets = es.tileOffsets,
      cols = es.cols,
      rows = es.rows,
      screenX = es.screenX,
      screenY = es.screenY,
      -- The hardware X-flip toggle IS this creature's 2nd animation
      -- "frame" (a horizontal mirror of the same tiles, not a second
      -- drawn frame -- see rom_profiles.lua's `enemySprite.
      -- flipXTogglesPerStep` doc comment for the live OAM trace).
      -- Exposed explicitly so the website/CatalogExplorer can show
      -- both poses instead of just the un-flipped one.
      flipXTogglesPerStep = es.flipXTogglesPerStep or false,
    } or nil,
    bosses = bosses,
  }, "enemySpeciesTable rows (EnemySpeciesTable.lua), grouped into 11 distinct species. " ..
     "ATK is VERIFIED (live register match); defCandidate1/2 are real bytes with no confirmed " ..
     "consumer found after 4 independent leads (see combat.md) -- shown as raw data, not " ..
     "claimed to be a working DEF stat. Only 1 of 11 species has a known sprite (found via live " ..
     "OAM tracing during combat) -- honestly flagged per-species; that sprite's 2-pose animation " ..
     "(X-flip toggle) is included under knownSprite. `bosses` (EnemyStatTable.lua) is a SEPARATE " ..
     "table -- 21 named story bosses with speed/hpBase/xp/gold confirmed byte-for-byte against " ..
     "the US cartridge's public disassembly; hpBase is a PRNG-formula input, not flat starting " ..
     "HP (see that module's doc comment); speciesByte/defeatBehaviorId/numObjects are real bytes, " ..
     "not yet independently confirmed against this EU ROM's code. Each boss also carries " ..
     "`spriteTileOffsets` -- ROM pixel data via MonsterDefinitionTable/SpriteTileFormula.lua, " ..
     "since this table IS MonsterDefinitionTable (same file base/stride/row count, found " ..
     "independently). Shown for all 21 regardless of `spriteArrangementConfirmed` (only true for " ..
     "index 16, \"Jackal\" -- the one row independently live-OAM-verified); the other 20 show " ..
     "individually-correct pixels in the ROM's raw DMA copy order, an honestly unconfirmed " ..
     "on-screen arrangement.")
end

----------------------------------------------------------------------
-- 11b. Graphics candidates (GraphicsCandidates.lua) -- visually-
-- confirmed creature/character art regions found via a heuristic ROM
-- scan, NOT tied to any confirmed species/room/NPC identity. See that
-- module's doc comment for the full honest scope.
----------------------------------------------------------------------
do
  local candidates = {}
  for i, e in ipairs(GraphicsCandidates.ENTRIES) do
    candidates[i] = {
      id = e.id,
      bank = e.bank,
      fileOffset = e.fileOffset,
      tileCount = e.tileCount,
      cols = e.cols,
      rows = math.ceil(e.tileCount / e.cols),
      kind = e.kind,
      note = e.note,
      tileOffsets = GraphicsCandidates.tileOffsets(e),
    }
  end
  writeJs("graphics-candidates.js", "GRAPHICS_CANDIDATES", candidates,
    "Visually-confirmed candidate creature/character graphics regions -- found via " ..
    "tools/rom/scan_graphics.py's heuristic tile-entropy scan, then confirmed by rendering each " ..
    "one and looking at it (see GraphicsCandidates.lua's doc comment). NOT tied to any " ..
    "confirmed species/room/NPC/spawn-trigger identity -- shown as ROM art with an honest " ..
    "visual description, not a decoded fact.")
end

----------------------------------------------------------------------
-- 11d. Sprite catalog (SpriteTileFormula.lua) -- the ROM->VRAM
-- sprite-tile PIXEL SOURCE for every NPC (ActorDefinitionTable, 218
-- rows) and every monster/boss (MonsterDefinitionTable, 21 rows). See
-- SpriteTileFormula.lua's doc comment for the full disassembly/
-- live-validation. HONEST SCOPE, carried into every entry below: this
-- closes the PIXEL-SOURCE half for everyone. The on-screen ARRANGEMENT
-- has 3 honest tiers: `arrangementConfirmed=true` (characterA/
-- characterB/the first boss -- individually live-OAM-verified) beats
-- `arrangementFamily="humanoid4pose"` (172 further NPC records, 91
-- distinct designs, sharing characterA/B's exact copy-order list --
-- `resolveSpriteTileOffsets` already reorders these into the logical
-- pose order, a family-level not individually-verified finding) beats
-- plain unflagged (an honestly unknown on-screen layout, shown in raw
-- DMA copy order, not a guessed grid).
----------------------------------------------------------------------
do
  local function buildSpriteEntries(records, resolveFn, confirmedIndices)
    local entries = {}
    for _, record in ipairs(records) do
      -- `chunksReordered`/`chunksTotal` are only meaningful for
      -- MonsterDefinitionTable's creature-4x4-pose reconstruction --
      -- nil for ActorDefinitionTable/NPCs, which use
      -- `arrangementFamily` instead (a whole-record flag, not a
      -- per-chunk count).
      local offsets, _, chunksReordered, chunksTotal = resolveFn(romData, record)
      -- Pose-by-pose presentation for NPCs too: every `humanoid4pose`
      -- family record's `offsets` are already reordered into the
      -- logical pose order (4 tiles/pose, `resolveSpriteTileOffsets`
      -- -> `reconstructPoseOrder`, the same "swap the middle two" rule
      -- characterA/characterB's down/up/left/left2 poses use) --
      -- splitting them into consecutive 4-tile groups gives
      -- individually-correct poses in order, the same shape as species
      -- 4's `spritePoses` (4 tiles/pose instead of 16, matching this
      -- family's 16x16-not-32x32 sprite size).
      local spritePoses = nil
      if record.spriteSource.arrangementFamily == "humanoid4pose" and offsets and #offsets % 4 == 0 then
        spritePoses = {}
        for c = 0, (#offsets / 4) - 1 do
          local pose = {}
          for k = 1, 4 do pose[k] = offsets[c * 4 + k] end
          spritePoses[c + 1] = pose
        end
      end
      entries[#entries + 1] = {
        index = record.index,
        bank = record.spriteSource.bank,
        kindByte = record.spriteSource.kindByte,
        cByte = record.spriteSource.cByte,
        tileOffsets = offsets,
        arrangementConfirmed = confirmedIndices[record.index] or false,
        arrangementFamily = record.spriteSource.arrangementFamily,
        chunksReordered = chunksReordered,
        chunksTotal = chunksTotal,
        spritePoses = spritePoses,
      }
    end
    return entries
  end

  local npcEntries = buildSpriteEntries(
    ActorDefinitionTable.scanTable(romData), ActorDefinitionTable.resolveSpriteTileOffsets,
    { [121] = true, [99] = true }
  )
  local monsterEntries = buildSpriteEntries(
    MonsterDefinitionTable.scanTable(romData), MonsterDefinitionTable.resolveSpriteTileOffsets,
    { [16] = true }
  )
  writeJs("sprite-catalog.js", "SPRITE_CATALOG", { npcs = npcEntries, monsters = monsterEntries },
    "ROM->VRAM sprite-tile PIXEL SOURCE for every NPC (ActorDefinitionTable, 218 rows, index " ..
    "121=characterA/99=characterB confirmed) and every monster/boss (MonsterDefinitionTable, 21 " ..
    "rows, index 16=the first boss confirmed) -- see SpriteTileFormula.lua's doc comment for the " ..
    "full disassembly/live-validation. 172 further NPC records (91 distinct designs) carry " ..
    "arrangementFamily=\"humanoid4pose\" -- their tileOffsets are already reordered into the " ..
    "logical pose order (same family as characterA/characterB), a real but not individually " ..
    "live-verified confidence tier, distinct from arrangementConfirmed. HONEST SCOPE: tileOffsets " ..
    "are individually-correct ROM pixel data for every entry -- the on-screen ARRANGEMENT (which " ..
    "tile goes where) is only independently confirmed for the 3 arrangementConfirmed=true " ..
    "entries; every other NPC entry's tileOffsets are shown in the ROM's raw DMA copy order, an " ..
    "honestly unknown on-screen layout, not a guessed grid. Monster/boss entries carry " ..
    "`chunksReordered`/`chunksTotal` instead -- each 16-tile chunk (one animation pose) that " ..
    "structurally matches species 4's already-known pose shape is reordered into the on-screen " ..
    "layout; chunks that don't match stay in raw DMA order. `chunksReordered==chunksTotal` is the " ..
    "strongest tier (every pose reconstructed); `chunksReordered>0` means at least one pose is " ..
    "confidently arranged; `chunksReordered==0` means nothing could be confidently reordered.")
end

----------------------------------------------------------------------
-- 11c. Map tile catalog (MapTileCatalog.lua) -- the OPPOSITE of 11b:
-- every map/environment tile this project has already confirmed via a
-- fully-decoded, VERIFIED room (not a candidate). Dedupes across all
-- of profile.graphics's rooms (same rooms ROOM_MAPS above exports
-- individually) into one aggregate, grouped by bank.
----------------------------------------------------------------------
do
  local catalog = MapTileCatalog.build(profile)
  writeJs("map-tile-catalog.js", "MAP_TILE_CATALOG", catalog,
    "Every map/environment ROM tile this project has already confirmed -- deduplicated across " ..
    "all " .. catalog.roomCount .. " fully-decoded, VERIFIED rooms this project has found (the " ..
    "same rooms ROOM_MAPS above exports individually; see MapTileCatalog.lua's doc comment for " ..
    "why this aggregate view exists). Each entry records which room(s) use it -- not a " ..
    "candidate/heuristic finding like GRAPHICS_CANDIDATES, every offset here was already " ..
    "individually matched against a live-captured VRAM tile pattern.")
end

----------------------------------------------------------------------
-- 12. Item/spell + weapon/armor catalog (ItemTable.lua/WeaponTable.lua
-- -- both table boundaries substantially extended, see rom_profiles.lua's
-- own doc comments).
----------------------------------------------------------------------
do
  local itemRecords = ItemTable.decode(romData, profile.itemTable)
  local items = {}
  for i, r in ipairs(itemRecords) do
    items[i] = {
      index = r.index,
      name = r.name,
      categoryByte = r.categoryByte,
      id = r.id,
      price = r.price,
      namePrefixByte = r.namePrefixByte,
      isSpell = r.index >= profile.itemTable.categoryBoundaryRecord,
    }
  end

  local weaponRecords = WeaponTable.decode(romData, profile.weaponTable)
  local weapons = {}
  for i, r in ipairs(weaponRecords) do
    weapons[i] = {
      index = r.index,
      name = r.name,
      categoryByte = r.categoryByte,
      statBytes = bytesToArray(r.statBytes),
    }
  end

  -- Catalog plan Phase 2: categoryByte groupings, for the website's
  -- category filter pills -- see ItemTable.lua's/WeaponTable.lua's
  -- `groupByCategory` doc comments for exactly what `sizeClass` does
  -- and does not claim. Only the summary (categoryByte/count/
  -- sizeClass) is exported here, not the nested record lists -- the
  -- flat `items`/`weapons` arrays above already carry the full
  -- records, and each row's `categoryByte` is enough for the website
  -- to filter client-side without duplicating the data.
  local itemCategories = {}
  for i, g in ipairs(ItemTable.groupByCategory(itemRecords)) do
    itemCategories[i] = { categoryByte = g.categoryByte, count = g.count, sizeClass = g.sizeClass }
  end
  local weaponCategories = {}
  for i, g in ipairs(WeaponTable.groupByCategory(weaponRecords)) do
    weaponCategories[i] = { categoryByte = g.categoryByte, count = g.count, sizeClass = g.sizeClass }
  end

  -- Found via the same external-reference-matching pass as
  -- EnemyStatTable -- see WeaponStatTable.lua's doc comment. A
  -- SEPARATE table from `weapons` above (own file offset, own 16-byte
  -- stride, own row order matching the external reference's catalog
  -- order) -- power/price confirmed byte-for-byte against the US
  -- cartridge's disassembly and independently cross-checked against
  -- an earlier gamesurge.com walkthrough capture. Kept SEPARATE from
  -- `weapons` (not merged by index) because the two tables' row-order
  -- correspondence isn't confirmed -- see that module's doc comment
  -- for a concrete example why (weaponCatalog's German "Streit"
  -- sitting where a naive same-order guess would expect "Were Axe"
  -- doesn't obviously fit).
  local weaponStats = {}
  if profile.weaponStatTable then
    local statRows = WeaponStatTable.decode(romData, profile.weaponStatTable)
    local names = profile.weaponStatTable.externalReferenceNames or {}
    for i, r in ipairs(statRows) do
      weaponStats[i] = {
        index = i - 1,
        name = names[i],
        power = r.power,
        price = r.price,
        flagA = r.flagA,
        typeTag = r.typeTag,
        variantFlag = r.variantFlag,
        byte3 = r.byte3,
        rawBytes = bytesToArray(r.raw),
      }
    end
  end

  writeJs("items.js", "ITEMS", {
    items = items,
    weapons = weapons,
    categoryBoundaryRecord = profile.itemTable.categoryBoundaryRecord,
    itemCategories = itemCategories,
    weaponCategories = weaponCategories,
    weaponStats = weaponStats,
  }, "Item/spell table (ItemTable.lua) and weapon/armor table (WeaponTable.lua). Names decode " ..
     "cleanly for most records (spell records need a 2nd name offset, see ItemTable.lua's doc " ..
     "comment) -- records with name=\"\" genuinely don't decode at either known offset, shown " ..
     "honestly rather than guessed. `items[].price` (found 2026-08-18, ItemTable.lua's own doc " ..
     "comment) is bytes 13-14 (LE u16), VERIFIED 8/8 against a real external gold-cost list -- " ..
     "0 for records never sold in a shop (the found/thrown combat items), not a missing value. " ..
     "Stat bytes beyond name/price are real but NOT interpreted (raw " ..
     "only). itemCategories/weaponCategories (catalog plan Phase 2) group the records by their " ..
     "categoryByte -- sizeClass is a plain size threshold (>=5 records), NOT a claimed slot name " ..
     "(e.g. weapon/armor/helm) -- see WeaponTable.lua's doc comment for why that's still " ..
     "unconfirmed. `weaponStats` (WeaponStatTable.lua) is a SEPARATE table -- 16 weapons with " ..
     "power/price confirmed byte-for-byte against the US cartridge's public disassembly, kept " ..
     "apart from `weapons` above since the two tables' row-order correspondence isn't confirmed.")
end

----------------------------------------------------------------------
-- 13. NPC catalog (NpcCatalog.lua) -- NOT a static ROM table (see that
-- module's doc comment for why "complete" here means "every NPC this
-- project has actually found," not "every NPC in the ROM").
----------------------------------------------------------------------
writeJs("npcs.js", "NPCS", NpcCatalog.build(profile),
  "NPCs this project has found and placed, read from rom_profiles.lua's verified scene data " ..
  "(NpcCatalog.lua). No static ROM table backs NPC placement in this game -- each entry was " ..
  "found individually via live OAM tracing + per-room dialogue testing, not decoded from a " ..
  "table this exporter could walk mechanically.")

----------------------------------------------------------------------
-- 14. Story text census (rom_profiles.lua's `storyText`) -- monster
-- defeat messages and named story characters, found via
-- tools/rom/dump_strings.py's proven text scanner (the same method
-- that found Amanda's secondRoom dialogue), NOT decoded from a table
-- -- see rom_profiles.lua's doc comment for the full honesty scope.
----------------------------------------------------------------------
if profile.storyText then
  writeJs("story.js", "STORY", profile.storyText,
    "ROM-wide text census: monster \"<Name> bezwungen/besiegt\" victory messages and named " ..
    "story characters, found via a targeted tools/rom/dump_strings.py scan. Only Willy and " ..
    "Amanda have a known live room/sprite (positionKnown=true) -- every other name was found in " ..
    "dialogue text only, with no live position ever captured for it (positionKnown=false, " ..
    "honestly labeled, not omitted). bossDefeats has no confirmed link to enemySpeciesTable's " ..
    "11 numbered species rows -- shown standalone, not force-matched.")
end

----------------------------------------------------------------------
-- 15. Music (MusicDecoder.lua) -- Bank-15 sound-driver song table +
-- per-channel event streams, decoded by walking the ROM bytes (same
-- module a future love.audio playback will build on), not
-- hand-transcribed. See docs/reverse-engineering/rom-map.md's "Audio
-- format -- DECODED" section for the full disassembly trail.
----------------------------------------------------------------------
do
  local songTable = MusicDecoder.loadSongTable(romData)
  local MAX_EVENTS_PER_CHANNEL = 260 -- generous enough to capture one full real loop for most songs (see the real LOOP_DETECTED marker below)
  local songs = {}
  for i, channelOffsets in ipairs(songTable) do
    local channels = {}
    for ch = 1, 3 do
      channels[ch] = MusicDecoder.decodeChannel(romData, channelOffsets[ch], MAX_EVENTS_PER_CHANNEL)
    end
    songs[i] = { index = i, channels = channels }
  end
  writeJs("music.js", "MUSIC", {
    songCount = #songTable,
    songTableFileOffset = MusicDecoder.SONG_TABLE_FILE_OFFSET,
    freqTableFileOffset = MusicDecoder.FREQ_TABLE_FILE_OFFSET,
    durationTableFileOffset = MusicDecoder.DURATION_TABLE_FILE_OFFSET,
    songs = songs,
  }, "Bank-15 sound-driver data: the 30-song table (file " ..
    string.format("%#x", MusicDecoder.SONG_TABLE_FILE_OFFSET) ..
    ") plus each song's 3 channel event streams, decoded by src/import/MusicDecoder.lua (a " ..
    "direct Lua port of tools/rom/decode_music.py, the tool this format was originally found " ..
    "and proven with -- see that file's doc comment / rom-map.md's \"Audio format -- DECODED\" " ..
    "section for the full disassembly trail). Event `type`s: NOTE (note-on, `noteName`/" ..
    "`durationFrames`/`regPair` all decoded values -- `regPair` is the literal GB hardware " ..
    "register pair this event writes, `noteName` is a derived convenience via the GB period " ..
    "formula, not itself a ROM finding), REST, NOTE_OFF, SET_OCTAVE/SHIFT_OCTAVE (octave-select " ..
    "commands), COMMAND (one of 13 driver commands -- `jumpTarget` on a 0xE1 COMMAND is the " ..
    "loop-back target this decoder follows), LOOP_DETECTED (the stream returned to an " ..
    "already-visited position -- this IS the song repeating, not a decoder bug), STOP (0xFF " ..
    "hard-stop), EOF (ran past the ROM data this exporter was given, only relevant near a bank " ..
    "boundary). NOT decoded: the auxiliary per-frame vibrato/pitch-delta stream (disassembled, " ..
    "structurally confirmed, but a fine modulation layer this decoder doesn't walk -- see " ..
    "rom-map.md); exact musical intent of several commands beyond their WRAM side effect.")
end

----------------------------------------------------------------------
-- 16. Cut-transition landing/connectivity table (CutTransitionTable
-- .lua) -- a general ROM structure that encodes both the target
-- roomSelector and the landing tile for every "wipe-style" room-to-room
-- cut transition, found via a live hardware watchpoint (the exact
-- indirect-write blind spot 6+ earlier static passes couldn't cover)
-- then generalized via static pattern search. See CutTransitionTable
-- .lua's doc comment for the full disassembly/live-trace chain and
-- docs/reverse-engineering/rom-map.md "Consolidated reference" section
-- 4 for the closed-blocker summary.
----------------------------------------------------------------------
do
  local distinct = CutTransitionTable.distinctLandings(romData)
  local selectorRecords = CutTransitionTable.scanSelectorRecords(romData)
  writeJs("transitions.js", "TRANSITIONS", {
    rawRecordCount = 186,
    distinct = distinct,
    selectorRecords = selectorRecords,
    knownLive = {
      { roomSelector = 1, pixelX = 120, pixelY = 112,
        label = "thirdRoom -> fourthRoom (live-verified, real ROM cut transition)" },
      { roomSelector = 4, pixelX = 136, pixelY = 32,
        label = "fourthRoom -> fifthRoom (live-verified, real ROM cut transition) -- " ..
          "roomSelector 4 is the SAME real room identity as willyRoom/secondRoom/thirdRoom " ..
          "(byte-identical $D392/$D393/$C3F0/$C3F5, live-confirmed 2026-08-17), not an " ..
          "independent room -- see rooms.fifthRoom's own sameRomIdentityNote" },
    },
  }, "General ROM structure (bank 14, 186 raw records collapsing to " ..
    #distinct .. " genuinely distinct transitions) that encodes both the target " ..
    "roomSelectorTable index and the landing tile for every wipe-style room-to-room cut " ..
    "transition -- found via a live hardware watchpoint on WRAM $C244/$C245 (the write is " ..
    "INDIRECT, LD (HL),D/LD (HL),E, a blind spot 6+ earlier static-only passes could never " ..
    "cover), then generalized via static byte-pattern search once the record shape was known. " ..
    "Only 2 of the 82 distinct transitions are currently live-verified end to end and wired into " ..
    "actual gameplay (see `knownLive` above); the rest are ROM-decoded DATA whose in-game TRIGGER " ..
    "(which story/dialogue moment actually invokes each one) is honestly still unknown -- a " ..
    "time-boxed live search across every wall of every currently-reachable room found nothing " ..
    "new. targetFamily=\"unknownRoomA\" entries (roomSelector 8-13) are especially notable: " ..
    "ROM-verified proof this long-mysterious room family (never reached live) is genuine intended " ..
    "content, not dead data. selectorRecords is a structurally distinct sibling record type this " ..
    "same investigation found (originally suspected to be the connectivity key -- that hypothesis " ..
    "turned out wrong, its own meaning stays undecoded, kept here as a verified structural " ..
    "finding).")
end

----------------------------------------------------------------------
-- 17. Actor-definition table (ActorDefinitionTable.lua) -- the
-- live-traced RNG-gated spawn table behind secondRoom's two NPCs, its
-- full measured extent (218 records, indices 0-217, 5 anomalous). See
-- ActorDefinitionTable.lua's doc comment for the full live-trace chain
-- and disassembly.
----------------------------------------------------------------------
do
  local function toHex(s)
    return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
  end

  local records = ActorDefinitionTable.scanTable(romData)
  local exported = {}
  for _, r in ipairs(records) do
    local sub = nil
    if r.spriteSubRecord then
      sub = { fileOffset = r.spriteSubRecord.fileOffset, rawHex = toHex(r.spriteSubRecord.raw) }
    end
    exported[#exported + 1] = {
      index = r.index,
      fileOffset = r.fileOffset,
      anomalous = r.anomalous,
      allocParam = r.allocParam,
      spritePointer = r.spritePointer,
      rawHex = toHex(r.raw),
      spriteSubRecord = sub,
    }
  end

  writeJs("actors.js", "ACTORS", {
    tableCount = ActorDefinitionTable.TABLE_COUNT,
    records = exported,
    liveConfirmed = ActorDefinitionTable.LIVE_CONFIRMED,
  }, "RNG-gated actor-definition table (bank 3, CPU $5f5a, 24-byte stride, " ..
    ActorDefinitionTable.TABLE_COUNT .. " records, indices 0-" .. (ActorDefinitionTable.TABLE_COUNT - 1) ..
    ") -- found live-tracing secondRoom's two NPC spawns (a proximity check calls the " ..
    "already-known combat PRNG, $2B1E, to compute an index into this table). Each record embeds " ..
    "a pointer (bytes[8..9]) to a SECOND 24-byte sprite sub-record; the two live-captured " ..
    "indices' (99, 121) sub-records differ by exactly +0x20 on every varying byte -- a " ..
    "byte-exact match, via a totally independent method (live OAM tile-ID capture), to this " ..
    "project's already-confirmed 'characterB's tile IDs are characterA's own +0x20' fact. Honest " ..
    "scope: this is NOT a static per-room placement table -- the index is computed at runtime " ..
    "(RNG-influenced), which is why static search alone never found one. 5 records " ..
    "(anomalous=true) point into the fixed bank-0 region instead of the normal bank-3 window -- " ..
    "index 0 plus a tight cluster at 12-15, plausibly a reserved/fixed-graphics family. Only " ..
    "indices 99 and 121 (see liveConfirmed) have a confirmed live spawn behind them -- every " ..
    "other record is structured ROM data whose in-game trigger is honestly unknown.")
end

io.stderr:write("done.\n")
