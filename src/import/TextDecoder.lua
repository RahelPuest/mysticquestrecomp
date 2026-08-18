-- Decodes Mystic Quest (EU)'s in-ROM text encoding -- see
-- docs/reverse-engineering/text.md for the full writeup of how this was
-- found (dynamic tracing with a real emulator, since static analysis
-- alone could not crack it -- see docs/reverse-engineering/tooling.md).
--
-- PROVEN BY DISASSEMBLY (see text.md's "FOUND: the static message-text
-- decoder, $3777" section): the static-text decode dispatcher (ROM
-- `$3777`, bank 0) was located and disassembled. For every byte >= 0x99
-- -- i.e. the whole MAIN_GLYPHS range (>=0xB0) and the UMLAUT_PARTIAL
-- range 0x99-0x9F -- the ROM formula is simply `vramTile = rawByte XOR
-- 0x80` (== `rawByte - 0x80` for this range), executed at ROM `$3794`.
-- Bytes < 0x99 (the whole digraph range) take a genuinely different
-- path (`$37DC`) that turned out to be word-wrap/line-cursor
-- bookkeeping, not yet traced to a concrete digraph lookup table --
-- still open, see text.md for the exact disassembly reached so far.
--
-- Confirmed formula: a byte >= 0xB0 encodes a character as
-- `MAIN_GLYPHS[byte - 0xB0 + 1]` (1-based Lua string indexing), covering
-- the same 64-glyph alphabet as the font's ROM tile order (digits, A-Z,
-- a-z, apostrophe, comma -- see src/import/rom_profiles.lua's
-- `graphics.font.rowGlyphs`). 0xFF is a space (the font's last tile is a
-- blank glyph). 0x00 terminates a string. 0x90-0xAF is a partially-
-- decoded umlaut/icon block -- only a few bytes are confirmed so far
-- (see UMLAUT_PARTIAL below); anything else in that range decodes to nil
-- rather than a guess, per the project's "no silent fallbacks" rule.
-- Below 0xB0, a two-character (digraph) compression table also exists
-- -- 16 entries confirmed so far (see DIGRAPH_PARTIAL below); the rest
-- of that range is a mix of still-unidentified digraphs and
-- script/control opcodes, and stays UNKNOWN rather than guessed.
-- Outside both ranges: 0xF0=period, 0xF2=hyphen, 0xF3=exclamation,
-- 0xF4=question mark, 0xF5=colon (all VERIFIED), 0x1A=newline.
--
-- Pure Lua, no love.* calls, so it's headlessly testable like GBTile/
-- RomIdentity.

local TextDecoder = {}

TextDecoder.MAIN_GLYPHS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz',"
TextDecoder.MAIN_BASE = 0xB0
TextDecoder.SPACE_BYTE = 0xFF
TextDecoder.TERMINATOR_BYTE = 0x00

