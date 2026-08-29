## Small helper library for building this pass's UI procedurally in code
## instead of hand-authoring .tscn node trees. Deliberately plain — dark
## background, readable text, no theming — this vertical slice is about
## proving the game loop and data pipeline, not matching the source
## prototype's look. Visual polish (the fan of cards, portrait moods, tarot
## glyph art, tooltip system) is out of scope for this pass; see
## docs/PORTING_NOTES.md.
class_name UIKit
extends RefCounted

const BG := Color(0.08, 0.07, 0.09)
const PANEL := Color(0.13, 0.12, 0.14)
const INK := Color(0.92, 0.9, 0.84)
const DIM := Color(0.92, 0.9, 0.84, 0.55)
const GOLD := Color(0.83, 0.69, 0.22)
const GREEN := Color(0.56, 0.75, 0.45)
const RED := Color(0.82, 0.42, 0.38)


static func root_control() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	return c


static func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	b.custom_minimum_size = Vector2(0, 36)
	return b


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


static func margin(px: int = 24) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	return m


static func panel_button(lines: Array, on_pressed: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.pressed.connect(on_pressed)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var v := vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in lines:
		var text: String = entry[0]
		var size: int = entry[1] if entry.size() > 1 else 14
		var color: Color = entry[2] if entry.size() > 2 else INK
		v.add_child(label(text, size, color))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.add_child(v)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	return b


## A plain two-rect meter (no Theme/StyleBox fuss) — used for composure and
## energy on the Reading screen. `ratio` is clamped to [0, 1].
static func bar(ratio: float, fg: Color, w: float = 260, h: float = 14) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fg
	fill.position = Vector2.ZERO
	fill.size = Vector2(w * clampf(ratio, 0.0, 1.0), h)
	c.add_child(fill)
	return c


static func stat_row(caption: String, value_text: String, ratio: float, fg: Color) -> Control:
	var row := hbox(10)
	row.add_child(label(caption, 12, DIM))
	row.add_child(bar(ratio, fg))
	row.add_child(label(value_text, 12, INK))
	return row


static func el_color(el: String) -> Color:
	var elements: Dictionary = Content.elements
	var hex: String = elements.get(el, {}).get("color", "#EAE4D7")
	return Color(hex)


static func card_summary(c: Dictionary) -> String:
	var bits: Array = []
	bits.append(c.get("n", "?"))
	if c.get("el") != null and c.get("el") != "":
		bits.append("[" + str(c["el"]).to_upper() + "]")
	return " ".join(bits)


static func card_text(c: Dictionary) -> String:
	if c.get("custom", false):
		return c.get("text", "")
	return Rules.auto_text(c)
