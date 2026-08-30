# Parlour — Godot port (vertical slice)

A Godot 4 (GDScript) port of `project/Parlour v23.dc.html`, the Claude Design
prototype in this repo's `project/` folder. Architected for mod support and
Steam Workshop distribution; see `docs/MODDING.md` and
`docs/STEAM_WORKSHOP.md`. Read `docs/PORTING_NOTES.md` first — it lists
exactly what's ported, what's a deliberate judgment call, and what's out of
scope for this pass.

## Running it

Open `godot/` as a project in the Godot 4.3 editor and run it, or headless:

```
godot --headless --path godot          # boots to the main menu
```

No Godot install locally? A portable Linux build is enough:

```
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
./Godot_v4.3-stable_linux.x86_64 --path godot
```

## Tests

No display needed:

```
godot --headless --path godot -s tests/test_rules.gd          # scoring engine vs hand-traced cases
godot --headless --path godot -s tests/test_run.gd             # state machine, plays random full encounters
godot --headless --path godot -s tests/test_scenes.gd          # every screen against every game state
godot --headless --path godot -s tests/test_content_audit.gd   # fx cross-check (the AUDIT tab equivalent)
godot --headless --path godot -s tests/test_art.gd             # art manifest -> texture pipeline
godot --headless --path godot -s tests/test_library.gd         # Library edits -> mod pack -> live content
godot --headless --path godot -s tests/test_i18n.gd            # localization + fallback
```

All seven should print `ALL PASS` / `SCENE SWEEP DONE` with no `ERROR` lines.

There's also a balance report (not pass/fail — read it, see `docs/PORTING_NOTES.md`'s "Balance: a first read"):

```
godot --headless --path godot -s tests/balance_sim.gd -- 600   # 600 sampled fights, ~1-2s
```

And a dev-only screenshot tool, for anyone doing further UI work without an
interactive display of their own (needs `xvfb-run`; real OpenGL software
rendering via Mesa/llvmpipe, not a mock):

```
xvfb-run -a godot --path godot -s tests/screenshot.gd -- read out.png
# scenario is one of: sign, gift, map, read, read_laid, win, reward, over
```

## For the artist

Everything that needs drawing is catalogued in `data/base/art_manifest.json`
(generated from live content, so it can't go stale), and **`docs/ART_GUIDE.md`
is the brief** — sizes, safe zones, naming, tone, and the full checklist.
Art is optional at every point: anything not yet delivered falls back to a
procedural placeholder, so the game always runs and improves piece by piece.

```
godot --headless --path godot -s tests/gen_art_manifest.gd   # refresh the checklist after content changes
```

## Languages

English plus a partially-filled French locale. Everything translatable lives
in one generated file per language (`data/base/locale/fr.json`); untranslated
strings fall back to English, so a half-finished locale is playable. See
`docs/LOCALIZATION.md`.

## Layout

```
autoload/     Settings, Content, ModLoader, Rules, Run, Nav, Workshop, Art, I18n, CardEdits — see their doc comments
data/base/    the base game's content, as JSON (also the mod-pack schema — see docs/MODDING.md)
assets/art/   where delivered art goes (see docs/ART_GUIDE.md); empty is fine
scenes/       the playable UI
mods_example/ a tiny working example mod, proving the pack format end to end
tests/        headless tests + dev tools (no editor/display required)
docs/         MODDING.md, STEAM_WORKSHOP.md, PORTING_NOTES.md, ART_GUIDE.md, LOCALIZATION.md
```
