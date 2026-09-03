## Dev-only tool (not part of the test suite): boots a scene under a real
## (Xvfb) display, lets it settle, and saves a PNG. Not run in CI — used
## interactively during visual work since this environment has no
## interactive display of its own. Run with:
##   xvfb-run -a godot --path godot -s tests/screenshot.gd -- <scene_setup> <out.png> [settle_seconds]
## where <scene_setup> is one of the keys in _setup() below.
##
## settle_seconds (default 1.2) is how long to let animations run before
## capturing. Pass a small value (e.g. 0.12) to catch a frame mid-tween —
## that's how the animation work was verified, since a single PNG can't show
## motion but a pair of them at different settle times can show that
## something is in fact moving (a half-filled bar at 0.12s vs. a full one at
## 1.2s proves the tween is running, not just that the end state is right).
extends SceneTree

var content: Node
var run: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	# Autoloads' own _ready() (Run's sets state = fresh(), Content's calls
	# reload()) doesn't fire synchronously here — it's deferred to the first
	# process frame, same as any other node entering the tree. Since this
	# script awaits several frames further down (to let the instantiated
	# scene's own _ready() build its UI), doing our state setup before that
	# first frame would just get silently overwritten the moment Run._ready()
	# finally fires. Wait it out up front instead, then everything after this
	# point is the last writer and sticks.
	await process_frame
	content.reload()

	var args := OS.get_cmdline_user_args()
	var setup_name := args[0] if args.size() > 0 else "sign"
	var out_path := args[1] if args.size() > 1 else "/tmp/screenshot.png"
	var settle: float = float(args[2]) if args.size() > 2 else 1.2
	# Optional 4th arg: locale to render in, for checking a translation.
	# Settings are persisted to user://settings.cfg, so setting this used to
	# leave the locale changed for every later run of the game and the tools —
	# which is exactly how a later English screenshot came back in French.
	# Put it back before quitting.
	var restore_locale := ""
	if args.size() > 3:
		var settings: Node = root.get_node("Settings")
		restore_locale = str(settings.get_value("locale"))
		settings.set_value("locale", args[3])
		root.get_node("I18n").reload()

	# Standalone screens aren't reachable from Run.state's "screen" field —
	# they're menus, not run states — so they're addressed by name directly.
	const STANDALONE := {
		"menu": "res://scenes/MainMenu.tscn",
		"settings": "res://scenes/SettingsMenu.tscn",
		"library": "res://scenes/Library.tscn",
		"mods": "res://scenes/ModsScreen.tscn",
		"minitel": "res://scenes/MinitelScreen.tscn",
		"help": "res://scenes/HowToPlay.tscn",
		"credits": "res://scenes/Credits.tscn",
		"menu_saved": "res://scenes/MainMenu.tscn",
	}
	var scene_path: String
	if STANDALONE.has(setup_name):
		# "menu_saved" is the main menu with a resumable run behind it, which is
		# a different screen (CONTINUE plus a line describing the run) and the
		# only way to see that branch.
		if setup_name == "menu_saved":
			_setup("map")
			root.get_node("Save")._write()
		scene_path = STANDALONE[setup_name]
	else:
		_setup(setup_name)
		scene_path = Nav.SCENES.get(run.state["screen"], "res://scenes/MainMenu.tscn")
		if run.state["screen"] == "read" and not run.state.get("res", {}).is_empty():
			scene_path = "res://scenes/ResultScreen.tscn"

	var packed: PackedScene = load(scene_path)
	var instance: Node = packed.instantiate()
	root.add_child(instance)

	# Let the scene lay out, then run animations for `settle` seconds of
	# real time. create_timer() is driven by the same frame loop the tweens
	# are, so this advances them rather than just sleeping past them.
	for i in 3:
		await process_frame
	if settle > 0.0:
		await create_timer(settle).timeout

	# Optional 5th arg: text of a Button to press before capturing, so the
	# modal overlays (deck, marks) can be screenshotted — they only exist
	# after a click, and a static capture can't click for itself.
	if args.size() > 4:
		var pressed := _press_button(instance, args[4])
		if not pressed:
			printerr("no button matching '%s' found" % args[4])
		for i in 3:
			await process_frame
		await create_timer(0.6).timeout

	if OS.get_environment("PARLOUR_DEBUG_SIZES") == "1":
		_debug_sizes(instance)

	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path, " (", scene_path, ", settled ", settle, "s)")
	if restore_locale != "":
		root.get_node("Settings").set_value("locale", restore_locale)
	quit(0)


