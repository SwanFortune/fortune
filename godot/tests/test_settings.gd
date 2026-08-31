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
##   - an unknown key is refused rather than silently persisted.
extends SceneTree

const TESTS := [
	"_test_rebind_and_reset",
	"_test_rebind_leaves_the_gamepad_alone",
	"_test_containers_are_copied_out",
	"_test_unknown_key_is_refused",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var settings: Node


func _initialize() -> void:
	settings = root.get_node("Settings")
	await process_frame

	var restore_binds: Dictionary = settings.get_value("keybinds")
	for t in TESTS:
		call(t)
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)
	settings.set_value("keybinds", restore_binds)

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
