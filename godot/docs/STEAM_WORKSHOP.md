# Steam Workshop integration — status and next steps

**Current status: architected for, not wired up.** `autoload/Workshop.gd`
defines the interface the rest of the codebase depends on
(`get_installed_item_paths()`, called from `ModLoader.discover_pack_dirs()`)
and returns "nothing installed" until real Steamworks access exists. This
document is the punch list for whoever does that wiring.

## Why it's stubbed, not implemented

This port doesn't have a Steam App ID — it isn't a registered Steam product.
Real Workshop access requires one (Steamworks won't initialize without it),
so there is nothing to test *real* Workshop calls against yet. Building a full
integration against no App ID would mean writing untestable code, which is
worse than writing an honest, clearly-marked stub with the real interface
already in the right shape.

## What "real" requires, in order

1. **Register a Steam App ID.** Nothing below works without one.
2. **Add [GodotSteam](https://godotsteam.com/)** as a GDExtension to this
   project (`godot/addons/godotsteam/` or similar, per its install docs).
   GodotSteam is the de facto standard Steamworks binding for Godot 4.
3. **Add `steam_appid.txt`** at the project root containing the App ID (used
   for local testing before the game is actually on Steam).
4. **Call `Steam.steamInit()`** at boot — earliest reasonable point is
   `Workshop._try_init_steamworks()`, which currently just sets
   `is_available = false` unconditionally. Replace that body with the real
   init call, check `Steam.isSteamRunning()`, and set `is_available` from the result.
5. **Implement `get_installed_item_paths()`** for real:
   - `Steam.getSubscribedItems()` to list subscribed Workshop item ids.
   - For each, `Steam.downloadItem(id, true)` if not already installed.
   - GodotSteam emits a `download_item_result` signal per completed download —
     connect to it (in `_ready()`, alongside the init call) and use it to
     maintain `_installed_item_ids` incrementally, rather than polling.
   - `Steam.getItemInstallInfo(id)` returns the on-disk folder for an
     installed item — that folder **is** the mod pack directory ModLoader
     wants, provided the item's uploader put a `mod.json` at its root (a
     Workshop-item-authoring requirement to document for creators, not a code
     change here).
6. **A publish flow.** Nothing today lets a player publish a pack *to*
   Workshop — the only distribution channel right now is "zip your
   `user://mods/<name>/` folder and share it, the recipient unzips it into
   their own `user://mods/`." A real publish flow means either:
   - An in-game "Upload to Workshop" button calling
     `Steam.createItem()` / `Steam.setItemContent()` / `Steam.submitItemUpdate()`
     against a pack folder, or
   - Pointing creators at Steamworks' own Workshop upload tooling
     (`steamcmd` / the Steamworks web UI) with documentation on the pack
     folder layout (which `docs/MODDING.md` already covers).
   Neither is started. `Workshop.publish_pack()` exists as a named stub for
   the former so the call site is obvious once someone picks this up.

## What the player sees today

The Mods screen (main menu → MODS) has a Steam Workshop section. With
`Workshop.is_available` false — which is always, in this build — it says so in
a sentence and points here, rather than showing a subscribe or publish button
that would do nothing. When the stub is replaced with real Steamworks calls,
that section grows a REFRESH SUBSCRIPTIONS button and subscribed packs appear
in the same list as every other pack, labelled "Steam Workshop" as their
source. That is already written and is behind the `is_available` check.

## What does *not* need to change

`ModLoader.gd` already calls `Workshop.get_installed_item_paths()` and
treats every path it returns exactly like any other pack directory (see
`ModLoader.discover_pack_dirs()`). Once step 5 above returns real paths
instead of an empty array, Workshop content loads with zero changes to the
merge/loading logic — that was the point of stubbing the interface first.

## Walking the Workshop path without Steam

The paragraph above was a claim, and for a long time it was only a claim. The
call to `Workshop.get_installed_item_paths()` had returned an empty array since
the day it was written, so the lines in `discover_pack_dirs()` that turn a
Workshop item into a pack **had never run with a path in them.** Every test of
them passed, none of them had ever failed, and the first thing to exercise that
code would have been a player's machine on the day GodotSteam landed.

So there is a stand-in. Point `PARLOUR_WORKSHOP_DIRS` at one or more directories
and each is treated exactly as a subscribed item's install folder:

```
PARLOUR_WORKSHOP_DIRS=/tmp/an-item godot --path godot
```

Separate several with the platform's PATH separator (`:`, or `;` on Windows,
because a Windows item folder begins `C:\`). The directory needs a `mod.json`
and nothing else — a Workshop item is an ordinary pack, which is the whole
point.

Two things keep this honest rather than making it a debug hatch:

- it is consulted **only while `is_available` is false**, so real Steam can
  never be masked by it;
- what it produces is a plain directory path, which is all a Workshop item ever
  is to the rest of the game. It exercises the real code, not a mock of it.

`tests/test_modloader.gd` drives it to check the three cases that arrive on a
real machine and could not be reached before: an item that loads and merges and
is labelled as Steam's and can be switched off; an item Steam has reported but
not finished downloading, or that was unsubscribed mid-session, which must be
silently skipped rather than reported as a broken pack; and a pack from a
directory none of the four roots explains, which must **not** be credited to
Steam. That last one was a real bug — `_source_of()` knew three roots and
answered "workshop" for everything else, so the Mods screen would have told a
player that Steam installed a pack Steam had never heard of, on the one line
they read to work out where to go and delete it.

## Still not started

The publish flow (point 6 above). Today the only way to distribute a pack is to
share its folder; the Library's "save as a mod pack" writes one that is
Workshop-ready as-is, but nothing uploads it.
