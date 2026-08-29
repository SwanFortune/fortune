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

- **Visual polish.** No fan-of-cards layout, no portrait mood animation, no
  hand-drawn sign/element/planet SVG glyphs, no unified tooltip system, no
  booster-pack-opening animation, no letter-by-letter "mumble" reveal when a
  reading resolves. The UI (`scenes/*.gd` + `scenes/UIKit.gd`) is plain
  labels-and-buttons, built to prove the loop plays correctly, not to look
  like the prototype. Pixel-matching the source's design is a real follow-up
  task, not a rejection of the "recreate pixel-perfectly" brief — it's a
  scope cut for this pass specifically.
- **The CARD TABLE dev UI** (CARDS/AUDIT tabs — live-editing content and
  cross-checking `fx` keys against hand-written prose). Nothing calls
  `Rules.auto_text()`/an fx-audit for the whole content set yet outside the
  tests; only the balance simulator below was built out.
- **Full Steam Workshop / Steamworks integration** — see `docs/STEAM_WORKSHOP.md`.
- **Meta-progression** (persistent unlocks across runs) — never implemented
  in the source either; nothing to port.
- **Localization, controller support, save/resume mid-run, settings menu.**

## Balance: a first read

`tests/balance_sim.gd` ports `simFight()`/`simSweep()`/`simGroup()` — the
source's own greedy-auto-player difficulty check — and runs clean against the
ported content. A 600-fight sample (each fight: one of the 13 readers vs. a
random sitter scaled to night=1/step=3, matching the source's own baseline)
came back:

- **83.8% overall win rate** — right at the edge of the source's own "over
  85% asks nothing of you" guideline. Consistent with the source's own
  admission that this measures night-1 difficulty, not a full 3-night run,
  and that the numbers were still being actively tuned at handoff time (see
  above) — not a claim that the port is under- or over-tuned, just that it's
  reproducing the same "still loose" state the source was in.
- **Taurus (sign) stands out low at 32%** — right at "close to unwinnable."
  Its denial (`shield`, a numeric wall that thickens every reading) is the
  only sign with a persistent stacking wall from reading 1, which the greedy
  bot handles worse than the purely-behavioral signs.
- **Virgo (reader) stands out high at 100%** — its passive (`white`: cards
  with no element restore +3) stacks unusually well with the 7 always-neutral
  basic cards every reader starts with.

Worth a look before any real balance pass, but not something this port
changed unilaterally — these are exactly the kind of numbers `docs/MODDING.md`'s
`cards_minor`-by-`n`-override mechanism exists to let someone patch without
touching engine code. Re-run with `godot --headless --path godot -s
tests/balance_sim.gd -- <n>` (n = sample size, default 400) any time the
content changes.

## Where to look

- `autoload/Rules.gd` — the scoring engine, pure and stateless, the intended
  single source of truth per `HANDOFF.md`.
- `autoload/Run.gd` — the run/turn state machine.
- `autoload/Content.gd` + `autoload/ModLoader.gd` — content loading and the
  mod-pack merge logic; see `docs/MODDING.md`.
- `autoload/Workshop.gd` — the Steam Workshop stub; see `docs/STEAM_WORKSHOP.md`.
- `scenes/` — the playable UI.
- `tests/` — headless tests, runnable without a display:
  `godot --headless --path godot -s tests/test_rules.gd` (scoring engine),
  `tests/test_run.gd` (state machine, plays random full encounters),
  `tests/test_scenes.gd` (instantiates every screen against every game state).
