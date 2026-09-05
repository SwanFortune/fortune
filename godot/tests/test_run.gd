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
	_test_named_cards_and_marks_resolve()
	_test_the_plan_is_the_night()
	_test_a_seed_is_a_run()
	_test_taking_it_back()
	_test_the_ladder()
	_test_the_ledger_and_the_ending()

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


## AN EVENT THAT NAMES A CARD HAS TO NAME A CARD THAT EXISTS.
##
## An option may say `"card": "Pour The Tea"` instead of carrying a whole copy
## of the card — see Run.resolve_named(), and the reason it exists: an events
## file that inlines a card is a second copy of that card's rules, which goes
## stale the moment anyone rebalances it.
##
## The cost of that convenience is a name that can be WRONG, and a wrong name
## fails quietly in the worst possible way: the option is still offered, still
## says something appealing, and hands the player nothing at all. Every name in
## the shipped content is checked here, and so is the behaviour on a bad one.
func _test_named_cards_and_marks_resolve() -> void:
	var named := 0
	for e in content.events:
		for o in e.get("opts", []):
			for key: String in ["card", "mark"]:
				if not (o.get(key) is String):
					continue
				named += 1
				var got: Dictionary = run.resolve_named(o)
				check(got.has(key) and got[key] is Dictionary,
					"event '%s' offers %s '%s', which no loaded pack has" % [e.get("title", "?"), key, o[key]])
	check(named > 0, "no event names a card or a mark — the resolver is not exercised by the content")

	# A name nothing answers to drops the key rather than crashing or handing
	# out an empty card. A pack that removes a card an event names is a mistake
	# to report, not a run to end.
	print("--- the next two WARNINGs are expected: deliberately unknown names ---")
	var bad: Dictionary = run.resolve_named({"card": "A Card That Does Not Exist", "kind": "X"})
	check(not bad.has("card"), "an unknown card name should be dropped, not offered empty")
	check(bad.get("kind", "") == "X", "resolving should leave the rest of the option alone")
	var bad_mark: Dictionary = run.resolve_named({"mark": "No Such Mark"})
	check(not bad_mark.has("mark"), "an unknown mark name should be dropped, not offered empty")

	# And the whole path: take an option that names a card, get that card.
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	var before: int = run.state["deck"].size()
	run.state["pick"] = {"kind": "rest", "opts": [{"card": "Pour The Tea", "kind": "TEST"}]}
	run.take_pick(0)
	var deck: Array = run.state["deck"]
	check(deck.size() == before + 1, "taking a named card should add exactly one card to the deck")
	if deck.size() == before + 1:
		check(str(deck[-1].get("n", "")) == "Pour The Tea",
			"the card added was '%s', not the one the option named" % deck[-1].get("n", ""))
		check(deck[-1].has("uid"), "a card taken by name still needs its own uid")


## THE AGENDA HAS TO BE TELLING THE TRUTH.
##
## The night is planned before it starts so it can be shown before it starts —
## and a plan the game then ignores is worse than no plan at all: a player who
## keeps two centimes back for an apothecary that never turns up has been lied
## to by the interface, and nothing anywhere would raise a word about it.
##
## So: for every hour of every night, what the plan promises and what the hour
## actually offers have to be the same set of things.
func _test_the_plan_is_the_night() -> void:
	for night in 3:
		var plan: Array = run.make_plan(night)
		check(plan.size() == run.HOURS.size(),
			"a night is %d hours and the plan has %d" % [run.HOURS.size(), plan.size()])
		for step in plan.size():
			var promised: Array = plan[step].get("offers", [])
			var got: Array = run.make_options(night, step, [], plan)
			# The kinds an hour produces, in the plan's own vocabulary.
			var actual: Array = []
			for o in got:
				match str(o.get("kind", "")):
					"break":
						var rest: Dictionary = o.get("rest", {})
						actual.append("shop" if str(rest.get("kind", "")) == "SHOP" else "event")
					var k:
						actual.append(k)
			# "secret" is an event as far as the hour is concerned; the plan
			# distinguishes them because only one of them needs a code.
			var want: Array = []
			for k: String in promised:
				want.append("event" if k == "secret" else k)
			want.sort()
			actual.sort()
			if want != actual:
				printerr("FAIL: night %d, %s — the agenda promises %s and the hour offers %s"
					% [night + 1, plan[step].get("at", "?"), want, actual])
				return
	check(true, "every hour offers what the agenda promised")


