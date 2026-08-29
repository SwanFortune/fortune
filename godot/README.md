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
godot --headless --path godot -s tests/test_rules.gd    # scoring engine vs hand-traced cases
godot --headless --path godot -s tests/test_run.gd       # state machine, plays random full encounters
godot --headless --path godot -s tests/test_scenes.gd    # every screen against every game state
```

All three should print `ALL PASS` / `SCENE SWEEP DONE` with no `ERROR` lines.

There's also a balance report (not pass/fail — read it, see `docs/PORTING_NOTES.md`'s "Balance: a first read"):

```
godot --headless --path godot -s tests/balance_sim.gd -- 600   # 600 sampled fights, ~1-2s
```

## Layout

```
autoload/     Content, ModLoader, Rules, Run, Nav, Workshop — see their doc comments
data/base/    the base game's content, as JSON (also the mod-pack schema — see docs/MODDING.md)
scenes/       the playable UI
mods_example/ a tiny working example mod, proving the pack format end to end
tests/        headless tests (no editor/display required)
docs/         MODDING.md, STEAM_WORKSHOP.md, PORTING_NOTES.md
```
