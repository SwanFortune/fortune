# Parlour — Godot port (vertical slice)

A Godot 4 (GDScript) port of `project/Parlour v23.dc.html`, the Claude Design
prototype in this repo's `project/` folder. Architected for mod support and
Steam Workshop distribution; see `docs/MODDING.md` and
`docs/STEAM_WORKSHOP.md`, and the in-game Mods screen (main menu → MODS) which
lists every loaded pack in load order, lets any of them but the base pack be
switched off, and shows load errors in full. Read `docs/PORTING_NOTES.md` first — it lists
exactly what's ported, what's a deliberate judgment call, and what's out of
scope for this pass.

## Running it

Open `godot/` as a project in the **Godot 4.7** editor and run it, or headless:

```
godot --headless --path godot          # boots to the main menu
```

Godot is a single portable executable — no installer, no dependencies.
Download the **standard** build (not .NET/mono; this is pure GDScript) from
<https://godotengine.org/download>, or:

```
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip
unzip godot.zip && chmod +x Godot_v4.7-stable_linux.x86_64
./Godot_v4.7-stable_linux.x86_64 --path godot
```

The suite is verified on **4.7**, which is what the project targets. Older
engines are no longer tested against — moving between versions is not cosmetic
here, see `docs/PORTING_NOTES.md`, "One engine version hid a bug for the whole
port".

## Tests