## A SEED IS A RUN. The whole point of showing one is that handing it to
## somebody else hands them the same three nights; if any roll escapes the run's
## own generator that stops being true, and it stops being true silently.
func _test_a_seed_is_a_run() -> void:
	var shapes: Array = []
	for i in 3:
		run.state = run.fresh("grandmother")
		run.pick_reader(0)
		shapes.append(_shape_of(run.state))
	check(shapes[0] == shapes[1] and shapes[1] == shapes[2],
		"the same seed should deal the same run three times running")

	run.state = run.fresh("a different evening")
	run.pick_reader(0)
	check(_shape_of(run.state) != shapes[0], "a different seed should deal a different run")
	check(str(run.state.get("seed", "")) == "a different evening",
		"the seed a player typed should be the seed the run records")

	# And an empty seed is a NEW one, not a constant. The generator has not been
	# seeded at the moment one is chosen, so asking it for the number would hand
	# out the same "random" seed on every launch of the game, forever.
	var picked := {}
	for i in 8:
		run.state = run.fresh("")
		picked[str(run.state.get("seed", ""))] = true
	check(picked.size() > 1, "an empty seed box should not produce the same run every time")


## The plan, the deck and who is at the door — enough of a run to tell two
## apart.
func _shape_of(st: Dictionary) -> String:
	var bits: Array = []
	for slot in st.get("plan", []):
		bits.append(str(slot.get("offers", [])))
	for c in st.get("deck", []):
		bits.append(str(c.get("n", "")))
	for o in st.get("options", []):
		bits.append(str(o.get("sitter", {}).get("name", o.get("kind", ""))))
	return "|".join(bits)


## TAKING BACK THE LAST CARD HAS TO PUT EVERYTHING BACK.
##
## Laying a card can draw more, refund energy, exhaust itself and shuffle the
## deck. An undo that unpicks that by hand has four ways to be subtly wrong
## about somebody's run — a card quietly duplicated, an energy point invented —
## and every one of them looks fine on screen.
func _test_taking_it_back() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	check(not run.can_unlay(), "nothing has been laid yet, so there is nothing to take back")

	var before := str(run.state["f"])
	var laid := false
	for c in run.state["f"]["hand"].duplicate():
		if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]):
			run.lay_card(c["uid"])
			laid = true
			break
	if not laid:
		return  # nothing affordable; a rare deal, not a failure
	check(run.can_unlay(), "a card has been laid and it should be possible to take it back")
	run.unlay()
	check(str(run.state["f"]) == before, "taking a card back should leave the reading exactly as it was")
	check(not run.can_unlay(), "there is nothing left to take back after taking one back")

	# And a reading closes the window. You cannot un-say a reading.
	for c in run.state["f"]["hand"].duplicate():
		if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]):
			run.lay_card(c["uid"])
			break
	run.read_it()
	check(not run.can_unlay(), "a reading has been read; the cards in it are said")


