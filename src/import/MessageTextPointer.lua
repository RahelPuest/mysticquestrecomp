-- Resolves a script-opcode `0xFE` (MESSAGE_HANDLER_ADDRESS) messageID
-- into its decoded text -- the formula this project independently
-- VERIFIED (see rom_profiles.lua's `messageTextPointer` doc comment and
-- docs/reverse-engineering/text.md's "SOLVED: the message-settings-
-- table text pointer") but had only ever exercised inline, once, in a
-- single test (`tests/import/text_decoder_test.lua`) -- pulled out
-- into its own small, reusable module so callers (the
-- `ScriptInterpreter`'s `ctx.onMessage`, first wired as part of proving
-- the interpreter->rendering pipeline for real, see events.md) don't
-- need to re-derive the record-stride arithmetic by hand.
--
-- HONEST SCOPE: the formula itself is VERIFIED (messageID 13 decodes to
-- the "gefunden" text, independently cross-checked against the record
-- field bytes and the decoded string). Most other messageIDs remain
-- blocked by `TextDecoder`'s incomplete digraph coverage, not a formula
-- problem -- this module surfaces that honestly (`nil, err` from
-- `TextDecoder.decodeString` itself, no silent fallback) rather than
-- hiding it.

local TextDecoder = require("src.import.TextDecoder")

local MessageTextPointer = {}

--- `romData`: the full ROM byte string. `ptr`: `profile.messageTextPointer`
-- (needs `.recordBaseFileOffset`, `.recordStride`, `.recordFieldOffset`,
-- `.fileOffsetBase`). `messageId`: the real 0-based ID a `0xFE` opcode's
-- own operand byte carries. Returns the real decoded text string.
function MessageTextPointer.resolveText(romData, ptr, messageId)
  assert(type(romData) == "string", "MessageTextPointer.resolveText expects a byte string")
  assert(type(ptr) == "table" and ptr.recordBaseFileOffset and ptr.recordStride
    and ptr.recordFieldOffset and ptr.fileOffsetBase,
    "MessageTextPointer.resolveText expects a real messageTextPointer profile")
  assert(type(messageId) == "number" and messageId >= 0,
    "MessageTextPointer.resolveText expects a real, non-negative messageId")

  local recordOffset = ptr.recordBaseFileOffset + messageId * ptr.recordStride
  local fieldOffset = recordOffset + ptr.recordFieldOffset
  local field = romData:byte(fieldOffset + 1) + romData:byte(fieldOffset + 2) * 256
  local textOffset = ptr.fileOffsetBase + field
  return TextDecoder.decodeString(romData, textOffset)
end

return MessageTextPointer