-- Confirmed by context: 0x9D appears exactly where German "erh[?]ht"
-- must read "erhoeht" (increased) -- the o-umlaut letter. 0x9C
-- confirmed the same way: appears exactly where "K[?]mpfer" must read
-- "Kaempfer" (fighter) in a live dialogue box read directly from VRAM
-- tile indices (see docs/reverse-engineering/text.md). Every other
-- byte 0x90-0xAF is UNKNOWN until similarly cross-checked against a
-- decoded sentence.
--
-- CORRECTED (direct user report of a rendering bug with umlauts):
-- these 7 bytes were being decoded as their ASCII-safe 2-letter
-- spellings ("ae","oe",...). Live-decoded the font tile graphics
-- directly from ROM (same linear formula already established for
-- period/hyphen/exclamation, `0x22900 + (tileId-0x10)*16`) and found
-- the glyphs are genuine single umlaut/eszett characters (visible dots
-- over the letter, or the double-loop eszett shape), not two separate
-- letter tiles -- tiles 25-31 (0x19-0x1F), immediately preceding the
-- main font block, in the exact order Ä,Ö,Ü,ä,ö,ü,ß. Cross-checked
-- twice against independently-captured live VRAM text: tile 28
-- appears exactly where "wächst"/"Kräfte" need ä (2 unrelated words),
-- tile 30 exactly where "berührt"/"überirdi-" need ü (2 unrelated
-- words) -- an exact match to this table's byte semantics (0x9C=ä,
-- 0x9E=ü), not a coincidence. Now decoded as their single UTF-8
-- characters (written as `\ddd` byte escapes so this source file's
-- bytes stay plain ASCII, matching this project's existing
-- convention) -- Font.lua's `:print`/`:measure` were updated to
-- iterate UTF-8-aware instead of assuming one byte = one glyph, and
-- rom_profiles.lua's `font.extraGlyphs` now has the 7 ROM tile offsets
-- these characters need to actually render as the correct single
-- glyph instead of two ASCII letters.
TextDecoder.UMLAUT_PARTIAL = {
  [0x9C] = "\195\164", -- ä (U+00E4)
  -- Confirmed by decoding the intro-text scroll live (see
  -- rom_profiles.lua's `introText` entry) -- both appear exactly where
  -- German requires them: 0x9E in "ber[?]hrt" (beruehrt) and
  -- "[?]berirdische" (ueberirdische); 0x9F in "mi[?]brauchen"
  -- (missbrauchen, the German "scharfes S").
  [0x9D] = "\195\182", -- ö (U+00F6)
  [0x9E] = "\195\188", -- ü (U+00FC)
  [0x9F] = "\195\159", -- ß (U+00DF, eszett/scharfes S)
  -- Confirmed from the name-entry on-screen keyboard grid (see
  -- rom_profiles.lua's `nameEntry` entry): its digits row is
  -- immediately followed by these 3 tiles, then the already-confirmed
  -- lowercase 0x9C/0x9D/0x9E in the very next position -- the keyboard
  -- groups uppercase-then-lowercase umlaut pairs (Ä/ä, Ö/ö, Ü/ü),
  -- confirming both the byte values here and (independently) that
  -- 0x9C/0x9D/0x9E really are the lowercase forms as already assumed.
  [0x99] = "\195\132", -- Ä (U+00C4)
  [0x9A] = "\195\150", -- Ö (U+00D6)
  [0x9B] = "\195\156", -- Ü (U+00DC)
}

-- Confirmed the same way as the umlaut bytes above: 0xF0 appears
-- exactly where a live dialogue sentence's terminating period must be
-- ("...Kaempfer[.]"). Outside MAIN_BASE's contiguous run (0xB0-0xEF)
-- so it needs its own case, same treatment as SPACE_BYTE.
TextDecoder.PERIOD_BYTE = 0xF0

-- VERIFIED (upgraded from a hypothesis): originally flagged from a
-- single example ("Lebens- und Magiepunkte") with no second,
-- independent confirmation. Now confirmed a second, unrelated way: the
-- intro-text scroll (rom_profiles.lua's `introText`) uses this exact
-- byte at every German word-wrap hyphenation point ("des-sen",
-- "brau-chen") when its tile IDs (found via live tilemap decode, a
-- completely different discovery path from the original dialogue-box
-- read) are converted to this same dialogue-byte space (tileId + 0x80
-- -- the project's already-established relationship). Two independent
-- confirmations is this project's bar for "VERIFIED" elsewhere (see
-- e.g. the umlaut bytes above) -- promoted into the normal decode path
-- accordingly, no longer opt-in.
TextDecoder.HYPHEN_BYTE = 0xF2

-- VERIFIED: found decoding the intro-text scroll's literal ROM bytes
-- (file offset 0xBED8, see rom_profiles.lua's `introText` entry) -- a
-- line-break control byte, distinct from TERMINATOR_BYTE (0x00 ends
-- the whole block; 0x1A just starts the next line). Confirmed by
-- position: appears exactly at every sentence/line boundary the
-- live-scrolled tilemap independently already showed as a new tilemap
-- row, decoding the full multi-paragraph text perfectly on the first
-- attempt once handled this way. This project's existing hardcoded
-- dialogue strings already used a literal "\n" for the same purpose
-- (e.g. Field.lua's WILLY_DIALOGUE) -- same convention, now backed by
-- a ROM byte for text that comes from decoded data instead.
TextDecoder.NEWLINE_BYTE = 0x1A

-- VERIFIED: found decoding the "Kämpfe!" battle-intro textbox (see
-- rom_profiles.lua's `battleIntro` entry) -- the box's character-by-
-- character reveal (one letter every 5 GB frames) stops at this exact
-- byte after "Kampfe", i.e. the text is "Kaempfe!" (German imperative
-- "Fight!"), not just "Kampf" as initially guessed from a low-
-- resolution screenshot read.
TextDecoder.EXCLAMATION_BYTE = 0xF3

-- VERIFIED: a full-ROM static re-scan (`dump_strings.py` superseded by
-- an updated scan folding in the whole current decoder, see tooling
-- notes) turned up 3 independent contexts: "Was soll ich nun tun[F4]"
-- ("What should I do now?"), "...helfen[F4]" ("...help you?"), and
-- "WILLY![F4]" (a shocked "WILLY!?"). Also sits in the punctuation
-- family's on-screen ordering (found in the font/keyboard dump: `',.`
-- `[F1]` `-` `!` `[F4]` `[F5]` `[F6]`, i.e. immediately after
-- `!`/`EXCLAMATION_BYTE` and before the now-also-confirmed
-- `COLON_BYTE` below) -- the natural remaining common punctuation mark
-- to complete that set.
TextDecoder.QUESTION_BYTE = 0xF4

-- VERIFIED: the end-of-credits screen (bank 2, ~file 0xbec3 onward)
-- has 9 independent "ROLE[0xF5]\nNAME" lines -- e.g. "MUSIK -
-- KOMPONIST[F5]\nKenji Ito", "GRAFIKEN[F5]\nKazuko Shibuya",
-- "DIREKTOR[F5]\nKoichi Ishii", "REGIE[F5]\nYoshinori Kitase" (real,
-- verifiable Seiken Densetsu 1 staff names/roles) -- every single
-- credit line, same byte, same "role label followed by a colon before
-- the name" role. Also fits "Hier hast Du Deine Ware[F5]" (a shop/
-- give-item template, colon before a following item-name insertion).
TextDecoder.COLON_BYTE = 0xF5

-- VERIFIED: a different byte from COLON_BYTE above, despite the same
-- rendered glyph and the same grammatical role. An earlier
-- investigation (see the `[0x12][0x1B]` control-byte note above) had
-- already found "18 confirmed instances of `[0x12][0x1B]<Name>[0x2C]`
-- with 6 different named speakers" and flagged "0x2C appears to be a
-- 'speaker name:' tag delimiter" -- a strong lead, never independently
-- re-confirmed or wired. A fresh `dump_strings.py --gaps` run found
-- the same pattern with 20 independent named speakers (all
-- already-known characters/nouns: Alter, Amanda, Bogard, Bowow, Cibba,
-- Davias, Glaive, Hasim, Julia, Koenig, Lester, Lord, Maedchen, Mann,
-- Marcie, Medaa, Mutter, Sarah, Watts, Willy) -- every single
-- occurrence in the exact same structural position (immediately after
-- a name, immediately before that speaker's own dialogue line begins),
-- plus 6 further occurrences after `0x14`/`0x15` (the already-VERIFIED
-- hero/heroine NAME-INSERTION control bytes above) instead of a
-- literal name -- e.g. `[14][2C]Bogard!` = "<HeroName>: Bogard!" --
-- independently cross-validating both this byte's role and the
-- pre-existing 0x14/0x15 finding at the same time. Far exceeds this
-- table's 2-independent-occurrences bar.
-- NOT the same byte as COLON_BYTE (0xF5) -- that one's independently-
-- confirmed contexts are credits-screen "ROLE:NAME" and shop "Ware:"
-- lines, structurally unrelated to a dialogue-box speaker tag; the ROM
-- apparently uses two distinct byte values for the same rendered
-- punctuation mark in different string contexts (not unprecedented --
-- SPACE_BYTE/PERIOD_BYTE/etc. are each single, fixed values only
-- because no second "same glyph, different byte" case had been found
-- before this one). Rendering hypothesis (a literal ":") is not
-- independently live-VRAM-confirmed the way COLON_BYTE's own 0xF6
-- sibling investigation was (no font-tile cross-check possible without
-- already knowing this byte's on-screen tile ID, which is exactly
-- what's unconfirmed) -- but structurally this is by far the most
-- likely reading, and not wiring it at all would leave the interpreter
-- refusing to render otherwise-perfectly-readable dialogue over a
-- single, well-understood punctuation mark. Honest note on the
-- whole-corpus scan's measured impact (`scripts/scan_all_scripts
-- .lua`): wiring this byte did not move the scan's headline "clean"
-- count (dozens of scripts contain 0x2C in their text, but the scan
-- only reports each script's first blocking byte, and most of those
-- scripts already fail earlier on a different, still-undecoded
-- digraph before ever reaching their own 0x2C) -- confirmed via a
-- before/after diff of the scan's per-byte breakdown: the one script
-- whose first failure was 0x2C now fails on 0x70 instead, net zero
-- change to the aggregate numbers. Verified, permanent progress
-- regardless (four independently decoded, grammatically perfect
-- German sentences prove the byte value itself is correct) -- it just
-- won't show up in the scan's aggregate count until more of the
-- higher-frequency blocking bytes (0xFC/0xFE/0x05/0x07/the 0x70-0x7F
-- range/...) are also closed.
TextDecoder.SPEAKER_COLON_BYTE = 0x2C

-- HYPOTHESIS-status control-byte family, bytes 0x10-0x1F -- see
-- docs/reverse-engineering/events.md's "the $38F6 table decoded"
-- section for the full disassembly trail). Found from the OPPOSITE
-- direction of every other constant in this file: not from a real text-
-- corpus scan, but from disassembling the real ROM's own script-
-- interpreter opcode 0x04 handler ($333D), which reads the byte right
-- after itself and dispatches via a real jump table at $38F6 (indexed
-- by `(byte - 0x10)`) -- i.e. these are real, decoded CONTROL codes a
-- SCRIPT's own embedded text can contain, not (necessarily) bytes that
-- appear in the static message-text blobs `TextDecoder.decodeString`
-- normally reads. NOT wired into the normal decode path (this
-- project's "2+ independent occurrences" VERIFIED bar isn't cleared
-- for most of these -- only 0x1A already was, independently, from the
-- completely separate text-corpus side, a decisive cross-validation
-- that this table is correctly understood). Disassembled conclusions
-- per byte, not guesses:
--   0x10 -- sets a mode register ($D84A=6), hands off to the
--           already-documented "0xFF sub-table" system (multi-line
--           textbox mode switch).
--   0x11 -- a conditional-halt bridge (tests WRAM $D853 bit 7 -- the
--           same cell the 0xFF sub-table's "release point" sub-opcode
--           already reads).
--   0x12 -- reschedules into the 0xFF sub-table's sub-opcode 4 (a
--           conditional halt via a bank-2 call).
--   0x13 -- a substantial 164-byte WRAM block copy ($D4A7->$D56E) plus
--           a smaller $C0A0->$D862 copy -- not yet further
--           characterized.
--   0x14, 0x15 -- the NAME-INSERTION mechanism: each sets a WRAM
--           pointer ($D79D for 0x14, $D7A2 for 0x15 -- two different
--           string slots, plausibly hero/heroine or two distinct
--           stored strings) into $D8AA/$D8AB, then bridges into the
--           0xFF sub-table. Very likely the mechanism behind the
--           long-flagged, never-decoded "[0x14]-style speaker tag"
--           VictorySequence.lua's doc comments have referenced since
--           early in this project's history -- the exact string
--           source ($D79D/$D7A2's relationship to NameEntry.lua's save
--           format) is not yet traced.
--   0x16-0x19 -- structured 0x0000 (unused/reserved) table entries --
--           deliberately not control codes.
--   0x1A -- NEWLINE_BYTE, see above -- independently, decisively
--           cross-validated: this byte's handler ($35B0) does
--           newline/line-advance work, matching this file's completely
--           separately-derived text-corpus finding exactly.
--   0x1B -- sets up the text-cursor position pair ($D8B2-$D8B5) from a
--           WRAM base position, then bridges into the 0xFF sub-table's
--           line-clear routine.
--   0x1C-0x1F -- an up/down/left/right TEXT-CURSOR MOVE family --
--           these are the exact same code (file $35C6-$35E3) an
--           earlier, separate "0xFF sub-table" investigation already
--           fully disassembled and named a "cursor-delta dispatcher",
--           now confirmed reachable directly through embedded script
--           text as well.
-- Jump-table targets (kept here for anyone continuing this, not
-- otherwise used by this module): 0x10=$34E7, 0x11=$34F4, 0x12=$3502,
-- 0x13=$351A, 0x14=$357D, 0x15=$3582, 0x1A=$35B0, 0x1B=$35C1,
-- 0x1C=$35C6, 0x1D=$35CD, 0x1E=$35D4, 0x1F=$35DD.

-- STRENGTHENED: the original finding was a single live-VRAM
-- observation ("LP [F6] MP [F6]" matching the live HUD's "LP <n> MP
-- <n>" display), never independently cross-checked a second way.
-- Found a static ROM string containing the exact same pattern -- file
-- offset 0xBE10, decodes cleanly (via this exact module) to "LP
-- [F6]   MP   [F6]Naechster Level" (a German status-menu screen:
-- "Kraft"/"Reife"/"Wille" stat labels immediately precede it,
-- "Naechster Level" = "Next Level" immediately follows) -- a second,
-- genuinely independent confirmation of the exact same meaning, this
-- time from actual ROM text data rather than a live screen read. A
-- second, unrelated occurrence also found in the on-screen name-entry
-- keyboard's static layout string (file ~0xBE6x, immediately before
-- the digit row "01234...") -- a use in a completely different UI
-- screen. Also cross-checked against `rom_profiles.lua`'s `font
-- .extraGlyphs` doc comment: the same linear tile-offset formula
-- already used for `.`/`-`/`!`/`?`/`:` predicts 0xF6's font tile as
-- file `0x22F60` -- directly decoded, and it's a plain diagonal line,
-- not a punctuation glyph -- ruling out "printable character this
-- project just hasn't assigned a name yet" as an alternative
-- explanation. Still reads as an "insert a numeric value here"
-- template/substitution opcode, not a printable character --
-- deliberately not added to decodeByte (would wrongly render it as a
-- literal glyph). What remains genuinely open: which CPU code reads it
-- and how the substitution actually happens (no live trace attempted
-- yet) -- the what is now solidly evidenced, the how is still open.

-- VERIFIED: the "documented two-character dialogue-compression scheme"
-- mentioned (as an unconfirmed reference-project hypothesis) in
-- docs/roadmap.md -- a digraph table living below MAIN_BASE (0xB0),
-- separate from and much larger than the general dialogue text found
-- so far. Found by first locating a completely literal, uncompressed
-- match for "WILLY" (via the already-known MAIN_GLYPHS formula, no
-- compression involved -- proper names/shouted words appear to bypass
-- the table) at ROM file offset 0x3A268, then decoding the ~1KB of
-- script bytes around it. Every entry below was cross-checked against
-- an otherwise-fully-readable German sentence or proper noun spanning
-- 2+ independent occurrences in that dump (e.g. 0x55 confirmed both
-- inside "Willy" and inside "Wasserfaellen" -- two unrelated words,
-- same byte, same 2 letters both times) -- this project's normal
-- VERIFIED bar. See docs/reverse-engineering/text.md for the full
-- byte-by-byte trace.
--
-- Confirmed real examples this table was built from (bytes elided,
-- see text.md for the literal ROM offsets):
--   "Wi[ll]y" / "Wasserfa[e][ll][en]"      -> 0x55="ll", 0x24="en"
--   "W[as][se]rfae[ll][en]"                -> 0x3C="as", 0x3B="se"
--   "V[ie][le]"                            -> 0x2A="ie", 0x39="le"
--   "[un]noetig"                            -> 0x37="un"
--   "[da][be]i"                            -> 0x4E="da", 0x31="be"
--   "[un]noetig[ i]hr" (space folded into the digraph)
--                                          -> 0x3A=" i"
--   "[li]e[ss]en" (0x9F already-known eszett byte reused as "ss" here)
--                                          -> 0x5F="li"
--   "G[em][ma]" (recurs 6+ times in the same dump)
--                                          -> 0x5C="em", 0x5A="ma"
--   "R[it][te]r" (recurs 4+ times)         -> 0x51="it", 0x2F="te"
--
-- Not yet in this table: the dump has many more repeating low-byte
-- values (0x25, 0x28, 0x2B, 0x33, 0x44, 0x46, 0x4A, 0x53, 0x64, 0x69,
-- 0x6A, 0x87, 0xA9, ...) that are almost certainly more digraphs
-- (context makes several of them guessable, e.g. 0x2B likely "ng" in
-- "bezwungen"/"Zwang" contexts) but were not cross-checked against a
-- second independent occurrence yet, so per this project's own bar
-- they stay UNKNOWN rather than guessed. Also UNKNOWN: whether this
-- table's low-byte range overlaps with a *separate* set of script/
-- control opcodes (0x00/0x04/0x12 and friends recur constantly in the
-- same dump in patterns that look like control flow, not text -- see
-- text.md's "control bytes" section) -- this table only claims the
-- specific byte values listed, not the whole sub-0xB0 range.
--
-- VERIFIED (live execution trace, ROM READ watchpoints across a
-- message's raw bytes, see text.md's "0x12 is VERIFIED" section): 0x12
-- is a control byte, not text -- it halts the dialogue engine's
-- forward progress and the game waits for player input once the read
-- pointer reaches it (confirmed: the pointer never advances past it,
-- observed for thousands of frames with zero input). Always followed
-- by a second, variable byte -- verified via a full-region static
-- cross-reference (not just this one message): [0x12][0x11] closes the
-- dialogue and returns to gameplay (30+ clean, unambiguous item-pickup
-- messages, "<Item> gefunden [0x12][0x11]", each a complete standalone
-- interaction with nothing following); [0x12][0x1B] closes the current
-- box but immediately shows the next queued box in the same
-- conversation (18 confirmed instances of "[0x12][0x1B]<Name>[0x2C]"
-- with 6 different named speakers -- Cibba, Bogard, Julia, Willy,
-- Sarah, Davias -- 0x2C appears to be a "speaker name:" tag delimiter,
-- the same shape used for the hero's own lines via 0x14 below). This
-- matches an earlier live-input test exactly: pressing input after a
-- "[0x1B]" page jumped straight to the next page's content instead of
-- returning control, while every "[0x11]" case in this dump is a short
-- one-off message with nothing to jump to. A third, rarer variant,
-- [0x12][0x13], recurs only twice in the dialogue region (vs. 30+/18+
-- for the other two) -- both times immediately after a "?" or "!",
-- suggestively (not confirmed) a yes/no-choice-prompt marker; left as
-- an open hypothesis, not enough contexts yet to call it. Deliberately
-- not added to decodeByte -- 0x12 already correctly falls through to
-- nil (unknown/non-text) with no change needed; this note exists so a
-- future reader doesn't mistake 0x12/0x11/0x1B/0x13 for unassigned
-- digraph slots still waiting to be filled in.
--
-- VERIFIED (same pass): 0x14 is a control byte, not a digraph -- it's
-- the HERO NAME substitution token (this project's `storyPages[1]`
-- already used "%s" for exactly this role). Confirmed two ways: (1)
-- mid-sentence substitution, e.g. "[14] i[2D][42]in \ntapferer
-- Kämpfer."="<Name> ist ein\ntapferer Kämpfer." (a fully grammatical
-- German sentence); (2) as a SPEAKER TAG, used exactly like the other
-- characters' literal names before 0x2C -- e.g.
-- "[14][2C]Bogard!"="<Name>: Bogard!" (the hero calling out to Bogard)
-- and "[14][2C]Ja,..aber.."="<Name>: Ja,..aber.." -- i.e. the hero's
-- own dialogue lines are tagged with this same placeholder rather than
-- a literal name, consistent with the mid-sentence use.
-- [0x58]="or" -- confirmed via the end-of-credits screen's staff
-- names, decoded consistently across two unrelated words:
-- "Yosh[0x29][0x58]i Kitase" = "Yoshinori Kitase" (a real, verifiable
-- Seiken Densetsu 1 staff credit) and "G[0x58]o O[?]shi" = "Goro
-- O[?]shi" (LANDKARTE/map credit) -- same byte, same 2 letters, two
-- unrelated names, this project's normal VERIFIED bar.
TextDecoder.DIGRAPH_PARTIAL = {
  -- HYPOTHESIS: `0xFC` is a high-frequency blocker (149 occurrences in
  -- the main dialogue region, 0x34800-) whose surrounding context is
  -- unusually noisy (heavily intermixed with still-undecoded
  -- control-code-shaped bytes), unlike most other entries in this
  -- table. Ranked all 149 occurrences by "how many neighboring bytes
  -- already decode cleanly" and tested a TRIGRAPH candidate (not a
  -- digraph -- genuinely different shape from every other entry here,
  -- but "sch" is an extremely common German 3-letter combination, a
  -- plausible dedicated compression code) against the cleanest
  -- results: 2 independent, clean hits, neither needing a borrowed
  -- letter from an adjacent (still-undecoded) byte --
  -- `"na" .. [FC] .. "en"` = "naschen" (to snack/nibble, file 0x3a25b)
  -- and `[FC] .. "au"` = "schau" (look!, file 0x350d2, directly
  -- preceding a speaker-tag transition, "Lester:"). No occurrence
  -- among the 30 cleanest contradicts this reading. NOT promoted to
  -- VERIFIED: only 2 independent words (this project's usual bar is
  -- "2+", but every other VERIFIED entry here has stronger,
  -- often-3+-occurrence support), no live/independent cross-check, and
  -- an unresolved competing observation: `0xFC` also appears unusually
  -- often immediately adjacent to speaker-tag transitions across
  -- several other occurrences (not just the "schau" one), which could
  -- also be read as "this byte plays a formatting/control role near
  -- textbox boundaries" rather than being a plain letter -- not ruled
  -- out, left honestly unresolved.
  --
  -- IMPORTANT DOMAIN CAVEAT (see docs/reverse-engineering/text.md's
  -- "The script-driven typewriter parser" section for the full
  -- disassembly): the script-driven typewriter-tick handler (opcode
  -- 0x04, ROM `$333D`) decisively sends every byte `>= 0x99` --
  -- including 0xFC -- to a separate non-text control path (`$3480`),
  -- never the character table, in that code path. This does NOT
  -- retract "sch" here: this table models the static message-text
  -- blob decode (`TextDecoder.decodeString`), a different, not-yet-
  -- located ROM routine, and the two domains are already
  -- independently confirmed to diverge over this exact byte range
  -- (0x99-0x9B are verified umlauts Ä/Ö/Ü in this static domain -- see
  -- UMLAUT_PARTIAL above -- while the script-tick domain sends that
  -- same range to `$3480`). Read: the same byte value can carry
  -- different meanings in the two domains, and this entry only claims
  -- the static one.
  [0xFC] = "sch",

  [0x24] = "en",
  [0x2A] = "ie",
  [0x2F] = "te",
  [0x31] = "be",
  [0x37] = "un",
  [0x39] = "le",
  [0x3A] = " i",
  [0x3B] = "se",
  [0x3C] = "as",
  [0x4E] = "da",
  [0x51] = "it",
  [0x55] = "ll",
  [0x58] = "or",
  [0x5A] = "ma",
  [0x5C] = "em",
  [0x5F] = "li",
  -- CONFIRMED: a full-ROM lenient scan (this project's established
  -- digraph-cross-referencing technique, now run systematically
  -- instead of against one opportunistic 1KB window) found a much
  -- larger dialogue block than previously known (file range roughly
  -- `0x34800`-`0x3B000`, the full Willy/Dark-Lord/Bogard story
  -- sequence) -- see docs/reverse-engineering/text.md's new section
  -- for the full derivation of each entry below, each confirmed via 2+
  -- independent words/names, same rigor bar as the original 15.
  [0x23] = "er", -- "H[23]r"="Herr" (x2+), "tapf[23][23]"="tapferer", "Kämpf[23]"="Kämpfer"
  [0x25] = "n ", -- "abe[25]das"="aben das" (Sie haben das), "obe[4F][25]"="oberen " (space-inclusive digraph, same shape as 0x3A)
  [0x29] = "in", -- "E[29] Jun[2B]e"="Ein Junge", "E[29][52]äd-"="Ein Mäd-(chen)" -- promotes the earlier single-occurrence "Yoshinori" hypothesis to VERIFIED
  [0x2B] = "ge", -- "bezwun[2B]n"="bezwungen" (x2, two different sentences), "Jun[2B]e"="Junge"
  [0x34] = "an", -- "G[34]z"="Ganz" (in "Herr! Ganz oben..."), "hinten [34]gegriffen"="angegriffen"
  [0x3F] = "he", -- "hier[3F]r?"/"Komm hier[3F]r!"="hierher" (x2, "Komm hierher!" and a standalone "hierher?")
  [0x47] = "ar", -- "W[47]te...ier"="Warte hier", "Bog[47]d"="Bogard" (a real character name, 20+ identical occurrences)
  [0x4C] = " b", -- "Zyklop[4C]ezwungen"/"Garuda[4C]ezwungen"/"Chimä[4F][4C]ezwungen"="...bezwungen" (3 different monster names, space-inclusive)
  -- REVISED (after a digraph table conflict was presented -- see this
  -- table's header note): was "a" (25+ occurrences of "Juli[5B]", read
  -- as "Julia"). The ROM digraph table (`$3F3F`, formula proven
  -- against ~85 other entries with zero exceptions) reads this byte as
  -- "us" -- i.e. the name is really "Julius", not "Julia". This also
  -- reads more grammatically natural in the flagship regression
  -- sentence ("Was hast du ihr angetan, Julius?" = "What have you done
  -- to HER, Julius?" -- Julius asked about a third person, "ihr"/her,
  -- rather than Julia implausibly being asked about herself in the 3rd
  -- person). Chose to trust the disassembly-proven table over the old
  -- pattern-matched guess. See text.md's "FOUND: the digraph lookup
  -- table" section for the full evidence trail; every doc/comment
  -- elsewhere in this project that still says "Julia" for this
  -- character reflects the old, now-corrected reading and should be
  -- read as "Julius" instead.
  [0x5B] = "us", -- "Juli[5B]"="Julius" (a real character name, 25+
  -- identical occurrences)
  -- RESOLVED (was: "newly found contradiction", checked while hunting
  -- secondRoom's "Amanda" dialogue -- direct user report that this
  -- must clearly read "Ausrüstung"): this byte already wanted "us"
  -- (not "a") in every one of 5 independent words that pass found --
  -- "A[5B]rüstung"="Ausrüstung" (equipment), "Da[8E][5B]"="Daraus"
  -- (from that), "[8E][5B]!"="raus!" (get out, Amanda's own line),
  -- "gr[8E][5B]a[82]r"="grausamer" (crueler),
  -- "gr[8E][5B]am!"="grausam!" (terrible!) -- all clean, all real. At
  -- the time this was left as a genuinely-contradictory, not-force-
  -- picked open question against the "Julia" reading (same shape as
  -- `0x82` below). The ROM digraph table found later (see this table's
  -- header note) settles it: "us" is correct -- these 5 words were
  -- right all along, and "Julia" was a mis-read (really "Julius", see
  -- the revision above).
  [0x65] = " h", -- "Sie[65]abe[25]das"="Sie haben das", "W[47]te[65]ier"="Warte hier" (space-inclusive, same shape as 0x3A/0x25)
  [0x6E] = "mm", -- "Willko[6E]en"="Willkommen" (x2), "entko[6E]en"="entkommen", "Ko[6E][65]ier[3F]r"="Komm hierher"
  [0x88] = "Da", -- "[88]rk Lord"="Dark Lord" (10+ identical occurrences) -- first confirmed CAPITALIZED 2-letter code, a proper noun/title
  -- CONFIRMED: found while resolving 0x12 (see text.md's "0x12 is
  -- VERIFIED" section) -- two DIFFERENT words each, same rigor bar as
  -- the rest of this table:
  [0x21] = "de", -- "gefun[21]n"="gefunden" (30+ item-pickup messages,
  -- each with a different item name before it: "Bonbon gefunden",
  -- "Bronze gefunden", "Gold gefunden", "Elixier gefunden", ...) AND,
  -- a genuinely different word, "fin[21][43].."="finden" ("to find",
  -- not "gefunden") -- this second reading also cross-confirms the
  -- previously-single-occurrence 0x43="n" hypothesis, promoted to
  -- confirmed alongside it (see below).
  [0x43] = "n", -- single-LETTER code, not a digraph (same shape as the
  -- already-established single-letter 0x5B="a" lead). Two independent
  -- words: "fin[21][43]"="finden" (see 0x21 above) and the original
  -- single-occurrence lead "ihr Lebe[43]"="ihr Leben" ("their life",
  -- real end-of-credits-adjacent lore text) -- promoted from HYPOTHESIS
  -- (see the old note further below, now resolved) to confirmed.

  -- CONFIRMED: a systematic pass, not opportunistic spot-checks --
  -- every byte below 0xB0 that appears in a "fill-in-the-blank" word
  -- (all OTHER bytes in that word already decode) was collected across
  -- the entire real dialogue region (file 0x34800-0x3B000, see text.md),
  -- deduplicated by template, and solved against real German vocabulary
  -- with this project's own bar: 2+ DIFFERENT words/contexts, verified
  -- by re-decoding the WHOLE region with the candidate table applied and
  -- checking the result reads as coherent German prose (not just that
  -- one isolated word parses) -- full trace, evidence, and the couple of
  -- genuinely unresolved leads left over in text.md. 29 new entries,
  -- more than doubling this table's prior coverage.
  [0x20] = "ch", -- MASSIVE confirmation, 15+ independent words:
  -- "S[20]luessel"="Schluessel" (key), "Men[20 via 0x64+this]..." see
  -- below, "verantwortli[20]"="verantwortlich", "gefaehrli[20]"=
  -- "gefaehrlich", "suedli[20]en"="suedlichen", "Maed[20]en"=
  -- "Maedchen" (girl), "S[20]ild"="Schild" (shield), "S[20]iff"=
  -- "Schiff" (ship), "Au[20]"="Auch" (also), "Ho[20]"="Hoch" (high),
  -- "su[20]e"="suche" (search), "Eide[20]sen"="Eidechsen" (lizards),
  -- "Wo bin i[20]"="Wo bin ich" (where am I), "Soll i[20]"="Soll ich".
  [0x22] = "e ", -- space-inclusive, 3 words: "Harf[22]verklang"=
  -- "Harfe verklang" (the harp faded), "Ein[22]Faelschung"="Eine
  -- Faelschung" (a forgery), "Enthuell[22]den"="Enthuelle den" (reveal
  -- the..., imperative).
  [0x26] = "r ", -- space-inclusive, 8+ words: "de[26]Spiegel"="der
  -- Spiegel" (the mirror), "zu[26]Arbeit"="zur Arbeit" (to work),
  -- "E[26]wohnt"="Er wohnt" (he lives), "E[26]spielt"="Er spielt" (he
  -- plays), "Silbe[26]gefunden"="Silber gefunden" (silver found),
  -- "de[26]letzte"="der letzte" (the last), "Ritte[26]soll"="Ritter
  -- soll", "uebe[26]Wasse[26]laufen"="ueber Wasser laufen".
  [0x28] = "t ", -- space-inclusive, 4+ words: "Trit[28]vor"="Tritt
  -- vor" (step forward), "benoetig[28]man"="benoetigt man", "Klapp
  -- [28]das"="Klappt das" (does it work?), and self-consistently the
  -- recurring place name "Jad[28]..."="Jadt..." (4 independent
  -- sentences, always the same spelling).
  [0x2D] = "st", -- 12+ words, this table's single best-confirmed
  -- entry this pass: "Sie i[2D]"="Sie ist", "Wer i[2D]"="Wer ist",
  -- "Was i[2D]"="Was ist", "Julia i[2D]"="Julia ist" (=X ist, x4),
  -- "wue[2D]e"="wueste" (desert), "ro[2D]ige"="rostige" (rusty),
  -- "gelang[2D]"="gelangst", "loe[2D]"="loest", "selb[2D]"="selbst",
  -- "_aerkte"="staerkte".
  [0x2E] = "ei", -- 8+ words: "Willkommen b[2E]"="Willkommen bei",
  -- "N[2E]n"="Nein" (no, x2), "z[2E]gt"="zeigt" (shows), "B[2E]"="Bei"
  -- (at/by), "beim"="b[2E]m", "Be[2E]lung"="Beeilung" (hurry!),
  -- "Verz[2E]hung"="Verzeihung" (pardon), "[2E]nzige"="einzige" (only).
  [0x30] = "d", -- 10+ words, all single-letter: "Folge[30]em"="Folge
  -- dem", "Hoehle[30]er"="Hoehle der", "in[30]er"="in der", "in[30]em"
  -- ="in dem", "bei[30]en"="bei den", "Hol[30]ie"="Hol die", "Mit[30]em"
  -- ="Mit dem", "Soll[30]as"="Soll das".
  [0x33] = "s ", -- space-inclusive, 9+ words: "da[33]Giftgas"="das
  -- Giftgas", "Da[33]legen(daere)"="Das legen...", "Da[33]boese"="Das
  -- boese", "Giftige[33]Gas"="Giftiges Gas", "Lord[33]Zimmer"="Lords
  -- Zimmer" (genitive -s), "de[33]Dark"="des Dark(Lord)" (genitive),
  -- "un[33]damals"="uns damals".
  [0x36] = "es", -- 4 words: "L[36]ter"="Lester" (character name),
  -- "All[36]"="Alles" (everything/all clear), "Julia b[36]iegt"=
  -- "Julia besiegt" (Julia defeats), "Kary b[36]iegt"="Kary besiegt".
  [0x3D] = "d", -- single letter, lowercase: "Der[3D]unkle"="Der
  -- dunkle" (the dark, e.g. "der dunkle Turm"), and self-consistently
  -- "Siehst[2D][3D][49]da[33]rie..."="Siehst du das rie(sige)..." (do
  -- you see the huge...) once combined with 0x2D/0x49 below. Also
  -- appears as "[3D]avias"="davias", almost certainly the character
  -- name "Davias" auto-capitalized by the game's own text renderer at
  -- sentence-start (this table only claims the literal byte value, not
  -- how the display layer capitalizes it -- flagged honestly, not
  -- silently assumed).
  [0x3E] = "au", -- 7+ words: "Blockz[3E]ber"="Blockzauber", "Bombenz
  -- [3E]ber"="Bombenzauber", "Flammenz[3E]ber"="Flammenzauber", "Z[3E]
  -- ber"="Zauber" (spell, standalone), "Gen[3E]"="Genau" (exactly), "H
  -- [3E]se"="Hause" (nach Hause = go home), "[3E]ftanken"="auftanken"
  -- (refuel).
  [0x41] = ", ", -- comma+space, promoted from the earlier single-
  -- occurrence HYPOTHESIS (see the old note further below) to
  -- VERIFIED: 10+ words, e.g. "klar[41]Junge"="klar, Junge", "Ja[41]
  -- das"="Ja, das", "Vielen[41]vielen"="Vielen, vielen (Dank)",
  -- "Warte[41]"="Warte,", "Ja[41]Herr"="Ja, Herr".
  [0x45] = "du", -- 3 words: "[45]nklen Turm"="dunklen Turm" (x2),
  -- "[45] hast"="du hast" (mid-sentence).
  [0x49] = "u ", -- space-inclusive, 4 words: "z[49]der"="zu der" (to
  -- the), "z[49]zer(stoeren)"="zu zerstoeren", "z[49]sein"="zu sein",
  -- "Z[49]spaet,"="Zu spaet," (too late, capitalized).
  [0x4F] = "re", -- 7+ words: "Chimae[4F]"="Chimaere" (chimera
  -- monster), "unse[4F]"="unsere" (our), "legendae[4F]"="legendaere"
  -- (legendary), "Tie[4F]"="Tiere" (animals), "Jah[4F]n"="Jahren"
  -- (years), "wiede[4F]rlangen"="wiedererlangen" (regain).
  [0x50] = "ir", -- 3 words: "W[50]"="Wir" (we), "P[50]a bezwungen"=
  -- "Pira bezwungen" (a monster name), "M[50]yon Tin Qua..." (a fantasy
  -- place name) -- consistent with the earlier single-occurrence
  -- "Saph[50]..." = "Saphir" lead from the messageID-13 item cluster
  -- (see text.md's dispatcher-investigation section), now promoted.
  [0x53] = "tt", -- promoted from the earlier single-word-only lead
  -- (see the old note further below): 3 INDEPENDENT words this pass --
  -- "Amule[53]"="Amulett", "Wa[53]s"="Watts" (a real Seiken Densetsu
  -- character, the dwarven smith), "Mu[53]er"="Mutter" (mother).
  [0x54] = "m ", -- space-inclusive, 4 words: "Gole[54]bezwungen"=
  -- "Golem bezwungen" (golem defeated), "Hoehle i[54]Sumpf"="Hoehle im
  -- Sumpf" (cave in the swamp), "Lori[54]an"/"Lori[54]befindet"=
  -- "Lorim an"/"Lorim befindet" (place name "Lorim"), and (dative,
  -- NOT the strong "giftiges" form) "giftige[54]Gas"="giftigem Gas".
  [0x59] = "Ma", -- capitalized, 2-letter: part of "Mana" (see 0x87
  -- below) PLUS its own standalone use "[59]rcie"="Marcie" (a
  -- character name, the Turm/tower-collapse NPC).
  [0x5D] = "al", -- 4 words: "H[5D]lo"="Hallo" (hello, recurring
  -- greeting), "Kor[5D]len"="Korallen" (coral, Korallenkueste), "f[5D]
  -- len"="fallen" (fall), "[5D]lein"="allein" (alone).
  [0x5E] = "W", -- capital single letter, 5 words: "[5E]illkommen"=
  -- "Willkommen", "[5E]as"="Was" (What), "[5E]ILLY"="WILLY", "[5E]ie"=
  -- "Wie" (How), "[5E]arum"="Warum" (Why).
  [0x60] = "t", -- single letter, 4 words: "Jad[60]"="Jadt" (place
  -- name, matches 0x28 above), "Stad[60]"="Stadt" (city), "gefuell
  -- [60]"="gefuellt" (filled), "Antwor[60]"="Antwort" (answer).
  [0x64] = "sc", -- 5+ words: "Luft[64]hiff"="Luftschiff" (airship),
  -- "Aut[64]h"="Autsch" (ouch!), "Men[64]hen"="Menschen" (people, x3),
  -- "Fael[64]hung"="Faelschung" (forgery, cross-checks 0x22 above).
  [0x6B] = "et", -- 3 words: "j[6B]zt"="jetzt" (now), "R[6B]te"=
  -- "Rette" (save/rescue, imperative), "J[6B]zt"="Jetzt" (Now, caps).
  [0x6D] = " v", -- space-inclusive, 3 words: "Ruinen[6D]on Vandol"=
  -- "Ruinen von Vandol" (ruins of Vandol), "Koenig[6D]on Van(dol)"=
  -- "Koenig von Vandol" (king of Vandol), "Julia[6D]er..."="Julia
  -- ver..." (start of a verb, self-consistent).
  [0x83] = " G", -- space+capital-G, 3 words: "Ein[83]lueck,"="Ein
  -- Glueck," (what luck!), "giftige[83]as"="giftige Gas" (weak
  -- adjective form, after "das" -- cross-checks 0x54's dative reading),
  -- "Der[83]emma"="Der Gemma (Ritter)" (matches the already-known
  -- recurring "Gemma Ritter" phrase).
  [0x84] = "ac", -- found hunting secondRoom's `characterA` NPC line
  -- offset ("Der Monsterein-\ngang führt n[84]h \ndraußen." -- needs
  -- "ac" to complete "nach", German "to/toward"). Comfortably clears
  -- this project's "2+ independent occurrences" bar -- 0x84 recurs at
  -- least 6 times in genuinely different
  -- sentences, every one needing exactly "ac": "M[84]ht kann\nnur
  -- einer widerstehen"="Macht kann nur einer widerstehen" (power only
  -- one can resist), "Sensenmann bew[84]ht"="Sensenmann bewacht"
  -- (guarded by a reaper), "seine wahre M[84]ht"="seine wahre Macht"
  -- (its true power), "Passage n[84]h\nNorden"="Passage nach Norden"
  -- (passage to the north), "gewaltige M[84]ht"="gewaltige Macht"
  -- (immense power) -- "Macht"/"nach"/"bewacht" each independently,
  -- self-consistently needing the same "ac" fill every time.
  [0x87] = "na", -- capitalized-pair partner of 0x59: together they
  -- spell "Mana", this ROM's own central Seiken Densetsu lore term
  -- (Sword/Tree of Mana). The exact 2-byte sequence `[0x59][0x87]`
  -- recurs 21 TIMES across the whole dialogue region, in genuinely
  -- different compounds/sentences -- "Mana-Amulett" (the key item),
  -- "des Mana" (genitive), "Macht/Kraft des Mana" (power of Mana,
  -- the plot's central theme), "Mana-Schrein". Solved by decoding the
  -- WHOLE region with this table applied and recognizing the same
  -- meaningful, thematically-central word recurring, not a single
  -- isolated guess.
  [0x89] = "a ", -- space-inclusive, 6+ words, all proper names/
  -- adverbs needing a trailing space: "Cibb[89]"="Cibba " (character
  -- name, x3), "Gai[89]"="Gaia " (place/character name, x2), "Meda
  -- [89]"="Medaa " (character name, x2, matches the ALREADY fully-
  -- spelled-out "Medaa" seen elsewhere with 2 literal a's), "N[89]gut"
  -- ="Na gut" (well, okay).
  [0x8E] = "ra", -- 4 words, including the ORIGINAL single-occurrence
  -- lead from the `$1F64` dispatcher investigation (see text.md,
  -- messageID 13's "Sma[8E]g[6A]d gefunden"="Smaragd gefunden"):
  -- "t[8E]urig"="traurig" (sad), "d[8E]ussen"="draussen" (outside),
  -- "t[8E]uen"="trauen" (to trust).

  -- A second round the SAME pass, chasing bytes uncovered only once the
  -- table above was already applied (their own words were unreadable
  -- garbage until then):
  [0x35] = "ic", -- 3 words -- CROSS-CHECKED against the credits screen
  -- to resolve a genuine boundary ambiguity: "[35][38]war"/"re[35][38]"
  -- alone are equally consistent with either 0x35="i"+0x38="ch " or
  -- 0x35="ic"+0x38="h " (both produce "ich war"/"reich"). Tie broken by
  -- the ALREADY-known credits-screen name "Ko[35]hi Ishii" (file
  -- 0x3b986) -- only 0x35="ic" gives the real name "Koichi Ishii" (a
  -- real, verifiable Seiken Densetsu 1 credit); 0x35="i" would give the
  -- wrong "Koihi Ishii". Confirms 0x35="ic", 0x38="h " (not the other
  -- split).
  [0x38] = "h ", -- space-inclusive, 3+ words (see 0x35 above for the
  -- boundary resolution): "[8D][38]bin"="Ich bin" (I am), "[8D][38]
  -- moechte"="Ich moechte" (I would like), "[8D][38][8C]be"="Ich habe"
  -- (I have, using 0x8C="ha" and 0x8D="Ic" below).
  [0x69] = "we", -- 3 words: "Z[69]rgenhoehle"="Zwergenhoehle" (dwarf
  -- cave -- Watts the dwarven smith's home), "Kommt [69]gen"="Kommt
  -- wegen" (comes because of), "Sch[69][80]"="Schwert" (sword, the
  -- legendary weapon, x3, using 0x80 below).
  [0x6A] = "d ", -- space-inclusive: PROMOTES the earlier HYPOTHESIS-
  -- only lead (see the old note further below, and the `$1F64`
  -- dispatcher investigation's own "Smaragd gefunden" reading) with
  -- 4 MORE independent contexts this pass: "un[6A]du"="und du" (and
  -- you), "un[6A]beschuetze"="und beschuetze" (and protect), "Lor[6A]
  -- besiegt"="Lord besiegt" (as in "Dark Lord besiegt"), "wir[6A][86]r
  -- helfen"="wird ihr helfen" (will help her, x2, using 0x86 below).
  [0x80] = "rt", -- 2 words: "Sch[69][80]"="Schwert" (sword, x3, see
  -- 0x69 above) and "O[80] heute"="Ort heute" (place, today).
  -- REVISED: was "ih" (from "wir[6A][86]r helfen"="wird
  -- ihr helfen", will help her, x2) -- a conflict against the ROM
  -- digraph table (`$3F3F`, see this table's header note), which reads
  -- this byte as "Di". Applying the same standard chosen for the
  -- 0x5B/"Julia"->"Julius" conflict above (the table is a proven,
  -- structural source, not per-byte word-count dependent):
  -- "wir[6A]Dir helfen"="wird Dir helfen" (will help YOU, capitalized
  -- formal "Dir") is equally natural German and now the one this table
  -- uses.
  [0x86] = "Di", -- "wir[6A][86]r helfen"="wird Dir helfen" (will help
  -- you, formal, x2, see 0x6A above).
  [0x8D] = "Ic", -- capitalized, 3-letter, paired with 0x38 above
  -- forming "Ich" (I) -- see 0x35's own note for why this split (not
  -- "I"+"ch ") is the one the credits cross-check supports: 3+
  -- contexts, "Ich bin", "Ich moechte", "Ich habe" (different verbs
  -- each time, satisfies this table's own "different word" bar despite
  -- the shared pronoun).
  [0x8F] = "eg", -- 3 words, independent of 0x6C below: "li[8F]t"=
  -- "liegt" (lies/is located, a recurring "X liegt im Sueden"
  -- pattern), "W[8F]"="Weg" (path/way), "L[8F]end"="Legend-" (start of
  -- "legendaer", legendary).
  [0x6C] = "si", -- 7+ INDEPENDENT dialogue-region words, found only
  -- after 0x8F above was already resolved (these were unreadable
  -- garbage until then): "be[6C]egt"="besiegt" (defeated, 4 different
  -- monster-defeat messages), "be[6C]egen"="besiegen" (to defeat,
  -- x2, a different grammatical form), "[6C]ch"="sich" (itself,
  -- reflexive pronoun), "be[6C]tzt"="besitzt" (possesses), "kennt
  -- [6C]e"="kennt sie" (knows her), "pas[6C]eren"="passieren" (to
  -- pass). Honest conflict, not hidden: the credits screen has one
  -- counter-example, "Yo[6C]nori Kitase" (file 0x3b6a6), which only
  -- works if 0x6C="shi" (a second, 3-letter spelling of "Yoshinori"
  -- alongside the already-known "Yosh[in][or]i" spelling elsewhere) --
  -- see this table's "still open" notes further below. Given 7+
  -- consistent, unambiguous dialogue-region words against 1
  -- credits-region outlier, "si" is used as this table's value (the
  -- credits screen possibly uses its own, separate local table for
  -- that one special screen -- not confirmed, flagged honestly rather
  -- than assumed).

  -- Third round, same overall pass, resolving what's still open. Re-ran
  -- the same "fill-in-the-blank word" extractor -- resolving the bytes
  -- above unlocked a large new batch of previously multi-gap words
  -- down to single-gap. Each entry below has 2+ independent word
  -- confirmations (compact citations this round, same rigor, less
  -- prose):
  [0x32] = "nd", -- "eindeutig", "Tausendfuessler", "Amanda" (name,
  -- 5x), "verwende", "Waende", "irgendjemand", "irgendwo", "endlich",
  -- "legendaere", "sind" (x2), "Haenden".
  [0x40] = "ne", -- "Traenen"/"Traene" (x3), "schnell", "Deine" (x2),
  -- "Schneewueste", "Keine", "einer" (x3), "schoenen", "Energie",
  -- "ohne", "einem", "Seine".
  [0x42] = " e", -- space-inclusive: "Der einzige", "spiele ein", "in
  -- eine(r)" (x2), "in einem" (x2), "Ruinen entdecken", "empfing",
  -- "Schwert entfaltet", "Zeige es", "ist ein", "ist es", "eine".
  [0x44] = "is", -- "bist" (x3, "du bist"), "ist" (8+x, "Hier ist"/
  -- "Das ist"/...), "Kristall" (crystal), "Auffrischung"
  -- (refreshment), "Eiszauber" (ice spell).
  [0x46] = " s", -- space-inclusive: "sein soll", "er sich", "er
  -- sprach", "es sicher".
  [0x48] = "rd", -- "Ordnung" (x2), "wuerdiger", "noerdlichen"
  -- (northern), "werde" (x3), "werden" (x2).
  [0x4A] = " g", -- space-inclusive: "Sie ging", "Vogel glauben",
  -- "ist gut", "Amulett gestohlen", "muss gerade", "alles geopfert" --
  -- same value as this session's earlier "Sma[8E]g[6A]" cluster's
  -- own unconfirmed "[4A]" lead, now promoted.
  [0x4B] = "ht", -- "Gesicht" (face), "Vernichte", "nicht" (7+x, the
  -- most common German negation), "bluehte", "ueberreicht",
  -- "erreichte".
  [0x4D] = " w", -- space-inclusive: "flog westwaerts", "du willst",
  -- "wieder" (x2), "retten wird", "wird" (x3), "dem wahren", "weit",
  -- "willst du", "wir werden", "wahren".
  [0x52] = " M", -- space+capital, space-inclusive: "viele Maedchen",
  -- "Davias Mutter", "Der/Werden Mana Baum" (x2), "bin Marcie" (a
  -- character name, cross-confirms the already-established 0x59="Ma"
  -- Mana/Marcie cluster), "Ein Maedchen".
  [0x56] = "el", -- "Keller" (cellar), "helfen" (x2), "Wurzeln"
  -- (roots), "Pickel" (pickaxe), "Welt" (world, x2), "Teufelskreis"
  -- (vicious cycle). Also resolves the place name spelled "Topp[56]!"
  -- as "Toppel" -- a Germanized form, not the English original
  -- "Topple" (real ROM evidence outweighs an assumption imported from
  -- the English original game).
  [0x57] = " m", -- space-inclusive: "Sie muessen"/"Wir muessen"
  -- (x3), "Schlage mit", "Gib mir", "lass mich", "Schau mal" (common
  -- phrase), "entkommst mir".
  [0x61] = " n", -- space-inclusive: "Waffen nutzen", "faellen nahe",
  -- "nur ein", "Meer nordoestlich", "So nimm".
  [0x62] = "nn", -- "Sensenmann" (Grim Reaper monster), "Mann" (man),
  -- "koennen"/"konnten" (can/could).
  -- REVISED: was "! " (exclaim+space), based on plausible-but-
  -- explicitly-uncertain context (this entry's original note: "RAUS!"
  -- and "das Boese! Halte durch" fit, but so would a plain "." or
  -- "?"). The digraph table (`$3F3F`, see this table's header note)
  -- reads slot 0x46 as tiles (0xF0,0xFF) -> period+space, and the font
  -- tile bitmap for tile `0x70` is now visually confirmed as a period,
  -- not an exclamation mark (see the punctuation-tiles note above) --
  -- both independent lines of new evidence agree on ". ", overturning
  -- the old admittedly-uncertain guess.
  [0x66] = ". ", -- period+space: "RAUS." (a shouted, all-caps
  -- declaration -- the capitalization alone already carries the
  -- emphasis) and "das Boese. Halte durch" both read naturally; the
  -- ROM digraph table plus the font tile bitmap for `0x70` (see above)
  -- now agree independently, superseding the earlier context-only
  -- guess.
  [0x67] = "ef", -- "Gefuehle" (feelings), "Gefahr" (danger) -- the
  -- SAME value this session's earlier "Saph[50][4A][67]unden" cluster
  -- already flagged as an unconfirmed lead, now promoted.
  [0x68] = "mi", -- "Tut mir leid" (I'm sorry), "hinter mir her", "es
  -- faellt mir", "Hoer mir", "Leiste mir", "mir helfen", "mit Watts",
  -- "mit den Fenstern", "mit dem Amulett", "fuer mich", "um mich",
  -- "vermisst", "Familie".
  [0x6F] = " B", -- space+capital, space-inclusive: "Mana Baum" (x3),
  -- "Bruder" (x2), "Berg", "Bogard", "Bowow" (both real character
  -- names), "Boesen".
  [0x81] = " a", -- space-inclusive: "alten Mine", "Schwert ab", "Gib
  -- acht" (pay attention), "Hau ab" (get lost), "du allein wirst",
  -- "wir alle", "vertrieb auch".
  [0x85] = "di", -- "dieses"/"diesem"/"dieser" (x5+), "Freundin",
  -- "die" (relative/article, several), "Entschuldigung" (sorry).
  [0x8A] = "eh", -- "Gehst du", "steht", "Mehr", "Gehe" (x3),
  -- "zurueckgekehrt" (returned), "bestehen", "stehen", "Geheim(nis)".
  [0x8B] = "ns", -- "Hoehlenmonster", "kannst" (x2), "Morgenstern"
  -- (mace weapon), "kennst".
  [0x8C] = "ha", -- "habe" (5+x), "vorbehalten", "erhalten", "haben",
  -- "hat" (x2), "halte", "festgehalten", "verhalf", "Spitzhacke"
  -- (pickaxe), "geschaffen", "Charakter", "Unterhaltung", "schaffe",
  -- "geschah", "Chance".
  -- RESOLVED (once the decode table was found by disassembly, see
  -- text.md's "FOUND: the static message-text decoder" section):
  -- `0x82` was previously left unmapped on purpose (see the retired
  -- note this replaces) because dynamic word-matching found it
  -- "genuinely contradictory" across occurrences. The ROM digraph
  -- table (`$3F3F`, bank 0) has now been located and read directly --
  -- it is a static lookup table, so the same input byte can never
  -- legitimately decode two different ways; the earlier "contradiction"
  -- was a transcription/attribution mistake in that pass, not a
  -- genuine ambiguity. Ground truth: `0x82` decodes to "me" (table
  -- slot `0x82-0x30=0x52`, tiles `0x40,0xD8` -> `m`,`e`), matching the
  -- one reading a narrower sample had already found independently.
  [0x82] = "me",

  -- FOUND: the ROM digraph decode table itself, ROM `$3F3F` (fixed
  -- bank 0, file offset == CPU address). Located by disassembling the
  -- static-text decode dispatcher (`$3777`, see text.md) down to its
  -- digraph-render routine (`$34A4`, already known from the earlier
  -- script-tick-parser pass): `HL=0x3F3F`, then `A = inputByte - 0x20`,
  -- `HL += A*2` -- a 2-bytes-per-entry lookup table indexed directly by
  -- the input byte for `0x20-0x7F`. Each entry's 2 bytes are VRAM tile
  -- IDs (normalize with the same proven `t>=0x80 -> t XOR 0x80` rule as
  -- the outer single-glyph formula, then read through the same
  -- MAIN_GLYPHS/space/`!` tile convention). Cross-checked against every
  -- one of this table's ~85 already-independently-confirmed entries in
  -- the `0x20-0x8F` range: exact match, zero contradictions, for every
  -- entry except 5 pre-existing single-letter codes
  -- (`0x30`,`0x3D`,`0x43`,`0x5E`,`0x60` -- the table technically
  -- encodes a 2nd character there too, a trailing space or (as
  -- corrected below) a period, left as-is below rather than
  -- overwritten since it's unclear whether that 2nd tile actually
  -- renders in practice or is swallowed by word-wrap logic -- attempted
  -- live via injection, inconclusive (see text.md's follow-up section
  -- for why) -- an open follow-up, not resolved by this table alone)
  -- and 2 direct conflicts with earlier single-word dynamic findings,
  -- both since resolved (after presenting the conflict to the user --
  -- see `0x5B`'s and `0x86`'s entries below for the full reasoning):
  -- `0x5B` revised from "a" ("Julia") to "us" ("Julius"), `0x86`
  -- revised from "ih" to "Di" (same reasoning, applied for
  -- consistency).
  --
  -- Bytes `0x80-0x8F` alias the same table slots as `0x70-0x7F`
  -- (verified: both formulas index the identical bytes) via a `-0x10`
  -- remap for `inputByte >= 0x80` (the same remap the script-tick
  -- handler's `$333D` already showed) -- i.e. `0x70` and `0x80` decode
  -- identically on purpose, not a bug in this reading.
  -- PUNCTUATION TILES IDENTIFIED: rendered the font tile bitmaps
  -- directly from ROM (same `0x22900 + (vramTile-0x10)*16` formula the
  -- umlaut tiles above were confirmed with -- see text.md). Visually
  -- unambiguous: tile `0x70`=period (a single small dot),
  -- `0x71`=colon (two dots), `0x72`=hyphen (one flat bar),
  -- `0x73`=exclamation mark, `0x74`=question mark. This corrects an
  -- earlier guess in this table's history that read tile `0x70` as `!`
  -- (cross-checked, wrongly, against the existing `0x66="! "` entry
  -- below -- see that entry's note for the resulting flagged
  -- conflict). Tiles `0x76`-`0x7E` are not punctuation or letters at
  -- all -- their bitmaps are clearly fragments of one larger image
  -- (diagonal lines, box-drawing bars) spanning multiple tiles, not
  -- individual glyphs; no digraph entry in this table actually lands
  -- on any of them, so this doesn't change any decode, just rules out
  -- ever reading them as text.
  [0x27] = "..", -- table slot 0x07 (tiles 0x70,0x70) -- a doubled
  -- period; unverified against a live word (no clean example found
  -- this pass), but a direct, unambiguous table read like every other
  -- entry here, now using the visually-confirmed tile identification.
  [0x63] = "ng", -- table slot 0x43 (tiles 0xE1,0xDA) -- matches the
  -- earlier, independently-found dynamic hypothesis exactly (text.md:
  -- "mostly ng (3 clean words...)"), and resolves that pass's "one
  -- counter-example" as a mis-attribution, not a genuine second
  -- reading (same reasoning as 0x82 above).
  [0x70] = "rt", -- table slot 0x50 (tiles 0xE5,0xE7) -- aliases with
  -- 0x80's already-established "rt" entry above one-for-one, via the
  -- `-0x10` remap note above (0x70 direct == 0x80 remapped, same slot
  -- 0x50) -- an addressable, distinct input byte even though it shares
  -- table content with 0x80.
  [0x71] = " a", [0x72] = "me", [0x73] = " G", [0x74] = "ac",
  [0x75] = "di", [0x76] = "Di", [0x77] = "na", [0x78] = "Da",
  [0x79] = "a ", [0x7A] = "eh", [0x7B] = "ns", [0x7C] = "ha",
  [0x7D] = "Ic", [0x7E] = "ra", [0x7F] = "eg",
  -- ^ 0x71-0x7F: direct table reads (slot=byte-0x20), each aliasing the
  -- corresponding already-established 0x81-0x8F entry above one-for-
  -- one (0x71=" a"==0x81, 0x72="me"==0x82 above, ... 0x7F="eg"==0x8F)
  -- -- addressable, distinct input bytes even though they share table
  -- content with the 0x8X family via the same `-0x10` remap
  -- relationship.
}

-- A now better-understood side-finding from this third round: several
-- of the space-inclusive digraphs found here (0x42=" e", 0x46=" s",
-- 0x4A=" g", 0x4D=" w", 0x52=" M", 0x57=" m", 0x61=" n", 0x6F=" B",
-- 0x81=" a") are exactly the "missing space" cases flagged as an
-- unexplained artifact in the previous round's notes -- most of them
-- turned out to be ordinary space-inclusive digraph codes this pass
-- just hadn't reached yet, not a separate mechanism. A few genuine
-- gaps remain even now (e.g. "in der" decoding as "inder", "auf der"
-- as "aufder") where the space-free forms of "d" (0x30), " B"/etc. get
-- used back-to-back with no space byte at all -- still unexplained,
-- but a much smaller residue than before, and clearly cosmetic rather
-- than a sign of wrong values.

-- Genuinely still open after the systematic pass above (not enough
-- independent, mutually consistent contexts to promote, per this
-- table's 2-independent-words bar) -- recorded as leads, not guessed
-- into the table:
--   0x82 = CONTRADICTORY across its own occurrences ("Klang[82]iner"/
--     "wegen[82]iner" want "e" for "seiner"/"einer"; "Krae[82]rlaeden"
--     wants "ute" for "Kraeuterlaeden"; "bekom[82]n" wants "me" for
--     "bekommen") -- a single fixed byte can't be all three; recorded
--     honestly as unresolved rather than picking the majority reading
--   0x63 = RESOLVED -- see DIGRAPH_PARTIAL's entry above: the ROM
--     digraph table decisively confirms "ng" (eingesperrt, Angriff,
--     eingefroren -- 3 clean, common words). The "one counter-example"
--     this note used to describe ("Watts verkauft\nih[0x86]"+[63]+"e
--     aus Silber") depended on the old 0x86="ih" reading, itself since
--     revised to "Di" (see DIGRAPH_PARTIAL's 0x86 note) -- both the
--     "ng" majority and the apparent "r" counter-example trace back to
--     the same table now, so this was never a real conflict, just
--     built on a since-corrected neighboring byte.
-- (0x52, 0x66, 0x40, and 0x6C used to be listed here too -- see the
-- table above instead, all now resolved with real evidence.)
-- Also: several messages show a MISSING space where grammar expects
-- one even with every byte in this table applied (e.g. "kommstdu",
-- "inder Hoehle") -- real, honestly-observed, NOT yet explained
-- (possibly a genuinely separate "joins the next word with no space"
-- byte this pass didn't isolate) -- flagged for a future pass, not
-- silently smoothed over.


-- HYPOTHESIS ONLY, NOT wired into decodeByte (single-occurrence so far,
-- below this project's 2-independent-confirmations bar -- recorded here
-- as a lead for a future pass, not guessed into the real table).
-- (0x29 and 0x43 used to be listed here too -- both since promoted to
-- the confirmed table above once a second independent word turned up.)
--   0x35 = "ic" (from "Ko[0x35]hi Ishii" = "Koichi Ishii", a real,
--     verifiable Seiken Densetsu 1 director credit -- one occurrence)
--   0x6C = "shi" as a 3-letter (not 2-letter) code (from
--     "Yo[0x6C]n[0x58]i Kitase" = "Yoshinori Kitase", the SAME real
--     name as 0x29's own lead, decoded a second, independent way in a
--     DIFFERENT credit line ("SZENEN" vs "REGIE") -- if real, implies
--     the table isn't uniformly 2-letter, plausible for a compression
--     scheme built around a Japanese-heavy credits screen)
--
-- Found while cross-referencing storyPages[1]'s bytes (same pass
-- 0x21/0x43 came from) -- each fits ONE clean sentence but
-- lacks a second independent word yet, so stays a lead, not a claim:
--   0x2D = "st", 0x42 = " e" (from "[14] i[2D][42]in\ntapferer
--     Kämpfer." = "<Name> ist ein\ntapferer Kämpfer." -- a fully
--     grammatical German sentence with every OTHER byte in it already
--     independently confirmed, strong contextual support even though
--     each byte alone has only this one occurrence so far)
--   0x41 = ", " (from "Oh[41]ja[41]..."="Oh, ja, ..." and
--     "hier[41][64]h[40]ll!!"="hier, schnell!!" -- two plausible but
--     not fully cross-checked contexts, some neighboring bytes in each
--     still unknown)
--   0x6A = "d " (from "un[6A]viele"="und viele", part of this same
--     session's own storyPages[1] bytes, and "Muuun[6A]bet[4F]ten!"
--     read as a drawn-out "Muuund..." -- weaker, second context isn't
--     fully resolved either)
--   0x81 = "vo" (from a recurring "[81]ll" shape in 3 different
--     sentences, plausibly "voll" (full) each time -- not confirmed,
--     surrounding bytes in each case still have other unknowns)
--   0x53 = "tt" (from "Amule[53]"="Amulett" (German spelling, double
--     t), 10+ occurrences -- but always the SAME word; per this
--     project's own bar (2 DIFFERENT words) this alone isn't enough,
--     no second word found yet)

--- Decode a single byte to a string fragment, or nil if it's not (yet)
-- known to be text (an unmapped control byte, or the terminator -- check
-- for TERMINATOR_BYTE separately since decodeByte does not special-case
-- it as "end of string", only as "not a printable character").
function TextDecoder.decodeByte(b)
  if b == TextDecoder.SPACE_BYTE then
    return " "
  end
  if b == TextDecoder.PERIOD_BYTE then
    return "."
  end
  if b == TextDecoder.HYPHEN_BYTE then
    return "-"
  end
  if b == TextDecoder.NEWLINE_BYTE then
    return "\n"
  end
  if b == TextDecoder.EXCLAMATION_BYTE then
    return "!"
  end
  if b == TextDecoder.QUESTION_BYTE then
    return "?"
  end
  if b == TextDecoder.COLON_BYTE then
    return ":"
  end
  if b == TextDecoder.SPEAKER_COLON_BYTE then
    return ":"
  end
  if TextDecoder.UMLAUT_PARTIAL[b] then
    return TextDecoder.UMLAUT_PARTIAL[b]
  end
  if TextDecoder.DIGRAPH_PARTIAL[b] then
    return TextDecoder.DIGRAPH_PARTIAL[b]
  end
  if b >= TextDecoder.MAIN_BASE and b < TextDecoder.MAIN_BASE + #TextDecoder.MAIN_GLYPHS then
    local idx = b - TextDecoder.MAIN_BASE
    return TextDecoder.MAIN_GLYPHS:sub(idx + 1, idx + 1)
  end
  return nil
end

--- Decode a NUL-terminated string starting at `offset` (0-based) in
-- `data`. Stops at TERMINATOR_BYTE, at an unrecognized byte, or at the
-- end of `data`. Returns (text, nextOffset) where nextOffset is one past
-- the terminator (or past the last consumed byte, if no terminator was
-- found before an unrecognized byte / end of data).
function TextDecoder.decodeString(data, offset)
  local chars = {}
  local i = offset
  while i < #data do
    local b = data:byte(i + 1)
    if b == TextDecoder.TERMINATOR_BYTE then
      return table.concat(chars), i + 1
    end
    local ch = TextDecoder.decodeByte(b)
    if not ch then
      return table.concat(chars), i
    end
    chars[#chars + 1] = ch
    i = i + 1
  end
  return table.concat(chars), i
end

return TextDecoder
