## The Minitel terminal. Dial 3615, type four letters, press ENVOI.
##
## The screen is a thin shell over autoload/Minitel.gd — it composes what the
## player typed, hands it to submit(), and prints what comes back. It holds no
## rules of its own on purpose: the tests drive Minitel directly, so anything
## that lived here would be untested by construction.
##
## The player types the PREFIX too, rather than it being printed on the case as
## decoration. Minitel.submit() refuses a wrong prefix with its own line, and a
## refusal nobody can trigger is not worth having; more to the point, dialling
## 3615 is the half of the gesture people remember.
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")

## The terminal's own palette, local to this screen. Everything else in the
## game is ink-on-dark parchment; a Minitel was a cathode tube in a beige box,
## and it should not look like the rest of the parlour.
const SCREEN_BG := Color(0.04, 0.06, 0.05)
const PHOSPHOR := Color(0.63, 0.94, 0.68)
const PHOSPHOR_DIM := Color(0.63, 0.94, 0.68, 0.45)
const PHOSPHOR_WARN := Color(0.95, 0.78, 0.42)

## Roughly the width of a Minitel 1B's screen at this font size. See _build().
const COLUMN_WIDTH := 600

var _return_scene: String = "res://scenes/MainMenu.tscn"

## The last submit()'s result, or {} before the first one. Only ever produced
## by Minitel.submit() — this screen never builds one itself.
var _last: Dictionary = {}

var _prefix_field: LineEdit
var _code_field: LineEdit


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)

	# Centred, and CAPPED IN WIDTH. Every other screen in the game fills the
	# window because it is showing a hand or a list that wants the room; this
	# one is a single object sitting on a sideboard, and stretched across a
	# 1152px window the tube read as a banner rather than as a screen. The cap
	# is what makes it look like a machine.
	var page := UIKit.vbox(0)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(page)
	var outer := UIKit.vbox(12)
	outer.custom_minimum_size.x = COLUMN_WIDTH
	outer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("MINITEL"), 26, UIKit.GOLD))
	outer.add_child(UIKit.block(
		I18n.t("It hums on the sideboard where the telephone used to be. Someone left the bill unpaid and it never stopped working."),
		12, UIKit.DIM))

	outer.add_child(_terminal())
	outer.add_child(_composer())
	outer.add_child(_log())

	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	outer.add_child(actions)

	# The code field, not the first button: the player came here to type.
	if _code_field != null:
		_code_field.call_deferred("grab_focus")
	else:
		UIKit.focus_first(self)


# ── the tube ────────────────────────────────────────────────────────────

## The printed area. Always says something — before the first dial it prints
## the service's own idle line, so the screen is never a blank rectangle the
## player has to guess at.
func _terminal() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = SCREEN_BG
	style.set_content_margin_all(16)
	style.set_border_width_all(2)
	style.border_color = Color(0.2, 0.3, 0.24)
	panel.add_theme_stylebox_override("panel", style)

	var v := UIKit.vbox(2)
	# Four service lines plus a blank row, so the tube keeps its shape whether
	# a code printed one line or five and the composer below never jumps.
	v.custom_minimum_size.y = 118
	for line in _screen_lines():
		# An empty line in a service's text is a deliberate blank row, and a
		# Label with no text collapses to nothing — so it becomes a spacer of
		# one line's height instead, keeping the author's layout.
		if str(line[0]) == "":
			var sp := Control.new()
			sp.custom_minimum_size.y = 14
			v.add_child(sp)
		else:
			v.add_child(UIKit.block(str(line[0]), 15, line[1]))
	panel.add_child(v)
	return panel


## [text, colour] rows for the tube.
func _screen_lines() -> Array:
	if _last.is_empty():
		return [
			[Minitel.SAY_IDLE, PHOSPHOR],
			["", PHOSPHOR],
			[Minitel.SAY_FORMAT, PHOSPHOR_DIM],
		]
	var colour: Color = PHOSPHOR
	if _last["kind"] == Minitel.UNKNOWN or _last["kind"] == Minitel.BAD_FORMAT:
		colour = PHOSPHOR_WARN
	var out: Array = []
	for line in _last["lines"]:
		out.append([str(line), colour])
	return out


# ── the keyboard ────────────────────────────────────────────────────────

func _composer() -> Control:
	var row := UIKit.hbox(10)

	_prefix_field = _field(4, "3615")
	# Digits only, and no accidental letters in the tariff prefix: it is a
	# number you dialled, not a word.
	_prefix_field.text_changed.connect(func(t: String): _clean(_prefix_field, t, false))
	row.add_child(_prefix_field)

	_code_field = _field(Minitel.CODE_LENGTH, "ABCD")
	_code_field.text_changed.connect(func(t: String): _clean(_code_field, t, true))
	# Enter sends, because on a Minitel the ENVOI key was the whole interface.
	_code_field.text_submitted.connect(func(_t: String): _send())
	row.add_child(_code_field)

	row.add_child(UIKit.button(I18n.t("ENVOI"), _send))
	return row


func _field(length: int, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = length
	e.placeholder_text = placeholder
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size = Vector2(90, 36)
	e.add_theme_color_override("font_color", PHOSPHOR)
	e.add_theme_font_size_override("font_size", 18)
	return e


## Uppercases and drops anything of the wrong kind as it is typed, keeping the
## caret where the player left it. Minitel.normalise() would reject the bad
## characters anyway — this simply means the field can never show something the
## terminal is about to refuse.
func _clean(field: LineEdit, text: String, letters: bool) -> void:
	var kept := ""
	for ch in text.to_upper():
		if letters and ch >= "A" and ch <= "Z":
			kept += ch
		elif not letters and ch >= "0" and ch <= "9":
			kept += ch
	if kept == text:
		return
	var caret := field.caret_column - (text.length() - kept.length())
	field.text = kept
	field.caret_column = maxi(caret, 0)


func _send() -> void:
	var prefix := _prefix_field.text
	var code := _code_field.text
	_last = Minitel.submit(prefix, code)
	Audio.play("ui_press" if _last["kind"] == Minitel.OK else "ui_move")
	# A code that took clears the field; a refused one is left in place, so the
	# player can see the typo rather than retyping from memory.
	var cleared: bool = _last["kind"] == Minitel.OK
	_build()
	if cleared:
		_code_field.text = ""
	else:
		_code_field.text = code
		_code_field.caret_column = code.length()
	_prefix_field.text = prefix


# ── what has been dialled ───────────────────────────────────────────────

## The player's own history. No hints and no counter of undiscovered codes:
## "3 of 8 found" turns a secret into a chore, and there is no honest total to
## print anyway once a mod can add its own.
func _log() -> Control:
	var v := UIKit.vbox(4)
	var seen: Array = Minitel.entered()
	if seen.is_empty():
		v.add_child(UIKit.block(I18n.t("You have not dialled anything yet."), 11, UIKit.DIM))
		return v
	v.add_child(UIKit.block(I18n.t("SERVICES YOU HAVE REACHED"), 12, UIKit.GOLD))
	for code in seen:
		v.add_child(UIKit.block("3615 " + str(code), 12, UIKit.DIM))
	return v


func _back() -> void:
	get_tree().change_scene_to_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
