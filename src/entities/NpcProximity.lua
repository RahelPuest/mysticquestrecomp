-- Pure, one-shot proximity-dialogue matching -- extracted from
-- VictorySequence.lua's inline `matchedNpcDialogue` (see that method's
-- doc comment for the live-trace evidence this is modeled on:
-- secondRoom's NPC dialogue is proximity-triggered, not room-entry-
-- triggered). Pulled out here (no love.* calls) so it's directly
-- unit-testable -- see tests/unit/npc_proximity_test.lua. Same
-- motivation as ZoneMatch.lua's doc comment: this exact shape of logic
-- is precisely where undetected regressions lived.

local NpcProximity = {}

--- `sceneData`: a room's `{name = char, ...}` table (each `char` needs
-- `.dialogue` -- lines, absent for a character with none captured yet
-- -- and a static `.screenX`/`.screenY` spawn-sample fallback).
-- `livePositions`: optional `{name = {x=,y=}}` overriding the static
-- position for a character that actually wanders (nil/absent entries
-- fall back to `char.screenX/screenY`). `player`: `{x=,y=,width=,
-- height=}`. `isShown(name)`: predicate -- true once this character's
-- dialogue has already fired once (one-shot behavior). `pad`: proximity
-- margin in px around the character's 16x16 footprint (default 8 -- a
-- reasonable approximation, not independently pixel-verified; the
-- trigger radius wasn't separately bracketed, same honesty status as
-- KnockbackFlicker.lua's direction extrapolation).
--
-- Returns `(dialogueLines, name)` for the first matched, not-yet-shown
-- character, or nil.
function NpcProximity.match(sceneData, livePositions, player, isShown, pad)
  if not sceneData or not player then return nil end
  pad = pad or 8
  for name, char in pairs(sceneData) do
    if char.dialogue and not isShown(name) then
      local live = livePositions and livePositions[name]
      local cx = (live and live.x) or char.screenX
      local cy = (live and live.y) or char.screenY
      local nx, ny = cx - pad, cy - pad
      local nw, nh = 16 + pad * 2, 16 + pad * 2
      if player.x < nx + nw and player.x + player.width > nx
          and player.y < ny + nh and player.y + player.height > ny then
        return char.dialogue, name
      end
    end
  end
  return nil
end

return NpcProximity
