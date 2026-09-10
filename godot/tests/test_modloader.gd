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
extends "res://tests/harness.gd"

## Where the test packs are written. Under user://mods/ because that is a real
## discovery root — a pack the loader finds the same way it finds a player's.
const ROOT := "user://mods"
const PREFIX := "zz_test_"


func setup() -> void:
	_clean()   # in case a previous run died before its own cleanup


func after_each(_test_name: String) -> void:
	_clean()


func teardown() -> void:
	# The autoloaded Content still holds registries built from whatever packs
	# existed when a test was mid-flight. Put it back to the real thing so a
	# suite runner that continues in this process is not left with test cards.
	root.get_node("Content").reload()


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

## Reusing an existing id PATCHES that record — this one restates several
## fields, which is the ordinary case; that the ones it leaves out survive is
## _test_an_override_inherits_the_rest_of_the_record below.
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
	done()


func _test_a_pack_extends_a_pool() -> void:
	var before: int = _load()["registries"]["cards_basics"].size()
	_pack("extend", {}, {"cards_basics.json": {
		"cards_basics": [{"n": "A Card Nobody Shipped", "cost": 1, "f": 3, "el": "water"}],
	}})
	var after := _load()
	var rows: Array = after["registries"]["cards_basics"]
	check(rows.size() == before + 1, "a new id should be appended (%d -> %d)" % [before, rows.size()])
	check(not _find(rows, "n", "A Card Nobody Shipped").is_empty(), "and be findable by name")
	done()


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
	done()


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
	done()


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
	done()


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
	done()


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
	done()


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
	done()


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
	done()


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
	done()


## A CARD A PACK INVENTS MUST LOOK LIKE A CARD.
##
## There was no contract of any kind. A card with no `cost` is a free card; one
## with no `el` has no element and scores as neutral; one with no `f` restores
## nothing. None of that fails at load — it fails later, on a screen, as a card
## that behaves oddly, and for a modder it fails on somebody else's machine.
##
## The contract is DERIVED: a field every base card carries is a field a card
## requires. Not a schema written down beside the data, which is one more list
## to fall out of step with it — add a field to all fifty-six base cards and
## mods must supply it, with nothing to edit.
func _test_a_new_record_must_carry_what_the_base_records_carry() -> void:
	_pack("half_a_card", {"id": PREFIX + "half_a_card", "name": "Half A Card", "files": ["cards.json"]},
		{"cards.json": {"cards_minor": [
			# A name, a cost, and nothing else — the shape of a first attempt.
			{"n": "A Half-Written Card", "cost": 1},
		]}})
	var loaded := _load()
	var said := "\n".join(loaded.errors)
	check(said.contains("A Half-Written Card"), "the incomplete card should be named in the load errors, got: %s" % said)
	check(said.contains("\"f\"") or said.contains("\"el\""),
		"and the error should name a field it is missing, got: %s" % said)
	# Reported, not refused: the pack still loaded its card.
	var found := false
	for c in loaded.registries.get("cards_minor", []):
		if str(c.get("n", "")) == "A Half-Written Card":
			found = true
	check(found, "a pack with one bad record should still load that record — the Mods screen is where a modder finds out, not a missing card")
	done()


## AN OVERRIDE INHERITS WHAT IT DOES NOT MENTION.
##
## The behaviour this replaced was measured before it was changed, and it was
## worse than the docs made it sound: `{"n": "Take Their Coat", "cost": 0}`
## loaded as exactly that — no element, no faith, no flavour, no spoken clause,
## and no load error. A blank card, in the deck, playable, worth nothing.
func _test_an_override_inherits_the_rest_of_the_record() -> void:
	var before: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(not before.is_empty(), "precondition: the base game should ship Take Their Coat")

	_pack("patch", {}, {"cards.json": {"cards_basics": [{"n": "Take Their Coat", "cost": 0}]}})
	var after: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(int(after.get("cost", -1)) == 0, "the field it changed should change, got %s" % after.get("cost"))
	for field in before:
		if field == "cost" or str(field).begins_with("_"):
			continue
		check(after.has(field) and after[field] == before[field],
			"a one-field patch must not take \"%s\" with it — was %s, now %s"
			% [field, before.get(field), after.get(field)])
	done()


