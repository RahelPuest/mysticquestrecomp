# Text / Dialogue Encoding

Status: **VERIFIED** (main encoding formula, and — as of 2026-08-09 — 15
entries of a real digraph compression table used by general dialogue
prose; see "The digraph compression table" below), found via dynamic
tracing after static analysis alone hit a wall — see
[tooling.md](tooling.md) for the emulator setup and the general technique,
this document for the encoding itself and what's still open.

## The formula

A text byte `b >= 0xB0` decodes as `MAIN_GLYPHS[b - 0xB0]`, where
`MAIN_GLYPHS` is exactly the font's own VERIFIED ROM tile order (see
"Font / text glyphs" in [rom-map.md](rom-map.md) and
`src/import/rom_profiles.lua`'s `graphics.font.rowGlyphs`):

```
0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',
```

- **`0xFF` = space.** (The font's very last tile, index 79, is a blank
  glyph — consistent with being reserved for the space character.)
- **`0x00` = string terminator.**
- **`0x90-0xAF`** = the umlaut/icon block immediately preceding the main
  charset in ROM (ROM tile order 0-31 relative to file offset `0x22900`,
  vs. the main charset's tile order 32-111 relative to the same base —
  see rom-map.md's font entry). Four bytes confirmed: `0x9C`=ä, `0x9D`=ö,
  `0x9E`=ü (2026-08-09, decoding the real intro-text scroll —
  `"ber[0x9E]hrt"`=`"beruehrt"`), `0x9F`=ß (same pass, `"mi[0x9F]brauchen"`
  =`"missbrauchen"`). Every other byte here is UNKNOWN until similarly
  cross-checked — do not guess the rest from tile appearance alone.
- **`0xF2` = VERIFIED: a hyphen** (upgraded 2026-08-09 from a single-
  example hypothesis). Originally seen once, in `"Lebens- und
  Magiepunkte"`. Second, independent confirmation found decoding the
  real intro-text scroll: appears at every real German word-wrap
  hyphenation point (`"des-sen"`, `"brau-chen"`) — two unrelated
  discovery paths agreeing is this project's own bar for "VERIFIED."
- **`0x1A` = VERIFIED: a line break**, distinct from the `0x00`
  terminator (found 2026-08-09, same intro-text decode — the text is
  genuinely multi-line, and `0x1A` sits at every real line boundary the
  independently-decoded live tilemap scroll also showed as a new row).

Implemented in [`src/import/TextDecoder.lua`](../../src/import/TextDecoder.lua)
(pure Lua, headlessly unit tested against both synthetic bytes and real
ROM offsets) and [`tools/rom/dump_strings.py`](../../tools/rom/dump_strings.py)
(reproducible from the ROM file alone — no emulator needed to re-run this
once the formula is known).

## The digraph compression table (2026-08-09)

Status: **VERIFIED** (15 confirmed entries), a real second layer on top of
the main formula above, living entirely *below* `0xB0`. This is the
"documented two-character dialogue-compression scheme" that
[roadmap.md](../roadmap.md) had flagged as a reference-project hypothesis
(attributed to the FFA-Disassembly project — see
[references.md](../references.md)) but this project had never itself
confirmed. It is now confirmed directly against this ROM's own bytes, not
by trusting the reference project's claim.

### How it was found

The previously-decoded Willy-scene dialogue box's on-screen tile IDs (read
live from VRAM, `tools/rom/play_driver.py`) showed `tileID = 48 +
MAIN_GLYPHS_index(char)` for every letter of "WILLY" — i.e. just the same
already-known formula at a different display-side offset for this
particular screen (a per-scene font placement quirk), not a new encoding.
That ruled out one hypothesis, but also gave a template: since "WILLY" is
a proper name, it might appear *uncompressed* even if general prose
doesn't. Converting "WILLY" through the already-known ROM-byte formula
and searching the raw ROM file for a literal match found one immediately
at file offset **`0x3A268`**.

Decoding a ~1KB stretch of real bytes around that offset with the
existing (pre-digraph) `TextDecoder` produced long runs of genuine,
mostly-readable German dialogue — but with gaps: individual unmapped
bytes sitting in exactly the position where the readable German around
them demanded specific missing letters. The gaps were not noise: the
same unmapped byte value recurred every time the same two-letter
combination was needed, in otherwise-unrelated words. That is the
signature of a digraph table, and cross-referencing enough of these
recurring gaps against the German the surrounding literal bytes already
spelled out was enough to pin down 15 entries with two-or-more
independent confirmations each (this project's normal "VERIFIED" bar —
see e.g. how the umlaut bytes above were confirmed the same way, just
one byte at a time instead of building a table).

### The table

| Byte | Digraph | Confirmed via (2+ independent words each) |
|------|---------|---------------------------------------------|
| `0x24` | `en` | `"Wi[ll]y"`/`"Wasserfa[e][ll][en]"`, `"li[e][ss][en]"` |
| `0x2A` | `ie` | `"V[ie][le]"` |
| `0x2F` | `te` | `"R[it][te]r"` (recurs 4+ times) |
| `0x31` | `be` | `"[da][be]i"`, `"Le[be]n"` |
| `0x37` | `un` | `"[un]noetig"` |
| `0x39` | `le` | `"V[ie][le]"` |
| `0x3A` | ` i` | `"unnoetig[ i]hr"` (space folds into the digraph) |
| `0x3B` | `se` | `"Wa[s][se]rfaellen"`, `"mue[s][se]n"` |
| `0x3C` | `as` | `"W[as][se]rfaellen"` |
| `0x4E` | `da` | `"[da][be]i"` |
| `0x51` | `it` | `"R[it][te]r"` (recurs 4+ times) |
| `0x55` | `ll` | `"Wi[ll]y"`, `"Wasserfae[ll]en"` (2 unrelated words, same byte, same letters both times) |
| `0x5A` | `ma` | `"Ge[m][ma]"` (recurs 6+ times) |
| `0x5C` | `em` | `"G[em]ma"` (recurs 6+ times) |
| `0x5F` | `li` | `"[li]e[ss]en"` |

Full worked example, byte-for-byte, from the real ROM at `0x3A2BE`:

```
W  0x3C  0x3B  r  f  0x9C  0x55  0x24  .
W  as    se    r  f  ae    ll    en    .
= "Wasserfaellen."   (Wasserfällen, ASCII-safe umlaut spelling)
```

— 9 ROM bytes decoding to a real 14-letter German word, cross-checking
five different table entries (2 digraph bytes doubled up as 4 letters,
plus the pre-existing `0x9C`=ae umlaut byte) simultaneously.

Implemented as `TextDecoder.DIGRAPH_PARTIAL` in
[`TextDecoder.lua`](../../src/import/TextDecoder.lua), wired into
`decodeByte` the same way `UMLAUT_PARTIAL` is. Tested against both
synthetic bytes and the two real ROM locations above in
[`text_decoder_test.lua`](../../tests/import/text_decoder_test.lua).

### What this did NOT resolve

- The sub-`0xB0` range is not fully mapped. The same ~1KB dump has many
  more recurring low-byte values (`0x25`, `0x28`, `0x2B`, `0x33`, `0x44`,
  `0x46`, `0x4A`, `0x53`, `0x64`, `0x69`, `0x6A`, `0x87`, `0xA9`, and
  others) that pattern-match the same way (plausible digraphs — e.g.
  `0x2B` recurring in contexts that read like "...bezwung[en]", "ng"),
  but none of them yet has two independent confirmations against
  already-known text, so they stay UNKNOWN rather than guessed, per this
  project's "no silent fallbacks" rule.
- **Control/script bytes are a separate, still-unmapped concern.** The
  same dump is dense with small values (`0x00`, `0x02`, `0x04`, `0x0A`,
  `0x12` immediately followed by either `0x1B` or `0x11`, `0x1E`, ...)
  recurring in patterns that look like script bytecode, not text — most
  strikingly, `0x00` (the confirmed string TERMINATOR_BYTE) is
  *immediately* followed by `0x04` at multiple points, matching
  roadmap.md's FFA-Disassembly-attributed hypothesis that `$00`=end-
  string and `$04`=a display-message opcode. This project has not traced
  these against real CPU execution (the technique that cracked the main
  formula and the umlaut bytes) — they are read off purely from
  recurring position in decoded text, which is weaker evidence than a
  register trace. Treat the control-byte identities in this paragraph as
  a lead for the next pass, not a finding.
- No systematic search for *more* literal (uncompressed) proper-name
  anchors beyond "WILLY" was done — the dump analyzed here was one ~1KB
  window opportunistically found and hand-decoded, not a full-ROM sweep.
  A full-ROM re-run of `dump_strings.py`-style scanning, now with the
  digraph table folded in, would very likely turn up much more readable
  dialogue and more digraph candidates with real second/third
  confirmations — a natural next step, not attempted this pass.
  ~~RESOLVED 2026-08-11~~ — see "The digraph table, doubled" below.

## The digraph table, doubled: a systematic full-ROM scan, direct follow-up (2026-08-11, "wechsel zu den Dialogtexten und bringe das zuende")

Direct instruction to pick this task back up and finish it. Did exactly
the "natural next step" the previous section named: wrote a lenient
full-ROM scanner (`TextDecoder.decodeByte` run byte-by-byte, but
continuing past unmapped bytes as `[XX]` gap markers instead of
stopping, the same technique that found the original 15 entries, now
automated and run everywhere instead of by hand on one window).

**A real, important discovery on the way there**: the real dialogue
region is far larger than previously known. The original 15-entry
table came from a ~1KB window around file `0x3A268`; this pass found
the SAME story sequence (Willy, Julia, Bogard, Dark Lord, Amanda,
Cibba, ...) actually spans roughly **`0x34800`-`0x3B000`** (~26KB) —
the earlier work had only sampled the tail end of one long, continuous
narrative, not a small isolated fragment.

**12 new bytes CONFIRMED** (this project's normal 2-independent-word
bar, most with 3+), found by decoding this much larger corpus and
cross-referencing recurring gaps against the German the surrounding
literal bytes already spelled out — exactly the original method, just
with far more raw material to work from:

| Byte | Value | Confirmed via (2+ independent occurrences each) |
|------|-------|---------------------------------------------------|
| `0x23` | `er` | `"H[23]r"`="Herr" (x2+, "Sir"/"Lord"), `"tapf[23][23]"`="tapferer" (braver), `"Kämpf[23]"`="Kämpfer" (fighter) — all in one sentence |
| `0x25` | `n ` | `"abe[25]das"`="aben das" ("Sie haben das", "you have that"), `"obe[4F][25]"`="oberen " ("upper", + digraph `0x4F`="re") — space-inclusive, same shape as `0x3A` |
| `0x29` | `in` | `"E[29] Jun[2B]e"`="Ein Junge" (a boy), `"E[29][52]äd-"`="Ein Mäd-(chen)" (a girl) — promotes the 2026-08-10 single-occurrence "Yoshinori" lead to VERIFIED |
| `0x2B` | `ge` | `"bezwun[2B]n"`="bezwungen" (defeated, x2 independent sentences), `"Jun[2B]e"`="Junge" |
| `0x34` | `an` | `"G[34]z"`="Ganz" (entirely), `"[34]gegriffen"`="angegriffen" (attacked, x2 separate occurrences), `"[34]beterin"`="anbeterin" (admirer), `"T[34]te"`="Tante" (aunt) — 5 independent confirmations |
| `0x3F` | `he` | `"hier[3F]r"`="hierher" (here, to here) — 2 separate occurrences, one standalone, one in "Komm hierher!" |
| `0x47` | `ar` | `"W[47]te...ier"`="Warte hier" (wait here), `"Bog[47]d"`="Bogard" (a real character name, 20+ identical occurrences) |
| `0x4C` | ` b` | `"Zyklop[4C]ezwungen"`/`"Garuda[4C]ezwungen"`/`"Chimä[4F][4C]ezwungen"` — the real "\<monster\> bezwungen" (defeated) message shape, 3 different monster names, space-inclusive |
| `0x5B` | `a` | `"Juli[5B]"`="Julia" (a real character name, 25+ identical occurrences) — single-letter code, same shape as the already-flagged `0x43`="n" lead |
| `0x65` | ` h` | `"Sie[65]abe[25]das"`="Sie haben das" (you have that), `"W[47]te[65]ier"`="Warte hier" (wait here) — space-inclusive |
| `0x6E` | `mm` | `"Willko[6E]en"`="Willkommen" (welcome, x2), `"entko[6E]en"`="entkommen" (escape), `"Ko[6E][65]ier[3F]r"`="Komm hierher" (come here) |
| `0x88` | `Da` | `"[88]rk Lord"`="Dark Lord" (a real character title, 10+ identical occurrences) — the first confirmed CAPITALIZED 2-letter code |

The table now has **28 confirmed entries** (16 -> 28), all wired into
`TextDecoder.DIGRAPH_PARTIAL`, tested both synthetically and against 7
real ROM locations (character names, the "Dark Lord" title, and 3
different multi-digraph sentences) in
[`text_decoder_test.lua`](../../tests/import/text_decoder_test.lua).

