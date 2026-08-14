-- Pure-Lua SHA-1 (FIPS 180-1), implemented against LuaJIT's `bit` library
-- (bitop), so it runs identically whether required from inside LÖVE or from
-- a plain `luajit` headless test run -- no love.data dependency, no C
-- extension. This is a generic cryptographic-hash utility, not specific to
-- any ROM or game; it exists so ROM verification (RomIdentity.lua) can be
-- unit-tested without booting LÖVE at all.
--
-- Reference: RFC 3174 / FIPS 180-1. Verified against the standard's own
-- test vectors in tests/unit/sha1_test.lua ("abc" and the empty string).

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

local function toHex(dwords)
  -- bit.band/bxor/etc. return LuaJIT's signed 32-bit integer representation,
  -- so a value with its top bit set prints as a giant negative number under
  -- string.format("%x", ...) (which widens through a 64-bit conversion).
  -- bit.tohex formats the same 32-bit pattern as unsigned, which is what a
  -- hash digest needs.
  local out = {}
  for i = 1, 5 do
    out[i] = bit.tohex(dwords[i])
  end
  return table.concat(out)
end

--- Compute the SHA-1 digest of `message` (a Lua string of raw bytes).
-- Returns a 40-character lowercase hex string.
local function sha1(message)
  local msgLen = #message
  local bitLen = msgLen * 8

  -- Padding: 0x80, then zero bytes, until length % 64 == 56, then the
  -- original bit length as a big-endian 64-bit integer.
  local padded = { message, "\128" }
  local padLen = (56 - (msgLen + 1) % 64) % 64
  padded[#padded + 1] = string.rep("\0", padLen)
  -- We only ever hash ROM-sized inputs (well under 2^32 bits), so the high
  -- 32 bits of the 64-bit length field are always zero.
  padded[#padded + 1] = string.char(
    0, 0, 0, 0,
    band(rshift(bitLen, 24), 0xFF),
    band(rshift(bitLen, 16), 0xFF),
    band(rshift(bitLen, 8), 0xFF),
    band(bitLen, 0xFF)
  )
  local data = table.concat(padded)
  assert(#data % 64 == 0)

  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  local w = {}
  for chunkStart = 1, #data, 64 do
    for i = 0, 15 do
      local o = chunkStart + i * 4
      local b1, b2, b3, b4 = data:byte(o, o + 3)
      w[i + 1] = bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
    end
    for i = 17, 80 do
      w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 1, 80 do
      local f, k
      if i <= 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif i <= 40 then
        f = bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif i <= 60 then
        f = bor(band(b, c), band(b, d), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(b, c, d)
        k = 0xCA62C1D6
      end
      -- 32-bit wraparound: `bit` ops already operate mod 2^32.
      local temp = rol(a, 5) + f + e + k + w[i]
      e, d, c, b, a = d, c, rol(b, 30), a, band(temp, 0xFFFFFFFF)
    end

    h0 = band(h0 + a, 0xFFFFFFFF)
    h1 = band(h1 + b, 0xFFFFFFFF)
    h2 = band(h2 + c, 0xFFFFFFFF)
    h3 = band(h3 + d, 0xFFFFFFFF)
    h4 = band(h4 + e, 0xFFFFFFFF)
  end

  return toHex({ h0, h1, h2, h3, h4 })
end

return sha1
