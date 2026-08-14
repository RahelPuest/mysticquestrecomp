-- Test-only helper: find a development copy of the Mystic Quest ROM on
-- disk, if one happens to be available, so ROM-dependent tests can run
-- against real bytes. Never required -- every caller must go through
-- Harness.testIfAvailable so the suite still passes with zero ROMs present.
-- This file lists *search locations*, never ROM offsets/content, so it does
-- not violate the "centralize ROM-specific knowledge" rule (that rule is
-- about byte layout, not filesystem paths).

-- Built with explicit indices (not a table constructor with the env var as
-- the first element) because ipairs() stops at the first nil slot -- when
-- MYSTICQUEST_ROM is unset, `{ os.getenv(...), "a", "b" }` puts a nil at
-- index 1 and silently makes every later candidate unreachable to ipairs.
local CANDIDATES = {}
CANDIDATES[#CANDIDATES + 1] = os.getenv("MYSTICQUEST_ROM")
CANDIDATES[#CANDIDATES + 1] = "baseroms/Mystic Quest (G) [!].gb"
CANDIDATES[#CANDIDATES + 1] = "../roms/extracted_mq/Mystic Quest (G) [!].gb"
CANDIDATES[#CANDIDATES + 1] = "../baseroms/Mystic Quest (G) [!].gb"

local DevRomLocator = {}

local function readFile(path)
  if not path then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

--- Returns (data, path) for the first candidate ROM found, or nil if none
-- of the search locations have one.
function DevRomLocator.find()
  for _, path in ipairs(CANDIDATES) do
    local data = readFile(path)
    if data then return data, path end
  end
  return nil
end

return DevRomLocator
