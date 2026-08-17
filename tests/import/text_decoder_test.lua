local Harness = require("tests.harness")
local TextDecoder = require("src.import.TextDecoder")
local DevRomLocator = require("tests.dev_rom_locator")
local RomIdentity = require("src.import.RomIdentity")
local RomProfiles = require("src.import.rom_profiles")

local function bytes(...)
  return string.char(...)
end

Harness.test("TextDecoder.decodeByte: main glyph range covers digits/letters/punctuation", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xB0), "0") -- first glyph
  Harness.assertEqual(TextDecoder.decodeByte(0xB0 + 10), "A")
  Harness.assertEqual(TextDecoder.decodeByte(0xB0 + 36), "a")
  Harness.assertEqual(TextDecoder.decodeByte(0xB0 + 63), ",") -- last glyph
end)

Harness.test("TextDecoder.decodeByte: space is 0xFF", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xFF), " ")
end)

Harness.test("TextDecoder.decodeByte: unmapped bytes return nil, not a guess", function()
  Harness.assertEqual(TextDecoder.decodeByte(0x00), nil)
  -- 0x50/0x66 were "ordinary low byte, not text" until the 2026-08-12
  -- digraph-closing passes confirmed them (see DIGRAPH_PARTIAL). 0x82
  -- was this test's own former "still genuinely open" example until
  -- 2026-08-17, when the real ROM digraph table itself was located by
  -- disassembly ($3F3F, see TextDecoder.lua's own note) and read
  -- directly -- a static lookup table can't legitimately disagree with
  -- itself, so "me" is now a disassembly-PROVEN reading, not a guess.
  -- 0x92 takes over as the "still genuinely open" example: even that
  -- same real table doesn't resolve it -- its own tile bytes (0x48,
  -- 0x96) include one that doesn't land on any known glyph, still a
  -- real, honest unknown (see DIGRAPH_PARTIAL's own note on the
  -- 0x90-0x98 sub-range).
  Harness.assertEqual(TextDecoder.decodeByte(0x92), nil)
  Harness.assertEqual(TextDecoder.decodeByte(0x90), nil) -- unconfirmed umlaut slot
end)

