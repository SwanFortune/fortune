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

4.7 is now the only version tested. Running the suite against both for a while
was worth it — it is how the above was caught in the first place — but keeping
a superseded engine green is upkeep the project is not being paid for, and the
guard that matters survived the retarget: `test_content_audit.gd` fails on a
whole number stored as a float regardless of how the engine renders it, so this
class of bug is caught by an assertion now rather than by owning two binaries.

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

## Settings, and the four rows that are not there

The settings screen grew from one scrolling column into a category rail when it
passed twenty rows. The layout is unremarkable; two decisions underneath it are
not.

**Every setting does something real, and the absences are the evidence.** There
is no music slider (there is no music), no screen-shake toggle (nothing
shakes), no gamepad-rumble row (nothing rumbles). Those are exactly the four
rows a settings menu accumulates by imitating other settings menus, and each
one would be the first control in this game that lies to the player. What did
get built is what could be wired: window mode, resolution, vsync and an fps cap
are real DisplayServer and Engine calls; the three volumes drive three real
AudioServer buses created at startup; text size and high contrast are read by
UIKit on every screen build. `tests/test_settings.gd` asserts DEFS and the
screen's section list cover each other exactly, so a setting can no longer be
added and then left unreachable — which is precisely what happened to the
`unlock` field for most of this port.

**The look settings are PULLED by UIKit, not pushed by Settings.** The obvious
design — Settings pushes `text_scale` and the palette into UIKit whenever they
change — does not work here, and the way it fails is the one this document
keeps recording. Settings is the first autoload, so when its `_ready()` runs,
I18n, Content, Rules and Art do not exist yet; UIKit refers to all four, so
`preload("res://scenes/UIKit.gd")` from Settings compiled to nothing
("Identifier not found: I18n") and every call on it failed silently. Deferring
the push would have fixed the compile and left an ordering hazard, since the
main scene is built before the first deferred call flushes. UIKit reading the
settings itself, at the top of `root_control()`, needs no ordering guarantee at
all. `tests/test_scenes.gd` asserts a built screen actually reflects both
settings, because a headless Settings test cannot load UIKit to check.

### A focus bug that only a rebuild could show

Building the rail surfaced a real bug in `UIKit.focus_first()` that had been
there since it was written. Screens rebuild by calling `queue_free()` on their
single root child and adding a new one; `is_queued_for_deletion()` reports only
on the node it is called on, so every Button inside that doomed subtree
answered "no", stayed in the tree until the end of the frame, and was the first
thing the focus walk found. Focus landed on a node that then vanished, and the
rebuilt screen had nothing focused — a keyboard or gamepad player was stuck.

It needed a screen that rebuilds itself in place to show up, and until the
settings rail there was not one. `UIKit.going_away()` now walks the ancestor
chain. A second, smaller version of the same problem sat next to it: Godot
places focus on a *disabled* Button quite happily, so the rail's disabled
"you are here" entry absorbed the focus and pressing Confirm on arrival did
nothing. `test_scenes.gd` now fails on both, and both were confirmed by
stubbing the fix and watching the test go red.

## The gamepad claim was not true

The controls pane told the player, in as many words, that the whole game is
playable on a gamepad and that rebinding a key leaves the pad button alone.
Neither sentence was true as the project loaded.

`parlour_deck` and `parlour_marks` had no joypad event at all — so there was no
button to keep, and a controller player could not open their deck or their
marks. Worse, and this is the one that matters: **`ui_accept` and `ui_cancel`
had none either**. A pad could move the highlight around every screen in the
game and never confirm anything.

The reason it stayed invisible is worth recording. `ui_left`, `ui_right`,
`ui_up` and `ui_down` DO arrive with their D-pad and stick events, so
navigation worked perfectly — which is exactly the half you notice. The comment
in `project.godot` asserting that the built-ins "already carry sensible
defaults on keyboard and gamepad" was written on the strength of that and was
half right. The existing test spot-checked `parlour_read`, which happened to be
the one action that did have a button.

`ui_accept` and `ui_cancel` are now declared explicitly with their keyboard
defaults plus A and B; the two overlay actions got the shoulder buttons.
`tests/test_settings.gd` fails if any action a player needs is left without a
joypad event, and the controls pane now SHOWS each pad button beside its key —
a promise about a button nobody can see is not much of a promise.

