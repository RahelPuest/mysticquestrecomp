-- Real MBC2 save-RAM container structure -- see docs/reverse-engineering
-- /rom-map.md "Save RAM (MBC2 built-in RAM...) -- format VERIFIED" for
-- the full trace (live dynamic trace, doubly confirmed against 12 real
-- external US-cartridge save files).
--
-- Real, VERIFIED structure of the full 512-byte SRAM region ($A000-
-- $A1FF), all offsets relative to $A000:
--   0x000-0x0F7 (248 bytes): the PRIMARY copy -- 124 real logical bytes,
--     nibble-packed 2 SRAM bytes per logical byte (see NibblePacking.lua).
--   0x0F8-0x0FF (8 bytes): unused padding (not written by the traced
--     ROM routine; zero-filled here, not a claimed ROM fact).
--   0x100-0x1F7 (248 bytes): the BACKUP copy -- a byte-for-byte
--     identical copy of the primary's own ALREADY-ENCODED nibble cells
--     (a plain copy loop in the real ROM, not a second encode pass --
--     see rom-map.md) -- corruption resilience, not two save slots.
--   0x1F8-0x1FF (8 bytes): unused padding, same reasoning.
--
-- The first decoded logical byte (real byte index 1, i.e. the byte
-- recovered from SRAM offsets 0x000/0x001) is a real, VERIFIED magic/
-- validity byte, `0x6C` -- confirmed twice: once from this project's
-- own live ROM trace, once independently from 12 real external
-- US-cartridge save files.
--
-- This module only handles the CONTAINER (nibble-packing + magic byte
-- + duplicate-copy structure) -- what the other 123 payload bytes MEAN
-- is a SEPARATE concern, `SaveData.lua`, since the real ROM's own
-- field-by-field mapping for those bytes was never decoded (see
-- rom-map.md's own honest "not yet matched field-by-field" note) --
-- this project uses its own, clearly-labeled layout for them, not a
-- claimed reproduction of the original's undecoded one.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local NibblePacking = require("src.save.NibblePacking")

local SaveFormat = {}

SaveFormat.MAGIC_BYTE = 0x6C
SaveFormat.PAYLOAD_LENGTH = 124
SaveFormat.SRAM_LENGTH = 512

SaveFormat.PRIMARY_OFFSET = 0
SaveFormat.PRIMARY_LENGTH = SaveFormat.PAYLOAD_LENGTH * 2 -- 248
SaveFormat.BACKUP_OFFSET = 256
SaveFormat.BACKUP_LENGTH = SaveFormat.PAYLOAD_LENGTH * 2 -- 248

--- Real, live-confirmed-safe placeholder for the payload's LAST byte
-- (real byte index 124): a brute-force sweep of all 256 possible
-- values against this EU ROM found 163 safe / 93 causing a hard CPU
-- lockup when the ORIGINAL ROM tries to load a save carrying them --
-- `0x00` is one of the confirmed-safe values (see rom-map.md's "eighth
-- pass"). This project's own save/load round-trip (native Lua code,
-- never feeds this byte back through the original ROM's own loader)
-- doesn't strictly need this caution, but it's kept as the default
-- since it's a real, verified-safe choice, not an arbitrary one.
SaveFormat.LAST_BYTE_PLACEHOLDER = 0x00

--- Encode a 124-byte payload (1-based array of integers 0-255,
-- `payload[1]` should already be `SaveFormat.MAGIC_BYTE`) into the
-- real, full 512-byte SRAM layout described above. Does not itself
-- enforce the magic byte -- callers building a real payload (see
-- SaveData.lua) are expected to set it; this module only implements
-- the real container shape.
function SaveFormat.encode(payload)
  assert(type(payload) == "table" and #payload == SaveFormat.PAYLOAD_LENGTH,
    "SaveFormat.encode expects a " .. SaveFormat.PAYLOAD_LENGTH .. "-byte payload, got " ..
    (type(payload) == "table" and #payload or type(payload)))

  local encoded = NibblePacking.packBytes(payload) -- 248 nibble cells

  local sram = {}
  for i = 1, SaveFormat.SRAM_LENGTH do
    sram[i] = 0
  end
  for i = 1, SaveFormat.PRIMARY_LENGTH do
    sram[SaveFormat.PRIMARY_OFFSET + i] = encoded[i]
  end
  for i = 1, SaveFormat.BACKUP_LENGTH do
    sram[SaveFormat.BACKUP_OFFSET + i] = encoded[i] -- real ROM: raw copy, not a re-encode
  end
  return sram
end

--- Decode a real 512-byte SRAM dump back into its 124-byte payload.
-- Returns `payload, nil` on success, or `nil, reason` on failure (no
-- silent fallback -- matches this project's "fail loudly" rule):
--   - wrong length
--   - primary/backup copies disagree (real corruption check this
--     project can offer, going beyond the original ROM's own simpler
--     magic-byte-only validity check)
--   - magic byte mismatch (no valid save present)
function SaveFormat.decode(sram)
  if type(sram) ~= "table" or #sram ~= SaveFormat.SRAM_LENGTH then
    return nil, "wrong SRAM length (expected " .. SaveFormat.SRAM_LENGTH ..
      ", got " .. (type(sram) == "table" and #sram or type(sram)) .. ")"
  end

  local primaryCells, backupCells = {}, {}
  for i = 1, SaveFormat.PRIMARY_LENGTH do
    primaryCells[i] = sram[SaveFormat.PRIMARY_OFFSET + i]
  end
  for i = 1, SaveFormat.BACKUP_LENGTH do
    backupCells[i] = sram[SaveFormat.BACKUP_OFFSET + i]
  end

  for i = 1, SaveFormat.PRIMARY_LENGTH do
    if primaryCells[i] ~= backupCells[i] then
      return nil, "primary/backup copies disagree at nibble cell " .. i .. " -- corrupt save"
    end
  end

  local payload = NibblePacking.unpackBytes(primaryCells)
  if payload[1] ~= SaveFormat.MAGIC_BYTE then
    return nil, "magic byte mismatch (expected " .. string.format("0x%02X", SaveFormat.MAGIC_BYTE) ..
      ", got " .. string.format("0x%02X", payload[1]) .. ") -- no valid save"
  end

  return payload, nil
end

return SaveFormat
