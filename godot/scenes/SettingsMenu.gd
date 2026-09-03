## Settings screen. A category rail down the left, the chosen category's rows
## on the right, actions along the bottom.
##
## It was one long scroll until it had twenty rows in it, at which point the
## thing a player actually does here — "find the volume" — meant reading past
## everything else. The rail is not decoration: it is the only way a settings
## screen stays findable as it grows, which is why every game with more than a
## dozen options has one.
##
## Every control is bound directly to a Settings key and takes effect
## immediately. There is no Apply button and no staged copy of the values,
## because Settings already persists on every change — and because a video
## setting you cannot see the result of until you press Apply is a video
## setting you cannot judge.
extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")


var _return_scene: String = "res://scenes/MainMenu.tscn"
var _section := 0
## Set once the rail has been used, so the initial build focuses the rail and
## every later one focuses the pane the player just opened.
var _focus_pane := false


func _ready() -> void:
	if Nav.settings_return_scene != "":
		_return_scene = Nav.settings_return_scene
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var outer := UIKit.vbox(12)
	m.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("SETTINGS"), 26, UIKit.GOLD))

	var body := UIKit.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	body.add_child(_rail())

	var scroll := UIKit.scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var pane := UIKit.vbox(8)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pane)
	_build_pane(pane)

	outer.add_child(_actions())
	if _focus_pane:
		UIKit.focus_first(scroll)
	else:
		UIKit.focus_first(self)


# ── the rail ────────────────────────────────────────────────────────────

func _rail() -> Control:
	var v := UIKit.vbox(4)
	v.custom_minimum_size.x = 170 * UIKit.text_scale
	for i in Settings.SECTIONS.size():
		var idx := i
		var b := UIKit.button(I18n.t(str(Settings.SECTIONS[i]["title"])), func(): _select(idx))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# The selected entry is gold and cannot be re-pressed. Disabling it is
		# what keeps keyboard focus from parking on the row that does nothing,
		# and it reads as "you are here" without needing a separate marker.
		if i == _section:
			# `font_disabled_color` is the theme item Button actually reads when
			# disabled — `font_color` alone leaves the selected entry rendered
			# DIMMER than its neighbours, which is the exact opposite of what
			# "you are here" should look like.
			b.add_theme_color_override("font_color", UIKit.GOLD)
			b.add_theme_color_override("font_disabled_color", UIKit.GOLD)
			b.disabled = true
		v.add_child(b)
	return v


func _select(index: int) -> void:
	_section = index
	_focus_pane = true
	_build()


# ── the panes ───────────────────────────────────────────────────────────

func _build_pane(v: VBoxContainer) -> void:
	match str(Settings.SECTIONS[_section]["id"]):
		"gameplay": _pane_gameplay(v)
		"video": _pane_video(v)
		"audio": _pane_audio(v)
		"interface": _pane_interface(v)
		"controls": _pane_controls(v)
		"language": _pane_language(v)
		"content": _pane_content(v)


func _pane_gameplay(v: VBoxContainer) -> void:
	v.add_child(UIKit.block(I18n.t(
		"These two are the knobs the original prototype exposed. Changing them rebalances the whole game — the defaults (3 and 5) are what everything else is tuned against."
	), 11, UIKit.DIM))
	v.add_child(UIKit.setting_slider(
		"start_energy", I18n.t("Energy per reading"),
		I18n.t("Base energy each reading, before any reader, relic, job or sign modifier. Default 3."),
		func(x): return str(x), true))
	v.add_child(UIKit.setting_slider(
		"hand_size", I18n.t("Hand size"),
		I18n.t("Base cards dealt each reading, before modifiers. Default 5."),
		func(x): return str(x), true))


