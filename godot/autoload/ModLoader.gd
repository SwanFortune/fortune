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
##   2. res://mods_example/*/           — bundled example/dev mods (only when the
##                                        'load_example_mods' setting is on; see load_example_mods below)
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
	# The difficulty ladder, keyed by its level number. A pack can retune one
	# rung without restating the rest, which is the whole reason these are
	# merged by an id field rather than replaced wholesale.
	"difficulty": "n",
	# The endings, keyed by the fewest people mended that they cover.
	"endings": "mended_from",
}

## Categories whose JSON root is an object (dict) merged key-by-key rather
## than an array merged by id field.
const DICT_CATEGORIES := ["elements", "fx", "jobs", "denial_wall", "pronouns", "sounds", "minitel_codes",
	"icons", "archetypes", "music"]

## Categories whose JSON root is a single record; the last pack to define one wins outright.
const SCALAR_CATEGORIES := ["boss", "shop"]

## The base game's own pack. Forced first, never disabled.
const BASE_DIR := "res://data/base"
const BASE_ID := "parlour.base"

## Field stamped onto every merged record naming the pack that last defined it.
## Underscore-prefixed to match the convention for keys that are bookkeeping
## rather than content.
const PACK_FIELD := "_pack"

var errors: Array[String] = []

## Whether to scan res://mods_example/. Set by Content from the player
## setting of the same name; user://mods/ and Workshop items always load.
var load_example_mods: bool = true

## Pack ids the player switched off in the Mods screen. The base pack ignores
## this list — a game with no base content is not a state worth reaching.
var disabled_ids: Array = []

## What discovery found, in load order, whether or not it was loaded:
## {id, name, version, description, priority, path, source, enabled, base,
##  categories, records}. Populated by build_registries(); this used to be
## thrown away, which is why nothing could tell the player which packs were
## live, in what order, or which of them was responsible for an error.
var packs: Array[Dictionary] = []


## Runs discovery + load + merge and returns the final registries dict,
## keyed by category name ("signs", "cards_minor", "fx", ...).
func build_registries() -> Dictionary:
	var registries: Dictionary = {}
	packs = []
	_manifests = {}
	for pack_dir in discover_pack_dirs():
		var manifest := _load_manifest(pack_dir)
		if manifest.is_empty():
			continue
		var is_base: bool = pack_dir == BASE_DIR
		var id: String = str(manifest.get("id", pack_dir))
		var enabled: bool = is_base or not disabled_ids.has(id)
		var rec := {
			"id": id,
			"name": str(manifest.get("name", id)),
			"version": str(manifest.get("version", "")),
			"description": str(manifest.get("description", "")),
			"priority": int(manifest.get("priority", 0)),
			"path": pack_dir,
			"source": _source_of(pack_dir),
			"base": is_base,
			"enabled": enabled,
			"categories": [],
			"records": 0,
		}
		packs.append(rec)
		if enabled:
			_load_pack_into(pack_dir, manifest, registries, rec)
	_check_against_the_base(registries)
	return registries


## Locale tables are keyed strings, not records with a name and a rule, so the
## contract below has nothing to say about them. Matched by prefix rather than
## named: this was a list of two, `locale_fr` and `locale_en`, which a pack
## shipping `locale_de` would have walked straight past — a hand-kept list that
## the data can outgrow, in the one file whose whole subject is that.
const NOT_RECORD_PREFIX := "locale_"


