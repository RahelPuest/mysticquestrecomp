-- DEV-ONLY browser for the real, RNG-gated "actor-definition table"
-- this session found (2026-08-16, direct continuation, "NPC-
-- Platzierungstabelle suchen" -> "Tabelle voll ausmessen" -- see
-- ActorDefinitionTable.lua's own doc comment for the full live-trace/
-- static-search derivation). Same "real content, no fabricated
-- trigger" precedent as RoomExplorer.lua (F8) / MusicJukebox.lua (F9)
-- / TransitionExplorer.lua (F10): this table's own real DATA (218
-- records, indices 0-217, each with a real embedded sprite-sub-record
-- pointer) is fully decoded and tested, but only 2 of the 218 have a
-- confirmed live spawn behind them -- the index actually used at
-- runtime is computed via the real combat PRNG, not a fixed per-room
-- constant, so this is an explicit developer browser for the full
-- underlying table, not a claim that all 218 are individually
-- reachable/meaningful through ordinary play.
--
-- Controls: UP/DOWN (or A/B) = previous/next entry, LEFT/RIGHT =
-- jump to the previous/next entry flagged anomalous (index 0 and the
-- 12-15 cluster -- see ActorDefinitionTable.lua's own doc comment for
-- what "anomalous" means here), SELECT or F11 = exit back to Field.

local ActorDefinitionTable = require("src.import.ActorDefinitionTable")

local ActorExplorer = { opaque = true }
ActorExplorer.__index = ActorExplorer

function ActorExplorer.new(romData, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    input = input,
    overlay = overlay,
    stack = stack,
    index = 1,
  }, ActorExplorer)

  self.entries = ActorDefinitionTable.scanTable(romData)
  self.liveLabelByIndex = {} -- 0-based table index -> label, the 2 real live-confirmed spawns
  for _, l in ipairs(ActorDefinitionTable.LIVE_CONFIRMED) do
    self.liveLabelByIndex[l.index] = l.plausibleCharacter
  end
  return self
end

function ActorExplorer:_current()
  return self.entries[self.index]
end

function ActorExplorer:_currentLiveLabel()
  local e = self:_current()
  if not e then return nil end
  return self.liveLabelByIndex[e.index]
end

--- The full `plausibleCharacter` strings in `ActorDefinitionTable
-- .LIVE_CONFIRMED` are long, explanatory doc-comment-style sentences
-- (correctly so, for the Lua source and the website) -- WAY too long
-- for this dev browser's native 160px-wide GB canvas (found live via
-- an actual `love .` screenshot, not guessed). Strips the room/scene
-- prefix and any trailing " (...)" explanation, keeping just the
-- short character name/label -- same real string, just not the full
-- sentence on this cramped screen (the full text is still what the
-- website/module themselves show).
local function shortLabel(full)
  local trimmed = full:match("^(.-)%s*%(") or full
  return trimmed:match("scene%.(.+)$") or trimmed
end

function ActorExplorer:keypressed(key)
  if key == "f11" and self.stack then
    self.stack:pop()
  end
end

function ActorExplorer:update(dt)
  if self.stack and self.input:pressed("select") then
    self.stack:pop()
    return
  end
  local n = #self.entries
  if n == 0 then return end
  if self.input:pressed("down") or self.input:pressed("b") then
    self.index = self.index % n + 1
  elseif self.input:pressed("up") or self.input:pressed("a") then
    self.index = (self.index - 2) % n + 1
  elseif self.input:pressed("right") then
    -- Jump to the next entry flagged anomalous (wraps).
    for i = 1, n do
      local e = self.entries[(self.index - 1 + i) % n + 1]
      if e.anomalous then
        self.index = (self.index - 1 + i) % n + 1
        break
      end
    end
  elseif self.input:pressed("left") then
    -- Jump to the previous entry flagged anomalous (wraps).
    for i = 1, n do
      local e = self.entries[(self.index - 1 - i) % n + 1]
      if e.anomalous then
        self.index = (self.index - 1 - i) % n + 1
        break
      end
    end
  end
end

function ActorExplorer:debugState()
  local e = self:_current()
  if not e then return { index = self.index, count = #self.entries } end
  return {
    index = self.index,
    count = #self.entries,
    tableIndex = e.index,
    allocParam = e.allocParam,
    spritePointer = e.spritePointer,
    anomalous = e.anomalous,
    liveVerified = self:_currentLiveLabel() ~= nil,
  }
end

function ActorExplorer:draw()
  love.graphics.setColor(0.05, 0.05, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(
    string.format("DEV Akteure %d/%d", self.index, #self.entries), 4, 4)

  local e = self:_current()
  if e then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("Index=%d", e.index), 4, 20)
    love.graphics.print(string.format("allocParam=%d", e.allocParam), 4, 32)
    love.graphics.print(string.format("spritePointer=0x%X", e.spritePointer), 4, 44)
    love.graphics.print(string.format("ROM-Offset: 0x%X", e.fileOffset), 4, 56)

    if e.anomalous then
      love.graphics.setColor(1, 0.7, 0.5, 1)
      love.graphics.print("ANOMAL (Bank-0-Pointer)", 4, 68)
      love.graphics.setColor(1, 1, 1, 1)
    elseif e.spriteSubRecord then
      love.graphics.print(string.format("Sub-Record: 0x%X", e.spriteSubRecord.fileOffset), 4, 68)
    end

    local liveLabel = self:_currentLiveLabel()
    if liveLabel then
      love.graphics.setColor(0.6, 1, 0.6, 1)
      love.graphics.print("LIVE-SPAWN:", 4, 88)
      love.graphics.print(shortLabel(liveLabel), 4, 100)
      love.graphics.setColor(1, 1, 1, 1)
    else
      love.graphics.setColor(1, 0.7, 0.5, 1)
      love.graphics.print("Spawn: RNG-Index", 4, 88)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  love.graphics.print("UP/DN Eintrag", 4, 112)
  love.graphics.print("L/R Anomal", 4, 122)
  love.graphics.print("SELECT/F11 Exit", 4, 132)

  if self.overlay and e then
    self.overlay:addLine("actors (dev-only, meiste Spawns unbekannt)",
      string.format("%d/%d index=%d anomalous=%s", self.index, #self.entries, e.index, tostring(e.anomalous)))
  end
end

return ActorExplorer
