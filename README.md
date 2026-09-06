# Parlour

A fortune-teller's card game set in a French village, in Godot 4.7.

Someone knocks. They have a job, a sign, and something they will not say. You
lay cards left to right and read them out as one sentence — and the ORDER is the
whole game, because most cards pay attention to what came before them. Eight
knocks a night, three nights, and the last one on the third night is the mayor.

```
godot/          the game — open this in Godot 4.7, or see godot/README.md
project/        the original browser prototype, Parlour v23.dc.html
chats/          the design conversations the prototype came out of
build/          exported binaries (gitignored; ./godot/build.sh makes them)
```

## Running it

Everything lives under `godot/`. From a fresh clone, with no editor pass and no
import step:

```
cd godot
tests/run_all.sh          # the whole suite, about ninety seconds
```

`godot/README.md` is the real front door: how to get the engine, how to run one
test at a time, and what each one is for. The docs beside it go deeper:

| | |
|---|---|
| `godot/docs/PORTING_NOTES.md` | every judgement call in the port, and why |
| `godot/docs/MODDING.md` | the pack format, and how content is merged |
| `godot/docs/ART_GUIDE.md` | the manifest an illustrator works from |
| `godot/docs/SOUND_GUIDE.md` | the score and room-tone spec, and CC0 sources |
| `godot/docs/LOCALIZATION.md` | the locale scheme and how to add a language |
| `godot/docs/RELEASING.md` | the release checklist, in order |
| `godot/docs/STEAM_RELEASE.md` | what shipping still needs |

`CLAUDE.md` holds the working conventions — the traps this codebase has already
fallen into, and the method that keeps catching them. Read it before changing
anything here.

## Where this came from

The game began as a single self-contained browser prototype,
`project/Parlour v23.dc.html`: the design, the writing, the cards and the
numbers are all its author's. `chats/` holds the conversations it grew out of.

Everything under `godot/` is a port of that file. The rules engine is a direct
translation of its `simulate()`, and **where the two disagree, the prototype is
right** — see `godot/docs/PORTING_NOTES.md`, which records each place they had
to differ and what was decided.

The prototype is kept because it is still the specification. It is not built,
not run, and not shipped.
