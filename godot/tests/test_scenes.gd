## Headless scene smoke test. Instantiates every UI scene against a range of
## Run.state shapes (one per "screen" value, plus each pick kind) and lets
## each run one process frame, to catch _ready()-time construction errors
## (wrong node types, bad theme overrides, null derefs) that a pure state-
## machine test (test_run.gd) can't see since it never builds any UI.
##
## Run with:
##   godot --headless --path godot -s tests/test_scenes.gd
## This prints a marker before/after each scene and relies on Godot's own
## SCRIPT ERROR / ERROR output surfacing between markers — grep the output
## for "ERROR" rather than trusting exit code alone.
extends SceneTree

var content: Node
var run: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	# See screenshot.gd's _initialize() comment: Run._ready() (state =
	# fresh()) is deferred to the first process frame, and this script awaits
	# frames later on — without waiting one out first, that deferred _ready()
	# would fire mid-sweep and silently reset whatever state the current
	# _visit() just built. Order happened to make this harmless today (the
	# first visit is "sign", which wants fresh() anyway) but that's luck, not
	# a guarantee against future reordering.
	await process_frame
	content.reload()
	# What the player's settings looked like before this file touched anything.
	# Several tests here change text_scale and high_contrast on purpose — they
	# have to, since the only way to check a look setting reaches the interface
	# is to build a screen under it — and Settings writes straight to disk, so a
	# test that forgets to put one back leaves it changed for the game and for
	# every tool. That is not hypothetical: a text_scale of 1.3 was left behind
	# once and quietly rendered every screenshot at the wrong size until somebody
	# noticed the words looked big.
	var settings_before := _settings_snapshot()

	await _visit("sign", func(): run.state = run.fresh())

	await _visit("pick (gift)", func():
		run.state = run.fresh()
		run.pick_reader(0)
	)

	await _visit("map", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
	)

	await _visit("read", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
		var sitter_opt = null
		for o in run.state["options"]:
			if o["kind"] in ["sitter", "elite"]:
				sitter_opt = o
				break
		run.choose(run.state["options"].find(sitter_opt))
		var f: Dictionary = run.state["f"]
		if not f["hand"].is_empty():
			run.lay_card(f["hand"][0]["uid"])
	)

	await _visit("result (win, forced)", func():
		var f: Dictionary = run.state["f"]
		f["hp"] = f["max"]
		run.win(f)
	)

	await _visit("pick (reward)", func():
		run.after_res()
	)

	await _visit("pick (shop)", func():
		run.state["pick"] = run.build_shop()
		run.state["screen"] = "pick"
	)

	await _visit("pick (event)", func():
		run.state["pick"] = run.build_event(content.events[0])
		run.state["screen"] = "pick"
	)

	await _visit("result (lose, forced)", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
		var sitter_opt = null
		for o in run.state["options"]:
			if o["kind"] in ["sitter", "elite"]:
				sitter_opt = o
				break
		run.choose(run.state["options"].find(sitter_opt))
		var f: Dictionary = run.state["f"]
		f["turn"] = f["turns"]
		f["hp"] = 0
		run.lose(f, "left")
	)

	await _visit("over", func():
		run.after_res()
	)

	await _visit_standalone()
	await _test_keyboard_can_play()
	_test_settings_return_path()
	_check_settings_put_back(settings_before)

	print("SCENE SWEEP DONE")
	quit(0)


## Every setting this file could have changed, by name and value.
func _settings_snapshot() -> Dictionary:
	var settings: Node = root.get_node("Settings")
	var out := {}
	for key in settings.DEFS:
		out[key] = settings.get_value(key)
	return out


func _check_settings_put_back(before: Dictionary) -> void:
	var settings: Node = root.get_node("Settings")
	var moved: Array = []
	for key in before:
		if settings.get_value(key) != before[key]:
			moved.append("%s %s -> %s" % [key, before[key], settings.get_value(key)])
	if moved.is_empty():
		print("--- the player's settings are as they were found ---")
		return
	printerr("FAIL: this test left the player's settings changed on disk: %s" % ", ".join(moved))


## The menus are not reachable from Run.state's "screen" field — they are
## screens, not run states — so the sweep above never built them and their
## _ready() went unchecked. That matters most for the main menu, which now has
## real branching in it (a resumable save, no save, an unreadable one) and for
## the mods screen, which reads pack metadata that only exists after a load.
func _visit_standalone() -> void:
	var save: Node = root.get_node("Save")

	save.clear()
	await _visit_scene("main menu (no save)", "res://scenes/MainMenu.tscn")

	# With a save present the menu grows a CONTINUE entry and a line describing
	# the run, which reaches into Content for the reader's name.
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	save._write()
	await _visit_scene("main menu (resumable save)", "res://scenes/MainMenu.tscn")

	# An unreadable save takes the third branch: the menu says so rather than
	# silently offering nothing.
	var f := FileAccess.open(save.PATH, FileAccess.WRITE)
	f.store_string("not a variant")
	f.close()
	print("--- the next ERROR line is expected: a deliberately corrupt save ---")
	await _visit_scene("main menu (unreadable save)", "res://scenes/MainMenu.tscn")
	save.clear()

	await _visit_scene("mods", "res://scenes/ModsScreen.tscn")
	await _visit_scene("minitel", "res://scenes/MinitelScreen.tscn")
	await _test_minitel_screen_dials()
	await _visit_scene("how to play", "res://scenes/HowToPlay.tscn")
	await _visit_scene("credits", "res://scenes/Credits.tscn")
	_test_the_rules_screen_matches_the_engine()
	await _test_a_failing_save_is_visible_to_the_player()
	await _test_the_overlays_are_modal()
	await _test_the_marks_are_on_the_hands()
	await _test_the_last_card_floats()
	await _test_the_raised_card_is_not_clipped()
	_test_the_sitters_are_different_people()
	await _test_the_screens_read_the_live_content()
	await _test_somebody_knocks()
	await _test_the_reading_shows_its_own_maths()
	await _test_the_reading_is_read_out_once()
	await _test_an_events_own_words_are_shown()
	await _test_every_settings_section_builds()
	await _test_look_settings_reach_a_built_screen()
	await _test_the_hand_stays_on_screen()
	await _test_a_spent_reading_can_still_be_played()
	await _visit_scene("settings", "res://scenes/SettingsMenu.tscn")
	await _visit_scene("library", "res://scenes/Library.tscn")


## The rules screen explains the element wheel, and a rules screen that
## explains the game wrongly is worse than none: a player follows it, loses,
## and concludes the game cheats. It is built from Content.ring rather than
## from a sentence, and this checks that Content.ring is genuinely what
## Rules.link_of() walks — the two could only be told apart by asking the
## engine, which is what this does.
func _test_the_rules_screen_matches_the_engine() -> void:
	var rules: Node = root.get_node("Rules")
	var ring: Array = content.ring
	if ring.size() < 2:
		printerr("FAIL: the element ring is too short to check")
		return

	var ctx := {}
	var fight := {}
	var wrong := 0
	for i in ring.size():
		var from := str(ring[i])
		var to := str(ring[(i + 1) % ring.size()])
		# Following the ring forward is a TURN — the exact claim the screen
		# makes in its own words.
		if rules.link_of(ctx, fight, from, {"el": to}) != "turn":
			printerr("FAIL: the rules screen says %s -> %s is a turn; the engine says '%s'"
				% [from, to, rules.link_of(ctx, fight, from, {"el": to})])
			wrong += 1
		if rules.link_of(ctx, fight, from, {"el": from}) != "same":
			printerr("FAIL: the rules screen says repeating %s is 'same'; the engine disagrees" % from)
			wrong += 1
	if wrong == 0:
		print("--- the rules screen's wheel matches the engine (%d elements) ---" % ring.size())


