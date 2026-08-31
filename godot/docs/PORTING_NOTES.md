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
- **Meta-progression** (persistent unlocks across runs) — never implemented
  in the source either; nothing to port. Note that every reader carries an
  `unlock: null` field that nothing reads, so the *scaffolding* is ported and
  inert: all 13 readers are available from the first launch.
- **Controller and keyboard navigation.** Escape closes the Settings, Library
  and Mods screens; everything else is mouse-only. No focus traversal, no
  gamepad, no keyboard shortcut for laying a card.
- **Sound.** `master_volume` and `muted` drive the real AudioServer master bus
  (deliberately — see `autoload/Settings.gd`), but the game ships no audio
  files, so both are honest wiring with nothing to carry.

Save/resume WAS on this list and is now done — see below.

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
dropped and counted rather than kept as a husk.

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

## Where to look

- `autoload/Rules.gd` — the scoring engine, pure and stateless, the intended
  single source of truth per `HANDOFF.md`.
- `autoload/Run.gd` — the run/turn state machine.
- `autoload/Save.gd` — run persistence and content re-resolution on load.
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
