-- Decodes the real combat-PRNG noise table found in the Mystic Quest
-- (EU) ROM -- see docs/reverse-engineering/rom-map.md "$50AC, the real
-- damage formula, fully decoded" and combat.md's "Enemy HP" section.
-- Fixed bank 0 (always mapped), 256 raw bytes, real noise-shaped data
-- (no visible structure when dumped) consumed by ROM routine `$2B1E`.
--
-- This module only extracts the raw bytes; the real counter/cap/
-- double-lookup draw algorithm that turns them into a PRNG stream is
-- `src/entities/CombatNoise.lua` -- kept separate so the pure-data
-- extraction (headlessly testable against the real ROM bytes) doesn't
-- depend on any stateful object.
--
-- Pure Lua, no love.* calls, same convention as MapTable/ItemTable/
-- RoomSelectorTable.

local NoiseTable = {}

--- Decode the full 256-byte table from `romData` per `noiseTable`
-- (`profile.noiseTable`). Returns a plain 1-based array of 256
-- integers (0-255) -- entry `i` corresponds to real ROM byte offset
-- `noiseTable.fileOffset + (i - 1)`.
function NoiseTable.decode(romData, noiseTable)
  assert(type(romData) == "string", "NoiseTable.decode expects a byte string")
  assert(noiseTable and noiseTable.fileOffset and noiseTable.length,
    "NoiseTable.decode expects a profile.noiseTable")

  local bytes = { romData:byte(noiseTable.fileOffset + 1, noiseTable.fileOffset + noiseTable.length) }
  assert(#bytes == noiseTable.length,
    "NoiseTable.decode: expected " .. noiseTable.length .. " bytes, got " .. #bytes ..
    " (fileOffset out of range or ROM truncated)")
  return bytes
end

return NoiseTable
