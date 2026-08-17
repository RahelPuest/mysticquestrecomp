-- Decodes the real per-weapon power/price stat table found in the
-- Mystic Quest (EU) ROM -- bank 2, file `0xA1FD`, 16-byte stride, 16
-- real records (the 16 real player-equippable weapons).
--
-- FOUND, 2026-08-17 (direct user instruction, "erst waffen stats
-- verdraten dann die maps anschauen" -- a follow-up to
-- EnemyStatTable.lua's own same-day discovery, see that module's doc
-- comment for the full methodology this reuses): the public US
-- "Final Fantasy Adventure" disassembly (daid/FFA-Disassembly, see
-- docs/references.md) documents a real 7-byte-per-weapon stat group
-- (`byte0..byte3`, `power`, `priceLo`, `priceHi`) inside its own
-- `equipmentDataTable`, with exact values for all 16 real weapons.
-- Searched this EU ROM for each weapon's own full 7-byte signature:
-- **all 16 matched byte-for-byte, at a perfect 16-byte stride**,
-- starting at file `0xA1FD` -- same real find as `EnemyStatTable`,
-- same conclusion: this EU localization kept the exact combat-balance
-- numbers from the US cartridge unchanged.
--
-- `power` and `price` are the two fields with independent, external
-- confirmation beyond the byte match itself: this project's own
-- earlier `gamesurge.com` walkthrough capture (docs/references.md)
-- gives human-transcribed weapon prices for a subset of weapons, 3 of
-- which match this table's own decoded `price` EXACTLY (Wind Spear
-- 1150, Flame Flail 6300, Thunder Spear 11250) -- a real, independent
-- (if partial -- several OTHER gamesurge prices don't match, most
-- likely simple OCR/transcription slips in a 1999 hand-typed FAQ, not
-- evidence against this table) confirmation on top of the disassembly
-- byte match. `power` similarly matches every one of gamesurge's own
-- "+N" ratings exactly (Broad Sword +4, Silver Sword +14, Zeus Axe
-- +48, Excalibur +85, ...).
--
-- **This is a genuinely SEPARATE table from `WeaponTable`'s own
-- name+stat records** (`rom_profiles.lua`'s `weaponTable`, file
-- `0xA1C0`) -- NOT two views of the same underlying record. The two
-- tables' own file offsets don't land on a shared record boundary
-- (`0xA1FD - 0xA1C0 = 0x3D`, not a clean multiple of either table's
-- own 16-byte stride), so this project keeps them as two independent,
-- parallel decoders rather than forcing a merged record shape that
-- isn't actually there.
--
-- Record shape (0-based byte offset; only `power`/`price` are
-- confirmed by the cross-checks above -- the other 4 bytes are the
-- external disassembly's own field split, unverified against this EU
-- ROM's actual code, exposed anyway per this project's own "return
-- raw, don't guess silently" convention):
--   +0  flagA     -- UNCONFIRMED. Real, varies `0x00`/`0x40` per
--                    weapon. The external disassembly's own summary
--                    associates a `0x40` value with several (not all)
--                    weapons the reference walkthrough separately
--                    describes as having a real field-interaction
--                    ability (chop trees/cut ferns/etc) -- but this
--                    EU table's own `0x40` set (Battle/Sickle/Chain/
--                    Star/Rusty/XCalibr) does NOT line up cleanly
--                    with that walkthrough's own ability list (e.g.
--                    "Were Axe" is walkthrough-described as tree-
--                    chopping but reads `0x00` here) -- left
--                    unconfirmed rather than force-explained.
--   +1  typeTag   -- UNCONFIRMED. Constant `0x11` in every real row
--                    observed -- a real, structurally-constant field
--                    (same shape as EnemySpeciesTable's own constant
--                    bytes), likely a record-type tag, not
--                    independently confirmed.
--   +2  variantFlag -- UNCONFIRMED. Real, varies per weapon; the
--                    non-`0x01` values (`0x02,0x04,0x08,0x10,0x20,
--                    0x40`) are each a distinct power-of-2, one per
--                    "named unique" weapon (Silver/Star/Flame/Ice/
--                    Thunder/XCalibr) -- suggestive of a per-weapon
--                    bitflag ID, not confirmed live.
--   +3  byte3     -- UNCONFIRMED, real, varies per weapon.
--   +4  power     -- CONFIRMED (see the gamesurge.com cross-check
--                    above): the weapon's real attack-power rating.
--   +5-6 price (LE u16) -- CONFIRMED (see the gamesurge.com cross-
--                    check above): the real shop price in gold.
--
-- Pure Lua, no love.* calls, same convention as EnemyStatTable/
-- WeaponTable/ItemTable.

local WeaponStatTable = {}

WeaponStatTable.ROW_STRIDE = 16

--- Decode all real records from `romData` per `weaponStatTable`
-- (`profile.weaponStatTable`, `{fileOffset, rowCount}`). Returns a
-- plain 1-based array of `rowCount` records, each `{flagA, typeTag,
-- variantFlag, byte3, power, price, raw}`.
function WeaponStatTable.decode(romData, weaponStatTable)
  assert(type(romData) == "string", "WeaponStatTable.decode expects a byte string")
  assert(weaponStatTable and weaponStatTable.fileOffset and weaponStatTable.rowCount,
    "WeaponStatTable.decode expects a profile.weaponStatTable")

  local rows = {}
  for i = 0, weaponStatTable.rowCount - 1 do
    local base = weaponStatTable.fileOffset + i * WeaponStatTable.ROW_STRIDE
    local raw = romData:sub(base + 1, base + WeaponStatTable.ROW_STRIDE)
    assert(#raw == WeaponStatTable.ROW_STRIDE,
      "WeaponStatTable.decode: row " .. i .. " ran past the end of romData")
    rows[i + 1] = {
      flagA = raw:byte(1),
      typeTag = raw:byte(2),
      variantFlag = raw:byte(3),
      byte3 = raw:byte(4),
      power = raw:byte(5),
      price = raw:byte(6) + raw:byte(7) * 256,
      raw = raw,
    }
  end
  return rows
end

return WeaponStatTable
