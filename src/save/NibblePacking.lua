-- Real MBC2 nibble-packing primitives -- see docs/reverse-engineering/
-- rom-map.md "Save RAM (MBC2 built-in RAM...) -- format VERIFIED" for
-- the full trace. MBC2's built-in SRAM is only 4 bits wide per byte
-- (the high nibble of every SRAM byte is unused hardware-side) -- this
-- is WHY the real ROM packs one logical byte into TWO SRAM cells,
-- not an arbitrary design choice this project is inventing.
--
-- Real ROM routines this ports exactly:
--   WriteNibblePair (bank 2, file 0xB46E): `PUSH AF / AND 0x0F /
--     LD (HL+),A / POP AF / SWAP A / AND 0x0F / LD (HL+),A` -- i.e.
--     cellLow = byte & 0x0F, cellHigh = (byte >> 4) & 0x0F, written
--     low cell first then high cell, HL advancing by 1 each write (so
--     each logical byte occupies 2 CONSECUTIVE SRAM addresses).
--   ReadNibblePair (file 0xB479): the inverse (`SWAP`+`OR` to
--     recombine) -- byte = cellLow | (cellHigh << 4).
--
-- Pure Lua, no love.* calls -- headlessly testable.

local NibblePacking = {}

--- Real WriteNibblePair: one logical byte (0-255) -> two nibble cells
-- (each 0-15), low nibble first. Returns `cellLow, cellHigh`.
function NibblePacking.packByte(byte)
  assert(byte >= 0 and byte <= 255, "NibblePacking.packByte: byte out of range: " .. tostring(byte))
  local cellLow = byte % 16
  local cellHigh = math.floor(byte / 16) % 16
  return cellLow, cellHigh
end

--- Real ReadNibblePair: two nibble cells -> one logical byte. Only the
-- low 4 bits of each cell are read (matching real hardware, which
-- physically can't return anything else), so out-of-range inputs are
-- silently masked here exactly like the real SM83 `AND 0x0F` would --
-- not an error case, a real hardware property.
function NibblePacking.unpackByte(cellLow, cellHigh)
  return (cellLow % 16) + (cellHigh % 16) * 16
end

--- Pack a whole byte array (1-based Lua array of integers 0-255) into
-- the real flat nibble-cell stream WriteNibblePair produces: for N
-- input bytes, returns a 2*N-entry array, `[2i-1]`=low cell,
-- `[2i]`=high cell for input byte `i`.
function NibblePacking.packBytes(bytes)
  local cells = {}
  for i, byte in ipairs(bytes) do
    local lo, hi = NibblePacking.packByte(byte)
    cells[2 * i - 1] = lo
    cells[2 * i] = hi
  end
  return cells
end

--- Inverse of packBytes: a 2*N-entry nibble-cell array -> an N-entry
-- byte array. Fails loudly (rather than silently truncating) if the
-- cell count isn't even, since that can't represent a whole number of
-- real bytes.
function NibblePacking.unpackBytes(cells)
  assert(#cells % 2 == 0, "NibblePacking.unpackBytes: odd cell count " .. #cells ..
    " can't represent a whole number of real bytes")
  local bytes = {}
  for i = 1, #cells / 2 do
    bytes[i] = NibblePacking.unpackByte(cells[2 * i - 1], cells[2 * i])
  end
  return bytes
end

return NibblePacking
