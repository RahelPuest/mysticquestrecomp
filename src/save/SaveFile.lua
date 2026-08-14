-- love.filesystem-backed save file I/O -- thin glue only, deliberately
-- NOT unit tested by the headless suite (see docs/architecture.md's
-- "Testing strategy": `love.*` calls stay out of the pure-logic layer
-- entirely; this project uses no love_stub.lua). The real, testable
-- logic (nibble-packing, container format, field layout) lives in
-- NibblePacking/SaveFormat/SaveData.lua, all pure Lua.
--
-- Real trigger condition: UNKNOWN in the original ROM (rom-map.md's
-- own "Save RAM" entry: "happened during undirected mixed-input
-- testing, not tied to a specific confirmed player action yet"). This
-- project does NOT claim to reproduce the real trigger -- it wires its
-- own, clearly-labeled save/load points (see Field.lua's own doc
-- comment for exactly which key/moment).

local SaveFormat = require("src.save.SaveFormat")
local SaveData = require("src.save.SaveData")

local SaveFile = {}

SaveFile.FILENAME = "mysticquest.sav"

local function sramToString(sram)
  local chars = {}
  for i = 1, #sram do
    chars[i] = string.char(sram[i])
  end
  return table.concat(chars)
end

local function stringToSram(str)
  local sram = {}
  for i = 1, #str do
    sram[i] = str:byte(i)
  end
  return sram
end

--- Write `stats` (a real Stats instance) and the real player-entered
-- `heroName` (see NameEntry.lua) to the save file. Returns `true` on
-- success, or `false, reason` on failure -- no silent fallback.
function SaveFile.write(stats, heroName)
  local payload = SaveData.serialize(stats, heroName)
  local sram = SaveFormat.encode(payload)
  local ok, err = love.filesystem.write(SaveFile.FILENAME, sramToString(sram))
  if not ok then
    return false, err
  end
  return true
end

--- Load the save file, if one exists and is valid. Returns
-- `statsFields, heroName` on success (see SaveData.deserialize), or
-- `nil, reason` otherwise (missing file, wrong size, corrupt copies,
-- bad magic byte -- SaveFormat.decode's own real checks) -- callers
-- must handle the "no valid save" case explicitly, this never
-- fabricates a fresh-game fallback silently.
function SaveFile.load()
  if not love.filesystem.getInfo(SaveFile.FILENAME) then
    return nil, "no save file present"
  end
  local data, err = love.filesystem.read(SaveFile.FILENAME)
  if not data then
    return nil, err or "could not read save file"
  end
  if #data ~= SaveFormat.SRAM_LENGTH then
    return nil, "save file is the wrong size (expected " .. SaveFormat.SRAM_LENGTH ..
      " bytes, got " .. #data .. ")"
  end
  local payload, reason = SaveFormat.decode(stringToSram(data))
  if not payload then
    return nil, reason
  end
  return SaveData.deserialize(payload)
end

--- Real existence check without a full load -- for UI (e.g. showing
-- "Weiterspielen" as available/greyed out).
function SaveFile.exists()
  return love.filesystem.getInfo(SaveFile.FILENAME) ~= nil
end

return SaveFile
