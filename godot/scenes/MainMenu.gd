extends Control


func _ready() -> void:
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(48)
	root.add_child(m)
	var v := UIKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)

	v.add_child(UIKit.label("PARLOUR", 40, UIKit.GOLD))
	v.add_child(UIKit.label("a fortune-teller's ledger, in card form — Godot vertical-slice port", 14, UIKit.DIM))
	v.add_child(Control.new())  # spacer
	v.add_child(UIKit.button("BEGIN A READING", _begin))
	v.add_child(UIKit.button("QUIT", _quit))

	if not Content.load_errors.is_empty():
		v.add_child(UIKit.label("Content load warnings (see console): %d" % Content.load_errors.size(), 12, UIKit.RED))


func _begin() -> void:
	Run.state = Run.fresh()
	Nav.goto_for_state()


func _quit() -> void:
	get_tree().quit()
