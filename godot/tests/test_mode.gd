## The two views (autoload/Mode.gd): what a player sees, and the workshop.
##   godot --headless --path godot -s tests/test_mode.gd
##
## The promise is one sentence: in the play view, nothing on any screen a
## player can reach talks about how the game is made. That is measured, not
## assumed — every such screen is built in the play view and every word on it
## read, the way a player would, for the marks the workshop leaves: file paths,
## .json and .md, the prototype, placeholders, the engine outside its licence
## line. The main menu's subtitle said "Godot vertical-slice port" to every
## player until this was asked.
##
## And the other half: the workshop's doors are there in the work view, the
## view cannot be opened on a machine that was never given it, and 3615 ATEL is
## the way in for a build that was handed to someone.
extends "res://tests/harness.gd"

## What the workshop writes and a player should never read.
const MARKS := ["docs/", ".json", ".md", "res://", "user://mods", "mods_example", "prototype",
	"placeholder", "Placeholder", "PLACEHOLDER", "vertical-slice", "simulate(", "GodotSteam", "App ID",
	"STUDIO", "LIBRARY", "MODS", "unfilled", "Parlour v23"]

## The one line that may name the engine: the credit its licence requires.
const ALLOWED := ["MIT licence"]

var mode: Node
var run: Node
var content: Node
var _unlocked_before := false
var _work_before := false


func setup() -> void:
	mode = root.get_node("Mode")
	run = root.get_node("Run")
	content = root.get_node("Content")
	_unlocked_before = mode.unlocked
	_work_before = mode.work
	root.size = Vector2i(1280, 720)
	root.get_node("Settings").set_value("locale", "en")
	root.get_node("I18n").reload()


func teardown() -> void:
	mode.unlocked = _unlocked_before
	mode.work = _work_before
	mode._save()


func _test_no_screen_a_player_reaches_talks_about_the_workshop() -> void:
	mode.unlocked = true
	mode.work = false
	var screens := _player_screens()
	for entry in screens:
		var texts: Array = await _texts_on(entry[0], entry[1], entry[2])
		for t in texts:
			if ALLOWED.any(func(a): return t.contains(a)):
				continue
			for m in MARKS:
				if t.contains(m):
					check(false, "the %s screen shows \"%s\" to a player (contains %s)" % [entry[0], t.left(120), m])
	# Every section a player can open in the settings, not just the first.
	var sections: Array = root.get_node("Settings").sections_for(false)
	for i in sections.size():
		var texts: Array = await _texts_on("settings — %s" % sections[i]["id"], "res://scenes/SettingsMenu.tscn", func(): pass, i)
		for t in texts:
			for m in MARKS:
				if t.contains(m):
					check(false, "settings — %s shows \"%s\" to a player (contains %s)" % [sections[i]["id"], t.left(120), m])
	done()


## The same screens, the workshop view: its doors are all there.
func _test_the_workshop_has_its_doors() -> void:
	mode.unlocked = true
	mode.work = true
	var menu: Array = await _texts_on("main menu", "res://scenes/MainMenu.tscn", func(): pass)
	for door in ["STUDIO", "LIBRARY", "MODS"]:
		check(menu.has(door), "the work view's main menu should offer %s, it shows %s" % [door, menu])
	check(root.get_node("Settings").sections_for(true).size() > root.get_node("Settings").sections_for(false).size(),
		"the work view should offer the workshop's settings sections too")
	mode.work = false
	menu = await _texts_on("main menu", "res://scenes/MainMenu.tscn", func(): pass)
	for door in ["STUDIO", "LIBRARY", "MODS"]:
		check(not menu.has(door), "the play view's main menu should not offer %s" % door)
	done()


func _test_the_view_cannot_be_opened_where_it_was_never_given() -> void:
	mode.unlocked = false
	mode.work = false
	mode.set_work(true)
	check(not mode.is_work(), "a machine that was never given the work view cannot switch to it")
	var f12 := InputEventKey.new()
	f12.keycode = KEY_F12
	f12.pressed = true
	mode._input(f12)
	check(not mode.is_work(), "and F12 does nothing there")
	# 3615 ATEL, on the Minitel, is the way in.
	var said: Dictionary = root.get_node("Minitel").submit("3615", "ATEL")
	check(str(said.get("kind", "")) == "ok", "3615 ATEL should be answered, got %s" % said.get("kind"))
	check(mode.unlocked and mode.is_work(), "and it should open the work view on this machine")
	check(root.get_node("Minitel").submit("3615", "ATEL").get("kind") == "ok", "it can be dialled again")
	done()


func _test_the_studio_sends_a_player_home() -> void:
	mode.unlocked = true
	mode.work = false
	var s: Node = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	check(s.get_child_count() == 0, "the studio should build nothing in the play view")
	s.free()
	await process_frame
	done()


# ── helpers ──────────────────────────────────────────────────────────────

func _player_screens() -> Array:
	var to_map := func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
	var to_reading := func():
		to_map.call()
		for i in run.state["options"].size():
			if run.state["options"][i]["kind"] in ["sitter", "elite"]:
				run.choose(i)
				break
	return [
		["main menu", "res://scenes/MainMenu.tscn", func(): pass],
		["credits", "res://scenes/Credits.tscn", func(): pass],
		["how to play", "res://scenes/HowToPlay.tscn", func(): pass],
		["records", "res://scenes/Records.tscn", func(): pass],
		["minitel", "res://scenes/MinitelScreen.tscn", func(): pass],
		["sign", "res://scenes/SignSelect.tscn", func(): run.state = run.fresh()],
		["gift", "res://scenes/PickScreen.tscn", func(): run.state = run.fresh(); run.pick_reader(0)],
		["map", "res://scenes/Map.tscn", to_map],
		["reading", "res://scenes/Reading.tscn", to_reading],
	]


## Every word on a screen as a player sees it: labels, buttons, rich text. The
## second argument of a settings screen picks the section to open.
func _texts_on(label: String, path: String, setup_fn: Callable, section: int = -1) -> Array:
	setup_fn.call()
	var s: Node = load(path).instantiate()
	if section >= 0:
		s.set("_section", section)
	root.add_child(s)
	for i in 3:
		await process_frame
	var out: Array = []
	for n in s.find_children("*", "", true, false):
		if n.is_queued_for_deletion() or not (n is CanvasItem) or not n.is_visible_in_tree():
			continue
		if n is Label or n is Button or n is RichTextLabel:
			var t := str(n.text).strip_edges()
			if t != "":
				out.append(t)
	s.queue_free()
	await process_frame
	return out