func _pane_video(v: VBoxContainer) -> void:
	var mode := str(Settings.get_value("window_mode"))
	v.add_child(UIKit.setting_choice(
		"window_mode", I18n.t("Window mode"),
		I18n.t("Borderless is a window the size of your screen with no frame — it alt-tabs faster than exclusive fullscreen."),
		Settings.WINDOW_MODES,
		[I18n.t("Windowed"), I18n.t("Borderless"), I18n.t("Fullscreen")],
		true, _build))
	# Real but inapplicable outside windowed mode, so the row is greyed rather
	# than hidden: it stays where the player last saw it, and the reason it is
	# unavailable is a sentence they can read.
	v.add_child(UIKit.setting_choice(
		"resolution", I18n.t("Window size"),
		I18n.t("Sizes larger than your screen are not offered.") if mode == "windowed"
			else I18n.t("Only applies in windowed mode."),
		Settings.available_resolutions(), Settings.available_resolutions(),
		mode == "windowed"))
	v.add_child(UIKit.setting_choice(
		"vsync", I18n.t("V-Sync"),
		I18n.t("On removes tearing. Adaptive tears rather than halving the frame rate when a frame is missed."),
		Settings.VSYNC_MODES,
		[I18n.t("Off"), I18n.t("On"), I18n.t("Adaptive")]))
	v.add_child(UIKit.setting_slider(
		"max_fps", I18n.t("Frame rate cap"),
		I18n.t("Caps the whole main loop. Useful on a laptop — this game does not need 240 frames a second."),
		func(x): return I18n.t("unlimited") if int(x) <= 0 else str(x), true))
	v.add_child(UIKit.setting_slider(
		"ui_scale", I18n.t("Interface scale"),
		I18n.t("Magnifies the whole interface, spacing included. For text alone, see INTERFACE."),
		func(x): return "%d%%" % round(float(x) * 100.0)))


func _pane_audio(v: VBoxContainer) -> void:
	v.add_child(UIKit.setting_slider(
		"master_volume", I18n.t("Master volume"),
		I18n.t("Everything, at once."),
		func(x): return _pct(x)))
	v.add_child(UIKit.setting_slider(
		"sfx_volume", I18n.t("Sound effects"),
		I18n.t("Cards, coins, the sitter arriving and leaving."),
		func(x): return _pct(x)))
	v.add_child(UIKit.setting_slider(
		"ui_volume", I18n.t("Interface sounds"),
		I18n.t("The click as focus moves and as a button is pressed. Playing on the keyboard, this is the sound you hear most."),
		func(x): return _pct(x)))
	v.add_child(UIKit.setting_toggle("muted", I18n.t("Mute"), I18n.t("Silence everything.")))
	# Said out loud rather than left for someone to wonder about. There is no
	# music slider because there is no music; adding one would be the first
	# control in this game that does nothing.
	v.add_child(UIKit.block(I18n.t(
		"Every sound in the game is a placeholder for now, and there is no music yet — which is why there is no music slider. See docs/SOUND_GUIDE.md."
	), 11, UIKit.DIM))


func _pane_interface(v: VBoxContainer) -> void:
	v.add_child(UIKit.setting_slider(
		"animation_scale", I18n.t("Animation speed"),
		I18n.t("How fast cards deal, bars fill and values pulse. Set to 0 for no motion at all — the game jumps straight to each end state."),
		func(x): return I18n.t("off") if float(x) <= 0.01 else "%.2fx" % float(x)))
	v.add_child(UIKit.setting_slider(
		"text_scale", I18n.t("Text size"),
		I18n.t("Makes the words bigger without magnifying the layout around them. Cards grow to match."),
		func(x): return _pct(x)))
	v.add_child(UIKit.setting_toggle(
		"high_contrast", I18n.t("High contrast"),
		I18n.t("A black ground, white text, and stronger secondary text. The game's usual dim greys are a deliberate look and hard to read for some people."),
		func(_p): _build()))


func _pane_controls(v: VBoxContainer) -> void:
	v.add_child(UIKit.block(I18n.t(
		"The whole game is playable from the keyboard or a gamepad: Tab and the arrow keys move between things, and Confirm activates whatever is highlighted."
	), 11, UIKit.DIM))
	for entry in Settings.ACTIONS:
		v.add_child(_keybind_row(entry[0], entry[1]))
	v.add_child(UIKit.block(I18n.t(
		"The gamepad button on the right is shown, not editable: only the keyboard key is rebindable, so changing one never costs you a controller button."
	), 11, UIKit.DIM))


