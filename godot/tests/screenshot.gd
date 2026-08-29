## Dev-only tool (not part of the test suite): boots a scene under a real
## (Xvfb) display, lets one frame settle, and saves a PNG. Not run in CI —
## used interactively during visual work since this environment has no
## interactive display of its own. Run with:
##   xvfb-run -a godot --path godot -s tests/screenshot.gd -- <scene_setup> <out.png>
## where <scene_setup> is one of the keys in SETUPS below.
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

	_setup(setup_name)
	var scene_path: String = Nav.SCENES.get(run.state["screen"], "res://scenes/MainMenu.tscn")
	if run.state["screen"] == "read" and not run.state.get("res", {}).is_empty():
		scene_path = "res://scenes/ResultScreen.tscn"

	var packed: PackedScene = load(scene_path)
	var instance: Node = packed.instantiate()
	root.add_child(instance)

	for i in 6:
		await process_frame

	if OS.get_environment("PARLOUR_DEBUG_SIZES") == "1":
		_debug_sizes(instance)

	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("saved ", out_path, " (", scene_path, ")")
	quit(0)


func _debug_sizes(n: Node, depth: int = 0) -> void:
	if n is Control:
		var c: Control = n
		print("  ".repeat(depth), n.get_class(), " ", n.name, " size=", c.size, " min=", c.get_minimum_size(), " flags_h=", c.size_flags_horizontal)
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
		"read":
			run.state = run.fresh()
			run.pick_reader(0)
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
