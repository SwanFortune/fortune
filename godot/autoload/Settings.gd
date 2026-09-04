## Autoload. Player settings, persisted to user://settings.cfg.
##
## Loaded before every other autoload (see project.godot's autoload order)
## because Content reads `load_example_mods` while building its registries and
## Run reads the gameplay knobs while starting a fight — both during their own
## _ready(), so this has to be ready first.
##
## EVERY SETTING HERE DOES SOMETHING REAL. The volumes drive AudioServer buses,
## `animation_scale` scales the UIKit tweens with an explicit 0 = off path,
## `max_fps` is Engine.max_fps. Do not add a row for something the game does not
## have — no music slider, no screen-shake toggle, no rumble — because each one
## is a control that lies to the player.
##
## tests/test_settings.gd asserts the pairing in both directions: no key here
## that the screen cannot reach, and no key the screen reaches that is not
## here.
extends Node

signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "parlour"

## key -> [default, minimum, maximum] for numeric settings, or [default] for
## the rest. Also the single source of truth for what a valid setting IS —
## set() rejects anything not listed, so a typo'd key fails loudly at the
## call site instead of silently persisting a value nothing ever reads.
## The four animation speeds, as multipliers. `dur()` divides by this, so a
## bigger number is a faster game.
##
## 1x, 2x, 4x, and INSTANT rather than Balatro's 0.5/1/2/4. Two reasons: the
## half-speed step is a control nobody reaches for, and 0 has to stay in the set
## because it is the reduced-motion path — every animation in the game checks
## UIKit.motion_off() and jumps to its end state. Folding that into the speed
## control keeps it to the four asked for instead of needing a fifth row.
const ANIMATION_SPEEDS := [1.0, 2.0, 4.0, 0.0]

const DEFS := {
	# ── video ────────────────────────────────────────────────────────────
	# One of WINDOW_MODES. Replaces the old `fullscreen` bool, which could not
	# express borderless — see _migrate_legacy() for what happens to a
	# settings.cfg written before this existed.
	"window_mode": ["windowed"],
	# "WxH", one of RESOLUTIONS. Windowed only: in either fullscreen mode the
	# window is the screen and setting a size does nothing, so the row is
	# disabled there rather than lying.
	"resolution": ["1280x720"],
	# One of VSYNC_MODES.
	"vsync": ["on"],
	# 0 = unlimited. Engine.max_fps, so it caps the whole main loop.
	"max_fps": [0, 0, 240],
	"ui_scale": [1.0, 0.75, 1.5],
	# ── audio ────────────────────────────────────────────────────────────
	# Three real AudioServer buses: SFX and UI feed Master. The split is what
	# lets someone keep the game's sounds and silence the click-on-every-focus,
	# which is the one sound a keyboard player hears constantly.
	#
	# There is NO music slider, deliberately. The game has no music, and a
	# slider that moves a bus nothing plays through is exactly the dead control
	# this file's header refuses. It gets one the day there is music.
	"master_volume": [0.8, 0.0, 1.0],
	"sfx_volume": [0.9, 0.0, 1.0],
	"ui_volume": [0.7, 0.0, 1.0],
	"muted": [false],
	# ── interface / accessibility ────────────────────────────────────────
	# FOUR SPEEDS, not a slider — the shape Balatro uses, and the one that
	# actually gets used: nobody drags a continuous control to 1.37x. See
	# ANIMATION_SPEEDS for why the fourth is "instant" rather than 0.5x.
	"animation_scale": [1.0],
	# Multiplies every font size UIKit hands out, and the card face with them
	# so the text still fits. Separate from ui_scale, which magnifies the whole
	# interface including the gaps: this makes the WORDS bigger at the same
	# layout, which is what someone who can read the game fine but not its
	# 11px captions actually wants.
	"text_scale": [1.0, 0.85, 1.3],
	# Raises the contrast of the whole palette — see UIKit.apply_palette().
	# The dim greys this game is written in are a deliberate look and a real
	# problem for anyone who cannot pick them off the background.
	"high_contrast": [false],
	# gameplay — the two knobs the prototype exposed as props (its cfg())
	"start_energy": [3, 1, 8],
	"hand_size": [5, 3, 10],
	# language
	"locale": ["en"],
	# content
	"load_example_mods": [true],
	# controls: {action_name: keycode}. Only the KEYBOARD binding of an action
	# is overridable here; an action's gamepad events are left alone, so a
	# rebind never silently costs a controller player their button.
	"keybinds": [{}],
	# ids of mod packs the player switched off in the Mods screen. The base
	# pack is not listed here and cannot be disabled — without it there is no
	# game to mod. Stored as ids rather than paths so a pack keeps its setting
	# when it moves (a manual install later subscribed to on the Workshop, say).
	"disabled_mods": [[]],
}