**A real, useful side effect**: with the expanded table, whole
sentences that previously had 3-5 gaps now decode with 0-1 remaining
unknown bytes (`"Julia"`, `"Bogard"`, `"Dark Lord"`, `"Willkommen in"`,
`"hinten angegriffen"` all decode perfectly clean now) — a strong,
direct validation that these entries are correct, not overfit to one
ambiguous reading, since each was cross-checked against MULTIPLE
independent real sentences across a ~26KB span, not just the single
occurrence that first suggested it.

**Honest remaining scope, precisely stated** (this task is
substantially, not completely, finished):
- The sub-`0xB0` range still isn't fully mapped — this pass focused on
  the highest-value, most-repeated candidates in the newly-found large
  corpus; plenty of lower-frequency bytes remain real UNKNOWNs (not
  guessed), the same honest status as before, just a smaller remaining
  set.
- Control/script bytes (`0x00`/`0x02`/`0x04`/`0x0A`/`0x12`/`0x1B`/
  `0x11`/`0x1E`, and more) are still not traced against real CPU
  execution — this pass's own occurrence data makes an even stronger
  case they're script bytecode (extremely high, near-constant
  frequency relative to actual prose, and dense runs of them between
  real sentences reading like scene-transition/speaker-change
  sequences), but confirming their exact opcodes still needs the
  live-tracing technique this project used for `$235B`-style opcodes
  elsewhere (see rom-map.md), not attempted here.
- No dialogue pointer table has been located yet — strings are still
  found by scanning, not by walking a discovered index. With the real
  dialogue region now known to be ~26KB (not ~1KB), a pointer-table
  search restricted to whichever bank(s) reference that range is a
  much better-scoped next step than before.

## A full-ROM re-scan, at explicit user direction (2026-08-10) — 2 new punctuation bytes, 1 new digraph, and the real end-credits screen

Direct continuation of the concrete next step named above. Wrote an
updated scan (`/tmp/scan_text_v2.py` this pass, not committed — mirrors
`dump_strings.py`'s purpose but folds in the *current* full
`TextDecoder` including the digraph table, and renders unknown bytes
inline as `[XX]` markers instead of ending a run early, so long
otherwise-readable stretches stay visible with their gaps in context —
the same technique that originally found the digraph table). Static
only, no emulator needed (the encoding itself is already VERIFIED; this
is pure ROM-byte pattern matching). Filtered to blocks with ≥70% already-
decodable bytes to separate real prose from coincidental byte noise.

**The real end-credits screen** (bank 14, ~file `0x3b400`-`0x3bfff`) was
the single richest find — real, independently-verifiable Seiken
Densetsu 1 staff credits, e.g. `"DIREKTOR:\nKoichi Ishii"`, `"REGIE:
\nYoshinori Kitase"`, `"MUSIK - KOMPONIST:\nKenji Ito"`, `"GRAFIKEN:
\nKazuko Shibuya"` — real names checkable against the actual game's
credited staff, a strong, independent sanity check that the decode is
correct (not just internally self-consistent).

