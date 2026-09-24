# What is still open

Everything else in this repository describes what was done and why. This is the
list of what has NOT been, kept here because it was living in a conversation,
and a conversation is not somewhere work can live.

Each item says how to check whether it is still open, so nobody has to trust
this file. Delete an item when it is done — a list that only grows stops being
read.

## Needs a decision that is not a code decision

**There is no licence.** `ls LICENSE` at the repository root finds nothing. The
credits screen carefully credits Godot (MIT) and the bundled font (Apache 2.0)
and the project itself states no terms at all. This matters twice: once for
whoever ships or forks the game, and once for mods — `docs/MODDING.md` spends
three pages encouraging people to build on the base content, and nothing tells
them what they may do with it. It is one file. The terms are the author's call.

**Is a `basic` card meant to be offered?** The prototype's rarity table says
`basic: 0`, and its `weighted()` reads `RARW[c.r] || 1` — so the 0 is falsy and
a basic card weighs 1, like a rare. The port now does the same, because the
prototype is the specification. No base card can reach it (every offerable card
is common, uncommon or rare); a mod's can. If 0 was meant as "never offered",
that is a one-line change in `Run.rarity_weight()` and the differential will
then report it, deliberately.

**Three changes to the author's words that nobody wrote down.** Comparing the
port's `data/base/` against the prototype's own tables, record by record, gives
88 differences; almost all are the balance pass (`docs/PORTING_NOTES.md`,
"Thirteen readers" and "Balance: Taurus and Virgo"), card text that
`autoText()` now generates, and sign/job text split into flavour and rule.
Three are none of those:
- five relic names lost their typographic apostrophe (`The Widow’s Wedding
  Band` is `The Widow's Wedding Band`), and so did two reader lines and a
  sitter's `win` line;
- Cancer's line lost its italics: `You are {i}extra{/i} careful`;
- Scorpio's line lost the line break in the middle of it.
The names are also save and locale keys, which is why this is a question and
not a fix.

**The main menu tells players this is a "Godot vertical-slice port".** It is
now translated (it went out in English to French players), but the words are
a developer's, on the first screen anyone sees. Whether the subtitle should be
the prototype's "a fortune-teller's ledger, in card form" alone is the
author's call. `grep -n "vertical-slice" godot/scenes/MainMenu.gd`.

**Should the work view reach a shipped build at all?** Today a build handed to
a player opens the workshop when 3615 ATEL is dialled on the Minitel
(`autoload/Mode.gd`). That is handy for testers and harmless to a player, but a
release could drop the code from `minitel.json` instead. Keep it or drop it
before the first public build.

## Needs a person, not a test

**Nobody has heard the sound.** The exported build was mute for the whole of the
port — every cue resolved to a file that was not in the pack — and that was
found by listing the pack, not by listening. What is verified now is that every
registered cue RESOLVES: `Audio._say_what_does_not_resolve()` says so at load and
both `tests/run_all.sh` and `tests/smoke_export.sh` fail on the warning. Nothing
verifies that it sounds right. The crossfades, the relative volumes, whether
`ui_move` machine-guns on a keyboard player — all of that needs headphones. The
smoke test runs under a dummy audio driver and could not hear it if it tried.

**Nobody has felt the haptics, and the particles are dots.** The feel system
(`autoload/Feel.gd`, `data/base/feel.json`, `docs/FEEL_GUIDE.md`) is built
and tested, and every preset in it is a placeholder: particles with no drawing
(a procedural soft dot), sizes and timings set by eye, rumble patterns written
by numbers and never held. `tests/test_feel.gd` proves the motions end where
they start, that the settings are obeyed, and that nothing named is missing.
It cannot say whether a thud feels like a thud. SETTINGS → CONTROLS → TRY IT
is the place to start, and CREDITS → STUDIO is where the rest is tuned.

**Nobody has watched a visit with the room remembering.** Eight cards turn
into things on the table (`data/base/room.json`), each drawn in code, at spots
chosen by screenshot so they miss the text. Whether a table with the cloth, the
cup, the coins and the ash on it still reads as a table — and which other cards
deserve a thing — is a person's call, and the studio's ROOM pane is where to
make it.

**A mod cannot ship art.** `docs/MODDING.md` says a mod's art is read from
bytes like its audio, and `tests/test_art.gd` says "a mod that wants art ships
its own manifest" — but `Art.gd` reads exactly one manifest,
`data/base/art_manifest.json`, and no pack's. A drawing in a mod has no entry
to be found by. Check: `grep -n MANIFEST_PATH godot/autoload/Art.gd`. The fix is
a `art` registry merged by ModLoader like `sounds`, with the base manifest as
its base pack's entry; the studio's ART pane would then show a mod's drawings
too.

**Nobody has played it.** Every test in here is structural: the screens build,
the keys reach something, the numbers agree with the specification, nothing
leaks. `tests/test_balance.gd` checks no reader is a trap and none is a free
pass. None of that says whether the difficulty curve rises at the right rate,
whether the third evening feels like the third evening, or whether the events
read the way they were written. That is a person playing an evening and
noticing, and it is the one thing none of this can stand in for.

## An agent can pick these up

**The end of a run is not differential-tested.**
`tests/test_against_the_prototype.gd` plays whole fights through the
prototype's `startFight()`/`beginTurn()`/`_lay()`/`resolveRead()`/`win()`/
`lose()`, and compares the shape of every night against `makeOptions()` on the
port's own dice. Not reached: `endRun()`, whose four score tiers the port
replaced with `endings.json` on purpose, so only the run's totals are
comparable; and WHO fills an hour (the shuffle and the picks), which each engine
rolls on its own dice.

The bridge's `METHODS`, `PURE_METHODS`, `FUNCTIONS` and `FLOW_METHODS` list what
is checked.

## Deliberately not done, so nobody redoes the analysis

**`UIKit.gd` is 1755 lines and is staying that way for now.** Length alone is not
a bug. Nothing fails because of it, no test is hard to write because of it, and
splitting a file that every scene loads is a large change with no measured
problem behind it. Do it when something actually hurts, and say what hurt.

**macOS and Windows are built in CI but never run.** `tests/smoke_export.sh`
drives a real window with real keystrokes and needs a Linux runner to do it, so
the other two platforms are only proved to EXPORT. This is already written down
in `.github/workflows/tests.yml` beside the step that does it; it is here so it
is not rediscovered as if it were news.

## Checked, and not missing

Recorded so the next sweep does not spend an afternoon on them again: the
gamepad is mapped (five joypad entries in `project.godot`), the main menu has a
QUIT, the element glyphs (△▽◇□) carry the distinction colour alone would not,
text scale and high contrast are real settings that reach a built screen, and
the game writes a log to `user://logs/` that a player could send with a bug
report — and the credits now say where, beside the version
(`tests/test_scenes.gd` checks the folder they name holds one).

**Rebuilding the reading screen on every action is not a performance problem.**
Measured, so the next sweep does not propose keeping the screen alive between
actions: building it costs 9 ms of CPU (under a frame at 60 fps). A full frame
measures around 70 ms under this container's software renderer, but 45 ms of
that is the GPU filling the room's translucent light and vignette — the room's
own drawing code is 0.4 ms of CPU — and a real graphics card does not pay it.
