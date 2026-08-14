# Save/Load — status summary

Required by the project's master brief as a maintained, topic-focused
doc. Full evidence trail in
[rom-map.md "Save RAM"](rom-map.md) — not duplicated here.

## Real ROM format — VERIFIED, doubly confirmed

MBC2's built-in SRAM (`$A000-$A1FF`, low nibble significant — the high
nibble of every SRAM byte is unused hardware-side): every logical byte
costs 2 SRAM cells (`WriteNibblePair`/`ReadNibblePair`, low nibble
first). A `0x6C` magic/validity byte is the first decoded byte. The
save is duplicated byte-for-byte (`$A000-$A0F7` primary, `$A100-$A1F7`
backup — a raw copy loop, not a second encode pass) for corruption
resilience, not two save slots. Confirmed twice: once by this project's
own live dynamic trace, once independently by decoding 12 real external
US-cartridge save files with the same formula.

**Still unknown**: the real trigger condition (never tied to a specific
confirmed player action), and the field-by-field meaning of the ~122
payload bytes beyond the magic byte (presumably stats/inventory/
position, per the live WRAM struct — never matched byte-for-byte). A
real, live-captured US save's own final payload byte causes a hard CPU
lockup when fed back into this EU ROM (`0xC6`, a fixed build/version
tag, not a per-save checksum — 93/256 possible values at that position
are unsafe); even avoiding the lockup, "Continue" doesn't reach a
normal interactive state within the tested window — a real, open
sub-problem this project's own native save/load below does not need to
solve, since it never round-trips through the original ROM's loader.

## This project's own save/load — IMPLEMENTED (2026-08-10)

Reuses the real, VERIFIED container format (nibble-packing, magic byte,
duplicate-copy structure) but defines its OWN field layout for the 122
undecoded payload bytes — clearly NOT a claimed reproduction of the
original ROM's own unknown layout (a save file this project writes is
not expected to be byte-compatible with a real cartridge's save):

- `src/save/NibblePacking.lua` — the real pack/unpack primitives, pure
  Lua, unit tested against every possible byte value (0-255).
- `src/save/SaveFormat.lua` — the real container (magic byte, 124-byte
  payload budget, primary+backup duplicate copy over the full 512-byte
  SRAM layout); `decode()` additionally verifies the two copies agree
  (a real corruption check beyond the original ROM's own simpler
  magic-byte-only validation).
- `src/save/SaveData.lua` — this project's own field layout: real Stats
  fields (curLP/maxLP/curMP/maxMP/level/gold/defense) in the same real
  field ORDER as the live WRAM struct (`$D7B2`), plus the real player-
  entered hero name (16-byte ASCII field, this project's own encoding,
  not the ROM's dialogue-byte charset).
- `src/save/SaveFile.lua` — thin `love.filesystem` glue (deliberately
  NOT unit tested, per this project's testing-strategy split — verified
  instead with a real file-I/O round-trip, including a deliberately
  corrupted file to confirm the corruption check actually fires).

**Wired into gameplay**: `Field.lua`'s F7 dev key saves (WHEN a save
happens is this project's own choice — the real trigger is unknown, see
above); the title screen's real "Weiterspielen" option loads a save and
jumps straight into `Field` with the restored Stats + hero name,
replacing the previous "not implemented" status message.

Full test suite covers `NibblePacking`/`SaveFormat`/`SaveData` fully
(round-trips, every real failure mode: wrong length, corrupt copies,
bad magic byte, over-length name) — 20 new tests, all passing.