## The deck and marks panels were not modal

They are drawn over an in-run screen that is still live underneath, and every
single thing that makes a modal a modal was missing. Each failure was silent:

- focus stayed on the card behind the scrim, so a keyboard or gamepad player
  who opened their deck and pressed Confirm played a card they could not see —
  worse than a dead highlight, because something happens;
- pressing D again opened a second deck on top of the first;
- Escape closed nothing;
- the reading's own READ IT shortcut still fired at the board underneath.

`RunHeader.handle_shortcut()` now swallows everything while an overlay is open,
the overlay takes focus when it opens and gives it back when it closes, and the
shortcut that opened it closes it. All four are asserted in
`tests/test_scenes.gd` and each was confirmed by stubbing the fix.

### The `preload` trap, for the fifth time

Writing that test hit the same wall this document keeps describing, in its
worst form yet. `preload("res://scenes/RunHeader.gd")` inside the test script
resolves while the test is being COMPILED — before `godot -s` has registered
the autoloads — and RunHeader refers to `Run`, `UIKit` and `I18n`. It did not
merely fail locally: RunHeader stayed compiled to nothing for the whole
process, so every in-run screen lost its header and six unrelated cases in the
same file started failing. `load()` at call time is the fix, as it was the
other four times.

## Editing a card did nothing to the run you were in

`Run.state` is full of COPIES of content records — every card in the deck, the
reader, the sitter's sign. Reloading the registries does not touch them, so
after a content change a run in progress has to be put through `Save` to be
re-resolved against the new registries.

The Mods screen knew that and did it. The Library did not. So retuning a card
in the Library while a run was in progress changed the registry, left the deck
holding the old numbers, and the player watched their own edit do nothing for
the rest of the night — with the Library showing the new values the whole time.

The fix is not "add the missing calls to the Library". Four things need
reloading (Art, Audio, I18n, and the live run), the Library did two, the
Settings screen did three, and the next screen that reloads content would have
had to get the list right from scratch. `Content` now emits `reloaded` and each
subsystem connects to it in its own `_ready()`, in autoload order — so the list
cannot be got wrong once and copied wrong forever, and every caller is a single
`Content.reload()`.

## Two things about autosaving that nothing was checking

Persistence had good tests and a blind spot: every one of them wrote the save
itself and then read it back, so all of them would have passed on a build where
`Run.state_changed` was never emitted and the game autosaved nothing at all.

`test_save.gd` now plays whole runs and, after every single action, checks that
a state which actually moved also armed a save — comparing the state's own hash
before and after, so a Run method that mutates and forgets to emit is caught at
the action that did it. Deleting one `state_changed.emit()` from `lay_card()`
turns it red, which is how it was verified.

The second is the quit path. Writes coalesce through a dirty flag to one a
frame, which is right — `state_changed` fires on every card laid — but it
leaves a window where the newest action exists only in memory. A player who
lays a card and immediately closes the window is squarely in it. `_notification`
already flushed on the way out; nothing checked that it did.

## The mod loader had no test

An odd place for this project to have a hole. Mod support is what the port is
FOR, `docs/MODDING.md` makes specific promises about merge behaviour, and seven
distinct error paths had been written in the belief that a real pack would hit
them one day. None of them had ever run.

`tests/test_modloader.gd` now drives the loader with REAL PACKS written to
`user://mods/` and read back off the disk, rather than handing the merge
functions dictionaries. The promises are about files — a manifest that will not
parse, a listed file that is not there — and a test that skips the filesystem
cannot make them.

Nine of the ten checks passed on the first run, which is the good news: the
merge rules and the recovery-from-a-bad-file behaviour were genuinely correct,
including the load-bearing one — a pack with four broken files still loads its
good ones.

The tenth found this: **one unparseable `mod.json` produced four error
messages**. `_read_json` reported the parse failure and `_load_manifest` then
added "and it is not a JSON object" on top, which is a second message for one
fault; and `_load_manifest` was called twice per pack, once during discovery
for the `priority` field and again in the load pass, doubling both. The Mods
screen counts what it is handed, so a modder with one typo was told they had
four problems. Manifests are now parsed once and cached, and a null parse is
left to the message that already explained it.

