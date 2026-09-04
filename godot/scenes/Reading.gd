## Lay cards from hand into the spoken line (cross), then READ IT to resolve via
## Rules.simulate().
##
## THE WHOLE SCREEN IS REBUILT after every action, so there is no previous frame
## to diff against. "What changed" comes from the _prevHp/_prevEnergy/_justDrawn/
## _justDiscarded snapshots Run.gd leaves on the fight dict for this purpose —
## see Run.begin_turn().
extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const RunHeader := preload("res://scenes/RunHeader.gd")
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## The card band, and the whole held area beneath it. The hands start where the
## cards stop and rise back over them by the difference.
##
## At 100% only. USE _band_px()/_held_px() for anything measured against a card:
## a card grows with the interface-size setting and these do not, so a fixed 176
## leaves a 196-pixel card overflowing its own band with the fingers gripping
## empty table above it.
const CARD_BAND := 176
const HELD_HEIGHT := 250

## How far the hands reach back UP over the cards. Table.gd draws its fingertips
## at the very top of the band it is given, so this number alone decides how far
## up the cards they reach: at 42 they cross the bottom quarter of a card face.
## Without an overlap the fan floats above a drawing of fingers rather than being
## held by them.
const HAND_OVERLAP := 42

## The last card in hand floats instead of being held. LIFT is how far above
## where it would sit, BOB how far it drifts, OPEN_REACH how far the fingers
## reach under it — together they leave visible daylight between the fingertips
## and the card, which is what makes it read as floating rather than gripped.
const LIFT := 14
const BOB := 5.0
const OPEN_REACH := 0.66


static func _band_px() -> float:
	return CARD_BAND * UIKit.card_scale()


static func _held_px() -> float:
	return HELD_HEIGHT * UIKit.card_scale()


func _ready() -> void:
	var f: Dictionary = Run.state["f"]
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(28)
	# No bottom margin: the hand sits on the screen's edge with the fingers
	# holding it running off it. A gap under them makes the table a panel.
	m.add_theme_constant_override("margin_bottom", 0)
	root.add_child(m)

	# THE THINGS YOU ACT ON ARE FIXED; THE THINGS YOU READ SCROLL. The header, the
	# READ IT row, the hand's line and the hand keep their places; the middle
	# takes what room is left. As one column instead, prose above the hand — a
	# long sign rule, a wrapped hint — pushes it off the bottom of the window,
	# and at the largest interface size it goes off entirely.
	var page := UIKit.vbox(10)
	m.add_child(page)

	page.add_child(RunHeader.build(self))

	var column := UIKit.scroll()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(column)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(v)

	# What the cards already on the table would do, worked out once and read by
	# both the bars and the pace line under them.
	var sim: Dictionary = Rules.simulate(Run.run_ctx(), f) if not f["cross"].is_empty() else {}

	v.add_child(_the_sitter(f))
	v.add_child(_the_state(f, sim))
	_the_notices(f, v)
	_said_so_far(f, sim, v)

	page.add_child(_the_say())
	var hand_label := _the_hand_label()
	page.add_child(hand_label)
	var held := _the_hand_box()
	page.add_child(held)
	var focus_on := _fill_the_hand(f, hand_label, held)

	# The hand, falling back to the whole screen. The fallback is load-bearing:
	# once the energy is spent every card is disabled and a full fan holds no
	# focusable control, so without it nothing on the screen takes focus and a
	# player without a mouse cannot reach READ IT to end the turn.
	UIKit.focus_first(focus_on, self)


## WHO IS SITTING THERE: their portrait, their name and job, their element, and
## the rule their sign imposes on this reading.
func _the_sitter(f: Dictionary) -> Control:
	var s: Dictionary = f["sitter"]
	var q: Dictionary = f["quirk"]
	var hp_ratio := float(f["hp"]) / float(f["max"]) if int(f["max"]) > 0 else 0.0

	var header := UIKit.hbox(14)
	header.add_child(UIKit.sitter_portrait(s, hp_ratio, Art.sitter_texture(s)))
	var header_text := UIKit.vbox(4)
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var who := UIKit.hbox(10)
	who.add_child(UIKit.label("%s · %s" % [I18n.sitter_field(s, "name"), I18n.sitter_field(s, "role")], 18, UIKit.INK))
	var el_badge := UIKit.el_badge(str(s["el"]), 24)
	if el_badge != null:
		who.add_child(el_badge)
	who.add_child(UIKit.label(I18n.element_field(str(s["el"]), "label"), 14, UIKit.el_color(s["el"])))
	header_text.add_child(who)
	header_text.add_child(_what_they_are(f))
	header.add_child(header_text)
	return header


