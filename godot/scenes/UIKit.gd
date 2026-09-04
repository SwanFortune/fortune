## The house style, and the widgets built in it. Every screen in the game is
## assembled from this file in code rather than from hand-authored .tscn trees.
##
## Two things here are load-bearing rather than cosmetic, and both are traps
## Godot sets rather than choices: block() explains why a wrapping Label needs
## EXPAND to render at all, and panel_button() explains why the game's rows are
## PanelContainers rather than Buttons. Read those before adding a widget.
class_name UIKit
extends RefCounted

## The palette. `static var`, not `const`, so the high-contrast setting can
## swap it — every call site still reads `UIKit.INK` unchanged, which is the
## whole reason for doing it this way rather than threading a theme through
## forty constructors. Written only by apply_palette(), from Settings.
##
## Both palettes are defined below in NORMAL and HIGH; these are the live
## values, and they start as NORMAL so a screen built before Settings has run
## (the tools, a test that never touches Settings) still has real colours.
static var BG := Color(0.08, 0.07, 0.09)
static var PANEL := Color(0.13, 0.12, 0.14)
static var INK := Color(0.92, 0.9, 0.84)
static var DIM := Color(0.92, 0.9, 0.84, 0.55)
static var GOLD := Color(0.83, 0.69, 0.22)
## The keyboard/gamepad focus ring. Distinct from GOLD so a focused row is
## still tellable apart from a row that is merely gold-accented.
static var FOCUS := Color(0.45, 0.78, 0.95)

## Multiplies every font size handed out by label()/block(), and the card face
## with them so the words still fit inside it. Driven by Settings.text_scale.
static var text_scale := 1.0

## The game's own look: warm off-white on near-black, with a lot of the
## secondary text carried at 55% alpha. That reads as a parlour at night and is
## genuinely hard to see for anyone who cannot pick low-contrast greys off a
## dark ground.
const NORMAL := {
	"bg": Color(0.08, 0.07, 0.09),
	"panel": Color(0.13, 0.12, 0.14),
	"ink": Color(0.92, 0.9, 0.84),
	"dim": Color(0.92, 0.9, 0.84, 0.55),
	"gold": Color(0.83, 0.69, 0.22),
	"focus": Color(0.45, 0.78, 0.95),
}

## High contrast. Not a filter over the above — a second set of chosen values.
## The ground goes to true black, the ink to true white, DIM keeps its role as
## "secondary" but at 85% rather than 55%, panels separate further from the
## ground, and gold and the focus ring are both brightened so they stay
## distinguishable from ink now that ink is white.
const HIGH := {
	"bg": Color(0.0, 0.0, 0.0),
	"panel": Color(0.18, 0.17, 0.2),
	"ink": Color(1.0, 1.0, 1.0),
	"dim": Color(1.0, 1.0, 1.0, 0.85),
	"gold": Color(1.0, 0.84, 0.31),
	"focus": Color(0.42, 0.85, 1.0),
}


## Points the live palette at one of the two sets. Called by Settings whenever
## `high_contrast` changes, and once at startup.
static func apply_palette(high: bool) -> void:
	var p: Dictionary = HIGH if high else NORMAL
	BG = p["bg"]
	PANEL = p["panel"]
	INK = p["ink"]
	DIM = p["dim"]
	GOLD = p["gold"]
	FOCUS = p["focus"]

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
		lines.append(I18n.t(KEYS["draw"]))
	if c.has("energy"):
		lines.append(I18n.t(KEYS["energy"]))
	if c.has("coin"):
		lines.append(I18n.t(KEYS["centimes"]))
	if c.get("exhaust", false):
		lines.append(I18n.t(KEYS["once"]))
	if c.has("follows"):
		lines.append(I18n.t(KEYS["follows"]))
	if c.has("opener"):
		lines.append(I18n.t(KEYS["first"]))
	if c.has("closer"):
		lines.append(I18n.t(KEYS["last"]))
	if c.get("pierce", false):
		lines.append(I18n.t(KEYS["denial"]))
	return "\n\n".join(lines)
const GREEN := Color(0.56, 0.75, 0.45)
const RED := Color(0.82, 0.42, 0.38)
## The denial wall's colour, taken from the source prototype's own bar
## (oklch(0.62 0.13 300), line ~728). Violet is not used anywhere else, which is
## the point: on the composure bar it is the one segment that is not yours.
const VIOLET := Color(0.55, 0.42, 0.78)


## Every screen starts by calling this, which makes it the one hook that is
## guaranteed to run before anything is built and after every autoload exists —
## so it is where the look settings are read. See Settings._apply_look()'s
## comment for why they are pulled here rather than pushed from there.
static func refresh_look() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var settings := tree.root.get_node_or_null("Settings")
	if settings == null:
		return   # a tool running without the autoloads: keep the defaults
	apply_palette(bool(settings.get_value("high_contrast")))
	text_scale = float(settings.get_value("text_scale"))


## `room` picks which view of the parlour is drawn behind the screen — see
## scenes/Table.gd. It is a parameter of THIS function and not something each
## screen does for itself, because "every screen is somewhere" is a rule, and a
## rule that each of thirteen screens has to remember is a rule that a
## fourteenth will break. tests/test_scenes.gd asserts the room is there.
##
## Table.gd is loaded by path rather than preloaded: this file is reached from
## autoloads, and preload() resolves at compile time, before `godot -s` has
## registered them. See autoload/Content.gd's header — seventh time.
static func root_control(room: String = "table") -> Control:
	refresh_look()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Still here under the room. The room draws over all of it, but a screen
	# that somehow gets no room, or a frame before the room has been sized, must
	# not show whatever was on screen before it.
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	if room != "none":
		c.add_child((load("res://scenes/Table.gd") as GDScript).background(room))
	return c


## A dark gradient down one side of the screen, so a column of text can sit on
## a drawn room and still be read.
##
## The alternative is a scrim over the WHOLE backdrop, which is what a first
## pass reached for — and it quietens the part of the room nothing is written on
## just as much as the part that needs it, so you pay for the room and then hide
## it. This darkens only the side the words are on and leaves the rest alone.
static func side_scrim(width: float, strength: float = 0.55) -> Control:
	var c := Control.new()
	c.name = "Scrim"
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var steps := 26
		for i in steps:
			var f := float(i) / float(steps)
			# Solid at the edge, gone by `width`. Squared so it holds its
			# darkness under the text and falls away quickly past it.
			c.draw_rect(Rect2(0, 0, width * (1.0 - f), c.size.y),
				Color(0, 0, 0, strength / float(steps)))
	)
	c.resized.connect(func(): c.queue_redraw())
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
	# The one place font sizes are set, which is what makes text_scale a
	# one-line feature instead of forty. maxi(...,1) because a 9px tag at the
	# bottom of the range must not round to zero and vanish.
	l.add_theme_font_size_override("font_size", maxi(int(round(size * text_scale)), 1))
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


## The default font size of Godot's Button theme. Buttons do not go through
## label(), so text_scale would otherwise leave every button in the game at
## 100% while the words around them grew — which looked, at 130%, exactly like
## a bug.
const BUTTON_FONT_SIZE := 16


## Applies the live text scale and palette to a Control whose text comes from
## the theme rather than from label() — Button and its subclasses.
static func style_text(c: Control, base: int = BUTTON_FONT_SIZE) -> void:
	c.add_theme_font_size_override("font_size", maxi(int(round(base * text_scale)), 1))
	c.add_theme_color_override("font_color", INK)


