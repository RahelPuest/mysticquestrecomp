-- This project's own field layout for the real 124-byte save payload
-- (see SaveFormat.lua for the VERIFIED container around it). The real
-- ROM's own field-by-field mapping for payload bytes beyond the magic
-- byte was NEVER decoded (rom-map.md: "the meaning of the ~122
-- remaining packed bytes... presumably the same stats/inventory/
-- position fields as the live WRAM struct... but not yet matched
-- field-by-field") -- so this module does NOT claim to reproduce the
-- original ROM's own layout. It reuses the real, VERIFIED WRAM struct
-- FIELD ORDER (Stats.lua's own doc comment, `$D7B2` curLP/maxLP/curMP/
-- maxMP/level/gold) as a reasonable, documented starting point, but the
-- exact byte OFFSETS within the save payload are this project's own
-- choice, not a claimed ROM fact -- a save file this module writes is
-- NOT expected to be byte-compatible with a real cartridge's save.
--
-- Payload layout (1-based, matching SaveFormat.PAYLOAD_LENGTH=124):
--   [1]      magic byte (SaveFormat.MAGIC_BYTE, real/VERIFIED)
--   [2-3]    curLP (u16 LE)
--   [4-5]    maxLP (u16 LE)
--   [6-7]    curMP (u16 LE)
--   [8-9]    maxMP (u16 LE)
--   [10]     level (u8)
--   [11-12]  gold (u16 LE)
--   [13]     defense (u8, see Stats.DEFAULT_DEFENSE)
--   [14]     heroName length (0-16) -- plain ASCII, this project's own
--            encoding (NOT the real ROM's own dialogue-byte charset --
--            this save file never round-trips through the original
--            ROM, so there's no reason to take on that encoding's
--            complexity for an internal format)
--   [15-30]  heroName bytes (16-byte fixed field, zero-padded)
--   [31-123] reserved (0x00) -- future inventory/position/etc, not
--            implemented yet; explicitly zeroed, not left undefined
--   [124]    SaveFormat.LAST_BYTE_PLACEHOLDER (real, live-confirmed
--            safe value for this EU ROM, see that field's doc comment)
--
-- Pure Lua, no love.* calls -- headlessly testable.

local SaveFormat = require("src.save.SaveFormat")

local SaveData = {}

local function packU16(value)
  assert(value >= 0 and value <= 0xFFFF, "SaveData: u16 field out of range: " .. tostring(value))
  return value % 256, math.floor(value / 256) % 256
end

local function unpackU16(lo, hi)
  return lo + hi * 256
end

local HERO_NAME_MAX = 16

--- `stats`: a real `Stats` instance (or any table with the same
-- curLP/maxLP/curMP/maxMP/level/gold/defense fields). `heroName`: the
-- real player-entered name (see NameEntry.lua) -- required here rather
-- than falling back to a silent placeholder, same "no silent
-- fallbacks" rule Field.lua/VictorySequence.lua already follow for
-- this exact field. Returns a real 124-byte payload (see
-- SaveFormat.encode).
function SaveData.serialize(stats, heroName)
  assert(type(heroName) == "string" and #heroName > 0,
    "SaveData.serialize requires a real, non-empty heroName -- see NameEntry.lua")
  assert(#heroName <= HERO_NAME_MAX,
    "SaveData.serialize: heroName longer than the " .. HERO_NAME_MAX .. "-byte field (" .. #heroName .. ")")

  local payload = {}
  for i = 1, SaveFormat.PAYLOAD_LENGTH do
    payload[i] = 0
  end

  payload[1] = SaveFormat.MAGIC_BYTE
  payload[2], payload[3] = packU16(stats.curLP)
  payload[4], payload[5] = packU16(stats.maxLP)
  payload[6], payload[7] = packU16(stats.curMP)
  payload[8], payload[9] = packU16(stats.maxMP)
  payload[10] = stats.level
  payload[11], payload[12] = packU16(stats.gold)
  payload[13] = stats.defense
  payload[14] = #heroName
  for i = 1, #heroName do
    payload[14 + i] = heroName:byte(i)
  end
  -- [31-123] already zeroed above (reserved)
  payload[124] = SaveFormat.LAST_BYTE_PLACEHOLDER

  return payload
end

--- Inverse of serialize(): a real 124-byte payload -> `statsFields,
-- heroName` -- `statsFields` is a plain table of the fields
-- `Stats.new(opts)` accepts directly (`Stats.new(SaveData
-- .deserialize(payload))`), `heroName` the real stored player name.
-- Does NOT itself validate the magic byte -- that's `SaveFormat
-- .decode`'s job; by the time a payload reaches here it's already
-- been validated.
function SaveData.deserialize(payload)
  assert(type(payload) == "table" and #payload == SaveFormat.PAYLOAD_LENGTH,
    "SaveData.deserialize expects a " .. SaveFormat.PAYLOAD_LENGTH .. "-byte payload")

  local nameLength = payload[14]
  local nameChars = {}
  for i = 1, nameLength do
    nameChars[i] = string.char(payload[14 + i])
  end

  local statsFields = {
    curLP = unpackU16(payload[2], payload[3]),
    maxLP = unpackU16(payload[4], payload[5]),
    curMP = unpackU16(payload[6], payload[7]),
    maxMP = unpackU16(payload[8], payload[9]),
    level = payload[10],
    gold = unpackU16(payload[11], payload[12]),
    defense = payload[13],
  }
  return statsFields, table.concat(nameChars)
end

return SaveData
