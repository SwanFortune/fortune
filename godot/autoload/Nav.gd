## Autoload. Tiny scene router: maps Run.state's "screen" (and the nested
## "res" win/lose popup) to the scene file that should be showing. Called
## explicitly by a UI scene right after it invokes a Run.* method that
## changes state — kept manual (not signal-driven) so a scene never reacts to
## a state change caused by a *different*, already-torn-down scene.
##
## Autoload singletons are reached here via get_node() rather than by their
## global name (`Run.state`). Those globals are registered from project.godot
## during startup, but a script launched with `godot -s` is compiled BEFORE
## that registration — and compiling it pulls in whatever it references, so
## this file used to fail to compile in that context ("Identifier not found:
## Run"), which silently left the Nav autoload as a plain scriptless Node.
## In-game everything worked, so it looked like harmless console noise; it
## actually meant any headless tool touching Nav's members hit a missing
## property. Resolving at call time instead makes this file compile
## standalone and behave identically either way.
extends Node

const SCENES := {
	"sign": "res://scenes/SignSelect.tscn",
	"pick": "res://scenes/PickScreen.tscn",
	"map": "res://scenes/Map.tscn",
	"read": "res://scenes/Reading.tscn",
	"over": "res://scenes/RunOver.tscn",
}

## Where SettingsMenu's BACK should return to. Set by whoever opens settings;
## empty means "the main menu". Lives here rather than being passed into the
## scene because change_scene_to_file() gives no way to hand the incoming
## scene an argument.
var settings_return_scene: String = ""

## Same idea for the rules screen, which is reachable from the main menu and
## (as an overlay) from inside a run.
var help_return_scene: String = ""


func _run() -> Node:
	return get_node_or_null("/root/Run")


## Goes to whichever scene Run.state currently calls for. If we're mid-reading
## and a result (win/lose) just landed, that takes priority over the "read" screen.
func goto_for_state() -> void:
	var run := _run()
	if run == null:
		return
	var st: Dictionary = run.state
	if st.get("screen", "") == "read" and not st.get("res", {}).is_empty():
		_goto("res://scenes/ResultScreen.tscn")
		return
	_goto(SCENES.get(st.get("screen", ""), "res://scenes/MainMenu.tscn"))


func goto_settings(return_scene: String = "") -> void:
	settings_return_scene = return_scene
	_goto("res://scenes/SettingsMenu.tscn")


func goto_records() -> void:
	_goto("res://scenes/Records.tscn")


func goto_library() -> void:
	_goto("res://scenes/Library.tscn")


func goto_mods() -> void:
	_goto("res://scenes/ModsScreen.tscn")


func goto_minitel() -> void:
	_goto("res://scenes/MinitelScreen.tscn")


func goto_how_to_play(return_scene: String = "") -> void:
	help_return_scene = return_scene
	_goto("res://scenes/HowToPlay.tscn")


func goto_main_menu() -> void:
	_goto("res://scenes/MainMenu.tscn")


func _goto(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.change_scene_to_file(path)
