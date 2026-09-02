## Soak test: plays COMPLETE runs, start to finish, many times.
##   godot --headless --path godot -s tests/test_soak.gd [runs]
##
## Everything else tests a slice. test_run.gd drives one encounter to
## resolution and stops; test_scenes.gd builds each screen against a state it
## was handed. Nothing played a whole run — so night rollover, the boss at
## night 2 step 7, shop purchases, elite twists, relic rolls, burning a card
## and end_run() had never all happened in sequence, and a state machine is
## exactly the kind of thing whose bugs only appear in sequence.
##
## This plays greedily and randomly (a real player is smarter, which is fine —
## the point is coverage, not skill) and checks INVARIANTS after every single
## action rather than only at the end, so a violation is reported at the step
## that caused it instead of wherever it eventually surfaced.
##
## Invariants:
##   - coin, faith and mended never go negative;
##   - the deck is never empty (burning must not strip it bare — you cannot
##     play a run with no cards);
##   - the screen is always one Nav knows how to route;
##   - a run always terminates, and terminates at "over".
##
## It also prints an outcome distribution, which is a cheap sanity read on
## progression: if every run ended in "failed" at night 0 something is wrong
## with the game, not with the test.
extends SceneTree

## Every screen the state machine may legitimately be in.
const SCREENS := ["sign", "pick", "map", "read", "over"]

## Hard ceiling on actions per run. A full run is 24 knocks and change; if one
## takes more than this, it is looping rather than progressing, and saying so
## is far more useful than hanging the suite.
const MAX_ACTIONS := 4000

var failures: Array[String] = []
var content: Node
var run: Node
var rng := RandomNumberGenerator.new()

## Times a reading was reached with nothing laid and nothing affordable — the
## state where READ IT is inert. See _do_read().
var stuck := 0


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	await process_frame
	content.reload()

	var n := 40
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		n = int(args[0])
	# Fixed seed: a soak test that fails only sometimes is a soak test nobody
	# trusts. Pass a count to widen coverage; the sequence stays reproducible.
	rng.seed = 20260902

	# energy=<n> soaks at a non-default energy budget. The two gameplay knobs
	# in Settings are player-adjustable down to 1, and a low budget is exactly
	# what makes "nothing in hand is affordable" reachable — so the interesting
	# question is not whether the default is safe but whether the whole
	# supported range is.
	var settings: Node = root.get_node("Settings")
	var restore_energy = settings.get_value("start_energy")
	for a in args:
		if a.begins_with("energy="):
			settings.set_value("start_energy", int(a.substr(7)))
			print("  (soaking at start_energy=%s)" % settings.get_value("start_energy"))

	var outcomes := {}
	var total_actions := 0
	var t0 := Time.get_ticks_msec()
	for i in n:
		var res := _play_one_run(i)
		if not failures.is_empty():
			break
		outcomes[res["how"]] = int(outcomes.get(res["how"], 0)) + 1
		total_actions += int(res["actions"])

	settings.set_value("start_energy", restore_energy)
	if failures.is_empty():
		print("ALL PASS — %d complete runs, %d actions, %dms" % [n, total_actions, Time.get_ticks_msec() - t0])
		print("  outcomes: ", outcomes)
		print("  readings with nothing affordable and nothing laid: %d" % stuck)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func fail(label: String) -> void:
	if failures.size() < 8:   # enough to see the pattern, not a wall of text
		failures.append(label)


## Plays one run from sign-select to the end screen.
func _play_one_run(index: int) -> Dictionary:
	run.state = run.fresh()
	run.pick_reader(rng.randi_range(0, content.readers.size() - 1))

	var actions := 0
	while actions < MAX_ACTIONS:
		actions += 1
		# A won or lost fight leaves screen == "read" and fills state.res; the
		# result screen is what the player actually sees. Mirrors Nav's own
		# rule — reading `screen` alone gets you an infinite loop, which is how
		# this test first "failed".
		if str(run.state.get("screen", "")) == "read" and not run.state.get("res", {}).is_empty():
			run.after_res()
			continue
		var screen := str(run.state.get("screen", ""))
		_check_invariants(index, actions, screen)
		if not failures.is_empty():
			break
		match screen:
			"over":
				return {"how": str(run.state.get("over", {}).get("head", "?")), "actions": actions}
			"pick":
				_do_pick()
			"map":
				_do_map()
			"read":
				_do_read()
			_:
				fail("run %d step %d: unroutable screen '%s'" % [index, actions, screen])
				break
	if failures.is_empty():
		fail("run %d never reached 'over' in %d actions — the state machine is looping" % [index, MAX_ACTIONS])
	return {"how": "unfinished", "actions": actions}


