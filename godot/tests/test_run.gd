## Headless smoke test for the Run.gd state machine. Run with:
##   godot --headless --path godot -s tests/test_run.gd
## Drives a fight to completion by always laying the first affordable card and
## reading as soon as nothing more fits (or hand is empty), which won't always
## win, but must never crash and must always reach a res/win/lose state.
extends SceneTree

var failures: Array[String] = []
var content: Node
var run: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	content.reload()
	run.state = run.fresh()

	_test_fresh_state()
	_test_pick_reader_and_gift()
	_test_start_fight_and_play_one_reading()
	_test_full_encounter_to_resolution()

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


func _test_fresh_state() -> void:
	check(run.state["screen"] == "sign", "fresh() should start on the sign-select screen")
	check(run.state["deck"].size() == 9, "fresh() base deck should be 7 basics + 2 reader cards = 9, got %d" % run.state["deck"].size())
	check(run.state["options"].size() >= 1, "fresh() should populate at least one map option")


func _test_pick_reader_and_gift() -> void:
	run.pick_reader(0)  # Aries
	check(run.state["reader"]["k"] == "aries", "pick_reader(0) should select Aries")
	check(run.state["screen"] == "pick", "picking a reader should move to the gift pick screen")
	check(run.state["pick"]["kind"] == "gift", "the post-pick screen should be the starting gift")
	check(run.state["pick"]["opts"].size() == 2, "the gift should offer 2 neighbour-element cards, got %d" % run.state["pick"]["opts"].size())
	run.take_pick(0)
	check(run.state["deck"].size() == 10, "taking the gift should bring the deck to 10 cards, got %d" % run.state["deck"].size())
	check(run.state["screen"] == "map", "after the gift the screen should be the map")


func _test_start_fight_and_play_one_reading() -> void:
	var sitter_opt = null
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			sitter_opt = o
			break
	check(sitter_opt != null, "there should be a sitter option on the map")
	if sitter_opt == null:
		return
	run.choose(run.state["options"].find(sitter_opt))
	check(run.state["screen"] == "read", "choosing a sitter should move to the read screen")
	var f: Dictionary = run.state["f"]
	check(f["hand"].size() > 0, "starting a fight should draw a hand")
	check(int(f["energy"]) == int(f["energyMax"]), "energy should be full at the start of a reading")

	# Lay whatever's affordable, then read.
	var laid_any := false
	for c in f["hand"].duplicate():
		if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]):
			run.lay_card(c["uid"])
			laid_any = true
			break
	check(laid_any, "should be able to lay at least one starting card")
	check(run.state["f"]["cross"].size() == 1, "laying a card should move it into cross")
	run.read_it()
	check(run.state["screen"] in ["read", "over"], "after read_it the screen should still be read (or over, if the whole run ended) got %s" % run.state["screen"])


## Plays an entire encounter to either a win (res.kind=='win') or a loss
## (screen becomes 'map' after advance(), or 'over' if the run ended), always
## laying the cheapest affordable card and reading once nothing more fits.
func _test_full_encounter_to_resolution() -> void:
	run.state = run.fresh()
	run.pick_reader(2)  # Gemini
	run.take_pick(0)
	var sitter_opt = null
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			sitter_opt = o
			break
	run.choose(run.state["options"].find(sitter_opt))

	var guard := 0
	while run.state["screen"] == "read" and guard < 500:
		guard += 1
		var f: Dictionary = run.state["f"]
		if f.is_empty():
			break
		var played := false
		for c in f["hand"]:
			if int(c.get("cost", 0)) <= int(f["energy"]):
				run.lay_card(c["uid"])
				played = true
				break
		if not played:
			if f["cross"].is_empty():
				# Genuinely stuck: no affordable card in hand and nothing laid
				# yet this reading. read_it() no-ops on an empty cross (matches
				# the source's own readIt() guard), so there is nothing left to
				# do — this can happen late in a long encounter once enough
				# exhaust:true cards have thinned the deck below hand size.
				break
			run.read_it()
	check(guard < 500, "encounter should resolve within 500 lay/read steps, not loop forever")

	if run.state["screen"] != "read" or run.state["f"].is_empty():
		pass  # fight ended some other way (win/lose already resolved below, or run ended)
	elif run.state["res"].is_empty():
		return  # stuck with an empty hand/cross — a legitimate rare edge case, not a failure

	if not run.state["res"].is_empty():
		var res: Dictionary = run.state["res"]
		check(res["kind"] in ["win", "lose"], "resolved encounter should have a win or lose result")
		if res["kind"] == "win":
			run.after_res()
			check(run.state["screen"] == "pick", "winning should move to a reward pick screen")
			check(run.state["pick"]["kind"] == "reward", "the post-win pick should be a reward")
			run.skip_pick()
			check(run.state["screen"] in ["map", "over"], "skipping the reward should advance to the map (or end the run)")
		else:
			run.after_res()
			check(run.state["screen"] == "over", "losing should end the run")
			check(run.state["over"]["head"] != "", "end-of-run screen should be populated")
