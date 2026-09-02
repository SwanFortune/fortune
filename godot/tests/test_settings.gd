## Headless test for Settings — the parts with real consequences beyond
## storing a number.
##   godot --headless --path godot -s tests/test_settings.gd
##
## The guarantees under test:
##   - rebinding an action actually rewrites the InputMap, and resetting it
##     puts the shipped key back (which is only possible because the defaults
##     are captured before any override is applied);
##   - rebinding the keyboard leaves an action's gamepad button alone;
##   - a container-valued setting is handed out as a copy, so a caller that
##     mutates what it got cannot corrupt the stored value — or, worse, the
##     `const` default shared by every later reader;
##   - an unknown key is refused rather than silently persisted;
##   - EVERY setting is reachable from the settings screen, and the screen
##     names no setting that does not exist. A knob nobody can turn is as dead
##     as a knob wired to nothing, and it fails just as quietly;
##   - a choice-valued setting cannot be left holding a value that is not one
##     of its choices — including one carried over from an older build, which
##     is what the fullscreen -> window_mode migration is about;
##   - the SFX and UI buses are real, and the sliders move them.
extends SceneTree

const TESTS := [
	"_test_rebind_and_reset",
	"_test_rebind_leaves_the_gamepad_alone",
	"_test_containers_are_copied_out",
	"_test_unknown_key_is_refused",
	"_test_every_setting_is_reachable",
	"_test_choice_defaults_are_valid_choices",
	"_test_a_bad_stored_choice_falls_back",
	"_test_legacy_fullscreen_migrates",
	"_test_the_buses_exist_and_the_volumes_reach_them",
	"_test_reset_puts_everything_back",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var settings: Node


func _initialize() -> void:
	settings = root.get_node("Settings")
	await process_frame

	# These tests write deliberately broken settings files and call
	# reset_to_defaults(), so the whole file is put back afterwards rather than
	# a key at a time — a test suite that silently wipes the player's settings
	# is a bad neighbour on a development machine.
	var saved := ""
	if FileAccess.file_exists(settings.PATH):
		saved = FileAccess.get_file_as_string(settings.PATH)

	for t in TESTS:
		call(t)
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)

	if saved != "":
		var f := FileAccess.open(settings.PATH, FileAccess.WRITE)
		f.store_string(saved)
		f.close()
	else:
		DirAccess.remove_absolute(settings.PATH)
	settings.load_from_disk()
	settings._apply_all()

	if failures.is_empty():
		print("ALL PASS — %d test methods" % TESTS.size())
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func done(name: String) -> void:
	finished[name] = true