## How the settings screen groups these, and — as far as
## tests/test_settings.gd is concerned — the CONTRACT between the two. `keys`
## is not documentation: the test asserts that every key in DEFS appears in
## exactly one section here, and that no section names a key DEFS does not
## have. A setting nobody can reach is as dead as a setting that does nothing,
## and it fails silently in exactly the same way.
##
## It lives here rather than in scenes/SettingsMenu.gd because that file
## preloads UIKit, which refers to four autoloads and so cannot be compiled by
## a `godot -s` tool — the test could not have read it there.
const SECTIONS := [
	{"id": "gameplay", "title": "GAMEPLAY", "keys": ["start_energy", "hand_size"]},
	{"id": "video", "title": "VIDEO", "keys": ["window_mode", "resolution", "vsync", "max_fps", "ui_scale"]},
	{"id": "audio", "title": "AUDIO", "keys": ["master_volume", "sfx_volume", "ui_volume", "muted"]},
	{"id": "interface", "title": "INTERFACE", "keys": ["animation_scale", "text_scale", "high_contrast"]},
	{"id": "controls", "title": "CONTROLS", "keys": ["keybinds"]},
	{"id": "language", "title": "LANGUAGE", "keys": ["locale"]},
	{"id": "content", "title": "CONTENT", "keys": ["load_example_mods", "disabled_mods"]},
]

## Window modes, in the order the settings screen offers them. `borderless` is
## a windowed window at screen size with no chrome — the "fullscreen windowed"
## most games list, and the one that alt-tabs cleanly.
const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]

## Vsync modes. `adaptive` tears rather than dropping to half rate when a frame
## is missed; it is offered because on some drivers it is the only one that
## feels right, not because most people should pick it.
const VSYNC_MODES := ["off", "on", "adaptive"]

## Offered window sizes, widest aspect last within each group. Anything larger
## than the player's screen is filtered out at display time rather than removed
## here, so the list does not depend on the machine that happens to be running
## the tests.
##
## NOT ONLY 16:9. This was five 16:9 sizes, which is the shape the game was
## designed at and quietly the only shape anyone had ever seen it in — a laptop
## at 1920x1200 and an ultrawide are ordinary hardware, and neither was on the
## list. With `canvas_items`/`expand` stretch the canvas is never SMALLER than
## the 1280x720 it is drawn for; a taller screen buys canvas height and a wider
## one buys canvas width, which gives four distinct shapes for the whole list:
## 1280x720 (16:9), 1280x800 (16:10), 1280x960 (4:3) and 1706x720 (21:9).
## tests/test_resolutions.gd builds every screen in every one of them.
const RESOLUTIONS := [
	"1024x768",
	"1280x720", "1280x800",
	"1366x768", "1440x900",
	"1600x900", "1680x1050",
	"1920x1080", "1920x1200",
	"2560x1080", "2560x1440",
	"3440x1440", "3840x2160",
]

