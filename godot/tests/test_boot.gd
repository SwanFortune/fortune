## Headless test that the game STARTS.
##   godot --headless --path godot -s tests/test_boot.gd
##
## Nothing tested this. tests/test_scenes.gd instantiates each screen directly
## and drives it, which is the right way to test a screen and never once goes
## through the project's actual main scene — so the path every player takes,
## and the only path that runs on launch, was the one path with no coverage.
##
## What that cost: `Boot._ready()` called change_scene_to_file() synchronously,
## which frees the current scene while the tree is still adding Boot as a child,
## and Godot printed
##
##   ERROR: Parent node is busy adding/removing children
##
## on every single launch since the first commit. Harmless, invisible to the
## suite, and found only by exporting a build and running it.
##
## The guarantees under test:
##   - booting reaches the main menu, rather than sitting on the boot scene;
##   - it does so promptly — a deferred call is one frame, not "eventually";
##   - the boot scene has nothing in it to get stuck on. Boot exists to give
##     content loading somewhere to put a spinner later; if it ever grows real
##     work, that work must not be able to leave the player on a blank screen.
##
## The engine's own ERROR lines are not visible to GDScript, so the absence of
## that message is checked the only way it can be — by running the real thing
## and reading the output. See the README's Tests section for the one-liner.
extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame

	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene == "":
		failures.append("the project has no main scene set — there is nothing to launch")
		_report()
		return

	var packed: PackedScene = load(main_scene)
	if packed == null:
		failures.append("the main scene (%s) does not load" % main_scene)
		_report()
		return

	var boot: Node = packed.instantiate()
	root.add_child(boot)

	# One frame for _ready, one for the deferred call to run, one for the scene
	# swap itself. If it needs materially more than this, something is doing
	# real work on the boot path and the player is looking at nothing while it
	# happens — worth failing over rather than waiting longer.
	var reached := ""
	for i in 6:
		await process_frame
		var scene := current_scene
		if scene != null and scene.scene_file_path != main_scene:
			reached = scene.scene_file_path
			break

	if reached == "":
		failures.append("booting never left %s — the game does not start" % main_scene)
	elif reached != "res://scenes/MainMenu.tscn":
		failures.append("booting landed on %s, expected the main menu" % reached)

	if is_instance_valid(boot):
		boot.queue_free()
	await process_frame
	_report()


func _report() -> void:
	if failures.is_empty():
		print("ALL PASS — the game boots to the main menu")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)