-- CORRECTED (2026-08-10): these decoded as 2-letter ASCII substitutions
-- ("oe"/"ae"/...) until a direct user report ("es gibt ein problem mit
-- umlauten") led to decoding the real font tile graphics -- the real
-- glyphs are genuine single umlaut characters (tiles 25-31, immediately
-- before the main font block; see TextDecoder.lua's UMLAUT_PARTIAL doc
-- comment for the full live cross-check). A real improvement, not a
-- regression -- these tests now expect the corrected single-character
-- UTF-8 output.
Harness.test("TextDecoder.decodeByte: confirmed umlaut byte 0x9D decodes", function()
  Harness.assertEqual(TextDecoder.decodeByte(0x9D), "\195\182") -- ö
end)

Harness.test("TextDecoder.decodeByte: confirmed umlaut byte 0x9C decodes (sixth pass, live VRAM read)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0x9C), "\195\164") -- ä
end)

Harness.test("TextDecoder.decodeByte: confirmed period byte 0xF0 decodes (sixth pass, live VRAM read)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xF0), ".")
end)

Harness.test("TextDecoder.decodeByte: hyphen byte 0xF2 decodes (upgraded to VERIFIED, real intro-text scroll)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xF2), "-")
end)

Harness.test("TextDecoder.decodeByte: new umlaut bytes 0x9E/0x9F decode (real intro-text scroll)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0x9E), "\195\188") -- ü
  Harness.assertEqual(TextDecoder.decodeByte(0x9F), "\195\159") -- ß
end)

Harness.test("TextDecoder.decodeByte: uppercase umlaut bytes 0x99-0x9B decode (real name-entry keyboard grid)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0x99), "\195\132") -- Ä
  Harness.assertEqual(TextDecoder.decodeByte(0x9A), "\195\150") -- Ö
  Harness.assertEqual(TextDecoder.decodeByte(0x9B), "\195\156") -- Ü
end)

Harness.test("TextDecoder.decodeByte: exclamation byte 0xF3 decodes (real 'Kaempfe!' battle-intro textbox)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xF3), "!")
end)

Harness.test("TextDecoder.decodeByte: speaker-tag colon byte 0x2C decodes (2026-08-15, task #150)", function()
  -- A DIFFERENT byte from COLON_BYTE (0xF5, credits/shop "label:" role)
  -- -- this one is the real "<SpeakerName>:" tag delimiter used at the
  -- start of dialogue-box lines, 20+ independent named speakers
  -- confirmed via a fresh dump_strings.py --gaps run (Alter, Amanda,
  -- Bogard, Bowow, Cibba, Davias, Glaive, Hasim, Julia, Koenig, Lester,
  -- Lord, Maedchen, Mann, Marcie, Medaa, Mutter, Sarah, Watts, Willy),
  -- plus 6 more after the already-VERIFIED hero-name control bytes
  -- 0x14/0x15 instead of a literal name -- see TextDecoder.lua's own
  -- SPEAKER_COLON_BYTE doc comment for the full evidence trail.
  Harness.assertEqual(TextDecoder.decodeByte(0x2C), ":")
end)

Harness.test("TextDecoder.decodeByte: confirmed digraph-compression bytes decode (2026-08-09, real ROM dialogue trace)", function()
  -- All 15 found by decoding a real ~1KB German dialogue block around
  -- ROM file offset 0x3A268 (see docs/reverse-engineering/text.md) --
  -- each cross-checked against a real, otherwise fully-readable German
  -- word or phrase in 2+ independent occurrences.
  Harness.assertEqual(TextDecoder.decodeByte(0x55), "ll") -- "Willy", "Wasserfaellen"
  Harness.assertEqual(TextDecoder.decodeByte(0x24), "en") -- "liessen", "Wasserfaellen"
  Harness.assertEqual(TextDecoder.decodeByte(0x3C), "as") -- "Wasserfaellen"
  Harness.assertEqual(TextDecoder.decodeByte(0x3B), "se") -- "Wasserfaellen", "muessen"
  Harness.assertEqual(TextDecoder.decodeByte(0x2A), "ie") -- "Viele"
  Harness.assertEqual(TextDecoder.decodeByte(0x39), "le") -- "Viele"
  Harness.assertEqual(TextDecoder.decodeByte(0x37), "un") -- "unnoetig"
  Harness.assertEqual(TextDecoder.decodeByte(0x4E), "da") -- "dabei"
  Harness.assertEqual(TextDecoder.decodeByte(0x31), "be") -- "dabei", "Leben"
  Harness.assertEqual(TextDecoder.decodeByte(0x3A), " i") -- "unnoetig ihr" (space folded in)
  Harness.assertEqual(TextDecoder.decodeByte(0x5F), "li") -- "liessen"
  Harness.assertEqual(TextDecoder.decodeByte(0x5C), "em") -- "Gemma"
  Harness.assertEqual(TextDecoder.decodeByte(0x5A), "ma") -- "Gemma"
  Harness.assertEqual(TextDecoder.decodeByte(0x51), "it") -- "Ritter"
  Harness.assertEqual(TextDecoder.decodeByte(0x2F), "te") -- "Ritter"
end)

Harness.test("TextDecoder.decodeByte: question mark 0xF4 and colon 0xF5 decode (2026-08-10, real credits-screen trace)", function()
  Harness.assertEqual(TextDecoder.decodeByte(0xF4), "?")
  Harness.assertEqual(TextDecoder.decodeByte(0xF5), ":")
end)

Harness.test("TextDecoder.decodeByte: digraph 0x58='or' decodes (2026-08-10, real credits-screen staff names)", function()
  -- "Yoshinori Kitase" / "Goro O?shi" -- two unrelated real names,
  -- same byte, same 2 letters (see docs/reverse-engineering/text.md).
  Harness.assertEqual(TextDecoder.decodeByte(0x58), "or")
end)

Harness.test("TextDecoder.decodeByte: 12 more digraph/single-letter bytes decode (2026-08-11, systematic full-ROM dialogue scan)", function()
  -- Found by running this project's own established digraph-cross-
  -- referencing technique systematically (a full lenient scan of the
  -- whole real Willy/Dark-Lord/Bogard story sequence, file range
  -- roughly 0x34800-0x3B000 -- MUCH larger than the original
  -- opportunistic 1KB window) instead of by hand on one small dump.
  -- Every entry has 2+ independent real-word confirmations -- see
  -- docs/reverse-engineering/text.md's own new section for the full
  -- derivation, and the real-ROM tests below for byte-exact proof
  -- against the actual ROM file.
  Harness.assertEqual(TextDecoder.decodeByte(0x23), "er") -- "Herr", "tapferer", "Kaempfer"
  Harness.assertEqual(TextDecoder.decodeByte(0x25), "n ") -- "haben", "oberen" (space-inclusive)
  Harness.assertEqual(TextDecoder.decodeByte(0x29), "in") -- "Ein Junge", "Ein Maedchen" -- promotes the 2026-08-10 "Yoshinori" single-occurrence lead to VERIFIED
  Harness.assertEqual(TextDecoder.decodeByte(0x2B), "ge") -- "bezwungen" (x2), "Junge"
  Harness.assertEqual(TextDecoder.decodeByte(0x34), "an") -- "Ganz", "angegriffen", "anbeterin", "Tante"
  Harness.assertEqual(TextDecoder.decodeByte(0x3F), "he") -- "hierher" (x2)
  Harness.assertEqual(TextDecoder.decodeByte(0x47), "ar") -- "Warte", "Bogard" (a real character name)
  Harness.assertEqual(TextDecoder.decodeByte(0x4C), " b") -- "...bezwungen" after 3 different monster names (space-inclusive)
  Harness.assertEqual(TextDecoder.decodeByte(0x5B), "a") -- "Julia" (a real character name, single-letter code)
  Harness.assertEqual(TextDecoder.decodeByte(0x65), " h") -- "Sie haben das", "Warte hier" (space-inclusive)
  Harness.assertEqual(TextDecoder.decodeByte(0x6E), "mm") -- "Willkommen", "entkommen", "Komm hierher"
  Harness.assertEqual(TextDecoder.decodeByte(0x88), "Da") -- "Dark Lord" -- first confirmed CAPITALIZED digraph
  -- CONFIRMED 2026-08-11 ("na dann finde raus was die anderen bytes
  -- bedeuten"), found while resolving the 0x12 control byte -- see
  -- TextDecoder.lua's own doc comment and text.md for the derivation.
  Harness.assertEqual(TextDecoder.decodeByte(0x21), "de") -- "gefunden" (30+ item-pickup messages), "finden"
  Harness.assertEqual(TextDecoder.decodeByte(0x43), "n") -- single-letter code: "finden", "ihr Leben"
end)

Harness.test("TextDecoder.decodeString: decodes a live-VRAM-read dialogue sentence with the new umlaut/period bytes", function()
  -- "ist ein tapferer Kaempfer." as read directly out of VRAM tile
  -- indices during a real dialogue box (docs/reverse-engineering/
  -- text.md "sixth pass") and converted back to ROM-byte form via
  -- romByte = vramTile + 0x80 -- the same relationship the title-screen
  -- text crack established (docs/reverse-engineering/tooling.md).
  local data = bytes(
    0xDC, 0xE6, 0xE7, 0xFF, -- "ist "
    0xD8, 0xDC, 0xE1, 0xFF, -- "ein "
    0xE7, 0xD4, 0xE3, 0xD9, 0xD8, 0xE5, 0xD8, 0xE5, 0xFF, -- "tapferer "
    0xC4, 0x9C, 0xE0, 0xE3, 0xD9, 0xD8, 0xE5, 0xF0 -- "Kaempfer."
  )
  local text = TextDecoder.decodeString(data, 0)
  -- CORRECTED (2026-08-10): "Kaempfer" -> "Kämpfer", real single-glyph
  -- umlaut instead of the old ASCII-safe 2-letter substitution -- see
  -- TextDecoder.lua's UMLAUT_PARTIAL doc comment.
  Harness.assertEqual(text, "ist ein tapferer K\195\164mpfer.")
end)

Harness.test("TextDecoder.decodeString: decodes 'Drache' and stops at terminator", function()
  -- D=0x0D->byte 0xBD, r=0x35->0xE5, a=0x24->0xD4, c=0x26->0xD6, h=0x2B->0xDB, e=0x28->0xD8
  local data = bytes(0xBD, 0xE5, 0xD4, 0xD6, 0xDB, 0xD8, 0x00, 0xAA)
  local text, nextOffset = TextDecoder.decodeString(data, 0)
  Harness.assertEqual(text, "Drache")
  Harness.assertEqual(nextOffset, 7) -- one past the 0x00 terminator (0-based offset 6)
end)

Harness.test("TextDecoder.decodeString: stops at an unrecognized byte if no terminator found", function()
  local data = bytes(0xB0, 0xB1, 0x05) -- '0','1', then a non-text byte
  local text, nextOffset = TextDecoder.decodeString(data, 0)
  Harness.assertEqual(text, "01")
  Harness.assertEqual(nextOffset, 2) -- points at the unrecognized byte, not past it
end)

-- --- ROM-dependent cross-check --------------------------------------------
local romData = DevRomLocator.find()

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes real item names from the ROM (bank 2 name table)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x9de5 in the real ROM: verified by dynamic tracing
    -- (docs/reverse-engineering/tooling.md) to be the start of an item/
    -- spell name table. "Lebe" (a fixed-width, terminator-truncated
    -- slot -- the full word "Leben"/life doesn't fit before the 0x00)
    -- is the first entry.
    local text = TextDecoder.decodeString(romData, 0x9de5)
    Harness.assertEqual(text, "Lebe")

    local text2 = TextDecoder.decodeString(romData, 0x9e25)
    Harness.assertEqual(text2, "Flam") -- truncated entry (fixed-width slot, no terminator before the next)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes a full German sentence fragment",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0xbd7b: "Hier hast Du Deine\nWare: " (dialogue near a
    -- chest/item pickup -- "Here, you have your goods: ", presumably
    -- followed by an inserted item name on a later "page" this decode
    -- doesn't reach). Previously decoded as just "Hier hast Du Deine"
    -- (NEWLINE_BYTE unmapped), then "...Ware" (COLON_BYTE unmapped) --
    -- now decodes further still since COLON_BYTE (0xF5) was added
    -- 2026-08-10 -- a real improvement each time, not a regression.
    local text = TextDecoder.decodeString(romData, 0xbd7b)
    Harness.assertEqual(text, "Hier hast Du Deine\nWare: ")
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real intro-text scroll block",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0xBED8: found by encoding the intro text this project
    -- independently decoded live from the title->Neues Spiel scroll's
    -- tilemap (real tile IDs, converted to dialogue-byte form via the
    -- established tileId+0x80 relationship) and searching the ROM for
    -- an exact literal match -- found on the first attempt, confirming
    -- this specific text is stored as plain literal bytes, NOT the
    -- unsolved dual-table compression that blocks general dialogue
    -- prose elsewhere (docs/reverse-engineering/text.md).
    local text = TextDecoder.decodeString(romData, 0xBED8)
    -- Trailing content is a long run of real blank-line (0x1A) bytes
    -- (the scroll keeps going well past the last sentence before
    -- reaching an unmapped byte) -- checked as a prefix, not pinned to
    -- an exact trailing newline count.
    -- CORRECTED (2026-08-10): real single-glyph umlauts (ä/ü/ß) instead
    -- of the old ASCII-safe substitutions -- see TextDecoder.lua's
    -- UMLAUT_PARTIAL doc comment.
    local expected =
      "Der Mana Baum\nw\195\164chst durch die\nKr\195\164fte der Natur.\n\n" ..
      "Er w\195\164chst hoch\noben auf dem\nBerg Illusia.\n\n" ..
      "Demjenigen, der\nihn ber\195\188hrt, ver-\nleiht er \195\188berirdi-\nsche Macht.\n\n" ..
      "Dark Lord sucht\nnach dem Weg zum\nMana Baum, um des-\n" ..
      "sen gewaltige\nKr\195\164fte zu mi\195\159brau-\nchen und die Welt\nzu unterwerfen."
    Harness.assertEqual(text:sub(1, #expected), expected)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real 'Kaempfe!' battle-intro textbox",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x346D4: found the same way as the intro text -- live
    -- character-by-character tilemap capture (one real letter every 5
    -- real GB frames) converted to dialogue-byte form and searched in
    -- the ROM file, found verbatim on the first attempt. The real text
    -- is "Kaempfe!" (German imperative "Fight!"), not just "Kampf" as
    -- guessed from a low-resolution screenshot earlier this project.
    local text = TextDecoder.decodeString(romData, 0x346D4)
    -- CORRECTED (2026-08-10): real single-glyph "ä" instead of the old
    -- ASCII-safe "ae" -- see TextDecoder.lua's UMLAUT_PARTIAL doc comment.
    Harness.assertEqual(text, "K\195\164mpfe!")
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes real compressed dialogue using the digraph table ('WILLY!\\nWilly')",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x3A268: the literal, uncompressed "WILLY" match that
    -- led to finding the digraph table (docs/reverse-engineering/
    -- text.md) -- immediately followed by "\nWilly" which DOES use the
    -- compression (0x55 = "ll"), i.e. this one real ROM location proves
    -- both the plain-text and the compressed path in a single string.
    -- UPDATED (2026-08-15, task #150: SPEAKER_COLON_BYTE 0x2C wired):
    -- this string decodes FURTHER now that 0x2C (immediately after
    -- "Willy") is recognized -- "Willy:Mana" (stops again at the next
    -- still-unrecognized byte, one real word into the following
    -- sentence). Real, honest consequence of the fix, not a widening
    -- of what this specific test claims to exercise.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x3A268)
    Harness.assertEqual(text, "WILLY!\nWilly:Mana")
    Harness.assertEqual(nextOffset, 0x3A277) -- stops at the next unrecognized byte
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes real compressed dialogue using the digraph table ('Wasserfaellen.')",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x3A2BE, same dump as above -- exercises 4 different
    -- digraph bytes (0x3C/0x3B/0x55/0x24) plus the already-known 0x9C
    -- umlaut byte in a single real word.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x3A2BE)
    -- CORRECTED (2026-08-10): real single-glyph "ä" instead of the old
    -- ASCII-safe "ae" -- see TextDecoder.lua's UMLAUT_PARTIAL doc comment.
    Harness.assertEqual(text, "Wasserf\195\164llen.")
    Harness.assertEqual(nextOffset, 0x3A2C7) -- stops at the next unrecognized byte
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real end-credits 'MUSIK - KOMPONIST' line (2026-08-10, new colon byte)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x3B62A: the real end-of-credits screen (bank 14).
    -- Real, verifiable Seiken Densetsu 1 staff credit -- Kenji Ito
    -- composed the game's music. Exercises the newly-found COLON_BYTE
    -- (0xF5) in its real, live context (a "ROLE:\nNAME" credits line,
    -- one of 9 identical-shaped real occurrences found this pass -- see
    -- docs/reverse-engineering/text.md).
    local text, nextOffset = TextDecoder.decodeString(romData, 0x3B62A)
    Harness.assertEqual(text, "MUSIK - KOMPONIST:\nKenji Ito")
    Harness.assertEqual(nextOffset, 0x3B646) -- one past the real terminator byte
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real character name 'Julia' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x034963 -- one of 25+ identical occurrences of this
    -- real character's name found across the story dialogue this pass.
    --
    -- UPDATED (2026-08-15, task #150: SPEAKER_COLON_BYTE 0x2C wired):
    -- decodes the FULL real speaker-tagged line now instead of just the
    -- bare name -- a perfectly grammatical German sentence ("Julia:
    -- Nun erfahre die wahre Macht des Mana!" = "Julia: Now learn the
    -- true power of Mana!", the hyphen splitting "erfahre" across a
    -- real line break exactly as HYPHEN_BYTE already models), stopping
    -- cleanly at the real terminator -- itself a strong further
    -- confirmation that 0x2C really does decode as ":" here.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x034963)
    Harness.assertEqual(text, "Julia:Nun er-\nfahredie wahre\nMacht des Mana!")
    Harness.assertEqual(nextOffset, 0x034981) -- one past the real terminator byte
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real character name 'Bogard' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x036CF2 -- one of 20+ identical occurrences.
    --
    -- UPDATED (2026-08-15, task #150: SPEAKER_COLON_BYTE 0x2C wired):
    -- decodes the real speaker tag AND a following ellipsis-style pause
    -- now ("Bogard: ......", a dramatic pause) instead of stopping at
    -- the bare name.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x036CF2)
    Harness.assertEqual(text, "Bogard:......")
    Harness.assertEqual(nextOffset, 0x036CFF)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes the real title 'Dark Lord' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x0352D4 -- one of 10+ identical occurrences; the
    -- first confirmed CAPITALIZED digraph (0x88="Da").
    --
    -- UPDATED (2026-08-15, task #150: SPEAKER_COLON_BYTE 0x2C wired):
    -- decodes the full real speaker-tagged line now ("Dark Lord: Sieht
    -- so a[u]s, als wärst du jetzt stärker." = "Dark Lord: Looks like
    -- you're stronger now.", grammatical apart from one small, real,
    -- PRE-EXISTING gap -- "aa" for "aus" -- a different, still-
    -- unmapped digraph this fix doesn't touch, left as-is).
    local text, nextOffset = TextDecoder.decodeString(romData, 0x0352D4)
    Harness.assertEqual(text, "Dark Lord:Sieht\nso aa, als w\195\164rst\ndu jetzt st\195\164rker.")
    Harness.assertEqual(nextOffset, 0x0352F8) -- one past the real terminator byte
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'Willkommen in' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x03664F -- exercises 0x6E="mm" and the newline byte
    -- together in one real, multi-line greeting. Decodes further now
    -- than when this test was written (2026-08-11): the 2026-08-12
    -- digraph-closing pass resolved 0x28="t " and 0x60="t", so the
    -- place name "Jadt" (previously cut short at "Jad") now decodes
    -- in full -- see TextDecoder.lua's own DIGRAPH_PARTIAL notes.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x03664F)
    Harness.assertEqual(text, "Willkommen in\nJadt")
    Harness.assertEqual(nextOffset, 0x03665E)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'anbeterin\\nbezwungen' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x03A0C6 -- exercises 0x34="an" and 0x4C=" b" (the
    -- monster-defeated message shape, "<name> bezwungen") together.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x03A0C6)
    Harness.assertEqual(text, "anbeterin\nbezwungen")
    Harness.assertEqual(nextOffset, 0x03A0D2)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'Tante!\\nEin Junge i' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x03A7A0 -- exercises 0x34="an" (Tante), 0x29="in"
    -- and 0x2B="ge" (Ein Junge) all in one real line. Decodes further
    -- now than when this test was written (2026-08-11): two rounds of
    -- 2026-08-12 digraph-closing passes (0x2D="st"/0x6D=" v", then
    -- 0x40="ne") complete the whole real sentence -- see
    -- TextDecoder.lua's own DIGRAPH_PARTIAL notes.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x03A7A0)
    Harness.assertEqual(text, "Tante!\nEin Junge ist vom\nHimmel gefallen")
    Harness.assertEqual(nextOffset, 0x03A7BA)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'hinten angegriffen' (2026-08-11, systematic dialogue scan)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x035732 -- a 3rd independent 0x34="an" confirmation.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x035732)
    Harness.assertEqual(text, "on\nhinten angegriffen")
    Harness.assertEqual(nextOffset, 0x035741)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'Bonbon gefunden' (2026-08-11, resolving the 0x12 control byte)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x0394C2 -- one of 30+ real item-pickup messages, all
    -- of the form "<Item> gefunden[0x12][0x11]" -- exercises the new
    -- 0x21="de" and 0x43="n" digraph/single-letter entries. Stops right
    -- at the real 0x12 control byte (not a terminator), matching
    -- decodeString's documented behavior for an unrecognized byte.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x0394C2)
    Harness.assertEqual(text, "Bonbon gefunden")
    Harness.assertEqual(nextOffset, 0x0394CD)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes 'Gemma Ritter\\nm\xC3\xBCssen da...' -- the real missing Willy-exchange box (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x3A28B, in the same ~26KB dialogue region storyPages
    -- was independently found in. This is real, previously-missing
    -- Willy-exchange content -- see VictorySequence.lua's own 2026-08-12
    -- doc comment (direct user report: "die texte scheinen ... nicht
    -- 100% korrekt") for the full story, including the fresh box this
    -- fragment is now wired into: "Willy: Gemma Ritter\nmüssen das
    -- wissen." Originally stopped at 0x33 (one of 3 unmapped bytes in
    -- the full sentence, per this test's own 2026-08-12 doc comment
    -- above) -- two rounds of the SAME day's later digraph-closing
    -- passes (0x33="s ", then 0x8C="ha") resolved every remaining
    -- byte, so this now decodes the COMPLETE real sentence end to end,
    -- matching VictorySequence.lua's own hardcoded text exactly.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x3A28B)
    Harness.assertEqual(text, "Gemma Ritter\nm\195\188ssen das wissen")
    Harness.assertEqual(nextOffset, 0x3A29F)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes a COMPLETE, gap-free real sentence -- 'Was hast du ihr angetan, Julia?' (2026-08-12, \"digraphs komplett schliessen\")",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x3A625 -- the flagship regression test for the
    -- systematic digraph-closing pass (see text.md's own writeup):
    -- a real, complete, grammatical German sentence with ZERO
    -- remaining gaps, decoded end to end using only entries from
    -- DIGRAPH_PARTIAL -- something that would have stopped after just
    -- "as" before this pass (0x65/0x28/0x45/0x3A/0x34/0x2B/0x41 were
    -- all still unmapped). Real dialogue: Julia's mother confronting
    -- her after the Dark Lord kidnapping.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x3A625)
    Harness.assertEqual(text, "Was hast du ihr\nangetan, Julia?")
    Harness.assertEqual(nextOffset, 0x3A63A)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes secondRoom's real characterA NPC line, confirming DIGRAPH_PARTIAL[0x84]='ac' (2026-08-12, \"ja bitte alles in dieser reinfolge\")",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x378AA (bank 13) -- found hunting secondRoom's own
    -- real NPC dialogue offsets, direct continuation of the Willy-
    -- exchange work. This exact sentence needs the newly-added
    -- DIGRAPH_PARTIAL[0x84]="ac" to complete "nach" (German "to/
    -- toward") -- without it, decoding would stop after "führt n".
    -- Also confirms `rom_profiles.lua`'s existing hand-transcribed
    -- `graphics.secondRoom.scene.characterA.dialogue` byte-for-byte.
    local text, nextOffset = TextDecoder.decodeString(romData, 0x378AA)
    Harness.assertEqual(text, "Der Monsterein-\ngang f\195\188hrt nach\ndrau\195\159en.")
    Harness.assertEqual(nextOffset, 0x378C6)
  end
)

Harness.testIfAvailable(
  "TextDecoder.decodeString: decodes secondRoom's real characterB NPC line -- a previously-honest gap, now filled (2026-08-12)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- File offset 0x378CC (bank 13), immediately after characterA's
    -- own box (see the test above) -- a real second NPC greeting this
    -- project never had a captured line for before (`rom_profiles.lua`
    -- had no `dialogue` field on `characterB` at all -- an honest gap,
    -- not a guess -- until this pass found and filled it).
    local text, nextOffset = TextDecoder.decodeString(romData, 0x378CC)
    Harness.assertEqual(text, "Hallo!Willkommen\nin Toppel!")
    Harness.assertEqual(nextOffset, 0x378E1)
  end
)

Harness.testIfAvailable(
  "TextDecoder + rom_profiles.messageTextPointer: the real messageID->text formula resolves messageID 13 to 'gefunden' (2026-08-12, $1F64 dispatcher investigation)",
  romData ~= nil,
  "no development ROM found",
  function()
    -- Reproduces the FULL real chain from scratch, using only the
    -- profile's own documented formula (not a hardcoded file offset) --
    -- see rom_profiles.lua's `messageTextPointer` entry and
    -- docs/reverse-engineering/text.md's "SOLVED: the real
    -- message-settings-table text pointer" for the disassembly
    -- (`$04E2` 5-way sub-dispatcher -> `$1F64` -> bank-4 table index 1
    -- -> `$102F7`, which computes this exact record address and reads
    -- this exact field).
    local report = RomIdentity.identify(romData)
    local profile = RomProfiles.match(report)
    local ptr = profile.messageTextPointer

    local messageId = 13
    local recordOffset = ptr.recordBaseFileOffset + messageId * ptr.recordStride
    local fieldOffset = recordOffset + ptr.recordFieldOffset
    local field = romData:byte(fieldOffset + 1) + romData:byte(fieldOffset + 2) * 256
    Harness.assertEqual(field, ptr.verifiedExample.fieldValue)

    local textOffset = ptr.fileOffsetBase + field
    Harness.assertEqual(textOffset, ptr.verifiedExample.textFileOffset)

    local text, nextOffset = TextDecoder.decodeString(romData, textOffset)
    Harness.assertEqual(text, "gefunden")
    -- Stops at the real [0x12] "close dialogue" control byte, same
    -- shape as every other item-pickup message already confirmed
    -- elsewhere in this file (see the "Bonbon gefunden" test above).
    Harness.assertEqual(romData:byte(nextOffset + 1), 0x12)

    -- The SAME real window holds two more, ADJACENT, complete
    -- item-pickup messages of the identical "<Item> gefunden[12][11]"
    -- shape (each with its own small script header before the actual
    -- text run, so not exercised via decodeString directly here) --
    -- confirming the formula lands in a genuine dense cluster of real
    -- dialogue text, not a coincidental single hit. See text.md for the
    -- full byte trace and plausible readings ("Smaragd gefunden",
    -- "Saphir ... gefunden", "Diamant gefunden").
  end
)

if romData then
  print("(TextDecoder ROM-dependent tests ran against a real dev ROM)")
end
