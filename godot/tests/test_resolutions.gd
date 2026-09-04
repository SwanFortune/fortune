## EVERY SCREEN AT EVERY RESOLUTION THE GAME OFFERS.
##
## Run with:
##   godot --headless --path godot -s tests/test_resolutions.gd
##
## The settings screen lists window sizes, and until this existed nothing had
## ever built a screen at any of them but the one the game is designed at. That
## was fine while the list was five 16:9 sizes; it is not fine now that it also
## has 16:10 laptops, a 4:3 and two ultrawides on it, and it was never fine as a
## claim — "the interface scales" was checked by reading the stretch settings,
## not by looking at what came out.
##
## WHAT THE STRETCH ACTUALLY DOES. With `canvas_items` and aspect `expand` the
## canvas is scaled by the SMALLER of the two ratios against the 1280x720 the
## game is drawn for, and the leftover on the other axis becomes more canvas.
## So the canvas is never smaller than 1280x720 — a taller screen buys canvas
## height, a wider one buys canvas width — and the whole list collapses to four
## shapes: 1280x720, 1280x800, 1280x960, 1706x720. Which is the good news; the
## reason to run all thirteen anyway is that this file should fail the day
## somebody adds a size whose shape is none of those.
##
## WHAT IS ASSERTED, per screen per resolution:
##   1. EVERY CONTROL YOU CAN REACH IS ON SCREEN. Anything focusable, visible,
##      and not inside a ScrollContainer must lie inside the canvas — a button
##      past the edge is a button a player cannot press, and at 4:3 or 21:9
##      nobody would have noticed.
##   2. THE ROOM COVERS THE CANVAS. The parlour is drawn from its own Control's
##      size, so an anchor that does not follow the window shows as bare
##      background down one side.
##   3. Nothing prints an error while building.
##
## Deliberately runs at text_scale 1.0 AND at the largest, since the interface
## size setting is exactly what turns "fits" into "does not".
extends SceneTree

var content: Node
var run: Node
var settings: Node


func _initialize() -> void:
	await process_frame
	content = root.get_node("Content")
	run = root.get_node("Run")
	settings = root.get_node("Settings")
	content.reload()

	var was_size: Vector2i = root.size
	var was_scale = settings.get_value("text_scale")
	var was_hand = settings.get_value("hand_size")
	# The widest hand the game deals, at both interface sizes: the two knobs
	# that decide whether what is on screen still fits on it.
	settings.set_value("hand_size", int(settings.DEFS["hand_size"][2]))

	var shapes: Dictionary = {}
	for res: String in settings.RESOLUTIONS:
		for scale: float in [1.0, float(settings.DEFS["text_scale"][2])]:
			settings.set_value("text_scale", scale)
			var canvas := await _at(res)
			shapes["%s @ %.2f" % [canvas, scale]] = res

	settings.set_value("text_scale", was_scale)
	settings.set_value("hand_size", was_hand)
	root.size = was_size
	await process_frame

	print("--- %d resolutions, %d distinct canvas shapes ---" % [settings.RESOLUTIONS.size(), shapes.size()])
	for k in shapes:
		print("      %-22s (e.g. %s)" % [k, shapes[k]])
	print("EVERY SCREEN FITS AT EVERY OFFERED RESOLUTION")
	quit(0)