## Nobody could build the game, and nothing tested that it starts

Two gaps that only showed up when the question became "what is missing for a
playable release" rather than "does this system work".

**There was no export configuration.** Not because it had been forgotten —
because `export_presets.cfg` is in the standard Godot `.gitignore` (it can hold
signing keystore paths and passwords), so anyone cloning this repo got a
project that could be run from source and not built into anything. It is
committed now, with the reason written into `.gitignore` next to it, and it
holds no secrets: codesigning is off on all three presets.

**Nothing booted the game.** `tests/test_scenes.gd` instantiates each screen
directly and drives it, which is the right way to test a screen — and means the
project's actual main scene, the one path every player takes and the only one
that runs on launch, had no coverage at all. What that cost: `Boot._ready()`
called `change_scene_to_file()` synchronously, which frees the current scene
while the tree is still adding Boot as a child, and Godot printed

    ERROR: Parent node is busy adding/removing children

on **every launch since the first commit**. Harmless, invisible to the suite,
and found only by exporting a build and running it. `tests/test_boot.gd` now
asserts the game reaches the main menu, and the README documents the one check
the suite cannot do for you — engine `ERROR` lines are not visible to GDScript,
so noticing them means running the game and reading the output.

## The interface did not scale with the window

Godot's default `stretch/mode` is `disabled`: the UI renders at 1:1 pixels
whatever the window size. Nothing had ever set it, because the whole port was
developed at the default 1152x648 — so the video settings added a commit
earlier made things worse rather than better. Going fullscreen on a 1080p
screen left the same small text stranded in more empty space, and `ui_scale`
was not a preference but the only thing making a large display usable at all.

`canvas_items` + `expand` now scales the interface with the window and gives
extra width to more view rather than to bars, which is right for a layout that
is columns and lists. `ui_scale` multiplies on top, so it goes back to meaning
"and a bit bigger than that". Checked at 1152x648 and 1920x1080 under Xvfb, and
asserted on the live Viewport in `tests/test_settings.gd` rather than on the
project setting, so a stray `content_scale_mode` assignment anywhere would
still be caught.

## The game explained itself nowhere

Every explanation in the port lived in a hover tooltip: unreachable on a
gamepad, invisible to anyone who does not think to hover, gone the moment the
mouse moves. A player opening it cold had no way to learn what composure is,
why the ORDER of the cards is the entire game, or what a sign's denial does.

`scenes/HowToPlay.gd` is that screen, and the interesting decision is that it
is mostly NOT new prose. The glossary is `UIKit.KEYS`, which the author wrote
and the locale already translates. The elements are `elements.json`. The
element wheel is drawn from `Content.ring` — the same array `Rules.link_of()`
walks — and the controls are read off the live InputMap, so a rebind appears
there immediately. Only the four sections describing the loop are written for
the screen, and they paraphrase the prototype's own `handoffRules()` ("The
loop", "Resolving one reading") for a player rather than for a porter.

That is not tidiness. A rules screen that restates the game in its own words is
wrong the first time a number changes and nothing notices, and a rules screen
that is wrong is worse than none: a player follows it, loses, and concludes the
game cheats. `tests/test_scenes.gd` asks the engine whether the wheel the
screen draws is the wheel it uses.

Two things fell out of building it. A ScrollContainer does not scroll from a
gamepad — it scrolls on the wheel and on a drag, and otherwise only moves to
keep a FOCUSED child visible. A screen made of paragraphs has no focusable
children, so on a controller it showed the first screenful and nothing else,
which for a rules screen is most of the rules missing. And the modal scrim was
inert, so the only way out of the deck panel with a mouse was to find CLOSE.

## The preload trap, made into a rule

Six times now a file has been broken by `preload()`ing a script under
`scenes/`. preload() resolves while the file containing it is COMPILED, and
anything launched with `godot -s`, plus every autoload, is compiled before the
autoloads are registered — so preloading a scene script from that position
compiles it to nothing, silently. The worst case did not even fail locally:
preloading RunHeader from a test left it compiled to nothing for the whole
process, and six unrelated cases in that file went red.

