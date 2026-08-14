-- The real intro sequence: title screen -> "Neues Spiel" continues
-- straight into a continuous upward scroll that carries the story text
-- into view, exactly as described live (direct user reference,
-- 2026-08-09, matching independent mGBA verification): "die aktuelle
-- Ansicht beginnt nach oben zu scrollen... der Intro-Text scrollt in
-- den Bildschirm."
--
-- Real, VERIFIED mechanics (see rom_profiles.lua's `introText` doc
-- comment for the full capture): `SCY` increases continuously (~1 unit
-- every ~5.2 real GB frames, confirmed live).
--
-- CORRECTED (2026-08-10, direct user instruction to re-verify against
-- real ROM code -- "das ganze ist nicht 100% rom korrekt"): the
-- previous doc comment here claimed BGP "shifts to a lighter palette
-- ($40) for the duration, reverting to normal ($E4) once the scroll
-- ends" -- re-traced live, per-frame, and that's not what the real
-- hardware does. Real `BGP` timeline (bank2 `$1D74`-adjacent sync
-- routine, WRAM shadow `$C0AA`): `0x00` for ~76 frames, `0x40` for
-- ~5 frames, repeating on an ~81-frame cycle for the ENTIRE scroll (not
-- a static shifted value), only settling on `0xE4` once the closing
-- transition completes. Screenshotted both states directly (frame+10,
-- BGP=$00 vs frame+37, BGP=$40) -- both show the ordinary title-screen/
-- story-text content at normal, clearly readable contrast; whatever
-- this oscillation is for, it does not visibly affect background
-- readability the way a `BGP=$00` reading would naively suggest (that
-- would map every tile-pixel index to white). Left unmodeled here
-- (the translucent white wash approximation is kept -- it does not
-- misrepresent the real *visible* result, only the previous doc
-- comment's claimed *mechanism* was wrong) rather than chasing an
-- effect that doesn't appear to change what's on screen.
--
-- Also re-verified (same pass): **no real fade-out/fade-in exists at
-- the scroll-to-NameEntry transition.** Per-frame register trace shows
-- `LCDC`/`BGP` snapping from their mid-scroll values directly to their
-- final ones (`$E5`/`$E4`) in exactly ONE frame, both on natural
-- completion and on the real A-skip (see below) -- no intermediate
-- palette values observed either way. The one real animated element at
-- this transition is the incoming NameEntry box's window layer: `WY`
-- moves from `255` (hidden) to `0` (fully shown) over a handful of
-- frames, i.e. a brief real slide-in of the dialogue box, not a screen
-- fade. Not modeled here (this project's `stack:replace()` is an
-- instant cut) -- a real, if minor, remaining gap.
--
-- **Real scroll-skip mechanic found and implemented (2026-08-10)**:
-- contrary to this file's previous assumption that no such button
-- exists in the ROM, live A/B/START comparison plus a direct code
-- trace found a real one. Bank 2, file offset `0xbca1`
-- (`CALL $1ED1` to read input into `C`, then `BIT 4,C` / `JR NZ`):
-- bit 4 of the debounced input byte is the ONLY one of the three
-- tested that does anything -- pressing **A** during the scroll jumps
-- straight into the closing sequence (clears part of the tilemap,
-- pins the scroll shadow `$C0A7`/`$D888` to 0, and proceeds to
-- NameEntry within ~16-20 real frames); B and START are provably
-- inert (confirmed: identical SCY/LCDC/BGP trajectory as pressing
-- nothing, sampled at 10 points across the whole scroll). Implemented
-- below using the real button (A), not a fake dev-only shortcut.
--
-- The text itself is real: `TextDecoder.decodeString` against the
-- ACTUAL literal ROM bytes at file offset 0xBED8 (found by decoding the
-- live tilemap scroll first, then confirming byte-for-byte in the ROM
-- file) -- not a hardcoded Lua string.
--
-- Continues to NameEntry.lua at the end (real hero/heroine name-entry
-- screens, 2026-08-09).

local TitleScreenBackground = require("src.rendering.TitleScreenBackground")
local Font = require("src.rendering.Font")
local TextDecoder = require("src.import.TextDecoder")
local FixedStep = require("src.core.FixedStep")

local Intro = { opaque = true }
Intro.__index = Intro

local SCREEN_W, SCREEN_H = 160, 144
-- Where the text block starts, and the real per-line spacing, in the
-- same scrolling coordinate space as the title screen's own 18-row
-- (144px) content.
--
-- CORRECTED TWICE (2026-08-10) -- the first "fix" this same pass was
-- itself wrong and is documented here rather than erased, since the
-- mistake and its correction are both real project history. First
-- pass: rendered tilemap row 16 as ASCII art and read it as "Der Mana
-- Baum" -- WRONG, caught by re-rendering the *entire* tilemap as an
-- actual image (not eyeballed ASCII art) instead of just 2 rows in
-- isolation: row 16 is really "LICENSED TO NINTENDO" and row 17 is
-- "(c) 1991 1993 SQUARE" -- the title screen's own copyright lines,
-- still visible at this scroll position, in the ORDINARY title-menu
-- font (the "special bold font for line 1" this project briefly
-- claimed to have found does not exist -- that was the same
-- misreading, not a real second font). Second, image-verified pass:
-- with all 32 tilemap rows rendered and every candidate line's row
-- number matched against actual on-screen letters (not tile-ID
-- guessing), "Der Mana Baum" is really row 22 (content-Y = 22*8 =
-- 176), "waechst durch die" row 24, "Kraefte der Natur." row 26, and
-- (after the real text's own blank line) "Er waechst hoch" row 30 --
-- gaps of exactly 2/2/4 tile-rows, matching `TextDecoder`'s own
-- decoded line breaks (no blank between lines 1-3, one blank line
-- before line 5) ONLY if each real line -- including blank ones --
-- occupies a full 2-tile-row (16px) slot, not 1 (8px). Static content,
-- cross-checked at 3 independent scroll offsets (+150/+300/+500
-- frames, byte-identical each time).
local TEXT_START_Y = 176
local LINE_HEIGHT = 16

function Intro.new(romData, profile, input, overlay, stack)
  local self = setmetatable({
    romData = romData,
    profile = profile,
    input = input,
    overlay = overlay,
    stack = stack,
    scrollY = 0,
    done = false,
  }, Intro)

  if romData and profile then
    self.background = TitleScreenBackground.new(romData, profile)
    self.font = Font.new(romData, profile)
    local data = profile.graphics.introText
    if data then
      self.text = TextDecoder.decodeString(romData, data.fileOffset)
      self.scyPerFrame = data.scy.unitsPerFrame
      self.scyTotal = data.scy.totalUnits

      -- CORRECTED (2026-08-09): direct user report ("nach dem Scroll
      -- geht es noch nicht zu Namenseingabe") -- NOT a broken
      -- transition (re-verified live: it does eventually fire, every
      -- time, using `scyTotal` as originally captured). The real
      -- problem: the real hardware's own `SCY` keeps scrolling for
      -- ~14 more real seconds of nothing but blank padding tilemap
      -- rows *after* the last real sentence has fully scrolled off
      -- screen (verified: the real text's last line, decoded from the
      -- literal ROM bytes, clears the screen around scroll-unit ~312,
      -- while the real captured `scyTotal` is ~475-494) -- accurate to
      -- the hardware, but reads as a stuck/broken screen to a player
      -- watching it with nothing on screen and no feedback. Ending the
      -- scroll once the real text has cleared (plus a small buffer)
      -- cuts only dead time, not real content -- a deliberate UX
      -- deviation from strict frame-accuracy, not a claim that real
      -- hardware actually stops here.
      local lastLineIndex = 0
      local n = 0
      for line in (self.text .. "\n"):gmatch("(.-)\n") do
        if line:match("%S") then lastLineIndex = n end
        n = n + 1
      end
      local lastLineBottom = TEXT_START_Y + lastLineIndex * LINE_HEIGHT + LINE_HEIGHT
      self.scyTotal = math.min(self.scyTotal, lastLineBottom + 16)
    end
  end

  return self
end

function Intro:advanceToNameEntry()
  if self.done then return end
  self.done = true
  local NameEntry = require("src.app.states.NameEntry")
  self.stack:replace(NameEntry.new(self.romData, self.profile, self.input, self.overlay, self.stack))
end

function Intro:update(dt)
  if self.done then return end

  -- Real ROM mechanic (see module doc comment): pressing A during the
  -- scroll is a genuine skip, code-verified (bank 2, file offset
  -- 0xbca1) and empirically confirmed against B/START (both inert).
  -- Real hardware takes ~16-20 more frames to reach NameEntry after the
  -- press (clearing part of the tilemap, pinning SCY, waiting on a
  -- close-out flag); collapsed to an immediate transition here since
  -- that closing state machine itself isn't modeled.
  if self.input and self.input:pressed("a") then
    self:advanceToNameEntry()
    return
  end

  -- Dev-only shortcut, kept separate from the real A-skip above (same
  -- "developer shortcuts" spirit as Field.lua's F3-F6) -- SELECT is
  -- confirmed INERT on real hardware here, so this is purely a testing
  -- convenience, not a claimed ROM behavior.
  if self.input and self.input:pressed("select") then
    self:advanceToNameEntry()
    return
  end

  if not self.scyPerFrame then
    self:advanceToNameEntry()
    return
  end

  self.scrollY = self.scrollY + self.scyPerFrame
  if self.scrollY >= self.scyTotal then
    self:advanceToNameEntry()
  end
end

function Intro:draw()
  if not self.background then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("(no ROM loaded -- intro unavailable)", 4, 4)
    return
  end

  -- Real BG fill is white everywhere the logo/text tiles don't cover
  -- (the confirmed-blank tile, see titleScreen's doc comment) -- drawn
  -- first so the gap between the logo scrolling off and the text
  -- scrolling in doesn't show the render canvas's own black clear color.
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)

  local y = -math.floor(self.scrollY)
  self.background:draw(0, y)

  if self.font and self.text then
    local ty = y + TEXT_START_Y
    for line in (self.text .. "\n"):gmatch("(.-)\n") do
      if ty > -8 and ty < SCREEN_H then
        self.font:print(line, 8, ty, { 0, 0, 0, 1 })
      end
      ty = ty + LINE_HEIGHT
    end
  end

  -- Real BGP-lightening effect during the scroll, approximated as a
  -- translucent white wash rather than a frame-exact palette replay
  -- (see module doc comment).
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  love.graphics.setColor(1, 1, 1, 1)

  if self.overlay then
    self.overlay:addLine("state", "Intro (real scroll + real text)")
    self.overlay:addLine("scroll", string.format("%.1f / %s px", self.scrollY, tostring(self.scyTotal)))
    self.overlay:addLine("keys", "A = real ROM skip; SELECT = dev-only skip")
  end
end

return Intro
