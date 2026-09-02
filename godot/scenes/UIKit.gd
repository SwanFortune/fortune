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


static func root_control() -> Control:
	refresh_look()
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
## panel_button() and card_face() each had their own verbatim copy of this
## block, and both copies handled only InputEventMouseButton — so every card in
## hand, every sitter on the map and every reward was mouse-only. Buttons made
## with button() were always keyboard-reachable (Godot's Button is focusable and
## works out its own focus neighbours from the layout); these rows, being
## PanelContainers, were not focusable at all, which left keyboard and gamepad
## players able to reach the menus and nothing else.
##
## `style` is mutated in place rather than swapped, because that is how the
## hover highlight already worked — a StyleBoxFlat handed to
## add_theme_stylebox_override stays live, so changing a property on it
## redraws the node.
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


## Puts keyboard focus on the first thing in `root` that can take it, so the
## first Tab or D-pad press does something visible instead of nothing. Deferred
## because grab_focus() needs the node to be in the tree with its visibility
## resolved, which is not yet true while a screen's _ready() is still running.
## Returns nothing; screens call it and forget.
static func focus_first(root: Node) -> void:
	(func(): _focus_first_now(root)).call_deferred()


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
## is_queued_for_deletion() only reports on the node it is called on, and every
## screen here rebuilds by calling queue_free() on its single root child — so
## the doomed subtree's Buttons each answered "no", stayed in the tree until
## the end of the frame, and were the first thing the focus walk found. Focus
## was placed on a node that then vanished, leaving the rebuilt screen with
## nothing focused and a keyboard player stuck.
##
## It only showed up on a REBUILD, which most screens never do — the settings
## screen's category rail rebuilds on every click, which is how it surfaced.
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

	make_interactive(wrap, style, on_pressed, enabled)

	var v := vbox(2)
	for entry in lines:
		var text: String = entry[0]
		var size: int = entry[1] if entry.size() > 1 else 14
		var color: Color = entry[2] if entry.size() > 2 else INK
		v.add_child(block(text, size, color))
	wrap.add_child(v)
	return wrap


## The running SceneTree, for kicking off Tweens from a static RefCounted
## helper. Node.create_tween() would be the normal way to do this, but the
## nodes these helpers build aren't attached to anything yet at the point
## they're constructed (their caller only parents them a few lines later) —
## calling create_tween() on a not-yet-attached node fails since it goes
## through get_tree() internally, which is null until the node is in the
## live tree. SceneTree.create_tween() has no such requirement: it just needs
## the tree to exist, not the animated node specifically, and a Tween's
## property writes land on whatever node reference it holds regardless of
## that node's own tree membership at the moment the tween was created — by
## the time the next frame actually renders, the whole subtree these helpers
## return is attached (every UI screen builds and parents its entire tree
## synchronously within one _ready() call), so the animation is visible from
## frame one with no dropped or out-of-order property writes.
static func tree() -> SceneTree:
	return Engine.get_main_loop()


