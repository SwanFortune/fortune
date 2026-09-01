extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const RunHeader := preload("res://scenes/RunHeader.gd")
const UIKit := preload("res://scenes/UIKit.gd")


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
	# The night's options, not the run header above them — the header is chrome,
	# and landing on its DECK chip would make the first key press do nothing useful.
	UIKit.focus_first(list)


func _opt_button(o: Dictionary, i: int) -> Control:
	var lines: Array = []
	match o["kind"]:
		"sitter", "elite", "boss":
			var s: Dictionary = o["sitter"]
			var q: Dictionary = o["quirk"]
			var tag := "ELITE — " if o["kind"] == "elite" else ("THE MAYOR — " if o["kind"] == "boss" else "")
			lines.append(["%s%s" % [tag, I18n.sitter_field(s, "name")], 17, UIKit.RED if o["kind"] != "sitter" else UIKit.INK])
			lines.append(["%s · %s %s (%s) · %s" % [I18n.sitter_field(s, "role"), I18n.t("sign"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn"), UIKit.el_tag(s["el"])], 12, UIKit.el_color(s["el"])])
			lines.append([I18n.sign_rule(q, s), 11, UIKit.DIM])
			lines.append(["composure %s · denial %s · %s readings" % [s["max"], s["denial"], s["turns"]], 11, UIKit.DIM])
			var job: Dictionary = Content.get_job(s["role"])
			if job.get("t", "") != "":
				lines.append([I18n.fill(I18n.job_text(s["role"], job), str(s.get("p", "they"))), 11, UIKit.GOLD])
			# An elite's twist changes composure, denial, readings or hand size,
			# and until now was applied silently — the option said "ELITE" and
			# nothing about what that elite actually does. The source shows this
			# line on the same card (~line 593), so the field was ported but
			# never read by anything.
			var tw: Dictionary = s.get("twist", {})
			if tw.get("t", "") != "":
				lines.append([I18n.fill(I18n.twist_text(tw), str(s.get("p", "they"))), 11, UIKit.RED])
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


func _unhandled_input(event: InputEvent) -> void:
	if RunHeader.handle_shortcut(event, self):
		get_viewport().set_input_as_handled()
