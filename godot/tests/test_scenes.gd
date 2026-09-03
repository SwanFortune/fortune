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

	print("SCENE SWEEP DONE")
	quit(0)


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
	await _test_every_settings_section_builds()
	await _test_look_settings_reach_a_built_screen()
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
	instance.queue_free()
	await process_frame
	print("--- END ", label, " (", scene_path, ") ---")
