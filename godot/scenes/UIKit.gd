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


## Single-line label at its natural (unwrapped) width. Use for short fixed
## strings — captions, chip labels, anything sitting in an HBoxContainer row
## next to other content — where staying at natural width is the point.
## NOT for anything that might need to wrap: see block() for that, and read
## its doc comment before reaching for autowrap on a one-off Label — it's a
## sharper edge than it looks.
static func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A wrapping, full-width label — use for any title/body/flavor-length text
## added directly to a vertical layout (a VBoxContainer, or a Container
## descended from one). Two things have to both be true for a wrapping Label
## to render sanely, and it's easy to only do one of them:
##   1. autowrap_mode has to be on (this is the part that's obvious).
##   2. size_flags_horizontal has to include EXPAND, or the Label has no way
##      to claim real width. This part is the trap: Godot sizes a Label's
##      *minimum* width from its content bottom-up, and a wrapping Label's
##      reported minimum is tiny — often one character — since by definition
##      it doesn't need width, it can always wrap more. A non-expand child in
##      any Container gets exactly its minimum size, no more. Put those two
##      sentences together and a wrapping Label with default size flags
##      renders as a single character-wide column, no matter how much space
##      its parent actually has to give it. (This is also true one level up:
##      a Control that isn't itself a Container — Button chief among them —
##      doesn't auto-size a manually-added child at all, wrapping or not; see
##      panel_button()'s doc comment for that half of the trap.)
static func block(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# set_anchors_preset is a no-op once this is placed inside a Container
	# parent (the parent's layout algorithm positions/sizes it directly) —
	# what actually matters is the size flag, so the parent VBoxContainer
	# stretches this to its own width instead of shrinking to content.
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


static func margin(px: int = 24) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	return m


## A clickable multi-line row — used for every card/reader/sitter/reward
## option in the game. Deliberately built on PanelContainer + gui_input
## rather than Button: Button is a plain Control, not a Container, so a rich
## multi-Label child added to it isn't auto-sized the way a real Container's
## children are — its minimum size doesn't account for manually-added
## children at all, which (before this was rewritten) left every wrapping
## Label fighting for a ~20px column regardless of size flags. PanelContainer
## is a real Container top-to-bottom, so width flows down and each Label's
## wrapped height correctly flows back up into how tall this row ends up.
static func panel_button(lines: Array, on_pressed: Callable, enabled: bool = true) -> Control:
	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL if enabled else Color(PANEL, 0.5)
	style.set_content_margin_all(10)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	wrap.add_theme_stylebox_override("panel", style)

	if enabled:
		wrap.mouse_filter = Control.MOUSE_FILTER_STOP
		wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		wrap.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call()
		)
		wrap.mouse_entered.connect(func(): style.bg_color = PANEL.lightened(0.12))
		wrap.mouse_exited.connect(func(): style.bg_color = PANEL)
	else:
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var v := vbox(2)
	for entry in lines:
		var text: String = entry[0]
		var size: int = entry[1] if entry.size() > 1 else 14
		var color: Color = entry[2] if entry.size() > 2 else INK
		v.add_child(block(text, size, color))
	wrap.add_child(v)
	return wrap


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
