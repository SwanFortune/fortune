## Small helper library for building this pass's UI procedurally in code
## instead of hand-authoring .tscn node trees. Deliberately plain — dark
## background, readable text, no theming — this vertical slice is about
## proving the game loop and data pipeline, not matching the source
## prototype's look. The fan-of-cards hand layout, portrait moods, and
## hand-drawn tarot glyph art are still out of scope for this pass; see
## docs/PORTING_NOTES.md. Keyword tooltips (KEYS below) are ported, using
## Godot's native hover tooltip rather than the source's cursor-following one.
class_name UIKit
extends RefCounted

const BG := Color(0.08, 0.07, 0.09)
const PANEL := Color(0.13, 0.12, 0.14)
const INK := Color(0.92, 0.9, 0.84)
const DIM := Color(0.92, 0.9, 0.84, 0.55)
const GOLD := Color(0.83, 0.69, 0.22)

## Ported from KEYS in Parlour v23.dc.html (~line 1131) — the words on a card
## that mean something exact. The source's object literal defines "once"
## twice; JS keeps the second, so this does too.
const KEYS := {
	"once": "ONCE — it can be said one time a sitter, then it is spoken for good.",
	"energy": "ENERGY — what a single reading can pay for. It comes back in full every reading.",
	"draw": "DRAW — take that many more cards into your hand, straight away.",
	"discard": "DISCARD — every reading, whatever is left in your hand goes. You draw a fresh one.",
	"denial": "DENIAL — their sign. One named thing it does to every reading you give them.",
	"composure": "COMPOSURE — what you are filling. Fill it before they leave and they go home whole.",
	"faith": "FAITH — your score, and what the village says about you afterwards.",
	"centimes": "CENTIMES — money. It buys cards and ink from the apothecary.",
	"follows": "FOLLOWS — it only pays if the card said before it carried that sign.",
	"first": "FIRST — it only pays if it opens the sentence.",
	"last": "LAST — it only pays if it closes the sentence.",
}


## Composes a tooltip out of whichever glossary terms actually apply to this
## card's mechanical fields — e.g. a card with draw:2 and exhaust:true gets
## the DRAW and ONCE definitions, nothing else. Empty string if none apply.
static func card_keyword_tooltip(c: Dictionary) -> String:
	var lines: Array = []
	if c.has("draw"):
		lines.append(KEYS["draw"])
	if c.has("energy"):
		lines.append(KEYS["energy"])
	if c.has("coin"):
		lines.append(KEYS["centimes"])
	if c.get("exhaust", false):
		lines.append(KEYS["once"])
	if c.has("follows"):
		lines.append(KEYS["follows"])
	if c.has("opener"):
		lines.append(KEYS["first"])
	if c.has("closer"):
		lines.append(KEYS["last"])
	if c.get("pierce", false):
		lines.append(KEYS["denial"])
	return "\n\n".join(lines)
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
static func panel_button(lines: Array, on_pressed: Callable, enabled: bool = true, tooltip: String = "") -> Control:
	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.tooltip_text = tooltip
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


static func stat_row(caption: String, value_text: String, ratio: float, fg: Color, tooltip: String = "") -> Control:
	var row := hbox(10)
	row.tooltip_text = tooltip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label(caption, 12, DIM))
	row.add_child(bar(ratio, fg))
	row.add_child(label(value_text, 12, INK))
	return row


## A small procedural face reacting to how close the sitter is to mended
## (hp_ratio), loosely following the source's MOODS state machine (~line
## 1147: waiting/listening/reached/struck, driven by eye height, brow angle,
## mouth shape, and a warm "flush" glow) — not the source's hand-drawn
## portrait, which this pass doesn't attempt, but the same idea: composure
## climbing is legible on the sitter's face, not just in a number.
static func sitter_portrait(el: String, hp_ratio: float) -> Control:
	var port := Control.new()
	port.custom_minimum_size = Vector2(96, 96)
	var r := clampf(hp_ratio, 0.0, 1.0)
	var flush := r  # 0 = closed off, 1 = fully reached
	var base_col := Color(0.82, 0.76, 0.7)
	var skin := base_col.lerp(el_color(el), flush * 0.35)
	var glow := el_color(el)

	port.draw.connect(func():
		# soft glow ring, grows with flush
		if flush > 0.05:
			port.draw_circle(Vector2(48, 48), 46, Color(glow, 0.10 + flush * 0.18))
		port.draw_circle(Vector2(48, 48), 40, skin)
		port.draw_arc(Vector2(48, 48), 40, 0, TAU, 48, Color(0, 0, 0, 0.35), 1.5, true)

		# brows: flat and low when waiting, lifted and arched when reached
		var brow_lift := lerpf(0.0, 5.0, r)
		var brow_angle := lerpf(0.02, 0.22, r)
		for side in [-1, 1]:
			var s: float = side
			var bx: float = 48.0 + s * 13.0
			var by: float = 36.0 - brow_lift
			port.draw_line(Vector2(bx - 6, by + s * brow_angle * 10.0), Vector2(bx + 6, by - s * brow_angle * 10.0), Color(0.25, 0.2, 0.15), 2.0, true)

		# eyes: small and half-lidded when waiting, wide when reached
		var eye_h := lerpf(2.0, 7.0, r)
		for side in [-1, 1]:
			var s2: float = side
			var ex: float = 48.0 + s2 * 13.0
			port.draw_rect(Rect2(ex - 3.5, 42.0 - eye_h * 0.5, 7.0, eye_h), Color(0.2, 0.15, 0.12), true)

		# mouth: flat when waiting, a rising arc (smile) as they're reached
		var mouth_w := lerpf(10.0, 16.0, r)
		var mouth_curve := lerpf(0.0, 10.0, r)
		var pts := PackedVector2Array()
		var steps := 12
		for i in steps + 1:
			var t := float(i) / float(steps)
			var x := 48.0 - mouth_w + t * mouth_w * 2.0
			var y := 62.0 - sin(t * PI) * mouth_curve
			pts.append(Vector2(x, y))
		for i in pts.size() - 1:
			port.draw_line(pts[i], pts[i + 1], Color(0.3, 0.18, 0.14), 2.2, true)
	)
	return port


