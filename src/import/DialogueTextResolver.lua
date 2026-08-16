-- Resolves real, hand-transcribed dialogue lines back into REAL,
-- LIVE-DECODED text read from actual ROM bytes at runtime -- the
-- concrete first step of a direct user request ("was fehlt um eine
-- komplett autark interpretierte App-Variante zu entwickeln, die auf
-- keinerlei precoded raeume/events setzt"): several real NPC dialogue
-- lines (`rom_profiles.lua`'s `secondRoom.scene.characterA/
-- characterB.dialogue`) were originally found via live capture/static
-- analysis and then HAND-TRANSCRIBED as plain string literals -- real,
-- byte-exact-confirmed text, but not actually decoded from the ROM at
-- runtime the way `VictorySequence.lua`'s own story-page/Willy-exchange
-- lines already are (`TextDecoder.decodeString(romData, OFFSET)`,
-- established 2026-08-12). This module generalizes that SAME pattern
-- for lines that need more than one plain `decodeString` call.
--
-- WHY a new module instead of more inline `TextDecoder.decodeString`
-- calls (VictorySequence.lua's own established convention for the
-- simple case): 2 of the 4 real lines this project has needed so far
-- hit an ALREADY-DOCUMENTED, per-occurrence digraph ambiguity (`0x5B`,
-- `0x82` -- see `TextDecoder.lua`'s own doc comment: both are real
-- bytes whose SHARED default mapping is correct almost everywhere but
-- wrong in a few specific, already-cross-checked real occurrences --
-- "raus!" needs `0x5B` read as "us" here, not the shared table's "a";
-- "meinem" needs `0x82` read as "me"). A single `decodeString` call
-- can't express "decode normally, except this ONE already-known real
-- byte, right here" -- this module's `resolve()` takes an explicit,
-- itemized segment list (real byte ranges to decode + real literal
-- overrides for specific already-documented exceptions) so that
-- per-occurrence exception is spelled out and testable, not silently
-- baked into a hand-typed string with no ROM citation at all.
--
-- Pure Lua, no love.* calls, same convention as MessageTextPointer.lua.

local TextDecoder = require("src.import.TextDecoder")

local DialogueTextResolver = {}

--- Decodes every byte in `romData[fromOffset, toOffsetExclusive)` via
-- `TextDecoder.decodeByte` (NOT `decodeString` -- this needs an exact,
-- bounded range, not "decode until something fails"). Fails loudly if
-- any byte in the range doesn't decode -- a real signal the caller's
-- own recorded offsets are stale (ROM changed, or a transcription
-- mistake), never a silently-wrong partial string.
function DialogueTextResolver.decodeRange(romData, fromOffset, toOffsetExclusive)
  assert(type(romData) == "string", "DialogueTextResolver.decodeRange expects a byte string")
  assert(type(fromOffset) == "number" and type(toOffsetExclusive) == "number"
    and toOffsetExclusive >= fromOffset,
    "DialogueTextResolver.decodeRange expects a real, non-empty [fromOffset, toOffsetExclusive) range")
  local chars = {}
  for i = fromOffset, toOffsetExclusive - 1 do
    local b = romData:byte(i + 1)
    local ch = TextDecoder.decodeByte(b)
    assert(ch ~= nil, string.format(
      "DialogueTextResolver.decodeRange: real byte %#04x at file offset %#x does not decode -- " ..
      "refusing to guess (the recorded [fromOffset, toOffsetExclusive) range may be stale)",
      b, i))
    chars[#chars + 1] = ch
  end
  return table.concat(chars)
end

--- Resolves `segments` (an ordered array of `{fromOffset=, toOffsetExclusive=}`
-- real-ROM-range pieces and/or `{literal=}` fixed-string pieces -- the
-- latter for a documented per-occurrence digraph override, or a real
-- runtime substitution like the player's own hero name) into one
-- concatenated real string.
function DialogueTextResolver.resolve(romData, segments)
  assert(type(segments) == "table" and #segments > 0,
    "DialogueTextResolver.resolve expects a real, non-empty segment list")
  local parts = {}
  for i, seg in ipairs(segments) do
    if seg.literal ~= nil then
      assert(type(seg.literal) == "string", string.format(
        "DialogueTextResolver.resolve: segment %d's literal must be a string", i))
      parts[#parts + 1] = seg.literal
    else
      assert(type(seg.fromOffset) == "number" and type(seg.toOffsetExclusive) == "number", string.format(
        "DialogueTextResolver.resolve: segment %d needs either `literal` or `fromOffset`+`toOffsetExclusive`", i))
      parts[#parts + 1] = DialogueTextResolver.decodeRange(romData, seg.fromOffset, seg.toOffsetExclusive)
    end
  end
  return table.concat(parts)
end

--- Convenience for a scene character's `dialogue` array: resolves
-- every entry of `dialogueSegments` (an array of segment-lists, one per
-- dialogue page -- see `rom_profiles.lua`'s own `dialogueSegments` doc
-- comment) into a plain array of real decoded strings, the exact shape
-- `NpcProximity.match` already expects from a character's `.dialogue`
-- field.
function DialogueTextResolver.resolvePages(romData, dialogueSegments)
  assert(type(dialogueSegments) == "table",
    "DialogueTextResolver.resolvePages expects a real dialogueSegments array")
  local pages = {}
  for i, segments in ipairs(dialogueSegments) do
    pages[i] = DialogueTextResolver.resolve(romData, segments)
  end
  return pages
end

return DialogueTextResolver