`tests/test_dead_content.gd` now refuses the pattern outright: nothing in
`autoload/` or `tests/` may preload a script under `scenes/`. It is a text
scan, not a runtime check, because the failure IS at compile time. It found a
seventh instance the moment it was written — a dead `const UIKit` in `Run.gd`
that was used by nothing at all.

## The quietest failure in the project: a run that stopped being saved

If `user://` is read-only, or the disk is full, every write fails. `Save` set
`last_error`, pushed a warning to the console, and told the player nothing at
all — and the player is mid-run, nowhere near a console. They finished three
nights, closed the game, and the run was simply gone: no CONTINUE on the menu,
and no explanation ever, because `last_error` does not survive a relaunch
either.

Reproduced by putting a DIRECTORY where the save file belongs, which is what a
full or read-only disk looks like from `FileAccess.open(WRITE)`. The run header
now carries a red line for as long as writing keeps failing, and clears it the
moment one succeeds — loud and permanent, but not a modal, because a player
mid-reading should not have their turn interrupted and must not reach the end
of the night still believing their progress is being kept.

The same silence covered the other two stores: `Profile.save_to_disk()` and
`Settings.save_to_disk()` both discarded `ConfigFile.save()`'s return value.
Smaller stakes — a lost unlock, a setting that resets every launch — and the
same fix, said once at the main menu, which is where someone would otherwise
notice their options reverting and have no idea why.

`tests/test_scenes.gd` asserts both by RENDERING THE SCREEN and reading its
labels, not by testing the flag. The flag was already being set correctly; what
was missing was anyone showing it, and a test of the flag would have passed
throughout.

## A whole visual system had not been carried over

The prototype draws real line art for every element, every zodiac sign, every
ruling planet and every card archetype — `EL_ART`, `SIGN_ART`, `PLANET_ART` and
`ARCH`, about thirty pieces of it. This port had been showing △▽◇□ instead,
which are the CHARACTER FALLBACK the source itself uses only when its own art
is unavailable. The icons were in the design the whole time and nobody had
looked for them.

They are now `data/base/icons.json`, path data verbatim, rasterised by
`autoload/Icons.gd` through `Image.load_svg_from_string()`. Nothing in this
project parses SVG: the paths go straight to Godot's renderer, which means they
stay exactly as authored (arcs and all), each icon is rasterised at the pixel
size it will actually be drawn at — so it is crisp under `text_scale` and
`ui_scale`, where a fixed-size PNG would go soft — and there is no import step,
so icons ride the ordinary content pipeline and a mod can ship its own.

**The bug that came with it is the interesting part.** `Color.to_html()` returns
bare hex digits; SVG requires a leading `#`; and an invalid colour in SVG is not
an error — the stroke simply renders as nothing. Every badge came out as an
empty tinted square, and the probe that was supposed to catch it missed because
it used a hardcoded `"#d4b038"` literal. `tests/test_icons.gd` now rasterises
every icon and COUNTS THE PIXELS, which is the only check that can tell a
drawing from a well-formed request that drew nothing; stubbing the `#` back out
turns thirty assertions red.

## Saves: atomic writes and a rolling backup

Three practices, each answering a specific way a save is lost.

**The write was not atomic.** The run went straight to `save.dat`, which means
the save WAS a half-written file for the length of every write — and this game
writes several times a minute, so that window gets sampled often. A crash or a
power cut in it left a truncated save and no run. It now goes to `save.dat.tmp`
and is RENAMED into place; a rename within one directory is atomic on every
filesystem this ships to, so the file on disk is only ever the old save or the
new one.

**There was nothing to fall back to.** The previous save now becomes
`save.dat.bak` before the new one replaces it, and a save that cannot be read
falls back to it — with a line on the menu saying the player may have lost a
step. Refusing a corrupt save while a good one from ten seconds earlier sat
beside it unused would have been a worse answer, and using it silently would
have moved someone back in time without telling them. A VERSION MISMATCH does
not fall back: a save from a newer build has a backup from that same build, and
trying it would only produce the same refusal twice. `clear()` takes the backup
with it, or an abandoned run could be resurrected by a later bad read.

