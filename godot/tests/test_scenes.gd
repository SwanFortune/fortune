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
	await _visit_scene("settings", "res://scenes/SettingsMenu.tscn")
	await _visit_scene("library", "res://scenes/Library.tscn")


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