# ── surfaces ────────────────────────────────────────────────────────────
#
# Everything in the game that is a box comes out of this section. The look is
# one sentence: warm dark paper, rounded a little, a hairline of ink around it
# and a soft shadow under it, gold only where something is live.
#
# Every colour derives from the LIVE palette (see apply_palette) rather than
# being written out, so the high-contrast setting keeps working without a
# second set of boxes to maintain.

## How round everything is. One number: a game with three corner radii in it
## looks like three games.
const RADIUS := 5
## The lift under a panel. Small — this is a table with paper on it, not a
## phone with cards floating over it.
const SHADOW := 4

## The group every "leave this screen for the main menu" control belongs to.
##
## A group rather than a naming convention, because it is what a test can ask
## about without matching on words: tests/test_scenes.gd builds every screen a
## run can be on and fails if any of them has nothing in this group. A screen
## with no way out looks exactly like a screen, so nothing else catches it.
const WAY_OUT := "way_out"


## Warms a colour toward gold. What makes the panels read as lamplight on paper
## rather than as grey, without a second palette to keep in step.
static func warm(c: Color, amount: float) -> Color:
	return Color(c.r, c.g, c.b, c.a).lerp(Color(GOLD.r, GOLD.g, GOLD.b, c.a), amount)


## The one place a surface is described.
static func surface(fill: Color, border: Color = Color(0, 0, 0, 0), width: int = 1,
		pad: int = 10, shadow: float = 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(RADIUS)
	box.set_content_margin_all(pad)
	box.border_color = border
	box.set_border_width_all(width if border.a > 0.0 else 0)
	if shadow > 0.0:
		box.shadow_color = Color(0, 0, 0, 0.45 * shadow)
		box.shadow_size = int(SHADOW * shadow)
		box.shadow_offset = Vector2(0, 2)
	return box


## Dresses a Button. Godot's default theme is a grey slab with square-ish
## corners and no relationship to anything else on screen; every Button in the
## game goes through here instead, including the two built outside button()
## (the run header's chips and the keybind rows).
##
## `weight` scales the whole treatment down for small chrome: 1.0 is a menu
## entry, 0.6 is a chip in the header that should not shout.
##
## The padding is WIDE AND SHALLOW, not square: a button is a line of text with
## air either side of it. Equal padding all round adds height to every button in
## the game, which is enough to push the last entry off the main menu.
static func style_button(b: Button, weight: float = 1.0) -> void:
	var pad_x := int(14 * weight)
	var pad_y := int(5 * weight)
	b.add_theme_stylebox_override("normal",
		_padded(surface(warm(PANEL, 0.05 * weight), Color(INK, 0.10), 1, 0, weight), pad_x, pad_y))
	b.add_theme_stylebox_override("hover",
		_padded(surface(warm(PANEL, 0.16), Color(GOLD, 0.45), 1, 0, weight), pad_x, pad_y))
	# Pressed loses the shadow: the paper is under your finger, not floating.
	b.add_theme_stylebox_override("pressed",
		_padded(surface(warm(PANEL, 0.01), Color(GOLD, 0.30), 1, 0), pad_x, pad_y))
	b.add_theme_stylebox_override("disabled",
		_padded(surface(Color(PANEL, 0.35), Color(INK, 0.06), 1, 0), pad_x, pad_y))
	# Focus is drawn OVER the state box, so it is a ring and nothing else.
	b.add_theme_stylebox_override("focus",
		_padded(surface(Color(0, 0, 0, 0), FOCUS, 2, 0), pad_x, pad_y))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))


static func _padded(box: StyleBoxFlat, x: int, y: int) -> StyleBoxFlat:
	box.content_margin_left = x
	box.content_margin_right = x
	box.content_margin_top = y
	box.content_margin_bottom = y
	return box


## Dresses an HSlider. Godot's default is a hairline with a white dot on it,
## which is the one control on the settings screen that still looked like a
## dialog box. A dark pill, gold behind the grabber, and a gold grabber.
static func style_slider(sl: HSlider) -> void:
	var track := surface(Color(0, 0, 0, 0.38), Color(INK, 0.10), 1, 0)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", track)
	var filled := surface(Color(GOLD, 0.55), Color(0, 0, 0, 0), 0, 0)
	filled.set_corner_radius_all(4)
	sl.add_theme_stylebox_override("grabber_area", filled)
	sl.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob := surface(GOLD, Color(0, 0, 0, 0.5), 1, 0)
	knob.set_corner_radius_all(7)
	knob.content_margin_left = 7
	knob.content_margin_right = 7
	knob.content_margin_top = 7
	knob.content_margin_bottom = 7
	sl.add_theme_stylebox_override("grabber", knob)
	sl.add_theme_stylebox_override("grabber_highlight", knob)


## Dresses a LineEdit — the Minitel's two fields and the Library's search box.
## Same reason as style_button(): the default is a grey slab.
static func style_field(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", surface(Color(BG, 0.85), Color(INK, 0.14), 1, 8))
	e.add_theme_stylebox_override("focus", surface(Color(BG, 0.85), FOCUS, 2, 8))
	e.add_theme_stylebox_override("read_only", surface(Color(BG, 0.5), Color(INK, 0.07), 1, 8))
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(INK, 0.30))
	e.add_theme_color_override("caret_color", GOLD)


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	style_text(b)
	# Sound goes on here rather than at each of the ~40 call sites, for the same
	# reason make_interactive() exists: one place to change, and no button that
	# somebody forgot to wire.
	b.pressed.connect(func():
		Audio.play("ui_press")
		on_pressed.call()
	)
	b.focus_entered.connect(func(): Audio.play("ui_move"))
	b.custom_minimum_size = Vector2(0, 36)
	style_button(b)
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


## Makes a PanelContainer row respond to the mouse AND to the keyboard/gamepad.
##
## Godot's Button is focusable and works out its own focus neighbours; a
## PanelContainer is neither, and the game's rows — every card in hand, every
## sitter, every reward — are PanelContainers. Without this they are mouse-only,
## and a keyboard or gamepad player can reach the menus and nothing else.
##
## `style` is mutated in place rather than swapped: a StyleBoxFlat handed to
## add_theme_stylebox_override stays live, so writing a property on it redraws
## the node.
static func make_interactive(wrap: Control, style: StyleBoxFlat, on_pressed: Callable, enabled: bool) -> void:
	if not enabled:
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.focus_mode = Control.FOCUS_NONE
		return

	# Captured before anything changes them, so leaving hover or focus restores
	# whatever the caller set up rather than a hardcoded guess. card_face()
	# gives its border the card's element colour; panel_button() has no border
	# at all until one is focused.
	var base_bg: Color = style.bg_color
	var base_border: Color = style.border_color
	var base_width: int = style.border_width_left

	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wrap.focus_mode = Control.FOCUS_ALL

	wrap.mouse_entered.connect(func(): style.bg_color = base_bg.lightened(0.12))
	wrap.mouse_exited.connect(func(): style.bg_color = base_bg)
	wrap.focus_entered.connect(func():
		style.border_color = FOCUS
		style.set_border_width_all(maxi(base_width, 2))
		Audio.play("ui_move")
	)
	wrap.focus_exited.connect(func():
		style.border_color = base_border
		style.set_border_width_all(base_width)
	)
	wrap.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Clicking moves focus too, so a player who starts with the mouse and
			# switches to the keyboard carries on from where they clicked rather
			# than from wherever focus happened to be left.
			wrap.grab_focus()
			Audio.play("ui_press")
			on_pressed.call()
			wrap.accept_event()
		elif event.is_action_pressed("ui_accept"):
			Audio.play("ui_press")
			on_pressed.call()
			wrap.accept_event()
	)


