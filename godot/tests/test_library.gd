## Headless test for the Library's edit pipeline (CardEdits -> mod pack on
## disk -> ModLoader merge -> live Content).
##   godot --headless --path godot -s tests/test_library.gd
##
## The claim under test is the one that makes the Library trustworthy: an
## edit made in-game becomes a real mod pack, that pack is loaded by the
## ordinary mod path, and the edited value is what the game actually uses.
## Reverting has to put the base value back just as completely.
extends SceneTree

var failures: Array[String] = []
var content: Node
var edits: Node
var rules: Node


func _initialize() -> void:
	content = root.get_node("Content")
	edits = root.get_node("CardEdits")
	rules = root.get_node("Rules")
	await process_frame

	# Start from a clean slate so a leftover pack from a previous run (or a
	# real player's edits, if this is ever run against a live user dir)
	# doesn't make the assertions below lie.
	edits.revert_all()
	content.reload()

	_test_starts_clean()
	_test_edit_reaches_live_content()
	_test_edit_is_a_real_mod_pack()
	_test_generated_text_follows_the_edit()
	_test_revert_restores_base()
	_test_revert_all_removes_the_pack()

	edits.revert_all()
	content.reload()

	if failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func _base_restore() -> int:
	return int(content.get_card("Pour The Tea").get("f", -1))


func _test_starts_clean() -> void:
	check(edits.edit_count() == 0, "should start with no edits, had %d" % edits.edit_count())
	check(_base_restore() == 3, "Pour The Tea's base restore should be 3, got %d" % _base_restore())


func _test_edit_reaches_live_content() -> void:
	var c: Dictionary = content.get_card("Pour The Tea").duplicate(true)
	c["f"] = 99
	edits.set_card("cards_minor", c)
	content.reload()
	check(_base_restore() == 99, "after editing, live content should report 99, got %d" % _base_restore())
	check(edits.has_edit("cards_minor", "Pour The Tea"), "the card should be marked as edited")
	check(edits.edit_count() == 1, "exactly one edit expected, got %d" % edits.edit_count())


## The whole point of the design: this is not a private save format, it's a
## mod. Assert the on-disk shape a third party (or the Workshop) would see.
func _test_edit_is_a_real_mod_pack() -> void:
	var manifest_path: String = edits.PACK_DIR.path_join("mod.json")
	check(FileAccess.file_exists(manifest_path), "the pack should have a mod.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	var manifest = JSON.parse_string(f.get_as_text())
	f.close()
	check(typeof(manifest) == TYPE_DICTIONARY, "mod.json should parse as an object")
	if typeof(manifest) != TYPE_DICTIONARY:
		return
	check(manifest.get("id", "") == edits.PACK_ID, "manifest id should be %s" % edits.PACK_ID)
	check(int(manifest.get("priority", 0)) == edits.PRIORITY, "pack should carry its high priority so it wins over other mods")
	check(manifest.get("files", []).has("cards_minor.json"), "manifest should list the pool file it wrote")

	# And only the changed card is written — unedited cards must keep
	# tracking the base game rather than being frozen into the pack.
	var pool_path: String = edits.PACK_DIR.path_join("cards_minor.json")
	var pf := FileAccess.open(pool_path, FileAccess.READ)
	var doc = JSON.parse_string(pf.get_as_text())
	pf.close()
	check(doc["cards_minor"].size() == 1, "only the edited card should be written, got %d" % doc["cards_minor"].size())
	check(doc["cards_minor"][0]["n"] == "Pour The Tea", "the written card should be the edited one")
	check(not doc["cards_minor"][0].has("uid"), "a runtime uid must never be baked into a saved card")


## Card text is generated from mechanics, so an edit to a mechanical field
## has to change the printed text too — that's the invariant that keeps text
## and behaviour from disagreeing.
func _test_generated_text_follows_the_edit() -> void:
	var c: Dictionary = content.get_card("Pour The Tea").duplicate(true)
	c["draw"] = 3
	edits.set_card("cards_minor", c)
	content.reload()
	var text: String = rules.auto_text(content.get_card("Pour The Tea"))
	check(text.contains("three"), "generated text should mention drawing three, got: %s" % text)


func _test_revert_restores_base() -> void:
	edits.revert_card("cards_minor", "Pour The Tea")
	content.reload()
	check(_base_restore() == 3, "after revert, restore should be back to 3, got %d" % _base_restore())
	check(not edits.has_edit("cards_minor", "Pour The Tea"), "the card should no longer be marked edited")
	var text: String = rules.auto_text(content.get_card("Pour The Tea"))
	check(text.contains("one"), "reverted card should draw one again, got: %s" % text)


## With nothing edited the pack should stop existing entirely, rather than
## lingering as an empty mod that still shows up in the loaded-packs count.
func _test_revert_all_removes_the_pack() -> void:
	var c: Dictionary = content.get_card("Ask Them Why").duplicate(true)
	c["cost"] = 3
	edits.set_card("cards_minor", c)
	check(FileAccess.file_exists(edits.PACK_DIR.path_join("mod.json")), "pack should exist while an edit is held")
	edits.revert_all()
	check(not FileAccess.file_exists(edits.PACK_DIR.path_join("mod.json")), "manifest should be gone once all edits are reverted")
	check(not FileAccess.file_exists(edits.PACK_DIR.path_join("cards_minor.json")), "pool file should be gone too")
	content.reload()
	check(int(content.get_card("Ask Them Why").get("cost", -1)) == 1, "base cost should be restored after revert_all")