## Audio buses this game creates at startup, each feeding Master. There is no
## default_bus_layout.tres in the project: building them here keeps the
## routing next to the volumes that drive it, and means a fresh clone has no
## binary resource to be out of step with this file.
const BUSES := ["SFX", "UI"]

## The actions offered for rebinding, in the order the settings screen lists
## them. ui_accept and ui_cancel are Godot built-ins rather than actions this
## project declares (see the [input] section of project.godot for why), but they
## are the two a player is most likely to want moved, so they belong on the list
## — InputMap treats a built-in action like any other.
const ACTIONS := [
	["ui_accept", "Confirm / play a card"],
	["ui_cancel", "Back / close"],
	["parlour_read", "Read it"],
	["parlour_deck", "Show your deck"],
	["parlour_marks", "Show your marks"],
]

## Each action's shipped keyboard events, captured before any override is
## applied. Without this a rebind would be irreversible: overriding replaces the
## keyboard events, so "reset" would have nothing to put back.
var _default_keys: Dictionary = {}

## Why the last write to disk failed, or "" if it did not. Read by the main
## menu — see save_to_disk().
var last_error: String = ""

var _values: Dictionary = {}


func _ready() -> void:
	_remember_default_keys()
	_make_buses()
	load_from_disk()
	_apply_all()


func _apply_all() -> void:
	_apply_display()
	_apply_audio()
	_apply_input()


func get_value(key: String):
	if not DEFS.has(key):
		push_error("[Settings] unknown setting '%s'" % key)
		return null
	var value = _values.get(key, DEFS[key][0])
	# Arrays are handed out by reference, and one of these defaults lives inside
	# a `const` — so a caller that appended to what it got back would corrupt the
	# default for every later reader, in a way no test would obviously catch.
	# Copy on the way out; callers are then free to mutate what they hold and
	# pass it to set_value().
	return value.duplicate() if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value


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
	if key in ["window_mode", "resolution", "vsync", "max_fps", "ui_scale"]:
		_apply_display()
	elif key in ["master_volume", "sfx_volume", "ui_volume", "muted"]:
		_apply_audio()
	elif key == "keybinds":
		_apply_input()
	# text_scale and high_contrast need no apply call — UIKit reads them on the
	# next screen build. See _apply_look()'s comment.
	changed.emit(key)


func reset_to_defaults() -> void:
	_values.clear()
	save_to_disk()
	_apply_all()
	changed.emit("")


# ── controls ────────────────────────────────────────────────────────────

func _remember_default_keys() -> void:
	for entry in ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			push_warning("[Settings] no such input action '%s'" % action)
			continue
		var keys: Array = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keys.append(e)
		_default_keys[action] = keys


## Rewrites the InputMap from the stored overrides. Only keyboard events are
## touched: an action's joypad events are left in place, so rebinding a key
## never costs a controller player their button.
func _apply_input() -> void:
	var binds: Dictionary = get_value("keybinds")
	for entry in ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		if binds.has(action):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(binds[action])
			InputMap.action_add_event(action, ev)
		else:
			for e in _default_keys.get(action, []):
				InputMap.action_add_event(action, e)


## The key currently bound to `action`, as something to show a player. Falls
## back to the action name if it somehow has no keyboard event at all, rather
## than rendering an empty cell that looks like a bug.
func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.as_text_physical_keycode() if e.physical_keycode != 0 else e.as_text_keycode()
	return "—"