## Runs `what` in `seconds`, unless whoever owns it has gone by then.
##
## CONNECTED DIRECTLY, with no wrapper lambda. That is the whole point of this
## helper, and the reason it is not obvious:
##
## A guard wrapper — `connect(func(): if what.is_valid(): what.call())` — is the
## defensive shape everyone reaches for and it is exactly wrong. The wrapper
## CAPTURES `what`; Godot nulls a freed capture, prints an error, and calls the
## body anyway, so the guard never runs and the error is moved rather than
## removed. Connected straight to the timer, Godot's signal bookkeeping drops
## the connection when the callable's object is freed and nothing fires at all.
##
## Every deferred beat in the game goes through here: the deal, the knock, the
## ledger's pacing.
static func after(seconds: float, what: Callable) -> void:
	if seconds <= 0.0:
		what.call()
		return
	tree().create_timer(dur(seconds)).timeout.connect(what)


## Puts focus on the first thing inside `root` that can take it, so the first
## Tab or D-pad press does something visible. Deferred by a frame: grab_focus()
## needs the node in the tree with its visibility resolved, which is not yet
## true while a screen's _ready() is running.
##
## `fallback` is where to look when `root` holds nothing focusable — usually the
## whole screen, when `root` is the part a player would normally start on. Not a
## nicety: the reading screen aims focus at the HAND, and every card in a hand
## is disabled once the energy is spent, so without it nothing on the screen
## takes focus and a gamepad player cannot reach READ IT.
static func focus_first(root: Node, fallback: Node = null) -> void:
	# The node's ID, not the node. This is deferred by a frame, and a screen torn
	# down inside that frame — which happens constantly in the scene sweep, and
	# in the game whenever an action rebuilds the screen immediately — would
	# leave the lambda holding a freed capture, which Godot reports as an
	# engine-level ERROR and nulls out BEFORE the body runs, so the going_away()
	# guard inside _focus_first_now() could not prevent it.
	var id := root.get_instance_id()
	var spare := fallback.get_instance_id() if fallback != null else 0
	(func():
		if not is_instance_id_valid(id):
			return
		if _focus_first_now(instance_from_id(id)):
			return
		if spare != 0 and is_instance_id_valid(spare):
			_focus_first_now(instance_from_id(spare))
	).call_deferred()


static func _focus_first_now(node: Node) -> bool:
	if going_away(node):
		return false
	if node is Control:
		var c: Control = node
		# `disabled` matters as much as visibility: grab_focus() on a disabled
		# Button is a no-op that reports nothing, so treating it as focusable
		# ends the search having placed no focus at all. The settings rail
		# disables its selected entry, which is exactly that case.
		var usable: bool = not (c is BaseButton and (c as BaseButton).disabled)
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and usable:
			c.grab_focus()
			return true
	for child in node.get_children():
		if _focus_first_now(child):
			return true
	return false


## True if `node` or ANY ancestor is queued for deletion.
##
## is_queued_for_deletion() only reports on the node it is called ON, and these
## screens rebuild by queue_free()-ing their single root child — so every Button
## in the doomed subtree answers "no", stays in the tree until the end of the
## frame, and is the first thing a focus walk finds. Focus then lands on a node
## that vanishes, and the rebuilt screen has nothing focused.
static func going_away(node: Node) -> bool:
	var n := node
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


## A clickable multi-line row — used for every card/reader/sitter/reward
## option in the game. Deliberately built on PanelContainer + gui_input
## rather than Button: Button is a plain Control, not a Container, so a rich
## multi-Label child added to it isn't auto-sized the way a real Container's
## children are — its minimum size doesn't account for manually-added
## children at all, which (before this was rewritten) left every wrapping
## Label fighting for a ~20px column regardless of size flags. PanelContainer
## is a real Container top-to-bottom, so width flows down and each Label's
## wrapped height correctly flows back up into how tall this row ends up.
## `leading` is an optional Control placed to the left of the text — the sign
## icon on a reader row, the element badge on a sitter. It is a Control rather
## than another line because that is the whole point: these are the drawn icons
## from the design, not more characters.
static func panel_button(lines: Array, on_pressed: Callable, enabled: bool = true,
		tooltip: String = "", leading: Control = null) -> Control:
	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.tooltip_text = tooltip
	# A sheet of paper on the table, not a slab: the same surface every button
	# and card face uses, with a hairline of ink round it and a little shadow
	# under it. See the surfaces section at the top of this file.
	var style := surface(
		warm(PANEL, 0.04) if enabled else Color(PANEL, 0.5),
		Color(INK, 0.10 if enabled else 0.05), 1, 10, 1.0 if enabled else 0.0)
	wrap.add_theme_stylebox_override("panel", style)

	make_interactive(wrap, style, on_pressed, enabled)

	var v := vbox(2)
	for entry in lines:
		var text: String = entry[0]
		# An empty line is a line NOT PRINTED, not a blank one. Callers build
		# these rows by appending whatever a card or a mark happens to have, and
		# a plain card — one with no rule beyond restoring — yields an empty
		# rules string. Printed, that is a visible gap between the price and the
		# flavour that reads as something missing, which is exactly what a player
		# would report it as.
		if text.strip_edges() == "":
			continue
		var size: int = entry[1] if entry.size() > 1 else 14
		var color: Color = entry[2] if entry.size() > 2 else INK
		v.add_child(block(text, size, color))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if leading == null:
		wrap.add_child(v)
		return wrap
	var row := hbox(12)
	# Top-aligned, not centred: the icon belongs beside the row's first line,
	# and a four-line row would otherwise float it halfway down the panel.
	leading.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(leading)
	row.add_child(v)
	wrap.add_child(row)
	return wrap


## The running SceneTree, for starting Tweens from a static helper.
##
## Node.create_tween() cannot be used here: the nodes these helpers build are
## not in the tree yet when they are constructed — the caller parents them a few
## lines later — and create_tween() goes through get_tree(), which is null until
## then. SceneTree.create_tween() only needs the tree to exist, and a Tween's
## writes land on whatever node it holds regardless of when that node was
## attached. Every screen builds and parents its whole subtree inside one
## _ready(), so the animation is correct from the first frame.
static func tree() -> SceneTree:
	return Engine.get_main_loop()


## Every animation helper below calls this immediately after create_tween().
##
## A SceneTree-level tween (see tree()) is NOT tied to any node's lifetime, and
## this UI tears down whole screens on every action — so an unbound tween
## outlives its target and writes to a freed node, which is a hard error rather
## than a silent no-op. bind_node() stops it the moment `target` leaves the tree.
static func bound_tween(target: Node) -> Tween:
	return tree().create_tween().bind_node(target)


## True when the player has turned animation off (Settings' animation_scale
## at 0). Every animate_* helper checks this and jumps straight to the end
## state instead of tweening — so "off" genuinely means no motion, not fast
## motion, which is the point for anyone who set it for motion sensitivity.
static func motion_off() -> bool:
	return Settings.animation_scale() <= 0.01


## A duration scaled by the player's animation-speed setting.
static func dur(seconds: float) -> float:
	return seconds / maxf(Settings.animation_scale(), 0.01)


## The width of the caption column every settings row starts with. Scales with
## text_scale, or a 30% larger caption is clipped by a column sized for 100%.
static func caption_width() -> float:
	return 190.0 * text_scale