## THE TWO THINGS PLAYING AGAINST YOU, side by side: their JOB and their SIGN.
##
## Both are written flavour-first — "She works while she talks. You draw one
## more card every reading." — and only the second half is a rule. The source
## splits them and shows the MECHANIC on the board with the flavour on a hover
## (v23 ~730); this does the same. See I18n.split_rule().
##
## The job was missing from this screen entirely. It is a rule that changes how
## the reading is played — an extra card every turn, an energy less, a card
## taken before you start — and it was visible only on the map, one screen back,
## as one line with its flavour run into it.
func _what_they_are(f: Dictionary) -> Control:
	var s: Dictionary = f["sitter"]
	var q: Dictionary = f["quirk"]
	var row := UIKit.hbox(14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var job: Dictionary = Content.get_job(str(s.get("role", "")))
	var job_text := I18n.fill(I18n.job_text(str(s.get("role", "")), job), str(s.get("p", "they")))
	if job_text != "":
		var split: Array = I18n.split_rule(job_text)
		row.add_child(_side(
			"%s · %s" % [I18n.t("THE JOB"), I18n.sitter_field(s, "role")],
			str(split[0]), str(split[1]), UIKit.GOLD))

	# The wall beside the sign's name, because it is the sign's doing and the
	# number a player is deciding against.
	var wall := ""
	if int(f.get("denial", 0)) > 0:
		wall = I18n.t("HOLDS OFF %d") % int(f["denial"])
	var sign_split: Array = I18n.split_rule(I18n.sign_rule(q, s))
	row.add_child(_side(
		"%s %s — %s  %s" % [I18n.t("sign"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn"), wall],
		str(sign_split[0]), str(sign_split[1]), UIKit.VIOLET))
	return row


## One of those two: a caption, the rule under it in `tint`, a coloured rule
## down the left, and the flavour on the hover.
func _side(caption: String, rule: String, flavour: String, tint: Color) -> Control:
	var box := UIKit.vbox(3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.tooltip_text = flavour
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	# The left rule is drawn rather than being a StyleBox, so the column keeps
	# its own height without a panel around it.
	box.draw.connect(func():
		box.draw_rect(Rect2(0, 0, 2, box.size.y), Color(tint, 0.55))
	)
	box.resized.connect(func(): box.queue_redraw())
	var pad := UIKit.margin(0)
	pad.add_theme_constant_override("margin_left", 9)
	box.add_child(pad)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)
	col.add_child(UIKit.block(caption, 10, UIKit.DIM))
	col.add_child(UIKit.block(rule, 11, tint))
	return box


## WHERE THE READING STANDS: the two bars, the piles, and whether you are on
## course. Kept together because they are one reading of one number — the pace
## line is worked out from the same projection the composure bar draws.
func _the_state(f: Dictionary, sim: Dictionary) -> Control:
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hp_ratio := float(f["hp"]) / float(f["max"]) if int(f["max"]) > 0 else 0.0
	var prev_hp_ratio := float(f.get("_prevHp", f["hp"])) / float(f["max"]) if int(f["max"]) > 0 else 0.0
	var energy_ratio := float(f["energy"]) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0
	var prev_energy_ratio := float(f.get("_prevEnergy", f["energy"])) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0

	# What the cards already laid would do, drawn onto the composure bar before
	# the player commits: gold for what reaches them, violet for what the denial
	# eats first. The source's three-segment bar (v23 ~726); see UIKit.bar().
	var room := maxf(0.0, float(f["max"]) - maxf(0.0, float(f["hp"])))
	var will_land: float = minf(float(sim.get("applied", 0)), room)
	var will_stop: float = minf(float(sim.get("absorbed", 0)), maxf(0.0, room - will_land))
	var whole: float = maxf(1.0, float(f["max"]))
	v.add_child(UIKit.stat_row(
		I18n.t("Composure"), "%s / %s" % [f["hp"], f["max"]], prev_hp_ratio, hp_ratio,
		UIKit.GREEN, I18n.t(UIKit.KEYS["composure"]),
		will_land / whole, will_stop / whole,
		("+%d" % int(will_land)) if will_land >= 1.0 else ""))
	v.add_child(UIKit.stat_row(I18n.t("Energy"), "%s / %s" % [f["energy"], f["energyMax"]], prev_energy_ratio, energy_ratio, UIKit.GOLD, I18n.t(UIKit.KEYS["energy"])))
	var denial_row := UIKit.block("%s %s / %s   ·   %s %s   ·   %s %d   ·   %s %d" % [
		I18n.t("Reading"), f["turn"], f["turns"], I18n.t("Denial wall"), f["denial"],
		I18n.t("Left to draw"), f["draw"].size(), I18n.t("Set aside"), f["disc"].size(),
	], 12, UIKit.DIM)
	denial_row.tooltip_text = I18n.t(UIKit.KEYS["denial"])
	denial_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(denial_row)

	# THE PACE: how far short you still are, spread over the readings left. A
	# reading is six or seven turns against a fixed number, and without this the
	# only way to learn you were behind was to run out.
	var still := maxi(0, int(f["max"]) - maxi(0, int(f["hp"])) - int(will_land))
	var readings_left := maxi(0, int(f["turns"]) - int(f["turn"]) + (0 if will_land > 0.0 else 1))
	if still > 0:
		var per := int(ceil(float(still) / float(maxi(1, readings_left))))
		var pace := UIKit.block(I18n.t("Still to reach: %d, with %d reading(s) after this one — about %d each")
			% [still, readings_left, per], 11,
			UIKit.RED if readings_left <= 0 else UIKit.DIM)
		v.add_child(pace)
	elif int(f["hp"]) < int(f["max"]):
		v.add_child(UIKit.block(I18n.t("This reading is enough."), 11, UIKit.GREEN))
	return v


## What happened to the hand before the player could start: a card the sitter's
## sign took, and whatever the last reading discarded.
##
## Added into `v` rather than returned: on an ordinary turn there is nothing to
## say, and an empty container would still take a gap in the column.
func _the_notices(f: Dictionary, v: Control) -> void:
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


## The line as it stands: every card already laid, each with what it is worth in
## this reading rather than what is printed on it.
func _said_so_far(f: Dictionary, sim: Dictionary, v: Control) -> void:
	# THE SENTENCE, and the arithmetic under it. What the reader has actually
	# said to the person across the table is what this game is about; the
	# per-card totals are only how it scored. Shown even with nothing laid,
	# where it says what the sitter is doing while they wait — which is why
	# there is no "SAID SO FAR" caption over it any more. The line says what it
	# is by being a sentence, and the caption cost a row the scores needed.
	v.add_child(UIKit.block(UIKit.spoken_line(f["cross"], f["sitter"]), 14, UIKit.INK))
	if f["cross"].is_empty():
		return
	var cross_box := UIKit.hbox(6)
	v.add_child(cross_box)
	for i in f["cross"].size():
		var c: Dictionary = f["cross"][i]
		var row: Dictionary = sim["rows"][i] if i < sim.get("rows", []).size() else {}
		var chip := UIKit.label("%s (+%s)" % [UIKit.card_summary(c), row.get("total", "?")], 12, UIKit.GREEN)
		cross_box.add_child(chip)
		if i == f["cross"].size() - 1:
			# Only the just-laid card is new — the rest were already on screen
			# before this rebuild.
			UIKit.animate_in(chip)


## READ IT, and TAKE IT BACK beside it when there is something to take back.
##
## READ IT is greyed while a play is still available and nothing is laid, which
## is the source's `cannotRead`. Without the greying the button looks live and
## silently does nothing.
func _the_say() -> Control:
	var say := UIKit.hbox(10)
	var read_btn := UIKit.button(I18n.t("READ IT"), _read_it)
	read_btn.disabled = not Run.can_read()
	read_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	say.add_child(read_btn)
	# Offered only while a card can be taken back. The reading itself, once read
	# out, cannot be.
	if Run.can_unlay():
		var undo := UIKit.button(I18n.t("TAKE IT BACK"), _unlay)
		undo.size_flags_horizontal = Control.SIZE_SHRINK_END
		say.add_child(undo)
	return say


## The line that prints whatever card is under the pointer OR has focus.
##
## FOCUS AS WELL AS HOVER, always. A card's full text lives in Godot's hover
## tooltip, and a keyboard or gamepad cannot hover — so on hover alone a
## controller player can reach every card, play them, and never read what any
## of them does.
func _the_hand_label() -> Control:
	var hand_label := UIKit.block(I18n.t("YOUR HAND — the card you are on says what it does here"), 12, UIKit.DIM)
	# Two lines' worth, held open, so the layout does not jump every time the
	# pointer crosses a card.
	hand_label.custom_minimum_size.y = 34 * UIKit.text_scale
	return hand_label


## The box the hand lives in: a plain Control stacking the drawn hands behind the
## cards they hold. Filled by _fill_the_hand().
func _the_hand_box() -> Control:
	var held := Control.new()
	# Reserves the CARD BAND, not the whole held area. The hands are drawn down
	# to HELD_HEIGHT and are meant to run off the bottom of the screen; that part
	# overflows this box on purpose, and nothing here clips.
	held.custom_minimum_size = Vector2(0, _band_px())
	held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Exactly its own height, never the leftover: the hands are drawn relative to
	# this box, so a box that grew with the window would walk them away from the
	# cards they are holding.
	held.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return held


## Puts the cards into `held`, draws the hands that hold them, and returns the
## node focus should be aimed at.
func _fill_the_hand(f: Dictionary, hand_label: Control, held: Control) -> Node:
	var just_drawn: Array = f.get("_justDrawn", [])
	# THE LAST CARD IS NOT HELD IN A FAN — one card clamped between fingertips
	# reads as the hands closing on nothing. It floats instead; see _lift().
	var alone: bool = f["hand"].size() == 1
	var focus_on: Node = self
	var span: Callable
	var hand_reach := 1.0

	if alone:
		var only: Dictionary = f["hand"][0]
		var face := _lift(held, only, int(only.get("cost", 0)) <= int(f["energy"]))
		_inspect(face, hand_label)
		if just_drawn.has(only["uid"]):
			UIKit.animate_in(face)
			_deal_sound(0.0)
		span = _card_span.bind(face, held)
		hand_reach = OPEN_REACH
		focus_on = face
	else:
		var scroll := UIKit.scroll()
		scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
		# ROOM FOR THE CARD TO COME UP IN. The fan lives in a ScrollContainer, and
		# a ScrollContainer CLIPS. The card under the pointer grows about a pivot
		# on its bottom edge, so it grows upward, out of the clip rect — cutting
		# off the cost and the restore, the only reason to point at it.
		# _fit_headroom() opens the room; see it for why the fan is not simply
		# moved down instead.
		scroll.offset_bottom = _band_px()
		held.add_child(scroll)
		var headroom := MarginContainer.new()
		headroom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(headroom)
		var fan := HFlowContainer.new()
		fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Centred, so the hands drawn to hold the fan stay symmetric about the
		# middle of the table.
		fan.alignment = FlowContainer.ALIGNMENT_CENTER
		fan.add_theme_constant_override("h_separation", FAN_GAP)
		fan.add_theme_constant_override("v_separation", 8)
		headroom.add_child(fan)
		var deal_index := 0
		for c in f["hand"]:
			var afford := int(c.get("cost", 0)) <= int(f["energy"])
			var face := UIKit.card_face(c, _lay.bind(c["uid"]), afford)
			_inspect(face, hand_label)
			fan.add_child(face)
			if just_drawn.has(c["uid"]):
				UIKit.animate_in(face, deal_index * 0.06)
				_deal_sound(deal_index * 0.06)
				deal_index += 1
		span = _fan_span.bind(fan, held)
		if fan.get_child_count() > 0:
			focus_on = fan
		# CONNECTED TO THE CARDS, not only to the fan. Opening the headroom moves
		# the fan without changing its size, so `fan.resized` never fires a second
		# time — and the first pass runs before the cards have been laid out at
		# all, so its answer would stand forever.
		var fit := func() -> void:
			_fit_fan(fan)
			_fit_headroom(fan, headroom, scroll)
		for child in fan.get_children():
			if child is Control:
				(child as Control).resized.connect(fit)
		fan.resized.connect(fit)
		fit.call()

	# Added AFTER the cards, and the order matters: the fingertips have to draw
	# in FRONT of the cards' lower edge, or they are a picture of hands near a
	# fan rather than hands holding one.
	var hands := Table.hands(Run.state.get("marks", []), span, hand_reach)
	hands.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hands.offset_top = _band_px() - HAND_OVERLAP * UIKit.card_scale()
	hands.offset_bottom = _held_px()
	held.add_child(hands)
	# The cards are laid out by a container, so their width settles a frame after
	# they are built and again on every window change. Without these redraws the
	# hands are drawn once, against a width that is zero on the first frame.
	held.resized.connect(func(): hands.queue_redraw())
	for child in held.get_children():
		if child is Container:
			(child as Container).sort_children.connect(func(): hands.queue_redraw())

	return focus_on


## Wires a card face to the hand label, so hovering or focusing it prints what
## the card does, and raises the card while it is the one being read.
##
## The text is the card's OWN TOOLTIP, flattened — never a second string built
## here. Two descriptions of one card drift apart, and the one nobody is looking
## at drifts first.
func _inspect(face: Control, into: Label) -> void:
	var idle := into.text
	var full := face.tooltip_text.replace("\n\n", "   ·   ").replace("\n", " ")
	if full.strip_edges() == "":
		return
	# SCALE, never position: an HFlowContainer re-asserts its children's positions
	# on every layout pass and leaves scale alone (see UIKit.animate_in). The
	# pivot sits on the card's bottom edge, so growing reads as lifting.
	#
	# The is_instance_valid guards below are not optional. The label and the card
	# are freed together when the screen rebuilds, and whichever goes first
	# leaves the other's handler holding a dead reference — which Godot nulls and
	# then calls the body with anyway.
	face.pivot_offset = Vector2(UIKit.card_face_size().x * 0.5, UIKit.card_face_size().y)
	for signal_name: String in ["mouse_entered", "focus_entered"]:
		face.connect(signal_name, func():
			if not is_instance_valid(into):
				return
			into.text = full
			into.add_theme_color_override("font_color", UIKit.INK)
			_raise(face, CARD_LIFT)
		)
	for signal_name: String in ["mouse_exited", "focus_exited"]:
		face.connect(signal_name, func():
			# Only if this card is still the one being shown: leaving card A
			# fires AFTER entering card B when the pointer slides between them,
			# so clearing unconditionally blanks the text just asked for.
			if is_instance_valid(into) and into.text == full:
				into.text = idle
				into.add_theme_color_override("font_color", UIKit.DIM)
			_raise(face, 1.0)
		)


## The gap between two cards in a hand that fits, and the least of a card that
## may still show in one that does not. Past half a card there is nothing left
## to read but a sliver of the name, so below that the hand wraps after all.
const FAN_GAP := 8
const CARD_MIN_SHOWS := 0.5


## Makes the hand fit on one row by OVERLAPPING the cards, via negative
## separation. Later children draw over earlier ones, so the cards tuck under
## each other left to right; the one under the pointer comes to the front by
## itself because _raise() gives it a z_index.
##
## Necessary because an HFlowContainer WRAPS, and the fan sits in a box one card
## tall — so a wrapped second row is clipped out of sight, present in the layout
## and invisible to the player. Eight cards at the largest interface size is
## enough to trigger it, and eight is a hand the settings can deal.
##
## The cost: an overlapped card loses its top-RIGHT corner, the restore value.
## Stacking the other way would lose the top-left corner, the cost — and a cost
## you cannot see is a card you cannot tell whether you can play.
func _fit_fan(fan: Control) -> void:
	if not is_instance_valid(fan):
		return
	var n := fan.get_child_count()
	if n < 2 or fan.size.x <= 0.0:
		return
	var card_w := UIKit.card_face_size().x
	var gap := float(FAN_GAP)
	var need := n * card_w + (n - 1) * gap
	if need > fan.size.x:
		gap = (fan.size.x - n * card_w) / float(n - 1)
		gap = maxf(gap, -card_w * (1.0 - CARD_MIN_SHOWS))
	var want := int(floor(gap))
	if fan.get_theme_constant("h_separation") != want:
		fan.add_theme_constant_override("h_separation", want)


## Opens room above the fan for the raised card to grow into, and lifts the clip
## rect by the same amount so the cards themselves do not move.
##
## Runs on every relayout of the fan, so it must not CAUSE one: writing a theme
## constant or an anchor offset marks the control dirty even when the value is
## unchanged, and `fan.resized` then fires again next pass. Hence the comparison
## before each write.
func _fit_headroom(fan: Control, headroom: MarginContainer, scroll: Control) -> void:
	if not is_instance_valid(fan) or not is_instance_valid(headroom) or not is_instance_valid(scroll):
		return
	var tallest := 0.0
	for child in fan.get_children():
		if child is Control:
			# Whichever is known. On the frame the screen is built a card has no
			# size yet but does have a minimum; once laid out it has both, and a
			# card given more room than its minimum is the one that matters.
			var c: Control = child
			tallest = maxf(tallest, maxf(c.size.y, c.get_combined_minimum_size().y))
	if tallest <= 0.0:
		return
	var head := int(ceil(tallest * (CARD_LIFT - 1.0)))
	if headroom.get_theme_constant("margin_top") != head:
		headroom.add_theme_constant_override("margin_top", head)
	if int(scroll.offset_top) != -head:
		scroll.offset_top = -head


## How far the card under the pointer comes off the table.
const CARD_LIFT := 1.14

## Scales `face` to `to`, and puts it in front of its neighbours while it is up.
func _raise(face: Control, to: float) -> void:
	if not is_instance_valid(face):
		return
	# In front only while raised: left at a high z_index a card would keep
	# covering the one beside it after the pointer had gone.
	face.z_index = 1 if to > 1.0 else 0
	if UIKit.motion_off():
		face.scale = Vector2(to, to)
		return
	UIKit.bound_tween(face).tween_property(face, "scale", Vector2(to, to), UIKit.dur(0.10)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	band.offset_bottom = _band_px()
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

	face.position.y = roundf((_band_px() - face_size.y) * 0.5) - LIFT
	var settle := func() -> void:
		# Guarded because this is also called DEFERRED, a frame later, and a
		# screen torn down inside that frame leaves the lambda holding freed
		# captures — which Godot reports as an ERROR before the body runs, so
		# checking inside the body is not enough on its own. See the id dance in
		# UIKit.focus_first() for the same problem solved the same way.
		if not (is_instance_valid(face) and is_instance_valid(band)):
			return
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
	var mid := Vector2(c.size.x * 0.5, roundf((_band_px() - face_size.y) * 0.5) - LIFT + face_size.y * 0.5)
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
	UIKit.after(delay, func(): Audio.play("card_draw"))


func _lay(card_uid: String) -> void:
	Audio.play("card_lay")
	Run.lay_card(card_uid)
	Nav.goto_for_state()


## READ IT resolved the whole reading in one frame and left for the next
## screen. That is where the game's mechanic actually pays off — a line of cards
## chained by their elements, a wall that eats the front of it, and whatever is
## left landing on the person opposite — and all of it happened between two
## frames. Nobody could see the rule they had just used, which is the reason it
## is the hardest thing in the game to learn.
##
## It is read out now, in the order the rule works: card by card with each link
## named, then the wall taking its share, then what actually reaches them.
const REVEAL_LINE := 0.24        ## per card
const REVEAL_WALL := 0.38        ## the wall taking its share
const REVEAL_LAND := 0.55        ## what reaches them
const REVEAL_HOLD := 0.45        ## before the screen changes
const REVEAL_WIDTH := 560.0

## Set for the length of the reveal, so a second READ IT (or the shortcut, or a
## click) skips to the end rather than resolving the reading twice.
var _revealing := false


func _unlay() -> void:
	Run.unlay()
	Nav.goto_for_state()


func _read_it() -> void:
	if _revealing:
		_finish_read()
		return
	if UIKit.motion_off():
		_finish_read()
		return
	_revealing = true
	_reveal()


func _finish_read() -> void:
	_revealing = false
	Audio.play("reading_resolve")
	Run.read_it()
	Nav.goto_for_state()


## The scrim, the panel and the column the ledger is written into. Separated
## from the writing of it because it is a different job: this is a modal over a
## busy screen — a portrait, two bars, a fan of cards, a room — and a ledger
## written straight onto that was unreadable however dark the scrim got.
##
## Returns the column to add lines to; the overlay is already in the tree.
func _reveal_stage() -> Control:
	var over := Control.new()
	over.name = "Reveal"
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Eats clicks, so the cards underneath cannot be played mid-reading.
	over.mouse_filter = Control.MOUSE_FILTER_STOP
	over.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_finish_read()
	)
	add_child(over)
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(scrim)

	var m := UIKit.margin(48)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(m)
	var centre := UIKit.vbox(0)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(centre)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = REVEAL_WIDTH * UIKit.text_scale
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIKit.PANEL, 0.97)
	box.border_color = Color(UIKit.GOLD, 0.30)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	var v := UIKit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	return v


## The reading, read out. A ledger that writes itself: one line per card with
## the link named, then the wall, then what lands.
##
## Built over the whole screen rather than woven into it, for the same reason
## the deck overlay is: this screen rebuilds itself from scratch on every
## action, so anything that has to survive a couple of seconds is safer as one
## node that owns its own lifetime.
func _reveal() -> void:
	var f: Dictionary = Run.state["f"]
	var sim: Dictionary = Rules.simulate(Run.run_ctx(), f)
	var rows: Array = sim.get("rows", [])
	var v := _reveal_stage()

	v.add_child(UIKit.block(I18n.t("YOU READ IT OUT"), 13, UIKit.DIM))
	var at := 0.0
	for row in rows:
		var line := UIKit.hbox(10)
		line.add_child(UIKit.label(str(row.get("name", "")), 15, UIKit.INK))
		# The link is the rule. Naming it here, next to what it paid, is the
		# only place in the game the player is shown WHY a card scored what it
		# scored while they are looking at the card that did it.
		var link := str(row.get("link", ""))
		if link != "":
			line.add_child(UIKit.label(I18n.t(link).to_upper(), 11, UIKit.el_color(str(row.get("el", "")))))
		var note := str(row.get("note", ""))
		if note != "":
			line.add_child(UIKit.label("· " + I18n.t(note), 11, UIKit.DIM))
		var pts := UIKit.label("+%s" % row.get("total", 0), 15, UIKit.GREEN)
		pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(pts)
		v.add_child(line)
		UIKit.animate_in(line, at, 0.22)
		_beat(at, "card_lay")
		at += REVEAL_LINE

	# The wall, which is the part players get wrong. It is only shown when it
	# actually took something — a line saying "the wall held off 0" teaches the
	# opposite of the rule.
	var absorbed := int(sim.get("absorbed", 0))
	if absorbed > 0:
		at += REVEAL_WALL - REVEAL_LINE
		var wall := UIKit.hbox(10)
		wall.add_child(UIKit.label(I18n.t("Their denial holds it off"), 14, UIKit.RED))
		var lost := UIKit.label("−%d" % absorbed, 15, UIKit.RED)
		lost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		wall.add_child(lost)
		v.add_child(wall)
		UIKit.animate_in(wall, at, 0.22)
		_beat(at, "card_discard")

	# And what actually reaches them, which is the number that mattered all
	# along and was never shown arriving.
	at += REVEAL_LAND
	var applied := int(sim.get("applied", 0))
	var landed := UIKit.hbox(10)
	landed.add_child(UIKit.label(
		I18n.t("Composure") if applied > 0 else I18n.t("Nothing reaches them"), 18, UIKit.INK))
	if applied > 0:
		var got := UIKit.label("+%d" % applied, 22, UIKit.GREEN)
		got.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		got.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		landed.add_child(got)
	v.add_child(landed)
	UIKit.animate_in(landed, at, 0.28)
	_beat(at, "reading_resolve")
	v.add_child(UIKit.block(I18n.t("(any key)"), 10, UIKit.DIM))

	UIKit.after(at + REVEAL_HOLD, func():
		if _revealing:
			_finish_read()
	)


## One sound, `delay` seconds from now. Same shape as _deal_sound().
func _beat(delay: float, event: String) -> void:
	UIKit.after(delay, func(): Audio.play(event))


func _unhandled_input(event: InputEvent) -> void:
	# Any key at all skips the reading being read out. A player on their
	# fortieth reading knows what the wall does.
	if _revealing and (event is InputEventKey or event is InputEventJoypadButton) \
			and event.is_pressed() and not event.is_echo():
		_finish_read()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("parlour_read"):
		_read_it()
		get_viewport().set_input_as_handled()
		return
	if RunHeader.handle_shortcut(event, self):
		get_viewport().set_input_as_handled()
