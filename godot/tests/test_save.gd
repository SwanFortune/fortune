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
##     half-restored;
##   - NO ACTION CHANGES THE RUN WITHOUT ARMING A SAVE. Everything above tests
##     that a save which was written comes back correctly; none of it tests
##     that one gets written in the first place. Autosaving is signal-driven
##     (Run.state_changed -> a dirty flag -> one write per frame), so a Run
##     method that mutates state and forgets to emit loses the player that
##     action silently, and only on a crash or a quit — the worst possible
##     time to find out;
##   - A CONTENT RELOAD REACHES THE RUN IN PROGRESS. Everything above is about
##     a save being read; this is about the live Run.state, which holds copies
##     of content records and does not update itself.
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
	"_test_every_action_marks_the_run_dirty",
	"_test_a_content_reload_reaches_a_live_run",
	"_test_quitting_flushes_the_last_action",
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


## Plays a whole run and, after EVERY action, checks that a state which
## actually changed also armed a save.
##
## The check is exact rather than approximate: the state's own hash before and
## after. If it moved, Save._dirty must be true; if it did not move, nothing is
## claimed either way (a no-op action is allowed to arm a save harmlessly).
##
## This is the half of persistence the round-trip tests cannot see. They all
## write the save themselves — save._write() — and then read it back, so every
## one of them would pass on a build where state_changed was never emitted at
## all and the game autosaved nothing.
func _test_every_action_marks_the_run_dirty() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	var checked := 0

	for attempt in 3:
		run.state = run.fresh()
		_act("pick_reader", func(): run.pick_reader(rng.randi_range(0, content.readers.size() - 1)))
		var guard := 0
		while str(run.state.get("screen", "")) != "over" and guard < 900:
			guard += 1
			checked += 1
			if str(run.state.get("screen", "")) == "read" and not run.state.get("res", {}).is_empty():
				_act("after_res", func(): run.after_res())
				continue
			match str(run.state.get("screen", "")):
				"pick": _drive_pick(rng)
				"map": _act("choose", func(): run.choose(rng.randi_range(0, run.state["options"].size() - 1)))
				"read": _drive_read()
				_: break
		if not failures.is_empty():
			break

	check(checked > 200, "the driver should have exercised a few hundred actions, did %d" % checked)
	save.clear()
	done("_test_every_action_marks_the_run_dirty")


## Runs one action and reports it if the state moved without arming a save.
func _act(label: String, action: Callable) -> void:
	save._dirty = false
	var before: int = run.state.hash()
	action.call()
	var after: int = run.state.hash()
	if before != after and not save._dirty:
		check(false, "%s changed the run without emitting state_changed — the action would be lost on a crash" % label)


func _drive_pick(rng: RandomNumberGenerator) -> void:
	var pick: Dictionary = run.state["pick"]
	var opts: Array = pick.get("opts", [])
	var affordable: Array[int] = []
	for i in opts.size():
		if int(opts[i].get("cost", 0)) <= int(run.state["coin"]):
			affordable.append(i)
	if affordable.is_empty() or (pick.get("skippable", false) and rng.randf() < 0.3):
		if pick.get("skippable", false):
			_act("skip_pick", func(): run.skip_pick())
		else:
			run.state["screen"] = "over"
		return
	var i: int = affordable[rng.randi_range(0, affordable.size() - 1)]
	_act("take_pick", func(): run.take_pick(i))


func _drive_read() -> void:
	var f: Dictionary = run.state["f"]
	var playable: Array = f["hand"].filter(func(c): return int(c.get("cost", 0)) <= int(f["energy"]))
	if not playable.is_empty():
		var card_uid: String = playable[0]["uid"]
		_act("lay_card", func(): run.lay_card(card_uid))
		return
	if run.can_read():
		_act("read_it", func(): run.read_it())
	else:
		run.state["screen"] = "over"


## Editing a card while a run is in progress has to reach the deck.
##
## Run.state holds COPIES of content records, so reloading the registries does
## not touch them. The Mods screen knew that and put the run through Save to
## re-resolve it; the Library did not, so a card retuned there changed the
## registry, left the deck holding the old numbers, and the player watched their
## edit do nothing for the rest of the night. Both now get it from
## Content.reloaded, and this is the assertion that keeps it.
func _test_a_content_reload_reaches_a_live_run() -> void:
	var edits: Node = root.get_node("CardEdits")
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)

	var card_name := str(run.state["deck"][0]["n"])
	var before := int(run.state["deck"][0].get("f", 0))
	var pool := ""
	for p in ["cards_basics", "cards_chroma", "cards_minor", "cards_arcana"]:
		for c in content.registries.get(p, []):
			if str(c.get("n", "")) == card_name:
				pool = p
	check(pool != "", "the starting deck's first card should be in a known pool")
	if pool == "":
		done("_test_a_content_reload_reaches_a_live_run")
		return

	var edited: Dictionary = content.get_card(card_name).duplicate(true)
	edited.erase("uid")
	edited["f"] = before + 41
	edits.set_card(pool, edited)
	# Exactly what a screen does after an edit, and nothing else — the point is
	# that this one call is now enough.
	content.reload()

	check(int(content.get_card(card_name).get("f", 0)) == before + 41,
		"precondition: the registry should carry the edit")
	var in_deck := 0
	for c in run.state["deck"]:
		if str(c.get("n", "")) == card_name:
			in_deck = int(c.get("f", 0))
			break
	check(in_deck == before + 41,
		"the edit should have reached the deck in play (%d, expected %d)" % [in_deck, before + 41])

	# The cards keep their run identity through the re-resolution — a deck that
	# came back with new uids would break the hand, which addresses cards by uid.
	for c in run.state["deck"]:
		check(str(c.get("uid", "")) != "", "every card in the re-resolved deck should keep a uid")

	edits.revert_all()
	content.reload()
	check(int(run.state["deck"][0].get("f", 0)) == before, "reverting should reach the run too")
	save.clear()
	done("_test_a_content_reload_reaches_a_live_run")


## The last action before a quit must not be the one that gets lost.
##
## Autosaving coalesces through a dirty flag and writes once a frame (see
## _process), which is right — state_changed fires on every card laid — but it
## means there is always a window where the newest action is in memory only. A
## player who lays a card and immediately closes the window is squarely in that
## window, and it is the least forgivable moment to drop an action.
func _test_quitting_flushes_the_last_action() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	save.clear()
	check(not save.has_save(), "precondition: no save on disk")

	save._dirty = true
	save._notification(Node.NOTIFICATION_EXIT_TREE)
	check(save.has_save(), "leaving the tree with an unwritten action should flush it to disk")

	# ...and it is the real run, not an empty file. Compared on the reader key
	# rather than the night: peek() reports night and step 1-BASED for display,
	# while the state counts them from 0.
	var peeked: Dictionary = save.peek()
	check(str(peeked.get("reader", "")) == str(run.state.get("reader", {}).get("k", "")),
		"the flushed save should describe the live run, got %s" % [peeked])
	save.clear()
	done("_test_quitting_flushes_the_last_action")
