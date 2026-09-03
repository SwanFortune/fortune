## Headless test for the mod-pack loader.
##   godot --headless --path godot -s tests/test_modloader.gd
##
## ModLoader had no test at all, which is an odd place for this project to have
## a hole: mod support is the thing the port is FOR, `docs/MODDING.md` makes
## specific promises about it, and seven distinct error paths were written in
## the belief that they would be hit by real packs one day. None of them had
## ever run.
##
## Everything here is driven with REAL PACKS written to user://mods/ and read
## back off the disk, rather than by handing the merge functions dictionaries.
## The promises being tested are about files — a manifest that will not parse, a
## listed file that is not there — and a test that skips the filesystem cannot
## make them.
##
## The guarantees under test:
##   - the merge rules docs/MODDING.md documents: array categories merge by
##     their id field (override or extend), dict categories merge key-by-key,
##     scalar categories are replaced whole, and `priority` decides who wins;
##   - EVERY error path reports, and the pack keeps loading anyway. "A pack that
##     reports an error is still loaded; only the record or file that caused it
##     is skipped" is a sentence in the docs, and it is the difference between
##     one typo costing a modder one card and costing them their whole pack;
##   - a broken pack cannot damage the base game;
##   - a disabled pack contributes nothing at all;
##   - every merged record carries the id of the pack that last defined it, so
##     the Mods screen and tests/test_art.gd can tell base content from a mod's.
##
## Autoloads are fetched via get_node() — see the note at the top of
## tests/test_rules.gd for why the bare global names don't resolve here.
extends SceneTree

const TESTS := [
	"_test_a_pack_overrides_by_key",
	"_test_a_pack_extends_a_pool",
	"_test_dict_categories_merge_key_by_key",
	"_test_scalar_categories_are_replaced_whole",
	"_test_priority_decides_who_wins",
	"_test_every_error_is_reported_and_the_pack_still_loads",
	"_test_a_broken_pack_leaves_the_base_game_intact",
	"_test_a_disabled_pack_contributes_nothing",
	"_test_every_record_names_its_pack",
	"_test_a_bad_manifest_is_reported_once",
]

## Where the test packs are written. Under user://mods/ because that is a real
## discovery root — a pack the loader finds the same way it finds a player's.
const ROOT := "user://mods"
const PREFIX := "zz_test_"

var failures: Array[String] = []
var finished: Dictionary = {}


func _initialize() -> void:
	await process_frame
	_clean()   # in case a previous run died before its own cleanup

	for t in TESTS:
		call(t)
		_clean()
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)

	# The autoloaded Content still holds registries built from whatever packs
	# existed when a test was mid-flight. Put it back to the real thing so a
	# suite runner that continues in this process is not left with test cards.
	root.get_node("Content").reload()

	if failures.is_empty():
		print("ALL PASS — %d test methods" % TESTS.size())
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func done(name: String) -> void:
	finished[name] = true


# ── building packs on disk ──────────────────────────────────────────────

## Writes a pack: `files` maps a filename to either a String (written verbatim,
## for the malformed cases) or a Variant (serialised as JSON). The manifest's
## `files` list is derived from the keys unless `manifest` names its own, so a
## test can deliberately list a file it does not write.
func _pack(name: String, manifest: Dictionary, files: Dictionary) -> String:
	var dir := ROOT.path_join(PREFIX + name)
	DirAccess.make_dir_recursive_absolute(dir)
	var m := manifest.duplicate(true)
	if not m.has("id"):
		m["id"] = PREFIX + name
	if not m.has("files"):
		m["files"] = files.keys()
	_write(dir.path_join("mod.json"), JSON.stringify(m, "  "))
	for filename in files:
		var body = files[filename]
		_write(dir.path_join(filename), body if body is String else JSON.stringify(body, "  "))
	return dir


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A loader configured the way the game configures it, minus the example pack —
## the bundled example mod is real content with real cards, and letting it into
## these registries would make every count assertion here depend on it.
func _load(disabled: Array = []) -> Dictionary:
	var loader = load("res://autoload/ModLoader.gd").new()
	loader.load_example_mods = false
	loader.disabled_ids = disabled
	var registries: Dictionary = loader.build_registries()
	return {"registries": registries, "errors": loader.errors, "packs": loader.packs}


func _clean() -> void:
	var d := DirAccess.open(ROOT)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and name.begins_with(PREFIX):
			_rm_rf(ROOT.path_join(name))
		name = d.get_next()
	d.list_dir_end()


