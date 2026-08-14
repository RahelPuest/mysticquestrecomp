# Dynamic Analysis Tooling (mGBA + Python)

Static ROM analysis (the `tools/rom/scan_*.py` family) has limits: it found
and confirmed the graphics regions and the map/room pointer table, but hit
a wall on text encoding (see [text.md](text.md)) that pure byte-pattern
guessing couldn't get through. This document covers the dynamic-analysis
setup that broke that wall: a real, scriptable Game Boy emulator
(mGBA, via its official Python bindings) built from source, used to run
the actual ROM and inspect live CPU/memory state.

**Not part of the shipped project.** Lives in the sibling
`tools-external/` workspace folder (alongside `gen1recomp-reference/`),
outside this repo, `.gitignore`d by convention (large build artifacts, a
Python venv, and third-party source) — this document exists so the setup
is reproducible, not so the build output gets committed.

## Why mGBA specifically

The master brief asked for "a GB emulator with debugger/Lua scripting."
mGBA (`mgba.io`) supports Game Boy/Color/Advance, has a CLI debugger and
GDB stub, embedded Lua scripting, *and* official Python bindings
(`src/platform/python` in its source tree) that wrap the same core used by
its GUI — the Python bindings turned out to be the most productive path
here since they give direct, synchronous, scriptable access to
memory/registers/frame stepping without needing to drive a GUI window or
write Lua against a REPL. BGB (Windows-only, no native Lua) and SameBoy
(interactive debugger console, not built for headless scripting) were
considered and set aside for this reason.

## Build recipe (macOS, Homebrew, Apple Silicon)

```sh
brew install cmake swig pkg-config ffmpeg  # ffmpeg was likely already
                                            # present; pkg-config was NOT
                                            # and its absence caused a
                                            # silent, hard-to-diagnose
                                            # feature-detection failure
                                            # (see gotcha #2 below)

cd tools-external
git clone --depth 1 --branch 0.10.5 https://github.com/mgba-emu/mgba.git
python3 -m venv mgba-venv
source mgba-venv/bin/activate
pip install cffi setuptools cached_property

cd mgba && mkdir build && cd build
cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DBUILD_PYTHON=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF \
      -DUSE_SQLITE3=OFF -DBUILD_LTO=OFF -DCMAKE_BUILD_TYPE=Release \
      -DPYTHON_EXECUTABLE=$(pwd)/../../mgba-venv/bin/python3 ..
make -j$(sysctl -n hw.ncpu)
```

Verify: `python3 -c "import sys; sys.path.insert(0,
'tools-external/mgba/build/python/lib.macosx-14.0-arm64-cpython-314');
import mgba.core"` should succeed silently. `tools/rom/mgba_env.py` (in
this repo) wraps this sys.path setup for actual analysis scripts — see its
docstring; adjust the hardcoded `lib.macosx-...` directory name if your
Python/platform triple differs.

## Two build gotchas that cost real time (recorded so they aren't hit twice)

1. **A CMake version mismatch, not a bug in mgba.** Homebrew's `cmake`
   (4.x) refuses mgba's `cmake_minimum_required(VERSION 2.8...)` outright
   ("Compatibility with CMake < 3.5 has been removed"). Fixed by
   `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (cmake's own suggested
   workaround), not by patching mgba's `CMakeLists.txt`.
2. **The real cause of a `symbol not found in flat namespace
   '_EReaderAnchorListAppend'` import error, which took several wrong
   turns to isolate.** The Python bindings failed to `dlopen` with that
   error. It looked like an optimizer dead-code-elimination problem
   (trying `-DBUILD_LTO=OFF`, then `CMAKE_BUILD_TYPE=Debug`, neither
   fixed it alone) but the actual root cause was structural: the function
   in question lives inside `src/gba/cart/ereader.c` entirely inside an
   `#ifdef USE_FFMPEG` block (an obscure GBA-only "e-Reader" peripheral
   feature that happens to need FFmpeg for image processing) — passing
   `-DUSE_FFMPEG=OFF` (done initially to avoid an extra dependency) simply
   compiled that function out, while the Python bindings' cffi-generated
   stub still declared and eagerly referenced it (macOS's
   `-undefined dynamic_lookup` linking resolves such references at
   `dlopen` time, so a *never-called* missing function still crashes the
   import). Fixed by enabling `-DUSE_FFMPEG=ON` — which itself required
   installing `pkg-config` (Homebrew's ffmpeg ships proper `.pc` files,
   but CMake's `find_package`/`pkg_check_modules` needs the `pkg-config`
   *binary* on `PATH` to read them at all, and it was simply absent,
   failing silently with only an easy-to-miss one-line configure warning
   "Requested module libavcodec missing for feature USE_FFMPEG"). Lesson:
   an unrelated-looking missing CLI tool (`pkg-config`) masqueraded as a
   linker/optimizer bug several layers downstream — check `cmake`'s own
   configure-time warnings for silently-disabled features before
   suspecting the compiler.