`profile.cfg` and `settings.cfg` are written the same way, for the same reason
at smaller stakes.

## The game was played on a table, and there was no table

The reading screen was a dark rectangle with widgets on it. The game is a
fortune-teller sitting at a table in a village front room, dealing cards to
someone in trouble, and none of that was anywhere on screen — not the room, not
the table, not the cloth, and not the person doing it.

`scenes/Table.gd` draws all three, procedurally: a warm wooden table, a deep
green cloth inset from its edges with a worn patch rubbed into the middle, a
vignette that puts the eye where the cards are, and — the part that matters —
the reader's own two hands, coming up from the bottom of the screen and holding
the fan.

**The hands were already in the writing.** The overlay that lists your relics
is titled YOUR HANDS. The four kinds of mark are RING, TATTOO, SCAR and BOON.
The game had always described them as things on the reader's hands, and for the
entire port they had been rows in a panel. They are now on the hands: a ring
you win goes on a finger and stays there for the rest of the run, ink goes on
the back of the hand, a scar across the knuckles, and a boon — the one that is
not a mark on skin — as a small warm light held above the hand, which is why it
is not drawn as one. The colour of each is its element, or gold when it has
none.

Four things about it are worth writing down, because each was a wrong version
first:

**The hands are drawn AFTER the cards.** Behind them they are a picture of
hands near a fan. In front of them, the fingertips cross the lower edge of the
cards and the fan is held. That is entirely a matter of sibling order, so
`tests/test_scenes.gd` asserts it — nothing else would notice a reorder.

**They hold the fan, not the screen.** Nailed to fixed fractions of the window,
two hands hold a hand of two cards at arm's length and a hand of nine by the
middle. `Table.hands()` takes a callable that returns the fan's real extent,
called at DRAW time, which is after layout — so the hands find the cards
wherever the container put them. The fan is centred for the same reason.

**Every mark has to land somewhere.** `Table.mark_places()` is a pure function
returning a point per mark, separate from the drawing, so a headless test can
assert that eight marks produce eight places, that no two land on the same
point, and that a kind the base game gains but the drawing does not know about
is caught rather than silently invisible. Rings WRAP around the four fingers
rather than stopping at the fourth: a fifth ring that is simply not drawn is a
reward the player was told they had and cannot find.

**And a placeholder is still a placeholder.** It is geometry — ellipses,
tapered capsules, a few lines — not illustration, on the same terms as the
sitter portraits. `docs/ART_GUIDE.md` says what an artist replaces and what
they have to keep.

## The room, and the card that floats in it

The table came first and the rest of the room followed, because a table alone
still reads as an abstraction: a green shape with cards on it. `scenes/Table.gd`
now draws the whole parlour — a papered wall with a picture rail and a skirting
board, a closed panelled door with a brass knob, a coat hung on a hook, a
floor whose boards crowd together toward the wall, the table in perspective
with its cloth, and, standing on it, a Minitel and a cup of tea going cold.

**Nothing in it was invented.** Every prop is something the game already says:
the door is the one someone knocks on and a run ends when the knocking stops;
the coat is TAKE THEIR COAT; the cup is POUR THE TEA and WARM THE CUP; the
cloth is SET DOWN THE CLOTH; the light is LIGHT THE LAMP, drawn as the pool it
throws because the framing never shows a ceiling. The Minitel is the machine
the 3615 screen has been dialling for the whole port without ever being drawn.

Three things it got wrong first, each worth keeping written down:

**A room drawn at full strength is a room you cannot read text on.** The first
pass had a lit architrave the size of a door sitting directly under the header
and wallpaper stripes competing with the sitter's name. Everything above the
horizon is now deliberately darker than the table, the door frame is a border
rather than a filled slab, and the props are placed in the gaps the reading
screen's layout actually leaves (`MINITEL_AT`, `TEACUP_AT`). A prettier wall
that makes a sentence hard to read is a bad trade.

**The table was a shape cut out of a void.** In perspective it does not reach
the sides of the screen, and what showed in the two wedges beside it was the
flat colour of the empty UI background. Drawing a floor first — three lines of
code — is the difference between furniture standing on something and a
polygon floating on a colour.

