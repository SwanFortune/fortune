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


func _ready() -> void:
	_try_init_steamworks()


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
