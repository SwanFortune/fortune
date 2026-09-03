## The core loop: lay cards from hand into the spoken line (cross), then READ
## IT to resolve via Rules.simulate(). Refreshes by reloading this same scene
## after every action (lay/read) — there's no reactive UI framework here, and
## re-running _ready() against the latest Run.state is simple and correct for
## a screen this size. See docs/PORTING_NOTES.md re: the letter-by-letter
## "mumble" animation this intentionally skips.
##
## Animation note: since the whole screen rebuilds from scratch each action,
## "what changed" comes from the _prevHp/_prevEnergy/_justDrawn/_justDiscarded
## snapshot fields Run.gd leaves on the fight dict for exactly this purpose
## (see Run.gd's begin_turn() doc comment) rather than from diffing against a
## previous frame of this scene, which doesn't exist by the time this runs.
extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const RunHeader := preload("res://scenes/RunHeader.gd")
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## The card band, and the whole held area beneath it. The hands start where the
## cards stop and rise back over them by the difference.
const CARD_BAND := 176
const HELD_HEIGHT := 250
## How far the hands reach back UP over the cards. Without an overlap the fan
## floats above a drawing of some fingers instead of being held by them.
##
## Table.gd draws its fingertips at the very top of the band it is given, so
## this number alone decides how far up the cards they reach: at 42 they cross
## the bottom quarter of a card face. Enough to read as held; not so much that
## a card is covered.
const HAND_OVERLAP := 42

## The last card in hand floats instead of being held. LIFT is how far above
## where it would sit; BOB is how far it drifts up and down; OPEN_REACH is what
## the hands do underneath it — Table.hands() shortens and curls the fingers,
## which turns two hands closing on a card into two hands that have let go of
## one. Together they leave a clear gap between the fingertips and the card,
## which is the whole point: you can see daylight under it.
const LIFT := 14
const BOB := 5.0
const OPEN_REACH := 0.66


