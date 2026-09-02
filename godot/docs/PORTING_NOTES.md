# Porting notes — Parlour v23.dc.html → Godot

This is a **vertical slice**: the full data model, the full scoring engine,
and a complete (if plain) playable loop from sign-select through three nights
to an end-of-run screen — built to prove the architecture and the mod/Workshop
story, not to be the finished game. Below is what changed on the way over,
and what's deliberately not here yet.

## How this was ported

Read directly from `project/Parlour v23.dc.html` and `project/HANDOFF.md`
(line references are in each data file's `_comment` field and in
`autoload/Rules.gd`'s doc comments). The prototype's own recommended
extraction path — open it in a browser, use the CARD TABLE → HANDOFF tab to
export `parlour-data.json`/`parlour-rules.md` — was attempted first via a
headless Chromium (Playwright) so the port could be checked against generated
output rather than hand-transcription, but the prototype loads React/Babel
from `unpkg.com`, which this environment's network policy blocks (cdnjs was
tried as a substitute and is also blocked here). Hand-porting from source with
recorded line numbers was the fallback, and every data file names exactly
where it came from. **If you have unrestricted network access**, it's worth
generating the real `parlour-data.json`/`parlour-rules.md` per HANDOFF.md and
diffing them against `data/base/*.json` as a correctness check — nothing here
should meaningfully disagree, but it hasn't been machine-diffed against the
canonical export.

The scoring engine (`Rules.simulate()`) is checked against hand-traced
expected values for a handful of card/sign/reader combinations in
`tests/test_rules.gd` (run via `godot --headless -s tests/test_rules.gd`),
not against a live run of the original JS, for the same network-access
reason. It's a faithful line-for-line translation of `simulate()`/`linkOf()`/
`elOf()` from the source (see the doc comments in `autoload/Rules.gd` for the
exact correspondence), but treat it as unverified against the original engine
until someone can run both side by side.

## Deliberate judgment calls

The user asked for best judgment on these, flagged rather than silently made:

- **The dead "nerve" event rewards were rewritten, not ported as-is.** The
  source's `nerve`/spiral stat was removed from the design in chat11 (replaced
  by "hand discards every reading" as the pacing clock) but three event
  option rewards in `EVENTS` were never migrated off it — `+10 nerve now, +2
  for the rest of the run` and similar foot text currently do nothing in
  v23. `data/base/events.json` keeps the exact flavor text and the same
  two-choices-per-event shape, but replaces the reward with a flat faith
  payout on the affected options (see that file's `_comment` for the specific
  mapping). This is the most substantive content judgment call in the port —
  worth a second look from whoever owns the actual game design.
- **The tarot-cross slot labels (BEHIND/OVER/BENEATH/AHEAD OF, roman numerals
  I–IV) were dropped.** The source's own code comment says "the cross is only
  the order you speak in" — the positional mechanic they used to represent
  was removed back in the design's momentum-era pivots, leaving them as pure
  decorative labels for what is mechanically just a left-to-right line. The
  Reading screen shows laid cards as a plain ordered list. If the tarot-cross
  framing is wanted back as flavor, it's a UI-only addition — nothing in
  `Rules.gd` needs it.
- **Title: "Parlour," not "Bad Fortune."** The prototype's own title screen
  still renders "Bad Fortune" (an old working title from the very first
  design pivot) despite the project, `HANDOFF.md`, and the generated
  `parlour-rules.md` all calling it Parlour. Went with the name every other
  artifact agrees on.
- **Signs are all unlocked from the start**, matching v23's actual (if
  possibly unintentional) behavior — every reader's `unlock` field is `null`
  and nothing in the source gates sign selection despite a design chat
  mentioning an intended lock-and-unlock system. No meta-progression exists
  in this port; see "Not in this pass" below.
- **Relics and marks stayed as two separate data pools** (`relics.json`,
  `marks.json`) even though both just populate the same runtime `state.marks`
  list of passive bonuses — that's how the source keeps them (relics from
  elite wins, marks from events/shop, otherwise identical), and unifying them
  wasn't asked for.

