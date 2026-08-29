extends Control


func _ready() -> void:
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	var st: Dictionary = Run.state
	v.add_child(UIKit.label("NIGHT %d · KNOCK %d OF 8" % [int(st["night"]) + 1, int(st["step"]) + 1], 14, UIKit.GOLD))
	v.add_child(UIKit.label("Who knocks tonight?", 22, UIKit.INK))
	v.add_child(UIKit.label("Reader: %s · Coin: %s · Faith: %s · Mended: %s · Deck: %s" % [
		st["reader"]["name"], st["coin"], st["faith"], st["mended"], st["deck"].size()
	], 12, UIKit.DIM))

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 460)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var opts: Array = st["options"]
	for i in opts.size():
		list.add_child(_opt_button(opts[i], i))


func _opt_button(o: Dictionary, i: int) -> Button:
	var lines: Array = []
	match o["kind"]:
		"sitter", "elite", "boss":
			var s: Dictionary = o["sitter"]
			var q: Dictionary = o["quirk"]
			var tag := "ELITE — " if o["kind"] == "elite" else ("THE MAYOR — " if o["kind"] == "boss" else "")
			lines.append(["%s%s" % [tag, s["name"]], 17, UIKit.RED if o["kind"] != "sitter" else UIKit.INK])
			lines.append(["%s · sign %s (%s) · element %s" % [s["role"], q["n"], q["dn"], s["el"].to_upper()], 12, UIKit.el_color(s["el"])])
			lines.append(["composure %s · denial %s · %s readings" % [s["max"], s["denial"], s["turns"]], 11, UIKit.DIM])
			lines.append([s["brings"], 12, UIKit.DIM])
		"break":
			var rest: Dictionary = o["rest"]
			if rest.get("kind", "") == "SHOP":
				lines.append(["THE APOTHECARY", 17, UIKit.GOLD])
				lines.append([rest.get("title", ""), 12, UIKit.DIM])
			else:
				lines.append([rest.get("head", "EVENT"), 13, UIKit.GOLD])
				lines.append([rest.get("title", ""), 17, UIKit.INK])
				lines.append([rest.get("line", ""), 12, UIKit.DIM])
	return UIKit.panel_button(lines, _choose.bind(i))


func _choose(i: int) -> void:
	Run.choose(i)
	Nav.goto_for_state()