## A run that cannot be written to disk has to SAY SO, on screen, where the
## player is.
##
## This was the quietest failure left in the project. A full disk or a
## read-only save directory made every write fail; Save set last_error and
## pushed a console warning, and the player — mid-run, nowhere near a console —
## was told nothing. They played three nights, closed the game, and the run was
## gone: no CONTINUE on the menu, and no explanation ever, since last_error
## does not survive a relaunch.
##
## Checked by rendering the real screen and reading the labels, not by testing
## the flag. The flag was already being set correctly; what was missing was
## anyone showing it.
func _test_a_failing_save_is_visible_to_the_player() -> void:
	var save: Node = root.get_node("Save")
	save.clear()
	# A DIRECTORY where the save file belongs: every FileAccess.open(WRITE)
	# fails, which is what a full or read-only disk looks like from here.
	DirAccess.make_dir_recursive_absolute(save.PATH)

	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	print("--- the next WARNING is expected: a deliberately unwritable save ---")
	save._write()
	if not save.write_failed:
		printerr("FAIL: precondition — the write was supposed to fail and did not")
		DirAccess.remove_absolute(save.PATH)
		return

	var instance: Node = load("res://scenes/Map.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var warned := _text_of(instance).contains("NOT BEING SAVED")
	if not warned:
		printerr("FAIL: the run cannot be saved and no screen says so — the player loses it silently")
	else:
		print("--- an unwritable save is on screen ---")
	instance.queue_free()
	await process_frame

	# And it goes away once writing works again, rather than sticking around
	# and training the player to ignore it.
	DirAccess.remove_absolute(save.PATH)
	save._write()
	if save.write_failed:
		printerr("FAIL: the warning did not clear after a successful write")
	else:
		instance = load("res://scenes/Map.tscn").instantiate()
		root.add_child(instance)
		await process_frame
		if _text_of(instance).contains("NOT BEING SAVED"):
			printerr("FAIL: the warning is still on screen after a successful write")
		instance.queue_free()
		await process_frame
	save.clear()

	# The same news at the menu, where the OTHER two stores live. If user:// is
	# unwritable then settings and unlocks are not persisting either, and a
	# player would otherwise just notice their options resetting every launch
	# with no idea why.
	var settings: Node = root.get_node("Settings")
	var profile: Node = root.get_node("Profile")
	for path in [settings.PATH, profile.PATH]:
		DirAccess.remove_absolute(path)
		DirAccess.make_dir_recursive_absolute(path)
	print("--- the next two WARNINGs are expected: deliberately unwritable config ---")
	settings.save_to_disk()
	profile.save_to_disk()
	if settings.last_error == "" or profile.last_error == "":
		printerr("FAIL: a failed config write was not recorded (settings '%s', profile '%s')"
			% [settings.last_error, profile.last_error])
	instance = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	if not _text_of(instance).contains("NOTHING IS BEING SAVED"):
		printerr("FAIL: settings and unlocks are not persisting and the menu does not say so")
	else:
		print("--- an unwritable user:// is on screen at the menu ---")
	instance.queue_free()
	await process_frame
	for path in [settings.PATH, profile.PATH]:
		DirAccess.remove_absolute(path)
	settings.save_to_disk()
	profile.save_to_disk()


## THE MARKS ARE ON THE HANDS, and they have to stay there.
##
## The reading screen draws the reader's own hands holding the fan, with every
## mark won this run drawn onto them — a ring on a finger, ink on the back of
## the hand, a scar across the knuckles, a boon as a light above. That is the
## payoff for a screen the game calls YOUR HANDS, and every part of it fails
## quietly: a mark placed off the control, a mark of a kind nobody draws, a
## fifth ring on a four-fingered hand, or the whole layer drawn BEHIND the cards
## it is supposed to be holding. None of those raise anything.
##
## Checked as data (Table.mark_places) plus the built screen's node order,
## because a headless run has no pixels to count.
func _test_the_marks_are_on_the_hands() -> void:
	# load(), not preload() — see _test_the_overlays_are_modal().
	var TableScript := load("res://scenes/Table.gd")

	# Every kind the content actually ships has to be one this knows how to
	# draw. An unknown kind is skipped on purpose (a mod's business), so a NEW
	# BASE KIND would silently be invisible on the hands and nowhere else.
	var kinds := {}
	for m in content.marks:
		kinds[str(m.get("kind", ""))] = true
	for kind in kinds:
		if not TableScript.KINDS.has(kind):
			printerr("FAIL: marks.json has kind '%s' and the hands cannot draw it — it would be invisible" % kind)

	# A hand is four fingers; ask for more of everything than fits on one.
	var band := 120.0
	var palm := Vector2(200, band)
	var fingers: Array = []
	for i in 4:
		var root := palm + Vector2((float(i) - 1.5) * 16.0, -0.19 * band)
		fingers.append([root, root + Vector2(0, -0.5 * band), 6.0])

	var worn: Array = []
	for kind in TableScript.KINDS:
		for i in 6:
			worn.append({"kind": kind, "n": "%s %d" % [kind, i]})
	var places: Array = TableScript.mark_places(worn, palm, fingers, band, 1.0)
	if places.size() != worn.size():
		printerr("FAIL: %d marks went onto the hands and %d came back — %d are invisible"
			% [worn.size(), places.size(), worn.size() - places.size()])

	# Two marks of one kind must not land on the same spot: stacked exactly, the
	# player sees one ring and owns two.
	var seen := {}
	for p in places:
		var key := "%s@%d,%d" % [p["kind"], roundi(p["at"].x), roundi(p["at"].y)]
		if seen.has(key):
			printerr("FAIL: two %s marks are drawn at the same point — one hides the other" % p["kind"])
		seen[key] = true

	# And a kind nobody draws draws nothing, rather than a guess.
	var invented: Array = TableScript.mark_places(
		[{"kind": "SOMETHING_A_MOD_INVENTED"}], palm, fingers, band, 1.0)
	if not invented.is_empty():
		printerr("FAIL: an unknown mark kind was given a place on the hands")

	# The hands have to be drawn IN FRONT of the cards. Behind them they are a
	# picture of hands near a fan, which is the version this replaced — and the
	# only thing that decides it is sibling order, which nothing else would
	# catch if a later edit reordered the two.
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	run.state["marks"] = [content.marks[0]]
	var instance: Node = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var scroll := _first_of_class(instance, "ScrollContainer")
	if scroll == null:
		printerr("FAIL: the reading screen has no card scroller to hold")
	else:
		var stack := scroll.get_parent()
		var hands_i := -1
		for i in stack.get_child_count():
			if stack.get_child(i) != scroll:
				hands_i = i
		if hands_i < scroll.get_index():
			printerr("FAIL: the hands are drawn behind the cards, so nothing looks held")
		else:
			print("--- the marks are on the hands, and the hands are in front of the cards ---")
	instance.queue_free()
	await process_frame


## THE LAST CARD FLOATS. When the hand is down to one, the card is lifted clear
## of two open hands rather than clamped between fingertips — which means it
## leaves the ScrollContainer and the flow container entirely, and a Control
## outside a container is on its own for two things that a container was doing
## for it:
##
##   - its SIZE. Control.size is clamped up to the combined minimum, and a card's
##     name is an auto-wrapping Label whose minimum height depends on the width
##     it has been given — zero, before the first layout pass. The first version
##     of this came out nearly twice as tall as every other card in the game and
##     raised nothing;
##   - being REACHABLE. A floating card that cannot be focused is a hand a
##     keyboard or gamepad player cannot play, and the run is stuck.
##
## And the float itself is only a float if there is a gap: the fingertips have
## to stop BELOW the card. That is checked against Table.finger_geometry(), the
## same geometry the drawing reads, in both directions — open hands clear the
## card, closed hands cross it.
func _test_the_last_card_floats() -> void:
	# load(), not preload() — see _test_the_overlays_are_modal().
	var TableScript := load("res://scenes/Table.gd")
	var ReadingScript := load("res://scenes/Reading.gd")
	var UIKitScript := load("res://scenes/UIKit.gd")

	const COUNTS := [1, 5]
	for count: int in COUNTS:
		# SEEDED, and it tries a few. An unseeded run.fresh() deals a hand that
		# some sitters shorten — a quirk that takes a card before the reading
		# starts is in the base content — so about one run in ten was dealt four
		# cards and reported a precondition failure that was nothing but the
		# weather. Seeds make the deal reproducible; trying several means the
		# test does not depend on one lucky one still being lucky after somebody
		# edits a card.
		var f: Dictionary = {}
		for spin in 8:
			run.state = run.fresh("floats-%d-%d" % [count, spin])
			run.pick_reader(0)
			run.take_pick(0)
			for o in run.state["options"]:
				if o["kind"] in ["sitter", "elite"]:
					run.choose(run.state["options"].find(o))
					break
			f = run.state["f"]
			if not f.is_empty() and f["hand"].size() >= count:
				break
		if f.is_empty() or f["hand"].size() < count:
			printerr("FAIL: precondition — wanted %d cards in hand, no seed in eight dealt that many" % count)
			continue
		f["hand"] = f["hand"].slice(0, count)
		var alone := count == 1

		var instance: Node = load("res://scenes/Reading.tscn").instantiate()
		root.add_child(instance)
		for i in 4:
			await process_frame

		var face := _first_focusable_panel(instance)
		var hands := instance.find_child("Hands", true, false)
		if face == null or hands == null:
			printerr("FAIL: with %d card(s) in hand there is no card face (%s) or no hands (%s)"
				% [count, face, hands])
			instance.queue_free()
			await process_frame
			continue

		var want: Vector2 = UIKitScript.card_face_size()
		if alone and (absf(face.size.x - want.x) > 1.0 or absf(face.size.y - want.y) > 1.0):
			printerr("FAIL: the floating card is %s, not the %s every other card is" % [face.size, want])
		if alone and not face.has_focus():
			printerr("FAIL: the floating card never took focus — it cannot be played without a mouse")

		# Where the fingertips actually reach, read from the drawing's own
		# geometry. x is irrelevant to a tip's height, so it is left at zero.
		var reach: float = ReadingScript.OPEN_REACH if alone else 1.0
		var base := Vector2(0, hands.global_position.y + hands.size.y)
		var tip_y := INF
		for finger in TableScript.finger_geometry(base, hands.size.y, 1.0, reach):
			tip_y = minf(tip_y, finger[2].y)
		var card_bottom: float = face.global_position.y + face.size.y
		if alone and tip_y <= card_bottom:
			printerr("FAIL: the fingertips reach %.0f and the floating card ends at %.0f — it is being held, not floating"
				% [tip_y, card_bottom])
		if not alone and tip_y >= card_bottom:
			printerr("FAIL: the fingertips stop at %.0f, below the cards at %.0f — the fan is not held by anything"
				% [tip_y, card_bottom])
		instance.queue_free()
		await process_frame
	print("--- the last card floats above open hands; a fan is held by closed ones ---")


## THE CARD YOU ARE POINTING AT IS NOT CUT IN HALF.
##
## The fan lives in a ScrollContainer so a hand too wide for the window wraps to
## a second row you can still reach, and a ScrollContainer clips. The card under
## the pointer grows by CARD_LIFT about a pivot on its BOTTOM edge — so it grows
## upward, out of the clip rect. The top of the raised card was being cut off,
## which is where its cost and its restore are printed: the two numbers that are
## the entire reason to point at a card in the first place.
##
## Checked as geometry rather than by eye, because this is exactly the kind of
## thing a screenshot at the wrong moment does not show: the clip only bites
## while a card is raised, and it comes back down in a tenth of a second.
func _test_the_raised_card_is_not_clipped() -> void:
	# load(), not preload() — see _test_the_overlays_are_modal().
	var ReadingScript := load("res://scenes/Reading.gd")

	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	var f: Dictionary = run.state["f"]
	# Two or more, so the fan branch runs. One card alone is _lift(), which has
	# no scroll box around it and cannot be clipped by one.
	if f["hand"].size() < 2:
		printerr("FAIL: precondition — wanted a fan, was dealt %d card(s)" % f["hand"].size())
		return

	var instance: Node = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(instance)
	for i in 4:
		await process_frame

	var face := _first_focusable_panel(instance)
	if face == null:
		printerr("FAIL: no card face on the reading screen at all")
		instance.queue_free()
		await process_frame
		return

	# The box that does the clipping, found by walking up from the card rather
	# than by name: if the shape of the hand changes, this should follow it or
	# say so, not quietly pass by matching nothing.
	var clipper: Control = null
	var walk: Node = face.get_parent()
	while walk != null and walk != instance:
		if walk is ScrollContainer:
			clipper = walk
			break
		walk = walk.get_parent()
	if clipper == null:
		printerr("FAIL: the fan is not inside a ScrollContainer any more — this test is measuring nothing")
		instance.queue_free()
		await process_frame
		return

	# Where the top edge goes when the card comes up. Scale is about a pivot on
	# the bottom edge, so all of the growth is upward.
	# Its top edge WITH THE SCALE TAKEN OFF. The first version of this read
	# face.global_position, which is not where the card sits: a Control scaled
	# about a pivot has that pivot folded into its transform, so a card caught
	# part-way through its own lift reports an origin already partly raised —
	# and multiplying that by the lift again counts the growth twice. The first
	# card in the fan takes focus as the screen builds, so this is not the rare
	# case, it is every run of this test. Measured from the fan, which is never
	# scaled, plus the card's own unscaled offset within it.
	var lift: float = ReadingScript.CARD_LIFT
	var fan: Control = face.get_parent()
	var resting_top: float = fan.global_position.y + face.position.y
	var raised_top: float = resting_top - face.size.y * (lift - 1.0)
	var clip_top: float = clipper.global_position.y
	if raised_top < clip_top - 0.5:
		printerr("FAIL: a %.0fpx card resting at y=%.0f reaches y=%.0f when raised, and the box clips at y=%.0f — %.0fpx of it, cost and restore included, is cut off"
			% [face.size.y, resting_top, raised_top, clip_top, clip_top - raised_top])
	instance.queue_free()
	await process_frame
	print("--- the card under the pointer comes up inside its box, not through the top of it ---")


## YOU CAN SEE WHAT YOUR PLAY WILL DO BEFORE YOU COMMIT TO IT.
##
## Three things the reading screen now shows and did not, each of which is
## invisible when it breaks — the screen looks perfectly reasonable without
## any of them, which is how they were missing for the whole port:
##
##   - THE PROJECTION on the composure bar: what the cards already on the table
##     would restore, and how much of it the sitter's denial would eat first.
##     This is the source prototype's own three-segment bar (v23 line ~726) and
##     it was not ported. Checked against the engine, not against itself: the
##     number on screen has to be the number Rules.simulate() produces, or the
##     bar is a decoration that lies;
##   - THE PILES. Every deckbuilder shows how many cards are left to draw;
##   - A CARD'S TEXT WITHOUT A MOUSE. It lived in a hover tooltip, and a hover
##     is something a gamepad cannot do, so a controller player could reach
##     every card, play them, and never read what one of them did.
func _test_the_reading_shows_its_own_maths() -> void:
	var rules: Node = root.get_node("Rules")
	# Autoloads are not bare identifiers in a `godot -s` script — the tree is
	# reachable, the globals are not. Same reason every other test here says
	# root.get_node("Save").
	var i18n: Node = root.get_node("I18n")
	# ONE card laid, not the whole hand: the projection needs something on the
	# table, and the card-text check needs something still IN hand to focus. A
	# first pass reused the "lay everything" helper, left an empty fan, and
	# reported that nothing was focused — which was true and not the point.
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	# Lay until there is something to project, and stop while a card is still in
	# hand to focus. Laying exactly one card was the first version and it is a
	# coin toss: plenty of hands put a 0-restore card down, or one the wall eats
	# whole, and the check then skips itself and passes with the feature
	# deleted — which is what happened.
	var f: Dictionary = run.state["f"]
	while int(rules.simulate(run.run_ctx(), run.state["f"]).get("applied", 0)) < 1:
		f = run.state["f"]
		if f["hand"].size() <= 1:
			break
		var laid_one := false
		for c in f["hand"].duplicate():
			if int(c.get("cost", 0)) <= int(f["energy"]):
				run.lay_card(c["uid"])
				laid_one = true
				break
		if not laid_one:
			break
	f = run.state["f"]
	var sim: Dictionary = rules.simulate(run.run_ctx(), f)
	var room: int = maxi(0, int(f["max"]) - maxi(0, int(f["hp"])))
	var expect_land: int = mini(int(sim.get("applied", 0)), room)
	var draw_left: int = f["draw"].size()

	var instance: Node = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(instance)
	for i in 3:
		await process_frame
	var screen := _text_of(instance)

	# Read THE ROW, not the whole screen. Asking whether "+8" appears anywhere
	# on a reading screen is not a test: every card in hand prints its own
	# restore value, so the first version of this passed happily with the
	# projection deleted. Same for the pile counts against a screen full of
	# numbers.
	var composure := _row_text(instance, i18n.t("Composure"))
	if expect_land >= 1 and not composure.contains("+%d" % expect_land):
		printerr("FAIL: this reading would restore %d and the composure row says '%s'"
			% [expect_land, composure.strip_edges()])
	var piles := _line_containing(instance, i18n.t("Left to draw"))
	if not piles.contains("%s %d" % [i18n.t("Left to draw"), draw_left]):
		printerr("FAIL: %d cards are left to draw and the line says '%s'" % [draw_left, piles.strip_edges()])

	# The card that has focus has to be readable without a pointer.
	var focused: Control = instance.get_viewport().gui_get_focus_owner()
	if focused == null:
		printerr("FAIL: nothing is focused, so there is no card to read")
	else:
		var tip: String = focused.tooltip_text
		var opening: String = tip.split("\n")[0].substr(0, 20) if tip != "" else ""
		if opening == "":
			printerr("FAIL: the focused card carries no text at all")
		elif not screen.contains(opening):
			printerr("FAIL: the focused card says '%s...' and nothing on screen does — its text is mouse-only"
				% opening)
	instance.queue_free()
	await process_frame
	print("--- the reading prices itself before you commit ---")


## Every Label in the row that begins with `caption`, joined. A "row" is an
## HBoxContainer, which is what stat_row() builds.
func _row_text(node: Node, caption: String) -> String:
	if node is HBoxContainer:
		var first := ""
		for child in node.get_children():
			if child is Label:
				first = (child as Label).text
				break
		if first == caption:
			return _text_of(node)
	for child in node.get_children():
		var found := _row_text(child, caption)
		if found != "":
			return found
	return ""


## The one Label containing `needle`, or "".
func _line_containing(node: Node, needle: String) -> String:
	if node is Label and (node as Label).text.contains(needle):
		return (node as Label).text
	for child in node.get_children():
		var found := _line_containing(child, needle)
		if found != "":
			return found
	return ""


## THE READING IS READ OUT — and, crucially, is resolved EXACTLY ONCE.
##
## READ IT used to resolve the whole reading between two frames and leave for
## the next screen. It now writes a ledger first: a line per card with its link
## named, then the wall taking its share, then what reaches them. Which means
## there is a window, a couple of seconds long, in which the reading has been
## asked for and has not happened — and in that window the player can press READ
## IT again, press a key, or click. Every one of those has to land on the same
## resolution.
##
## Resolving twice would lay the whole line a second time: double composure,
## double faith, a reading the player never played. It is the one thing about
## this that would be a real bug rather than a cosmetic one, and it is invisible
## from the outside — the screen looks right either way.
func _test_the_reading_is_read_out_once() -> void:
	var settings: Node = root.get_node("Settings")
	var was: float = float(settings.get_value("animation_scale"))

	for motion: bool in [true, false]:
		settings.set_value("animation_scale", 1.0 if motion else 0.0)
		_lay_a_reading()
		# A reading advancing is the observable, not Run.state["res"] — `res` is
		# only set when the whole ENCOUNTER ends, so a first pass at this test
		# asserted against a field that is empty after every ordinary reading and
		# reported two failures that were not there.
		var turn_before := int(run.state["f"]["turn"])

		var instance: Node = load("res://scenes/Reading.tscn").instantiate()
		root.add_child(instance)
		await process_frame
		await process_frame

		instance._read_it()
		await process_frame
		var reveal := instance.find_child("Reveal", true, false)

		if motion:
			if _turn_now() != turn_before:
				printerr("FAIL: READ IT resolved the reading before reading it out — nobody sees the ledger")
			if reveal == null:
				printerr("FAIL: READ IT with motion on shows no ledger at all")
			# Everything a player can do in that window ends the SAME reading.
			instance._read_it()
			instance._read_it()
			await process_frame
			var after := _turn_now()
			if after == turn_before:
				printerr("FAIL: pressing READ IT during the ledger did not finish the reading")
			elif after > turn_before + 1:
				printerr("FAIL: the reading advanced %d turns from one READ IT — it resolved more than once"
					% (after - turn_before))
		else:
			if _turn_now() == turn_before:
				printerr("FAIL: with motion off READ IT did not resolve — the player is waiting on nothing")
			if reveal != null:
				printerr("FAIL: motion is off and the ledger is animating anyway")
		instance.queue_free()
		await process_frame

	settings.set_value("animation_scale", was)
	print("--- the reading is read out, and resolves exactly once ---")


## The reading number, or -1 once the encounter itself has ended (a reading big
## enough to mend them takes the fight with it, and there is no `f` left to ask).
func _turn_now() -> int:
	if not run.state.get("res", {}).is_empty():
		return -1
	return int(run.state.get("f", {}).get("turn", -2))


## A reading with everything affordable already laid, ready for READ IT.
func _lay_a_reading() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for o in run.state["options"]:
		if o["kind"] in ["sitter", "elite"]:
			run.choose(run.state["options"].find(o))
			break
	var f: Dictionary = run.state["f"]
	for c in f["hand"].duplicate():
		if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]):
			run.lay_card(c["uid"])


