# Modding Parlour

Every piece of game content — elements, signs, jobs, readers, cards, relics,
marks, sitters, the boss, events, the shop — is data, not code. The base game
ships as one *content pack* (`data/base/`) loaded through exactly the same
pipeline a mod uses. There is no special-cased "built-in content" code path;
`Content.gd` and `ModLoader.gd` don't know or care whether a given record came
from the base game or a mod.

## The Mods screen

Main menu → **MODS**. It is the front door to all of this and the first place
to look when a pack is not doing what you expect. It shows every pack
discovery found — **in load order**, which is the thing that decides who wins
a conflict — with its id, version, where it came from, its priority, how many
records it contributed and to which registries, and its path on disk. Any pack
except the base one can be switched off from there without deleting it; the
choice is stored in the `disabled_mods` setting, keyed by pack id, so it
survives the pack moving. **Load errors are printed on that screen in full**,
which is worth knowing because they used to exist only in the console.

The base pack cannot be switched off. There would be no game left to mod.

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
| `sounds` | object | (whole-object merge) | `sounds.json` |
| `minitel_codes` | object | (whole-object merge) | `minitel.json` |
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

### A rule and its flavour are two fields

A sign and a job each say two things: what they are LIKE, and what they DO.
They are separate fields, and the game shows them in different places.

```json
{ "k": "aries", "n": "ARIES", "el": "fire", "dn": "THE HEAD START",
  "rule": "The first card of every reading restores nothing.",
  "fl": "{S} {is} already ahead of you.",
  "fx": "mutefirst" }
```

`rule` (a sign) and `t` (a job) are the MECHANIC, printed on the map and on the
reading screen where a player can act on it. `fl` is the flavour, kept for the
hover. Write the mechanic so it stands alone — it is the half that has to be
read while deciding.

The original carried both in one string and cut it at the first full stop; the
port does not, because a rule with no full stop in the right place then loses
half of itself, and because a translator should get two strings rather than one
they must punctuate correctly. A pack that supplies only `rule` still works:
the whole string shows as the mechanic and the hover is empty.

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

### Sounds

`sounds` maps a game moment to an audio file. The moments are fixed (they are
`Audio.EVENTS` in `autoload/Audio.gd`); a pack repoints one by naming it:

```json
{ "sounds": { "card_lay": { "file": "res://mods/my_pack/audio/slap.ogg" } } }
```

A `res://` or `user://` path is taken as-is, so point at your own folder; a
bare filename resolves under the base game's `assets/audio/`. WAV, OGG and MP3
are read **from bytes at runtime**, not through Godot's import pipeline, which
is what makes a mod's audio work at all — the importer only ever sees `res://`
assets known at export time. The same is true of a mod's **art**. See
`docs/SOUND_GUIDE.md` for the spec and what each moment is for.

### Locking a reader

Every reader carries an `unlock` field. `null` — what all thirteen base
readers have — means always available. A condition makes the reader appear on
the sign-select screen greyed out, with what it wants written underneath:

```json
"unlock": { "stat": "runs_finished", "at_least": 2, "text": "Finish two runs" }
```

`stat` is one of the keys in `Profile.STATS` (`runs_finished`, `best_faith`,
`total_mended`, `readers_finished`, `codes_entered`), compared with `at_least`
for the numbers or `includes` for the lists — including `codes_entered`, which
is how a reader is hidden behind a Minitel code (see below). `text` is what the player is told and is a
translation key like any other UI string; leave it out and a plainer line is
derived from the condition.

An unknown stat or a condition with no comparison is **reported and treated as
unlocked** — a typo in a pack should not produce a reader nobody can select.

`mods_example/example_mod/readers.json` is a working example. No base reader
uses this; whether one should is the game author's call.

### Minitel codes

`minitel_codes` is the secret-code channel: the player dials 3615 and four
letters on the Minitel in the parlour. Your pack adds a code by adding a key —
four capital letters, no accents, since that is all the terminal accepts:

```json
{ "minitel_codes": { "LUNE": {
  "screen": ["SERVICE LUNE — METEO DU CIEL", "", "IL FERA NOIR."],
  "grants": { "stat": "total_mended", "add": 1 },
  "arms": "The night the moon was wrong",
  "repeatable": false
} } }
```

- `screen` — what the terminal prints, one string per line; `""` is a blank
  row. This is prose, so it is translatable, under the ids
  `minitel/LUNE/screen0`, `screen1`, … (one key per line).
- `grants` — `{stat, add}`, adding to a **numeric** `Profile.STATS` key.
- `arms` — the `title` of an event carrying `"secret": true`. A secret event is
  held out of the ordinary map pool entirely, so it can only ever be met by a
  player who dialled the code that arms it.
- `repeatable` — `false` (the default) makes it a one-shot: dialling again
  re-prints the screen and says so, without applying anything twice.

All three levers are optional. A code with none of them is still worth having:
simply dialling it is recorded in the `codes_entered` profile stat, so an
`unlock` condition of `{"stat": "codes_entered", "includes": "LUNE"}` gates a
reader behind it with no other machinery.

Naming a stat that does not exist, adding to a list stat, or arming an event
that is not a secret one is **reported** as a warning and does nothing — the
alternative, a code that quietly has no effect, is the failure mode this port
keeps trying to design out.

There is no general effect language here on purpose; see `docs/MINITEL.md` for
why, and for the two demonstrator codes the base game ships (which are meant to
be replaced, not built on).

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
rather than crashing the game. **Read them on the Mods screen** — they are also
pushed as warnings to the console, but needing a terminal to find out why your
mod does nothing is not a reasonable thing to ask of anyone.

A pack that reports an error is still loaded; only the record or file that
caused it is skipped. So "my mod half works" is a normal symptom of one bad
JSON file among several, and the Mods screen will name it.

That sentence is asserted rather than intended: `tests/test_modloader.gd`
builds a pack containing a missing file, an unparseable one, a JSON array where
an object belongs, an unrecognised top-level key **and** a good file, and
checks that all four are reported by name and the good one still loads. Run it
if you change anything in `ModLoader.gd`.

## Mods and a run in progress

Saved runs store cards by name and readers/signs by key, not as frozen copies,
so a pack you change or retune reaches a run already in progress rather than
being shut out of it (see `autoload/Save.gd`). The flip side: a card whose pack
you switch off **disappears from the deck of a saved run**, and is reported as
dropped when that run is loaded. Switching a pack off mid-run is therefore
safe, but not free — expect the deck to be shorter afterwards.
