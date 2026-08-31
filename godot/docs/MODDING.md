# Modding Parlour

Every piece of game content — elements, signs, jobs, readers, cards, relics,
marks, sitters, the boss, events, the shop — is data, not code. The base game
ships as one *content pack* (`data/base/`) loaded through exactly the same
pipeline a mod uses. There is no special-cased "built-in content" code path;
`Content.gd` and `ModLoader.gd` don't know or care whether a given record came
from the base game or a mod.

## Where mods live

- `res://mods_example/<your_mod>/` — bundled example/dev mods, loaded only
  when the **Load example mods** setting is on (Settings → Content; stored as
  `load_example_mods`, read by `ModLoader` via `Content.reload()`).
  Useful for testing a mod during development of the game itself.
- `user://mods/<your_mod>/` — where a player's installed mods actually live.
  This directory is created automatically on first run. On desktop this
  resolves to a real folder (Windows: `%APPDATA%/Godot/app_userdata/Parlour/mods/`,
  Linux: `~/.local/share/godot/app_userdata/Parlour/mods/`, macOS:
  `~/Library/Application Support/Godot/app_userdata/Parlour/mods/`) — tell
  players to drop mod folders there.
- Steam Workshop items, once `Workshop.gd` is wired up to real Steamworks
  calls (see `docs/STEAM_WORKSHOP.md`) — `ModLoader` already treats whatever
  `Workshop.get_installed_item_paths()` returns as more pack directories, so
  no loader change is needed when that day comes.

## Anatomy of a pack

A pack is a folder containing:

```
your_mod/
  mod.json          -- manifest (required)
  cards_minor.json  -- one or more data files, named however you like
  ...
```

### `mod.json`

```json
{
  "id": "yourname.a_few_new_cards",
  "name": "A Few New Cards",
  "version": "1.0.0",
  "priority": 10,
  "description": "What this mod does, for a future in-game mod list.",
  "files": ["cards_minor.json"]
}
```

- `id` — a unique string. Convention: `yourname.short_slug`.
- `priority` — packs load in ascending priority order (default `0`); when two
  packs define the same record id, the higher-priority pack wins. The base
  game is always priority 0 and always loads first, regardless of what you set.
- `files` — every data file this pack contributes, relative to the pack folder.

### Data files

Each data file is a JSON object whose **top-level key names the registry it
feeds** — this is the entire addressing scheme, there's no filename
convention to memorize. The same key used in `data/base/*.json` is what you
use. For example, to add cards to the minor (signed/elemental) pool:

```json
{
  "cards_minor": [
    { "n": "Warm The Cup", "r": "common", "a": "", "sp": "warm the cup", "el": "water", "f": 3, "cost": 1, "draw": 1 }
  ]
}
```

See `mods_example/example_mod/` for a complete, working, minimal example —
one file, one new card, that loads automatically in dev builds.

The full list of registries (top-level keys) you can target, and the field
each record is merged by:

| Key | Shape | Merged by field | Example base file |
|---|---|---|---|
| `elements` | object | (whole-object merge) | `elements.json` |
| `ring`, `next`, `opp`, `neighbors` | array/object | (whole-value override) | `elements.json` |
| `fx` | object | (whole-object merge) | `fx.json` |
| `denial_shield` | object | (whole-value override) | `fx.json` |
| `denial_wall` | object | (whole-object merge) | `fx.json` |
| `pronouns` | object | (whole-object merge) | `pronouns.json` |
| `card_effects` | array | `k` | `card_effects.json` |
| `signs` | array | `k` | `signs.json` |
| `jobs` | object | (whole-object merge) | `jobs.json` |
| `readers` | array | `k` | `readers.json` |
| `cards_basics` | array | `n` | `cards_basics.json` |
| `cards_chroma` | array | `n` | `cards_chroma.json` |
| `cards_minor` | array | `n` | `cards_minor.json` |
| `cards_arcana` | array | `n` | `cards_arcana.json` |
| `relics` | array | `n` | `relics.json` |
| `marks` | array | `n` | `marks.json` |
| `elite_twists` | array | `tag` | `elite_twists.json` |
| `sitters` | array | `name` | `sitters.json` |
| `boss` | object | (whole-value override) | `boss.json` |
| `events` | array | `title` | `events.json` |
| `shop` | object | (whole-value override) | `shop.json` |