## The gamepad button bound to `action`, as something to show a player, or ""
## if it has none. Shown beside the key in the controls pane: the screen
## already promised that rebinding a key leaves the pad button alone, and a
## promise about a button nobody can see is not much of one.
##
## The name comes from Godot's own as_text(), trimmed to the part that is
## useful — it renders "Joypad Button 0 (Bottom Action, Sony Cross, Xbox A,
## Nintendo B)", and the parenthesised list is the half that tells a player
## anything.
func pad_label(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			var text := e.as_text()
			var open := text.find("(")
			return text.substr(open + 1, text.rfind(")") - open - 1) if open >= 0 else text
	return ""


func set_keybind(action: String, keycode: int) -> void:
	var binds: Dictionary = get_value("keybinds")
	binds[action] = keycode
	set_value("keybinds", binds)


func clear_keybind(action: String) -> void:
	var binds: Dictionary = get_value("keybinds")
	if binds.erase(action):
		set_value("keybinds", binds)


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
	_migrate_legacy(cfg)
	_validate_choices()


## Settings files outlive the code that wrote them. `fullscreen` was a bool
## until window_mode replaced it; without this, anyone who had turned
## fullscreen on would silently be put back in a window on next launch and
## have to find the setting again. Dropped keys are left in the file rather
## than rewritten out — harmless, and it means downgrading still works.
func _migrate_legacy(cfg: ConfigFile) -> void:
	if not _values.has("window_mode") and cfg.has_section_key(SECTION, "fullscreen"):
		if bool(cfg.get_value(SECTION, "fullscreen")):
			_values["window_mode"] = "fullscreen"


## A choice-valued setting whose stored value is not one of the choices would
## fall through every match and land on an arbitrary branch. Cheaper to refuse
## it on load than to make each apply function defensive.
func _validate_choices() -> void:
	for pair in [["window_mode", WINDOW_MODES], ["vsync", VSYNC_MODES], ["resolution", RESOLUTIONS],
			["animation_scale", ANIMATION_SPEEDS]]:
		var key: String = pair[0]
		if _values.has(key) and not pair[1].has(_values[key]):
			push_warning("[Settings] '%s' had an unknown value %s; using the default." % [key, _values[key]])
			_values.erase(key)
	# locale is deliberately not checked here: Settings is the FIRST autoload
	# (see this file's header), so the I18n node does not exist yet at load
	# time. I18n.current() already falls back to English for a code it does not
	# know, which is the same outcome one step later.


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, key, _values[key])
	# The return value is not decoration: a read-only user:// or a full disk
	# fails here, and the main menu shows it once for whichever of the three
	# config writes failed. Silent, it costs a setting or an unlock.
	# Written to a temporary file and renamed into place, for the same reason
	# Save.gd does it: a crash partway through a write would otherwise leave a
	# truncated config, and a truncated config is one ConfigFile.load() refuses
	# — losing every setting rather than the one being written.
	var tmp := PATH + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		var dir := DirAccess.open("user://")
		err = dir.rename(tmp.get_file(), PATH.get_file()) if dir != null else FAILED
	if err != OK:
		last_error = "could not write %s (%s)" % [PATH, error_string(err)]
		push_warning("[Settings] " + last_error)
	else:
		last_error = ""


## The one setting group that can fail on the machine rather than in the code:
## a display server may refuse a mode, and headless has none at all. Every call
## here is guarded and none of them is load-bearing for the game running.
func _apply_display() -> void:
	# ui_scale is a Viewport property, not a DisplayServer one, so it applies
	# under headless too — and test_scenes builds real screens headless, so it
	# has to be set before the early return, not after it.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.content_scale_factor = float(get_value("ui_scale"))
	if DisplayServer.get_name() == "headless":
		return

	var mode := str(get_value("window_mode"))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if mode == "fullscreen" else DisplayServer.WINDOW_MODE_WINDOWED
	)
	# Borderless is a windowed window with its chrome off, so the flag has to be
	# set for "borderless" and CLEARED for the other two — otherwise switching
	# back to windowed leaves a title bar missing with no way to get it back.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
	if mode == "borderless":
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
		DisplayServer.window_set_position(Vector2i.ZERO)
	elif mode == "windowed":
		var size := _resolution_size()
		# Only when it is actually a different size. This runs on boot and on
		# every apply, and a resize to the size you already are still moves the
		# window and costs a frame — and asking for one is what left the game
		# drawn in the corner on a display server that does not hand it back.
		if DisplayServer.window_get_size() != size:
			DisplayServer.window_set_size(size)
			# Re-centre, or a window that just grew can end up mostly off-screen
			# with its close button somewhere the mouse cannot reach.
			var screen := DisplayServer.screen_get_size()
			if screen.x > 0 and screen.y > 0:
				DisplayServer.window_set_position((screen - size) / 2 + DisplayServer.screen_get_position())

	match str(get_value("vsync")):
		"off": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"adaptive": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	Engine.max_fps = int(get_value("max_fps"))