## AN OPTION'S OWN WORDS ARE ON THE ROW. Several of the events hand over a card
## or a mark and say something about it in their own voice; the row that shows a
## card printed the CARD's rules and flavour and threw the option's line away,
## which turned an event into a shop entry. Nothing raises when a line of
## writing is dropped — it just is not there.
func _test_an_events_own_words_are_shown() -> void:
	var wanted := {}
	for e in content.events:
		for o in e.get("opts", []):
			if (o.get("card") is String or o.get("mark") is String) and str(o.get("text", "")) != "":
				wanted[e.get("title", "?")] = str(o["text"])
				break
	if wanted.is_empty():
		printerr("FAIL: no event hands over a card or mark with anything to say — nothing to check")
		return

	for title: String in wanted:
		for e in content.events:
			if str(e.get("title", "")) != title:
				continue
			run.state = run.fresh()
			run.pick_reader(0)
			run.take_pick(0)
			run.state["pick"] = run.build_event(e)
			run.state["screen"] = "pick"
			var instance: Node = load("res://scenes/PickScreen.tscn").instantiate()
			root.add_child(instance)
			await process_frame
			await process_frame
			# The first few words are enough, and survive wrapping.
			var opening: String = str(wanted[title]).substr(0, 28)
			if not _text_of(instance).contains(opening):
				printerr("FAIL: '%s' says \'%s...\' about what it gives, and the row does not show it"
					% [title, opening])
			instance.queue_free()
			await process_frame
			break
	print("--- %d event(s) hand over a card or a mark and get to say why ---" % wanted.size())