## EVERY RECORD A PACK ADDS CARRIES WHAT THE BASE GAME'S RECORDS CARRY.
##
## There was no contract at all. A card missing `cost` is a free card; one
## missing `el` has no element and quietly scores as neutral; one missing `f`
## restores nothing. None of that fails at load — it fails later, on a screen,
## as a card that behaves strangely, and for a modder it fails on somebody
## else's machine.
##
## THE CONTRACT IS DERIVED, NOT WRITTEN DOWN. A hand-kept schema is one more
## list to fall behind the data, which is the failure this project keeps
## finding; and a schema written today would be wrong the first time a field is
## added to the base game. So the base pack IS the schema: a field that every
## base record of a kind carries is a field that kind requires. Add `patience`
## to all thirteen readers and mods must supply it, with no schema to edit —
## add it to twelve and it is optional, which is also the right answer.
##
## EVERY RECORD, INCLUDING OVERRIDES. Overrides used to be exempt because they
## had to be: replacement was wholesale, so a balance patch restating one number
## reached here with one number and this would have called it broken. Since
## _laid_over() an override inherits what it does not mention, so it satisfies
## the contract for free — and the only way to reach here incomplete is to have
## asked for it with `"_replace": true`.
##
## Reported rather than refused. A pack with a malformed card should load its
## other forty, and the Mods screen already puts load errors in front of the
## player; dropping the pack would leave them with a game that quietly lacks
## the content they installed.
func _check_against_the_base(registries: Dictionary) -> void:
	for key in registries:
		if str(key).begins_with(NOT_RECORD_PREFIX):
			continue
		var records = registries[key]
		if not (records is Array) or records.is_empty() or not (records[0] is Dictionary):
			continue
		var required := _fields_every_base_record_has(records)
		if required.is_empty():
			continue
		# NO EXEMPTION FOR OVERRIDES ANY MORE. There used to be one, and it was
		# forced: replacement was wholesale, so a balance patch legitimately
		# restating one number arrived here missing everything else and this
		# would have called it broken. Now an override is laid OVER the base
		# record — see _laid_over() — so by the time it is checked it carries
		# what the base carried, and the contract applies to every record
		# equally. The one way to arrive here incomplete is `"_replace": true`,
		# which is a record saying it means to start from nothing; that is
		# exactly when somebody should be told what it dropped.
		for r in records:
			if not (r is Dictionary) or str(r.get("_pack", BASE_ID)) == BASE_ID:
				continue
			for field in required:
				if not r.has(field):
					errors.append("%s: its %s entry \"%s\" has no \"%s\", which every %s in the base game has — it will load and then behave oddly"
						% [r.get("_pack", "?"), key, _name_of(r), field, key])


## The fields common to every base record of one kind. Empty when the kind has
## no base records at all — a pack inventing a whole new registry has nothing to
## be measured against, and that is allowed.
func _fields_every_base_record_has(records: Array) -> Array:
	var common: Dictionary = {}
	var first := true
	for r in records:
		if not (r is Dictionary) or str(r.get("_pack", BASE_ID)) != BASE_ID:
			continue
		if first:
			for k in r:
				if not str(k).begins_with("_"):
					common[k] = true
			first = false
			continue
		for k in common.keys():
			if not r.has(k):
				common.erase(k)
	return common.keys()


## Enough to find the record in a file. Most content is named; some is keyed.
func _name_of(r: Dictionary) -> String:
	for field in ["n", "name", "k", "title", "tag", "head"]:
		if r.has(field):
			return str(r[field])
	return "(unnamed)"


## Which of the four discovery roots a pack came from, for the Mods screen —
## a player needs to tell "shipped with the game" from "I dropped this in"
## from "Steam installed this", because that decides where to go to remove it.
func _source_of(pack_dir: String) -> String:
	if pack_dir == BASE_DIR:
		return "base"
	if pack_dir.begins_with("res://mods_example"):
		return "example"
	if pack_dir.begins_with("user://mods"):
		return "user"
	# NOT a fallthrough. This used to answer "workshop" for anything that was
	# none of the three above, which is a guess printed as a fact on the one line
	# a player reads to decide where to go and delete something. A Workshop
	# item's folder is an absolute path Steam picks, so it cannot be recognised
	# by its shape — only by having COME FROM Workshop, which is what this
	# remembers. Anything else says so instead of blaming Steam.
	if _from_workshop.has(pack_dir):
		return "workshop"
	return "elsewhere"


## The paths Workshop reported during the last discovery pass; see _source_of().
var _from_workshop: Dictionary = {}


## Returns pack directories in load order (base first, then example/user/workshop
## packs sorted by ascending priority).
func discover_pack_dirs() -> Array[String]:
	var dirs: Array[String] = []
	if DirAccess.dir_exists_absolute(BASE_DIR):
		dirs.append(BASE_DIR)

	var extra: Array[Dictionary] = []  # {path, priority}
	if load_example_mods:
		_collect_subpacks("res://mods_example", extra)
	_ensure_user_mods_dir()
	_collect_subpacks("user://mods", extra)
	_from_workshop.clear()
	for p in Workshop.get_installed_item_paths():
		_from_workshop[p] = true
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