No display needed, and no setup step — a fresh `git clone` runs green as-is
(that is deliberate and checked; see `docs/PORTING_NOTES.md`, "The project did
not work from a fresh clone").

Run the whole suite with:

```
tests/run_all.sh                      # from the godot/ directory
GODOT=/path/to/godot tests/run_all.sh # if the binary is not at ~/bin/godot
```

It prints one line per file and ends in `ALL GREEN` or `NOT GREEN`, and it is
the only thing worth believing about whether the suite passes: it checks for
FAIL lines **and** for `ERROR`/`WARNING` output that is not on a named
allow-list. Grepping for FAIL alone is how ten freed-capture errors went
unnoticed for weeks (`docs/PORTING_NOTES.md`, "The lambda captures").

The files, if you want one at a time:

```
godot --headless --path godot -s tests/test_rules.gd          # scoring engine vs hand-traced cases
godot --headless --path godot -s tests/test_run.gd             # state machine, plays random full encounters
godot --headless --path godot -s tests/test_soak.gd            # plays complete runs, checks invariants throughout
godot --headless --path godot -s tests/test_scenes.gd          # every screen against every game state
godot --headless --path godot -s tests/test_resolutions.gd     # every screen at every offered window size
godot --headless --path godot -s tests/test_content_audit.gd   # fx cross-check (the AUDIT tab equivalent)
godot --headless --path godot -s tests/test_art.gd             # art manifest -> texture pipeline
godot --headless --path godot -s tests/test_library.gd         # Library edits -> mod pack -> live content
godot --headless --path godot -s tests/test_i18n.gd            # localization + fallback
godot --headless --path godot -s tests/test_save.gd            # save/resume round-trip
godot --headless --path godot -s tests/test_settings.gd        # key rebinding + setting hygiene
godot --headless --path godot -s tests/test_audio.gd           # sound registry + runtime loader
godot --headless --path godot -s tests/test_profile.gd         # cross-run stats + reader unlocks
godot --headless --path godot -s tests/test_dead_content.gd    # content fields nothing reads
godot --headless --path godot -s tests/test_minitel.gd         # the 3615 code channel + secret events
godot --headless --path godot -s tests/test_modloader.gd       # pack discovery, merge rules, every error path
godot --headless --path godot -s tests/test_boot.gd            # the game actually starts
godot --headless --path godot -s tests/test_icons.gd           # the vector icons rasterise and are complete
```

All eighteen should print `ALL PASS` / `SCENE SWEEP DONE`. Several of them
also print `ERROR` lines on purpose — they feed `get_var()` a corrupt save, make
`user://` unwritable, hand the mod loader broken JSON, and name content nothing
answers to, all to check those paths are refused rather than half-honoured. The
expected ones are enumerated in `tests/run_all.sh`, each next to the test that
causes it; anything not on that list is a real error, which is precisely what
the runner is for.

### The one the suite cannot do: the exported build

Everything above runs from source. What a player is handed is an export, where
resources are packed and `tests/*` is filtered out — a file the packer skipped
is missing only there. `tests/smoke_export.sh` builds the game and then PLAYS
it: real binary, real window, real keystrokes, menu to sign to gift to map to
reading, laying a card at the end.

```
tests/smoke_export.sh              # from godot/ — builds, then plays
tests/smoke_export.sh --no-build   # use the binary already in build/linux
```

It fails if the build is not still running at the end, if the console carries
anything but this container's known complaints, or if **any step leaves the
screen unchanged** — a key that reaches nothing is what a scene that failed to
load looks like. Needs `xvfb-run`, `xdotool` and ImageMagick, and it is not part
of `run_all.sh`: it builds a 74 MB binary and takes a minute.

One thing neither can check for you: Godot's own `ERROR` lines on the real
launch path. Nothing in `tests/` boots the project's main scene — they each
instantiate a screen directly — and an engine error is not visible to GDScript.
Run the game for a moment and read the output:

```
godot --path godot --quit-after 150     # should print no ERROR of its own
```

That is how a `remove_child()` error that had printed on every launch since the
first commit was finally noticed. On a machine with no sound card you will see
ALSA complaints and a V-Sync warning; those are the container, not the game.

There's also a balance report (not pass/fail — read it, see
`docs/PORTING_NOTES.md`'s "Balance: Taurus and Virgo"):

```
godot --headless --path godot -s tests/balance_sim.gd -- 6500              # the whole field
godot --headless --path godot -s tests/balance_sim.gd -- 1300 sign=taurus  # one cell, properly sampled
godot --headless --path godot -s tests/balance_sim.gd -- 6500 night=2 step=6
```

And a dev-only screenshot tool, for anyone doing further UI work without an
interactive display of their own (needs `xvfb-run`; real OpenGL software
rendering via Mesa/llvmpipe, not a mock):

```
xvfb-run -a godot --path godot -s tests/screenshot.gd -- read out.png
# scenario is one of: sign, gift, map, read, read_taurus, read_laid, marks,
#   win, reward, over, menu, menu_saved, mods, settings, library
```

## For the artist and the composer

Everything that needs drawing is catalogued in `data/base/art_manifest.json`
(generated from live content, so it can't go stale), and **`docs/ART_GUIDE.md`
is the brief** — sizes, safe zones, naming, tone, and the full checklist.
Art is optional at every point: anything not yet delivered falls back to a
procedural placeholder, so the game always runs and improves piece by piece.

```
godot --headless --path godot -s tests/gen_art_manifest.gd   # refresh the checklist after content changes
```

Sound works the same way. The nine moments the game announces are listed in
`data/base/sounds.json` and **`docs/SOUND_GUIDE.md` is the brief**. What ships
today is placeholder audio, marked as such; drop a real file into
`assets/audio/` and set that entry's status to `"final"`. No import step and no
editor needed — both loaders read from bytes at runtime, which is also the only
way a mod's own art or audio can work at all.

```
python3 tests/gen_sounds.py                                  # regenerate the placeholders
```

## Settings

Main menu → SETTINGS. A category rail (GAMEPLAY, VIDEO, AUDIO, INTERFACE,
CONTROLS, LANGUAGE, CONTENT) with the chosen category's rows beside it;
everything takes effect the moment you change it, with no Apply button.

The rule the screen is built around is that **every setting does something
real**. That is as much about what is missing as what is there: no music
slider, because there is no music; no screen-shake toggle, because nothing
shakes; no gamepad-rumble row, because nothing rumbles. Those are the rows a
settings menu grows by imitation, and each would be a control that lies.
`tests/test_settings.gd` asserts the pairing in both directions — no setting
the screen cannot reach, no row naming a setting that does not exist.

Two of them are worth calling out because they are accessibility features
rather than preferences: **Text size** enlarges the words (and the cards with
them) without magnifying the layout, and **High contrast** swaps the whole
palette for a black-and-white one. The game's usual dim greys are a deliberate
look and a genuine problem for some people.

### Gamepad

Fully playable on a controller: the stick or D-pad moves the highlight, A
confirms, B goes back, X reads, and the shoulder buttons open your deck and
your marks. Rebinding in SETTINGS → CONTROLS changes the keyboard key only, so
it never costs you a pad button; each action's button is shown beside its key.

## The icons

Every element, sign and planet is drawn, not spelled. The path data is the
prototype's own line art (`EL_ART`, `SIGN_ART`, `PLANET_ART` in
`Parlour v23.dc.html`), carried over verbatim into `data/base/icons.json` and
rasterised at runtime by `autoload/Icons.gd` — at the exact pixel size and
colour each place needs, so they stay crisp under `text_scale` and `ui_scale`
and need no import step. A mod ships its own icons the same way it ships art.

The badge around them is the source's geometry too: the icon at 68% of its box,
a 30% corner radius, the ground at 24% of the icon's colour and a hairline
border at 52%.

## Learning the game

Main menu → HOW TO PLAY, and the RULES chip on any in-run screen (the same
text, as an overlay, so you never have to leave a reading to look something
up). CREDITS and the version live behind it.

It is assembled from live data rather than written out again: the glossary is
the same authored text the card tooltips use, the elements come from
`elements.json`, the element wheel is drawn from `Content.ring` — the array the
scoring engine actually walks — and the control list is read off the InputMap,
so a rebind shows up there at once. `tests/test_scenes.gd` checks the wheel it
draws against what `Rules.link_of()` really does; a rules screen that explains
the game wrongly is worse than none.

## The Minitel

Main menu → MINITEL. Dial **3615**, four letters, ENVOI. It is the game's
secret-code channel and the only meta-progression that is not a run — a code
can arm an event the map otherwise never offers, bump a profile stat, or gate a
reader behind having dialled it. Codes are data, so a mod ships its own.

This is the one feature here that is an addition rather than a port. Two
demonstrator codes ship, marked as such, and are meant to be replaced. See
`docs/MINITEL.md` for the design and `docs/MODDING.md` for the schema.

## Building

Export presets for Linux, Windows and macOS are committed (`export_presets.cfg`
— see `godot/.gitignore` for why, since the usual Godot ignore file excludes
it). You need Godot's export templates for your version installed; the editor
offers to download them, or `godot --headless --export-release` will tell you
they are missing.

Use `build.sh`, which stamps the commit into the build before exporting it:

```
cd godot && ./build.sh            # Linux and Windows
cd godot && ./build.sh Linux      # one preset
```

A build then names itself on the main menu and in the credits — "0.2.0 · Godot
4.7.0 · 9117492" — which is the difference between a bug report you can act on
and one you cannot. Without it every build between two hand-bumped version
numbers is indistinguishable, and a stale binary looks exactly like a broken
one. The raw command still works and produces an unstamped build:

```
godot --headless --path godot --export-release "Linux" ../build/linux/parlour.x86_64
```

Builds land in `build/` and are gitignored. `tests/` is excluded from the
shipped pack; `mods_example/` is not, because the settings screen offers to
load it.

`docs/STEAM_RELEASE.md` covers what a Steam release needs on top of this —
what is already done, what needs an App ID or a signing identity, and which
files Steam Cloud should be pointed at.

The Linux build is verified: it exports, and it boots clean under a real
OpenGL driver. The Windows and macOS presets are written but have not been
built here — no templates for those targets were exercised, and neither was
codesigning, which is off on all three. The app icon is a placeholder on the
same terms as the rest of `assets/art/`.

## Languages

English plus a partially-filled French locale. Everything translatable lives
in one generated file per language (`data/base/locale/fr.json`); untranslated
strings fall back to English, so a half-finished locale is playable. See
`docs/LOCALIZATION.md`.

## Layout

```
autoload/     Settings, Content, ModLoader, Rules, Run, Nav, Workshop, Art, I18n, CardEdits, Profile, Save, Audio, Minitel — see their doc comments
data/base/    the base game's content, as JSON (also the mod-pack schema — see docs/MODDING.md)
assets/art/   where delivered art goes (see docs/ART_GUIDE.md); empty is fine
scenes/       the playable UI (incl. SettingsMenu, Library, and the in-run RunHeader)
mods_example/ a tiny working example mod, proving the pack format end to end
tests/        headless tests + dev tools (no editor/display required)
docs/         MODDING.md, STEAM_WORKSHOP.md, STEAM_RELEASE.md, PORTING_NOTES.md, ART_GUIDE.md, SOUND_GUIDE.md, LOCALIZATION.md, MINITEL.md
```