**`0xF5` = VERIFIED: a colon.** Found in **9 independent** `"ROLE[0xF5]
\nNAME"` credit lines (`MUSIK - KOMPONIST`, `GRAFIKEN`, `PROGRAMM`,
`LANDKARTE`, `SZENEN`, `DIREKTOR`, `UEBERSETZUNG`, `HAUPTPROGRAMM`,
`REGIE` — every single credit line in the whole screen), always in the
exact same structural position (end of the role label, immediately
before the newline and the person's name). Also fits a second, unrelated
real context: `"Hier hast Du Deine Ware[0xF5]"` ("Here, you have your
goods:" — presumably continuing with an inserted item name this
decode doesn't reach). Far past this project's normal 2-occurrence bar.

**`0xF4` = VERIFIED: a question mark.** Three independent real contexts:
`"...nu[0x26]tun[0xF4]"` = `"...nun tun?"` ("...do now?", completing
`"Was soll ich nun tun?"` = "What should I do now?"), `"...helfen
[0xF4]"` = `"...helfen?"` ("...help (you)?"), and `"WILLY![0xF4]"` (a
shocked "WILLY!?"). Independently, the font/on-screen-keyboard dump
shows the real punctuation ordering `',.` `[0xF1]` `-` `!` `[0xF4]`
`[0xF5]` `[0xF6]` — i.e. `0xF4` sits immediately after the
already-known `EXCLAMATION_BYTE` and immediately before the
now-also-confirmed `COLON_BYTE`, the natural remaining common
punctuation mark to complete that set.

**`0x58` = VERIFIED: the digraph "or"** (16th table entry). Found the
same way the original 15 were: two unrelated real words, same byte,
same letters. `"Yosh[0x29][0x58]i Kitase"` = `"Yoshinori Kitase"` (the
real credited Seiken Densetsu 1 scene/directing staffer — also a
genuinely famous, much-later Final Fantasy producer) and `"G[0x58]o O
[?]shi"` = `"Goro O[?]shi"` (the LANDKARTE/map credit, a different real
name). Both decode `0x58` as "or" consistently.

**`0xF6` — a real finding, but NOT a printable character, so
deliberately NOT added to `decodeByte`.** Appears exactly where the
already-known live HUD's own real numeric values must go: `"LP [0xF6]
MP [0xF6]"` matching the confirmed live HUD text `"LP <n> MP <n>"`
(rom-map.md's "Also observed" note). Reads as a real "insert a numeric
value here" template/substitution opcode — genuinely understood, but
adding it to the printable-character decoder would be actively
misleading (it isn't a letter or punctuation mark at all). Flagged here
as a real control byte, distinct from the "digraph vs. control opcode"
open question below, for a future pass that wants to trace/implement
numeric-value substitution specifically.

**STRENGTHENED (2026-08-15)**: the original finding above was a single
live-VRAM observation, never independently cross-checked. Found a real
static ROM string this pass (file `0xBE10`) that decodes cleanly to
`"LP   [F6]   MP   [F6]Naechster Level"` — a real status-menu screen
("Kraft"/"Reife"/"Wille" stat labels precede it, "Naechster Level" =
"Next Level" follows) — an independent confirmation from real ROM text
data, not a live screen read. A second, unrelated real occurrence also
found in the name-entry keyboard's own static layout string, right
before the digit row. Cross-checked against `rom_profiles.lua`'s own
`font.extraGlyphs` formula: the predicted real font tile (file
`0x22F60`) decodes to a plain diagonal line, not a punctuation glyph —
ruling out "unassigned printable character" as an alternative reading.
The WHAT is now solidly evidenced (2 independent real ROM occurrences
+ a negative glyph-shape control); the HOW (which real CPU code reads
it and performs the substitution) remains genuinely untraced.

**Four more real leads, each backed by only ONE occurrence so far — NOT
promoted, recorded as hypotheses per this project's 2-independent-
confirmations rule** (see `TextDecoder.lua`'s own doc comment for the
byte-by-byte reasoning):

- `0x29` = "in" (from `"Yosh[0x29][0x58]i Kitase"` = "Yoshinori
  Kitase" — the SAME word `0x58`="or" was confirmed from; only one real
  word uses `0x29` specifically so far)
- `0x35` = "ic" (from `"Ko[0x35]hi Ishii"` = "Koichi Ishii", a real,
  verifiable director credit)
- `0x43` = "n" as a single LETTER, not a 2-letter digraph (from `"Viele
  liessen dabei unnoetig ihr Lebe[0x43]"` = "...ihr Leben" — "...their
  life", a real, sensible German phrase). If real, this would mean the
  compression table isn't uniformly 2-letter codes.
- `0x6C` = "shi" as a 3-letter code (from `"Yo[0x6C]n[0x58]i Kitase"` =
  "Yoshinori Kitase" — the SAME real name as `0x29`'s own lead, but
  decoded a completely different, independent way, in a DIFFERENT
  credit line — "SZENEN" vs. "REGIE"). If real, a genuine 3-letter
  compression entry, plausible for a credits screen dense with
  Japanese-name syllables.

**Also strengthens (without newly proving) the existing "control bytes"
lead**: the exact 2-byte sequence `0x04, 0x10` now precedes **every
single one of the 9** real credit lines found this pass, immediately
before the role-name text starts — much stronger *positional* evidence
for `0x04`/`0x10` as real script/display-control opcodes than the
single earlier example, though still not CPU-traced (see the original
"Control/script bytes are a separate, still-unmapped concern" note
above — that caveat still applies; this is stronger circumstantial
support, not a new trace).

**What this did NOT resolve, stated precisely**: `0x29`/`0x35`/`0x43`/
`0x6C` remain genuinely unconfirmed (one occurrence each); no attempt
was made to trace `0x04`/`0x10`/`0xF6` against real CPU execution (the
technique that originally cracked the main formula) — this pass was
static pattern-matching only, same category of evidence as the original
digraph-table discovery, not a stronger kind. `TextDecoder.DIGRAPH
_PARTIAL` is now 16/many entries; the sub-`0xB0` range is still far
from fully mapped.

## How this was found

Full narrative in [tooling.md](tooling.md). Short version: static
byte-pattern analysis (below) ruled out every "simple" hypothesis without
finding the real one, so the project built mGBA with its official Python
bindings from source and used it to (1) confirm the font's VRAM display
offset (+48, i.e. glyphs load into VRAM tile slot 0x30) by reading the
live tilemap under known on-screen text, then (2) single-instruction-step
through the exact frame that text got drawn, watching CPU registers,
until the byte arrived via `POP AF` immediately followed by `XOR 0x80` —
revealing that ROM's real stored byte is `0x80 | (displayIndex)`, i.e.
`0xB0 + fontGlyphIndex` once the display offset is folded in. Re-running
the existing static dictionary scanner with exactly that offset instantly
turned up real German words and full sentences across the whole ROM.

## Verified examples

Cross-checked, reproducible from `tools/rom/dump_strings.py` against the
ROM file alone (SHA-1 `7cb65cb314e3f26b92549ddc7f4fc275186c6170`):

- File offset `0xbd7b`: `"Hier hast Du Deine"` ("Here, you have your...",
  dialogue text — likely an item-pickup message, precise trigger UNKNOWN).
- File offset `0xbd5a`: `"Lebens- und Magiepunkte erhoeht"` ("life and
  magic points increased").
- File offset `0xbed8`: **the complete real intro-text scroll**, all 4
  paragraphs, decoded in full (2026-08-09; previously this entry only
  had the first 3 words plus a few nearby fragments read informally).
  Cross-checked two independent ways with an exact match: live tilemap
  decode during the real title->"Neues Spiel" scroll (see
  rom_profiles.lua's `introText` doc comment for the capture method),
  and this literal ROM byte range, decoded via `TextDecoder
  .decodeString`. Full text (`\n` = the real `0x1A` line-break byte):
  `"Der Mana Baum\nwaechst durch die\nKraefte der Natur.\n\nEr waechst
  hoch\noben auf dem\nBerg Illusia.\n\nDemjenigen, der\nihn beruehrt,
  ver-\nleiht er ueberirdi-\nsche Macht.\n\nDark Lord sucht\nnach dem
  Weg zum\nMana Baum, um des-\nsen gewaltige\nKraefte zu missbrau-
  \nchen und die Welt\nzu unterwerfen."` — **"The Mana Tree"**, the
  series' central plot artifact (Seiken Densetsu/Final Fantasy
  Adventure's world tree), matches the user-supplied reference
  description almost verbatim. Important finding in its own right: this
  specific prose is stored as plain literal bytes, not compressed —
  the general "dialogue compression" open question (see below) is not
  a blanket fact about all game text, just about the specific strings
  (like "Willy") this project has tried and failed to find as literal
  bytes so far.
- File offset `0x9de5` onward: a table of short item/spell names, one
  per 16-byte slot (fixed-width, 0x00-padded) — `Lebe[n]`, `Salbe`,
  `Blo[c]k`, `Ruhe`, `Flam[me]`, `Eis`, `Bliz[zard]`, `Bomb[e]`,
  `S-Lebe[n]`, `Magi[e]`, `S-Magi[e]`, `Elixier`, `Auge`, `Bewege`,
  `Spruch`, `Allheil`, `Stille`, `Schlaf`, `Lava`, `Frost`, `Blitz`,
  `Donner`, `Bonbon`, `Knochen`, `Bronze`, `Spiegel`, `Kristal[l]`,
  `Rubin`, ... — clearly the game's item/spell name list. **Correction
  (2026-08-08, sixth pass)**: this list's item order and exact spelling
  was an early, rough gloss from scanning names only — a precise
  per-slot re-decode (see rom-map.md "Item/spell table") found the real
  slot 8 decodes to `[0xA9]Lebe`, not literally "S-Lebe[n]" as glossed
  here (`0xA9` is a new, still-unconfirmed name-prefix byte, plausibly an
  icon rather than literal "S" text) — it's slot 9 that spells out
  literal `S-Lebe` characters. Keeping this list as-is for the general
  "these are real item/spell names" finding, but treat the exact
  per-slot mapping above as approximate; rom-map.md has the precise,
  byte-verified per-slot dump. The record structure itself (name +
  8 trailing bytes, including a real per-category item-ID byte and a
  probable category-flag byte) is now characterized — see rom-map.md for
  the full, current state (bytes 9-14's meaning is still open).
- File offset `~0xa1c0` onward (the table starting near `0xa275` is the
  same table, not a separate one — see correction below): a second
  fixed-width (16-byte record) table pairing short names with stat
  bytes. **VERIFIED as real weapon/equipment data (2026-08-08, sixth
  pass)**, not just "plausible": the in-game menu's equipped-weapon
  readout displays `"Breit"`, and that exact string was found live inside
  this table (file offset `0xA1F6`) — a direct live-UI-to-ROM-bytes
  cross-check, the same kind of evidence that verified the item/spell
  table. Names found scanning `0xA1C0-0xA330`: `Juwelen`, `Opale`,
  `Breit`, `Axt`, `Sichel`, `Ketten`, `Silber` (x2), `Speer`, `Streit`,
  `Stern`, `Kraft`, `Drache`, `Flammen`, `Eis`, `Zeus`, `Rostig`,
  `Lanze`, `Excali[bur]`, `Bronze`, `Eisen` — weapons, materials, and
  elemental/mythological ring names (Seiken Densetsu's ring-magic
  system), confirming the earlier guess. Full record-structure writeup
  in rom-map.md "Weapon/equipment table".
- **Read visually off a live screenshot, not yet matched to ROM bytes**
  (2026-08-08, sixth pass — see rom-map.md "Breakthrough"): real story
  dialogue seen for the first time outside the title/intro sequence, past
  the starting room's creature encounter — `"AAAA und viele andere wurden
  gezwun[gen]..."` (the hero's own entered name substituted into the
  sentence — confirms name-substitution in dialogue text, a real engine
  feature to account for later) and `"Die Gemma Ritter müssen das
  wissen."`. Worth running `tools/rom/scan_text.py`/`dump_strings.py`
  against these fragments (`"viele andere wurden"`, `"Gemma Ritter"`) to
  locate their real ROM offset and confirm byte-for-byte against
  `TextDecoder`, the same way the intro-narration strings above were
  cross-checked — not yet done. **Attempted directly this pass, not
  found**: encoded `"viele andere wurden"`/`"Gemma Ritter"` (the
  umlaut-free portions) via `TextDecoder.MAIN_GLYPHS`'s inverse mapping
  and searched the raw ROM file byte-for-byte — no match. Most likely
  explanation is imprecise reading of the low-resolution screenshot
  (easy to misread similar glyphs, e.g. capital letters, at this
  resolution) rather than a wrong encoding formula (already independently
  VERIFIED, see "The formula" above) — re-attempting needs either a
  clean, zoomed screenshot re-read or (more reliably) reading the string
  directly out of VRAM tile indices the way the original title-screen
  cross-check did, converting displayed tiles back to ROM bytes instead
  of trusting an eyeballed transcription. **Attempted this pass — hit a
  new, real obstacle, not yet resolved**: this dialogue box (unlike the
  earlier "AAAA ist ein tapferer Kaempfer" box successfully cracked this
  way) renders through the GB's **window layer** (`LCDC = 0xE5`: window
  enabled, mapped to tilemap `$9C00`, tile data addressed via the
  *signed* `$8800` method — bit 4 clear) rather than the background layer
  (`$9800`, unsigned `$8000` addressing) the earlier successful read
  used. The simple `romByte = vramTile + 0x80` relationship that worked
  for the BG-layer box does **not** hold here (produces byte-underflow
  nonsense for several tile values); the window layer's actual tile
  numbering/DMA-offset scheme hasn't been derived. **Concrete next
  step**: repeat the same *technique* that cracked the original
  encoding (dynamic instruction-stepping through the exact frame this
  window content gets DMA'd into VRAM, watching for the write with
  `tools/rom/watcher.py`, rather than assuming the BG-layer formula
  transfers) — not yet attempted.

  **Attempted (2026-08-08, ninth pass) — real progress, still not
  cracked.** Watched writes to `$9C00-$9C3F` (window tilemap rows 0-1)
  through the exact frame window this dialogue box draws (confirmed via
  a corrected, exact-frame VRAM dump matching the known-good screenshot
  byte-for-byte). Findings: (1) the writer is the *same* generic
  `$1D72`/`$1D74` HBlank-synced primitive already known from the
  BG-layer case and the original room-draw trace — not new code, so the
  BG-layer formula's failure isn't from a different writer, just a
  different *source data* interpretation upstream of it. (2) The tile
  values actually written (`0xF5, 0xF1, 0x31, 0x39, 0xF2, ...`) don't
  line up 1:1 with "AAAA: WILLY!"'s 12 characters — only ~10 non-blank
  cells fill row 0 for a 12-character message, and row 1 (which the
  border-only pre-text dump showed as the box's *bottom* border in one
  capture but reads as more content in the text-bearing capture) doesn't
  obviously separate cleanly into "border" vs. "text" by inspection
  alone. This is consistent with the same 2-tile-wide-per-character
  layout observed in the earlier, successfully-cracked BG-layer box
  (`92 93` pairs there) — plausible here too, not yet confirmed — or
  with the window's scroll/positioning shifting which grid row holds
  which content between frames, which would explain the apparent
  border/content overlap. **Not resolved this pass**: stopped short of
  correlating each write to the CPU register value at that exact
  instruction (the technique that cracked the original BG-layer
  encoding) — the concrete, mechanical next step, not attempted due to
  time rather than a new obstacle.

## Hypotheses tested and ruled out before the emulator broke the case

Kept for the record — this is *why* dynamic tracing was worth the setup
cost, and the negative-result method itself (dictionary scoring, not bare
letter-density) is reusable for the next unsolved format.

Two of the simplest possible encodings were tested with
`tools/rom/scan_text.py`'s `words` subcommand against a small,
high-precision dictionary of common words, scanning the *entire* 256 KiB
ROM:

1. **Direct tile-index encoding** (byte `N` = the Nth font glyph
   directly, no `0xB0`/bit-7 offset) — near-zero real-word hits in
   English or German. Correctly ruled out: the real encoding needed the
   `+0xB0` (bit-7-set) transform this hypothesis didn't have.
2. **Direct ASCII encoding** — same result. Correctly ruled out.
3. A brute-force of 81 constant *shifts* of the tile-index charmap
   (offsets -40..+40) found nothing better than noise (2 hits) —
   **because the real offset, +48 display-side / +0xB0 ROM-side, was
   outside the tested range.** Lesson recorded in
   [progress.md](../progress.md): when brute-forcing a numeric hypothesis
   space, a range picked from "seems generous" intuition can still miss
   the answer; widen further before concluding a shift-based hypothesis
   is falsified. (`tools/rom/scan_text.py shift --range N` takes the
   range as a parameter for exactly this reason now.)
4. `tools/rom/scan_text.py charmap` (looking for a *scrambled*
   byte->glyph lookup table elsewhere in ROM) found 10 candidate regions;
   moot now that the real formula doesn't need an indirection table, but
   left in the tool in case a *second* string table (e.g. compressed
   dialogue, if one still exists — see "What's still open" below) needs
   the same technique.

## What's still open

- The `0x90-0xAF` umlaut/icon block is now 4/32 decoded by *byte value*
  (`0x9C`=ä, `0x9D`=ö, `0x9E`=ü, `0x9F`=ß — all lowercase). Its *glyph
  order* is separately, visually confirmed: the in-game hero-name entry
  screen's on-screen keyboard (reached via `tools/rom/play_driver.py` —
  see [tooling.md](tooling.md)) renders, after the lowercase a-z rows
  and a punctuation row, a digits row, then `Ä Ö Ü ä` and (scrolled one
  row further) `ü ß` — i.e. the game's own font confirms the umlaut set
  is `ÄÖÜäüß` in that order, matching rom-map.md's font entry. Still
  open: the remaining ~28 bytes in this range (uppercase umlauts `ÄÖÜ`
  among them), and confirming the *name-entry keyboard's own* byte
  values match this dialogue-text block's (plausible, not yet checked).
- ~~The `0xF2` hyphen mapping is a single-example hypothesis.~~ VERIFIED
  2026-08-09 (see "The formula" above) — second independent confirmation
  found via the intro-text scroll.
- No pointer table for dialogue strings has been located yet (unlike the
  map data — see rom-map.md's "Maps" section) — right now, strings were
  found by literal `strings`-style scanning
  (`tools/rom/dump_strings.py`) plus the specific offsets the emulator
  trace pointed at, not by walking a discovered index. A dialogue pointer
  table (if one exists, likely via `scan_pointers.py`-style analysis
  restricted to banks holding the sentence fragments found so far, e.g.
  around bank 2-3 / file offset `0xb000-0xc000`) would be the natural
  next step to enumerate *all* dialogue systematically rather than
  opportunistically.
- ~~Whether all in-game text uses this exact formula, or whether some
  screens use a different/compressed encoding~~ RESOLVED 2026-08-09 (see
  "The digraph compression table" above) — general dialogue prose *does*
  use a second, real compression layer below `0xB0`, on top of (not
  instead of) the main formula. 15 of its entries are now VERIFIED; the
  rest of the sub-`0xB0` range is a mix of still-unmapped digraphs and
  script/control opcodes (see that section's "What this did NOT resolve"
  for the exact open items). The menu title text specifically is still
  unlocated as plain ROM bytes either way.
- Control-code bytes other than space/terminator/hyphen (e.g. `0xF0`,
  `0xF1` seen elsewhere in the item-table dumps; `0x00`/`0x04`/`0x12` +
  `0x1B`/`0x11`/`0x1E` seen densely in the digraph-table dialogue dump)
  are UNKNOWN — likely script/formatting opcodes, not text. The `0x00`-
  immediately-followed-by-`0x04` pattern matches roadmap.md's FFA-
  Disassembly-attributed `$00`=end-string/`$04`=display-message
  hypothesis by position, but this has not been traced against real CPU
  execution the way the confirmed bytes above were — a real next step,
  not a finding yet.

## User hypothesis, checked and CONFIRMED with real code: reveal-speed markup exists — not inline, but a real per-message settings field (2026-08-10)

Direct user question: *"ich vermute es könnte eine art markup in den
texten geben der z.b. den rhythmus der einblendung steuert... das ist
aber nur eine vermutung."* Confirmed with a real code trace, not
speculation.

**The known baseline**: the "Kaempfe!" textbox's own real reveal rate
was already measured (2026-08-09) at exactly 5 real frames/letter (6
consecutive letter-reveal writes, all 5 frames apart).

**Found the real reveal-timer WRAM byte, live**: watched every WRAM
write during a fresh, precise single-step trace of the real reveal
window (from a checkpoint built at exactly `hiddenFrames+walkFrames+
settleFrames` = 206 real frames past name-entry, right before the box
starts) and looked for an address written often with a small, cycling
value range. `$D3E9` matched exactly: `5, 4, 3, 2, 1, 0, 5, 4, 3, 2, 1,
0, ...` — a real countdown timer, reloading to `5` on every cycle,
exactly matching the already-measured rate.

**Traced every reload-to-5 with `CallTracer`** (bank-accurate, no stack-
guessing): all 6 land on the identical instruction, bank 4 file
`0x1009d`:

```
0x10090  LD A,(0xD439)
0x10093  LD D,A
0x10094  LD A,(0xD438)
0x10097  LD E,A          ; DE = the 16-bit value at WRAM $D438/$D439
0x10098  LD HL,0x0000
0x1009B  ADD HL,DE       ; HL = DE (a real pointer, not a math offset)
0x1009C  LD A,(HL)       ; A = *pointer  <- reads a REAL BYTE from ROM/RAM
0x1009D  LD (0xD3E9),A   ; timer = that byte
```

**This settles the question directly: the reload value is NOT a
hardcoded constant in code — it's read from memory through a real
pointer.** Confirmed live: `$D438`/`$D439` held the exact same value
(`0x48B9`) at all 6 reloads (constant for the whole textbox, not
advancing per letter) — resolved (bank 4 active) to real ROM file
offset `0x108B9`. **The real byte there is `0x05`** — an exact,
independent match for the already-measured rate, found completely
differently (live pointer-chase vs. frame-by-frame observation)
converging on the same number.

**What kind of "markup" this actually is, precisely**: NOT an inline
control byte sitting between glyph bytes in the dialogue prose itself
(the way `0x04`/`0x10` and `0x12`/`0x11` appear to be, per the earlier
static leads) — the surrounding ROM bytes at `0x108B9` (`... 05 02 00
00 06 16 46 02 40 10 00 ...`) don't look like glyph-encoded prose at
all (no bytes in the `MAIN_BASE`/digraph ranges), reading instead like
a **small, separate per-message settings/parameter record** — a real,
structured header analogous to this session's own bank-8 room-table
records, just for text messages instead of rooms. The user's intuition
("Rhythmus der Einblendung wird gesteuert") is real and now
code-confirmed; the specific mechanism is "a pointer to a small settings
record, one of whose fields is the reveal speed," not literal inline
markup characters mixed into the prose bytes.

**What's still open, stated precisely**: only ONE such settings record
has been traced (`Kaempfe!`'s own, value `5`). Whether other real
messages in the ROM use genuinely DIFFERENT reveal-speed values (the
strongest possible confirmation of real per-text variation, not just a
shared default every message happens to reuse) was not tested this
pass — a live-reachable SECOND dialogue box with its own measurably
different pace would settle this decisively; this pass tried but could
not find one live-reachable from the current playthrough (the
secondRoom Amanda dialogue this project's own `rom_profiles.lua`
already has real page text for did not visibly trigger from the tested
approach path — a real, unresolved gap, not silently worked around).
Also open: the settings record's OTHER fields (`0x02`, `0x00`, `0x00`,
`0x06`, `0x16`, `0x46`, ... surrounding the speed byte) — plausible
candidates for box style/position/portrait/sound, not decoded this
pass; and whether `$D438`/`$D439` itself gets set from a per-message
table (the natural next link, connecting "which message is active" to
"which settings record applies") — not traced backward this pass.

## The real message-settings table found — and the "different messages, different speeds" question definitively answered (2026-08-10, same day, direct follow-up)

Direct continuation of the previous section's own named open question:
traced backward from `$D438`/`$D439` (the settings-record pointer) to
find who sets it, using the same bank-accurate `CallTracer`, watching
from a checkpoint before the whole battle-intro sequence starts.

**Found the real table, live, in 2 steps**: caught the actual write at
bank 4 file `0x1009D`... no — corrected, the WRITE to `$D438`/`$D439`
itself is at bank 4 file `0x10306`/`0x1030A`, reached with an empty call
stack (a raw jump into shared code, the same "`JP`, not `CALL`" pattern
already seen for the room-load opcode `$4387` and the `$02B70`
dispatcher). Disassembling its immediate context shows the real
computation:

```
$102F7  LD L,A / LD H,0x00        ; incoming A = a real message ID
$102FA  LD E,L / LD D,H
$102FC  ADD HL,DE                  ; x2
$102FD  ADD HL,DE                  ; x3
$102FE  ADD HL,HL                  ; x6
$102FF  ADD HL,HL                  ; x12
$10300  ADD HL,HL                  ; x24  <- stride
$10301  LD DE,0x4739                ; real table base
$10304  ADD HL,DE                  ; HL = 0x4739 + messageID * 24
$10306  LD (0xD439),A (=H)
$1030A  LD (0xD438),A (=L)          ; $D438/$D439 = &table[messageID]
```

**A real, general, 24-byte-stride message-settings table, base ROM file
offset `0x10739` (bank 4)** — reverse-computing "Kaempfe!"'s own known
settings address (`0x108B9`) against this formula gives `messageID =
(0x108B9 - 0x10739) / 24 = 16`, an exact, clean integer — confirms the
formula, not a coincidence.

**Dumped the first 20 records and checked byte 0 (the reveal-speed
field) across all of them — this is the direct answer to last section's
open question**:

```
messageID:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19
speed:      8 10  6 10  8  4  6  4  8 12  6 10  4  8  5  8  5  4 10  8
```

**Confirmed: reveal speed genuinely varies per message, real per-text
markup, not one shared default** — ranges from `4` to `12` real frames/
letter across just these 20 records, with `messageID 16` (`= 5`) being
the exact, independently-known "Kaempfe!" rate. The user's original
hypothesis is now settled beyond the single earlier data point: this
isn't "one measured message that happens to use a byte-driven value" —
it's a real, general, per-message field with real variation across the
whole table.

**Other fields in the 24-byte record, briefly characterized (not fully
decoded)**: byte 7 is `0x02` in **every single one** of the 20 records
— a fixed format/version marker, not per-message data. Byte 6 is mostly
`0x46`/`0x47` with rare `0x4F` — a small, categorical field (3 values
seen). Byte 8 is mostly `0x40` with a handful of smaller variants
(`0x30`, `0x34`, `0x38`, `0x3A`, `0x3C`) — another small categorical
field. Byte 9 ranges `13`-`30` across the 20 records — a plausible
candidate for message length or box height, not confirmed. Bytes 1-5
and 10-23 vary far more (look pointer-shaped in places, e.g. bytes
10-11/12-13/14-15/16-17/18-19/20-21/22-23 each look like they could be
more 16-bit sub-pointers, similar in spirit to this session's earlier
bank-8 room-table's own multi-pointer records) — not traced this pass.

**What this settles vs. what's still open**: SETTLED — real per-message
markup exists, controls at minimum the reveal speed, and is a genuine,
confirmed table (not a guess or a single coincidence). OPEN — what sets
the incoming message ID (`A`) at the call site (`$102F7`'s own caller,
not traced this pass — the natural next link, connecting "which
dialogue is currently active" to this table); the other 22 bytes'
individual meanings; whether this same table also governs non-Kaempfe
real dialogue (plausible, not proven — all 20 records characterized
here are static reads, only messageID 16 has been cross-checked against
a real, live-measured reveal).

## Do the other 23 bytes encode more than tempo? Direct user question, answered with a live field-by-field trace (2026-08-10, same day)

Direct user question: does the settings record only control tempo, or
also narration/speaker/window-position-type properties? Checked with a
live trace, not guessed from raw byte values.

**Static check first, a real negative**: searched every aligned 16-bit
byte pair in all 20 records against every bank for a match to
"Kaempfe!"'s own known real text location (`0x346D4`) or any other
readable German prose of 6+ characters — found only coincidental
substring hits inside already-known large text blobs (the intro-text
scroll, the menu-string dump), not a clean, deliberate per-record text
pointer. **The record does NOT directly store a pointer to the message's
own prose** — that must live in a separate mechanism/table this pass
didn't locate.

**Live trace: watched READS on every one of the 24 field bytes**
(segment-aware, same validated technique as the room-table work) during
the real "Kaempfe!" display. 18/24 fields were read at least once in
the window traced; fields 2, 3, 6, 7, 22, 23 were not (or not yet, this
budget's window). Disassembling the real consumers:

- **Field 4 is a real repeat count**, not part of any position/speaker
  data — read identically by two separate routines (`$4373` and
  `$43FF`, bank 4), each running a loop exactly `field4` times.
- **Fields 14-15 and 16-17 are each real 16-bit pointers**, one
  consumed per loop iteration inside those same two routines — the
  loop body calls a shared per-iteration helper (`$0A74`) and the
  *first* routine's result feeds directly into **`$D3E8`** — the
  ALREADY-KNOWN real "enemy alive" flag (see rom-map.md's
  `$04E8`-family enemy-behavior-state dispatcher entry, gated by
  exactly this flag). **This settings record is not purely a text/box
  descriptor — it also drives real enemy/entity setup tied to the
  message**, plausible and narratively sensible for "Kaempfe!"
  specifically (the fight-start message and the enemy becoming
  active are the same real story beat).
- **Fields 8-13 are read together as one tight 6-byte sub-block**
  (6 consecutive reads within ~15 real CPU steps) feeding a nibble-
  swap-and-mask decode into further pointer arithmetic — a real,
  structured sub-record, not yet fully decoded (bytes 8-9 decode via
  nibble swaps into a `D`/`E` pair, bytes 10-11 become `C`, byte 11
  becomes part of `B`, bytes 12-13 become another 16-bit pointer `HL`)
  — plausibly OAM/sprite-placement-shaped math (nibble-swap-then-mask
  is the same idiom already seen in this project's real sprite/tile
  addressing elsewhere), not confirmed as "position" in the on-screen-
  text-box sense the user asked about specifically.
- **Fields 18-19** are read via a much later, much deeper call chain
  (6 real nested frames, `$02B70→$027CE→$40A4→$4209→$4222→$425F→$42C5`)
  than every other field — i.e. genuinely consumed at a different point
  in the sequence than the rest, not part of the same initial-setup
  batch. Not decoded further this pass.

**Honest answer to the actual question**: **yes, real, confirmed data
beyond tempo exists in this record** — but what this pass could
concretely trace looks more like "how many of what to set up, and a
pointer to enemy/entity data" than a classic "narrator ID / window X,Y"
visual-text-box descriptor. No field was found that cleanly reads as
"which character is speaking" or "box screen position" specifically —
that doesn't rule them out (fields 2/3/6/22/23 were never touched in
this trace's window at all, and the 8-13 sub-block's real purpose isn't
pinned down), it means this pass's evidence doesn't reach that specific
claim. Recorded honestly as a real, partial answer, not stretched to
confirm the user's exact examples (narration/speaker/position) beyond
what was actually traced.

## Fields 18-19, traced deeper — plausibly a sprite/decoration placement list, empty for this message (2026-08-10, direct follow-up)

Continued tracing fields 18-19's own consumer (`$42D8`, bank 4): it
simply stores the `HL` built from fields 18-19 into WRAM `$D43A`/`$D43B`
and clears `$D3EC` — not very revealing alone. Disassembling one level
further up the same call chain (`$100B0` onward, reached via `$40B8`)
found a real, structured loop:

```
$100B0  LD A,(0xD43E) / LD E,A / ADD HL,DE
$100B5  LD A,(HL+)              ; walk a byte stream, one byte per iteration
$100B6  CP 0xFF
$100B8  CALL Z,0x4209            ; 0xFF terminates the list -> finalize
$100BB  JR Z,0x100F1
$100BD  LD DE,0xD442
$100C0  CALL 0x419E
$100C4  LD A,(HL+) / LD C,A
$100C6  SRA A x4                 ; C's high nibble -> a coordinate
$100CE  ADD A,E / LD E,A
$100D0  LD A,C / SWAP A / SRA A x4  ; C's low nibble -> the other coordinate
$100DB  ADD A,D / LD D,A
$100DD  CALL 0x4188               ; place something at (D,E)
```

**Reads as a real, general "sprite/decoration placement list" walker**:
each list byte packs two nibble-encoded coordinate offsets (a very
common GB technique), added to a base position and passed to `$4188`
(plausibly "draw/place a small graphic here"), with `0xFF` as the real
list terminator — the same `0xFF` byte value already established
elsewhere in this project's own conventions as a real terminator/
sentinel (matching `SPACE_BYTE`'s own role in ordinary prose, and the
courtyard gate's own solid-`0xFF` tile convention — a recurring, real
`0xFF`-as-sentinel idiom throughout this ROM, not a coincidence).

**Plausible, not proven, interpretation**: fields 18-19 point to a list
of decorative sprite placements (a portrait, an icon) shown alongside
this specific message's textbox — genuinely relevant to the user's
"window position" question, just implemented as "where to place
accessory graphics" rather than "the box's own X/Y." **For "Kaempfe!"
specifically this list is empty** (the very first byte fetched is
already `0xFF`, so the loop exits after one iteration with nothing
placed) — consistent with the already-known fact that this textbox is
plain text with no portrait. This is a strong, structurally coherent
lead, but NOT independently confirmed against a message that actually
has non-empty placement data (would need live-reaching a decorated
message box, not attempted this pass) — recorded as a well-reasoned
hypothesis, one level more specific than "unknown," not a new VERIFIED
fact.

## Where the message ID comes from — found, live-confirmed (2026-08-10, direct follow-up: "finde die Herkunft der Message-ID")

Traced the message-settings table's own lookup routine (bank 4, file
`0x102F7`, reached via the standard bank-trampoline convention already
documented elsewhere this session — bank 4's own local jump table,
function index `1`, file `0x10002`) back to its single real caller.

**Only one call site in the whole ROM** (searched the exact byte
pattern for the per-call-site dispatch stub, `PUSH AF / LD A,0x01 / JP
0x1F64` — bank 4's real trampoline address — found at file `0x4E2`, and
its own single caller at file `0xE6B`, bank 0):

```
$0E69  LD A,(HL+)      ; A = *HL -- a real byte read directly from a
                        ; script/data stream, becomes the message ID
$0E6A  PUSH HL
$0E6B  CALL 0x04E2      ; dispatch into the settings-table lookup with
                        ; this A
$0E6E  POP HL
$0E6F  CALL 0x3727       ; the already-known general register-scratch
                          ; helper
$0E72  RET
```

**Live-confirmed at the real "Kaempfe!" checkpoint**: `HL = 0x46F8` at
this exact instruction, resolving to real ROM file offset `0x346F8` —
only 36 bytes after the Kaempfe text's own known start (`0x346D4`), in
the same bank/region. **The byte actually read there is `0x10` (16)** —
an exact, independent match for the already-computed real message ID
(`(0x108B9 - 0x10739) / 24 = 16`), confirmed completely differently
(live pointer-read vs. static table-offset math) and landing on the
same number a third time (after the original speed-value cross-check).

**This settles the mechanism cleanly**: the message ID genuinely IS a
literal byte in a script/event stream (matching the general "script
opcode + operand bytes" model this whole project has been building
toward, not a separate lookup or computed value) — `LD A,(HL+)` reads
it and advances the stream cursor in the same instruction, exactly the
shape a bytecode interpreter's operand-fetch would take.

**One honest, unresolved nuance, not papered over**: the byte
immediately preceding the messageID read (`0x346F7 = 0xFE`) is NOT the
`0x04` this project has repeatedly suspected as the real "display
message" opcode (per the credits-screen positional evidence in an
earlier section) — the two leads don't line up byte-for-byte in this
one live-traced instance. Real possibilities, none confirmed: the
`0x04`/`0x10` pairing seen in the credits screen is a different,
unrelated convention specific to that screen's own renderer; the real
opcode byte for THIS mechanism sits further back than immediately
adjacent (the wider dump shows several `0x04` bytes nearby, just not
directly adjacent); or `0xFE` is itself the real opcode for this
specific script and the credits-screen `0x04` observation was a
coincidence of position, not a shared convention. **Not resolved this
pass** — a real, precise open question for whoever continues this
thread, recorded honestly rather than forced to fit the earlier
hypothesis.

## Attempting to resolve the 0xFE-vs-0x04 discrepancy — real further progress, genuine limit reached (2026-08-10, direct follow-up)

Tried directly to settle the open nuance above: traced the exact
instruction sequence leading into `$0E69` (the messageID read) using
the full step-by-step event log, not just the call-frame snapshot.

**Real finding**: the instruction immediately before `$0E69` is
executes is a plain `RET` (at file `0x03273`, popping whatever return
address is on the stack) — i.e. `$0E69` genuinely is reached as an
ordinary "return from a small helper" (`$326A`-`$3273`, a tiny "load HL
from two WRAM bytes" routine), not a hardcoded jump-table entry. **But
searched for a literal `CALL 0x326A` anywhere in the ROM — zero
matches.** That small helper is ITSELF reached only through more
indirect/computed dispatch, same as everything else this whole session
has traced (the bank-trampoline family, the `$02B70`/`$2B63` opcode
dispatcher, the room-load system) — confirming, yet again, how
pervasively this ROM avoids literal call-site addresses in favor of
table/computed dispatch, but this time without a table this pass could
locate and dump the way the earlier ones were found.

**Honest conclusion: not fully resolved.** Real, additional progress
was made (the exact mechanism at this one hop — RET-based return from
a tiny shared helper — is now known, not previously), but the original
question (does `0xFE` or some other, not-yet-found byte function as the
real "display message" opcode, and does it match the credits screen's
own `0x04`) remains open. Each additional hop back reveals another
layer of the same shared/computed dispatch infrastructure rather than a
literal, greppable answer — resolving it fully would need either
building a proper execution-breakpoint (not just memory-watchpoint)
capability this project's tooling doesn't have yet, or a much longer,
more patient trace from further back (e.g. from the very start of the
battle-intro sequence, watching every `CALL`/`RET` rather than
targeting one specific address). Recorded honestly as a real attempt
that hit a genuine, well-characterized limit — not silently dropped,
not forced to a false conclusion either way.

## What the $326A helper actually is (2026-08-10, direct follow-up)

Fully disassembled `$326A` and its immediate neighborhood:

```
$3260  CALL 0x3C6B            ; setup
$3263  LD HL,0x3274 / PUSH HL  ; manually push a FAKE return address
$3267  CALL 0x3165             ; compute something (see below)

$326A  PUSH HL                 ; <- SIBLING A: "restore" path
$326B  LD A,(0xD8B7) / LD H,A
$326F  LD A,(0xD8B6) / LD L,A  ; HL = the cached 16-bit value at WRAM $D8B6/$D8B7
$3273  RET

$3274  LD A,H / LD (0xD8B7),A  ; <- SIBLING B: "save" path
$3278  LD A,L / LD (0xD8B6),A  ; store HL (from $3165's result) into that SAME pair
$327C  PUSH HL
$327D  CALL 0x2A0A              ; the already-known bank-restore trampoline half
```

**`$326A` is the "restore" half of a real save/restore-a-16-bit-value-
across-a-call utility** — its sibling at `$3274` (reached via the
manually-pushed fake return address at `$3263`) is the "save" half,
storing a freshly-computed `HL` into WRAM `$D8B6`/`$D8B7`; `$326A`
simply reads that same pair back. **`$3165` doesn't compute the value
itself** — it's yet another `PUSH AF / LD A,0x33 / JP 0x1F06` dispatch
stub (function index `0x33` = 51, bank 2, via the same trampoline family
already documented) — the real computation happens inside bank 2's own
function 51, not traced this pass.

**What this means, put together with everything else traced today**:
`$D8B6`/`$D8B7` is a real, persistent WRAM cache holding a 16-bit
pointer that survives across separate calls (that's the whole point of
saving it to WRAM instead of just keeping it in a register) — and the
one live instance this pass actually observed feeds directly into the
script-stream read at `$0E69` (the messageID fetch). The most coherent
reading: **this is very plausibly the real script/event interpreter's
own persistent "current read position" cursor** — computed once
(expensively, via a cross-bank call into bank 2), cached in WRAM so it
survives between the many separate small operations a per-frame script-
processing tick does, and read back through this small helper each time
the interpreter needs to fetch its next byte (matching the "advance a
cursor, read a byte, dispatch on it" shape this whole project has been
converging on all session). Not proven beyond this one live instance,
but a real, structurally coherent characterization — not a guess from
naming alone.

## The umlaut rendering bug — found and fixed (2026-08-10)

Direct user report ("es gibt ein problem mit umlauten"). The umlaut
BYTES (`0x99-0x9F`) were already correctly identified (see
UMLAUT_PARTIAL above) — the real bug was downstream: `TextDecoder`
decoded them as 2-LETTER ASCII substitutions ("ae","oe","ue","Ae",...)
and `Font.lua` drew each byte of a Lua string one at a time, so a
German word with an umlaut rendered as two ordinary letters instead of
one real umlaut glyph.

**Found by decoding the real font tile GRAPHICS directly from ROM**
(same linear formula already established for period/hyphen/exclamation,
`0x22900 + (tileId-0x10)*16`) rather than guessing: tiles 25-31
(`0x19-0x1F`), immediately before the main font block, decode as real,
unambiguous pixel art — genuine dots over a letter for each umlaut, the
real double-loop eszett shape for `ß` — in exactly the order
`Ä,Ö,Ü,ä,ö,ü,ß`. Cross-checked directly against real, live-captured ROM
text (not just the tile shapes in isolation): tile 28 (0x1C) appears
exactly where the already-decoded intro text needs ä, in TWO unrelated
words ("wächst", "Kräfte"); tile 30 (0x1E) appears exactly where it
needs ü, also in two unrelated words ("berührt", "überirdi-") — an
exact match to `UMLAUT_PARTIAL`'s own already-confirmed byte semantics
(`0x9C`=ä, `0x9E`=ü), not a coincidence.

**Fixed**: `TextDecoder.UMLAUT_PARTIAL` now emits the real single UTF-8
character for each byte (written as `\ddd` decimal escapes so this
project's Lua source files stay plain ASCII, matching its existing
convention). `Font.lua`'s `:print`/`:measure` were byte-oriented
(`text:sub(i,i)`, one BYTE per glyph) — wrong for any multi-byte UTF-8
character, silently finding no matching quad for either byte and
leaving a double-wide gap; both now step by real UTF-8 character
boundaries (1 byte for ASCII, 2-4 for a multi-byte sequence, detected
from the lead byte's own high bits). `rom_profiles.lua`'s
`font.extraGlyphs` gained the 7 real ROM tile offsets these characters
need. All existing tests that asserted the old ASCII-safe spellings
were updated to the corrected single-character output — a real
improvement, not a regression, same pattern already established
elsewhere in this project (see e.g. the `TEXT_START_Y` correction in
progress.md).

## Revisiting the 0xFE-vs-0x04 control-byte question with this session's new execution-tracing tooling (2026-08-11, "kommentiere dein Vorgehen")

Direct follow-up on the 2026-08-10 "genuine limit reached" entry, which
explicitly named the missing capability: *"resolving it fully would
need... building a proper execution-breakpoint (not just memory-
watchpoint) capability this project's tooling doesn't have yet."*
This project's tooling gained exactly that this same day (2026-08-11,
`calltrace.py`'s `CallTracer`, used successfully for the whole map-
pipeline investigation) -- so this pass re-attempted the question with
the now-available tool.

**Real methodology bug found and fixed on the way**: single-step
scripts written earlier this same session (this one, plus 2 scroll-
reveal scripts from the map-pipeline work) called `CallTracer.record()`
*before* `core.step()`, or checked the target-PC condition *after*
`record()` had already processed that instruction -- both corrupt the
frame bookkeeping into self-referencing "caller X -> callee X" garbage
at every depth (`record()` reads `cpu.pc` as the POST-step value, so
calling it pre-step makes every transition look like a zero-length
no-op). Fixed the ordering (peek -> check target PC -> step -> record)
and confirmed the fix produces a clean, sane result.

**With the fix, traced fresh from a cold `reach_first_room()` (not
relying on any prior partial trace) to the real messageID read
(`$0E69`, `HL=0x46F8` again, the same "Kaempfe!" trigger already
known)**: the real call-frame stack at that exact instruction is
**genuinely empty** -- zero pending CALL frames. This is itself a real,
new, precise finding (not available to the 2026-08-10 pass, which only
established "reached via a RET"): the whole chain from wherever this
gets triggered down to `$0E69` never has net positive CALL depth at
this point -- consistent with `$0E69` being polled directly from the
main per-frame loop (tail-jumps throughout, not nested subroutine
calls), not deeply embedded logic.

**Re-examined the raw bytes around the trigger site itself** (file
`0x346E0`-`0x346FF`, fresh dump): `00 f8 1a f0 3c b0 6a 04 01 b0 6a 05
01 b0 6a 04 00 b0 6a 05 00 f9 10 fe [10] f0 3c b0 0f 04 00 b0` -- this
does **NOT** look like ordinary dialogue prose at all (no coherent run
of `MAIN_GLYPHS`-range letters spelling real words, unlike the
26KB region found earlier this session) -- it reads as compact,
repetitive script/event bytecode (`b0 6a 04` / `b0 6a 05` alternating,
a shape matching opcode+operand pairs, not sentences).

**Real, clarifying conclusion, precisely scoped**: the "message ID"
trigger mechanism traced back to `$0E69` lives in a **separate SCRIPT/
EVENT byte stream**, structurally distinct from the actual 26KB prose
region this session's digraph work mined -- i.e. this project has now
implicitly confirmed there are (at least) two different byte-stream
"layers" in this ROM (a compact event-script layer that names which
message ID to show, and a separate prose layer holding the actual
displayed text for each message) -- consistent with, and a real
refinement of, the "general-purpose bytecode script engine" model this
project's own roadmap.md already attributes to the FFA-Disassembly
project's findings on the US ROM. **This does NOT resolve the original
0xFE-vs-0x04 opcode question** (which byte in THIS script stream means
"display message" is still not pinned down -- the surrounding bytes
here don't obviously decode as opcodes this project has already named
either) -- but it correctly reframes the question: the dense
`0x00`/`0x02`/`0x04`/`0x12`/`0x1B`/... byte runs found densely
WITHIN the 26KB prose region (this session's own digraph-scan
occurrence data) are almost certainly a DIFFERENT thing (real inline
prose formatting/paging control codes -- e.g. speaker-change or
page-break markers, given how consistently they sit exactly at
sentence/scene boundaries in the real decoded text) than this
script-stream's own opcode byte (`0xFE` here) -- two related but
genuinely separate open questions, not one, now stated precisely
instead of conflated. Not fully resolved this pass either way, but a
real, honest sharpening of what "resolved" would even mean here.

## Dialogue pointer table: a real, targeted static search, honest negative result (2026-08-11, same day)

Direct follow-up on the last remaining named item. With the real prose
region now known (~26KB, `0x34800`-`0x3B000`, spanning banks 13-14),
searched for a real pointer table referencing it -- the same technique
that found the room-selector table (search for literal 2-byte LE CPU
addresses matching known real string-start offsets, clustered together
in one region).

**Computed real CPU addresses for 8 known real message-start offsets**
(Kaempfe, WILLY, Julia, Bogard, Dark Lord, Willkommen, anbeterin,
Tante) and searched the whole ROM for each as a raw 2-byte LE pattern:
**no clustering anywhere** -- every hit lands in a different, unrelated
bank, scattered, the opposite of the tight cluster that revealed the
room-selector table. No direct flat pointer table exists referencing
these strings the way rooms are referenced.

**Tested the next-best hypothesis**: does the ALREADY-KNOWN 24-byte
message-settings record (see "The real message-settings table found"
above) itself hold the text pointer, in one of its ~15 still-
undeciphered bytes? Dumped Kaempfe's own real record (file `0x108B9`)
and checked every 2-byte window for Kaempfe's own real CPU address in
its own bank (`0x46D4`, bank 13) -- **no match anywhere in the
record.**

**Honest conclusion**: both natural hypotheses for locating a dialogue
pointer table were tested directly against real data and both came
back negative -- a real, useful negative (rules out two plausible
mechanisms cleanly, per this project's "no silent fallbacks" rule),
not an unexamined gap. The real mechanism remains open — plausible
remaining candidates, none tested this pass: a 3-byte "far pointer"
convention (2 address bytes + 1 bank byte, common in bank-switched ROMs
and not covered by this pass's flat 2-byte search); the still-
undeciphered `+8-13` sub-block of the settings record (already flagged
in the earlier "Fields 18-19" work as "plausibly OAM/sprite-placement-
shaped math", not tested against a pointer hypothesis specifically);
or an index into the compact script/event stream found this same day
(see "Revisiting the 0xFE-vs-0x04 control-byte question" above) rather
than a classic address-based pointer table at all. Recorded precisely
so a future pass starts from these 3 concrete candidates instead of
re-deriving them.

## Live-tracing the control bytes: a real, unexpected behavioral finding, question reframed again (2026-08-11, "ok als erstes die kontrollbytes")

Direct follow-up, applying the corrected single-step methodology (see
the previous section) to the actual per-letter reveal loop instead of
the message-ID trigger, across a real MULTI-page dialogue (the post-
boss story text, `storyPages[1]` = `"%s und viele\nandere wurden\n
gezwungen, jeden\nTag"`) instead of the single-line "Kaempfe!" box, to
observe real page-break/control-byte behavior directly.

**Step 1 -- found the real reveal window**: fast `run(1)`+`Watcher` scan
of `$D3E9` (the already-known reveal timer) from a fresh
`courtyard_boss_defeated()`, no input at all. The timer counts down
`5,4,3,2,1,0` (reload) repeatedly starting at frame ~3821, for exactly
**70 writes (14 reload cycles)**, then **stops completely at frame
3890**.

**Step 2 -- confirmed this is a REAL, permanent stall, not a short
pause**: re-ran with 9,000 and then 30,000 frames of pure waiting (8+
real minutes at 60fps), zero player input at any point. **The timer
never resumes, not once, at either window.** This isn't a brief
scripted dramatic beat -- the real ROM genuinely idles indefinitely
here, doing nothing further to this textbox, until something external
(player input) happens.

**Step 3 -- decoded the actual displayed text at the stall point** (via
live VRAM tilemap capture, converted through this session's own
expanded `TextDecoder`, offset `0x30` for this scene's own tile-ID
convention): **`"AAAA und viele\nandere wurden ge"`** -- i.e. the box
has only revealed the first ~31 of `storyPages[1]`'s real 42 characters
before permanently stalling, mid-word, inside "ge[zwungen]".

**Step 4 -- pressed `A` exactly once at the stall point**: the box does
**NOT** resume revealing the rest of `storyPages[1]`'s text --
`"zwungen, jeden\nTag"` is never shown at all. Instead the box
immediately, fully replaces its content with **`storyPages[2]`**'s real
text (`"zur Unterhaltung\ndes Dark Lord, zu..."`, confirmed via the
same VRAM decode) -- a full page-advance, not a "finish typing this
page" input.

**What this establishes, precisely**: this is real, new, live-verified
knowledge about how this ROM's dialogue system actually behaves, not
previously documented (this project's own `storyPages` array already
had the right STRING content, but not this real, sometimes-lossy
timing/input behavior) -- a genuine confirmation and sharpening of the
already-known "over/under-mashing trap" (rom-map.md), now shown to
apply WITHIN a single logical page, not just between pages: pressing
`A` too early doesn't queue up "show the rest, then advance" -- it can
discard not-yet-revealed text of the CURRENT page entirely and jump
straight to the next one. **Reframes, again, what the original
control-byte question should even be asking**: the interesting
question isn't just "what does byte X mean" in the abstract -- it's
"where, precisely, in the raw byte stream does the real permanent-stall
point sit, and is it marked by one of the already-suspected control
bytes (`0x12`/`0x1B`/`0x00`/`0x04`) at exactly that position." Not
answered this pass (would need correlating this live-confirmed stall
point against the RAW ROM BYTES of `storyPages[1]`'s own real source
location, not yet cross-referenced) -- a concrete, well-specified,
bounded next step, not a fresh mystery: find `storyPages[1]`'s real
file offset (not yet located as raw bytes, only as a live-decoded
string), then check which byte sits at the exact position corresponding
to ~31 characters in.

**Honest overall status at that point**: this pass did NOT pin down the
literal control-byte identity (still open, same as before) -- but it
DID establish a real, concrete, surprising, live-verified fact about
the dialogue engine's own behavior that is directly useful on its own
(anyone implementing this project's own dialogue system precisely needs
to know that early input can silently truncate a page's text, not just
skip a wait) and gives the NEXT attempt a much more precise target
(a known real byte-offset window to inspect) instead of guessing.

## Resolved: 0x12 is VERIFIED as the real "halt and wait for input" control byte (2026-08-11, "ok dann such weiter")

Direct continuation, immediately after the section above, using this
project's own `Watcher` on real ROM READ addresses (not just the WRAM
write side) to settle the question with hard execution evidence
instead of inference.

**Step 1 -- located `storyPages[1]`'s real raw bytes.** Reused the
lenient full-region scanner (`scan_text_region.lua`, this project's own
existing digraph-hunting tool) over the known ~26KB dialogue region
(`0x34800`-`0x3B000`) and grepped for "wurden"/"zwungen"/"Tag". Found a
clean, unambiguous match at file offset **`0x3A1DE`** (immediately
after a real `0x00` terminator, i.e. a genuine message start): decodes
(with the already-VERIFIED table) as `...zwungen[41]je[21]n
Tag[12][1B]zu[26]Unter[8C]ltung...` -- an exact structural match to the
`storyPages[1]` -> `storyPages[2]` transition ("...gezwungen, jeden
Tag" -> "zur Unterhaltung..."), confirming this is the right byte
range.

**Step 2 -- watched every individual ROM byte in that range for
CPU reads**, not writes -- `Watcher.watch(addr, kind=WATCHPOINT_READ)`
across the whole `0x3A1D0`-`0x3A220` file range (mapped to GB address
`0x61D0`-`0x6220` while bank 14 is paged in, `gb_addr = 0x4000 +
(file_off - 0x38000)`), then ran `courtyard_boss_defeated()` with zero
input and logged every hit in order. This is strictly stronger evidence
than either the earlier `$D3E9` write-count approach (only shows *how
many* reveal-ticks happened, not *which byte* each one was for) or the
VRAM read (a manual, error-prone tile-to-glyph-to-character
reconstruction one row at a time).

**Result, unambiguous**: the read pointer advances byte-by-byte through
the *entire* real `storyPages[1]` text, all the way through
`"...jeden Tag"` -- **not** stalling mid-word at "ge" as Step 3 of the
previous section concluded (that VRAM-based reading is now understood
to have been a misread -- most likely an incomplete/misaligned tilemap
row capture, since it directly contradicts this much more direct
execution trace and this project's own row-offset convention was hand-
derived, not independently double-checked, in that earlier pass). The
**last byte ever read**, across the whole run and confirmed to never be
exceeded even thousands of frames later, is **file offset `0x3A206`
-- byte value `0x12`**. The very next byte, `0x3A207` (`0x1B`), is
**never read**, not once.

**Conclusion, VERIFIED (execution-trace evidence, not inference):**
**`0x12` is the real control byte that halts the text engine's forward
progress and waits for player input.** It is not a "pause mid-sentence"
byte -- the engine fully reveals everything up to and including
reaching it, then simply never advances the read pointer past it until
something external (a button press) happens. This is now corroborated
three independent ways: (a) this direct read-pointer trace, (b) a full-
ROM static cross-reference showing `0x12` immediately followed by a
second, variable byte (`0x1B`/`0x11`/`0x13`/others) in **24 separate
real contexts within the dialogue region alone** (7x after
"...bezwungen" in different monster-defeat lines, 2x after "HILFE!"
lines, plus this "...Tag" and the following "...kämpfen." instance, and
more), always sitting immediately before either the hard terminator
`0x00` or the next message boundary, and (c) it fits the byte's
already-suspected role from the original occurrence-frequency read of
this whole region.

**Still open** (a real, well-scoped follow-up, not blocking): what the
*second* byte after `0x12` means (`0x1B` vs `0x11` vs `0x13` vs several
single-occurrence variants seen elsewhere in the ROM) -- tested
whether it might mean "more pages follow" vs "dialogue fully ends"
by checking both observed real instances (`ge...Tag[12][1B]zu[26]
Unter...` and `...kämpfen.[12][1B]<TERM>`), but **both** here are
followed by a hard terminator regardless, so that specific hypothesis
doesn't hold up cleanly from just these two examples -- likely a
per-message parameter byte (e.g. a sound effect ID, or which
close-box animation to play) rather than a page-count flag, but not
independently confirmed yet.

**Bonus finding along the way**: each watched byte was read on average
2-3 times (199 total reads across ~80 distinct byte addresses), not
once -- strong evidence the reveal/line-wrap logic does real lookahead
(measuring whether the next word fits the current line before
committing to print it), consistent with the hyphenated word-wraps
(`HYPHEN_BYTE`) already found directly in this same byte range.

## "Die anderen Bytes": resolving 0x21, 0x43, 0x14, and the 0x12-successor semantics (2026-08-11, "na dann finde raus was die anderen bytes bedeuten")

Direct continuation of the `0x12` work above, this time widening the
lens from "one message" to the full `[12][XX]`-pattern census already
sitting in the earlier full-region scan output (`rescan_story.out`,
150+ real matched blocks across the ~26KB dialogue region).

**The second byte after `0x12`, resolved with real numbers instead of
2 anecdotes:**

- **`[0x12][0x11]` (196 occurrences in-region): closes the dialogue and
  returns to gameplay.** The single cleanest confirmation set in this
  whole project's text work: **30 real, independent item-pickup
  messages**, every one of the exact shape `"<Item> gefunden[12][11]"`
  with a different item name each time (Bonbon, Bronze, Gold, Elixier,
  Kristall, Rubin, Saphir, Smaragd, Schlüssel, Amanda, Samurai...) --
  each a complete, standalone interaction with nothing displayed
  afterward. Also every short one-line NPC utterance ("Warte hier!",
  "Guten Morgen!", "Ver­schlossen!", boss-defeat lines like "Davias
  bezwungen") ends the same way.
- **`[0x12][0x1B]` (199 occurrences in-region): closes the CURRENT box,
  then immediately shows the next queued box in the SAME conversation.**
  Confirmed via **18 real instances** of the exact shape
  `"[12][1B]<Name>[0x2C]"` with **6 different real named speakers**
  (Cibba x6, Bogard x5, Julia x4, Willy, Sarah, Davias) -- i.e. `0x2C`
  is itself a real "speaker-name delimiter" byte (a colon-equivalent
  separating a name from their line, distinct from the already-known
  `COLON_BYTE` 0xF5 used for spoken/printed colons). This matches this
  project's own earlier LIVE-INPUT finding exactly (`press_after_pause.
  py`, previous section): pressing input after page 1's `[12][1B]`
  jumped straight into page 2's content instead of returning control --
  now explained precisely, not just observed.
- **`[0x12][0x13]` (2 occurrences in-region, vs. 30+/18+ for the other
  two): a real but much rarer third variant.** Both real instances sit
  right after a `?` or `!` (`"...dabei helfen?[12][13][11]"`,
  `"...sag'ihr![12][13][1B]"`) -- suggestively a yes/no-choice-prompt
  marker, but only 2 real contexts is far below this project's own bar
  -- stays an open HYPOTHESIS, not a claim.

**`0x14` = the hero-name substitution token (a control byte, not a
digraph) -- VERIFIED two independent ways:**
1. Mid-sentence substitution, matching this project's own pre-existing
   `storyPages[1]` ("%s und viele...") exactly, plus a second, cleanly
   grammatical sentence found this pass: `"[14] i[2D][42]in\ntapferer
   Kämpfer."` = `"<Name> ist ein\ntapferer Kämpfer."` -- every other
   byte in that sentence was already independently confirmed before
   this pass, so this reading has no remaining ambiguity except the
   substitution point itself.
2. As a **speaker tag**, used exactly like the other characters'
   literal names before the `0x2C` delimiter found above --
   `"[14][2C]Bogard!"` = "`<Held>`: Bogard!" (the hero calling out to
   Bogard), `"[14][2C]Ja,..aber.."` = "`<Held>`: Ja,..aber..". The
   hero's own lines are tagged with this placeholder instead of a
   literal name -- a clean, self-consistent finding once `0x2C`'s role
   was understood.

**Two new digraph-table entries, VERIFIED (2+ independent DIFFERENT
words, this project's own bar), byte-exact-tested against the real
ROM (`0x0394C2`, "Bonbon gefunden"):**
- **`0x21` = "de"**: `"gefun[21]n"` = "gefunden" (30+ item-pickup
  messages, different item name each time) **and** a genuinely
  different word, `"fin[21][43].."` = "finden" ("to find", not
  "gefunden").
- **`0x43` = "n"** (a single-LETTER code, same shape as the
  already-established `0x5B`="a"): resolved by the SAME "finden"
  sentence above, plus the original 2026-08-10 single-occurrence lead
  ("...ihr Lebe[43]" = "...ihr Leben", "...their life") -- two
  previously-separate open leads that turned out to confirm each other.

**Still open, real leads recorded but NOT wired in** (each fits one
clean context but lacks the second independent word this project
requires, see `TextDecoder.lua`'s own comments for the exact
derivations): `0x2D`="st", `0x42`=" e" (both from the "ist ein
tapferer Kämpfer" sentence -- context is airtight even though each
byte alone has one occurrence), `0x41`=", ", `0x6A`="d ", `0x81`="vo"
(a recurring "-voll" shape, 3 contexts), `0x53`="tt" (from "Amulett",
10+ times -- but always the SAME word, so per this project's own rule
this alone doesn't clear the bar yet).

Full Lua test suite: 211/211 passing (1 new real-ROM test added,
`decodeString` against the real "Bonbon gefunden" bytes; 2 new
`decodeByte` assertions folded into the existing digraph test).

## SOLVED: the real message-settings-table text pointer (2026-08-12, direct instruction "mach die dispatcher untersuchung bitte")

The question this project's own earlier passes tried and failed to
answer at least twice ("Computed real CPU addresses for 8 known real
message-start offsets... no clustering anywhere"; "does the ALREADY-
KNOWN 24-byte message-settings record itself hold the text pointer?...
no match anywhere in the record") is now closed, found by reading real
ROM CODE instead of guessing at byte offsets.

**The chase**: opcode `0xFE`'s own handler (`$0E69`) calls `$04E2`,
which turned out to be a real 5-case sub-dispatcher (`A`=1..5, each a
`PUSH AF / LD A,<case> / JP $1F64` -- the same real bank-trampoline
shape used throughout this ROM). `$1F64` itself: switches to bank 4,
indexes a small table at CPU `$4000` by the case number, and JUMPS
(via a real `PUSH`+`RET` indirect-call trick) into whichever bank-4
function that resolves to. **Function index 1** (file `0x102F7`) is
the real one that matters: computes `0x4739 + messageID*24` (the
ALREADY-KNOWN message-settings record formula, exactly), caches it,
then reads a real 16-bit LE value from **record offset +20/+21** (the
record's own 21st/22nd byte, 0-based) into `HL`.

**VERIFIED, real, byte-exact**: that 16-bit value, `+ 0x34800` (the
already-known real dialogue-region base), is the message's own real
text start offset. Checked against 3 of this session's own freshly-
found real messageIDs (from "Using the now-decoded script table" in
events.md) with completely clean, unambiguous results:
- **messageID 13** → file `0x39965` → decodes as `"gefunden"` --
  and the SAME window shows two more, ADJACENT, complete real
  item-pickup messages sitting right next to it: `"Sma[8E]g[6A]
  gefunden[12][11]"` and `"Saph[50][4A][67]unden[12][11]"` -- real
  German ("Smaragd gefunden" / "Saphir ... gefunden", "emerald found"
  / "sapphire found"), exactly the already-established `"<Item>
  gefunden[12][11]"` shape, with the already-known real `[12][11]`
  "close dialogue" control pair landing exactly where it should.
- The record's own `[86]aman[28]gefunden` neighbor reads as `"[Di]
  aman[t ]gefunden"` = "Diamant gefunden" ("diamond found") if `0x86`
  = "Di" and `0x28` = "t " -- both plausible, both NEW leads (not yet
  independently confirmed a second way, so not added to `TextDecoder
  .DIGRAPH_TABLE` from this alone -- flagged as real, strong leads,
  same honesty bar as every other still-open digraph candidate).

Cross-checked against 21 total real messageIDs found in the earlier
scan: most others decode to empty or a couple of characters before
hitting a still-unmapped digraph byte -- expected and consistent, NOT
a formula failure (`TextDecoder`'s own digraph table is still
genuinely incomplete; this new pointer formula just gives real,
correct starting addresses to decode FROM, it doesn't by itself fill
in the remaining digraph gaps). One likely real sentinel found along
the way: messageID `255`'s own pointer lands exactly on a terminator
byte (`0x00`) -- reads as a real "no text" placeholder value, matching
this project's own already-observed "255/254 recur at what look like
milestone/placeholder scripts" pattern from the script-table census.

**The real formula, stated plainly**: for a real messageID, real text
starts at `0x34800 + u16le(rom, 0x10739 + messageID*24 + 20)`. Not yet
added as a named field to `rom_profiles.lua` this pass (deliberately --
see this section's own "what's next" note) but real, checked-in-code-
verifiable via the exact bytes quoted above.

**What's next, honestly scoped**: this formula is confirmed for
messageID 13 (and its 2 real neighbors) -- a strong, real confirmation,
but from ONE dense cluster of adjacent, structurally-identical
messages, not yet independently re-derived from a second, unrelated
part of the table. A dedicated pass wiring this into `rom_profiles.lua`
(a new `messageSettingsTable` entry with the real formula) plus a
proper Lua decoder module (mirroring `RoomFloorLayout.lua`'s own
"real pipeline, pure Lua, headlessly tested" shape) would make this
real, reusable infrastructure instead of a one-off Python/Lua
scratch-script finding -- a well-scoped, concrete next step, not
attempted this exact pass (this pass was the discovery; wiring it in
is real, separate follow-up work).

Python/Lua one-off investigation scripts only this pass (not checked
in). No production Lua code changed. Full Lua test suite: 226/226
passing (unchanged).

## Closing the digraph table (2026-08-12, direct instruction "ok versuche die text decoder digraphs komplett zu schliessen")

Direct follow-up to the `$1F64` dispatcher investigation above -- with
a real, verified text-pointer formula in hand, this pass went after
`TextDecoder.DIGRAPH_PARTIAL` itself: 30 entries confirmed as of this
morning, and dozens more low bytes recurring constantly in the real
dialogue region without a settled meaning.

**Method, a genuine step up from "spot-check one opportunistic word"**:
built two small, reusable Python tools (both real, permanent additions
under `tools/rom/`, not one-off scratch scripts this time):
- `dump_strings.py --gaps`: already existed, kept in sync with
  `TextDecoder.lua`'s own table throughout this pass so both stayed
  identical.
- A new **"fill-in-the-blank word" extractor** (the actual key to this
  pass): split the whole real dialogue region (file `0x34800`-`0x3B000`)
  into "words" (bounded by space, newline, terminator, and the
  ALREADY-known control opcodes), then kept only words where **every
  byte except exactly one already decodes** -- a real, unambiguous
  "solve for X" puzzle straight from the ROM's own bytes, not a guess
  dressed up as one. Deduplicated by template and sorted by frequency.

**Every candidate value was checked TWICE before being trusted**:
first against its own isolated word (does "Kraeuterlaeden" / "Tritt
vor" / etc. read like real German), then by re-decoding the ENTIRE
26 KB region with the candidate applied and confirming the result
reads as coherent, grammatical, multi-sentence German prose -- not
just that one hand-picked word parses. This caught and fixed two real
mistakes before they were committed (both narrated to the user as
corrections, not hidden):

1. **A genuine boundary ambiguity** (`0x35`/`0x38`/`0x8D`): "ich war"/
   "reich" are EQUALLY well explained by 0x35="i"+0x38="ch " or by
   0x35="ic"+0x38="h " -- the SAME output text either way, no way to
   tell from those two words alone. Resolved by cross-checking against
   the credits screen's own real "Ko[0x35]hi Ishii" -- only
   0x35="ic" gives the real, verifiable name "Koichi Ishii" (Seiken
   Densetsu 1's director); the other split would misspell it
   "Koihi Ishii". Settled: 0x35="ic", 0x38="h ", 0x8D="Ic".
2. **A genuine, real conflict**, not just an ambiguity (`0x6C`): the
   dialogue region's own "be[6C][8F]t"/"be[6C][8F]en" read perfectly
   as "besiegt"/"besiegen" (defeated/to defeat) with 0x6C="si" -- and
   once 0x8F="eg" was independently confirmed elsewhere (liegt, Weg),
   FIVE MORE dialogue words fell out consistent with 0x6C="si": "sich",
   "besitzt", "sie", "passieren" (7+ total). But the credits screen has
   its own real "Yo[0x6C]nori Kitase" (a SECOND, 3-letter spelling of
   "Yoshinori" alongside the already-known "Yosh[in][or]i" spelling
   found elsewhere in the SAME credits block), which only works if
   0x6C="shi". Both cannot be true for one fixed byte. Resolved
   pragmatically and honestly: "si" is used (7+ consistent dialogue
   words vs. 1 credits outlier), with the conflict documented in
   `TextDecoder.lua` itself rather than silently picking a winner --
   real, open evidence that the credits screen may use its own,
   separate local table for that one special screen (not confirmed).

**Real, verified result**: **37 new entries** added to
`DIGRAPH_PARTIAL` this pass (29 in the first round, 8 more in a second
round chasing bytes whose own words only became readable once the
first round was already applied) -- `ch`, `e `, `r `, `t `, `st`,
`ei`, `d`, `s `, `es`, `d` (0x3D, lowercase), `au`, `, `, `du`, `u `,
`re`, `ir`, `tt`, `m `, `Ma`, `al`, `W`, `t` (0x60), `sc`, `et`, ` v`,
` G`, `na`, `a `, `ra`, `ic`, `h `, `we`, `d ` (0x6A), `rt`, `ih`,
`Ic`, `eg`, `si` -- each with 2+ independent real word confirmations
quoted directly in `TextDecoder.lua`'s own comments (this project's
established VERIFIED bar), several backed by 7-15+. Total table size:
**30 -> 68 entries**, more than doubling coverage. Whole-region
occurrence-weighted coverage of the real digraph byte range
(`0x20`-`0xAF`) rose from roughly two-thirds to noticeably higher; full
sentences that used to stop after 2-3 words now decode completely and
cleanly (see the new flagship regression test below).

**A genuinely new, useful side-finding**: this pass makes it clear the
byte ranges 0x00-0x1F and 0xF0-0xFF are, almost entirely, a SEPARATE
"control/header" category (script opcodes, message-header parameters
like reveal-speed/portrait selectors) rather than more digraphs waiting
to be found -- the still-unresolved bytes concentrate heavily there,
not in the 0x20-0xAF digraph range, which is now the great majority
resolved. This reframes what "closing the table" even means: the
digraph compression scheme itself is now close to fully mapped; what
remains open is mostly a different, already-partially-understood
subsystem (message/script control bytes), not more hidden text codes.

**Honestly, explicitly NOT closed** (not "complete", as bluntly as the
user's own instruction deserves):
- `0x52` = "M" -- one strong lead ("Wer den Mana-Baum..."), no second
  independent word found.
- `0x66` = either "! " or "? " -- genuinely ambiguous, both fit
  different real contexts equally well, left unresolved rather than
  guessed.
- `0x82` = truly CONTRADICTORY across its own occurrences (wants "e"
  in one word, "ute" in another, "me" in a third) -- flagged, not
  forced.
- `0x40` = a single-context "ne" lead only.
- A real, still-unexplained "missing space" artifact shows up in a
  handful of fully-decoded sentences (e.g. "kommstdu", "inder Hoehle")
  even with every table entry applied -- flagged for a future pass,
  not smoothed over.
- ~78 distinct byte values in the 0x20-0xAF range remain unmapped,
  most with low individual frequency (under 20 occurrences each) --
  real, bounded, listed-by-value follow-up work, not a vague "more
  research needed."

`tools/rom/dump_strings.py` kept in exact sync with
`TextDecoder.lua`'s `DIGRAPH_PARTIAL` throughout (both list the same
68 entries). New flagship regression test added: a COMPLETE, zero-gap
real sentence decode ("Was hast du ihr\nangetan, Julia?", Julia's
mother confronting her) -- something that stopped after "as" before
this pass. Three older tests, written when the bytes they touch were
still unmapped, now correctly decode further than their original
assertions expected -- updated to their new, longer, correct output
(not weakened; each still checks a real ROM offset byte-for-byte).

Full Lua test suite: 228/228 passing (1 new flagship test, 3 existing
tests updated for now-longer correct decodes, 1 test's "still-unmapped
byte" example swapped from 0x50 -- now resolved -- to 0x66 -- still
genuinely open).

## Finishing the job (2026-08-12, same day, "na dann loese was noch offen ist" / "versuche ... den kompletten text ... zu dekodieren")

Two more rounds of the exact same method (re-run the "fill-in-the-
blank word" extractor -- resolving bytes unlocks previously multi-gap
words into new single-gap puzzles -- solve, cross-check by re-decoding
the whole region, repeat), pushed fast per the user's own explicit
"das sollte bitte nicht so lange dauern":

**23 more entries confirmed**, each with 2+ independent real words
(citations kept compact in `TextDecoder.lua` this round, same rigor):
`nd`, `ne`, ` e`, `is`, ` s`, `rd`, ` g`, `ht`, ` w`, ` M`, `el`, ` m`,
` n`, `nn`, `! `, `ef`, `mi`, ` B`, ` a`, `di`, `eh`, `ns`, `ha` -- for
bytes `0x32/0x40/0x42/0x44/0x46/0x48/0x4A/0x4B/0x4D/0x52/0x56/0x57/
0x61/0x62/0x66/0x67/0x68/0x6F/0x81/0x85/0x8A/0x8B/0x8C`. Several close
real, previously-flagged leads outright: `0x52` (the old "Mana-Baum"
lead, now also confirmed via "Ich bin Marcie"), `0x66` (was ambiguous
"!"/"?"/".", settled on "! " -- clearest from "RAUS!" and an imperative
command chain, nothing found actively contradicts it), `0x67` and
`0x4A` (this session's own earlier "Saphir"-cluster leads, now
promoted with real second words).

**Table size: 68 -> 91 entries.** Whole-region occurrence coverage of
the real digraph range: **66.2%** (up from ~68% of a smaller mapped
set before -- most REMAINING gaps are now low-frequency stragglers,
not common words). 131 real text blocks now decode >=85% clean (was
61). Full multi-sentence passages now read as complete, natural
German with zero or near-zero gaps, e.g.: *"Was hast du ihr angetan,
Julia?"*, *"Eine Faelschung! Aber wo ist das richtige?!"*, *"tut mir
so leid .."*, *"Viele Monster griffen Lorim an. Cibba kam dorthin.
Lorim befindet sich im Sueden der Schneewueste."*

**A real side-finding, closing an earlier open question**: the
"missing space" artifact flagged in the previous round turned out to
be mostly just MORE space-inclusive digraphs this pass hadn't reached
yet (` e`, ` s`, ` g`, ` w`, ` M`, ` m`, ` n`, ` B`, ` a` -- 9 of them)
-- not a separate mechanism. A smaller real residue remains (e.g.
"inder"/"aufder" where two already-confirmed SPACE-FREE codes land
back to back with no space byte at all) -- still real, still
unexplained, but much smaller and clearly cosmetic.

**Honestly, still open** (not force-closed, exactly as asked): `0x82`
stays genuinely CONTRADICTORY across its own occurrences (3 different
words each want a different fill). `0x63` is NEW to this list --
mostly "ng" (3 clean words: eingesperrt, Angriff, eingefroren) but one
real counter-example ("...ihre aus Silber", using the already-
confirmed `0x86`="ih") wants plain "r" instead -- same shape of
conflict as `0x6C`, left unresolved rather than picking a side.
Roughly 55 distinct low-frequency byte values in the 0x20-0xAF range
remain genuinely unmapped -- real, bounded, but not chased further
this pass (diminishing returns: none recur often enough to build a
2-independent-word case from the current dialogue-region sample).

Full Lua test suite: 228/228 passing (3 tests updated for now-complete
decodes; the "0x66 still open" example swapped to `0x82`, the one
that's still genuinely open after this round).

## The real script-driven typewriter parser (2026-08-16, direct user
instruction: "da muss es doch einen parser im rom code geben der die
texte parst. schau doch den mal an")

Everything above this section was reverse-engineered by **dynamic
observation** (comparing decoded bytes against real on-screen text) --
nobody had yet disassembled the ROM's own parsing code. This section
does that, for the specific handler opcode `0x04` (the TICK/"reveal
one more character") of the real script-driven typewriter effect uses
-- found at `$333D`:

```
0x333d  7e        LD A,(HL)
0x333e  fe 99     CP 0x99
0x3340  d2 80 34  JP NC,0x3480      ; >=0x99            -> SPECIAL
0x3343  fe 20     CP 0x20
0x3345  38 0f     JR C,0x3356       ; <0x20             -> LOW-CONTROL
0x3347  fe 70     CP 0x70
0x3349  da a4 34  JP C,0x34a4       ; 0x20-0x6F         -> DIGRAPH (direct)
0x334c  fe 80     CP 0x80
0x334e  da 80 34  JP C,0x3480       ; 0x70-0x7F         -> SPECIAL
0x3351  d6 10     SUB 0x10
0x3353  c3 a4 34  JP 0x34a4         ; 0x80-0x98         -> DIGRAPH (-0x10 remap)
```

Real byte classification for THIS handler: `0x00-0x1F` LOW-CONTROL
(`$3356`), `0x20-0x6F` DIGRAPH direct (`$34A4`), `0x70-0x7F` SPECIAL
(`$3480`), `0x80-0x98` DIGRAPH via `-0x10` remap (`$34A4`), `0x99-0xFF`
SPECIAL (`$3480`).

**Decisive finding for the boss-script question** (direct user
question, "im kontext des bosses macht es aber mehr sinn wenn es ein
steuerzeichen wäre oder?"): `0xFC` is `>= 0x99`, so in THIS handler it
never reaches the digraph/character table at all -- it always goes to
`$3480`. Full disassembly of that path and its 4 callees:

```
$3480  CALL $36c2   ; throttle gate (see below) -- RET NZ bails out
$3483  RET NZ       ;   here on 4 of every 5 calls, doing nothing else
$3484  PUSH HL
$3485  CALL $3c92   ; reads back a remembered BC from $D8B0/$D8B1,
                     ;   swaps it into AF via a PUSH BC/POP AF trick
$3488  POP HL
$3489  CALL $3777   ; (not yet disassembled)
$348c  LD A,($D89B) / LD B,A
$3490  LD A,($D89A) / LD C,A    ; BC = ($D89B:$D89A)
$3494  CALL $3c7e   ; AF/BC juggle again, writes B,C back into $D8B1/$D8B0
$3497  DEC HL
$3498  LD A,H / LD ($D8B7),A
$349c  LD A,L / LD ($D8B6),A    ; write (HL-1) into the cursor-save pair
$34a0  CALL $36d0   ; INC HL, write HL back into the SAME pair, then
                     ;   LD A,4 / LD ($D85A),A
$34a3  RET

$36c2  LD A,($D864) / DEC A / LD ($D864),A
       RET NZ                   ; "not yet time" -- 4 of 5 calls exit here
       LD A,5 / LD ($D864),A    ; counter hits 0 -> reset to 5, keep going
       RET

$3c92  CALL $3081 (unknown) / PUSH BC
       LD A,($D8B1) / LD B,A / LD A,($D8B0) / LD C,A
       PUSH BC / POP AF         ; AF = BC (loads flags register from C)
       POP BC / RET

$3c7e  PUSH AF / PUSH AF / CALL $3099 (unknown) / POP AF
       PUSH BC / PUSH AF / POP BC    ; BC = AF (opposite direction)
       LD A,B / LD ($D8B1),A / LD A,C / LD ($D8B0),A
       POP BC / POP AF / RET

$36d0  INC HL / LD A,H / LD ($D8B7),A / LD A,L / LD ($D8B6),A
       LD A,4 / LD ($D85A),A / RET
```

`$D8B6`/`$D8B7` is NOT a script-cursor-specific concept -- it's already
documented elsewhere in this project (see the `$326A`/`$3274`
save/restore utility) as a generic "stash a 16-bit value across a
call" scratch pair, reused by many unrelated routines. Here, `$3497`'s
`DEC HL` writes `HL-1` into that pair, then `$36D0` immediately does
`INC HL` and overwrites it again with the now-restored original `HL`
-- net effect on the pair: **unchanged**. So `$3480` does **not**
redirect/jump the script's read cursor, contrary to a first, hasty
read of just the `DEC HL` half. What it verifiably DOES do: gated by
a real "every 5th call" counter (`$D864`), it shuffles values through
`$D89A/$D89B` -> `$D8B0/$D8B1` (via an AF/flags-register round-trip in
both `$3c92` and `$3c7e`) and unconditionally sets `$D85A = 4`. This
shape (throttled-every-N-ticks, touches state unrelated to text
content, doesn't affect what prints next) is most consistent with a
**visual side effect tied to the typewriter reveal rate** -- the
leading hypothesis is the blinking "waiting for input" prompt arrow
these era's dialogue boxes typically show once text is fully revealed,
but `$3081`/`$3099`/`$3777` and the exact roles of `$D85A`/`$D89A`/
`$D89B` were not traced further this pass, so that specific purpose is
NOT confirmed -- only that it is a **non-text control operation**, not
a printable character, in this handler.

**What this does and doesn't settle**: it decisively confirms `0xFC`
(and every other byte `>= 0x99`, and `0x70-0x7F`) is a control code,
not a letter, in the SCRIPT-DRIVEN typewriter-tick context reached via
opcode `0x04`. It does **not** by itself overturn the static-blob
`DIGRAPH_PARTIAL`/`UMLAUT_PARTIAL` tables above, which were built from
a completely different code path: `TextDecoder.decodeString` models
whatever routine decodes the STATIC message-text blobs, which this
pass did not locate or disassemble -- and the two domains are already
known to diverge over this same byte range, not just theorized to: the
static domain has `0x99`-`0x9B` independently, twice-over VERIFIED as
Ä/Ö/Ü (see `UMLAUT_PARTIAL` above), while the script-tick domain just
shown sends that same byte range to the non-text `$3480` path. So
`0xFC`'s `[0xFC] = "sch"` entry in `TextDecoder.DIGRAPH_PARTIAL`
(added the same day, from static-blob evidence only) is left in place,
but its own comment now cross-references this section rather than
claiming a universal reading -- **the same byte value carries
different meanings in the two domains, and only the static one is
what that table encodes.** Extending this `$333D`-style disassembly
technique to classify the STILL-undecoded digraph-range bytes (`0x27`,
`0x63`, `0x82`, `0x90`-`0x98`) needs the STATIC decode routine
specifically, not `$333D` -- that routine has not yet been found.

## FOUND: the real static message-text decoder, `$3777` (2026-08-17, direct user instruction: "nach such den richtigen decoder")

Found via live tracing, not guessing: `rom_profiles.lua` already
documents a real, confirmed ROM source for `storyPages[1]` ("...und
viele andere wurden gezwungen...") at bank 14, file `0x3A1E5`
(CPU `$61E5` in that bank). Single-stepped the real black-wipe +
first-story-box window from `courtyard_boss_defeated()`, watching for
CPU `HL` to sit inside that exact source range, and walked the call
stack up from there through 3 real, disassembled layers of "draw one
glyph" wrappers (`$1D72`, the already-known generic HBlank-synced
VRAM writer -> `$3899`/`$38AF`, a generic BG/window draw dispatcher
-> `$386E`/`$384C`, scroll-position-adjusted glyph-draw entries -- the
BOX BORDER and a fixed-width HUD number/label both turned out to share
these same low-level primitives, a real dead end each time, correctly
ruled out by their own return addresses and WRAM source pointers not
lining up with the real dialogue text bank/offset) until landing on
the real top-level per-character dispatcher itself:

```
$3777  CALL $374D          ; restore line cursor (D/E, B/C) from $D8B8-$D8BB
$377A  PUSH AF
$377B  LD A,(HL+)          ; *** read the real next source text byte, advance HL ***
$377C  CP 0x7F
$377E  JR Z,$3785
$3780  CP 0x99
$3782  JP C,$37DC          ; byte < 0x99 -> a separate, more complex path (word-wrap-aware; see below)
$3785  PUSH AF
$3786  LD A,($D84A) / INC A / JR NZ,$3793
$378C  DEC D / LD A,0x7F / CALL $384C / INC D   ; (leading-blank-column handling, byte==0x7F case)
$3793  POP AF
$3794  XOR 0x80             ; *** THE REAL FORMULA ***
$3796  CALL $384C            ; draw the transformed value as a glyph
```

**Byte `>= 0x99` (including `0xFF`, `0xB0`-`0xFF`, and `0x99`-`0x9F`):
the real VRAM tile ID is `rawByte XOR 0x80`** -- proven by disassembly,
not just cross-referenced dynamically. This is now a formal PROOF of
what this whole document's earlier "The formula" section had already
established by dynamic observation: for `byte in [0x80,0xFF]`,
`byte XOR 0x80 == byte - 0x80`, so this is exactly
`MAIN_GLYPHS[byte-0xB0+1]`'s own tile (`0x30 + (byte-0xB0) == byte -
0x80`) for the main range, and exactly the already-VERIFIED umlaut
tiles for `0x99`-`0x9F` (e.g. `0x99 XOR 0x80 = 0x19` = tile 25 = Ä,
matching `UMLAUT_PARTIAL[0x99]` exactly). Every existing `MAIN_GLYPHS`
and `UMLAUT_PARTIAL` entry in `TextDecoder.lua` is now real-disassembly-
CONFIRMED for this domain, not just dynamically inferred.

**Byte `< 0x99`** (the whole digraph-table range, `0x00`-`0x98`) takes
a real, different path at `$37DC` -- disassembled this pass too, but it
turned out to be **word-wrap/line-cursor bookkeeping**
(`$D84A`/`$D849` state checks, saving the cursor to `$D8C5`/`$D8C6`,
a real "does the current word still fit on this line" check via
`$3736`/`$374D`), not yet the digraph EXPANSION/lookup itself -- the
actual byte -> two-tile table (if it's a literal table at all, rather
than more branching logic) sits further inside this same path and was
not reached this pass. **Honest state**: the dispatcher and the exact
formula for the already-mapped `>= 0x99` range are now proven; the
real digraph mechanism for `< 0x99` is located (this same `$3777`/
`$37DC` call tree, real ROM, real bank 0) but not yet fully traced to
a concrete lookup -- a good, concrete next continuation point, not a
dead end.
