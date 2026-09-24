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

## Needs a person, not a test

**Nobody has heard the sound.** The exported build was mute for the whole of the
port — every cue resolved to a file that was not in the pack — and that was
found by listing the pack, not by listening. What is verified now is that every
registered cue RESOLVES: `Audio._say_what_does_not_resolve()` says so at load and
both `tests/run_all.sh` and `tests/smoke_export.sh` fail on the warning. Nothing
verifies that it sounds right. The crossfades, the relative volumes, whether
`ui_move` machine-guns on a keyboard player — all of that needs headphones. The
smoke test runs under a dummy audio driver and could not hear it if it tried.

**Nobody has played it.** Every test in here is structural: the screens build,
the keys reach something, the numbers agree with the specification, nothing
leaks. `tests/test_balance.gd` checks no reader is a trap and none is a free
pass. None of that says whether the difficulty curve rises at the right rate,
whether the third evening feels like the third evening, or whether the events
read the way they were written. That is a person playing an evening and
noticing, and it is the one thing none of this can stand in for.

## An agent can pick these up

**Two parts of the run flow are not differential-tested.**
`tests/test_against_the_prototype.gd` now plays whole fights through the
prototype's `startFight()`/`beginTurn()`/`_lay()`/`resolveRead()`/`win()`/
`lose()`. Not reached yet, and each for a reason worth knowing before starting:

- **`advance()`/`makeOptions()`**: the port plans a whole night at once
  (`Run.make_plan()`) where the prototype rolls each knock, deliberately. What
  can still be compared is the shape — which hours can be elite, when the shop
  appears, the boss on the last knock of the last night.
- **`endRun()`**: the port's endings come from `endings.json` rather than four
  score tiers, deliberately, so only the run's totals are comparable.

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
report — though nothing on screen tells them where it is.
