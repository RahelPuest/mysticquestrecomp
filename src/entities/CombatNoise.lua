-- Port of ROM routine `$2B1E` (bank 0, always mapped) -- the PRNG draw
-- combat's damage/HP formulas use. Disassembled fresh (see
-- docs/reverse-engineering/rom-map.md "$50AC, the damage formula") to
-- get the exact algorithm, not a `math.random()` stand-in:
--
--   $2B1E  LD A,(0xC0B0)   ; A = counter
--   $2B22  INC A            ; counter += 1 (wraps 255->0, plain 8-bit)
--   $2B23  LD (0xC0B0),A
--   $2B26  LD L,A           ; L = new counter
--   $2B27  LD A,(0xC0B1)    ; A = cap byte
--   $2B2A  CP L
--   $2B2B  JR NZ,$2B31       ; if counter == cap:
--   $2B2D  DEC A             ;   cap -= 1 (wraps 255->0)
--   $2B2E  LD (0xC0B1),A     ;   store back
--   $2B31  ...               ; HL = table[0x2A1E + counter] (H)
--                             ; then A = H, HL = table[0x2A1E + cap]
--   $2B3D  ADD A,(HL)        ; RESULT = table[counter] + table[cap] (8-bit wrap)
--
-- i.e. this is a combined double-lookup PRNG (an advancing position
-- counter summed with a second, much-more-slowly-drifting "cap" index
-- that only decrements when the fast counter catches up to it) -- not
-- a plain single-counter table walk. Both internal state bytes wrap
-- mod 256, matching the 8-bit registers exactly.
--
-- Real hardware's starting `$C0B0`/`$C0B1` values (whatever WRAM
-- happens to hold at boot) are not reproduced here -- this project has
-- no way to observe the original cartridge's true power-on RAM state,
-- and doing so isn't the point: what matters is porting the algorithm/
-- shape, not one specific cartridge's boot-time seed. Both counters
-- start at 0 here, a clearly-documented choice, not a claimed ROM fact.
--
-- Pure Lua, no love.* calls -- headlessly testable.

local CombatNoise = {}
CombatNoise.__index = CombatNoise

--- `noiseTableBytes`: a 256-entry 1-based array of integers 0-255, as
-- returned by `NoiseTable.decode`.
function CombatNoise.new(noiseTableBytes)
  assert(type(noiseTableBytes) == "table" and #noiseTableBytes == 256,
    "CombatNoise.new expects a 256-entry noise table (see NoiseTable.decode)")
  return setmetatable({
    table = noiseTableBytes,
    counter = 0,
    cap = 0,
  }, CombatNoise)
end

--- One PRNG draw (0-255), advancing internal state exactly like the
-- ROM routine.
function CombatNoise:draw()
  self.counter = (self.counter + 1) % 256
  if self.cap == self.counter then
    self.cap = (self.cap - 1) % 256
  end
  -- `NoiseTable.decode`'s array is 1-based; counter/cap are 0-based
  -- byte indices into the 256-byte table, hence the +1.
  local value = (self.table[self.counter + 1] + self.table[self.cap + 1]) % 256
  return value
end

return CombatNoise