## Activates whatever matches `needle`, by its visible text.
##
## Real Buttons are easy. The rows built by UIKit.panel_button()/card_face()
## are not Buttons at all — they are PanelContainers holding Labels, which is
## every card in hand, every sitter on the map, every reward and every row in
## the Library. So the tool could not click on ANY of the game's actual
## choices, only its chrome, which made screenshotting anything that needs a
## selection first impossible. Those rows now get a synthetic click through the
## same gui_input path a real mouse takes.
func _press_button(n: Node, needle: String) -> bool:
	if n is Button and str(n.text).contains(needle):
		n.emit_signal("pressed")
		return true
	if n is PanelContainer and (n as Control).focus_mode == Control.FOCUS_ALL and _text_of(n).contains(needle):
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		(n as Control).gui_input.emit(click)
		return true
	for child in n.get_children():
		if _press_button(child, needle):
			return true
	return false


## Every Label under `n`, joined — what a person would read on that row.
func _text_of(n: Node) -> String:
	var parts: Array[String] = []
	if n is Label:
		parts.append((n as Label).text)
	for child in n.get_children():
		parts.append(_text_of(child))
	return " ".join(parts)


func _debug_sizes(n: Node, depth: int = 0) -> void:
	if n is Control:
		var c: Control = n
		var tip := c.tooltip_text
		var tip_note := "" if tip == "" else (" tooltip=%d chars" % tip.length())
		print("  ".repeat(depth), n.get_class(), " ", n.name, " size=", c.size, " min=", c.get_minimum_size(), " flags_h=", c.size_flags_horizontal, tip_note)
	for child in n.get_children():
		_debug_sizes(child, depth + 1)


func _setup(name: String) -> void:
	match name:
		"sign":
			run.state = run.fresh()
		"gift":
			run.state = run.fresh()
			run.pick_reader(0)
		"map":
			run.state = run.fresh()
			run.pick_reader(0)
			run.take_pick(0)
		"read", "read_cancer":
			run.state = run.fresh()
			# Cancer (index 3) starts holding Pour The Tea, which is the card
			# the art-pipeline test image is attached to — handy for checking
			# delivered card art actually renders in the hand.
			run.pick_reader(3 if name == "read_cancer" else 0)
			run.take_pick(0)
			var sitter_idx := -1
			for i in run.state["options"].size():
				if run.state["options"][i]["kind"] in ["sitter", "elite"]:
					sitter_idx = i
					break
			if OS.get_environment("PARLOUR_DEBUG_SIZES") == "1":
				print("options: ", run.state["options"], " sitter_idx=", sitter_idx)
			run.choose(sitter_idx)
			if OS.get_environment("PARLOUR_DEBUG_SIZES") == "1":
				print("after choose, screen=", run.state["screen"], " f=", run.state["f"])
		"read_taurus":
			# The one sign with a denial WALL, so the reading screen's wall
			# readout and its "what it becomes next reading" preview have
			# something to show. Every other sign leaves both at zero, which is
			# why the plain "read" setup can't be used to check them.
			_setup("read")
			var f: Dictionary = run.state["f"]
			f["quirk"] = content.get_sign("taurus")
			f["denial"] = int(f["sitter"]["denial"])
			f["denialUp"] = int(content.denial_shield.get("shield", 0))
		"marks":
			# Grant a couple of marks so the "what's on your hands" overlay has
			# something to show — they're otherwise only reachable by winning
			# an elite, which a screenshot can't wait around for.
			_setup("read")
			run.state["marks"] = [content.marks[0], content.relics[0]]
		"read_marked":
			# One mark of EVERY kind, so the drawing on the hands can actually be
			# looked at. Table.gd draws a ring, a tattoo, a scar and a boon
			# differently, and until there is a run carrying all four on screen
			# at once, three of those four have never been seen.
			_setup("read")
			var kinds := ["RING", "TATTOO", "SCAR", "BOON"]
			var worn: Array = []
			for kind in kinds:
				for m in content.marks:
					if str(m.get("kind", "")) == kind:
						# Twice each: the second one has to land on a different
						# finger / a different place, and a bug that stacks them
						# all on top of each other only shows with two.
						worn.append(m)
						worn.append(m)
						break
			run.state["marks"] = worn
		"read_laid":
			_setup("read")
			var f: Dictionary = run.state["f"]
			for c in f["hand"].duplicate():
				if int(c.get("cost", 0)) <= int(run.state["f"]["energy"]):
					run.lay_card(c["uid"])
		"win":
			_setup("read")
			var f: Dictionary = run.state["f"]
			f["hp"] = f["max"]
			run.win(f)
		"reward":
			_setup("win")
			run.after_res()
		"over":
			_setup("win")
			run.after_res()
			run.skip_pick()
			# fast-forward: just force endRun for a screenshot rather than
			# playing 23 more knocks.
			run.end_run("done")