## Not in this pass (by design, per the agreed scope)

- **Full visual fidelity.** No hand-drawn sign/element/planet SVG art (glyphs
  use the source's own unicode fallback character instead — see
  `UIKit.el_glyph()` — not the SVG path art), no booster-pack-opening
  animation, no letter-by-letter "mumble" reveal when a reading resolves, no
  cursor-following tooltip (Godot's native hover tooltip is used instead —
  see `UIKit.KEYS`/`card_keyword_tooltip()`). Card and portrait illustration
  is **not missing so much as pending**: the pipeline for it is built and
  tested (`autoload/Art.gd`, `data/base/art_manifest.json`,
  `docs/ART_GUIDE.md`), every asset falls back to a placeholder until
  delivered, and nothing needs a code change when art lands. A fan-of-cards hand layout and a
  procedural mood-reactive sitter portrait ARE in (see `UIKit.card_face()` /
  `UIKit.sitter_portrait()`), on the Reading screen specifically — other
  screens (PickScreen's reward/shop rows) intentionally keep the roomier
  full-text row style, since a considered reward/shop choice benefits from
  everything visible at once, unlike a hand you're scanning at a glance.
  Pixel-matching the source's design beyond that is a real follow-up task,
  not a rejection of the "recreate pixel-perfectly" brief.
- **The CARD TABLE dev UI's CARDS tab** (live-editing content in a running
  game — this port edits content by editing JSON directly instead). The
  AUDIT tab equivalent IS ported — see `Rules.fx_audit()` and
  `tests/test_content_audit.gd`.
- **Full Steam Workshop / Steamworks integration** — see `docs/STEAM_WORKSHOP.md`.
- **Any actual meta-progression content.** The unlock *mechanism* is now real
  (see below) but no base reader uses it; all 13 are still available from the
  first launch, which is the source's behaviour and not mine to change.
- **Real sound design.** The audio layer and placeholder sounds are in; they
  are stand-ins, and `docs/SOUND_GUIDE.md` is the brief for replacing them,
  exactly as `docs/ART_GUIDE.md` is for the art.

Save/resume, keyboard navigation, key rebinding, sound and the unlock
mechanism were all on this list and are now done — see below.

## Keyboard and gamepad

