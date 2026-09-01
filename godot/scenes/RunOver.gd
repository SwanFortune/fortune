extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")


func _ready() -> void:
	var over: Dictionary = Run.state["over"]

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(48)
	root.add_child(m)
	var v := UIKit.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)

	v.add_child(UIKit.block(UIKit.tr_line(over.get("head")), 15, UIKit.GOLD))
	v.add_child(UIKit.block(UIKit.tr_line(over.get("title")), 22, UIKit.INK))
	v.add_child(UIKit.block(UIKit.tr_line(over.get("body")), 13, UIKit.DIM))

	for line in over.get("lines", []):
		var row := UIKit.hbox(12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UIKit.label(UIKit.tr_line(line["left"]), 13, UIKit.DIM))
		var right := UIKit.label(_right_text(line), 13, UIKit.GOLD)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(right)
		v.add_child(row)

	v.add_child(UIKit.button(I18n.t("BEGIN AGAIN"), _restart))
	UIKit.focus_first(self)


func _restart() -> void:
	Run.restart()
	Nav.goto_for_state()


## A line's right side is usually a bare value (a number or a name, which
## must NOT be translated), but may also use the [format_key, args]
## convention when the value needs a word attached to it ("%s cards"), and
## may carry a separate translated `note` clause appended after an em-dash.
func _right_text(line: Dictionary) -> String:
	var raw = line.get("right", "")
	var value: String = UIKit.tr_line(raw) if raw is Array else str(raw)
	var note: String = UIKit.tr_line(line.get("note"))
	if note == "":
		return value
	return note if value == "" else "%s — %s" % [value, note]