3. Two more mundane missing-Python-package errors along the way
   (`cffi`, then `setuptools`, then `cached_property` at *import* time,
   not build time) — all fixed with `pip install` inside the dedicated
   venv. Using a venv (rather than `--break-system-packages` against
   Homebrew's externally-managed Python) avoided touching the system
   Python install.

## What this unlocked: cracking the text encoding

Full narrative in [text.md](text.md). Summary of the technique, since it's
reusable for future dynamic-analysis questions (combat formulas, event
triggers, save RAM):

1. Load the ROM (`mgba.core.load_path`), attach a video buffer, run
   frames (`core.run_frame()`) until a known screen appears (found by
   binary-searching frame numbers while checking one VRAM tilemap byte
   for a value change — 72 frames to the title screen's menu text).
2. Read VRAM directly (`core.memory.vram.u8[...]`) to get the *displayed*
   tile indices for known on-screen text ("Neues Spiel" / "Weiterspielen"
   from the German title screen) and solve for a constant relationship
   against the already-VERIFIED font ROM tile order: found VRAM tile
   index = font-order index + 48 (glyphs get DMA'd into VRAM tile slot
   0x30, not slot 0) by testing all ten letters of two words and finding
   one consistent offset.
3. That still didn't explain ROM-resident dialogue bytes (a wide shift
   search over the ROM found nothing). Switched to true dynamic tracing:
   single-instruction-stepped (`core.step()`, reading `core.cpu.pc/a/hl/
   .../sp` each step — the SM83Core wrapper) through the exact frame the
   text first got drawn, logging every `PUSH AF`/`POP AF`/`CALL`/`RET`
   to reconstruct the call chain cheaply (full-instruction tracing is
   ~1000x more data than needed; opcode-filtered tracing narrows fast).
   Found the value arriving via `POP AF` immediately followed by
   `XOR 0x80`, i.e. the ROM's real stored byte has bit 7 set on top of
   the display-index-plus-48 value. That gives a single closed-form
   formula (`romByte = 0xB0 + fontGlyphIndex`), confirmed instantly by
   re-running the existing static shift-search tool with that exact
   offset and finding real German words (`"Drache"`, `"Kraft"`, `"Der
   Mana Baum"`, ...) across the whole ROM.

The pattern worth repeating: **use the emulator to find one confirmed
constant (an address, an offset, a formula) from a screen you can already
see and identify, then hand that constant back to fast, ROM-file-only
static tools** (`tools/rom/scan_text.py`, `dump_strings.py`) rather than
doing the full analysis inside the slow instruction-stepping loop. Single
`core.step()` calls in Python are fast per-call (sub-millisecond) but a
full second of gameplay is still tens of thousands of them — narrow the
window with `run_frame()` first, then step only the frame that matters.

**Measured `core.step()` throughput** (this round, Apple Silicon): ~800k
instructions/second sustained (4.5M steps in 5.7s while tracing across
~450 frames with a live watchpoint armed). Faster than the "narrow the
window first" caution above implied — stepping through several hundred
frames end-to-end, not just one, is entirely practical. Still narrow with
`run_frame()` when you can (it's C-loop speed, no Python per-instruction
overhead at all), but don't over-invest in bisection tricks to avoid
stepping a few hundred frames; just step them.

## Native watchpoints (`tools/rom/watcher.py`) — reusable, built this round

The previous round's text-encoding trace (above) found its target frame by
*manually diffing memory snapshots* while single-stepping — workable, but
it means writing custom diff logic per investigation and manually spotting
which of many byte changes is the interesting one. mGBA's own C core has a
real watchpoint facility (per-instruction memory-access interception that
reports the exact PC, address, and old/new value on a match) that makes
this precise and address-targeted instead — flagged in the previous
round's progress notes as unfinished ("`NativeDebugger`/`set_watchpoint`
exist in the bindings but need a lower-level `mDebuggerCreate` call this
pass didn't reach"). Getting it working took real digging, recorded here
so it isn't repeated:

1. **The bindings' own convenience wrapper doesn't work.**
   `mgba.debugger.NativeDebugger.set_watchpoint(self, address)` calls
   `platform.setWatchpoint(platform, address)`, passing a bare Python int
   where the native C signature (`ssize_t (*setWatchpoint)(struct
   mDebuggerPlatform*, const struct mWatchpoint*)`) expects a pointer to a
   real `struct mWatchpoint` (`address`, `segment`, `type`, plus an
   optional condition tree). Build one by hand with
   `ffi.new("struct mWatchpoint*", {"address": a, "segment": -1, "type":
   lib.WATCHPOINT_WRITE})` and pass that instead.
2. **`mDebuggerCreate()`'s only two working types both add unwanted
   machinery for a headless scripted driver.** `DEBUGGER_CLI`'s `entered`
   callback (`_reportEntry` in mgba's `cli-debugger.c`) unconditionally
   calls `cliDebugger->backend->printf(...)` with **no null check** — it
   segfaults the moment a watchpoint fires unless a real `CLIDebuggerBackend`
   (stdio, a GUI console, ...) has been attached, which a plain `import
   mgba.core` script never does. `DEBUGGER_GDB` needs an actual socket
   client on the other end. Neither fits "one Python process, no
   interactive console."
3. **The fix: build a bare `struct mDebugger` by hand and skip
   `mDebuggerCreate` entirely.** `ffi.new("struct mDebugger*")` (cffi
   zero-fills it) + `lib.mDebuggerAttach(debugger, core._core)` wires it to
   the core exactly like the CLI path does internally, *without* the CLI's
   presentation layer. Reading mgba's C source
   (`src/sm83/debugger/memory-debugger.c`, `src/debugger/debugger.c`)
   clarified the two distinct `entered` callbacks that matter here: the
   **platform's** `entered` (`SM83DebuggerEnter`, always set by
   `SM83DebuggerPlatformCreate` regardless of debugger type — this is what
   sets `cpu->nextEvent = cpu->cycles` and is what actually makes a hit
   surface promptly) checks the **top-level `mDebugger.entered`** for
   NULL before calling it — so leaving that one unset is safe, no crash,
   no CLI backend needed.
4. **Wiring `mDebugger.entered` to a real Python callback gets the full
   hit info, not just a pause flag.** `ffi.callback("void(struct
   mDebugger*, enum mDebuggerEntryReason, struct mDebuggerEntryInfo*)",
   fn)` works fine in this ordinary (non-embedded) `import mgba` API-mode
   usage — cffi's `embedding_api`/`embedding_init_code` machinery visible
   in `_builder.py` (`mPythonSetDebugger` et al.) is a *different*,
   unrelated mechanism for the reverse scenario (mGBA's own binary
   embedding a Python interpreter for its scripting console); it plays no
   part here and doesn't need touching.
5. **A hit doesn't stop `core.run_frame()` — drive with `core.step()`
   and check after every call**, same as the text-encoding trace. The
   memory shim's `mDebuggerEnter()` just sets `debugger.state =
   DEBUGGER_PAUSED`; nothing about that unwinds a C-level `runFrame` loop
   already in flight. `Watcher.run_until_hit()` wraps this: step, check
   `watcher.hit`, resume, repeat.

Net result (`tools/rom/watcher.py`): `Watcher(core).watch(address)` /
`.watch_many(addrs)`, then `pc, steps = watcher.run_until_hit()` — returns
the exact instruction that touched a watched address, with
`watcher.last_hit` giving old/new value and `watcher.rom_offset(core, pc)`
resolving the hit PC through the live MBC bank register into a real ROM
file offset. Used this round to trace the room-load VRAM write (see
rom-map.md); reusable as-is for the next dynamic-analysis question (combat
formulas, event triggers, save RAM writes).

**`tools/rom/reach_room.py`** saves the button sequence worked out this
round (screenshot-and-iterate, the same technique as the room-frame
bisection above) to drive a fresh boot into the first real playable room
— `reach_room.reach_first_room()` returns a `Session` sitting there. The
previous round's equivalent sequence lived only in an ad hoc, unsaved
script and would have needed rediscovering; this one won't.

**`tools/rom/disasm.py`** is a small, from-scratch SM83 disassembler
(unprefixed + CB-prefixed opcodes, standard GB opcode table), written
after manual hex-counting produced a real, caught-in-review mistake
mid-trace (see rom-map.md "Maps", fourth pass: an early misreading of the
`$1E9F` block's byte layout, corrected once real disassembly output was
available). `mgba`'s own C source has a proper decoder
(`SM83Decode`/`SM83Disassemble` in `include/mgba/internal/sm83/decoder.h`)
but it isn't exposed through the compiled Python bindings' cdef (checked:
`hasattr(lib, "SM83Decode")` is `False`) and wiring it in would mean
rebuilding the extension — writing the ~150-line Python table was faster
and is good enough for reading fixed-bank ROM code. CLI: `python3
tools/rom/disasm.py <rom_path> <start_hex> <end_hex>`. **Lesson worth
repeating**: don't hand-count hex offsets for anything beyond a couple of
instructions — it's a real, silent error source, distinct from (and in
addition to) the "verify claims with live register captures, not just
static reading" lesson from the same pass.

## Two more gotchas found this pass (fifth pass, milestones 5/8/9/save sweep)

1. **`core.memory.search()` (the bindings' Cheat-Engine-style value
   scanner) silently returns nothing without a manual fix.** It never
   sets `params.width`/`params.align` on the underlying
   `mCoreMemorySearchParams` (a real gap in the Python wrapper, not user
   error), which defaults to `0` via `ffi.new`'s zero-fill and matches
   nothing. Build the params by hand instead (`ffi.new("struct
   mCoreMemorySearchParams*")`, set `memoryFlags`/`type`/`op`/`width=1`/
   `align=1`/`valueInt`, call `lib.mCoreMemorySearch` directly) — this is
   how the `$D7B2` player-stats struct was found, a real two-pass
   Cheat-Engine-style scan (search for the known HUD value `19`, take a
   real hit, filter to addresses still matching after the value visibly
   changed). Also worth knowing: it searches the *entire* address space
   including ROM unless you filter the returned addresses yourself
   (e.g. to `0xC000-0xDFFF` for WRAM) — there is no built-in region
   restriction beyond the `memoryFlags` R/W bits.
2. **A raw PC number is meaningless without its bank.** `tools/rom/
   disasm.py` (or any manual hex read) takes a flat *file offset*; a live
   `core.cpu.pc` in `$4000-$7FFF` is a bank-relative CPU address that only
   maps to a file offset via the bank that happened to be active at that
   exact moment (`watcher.rom_offset(core, pc)`, using
   `GBMemory.currentBank`). Disassembling a raw PC value directly against
   the ROM file without this conversion produces plausible-looking but
   wrong garbage (hit this concretely tracing the save-write loop: `pc =
   0x7471` disassembled as nonsense at file offset `0x7471`, but was
   real, clean code once resolved through `rom_offset()` to its actual
   bank-2 file offset `0xB471`). Always resolve through `rom_offset()`
   before feeding a captured PC to `disasm.py`, never use it as a file
   offset directly.

## `tools/rom/gamegenie.py` — decode community cheat codes as a cross-check

Added this round after the user suggested checking published GameShark/
Game Genie codes for the US cartridge against this project's own
findings (see references.md and rom-map.md "Breakthrough" for what this
turned up — strong three-way confirmation of the whole RAM-address set,
plus a working, byte-verified "walk through walls" ROM patch). GB
GameShark codes (`01VVAAAA`) need only a byte-swap of the address pair to
decode; GB Game Genie's 6/9-digit codes need a real bit-scrambling
algorithm, ported directly from mgba's own `GBCheatAddGameGenieLine`
(`src/gb/cheats.c`) rather than re-derived — that source is already
correct and saved real time. CLI: `python3 tools/rom/gamegenie.py
<code>...`. To actually apply a decoded Game Genie ROM patch live,
`core.memory.u8.raw_write(address, new_value)` bypasses the normal
MBC-redirected bus write that a plain `core.memory.u8[address] = value`
would trigger for ROM addresses (confirmed necessary: the plain form
does not patch ROM content, `raw_write` does).

## External save files as a cross-check, and a `core.load_save()` gotcha (2026-08-08, seventh pass)

This sandbox's Bash environment has real outbound network access (`curl`
works directly) — worth knowing for future research passes; not
previously confirmed in this project's docs.

