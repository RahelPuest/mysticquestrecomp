local Harness = require("tests.harness")
local SaveFormat = require("src.save.SaveFormat")

local function makeValidPayload()
  local payload = {}
  for i = 1, SaveFormat.PAYLOAD_LENGTH do
    payload[i] = 0
  end
  payload[1] = SaveFormat.MAGIC_BYTE
  payload[2] = 19 -- an arbitrary real-looking field, e.g. curLP low byte
  return payload
end

Harness.test("SaveFormat.MAGIC_BYTE: matches the real, doubly-verified ROM value", function()
  Harness.assertEqual(SaveFormat.MAGIC_BYTE, 0x6C)
end)

Harness.test("SaveFormat.encode: produces the real 512-byte SRAM layout", function()
  local sram = SaveFormat.encode(makeValidPayload())
  Harness.assertEqual(#sram, SaveFormat.SRAM_LENGTH)
end)

Harness.test("SaveFormat.encode: fails loudly on a wrong-length payload", function()
  local ok = pcall(SaveFormat.encode, { 1, 2, 3 })
  Harness.assertTrue(not ok, "expected encode to reject a payload that isn't exactly PAYLOAD_LENGTH bytes")
end)

Harness.test("SaveFormat.encode: primary and backup regions hold byte-for-byte identical encoded data (real duplicate-copy structure)", function()
  local sram = SaveFormat.encode(makeValidPayload())
  for i = 1, SaveFormat.PRIMARY_LENGTH do
    Harness.assertEqual(
      sram[SaveFormat.PRIMARY_OFFSET + i],
      sram[SaveFormat.BACKUP_OFFSET + i],
      "primary/backup mismatch at cell " .. i)
  end
end)

Harness.test("SaveFormat.encode/decode: round-trips a real payload exactly", function()
  local payload = makeValidPayload()
  payload[50] = 200
  payload[124] = SaveFormat.LAST_BYTE_PLACEHOLDER
  local sram = SaveFormat.encode(payload)
  local decoded, reason = SaveFormat.decode(sram)
  Harness.assertTrue(reason == nil, "unexpected decode failure: " .. tostring(reason))
  Harness.assertEqual(#decoded, SaveFormat.PAYLOAD_LENGTH)
  for i = 1, SaveFormat.PAYLOAD_LENGTH do
    Harness.assertEqual(decoded[i], payload[i], "payload mismatch at byte " .. i)
  end
end)

Harness.test("SaveFormat.decode: fails loudly on the wrong SRAM length", function()
  local decoded, reason = SaveFormat.decode({ 1, 2, 3 })
  Harness.assertTrue(decoded == nil)
  Harness.assertTrue(reason ~= nil)
end)

Harness.test("SaveFormat.decode: fails loudly when primary/backup copies disagree (real corruption check)", function()
  local sram = SaveFormat.encode(makeValidPayload())
  sram[SaveFormat.BACKUP_OFFSET + 1] = (sram[SaveFormat.BACKUP_OFFSET + 1] + 1) % 16
  local decoded, reason = SaveFormat.decode(sram)
  Harness.assertTrue(decoded == nil)
  Harness.assertTrue(reason:find("disagree") ~= nil, "expected a 'disagree' reason, got: " .. tostring(reason))
end)

Harness.test("SaveFormat.decode: fails loudly on a bad magic byte (no valid save)", function()
  local payload = makeValidPayload()
  payload[1] = 0x00 -- not the real magic byte
  local sram = SaveFormat.encode(payload)
  local decoded, reason = SaveFormat.decode(sram)
  Harness.assertTrue(decoded == nil)
  Harness.assertTrue(reason:find("magic") ~= nil, "expected a 'magic' reason, got: " .. tostring(reason))
end)

Harness.test("SaveFormat: real, independently-confirmed magic-byte decode (rom-map.md 'External validation')", function()
  -- Real external US save file's first two raw SRAM bytes decoded to
  -- 0x6C via low_nibble(cellA) | (low_nibble(cellB) << 4) -- the exact
  -- same formula this module ports, cross-checked here directly
  -- against that independently-sourced real data point.
  local NibblePacking = require("src.save.NibblePacking")
  Harness.assertEqual(NibblePacking.unpackByte(0xC, 0x6), 0x6C)
end)