func _pane_language(v: VBoxContainer) -> void:
	v.add_child(_language_row())
	var cov := I18n.coverage(I18n.current())
	if int(cov["total"]) > 0:
		var pct := int(round(100.0 * float(cov["translated"]) / float(cov["total"])))
		v.add_child(UIKit.block(I18n.t(
			"%d%% translated (%d of %d strings). Anything untranslated falls back to English."
		) % [pct, cov["translated"], cov["total"]], 11, UIKit.DIM))


func _pane_content(v: VBoxContainer) -> void:
	v.add_child(UIKit.setting_toggle(
		"load_example_mods", I18n.t("Load example mods"),
		I18n.t("Loads the bundled demo mod in mods_example/. Your own mods in the user mods folder always load."),
		func(_p): Content.reload(); _build()))
	v.add_child(UIKit.block(I18n.t("Mods loaded: %s pack(s). %s") % [_pack_count(), _errors_line()],
		11, UIKit.RED if not Content.load_errors.is_empty() else UIKit.DIM))
	# `disabled_mods` is a real setting with no row of its own: which packs are
	# switched off is a decision made per pack, in front of the pack's name and
	# its load errors, which is the Mods screen. Sending the player there is
	# the honest version of listing it here.
	v.add_child(UIKit.block(I18n.t(
		"Individual packs are switched on and off in MODS, where each one's name, order and load messages are."
	), 11, UIKit.DIM))
	v.add_child(UIKit.button(I18n.t("MODS"), func(): Nav.goto_mods()))


func _pct(x) -> String:
	return "%d%%" % round(float(x) * 100.0)


# ── rows that are more than one control ─────────────────────────────────

## Switching locale rebuilds this screen so its own labels change with it —
## immediate feedback that the setting took, and the same rebuild every other
## screen gets when it is next constructed.
func _language_row() -> Control:
	var row := UIKit.setting_row(I18n.t("Language"), "")
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
	UIKit.style_text(opt, 14)
	opt.custom_minimum_size.x = 200
	opt.item_selected.connect(func(idx: int):
		# No I18n.reload() here: I18n already listens to Settings.changed for
		# the locale key, so calling it would reload the tables twice.
		Settings.set_value("locale", opt.get_item_metadata(idx))
		_build()
	)
	row.add_child(opt)
	return row


## One rebindable action. Pressing the button arms a capture: the next key
## goes to that action. Escape cancels rather than binding itself, since a
## player who has just bound Confirm to something unreachable needs one key
## that always means "get me out of this".
func _keybind_row(action: String, caption: String) -> Control:
	var row := UIKit.setting_row(I18n.t(caption), "")

	var armed := false
	var b := Button.new()
	UIKit.style_text(b)
	b.custom_minimum_size = Vector2(150 * UIKit.text_scale, 32)
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

	# The pad button, shown and not editable. Only the keyboard binding is
	# rebindable (a rebind must never cost a controller player their button),
	# so showing this as a control would promise an edit that is not offered —
	# it is a label, next to the key it sits alongside on the same action.
	var pad := Settings.pad_label(action)
	row.add_child(UIKit.label(pad if pad != "" else "—", 11, UIKit.DIM))
	return row


# ── the footer ──────────────────────────────────────────────────────────

func _actions() -> Control:
	var row := UIKit.hbox(10)
	row.add_child(UIKit.button(I18n.t("BACK"), _back))
	# Per-section reset first: it is the one someone actually wants after
	# breaking their video settings, and it does not cost them their keybinds.
	row.add_child(UIKit.button(I18n.t("RESET THIS SECTION"), _reset_section))
	row.add_child(UIKit.button(I18n.t("RESET EVERYTHING"), _reset_all))
	return row


func _reset_section() -> void:
	for key in Settings.SECTIONS[_section]["keys"]:
		Settings.set_value(key, Settings.default_for(key))
	if str(Settings.SECTIONS[_section]["id"]) == "content":
		Content.reload()
	_build()


func _reset_all() -> void:
	Settings.reset_to_defaults()
	Content.reload()
	_build()


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


func _back() -> void:
	Nav.settings_return_scene = ""
	get_tree().change_scene_to_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
