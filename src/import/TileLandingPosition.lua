-- The real, general formula this ROM uses to convert a TILE-space
-- landing coordinate into the actual on-screen PIXEL position a real
-- entity gets committed to -- found 2026-08-14, live-traced end to end
-- for a real "cut" room transition (thirdRoom -> fourthRoom, via the
-- staircase), direct follow-up to the user's own question after task
-- #85's negative result: "ja aber wo kann sie dann liegen? wir müssen
-- die spawn position finden".
--
-- REAL, COMPLETE, LIVE-VERIFIED CHAIN (see docs/reverse-engineering/
-- events.md's own dated entry for the full trace, including exact
-- addresses/frames):
--   1. A real, small, script-opcode-SHAPED handler at bank-0 CPU
--      `$11B7` (`LD A,(HL+) / LD B,A / LD A,(HL-) / LD C,A`) reads TWO
--      literal bytes directly from a real script cursor (`HL`) into
--      `B`/`C` -- for the thirdRoom->fourthRoom transition, live-traced
--      to `HL=$42F9`, real bank 14, real ROM FILE OFFSET `0x382F9`,
--      containing the literal real bytes `0E 0C` (14, 12 decimal) --
--      i.e. this project's own already-documented `landingX=120,
--      landingY=112` for that exact transition is not an arbitrary
--      pixel pair; it is `screenFromTile(14, 12)` (see below), stored
--      as 2 raw bytes directly in ROM. This handler shape (2 literal
--      operand bytes read from an HL cursor, gated on WRAM `$D499`,
--      the SAME real latch this project's own `0xFC`/`0xFD` opcode
--      family already uses) strongly suggests a real, small, separate
--      script/event mechanism this project has not otherwise mapped --
--      NOT the primary 256-opcode `$D85A` system (already proven, via
--      60M+ single-stepped real frames, to NOT drive room transitions
--      at all -- see events.md's "no real script drives the whole
--      start sequence" negative result).
--   2. `B`,`C` (the real tile coordinates) flow through a real bank-1
--      routine (`$44A5`) that converts them to real pixel deltas via
--      EXACTLY the formula below, then through `$4992` (`LD B,0x00 /
--      LD C,0x04 / CALL $0611` -- `C=4` is the real, LIVE-CONFIRMED
--      player entity slot, see `EntityStructLayout
--      .PLAYER_SLOT_INDEX_HYPOTHESIS`, no longer just a hypothesis)
--      into `$0611`, the SAME real per-tick position-commit routine
--      this project already fully disassembled for ordinary entity
--      movement (see the gate-creature sprite investigation earlier
--      the same session) -- i.e. a room-transition "spawn" is not a
--      special-cased write; it's the identical general position-commit
--      primitive every other entity move already goes through.
--   3. Cross-checked against EVERY `landingX`/`landingY` pair already
--      recorded in `rom_profiles.lua` (all 5, independently measured
--      empirically over many earlier sessions, long before this
--      formula was known): every single one decomposes into a clean,
--      small integer tile coordinate via this exact formula (see
--      `tests/import/tile_landing_position_test.lua`) -- strong,
--      independent confirmation this is the ROM's real, general
--      mechanism, not a coincidence specific to the one transition it
--      was live-traced from.
--
-- HONEST SCOPE: the PIXEL formula and the entity-slot/commit mechanism
-- are now proven. What remains genuinely open: WHICH real ROM address
-- holds the literal tile-coordinate bytes for every OTHER room
-- transition (only thirdRoom->fourthRoom's own real source address,
-- `0x382F9`, has actually been located), and what the small `$11B7`-
-- family dispatcher's own real "script" format looks like in general
-- (single opcode, or one of several -- only ONE real instance was
-- traced). A real, concrete, well-scoped next step for whoever
-- continues this, not claimed as solved here.
--
-- Pure Lua, no love.* calls.

local TileLandingPosition = {}

-- Real, hardware-matching constants: standard Game Boy sprite-offset
-- convention (OAM X = pixelX+8, OAM Y = pixelY+16) applied to a TILE
-- (8px) coordinate -- i.e. `screenX = tileX*8 + 8`, `screenY =
-- tileY*8 + 16`. Confirmed live for tile (14,12) -> screen (120,112).
TileLandingPosition.TILE_SIZE = 8
TileLandingPosition.OFFSET_X = 8
TileLandingPosition.OFFSET_Y = 16

--- Real bank-0 CPU address of the `$11B7`-shaped operand-fetch handler
-- this formula was traced through (see this file's own doc comment).
TileLandingPosition.OPERAND_FETCH_HANDLER_ADDRESS = 0x11B7

--- Real bank-1 CPU address of the tile->pixel conversion routine.
TileLandingPosition.CONVERT_ROUTINE_ADDRESS = 0x44A5

function TileLandingPosition.screenFromTile(tileX, tileY)
  return tileX * TileLandingPosition.TILE_SIZE + TileLandingPosition.OFFSET_X,
      tileY * TileLandingPosition.TILE_SIZE + TileLandingPosition.OFFSET_Y
end

--- Inverse of `screenFromTile` -- returns `nil` (not a fabricated
-- fractional tile) when `screenX`/`screenY` don't land exactly on a
-- real tile boundary, per this project's "no silent fallbacks" rule.
function TileLandingPosition.tileFromScreen(screenX, screenY)
  local tx = (screenX - TileLandingPosition.OFFSET_X) / TileLandingPosition.TILE_SIZE
  local ty = (screenY - TileLandingPosition.OFFSET_Y) / TileLandingPosition.TILE_SIZE
  if tx ~= math.floor(tx) or ty ~= math.floor(ty) then
    return nil
  end
  return tx, ty
end

return TileLandingPosition
