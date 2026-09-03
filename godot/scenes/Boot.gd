extends Node

## Boots straight into the main menu once autoloads (Content/Rules/Run) have
## finished loading. A separate boot scene (rather than making MainMenu the
## project's main scene directly) gives us one place to put a loading spinner
## later if content packs ever get big enough to need one.
## Deferred, not called straight from _ready(). change_scene_to_file() frees the
## current scene, and _ready() runs while the tree is still in the middle of
## adding this node — so calling it here made Godot print
##
##   ERROR: Parent node is busy adding/removing children, `remove_child()`
##   can't be called at this time.
##
## on EVERY LAUNCH of the game, from the first commit. It was harmless (the
## menu still came up) and completely invisible to the test suite, because no
## test boots the game: test_scenes.gd instantiates each screen directly, which
## never goes through the main scene at all. It took exporting a build and
## running it to see the line.
func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/MainMenu.tscn")
