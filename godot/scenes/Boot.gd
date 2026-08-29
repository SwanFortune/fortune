extends Node

## Boots straight into the main menu once autoloads (Content/Rules/Run) have
## finished loading. A separate boot scene (rather than making MainMenu the
## project's main scene directly) gives us one place to put a loading spinner
## later if content packs ever get big enough to need one.
func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
