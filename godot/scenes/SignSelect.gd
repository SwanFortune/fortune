extends Control


func _ready() -> void:
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	v.add_child(UIKit.block(I18n.t("CHOOSE YOUR SIGN"), 26, UIKit.GOLD))
	v.add_child(UIKit.block(I18n.t("Every reader is a sign, an element, and a starting deck of ten."), 13, UIKit.DIM))

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 500)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in Content.readers.size():
		var r: Dictionary = Content.readers[i]
		var el_c := UIKit.el_color(r["el"])
		var lines := [
			["%s — %s" % [I18n.reader_field(r, "name"), I18n.reader_field(r, "sign")], 16, UIKit.INK],
			[I18n.reader_field(r, "line"), 12, UIKit.DIM],
			["%s  %s" % [UIKit.el_glyph(r["el"]), I18n.reader_field(r, "rule")], 12, el_c],
			["Starts with: %s" % ", ".join(r.get("deck", [])), 11, UIKit.DIM],
		]
		list.add_child(UIKit.panel_button(lines, _pick.bind(i)))
	UIKit.focus_first(self)


func _pick(i: int) -> void:
	Run.pick_reader(i)
	Nav.goto_for_state()