func _ready() -> void:
	var f: Dictionary = Run.state["f"]
	var root := UIKit.root_control()
	add_child(root)
	# The table and its cloth, behind everything. See scenes/Table.gd.
	root.add_child(Table.background())
	var m := UIKit.margin(28)
	root.add_child(m)
	var v := UIKit.vbox(10)
	m.add_child(v)

	v.add_child(RunHeader.build(self))

	var s: Dictionary = f["sitter"]
	var q: Dictionary = f["quirk"]
	var hp_ratio := float(f["hp"]) / float(f["max"]) if int(f["max"]) > 0 else 0.0
	var prev_hp_ratio := float(f.get("_prevHp", f["hp"])) / float(f["max"]) if int(f["max"]) > 0 else 0.0
	var energy_ratio := float(f["energy"]) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0
	var prev_energy_ratio := float(f.get("_prevEnergy", f["energy"])) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0

	var header := UIKit.hbox(14)
	header.add_child(UIKit.sitter_portrait(s["el"], hp_ratio, Art.sitter_texture(s)))
	var header_text := UIKit.vbox(4)
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The element as its drawn badge rather than a character. The sitter's
	# element decides what every card in hand is worth against them, so it is
	# worth a glance rather than a squint.
	var who := UIKit.hbox(10)
	who.add_child(UIKit.label("%s · %s" % [I18n.sitter_field(s, "name"), I18n.sitter_field(s, "role")], 18, UIKit.INK))
	var el_badge := UIKit.el_badge(str(s["el"]), 24)
	if el_badge != null:
		who.add_child(el_badge)
	who.add_child(UIKit.label(I18n.element_field(str(s["el"]), "label"), 14, UIKit.el_color(s["el"])))
	header_text.add_child(who)
	header_text.add_child(UIKit.block("%s %s — %s: %s" % [I18n.t("sign"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn"), I18n.sign_rule(q, s)], 12, UIKit.DIM))
	header.add_child(header_text)
	v.add_child(header)
	v.add_child(UIKit.stat_row(I18n.t("Composure"), "%s / %s" % [f["hp"], f["max"]], prev_hp_ratio, hp_ratio, UIKit.GREEN, I18n.t(UIKit.KEYS["composure"])))
	v.add_child(UIKit.stat_row(I18n.t("Energy"), "%s / %s" % [f["energy"], f["energyMax"]], prev_energy_ratio, energy_ratio, UIKit.GOLD, I18n.t(UIKit.KEYS["energy"])))
	var denial_row := UIKit.block("%s %s / %s   ·   %s %s" % [I18n.t("Reading"), f["turn"], f["turns"], I18n.t("Denial wall"), f["denial"]], 12, UIKit.DIM)
	denial_row.tooltip_text = I18n.t(UIKit.KEYS["denial"])
	denial_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(denial_row)

	if f.get("taken", null) != null:
		v.add_child(UIKit.block("(%s slips out of your hand before you can start.)" % f["taken"], 11, UIKit.RED))

	var discarded: Array = f.get("_justDiscarded", [])
	if not discarded.is_empty():
		Audio.play("card_discard")
		var disc_label := UIKit.block("%s %s" % [I18n.t("Discarded:"), ", ".join(discarded)], 11, UIKit.DIM)
		v.add_child(disc_label)
		if not UIKit.motion_off():
			var fade := UIKit.bound_tween(disc_label)
			fade.tween_interval(UIKit.dur(0.9))
			fade.tween_property(disc_label, "modulate:a", 0.0, UIKit.dur(1.2)).set_trans(Tween.TRANS_QUAD)

	v.add_child(UIKit.block(I18n.t("SAID SO FAR"), 12, UIKit.DIM))
	var cross_box := UIKit.hbox(6)
	v.add_child(cross_box)
	if f["cross"].is_empty():
		cross_box.add_child(UIKit.label(I18n.t("(nothing yet)"), 12, UIKit.DIM))
	else:
		var preview: Dictionary = Rules.simulate(Run.run_ctx(), f)
		for i in f["cross"].size():
			var c: Dictionary = f["cross"][i]
			var row: Dictionary = preview["rows"][i] if i < preview["rows"].size() else {}
			var chip := UIKit.label("%s (+%s)" % [UIKit.card_summary(c), row.get("total", "?")], 12, UIKit.GREEN)
			cross_box.add_child(chip)
			if i == f["cross"].size() - 1:
				# Only the just-laid card is new; the rest were already on
				# screen before this rebuild (or, for the very first card of
				# a reading, "new" and "only" are the same card either way).
				UIKit.animate_in(chip)

	# Greyed while a play is still available and nothing is laid — the source
	# does this (`cannotRead`) and the port had inherited only the silent
	# early-return, so the button looked live and did nothing.
	var read_btn := UIKit.button(I18n.t("READ IT"), _read_it)
	read_btn.disabled = not Run.can_read()
	v.add_child(read_btn)

	var hand_label := UIKit.label(I18n.t("YOUR HAND — hover a card for its full text"), 12, UIKit.DIM)
	v.add_child(hand_label)
	# The fan sits on top of the reader's own hands: the cards are HELD, and
	# every mark won this run is drawn on the fingers holding them. A Control
	# stacking the two, so the hands are behind and the cards in front.
	var held := Control.new()
	held.custom_minimum_size = Vector2(0, HELD_HEIGHT)
	held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Exactly its own height, not the leftover: the hands are positioned
	# relative to this box, and a box that grows with the window would walk
	# them away from the cards they are supposed to be holding.
	held.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.add_child(held)

	var just_drawn: Array = f.get("_justDrawn", [])
	# THE LAST CARD IS NOT HELD IN A FAN. One card between two hands is not a
	# fan at all, and clamping it between the fingertips the way five cards are
	# clamped looked like a mistake — the hands closed on each other around a
	# single sliver. It floats instead: lifted clear of two open hands, in its
	# own light, breathing. See _lift().
	var alone: bool = f["hand"].size() == 1
	var focus_on: Node = self
	var span: Callable
	var hand_reach := 1.0

	if alone:
		var only: Dictionary = f["hand"][0]
		var face := _lift(held, only, int(only.get("cost", 0)) <= int(f["energy"]))
		if just_drawn.has(only["uid"]):
			UIKit.animate_in(face)
			_deal_sound(0.0)
		span = _card_span.bind(face, held)
		hand_reach = OPEN_REACH
		focus_on = face
	else:
		var scroll := UIKit.scroll()
		scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
		scroll.offset_bottom = CARD_BAND
		held.add_child(scroll)
		var fan := HFlowContainer.new()
		fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Centred, so the hands that hold it are symmetric about the middle of
		# the table rather than both crowding whichever side the cards happened
		# to stack up on.
		fan.alignment = FlowContainer.ALIGNMENT_CENTER
		fan.add_theme_constant_override("h_separation", 8)
		fan.add_theme_constant_override("v_separation", 8)
		scroll.add_child(fan)
		var deal_index := 0
		for c in f["hand"]:
			var afford := int(c.get("cost", 0)) <= int(f["energy"])
			var face := UIKit.card_face(c, _lay.bind(c["uid"]), afford)
			fan.add_child(face)
			if just_drawn.has(c["uid"]):
				UIKit.animate_in(face, deal_index * 0.06)
				_deal_sound(deal_index * 0.06)
				deal_index += 1
		span = _fan_span.bind(fan, held)
		if fan.get_child_count() > 0:
			focus_on = fan

	# The hands are rooted below the cards and reach UP over them, so the fan
	# reads as held rather than as floating above a drawing of some fingers.
	# Added AFTER the cards on purpose: the fingertips have to be in FRONT of
	# their lower edge. Behind them, they are a picture of hands near a fan.
	var hands := Table.hands(Run.state.get("marks", []), span, hand_reach)
	hands.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hands.offset_top = CARD_BAND - HAND_OVERLAP
	hands.offset_bottom = HELD_HEIGHT
	held.add_child(hands)
	# The cards are laid out by a container, so their width settles a frame
	# after they are built and again whenever the window changes. Without this
	# the hands are drawn once against whatever was measured first — which, on
	# the frame the screen is built, is nothing at all.
	held.resized.connect(func(): hands.queue_redraw())
	for child in held.get_children():
		if child is Container:
			(child as Container).sort_children.connect(func(): hands.queue_redraw())

	# The hand, not the run header above it. See Map.gd. Falls back to the whole
	# screen when the hand is empty, so READ IT is still reachable.
	UIKit.focus_first(focus_on)


## One card, alone, floating between two open hands instead of clamped in them.
##
## It is a plain Control rather than the usual ScrollContainer + flow: a single
## card never needs scrolling, and a ScrollContainer CLIPS, which would cut the
## halo off at the band's edge and cut the card in half as it bobs above it.
## Outside a container the card also owns its own `position`, so it can be
## tweened without a layout pass snapping it back — which is exactly why the
## fan's cards are animated with modulate and scale and never with position.
##
## Returns the card face, so the caller can focus it and measure it.
func _lift(held: Control, card: Dictionary, afford: bool) -> Control:
	var band := Control.new()
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = CARD_BAND
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held.add_child(band)

	var face := UIKit.card_face(card, _lay.bind(card["uid"]), afford)
	var face_size := UIKit.card_face_size()

	# The light it hangs in, and the shadow it casts on the cloth below. Both
	# stay put while the card bobs: they are the lamp and the table, and neither
	# of those moves. A halo that rose and fell with the card would read as a
	# sticker attached to it.
	var glow := Control.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(func(): _draw_lift(glow, face_size))
	glow.resized.connect(func(): glow.queue_redraw())
	band.add_child(glow)
	band.add_child(face)

	face.position.y = roundf((CARD_BAND - face_size.y) * 0.5) - LIFT
	var settle := func() -> void:
		if face.size != face_size:
			face.size = face_size
		face.position.x = roundf((band.size.x - face_size.x) * 0.5)
	band.resized.connect(settle)
	# Outside a container a card does NOT simply keep the size it is given.
	# Control.size is clamped up to the combined minimum, and the card's name is
	# an auto-wrapping Label whose minimum HEIGHT depends on the width it has
	# been given — which, before the first layout pass, is zero. So it reports
	# the height of a one-word-per-line column and the card comes out nearly
	# twice as tall as every other card in the game. Re-applying the intended
	# size whenever the minimum changes is what actually pins it; the y is left
	# alone because the bob tween owns it.
	face.minimum_size_changed.connect(settle)
	settle.call()
	settle.call_deferred()

	# And it breathes. Position is safe to drive here for the reason in the
	# docstring; UIKit.dur() folds in the animation-speed setting, and motion_off
	# leaves it hanging perfectly still rather than removing the lift.
	if not UIKit.motion_off():
		var rest := face.position.y
		var t := UIKit.bound_tween(face)
		t.set_loops()
		t.tween_property(face, "position:y", rest - BOB, UIKit.dur(2.1)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(face, "position:y", rest + BOB, UIKit.dur(2.1)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return face


## The pool of light behind a lifted card, and its shadow on the cloth.
func _draw_lift(c: Control, face_size: Vector2) -> void:
	if c.size.x < 4.0:
		return
	var mid := Vector2(c.size.x * 0.5, roundf((CARD_BAND - face_size.y) * 0.5) - LIFT + face_size.y * 0.5)
	for i in range(10, 0, -1):
		var f := float(i) / 10.0
		c.draw_circle(mid, face_size.x * 1.15 * f, Color(UIKit.GOLD, 0.016))
	# The shadow sits where the card WOULD be if it were lying on the cloth,
	# which is what says it is not.
	var floor_y := mid.y + LIFT + face_size.y * 0.42
	for i in range(5, 0, -1):
		var f := float(i) / 5.0
		_shadow(c, Vector2(mid.x, floor_y), face_size.x * 0.46 * f, face_size.y * 0.09 * f)


static func _shadow(c: Control, at: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := float(i) / 24.0 * TAU
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, Color(0, 0, 0, 0.055))


## Where the fan actually starts and stops, in the coordinates of the hands
## drawn under it. `origin` is the box both of them are anchored across, which
## is how a position measured on the cards becomes one the hands can use.
##
## Returns a zero span when there is nothing laid out yet — no cards, or a fan
## the container has not measured — and Table.hands() falls back to fixed
## fractions of the screen rather than drawing two hands on top of each other.
func _fan_span(fan: Control, origin: Control) -> Vector2:
	return _span_of(fan.get_children(), origin)


## The same, for the single lifted card, which has no container around it to
## enumerate. Passing its `band` instead would measure the full-width glow
## behind it and set the hands at the edges of the screen.
func _card_span(face: Control, origin: Control) -> Vector2:
	return _span_of([face], origin)


func _span_of(cards: Array, origin: Control) -> Vector2:
	if cards.is_empty() or not is_instance_valid(origin):
		return Vector2.ZERO
	var left := INF
	var right := -INF
	for child in cards:
		if child is Control:
			var r: Control = child
			left = minf(left, r.global_position.x)
			right = maxf(right, r.global_position.x + r.size.x)
	if left > right:
		return Vector2.ZERO
	var at := origin.global_position.x
	return Vector2(left - at, right - at)


## One click per card dealt, staggered to match the deal animation. Uses the
## same delay the tween does, so a hand riffles rather than arriving as one
## thud — and goes silent with the animations when motion is turned off.
func _deal_sound(delay: float) -> void:
	if UIKit.motion_off() or delay <= 0.0:
		Audio.play("card_draw")
		return
	var timer := get_tree().create_timer(UIKit.dur(delay))
	timer.timeout.connect(func(): Audio.play("card_draw"))


func _lay(card_uid: String) -> void:
	Audio.play("card_lay")
	Run.lay_card(card_uid)
	Nav.goto_for_state()


func _read_it() -> void:
	Audio.play("reading_resolve")
	Run.read_it()
	Nav.goto_for_state()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("parlour_read"):
		_read_it()
		get_viewport().set_input_as_handled()
		return
	if RunHeader.handle_shortcut(event, self):
		get_viewport().set_input_as_handled()
