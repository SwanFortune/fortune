# Working in this repository

Conventions and traps. Everything here was learned by being caught out by it, so
none of it is style preference — each line stands in for a bug that shipped or
nearly did.

## Where things are

The game is `godot/`. `project/` is the browser prototype it was ported from and
is still the specification; `chats/` is the design conversation behind it.
Neither is built or run. Do not edit them.

## The method

**Measure the claim, do not repeat it.** "The ladder makes the game harder" and
"the locale is at 100%" were both false while everything said otherwise. If the
code makes a claim about itself, write the thing that checks it.

**Render the screen and look at it.** `godot/tests/screenshot.gd` boots any screen
under Xvfb and saves a PNG:

```
xvfb-run -a godot --path godot -s tests/screenshot.gd -- <screen> out.png [settle] [locale] [WxH]
```

This is how the canvas bug, the untranslated half of the game, and every layout
problem were found. None of them failed a test that only asked whether the
screen built.

**Verify every guard RED.** Stub the fix, watch the test fail, restore. A test
that has never failed is a test that proves nothing — this repository has
shipped at least three that passed for the wrong reason, including one whose
needle matched its own definition and one that read the buggy ordering back out
of the file and agreed with it.

**When a checklist is maintained by hand, it will fall behind.** The README's
test list, the locale's UI strings, the art manifest: each one quietly stopped
listing things, and each fix was to DERIVE the list and add a check that the
derivation and the source agree. Prefer asking the data over typing a list.

**Do not `git checkout` a file to undo a stub.** It reverts real work too. Copy
to `/tmp` first and copy back.

## Godot traps, all of them load-bearing

**Autoload names do not resolve in `godot -s` scripts.** Use
`root.get_node("Content")`, not `Content`. Bare names work in scenes only.

**Never `preload("res://scenes/…")` from an autoload.** It resolves at compile
time, before autoloads exist. Scene scripts load each other by PATH for the same
reason — a bare `class_name` does not resolve on a fresh clone.

**JSON has no integers.** Godot parses every number as a float, so `int(1.1)` is
1 and a "these keys add up" fold silently destroys a multiplier. Which keys are
amounts and which are settings must be LISTED, never inferred from type.

**A SpinBox cannot take focus.** Its `focus_mode` is NONE; the LineEdit inside
it is what a player is on. `grab_focus()` on the SpinBox warns and does nothing.

**A ScrollContainer does not centre its child**, and reads the horizontal size
flag only to decide whether to stretch it. It also ships with `follow_focus`
off, which strands every control below the fold — `UIKit.scroll()` turns it on.

**Rebuilding a panel from inside a control's own signal frees that control.**
Refresh what READS the state and leave the controls alone; chasing the focus
afterwards does not work.

**A canvas is never smaller than the design size.** With `canvas_items` +
`expand`, a taller window buys canvas height and a wider one buys width, and
controls lay out in canvas units, not window pixels. A headless root is 64px
wide, so any geometry test must set `root.size` first or it measures nothing.

**`queue_free()` children are still children until the end of the frame.** Skip
`is_queued_for_deletion()` nodes when searching a subtree you have just rebuilt.

## Content and locale

Content is JSON under `godot/data/base/`, merged by `ModLoader`; the base pack
has the same shape as any mod. Adding a field means adding it to a pack, not to
a script.

The locale scheme is source-as-key for interface strings (`I18n.t("Left to
draw")` → `ui/Left to draw`) and slug ids for content (`sitter/mme-perrot/win`).
An EMPTY value means untranslated and falls back to English — which is why two
French pronoun keys are deliberately blank.

After adding any user-facing string, run
`godot --headless --path godot -s tests/gen_locale_template.gd` and translate
what it adds. `godot/tests/test_i18n.gd` fails if a literal in the source reaches
`I18n.t()` and is on no list. It scrapes the source, and it ignores comments —
a doc comment that mentions the idiom once added a real key to the template.

## Before committing

```
cd godot && tests/run_all.sh          # all twenty files
tests/smoke_export.sh                 # the EXPORTED binary, walked with real keys
```

Fifty-nine of the suite's runs are started with no seed on purpose — a different
evening every time is how the soak test and the scene sweep find things. The
runner prints the seed it played on, and `PARLOUR_SEED=<that>` replays the whole
series exactly; a failing file's complete output is kept in
`/tmp/parlour-failures`. Use both before assuming a failure was a fluke.

The suite fails on unexpected `ERROR`/`WARNING` lines as well as on `FAIL`,
because most interesting failures are engine errors, not assertions.
`godot/tests/smoke_export.sh` is the only thing that tests the artefact a player is
handed — resources packed, `godot/tests/` filtered out, the main scene actually
booted — and it is not part of `run_all.sh` because it builds a 74 MB binary.

CI runs both on every push, and builds all three platforms; see
`.github/workflows/tests.yml`. `godot/docs/RELEASING.md` is the order the
release steps go in — version bump, build, play, translate-check, tag.

## Commit messages

Say what was wrong and how it was found, not what was typed. A commit here is
the only place the reasoning survives, and several of them are the reason a bug
was not reintroduced. Do not put model names or version identifiers into
anything pushed to the repository.
