-- DEV-ONLY browser for the real, general "cut-transition landing
-- table" this project found 2026-08-16 (task "komplett autark
-- interpretiert"/blocker resolution -- see CutTransitionTable.lua's
-- own doc comment for the full live-trace/static-search derivation).
-- Same "real content, no fabricated trigger" precedent as
-- RoomExplorer.lua (F8) / MusicJukebox.lua (F9): this table's own real
-- DATA (target roomSelector + real landing tile, for 82 genuinely
-- distinct transitions) is fully decoded and tested, but which real
-- story/dialogue moment actually TRIGGERS most of them in-game is
-- still honestly unknown (a time-boxed live search found nothing new)
-- -- so this is an explicit, clearly-labeled developer browser, not a
-- claim that all 82 are reachable through ordinary play.
--
-- Controls: UP/DOWN (or A/B) = previous/next entry, LEFT/RIGHT =
-- jump to the previous/next `roomSelector` group, SELECT or F10 =
-- exit back to Field.

local CutTransitionTable = require("src.import.CutTransitionTable")

local TransitionExplorer = { opaque = true }
TransitionExplorer.__index = TransitionExplorer

function TransitionExplorer.new(romData, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    input = input,
    overlay = overlay,
    stack = stack,
    index = 1,
  }, TransitionExplorer)

  self.entries = CutTransitionTable.distinctLandings(romData)
  self.knownLive = {} -- keyed "roomSelector:pixelX:pixelY" -> label, same 2 real, live-verified transitions rom_profiles.lua's own exits actually use
  self.knownLive["1:120:112"] = "thirdRoom -> fourthRoom (im Spiel verdrahtet)"
  self.knownLive["4:136:32"] = "fourthRoom -> fifthRoom (im Spiel verdrahtet)"
  return self
end

function TransitionExplorer:_current()
  return self.entries[self.index]
end

function TransitionExplorer:_currentLiveLabel()
  local e = self:_current()
  if not e then return nil end
  return self.knownLive[e.roomSelector .. ":" .. e.pixelX .. ":" .. e.pixelY]
end

function TransitionExplorer:keypressed(key)
  if key == "f10" and self.stack then
    self.stack:pop()
  end
end

function TransitionExplorer:update(dt)
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
    -- Jump to the first entry of the NEXT roomSelector group.
    local cur = self:_current().roomSelector
    for i = 1, n do
      local e = self.entries[(self.index - 1 + i) % n + 1]
      if e.roomSelector ~= cur then
        self.index = (self.index - 1 + i) % n + 1
        break
      end
    end
  elseif self.input:pressed("left") then
    -- Jump to the first entry of the PREVIOUS roomSelector group.
    local cur = self:_current().roomSelector
    local target
    for i = 1, n do
      local e = self.entries[(self.index - 1 - i) % n + 1]
      if e.roomSelector ~= cur then
        target = e.roomSelector
        break
      end
    end
    if target then
      for i = 1, n do
        if self.entries[i].roomSelector == target then
          self.index = i
          break
        end
      end
    end
  end
end

function TransitionExplorer:debugState()
  local e = self:_current()
  if not e then return { index = self.index, count = #self.entries } end
  return {
    index = self.index,
    count = #self.entries,
    roomSelector = e.roomSelector,
    targetFamily = e.targetFamily,
    pixelX = e.pixelX,
    pixelY = e.pixelY,
    tileCol = e.tileCol,
    tileRow = e.tileRow,
    occurrences = e.occurrences,
    liveVerified = self:_currentLiveLabel() ~= nil,
  }
end

function TransitionExplorer:draw()
  love.graphics.setColor(0.05, 0.05, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(
    string.format("DEV Uebergaenge %d/%d", self.index, #self.entries), 4, 4)

  local e = self:_current()
  if e then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("roomSelector=%d", e.roomSelector), 4, 20)
    love.graphics.print(e.targetFamily, 4, 32)
    love.graphics.print(string.format("Tile (%d,%d) Pixel (%d,%d)", e.tileCol, e.tileRow, e.pixelX, e.pixelY), 4, 44)
    love.graphics.print(string.format("Vorkommen: %d", e.occurrences), 4, 56)
    love.graphics.print(string.format("ROM-Offset: 0x%X", e.exampleFileOffset), 4, 68)

    local liveLabel = self:_currentLiveLabel()
    if liveLabel then
      love.graphics.setColor(0.6, 1, 0.6, 1)
      love.graphics.print("LIVE-VERIFIZIERT:", 4, 84)
      love.graphics.print(liveLabel, 4, 96)
      love.graphics.setColor(1, 1, 1, 1)
    else
      love.graphics.setColor(1, 0.7, 0.5, 1)
      love.graphics.print("Trigger unbekannt", 4, 84)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  love.graphics.print("UP/DN Eintrag, L/R Gruppe", 4, 122)
  love.graphics.print("SELECT/F10 Exit", 4, 132)

  if self.overlay and e then
    self.overlay:addLine("transitions (dev-only, meiste Trigger unbekannt)",
      string.format("%d/%d roomSelector=%d %s", self.index, #self.entries, e.roomSelector, e.targetFamily))
  end
end

return TransitionExplorer
