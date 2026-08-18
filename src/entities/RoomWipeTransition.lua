-- The visual effect this ROM uses for "cut" (jump-cut) room
-- transitions -- distinct from the hardware-scroll pan already modeled
-- in `VictorySequence.lua`'s "transitioning" phase, and distinct from
-- the other cut style (a solid black backdrop room,
-- `unknownRoomB`/roomSelectors 14-15, already reproduced via a plain
-- black rectangle in `VictorySequence.lua`'s cutscene-phase draw code
-- -- see that file's doc comment, "This project's recomp already
-- reproduces the same visual effect through different means").
--
-- FOUND (direct user instruction to search the ROM for the algorithms
-- behind jump-cut transitions, which are either a wipe-cut from top and
-- bottom or a fade to black): live-traced the thirdRoom->fourthRoom
-- staircase cut (`tools/rom/checkpoints.third_room_free()` + walking to
-- the exit zone), capturing screenshots every 2 frames across the whole
-- transition while independently confirming via WRAM (`$C244`/`$C245`
-- position, `$D392`/`$D393` room pointer, `$FF42`/`$FF43` SCY/SCX) that
-- neither the player's position nor the hardware scroll registers move
-- during the visual change -- ruling out camera movement or a
-- scroll-based explanation. The visual, confirmed via a dense
-- screenshot sequence: the old room shrinks from its full height down
-- to a thin horizontal band, symmetrically from the top edge and the
-- bottom edge converging toward the room's vertical center (matching
-- the player's Y position, where the staircase sits) -- not a
-- scroll-off-screen wipe, a `$D392`/`$D393`-pointer-unchanged visual
-- effect that happens before the room pointer commits. Once fully
-- closed (ROM room pointer changes here, live-confirmed), the new
-- room's content grows back out from that same thin band.
--
-- HONEST SCOPE: the underlying ROM mechanism was not fully traced to a
-- byte-for-byte VRAM write algorithm this pass (a BG tilemap ID dump
-- across the whole sequence showed the same tile IDs present
-- throughout -- the visual change comes from the actual tile pattern
-- data in VRAM being rewritten in place, not from tilemap ID changes
-- or the Window layer, which stayed disabled throughout per `$FF40`
-- bit 5 -- tracing that VRAM-pattern-rewrite routine itself is a
-- separate, not-yet-attempted follow-up). What is real and live-
-- measured: the closing half takes approximately 20 frames (screenshots
-- confirm the room is still fully open at frame 17004 and fully closed
-- by frame 17026, both relative to the same reproducible checkpoint
-- sequence) -- `CLOSE_FRAMES` below uses that number. The opening
-- half's duration was not independently measured to the same rigor
-- (harder to cleanly isolate the moment it reaches "fully open" from
-- ordinary room-edge rendering) -- `OPEN_FRAMES` mirrors `CLOSE_FRAMES`
-- as a reasonable, explicitly-flagged default, not an independently
-- confirmed value.
--
-- This project's recomp reproduces the visual result (a band that
-- closes then reopens, real-timed) via `love.graphics.setScissor`
-- rather than the VRAM-tile-pattern-rewrite mechanism -- same "same
-- effect, different means" precedent already established for the
-- black-backdrop cut style.
--
-- Pure Lua, no love.* calls -- the actual clipping/drawing is
-- VictorySequence.lua's job.

local RoomWipeTransition = {}

RoomWipeTransition.CLOSE_FRAMES = 20 -- live-measured (see doc comment above)
RoomWipeTransition.OPEN_FRAMES = 20  -- mirrored default, not independently measured

--- Returns `top, height` (pixels) of the currently-visible horizontal
-- band within a room area `fullHeight` pixels tall, given elapsed
-- `frame`s (0-based) out of `totalFrames` for the given `phase`
-- (`"closing"` or `"opening"`). Symmetric top/bottom convergence toward
-- `centerY` (defaults to `fullHeight/2` if omitted), matching the
-- live-observed effect -- CORRECTED (same live verification pass,
-- direct `love .` screenshot comparison): the ROM's wipe converges
-- toward wherever the exit/player actually is on screen (live-observed
-- near the top of the room for the thirdRoom staircase, Y=24 of a
-- 128px-tall playable area, not the room's geometric middle) -- a
-- fixed room-center convergence point looked visibly wrong (band
-- forming far from the doorway) the first time this was tried and
-- rendered. `centerY` is clamped so the band never extends past `[0,
-- fullHeight]` even when the convergence point sits near an edge.
-- Clamps `frame` to `[0, totalFrames]` so a caller doesn't need to
-- separately guard against an off-by-one overshoot.
function RoomWipeTransition.visibleBand(phase, frame, totalFrames, fullHeight, centerY)
  assert(phase == "closing" or phase == "opening",
    "RoomWipeTransition.visibleBand: phase must be 'closing' or 'opening', got " .. tostring(phase))
  assert(totalFrames > 0, "RoomWipeTransition.visibleBand: totalFrames must be > 0")
  centerY = centerY or (fullHeight / 2)

  local t = frame / totalFrames
  if t < 0 then t = 0 end
  if t > 1 then t = 1 end

  -- `openFraction`: 0 = fully closed (zero-height band), 1 = fully
  -- open (the whole real room height visible).
  local openFraction = (phase == "closing") and (1 - t) or t

  local height = fullHeight * openFraction
  -- Grow/shrink symmetrically around `centerY`, then clamp the whole
  -- band back inside `[0, fullHeight]` (a `centerY` near an edge would
  -- otherwise push part of the band out of the real room area).
  local top = centerY - height / 2
  if top < 0 then top = 0 end
  if top + height > fullHeight then top = fullHeight - height end
  return top, height
end

return RoomWipeTransition