## A labelled row: caption on the left at a fixed width, `control` after it.
## The three setting_* helpers below all start this way; having it once means a
## row cannot drift out of alignment with its neighbours.
static func setting_row(caption: String, help: String) -> HBoxContainer:
	var row := hbox(12)
	row.tooltip_text = help
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var cap := label(caption, 13, INK)
	cap.custom_minimum_size.x = caption_width()
	row.add_child(cap)
	return row


## The explanatory text that sits to the right of a settings control.
##
## block(), never label(): a non-wrapping Label reports its full text width as
## its MINIMUM, forcing the enclosing HBoxContainer at least that wide and
## pushing the row past the window — where it is clipped, because the outer
## ScrollContainer has horizontal scrolling off. See block() for the other half
## of this trap.
static func _inline_help(text: String) -> Label:
	var l := block(text, 11, DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A labelled dropdown bound to one string-valued Settings key. `values` are
## what gets stored; `labels` are what the player reads, already translated.
## `enabled` false greys the row out — used for a setting that is real but
## inapplicable right now (window size, in fullscreen), which is honest in a
## way that hiding the row would not be: it stays where the player remembers it.
static func setting_choice(key: String, caption: String, help: String, values: Array,
		labels: Array, enabled: bool = true, on_changed: Callable = Callable()) -> Control:
	var row := setting_row(caption, help)
	var opt := OptionButton.new()
	style_button(opt)
	opt.disabled = not enabled
	var current = Settings.get_value(key)
	var selected := 0
	for i in values.size():
		opt.add_item(str(labels[i]) if i < labels.size() else str(values[i]))
		opt.set_item_metadata(i, values[i])
		if values[i] == current:
			selected = i
	opt.select(selected)
	style_text(opt, 14)
	opt.custom_minimum_size.x = 200
	opt.item_selected.connect(func(idx: int):
		Settings.set_value(key, opt.get_item_metadata(idx))
		if on_changed.is_valid():
			on_changed.call()
	)
	row.add_child(opt)
	row.add_child(_inline_help(help))
	return row


## A labelled slider row bound to one numeric Settings key. `fmt` turns the
## raw value into its readout ("80%", "1.2x", "3"); pass `whole` for keys
## whose value must stay an integer.
static func setting_slider(key: String, caption: String, help: String, fmt: Callable, whole: bool = false) -> Control:
	var def: Array = Settings.DEFS[key]
	var row := setting_row(caption, help)

	var slider := HSlider.new()
	style_slider(slider)
	slider.min_value = float(def[1])
	slider.max_value = float(def[2])
	slider.step = 1.0 if whole else 0.05
	slider.value = float(Settings.get_value(key))
	slider.custom_minimum_size = Vector2(260, 18)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var readout := label(str(fmt.call(Settings.get_value(key))), 13, GOLD)
	readout.custom_minimum_size.x = 70
	row.add_child(readout)

	# Sliders carry their explanation inline like the choice and toggle rows do,
	# rather than only in a tooltip: a pane where two row shapes explain
	# themselves and the third only does so on hover reads as unfinished, and a
	# tooltip is unreachable to a player on a gamepad.
	row.add_child(_inline_help(help))

	slider.value_changed.connect(func(v: float):
		Settings.set_value(key, int(round(v)) if whole else v)
		readout.text = str(fmt.call(Settings.get_value(key)))
	)
	return row


## A labelled on/off row bound to one boolean Settings key. `on_toggled` runs
## after the setting is stored, for keys that need extra work (e.g. reloading
## content when the mod toggle flips).
static func setting_toggle(key: String, caption: String, help: String, on_toggled: Callable = Callable()) -> Control:
	var row := setting_row(caption, help)

	var box := CheckButton.new()
	box.button_pressed = bool(Settings.get_value(key))
	row.add_child(box)

	row.add_child(_inline_help(help))

	box.toggled.connect(func(pressed: bool):
		Settings.set_value(key, pressed)
		if on_toggled.is_valid():
			on_toggled.call(pressed)
	)
	return row


## A plain two-rect meter (no Theme/StyleBox fuss) — used for composure and
## energy on the Reading screen. Animates from `from_ratio` to `to_ratio`
## (pass them equal for no animation); both clamped to [0, 1].
## `projected` and `absorbed` sit AFTER the fill, in that order: what the cards
## on the table would restore if you read them now, and how much of that the
## sitter's denial would eat before it got there.
##
## The three segments are the source prototype's own bar — `hpPct`, `projPct`,
## `absorbPct`, v23 line ~726. Drawing only the first asks the player to lay
## cards toward a number they cannot see coming.
static func bar(from_ratio: float, to_ratio: float, fg: Color, w: float = 260, h: float = 14,
		duration: float = 0.5, projected: float = 0.0, absorbed: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	# A track and a fill, both pills. Two hard-edged rectangles is what a
	# progress bar looks like in a settings dialog; this one sits under a
	# person's name on a table in a room, and a rounded end costs nothing.
	var track := Panel.new()
	var track_box := surface(Color(0, 0, 0, 0.38), Color(INK, 0.10), 1, 0)
	track_box.set_corner_radius_all(int(h * 0.5))
	track.add_theme_stylebox_override("panel", track_box)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(track)
	var fill := Panel.new()
	var fill_box := surface(fg, Color(0, 0, 0, 0), 0, 0)
	fill_box.set_corner_radius_all(int(h * 0.5))
	fill.add_theme_stylebox_override("panel", fill_box)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2.ZERO
	fill.size = Vector2(w * clampf(from_ratio, 0.0, 1.0), h)
	c.add_child(fill)
	var target_w := w * clampf(to_ratio, 0.0, 1.0)

	# The two projection segments, stacked after the fill at its TARGET width —
	# not its current one, since the fill animates and these must not chase it.
	var at := target_w
	for seg: Array in [[projected, GOLD], [absorbed, VIOLET]]:
		var span: float = w * clampf(seg[0], 0.0, 1.0)
		if span < 0.5:
			continue
		var piece := Panel.new()
		var piece_box := surface(Color(seg[1], 0.85), Color(0, 0, 0, 0.5), 1, 0)
		piece_box.set_corner_radius_all(int(h * 0.5))
		piece.add_theme_stylebox_override("panel", piece_box)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.position = Vector2(at, 0)
		piece.size = Vector2(span, h)
		c.add_child(piece)
		if not motion_off():
			piece.modulate.a = 0.0
			bound_tween(piece).tween_property(piece, "modulate:a", 1.0, dur(0.25))
		at += span

	if not is_equal_approx(fill.size.x, target_w):
		if motion_off():
			fill.size.x = target_w
		else:
			bound_tween(fill).tween_property(fill, "size:x", target_w, dur(duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return c


static func stat_row(caption: String, value_text: String, from_ratio: float, to_ratio: float,
		fg: Color, tooltip: String = "", projected: float = 0.0, absorbed: float = 0.0,
		projected_text: String = "") -> Control:
	var row := hbox(10)
	row.tooltip_text = tooltip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label(caption, 12, DIM))
	row.add_child(bar(from_ratio, to_ratio, fg, 260, 14, 0.5, projected, absorbed))
	var value_l := label(value_text, 12, INK)
	row.add_child(value_l)
	# The projection as a number as well as a length. A bar says "about this
	# much"; a player deciding whether one more card is worth the energy wants
	# the figure.
	if projected_text != "":
		row.add_child(label(projected_text, 12, GOLD))
	if not is_equal_approx(from_ratio, to_ratio):
		pulse(value_l, GREEN if to_ratio > from_ratio else RED)
	return row


## A quick colour flash and scale bump on a value the instant it changes, so
## the change reads as an event rather than a different number after a rebuild.
##
## Pivots from the TOP-LEFT, not the centre: this is called before layout has
## run and a fresh Control reports size (0,0) until it has, so a true centre
## pivot is not available. The content is a few characters, so it does not show.
static func pulse(node: Control, flash_color: Color, duration: float = 0.5) -> void:
	if motion_off():
		return  # nothing to restore: the node is already in its end state
	if node is Label:
		var start_color: Color = node.get_theme_color("font_color") if node.has_theme_color("font_color") else INK
		# By ID, not by node. bind_node() stops the tween when the node goes, but
		# not necessarily before a step already queued for this frame runs — and
		# a lambda holding a freed capture is reported by the engine as an ERROR
		# before its body is entered, so a guard inside the body cannot help.
		# This screen rebuilds itself on every single action, so a stat pulsing
		# as the player plays a card is exactly the shape of it.
		var id := node.get_instance_id()
		bound_tween(node).tween_method(func(c: Color):
			if not is_instance_id_valid(id):
				return
			(instance_from_id(id) as Control).add_theme_color_override("font_color", c)
		, flash_color, start_color, dur(duration)).set_trans(Tween.TRANS_CUBIC)
	node.scale = Vector2(1.35, 1.35)
	bound_tween(node).tween_property(node, "scale", Vector2.ONE, dur(duration)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fades and scales a node in, staggered by `delay` so a hand of five reads as
## a deal rather than a simultaneous pop.
##
## MODULATE AND SCALE, never position. Everything this is used on lives inside a
## Container, and a Container re-asserts its children's `position` on every
## layout pass — an animated position fights it and snaps back. modulate and
## scale are not part of Container layout and are safe to drive.
static func animate_in(node: Control, delay: float = 0.0, duration: float = 0.32) -> void:
	if motion_off():
		return  # leave it fully visible at rest scale; no fade-in to play
	node.modulate.a = 0.0
	node.scale = Vector2(0.75, 0.75)
	var t := bound_tween(node)
	t.set_parallel(true)
	t.tween_property(node, "modulate:a", 1.0, dur(duration)).set_delay(dur(delay)).set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "scale", Vector2.ONE, dur(duration)).set_delay(dur(delay)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The person sitting across the table: shoulders out of the bottom of the
## frame, a collar, a neck, a head, hair and a face. It follows the source's
## MOODS state machine (v23 ~1147) in spirit — composure legible on the face
## rather than only in a number.
##
## `art` is an optional delivered portrait (Art.sitter_texture); when present it
## replaces the drawing entirely, keeping only the composure glow behind it.
## Null — the state of every sitter until an artist delivers — falls through to
## the placeholder below.
##
## Everything drawn answers to two things and nothing else:
##
##   COMPOSURE  how far they have been mended, 0 to 1. The brows lift and arch,
##              the eyes open, the mouth goes from a flat line to something
##              close to a smile, the shoulders come down out of their hunch,
##              and their element warms behind them. Someone closing off and
##              someone reached should not need a number to tell apart.
##   WHO THEY ARE  a stable hash of the sitter's key picks the hair, the
##              colouring, the width of the face and the moustache. DERIVED,
##              never random: a face that changes between two screens is not a
##              person.
##
## PLACEHOLDER, on the same terms as scenes/Table.gd — geometry, not
## illustration. See docs/ART_GUIDE.md.
static func sitter_portrait(sitter: Dictionary, hp_ratio: float, art: Texture2D = null) -> Control:
	var el := str(sitter.get("el", ""))
	if art != null:
		return sitter_portrait_art(el, hp_ratio, art)
	var port := Control.new()
	# 3:4, the same shape the delivered portraits are authored at, so swapping
	# one in does not move the layout around it.
	port.custom_minimum_size = Vector2(112, 148)
	var r := clampf(hp_ratio, 0.0, 1.0)
	# name + role, because that is what a sitter is identified BY in the data —
	# there is no key field. An earlier version asked for one, got "" for every
	# sitter, and drew the same person ten times.
	var who := _face_of("%s/%s" % [sitter.get("name", ""), sitter.get("role", "")],
		str(sitter.get("p", "")))
	# The face this portrait actually got, hung on the node. A headless test has
	# no pixels to compare, and a test that derives the key for itself proves
	# only that two copies of one line agree — which is exactly the bug that
	# happened here, asking sitters for a `k` field they do not have. Reading it
	# back off the real portrait is the only version of this check that would
	# have caught that.
	port.set_meta("face", who)
	port.draw.connect(func(): _draw_bust(port, who, el, r))
	port.resized.connect(func(): port.queue_redraw())
	return port


## Skin, hair and clothes to pick from. Small palettes on purpose: a village in
## the rain, not a character creator.
const SKIN_TONES := [
	Color(0.80, 0.66, 0.55), Color(0.68, 0.53, 0.42),
	Color(0.86, 0.73, 0.63), Color(0.55, 0.41, 0.32),
	Color(0.74, 0.60, 0.50),
]
const HAIR_TONES := [
	Color(0.16, 0.12, 0.10), Color(0.30, 0.20, 0.13), Color(0.45, 0.33, 0.20),
	Color(0.62, 0.60, 0.58), Color(0.82, 0.80, 0.77), Color(0.35, 0.14, 0.09),
]
const CLOTH_TONES := [
	Color(0.17, 0.19, 0.24), Color(0.22, 0.18, 0.16), Color(0.15, 0.22, 0.20),
	Color(0.26, 0.22, 0.17), Color(0.19, 0.16, 0.22),
]
## 0 cropped · 1 long · 2 receding · 3 tied up · 4 headscarf
const HAIR_STYLES := 5


## Everything about a face that is not composure, derived from the sitter's key
## so it is the same face every time you meet them.
##
## `pronoun` is the sitter's own `p` field, and the ONLY thing it decides is the
## moustache. Everything else comes from the hash, for everybody — deriving more
## from a pronoun would invent people the writing did not write.
static func _face_of(key: String, pronoun: String = "") -> Dictionary:
	var h := _stable_hash(key)
	return {
		"skin": SKIN_TONES[h % SKIN_TONES.size()],
		"hair": HAIR_TONES[(h / 5) % HAIR_TONES.size()],
		"cloth": CLOTH_TONES[(h / 31) % CLOTH_TONES.size()],
		"style": (h / 173) % HAIR_STYLES,
		# A narrow face and a broad one at the extremes, most in between.
		"width": 0.88 + float((h / 907) % 5) * 0.06,
		"moustache": pronoun == "he" and (h / 3313) % 3 == 0,
		"nose": 0.9 + float((h / 11) % 4) * 0.1,
	}


## Deliberately NOT String.hash(). That is an engine detail with no promise
## attached, and a face that quietly rearranges itself on a Godot upgrade would
## be a very confusing bug to be handed. This is nine lines and it is ours.
static func _stable_hash(text: String) -> int:
	var h := 2166136261
	for i in text.length():
		h = (h ^ text.unicode_at(i)) * 16777619
		h = h & 0x7FFFFFFF
	return h


static func _draw_bust(c: Control, who: Dictionary, el: String, r: float) -> void:
	var w := c.size.x
	var h := c.size.y
	if w < 8.0 or h < 8.0:
		return
	var skin: Color = who["skin"]
	var hair: Color = who["hair"]
	var cloth: Color = who["cloth"]
	var shade := skin.darkened(0.28)
	var line := skin.darkened(0.62)
	var glow := el_color(el)

	# Their element behind them, warming as they are reached. This is the one
	# part of the old drawing worth keeping: it reads across the room.
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_circle(Vector2(w * 0.5, h * 0.42), w * 0.56 * f, Color(glow, 0.020 + r * 0.030))

	# Shoulders. They come DOWN as composure climbs — a person who has been got
	# through to stops holding themselves up.
	var drop := h * 0.02 * r
	var shoulder_y := h * 0.76 + drop
	var shoulders := PackedVector2Array([
		Vector2(w * 0.20, shoulder_y), Vector2(w * 0.80, shoulder_y),
		Vector2(w * 1.02, h * 1.05), Vector2(-w * 0.02, h * 1.05),
	])
	c.draw_colored_polygon(_soft_poly(shoulders, w * 0.16), cloth)

	# Neck, then the collar over the bottom of it.
	c.draw_rect(Rect2(w * 0.41, h * 0.56, w * 0.18, h * 0.24), shade)
	var collar := PackedVector2Array([
		Vector2(w * 0.34, shoulder_y - h * 0.03), Vector2(w * 0.5, shoulder_y + h * 0.06),
		Vector2(w * 0.66, shoulder_y - h * 0.03), Vector2(w * 0.66, shoulder_y + h * 0.02),
		Vector2(w * 0.5, shoulder_y + h * 0.11), Vector2(w * 0.34, shoulder_y + h * 0.02),
	])
	c.draw_colored_polygon(collar, cloth.lightened(0.10))

	# The head.
	var cx := w * 0.5
	var cy := h * 0.37
	var rx: float = w * 0.27 * float(who["width"])
	var ry := h * 0.25
	_ellipse(c, Vector2(cx, cy + h * 0.012), rx * 1.03, ry * 1.03, line)
	_ellipse(c, Vector2(cx, cy), rx, ry, skin)
	# Ears, and the jaw shadow under the chin.
	for side: float in [-1.0, 1.0]:
		_ellipse(c, Vector2(cx + side * rx * 0.98, cy + ry * 0.12), rx * 0.13, ry * 0.16, shade)
	_ellipse(c, Vector2(cx, cy + ry * 0.86), rx * 0.55, ry * 0.10, Color(line, 0.18))

	_draw_hair(c, who, Vector2(cx, cy), rx, ry, hair)
	_draw_face(c, who, Vector2(cx, cy), rx, ry, r, line, shade, hair)


## Where the hair stops, per style, as multiples of (rx, ry) from the centre of
## the head — left temple, over the brow, and back down to the right. This is
## the whole difference between the styles that have a crown: a RECEDING
## hairline is a hairline further back, not a different kind of object.
const HAIRLINES := {
	0: [Vector2(0.86, -0.30), Vector2(0.44, -0.56), Vector2(0.0, -0.46), Vector2(-0.44, -0.56), Vector2(-0.86, -0.30)],
	1: [Vector2(0.86, -0.30), Vector2(0.44, -0.56), Vector2(0.0, -0.46), Vector2(-0.44, -0.56), Vector2(-0.86, -0.30)],
	2: [Vector2(0.98, -0.12), Vector2(0.42, -0.76), Vector2(0.0, -0.64), Vector2(-0.42, -0.76), Vector2(-0.98, -0.12)],
	3: [Vector2(0.84, -0.34), Vector2(0.42, -0.60), Vector2(0.0, -0.52), Vector2(-0.42, -0.60), Vector2(-0.84, -0.34)],
}


static func _draw_hair(c: Control, who: Dictionary, at: Vector2, rx: float, ry: float, hair: Color) -> void:
	var style: int = who["style"]
	if style == 4:
		# A headscarf: over the crown and down past the jaw, tied at the side.
		var scarf := PackedVector2Array([
			at + Vector2(-rx * 1.10, ry * 0.10), at + Vector2(-rx * 0.95, -ry * 0.80),
			at + Vector2(0, -ry * 1.14), at + Vector2(rx * 0.95, -ry * 0.80),
			at + Vector2(rx * 1.10, ry * 0.10), at + Vector2(rx * 0.86, ry * 0.92),
			at + Vector2(0, ry * 1.02), at + Vector2(-rx * 0.86, ry * 0.92),
		])
		c.draw_colored_polygon(_soft_poly(scarf, rx * 0.35), hair.lightened(0.18))
		_ellipse(c, at + Vector2(-rx * 1.02, ry * 0.30), rx * 0.22, ry * 0.16, hair.lightened(0.28))
		return

	# The crown, sitting a little proud of the skull, closed off by a HAIRLINE
	# rather than by a straight cut across the middle of the face. The first
	# version closed at head-centre height and read as a knitted hat pulled down
	# over the eyebrows; the second gave the receding style two side blobs that
	# read as earmuffs.
	var cap := PackedVector2Array()
	var steps := 18
	var span: float = 0.30 if style != 2 else 0.12
	for i in steps + 1:
		var a := (PI - span) + float(i) / float(steps) * (PI + span * 2.0)
		cap.append(at + Vector2(cos(a) * rx * 1.05, sin(a) * ry * 1.06))
	for point: Vector2 in HAIRLINES[style]:
		cap.append(at + Vector2(point.x * rx, point.y * ry))
	c.draw_colored_polygon(cap, hair)

	if style == 1:
		# Long: down both sides to below the jaw.
		for side: float in [-1.0, 1.0]:
			var fall := PackedVector2Array([
				at + Vector2(side * rx * 1.02, -ry * 0.55),
				at + Vector2(side * rx * 1.16, ry * 0.30),
				at + Vector2(side * rx * 1.02, ry * 1.30),
				at + Vector2(side * rx * 0.66, ry * 1.24),
				at + Vector2(side * rx * 0.80, ry * 0.10),
			])
			c.draw_colored_polygon(_soft_poly(fall, rx * 0.20), hair)
	elif style == 3:
		# Tied up, which from the front is a shape behind the head.
		_ellipse(c, at + Vector2(0, -ry * 1.16), rx * 0.34, ry * 0.28, hair.darkened(0.10))


static func _draw_face(c: Control, who: Dictionary, at: Vector2, rx: float, ry: float,
		r: float, line: Color, shade: Color, hair: Color) -> void:
	var eye_x := rx * 0.42
	var eye_y := at.y + ry * 0.06        # eyes sit ON the midline of a head
	var eye_rx := rx * 0.21
	var eye_ry := ry * 0.135

	# Brows: low and flat when they are closed off, lifted and arched when they
	# have been reached.
	var lift := ry * (0.30 + 0.12 * r)
	var arch := 0.06 + 0.26 * r
	for side: float in [-1.0, 1.0]:
		var bx := at.x + side * eye_x
		var by := eye_y - lift
		c.draw_line(Vector2(bx - rx * 0.24, by + side * arch * rx * 0.30),
			Vector2(bx + rx * 0.24, by - side * arch * rx * 0.30),
			Color(hair.darkened(0.15), 0.9), maxf(1.5, rx * 0.075), true)

	# Eyes. The eye is always the same SIZE; what changes is how much of it the
	# lid covers — which is how an eye actually works, and the only version of
	# this that reads. Scaling the whole eye down instead gave a one-pixel white
	# bar at low composure that looked like a pair of spectacles.
	var open := lerpf(0.30, 1.0, r)
	for side: float in [-1.0, 1.0]:
		var ex := at.x + side * eye_x
		var eye := Vector2(ex, eye_y)
		_ellipse(c, eye, eye_rx, eye_ry, Color(0.90, 0.88, 0.85))
		_ellipse(c, eye + Vector2(side * eye_rx * 0.10, 0), eye_rx * 0.46, eye_ry * 0.86,
			Color(0.17, 0.13, 0.11))
		if r > 0.4:
			c.draw_circle(eye + Vector2(-eye_rx * 0.22, -eye_ry * 0.30),
				maxf(0.8, eye_rx * 0.20), Color(1, 1, 1, (r - 0.4) * 1.1))
		# The lid, in skin, coming down over the top of it — the SAME ellipse
		# shifted up, so its lower edge is curved like an eyelid instead of the
		# straight cut a rectangle leaves across the eye.
		var cover := eye_ry * 2.0 * (1.0 - open)
		if cover > 0.4:
			_ellipse(c, Vector2(ex, eye_y - eye_ry * 2.0 + cover), eye_rx * 1.04, eye_ry * 1.04, shade)
		c.draw_line(Vector2(ex - eye_rx, eye_y - eye_ry * 1.02 + cover),
			Vector2(ex + eye_rx, eye_y - eye_ry * 1.02 + cover),
			Color(line, 0.75), maxf(1.0, rx * 0.055), true)

	# Nose: two short strokes, because a drawn nose at this size is a smudge.
	var nose_top := eye_y + ry * 0.14
	var nose_len: float = ry * 0.20 * float(who["nose"])
	c.draw_line(Vector2(at.x - rx * 0.05, nose_top), Vector2(at.x - rx * 0.11, nose_top + nose_len),
		Color(line, 0.38), maxf(1.0, rx * 0.05), true)
	c.draw_line(Vector2(at.x - rx * 0.11, nose_top + nose_len), Vector2(at.x + rx * 0.05, nose_top + nose_len),
		Color(line, 0.38), maxf(1.0, rx * 0.05), true)

	# Mouth: a flat line closed off, a small smile reached. Drawn as a curve
	# rather than an arc so the ends can stay put while the middle moves.
	var mouth_y := at.y + ry * 0.62
	var half := rx * lerpf(0.24, 0.36, r)
	var curve := ry * lerpf(-0.02, 0.17, r)
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(Vector2(at.x - half + t * half * 2.0, mouth_y - sin(t * PI) * curve))
	c.draw_polyline(pts, Color(line, 0.85), maxf(1.6, rx * 0.065), true)

	if who["moustache"]:
		var my := mouth_y - ry * 0.14
		var m := PackedVector2Array([
			Vector2(at.x - rx * 0.32, my - ry * 0.02),
			Vector2(at.x, my - ry * 0.09),
			Vector2(at.x + rx * 0.32, my - ry * 0.02),
			Vector2(at.x + rx * 0.20, my + ry * 0.07),
			Vector2(at.x, my + ry * 0.02),
			Vector2(at.x - rx * 0.20, my + ry * 0.07),
		])
		c.draw_colored_polygon(_soft_poly(m, rx * 0.07), Color(hair, 0.92))


## A filled ellipse. draw_circle only does circles, and nothing about a head is.
static func _ellipse(c: Control, at: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 30
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, col)


## A polygon with its corners rounded off — shoulders, a fall of hair, a
## moustache. Same construction as Table.gd's _soften(); kept here rather than
## reached for across files because UIKit is loaded from places Table is not.
static func _soft_poly(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	var n := points.size()
	if n < 3 or radius <= 0.0:
		return points
	var out := PackedVector2Array()
	for i in n:
		var prev := points[(i - 1 + n) % n]
		var cur := points[i]
		var next := points[(i + 1) % n]
		var a := cur + (prev - cur).normalized() * minf(radius, (prev - cur).length() * 0.45)
		var b := cur + (next - cur).normalized() * minf(radius, (next - cur).length() * 0.45)
		for j in 5:
			var t := float(j) / 4.0
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	return out


## Delivered-portrait variant of sitter_portrait(). Keeps the composure-driven
## element glow (so the "they're softening" read survives) but lets the
## artwork carry the face. Portraits are authored 3:4 (see docs/ART_GUIDE.md);
## this crops to the square header slot, biased to the top where the face is.
static func sitter_portrait_art(el: String, hp_ratio: float, art: Texture2D) -> Control:
	var port := Control.new()
	port.custom_minimum_size = Vector2(96, 96)
	var flush := clampf(hp_ratio, 0.0, 1.0)
	var glow := el_color(el)

	var glow_layer := Control.new()
	glow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_layer.draw.connect(func():
		if flush > 0.05:
			glow_layer.draw_circle(Vector2(48, 48), 46, Color(glow, 0.10 + flush * 0.18))
	)
	port.add_child(glow_layer)

	var tex := TextureRect.new()
	tex.texture = art
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port.add_child(tex)
	return port


## A tinted rounded-square badge holding one of the prototype's vector icons —
## its elIcon()/archIcon(), proportions and all: the icon at 68% of the box, a
## corner radius of 30%, the ground at 24% of the icon's colour and a hairline
## border at 52%.
##
## Returns null when there is no such icon, so a caller can fall back to the
## text glyph rather than leaving a hole. Never assume one exists: a mod can
## add elements without adding art for them.
static func icon_badge(kind: String, name: String, size: int, color: Color) -> Control:
	var px := int(round(size * Icons.ICON_FRACTION))
	var tex := Icons.texture(kind, name, px * 2, color)   # 2x, for a crisp downscale
	if tex == null:
		return null

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(size, size)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, Icons.BADGE_FILL_ALPHA)
	style.border_color = Color(color, Icons.BADGE_BORDER_ALPHA)
	style.set_border_width_all(1)
	var r := int(round(size * Icons.RADIUS_FRACTION))
	for corner in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		style.set(corner, r)
	style.set_content_margin_all(int(round((size - px) * 0.5)))
	box.add_theme_stylebox_override("panel", style)

	var img := TextureRect.new()
	img.texture = tex
	img.custom_minimum_size = Vector2(px, px)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(img)
	return box


## The badge for a card's archetype, in the archetype's own colour. Null when
## the card has none — twenty-two of the base cards are plain.
static func archetype_badge(key: String, size: int = 16) -> Control:
	if key == "":
		return null
	var rec: Dictionary = Content.archetypes.get(key, {})
	if rec.is_empty():
		return null
	return icon_badge("archetype", key, size, Color(str(rec.get("color", "#eae4d7"))))


## What an archetype means, for a card's tooltip — the source's own one-line
## description of each family.
static func archetype_text(key: String) -> String:
	var rec: Dictionary = Content.archetypes.get(key, {})
	if rec.is_empty():
		return ""
	return "%s — %s" % [key.to_upper(), I18n.content("archetype/" + key, "text", str(rec.get("text", "")))]


## The badge for an element, in the element's own colour.
static func el_badge(el: String, size: int = 18) -> Control:
	if el == null or str(el) == "":
		return null
	return icon_badge("element", str(el), size, el_color(str(el)))


## An element badge followed by its name, as a row — the Control counterpart of
## el_tag(), which stays for the places that genuinely need a String (tooltips,
## and text built by Run.gd). Falls back to el_tag() when there is no icon.
static func el_row(el: String, size: int = 16, color: Color = INK) -> Control:
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var badge := el_badge(el, size)
	if badge != null:
		row.add_child(badge)
		row.add_child(label(I18n.element_field(str(el), "label"), size - 3, color))
	else:
		row.add_child(label(el_tag(str(el)), size - 3, color))
	return row


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
	return "%s %s" % [el_glyph(el), I18n.element_field(el, "label")]


## The card's name, with its element glyph in front. Still used where a card
## has to be a STRING — deck lists, rewards, the Library — but NOT on the card
## face any more: that carries the drawn badge instead (see card_face()).
static func card_summary(c: Dictionary) -> String:
	var bits: Array = []
	var el = c.get("el")
	if el != null and el != "":
		bits.append(el_glyph(el))
	bits.append(I18n.card_name(c))
	return " ".join(bits)


## Resolves the display-string convention Run.gd emits (see its header):
## a String is a translation key; an Array is [format_key, arg, ...] whose
## key is translated first and then "%"-formatted. Anything else stringifies.
## Empty/null yields "" so callers can pass optional fields straight through.
static func tr_line(value) -> String:
	if value == null:
		return ""
	if value is Array:
		if value.is_empty():
			return ""
		var fmt: String = I18n.t(str(value[0]))
		var args: Array = value.slice(1)
		if args.is_empty():
			return fmt
		return fmt % (args[0] if args.size() == 1 else args)
	return I18n.t(str(value))


## What a card costs to say and what it restores before any rule applies — the
## two numbers printed on its face, as a sentence.
##
## One function because it is said in two places that must not drift: the hand
## card's tooltip and the reward row. It also guarantees a card ALWAYS has
## something to say, which card_face() relies on — see its tooltip.
static func card_price(c: Dictionary) -> String:
	return I18n.t("%s energy · restores %s") % [c.get("cost", 0), c.get("f", 0)]


static func card_text(c: Dictionary) -> String:
	if c.get("custom", false):
		return c.get("text", "")
	return Rules.auto_text(c)


const CARD_FACE_SIZE := Vector2(122, 158)


## How much bigger a card is at the current interface size. Less than the text
## scale itself (four fifths of it): the words inside a card have to grow with
## the setting, but a card that grew at the full rate would leave no table.
##
## A function rather than a number repeated in two files, because everything
## measured against a card — the band it sits in, the hands that hold it — has
## to move with it or the fingers grip thin air. That was the bug: the band was
## a fixed 176 and a card at the top of the range is 196.
static func card_scale() -> float:
	return lerpf(1.0, text_scale, 0.8)


## The card face at the current text scale. A fixed 122x158 with 30% larger
## type in it clips the name, so the card grows with the words — checked
## visually at both ends of the range, which is the only way this kind of thing
## is ever actually checked.
static func card_face_size() -> Vector2:
	return CARD_FACE_SIZE * card_scale()


## A fixed-size card face for the hand fan: cost top-left, base restore
## top-right, name centred, element-coloured border. Everything else — the
## mechanic text, the flavour, the keyword glossary — moves into the hover
## tooltip, which is the source's own rule for a card at this size. The roomier
## panel_button rows the reward and shop screens use are the other choice, and
## right for a decision made once.
##
## `enabled` and `interactive` are DIFFERENT. `enabled` false is a card you
## cannot afford: greyed, and saying so. `interactive` false is a card being
## shown as an illustration — full strength, but taking neither the pointer nor
## the focus. Without the second, ten deck cards are ten focus stops that do
## nothing when pressed, standing between the player and CLOSE.
static func card_face(c: Dictionary, on_pressed: Callable, enabled: bool = true,
		interactive: bool = true) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = card_face_size()
	var el = c.get("el")
	var el_c: Color = el_color(el) if el != null and el != "" else DIM
	# ALWAYS STARTS WITH THE PRICE, so a card can never have an empty tooltip.
	# A plain card — no extra rule, no archetype, no flavour, no keyword — has
	# nothing else to say, and an empty tooltip means the reading screen's hand
	# label stays blank when that card is focused. That label is the only channel
	# a keyboard player has for reading a card at all.
	var tip_lines: Array = [card_price(c)]
	if card_text(c) != "":
		tip_lines.append(card_text(c))
	var arch_tip := archetype_text(str(c.get("a", "")))
	if arch_tip != "":
		tip_lines.append(arch_tip)
	if I18n.card_flavor(c) != "":
		tip_lines.append(I18n.card_flavor(c))
	var kw := card_keyword_tooltip(c)
	if kw != "":
		tip_lines.append(kw)
	wrap.tooltip_text = "\n\n".join(tip_lines)

	# The element's colour is the border; everything else is the house surface.
	var style := surface(
		warm(PANEL, 0.05) if enabled else Color(PANEL, 0.5),
		el_c if enabled else Color(el_c, 0.35), 2, 8, 1.0 if enabled else 0.0)
	wrap.add_theme_stylebox_override("panel", style)

	if interactive:
		make_interactive(wrap, style, on_pressed, enabled)
	else:
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.focus_mode = Control.FOCUS_NONE

	var v := vbox(4)
	var top := hbox(0)
	var cost_l := label(str(c.get("cost", 0)), 13, GOLD if enabled else DIM)
	var restore_l := label("+%s" % c.get("f", 0), 13, GREEN if enabled else DIM)
	restore_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cost_l)
	# The element badge sits between cost and restore, which is the only spare
	# room on a card this size. The border already carries the element's colour;
	# the badge is what tells a player WHICH element without reading the name.
	var face_badge := el_badge(el, int(round(17 * text_scale))) if el != null and str(el) != "" else null
	if face_badge != null:
		if not enabled:
			face_badge.modulate = Color(1, 1, 1, 0.45)
		# Expand-and-centre, so the badge sits in the middle of the top row
		# rather than crowding the cost: the restore label takes the leftover
		# otherwise and pushes it left.
		face_badge.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
		top.add_child(face_badge)
	top.add_child(restore_l)
	v.add_child(top)

	# The middle band is the art slot. With art delivered the name sits over
	# it on a scrim (so it stays legible against any illustration); with none,
	# the name simply centres in the empty band exactly as before.
	var art := Art.card_texture(c)
	var name_l := block(I18n.card_name(c), 12, INK if enabled else DIM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if art == null:
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(name_l)
	else:
		var band := Control.new()
		band.size_flags_vertical = Control.SIZE_EXPAND_FILL
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := TextureRect.new()
		tex.texture = art
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not enabled:
			tex.modulate = Color(1, 1, 1, 0.45)
		band.add_child(tex)
		var scrim := ColorRect.new()
		scrim.color = Color(0.05, 0.045, 0.055, 0.55)
		scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		scrim.anchor_top = 0.62
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(scrim)
		name_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		name_l.anchor_top = 0.62
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(name_l)
		v.add_child(band)

	var tags: Array = []
	if c.get("exhaust", false):
		tags.append(I18n.t("ONCE"))
	if c.get("pierce", false):
		tags.append(I18n.t("PIERCE"))

	# The card's ARCHETYPE — the source's five families of card (digging,
	# switch, pinpoint, channel, timing), each with its own drawn icon and its
	# own colour. Thirty-four of the fifty-six base cards carry one and the port
	# had never shown it at all; a player could not see that two cards were the
	# same kind of move without reading both.
	var foot := hbox(6)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	var arch_badge := archetype_badge(str(c.get("a", "")), 16)
	if arch_badge != null:
		if not enabled:
			arch_badge.modulate = Color(1, 1, 1, 0.45)
		foot.add_child(arch_badge)
	if tags.size() > 0:
		foot.add_child(label(" · ".join(tags), 9, DIM))
	if foot.get_child_count() > 0:
		v.add_child(foot)

	wrap.add_child(v)
	return wrap
