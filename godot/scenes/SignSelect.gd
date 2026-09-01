extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")


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
		# A reader may be locked behind a condition (readers.json's `unlock`).
		# No base reader is; a pack can be. A locked one is shown rather than
		# hidden, with what it wants — a reader you cannot see is not a goal.
		var locked: bool = Profile.reader_locked(r)
		var lines := [
			["%s — %s" % [I18n.reader_field(r, "name"), I18n.reader_field(r, "sign")], 16,
				UIKit.DIM if locked else UIKit.INK],
			[I18n.reader_field(r, "line"), 12, UIKit.DIM],
			["%s  %s" % [UIKit.el_glyph(r["el"]), I18n.reader_field(r, "rule")], 12,
				UIKit.DIM if locked else el_c],
			["%s %s" % [I18n.t("Starts with:"), ", ".join(r.get("deck", []))], 11, UIKit.DIM],
		]
		if locked:
			lines.append(["%s %s" % [I18n.t("LOCKED —"), Profile.unlock_text(r.get("unlock", null))], 12, UIKit.GOLD])
		list.add_child(UIKit.panel_button(lines, _pick.bind(i), not locked))
	UIKit.focus_first(self)


func _pick(i: int) -> void:
	Run.pick_reader(i)
	Nav.goto_for_state()
