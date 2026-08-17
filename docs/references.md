# External References

External technical sources consulted during reverse engineering, and what
each one was used for. Cross-check everything here against our actual EU
"MYSTIC QUEST" ROM (SHA-1 `7cb65cb314e3f26b92549ddc7f4fc275186c6170` — see
[rom-identification.md](rom-identification.md)) before trusting it as fact:
addresses/offsets documented for other regions or revisions can and do shift.

## Game identity

- Wikipedia, [*Final Fantasy Adventure*](https://en.wikipedia.org/wiki/Final_Fantasy_Adventure)
  and [*Final Fantasy Gaiden*](https://en.wikipedia.org/wiki/Final_Fantasy_Gaiden) —
  general background: developed by Square, released 1991 (JP as *Seiken
  Densetsu: Final Fantasy Gaiden*, US as *Final Fantasy Adventure*, EU as
  *Mystic Quest*), first entry in the *Mana* series. Confirms our ROM's
  header title `MYSTIC QUEST` + Overseas destination code is the EU release
  of this game, not the unrelated 1993 SNES title *Final Fantasy: Mystic
  Quest*.

## ROM/RAM maps (existing public reverse-engineering work)

- **[FFA-Disassembly](https://github.com/daid/FFA-Disassembly) by daid — a full, real disassembly
  project for this exact game (US "Final Fantasy Adventure" cartridge),
  with a technical devlog at [daid.github.io/FFA-Disassembly](https://daid.github.io/FFA-Disassembly/)
  (4 parts as of 2026-08-08: [part0](https://daid.github.io/FFA-Disassembly/part0)
  "Humble beginnings" — tooling (a custom BadBoy emulator/disassembler,
  BGB for live debugging, `rom2png.py`); [part1](https://daid.github.io/FFA-Disassembly/part1)
  "Adventures of code" — jump-table discovery, the bank-calling
  convention; [part2](https://daid.github.io/FFA-Disassembly/part2)
  "The quest for maps" — full map/room data format; [part3](https://daid.github.io/FFA-Disassembly/part3)
  "Where are the string tables?" — text encoding and the script system).
  Found 2026-08-08 (at the user's explicit direction to search for
  walkthroughs/technical documentation) and used as a major additional
  source — see rom-map.md and text.md for what it explains and what
  still needs independent EU-ROM verification. **Everything in this
  project targets the US cartridge**; bank *numbers* are already known
  to differ from our EU ROM (their bank `$08` = map headers; ours is
  VERIFIED as the font — see rom-map.md), so treat every specific
  address/bank number as a US-only fact and every *structural/format*
  claim (RLE encoding, script opcodes, the dual-character text
  compression, the bank-calling convention) as a promising lead to
  verify against our own ROM, not an assumed match. License: check the
  repo directly before reusing any of its code verbatim (its own
  `tools/romAsText.py`, `tools/mapExport.py`, `plugins/script.py` were
  not copied into this project, only their *documented behavior* was
  used as a lead).
  - **REAL DATA WIN, 2026-08-17** (direct user instruction to find a
    comprehensive walkthrough/reference and use it to find more ROM
    content): `src/data/boss.asm` documents a real 24-byte boss stat
    record (speed/HP/XP/money/...) with exact numeric values for all
    21 real bosses. Searched this project's own EU ROM for each
    boss's 4-byte (speed,HP,XP,money) signature: **all 21 matched
    byte-for-byte at a perfect 24-byte stride**, starting at EU file
    `0x10739` -- this EU localization kept the exact same combat-
    balance numbers as the US cartridge. Independently cross-checked
    against this project's own EARLIER, unrelated live-CPU-trace
    finding (`Enemy.lua`'s `HP_INIT_TRACE_NOTE`, file `0x108ba`) --
    two unrelated investigations landing on the same byte. See
    `src/import/EnemyStatTable.lua`'s own doc comment for the full
    trail. `src/data/items.asm` similarly documents a real per-weapon
    stat record (power+price); searched for each weapon's own
    (power,priceLo,priceHi) 3-byte signature and found all 16 at a
    perfect 16-byte stride, EU file `0x0A201` -- a real table this
    project didn't have before, not yet wired into a decoder module
    (a concrete, ready next step).
- Data Crystal, [*Final Fantasy Adventure*](https://datacrystal.tcrf.net/wiki/Final_Fantasy_Adventure)
  — hub page for existing community RE notes on this game (all documented
  against the **US** release unless stated otherwise; license: TCRF wiki
  content, check page history for contributor licensing before reusing text
  verbatim — safe to use as a research lead, not to copy wholesale).
  - [ROM map](https://datacrystal.tcrf.net/wiki/Final_Fantasy_Adventure/ROM_map) —
    marked a stub by the wiki itself at the time of writing. Only concrete
    entry found: `$BE8A` labeled "Intro". Not useful as a structural
    reference yet; needs independent verification regardless.
  - [RAM map](https://datacrystal.tcrf.net/wiki/Final_Fantasy_Adventure/RAM_map) —
    more substantial. Documents WRAM addresses for: current/max HP
    (`$D7B2-$D7B5`), current/max MP (`$D7B6-$D7B9`), level (`$D7BA`),
    experience (`$D7BB-$D7BD`), experience-to-next-level table
    (`$D7A9-$D7AF`, noted as BCD), the four stats — stamina/power/wisdom/will
    (`$D7C1-$D7C4`), attack/defense power (`$D7DF`/`$D7E0`), lucre/gold
    (`$D7BE-$D7BF`), deathblow gauge (`$D858`), hero/heroine name buffers
    (`$D79D-$D7A0` / `$D7A2-$D7A5`), equipment power values
    (`$D6B3-$D6BE`), items bag (`$D6C5-$D6D4`), equipment bag
    (`$D6DD-$D6E8`), and a boss-HP field (`$D3F4-$D3F5`).
    **Status: VERIFIED for our ROM (2026-08-08)** for HP/MP/level/gold/
    stats/attack-defense/hero+heroine name buffers — cross-checked live
    against the EU ROM at the first room and matched with **zero address
    shift** on every field checked (see
    [rom-map.md](reverse-engineering/rom-map.md) "Data Crystal's
    US-cartridge RAM map"). Items bag/equipment bag/equipment power are
    only consistent-with-empty so far (nothing to distinguish from
    uninitialized memory pre-inventory), not positively confirmed; the
    remaining fields (experience-to-next-level table, deathblow gauge,
    boss-HP field) are plausible but not individually cross-checked yet.
    Originally these addresses were undated and not marked with a region/
    revision; they were almost certainly derived from the *US* "Final
    Fantasy Adventure" cartridge (the version the RE community mostly
    worked from), not the EU "Mystic Quest" dump this
    project targets. RAM *variable* addresses are often — but not
    guaranteed — stable across localizations of the same game engine since
    translated text usually lives in ROM, not WRAM, and doesn't reflow the
    engine's data-segment layout the way it can reflow ROM code/pointer
    banks. Every one of these must be independently confirmed against the
    EU ROM (e.g. by watching memory while HP/MP/level/gold visibly change in
    an emulator, or by static analysis of the EU dump) before
    `docs/reverse-engineering/rom-map.md` may mark it VERIFIED.
  - Text table / notes / tutorials sub-pages: not yet created on the wiki as
    of this check — no encoding table available from this source.
- [almarsguides.com GameShark codes (US)](https://almarsguides.com/retro/walkthroughs/GameBoy/Games/FinalFantasyAdventure/Gameshark/)
  and [Game Genie codes (US)](https://almarsguides.com/retro/walkthroughs/GameBoy/Games/FinalFantasyAdventure/GameGenie/)
  — used 2026-08-08 (sixth pass) at the user's suggestion, as a **third,
  independent** cross-check of the WRAM addresses above (decoded by hand:
  GB GameShark's `01VVAAAA` format stores the address byte-swapped, i.e.
  real address = swap the `AAAA` pair; GB Game Genie's 6/9-digit format
  decoded using mgba's own `GBCheatAddGameGenieLine` algorithm,
  `src/gb/cheats.c`, ported to Python rather than re-derived from
  scratch). **Every GameShark address checked decoded to exactly the same
  WRAM address Data Crystal's RAM map and this project's own live reads
  already agreed on** (`$D7B2` HP, `$D7B6` MP, `$D7BA` level, `$D7BE`
  gold, `$D7C1-$D7C4` the four stats, `$D858` — GameShark labels it
  "Willpower Meter", matching Data Crystal's "deathblow gauge" for the
  same address) — three independent sources agreeing is strong
  confirmation. New lead not in Data Crystal's list: `$D6F0`, "Infinite
  Item Use (Equipped Item-Slot 1)" — plausibly an equipped-item use/
  durability counter, worth checking once milestone 8 needs it. **Game
  Genie "Walk Through Walls" (`B56-7FF-2A4`) decodes to a ROM patch at
  `$067F`** (checked-byte `0xB3` -> `0xB5`, i.e. `OR E` -> `OR L`) — the
  real EU ROM byte at `$067F` **is** `0xB3`, so this specific patch
  transfers byte-for-byte to this EU ROM too (applied live via
  `core.memory.u8.raw_write`, see rom-map.md "Breakthrough" for what it
  revealed and its limits — landing in truly out-of-bounds position space
  broke the game state rather than showing new content, though the
  patched instruction's location independently corroborates this
  project's own `entity+4`/`+5` movement-delta trace). Not every code
  transfers this cleanly — a second Game Genie code checked (`FAE-3FC-
  4C1`, "reduce damage taken") decoded to a real ROM address inside this
  project's own independently-traced damage-application routine
  (`$3E30`-ish) but with a checked byte that does **not** match this EU
  ROM's actual byte there, i.e. ROM *code* addresses/bytes can and do
  differ between the US and EU builds even where the RAM *data* layout
  stayed identical — treat each Game Genie code as its own claim to
  verify, not a blanket "US codes work here."

## Text encoding / tools

- [romhacking.net forum: "Final Fantasy Adventure - Text Editing Tool"](https://www.romhacking.net/forum/index.php?topic=33465.0) —
  a community member's personal in-progress tool as of the thread's start
  (Sept 2021). No public text table or finished tool found via this thread
  at the time of writing. Follow up if the encoding needs a head start;
  otherwise this project will derive the encoding directly from the ROM
  (font tile graphics + observed byte→glyph correlation) per the "evidence
  over assumptions" rule.
- [romhacking.net: Final Fantasy Adventure hacks/games index](https://www.romhacking.net/games/1177/) —
  index of existing translation/hacking projects for the US release; useful
  as a pointer to community members who may have documented the format
  further, not consulted in depth yet.

## Save files (US cartridge) — used as an independent format cross-check

- [fantasyanime.com: Final Fantasy Adventure game saves](https://fantasyanime.com/mana/ffadventsaves.htm)
  — a fan archive of 23 real, progressively-advanced save files for the
  **US** "Final Fantasy Adventure" cartridge, one per major story
  checkpoint (`ffadv_save01-first_cave.zip` through
  `ffadv_save23-final.zip`, each a zip of a `.sav` battery-save file plus
  a BGB-emulator-specific `.sn1` savestate — only the `.sav` is portable/
  useful here, the `.sn1` is a proprietary full-state format tied to
  BGB + the exact US ROM, not usable with mGBA or against this project's
  EU ROM). Used 2026-08-08 (seventh pass, at the user's suggestion) as an
  independent, external cross-check of this project's own
  dynamically-traced save-RAM nibble-pack format — decoding a real save's
  raw bytes with this project's own formula produced the exact expected
  magic byte, strong external confirmation. **Loading a real save's full
  content into the EU ROM does not work cleanly**, though (a hard,
  authentic CPU lockup past a specific field) — see
  [reverse-engineering/rom-map.md](reverse-engineering/rom-map.md) "Save
  RAM" for the full account, including the exact byte-offset boundary
  found by bisection. **Compliance note, checked after the fact (should
  have been checked first)**: this site's `robots.txt` disallows
  automated fetching of `.zip` files (`Disallow: /*.zip$`) — the two
  `.htm` index pages were fetched fine (not disallowed), but the four
  save `.zip` archives downloaded directly via `curl` (this project's
  Bash environment has outbound network access, confirmed this pass)
  were fetched in violation of that rule, not checked beforehand. No
  further automated fetches (of any file type) from this host without
  re-confirming `robots.txt` first.

## Architectural reference (not the target game)

- [bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp) —
  the project this recomp's architecture is modeled on. MIT-family license
  per its `LICENSE.MD` (verify exact terms before reusing any code
  verbatim; this project treats it primarily as an architectural pattern to
  learn from, not a code source, per the master brief). See
  [gen1recomp-analysis.md](gen1recomp-analysis.md) for what was extracted
  from it and why.

## Walkthroughs / game-content reference (2026-08-17)

Found via direct user instruction ("suche eine möglichst umfangreiche
Komplettlösung mir karten, items, gegnerlisten usw und benutzte die
als grundlage um möglichst viele dinge im rom zu finden") -- used as
STORY/CONTENT reference (what exists, roughly in what order), cross-
checked against real ROM bytes before trusting anything numeric (see
the FFA-Disassembly entry above for the actual byte-level wins this
produced). Most GameFAQs/vgmaps/Fandom/Neoseeker/StrategyWiki/
archive.org URLs returned HTTP 403/402 to this project's own fetch
tool -- not dead links, just blocked to this tool; a human browser
would likely see them fine.

- [gamesurge.com: Final Fantasy Adventure Walkthrough](http://www.gamesurge.com/strategies/Gameboy/Walkthroughs-F/Final%20Fantasy%20Adventure%20B.shtml)
  by Robert Paulson (v1.00, 1999) -- the one full-text guide this pass
  could actually fetch. Complete weapon (16), armor (9), helmet (6),
  shield (9) tables with power/DP/price; complete consumable-item and
  magic-spell (8) lists; a 22-entry story-order boss list; a 12-entry
  named-character list. **Independently confirms this project's own
  2026-08-17 text-decoding correction**: the character this project
  had read as "Julia" (from ROM byte `0x5B`) is named **Julius**
  here too, the final boss at the Mana Tree -- see `TextDecoder.lua`'s
  own `0x5B` note.
- GameFAQs lists 30 separate FAQs for this game
  ([faqs index](https://gamefaqs.gamespot.com/gameboy/563272-final-fantasy-adventure/faqs),
  blocked to this tool) including a German-language walkthrough by
  Corlagon and several with ASCII dungeon maps (LevinMage, 3vrB257A5gq3fg)
  -- not fetched this pass, a real follow-up if gamesurge.com's own
  coverage runs out for a specific area.
- [Final Fantasy Wiki (Fandom): items/weapons/enemies pages](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Adventure)
  -- blocked to this tool (HTTP 402); a real lead for enemy names
  specifically, since (per this project's own web search results)
  "outside of boss encounters, enemies in Adventure have only ever
  been named in Japanese in official guidebooks" -- meaning REGULAR
  field-monster English names may not exist as a reference at all,
  only the 21-boss list this pass already captured.
- ~~[vgmaps.de: Final Fantasy Adventure maps]~~ blocked to this tool
  (HTTP 403) -- SUPERSEDED, see the fantasyanime.com entry below,
  which hosts the same kind of content and IS reachable.
- [fantasyanime.com: Final Fantasy Adventure maps](https://fantasyanime.com/mana/ffadventmap.htm)
  (2026-08-17, direct user instruction "dann die maps anschauen",
  follow-up to the weapon-stat-table win above) -- real, drawn,
  room-by-room dungeon maps (17 dungeons + 10 overworld areas + a full
  world map), reachable by this tool (unlike vgmaps.de/GameFAQs/
  Fandom/archive.org, all blocked) and confirmed clean under this
  site's own `robots.txt` (only disallows `.zip`/media files, not
  `.png`). Downloaded and visually inspected 2 dungeon maps so far:
  - **The Marsh Cave** (the first dungeon) -- a real, labeled room
    grid with a `Start` marker, lettered sub-area connectors (A-F),
    2 mattock-crackable walls, 2 key-locked doors, item pickups
    ("Iron Shield", "Sickle" -- the same real weapon this project's
    own `WeaponStatTable`/`WeaponTable` already decode), and exactly
    **ONE** labeled `Boss` room (bottom, reached via connector F).
  - **Kett's Dungeon** (the second dungeon) -- same style map, own
    `Start`/lettered connectors/item pickups (a "Chain" [Flail]
    weapon pickup), but **no room is labeled `Boss` anywhere on this
    map**, despite gamesurge.com's own boss list naming a "Werewolf
    (Kett's guard)" fight here -- either this map's own author didn't
    mark it, or it's a smaller/scripted encounter this particular fan
    map doesn't call out.
  - **Real, still-open relevance to this project's own long-running
    "second boss" placement question** (see events.md's "Second boss
    investigation" and this project's own `sixthRoom.gate` work): The
    Marsh Cave map shows only ONE boss for the entire first dungeon,
    which is where this project's OWN 9 decoded rooms (`startRoom`
    through `ninthRoom`) most plausibly sit (matching item names
    already found: Sickle, and this project's own `startRoom`
    checkerboard/gate imagery). If this project's 2 in-ROM boss
    fights are really BOTH inside "the first dungeon" as currently
    modeled, that would be one MORE boss than this specific fan map
    shows for that dungeon -- not a contradiction (fan maps can miss
    optional/scripted encounters, and this project's own live-testing
    already independently confirmed `sixthRoom`'s own boss+gate
    mechanic really exists in the ROM), but a real, honest data point
    worth keeping in mind, NOT yet resolved either way. A full room-
    by-room visual cross-check (rendering this project's own 9 decoded
    rooms as images and comparing tile-for-tile against this map's own
    grid) was NOT attempted this pass -- a substantial, concrete next
    step, not started here.

## Open research leads (not yet followed up)

- ~~No dedicated GitHub disassembly project...~~ SUPERSEDED -- see the
  FFA-Disassembly entry above (found 2026-08-08); this line was stale
  the moment that entry was added and should have been removed then.
  Real remaining lead: no dedicated disassembly targeting the **EU**
  cartridge specifically was found (FFA-Disassembly is US-only) --
  worth a search pass focused on that if the US->EU bank/address
  translation ever becomes a bottleneck.
- The Spriters Resource has ripped sprite sheets for this game
  ([spriters-resource.com/game_boy_gbc/ffadv/](https://www.spriters-resource.com/game_boy_gbc/ffadv/)).
  Useful only as a *visual cross-check* once we decode our own tiles from
  the ROM — never as a source to copy graphics from, since this project's
  rule is that all game assets are decoded from the user's own ROM, not
  imported from third-party rips.