## Every animation helper below calls this immediately after create_tween().
## A SceneTree-level tween (see tree() above) is NOT tied to any node's
## lifetime by default, so if the screen it's animating gets torn down before
## the tween finishes — this UI rebuilds the whole scene on every action, so
## that's routine, not an edge case — the tween keeps running and then writes
## to a freed node on its next step, which is a hard error, not a silent
## no-op. bind_node() makes the tween stop itself the moment `target` leaves
## the tree, which is exactly the lifetime this needs to track.
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
## block(), not label(): a non-wrapping Label reports its full text width as
## its MINIMUM, so an HBoxContainer holding one is forced at least that wide —
## which pushed the row past the window and clipped the sentence, since the
## enclosing ScrollContainer has horizontal scrolling off. A wrapping Label
## with EXPAND_FILL takes whatever is left after the caption and the control
## and wraps inside it. See block()'s own doc comment for the other half of
## this trap.
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
static func bar(from_ratio: float, to_ratio: float, fg: Color, w: float = 260, h: float = 14, duration: float = 0.5) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fg
	fill.position = Vector2.ZERO
	fill.size = Vector2(w * clampf(from_ratio, 0.0, 1.0), h)
	c.add_child(fill)
	var target_w := w * clampf(to_ratio, 0.0, 1.0)
	if not is_equal_approx(fill.size.x, target_w):
		if motion_off():
			fill.size.x = target_w
		else:
			bound_tween(fill).tween_property(fill, "size:x", target_w, dur(duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return c


static func stat_row(caption: String, value_text: String, from_ratio: float, to_ratio: float, fg: Color, tooltip: String = "") -> Control:
	var row := hbox(10)
	row.tooltip_text = tooltip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label(caption, 12, DIM))
	row.add_child(bar(from_ratio, to_ratio, fg))
	var value_l := label(value_text, 12, INK)
	row.add_child(value_l)
	if not is_equal_approx(from_ratio, to_ratio):
		pulse(value_l, GREEN if to_ratio > from_ratio else RED)
	return row


## A quick color flash + scale bump — used on a value label the instant it
## changes (composure/energy ticking, faith/coin gained) so the change reads
## as an event, not just a number that's suddenly different after a screen
## rebuild. Pivots from the node's top-left rather than its center — its
## real size isn't known yet at the point this is called (layout hasn't run;
## a fresh Control reports size (0,0) until it's actually been through a
## layout pass), so a true center-pivot isn't available cheaply here. Small
## enough content (a stat value, a few characters) that it isn't noticeable.
static func pulse(node: Control, flash_color: Color, duration: float = 0.5) -> void:
	if motion_off():
		return  # nothing to restore: the node is already in its end state
	if node is Label:
		var start_color: Color = node.get_theme_color("font_color") if node.has_theme_color("font_color") else INK
		bound_tween(node).tween_method(func(c: Color): node.add_theme_color_override("font_color", c), flash_color, start_color, dur(duration)).set_trans(Tween.TRANS_CUBIC)
	node.scale = Vector2(1.35, 1.35)
	bound_tween(node).tween_property(node, "scale", Vector2.ONE, dur(duration)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fades + scales a node in — used for newly-drawn hand cards and the
## most-recently-laid card, staggered by `delay` so a hand of 5 reads as a
## deal rather than a simultaneous pop. Animates modulate/scale rather than
## position deliberately: every place this is used lives inside a real
## Container (HFlowContainer for the hand, HBoxContainer for the laid line),
## and a Container re-asserts its children's `position` on every layout
## pass — animating position there would just fight the container and
## visibly snap back or jitter. modulate and scale aren't part of Container
## layout, so they're safe to drive with a tween no matter what the parent
## does on its next sort.
static func animate_in(node: Control, delay: float = 0.0, duration: float = 0.32) -> void:
	if motion_off():
		return  # leave it fully visible at rest scale; no fade-in to play
	node.modulate.a = 0.0
	node.scale = Vector2(0.75, 0.75)
	var t := bound_tween(node)
	t.set_parallel(true)
	t.tween_property(node, "modulate:a", 1.0, dur(duration)).set_delay(dur(delay)).set_trans(Tween.TRANS_QUAD)
	t.tween_property(node, "scale", Vector2.ONE, dur(duration)).set_delay(dur(delay)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A small procedural face reacting to how close the sitter is to mended
## (hp_ratio), loosely following the source's MOODS state machine (~line
## 1147: waiting/listening/reached/struck, driven by eye height, brow angle,
## mouth shape, and a warm "flush" glow) — not the source's hand-drawn
## portrait, which this pass doesn't attempt, but the same idea: composure
## climbing is legible on the sitter's face, not just in a number.
## `art` is an optional delivered portrait (Art.sitter_texture(...)); when
## present it replaces the procedural face entirely, keeping only the
## composure glow behind it. Null (the default, and the state of every sitter
## until the artist delivers) falls through to the drawn placeholder.
static func sitter_portrait(el: String, hp_ratio: float, art: Texture2D = null) -> Control:
	if art != null:
		return sitter_portrait_art(el, hp_ratio, art)
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


static func card_text(c: Dictionary) -> String:
	if c.get("custom", false):
		return c.get("text", "")
	return Rules.auto_text(c)


const CARD_FACE_SIZE := Vector2(122, 158)


## The card face at the current text scale. A fixed 122x158 with 30% larger
## type in it clips the name, so the card grows with the words — checked
## visually at both ends of the range, which is the only way this kind of thing
## is ever actually checked.
static func card_face_size() -> Vector2:
	return CARD_FACE_SIZE * lerpf(1.0, text_scale, 0.8)

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
	wrap.custom_minimum_size = card_face_size()
	var el = c.get("el")
	var el_c: Color = el_color(el) if el != null and el != "" else DIM
	var tip_lines: Array = [card_text(c)]
	if I18n.card_flavor(c) != "":
		tip_lines.append(I18n.card_flavor(c))
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

	make_interactive(wrap, style, on_pressed, enabled)

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

	# The middle band is the art slot. With art delivered the name sits over
	# it on a scrim (so it stays legible against any illustration); with none,
	# the name simply centres in the empty band exactly as before.
	var art := Art.card_texture(c)
	var name_l := block(card_summary(c), 12, INK if enabled else DIM)
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
	if tags.size() > 0:
		var tag_l := label(" · ".join(tags), 9, DIM)
		tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag_l)

	wrap.add_child(v)
	return wrap
