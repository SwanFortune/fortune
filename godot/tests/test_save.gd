## Headless test for save/resume.
##   godot --headless --path godot -s tests/test_save.gd
##
## The guarantees under test:
##   - a run round-trips: mid-fight, mid-pick and on the map, with card
##     identity (uid) and pile membership intact;
##   - numbers come back as numbers — the specific reason this uses store_var
##     rather than JSON, which has no integer type and would turn every hp and
##     coin into a float that renders as "5.0";
##   - content is re-resolved on load, so a card retuned in the Library or by a
##     mod reaches a run already in progress, and a card that no longer exists
##     is dropped rather than kept as a husk;
##   - a save is not left behind for a state that is not a run (the sign-select
##     screen before one starts, the "over" screen after one ends), because
##     CONTINUE must never drop the player into a finished run;
##   - a corrupt or version-skewed file is refused outright rather than
##     half-restored.
##
## Autoloads are fetched via get_node() — see the note at the top of
## tests/test_rules.gd for why the bare global names don't resolve here.
extends SceneTree

const TESTS := [
	"_test_roundtrip_on_map",
	"_test_roundtrip_mid_fight",
	"_test_numbers_stay_numbers",
	"_test_content_is_re_resolved",
	"_test_missing_card_is_dropped",
	"_test_no_save_for_a_non_run",
	"_test_corrupt_save_is_refused",
	"_test_peek",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var run: Node
var save: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	save = root.get_node("Save")
	# Run._ready() sets state = fresh() on the first process frame and would
	# clobber whatever a test just built. Wait it out up front.
	await process_frame
	content.reload()

	for t in TESTS:
		save.clear()
		call(t)
		# A GDScript runtime error aborts the function but sets no exit code,
		# so a test that died half-way would otherwise report as passing.
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)
	save.clear()

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


## Puts a run on the map with a reader chosen and the gift taken.
func _a_run_on_the_map() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)


## Puts a run mid-reading with a card or two already laid.
func _a_run_mid_fight() -> void:
	_a_run_on_the_map()
	var idx := -1
	for i in run.state["options"].size():
		if run.state["options"][i]["kind"] in ["sitter", "elite"]:
			idx = i
			break
	run.choose(idx)
	var f: Dictionary = run.state["f"]
	for c in f["hand"].duplicate():
		if int(c.get("cost", 0)) <= int(f["energy"]):
			run.lay_card(c["uid"])
			break


func _test_roundtrip_on_map() -> void:
	_a_run_on_the_map()
	var before: Dictionary = run.state.duplicate(true)
	save._write()
	run.state = run.fresh()  # wipe, as closing and reopening the game would
	var res: Dictionary = save.restore()
	check(res.get("ok", false), "restoring a map-screen run should succeed (%s)" % save.last_error)
	check(run.state["screen"] == "map", "screen should come back as map, got '%s'" % run.state["screen"])
	check(run.state["deck"].size() == before["deck"].size(),
		"deck size should survive: %d vs %d" % [run.state["deck"].size(), before["deck"].size()])
	check(str(run.state["reader"]["k"]) == str(before["reader"]["k"]), "reader should survive")
	check(run.state["options"].size() == before["options"].size(), "the night's options should survive")
	done("_test_roundtrip_on_map")


func _test_roundtrip_mid_fight() -> void:
	_a_run_mid_fight()
	var f_before: Dictionary = run.state["f"].duplicate(true)
	check(f_before["cross"].size() > 0, "setup should have laid at least one card")
	var laid_uid: String = str(f_before["cross"][0]["uid"])
	save._write()
	run.state = run.fresh()
	var res: Dictionary = save.restore()
	check(res.get("ok", false), "restoring a mid-fight run should succeed (%s)" % save.last_error)

	var f: Dictionary = run.state["f"]
	check(run.state["screen"] == "read", "screen should come back as read, got '%s'" % run.state["screen"])
	check(f["cross"].size() == f_before["cross"].size(), "the line being spoken should survive")
	check(str(f["cross"][0]["uid"]) == laid_uid, "a laid card keeps its uid, got '%s'" % f["cross"][0]["uid"])
	for pile in ["hand", "draw", "disc", "gone"]:
		check(f[pile].size() == f_before[pile].size(),
			"%s should survive: %d vs %d" % [pile, f[pile].size(), f_before[pile].size()])
	check(str(f["sitter"]["name"]) == str(f_before["sitter"]["name"]), "the sitter should survive")
	check(str(f["quirk"]["k"]) == str(f_before["quirk"]["k"]), "the sitter's sign should survive")
	check(not f["job"].is_empty(), "the sitter's job should be resolved again on load")
	done("_test_roundtrip_mid_fight")