**`core.load_save(vfile)` segfaulted** when tried against a real,
externally-sourced 8 KiB `.sav` file (way larger than MBC2's real
512-byte address space — many emulators/tools pad SRAM save files to a
generic size regardless of the actual cart's real capacity). Root cause
not isolated (possibly a size-mismatch bug in this exact mgba build's
`GBCheatDevice`-adjacent save-loading path, not investigated further).
**Workaround, safe and proven**: skip the VFile/`load_save()` API
entirely and poke bytes directly into the exposed `core.memory.sram.u8`
`MemoryView` with `.raw_write(offset, value)` (same `raw_write` already
used elsewhere this project for ROM patches — bypasses the MBC's normal
enable/gate logic, appropriate for a research tool feeding known-good
data directly into the emulated hardware's storage, not appropriate for
faithfully reproducing what an *unmodified* real cartridge would do).

**A real save file's byte layout needed bisecting against this
project's own address findings, not assumed**: naively copying an
external `.sav`'s bytes `[0:512]` 1:1 into SRAM produced a byte range
past offset ~248 that didn't decode as valid nibbles (values >15) —
inconsistent with this project's own live-traced finding that valid
save data occupies exactly two 248-address regions (`$A000-$A0F7` primary,
`$A100-$A1F7` backup, byte-identical). The external file's own bytes past
offset ~504 don't cleanily represent a real backup copy (specific tool/
emulator's own save-file convention, not further investigated) — the
robust move was deriving the backup region **from this project's own
verified duplicate-copy fact** (mirror the real primary bytes into both
regions) rather than trusting the external file's raw byte layout past
the primary copy.

**Bisecting a hang/crash by binary-searching how much of a payload gets
written is a fast, general debugging technique**, reusable beyond this
one case: wrap "write N bytes, boot, check for a known-good visual/
memory signal" in a function and binary-search N between a known-good
and known-bad value. Found the exact byte offset responsible for a real
CPU lockup in ~8 probes this way — **but the first attempt used the
wrong signal and bisected to the wrong byte** (see rom-map.md "Save
RAM"'s correction): checking "does a known tilemap pattern appear by
frame 600" conflates *slow/incomplete loading* with *genuinely,
permanently locked up* — a save that's merely still animating at frame
600 looks identical to that check as one that's hard-crashed. Re-running
the same bisection with the *actual* lockup signature (`core.cpu.pc`
sampled across thousands of `core.step()` calls, genuinely never
changing — the same technique already used elsewhere in this project
for single-instruction tracing) found a different, more precise answer.
**Lesson**: when bisecting a hang/crash, bisect on the most direct,
unambiguous signal available (a truly-frozen PC), not a proxy signal
(a UI screen failing to appear by an arbitrary frame count) that can
also be explained by an innocent, slower-than-expected but ultimately
successful boot path.

## `tools/rom/calltrace.py` — bank-accurate live call-stack tracer (2026-08-09)

Built after a real, specific failure: reading the raw SM83 stack bytes
*after* a watchpoint fires and guessing which MBC bank each saved return
address was pushed from produced a wrong answer (a stack slot was
mis-attributed to bank 8 and disassembled as if it were code — it was
graphics data; see rom-map.md's room-transition trace for the full
story). Raw stack contents don't carry bank information at all, and by
the time a watchpoint fires, any of several earlier calls could have run
in a since-switched-away bank.

`CallTracer` fixes this by construction instead of by more careful
guessing: it decodes the opcode at PC on **every single step** (paired
with `Watcher.step()` in the same loop, not a second pass) and
maintains a live call-frame stack, pushing on `CALL`/`RST` (detected via
"did PC actually jump" — comparing post-step PC against the arithmetic
fallthrough address, not by decoding condition-code flags, so it can't
be thrown off by a flag-semantics mistake) and popping on `RET`/`RETI`.
Each frame's caller/callee addresses are resolved through the
already-existing bank-aware `rom_offset()` **at the moment they
happened**, so the bank is always correct — never reconstructed later
from a stale value.

Also handles **hardware interrupt dispatch** as a synthetic call frame:
PC landing exactly on one of the 5 ISR vectors (`$40/$48/$50/$58/$60`)
without the just-read opcode being what put it there means the CPU
hardware itself pushed a return address and jumped, invisible to opcode
decoding otherwise. Omitting this would have silently desynced the
frame stack the first time an interrupt fired mid-trace — and one does,
routinely: this ROM's hardware-register writes (SCX/SCY/LCDC/OBP0/OBP1/
BGP/WX/WY) all happen from inside the VBlank handler, not mainline code,
so any trace anchored on watching one of those registers directly will
mostly show the *generic ISR flush routine* as the immediate caller, not
the real decision logic — the actual fix that unblocked this pass was
realizing the ISR reads its values from real WRAM *shadow* bytes
(`$C0A6`-`$C0A9` etc., found by disassembling the ISR itself) and
watching writes to the shadow byte instead of the hardware register.

Usage sketch (see rom-map.md's write-up for the full real trace this
produced):

```python
from watcher import Watcher
from calltrace import CallTracer

w = Watcher(session.core)
w.watch(0xC0A7)  # a WRAM shadow byte, not the hardware register itself
tracer = CallTracer(session.core, rom_bytes)  # rom_bytes = open(rom_path,'rb').read()
for i in range(2_000_000):
    pc_before = session.core.cpu.pc
    peeked = tracer.peek(pc_before)
    hit = w.step()
    tracer.record(pc_before, peeked)
    if hit and w.last_hit.get("newValue") not in (0, None):
        print(tracer.format_stack())  # real, bank-resolved, outermost-first
        break
```

**A second, separate lesson from the same pass, about reproducing game
state, not the ROM itself**: reconstructing "boss defeated, player
centered in a specific doorway" by blind button-mashing from a cold boot
is fragile across sessions (exact frame counts from an earlier
investigation don't reliably transfer). `core.save_raw_state()` /
`core.load_raw_state()` round-trip through plain Python `bytes` cleanly
(no special wrapping needed) — once a state of interest is found via a
*verified*, feedback-driven search (checking real position/register
reads after each input, not trusting a fixed frame count), save it once
and reload it for every further experiment instead of re-deriving it.

## A real bug found and fixed: `session.run(N)` + `Watcher` can silently drop hits (2026-08-12)

Direct user question after a "zero hits" claim turned out to be
wrong ("kann der auch andre stellen betroffen haben?"). This module's
own doc comment (see the top of `watcher.py`) already said the safe
way to drive a `Watcher` is `core.step()` in a loop, checking `w.hit`
after every SINGLE instruction — **not** `session.run(N)` (which calls
`core.run_frame()`, a whole frame's worth of instructions per native
call). The usage sketch earlier in this file already showed the
correct `w.step()`-in-a-loop pattern. Despite that, an entire session's
worth of investigation scripts (the `0xFF` sub-dispatch trigger search,
the `$C5A0`/`$C4E0` actor-array persistence tests) used
`session.run(1)` per tick with `Watcher` instead — the wrong,
undocumented-as-safe pattern — because nothing forced a re-read of this
file's own existing guidance before writing new scripts.

**Real, concrete, measured consequence**: watching `$D86B` (2 addresses:
`$D86B`+`$D85A`) across a real post-boss dialogue sequence with
`session.run(1)` reported **zero** `$D86B` writes. Re-run with the
correct `w.step()` pattern, single-address: **7** writes. Full
`w.step()`-driven re-verification (watching `$D86B` together with
`$C5A0`+`$C4E0`'s full 200-byte range, ALL AT ONCE, 180,000,000
single-stepped instructions) confirmed the 7 real hits and found
**zero** additional hits anywhere else — i.e. once driven correctly,
even 201 simultaneous watchpoints are perfectly reliable; the bug was
never really about the WATCHPOINT COUNT, it was about the DRIVER
(`run()` vs `step()`). A prior investigation pass's own guess ("many
simultaneous watchpoints undercount") was directionally right about
the symptom but wrong about the mechanism — worth correcting here so
the real lesson doesn't get mis-filed as "keep watchpoint counts low"
(the actual fix is "always drive with `step()`, count doesn't matter").

**Performance note, since it matters for whether the correct pattern is
even practical**: `w.step()` single-stepping runs at roughly
**1,000,000 SM83 instructions/second** on ordinary hardware (measured,
not estimated) — a real ~9000-frame (~150M-instruction) window takes
under 5 real minutes. Not free, but very much affordable for anything
short of a full-game sweep; there is no good reason to reach for
`session.run(N)` when a `Watcher` is involved.

**New, load-bearing rule for this project's own tooling, stated
plainly so it survives past this one session**: *any* script that
combines `Watcher` with `session.run(N)` (instead of `w.step()` in a
loop) produces results that cannot be trusted for a "zero hits"
conclusion — a positive hit-count from such a script is still
meaningful (real hits genuinely happened), but silence is not evidence
of absence. Retroactively affects every "negative"/"zero hits" claim
made via `session.run(N)`-driven watching before 2026-08-12 in this
project's own docs — each should be treated as unverified, not
disproven, until re-checked the correct way (see events.md's own
"Definitive re-verification" section for the one dialogue-sequence
case this was actually caught and fixed for).

## Three more real tooling bugs found and fixed, plus a general audit of whether they tainted older results (2026-08-13)

Direct user instruction after several bugs surfaced in one long
session ("du hast mehrere fehler in den tools entdeckt. prüfe ob diese
ursprüngliche alte ergebnisse verfälscht haben und korrigiere wenn
nötig" -> "nicht nur diese session sondern allgemein" -> "nicht nur
fehler prüfen sondern auch korrigieren"). Three DISTINCT bugs, all in
NEW code written in that same session (not regressions of the
2026-08-12 `session.run(N)` bug above, which remains its own, already-
audited, already-closed issue):

1. **A custom execution-breakpoint helper (`struct mBreakpoint` +
   `platform.setBreakpoint`) never fired at all.** `watcher.py` only
   ever implements memory WATCHPOINTS (this file's own section above);
   a same-session script extended that pattern by hand for PC-address
   breakpoints and got it wrong in some way not yet root-caused. Self-
   caught via a sanity check: breakpointing `$3727` (a known-
   extremely-frequent address, confirmed elsewhere in this file) ALSO
   produced zero hits, proving the mechanism itself was broken rather
   than proving anything about the addresses being watched. **Rule**:
   don't add a new native-debugger code path without a sanity check
   against an address already known to fire constantly — the
   `watcher.py` watchpoint mechanism remains the only mGBA hit-
   detection method this project has actually proven correct; treat
   any OTHER native-debugger technique as unproven until it passes the
   same kind of sanity check.
2. **A real segfault (exit code 139) from attaching a SECOND
   `mDebugger` to a `core` that already has one attached.** Calling
   `Watcher(core)` twice against the same session's `core` (e.g. to
   re-scan after advancing gameplay) corrupts mgba's native state.
   Caught via direct user report ("python stürzt ab") after a script's
   own output cut off mid-run without the caller noticing the non-zero
   exit code. **Rule**: create exactly ONE `Watcher` (and therefore one
   native `mDebugger`) per `core`, for that core's entire lifetime;
   thread it through every subsequent call against that same core
   rather than constructing a new one. **Also**: always check a
   script's own exit code (`echo $?` or equivalent) after a long run,
   not just whether SOME output was printed — a crash partway through
   can still leave plausible-looking partial output on screen.
3. **Watching a single WRAM cell for a VALUE match, with no check on
   which real code path produced it, silently false-positives.**
   `$D85A` (the real "current opcode" byte) is written by `$3727`
   (this file's own already-documented general fetch primitive) —
   but `$3727` is reused by MANY unrelated code paths (e.g. the
   already-known Family-A `actorAction` dispatcher at `$2879` calls it
   too, to fetch its OWN group operand), so a `$D85A` write matching a
   opcode value being searched for does NOT by itself prove that
   opcode's real top-level handler ran. Caught by cross-checking a
   "hit" against `disasm.py` output (not hand-counted): the PC right
   after the hit landed inside `$2879`'s own body, completely
   unrelated to the opcode being searched for. **Rule**: after any
   `$D85A`/`$D8B6`-style "value matched" hit, verify the SUBSEQUENT PC
   actually lands inside the SPECIFIC real handler address being
   searched for (cross-checked via `disasm.py`, not assumed) before
   treating the hit as a genuine top-level dispatch.

**General audit of whether these bugs affected OLDER (pre-2026-08-13,
including earlier sessions') results, not just this session's own new
work** (direct user request, "nicht nur diese session sondern
allgemein"): bugs 1 and 2 are in code that was NEW this session (the
breakpoint helper and the double-Watcher pattern were never used in
any previously-checked-in script) — by construction they cannot have
tainted anything written before they existed. Bug 3 (value-match
without a landing check) is a genuine, GENERALIZABLE methodology risk,
so it was checked against this project's own FOUNDATIONAL `$D85A`-based
findings specifically:
- The original opcode-dispatch-table discovery (rom-map.md, `$D85A=0x04
  -> table[4]=0x333D`, `$D85A=0xFE -> table[0xFE]=0x0E69`) does NOT
  share the flaw: it cross-verified the table LOOKUP's own real output
  (`HL` at function 51's `$4575` RET, sampled 5 times) against an
  independently-derived expected value, anchored to a real, externally
  visible narrative moment (the "Kaempfe!" trigger) — a fundamentally
  stronger evidentiary standard than a bare value-match.
- The boss-defeat script's own 18-real-opcode trace (events.md, "The
  real boss-defeat script: every opcode it actually uses, decoded")
  does NOT share the flaw either: the watch began only once the
  persistent cursor (`$D8B6`/`$D8B7`) was independently confirmed to be
  AT the real script's own known start address (`$470F`), so subsequent
  `$D85A` writes genuinely reflect THAT script's own real opcode
  stream, not an arbitrary unrelated `$3727` call elsewhere.
- No other pre-2026-08-13 finding in rom-map.md/events.md was found
  relying on a bare `$D85A`/cursor value-match without one of these two
  stronger anchors.
**Conclusion: no pre-existing, older project finding needed correction
from this specific audit.** Only this session's OWN new claims (task
#83's "9,000,000 steps, zero hits, decisive" result, which used the
broken breakpoint mechanism) were wrong and have been retracted in
place in both events.md and progress.md (see their own dated
"RETRACTED" notes) — not silently rewritten, so the mistake and its
correction are both visible to anyone reading the history.

## Two reusable `tools/rom/lib.py` helpers, generalized from real mistakes (2026-08-12)

Direct instruction, after a real-play bug sweep found and fixed 7
concrete problems: "untersuche die dinge die ueber einzelfixes hinnaus
gehen, dokumentiere sie als systeme" -- two of that sweep's root causes
were really the SAME kind of investigation mistake, made twice,
independently. Generalized both into reusable functions so future
investigations don't have to re-learn them by hand.

**`capture_closed_cycle(session, oam_filter, step_frames, max_steps)`**
-- the real lesson behind the boss-movement fix (see rom-map.md's
2026-08-12 correction): this project's own original `Enemy.
MOVEMENT_CYCLE` was built from a 700-real-frame capture that never
actually saw the real cycle close (825 frames), and got "fixed" by
inventing a plausible-looking mirror-return leg rather than just
capturing longer. This function makes "run until you can PROVE closure
(a later sample exactly repeats an earlier one), not until an arbitrary
frame budget runs out" the default method instead of a lesson to
remember by hand -- returns `(cycle, period_frames)` or `(None, None)`
if no real closure is found (an honest negative, never a forced guess).
Verified against the already-known-correct real 33-step/825-frame boss
cycle: reproduces it exactly.

**`sample_palette_at(session_factory, checkpoint_fns)`** -- the real
lesson behind the NPC-palette fix: `willyScene.paletteShadeIndices`
(`0xFB`) was a real, correctly-read live value that got wrongly reused
as "the" general resting sprite palette -- it was actually specific to
the exact instant of a dialogue box. A SECOND real sample (this
project's own `willy_room_free()`, well after any dialogue box) would
have caught the disagreement immediately. This function takes several
real checkpoints that are all supposed to represent the same "calm"
state and reads OBP0/OBP1/BGP at each, printing a loud warning the
moment they disagree instead of letting a single lucky (or unlucky)
sample stand in for "the" value unchallenged.

**General rule these two encode**: a single live sample is a real,
verified FACT about the exact instant it was taken -- it is not
automatically a fact about the general/resting/repeating state unless
something has actually checked that it repeats. Both a room's own
cyclic AI movement and a hardware palette register are real, dynamic,
time-varying ROM state; treating either as a permanent constant off one
sample is the same mistake wearing two different hats.
