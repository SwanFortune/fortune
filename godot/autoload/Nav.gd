## Autoload. Tiny scene router: maps Run.state's "screen" (and the nested
## "res" win/lose popup) to the scene file that should be showing. Called
## explicitly by a UI scene right after it invokes a Run.* method that
## changes state — kept manual (not signal-driven) so a scene never reacts to
## a state change caused by a *different*, already-torn-down scene.
extends Node

const SCENES := {
	"sign": "res://scenes/SignSelect.tscn",
	"pick": "res://scenes/PickScreen.tscn",
	"map": "res://scenes/Map.tscn",
	"read": "res://scenes/Reading.tscn",
	"over": "res://scenes/RunOver.tscn",
}


## Goes to whichever scene Run.state currently calls for. If we're mid-reading
## and a result (win/lose) just landed, that takes priority over the "read" screen.
func goto_for_state() -> void:
	var st: Dictionary = Run.state
	if st.get("screen", "") == "read" and not st.get("res", {}).is_empty():
		Engine.get_main_loop().change_scene_to_file("res://scenes/ResultScreen.tscn")
		return
	var path: String = SCENES.get(st.get("screen", ""), "res://scenes/MainMenu.tscn")
	Engine.get_main_loop().change_scene_to_file(path)