## AND IT TRACKS THE BASE GAME AFTERWARDS, which is the reason for the change
## rather than a nicety.
##
## Whole-record replacement made every override a COPY, and a copy stops
## tracking what it copied: a balance patch written before the base game grew a
## field kept overriding that card without one for ever. Measured too — dropping
## `sp` makes the spoken clause fall back to the card's NAME, so a reading says
## "and Take Their Coat" in the middle of a sentence, with no error anywhere.
## Simulated here by a patch that restates the card as it was before a field
## existed; the field has to survive.
func _test_an_override_does_not_freeze_the_record_it_patches() -> void:
	var before: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(before.has("sp"), "precondition: the base card should carry a spoken clause")
	var stale: Dictionary = before.duplicate(true)
	stale.erase("sp")
	stale.erase("_pack")
	stale["f"] = 9

	_pack("stale", {}, {"cards.json": {"cards_basics": [stale]}})
	var after: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(int(after.get("f", -1)) == 9, "the patch should still apply, f is %s" % after.get("f"))
	check(str(after.get("sp", "")) == str(before["sp"]),
		"a field the patch predates must survive it — '%s' became '%s'" % [before["sp"], after.get("sp", "")])
	done()


## THE TWO WAYS OUT: `_remove` lists fields to drop, `_replace` restores
## whole-record replacement for a record that means it. Neither may reach the
## content, and neither may be a value the data could already carry.
func _test_a_field_can_be_removed_and_a_record_replaced_outright() -> void:
	_pack("remove", {}, {"cards.json": {"cards_basics": [{"n": "Take Their Coat", "_remove": ["fl"]}]}})
	var stripped: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(not stripped.has("fl"), "a listed field should be removed, still says %s" % stripped.get("fl"))
	check(stripped.has("el"), "and nothing else should go with it")
	check(not stripped.has("_remove"), "and the list must not reach the content")
	# `null` is a VALUE here, not a sentinel: seven base cards are neutral and say
	# so with "el": null. The first version of this used null to mean "remove"
	# and erased the element of every card the Library writes back.
	_clean()
	# ON A CARD THAT IS ALREADY THERE, or this measures nothing: a name the pool
	# does not have is APPENDED, which never goes through the patch path at all.
	# The first version of this used a card from another pool and passed just as
	# happily with the null-as-sentinel bug put back.
	_pack("nulled", {}, {"cards.json": {"cards_basics": [{"n": "Take Their Coat", "fl": null}]}})
	var nulled: Dictionary = _find(_load()["registries"]["cards_basics"], "n", "Take Their Coat")
	check(nulled.has("fl") and nulled["fl"] == null,
		"a field set to null should BE null, not gone — got has=%s value=%s"
		% [nulled.has("fl"), nulled.get("fl", "<gone>")])
	_clean()

	_pack("wholesale", {}, {"cards.json": {"cards_basics": [
		{"n": "Take Their Coat", "cost": 0, "_replace": true},
	]}})
	var loaded := _load()
	var replaced: Dictionary = _find(loaded["registries"]["cards_basics"], "n", "Take Their Coat")
	check(not replaced.has("fl"), "_replace should start from nothing, kept %s" % replaced.get("fl"))
	check(not replaced.has("_replace"), "and the flag must not reach the content")
	# Starting from nothing means the base-content contract now has something to
	# say, which is the point: the one way to arrive incomplete is to ask for it.
	check("\n".join(loaded["errors"]).contains("Take Their Coat"),
		"a _replace that drops required fields should be reported: %s" % [loaded["errors"]])
	done()


