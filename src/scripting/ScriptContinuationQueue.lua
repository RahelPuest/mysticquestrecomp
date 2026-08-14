-- Real port of the ROM's own WRAM-resident "script continuation
-- queue" -- see docs/reverse-engineering/events.md's "Opcode 0x00,
-- resolved" section for the full disassembly this implements.
--
-- Real ROM shape: a small FIFO living in WRAM, popped by `$3705`
-- (SP briefly redirected to point at a live cursor pair, `$D8BC`/
-- `$D8BD`, 2 real POPs, real counter `$D865` decremented) and pushed
-- by `$36DF` (the mirror operation: 2 real PUSHes onto the same
-- structure, `$D865` incremented). Two real, confirmed producers push
-- onto it (opcode `0x02` CHAIN, opcode `0x03`); one real, confirmed
-- consumer pops from it (opcode `0x00`, see `StandardScriptHandlers
-- .queueGate`).
--
-- Each real popped entry is a 2-word pair (`B`, `DE` in the real ROM's
-- own registers) -- but `$3297`'s own real logic (byte-for-byte
-- disassembled) only ever does ONE OF TWO THINGS with a popped entry,
-- depending on `B`: if `B==2`, redirect the persistent script cursor
-- to the popped `DE` value and continue; for EVERY other real `B`
-- value seen (`3`, from opcode `0x03`'s own pushes, and structurally
-- any other value too), it just halts, discarding the entry. Since
-- `B` and `C` are otherwise never read back, this project's own queue
-- collapses the real 2-word entry down to exactly what's observably
-- different: `shouldRedirect` (was `B==2`?) and `cursor` (the real
-- `DE` value, meaningful only when `shouldRedirect` is true) --
-- a deliberate, evidence-backed simplification, not a guess.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local ScriptContinuationQueue = {}
ScriptContinuationQueue.__index = ScriptContinuationQueue

function ScriptContinuationQueue.new()
  return setmetatable({
    entries = {},
    head = 1, -- next real POP reads entries[head]
    tail = 0, -- last real PUSH wrote entries[tail]
  }, ScriptContinuationQueue)
end

--- Real `$36DF` port: enqueue one entry. `shouldRedirect`: whether
-- this entry's own real `B` value was `2` (the only real value that
-- causes a later `$3297` pop to redirect the persistent cursor).
-- `cursor`: the real `DE` value pushed alongside it (the interpreter
-- cursor to redirect to, meaningful only when `shouldRedirect` is
-- true -- see this module's own doc comment).
function ScriptContinuationQueue:push(shouldRedirect, cursor)
  self.tail = self.tail + 1
  self.entries[self.tail] = { shouldRedirect = shouldRedirect, cursor = cursor }
end

--- Real `$D865`-empty check (`AND A` on the real counter).
function ScriptContinuationQueue:isEmpty()
  return self.head > self.tail
end

--- Real `$3705` port: dequeue one entry. Returns `shouldRedirect,
-- cursor` (both `nil` if the queue is empty -- callers should check
-- `isEmpty()` first, matching the real ROM's own `$D865`-empty gate
-- coming BEFORE the pop, not after).
function ScriptContinuationQueue:pop()
  if self:isEmpty() then
    return nil, nil
  end
  local entry = self.entries[self.head]
  self.entries[self.head] = nil
  self.head = self.head + 1
  return entry.shouldRedirect, entry.cursor
end

return ScriptContinuationQueue
