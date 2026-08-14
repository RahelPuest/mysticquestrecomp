# Checkpoint recipes

This directory holds nothing but generated `.state`/`.png` artifacts
(gitignored, see `.gitignore` here) and this README. The actual
checkpoint *recipes* live in `../checkpoints.py`, one function each:

| Name | Real moment |
|---|---|
| `courtyard_enemy_engaged` | Fresh boot, walked up into contact with the real gate creature. Not yet attacked. |
| `courtyard_boss_defeated` | The creature's HP has just hit the real `$FFFF` dead sentinel. |
| `post_black_wipe` | The real full-screen black wipe has resolved; the first real story textbox is showing, fully typed. |
| `willy_room_free` | Every story/Willy-exchange box dismissed; free-roaming in willyRoom. |
| `door_ready` | Walked up to the real door threshold; the scroll hasn't started yet. |
| `second_room_free` | The real north-door scroll has completed; free-roaming in secondRoom. |

Regenerate any of them:

```sh
cd tools/rom
python3 checkpoints.py second_room_free --save
# -> checkpoints/second_room_free.state + a same-named .png sanity screenshot
```

Chain your own investigation off a later one without replaying earlier
steps in the same process:

```python
import checkpoints as cp
s = cp.second_room_free()   # runs the whole chain once, in-process
# ... your own watcher/calltrace/OAM work against `s` here ...
```

## Why no `.state` files are checked in

An mgba raw state is a full emulated-console memory snapshot -- it
embeds real copyrighted ROM/game data (graphics, text, code) in
directly-extractable form, exactly the kind of content this project's
own "never check in a copyrighted ROM" rule exists to keep out of
version control. The *recipe* (this Python code) is what's durable and
checked in; the binary snapshots it produces are local, regenerable
build output, same spirit as a Makefile target vs. its compiled
artifact.

## A real gotcha this session hit twice, worth knowing before adding a new recipe

`mgba_env.load_core`'s `core.autoload_save()` auto-loads a `.sav` file
sitting next to the ROM, if one exists -- and mgba itself auto-writes
one back after any session that reaches real SRAM-touching gameplay
(which every checkpoint here does). A stray `.sav` silently makes a
"fresh boot" not fresh anymore (the game skips into whatever that
save's own progress was). `checkpoints.py`'s own `courtyard_
enemy_engaged` already clears it before starting a truly fresh chain
(see `_clear_stray_sav`'s own doc comment) -- keep that call if you add
an even-earlier entry point.
