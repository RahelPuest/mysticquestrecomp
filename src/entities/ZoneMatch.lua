-- Pure, general rectangular trigger-zone matching -- extracted
-- 2026-08-10 from VictorySequence.lua's own inline `matchedExit` (see
-- docs/progress.md's "tooling improvements" entry: the secondRoom
-- east-exit regressions this same day -- first a missing `xMin` letting
-- ANY x through, then a wrong `xMin` sitting inside a real wall -- both
-- lived in exactly this logic, and BOTH shipped undetected because
-- VictorySequence.lua needs `love.graphics` to even `require()`, so the
-- 170-test headless suite never touched it. Pulling the pure
-- decision logic out here (no love.* calls) makes it directly unit-
-- testable -- see tests/unit/zone_match_test.lua.

local ZoneMatch = {}

--- `zone`: `{xMin=,xMax=,yMin=,yMax=}` -- any field may be omitted,
-- meaning "unbounded on that side" (the exact real convention
-- VictorySequence.lua's room `exits`/rom_profiles.lua already use).
-- Returns true if `(x,y)` is inside.
function ZoneMatch.contains(zone, x, y)
  return (not zone.xMin or x >= zone.xMin) and (not zone.xMax or x <= zone.xMax)
    and (not zone.yMin or y >= zone.yMin) and (not zone.yMax or y <= zone.yMax)
end

--- Returns the first entry of `list` (an array of `{zone=..., ...}`,
-- e.g. a room's own `exits`) whose `zone` contains `(x,y)`, or nil.
-- `list` may itself be nil (a room with no exits) -- returns nil, not
-- an error, matching every call site's existing "no exits" handling.
function ZoneMatch.first(list, x, y)
  if not list then return nil end
  for _, entry in ipairs(list) do
    if ZoneMatch.contains(entry.zone, x, y) then return entry end
  end
  return nil
end

return ZoneMatch
