# Shipping on Steam

What is already done, what has to be done by a person with a Steamworks
account, and what is deliberately not started. `docs/STEAM_WORKSHOP.md` covers
the Workshop side specifically; this is the release around it.

Nothing here is speculative about the code: every "already done" is something
you can check in the repository today, and every "not done" is not done.

## Already done

| | |
|---|---|
| Builds | `export_presets.cfg` for Linux, Windows and macOS; `docs`/README explain the command. Linux and Windows are verified to export. |
| Version | One source of truth (`autoload/Version.gd`), shown on the menu and in the credits, and asserted against the content pack's version by a test. |
| Settings | Video, audio, interface, controls, language — all persisted, all real. |
| Controller | Every action has a gamepad binding and the whole game is navigable from one. `tests/test_settings.gd` fails if that stops being true. |
| Saves | Atomic writes, a rolling backup, and a visible warning when the disk refuses. See "Saves and Steam Cloud" below. |
| Languages | English + French, with a generated checklist so a locale cannot drift. |
| Mod loading | Reads Workshop item paths through `Workshop.get_installed_item_paths()` — the only integration point needed for *loading* subscribed content. |

## What a person with a Steamworks account has to do

These need an account, an App ID, or a signing identity. None can be done from
the repository alone.

1. **Get an App ID.** Everything else keys off it. Put it in `steam_appid.txt`
   beside the executable for local development (Steam reads it when the game is
   launched outside the client); do NOT ship that file in the depot.
2. **Add GodotSteam.** The Steamworks SDK is not usable from GDScript directly;
   <https://godotsteam.com/> is the GDExtension everyone uses. Add it, then
   implement the five stubbed methods in `autoload/Workshop.gd`. The file says
   exactly which Steamworks calls each one wants.
3. **Initialise Steam at boot** and set `Workshop.is_available` from
   `Steam.isSteamRunning()`. The Mods screen already tells the player, in
   words, when it is not connected — that message stops being shown the moment
   this is true.
4. **Set up depots and launch options** per platform. The builds are single
   self-contained executables (`embed_pck=true`), so a depot is the executable
   and nothing else.
5. **Code-sign.** Off in all three presets. macOS notarisation in particular is
   not optional for a downloadable build, and neither signing nor notarisation
   has been exercised here.
6. **Store page assets.** Capsules, screenshots, trailer. Not code; not in this
   repository.
7. **Age rating and content survey.** The game is about grief, and someone will
   need to answer for that honestly on the form.

## Saves and Steam Cloud

Godot's `user://` maps to a per-platform directory. For Steam Auto-Cloud, the
paths to register are:

| Platform | Root | Pattern |
|---|---|---|
| Windows | `%APPDATA%` | `Godot/app_userdata/Parlour` |
| macOS | `~/Library/Application Support` | `Godot/app_userdata/Parlour` |
| Linux | `~/.local/share` | `godot/app_userdata/Parlour` |

The files worth syncing, and what each one is:

- `save.dat` — the run in progress.
- `save.dat.bak` — the previous good save. **Sync it too.** It is the whole
  point of keeping one; syncing only the current file means a machine that
  syncs mid-write has no fallback.
- `profile.cfg` — cross-run stats and unlocks, including dialled Minitel codes.
- `settings.cfg` — settings, including keybinds.
- `mods/` — **do not sync.** These are the player's own files and can be large.

`save.dat.tmp` should not be synced either; it exists for at most a few
milliseconds during a write (see below) and a synced copy of it is meaningless.

**Auto-Cloud versus the API.** Auto-Cloud is a file-pattern sync and needs no
code, which is why the paths are written out above. It has a known weakness:
two machines editing the same run offline produce a conflict Steam resolves by
timestamp, and the loser is simply gone. The Cloud API (`ISteamRemoteStorage`)
would let the game notice and ask. That is a real decision, not an oversight —
Auto-Cloud is right until enough people play on two machines to be bitten.

## What the saves already do, and why

Three practices, each in response to a specific way a save is lost:

**Atomic writes.** The run is written to `save.dat.tmp` and then RENAMED over
`save.dat`. Writing in place means the save is, for the length of the write, a
half-written file — and this game writes several times a minute, so that window
gets sampled often. A rename within one directory is atomic on every filesystem
this ships to, so the file on disk is only ever the old save or the new one,
never half of either.

**A rolling backup.** The previous save becomes `save.dat.bak` before the new
one takes its place. If the current save cannot be read, the backup is used and
the player is told they may have lost a step — refusing a corrupt save while a
good one from ten seconds earlier sat beside it unused would be a worse answer.
A VERSION MISMATCH does not fall back: a save from a newer build means its
backup is from that build too, and trying it would only fail twice.

**Saying so when it fails.** If `user://` is read-only or the disk is full, the
run header carries a red line for as long as writes keep failing, and the main
menu says that settings and unlocks are not persisting either. This was silent
until recently, which is the worst version of it: three nights played, game
closed, run gone, no explanation ever.

`profile.cfg` and `settings.cfg` are written the same atomic way.

## Achievements

Not started, and worth being deliberate about. `autoload/Profile.gd` already
records `runs_finished`, `best_faith`, `total_mended`, `readers_finished` and
`codes_entered` — the natural source for a first set — and unlocking a Steam
achievement would be one call at the same place a stat is recorded.

What is missing is the achievement LIST, which is a design decision about what
the game wants to celebrate, not a porting one. Inventing it here would be
inventing content.

## Steam Input

The game declares its own actions with both keyboard and gamepad bindings, so
Steam Input's default desktop configuration works without a controller config
being published. Publishing one would let a player remap in Steam's own UI;
the in-game rebinding covers the keyboard half already, deliberately leaving
gamepad bindings alone so a rebind never costs someone their controller button.

## The honest state of it

The game builds, runs, saves safely, and is playable start to finish on a
keyboard or a controller in two languages. What stands between it and a store
page is not engineering: it is an App ID, art, sound, and more content —
three ordinary events for a sixteen-knock run is the shortage a player would
notice first. See `docs/PORTING_NOTES.md` for the running list.
