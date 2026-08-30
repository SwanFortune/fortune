## Autoload. Persistence for the Library's card edits.
##
## Edits are saved as a NORMAL MOD PACK at user://mods/library-edits/ rather
## than as a bespoke save format. That's deliberate and buys several things
## for free:
##   - ModLoader already merges packs by record key ("n" for cards), so an
##     edited card overrides its base version through the exact code path a
##     third-party balance mod would use — no special-casing in the loader.
##   - A high `priority` means these edits win over other installed mods.
##   - The result is a real, shareable, Workshop-uploadable folder. "I
##     rebalanced the deck in the Library" and "I made a mod" are the same
##     artifact.
##   - Only *changed* cards are written, so unedited cards keep tracking the
##     base game as it changes rather than being frozen at their current
##     values.
##
## The prototype stored the equivalent in localStorage under
## 'parlour.cards.v2' (see its loadCards()); this is the same idea pointed at
## a format the rest of this port already understands.
extends Node

const PACK_DIR := "user://mods/library-edits"
const PACK_ID := "local.library-edits"
const PRIORITY := 1000

## Which card pools the Library can edit, and therefore which files this pack
## may write. Matches ModLoader.ARRAY_KEY_FIELDS' card categories.
const POOLS := ["cards_basics", "cards_chroma", "cards_minor", "cards_arcana"]

## pool -> { card name -> full edited card dict }
var edits: Dictionary = {}


func _ready() -> void:
	load_from_disk()


func has_edit(pool: String, card_name: String) -> bool:
	return edits.has(pool) and edits[pool].has(card_name)


func edit_count() -> int:
	var n := 0
	for pool in edits:
		n += edits[pool].size()
	return n


## Records `card` as the new definition of that card and rewrites the pack.
## `card` should be the complete card dict (the Library hands us the whole
## edited record, not a delta) so the written pack is self-contained.
func set_card(pool: String, card: Dictionary) -> void:
	if not POOLS.has(pool):
		push_error("[CardEdits] '%s' is not an editable pool" % pool)
		return
	if not edits.has(pool):
		edits[pool] = {}
	edits[pool][card["n"]] = card.duplicate(true)
	save_to_disk()


## Drops the override for one card, so it reverts to whatever the base game
## (plus any lower-priority mod) says.
func revert_card(pool: String, card_name: String) -> void:
	if edits.has(pool):
		edits[pool].erase(card_name)
		if edits[pool].is_empty():
			edits.erase(pool)
	save_to_disk()


func revert_all() -> void:
	edits.clear()
	save_to_disk()


func load_from_disk() -> void:
	edits.clear()
	for pool in POOLS:
		var path := PACK_DIR.path_join(pool + ".json")
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has(pool):
			continue
		var by_name := {}
		for c in parsed[pool]:
			if c.has("n"):
				by_name[c["n"]] = c
		if not by_name.is_empty():
			edits[pool] = by_name


## Rewrites the whole pack from `edits`. Files for pools with no edits are
## deleted rather than left behind empty, so the manifest never lists a file
## that contributes nothing (ModLoader would warn about a listed-but-missing
## file, and an empty array is just noise).
func save_to_disk() -> void:
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	var files: Array[String] = []
	for pool in POOLS:
		var path := PACK_DIR.path_join(pool + ".json")
		var by_name: Dictionary = edits.get(pool, {})
		if by_name.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var rows: Array = []
		for name in by_name:
			rows.append(by_name[name])
		var doc := {
			"_comment": "Written by the in-game Library. Each entry fully replaces the base card of the same name (ModLoader merges card pools by \"n\"). Safe to hand-edit, share, or upload to the Workshop as-is.",
			pool: rows,
		}
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(doc, "  ") + "\n")
		f.close()
		files.append(pool + ".json")

	var manifest_path := PACK_DIR.path_join("mod.json")
	if files.is_empty():
		# No edits left: remove the manifest too, so the pack stops existing
		# rather than lingering as an empty mod in the loaded-packs count.
		if FileAccess.file_exists(manifest_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest_path))
		return
	var manifest := {
		"id": PACK_ID,
		"name": "Library edits",
		"version": "1.0.0",
		"priority": PRIORITY,
		"description": "Card changes made in the in-game Library. Loads after other mods so these edits win.",
		"files": files,
	}
	var mf := FileAccess.open(manifest_path, FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "  ") + "\n")
	mf.close()


## Absolute path to the pack, for showing the player where their edits live
## (so they can find, back up, or share the folder).
func pack_path_for_display() -> String:
	return ProjectSettings.globalize_path(PACK_DIR)
