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
const Table := preload("res://scenes/Table.gd")

## The terminal's own palette, local to this screen. Everything else in the
## game is ink-on-dark parchment; a Minitel was a cathode tube in a beige box,
## and it should not look like the rest of the parlour.
const SCREEN_BG := Color(0.04, 0.06, 0.05)
const PHOSPHOR := Color(0.63, 0.94, 0.68)
const PHOSPHOR_DIM := Color(0.63, 0.94, 0.68, 0.45)
const PHOSPHOR_WARN := Color(0.95, 0.78, 0.42)

## Roughly the width of a Minitel 1B's screen at this font size. See _build().
const COLUMN_WIDTH := 600

## The case around the tube. The screen had a green rectangle on it and nothing
## else, which is a terminal emulator; the machine itself — the beige box, the
## bezel, the curved dark glass, the scan lines and the little red light that
## says it is on — is most of what anyone remembers about a Minitel, and it was
## the one thing the game draws on the parlour table (see scenes/Table.gd) and
## did not draw on the screen named after it.
const TUBE_HEIGHT := 150
const CASE_PAD := 26
const CASE_FOOT := 30
const CASE := Color(0.42, 0.39, 0.33)
const CASE_LIT := Color(0.50, 0.46, 0.39)
const CASE_SHADE := Color(0.27, 0.25, 0.21)
const BEZEL := Color(0.13, 0.12, 0.10)
const POWER_LED := Color(0.92, 0.30, 0.22)

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

	var root := UIKit.root_control(Table.VIEW_WALL)
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
	var stack := Control.new()
	stack.custom_minimum_size.y = TUBE_HEIGHT + CASE_PAD * 2 + CASE_FOOT
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The machine, drawn behind the text. A plain Control rather than a
	# PanelContainer with a StyleBox: a StyleBox can do a rounded beige box and
	# cannot do scan lines, a curved glass edge or a power light, and those are
	# the three things that make it a Minitel rather than a green rectangle.
	var skin := Control.new()
	skin.set_anchors_preset(Control.PRESET_FULL_RECT)
	skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skin.draw.connect(func(): _draw_case(skin))
	skin.resized.connect(func(): skin.queue_redraw())
	stack.add_child(skin)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right"]:
		pad.add_theme_constant_override("margin_" + side, CASE_PAD + 12)
	pad.add_theme_constant_override("margin_bottom", CASE_PAD + CASE_FOOT + 12)
	stack.add_child(pad)

	var v := UIKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	v.add_child(_cursor())
	pad.add_child(v)
	return stack


## The block cursor sitting under the last line, blinking. A cathode terminal
## with nothing blinking on it looks switched off.
func _cursor() -> Control:
	var caret := ColorRect.new()
	caret.color = PHOSPHOR
	caret.custom_minimum_size = Vector2(10, 15)
	caret.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not UIKit.motion_off():
		var t := UIKit.bound_tween(caret)
		t.set_loops()
		t.tween_property(caret, "modulate:a", 0.0, UIKit.dur(0.01)).set_delay(UIKit.dur(0.5))
		t.tween_property(caret, "modulate:a", 1.0, UIKit.dur(0.01)).set_delay(UIKit.dur(0.5))
	return caret


## The beige box, the bezel, the glass and the light.
func _draw_case(c: Control) -> void:
	var s := c.size
	if s.x < 40.0 or s.y < 40.0:
		return
	var body := Rect2(Vector2.ZERO, s)
	_rounded(c, body, 12.0, CASE_SHADE)
	_rounded(c, Rect2(body.position, body.size - Vector2(0, 3)), 12.0, CASE)
	# The lit top edge, which is what makes moulded plastic read as moulded.
	c.draw_line(Vector2(14, 2), Vector2(s.x - 14, 2), Color(CASE_LIT, 0.9), 2.0, true)

	# The bezel, then the glass sunk into it.
	var glass := Rect2(CASE_PAD, CASE_PAD, s.x - CASE_PAD * 2.0, s.y - CASE_PAD - CASE_FOOT)
	_rounded(c, glass.grow(5.0), 9.0, BEZEL)
	_rounded(c, glass, 7.0, SCREEN_BG)

	# The phosphor haze, brightest in the middle where the text is.
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_circle(glass.position + glass.size * Vector2(0.5, 0.45),
			glass.size.x * 0.52 * f, Color(PHOSPHOR, 0.012))

	# Scan lines. Three pixels apart is what reads as a tube rather than as a
	# hatch pattern, and the alpha has to stay low enough to leave the words
	# alone — the point is the surface, not the effect.
	var y := glass.position.y + 1.0
	while y < glass.end.y:
		c.draw_line(Vector2(glass.position.x + 2.0, y), Vector2(glass.end.x - 2.0, y),
			Color(0, 0, 0, 0.16), 1.0)
		y += 3.0

	# The corners of the glass, going off into the dark the way a curved tube
	# does. Four soft wedges rather than a real barrel distortion, which would
	# need a shader and would be the wrong amount of work for a bezel.
	for i in 10:
		var f := float(i) / 10.0
		var inset := glass.grow(-glass.size.y * 0.42 * f)
		c.draw_rect(Rect2(glass.position, Vector2(glass.size.x, inset.position.y - glass.position.y)), Color(0, 0, 0, 0.035))
		c.draw_rect(Rect2(glass.position.x, inset.end.y, glass.size.x, glass.end.y - inset.end.y), Color(0, 0, 0, 0.035))

	# The foot: vents, and the light that says it is on.
	var foot_y := glass.end.y + 12.0
	for i in 9:
		var vx := s.x - CASE_PAD - 8.0 - float(i) * 9.0
		c.draw_line(Vector2(vx, foot_y), Vector2(vx, foot_y + 9.0), Color(CASE_SHADE, 0.85), 3.0)
	c.draw_circle(Vector2(CASE_PAD + 6.0, foot_y + 5.0), 6.0, Color(POWER_LED, 0.18))
	c.draw_circle(Vector2(CASE_PAD + 6.0, foot_y + 5.0), 2.6, POWER_LED)


## A filled rounded rectangle. Same construction as scenes/Table.gd's; kept
## local because this screen is the only thing in the file that needs one.
func _rounded(c: Control, rect: Rect2, r: float, col: Color) -> void:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	const CORNERS := [[PI, 1.5 * PI], [1.5 * PI, TAU], [0.0, 0.5 * PI], [0.5 * PI, PI]]
	var centres := [
		rect.position + Vector2(r, r),
		rect.position + Vector2(rect.size.x - r, r),
		rect.end - Vector2(r, r),
		rect.position + Vector2(r, rect.size.y - r),
	]
	for i in 4:
		for j in 7:
			var a: float = lerpf(CORNERS[i][0], CORNERS[i][1], float(j) / 6.0)
			pts.append(centres[i] + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(pts, col)


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
