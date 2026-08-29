## The core loop: lay cards from hand into the spoken line (cross), then READ
## IT to resolve via Rules.simulate(). Refreshes by reloading this same scene
## after every action (lay/read) — there's no reactive UI framework here, and
## re-running _ready() against the latest Run.state is simple and correct for
## a screen this size. See docs/PORTING_NOTES.md re: the letter-by-letter
## "mumble" animation this intentionally skips.
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
	var energy_ratio := float(f["energy"]) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0

	var header := UIKit.hbox(14)
	header.add_child(UIKit.sitter_portrait(s["el"], hp_ratio))
	var header_text := UIKit.vbox(4)
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_text.add_child(UIKit.block("%s · %s   %s" % [s["name"], s["role"], UIKit.el_tag(s["el"])], 18, UIKit.INK))
	header_text.add_child(UIKit.block("sign %s — %s: %s" % [q["n"], q["dn"], q["rule"]], 12, UIKit.DIM))
	header.add_child(header_text)
	v.add_child(header)
	v.add_child(UIKit.stat_row("Composure", "%s / %s" % [f["hp"], f["max"]], hp_ratio, UIKit.GREEN, UIKit.KEYS["composure"]))
	v.add_child(UIKit.stat_row("Energy", "%s / %s" % [f["energy"], f["energyMax"]], energy_ratio, UIKit.GOLD, UIKit.KEYS["energy"]))
	var denial_row := UIKit.block("Reading %s of %s   ·   Denial wall %s" % [f["turn"], f["turns"], f["denial"]], 12, UIKit.DIM)
	denial_row.tooltip_text = UIKit.KEYS["denial"]
	denial_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(denial_row)

	if f.get("taken", null) != null:
		v.add_child(UIKit.block("(%s slips out of your hand before you can start.)" % f["taken"], 11, UIKit.RED))

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
			cross_box.add_child(UIKit.label("%s (+%s)" % [UIKit.card_summary(c), row.get("total", "?")], 12, UIKit.GREEN))

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
	for c in f["hand"]:
		var afford := int(c.get("cost", 0)) <= int(f["energy"])
		fan.add_child(UIKit.card_face(c, _lay.bind(c["uid"]), afford))


func _lay(card_uid: String) -> void:
	Run.lay_card(card_uid)
	Nav.goto_for_state()


func _read_it() -> void:
	Run.read_it()
	Nav.goto_for_state()
