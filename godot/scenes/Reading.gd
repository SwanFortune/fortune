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
	header_text.add_child(UIKit.block("%s · %s   %s" % [s["name"], s["role"], UIKit.el_tag(s["el"])], 18, UIKit.INK))
	header_text.add_child(UIKit.block("sign %s — %s: %s" % [q["n"], q["dn"], q["rule"]], 12, UIKit.DIM))
	header.add_child(header_text)
	v.add_child(header)
	v.add_child(UIKit.stat_row("Composure", "%s / %s" % [f["hp"], f["max"]], prev_hp_ratio, hp_ratio, UIKit.GREEN, UIKit.KEYS["composure"]))
	v.add_child(UIKit.stat_row("Energy", "%s / %s" % [f["energy"], f["energyMax"]], prev_energy_ratio, energy_ratio, UIKit.GOLD, UIKit.KEYS["energy"]))
	var denial_row := UIKit.block("Reading %s of %s   ·   Denial wall %s" % [f["turn"], f["turns"], f["denial"]], 12, UIKit.DIM)
	denial_row.tooltip_text = UIKit.KEYS["denial"]
	denial_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(denial_row)

	if f.get("taken", null) != null:
		v.add_child(UIKit.block("(%s slips out of your hand before you can start.)" % f["taken"], 11, UIKit.RED))

	var discarded: Array = f.get("_justDiscarded", [])
	if not discarded.is_empty():
		var disc_label := UIKit.block("Discarded: %s" % ", ".join(discarded), 11, UIKit.DIM)
		v.add_child(disc_label)
		if not UIKit.motion_off():
			var fade := UIKit.bound_tween(disc_label)
			fade.tween_interval(UIKit.dur(0.9))
			fade.tween_property(disc_label, "modulate:a", 0.0, UIKit.dur(1.2)).set_trans(Tween.TRANS_QUAD)

	v.add_child(UIKit.block("SAID SO FAR", 12, UIKit.DIM))
	var cross_box := UIKit.hbox(6)
	v.add_child(cross_box)
	if f["cross"].is_empty():
		cross_box.add_child(UIKit.label("(nothing yet)", 12, UIKit.DIM))
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

	v.add_child(UIKit.button("READ IT", _read_it))

	var hand_label := UIKit.label("YOUR HAND — hover a card for its full text", 12, UIKit.DIM)
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
			deal_index += 1


func _lay(card_uid: String) -> void:
	Run.lay_card(card_uid)
	Nav.goto_for_state()


func _read_it() -> void:
	Run.read_it()
	Nav.goto_for_state()