static func el_color(el: String) -> Color:
	var elements: Dictionary = Content.elements
	var hex: String = elements.get(el, {}).get("color", "#EAE4D7")
	return Color(hex)


## The source draws a hand-inked SVG icon per element; this port uses the
## same glyph character the source's own card art falls back to internally
## (elements.json's "glyph" field — △▽◇□) rather than building an SVG/vector
## icon pipeline. Cheap, but it's literally the source's own symbol, not an
## invented substitute.
static func el_glyph(el: String) -> String:
	var elements: Dictionary = Content.elements
	return elements.get(el, {}).get("glyph", "")


## "△ FIRE" — glyph + element name, colored by the caller. Used anywhere the
## source would show an element chip (a sitter's element, a reader's rule
## line, a card's element tag).
static func el_tag(el: String) -> String:
	if el == null or el == "":
		return ""
	return "%s %s" % [el_glyph(el), str(el).to_upper()]


static func card_summary(c: Dictionary) -> String:
	var bits: Array = []
	var el = c.get("el")
	if el != null and el != "":
		bits.append(el_glyph(el))
	bits.append(c.get("n", "?"))
	return " ".join(bits)


static func card_text(c: Dictionary) -> String:
	if c.get("custom", false):
		return c.get("text", "")
	return Rules.auto_text(c)


const CARD_FACE_SIZE := Vector2(122, 158)

## A fixed-size card face for the hand fan — cost top-left, base restore
## top-right, name centered, element-colored border; the full mechanic text,
## flavor, and keyword glossary all move into the hover tooltip since there's
## no room to print them at this size. This mirrors the source's own card
## design rule ("no numbers in the face beyond cost/restore, everything else
## is a tooltip") more closely than the roomy panel_button rows PickScreen
## and the pre-fan hand list use — those stay as they are; a reward/shop
## choice benefits from full text visible, a hand fan does not.
static func card_face(c: Dictionary, on_pressed: Callable, enabled: bool = true) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = CARD_FACE_SIZE
	var el = c.get("el")
	var el_c: Color = el_color(el) if el != null and el != "" else DIM
	var tip_lines: Array = [card_text(c)]
	if c.get("fl", "") != "":
		tip_lines.append(c["fl"])
	var kw := card_keyword_tooltip(c)
	if kw != "":
		tip_lines.append(kw)
	wrap.tooltip_text = "\n\n".join(tip_lines)

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL if enabled else Color(PANEL, 0.5)
	style.set_content_margin_all(8)
	style.set_border_width_all(2)
	style.border_color = el_c if enabled else Color(el_c, 0.35)
	for c4 in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(c4, 5)
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

	var v := vbox(4)
	var top := hbox(0)
	var cost_l := label(str(c.get("cost", 0)), 13, GOLD if enabled else DIM)
	var restore_l := label("+%s" % c.get("f", 0), 13, GREEN if enabled else DIM)
	restore_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cost_l)
	top.add_child(restore_l)
	v.add_child(top)

	var name_l := block(card_summary(c), 12, INK if enabled else DIM)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(name_l)

	var tags: Array = []
	if c.get("exhaust", false):
		tags.append("ONCE")
	if c.get("pierce", false):
		tags.append("PIERCE")
	if tags.size() > 0:
		var tag_l := label(" · ".join(tags), 9, DIM)
		tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag_l)

	wrap.add_child(v)
	return wrap
