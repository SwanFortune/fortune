## Autoload. Player settings, persisted to user://settings.cfg.
##
## Loaded before every other autoload (see project.godot's autoload order)
## because Content reads `load_example_mods` while building its registries and
## Run reads the gameplay knobs while starting a fight — both during their own
## _ready(), so this has to be ready first.
##
## Every setting here does something real. There is deliberately no setting
## that only looks like it works: `master_volume` drives the actual
## AudioServer master bus (the game ships no sound yet, so it is silent
## either way, but the wiring is genuine and needs no revisiting when audio
## lands), and `animation_scale` genuinely scales the UIKit tweens including
## an explicit 0 = off path.
extends Node

signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "parlour"

## key -> [default, minimum, maximum] for numeric settings, or [default] for
## the rest. Also the single source of truth for what a valid setting IS —
## set() rejects anything not listed, so a typo'd key fails loudly at the
## call site instead of silently persisting a value nothing ever reads.
const DEFS := {
	# display
	"fullscreen": [false],
	"ui_scale": [1.0, 0.75, 1.5],
	# audio (real AudioServer wiring; no sounds ship yet)
	"master_volume": [0.8, 0.0, 1.0],
	"muted": [false],
	# accessibility / feel
	"animation_scale": [1.0, 0.0, 2.0],
	# gameplay — the two knobs the prototype exposed as props (its cfg())
	"start_energy": [3, 1, 8],
	"hand_size": [5, 3, 10],
	# content
	"load_example_mods": [true],
}

var _values: Dictionary = {}


func _ready() -> void:
	load_from_disk()
	_apply_display()
	_apply_audio()


func get_value(key: String):
	if not DEFS.has(key):
		push_error("[Settings] unknown setting '%s'" % key)
		return null
	return _values.get(key, DEFS[key][0])


func set_value(key: String, value) -> void:
	if not DEFS.has(key):
		push_error("[Settings] unknown setting '%s'" % key)
		return
	var def: Array = DEFS[key]
	if def.size() == 3:
		value = clampf(float(value), float(def[1]), float(def[2]))
		if typeof(def[0]) == TYPE_INT:
			value = int(round(value))
	if _values.get(key) == value:
		return
	_values[key] = value
	save_to_disk()
	if key in ["fullscreen", "ui_scale"]:
		_apply_display()
	elif key in ["master_volume", "muted"]:
		_apply_audio()
	changed.emit(key)


func reset_to_defaults() -> void:
	_values.clear()
	save_to_disk()
	_apply_display()
	_apply_audio()
	changed.emit("")


func default_for(key: String):
	return DEFS[key][0] if DEFS.has(key) else null


## Multiplier every UIKit animation runs its duration through. 0 disables
## animation entirely (UIKit jumps to the end state rather than tweening).
func animation_scale() -> float:
	return float(get_value("animation_scale"))


func load_from_disk() -> void:
	_values.clear()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run, or an unreadable file: defaults are fine
	for key in DEFS:
		if cfg.has_section_key(SECTION, key):
			var raw = cfg.get_value(SECTION, key)
			# Guard against a hand-edited or version-skewed file handing us a
			# string where a number belongs, etc. A bad value falls back to
			# the default rather than propagating a wrong type into the game.
			if typeof(raw) == typeof(DEFS[key][0]):
				_values[key] = raw


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want_fs: bool = bool(get_value("fullscreen"))
	var mode := DisplayServer.window_get_mode()
	var is_fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fs != is_fs:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED
		)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.content_scale_factor = float(get_value("ui_scale"))


func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, bool(get_value("muted")))
	var vol: float = float(get_value("master_volume"))
	# linear_to_db(0) is -inf, which AudioServer takes but which reads badly
	# in logs; clamp the floor to a silent-but-finite -60dB instead.
	AudioServer.set_bus_volume_db(bus, -60.0 if vol <= 0.001 else linear_to_db(vol))
