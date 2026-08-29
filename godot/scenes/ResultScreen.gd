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

	v.add_child(UIKit.block(res.get("head", ""), 15, UIKit.GREEN if win else UIKit.RED))
	v.add_child(UIKit.block(res.get("title", ""), 22, UIKit.INK))
	v.add_child(UIKit.block(res.get("said", ""), 13, UIKit.DIM))

	for line in res.get("lines", []):
		var row := UIKit.hbox(12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UIKit.label(line["left"], 13, UIKit.DIM))
		var right := UIKit.label(line["right"], 13, UIKit.GOLD)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(right)
		v.add_child(row)

	v.add_child(UIKit.button(res.get("cta", "CONTINUE"), _continue))


func _continue() -> void:
	Run.after_res()
	Nav.goto_for_state()