func _check_invariants(index: int, step: int, screen: String) -> void:
	var st: Dictionary = run.state
	var where := "run %d step %d (%s)" % [index, step, screen]
	if not SCREENS.has(screen):
		fail("%s: screen is not one Nav can route" % where)
	for key in ["coin", "faith", "mended"]:
		if int(st.get(key, 0)) < 0:
			fail("%s: %s went negative (%s)" % [where, key, st.get(key)])
	# A deck stripped bare by burning is unplayable — draw_to() would deal an
	# empty hand every reading and the run could never end except by running
	# out of readings.
	if screen != "over" and st.get("deck", []).is_empty():
		fail("%s: deck is empty — burning left nothing to play" % where)
	var f = st.get("f", {})
	if screen == "read" and typeof(f) == TYPE_DICTIONARY and not f.is_empty():
		if int(f.get("energy", 0)) < 0:
			fail("%s: energy went negative (%s)" % [where, f.get("energy")])
		if int(f.get("hp", 0)) > int(f.get("max", 0)):
			fail("%s: composure %s exceeds max %s" % [where, f.get("hp"), f.get("max")])
		if int(f.get("turn", 0)) > int(f.get("turns", 0)) + 1:
			fail("%s: reading %s past the sitter's %s" % [where, f.get("turn"), f.get("turns")])


## Take a random affordable option, or skip. Exercises gifts, rewards, the
## shop (including burning) and events.
func _do_pick() -> void:
	var pick: Dictionary = run.state["pick"]
	var opts: Array = pick.get("opts", [])
	var affordable: Array[int] = []
	for i in opts.size():
		if int(opts[i].get("cost", 0)) <= int(run.state["coin"]):
			affordable.append(i)
	if affordable.is_empty() or (pick.get("skippable", false) and rng.randf() < 0.3):
		if pick.get("skippable", false):
			run.skip_pick()
		else:
			# A non-skippable pick with nothing affordable would deadlock the
			# run; the gift screen is the only non-skippable one and its
			# options are free, so this should be unreachable.
			fail("a non-skippable pick offered nothing affordable")
			run.state["screen"] = "over"
		return
	run.take_pick(affordable[rng.randi_range(0, affordable.size() - 1)])


func _do_map() -> void:
	var opts: Array = run.state["options"]
	if opts.is_empty():
		fail("the map offered no options at all")
		run.state["screen"] = "over"
		return
	run.choose(rng.randi_range(0, opts.size() - 1))


## Lay whatever fits, then read. Not clever — the point is that the engine
## survives a full run, not that it is beaten.
func _do_read() -> void:
	var f: Dictionary = run.state["f"]
	var guard := 0
	while guard < 30:
		guard += 1
		var playable: Array = f["hand"].filter(func(c): return int(c.get("cost", 0)) <= int(f["energy"]))
		if playable.is_empty():
			break
		run.lay_card(playable[0]["uid"])
		if str(run.state.get("screen", "")) != "read" or not run.state.get("res", {}).is_empty():
			return   # laying can end the fight outright
		f = run.state["f"]

	# Nothing laid and nothing affordable. This used to be a dead end: READ IT
	# returned early on an empty line (as the prototype does) and there was no
	# other legal action, so the run could not continue. It is reachable — this
	# soak hits it several times per 60 runs at start_energy=1, a supported
	# setting — so Run.can_read() now lifts the guard exactly here.
	#
	# Assert the way out actually works, rather than stepping around it: the
	# reading must resolve, which means either the fight ends or the turn
	# advances. Without the fix this fails instead of silently looping.
	if f["cross"].is_empty():
		stuck += 1
		var turn_before := int(f.get("turn", 0))
		if not run.can_read():
			fail("with nothing affordable and nothing laid, READ IT is still refused — soft-lock")
			return
		run.read_it()
		var after = run.state.get("f", {})
		var ended: bool = not run.state.get("res", {}).is_empty() or str(run.state.get("screen", "")) != "read"
		if not ended and int(after.get("turn", 0)) <= turn_before:
			fail("reading an empty line did not advance the reading (turn stayed %d)" % turn_before)
		return
	run.read_it()
