## Autoload. Steam Workshop integration point.
##
## STATUS: STUBBED. This class defines the interface ModLoader.gd already
## calls (get_installed_item_paths()), and returns "nothing installed" until
## real Steamworks access is wired in. Nothing elsewhere in the codebase needs
## to change when that happens — ModLoader treats a Workshop item exactly like
## any other mod pack (a directory with a mod.json), so plugging in real data
## here is the entire integration surface for *loading* Workshop content.
##
## What "real" requires (see docs/STEAM_WORKSHOP.md for the full write-up):
##   1. A Steam App ID (none exists yet — this is a prototype, not a Steam product).
##   2. The GodotSteam GDExtension (https://godotsteam.com/) added to this project.
##   3. steam_appid.txt at the project root with that App ID.
##   4. Steam.steamInit() called at boot, before anything here is trusted.
##   5. Real implementations of the methods below, backed by Steam's
##      ISteamUGC calls (SubscribeItem, DownloadItem, GetItemInstallInfo, ...).
##   6. A publish flow (ShowWorkshopUploadStep or ISteamRemoteStorage calls)
##      for players who want to publish a pack — not started; today the only
##      way to distribute a pack is "share the folder, drop it in user://mods/".
##
## None of that is wired up in this pass — the user asked to architect for it
## and stub the rest. Every method below is written so flipping it from a stub
## to a real Steamworks call is a localized change, not a redesign.
extends Node

## True once real Steamworks access has been initialized. Always false today.
var is_available: bool = false

## Subscribed + downloaded Workshop item ids, cached from the last refresh.
## Empty until real Steamworks calls populate it.
var _installed_item_ids: Array[int] = []

## THE STAND-IN FOR STEAM, so this path can be walked before Steam exists.
##
## Every method here has always returned "nothing installed" — which means the
## branch of ModLoader.discover_pack_dirs() that reads them HAS NEVER ONCE RUN
## WITH DATA IN IT. That is the exact shape this repository has been caught by
## before: a test that passes, has never failed, and proves nothing. As it
## stood, the first thing ever to exercise the Workshop path would have been a
## player's machine on the day GodotSteam landed.
##
## A directory listed here is treated as a subscribed item's install folder,
## with no other difference. It is seeded from PARLOUR_WORKSHOP_DIRS — paths
## separated the way this platform separates PATH — so the whole thing can be
## walked with a real folder and no App ID:
##
##   PARLOUR_WORKSHOP_DIRS=/tmp/an-item godot --path godot
##
## Two things make this safe to ship rather than a debug hatch to remember to
## remove. It is only consulted while `is_available` is false, so real Steam can
## never be masked by it; and what it produces is a plain directory path, which
## is all a Workshop item ever is to the rest of the game — so what it exercises
## is the real code, not a mock of it.
const SIMULATED_ITEMS_PIN := "PARLOUR_WORKSHOP_DIRS"

var simulated_item_paths: Array[String] = []


func _ready() -> void:
	_try_init_steamworks()
	_read_simulated_items()


## Steam hands back an ABSOLUTE path chosen by the client, not a res:// or
## user:// one, so the separator has to be the platform's: a Windows item folder
## begins "C:\", and splitting that on ":" would produce two paths and no pack.
func _read_simulated_items() -> void:
	simulated_item_paths.clear()
	var pin := OS.get_environment(SIMULATED_ITEMS_PIN)
	if pin.strip_edges() == "":
		return
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for path in pin.split(sep, false):
		var trimmed := path.strip_edges()
		if trimmed != "":
			simulated_item_paths.append(trimmed)
	if not simulated_item_paths.is_empty():
		print("[Workshop] %s is set — %d simulated item(s): %s"
			% [SIMULATED_ITEMS_PIN, simulated_item_paths.size(), ", ".join(simulated_item_paths)])


## Real implementation: call Steam.steamInit(), check Steam.isSteamRunning(),
## and set is_available accordingly. Left false here — there is no App ID and
## no GodotSteam extension in this project yet.
func _try_init_steamworks() -> void:
	is_available = false


## Returns the on-disk install path of every subscribed, downloaded Workshop
## item, as res://-or-absolute directory paths ModLoader can treat as mod
## packs (i.e. each must contain a mod.json). Empty until Workshop is wired up.
##
## Real implementation sketch:
##   var paths: Array[String] = []
##   for id in _installed_item_ids:
##       var info = Steam.getItemInstallInfo(id)
##       if info.ret:
##           paths.append(info.folder)
##   return paths
func get_installed_item_paths() -> Array[String]:
	if not is_available:
		return simulated_item_paths.duplicate()
	return []


## Real implementation: Steam.getSubscribedItems() + Steam.downloadItem() per
## id, then populate _installed_item_ids from getItemInstallInfo() as
## downloads complete (Steam delivers this asynchronously via the
## download_item_result signal in GodotSteam — this stub has no such signal).
func refresh_subscribed_items() -> void:
	push_warning("[Workshop] refresh_subscribed_items() is a stub — no Steamworks access. See docs/STEAM_WORKSHOP.md.")


## Placeholder for the "publish this pack to Workshop" flow a future in-game
## mod browser would call. Not implemented — see class doc comment, point 6.
func publish_pack(_pack_dir: String) -> void:
	push_warning("[Workshop] publish_pack() is not implemented. Workshop publishing requires GodotSteam + an App ID; see docs/STEAM_WORKSHOP.md.")