**A rounded-rectangle helper could draw none of it.** Nothing in the room is a
rectangle: the table and the cloth are trapezoids because they are in
perspective, the Minitel's body and the cup are tapered. `_soften()` rounds
whatever polygon it is handed, using each corner as the control point of a
quadratic curve between the two edges meeting there.

### One card does not get held

When the hand is down to a single card, clamping it between two fingertips the
way five cards are clamped looked like a mistake — the hands closed on each
other around one sliver. The last card FLOATS instead: lifted clear of two open
hands, in its own pool of light, with a shadow where it would be lying if it
were on the cloth, breathing gently up and down.

Two mechanisms, both worth knowing about:

**The hands open.** `Table.hands()` takes a `reach`. At 1.0 the fingers stretch
to the top of the band and close over what is drawn there; below it they
shorten AND curl — shortening alone gives a hand with stubs on it — which is
what a pair of hands that has just let go looks like. It also raises the floor
on how close the two hands may come, because an open hand's fingers curl inward
across its own palm and need more room than a closed one's.

**The card leaves its container**, since a ScrollContainer clips (it would cut
the halo off at the band's edge and cut the card in half as it bobbed) and a
Container re-asserts its children's positions every layout pass. That buys the
freedom to tween `position` — and costs two things the container was doing:

- **Its size.** `Control.size` is clamped up to the combined minimum, and a
  card's name is an auto-wrapping Label whose minimum HEIGHT depends on the
  width it has been given — which, before the first layout pass, is zero. So it
  reported the height of a one-word-per-line column and the card came out
  nearly twice as tall as every other card in the game, silently. Re-applying
  the intended size on `minimum_size_changed` is what actually pins it.
- **Being reachable.** A floating card that cannot take focus is a hand a
  keyboard or gamepad player cannot play, and the run is stuck.

`tests/test_scenes.gd` checks all three: the floating card is the same size as
every other card, it takes focus, and the fingertips clear it — the last one
read from `Table.finger_geometry()`, the same geometry the drawing uses, and
asserted in BOTH directions, so open hands must clear the card and closed hands
must cross the fan. Every guard was verified by stubbing the fix and watching
the test go red.

## Every screen is somewhere

Drawing the parlour behind the reading screen made a new problem: the reading
screen was a room and the other thirteen were flat rectangles with widgets on
them, so the game looked half-finished in a way it had not before. The map is
seen as often as the reading is.

The room is now the backdrop to the whole game, in three views, all of the same
house:

| View | Where you are | Screens |
|---|---|---|
| `VIEW_TABLE` | At the table, looking down at the cloth | The reading, the result, rewards, the shop, events |
| `VIEW_DOOR` | Looking across the room at the closed door | The main menu, "who knocks tonight?", and the end of a run |
| `VIEW_WALL` | The papered wall and the boards, nothing else | Settings, library, mods, the rules, the credits, the Minitel, choosing a sign |

**The view is a parameter of `UIKit.root_control()`, not something each screen
does for itself.** Every screen already called it, so this was one change rather
than thirteen — and, more to the point, "every screen is somewhere" is now a
rule a fourteenth screen cannot forget, because it gets the room whether or not
whoever writes it knows the rule exists. `tests/test_scenes.gd` asserts it from
inside `_check_focus()`, which every visit in the sweep already goes through, so
the check extends to screens that do not exist yet. It also asserts the room is
BEHIND the screen: a backdrop drawn over the words is worse than no backdrop,
and nothing else would notice.

`VIEW_WALL` exists because the first pass gave the reference screens the table.
A settings list is dense with words and nothing is happening in it; a table laid
out behind a row of sliders, with a teacup showing through the gaps between
them, is something to look past rather than at. The bare wall keeps those
screens in the same house without asking anything of the reader.

### The menu became a column

With a room behind it, the main menu's stack of buttons stretched from one edge
of the window to the other was suddenly the problem: it covered the room
completely, and an 1100-pixel-wide button was never good anyway. The menu and
the run-over screen now read down a column on the left, with `UIKit.side_scrim()`
darkening only that side.

A scrim over the WHOLE backdrop was the first attempt, and it quietens the part
of the room nothing is written on exactly as much as the part that needs it —
you pay for the room and then hide it. Darken the side the words are on and
leave the rest.

The door moved to the right of the frame for the same reason, so the screens
using that view have somewhere to put their text. And what is under the door
went from a bright bar — a strip light, not a door — to a hairline at the
threshold with a soft spill on the boards in front of it, because light coming
under a door lands somewhere.

## The person across the table, and the knock at the door

Two things the writing had always described and the game had never shown.

### The sitter was a smiley face

`UIKit.sitter_portrait()` drew an oval with two rectangles and a curve in it,
which is exactly what it read as. It sat on a screen that is now a room, and
the weakest thing in that room was the one PERSON in it — the one you look at
for a whole encounter while deciding what to say to them.

It is a bust now: shoulders coming up out of the frame, a collar, a neck, a
head, hair, a face. Everything about it answers to two things:

**Composure.** The brows lift and arch, the eyes open, the mouth goes from a
flat line to something close to a smile, and the shoulders come down out of
their hunch — a person who has been got through to stops holding themselves up.
Closed off and reached should not need a number to tell apart.

**Who they are.** Hair, colouring, face width and moustache come from a hash of
the sitter's name and role. Ten villagers who all look the same are not
villagers; a face that changes between one screen and the next is not a person.
So it is derived, never random — and the hash is nine lines of ours rather than
`String.hash()`, which is an engine detail with no promise attached and would
quietly rearrange every face in the village on a Godot upgrade. The only thing
taken from the sitter's `p` field is whether they can have a moustache;
deriving more than that from a pronoun would be inventing people the writing
did not write.

Two bugs worth keeping: the first version asked sitters for a `k` field they do
not have, so every hash was the hash of `""` and the village was one person
drawn nine times. The FIRST version of the test did not catch it, because the
test derived the key for itself and so only proved that two copies of one line
agreed. The portrait now hangs the face it actually got on the node as metadata
and the test reads that back — the only version of the check that goes through
the real path.

### Nobody had ever knocked

The map screen asks "who knocks tonight?". A run is sixteen knocks long. It
ends the night the knocking stops. Nothing in the port had ever knocked.

Three raps on the door behind the screen, accelerating slightly the way a
person's knuckles do: the sound (`knock`, a placeholder in `gen_sounds.py`
like the rest), the door leaf jumping in its frame — the leaf and not the
frame, because it is the gap between them that rattles — and more of whoever is
outside coming under the door with each one. The options fade in on the beats.