func _rm_rf(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			_rm_rf(dir.path_join(name))
		else:
			DirAccess.remove_absolute(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)


## The record with `key_field == value` in a registry array, or {}.
func _find(rows: Array, key_field: String, value: String) -> Dictionary:
	for r in rows:
		if str(r.get(key_field, "")) == value:
			return r
	return {}


# ── the merge rules ─────────────────────────────────────────────────────

## Reusing an existing id REPLACES that record. This is how a balance patch
## retunes a card without shipping a copy of the base game.
func _test_a_pack_overrides_by_key() -> void:
	var base := _load()
	var before: Array = base["registries"]["cards_basics"]
	var target := str(before[0]["n"])
	var was := int(before[0].get("f", 0))

	_pack("override", {}, {"cards_basics.json": {
		"cards_basics": [{"n": target, "cost": 0, "f": was + 50, "el": "fire"}],
	}})
	var after := _load()
	var rows: Array = after["registries"]["cards_basics"]
	check(rows.size() == before.size(), "an override must not change the pool size (%d -> %d)" % [before.size(), rows.size()])
	check(int(_find(rows, "n", target).get("f", 0)) == was + 50,
		"'%s' should carry the pack's value, got %s" % [target, _find(rows, "n", target).get("f")])
	check(after["errors"].is_empty(), "a well-formed pack should report nothing: %s" % [after["errors"]])
	done("_test_a_pack_overrides_by_key")


func _test_a_pack_extends_a_pool() -> void:
	var before: int = _load()["registries"]["cards_basics"].size()
	_pack("extend", {}, {"cards_basics.json": {
		"cards_basics": [{"n": "A Card Nobody Shipped", "cost": 1, "f": 3, "el": "water"}],
	}})
	var after := _load()
	var rows: Array = after["registries"]["cards_basics"]
	check(rows.size() == before + 1, "a new id should be appended (%d -> %d)" % [before, rows.size()])
	check(not _find(rows, "n", "A Card Nobody Shipped").is_empty(), "and be findable by name")
	done("_test_a_pack_extends_a_pool")


## A dict category merges KEY BY KEY. Whole-value replacement here would mean a
## pack that retunes one effect silently deletes every other effect in the game
## — the kind of breakage that looks like the base game is broken.
func _test_dict_categories_merge_key_by_key() -> void:
	var base: Dictionary = _load()["registries"]["fx"]
	var keys := base.keys()
	check(keys.size() > 3, "precondition: the base game should ship several fx")
	var target := str(keys[0])

	_pack("dictmerge", {}, {"fx.json": {"fx": {target: {"t": "REPLACED BY A TEST"}}}})
	var after: Dictionary = _load()["registries"]["fx"]
	check(after.size() == base.size(), "the other fx must survive (%d -> %d)" % [base.size(), after.size()])
	check(str(after.get(target, {}).get("t", "")) == "REPLACED BY A TEST", "and the named one is replaced")
	done("_test_dict_categories_merge_key_by_key")


## A scalar category is one record, so the last pack to define it wins outright
## rather than having its fields merged into the previous one.
func _test_scalar_categories_are_replaced_whole() -> void:
	var base: Dictionary = _load()["registries"]["boss"]
	check(not base.is_empty(), "precondition: the base game ships a boss")
	check(base.has("role"), "precondition: the base boss has a role")

	_pack("boss", {}, {"boss.json": {"boss": {"name": "A Test Boss", "max": 10}}})
	var after: Dictionary = _load()["registries"]["boss"]
	check(str(after.get("name", "")) == "A Test Boss", "the later pack's boss should win")
	check(not after.has("role"), "and win WHOLE — no field left over from the one it replaced")
	done("_test_scalar_categories_are_replaced_whole")


## Two packs touching the same card: the higher `priority` loads later and wins.
## Load order is otherwise directory order, which is not something a modder can
## rely on.
func _test_priority_decides_who_wins() -> void:
	var target := str(_load()["registries"]["cards_basics"][0]["n"])
	# Written in the order that would give the WRONG answer if priority were
	# ignored and directory order used: "aaa" sorts first but claims to be last.
	_pack("aaa_high", {"priority": 10}, {"cards_basics.json": {
		"cards_basics": [{"n": target, "cost": 0, "f": 111, "el": "fire"}]}})
	_pack("bbb_low", {"priority": 1}, {"cards_basics.json": {
		"cards_basics": [{"n": target, "cost": 0, "f": 222, "el": "fire"}]}})

	var out := _load()
	var row := _find(out["registries"]["cards_basics"], "n", target)
	check(int(row.get("f", 0)) == 111, "priority 10 should beat priority 1, got f=%s" % row.get("f"))
	check(str(row.get("_pack", "")) == PREFIX + "aaa_high", "and the stamp should say so, got '%s'" % row.get("_pack"))
	done("_test_priority_decides_who_wins")


# ── the error paths ─────────────────────────────────────────────────────

## Four different ways to write a broken file, in one pack that also contains a
## good one. Each must be reported BY NAME, and the good file must still load —
## that is the promise in docs/MODDING.md, and it is the difference between one
## typo costing a modder one file and costing them their whole pack.
func _test_every_error_is_reported_and_the_pack_still_loads() -> void:
	_pack("broken", {"files": [
		"good.json", "missing.json", "notjson.json", "notobject.json", "unknown.json",
	]}, {
		"good.json": {"cards_basics": [{"n": "Survivor", "cost": 1, "f": 2, "el": "air"}]},
		# missing.json is listed above and deliberately not written.
		"notjson.json": "{ this is not json at all",
		"notobject.json": "[1, 2, 3]",
		"unknown.json": {"cards_basics": [{"n": "Also Survives", "cost": 1, "f": 2, "el": "air"}],
			"nonsense_category": [1, 2, 3]},
	})

	var out := _load()
	var errs: Array = out["errors"]
	var joined := "\n".join(errs)
	for needle in ["missing.json", "notjson.json", "notobject.json", "nonsense_category"]:
		check(joined.contains(needle), "'%s' should be named in an error, got:\n%s" % [needle, joined])

	# The whole point: the rest of the pack loaded anyway.
	var rows: Array = out["registries"]["cards_basics"]
	check(not _find(rows, "n", "Survivor").is_empty(),
		"the good file in a pack with four broken ones must still load")
	check(not _find(rows, "n", "Also Survives").is_empty(),
		"and so must the good half of a file with one unrecognised key")
	done("_test_every_error_is_reported_and_the_pack_still_loads")


## A pack can be as broken as it likes; the game it is modding still has to be
## there. Anything else turns "I installed a mod" into "my game is corrupt".
func _test_a_broken_pack_leaves_the_base_game_intact() -> void:
	var base := _load()
	_pack("garbage", {"files": ["a.json", "b.json"]}, {
		"a.json": "\\u0000 not even text",
		"b.json": "null",
	})
	var after := _load()
	check(not after["errors"].is_empty(), "precondition: the garbage pack should report something")
	for category in base["registries"]:
		var was = base["registries"][category]
		var now = after["registries"][category]
		if typeof(was) == TYPE_ARRAY:
			check(now.size() == was.size(), "%s lost records to a broken pack (%d -> %d)" % [category, was.size(), now.size()])
		elif typeof(was) == TYPE_DICTIONARY:
			check(now.size() == was.size(), "%s lost keys to a broken pack (%d -> %d)" % [category, was.size(), now.size()])
	done("_test_a_broken_pack_leaves_the_base_game_intact")


## Switching a pack off in the Mods screen has to mean it contributes nothing,
## not that it is merely hidden from the list.
func _test_a_disabled_pack_contributes_nothing() -> void:
	var id := PREFIX + "switchable"
	_pack("switchable", {}, {"cards_basics.json": {
		"cards_basics": [{"n": "Only When Enabled", "cost": 1, "f": 2, "el": "air"}]}})

	var on := _load()
	check(not _find(on["registries"]["cards_basics"], "n", "Only When Enabled").is_empty(),
		"precondition: the pack loads when enabled")

	var off := _load([id])
	check(_find(off["registries"]["cards_basics"], "n", "Only When Enabled").is_empty(),
		"a disabled pack must contribute no records")
	# It is still LISTED, switched off — the Mods screen needs to offer it back.
	var listed := false
	for p in off["packs"]:
		if str(p.get("id", "")) == id:
			listed = true
			check(not bool(p.get("enabled", true)), "and be listed as switched off")
	check(listed, "a disabled pack should still appear in the pack list, to be switchable back on")

	# The base pack ignores the list entirely: a game with no base content is
	# not a state worth being able to reach.
	var no_base := _load(["parlour.base"])
	check(not no_base["registries"].get("cards_basics", []).is_empty(),
		"the base pack must not be disableable")
	done("_test_a_disabled_pack_contributes_nothing")


## Provenance. tests/test_art.gd scopes its manifest check with this stamp, and
## the Mods screen counts records per pack from it, so an unstamped record is a
## record neither of them can account for.
func _test_every_record_names_its_pack() -> void:
	_pack("stamped", {}, {"cards_basics.json": {
		"cards_basics": [{"n": "Stamped Card", "cost": 1, "f": 2, "el": "air"}]}})
	var out := _load()
	var rows: Array = out["registries"]["cards_basics"]
	check(str(_find(rows, "n", "Stamped Card").get("_pack", "")) == PREFIX + "stamped",
		"a mod's record should name the mod")
	for r in rows:
		check(str(r.get("_pack", "")) != "", "every card should name a pack; '%s' names none" % r.get("n"))

	# And the pack list's own record count agrees with what actually landed.
	for p in out["packs"]:
		if str(p.get("id", "")) == PREFIX + "stamped":
			check(int(p.get("records", 0)) == 1, "the pack list should count 1 record, says %s" % p.get("records"))
	done("_test_every_record_names_its_pack")


## A manifest that will not parse is ONE problem, and the Mods screen counts
## what it is handed — so reporting it twice tells the player they have two.
func _test_a_bad_manifest_is_reported_once() -> void:
	var dir := ROOT.path_join(PREFIX + "badmanifest")
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("mod.json"), "{ not a manifest")

	var errs: Array = _load()["errors"]
	var about_manifest := 0
	for e in errs:
		if str(e).contains(PREFIX + "badmanifest"):
			about_manifest += 1
	check(about_manifest > 0, "an unparseable manifest should be reported at all, got %s" % [errs])
	check(about_manifest <= 2, "one broken manifest should not produce %d messages: %s" % [about_manifest, errs])
	done("_test_a_bad_manifest_is_reported_once")
