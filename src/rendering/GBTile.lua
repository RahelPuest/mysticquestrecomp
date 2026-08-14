-- Game Boy 2bpp tile decoding -- a hardware-format decoder, not specific to
-- Mystic Quest's ROM layout. Mirrors tools/graphics/gbtile.py exactly (same
-- algorithm, kept in sync deliberately) so the reverse-engineering findings
-- in docs/reverse-engineering/rom-map.md (found using the Python tool) and
-- the native runtime's own decoding agree by construction, not by luck.
--
-- Format (Pan Docs, "VRAM Tile Data"): each 8x8 tile is 16 bytes = 8 rows of
-- 2 bytes. For row y, byte0's bit(7-x) is the low bit of pixel x's 2-bit
-- palette index, byte1's bit(7-x) is the high bit.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local GBTile = {}

GBTile.TILE_BYTES = 16
GBTile.TILE_W = 8
GBTile.TILE_H = 8

--- Decode one 16-byte tile (given as a Lua string, `offset` is 0-based into
-- it) into an 8x8 array of arrays of 0-3 palette indices, row-major
-- (result[y+1][x+1], both 1-based per Lua convention).
function GBTile.decodeTile(data, offset)
  offset = offset or 0
  assert(#data - offset >= GBTile.TILE_BYTES,
    "GBTile.decodeTile: need 16 bytes, got " .. (#data - offset))
  local rows = {}
  for y = 0, GBTile.TILE_H - 1 do
    local lo, hi = data:byte(offset + y * 2 + 1, offset + y * 2 + 2)
    local row = {}
    for x = 0, GBTile.TILE_W - 1 do
      local bitIndex = 7 - x
      local pixel = bor(
        lshift(band(rshift(hi, bitIndex), 1), 1),
        band(rshift(lo, bitIndex), 1)
      )
      row[x + 1] = pixel
    end
    rows[y + 1] = row
  end
  return rows
end

--- Decode `count` consecutive tiles starting at `offset` (0-based) in
-- `data`. count defaults to as many whole tiles as fit after offset.
function GBTile.decodeTiles(data, offset, count)
  offset = offset or 0
  local maxCount = math.floor((#data - offset) / GBTile.TILE_BYTES)
  count = count or maxCount
  assert(count <= maxCount, "GBTile.decodeTiles: not enough data for " ..
    count .. " tiles (have " .. maxCount .. ")")
  local tiles = {}
  for i = 0, count - 1 do
    tiles[i + 1] = GBTile.decodeTile(data, offset + i * GBTile.TILE_BYTES)
  end
  return tiles
end

--- Shannon entropy (bits) of a decoded tile's 4 palette-index symbols.
-- Ported from tools/rom/scan_graphics.py's tile_entropy for the same
-- "does this look like real tile art" lead-generation heuristic -- kept
-- here so a future Lua-side scanner (or a debug tool) doesn't need to shell
-- out to Python. Not a source of truth by itself (see rom-map.md's
-- bank-5 false positive) -- always confirm visually.
function GBTile.tileEntropy(tile)
  local counts = { 0, 0, 0, 0 }
  local total = 0
  for _, row in ipairs(tile) do
    for _, v in ipairs(row) do
      counts[v + 1] = counts[v + 1] + 1
      total = total + 1
    end
  end
  if total == 0 then return 0.0 end
  local h = 0.0
  for _, c in ipairs(counts) do
    if c > 0 then
      local p = c / total
      h = h - p * (math.log(p) / math.log(2))
    end
  end
  return h
end

return GBTile
