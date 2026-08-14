-- Finds a candidate Mystic Quest ROM on disk. Read-only: never writes,
-- moves, or modifies anything it finds. Does not itself decide whether a
-- found file is actually a *supported* ROM -- that's RomIdentity + the
-- RomProfiles registry's job (src/import/rom_profiles.lua); this module
-- only answers "where might a .gb/.gbc file be."
--
-- Search order:
--   1. MYSTICQUEST_ROM env var (an explicit path -- the primary supported
--      way to point the importer at a ROM during development; mirrors
--      gen1recomp's `scripts/setup.sh --rom <path>`, see scripts/setup.sh).
--   2. baseroms/<anything>.gb or .gbc next to the game, via love.filesystem
--      (mirrors gen1recomp's baseroms/ convention, docs/gen1recomp-
--      analysis.md SS1/SS3) -- this is the shipped, no-terminal-needed path:
--      a player drops their ROM in baseroms/ and the app finds it.
--
-- baseroms/ is gitignored (see .gitignore) and never shipped with content.

local RomLocator = {}

local function readExternalPath(path)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError end
  local data = file:read("*a")
  file:close()
  return data
end

--- Returns (data, path) for the first candidate ROM found, or (nil, reason).
function RomLocator.find()
  local envPath = os.getenv("MYSTICQUEST_ROM")
  if envPath and envPath ~= "" then
    local data, err = readExternalPath(envPath)
    if data then return data, envPath end
    return nil, "MYSTICQUEST_ROM is set to '" .. envPath ..
      "' but it could not be read: " .. tostring(err)
  end

  if love and love.filesystem then
    local info = love.filesystem.getInfo("baseroms")
    if info and info.type == "directory" then
      local names = love.filesystem.getDirectoryItems("baseroms")
      table.sort(names)
      for _, name in ipairs(names) do
        if name:lower():match("%.gbc?$") then
          local path = "baseroms/" .. name
          local data = love.filesystem.read(path)
          if data then return data, path end
        end
      end
    end
  end

  return nil, "no ROM found (set MYSTICQUEST_ROM, or place a .gb/.gbc " ..
    "file in baseroms/)"
end

return RomLocator
