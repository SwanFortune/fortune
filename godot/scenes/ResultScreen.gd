extends Control


func _ready() -> void:
	var res: Dictionary = Run.state["res"]
	var kind: String = res.get("kind", "")
	var win: bool = kind == "win"

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(48)
	root.add_child(m)
	var v := UIKit.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)

	v.add_child(UIKit.block(UIKit.tr_line(res.get("head")), 15, UIKit.GREEN if win else UIKit.RED))
	v.add_child(UIKit.block(UIKit.tr_line(res.get("title")), 22, UIKit.INK))
	var sitter: Dictionary = res.get("sitter", {})
	var said_field: String = "win" if win else "fail"
	v.add_child(UIKit.block(
		I18n.sitter_field(sitter, said_field) if not sitter.is_empty() else res.get("said", ""),
		13, UIKit.DIM))

	for line in res.get("lines", []):
		var row := UIKit.hbox(12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UIKit.label(UIKit.tr_line(line["left"]), 13, UIKit.DIM))
		var right := UIKit.label(_right_text(line), 13, UIKit.GOLD)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(right)
		v.add_child(row)

	v.add_child(UIKit.button(UIKit.tr_line(res.get("cta")), _continue))


func _continue() -> void:
	Run.after_res()
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
