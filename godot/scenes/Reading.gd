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
	v.add_child(UIKit.label("%s · %s" % [s["name"], s["role"]], 18, UIKit.INK))
	v.add_child(UIKit.label("sign %s — %s: %s" % [q["n"], q["dn"], q["rule"]], 12, UIKit.DIM))

	var hp_ratio := float(f["hp"]) / float(f["max"]) if int(f["max"]) > 0 else 0.0
	var energy_ratio := float(f["energy"]) / float(f["energyMax"]) if int(f["energyMax"]) > 0 else 0.0
	v.add_child(UIKit.stat_row("Composure", "%s / %s" % [f["hp"], f["max"]], hp_ratio, UIKit.GREEN))
	v.add_child(UIKit.stat_row("Energy", "%s / %s" % [f["energy"], f["energyMax"]], energy_ratio, UIKit.GOLD))
	v.add_child(UIKit.label("Reading %s of %s   ·   Denial wall %s" % [f["turn"], f["turns"], f["denial"]], 12, UIKit.DIM))

	if f.get("taken", null) != null:
		v.add_child(UIKit.label("(%s slips out of your hand before you can start.)" % f["taken"], 11, UIKit.RED))

	v.add_child(UIKit.label("SAID SO FAR", 12, UIKit.DIM))
	var cross_box := UIKit.hbox(6)
	v.add_child(cross_box)
	if f["cross"].is_empty():
		cross_box.add_child(UIKit.label("(nothing yet)", 12, UIKit.DIM))
	else:
		var preview: Dictionary = Rules.simulate(Run.run_ctx(), f)
		for i in f["cross"].size():
			var c: Dictionary = f["cross"][i]
			var row: Dictionary = preview["rows"][i] if i < preview["rows"].size() else {}
			cross_box.add_child(UIKit.label("%s (+%s)" % [c["n"], row.get("total", "?")], 12, UIKit.GREEN))

	v.add_child(UIKit.button("READ IT", _read_it))

	v.add_child(UIKit.label("YOUR HAND", 12, UIKit.DIM))
	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 320)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for c in f["hand"]:
		list.add_child(_card_button(c, f))


func _card_button(c: Dictionary, f: Dictionary) -> Button:
	var afford := int(c.get("cost", 0)) <= int(f["energy"])
	var el_c: Color = UIKit.el_color(c["el"]) if c.get("el") != null else UIKit.DIM
	var lines := [
		["%s   (cost %s)" % [c["n"], c.get("cost", 0)], 15, el_c if afford else UIKit.DIM],
		[UIKit.card_text(c), 12, UIKit.INK if afford else UIKit.DIM],
	]
	if c.get("fl", "") != "":
		lines.append([c["fl"], 11, UIKit.DIM])
	return UIKit.panel_button(lines, _lay.bind(c["uid"]), afford)


func _lay(card_uid: String) -> void:
	Run.lay_card(card_uid)
	Nav.goto_for_state()


func _read_it() -> void:
	Run.read_it()
	Nav.goto_for_state()