**It does not take the screen away.** The choices are built and focused on the
first frame; a player can choose during the first knock. An atmosphere beat that
holds the game hostage is one you resent by the tenth night, and the test
asserts focus is placed BEFORE waiting for a single knock.

**And it still knocks with the animations off.** Turning off motion should not
make the game go quiet, and the easy version of this feature is one early return
that does exactly that. `Audio.played` — a count per event — exists so a
headless test can hear it; there was no other way to assert a sound.

## The reading is read out

READ IT resolved the whole reading between two frames and left for the next
screen. That is where the game's mechanic actually pays off — a line of cards
chained by their elements, a wall that eats the front of it, and whatever is
left landing on the person opposite — and none of it was ever visible. Which is
a fair part of why it is the hardest thing in the game to learn: the rule ran,
and the player saw a number change on a screen they had already left.

It is read out now, as a ledger that writes itself, in the order the rule
actually works:

1. a line per card, with the LINK NAMED next to what it paid. This is the only
   place in the game a player is shown *why* a card scored what it scored while
   looking at the card that did it;
2. the wall taking its share — shown only when it took something, because a
   line saying "the wall held off 0" teaches the opposite of the rule;
3. what actually reaches them, which is the number that mattered all along and
   was never once seen arriving.

**It is skippable and it never blocks.** Any key, a click, or READ IT again
jumps to the end. With animation turned off there is no ledger at all — the
old behaviour, unchanged.

**And it resolves exactly once.** That is the whole risk in this feature and it
is invisible from outside: there is now a two-second window in which the reading
has been asked for and has not happened, and everything a player can do in that
window has to land on the same resolution. Resolving twice would lay the entire
line a second time — double composure, double faith, a reading nobody played —
and the screen would look right either way. `tests/test_scenes.gd` asserts the
turn advances by exactly one.

