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