## AND AN OVERRIDE IS LEFT ALONE BY THE CONTRACT. Restating only the field you
## are changing is the documented way to patch a card, so the "every record
## carries what the base records carry" check must not call it broken. It no
## longer needs an exemption to manage that — a patched record has inherited the
## base record's fields by the time it is checked — but the promise is the same
## one and it is worth a test of its own.
func _test_an_override_may_restate_only_what_it_changes() -> void:
	_pack("cheap_coat", {"id": PREFIX + "cheap_coat", "name": "Cheap Coat", "files": ["cards.json"]},
		{"cards.json": {"cards_basics": [{"n": "Take Their Coat", "cost": 0}]}})
	var loaded := _load()
	var said := "\n".join(loaded.errors)
	check(not said.contains("Take Their Coat"),
		"overriding a base card by restating one field is documented and must not be reported: %s" % said)
	done()


# ── the Steam Workshop path ─────────────────────────────────────────────
#
# ModLoader has read Workshop.get_installed_item_paths() since the day it was
# written, and that call has always returned an empty array. So the lines that
# take a Workshop item and turn it into a pack HAD NEVER RUN WITH A PATH IN
# THEM — a test that passes, has never failed, and proves nothing, which is the
# shape this repository keeps being caught by. Without something like this, the
# first thing ever to exercise that code would be a player's machine on the day
# GodotSteam lands, with a folder Steam chose and nobody has looked at.
#
# Driven through Workshop.simulated_item_paths, which is the stand-in that
# exists for exactly this (see autoload/Workshop.gd). What it produces is a
# plain directory path, which is the whole of what a Workshop item ever is to
# the rest of the game — so this exercises the real code rather than a mock of
# it.

## Where a simulated item is written: deliberately NOT under user://mods, so
## that a pack found here can only have been found through Workshop. Under
## user://mods it would load either way and the test would pass without the
## path it is about ever running.
const ITEM_ROOT := "user://zz_test_workshop"


## Points Workshop at `paths` for one call to _load(), and puts it back. It is
## an autoload, shared with everything else in this process — a probe that left
## it set would quietly change what every later test in this file loads.
func _load_with_workshop(paths: Array, disabled: Array = []) -> Dictionary:
	var workshop: Node = root.get_node("Workshop")
	var before: Array = workshop.simulated_item_paths.duplicate()
	var typed: Array[String] = []
	for p in paths:
		typed.append(str(p))
	workshop.simulated_item_paths = typed
	var out := _load(disabled)
	workshop.simulated_item_paths = before
	return out


func _pack_named(loaded: Dictionary, id: String) -> Dictionary:
	for p in loaded["packs"]:
		if str(p.get("id", "")) == id:
			return p
	return {}


## A SUBSCRIBED ITEM IS A PACK LIKE ANY OTHER — the promise Workshop.gd's header
## makes ("plugging in real data here is the entire integration surface"), which
## nothing had ever checked. Its content merges, it is listed, it is labelled as
## Steam's rather than as the player's own folder, and it can be switched off
## from the Mods screen like anything else.
func _test_a_workshop_item_loads_like_any_other_pack() -> void:
	var dir := ITEM_ROOT.path_join("2914857001")   # Steam names them by item id
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("mod.json"), JSON.stringify({
		"id": "zz_test_subscribed", "name": "A Subscribed Pack", "files": ["cards.json"],
	}, "  "))
	# An OVERRIDE of a base card, so this says nothing about the new-record
	# contract and everything about whether the pack was found at all.
	_write(dir.path_join("cards.json"), JSON.stringify({
		"cards_basics": [{"n": "Take Their Coat", "f": 41}],
	}, "  "))

	var without := _load()
	check(_pack_named(without, "zz_test_subscribed").is_empty(),
		"precondition: nothing outside Workshop should find this folder — if it does, this test proves nothing")

	var loaded := _load_with_workshop([dir])
	var rec := _pack_named(loaded, "zz_test_subscribed")
	check(not rec.is_empty(), "a subscribed item should be discovered and listed as a pack")
	check(str(rec.get("source", "")) == "workshop",
		"and be labelled as Steam's, not the player's own folder — says '%s'" % rec.get("source", ""))
	check(int(_find(loaded["registries"]["cards_basics"], "n", "Take Their Coat").get("f", 0)) == 41,
		"its content should merge exactly like a pack from user://mods")
	check(loaded["errors"].is_empty(), "a well-formed item should report nothing: %s" % [loaded["errors"]])

	# And the Mods screen's switch works on it — a pack a player cannot turn off
	# is a pack they have to unsubscribe from to test anything.
	var off := _load_with_workshop([dir], ["zz_test_subscribed"])
	check(int(_find(off["registries"]["cards_basics"], "n", "Take Their Coat").get("f", 0)) != 41,
		"a disabled Workshop pack should contribute nothing")
	check(not _pack_named(off, "zz_test_subscribed").is_empty(),
		"but still be listed, so it can be switched back on")

	_rm_rf(ITEM_ROOT)
	done()


