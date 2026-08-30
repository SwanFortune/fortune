extends Control


func _ready() -> void:
	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(48)
	root.add_child(m)
	var v := UIKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)

	v.add_child(UIKit.block(I18n.t("PARLOUR"), 40, UIKit.GOLD))
	v.add_child(UIKit.block("a fortune-teller's ledger, in card form — Godot vertical-slice port", 14, UIKit.DIM))
	v.add_child(Control.new())  # spacer
	v.add_child(UIKit.button(I18n.t("BEGIN A READING"), _begin))
	v.add_child(UIKit.button(I18n.t("LIBRARY"), func(): Nav.goto_library()))
	v.add_child(UIKit.button(I18n.t("SETTINGS"), func(): Nav.goto_settings()))
	v.add_child(UIKit.button(I18n.t("QUIT"), _quit))

	var edits := CardEdits.edit_count()
	if edits > 0:
		v.add_child(UIKit.block("%d card(s) changed in the Library." % edits, 11, UIKit.GOLD))

	if not Content.load_errors.is_empty():
		v.add_child(UIKit.block("Content load warnings (see console): %d" % Content.load_errors.size(), 12, UIKit.RED))


func _begin() -> void:
	Run.state = Run.fresh()
	Nav.goto_for_state()


func _quit() -> void:
	get_tree().quit()