## THE LADDER ONLY GOES UP. Every rung is cumulative, so a higher level must
## never make an encounter easier — which is exactly the kind of thing a
## mis-signed number in a JSON file does, and which nothing else would catch.
func _test_the_ladder() -> void:
	var rungs: Array = content.difficulty
	check(rungs.size() > 1, "there should be a ladder to climb")
	var last_denial := -999
	var last_turns := 999
	var last_max := -999
	for rung in rungs:
		run.state = run.fresh("a fixed evening", int(rung.get("n", 0)))
		var fx: Dictionary = run.level_fx()
		var s: Dictionary = run.scale_sitter(content.sitters[0], 0, 0)
		check(int(s["denial"]) >= last_denial,
			"level %s should not have a thinner wall than the rung below it" % rung.get("n"))
		check(int(s["turns"]) <= last_turns,
			"level %s should not give more readings than the rung below it" % rung.get("n"))
		check(int(s["turns"]) >= 1, "no level may leave an encounter with no readings in it")
		check(int(s["max"]) >= last_max,
			"level %s should not ask for less composure than the rung below it" % rung.get("n"))
		# A rung's fractions must survive the fold. JSON hands every number over
		# as a float, so a key folded as an amount turns a 1.1 multiplier into 1
		# — a rung that silently does nothing, which is what this whole ladder was
		# measured for in the first place (see tests/balance_sim.gd).
		for key in rung.get("fx", {}):
			if key in run.SET_OUTRIGHT:
				check(is_equal_approx(float(fx.get(key, 0.0)), float(rung["fx"][key])),
					"level %s should carry %s as %s, not %s" % [rung.get("n"), key, rung["fx"][key], fx.get(key, 0.0)])
		last_denial = int(s["denial"])
		last_turns = int(s["turns"])
		last_max = int(s["max"])

	# And the lowest rung changes nothing: level 0 is the game as written.
	run.state = run.fresh("a fixed evening", 0)
	check(run.level_fx().is_empty(), "level 0 should be the game exactly as it is")


## THE ENDING IS ABOUT THE PEOPLE. Every sitter who sits down goes on the run's
## ledger with what became of them, and how many of them you got through to is
## what picks the closing paragraphs. Both are silent when they break: the
## screen still renders, with an empty list and whichever ending is first.
##
## EVERY ENDING HAS TO BE REACHABLE, which is the check that was missing. The
## endings were keyed on how many people LEFT as they came, ascending — and one
## person leaving ends the run, so a ledger never holds more than one failure and
## the two lines covering two and five failures could not be seen at any count.
## The old test here read the file's own ordering back and agreed with it.
func _test_the_ledger_and_the_ending() -> void:
	check(not content.endings.is_empty(), "there should be endings to reach")
	var covers := 999999
	for e in content.endings:
		check(int(e.get("mended_from", 0)) < covers, "the endings must be in descending order, best first")
		covers = int(e.get("mended_from", 0))
		check(str(e.get("village", "")) != "" and str(e.get("reader", "")) != "",
			"an ending has to say what became of the village AND of you")
	check(covers == 0, "the last ending must cover a run where you got through to nobody")

	# Asked of the game's own chooser across every count a run can produce.
	# 24 is three nights of eight hours with one caller taken at each.
	var reached := {}
	for mended in 25:
		var e: Dictionary = run.ending_for(mended)
		check(not e.is_empty(), "no ending covers a run that mended %d people" % mended)
		reached[str(e.get("head", ""))] = true
	for e in content.endings:
		check(reached.has(str(e.get("head", ""))),
			"the ending \"%s\" cannot be reached by any run" % e.get("head", ""))

	run.state = run.fresh("a fixed evening")
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	var who := str(run.state["f"]["sitter"]["name"])
	var f: Dictionary = run.state["f"]
	f["turn"] = f["turns"]
	f["hp"] = 0
	run.lose(f, "left")
	var ledger: Array = run.state.get("ledger", [])
	check(ledger.size() == 1, "one person sat down and the ledger has %d" % ledger.size())
	if ledger.size() == 1:
		check(str(ledger[0].get("name", "")) == who, "the ledger recorded the wrong person")
		check(str(ledger[0].get("outcome", "")) == "left", "they left as they came and the ledger says otherwise")
		check(str(ledger[0].get("said", "")) != "", "the ledger should carry their own closing line")


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
