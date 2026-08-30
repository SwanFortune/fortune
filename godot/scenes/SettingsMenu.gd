## Settings screen. Every control here is bound directly to a Settings key
## and takes effect immediately — there's no Apply button and no staged copy
## of the values, because Settings already persists on every change.
##
## Reachable from the main menu, and from anywhere via Esc (see Nav).
extends Control

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
		"Mods loaded: %d pack(s). %s" % [_pack_count(), _errors_line()],
		11, UIKit.RED if not Content.load_errors.is_empty() else UIKit.DIM
	))

	v.add_child(Control.new())
	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	actions.add_child(UIKit.button(I18n.t("RESET TO DEFAULTS"), _reset))
	v.add_child(actions)


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


func _section(v: VBoxContainer, title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	v.add_child(sp)
	v.add_child(UIKit.block(title, 12, UIKit.GOLD))


func _pack_count() -> int:
	var loader := ModLoader.new()
	loader.load_example_mods = bool(Settings.get_value("load_example_mods"))
	return loader.discover_pack_dirs().size()


func _errors_line() -> String:
	if Content.load_errors.is_empty():
		return "No content errors."
	return "%d content warning(s) — see console." % Content.load_errors.size()


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