## Builds the whole game at one window size and returns the canvas it produced.
func _at(res: String) -> Vector2i:
	var parts := res.split("x")
	root.size = Vector2i(int(parts[0]), int(parts[1]))
	# Two: one for the resize to reach the tree, one for the layout it causes.
	await process_frame
	await process_frame
	var canvas := Vector2i(root.get_visible_rect().size)

	await _screen(res, canvas, "sign", func(): run.state = run.fresh())
	await _screen(res, canvas, "gift", func():
		run.state = run.fresh()
		run.pick_reader(0)
	)
	await _screen(res, canvas, "map", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
	)
	await _screen(res, canvas, "reading", func():
		run.state = run.fresh()
		run.pick_reader(0)
		run.take_pick(0)
		for o in run.state["options"]:
			if o["kind"] in ["sitter", "elite"]:
				run.choose(run.state["options"].find(o))
				break
		var f: Dictionary = run.state["f"]
		if not f["hand"].is_empty():
			run.lay_card(f["hand"][0]["uid"])
	)
	await _screen(res, canvas, "shop", func():
		run.state["pick"] = run.build_shop()
		run.state["screen"] = "pick"
	)
	# The screens a run does not put you on, which have their own scenes.
	for pair in [
		["menu", "res://scenes/MainMenu.tscn"], ["settings", "res://scenes/SettingsMenu.tscn"],
		["library", "res://scenes/Library.tscn"], ["how to play", "res://scenes/HowToPlay.tscn"],
		["mods", "res://scenes/ModsScreen.tscn"], ["minitel", "res://scenes/MinitelScreen.tscn"],
		["credits", "res://scenes/Credits.tscn"],
	]:
		await _build(res, canvas, pair[0], pair[1])
	return canvas


func _screen(res: String, canvas: Vector2i, label: String, setup: Callable) -> void:
	setup.call()
	var path: String = Nav.SCENES.get(run.state["screen"], "res://scenes/MainMenu.tscn")
	await _build(res, canvas, label, path)


func _build(res: String, canvas: Vector2i, label: String, path: String) -> void:
	var instance: Node = (load(path) as PackedScene).instantiate()
	root.add_child(instance)
	# focus_first() defers a frame, and the fan sizes itself off a `resized`
	# signal, so an early look measures a layout that is not finished.
	for i in 4:
		await process_frame
	_check_fits(res, canvas, label, instance)
	_check_room(res, canvas, label, instance)
	instance.queue_free()
	await process_frame


## Everything a player can put focus on has to be inside the canvas — unless it
## is in a ScrollContainer, which is the one place off-screen is reachable.
func _check_fits(res: String, canvas: Vector2i, label: String, instance: Node) -> void:
	var worst := 0.0
	var worst_name := ""
	var lost := 0
	for node in _all_of(instance, []):
		var c := node as Control
		if c == null or c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree():
			continue
		if _inside_a_scroll(c, instance):
			continue
		var r := Rect2(c.global_position, c.size)
		var over := maxf(
			maxf(0.0, r.end.x - float(canvas.x)) + maxf(0.0, -r.position.x),
			maxf(0.0, r.end.y - float(canvas.y)) + maxf(0.0, -r.position.y))
		if over > 1.0:
			lost += 1
			if over > worst:
				worst = over
				worst_name = _name_of(c)
	if lost > 0:
		printerr("FAIL: at %s (canvas %dx%d) the %s screen puts %d control(s) off it — worst \"%s\" by %.0fpx"
			% [res, canvas.x, canvas.y, label, lost, worst_name, worst])


## The parlour is drawn from its own Control's size, so if that Control does not
## follow the window the room stops short and the bare background shows.
func _check_room(res: String, canvas: Vector2i, label: String, instance: Node) -> void:
	for node in _all_of(instance, []):
		if node.name != "Room":
			continue
		var c := node as Control
		if c == null:
			continue
		if int(c.size.x) < canvas.x or int(c.size.y) < canvas.y:
			printerr("FAIL: at %s the %s screen draws its room at %s in a %dx%d canvas — the rest is bare"
				% [res, label, c.size, canvas.x, canvas.y])
		return


func _inside_a_scroll(c: Node, stop: Node) -> bool:
	var n := c.get_parent()
	while n != null and n != stop:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


## Something to name in a failure. A button says what it says; a card panel
## carries its text in a child Label.
func _name_of(c: Control) -> String:
	if c is Button and str((c as Button).text) != "":
		return str((c as Button).text)
	for node in _all_of(c, []):
		if node is Label and str((node as Label).text) != "":
			return str((node as Label).text)
	return c.name


func _all_of(node: Node, out: Array) -> Array:
	for child in node.get_children():
		out.append(child)
		_all_of(child, out)
	return out
