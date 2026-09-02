# The Minitel

A beige terminal on the sideboard. You dial **3615**, type **four letters**,
press **ENVOI**, and the tube answers. It is the game's secret-code channel and
its only meta-progression surface that is not a run.

Not in the source prototype — added during the port. See
`docs/PORTING_NOTES.md` for the entry.

## For a player

Main menu → MINITEL. Type `3615` in the left field, four letters in the right,
press ENVOI (or Enter). The screen prints what the service has to say. Codes
you have reached are listed underneath; there is no counter of ones you have
not, deliberately — a "3 of 8" line turns a secret into a chore, and once a mod
can add its own there is no honest total to print anyway.

Codes survive between runs. They live in the profile, not the save file, so
starting a new run does not spend them.

## For an author or modder

The whole feature is **machinery with almost no content**. `autoload/Minitel.gd`
validates, records and applies; the codes themselves are data, in
`data/base/minitel.json`, and the two that ship are marked DEMONSTRATOR in
their own `_note` fields. They exist so the tests exercise the three levers on
real records rather than on fixtures. Replace them.

The schema and the three levers are documented in `docs/MODDING.md` under
**Minitel codes**. In short:

| lever | what it does |
|---|---|
| `grants` | adds to a numeric `Profile.STATS` key |
| `arms` | makes a `"secret": true` event eligible on the map |
| (entering it) | recorded in `codes_entered`, which any `unlock` can test |

### Why only three

The obvious next step is an effect language — "give the player 2 relics and
start night 2 with a mark". It is not here, and not because it would be hard to
write: it would be impossible to *check*. Every other content registry in this
port has a headless test that says a record is well-formed and does what it
claims; a general effect DSL has no such shape, and the failure this project
keeps rediscovering (see `docs/PORTING_NOTES.md`) is content that loads clean
and silently does nothing.

Three named levers can each be validated by name. A code that arms an event
nobody wrote, or adds to a stat that does not exist, gets a warning on the
console and on the Mods screen's load messages — it does not fail quietly.

If a fourth lever is genuinely wanted, add it the same way: a named field, a
check that its target resolves, and a line in `tests/test_minitel.gd`.

### Secret events

`arms` is the interesting one, and it is the only lever that needs anything
outside this file. An event in `events.json` carrying `"secret": true` is
excluded from `Run.ordinary_events()`, which is what the map draws from — so
it is unreachable by any route except a code that arms it. Once armed it is
injected into the map's options at a low rate, so it arrives as a night that
happens to go strangely rather than as a reward screen.

`tests/test_minitel.gd` asserts both halves: that no secret event is in the
ordinary pool, and that an armed one does eventually turn up. The first of
those is the load-bearing one — a bug there would show the player the payoff
for a code they never found.

## The terminal speaks French

The lines the machine itself prints (`SAY_*` in `autoload/Minitel.gd`) are the
only strings in the game not run through `I18n`. A Minitel is not part of the
interface; it is a French object in the room, and it printed unaccented
capitals because its character set could do nothing else. Translating
`ANNUAIRE ELECTRONIQUE` would not be translating anything.

The chrome *around* the machine — the menu entry, the list of services reached,
the flavour line under the title — is ordinary UI and is translated normally.
A code's own `screen` text is content, and is translatable per line: a pack set
somewhere other than 1980s France will want its own terminal.

## Files

| file | what |
|---|---|
| `autoload/Minitel.gd` | validation, persistence, the three levers |
| `data/base/minitel.json` | the code registry (two demonstrators) |
| `scenes/MinitelScreen.gd` | the terminal UI — a thin shell, no rules |
| `tests/test_minitel.gd` | ten checks, including the secret-event guard |
| `autoload/Profile.gd` | `codes_entered`, and `meets()` reading it |
| `autoload/Run.gd` | `ordinary_events()` and the armed-event injection |
