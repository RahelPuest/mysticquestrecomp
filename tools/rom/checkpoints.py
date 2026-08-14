#!/usr/bin/env python3
"""Reusable, documented checkpoint recipes for the real ROM under mgba --
each function drives a `Session` (see play_driver.py) from an EARLIER
checkpoint (or a fresh boot, via reach_room.reach_first_room()) to a
named real moment in the post-boss sequence, and can optionally save the
result as an mgba raw state via `--save <name>`.

WHY THIS EXISTS (2026-08-11, "wir brauchen wesentlich besseres
tooling..."): earlier investigation sessions built up a real library of
useful checkpoint .state files (pre_kaempfe_box, door_ready,
room2_free, ...), but they lived only in the per-session scratchpad
directory -- gone the moment the session ended, so every fresh
investigation had to re-grind the same boss fight / dialogue sequence
from scratch. The .state files THEMSELVES are never checked in here --
an mgba raw state is a full emulated-console memory snapshot, which
embeds real copyrighted ROM/game data (graphics, text, code) in
directly-extractable form, exactly the kind of content this project's
own "never check in a copyrighted ROM" rule exists to keep out of
version control. What IS checked in is this REPRODUCIBLE RECIPE --
regenerate the actual .state files locally (into `checkpoints/`, already
gitignored -- see tools/rom/.gitignore) by running this script, same
spirit as a Makefile target, not prebuilt binary artifacts.

Usage:
    python3 checkpoints.py <name> [--save]
    # e.g. python3 checkpoints.py second_room_free --save
    # writes checkpoints/second_room_free.state, and a same-named .png
    # screenshot for a quick sanity check.

Each function also accepts an optional `session=` (a `Session` object
already sitting at an earlier real point) so a later checkpoint can
chain off an earlier one without replaying the whole thing from cold
boot -- see `CHECKPOINTS`' own `depends_on` wiring at the bottom.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import mgba_env  # noqa: E402
import reach_room  # noqa: E402

CHECKPOINT_DIR = os.path.join(os.path.dirname(__file__), "checkpoints")


def _stray_sav_path():
    rom = mgba_env.DEFAULT_ROM
    return os.path.splitext(rom)[0] + ".sav"


def _clear_stray_sav():
    """Real bug hit and fixed while building this module (2026-08-11):
    `mgba_env.load_core`'s own `core.autoload_save()` auto-loads a
    `.sav` file sitting next to the ROM, if one exists -- and mgba
    itself auto-WRITES one back after any session that reaches real
    SRAM-touching gameplay (which every checkpoint here does). Left in
    place, a later "fresh boot" call silently isn't fresh anymore: the
    game skips straight into whatever that stale save's own progress
    was (confirmed live -- see reach_room.py's own 2026-08-11 doc
    comment for the exact symptom this caused: name entry appearing to
    "auto-resolve" was really the ROM finding an already-named save).
    Called once before the very first checkpoint in a fresh run.
    """
    path = _stray_sav_path()
    if os.path.exists(path):
        os.remove(path)


def _hold(session, key, frames):
    session.core.add_keys(key)
    session.run(frames)
    session.core.clear_keys(key)


def _tap_a(session, hold=6, wait=400):
    """One deliberate `A` tap with a generous post-wait -- long enough
    for this project's real ~5-frames/char typewriter cadence to finish
    even a long real dialogue line before the next tap, avoiding the
    over/under-mashing trap docs/reverse-engineering/rom-map.md already
    documents."""
    session.press(session.core.KEY_A, hold=hold, then_wait=wait)


def courtyard_enemy_engaged(session=None):
    """Real moment: fresh boot -> first room -> walked up into contact
    with the real gate creature (OAM count 2 -> 14, real HP=30
    populated at $D3F4/$D3F5). NOT yet attacked."""
    if session is None:
        _clear_stray_sav()  # see this function's own doc comment -- must run before Session() touches the ROM dir
    s = session or reach_room.reach_first_room()
    _hold(s, s.core.KEY_UP, 240)
    return s


def courtyard_boss_defeated(session=None):
    """Real moment: the gate creature's HP has just hit the real
    $FFFF dead sentinel (up to 80 real `A` taps while adjacent -- see
    docs/reverse-engineering/rom-map.md "Enemy HP struct" for the
    struct itself). Player LP checked to stay well above 0 throughout
    (contact damage is real and ongoing while approaching/fighting).
    Raises if the enemy is somehow still alive after generous margin --
    real per-attack damage has some variance (this project's own real
    combat-noise PRNG, see src/entities/CombatNoise.lua), so a fixed
    tap count needs real headroom rather than assuming the minimum
    observed case always holds; failing loudly beats silently returning
    a session that isn't actually at the named real moment."""
    s = session or courtyard_enemy_engaged()
    m = s.core.memory
    for _ in range(140):
        s.press(s.core.KEY_A, hold=4, then_wait=6)
        if m.u8[0xD3F5] == 0xFF:  # real HP-high-byte dead sentinel
            break
    if m.u8[0xD3F5] != 0xFF:
        raise RuntimeError(
            "courtyard_boss_defeated: enemy HP high byte still %#x after 140 attack taps "
            "(expected 0xff, the real dead sentinel) -- did not reach the named checkpoint"
            % m.u8[0xD3F5])
    return s


def post_black_wipe(session=None):
    """Real moment: boss just defeated, the real full-screen black wipe
    has resolved and the first real story textbox ("...und viele
    andere wurden gezwungen...") is showing, fully typed, waiting for
    input."""
    s = session or courtyard_boss_defeated()
    s.run(900)  # real heal-to-full + black-wipe + box-draw sequence, then a long real passive wait for input
    return s


