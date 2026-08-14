-- A real, reusable, data-driven event/trigger system -- built to fix a
-- concrete deviation from this project's own master brief: "Do NOT
-- simulate every event using hardcoded map-specific Lua if a reusable
-- event architecture can represent it." Before this module existed, the
-- one known real event (the post-boss "Willy" dialogue) was an
-- `if self.dialogueQueued then push DialogueBox end` inline in
-- Field.lua -- exactly the anti-pattern the brief calls out by name.
--
-- WHAT THIS IS: a small, pure, headlessly-testable engine that holds a
-- list of `{ trigger = fn(state) -> bool, actions = {...}, once = bool }`
-- event definitions and fires an event's actions the first (or every)
-- time its trigger condition becomes true. It does not know what any
-- action *means* -- that's the caller-supplied `dispatch(action, state)`
-- function's job (see Field.lua for the one that knows how to push a
-- real DialogueBox, etc.) -- keeping this module free of love.* calls.
--
-- WHAT THIS IS NOT (yet): a decoder for the real Mystic Quest ROM script
-- format. That format is still only a well-evidenced HYPOTHESIS (the
-- FFA-Disassembly project's documented ~1283-script bytecode engine --
-- see docs/reverse-engineering/rom-map.md "External source" / the new
-- events.md), not confirmed against this EU ROM, let alone decoded into
-- data this system could consume directly. The event *definitions* this
-- project currently supplies (e.g. Field.lua's `FIELD_EVENTS`) are still
-- hand-authored from live-observed behavior, same honesty status as
-- before -- what changed is that they're now expressed as real,
-- reusable, inspectable data instead of imperative one-off code, so the
-- moment real ROM script data IS decoded, it has a real system to
-- import into rather than needing one built from scratch.
--
-- Action *types* are deliberately named after the master brief's own
-- list ("dialogue, movement, flags, conditional branches, item grants,
-- map changes, NPC visibility, boss triggers, cutscenes, transitions")
-- so the vocabulary is ready even though only "dialogue" has a real
-- dispatch handler implemented so far (see Field.lua) -- unimplemented
-- action types fail loudly via the dispatcher, per this project's "no
-- silent fallbacks" rule, rather than being silently ignored.

local EventSystem = {}
EventSystem.__index = EventSystem

--- `events`: array of `{ id, trigger = function(state) -> boolean,
-- actions = { {type=...,...}, ... }, once = boolean (default true) }`.
function EventSystem.new(events)
  return setmetatable({
    events = events,
    fired = {},
  }, EventSystem)
end

--- Check every not-yet-fired (or repeatable) event's trigger against
-- `state` (a plain table/object the caller controls the shape of --
-- this module never inspects it, only passes it through), and call
-- `dispatch(action, state)` once per action for every event that fires
-- this call. Returns the list of event ids that fired, for tests/
-- debugging (e.g. the F1 overlay can show "last event fired").
function EventSystem:update(state, dispatch)
  local justFired = {}
  for i, event in ipairs(self.events) do
    local once = event.once ~= false
    if not (once and self.fired[i]) then
      if event.trigger(state) then
        if once then self.fired[i] = true end
        for _, action in ipairs(event.actions) do
          dispatch(action, state)
        end
        justFired[#justFired + 1] = event.id
      end
    end
  end
  return justFired
end

--- True if the (one-shot) event with this id has already fired --
-- lets a trigger function reference another event's completion (a
-- plain building block for "conditional branches" per the master
-- brief's action-type list) without the caller tracking flags by hand.
function EventSystem:hasFired(id)
  for i, event in ipairs(self.events) do
    if event.id == id then return self.fired[i] == true end
  end
  return false
end

return EventSystem