func _keys_of(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	return out


func _test_rebind_and_reset() -> void:
	settings.clear_keybind("parlour_read")
	var shipped: Array = _keys_of("parlour_read")
	check(shipped.has(KEY_R), "parlour_read should ship on R, got %s" % str(shipped))

	settings.set_keybind("parlour_read", KEY_F)
	check(_keys_of("parlour_read") == [KEY_F], "rebinding should replace the key, got %s" % str(_keys_of("parlour_read")))
	check(InputMap.has_action("parlour_read"), "the action itself must survive a rebind")

	# Resetting is only possible because the shipped events were captured at
	# startup — applying an override erases them from the InputMap.
	settings.clear_keybind("parlour_read")
	check(_keys_of("parlour_read").has(KEY_R), "clearing should restore R, got %s" % str(_keys_of("parlour_read")))
	done("_test_rebind_and_reset")


## A player rebinding a key must not lose their controller button for it.
func _test_rebind_leaves_the_gamepad_alone() -> void:
	var pads_before := 0
	for e in InputMap.action_get_events("parlour_read"):
		if e is InputEventJoypadButton:
			pads_before += 1
	check(pads_before > 0, "precondition: parlour_read should ship with a gamepad button")

	settings.set_keybind("parlour_read", KEY_G)
	var pads_after := 0
	for e in InputMap.action_get_events("parlour_read"):
		if e is InputEventJoypadButton:
			pads_after += 1
	check(pads_after == pads_before,
		"rebinding the key should leave %d gamepad event(s) alone, got %d" % [pads_before, pads_after])
	settings.clear_keybind("parlour_read")
	done("_test_rebind_leaves_the_gamepad_alone")


## get_value() hands out Arrays and Dictionaries by value. One of those
## defaults lives inside a `const`, so a caller appending to what it received
## would corrupt the default for every later reader — invisibly, and for the
## rest of the session.
func _test_containers_are_copied_out() -> void:
	var a: Array = settings.get_value("disabled_mods")
	a.append("mutating.what.i.was.handed")
	check(not settings.get_value("disabled_mods").has("mutating.what.i.was.handed"),
		"mutating a returned Array must not reach the stored value")

	var d: Dictionary = settings.get_value("keybinds")
	d["not_an_action"] = 1
	check(not settings.get_value("keybinds").has("not_an_action"),
		"mutating a returned Dictionary must not reach the stored value")
	done("_test_containers_are_copied_out")


func _test_unknown_key_is_refused() -> void:
	# DEFS is the single source of truth for what a valid setting is; a typo
	# should fail at the call site rather than persist a value nothing reads.
	print("--- the next two errors are expected: setting and reading a key that does not exist ---")
	settings.set_value("no_such_setting", 3)
	check(settings.get_value("no_such_setting") == null, "an unknown key should read back null")
	done("_test_unknown_key_is_refused")


## The screen and the registry have to agree in both directions. This is the
## guard that would have caught a setting added to DEFS and then never given a
## row — which is how the `unlock` field spent the whole port doing nothing.
func _test_every_setting_is_reachable() -> void:
	var seen := {}
	for section in settings.SECTIONS:
		for key in section["keys"]:
			check(settings.DEFS.has(key),
				"section '%s' offers '%s', which is not a setting" % [section["id"], key])
			check(not seen.has(key),
				"'%s' appears in two sections (%s and %s)" % [key, seen.get(key, ""), section["id"]])
			seen[key] = section["id"]
	for key in settings.DEFS:
		check(seen.has(key), "setting '%s' is in no section — nothing can reach it" % key)
	done("_test_every_setting_is_reachable")


## Each choice setting's DEFAULT has to be one of its choices, or a fresh
## profile starts out in a state the screen cannot display and every apply
## falls through to whatever the last match arm happens to be.
func _test_choice_defaults_are_valid_choices() -> void:
	for pair in [["window_mode", settings.WINDOW_MODES], ["vsync", settings.VSYNC_MODES],
			["resolution", settings.RESOLUTIONS]]:
		check(pair[1].has(settings.default_for(pair[0])),
			"'%s' defaults to %s, which is not one of its choices" % [pair[0], settings.default_for(pair[0])])
	# available_resolutions() must never hand the screen an empty dropdown.
	check(not settings.available_resolutions().is_empty(), "there is always at least one offered resolution")
	done("_test_choice_defaults_are_valid_choices")


## A hand-edited or version-skewed settings.cfg holding a value that is not a
## choice is refused on load rather than carried into the apply functions.
func _test_a_bad_stored_choice_falls_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(settings.SECTION, "window_mode", "cinema")
	cfg.set_value(settings.SECTION, "vsync", "sometimes")
	cfg.save(settings.PATH)
	print("--- the next two WARNINGs are expected: deliberately bad stored choices ---")
	settings.load_from_disk()
	check(settings.get_value("window_mode") == "windowed",
		"an unknown window mode falls back to the default, got '%s'" % settings.get_value("window_mode"))
	check(settings.get_value("vsync") == "on",
		"an unknown vsync mode falls back to the default, got '%s'" % settings.get_value("vsync"))
	done("_test_a_bad_stored_choice_falls_back")


## Settings files outlive the code that wrote them. Someone who had turned
## fullscreen on before window_mode existed must not silently be put back in a
## window and have to find the setting again.
func _test_legacy_fullscreen_migrates() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(settings.SECTION, "fullscreen", true)
	cfg.save(settings.PATH)
	settings.load_from_disk()
	check(settings.get_value("window_mode") == "fullscreen",
		"a legacy fullscreen=true should become window_mode=fullscreen, got '%s'" % settings.get_value("window_mode"))

	# ...and an explicit window_mode wins over the legacy key, so migrating
	# cannot undo a choice made since.
	cfg.set_value(settings.SECTION, "window_mode", "borderless")
	cfg.save(settings.PATH)
	settings.load_from_disk()
	check(settings.get_value("window_mode") == "borderless",
		"an explicit window_mode wins over the legacy key, got '%s'" % settings.get_value("window_mode"))
	done("_test_legacy_fullscreen_migrates")


## The three volume sliders are only worth having if they drive three separate
## buses. Checks the routing as well as the levels: SFX and UI both have to
## feed Master, or the master slider would stop working.
func _test_the_buses_exist_and_the_volumes_reach_them() -> void:
	for name in settings.BUSES:
		var i := AudioServer.get_bus_index(name)
		check(i >= 0, "bus '%s' should exist" % name)
		if i >= 0:
			check(AudioServer.get_bus_send(i) == "Master",
				"bus '%s' should feed Master, sends to '%s'" % [name, AudioServer.get_bus_send(i)])

	for pair in [["master_volume", "Master"], ["sfx_volume", "SFX"], ["ui_volume", "UI"]]:
		settings.set_value(pair[0], 0.5)
		var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(pair[1]))
		check(is_equal_approx(db, linear_to_db(0.5)),
			"%s should set bus %s to %.2f dB, got %.2f" % [pair[0], pair[1], linear_to_db(0.5), db])
		# 0 is the interesting one: linear_to_db(0) is -inf, which is legal but
		# unreadable, so it is clamped to a silent-but-finite floor.
		settings.set_value(pair[0], 0.0)
		db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(pair[1]))
		check(db > -1000.0 and db <= -60.0, "silence should be finite, got %.2f dB" % db)

	# Mute is Master only: muting must silence everything, not just one bus.
	settings.set_value("muted", true)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute should mute Master")
	settings.set_value("muted", false)
	done("_test_the_buses_exist_and_the_volumes_reach_them")


## reset_to_defaults() has to put back EVERY key, not the handful whose apply
## functions it happens to call.
func _test_reset_puts_everything_back() -> void:
	settings.set_value("window_mode", "borderless")
	settings.set_value("max_fps", 60)
	settings.set_value("text_scale", 1.3)
	settings.set_value("sfx_volume", 0.1)
	settings.reset_to_defaults()
	for key in settings.DEFS:
		check(settings.get_value(key) == settings.default_for(key),
			"'%s' should be back to its default, got %s" % [key, settings.get_value(key)])
	done("_test_reset_puts_everything_back")
