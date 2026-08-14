# Audio — status summary

Required by the project's master brief as a maintained, topic-focused
doc. Full evidence trail in
[rom-map.md "Audio"](rom-map.md) — not duplicated here.

## Driver location — VERIFIED

Watched all sound-hardware-register writes through boot + title-screen
music: 100% (830/830) came from ROM bank 15, confirming a static
bank-write-heuristic scan's hypothesis and ruling out the graphics
banks' coincidental hits.

## Note table / instrument / sequence format — UNKNOWN

This is genuinely the least-investigated system in the project — the
driver's *location* is confirmed, but nothing about *how* it encodes
notes, instruments/waveforms, or music sequences has been determined.
No `src/audio/` implementation exists.

## Priority

Explicitly the lowest-priority open item per this project's own
recommendation (least tractable of the remaining unknowns, and the
master brief itself says audio "can initially be a later milestone" and
should not block core gameplay work). Not attempted this pass.