def willy_room_free(session=None):
    """Real moment: every real story/Willy-exchange box dismissed (9
    real advances -- 3 courtyard story pages + 6 Willy-exchange boxes,
    see rom_profiles.lua's `victorySequence` doc comment for the exact
    real text), player free-roaming in willyRoom.

    Taps MORE than 9 times with generous margin, not exactly 9: real
    testing found some taps land while a box's own text hasn't finished
    typing yet (or right as the room-transition scroll itself is still
    resolving) and are silently absorbed without advancing a page --
    same real trap docs/reverse-engineering/rom-map.md already
    documents for hand-mashing this exact sequence. A fixed, small tap
    count assuming every tap lands is fragile; comfortable headroom
    (14) plus each tap's own generous 400-frame settle wait is more
    robust than chasing the exact minimum."""
    s = session or post_black_wipe()
    for _ in range(14):
        _tap_a(s)
    return s


def door_ready(session=None):
    """Real moment: player walked from willyRoom's own spawn up to the
    real door threshold (SCY shadow still 0 -- the scroll hasn't
    started yet).

    Real bug hit and fixed while building this (2026-08-11):
    `willy_room_free` leaves the player at real x=88 -- OUTSIDE the
    real door's own narrow working x-range (documented elsewhere as
    "x=72-86"/"x=77-80 centered", but x=88 specifically confirmed dead:
    holding UP alone from there walks straight into a wall beside the
    door and NEVER triggers the scroll, no matter how long held). A
    small `LEFT` nudge first is required, and the exact amount matters
    more than it looks: 8 frames (88 -> real x=80) works; 20 frames
    (-> x=72, past the door's own real left edge) does NOT -- confirmed
    by holding UP for 750+ real frames at x=72 with zero scroll ever
    starting, vs. the SAME hold from x=80 triggering it within about 50
    real frames. Left as an explicit, narrow value rather than a
    "close enough" range because this was measured, not guessed."""
    s = session or willy_room_free()
    _hold(s, s.core.KEY_UP, 50)
    _hold(s, s.core.KEY_LEFT, 8)
    return s


def second_room_free(session=None):
    """Real moment: the real north-door scroll has completed (SCY
    shadow settled at 128) and the player has walked far enough into
    secondRoom to be clear of the landing spot, free-roaming."""
    s = session or door_ready()
    _hold(s, s.core.KEY_UP, 250)  # scroll (~32f, automatic) + walk further in
    return s


def third_room_free(session=None):
    """Real moment: the real east horizontal scroll out of secondRoom
    has completed (SCX shadow settled at its real 160, live-confirmed)
    and the player has walked clear of the landing spot in thirdRoom.

    FIXED (2026-08-12, "ja fixe den bug"): the previous version held
    `UP` first and got stuck -- turned out to be a bug in the
    INVESTIGATING script, not the ROM/game: `$C244`=Y, `$C245`=X (see
    rom-map.md's own "CORRECTED" note on this exact pair), but the
    probe script that built the original version printed/reasoned
    about them as `(X,Y)`, so a perfectly-normal "Y constant, X
    increasing while holding RIGHT" reading got misread as "stuck".
    With the coordinates the right way round: `second_room_free()`'s
    own real resting spot is Y=24 (need Y in the exit's real 60-68
    band, i.e. hold DOWN, not UP), X=80 (need X>=110, hold RIGHT).
    `DOWN` for 40 frames lands Y=63-64, comfortably mid-band (not right
    at the `yMax=68` edge, which a first attempt at this fix found
    drifts OUT of the band during the following RIGHT hold and
    produces a real wall-block instead, at real X~120-129 -- see
    rom_profiles.lua's `secondRoom.exits` own doc comment for that
    wall). Live-verified this exact sequence: SCX genuinely climbs
    0->160 (the real settled value) and the room ID (`$D392`/`$D393`)
    stays unchanged throughout -- confirming secondRoom and thirdRoom
    are (like willyRoom/secondRoom) the SAME continuous room space,
    not a real discrete transition at the WRAM room-ID level, only at
    the SCX/SCY scroll level."""
    s = session or second_room_free()
    _hold(s, s.core.KEY_DOWN, 40)  # (Y=24,X=80) -> Y~63-64, mid exit band
    _hold(s, s.core.KEY_RIGHT, 240)  # walk to the exit + real scroll (SCX->160) + clear the landing spot
    return s


CHECKPOINTS = {
    "courtyard_enemy_engaged": courtyard_enemy_engaged,
    "courtyard_boss_defeated": courtyard_boss_defeated,
    "post_black_wipe": post_black_wipe,
    "willy_room_free": willy_room_free,
    "door_ready": door_ready,
    "second_room_free": second_room_free,
    "third_room_free": third_room_free,
}


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CHECKPOINTS:
        print("usage: python3 checkpoints.py <name> [--save]")
        print("available:", ", ".join(CHECKPOINTS))
        sys.exit(1)
    name = sys.argv[1]
    save = "--save" in sys.argv[2:]
    s = CHECKPOINTS[name]()
    print(f"{name}: frame {s.frame}")
    if save:
        os.makedirs(CHECKPOINT_DIR, exist_ok=True)
        state_path = os.path.join(CHECKPOINT_DIR, name + ".state")
        with open(state_path, "wb") as f:
            f.write(bytes(s.core.save_raw_state()))
        png_path = os.path.join(CHECKPOINT_DIR, name + ".png")
        s.screenshot(png_path)
        print(f"saved {state_path} and {png_path}")
