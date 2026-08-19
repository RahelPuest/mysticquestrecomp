-- Pure "hold direction against a wall for N frames" trigger tracker --
-- reproduces a ROM mechanic found live: fourthRoom's cut-transition
-- into fifthRoom needs the player to hold a specific direction while
-- blocked against a wall, not firing instantly the moment the player's
-- position enters the trigger zone the way this project's general
-- per-frame zone-check exit mechanism otherwise does (see
-- rom_profiles.lua's `fourthRoom.exits` doc comment for the full
-- evidence trail).
--
-- CORRECTED (2026-08-18, direct user instruction "kopiere den
-- kollisions/timer mechanismus"): an earlier version of this doc
-- comment claimed the real ROM needs the direction "held continuously"
-- for the whole ~64-frame duration -- a live re-trace (WRAM write-
-- watchpoint on `$D49A` + full disassembly) DISPROVED that: the real
-- ROM only needs 9 consecutive blocked-and-held frames to ARM a
-- one-shot state machine that then runs to completion entirely on its
-- own, independent of any further input (live-verified: releasing the
-- direction after just 15 frames still lands the player at the exact
-- real spot, ~64 frames after the hold started). The ~64 frames is a
-- real, reproducible AUTONOMOUS ANIMATION duration (a WRAM wipe-band
-- counter, `$D49A`, ramping 0->30 then 30->0), not a continuous input
-- requirement. This module's own `holdFrames`/consecutive-frame-count
-- behavior below is unchanged and, read as "the ARM threshold," is
-- exactly correct -- only the THRESHOLD VALUE passed by the caller
-- needed correcting (64 -> 9, see rom_profiles.lua's `fourthRoom.exits`
-- doc comment for the full trace). Firing immediately once armed (this
-- module's existing behavior) is the honest analog of the real
-- autonomous completion, since this engine doesn't render the
-- intervening wipe animation.
--
-- Extracted as its own pure, headlessly-tested module (no love.* calls)
-- rather than inlined into VictorySequence.lua, matching this project's
-- established "pull the decision logic out, keep the love-side plumbing
-- thin" convention (see ZoneMatch.lua/NpcProximity.lua's doc comments --
-- the exact same class of regression those modules were extracted to
-- prevent: VictorySequence.lua needs `love.graphics` to even
-- `require()`, so the headless test suite can't otherwise reach this
-- logic at all).

local HoldTrigger = {}

--- `state`: a plain `{ frames = <int> }` table the caller owns (one per
-- exit that needs this, persisted across frames -- see
-- VictorySequence.lua's `self.holdTriggerState`).
--
-- `matched`: true if the player is inside the exit's zone and holding
-- the exit's required direction this frame -- the caller's
-- responsibility to compute (this module doesn't know about
-- zones/input).
--
-- Returns true the instant `state.frames` reaches `holdFrames` (and
-- resets `state.frames` to 0 so a second attempt -- e.g. walking away
-- and back -- needs the full arm threshold again, matching the real
-- ROM's own arming behavior -- see this module's own top-of-file doc
-- comment: `holdFrames` should be the real ARM threshold, not the
-- longer autonomous-animation duration that follows it). Also resets
-- `state.frames` to 0 the instant `matched` goes false.
function HoldTrigger.step(state, matched, holdFrames)
  if not matched then
    state.frames = 0
    return false
  end
  state.frames = state.frames + 1
  if state.frames >= holdFrames then
    state.frames = 0
    return true
  end
  return false
end

return HoldTrigger