## Manifests read so far, by pack directory. Discovery needs each manifest for
## its `priority` and the load pass needs it again for everything else, so
## without this every manifest is parsed twice — and a BROKEN one is reported
## twice. Combined with _read_json's own message that made a single unparseable
## mod.json produce four entries in Content.load_errors, and the Mods screen
## counts what it is handed: one typo, "4 problems".
var _manifests: Dictionary = {}


func _load_manifest(pack_dir: String) -> Dictionary:
	if _manifests.has(pack_dir):
		return _manifests[pack_dir]
	var manifest := _parse_manifest(pack_dir)
	_manifests[pack_dir] = manifest
	return manifest


func _parse_manifest(pack_dir: String) -> Dictionary:
	var path := pack_dir.path_join("mod.json")
	if not FileAccess.file_exists(path):
		errors.append("pack at %s has no mod.json" % pack_dir)
		return {}
	var parsed = _read_json(path)
	# null means _read_json already said why (unreadable, or unparseable), and
	# saying "and it is not a JSON object" after that is a second message for
	# one fault. A parsed-but-wrong-shape manifest — an array, a bare number —
	# is a different fault and still gets its own line.
	if parsed == null:
		return {}
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("mod.json at %s is not a JSON object" % path)
		return {}
	return parsed


func _load_pack_into(pack_dir: String, manifest: Dictionary, registries: Dictionary, rec: Dictionary) -> void:
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
		_merge_file(data, registries, manifest.get("id", pack_dir), rec)


func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("could not open %s" % path)
		return null
	var text := f.get_as_text()
	var result = JSON.parse_string(text)
	if result == null and text.strip_edges() != "null":
		errors.append("invalid JSON in %s" % path)
	return _whole_numbers_to_ints(result)


## JSON HAS NO INTEGER TYPE, so Godot parses every number as a float: a card's
## `"cost": 1` arrives as 1.0. The codebase treats these as ints throughout, and
## str() on an integral float prints "1" on Godot 4.3 and "1.0" on 4.7 — so
## without this every card reads "1.0" for its cost, with nothing erroring and
## no test failing.
##
## Coerced HERE rather than at the display sites, so "a number that looks whole
## IS an int" holds for base content and every mod at once. Genuinely fractional
## values (maxMul 1.35, pitch_jitter 0.05) are left alone.
func _whole_numbers_to_ints(value):
	match typeof(value):
		TYPE_FLOAT:
			# is_equal_approx guards against a value that is whole but stored
			# with float error; is_finite guards INF/NAN, which int() would
			# turn into nonsense.
			if is_finite(value) and value == floor(value) and absf(value) < 9007199254740992.0:
				return int(value)
			return value
		TYPE_DICTIONARY:
			var d := {}
			for k in value:
				d[k] = _whole_numbers_to_ints(value[k])
			return d
		TYPE_ARRAY:
			var a := []
			for item in value:
				a.append(_whole_numbers_to_ints(item))
			return a
	return value


## Every data file's top-level key(s) name the registry they feed directly —
## e.g. cards_minor.json has a "cards_minor" key, elements.json has "elements"
## plus the topology keys "ring"/"next"/"opp"/"neighbors". A mod's own JSON
## files must follow the same convention: whatever top-level key you write is
## the registry it merges into, so name it after the category you're
## extending, not after your mod. Unrecognised keys (or ones starting with
## "_", used for author comments) are ignored rather than merged blind.
func _merge_file(data: Dictionary, registries: Dictionary, pack_id: String, rec: Dictionary = {}) -> void:
	for raw_key in data.keys():
		if raw_key.begins_with("_"):
			continue
		if not _is_known_category(raw_key):
			errors.append("%s: unrecognised top-level key \"%s\" ignored" % [pack_id, raw_key])
			continue
		_merge_category(raw_key, data[raw_key], registries, pack_id)
		if not rec.is_empty():
			if not rec["categories"].has(raw_key):
				rec["categories"].append(raw_key)
			var value = data[raw_key]
			rec["records"] += value.size() if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else 1


func _is_known_category(category: String) -> bool:
	return category in ARRAY_KEY_FIELDS or category in DICT_CATEGORIES or category in SCALAR_CATEGORIES \
		or category in ["ring", "next", "opp", "neighbors", "denial_shield"] \
		or category.begins_with("locale_")