## SOMEBODY KNOCKS. The map screen asks "who knocks tonight?", a run is sixteen
## knocks long and it ends the night the knocking stops — and for the whole port
## nothing ever knocked.
##
## Three things, each of which fails in silence:
##
##   - the knock has to HAPPEN. It is a timer inside a scene; nothing else in
##     the game would notice if it stopped firing;
##   - it has to happen with ANIMATION TURNED OFF too. Turning off motion should
##     not make the game go quiet, and the easy version of this feature is one
##     early return that does exactly that;
##   - it must not TAKE THE SCREEN AWAY. The options have to be there and
##     focused from the first frame, or a player on their fortieth night is
##     waiting on a cutscene to let them click.
func _test_somebody_knocks() -> void:
	var audio: Node = root.get_node("Audio")
	var settings: Node = root.get_node("Settings")
	var was: float = float(settings.get_value("animation_scale"))

	for motion: bool in [true, false]:
		settings.set_value("animation_scale", 1.0 if motion else 0.0)
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
		audio.played.erase("knock")

		var instance: Node = load("res://scenes/Map.tscn").instantiate()
		root.add_child(instance)
		await process_frame
		await process_frame

		# Before waiting for a single knock: the choices are here and one of
		# them is focused. This is the assertion that the beat is a beat.
		var focused: Control = instance.get_viewport().gui_get_focus_owner()
		if focused == null or not instance.is_ancestor_of(focused):
			printerr("FAIL: the map is knocking and nothing is focused — the player is waiting on it")

		# The first knock is at t=0, so it has already fired; the rest are
		# timers, and this is a real display-less frame loop, so wait them out.
		await create_timer(1.0).timeout
		var heard := int(audio.played.get("knock", 0))
		var want: int = load("res://scenes/Map.gd").KNOCKS.size() if motion else 1
		if heard < want:
			printerr("FAIL: %d knock(s) with motion %s, wanted %d — nobody is at the door"
				% [heard, "on" if motion else "off", want])
		instance.queue_free()
		await process_frame

	settings.set_value("animation_scale", was)
	print("--- somebody knocks, with the animations on and off ---")