## WHAT THE DRIVER ACTUALLY DID with the vsync request, as one of VSYNC_MODES,
## or "" when there is no display to ask.
##
## Asked for rather than assumed, because this is the one video setting that can
## be refused: a driver may simply not support changing it, and Godot then warns
## on the console — which no player reads. Under this project's own test
## environment (Xvfb software GL) every mode is refused, so the setting cannot
## be verified here at all; on real hardware it is honoured. The settings screen
## prints the disagreement so whoever is running the build can see the truth on
## their own machine instead of taking a porter's word for it.
func vsync_actual() -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_DISABLED: return "off"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptive"
		DisplayServer.VSYNC_MAILBOX: return "on"
		_: return "on"


## The stored "WxH" as a size, clamped to the screen so a resolution carried
## over from a bigger monitor cannot open a window nobody can reach.
func _resolution_size() -> Vector2i:
	var parts := str(get_value("resolution")).split("x")
	var size := Vector2i(1280, 720)
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		size = Vector2i(int(parts[0]), int(parts[1]))
	var screen := DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		size = size.min(screen)
	return size


## Resolutions that fit on this machine's screen. The settings screen offers
## these rather than the full list, so nobody can pick a window larger than
## their monitor and lose the one that was working.
func available_resolutions() -> Array:
	var screen := DisplayServer.screen_get_size()
	var out: Array = []
	for r in RESOLUTIONS:
		var parts := str(r).split("x")
		if screen.x <= 0 or (int(parts[0]) <= screen.x and int(parts[1]) <= screen.y):
			out.append(r)
	# Never hand back nothing: on a very small screen the smallest entry is
	# still a better answer than an empty dropdown.
	return out if not out.is_empty() else [RESOLUTIONS[0]]


## Creates the SFX and UI buses if they are not already there. Idempotent, so
## reset_to_defaults() and a reload cannot end up with two of each.
func _make_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")


func _apply_audio() -> void:
	_set_bus("Master", float(get_value("master_volume")), bool(get_value("muted")))
	_set_bus("SFX", float(get_value("sfx_volume")), false)
	_set_bus("UI", float(get_value("ui_volume")), false)


func _set_bus(name: String, linear: float, mute: bool) -> void:
	var bus := AudioServer.get_bus_index(name)
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, mute)
	# linear_to_db(0) is -inf, which AudioServer takes but which reads badly
	# in logs; clamp the floor to a silent-but-finite -60dB instead.
	AudioServer.set_bus_volume_db(bus, -60.0 if linear <= 0.001 else linear_to_db(linear))


## The look settings (`text_scale`, `high_contrast`) have NO apply function
## here, and that is deliberate — UIKit pulls them instead, in root_control(),
## at the top of every screen build.
##
## PUSHING THEM CANNOT WORK. Settings is the first autoload, so when its
## _ready() runs the I18n, Content, Rules and Art autoloads do not exist — and
## UIKit refers to all four, so preloading it from here compiles to nothing and
## every call on it fails silently at runtime.
##
## Deferring the push would compile but leaves an ordering hazard: the main
## scene is built before the first deferred call flushes, so the opening screen
## would use an unscaled palette. A pull needs no ordering guarantee at all.
## tests/test_scenes.gd asserts a built screen reflects the setting, which is
## the half a headless Settings test cannot see.
