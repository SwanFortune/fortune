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
not work from a fresh clone"):

```
godot --headless --path godot -s tests/test_rules.gd          # scoring engine vs hand-traced cases
godot --headless --path godot -s tests/test_run.gd             # state machine, plays random full encounters
godot --headless --path godot -s tests/test_soak.gd            # plays complete runs, checks invariants throughout
godot --headless --path godot -s tests/test_scenes.gd          # every screen against every game state
godot --headless --path godot -s tests/test_content_audit.gd   # fx cross-check (the AUDIT tab equivalent)
godot --headless --path godot -s tests/test_art.gd             # art manifest -> texture pipeline
godot --headless --path godot -s tests/test_library.gd         # Library edits -> mod pack -> live content
godot --headless --path godot -s tests/test_i18n.gd            # localization + fallback
godot --headless --path godot -s tests/test_save.gd            # save/resume round-trip
godot --headless --path godot -s tests/test_settings.gd        # key rebinding + setting hygiene
godot --headless --path godot -s tests/test_audio.gd           # sound registry + runtime loader
godot --headless --path godot -s tests/test_profile.gd         # cross-run stats + reader unlocks
godot --headless --path godot -s tests/test_dead_content.gd    # content fields nothing reads
```

All thirteen should print `ALL PASS` / `SCENE SWEEP DONE`. Two of them print one
`ERROR` line each, immediately after a `--- the next ERROR line is expected`
marker: they feed `get_var()` a deliberately corrupt save to check it is
refused rather than half-restored. Any `ERROR` line *without* that marker
above it is a real one.

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

## The Minitel

Main menu → MINITEL. Dial **3615**, four letters, ENVOI. It is the game's
secret-code channel and the only meta-progression that is not a run — a code
can arm an event the map otherwise never offers, bump a profile stat, or gate a
reader behind having dialled it. Codes are data, so a mod ships its own.

This is the one feature here that is an addition rather than a port. Two
demonstrator codes ship, marked as such, and are meant to be replaced. See
`docs/MINITEL.md` for the design and `docs/MODDING.md` for the schema.

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
docs/         MODDING.md, STEAM_WORKSHOP.md, PORTING_NOTES.md, ART_GUIDE.md, SOUND_GUIDE.md, LOCALIZATION.md, MINITEL.md
```
