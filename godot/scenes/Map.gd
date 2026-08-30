extends Control


func _ready() -> void:
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	var st: Dictionary = Run.state
	v.add_child(RunHeader.build(self))
	v.add_child(UIKit.block("%s %d · %s %d / 8" % [
		I18n.t("NIGHT"), int(st["night"]) + 1, I18n.t("KNOCK"), int(st["step"]) + 1
	], 14, UIKit.GOLD))
	v.add_child(UIKit.block(I18n.t("Who knocks tonight?"), 22, UIKit.INK))

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 460)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var opts: Array = st["options"]
	for i in opts.size():
		list.add_child(_opt_button(opts[i], i))


func _opt_button(o: Dictionary, i: int) -> Control:
	var lines: Array = []
	match o["kind"]:
		"sitter", "elite", "boss":
			var s: Dictionary = o["sitter"]
			var q: Dictionary = o["quirk"]
			var tag := "ELITE — " if o["kind"] == "elite" else ("THE MAYOR — " if o["kind"] == "boss" else "")
			lines.append(["%s%s" % [tag, I18n.sitter_field(s, "name")], 17, UIKit.RED if o["kind"] != "sitter" else UIKit.INK])
			lines.append(["%s · sign %s (%s) · %s" % [I18n.sitter_field(s, "role"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn"), UIKit.el_tag(s["el"])], 12, UIKit.el_color(s["el"])])
			lines.append(["composure %s · denial %s · %s readings" % [s["max"], s["denial"], s["turns"]], 11, UIKit.DIM])
			var job: Dictionary = Content.get_job(s["role"])
			if job.get("t", "") != "":
				lines.append([I18n.job_text(s["role"], job), 11, UIKit.GOLD])
			lines.append([I18n.sitter_field(s, "brings"), 12, UIKit.DIM])
		"break":
			var rest: Dictionary = o["rest"]
			if rest.get("kind", "") == "SHOP":
				lines.append([I18n.t("THE APOTHECARY"), 17, UIKit.GOLD])
				lines.append([rest.get("title", ""), 12, UIKit.DIM])
			else:
				lines.append([rest.get("head", "EVENT"), 13, UIKit.GOLD])
				lines.append([rest.get("title", ""), 17, UIKit.INK])
				lines.append([rest.get("line", ""), 12, UIKit.DIM])
	return UIKit.panel_button(lines, _choose.bind(i))


func _choose(i: int) -> void:
	Run.choose(i)
	Nav.goto_for_state()