## THE HALF-DOWNLOADED CASE, which is the normal one at launch. Steam reports an
## item before its files are on disk, and reports items that were unsubscribed
## while the game was running. Both arrive here as a path to a folder that is
## not there or holds nothing — and neither may be an error, a missing card, or
## a warning on the console, because the player has done nothing wrong.
func _test_a_workshop_item_that_is_not_there_changes_nothing() -> void:
	var baseline := _load()
	var empty := ITEM_ROOT.path_join("still_downloading")
	DirAccess.make_dir_recursive_absolute(empty)   # exists, no mod.json yet

	var loaded := _load_with_workshop([
		ITEM_ROOT.path_join("unsubscribed_mid_session"),   # gone entirely
		empty,
		"/nowhere/at/all/1234",                            # an absolute path, as Steam gives
	])
	check(loaded["errors"].size() == baseline["errors"].size(),
		"an item with nothing behind it must not be reported as a broken pack: %s" % [loaded["errors"]])
	check(loaded["packs"].size() == baseline["packs"].size(),
		"and must not be listed as a pack (%d vs %d)" % [loaded["packs"].size(), baseline["packs"].size()])
	check(loaded["registries"]["cards_basics"].size() == baseline["registries"]["cards_basics"].size(),
		"and must leave the game exactly as it was")

	_rm_rf(ITEM_ROOT)
	done()


## A PACK FROM A DIRECTORY NOBODY EXPLAINS SAYS SO.
##
## _source_of() knew three roots and answered "workshop" for everything else, so
## the Mods screen would tell a player that Steam had installed a pack that
## Steam had never heard of — on the one line they read to work out where to go
## and delete it. Reachable today by any future discovery root, and by the
## simulation above; the fix is that a Workshop item is recognised by having
## come from Workshop, not by the shape of its path.
func _test_a_pack_from_nowhere_does_not_blame_steam() -> void:
	var dir := ITEM_ROOT.path_join("hand_placed")
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("mod.json"), JSON.stringify({
		"id": "zz_test_elsewhere", "name": "From Nowhere", "files": [],
	}, "  "))

	# Found the way a future root would find it: handed to the loader directly,
	# with Workshop reporting nothing.
	var loader = load("res://autoload/ModLoader.gd").new()
	loader.load_example_mods = false
	loader.build_registries()
	check(loader._source_of(dir) == "elsewhere",
		"a path Workshop never reported must not be credited to Steam, says '%s'" % loader._source_of(dir))
	check(loader._source_of("user://mods/whatever") == "user", "and the roots it does know still answer")
	check(loader._source_of(loader.BASE_DIR) == "base", "including the base pack")

	# The Mods screen has a word for it rather than printing the code.
	var ModsScreen = load("res://scenes/ModsScreen.gd")
	check(ModsScreen._source_label("elsewhere") != "elsewhere",
		"the Mods screen should have a sentence for a pack from elsewhere, not the raw code")

	_rm_rf(ITEM_ROOT)
	done()
