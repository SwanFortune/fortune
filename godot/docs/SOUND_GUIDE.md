# Sound — what the game asks for, and how to deliver it

The companion to `docs/ART_GUIDE.md`, and built the same way: the game runs
with **no audio at all**, every sound is looked up by name and falls back to
silence when it is missing, and it improves one file at a time as real work
lands. Nothing here ever needs a code change.

## The short version

1. Look at `godot/data/base/sounds.json`. Every key is a moment in the game.
2. Put your file at `godot/assets/audio/<key>.wav` (or `.ogg`, or `.mp3`).
3. Set that entry's `"status"` to `"final"`.
4. Run the tests. `tests/test_audio.gd` will tell you if it does not load.

You do not need to open the Godot editor and you do not need to import
anything — the loader reads audio files from bytes at runtime, precisely so
that dropping a file in a folder is all it takes. (Same for a mod's audio in
`user://mods/`, which the editor's import pipeline can never reach.)

## Everything the game announces

Nine moments, listed in `Audio.EVENTS` in `godot/autoload/Audio.gd`, which is
the authority — `sounds.json` must cover exactly those keys and no others, and
`tests/test_audio.gd` fails if the two lists drift apart in either direction.

| key | when it fires | notes |
| --- | --- | --- |
| `card_draw` | a card arriving in hand | **fires once per card**, five times for a normal hand, staggered to match the deal animation. Must survive being heard several times a second. |
| `card_lay` | a card leaving the hand for the table | the most-heard sound in the game by a wide margin |
| `card_discard` | the hand being swept at end of reading | one per reading, not one per card |
| `reading_resolve` | a reading being read | the one moment that should feel like an event |
| `sitter_win` | they go home whole | |
| `sitter_lose` | they leave as they came | should not sound like a failure buzzer; they are disappointed, not buzzed |
| `coin` | centimes changing hands | only on a purchase that actually costs something |
| `ui_move` | keyboard/gamepad focus moving | fires on **every** arrow key press — the quietest thing in the game |
| `ui_press` | a button or row being activated | |

## Spec

- **Format**: WAV (uncompressed PCM, 8- or 16-bit, mono or stereo), OGG
  Vorbis, or MP3. OGG is the sensible default for anything longer than a
  second; WAV is fine and lowest-friction for the short ones.
- **Sample rate**: 44.1 kHz. Anything is read, but mixing rates is a good way
  to end up with one sound that sounds subtly wrong.
- **Mono** for everything in the table above. These are diegetic objects on a
  table, not a score; stereo width on a card flip mostly reads as a mistake.
- **Length**: the card and UI sounds want to be under ~250 ms. `sitter_win`
  and `sitter_lose` can run to a second and a half.
- **Headroom**: normalize to about −3 dBFS and let `gain_db` in the registry do
  the final trim. Do not master these loud; `ui_move` in particular sits at
  −18 dB and is still audible.
- **No silence at the head.** A leading gap reads as input lag.

## The registry

`data/base/sounds.json`, one entry per event:

```json
"card_lay": { "status": "final", "gain_db": -6.0, "pitch_jitter": 0.05 }
```

- `status` — `placeholder` or `final`. Only bookkeeping; it does not change
  playback. It is how anyone can see at a glance what is still stand-in.
- `file` — optional. Defaults to `assets/audio/<key>.wav`. A bare filename
  resolves under `assets/audio/`; a `res://` or `user://` path is taken as-is,
  which is how a mod points at its own folder.
- `gain_db` — trims a sound that lands too loud without re-rendering it.
- `pitch_jitter` — varies pitch by ± that fraction on each play. It exists for
  `card_draw`: five identical clicks in a row sound like a machine gun, and
  0.07 is enough to stop that. Leave it at 0 for anything melodic.

## About the sounds that are in there now

They are **placeholders and they are meant to be replaced.** They were
synthesized by `tests/gen_sounds.py` — filtered noise for the paper sounds,
plain struck tones for the rest — for one reason: `master_volume` and `muted`
in Settings drive the real audio bus, and before this they drove it with
nothing on it. They are deliberately plain rather than trying to be good.

Every one of them is marked `"status": "placeholder"`, so the list of what is
still stand-in is the list of entries with that status.
