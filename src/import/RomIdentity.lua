-- Game Boy cartridge header parsing + SHA-1, in pure Lua (no love.* calls),
-- so it can be unit-tested headlessly with plain luajit and reused
-- identically by the real LÖVE importer. Mirrors
-- tools/rom/identify_rom.py's field layout -- kept in sync deliberately.
--
-- This module answers "what ROM is this" only. It does not decode game
-- data; see src/import/rom_profiles.lua for the registry of ROMs this
-- project knows how to import, and src/rendering/GBTile.lua for graphics
-- decoding.

local Sha1 = require("src.core.Sha1")

local RomIdentity = {}

local HEADER_START = 0x0100 -- unused directly; fields below are absolute offsets
local ROM_SIZES = {
  [0x00] = 2, [0x01] = 4, [0x02] = 8, [0x03] = 16,
  [0x04] = 32, [0x05] = 64, [0x06] = 128, [0x07] = 256, [0x08] = 512,
}

local CART_TYPES = {
  [0x00] = "ROM ONLY", [0x01] = "MBC1", [0x02] = "MBC1+RAM",
  [0x03] = "MBC1+RAM+BATTERY", [0x05] = "MBC2", [0x06] = "MBC2+BATTERY",
  [0x08] = "ROM+RAM", [0x09] = "ROM+RAM+BATTERY", [0x0F] = "MBC3+TIMER+BATTERY",
  [0x10] = "MBC3+TIMER+RAM+BATTERY", [0x11] = "MBC3", [0x12] = "MBC3+RAM",
  [0x13] = "MBC3+RAM+BATTERY", [0x19] = "MBC5", [0x1A] = "MBC5+RAM",
  [0x1B] = "MBC5+RAM+BATTERY",
}

local function byte(data, offset1based)
  return data:byte(offset1based)
end

--- Parse the Game Boy cartridge header out of `data` (a Lua string of raw
-- ROM bytes) and compute its hashes. Returns a plain table of fields; does
-- not throw for a too-small input, callers should check #data first if
-- that matters (RomProfiles.match below handles it).
function RomIdentity.identify(data)
  assert(type(data) == "string", "RomIdentity.identify expects a byte string")
  local report = {
    sizeBytes = #data,
    sha1 = Sha1(data),
  }
  if #data < 0x150 then
    report.error = "file too small to contain a GB header"
    return report
  end

  -- Title: 0x0134-0x0143 (16 bytes, 1-based Lua offset 0x135-0x144),
  -- NUL-terminated / stops at the first non-printable byte.
  local titleChars = {}
  for i = 0, 15 do
    local b = byte(data, 0x135 + i)
    if b == 0 then break end
    if b >= 0x20 and b <= 0x7E then
      titleChars[#titleChars + 1] = string.char(b)
    else
      break
    end
  end
  report.title = table.concat(titleChars)

  report.cgbFlag = byte(data, 0x144)
  report.sgbFlag = byte(data, 0x147)
  report.cartridgeTypeCode = byte(data, 0x148)
  report.cartridgeType = CART_TYPES[report.cartridgeTypeCode] or "UNKNOWN"
  report.romSizeCode = byte(data, 0x149)
  report.romSizeBanks = ROM_SIZES[report.romSizeCode]
  report.ramSizeCode = byte(data, 0x14A)
  report.destinationCode = byte(data, 0x14B)
  report.oldLicenseeCode = byte(data, 0x14C)
  report.maskRomVersion = byte(data, 0x14D)

  -- Header checksum (0x014D, 1-based 0x14E): x = x - byte - 1 over
  -- 0x0134-0x014C.
  local x = 0
  for i = 0x135, 0x14D do
    x = (x - byte(data, i) - 1) % 256
  end
  report.headerChecksumStored = byte(data, 0x14E)
  report.headerChecksumCalculated = x
  report.headerChecksumOk = (x == report.headerChecksumStored)

  -- Global checksum (0x014E-0x014F, 1-based 0x14F-0x150): big-endian sum of
  -- all bytes except these two.
  local storedGlobal = byte(data, 0x14F) * 256 + byte(data, 0x150)
  local total = 0
  for i = 1, #data do
    total = total + byte(data, i)
  end
  total = (total - byte(data, 0x14F) - byte(data, 0x150)) % 65536
  report.globalChecksumStored = storedGlobal
  report.globalChecksumCalculated = total
  report.globalChecksumOk = (total == storedGlobal)

  return report
end

return RomIdentity
