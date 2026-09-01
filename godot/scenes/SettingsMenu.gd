## Settings screen. Every control here is bound directly to a Settings key
## and takes effect immediately — there's no Apply button and no staged copy
## of the values, because Settings already persists on every change.
##
## Reachable from the main menu, and from anywhere via Esc (see Nav).
extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")

var _return_scene: String = "res://scenes/MainMenu.tscn"


func _ready() -> void:
	if Nav.settings_return_scene != "":
		_return_scene = Nav.settings_return_scene

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(10)
	m.add_child(v)

	v.add_child(UIKit.block(I18n.t("SETTINGS"), 26, UIKit.GOLD))

	_section(v, I18n.t("DISPLAY"))
	v.add_child(UIKit.setting_toggle("fullscreen", I18n.t("Fullscreen"), I18n.t("Toggle between windowed and fullscreen.")))
	v.add_child(UIKit.setting_slider(
		"ui_scale", I18n.t("Interface scale"),
		I18n.t("Scales the whole interface. Useful on very large or very small displays."),
		func(x): return "%d%%" % round(float(x) * 100.0)
	))

	_section(v, I18n.t("SOUND"))
	v.add_child(UIKit.setting_slider(
		"master_volume", I18n.t("Master volume"),
		"Drives the real audio bus. The game ships no sound yet, so this is silent either way — the wiring is here so it works the moment audio lands.",
		func(x): return "%d%%" % round(float(x) * 100.0)
	))
	v.add_child(UIKit.setting_toggle("muted", I18n.t("Mute"), I18n.t("Silence everything.")))

	_section(v, I18n.t("MOTION"))
	v.add_child(UIKit.setting_slider(
		"animation_scale", I18n.t("Animation speed"),
		"How fast cards deal, bars fill and values pulse. Set to 0 for no motion at all — the game jumps straight to each end state.",
		func(x): return "off" if float(x) <= 0.01 else "%.2fx" % float(x)
	))

	_section(v, I18n.t("GAMEPLAY"))
	v.add_child(UIKit.block(
		"These two are the knobs the original prototype exposed. Changing them rebalances the whole game — the defaults (3 and 5) are what everything else is tuned against.",
		11, UIKit.DIM
	))
	v.add_child(UIKit.setting_slider(
		"start_energy", I18n.t("Energy per reading"),
		"Base energy each reading, before any reader, relic, job or sign modifier. Default 3.",
		func(x): return str(x), true
	))
	v.add_child(UIKit.setting_slider(
		"hand_size", I18n.t("Hand size"),
		"Base cards dealt each reading, before modifiers. Default 5.",
		func(x): return str(x), true
	))

	_section(v, I18n.t("CONTROLS"))
	v.add_child(UIKit.block(
		I18n.t("The whole game is playable from the keyboard or a gamepad: Tab and the arrow keys move between things, and Confirm activates whatever is highlighted."),
		11, UIKit.DIM))
	for entry in Settings.ACTIONS:
		v.add_child(_keybind_row(entry[0], entry[1]))
	v.add_child(UIKit.block(
		I18n.t("Only the keyboard key is changed — an action keeps its gamepad button either way."),
		11, UIKit.DIM))

	_section(v, I18n.t("LANGUAGE"))
	v.add_child(_language_row())
	var cov := I18n.coverage(I18n.current())
	if int(cov["total"]) > 0:
		var pct := int(round(100.0 * float(cov["translated"]) / float(cov["total"])))
		v.add_child(UIKit.block(
			"%d%% translated (%d of %d strings). Anything untranslated falls back to English." % [pct, cov["translated"], cov["total"]],
			11, UIKit.DIM))

	_section(v, I18n.t("CONTENT"))
	v.add_child(UIKit.setting_toggle(
		"load_example_mods", I18n.t("Load example mods"),
		"Loads the bundled demo mod in mods_example/. Your own mods in the user mods folder always load.",
		func(_p): Content.reload(); Art.reload()
	))
	v.add_child(UIKit.block(
		I18n.t("Mods loaded: %s pack(s). %s") % [_pack_count(), _errors_line()],
		11, UIKit.RED if not Content.load_errors.is_empty() else UIKit.DIM
	))

	v.add_child(Control.new())
	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	actions.add_child(UIKit.button(I18n.t("RESET TO DEFAULTS"), _reset))
	v.add_child(actions)
	UIKit.focus_first(self)


## Switching locale rebuilds this screen so its own labels change with it —
## immediate feedback that the setting took, and the same rebuild every other
## screen gets when it is next constructed.
func _language_row() -> Control:
	var row := UIKit.hbox(12)
	var cap := UIKit.label(I18n.t("Language"), 13, UIKit.INK)
	cap.custom_minimum_size.x = 190
	row.add_child(cap)
	var opt := OptionButton.new()
	var i := 0
	var selected := 0
	for code in I18n.LOCALES:
		opt.add_item(I18n.LOCALES[code])
		opt.set_item_metadata(i, code)
		if code == I18n.current():
			selected = i
		i += 1
	opt.select(selected)
	opt.item_selected.connect(func(idx: int):
		Settings.set_value("locale", opt.get_item_metadata(idx))
		get_tree().reload_current_scene()
	)
	row.add_child(opt)
	return row


## One rebindable action. Pressing the button arms a capture: the next key
## goes to that action. Escape cancels rather than binding itself, since a
## player who has just bound Confirm to something unreachable needs one key
## that always means "get me out of this".
func _keybind_row(action: String, caption: String) -> Control:
	var row := UIKit.hbox(12)
	var cap := UIKit.label(I18n.t(caption), 13, UIKit.INK)
	cap.custom_minimum_size.x = 190
	row.add_child(cap)

	var armed := false
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 32)
	b.text = Settings.key_label(action)
	b.pressed.connect(func():
		armed = true
		b.text = I18n.t("press a key…")
	)
	# A key press is only a rebind while this row is armed; the rest of the time
	# it must fall through, or arming one row would swallow the whole screen's
	# keyboard navigation.
	b.gui_input.connect(func(event: InputEvent):
		if not armed or not (event is InputEventKey) or not event.pressed or event.echo:
			return
		armed = false
		if event.keycode != KEY_ESCAPE:
			Settings.set_keybind(action, event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		b.text = Settings.key_label(action)
		b.accept_event()
	)
	row.add_child(b)

	var reset := UIKit.button(I18n.t("DEFAULT"), func():
		Settings.clear_keybind(action)
		b.text = Settings.key_label(action)
	)
	reset.custom_minimum_size = Vector2(100, 32)
	row.add_child(reset)
	return row


func _section(v: VBoxContainer, title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	v.add_child(sp)
	v.add_child(UIKit.block(title, 12, UIKit.GOLD))


## Content already records what discovery found; re-running it here meant a
## second, subtly different answer (it counted discovered dirs, not loaded
## packs, so a pack switched off in the Mods screen still counted).
func _pack_count() -> int:
	var live := 0
	for p in Content.packs:
		if bool(p.get("enabled", true)):
			live += 1
	return live


func _errors_line() -> String:
	if Content.load_errors.is_empty():
		return I18n.t("No content errors.")
	return I18n.t("%s content warning(s) — see MODS.") % Content.load_errors.size()


func _reset() -> void:
	Settings.reset_to_defaults()
	Content.reload()
	Art.reload()
	get_tree().reload_current_scene()


func _back() -> void:
	Nav.settings_return_scene = ""
	get_tree().change_scene_to_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