For an array registry merged "by field": if your record's id (e.g. a card's
`n`) matches an existing record, yours **replaces** it — this is how a
balance-patch mod overrides an existing card's numbers without touching the
base game's files. If the id is new, your record is appended. This is exactly
how `ModLoader._merge_array_by_key()` works; read it if you want the precise
mechanics.

### Two registries that are not in the original

`denial_wall` and `pronouns` were added during the port; see
`docs/PORTING_NOTES.md`.

`denial_wall` sits alongside `denial_shield` and governs the two signs whose
denial is a numeric wall. `denial_shield` says how much a wall thickens by each
reading; `denial_wall` says whether it is worn down in between, and how far it
may go:

```json
"denial_shield": { "shield": 3, "tide": 4 },
"denial_wall": {
  "shield": { "drain": true,  "cap": 2 },
  "tide":   { "drain": false, "cap": 0 }
}
```

- `drain` — whatever the wall absorbed this reading is gone from it, so it is a
  buffer to break through rather than a toll charged again every reading.
- `cap` — a multiple of the sitter's base denial the wall may never exceed;
  `0` means no ceiling.

Because it merges key-by-key, retuning one sign takes three lines and leaves
the other alone. An fx with **no** entry here behaves as
`{drain: false, cap: 0}`, which is the original's behaviour — so a new wall fx
needs an entry only if it wants these rules.

`pronouns` backs the `{S}`/`{es}`/`{o}` tokens that sign rules, job traits and
elite twists are written with, substituted from each sitter's `p` field at
display time. Add a key here and you can use it as a sitter's `p`. The
verb-agreement tokens (`is`/`es`/`has`/`do`/`goes`) exist so one sentence reads
correctly for both singular and plural pronouns — write `"{S} need{es} it"`,
not `"She needs it"`.

## Card and record schema

Every card record's fields map directly onto `Rules.gd`'s scoring engine —
see the field names used throughout `data/base/cards_minor.json` and the
`Rules.simulate()` doc comment in `autoload/Rules.gd` for what each one does
(`f`, `cost`, `el`, `energy`, `draw`, `coin`, `turn`, `opener`, `closer`,
`next`, `bonusFlat`, `solo`, `perLaid`, `perEl`/`perAmt`, `follows`/`bonus`,
`pierce`, `exhaust`, `bank`, `wild`, `any`, `chroma`, `neutral`). A card's
printed text is **generated** from those fields via `Rules.auto_text()` — you
don't write it by hand unless you set `"custom": true` and provide your own
`"text"`.

New `fx` keys referenced by a reader/relic/mark (`"on": "trait"`), a sign
(`"on": "sign"`), or a job (`"on": "job"`) need actual support added in
`Rules.gd` (`has()`, `simulate()`) to do anything — adding a new `fx.json`
entry alone only registers its *description text*, the same way the base
game's `fx.json` doesn't implement behavior, `Rules.simulate()` does. This is
the one place modding requires a code change, not just data — by design,
since the alternative (a full scripting sandbox for arbitrary effects) is a
much bigger commitment than this vertical slice takes on. See
`docs/PORTING_NOTES.md` for the current scope cut.

## Load-order errors

`ModLoader` collects problems (missing `mod.json`, a listed file that doesn't
exist, invalid JSON, an unrecognised top-level key) into `Content.load_errors`
rather than crashing the game — check that array (or the console, since
they're also pushed as warnings) if your mod doesn't seem to be doing anything.