## The whole reason this uses store_var and not JSON.
func _test_numbers_stay_numbers() -> void:
	_a_run_mid_fight()
	run.state["coin"] = 7
	run.state["f"]["hp"] = 11
	save._write()
	run.state = run.fresh()
	save.restore()
	check(typeof(run.state["coin"]) == TYPE_INT, "coin should come back an int, got %s" % type_string(typeof(run.state["coin"])))
	check(typeof(run.state["f"]["hp"]) == TYPE_INT, "hp should come back an int, got %s" % type_string(typeof(run.state["f"]["hp"])))
	check(str(run.state["coin"]) == "7", "an int must not render as '7.0', got '%s'" % run.state["coin"])
	done("_test_numbers_stay_numbers")


## A run in progress must see content as it is NOW, not as it was when the run
## started — otherwise a card retuned in the Library, or a mod pack updated,
## would never reach the deck the player is actually holding.
func _test_content_is_re_resolved() -> void:
	_a_run_on_the_map()
	var name := str(run.state["deck"][0]["n"])
	save._write()

	# Stand in for an edit landing between saving and loading.
	var original: int = int(content.get_card(name).get("f", 0))
	content.get_card(name)["f"] = original + 99
	run.state = run.fresh()
	save.restore()
	content.get_card(name)["f"] = original  # put it back for the tests after this one

	var found := 0
	for c in run.state["deck"]:
		if str(c["n"]) == name:
			found += 1
			check(int(c["f"]) == original + 99,
				"a card changed since the save should come back changed, got f=%s" % c["f"])
	check(found > 0, "the edited card should still be in the restored deck")
	done("_test_content_is_re_resolved")


## A card from a pack the player has since switched off cannot be revived, so
## it is dropped and counted rather than restored as a husk that would then
## crash or score as nothing.
func _test_missing_card_is_dropped() -> void:
	_a_run_on_the_map()
	var deck_size: int = run.state["deck"].size()
	run.state["deck"].append({"n": "A Card From A Pack You Removed", "uid": "ghost", "f": 3, "cost": 1})
	save._write()
	run.state = run.fresh()
	var res: Dictionary = save.restore()
	check(res.get("ok", false), "a save with an unresolvable card should still load")
	check(int(res.get("dropped", 0)) == 1, "the missing card should be counted as dropped, got %s" % res.get("dropped", 0))
	check(run.state["deck"].size() == deck_size, "the rest of the deck should be untouched")
	for c in run.state["deck"]:
		check(str(c.get("uid", "")) != "ghost", "the unresolvable card should not survive")
	done("_test_missing_card_is_dropped")


## CONTINUE must never drop the player back into a finished run, or into the
## sign-select screen of a run that never started.
func _test_no_save_for_a_non_run() -> void:
	_a_run_on_the_map()
	save._write()
	check(save.has_save(), "a run on the map should be saved")

	run.state = run.fresh()  # screen == "sign"
	save._write()
	check(not save.has_save(), "the sign-select screen is not a run and should clear the save")

	_a_run_on_the_map()
	save._write()
	run.end_run("done")     # screen == "over"
	save._write()
	check(not save.has_save(), "a finished run should clear the save")
	done("_test_no_save_for_a_non_run")


func _test_corrupt_save_is_refused() -> void:
	# Godot's own get_var() prints an ERROR line when handed bytes that are not
	# a variant. That line is the engine noticing exactly what this test is
	# checking for, not a failure — say so, because the scene sweep greps
	# output for "ERROR" and a stray one here would look alarming.
	print("--- the next ERROR line is expected: feeding get_var() a corrupt file on purpose ---")
	var f := FileAccess.open(save.PATH, FileAccess.WRITE)
	f.store_string("this is not a Godot variant")
	f.close()
	_a_run_on_the_map()
	var expected: Dictionary = run.state.duplicate(true)
	var res: Dictionary = save.restore()
	check(not res.get("ok", true), "a corrupt save should be refused")
	check(save.last_error != "", "a refusal should say why")
	check(str(run.state["screen"]) == str(expected["screen"]),
		"a refused restore must leave the live run untouched")

	# And a save written by a build whose shape this one cannot read.
	var g := FileAccess.open(save.PATH, FileAccess.WRITE)
	g.store_var({"version": save.VERSION + 1, "state": {"screen": "map"}}, false)
	g.close()
	check(not save.restore().get("ok", true), "a future-version save should be refused")
	done("_test_corrupt_save_is_refused")


func _test_peek() -> void:
	check(save.peek().is_empty(), "peek with no save should be empty")
	_a_run_on_the_map()
	run.state["faith"] = 42
	save._write()
	var p: Dictionary = save.peek()
	check(not p.is_empty(), "peek should describe an existing save")
	check(int(p["faith"]) == 42, "peek should report faith, got %s" % p.get("faith"))
	check(int(p["night"]) == 1, "peek should report night 1-based, got %s" % p.get("night"))
	check(str(p["reader"]) != "", "peek should report which reader")
	check(int(p["saved_at"]) > 0, "peek should report when it was saved")
	done("_test_peek")
