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


func _ready() -> void:
	var f: Dictionary = Run.state["f"]
	var root := UIKit.root_control()
	add_child(root)
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
	header_text.add_child(UIKit.block("%s · %s   %s" % [I18n.sitter_field(s, "name"), I18n.sitter_field(s, "role"), UIKit.el_tag(s["el"])], 18, UIKit.INK))
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

	v.add_child(UIKit.button(I18n.t("READ IT"), _read_it))

	var hand_label := UIKit.label(I18n.t("YOUR HAND — hover a card for its full text"), 12, UIKit.DIM)
	v.add_child(hand_label)
	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 340)
	var fan := HFlowContainer.new()
	fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fan.add_theme_constant_override("h_separation", 8)
	fan.add_theme_constant_override("v_separation", 8)
	scroll.add_child(fan)
	var just_drawn: Array = f.get("_justDrawn", [])
	var deal_index := 0
	for c in f["hand"]:
		var afford := int(c.get("cost", 0)) <= int(f["energy"])
		var face := UIKit.card_face(c, _lay.bind(c["uid"]), afford)
		fan.add_child(face)
		if just_drawn.has(c["uid"]):
			UIKit.animate_in(face, deal_index * 0.06)
			_deal_sound(deal_index * 0.06)
			deal_index += 1
	# The hand, not the run header above it. See Map.gd. Falls back to the whole
	# screen when the hand is empty, so READ IT is still reachable.
	UIKit.focus_first(fan if fan.get_child_count() > 0 else self)


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