Writing that test turned up a mistake worth recording: the first version watched
`Run.state["res"]`, which is only set when the whole ENCOUNTER ends, not after an
ordinary reading. It reported two failures that were not there. The observable
is the reading number.

## The Minitel had no Minitel in it

The screen the game names after the machine was a green rectangle with text in
it, which is a terminal emulator. The machine — the beige box, the bezel, the
curved dark glass, the scan lines, the blinking block cursor and the little red
light that says it is on — is most of what anyone remembers about a Minitel, and
the game was already drawing one on the parlour table (`scenes/Table.gd`) while
the screen named after it drew none.

Drawn rather than styled, because a StyleBox can do a rounded beige box and
cannot do any of the other four, and those four are the difference.

## Eight more evenings

`docs/STEAM_RELEASE.md` has said for a while that the shortage a player would
notice first is content, and named the number: THREE ordinary events for a
sixteen-knock run. You see one roughly every five knocks, and you have seen all
three by the middle of the first night.

There are eleven now. **The eight new ones were written during the port, not by
the game's author, and they say so**: each carries `"added": "port"`, so the
whole set can be found and replaced in one search. They follow the source's
shape exactly — a head, a title, a line, and two options that trade the
evening's money against what the village thinks of you — because that shape IS
the game: you are a fraud doing counselling, and every event is the same
question about whether you take the coin.

`test_dead_content.gd` caught the marker immediately, which is what it is for: a
field no code reads is either a mistake or a decision, and it now sits in KNOWN
as a decision, with the reason. A marker the code acted on would be a marker
that changed the game.

### An option can name its card

Two of the new events hand over a real card and one hands over a mark, which
needed something the engine did not have. An option may now say
`"card": "Pour The Tea"` instead of carrying a copy of the card object, and
`Run.resolve_named()` looks it up against whatever content is loaded.

Inlining the card would have been less code and quietly wrong: an events file
carrying a copy of a card is a SECOND COPY OF THAT CARD'S RULES. It goes stale
the moment anyone rebalances the card, a mod that rebalances it does not
rebalance the copy, and `Save.gd`'s content re-resolution cannot tell the copy
from the original. The cost of the name is that it can be misspelled, and a
misspelled name fails in the worst possible way — the option is still offered,
still reads well, and hands over nothing — so `tests/test_run.gd` walks every
name in the shipped content and asks whether anything answers to it.

`Run.resolve_named()` is called from the pick SCREEN too, not only from
`take_pick()`. Without that the row a player reads and the thing they get are
built from different objects, and a named card fell through to the branch for
options that are neither a card nor a mark: it printed its own name as flavour
text and no rules at all.

And the row shows the option's own words. Only that third branch printed
`text`, so an option that handed over a card threw its line away and read like a
shop entry — which for these events is the whole voice of them ("It smells like
her kitchen and it works, which you resent").

## Where to look

- `autoload/Rules.gd` — the scoring engine, pure and stateless, the intended
  single source of truth per `HANDOFF.md`.
- `autoload/Run.gd` — the run/turn state machine.
- `autoload/Save.gd` — run persistence and content re-resolution on load.
- `autoload/Profile.gd` — what persists between runs, and unlock conditions.
- `autoload/Minitel.gd` — the 3615 secret-code channel; see `docs/MINITEL.md`.
- `autoload/Settings.gd` — every player setting, what it applies to, and the
  section list the settings screen renders.
- `autoload/Audio.gd` — named game moments; see `docs/SOUND_GUIDE.md`.
- `autoload/Content.gd` + `autoload/ModLoader.gd` — content loading and the
  mod-pack merge logic; see `docs/MODDING.md`.
- `autoload/Workshop.gd` — the Steam Workshop stub; see `docs/STEAM_WORKSHOP.md`,
  and `docs/STEAM_RELEASE.md` for what a Steam release needs beyond it.
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
  `tests/test_modloader.gd` (pack discovery, the merge rules, and every error
  path, driven with real packs on disk),
  `tests/test_boot.gd` (the game starts — the main scene had no coverage at
  all until a build was exported and run),
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
