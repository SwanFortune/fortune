## Content-pack discovery and merging — the actual "mod support" plumbing.
##
## A *pack* is any directory containing a `mod.json` manifest plus the JSON data
## files it lists. The base game ships as one such pack (res://data/base/) so
## there is exactly one code path for "the game's own content" and "a mod" —
## a mod is not a special case, it is just another pack loaded after the base
## pack (and after other mods, ordered by `priority`).
##
## Packs are discovered from, in this order:
##   1. res://data/base/                — the base game, forced first (priority ignored, always 0)
##   2. res://mods_example/*/           — bundled example/dev mods (see Content.LOAD_EXAMPLE_MODS)
##   3. user://mods/*/                  — mods the player dropped in manually
##   4. Workshop.get_installed_item_paths() — Steam Workshop items, once wired up (currently empty; see Workshop.gd)
##
## Within groups 2-4, packs are sorted by ascending `priority` (default 0) so a
## higher-priority pack's records win when both packs define the same id.
class_name ModLoader
extends RefCounted

## Which JSON key holds each category's per-record identifier, used to merge
## by key (a mod can override an existing record by reusing its id, or extend
## the pool by using a new one). Categories not listed here are whole-value
## overrides (the last pack to touch them wins entirely) or plain dict merges.
const ARRAY_KEY_FIELDS := {
	"card_effects": "k",
	"signs": "k",
	"readers": "k",
	"cards_basics": "n",
	"cards_chroma": "n",
	"cards_minor": "n",
	"cards_arcana": "n",
	"relics": "n",
	"marks": "n",
	"elite_twists": "tag",
	"sitters": "name",
	"events": "title",
}

## Categories whose JSON root is an object (dict) merged key-by-key rather
## than an array merged by id field.
const DICT_CATEGORIES := ["elements", "fx", "jobs"]

## Categories whose JSON root is a single record; the last pack to define one wins outright.
const SCALAR_CATEGORIES := ["boss", "shop"]

var errors: Array[String] = []


## Runs discovery + load + merge and returns the final registries dict,
## keyed by category name ("signs", "cards_minor", "fx", ...).
func build_registries() -> Dictionary:
	var registries: Dictionary = {}
	for pack_dir in discover_pack_dirs():
		var manifest := _load_manifest(pack_dir)
		if manifest.is_empty():
			continue
		_load_pack_into(pack_dir, manifest, registries)
	return registries


## Returns pack directories in load order (base first, then example/user/workshop
## packs sorted by ascending priority).
func discover_pack_dirs() -> Array[String]:
	var dirs: Array[String] = []
	if DirAccess.dir_exists_absolute("res://data/base"):
		dirs.append("res://data/base")

	var extra: Array[Dictionary] = []  # {path, priority}
	_collect_subpacks("res://mods_example", extra)
	_ensure_user_mods_dir()
	_collect_subpacks("user://mods", extra)
	for p in Workshop.get_installed_item_paths():
		_collect_one_pack(p, extra)

	extra.sort_custom(func(a, b): return a.priority < b.priority)
	for e in extra:
		dirs.append(e.path)
	return dirs


func _collect_subpacks(root: String, out: Array[Dictionary]) -> void:
	if not DirAccess.dir_exists_absolute(root):
		return
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			_collect_one_pack(root.path_join(name), out)
		name = d.get_next()
	d.list_dir_end()


func _collect_one_pack(path: String, out: Array[Dictionary]) -> void:
	if not FileAccess.file_exists(path.path_join("mod.json")):
		return
	var manifest := _load_manifest(path)
	out.append({"path": path, "priority": int(manifest.get("priority", 0))})


func _ensure_user_mods_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://mods")


func _load_manifest(pack_dir: String) -> Dictionary:
	var path := pack_dir.path_join("mod.json")
	if not FileAccess.file_exists(path):
		errors.append("pack at %s has no mod.json" % pack_dir)
		return {}
	var parsed = _read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("mod.json at %s is not a JSON object" % path)
		return {}
	return parsed


func _load_pack_into(pack_dir: String, manifest: Dictionary, registries: Dictionary) -> void:
	var files: Array = manifest.get("files", [])
	for filename in files:
		var path: String = pack_dir.path_join(str(filename))
		if not FileAccess.file_exists(path):
			errors.append("%s: %s lists %s but the file is missing" % [manifest.get("id", pack_dir), pack_dir, filename])
			continue
		var data = _read_json(path)
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s did not parse to a JSON object" % path)
			continue
		_merge_file(data, registries, manifest.get("id", pack_dir))


func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("could not open %s" % path)
		return null
	var text := f.get_as_text()
	var result = JSON.parse_string(text)
	if result == null and text.strip_edges() != "null":
		errors.append("invalid JSON in %s" % path)
	return result


## Every data file's top-level key(s) name the registry they feed directly —
## e.g. cards_minor.json has a "cards_minor" key, elements.json has "elements"
## plus the topology keys "ring"/"next"/"opp"/"neighbors". A mod's own JSON
## files must follow the same convention: whatever top-level key you write is
## the registry it merges into, so name it after the category you're
## extending, not after your mod. Unrecognised keys (or ones starting with
## "_", used for author comments) are ignored rather than merged blind.
func _merge_file(data: Dictionary, registries: Dictionary, pack_id: String) -> void:
	for raw_key in data.keys():
		if raw_key.begins_with("_"):
			continue
		if not _is_known_category(raw_key):
			errors.append("%s: unrecognised top-level key \"%s\" ignored" % [pack_id, raw_key])
			continue
		_merge_category(raw_key, data[raw_key], registries)


func _is_known_category(category: String) -> bool:
	return category in ARRAY_KEY_FIELDS or category in DICT_CATEGORIES or category in SCALAR_CATEGORIES \
		or category in ["ring", "next", "opp", "neighbors", "denial_shield"]


func _merge_category(category: String, value, registries: Dictionary) -> void:
	if category in SCALAR_CATEGORIES:
		registries[category] = value
		return
	if category in DICT_CATEGORIES:
		if not registries.has(category):
			registries[category] = {}
		for k in value.keys():
			registries[category][k] = value[k]
		return
	if category in ["ring", "next", "opp", "neighbors", "denial_shield"]:
		registries[category] = value
		return
	# Only remaining case per _is_known_category: an array-of-records category.
	var key_field: String = ARRAY_KEY_FIELDS[category]
	if not registries.has(category):
		registries[category] = []
	_merge_array_by_key(registries[category], value, key_field)


func _merge_array_by_key(target: Array, incoming: Array, key_field: String) -> void:
	var index_of := {}
	for i in target.size():
		var rec = target[i]
		if rec.has(key_field):
			index_of[rec[key_field]] = i
	for rec in incoming:
		if not rec.has(key_field):
			target.append(rec)
			continue
		var id = rec[key_field]
		if index_of.has(id):
			target[index_of[id]] = rec
		else:
			index_of[id] = target.size()
			target.append(rec)