Buttons made with `UIKit.button()` were always reachable — Godot's `Button` is
focusable and works out its own focus neighbours from the layout. But every
*interesting* control in the game is a `UIKit.panel_button()` or a
`UIKit.card_face()`, and those are `PanelContainer`s, built that way for layout
reasons (see `panel_button`'s comment). A PanelContainer is not focusable and
handles no input of its own, so cards, map options, rewards, shop offers and
the Library's card list were **mouse-only**: a keyboard or gamepad player could
reach the menus and nothing else.

Both had a verbatim copy of the same click/hover block, each handling only
`InputEventMouseButton`. That is now one `UIKit.make_interactive()`, which also
sets `focus_mode`, draws a focus ring (`UIKit.FOCUS`, deliberately a different
colour from `GOLD` so a focused row is tellable from a merely gold-accented
one), and handles `ui_accept`.

Each screen then calls `UIKit.focus_first()` so the first key press does
something. The in-run screens pass their *content* container rather than
themselves — otherwise focus lands on the run header's DECK chip, which is
chrome, and the first press does nothing useful.

`tests/test_scenes.gd` asserts both halves: that every screen leaves something
focused (stub `focus_first` out and 16 screens fail; with it, none do), and
that pushing a `ui_accept` at the viewport on the reading screen actually lays
a card — driving the real routing rather than calling the handler directly,
since the routing was as much in doubt as the handler.

### Rebinding

Settings → CONTROLS lists five actions and rebinds any of them. `ui_accept` and
`ui_cancel` are Godot built-ins rather than actions this project declares —
deliberately, since `Button` responds to `ui_accept` natively and redefining it
would risk desyncing real Buttons from panel rows — but `InputMap` treats a
built-in like any other action, so they are on the list, being the two a player
is most likely to want moved.

Only an action's **keyboard** event is replaced; its gamepad button is left
alone, so a rebind never quietly costs a controller player their button.
Settings captures each action's shipped keyboard events at startup, because
applying an override erases them from the InputMap and "reset to default" would
otherwise have nothing to put back.

## Sound

`master_volume` and `muted` drove the real AudioServer master bus with nothing
on it. There is now an `Audio.gd` autoload with nine named moments
(`Audio.EVENTS`), a moddable `sounds` registry, and placeholder audio so the
bus carries something.

The sounds that ship are **placeholders** — synthesized by
`tests/gen_sounds.py`, marked `"status": "placeholder"`, and meant to be
replaced. This mirrors the art pipeline deliberately: `docs/SOUND_GUIDE.md` is
the composer's brief the way `docs/ART_GUIDE.md` is the artist's, and
`tests/test_audio.gd` asserts that `Audio.EVENTS` and `sounds.json` cover
exactly the same keys, so a renamed moment cannot silently stop making a noise.

Sounds fire from the **UI**, not from `Run.gd`, for the same layering reason
`Run.gd` emits translation keys rather than prose. `Reading.gd` already holds
`_justDrawn`/`_justDiscarded` snapshots for its animations, so audio and motion
read the same source and cannot disagree.

### A latent bug this uncovered

`Art.gd` resolved textures with `ResourceLoader.exists()` + `load()`, which
only works for assets **the editor has imported**. Art delivered later and
dropped into `assets/art/` has no `.import` file; art a mod ships in
`user://mods/` never can, since the importer only covers `res://` assets known
at export time. So the art pipeline worked for exactly the case that was never
going to be the interesting one — and `test_art.gd` could not see it, because
its delivered-art check skips itself while every asset is still `"missing"`,
which is always, until the artist delivers.

Both loaders now decode from bytes (`Image.load()` for art; a small RIFF/WAVE
reader plus Godot's runtime OGG/MP3 loaders for audio), and `test_art.gd`
writes its own un-imported file to `user://` to pin it down without needing any
committed art.

## The project did not work from a fresh clone

Found by bundling the repo, cloning it somewhere else and running the suite —
which nothing had done before, because this container had been warm since the
first commit.

Three of this project's scripts declare a `class_name` (`UIKit`, `RunHeader`,
`ModLoader`). A `class_name` global is only *declared* once Godot has written
`.godot/global_script_class_cache.cfg`, and that file is generated by the
**editor** and gitignored — correctly, it is a cache, not source. So on a fresh
clone none of those three names resolves. `Content.gd` failed to compile, taking
every autoload with it; every scene script failed to compile too, which meant
each scene instantiated **with no script at all**.

The failure mode is nasty precisely because it is quiet: scenes still load,
nothing crashes, and most of the suite still passes. What gave it away was the
keyboard-focus assertion — sixteen screens reporting "left nothing focused",
because the code that would have focused anything was not attached. A check
written for accessibility caught a total project failure.

All three are now `preload()`ed by path, which needs no registry. The
`class_name` declarations stay (they are useful in the editor); nothing depends
on them at runtime. This is the third time a bare global name has bitten this
port — see `Nav.gd`'s header for the other two, which were the same shape in
`-s` scripts.

`git clone` + run the suite is now part of what "green" means. It is the only
way this class of thing shows up.

## One engine version hid a bug for the whole port

The project targeted Godot 4.3 for no better reason than that 4.3 was the
binary available while it was being written. Retargeting to 4.7 turned out not
to be housekeeping: it exposed a bug that had been there since the first
commit.

JSON has no integer type, so Godot parses `"cost": 1` as `1.0`. The codebase
treats these as ints throughout — `int()` in scoring, `str()` on a card face —
and that appeared to work, because **Godot 4.3 renders an integral float as
"1"**. Godot 4.7 renders it as `"1.0"`. Under 4.7 every card in the game showed
a cost of "1.0" and a restore of "+5.0".

Nothing errored. All thirteen test files passed on 4.7 — none of them assert on
rendered card text. It took a screenshot under the new engine to see it, which
is the third time in this port that a visual check caught what the logic tests
structurally could not.

Fixed at the boundary rather than at the display sites: `ModLoader` now
converts whole-looking numbers to ints as JSON is read, so "a number that looks
whole IS an int" holds for base content and every mod at once, which is what
the code always assumed. Genuinely fractional values (an elite's `maxMul`, a
sound's `pitch_jitter`) are left alone. `tests/test_content_audit.gd` walks
every registry and fails on any whole number still stored as a float, so the
check travels to whatever engine anyone runs it on rather than depending on one
version's formatting.

The suite is now run against **both 4.3 and 4.7** before a version claim is
made in the README.

## A soft-lock, found by playing whole runs

Every test covered a slice. `test_run.gd` drives one encounter to resolution
and stops; `test_scenes.gd` builds each screen against a state handed to it.
Nothing ever played a **whole run**, so night rollover, the boss, the shop,
elite twists, burning a card and `end_run()` had never happened in sequence —
and a state machine's bugs are exactly the ones that only appear in sequence.

`tests/test_soak.gd` now plays complete runs (40 by default), checking
invariants after every action rather than at the end: coin/faith/mended never
negative, the deck never emptied by burning, the screen always one Nav can
route, composure never past its maximum, and the run always terminating at
"over". It found one real bug immediately.

**READ IT could leave the game stuck.** `read_it()` returns early on an empty
line, faithfully copying the prototype (`readIt` does the same, and greys the
button out via `cannotRead`). But if nothing in hand is affordable *and*
nothing is laid, there is no legal action left at all — the reading cannot
resolve, the turn cannot advance, and the only way out is abandoning the run.

Two things were wrong. The port had inherited the *guard* but not the
*affordance*: the button looked live and silently did nothing, where the
prototype greys it. And the deadlock is real in both — the soak reaches it 7
times in 60 runs at `start_energy=1`, which is a supported setting, so it is
not theoretical.

`Run.can_read()` now keeps the misclick protection while a play is still
available and lifts it when there is none. Reading an empty line then costs a
reading and scores nothing: a bad move, but a legal one, and always better than
a stuck game. The soak asserts the way out actually advances the reading —
stub the fix back out and it fails rather than looping.

## Inert data, and a guard against more of it

The same bug happened four times on this port, and every time it was found by
accident: `Content.LOAD_EXAMPLE_MODS` (a constant nothing consulted, so the
setting it documented did not exist), every reader's `unlock` field, an elite's
`twist.t` sentence, and the `{S}`/`{es}` pronoun tokens. They share a shape —
data faithfully ported, plausible-looking, and inert. Nothing errors, nothing
looks wrong in a screenshot, no test fails; the feature simply is not there.

A grep finds them, so `tests/test_dead_content.gd` now does the grep on every
run: it collects every key across every record in every registry and fails on
any that appears in no `.gd` file, unless it is listed in `KNOWN` with a reason
(`dynamic` — read by variable; `dead` — genuinely unread, named so it stays
visible). It is a grep and says so in its own header: it proves a key is
mentioned, not that it is used correctly, so it under-reports. It does not
over-report, which is the direction that matters.

Running it turned up two more:

- **`card_effects`' `d`** — each effect's typical amount (draw 1, coin 3,
  next 4, solo 6). Nothing read it, so the Library's effect editor started every
  field at 0 and "give this card the solo bonus" was six clicks on a spin box.
  Now a one-click button per row.
- **`guard: 3`** on *Let Them Say The Worst Of It* — and this one is dead in
  the **prototype** too: it sits on that one card and appears in no scoring code
  on either side of the port. An abandoned mechanic, not a porting miss. Left in
  place (deleting it would discard the author's intention) and listed in `KNOWN`
  as dead (implementing it would be inventing a rule nobody wrote).

## Unlocks

Every reader carries an `unlock` field, ported faithfully and then read by
nothing — inert scaffolding. `Profile.gd` (cross-run stats at
`user://profile.cfg`, distinct from `Save.gd`'s run in progress) now evaluates
it, and the sign-select screen greys out a locked reader and says what it wants
rather than hiding it.

**No progression is invented for the base game.** All 13 base readers keep
`unlock: null`, and `tests/test_profile.gd` asserts it, so making the mechanism
work cannot quietly become a design change. The example pack ships a locked
reader so the feature is exercised rather than merely present. If a base reader
should ever be locked the obvious candidate is Serpentarius — "You were never
on the wheel" — but that is the author's call, not a porting one.

A `runs_started` stat was written and then dropped: there is no unambiguous
screen transition for it, it would have needed persistence calls inside
`Run.gd` to be honest, and no unlock condition wanted it.

## Save and resume

A run used to live only in memory: closing the game on night 2 threw away
everything. `autoload/Save.gd` now writes `Run.state` to `user://save.dat` on
every state change (coalesced to at most once a frame, plus a flush on the way
out), and the main menu grows a CONTINUE entry describing what it would resume
into. Two decisions in there are worth knowing about:

**store_var, not JSON.** `Run.state` is a plain Dictionary and JSON is the
obvious reach, but JSON has no integer type — every `hp`, `coin` and `denial`
would come back a float, and the places that render a number with `str()`
rather than `int()` would start showing "5.0". `store_var` round-trips Godot's
types exactly. `allow_objects` is false in both directions: a save file is a
file on disk that can be edited or swapped, and object deserialization would
let one execute code.

**The whole state is written verbatim; content is re-resolved on load.**
Writing it wholesale means a field added to a run later cannot be silently
dropped by a serializer nobody remembered to update. But `state` is full of
*copies* of content records, and restoring those verbatim would freeze the run
against the content as it stood when it started — a card retuned in the
Library, or a mod pack updated, would never reach the deck the player is
holding, and a deck could go on containing cards that exist nowhere. So on
load every content-derived record is looked up again by its stable identity (a
card by name, a reader or sign by key) and replaced with the current version,
keeping only what is genuinely per-run: a card's `uid`, a sitter's scaled
`max`/`denial`/`turns`, an elite's `twist`. A card that no longer resolves is
dropped and counted rather than kept as a husk — and the main menu stops on the
first CONTINUE to say how many went, rather than handing back a quietly shorter
deck.

A save is cleared rather than written whenever the screen is not a run in
progress ("sign" before one starts, "over" after one ends), so CONTINUE can
never drop a player into a finished run. `tests/test_save.gd` covers the
round trip mid-fight, the int-vs-float trap, re-resolution, a dropped card, a
corrupt file and a version-skewed one.

## The Mods screen

`ModLoader`, `CardEdits` and `Workshop` all ran with no interface at all: a
player could not see which packs were loaded, in what order, or which one
caused an error — errors were *counted* on the main menu but the messages went
to `push_warning`, so reading them meant launching from a terminal. Main menu →
MODS now lists every pack discovery found, in load order, with source,
priority, record counts and path; any pack but the base one can be switched off
(stored in the `disabled_mods` setting, keyed by pack id); load messages are
shown in full; and the Workshop section says plainly that it is not connected
rather than offering an inert button.

To make that possible `ModLoader` now *records* what it discovered
(`ModLoader.packs`, surfaced as `Content.packs`) instead of throwing the
manifests away after merging.

## Balance: Taurus and Virgo

`tests/balance_sim.gd` ports `simFight()`/`simSweep()`/`simGroup()` — the
source's own greedy-auto-player difficulty check — and runs clean against the
ported content. Two outliers came out of it, and both have now been changed;
this section records what was measured, what was changed, and what is still
open, because these are the only places the port deliberately departs from the
source's *rules* rather than its structure.

**Correcting an earlier note.** A first 600-fight pass reported "Taurus (sign)
32%" and "Virgo (reader) 100%, stands out high". The Taurus reading held up;
the Virgo one did not. At 6500 fights, Virgo is at the top of a five-reader
cluster (Virgo 100%, Aries 99.8%, Serpentarius 99.4%, Leo 99.2%, Cancer 99.0%)
rather than a lone outlier, and *four signs* sit at ~100%, not just one. The
smaller sample also conflated the Virgo reader with the Virgo sign, which are
unrelated mechanics. Treat any single cell below n≈300 as noise; run-to-run
variance at n=1300 measured ~3.5 points.

### Taurus (the sign) — 42% → 60%

Taurus is the only sign whose denial is a numeric **wall**: it starts at the
sitter's full denial and, in the source, is charged again in full every reading
while thickening without a ceiling.

Pinning the sign and sweeping all 13 readers against it showed the real
problem, which is not that it was hard but *what kind* of hard it was: win
rates ran from **18% (Gemini) to 100% (Virgo)** against the same sign. A flat
amount taken off the top of every reading turns any reading that lands under
the wall into exactly zero progress, so what decides the matchup is a reader's
*worst* reading rather than their average — which punishes precisely the
readers whose identity is building a combo, and rewards the ones with a small
reliable flat bonus. It was also a one-way spiral: falling behind thickened the
wall, which made falling further behind certain.

The wall now **drains** — whatever it absorbs is gone from it — and thickens 3
again after every reading, up to a ceiling of twice the sitter's base denial.
Same fiction (a cold shoulder you have to wear down), but a weak reading still
chips at it, so the sign is a buffer to break through against its own regrowth
instead of a toll. Measured after: Taurus **59.5%**, still comfortably the
hardest sign (next is Cancer at 73.6%), with the reader spread narrowed to
42–100%.

Both the drain and the ceiling live in the new `denial_wall` registry in
`fx.json`, and the growth rate stays in `denial_shield`, so this is retunable
(and mod-overridable) without touching engine code. An fx with no `denial_wall`
entry keeps the source's exact behaviour, which is what Pisces (`tide`) does.

### Virgo (the reader) — a design fix, not a win-rate fix

Virgo's passive (`white`) paid +3 to every elementless card. All seven basics
every reader starts with are elementless, so it was the only reader bonus that
was **unconditional** — no element to match, no ordering, no chain — on 7 of
the opening 10 cards. Those cards also dodge four of the twelve denials
(`norepeat`, `deadel`, `halfown`, and the sitter-element check all test
`el != ""`). It is now capped at the first two elementless cards per reading,
which puts it in the same family as Aries's "your first card restores +2" and
Cancer's "your last card restores +3". The cap is `fx.white.cap`; 0 restores
the source's behaviour.

Be clear about what this did and did not do: capping it moved Virgo from 3.28
to 3.70 average readings and **left the win rate at 100%**. Capping to 1 only
reached 98%. The ceiling is not Virgo — it is the difficulty of night 1 / step
3, which is what the source's baseline measures. Re-measured at night 2 /
step 6 the field separates properly with no 100% anywhere:

    reader:  Scorpio 26.0% … Virgo 97.2%       (overall 65.3%)
    sign:    Cancer 35.8%, Taurus 38.1% … Gemini 90.7%

So the remaining questions are the *opening* difficulty curve, four signs that
ask almost nothing early (Libra `halfown`, Virgo `norepeat`, Capricorn
`deadel`, Gemini `steal` — each of which can be a complete no-op against a deck
that happens not to care), and Scorpio the reader at 26% late. Those are design
calls on content, not port fidelity, and are left alone deliberately.

Re-measure with `godot --headless --path godot -s tests/balance_sim.gd -- <n>
[sign=<key>] [reader=<key>] [night=<n>] [step=<n>]`. Pin an axis when tuning
one cell — a whole-field sweep gives ~n/13 samples per reader and is too noisy
to read a real shift off.

### fill()/PRON — a missed port, not a balance question

Separately: sign rules are written with `{S}`/`{es}`/`{o}` pronoun tokens meant
to be substituted from the sitter's own pronoun at display time (source `PRON`
~1156, `fill()` ~1187). Nothing did the substituting, so every sign rule was
shown to the player raw — "{S} need{es} it to be a performance." The table is
now `data/base/pronouns.json` (a normal, moddable registry) and `I18n.fill()`
does the substitution *after* translation, so a locale supplies its own pronoun
words. `tests/test_i18n.gd` now asserts no sign, job or elite twist can leave a
`{token}` unfilled for any pronoun.

## The Minitel — an addition, not a port

Nothing in `Parlour v23.dc.html` has a Minitel in it. This is the one feature
in the project that is invented rather than ported, and it is recorded here so
nobody later mistakes it for something the prototype had.

It exists because the port grew two things the prototype did not have — a
profile that persists between runs, and an `unlock` field that finally does
something — and neither had a way for the player to *reach* them. A code you
type on a period-correct terminal is a way in that costs one screen.

What was deliberately NOT built:

- **A general effect language.** Three named levers (`grants`, `arms`, and the
  bare fact of having dialled) instead. Each can be validated by name; a DSL
  cannot, and the recurring failure this document keeps recording is content
  that loads clean and silently does nothing. `docs/MINITEL.md` has the
  argument at length.
- **Real content.** Two demonstrator codes ship, marked as such in their own
  `_note` fields, so the levers are exercised by the tests on real records.
  The codes worth finding are the author's to write.
- **A progress counter.** "3 of 8 services found" is a checklist, not a secret,
  and there is no honest total once a mod can add codes.

Two things fell out of building it that are worth naming. `Profile.unlock_text`
derived "Finish a run as %s" from any `includes` condition, which became wrong
the moment a second list stat existed — it now branches on the stat. And a
code's `screen` array keyed every line under one id, so a *translated* service
would have printed its first line four times over; invisible in English, where
every lookup misses and falls back. Both are guarded in
`tests/test_minitel.gd`.

## Where to look

- `autoload/Rules.gd` — the scoring engine, pure and stateless, the intended
  single source of truth per `HANDOFF.md`.
- `autoload/Run.gd` — the run/turn state machine.
- `autoload/Save.gd` — run persistence and content re-resolution on load.
- `autoload/Profile.gd` — what persists between runs, and unlock conditions.
- `autoload/Minitel.gd` — the 3615 secret-code channel; see `docs/MINITEL.md`.
- `autoload/Audio.gd` — named game moments; see `docs/SOUND_GUIDE.md`.
- `autoload/Content.gd` + `autoload/ModLoader.gd` — content loading and the
  mod-pack merge logic; see `docs/MODDING.md`.
- `autoload/Workshop.gd` — the Steam Workshop stub; see `docs/STEAM_WORKSHOP.md`.
- `autoload/Art.gd` — resolves art ids to textures, null when undelivered;
  see `docs/ART_GUIDE.md` (artist-facing) and `tests/gen_art_manifest.gd`.
- `scenes/` — the playable UI.
- `tests/` — headless tests, runnable without a display:
  `godot --headless --path godot -s tests/test_rules.gd` (scoring engine),
  `tests/test_run.gd` (state machine, plays random full encounters),
  `tests/test_scenes.gd` (instantiates every screen against every game state),
  `tests/test_content_audit.gd` (fx cross-check, the AUDIT tab equivalent),
  `tests/test_minitel.gd` (the 3615 code channel, incl. the guarantee that a
  secret event cannot be met without its code),
  `tests/test_art.gd` (art manifest -> texture pipeline, incl. the
  "runs fine with zero art delivered" guarantee),
  `tests/balance_sim.gd -- <n>` (difficulty report, the BALANCE tab equivalent),
  `tests/gen_art_manifest.gd` (regenerates the artist's checklist from live
  content), `tests/gen_test_art.gd` (dev-only: fake gradient art to exercise
  the delivered-art path),
  `tests/screenshot.gd <scenario> <out.png>` (dev-only: renders one scenario
  under a real Xvfb + software-GL display and saves a PNG — how every UI
  layout claim in this file and in commit messages was actually verified,
  not guessed at; requires `xvfb-run`, not part of the pass/fail test suite).
