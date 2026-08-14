"""The proven button sequence to drive a fresh boot all the way into the
first real, playable game room (title -> "Neues Spiel" -> intro text ->
name entry -> first room: a barred-gate courtyard with a real enemy
creature, HUD reading `LP 19 MP 6 G 50`).

CORRECTED (2026-08-09): the previous version of this sequence added
extra `START` presses after 19+4 `A` presses, intended for "hero name
entry" / "second name entry" confirmation. Direct testing found those
extra presses actually fire *after* the game has already reached the
real room -- i.e. gameplay begins, and takes input, well before this
function's old step count assumed. Concretely: at the old sequence's
frame count, the on-screen "player" sprite jumped 72px in a single frame
under held input, instead of the independently-VERIFIED 1px/frame walk
speed (src/entities/Player.lua) -- a decisive tell that those extra
`START` presses were landing during real gameplay, most likely opening
the in-game pause menu (see src/app/states/Menu.lua), not confirming a
name-entry field. That's what an earlier pass mistakenly captured and
documented as "the room" (see docs/progress.md's correction entry).

This version is simpler and was verified against the resulting room's
actual content matching every already-independently-known fact about
it (real environment-tileset wall/gate art, a real 4x2-tile enemy, a
real 2-tile player, the expected HUD stats) -- not just "doesn't crash."
Name entry appears to auto-resolve to the default name during this
simpler sequence's `A` presses (consistent with this project's existing
"AAAA" findings elsewhere), rather than needing a dedicated `START` step.

CORRECTED AGAIN (2026-08-11, "wir brauchen wesentlich besseres
tooling..."): the "auto-resolves" claim above turned out to be
environment-dependent, not a real property of the ROM's own flow -- it
only "worked" because a stale mgba `.sav` file (auto-persisted SRAM
from an EARLIER investigation session, sitting next to the ROM and
auto-loaded via `mgba_env.load_core`'s own `core.autoload_save()`) let
the game skip straight past name entry using leftover save data. A
genuinely clean run (no `.sav` present) gets stuck on the real hero
name-entry keyboard forever under blind `A`-mashing -- confirmed this
project's own `src/app/states/NameEntry.lua` already documents exactly
why: "START confirms and advances ONLY once at least one character has
been entered" -- so `A` alone (selecting letters, never actually
submitting) can mash forever without ever reaching the room, and the
SECOND (heroine, "Frau"-labeled) screen starts with a genuinely empty
name each time, needing its own letter selection before `START` does
anything either. Real, verified fix: an explicit `START` after the hero
letters, one more letter selection + `START` for the heroine screen.
Re-verified end to end with NO `.sav` file present (the only reliable
way to test a "fresh boot" claim) -- lands in the real room with the
enemy visible, `LP 19 MP 6 G 50` HUD, matching every fact the previous
correction already established.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
import play_driver as pd  # noqa: E402


def reach_first_room(session=None):
    """Returns a Session sitting in the first room, right after the
    HUD/room finish drawing (frame 2514 at these press timings, real
    hero name "AAAA", real heroine name "A")."""
    s = session or pd.Session()
    s.run(600)  # boot -> title screen menu ready
    s.press(s.core.KEY_A, hold=6, then_wait=10)  # confirm "Neues Spiel"
    s.run(300)  # title fade -> intro narration starts
    for _ in range(30):  # skip through intro dialogue, selecting hero name letters (lands on "AAAA")
        s.press(s.core.KEY_A, hold=6, then_wait=40)
    s.press(s.core.KEY_START, hold=6, then_wait=60)  # confirm hero name -> heroine ("Frau") screen
    s.press(s.core.KEY_A, hold=6, then_wait=20)  # heroine screen starts EMPTY -- needs its own letter first
    s.press(s.core.KEY_START, hold=6, then_wait=120)  # confirm heroine name -> real room
    return s


if __name__ == "__main__":
    s = reach_first_room()
    s.screenshot("/tmp/reach_room.png")
    print("frame", s.frame, "-- first room, saved /tmp/reach_room.png")
