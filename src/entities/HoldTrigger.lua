-- Pure "hold direction against a wall for N frames" trigger tracker --
-- reproduces a ROM mechanic found live: fourthRoom's cut-transition
-- into fifthRoom needs the player to hold a specific direction for ~64
-- frames while blocked against a wall -- confirmed via precise, frame-
-- by-frame live testing, not firing instantly the moment the player's
-- position enters the trigger zone the way this project's general
-- per-frame zone-check exit mechanism otherwise does (see
-- rom_profiles.lua's `fourthRoom.exits` doc comment for the full
-- evidence trail).
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
-- resets `state.frames` to 0 so a second trigger -- e.g. walking away
-- and back -- needs the full hold again, matching the ROM's "must be
-- held continuously" behavior, not an accumulating total across
-- separate attempts). Also resets `state.frames` to 0 the instant
-- `matched` goes false.
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