func _merge_category(category: String, value, registries: Dictionary, pack_id: String = "") -> void:
	if category in SCALAR_CATEGORIES:
		registries[category] = value
		return
	# locale_<lang> tables merge key-by-key like any other dict category, so
	# a mod can translate just the handful of strings it cares about without
	# having to restate a whole locale.
	if category in DICT_CATEGORIES or category.begins_with("locale_"):
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
	_merge_array_by_key(registries[category], value, key_field, pack_id)


## Records carry a PACK_FIELD naming whoever last defined them. It answers the
## question a modder actually asks ("who overrode my card?"), and it lets
## anything that reasons about base content — tests/test_art.gd, for one — tell
## "the base game is missing this" from "a mod added this", which are opposite
## conclusions from the same missing manifest entry.
func _merge_array_by_key(target: Array, incoming: Array, key_field: String, pack_id: String = "") -> void:
	var index_of := {}
	for i in target.size():
		var rec = target[i]
		if rec.has(key_field):
			index_of[rec[key_field]] = i
	for rec in incoming:
		if pack_id != "":
			rec[PACK_FIELD] = pack_id
		if not rec.has(key_field):
			target.append(rec)
			continue
		var id = rec[key_field]
		if not index_of.has(id):
			index_of[id] = target.size()
			target.append(_without_the_flags(rec))
			continue
		var at: int = index_of[id]
		if bool(rec.get(REPLACE_FIELD, false)):
			target[at] = _without_the_flags(rec)
		else:
			target[at] = _laid_over(target[at], rec)


## AN OVERRIDE SUPPLIES WHAT IT CHANGES, and inherits the rest.
##
## This used to be `target[at] = rec` — the record replaced the one it matched,
## whole. That was documented, and docs/MODDING.md called it a sharp edge and
## told a modder to restate the whole card. Both halves of that were measured
## before this changed, and both are worse than they read:
##
##   - a balance patch that restates one number got a card that was ONLY that
##     number. `{"n": "Take Their Coat", "cost": 0}` loaded as exactly that: no
##     element, no faith, no effects, no flavour, and NO LOAD ERROR. A blank
##     card, in the deck, playable, worth nothing;
##   - and doing what the docs said instead is worse in the long run, because
##     restating the whole card FREEZES it at the version it was copied from.
##     A mod written before the base game grew `sp` keeps overriding the card
##     without one for ever; the spoken clause then falls back to the card's
##     NAME, so a reading says "and Take Their Coat" in the middle of a
##     sentence. Measured, silent, and no error either.
##
## The second is the one that decided it. A full restate is a COPY of the base
## record, and a copy stops tracking what it copied — which is the failure this
## repository keeps finding in hand-kept lists, arriving here by another door.
## Laying the patch over the base instead means an override tracks the base for
## everything it does not mention, which is what a balance patch means.
##
## Nested values are taken whole rather than merged into. `"e"` is a card's
## effects, and "the effects are now exactly this" has to stay sayable — merging
## a level down would make removing one effect impossible.
##
## TWO ESCAPES, both explicit and both underscored like every other bookkeeping
## key here, and both stripped before the record reaches content:
##
##   - `"_remove": ["fl"]` takes fields away;
##   - `"_replace": true` restores wholesale replacement for a record that really
##     does mean to start from nothing.
##
## THE FIRST ONE WAS `"fl": null` AND THAT WAS WRONG. It reads better and it
## overloads a value this content already uses: seven base cards are neutral and
## say so with `"el": null`, so the Library's own pack — which writes the card
## back whole — had its element erased by the rule meant to help it. The suite
## caught it, once the check below stopped exempting overrides. A sentinel has
## to be something the data cannot already mean.
const REPLACE_FIELD := "_replace"
const REMOVE_FIELD := "_remove"


func _laid_over(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in patch:
		if str(k) == REPLACE_FIELD or str(k) == REMOVE_FIELD:
			continue
		out[k] = patch[k]
	for k in _asked_to_remove(patch):
		out.erase(k)
	return out


## A record as it should reach the content: its own fields, minus anything it
## asked to drop, minus the two flags themselves.
func _without_the_flags(rec: Dictionary) -> Dictionary:
	var out: Dictionary = rec.duplicate(true)
	for k in _asked_to_remove(rec):
		out.erase(k)
	out.erase(REPLACE_FIELD)
	out.erase(REMOVE_FIELD)
	return out


func _asked_to_remove(rec: Dictionary) -> Array:
	var listed = rec.get(REMOVE_FIELD, [])
	return listed if listed is Array else []
