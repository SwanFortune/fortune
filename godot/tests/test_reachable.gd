## EVERY CONTROL ON EVERY SCREEN CAN BE REACHED WITHOUT A MOUSE.
##
##     godot --headless --path godot -s tests/test_reachable.gd
##
## The suite already checked that each screen PLACES focus somewhere, which is
## where a keyboard player starts. It never asked where they can get to from
## there, and the answer was: not far.
##
##   - Godot's ScrollContainer has `follow_focus` OFF by default. Off means a
##     list only ever shows the rows it opened on — focus moves past the fold,
##     the view does not follow, and Godot's directional search then refuses to
##     hand focus to a control that is not on screen, so the chain closes early.
##     63 of the Library's 80 controls and the last four readers on the sign
##     screen could not be reached at all. Every one of them looked fine, was
##     focusable, was styled, and answered the mouse.
##   - On the sign screen, NOTHING could reach the difficulty's − button, in any
##     direction: from + going left, Godot picks the seed field on the row below,
##     whose rect overlaps the + horizontally, in preference to the − sitting
##     240px away past the difficulty's name. The ladder only went up.
##
## HOW IT ASKS. By pressing the keys. find_valid_focus_neighbor() answers from
## the rects as they are at that instant, and most of this game's focusable
## controls are inside a scroll that only brings them into view once focus
## arrives — so a static graph search declares the bottom of every list
## unreachable and is wrong in exactly the case that matters. This grabs a
## control, pushes a real ui_left/up/right/down, lets the frame settle, and sees
## where the focus went. Slower, and the only version that tells the truth: both
## methods were run against the same screens, and they disagreed.
##
## WHAT COUNTS AS REACHABLE is stated narrowly on purpose: a control that is
## visible, focusable and not disabled is one a player can see doing something,
## so if the keys cannot get there it is a control that exists only for the
## mouse.
extends SceneTree

const MAX_STEPS := 6000

var content: Node
var run: Node
var failures: Array[String] = []


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	await process_frame
	content.reload()
	# A real canvas: headless starts at 64px wide, where every control overlaps
	# every other one and "reachable" means nothing.
	root.size = Vector2i(1280, 720)
	# The Library reads the player's own card edits, and a leftover pack from an
	# earlier run would change how many rows there are to walk.
	root.get_node("CardEdits").revert_all()
	content.reload()

	await _walk("main menu", "res://scenes/MainMenu.tscn", func(): pass)
	await _walk("settings", "res://scenes/SettingsMenu.tscn", func(): pass)
	await _walk("library", "res://scenes/Library.tscn", func(): pass)
	await _walk("mods", "res://scenes/ModsScreen.tscn", func(): pass)
	await _walk("minitel", "res://scenes/MinitelScreen.tscn", func(): pass)
	await _walk("records", "res://scenes/Records.tscn", func(): pass)
	await _walk("how to play", "res://scenes/HowToPlay.tscn", func(): pass)
	await _walk("credits", "res://scenes/Credits.tscn", func(): pass)
	await _walk("sign", "res://scenes/SignSelect.tscn", func(): run.state = run.fresh())
	await _walk("pick (gift)", "res://scenes/PickScreen.tscn", func():
		run.state = run.fresh()
		run.pick_reader(0)
	)
	await _walk("map", "res://scenes/Map.tscn", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
	)
	await _walk("reading", "res://scenes/Reading.tscn", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
		for i in run.state["options"].size():
			if run.state["options"][i]["kind"] in ["sitter", "elite"]:
				run.choose(i)
				break
	)

	for f in failures:
		printerr("FAIL: ", f)
	if failures.is_empty():
		print("ALL PASS — every screen can be played through with the keys alone")
	quit(1 if not failures.is_empty() else 0)


func _walk(label: String, path: String, setup: Callable) -> void:
	setup.call()
	var instance: Node = load(path).instantiate()
	root.add_child(instance)
	# Four frames: one for _ready, one for the layout pass the rects come from,
	# and two for focus_first, which defers itself.
	for i in 4:
		await process_frame

	var here: Array[Control] = []
	_actionable(instance, here)
	var start := root.gui_get_focus_owner()
	if start == null:
		# Not this file's failure to report — _check_focus in test_scenes.gd owns
		# it — but without a starting point there is nothing to walk, and saying
		# so beats reporting every control on the screen as stranded.
		failures.append("%s places no focus at all, so there is nowhere to walk from" % label)
		instance.queue_free()
		await process_frame
		return

	var seen := {start.get_instance_id(): true}
	var frontier: Array[Control] = [start]
	var steps := 0
	while not frontier.is_empty() and steps < MAX_STEPS:
		var from: Control = frontier.pop_back()
		if not is_instance_valid(from) or not from.is_inside_tree():
			continue
		for action in ["ui_left", "ui_up", "ui_right", "ui_down"]:
			# Focus is put back before each direction so all four are tried from
			# the same place. Pressing them in sequence would walk away after the
			# first one and never ask the other three of this control.
			from.grab_focus()
			await process_frame
			var press := InputEventAction.new()
			press.action = action
			press.pressed = true
			root.push_input(press)
			await process_frame
			steps += 1
			var landed := root.gui_get_focus_owner()
			if landed == null or seen.has(landed.get_instance_id()):
				continue
			seen[landed.get_instance_id()] = true
			frontier.append(landed)

	if steps >= MAX_STEPS:
		failures.append("%s did not finish walking in %d presses — the screen is bigger than this test assumes" % [label, MAX_STEPS])

	var stranded: Array[String] = []
	for c in here:
		if not seen.has(c.get_instance_id()):
			stranded.append(_describe(c))
	if not stranded.is_empty():
		failures.append("%s strands %d of %d controls — no sequence of arrow keys reaches them, so they are mouse-only: %s"
			% [label, stranded.size(), here.size(), ", ".join(stranded.slice(0, 4))])

	instance.queue_free()
	await process_frame


## Visible, focusable, and not disabled — a control a player can see doing
## something. Disabled ones are excluded because Godot will not focus them and
## a player is not owed a route to a button that would do nothing.
func _actionable(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c: Control = node
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() \
				and not (c is BaseButton and (c as BaseButton).disabled):
			out.append(c)
	for child in node.get_children():
		_actionable(child, out)


## Enough to find the thing on screen. Most of the game's focusable controls are
## PanelContainers built at runtime, so their node names are @PanelContainer@281
## and useless in a failure message — the first label inside one is its title.
func _describe(c: Control) -> String:
	if c is Button and (c as Button).text != "":
		return "%s \"%s\"" % [c.get_class(), (c as Button).text]
	# Searched all the way down, not one level: panel_button() puts its lines in
	# a vbox inside the panel, so a direct-children-only look found nothing and
	# reported every stranded card row as "PanelContainer at (24, 699)".
	var title := _first_label(c)
	if title != "":
		return "%s \"%s\"" % [c.get_class(), title.substr(0, 24)]
	return "%s at %s" % [c.get_class(), c.get_global_rect().position]


func _first_label(node: Node) -> String:
	for child in node.get_children():
		if child is Label and (child as Label).text.strip_edges() != "":
			return (child as Label).text
		var deeper := _first_label(child)
		if deeper != "":
			return deeper
	return ""
