-- Stack of game states. The top state receives input/update; draw runs
-- bottom-up starting from the last *opaque* state (so a translucent overlay
-- state, e.g. a pause menu, doesn't require states beneath it to redraw
-- themselves manually). Pattern adopted from gen1recomp's StateStack (see
-- docs/gen1recomp-analysis.md SS2); genre-agnostic engine plumbing.
--
-- A state is a plain table with optional callbacks:
--   state:enter(...)         called when pushed
--   state:exit()             called when popped
--   state:pause()            called when another state is pushed on top
--   state:resume()           called when the state above it is popped
--   state:update(dt)
--   state:draw()
--   state:keypressed(key, scancode, isrepeat)
--   state:keyreleased(key, scancode)
--   state.opaque             boolean; defaults to true (see draw() below)

local StateStack = {}
StateStack.__index = StateStack

function StateStack.new()
  return setmetatable({ stack = {} }, StateStack)
end

function StateStack:push(state, ...)
  local top = self.stack[#self.stack]
  if top and top.pause then top:pause() end
  self.stack[#self.stack + 1] = state
  if state.enter then state:enter(...) end
  return state
end

function StateStack:pop()
  local top = self.stack[#self.stack]
  if not top then return nil end
  self.stack[#self.stack] = nil
  if top.exit then top:exit() end
  local newTop = self.stack[#self.stack]
  if newTop and newTop.resume then newTop:resume() end
  return top
end

--- Pop every state and push a new one -- a full state switch. Exits each
-- state top-down WITHOUT calling resume() on the ones beneath it: unlike a
-- single pop(), nothing is left running afterward, so a state that's about
-- to be torn down anyway should never see a spurious resume right before
-- its own exit (e.g. it could restart music just to have it killed a
-- moment later).
function StateStack:replace(state, ...)
  for i = #self.stack, 1, -1 do
    local s = self.stack[i]
    self.stack[i] = nil
    if s.exit then s:exit() end
  end
  return self:push(state, ...)
end

function StateStack:top()
  return self.stack[#self.stack]
end

function StateStack:update(dt)
  local top = self:top()
  if top and top.update then top:update(dt) end
end

function StateStack:draw()
  -- Find the topmost opaque state; draw from there upward so translucent
  -- states on top layer correctly over whatever's beneath them.
  local startIndex = 1
  for i = #self.stack, 1, -1 do
    local s = self.stack[i]
    if s.opaque ~= false then
      startIndex = i
      break
    end
  end
  for i = startIndex, #self.stack do
    local s = self.stack[i]
    if s.draw then s:draw() end
  end
end

local function dispatch(self, method, ...)
  local top = self:top()
  if top and top[method] then top[method](top, ...) end
end

function StateStack:keypressed(...) dispatch(self, "keypressed", ...) end
function StateStack:keyreleased(...) dispatch(self, "keyreleased", ...) end
function StateStack:textinput(...) dispatch(self, "textinput", ...) end

return StateStack