## THE RULES SCREEN KNOWS ABOUT THE LADDER, AND THE MAP DRAWS THE AGENDA.
##
## Two screens that are built from live data and would go quietly stale
## otherwise. The rules screen's whole premise is that it explains the game by
## READING it rather than by restating it, so a rung added to difficulty.json
## and never mentioned is exactly the drift it exists to prevent. And the agenda
## is only worth having if it is on screen: an hour missing from the page is a
## plan the player cannot use, and nothing else in the game would notice.
func _test_the_screens_read_the_live_content() -> void:
	var instance: Node = load("res://scenes/HowToPlay.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	var rules_text := _text_of(instance)
	for rung in content.difficulty:
		if int(rung.get("n", 0)) == 0:
			continue
		if not rules_text.contains(str(rung.get("name", ""))):
			printerr("FAIL: difficulty rung '%s' exists and the rules screen has never heard of it"
				% rung.get("name", "?"))
	instance.queue_free()
	await process_frame

	run.state = run.fresh("a fixed evening")
	run.pick_reader(0)
	run.take_pick(0)
	instance = load("res://scenes/Map.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var map_text := _text_of(instance)
	var plan: Array = run.state.get("plan", [])
	check_not_empty(plan, "the night should have a plan")
	for slot in plan:
		if not map_text.contains(str(slot.get("at", ""))):
			printerr("FAIL: the night runs to %s and the agenda does not show that hour" % slot.get("at", "?"))
			break
	# And the last half-hour of the last night is the Mayor, said out loud —
	# the one thing a player most needs to be able to plan against.
	instance.queue_free()
	await process_frame
	run.state["night"] = 2
	run.state["step"] = 0
	run.state["plan"] = run.make_plan(2)
	instance = load("res://scenes/Map.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	if not _text_of(instance).contains(load("res://scenes/Map.gd").PROMISE["boss"]):
		printerr("FAIL: the mayor is at the end of the last night and the agenda does not say so")
	instance.queue_free()
	await process_frame
	print("--- the rules screen and the agenda are reading the live content ---")


func check_not_empty(a: Array, why: String) -> void:
	if a.is_empty():
		printerr("FAIL: " + why)


## THE VILLAGERS ARE DIFFERENT PEOPLE, AND THE SAME ONES EVERY TIME.
##
## The sitter portrait is drawn rather than painted, and it takes its hair,
## colouring, face width and moustache from a hash of who the sitter is. Two
## things about that fail silently and both would be bad:
##
##   - ask for the wrong field and every hash is the hash of "", so ten
##     villagers are one villager drawn ten times. This is not hypothetical: the
##     first version asked sitters for a `k` they do not have;
##   - use a hash with no promise attached — String.hash(), say — and the whole
##     village quietly rearranges its faces on a Godot upgrade. Someone you have
##     met twenty times is suddenly a stranger, and nothing in the game changed.
##
## So: the hash is pinned to known values, and the faces are counted.
func _test_the_sitters_are_different_people() -> void:
	# load(), not preload() — see _test_the_overlays_are_modal().
	var UIKitScript := load("res://scenes/UIKit.gd")

	# Pinned. If these move, every face in the game moved with them — which is
	# allowed, but it is a decision, not something to discover later.
	const PINNED := {"Mme Perrot/THE LAUNDRESS": 905259117, "Guillaume/THE POSTMAN": 54687178}
	for key: String in PINNED:
		var got: int = UIKitScript._stable_hash(key)
		if got != PINNED[key]:
			printerr("FAIL: the face hash for '%s' changed (%d, was %d) — every villager now looks like someone else"
				% [key, got, PINNED[key]])

	# Built through the REAL portrait, which is what reads the sitter's fields.
	var faces := {}
	for st in content.sitters:
		var first: Control = UIKitScript.sitter_portrait(st, 0.5)
		var again: Control = UIKitScript.sitter_portrait(st, 0.9)
		var a: Dictionary = first.get_meta("face", {})
		if a != again.get_meta("face", {}):
			printerr("FAIL: %s does not look the same twice in a row" % st.get("name", "?"))
		if a.is_empty():
			printerr("FAIL: the portrait for %s carries no face at all" % st.get("name", "?"))
			continue
		faces["%d/%s/%s/%s/%s" % [a["style"], a["skin"], a["hair"], a["cloth"], a["width"]]] = true
		first.free()
		again.free()

	# Not "all distinct" — a hash may honestly collide, and demanding otherwise
	# would be a test of luck. Most of them, though: if the count collapses, the
	# hash is being fed something constant.
	var want: int = maxi(1, int(content.sitters.size() * 0.7))
	if faces.size() < want:
		printerr("FAIL: %d sitters produce only %d different faces (wanted %d) — they are all the same person"
			% [content.sitters.size(), faces.size(), want])
	else:
		print("--- %d sitters, %d faces ---" % [content.sitters.size(), faces.size()])


## The card faces are PanelContainers that take focus; every other focusable
## thing on the reading screen is a Button. Nothing else identifies a card.
func _first_focusable_panel(node: Node) -> Control:
	if node is PanelContainer and (node as Control).focus_mode == Control.FOCUS_ALL:
		return node
	for child in node.get_children():
		var found := _first_focusable_panel(child)
		if found != null:
			return found
	return null


func _first_of_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var found := _first_of_class(child, cls)
		if found != null:
			return found
	return null


## Every Label's text in a built screen, joined — for asserting that something
## a player must see is actually rendered somewhere.
func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


## The deck and marks panels are MODAL — drawn over an in-run screen that is
## still live underneath. Everything that makes a modal a modal was missing,
## and each failure was silent:
##   - focus stayed on the card behind the scrim, so a keyboard or gamepad
##     player who opened their deck and pressed Confirm played a card they
##     could not see. That is worse than a dead highlight;
##   - pressing D again opened a SECOND deck on top of the first;
##   - Escape closed nothing;
##   - the reading's own READ IT shortcut still fired underneath.
## Driven through RunHeader.handle_shortcut(), which is the same entry point
## the in-run screens call from their _unhandled_input.
func _test_the_overlays_are_modal() -> void:
	# load() at call time, NOT preload(). preload() resolves while this test
	# script is being compiled, which is before `godot -s` has registered the
	# autoloads — and RunHeader refers to Run, UIKit and I18n. Preloading it
	# here did not merely fail locally: it left RunHeader.gd compiled to
	# nothing for the whole process, so every in-run screen lost its header and
	# six unrelated cases in this file started failing. Fifth time this trap has
	# been hit in this port; see autoload/Content.gd's header.
	var RunHeaderScript := load("res://scenes/RunHeader.gd")
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for i in run.state["options"].size():
		if run.state["options"][i]["kind"] in ["sitter", "elite"]:
			run.choose(i)
			break

	var instance: Node = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var before: Control = instance.get_viewport().gui_get_focus_owner()
	if before == null:
		printerr("FAIL: precondition — the reading screen focused nothing to begin with")
		instance.queue_free()
		await process_frame
		return

	var deck := InputEventAction.new()
	deck.action = "parlour_deck"
	deck.pressed = true

	RunHeaderScript.handle_shortcut(deck, instance)
	await process_frame
	await process_frame
	var layer: Node = RunHeaderScript.open_overlay(instance)
	var inside: Control = instance.get_viewport().gui_get_focus_owner()
	if layer == null:
		printerr("FAIL: the deck shortcut opened no overlay")
	elif inside == null or not layer.is_ancestor_of(inside):
		printerr("FAIL: opening the deck left focus outside it (%s) — Confirm would act on the hidden screen" % inside)
	else:
		print("--- the deck overlay takes focus ---")

	# An in-run shortcut must not reach the screen behind a modal.
	var read := InputEventAction.new()
	read.action = "parlour_read"
	read.pressed = true
	if not RunHeaderScript.handle_shortcut(read, instance):
		printerr("FAIL: READ IT was not swallowed while an overlay was open")

	# A second press closes rather than stacking, and puts focus back.
	RunHeaderScript.handle_shortcut(deck, instance)
	await process_frame
	await process_frame
	if RunHeaderScript.open_overlay(instance) != null:
		printerr("FAIL: pressing the deck shortcut twice stacked a second overlay")
	elif instance.get_viewport().gui_get_focus_owner() != before:
		printerr("FAIL: closing the deck did not put focus back where it came from")
	else:
		print("--- closing it restores focus ---")

	# And so does ui_cancel.
	RunHeaderScript.handle_shortcut(deck, instance)
	await process_frame
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	RunHeaderScript.handle_shortcut(cancel, instance)
	await process_frame
	await process_frame
	if RunHeaderScript.open_overlay(instance) != null:
		printerr("FAIL: ui_cancel did not close the overlay")
	else:
		print("--- ui_cancel closes it ---")

	instance.queue_free()
	await process_frame


## The settings screen shows one section at a time, so the sweep above only
## ever built the first. Every other pane's construction went unchecked — and a
## pane is exactly where a bad theme override or a null deref lives.
##
## Each section is reached the way a player reaches it: one instance, then
## _select() for each category in turn. That matters — driving it by setting
## _section before the first build would have missed the bug this test found,
## which only happens on a REBUILD (see UIKit.going_away()).
func _test_every_settings_section_builds() -> void:
	var settings: Node = root.get_node("Settings")
	var instance: Node = load("res://scenes/SettingsMenu.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	for i in settings.SECTIONS.size():
		instance._select(i)
		await process_frame
		await process_frame
		_check_focus("settings/" + str(settings.SECTIONS[i]["id"]), instance)
	instance.queue_free()
	await process_frame

	# The rail path above always focuses the freshly built pane. The OTHER
	# rebuild path — a control that rebuilds the whole screen in place, which
	# is what RESET THIS SECTION, the window-mode dropdown, the high-contrast
	# toggle and the language picker all do — focuses the screen from the top,
	# and that is where focus was being lost: the walk found the doomed
	# subtree's first button (queue_free() flags only the root it was called
	# on) and then, once past that, the rail's DISABLED selected entry, on
	# which grab_focus() does nothing at all. Both are checked here because
	# both silently produce the same symptom.
	instance = load("res://scenes/SettingsMenu.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	instance._reset_section()
	await process_frame
	await process_frame
	_check_focus("settings after an in-place rebuild", instance)
	instance.queue_free()
	await process_frame
	print("--- all %d settings sections build and keep focus ---" % settings.SECTIONS.size())


## text_scale and high_contrast are read by UIKit, which a headless Settings
## test cannot even load (UIKit refers to four autoloads, so `godot -s` cannot
## compile it — see Settings._apply_look()'s comment). So the assertion that
## they actually reach the interface has to live here, where real scenes are
## built. Without it the pull could quietly stop happening and every screen
## would just carry on at 100%.
func _test_look_settings_reach_a_built_screen() -> void:
	var settings: Node = root.get_node("Settings")
	var restore_scale = settings.get_value("text_scale")
	var restore_hc = settings.get_value("high_contrast")

	var plain := await _sample_label(1.0, false)
	var big := await _sample_label(1.3, true)

	if plain.is_empty() or big.is_empty():
		printerr("FAIL: could not find a Label to measure on the main menu")
	else:
		if int(big["size"]) <= int(plain["size"]):
			printerr("FAIL: text_scale 1.3 did not enlarge the interface (%d -> %d px)" % [plain["size"], big["size"]])
		else:
			print("--- text_scale reaches the screen (%d -> %d px) ---" % [plain["size"], big["size"]])
		if big["color"] == plain["color"]:
			printerr("FAIL: high_contrast did not change the palette (both %s)" % plain["color"])
		else:
			print("--- high_contrast reaches the screen (%s -> %s) ---" % [plain["color"], big["color"]])

	settings.set_value("text_scale", restore_scale)
	settings.set_value("high_contrast", restore_hc)


## THE HAND CANNOT BE PUSHED OFF THE BOTTOM OF THE WINDOW.
##
## The reading screen used to be one column: header, sitter, bars, pace, what
## has been said so far, READ IT, and the hand last. So everything above the
## hand pushed it down — a long sign rule, a card that slipped out before the
## reading started, a hint line that wrapped to two — and at the largest
## interface size, which exists so that people can read the game, it pushed the
## cards clean off the screen. Measured across forty readings before the fix:
## fifteen lost the cards entirely, the worst by 261 pixels, with no way to
## scroll to them. The setting for players who need bigger text made the game
## unplayable, and nothing in the suite noticed, because nothing failed.
##
## Run at BOTH sizes: at 100% the old layout was fine on almost every hand, so
## a check at the default alone would have gone green over the whole bug.
##
## The window has to be set explicitly. A headless SceneTree's root is square
## (1152x1152), which is not a shape any player has, and it hides the fault
## completely — this measured zero overflow at that size while the real window
## was losing a quarter of the screen.
func _test_the_hand_stays_on_screen() -> void:
	var settings: Node = root.get_node("Settings")
	var restore_scale = settings.get_value("text_scale")
	var restore_hand = settings.get_value("hand_size")
	var restore_size: Vector2i = root.size
	root.size = Vector2i(1152, 648)
	# The widest hand the game can deal, which is the case that broke: eight is
	# the top of the hand-size setting and a reader can add one on top of it. A
	# seeded sample of ordinary hands would mostly miss it, and a test that does
	# not contain the shape it is guarding against is decoration.
	settings.set_value("hand_size", int(settings.DEFS["hand_size"][2]))
	await process_frame

	for scale: float in [1.0, 1.3]:
		settings.set_value("text_scale", scale)
		var worst := 0.0
		var lost := 0
		var tried := 0
		for attempt in 16:
			# SEEDED, so the twelve-odd readings are the same ones every run. An
			# unseeded version of this found a real overflow on about one run in
			# ten and passed on the others, which is a test that reports the
			# weather. A seed also means a failure can be reproduced by typing it
			# into the sign screen.
			run.state = run.fresh("hand-fits-%d" % attempt)
			run.pick_reader(attempt % content.readers.size())
			run.take_pick(0)
			var picked := false
			for o in run.state["options"]:
				if o["kind"] in ["sitter", "elite"]:
					run.choose(run.state["options"].find(o))
					picked = true
					break
			if not picked:
				continue
			# The busiest the screen gets: everything affordable already on the
			# table, which is what the said-so-far row and the hint line grow with.
			var f: Dictionary = run.state["f"]
			for c in f["hand"].duplicate():
				if int(c.get("cost", 0)) <= int(f["energy"]) and f["hand"].size() > 1:
					run.lay_card(c["uid"])

			var instance: Node = load("res://scenes/Reading.tscn").instantiate()
			root.add_child(instance)
			for i in 4:
				await process_frame
			tried += 1
			var bottom := 0.0
			for node in _all_of(instance, []):
				if node is PanelContainer and (node as Control).focus_mode == Control.FOCUS_ALL \
						and node.get_parent() is HFlowContainer:
					var c: Control = node
					bottom = maxf(bottom, c.global_position.y + c.size.y)
			if bottom > 648.0:
				lost += 1
				worst = maxf(worst, bottom - 648.0)
			instance.queue_free()
			await process_frame
		if tried == 0:
			printerr("FAIL: precondition — no reading with a fan was dealt at text_scale %.2f" % scale)
		elif lost > 0:
			printerr("FAIL: at text_scale %.2f, %d of %d readings put the hand off the bottom of a 1152x648 window (worst %.0fpx) — those cards cannot be played"
				% [scale, lost, tried, worst])
	settings.set_value("text_scale", restore_scale)
	settings.set_value("hand_size", restore_hand)
	root.size = restore_size
	await process_frame
	print("--- the hand stays on the table at every interface size ---")


## A READING WITH NO ENERGY LEFT IS STILL PLAYABLE WITHOUT A MOUSE.
##
## The reading screen aims focus at the hand, which is right — that is where a
## player acts. But once the energy is spent every card in the hand is disabled,
## and a disabled control cannot take focus, so a fan of five perfectly visible
## cards contained nothing focusable at all and focus_first quietly placed
## nothing. Not a card, not READ IT, not the header: NOTHING on the screen had
## focus, so a player on a keyboard or a gamepad was holding a controller that
## did nothing and no way to end the turn. It happened on more than half of all
## readings — measured, not guessed — and it was invisible with a mouse, which
## is how it survived the whole port.
##
## Driven to the actual state rather than faked: cards are laid until the energy
## really is gone, and then the screen is built from Run.state like any other.
func _test_a_spent_reading_can_still_be_played() -> void:
	var checked := 0
	for attempt in 10:
		run.state = run.fresh("spent-%d" % attempt)
		run.pick_reader(attempt % content.readers.size())
		run.take_pick(0)
		for o in run.state["options"]:
			if o["kind"] in ["sitter", "elite"]:
				run.choose(run.state["options"].find(o))
				break
		var f: Dictionary = run.state["f"]
		if f.is_empty():
			continue
		# Spend it down. Cards are laid one at a time because laying one changes
		# what the rest cost against.
		var spending := true
		while spending:
			spending = false
			for c in run.state["f"]["hand"].duplicate():
				if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]) and int(c.get("cost", 0)) > 0:
					run.lay_card(c["uid"])
					spending = true
					break
		f = run.state["f"]
		if int(f["energy"]) > 0 or f["hand"].is_empty():
			continue   # not the state under test

		var instance: Node = load("res://scenes/Reading.tscn").instantiate()
		root.add_child(instance)
		for i in 4:
			await process_frame
		checked += 1
		var focused: Control = instance.get_viewport().gui_get_focus_owner()
		if focused == null:
			printerr("FAIL: a reading with %d unaffordable card(s) and no energy left focused nothing — there is no way to reach READ IT without a mouse"
				% f["hand"].size())
		elif not instance.is_ancestor_of(focused):
			printerr("FAIL: focus went outside the reading screen (%s)" % focused)
		instance.queue_free()
		await process_frame
	if checked == 0:
		printerr("FAIL: precondition — no reading ran out of energy with cards still in hand, so this checked nothing")
	else:
		print("--- a reading with the energy spent still has somewhere to put focus (%d checked) ---" % checked)


## Builds the main menu under the given look settings and reports the first
## Label's font size and colour.
func _sample_label(scale: float, high_contrast: bool) -> Dictionary:
	var settings: Node = root.get_node("Settings")
	settings.set_value("text_scale", scale)
	settings.set_value("high_contrast", high_contrast)
	var instance: Node = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	var found := _first_label(instance)
	var out := {}
	if found != null:
		out = {"size": found.get_theme_font_size("font_size"), "color": found.get_theme_color("font_color")}
	instance.queue_free()
	await process_frame
	return out


func _first_label(node: Node) -> Label:
	if node is Label and not (node as Label).text.is_empty():
		return node
	for child in node.get_children():
		var found := _first_label(child)
		if found != null:
			return found
	return null


## The Minitel screen's own wiring. test_minitel.gd drives the autoload
## directly and so would pass with an ENVOI button connected to nothing —
## which is precisely the shape of bug a screen this thin can have. Presses
## the real button and checks the code came out the other end.
func _test_minitel_screen_dials() -> void:
	var profile: Node = root.get_node("Profile")
	var minitel: Node = root.get_node("Minitel")
	var before: Array = minitel.entered()

	var instance: Node = load("res://scenes/MinitelScreen.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	instance._prefix_field.text = "3615"
	instance._code_field.text = "oeil"
	# I18n by get_node(), not by its global name: this script is compiled by
	# `godot -s` BEFORE the autoloads are registered, so the bare identifier
	# does not resolve here. Same trap as autoload/Nav.gd's header describes.
	var envoi := _find_button(instance, root.get_node("I18n").t("ENVOI"))
	if envoi == null:
		printerr("FAIL: the minitel screen has no ENVOI button")
	else:
		envoi.pressed.emit()
		await process_frame
		if not minitel.entered().has("OEIL"):
			printerr("FAIL: pressing ENVOI did not dial — the screen is not wired to Minitel.submit()")
		else:
			print("--- minitel screen dials (%s) ---" % [minitel.entered()])

	instance.queue_free()
	await process_frame
	profile.set_stat("codes_entered", before)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _visit_scene(label: String, scene_path: String) -> void:
	print("--- BEGIN ", label, " ---")
	var packed: PackedScene = load(scene_path)
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	# focus_first() defers a frame, so give it one more before looking.
	await process_frame
	_check_focus(label, instance)
	instance.queue_free()
	await process_frame
	print("--- END ", label, " (", scene_path, ") ---")


## Focus being placed is only half of it: the focused thing has to actually do
## something when activated. Cards and map options are PanelContainers, not
## Buttons, so nothing about that is free — it is the ui_accept branch in
## UIKit.make_interactive(), and without it a keyboard player could tab around
## a hand of cards and never play one.
##
## Drives the real path (a key event pushed at the viewport, routed by Godot to
## whatever holds focus) rather than calling the handler directly, since what is
## in doubt is the routing as much as the handler.
func _test_keyboard_can_play() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	for i in run.state["options"].size():
		if run.state["options"][i]["kind"] in ["sitter", "elite"]:
			run.choose(i)
			break

	var instance: Node = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame

	var laid_before: int = run.state["f"]["cross"].size()
	var focused: Control = instance.get_viewport().gui_get_focus_owner()
	if focused == null:
		printerr("FAIL: the reading screen focused nothing, so ui_accept has nowhere to land")
	else:
		var press := InputEventAction.new()
		press.action = "ui_accept"
		press.pressed = true
		instance.get_viewport().push_input(press)
		await process_frame
		var laid_after: int = run.state["f"]["cross"].size()
		if laid_after <= laid_before:
			printerr("FAIL: ui_accept on a focused card laid nothing (%d -> %d) — the hand is mouse-only" % [laid_before, laid_after])
		else:
			print("--- keyboard can lay a card (%d -> %d) ---" % [laid_before, laid_after])

	instance.queue_free()
	await process_frame


## Every screen has to leave keyboard focus somewhere, or the first Tab or
## D-pad press does nothing and a player without a mouse is simply stuck. This
## is cheap to assert and easy to lose: focus_first() takes the first focusable
## Control it finds, so a screen whose interactive rows stop being focusable —
## which is exactly what every card and every map option was until now — fails
## to place it and nothing else notices.
##
## Screens with genuinely no interactive controls would be exempt, listed by
## name rather than waved through by a null check, so that adding a button to
## one and forgetting to focus it still fails here. There are none today.
const NO_CONTROLS: Array[String] = []


func _check_focus(label: String, instance: Node) -> void:
	_check_room(label, instance)
	_check_styled(label, instance)
	var focused: Control = instance.get_viewport().gui_get_focus_owner()
	if focused == null:
		if not NO_CONTROLS.has(label):
			printerr("FAIL: %s left nothing focused — keyboard and gamepad players cannot start here" % label)
	elif not instance.is_ancestor_of(focused):
		printerr("FAIL: %s focused a node outside itself (%s)" % [label, focused])
	elif focused is BaseButton and (focused as BaseButton).disabled:
		# Godot places focus on a disabled Button quite happily, so "something
		# is focused" is not enough — a player pressing Confirm on arrival would
		# get nothing and have no way to know why. The settings rail disables
		# its selected entry, which put it first in line for focus.
		printerr("FAIL: %s focused a DISABLED control (%s) — pressing Confirm there does nothing" % [label, focused])


## EVERY SCREEN A RUN CAN BE ON HAS A WAY OFF IT.
##
## For most of the port there was none. Pressing BEGIN on the main menu took you
## to the sign screen, which had no BACK; picking a reader took you into a run,
## whose header offered DECK, MARKS, RULES and SETTINGS — and SETTINGS came back
## to the run it was opened from. The ending offered BEGIN AGAIN. So from the
## moment a player pressed BEGIN, the Library, the Minitel, the mods list and
## QUIT were unreachable for the rest of the session, and the only way to leave
## the game was the window's close button.
##
## Nothing about that is visible: a screen with no exit looks exactly like a
## screen. Hence a check that runs on every screen the sweep builds rather than
## one written per screen, so a fourteenth screen inherits it.
##
## Asked as a GROUP rather than by matching button text, so it cannot be
## satisfied by a label that happens to read MENU, and it does not break the
## first time somebody translates one.
func _check_way_out(label: String, instance: Node) -> void:
	# load(), not preload() — see _test_the_overlays_are_modal().
	var UIKitScript := load("res://scenes/UIKit.gd")
	var out: Array = []
	for node in _all_of(instance, []):
		if node.is_in_group(UIKitScript.WAY_OUT):
			out.append(node)
	if out.is_empty():
		printerr("FAIL: %s has no way back to the main menu — from here the Library, the Minitel and QUIT are all unreachable" % label)
		return
	# Present is not the same as usable. Disabled is the one this can really
	# check: UIKit.button() connects a sound wrapper to every button it makes, so
	# "has a connection" is true of any button built the normal way and only
	# catches a bare Button.new() dropped into the group. Kept for that case, and
	# named honestly rather than treated as proof the exit goes anywhere.
	for node in out:
		if node is BaseButton and (node as BaseButton).disabled:
			printerr("FAIL: %s has a way out that is disabled" % label)
		elif node is BaseButton and (node as BaseButton).pressed.get_connections().is_empty():
			printerr("FAIL: %s has a way-out control that nothing at all is connected to (%s)" % [label, node])


## EVERY SCREEN IS SOMEWHERE. The game is set in one room and every screen is a
## view of it — the table, the door, or the bare wall — so no screen should be a
## rectangle of flat colour with widgets on it. That is what the whole game was
## before, and the way back to it is not a decision anyone makes: it is somebody
## adding a fourteenth screen and not knowing there was anything to remember.
##
## Called from _check_focus(), so every scene the sweep above visits is checked,
## including any added later. The room comes from UIKit.root_control() precisely
## so a screen cannot forget it — this is the assertion that that stays true.
##
## It also has to be BEHIND the screen. A backdrop drawn over the words is worse
## than no backdrop, and nothing else would notice.
func _check_room(label: String, instance: Node) -> void:
	var room := instance.find_child("Room", true, false)
	if room == null:
		printerr("FAIL: %s has no room behind it — it is a flat rectangle with widgets on it" % label)
		return
	var siblings: int = room.get_parent().get_child_count()
	if room.get_index() > 1:
		printerr("FAIL: %s draws its room at position %d of %d — it is over the screen, not behind it"
			% [label, room.get_index(), siblings])


## NOTHING WEARS GODOT'S DEFAULT THEME.
##
## The game is a drawn parlour, and Godot's stock Button is a grey slab with
## square-ish corners and no relationship to anything else on screen. Every
## Button and LineEdit goes through UIKit.style_button() / style_field()
## instead — and the way that stops being true is not a decision anyone makes,
## it is somebody writing `Button.new()` on a new screen because that is what
## the engine's documentation says. Two already existed when this was written
## (the run header's chips and the keybind rows) and both looked wrong.
##
## Called from _check_focus(), so every scene the sweep visits is checked,
## including ones added later.
func _check_styled(label: String, instance: Node) -> void:
	for node in _all_of(instance, []):
		# CheckButton and CheckBox are exempt: what they look like IS the
		# toggle graphic, and a panel behind one reads as a button that also
		# happens to have a switch on it.
		if node is CheckBox or node is CheckButton:
			continue
		if node is Button and not (node as Button).has_theme_stylebox_override("normal"):
			printerr("FAIL: %s has an unstyled Button ('%s') — it is wearing Godot's grey default"
				% [label, (node as Button).text])
			return
		if node is LineEdit and not (node as LineEdit).has_theme_stylebox_override("normal"):
			printerr("FAIL: %s has an unstyled LineEdit — it is wearing Godot's grey default" % label)
			return


func _all_of(node: Node, out: Array) -> Array:
	out.append(node)
	for child in node.get_children():
		_all_of(child, out)
	return out


## The in-run SETTINGS chip has to remember which screen to come back to,
## or a player who opens settings mid-run gets dumped at the main menu with
## their run still live but unreachable. Checks the handoff Nav does, rather
## than the scene swap itself (which is deferred to idle and so isn't
## observable from inside the frame that triggers it).
func _test_settings_return_path() -> void:
	var nav: Node = root.get_node("Nav")
	nav.settings_return_scene = ""
	nav.goto_settings("res://scenes/Map.tscn")
	if nav.settings_return_scene != "res://scenes/Map.tscn":
		printerr("FAIL: Nav should record the return scene, got '%s'" % nav.settings_return_scene)
	else:
		print("--- settings return path OK ---")
	nav.settings_return_scene = ""


func _visit(label: String, setup: Callable) -> void:
	print("--- BEGIN ", label, " ---")
	setup.call()
	var scene_path: String = Nav.SCENES.get(run.state["screen"], "res://scenes/MainMenu.tscn")
	if run.state["screen"] == "read" and not run.state.get("res", {}).is_empty():
		scene_path = "res://scenes/ResultScreen.tscn"
	var packed: PackedScene = load(scene_path)
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	# focus_first() defers a frame, so give it one more before looking.
	await process_frame
	_check_focus(label, instance)
	# Only the screens a RUN can be on, which is what _visit builds. The menus
	# _visit_scene reaches are what a way out leads TO, and each has its own BACK.
	_check_way_out(label, instance)
	instance.queue_free()
	await process_frame
	print("--- END ", label, " (", scene_path, ") ---")
