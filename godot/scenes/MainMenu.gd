extends Control

## Set once BEGIN has been pressed while a run was in progress, so the second
## press is the one that actually discards it. A two-step button rather than a
## modal: there is no dialog system here, and losing three nights to a misclick
## is exactly the kind of thing a confirmation exists for.
var _begin_armed := false

var _root: Control


func _ready() -> void:
	_build()


func _build() -> void:
	if _root != null:
		_root.queue_free()
	_root = UIKit.root_control()
	add_child(_root)
	var m := UIKit.margin(48)
	_root.add_child(m)
	var v := UIKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)

	v.add_child(UIKit.block(I18n.t("PARLOUR"), 40, UIKit.GOLD))
	v.add_child(UIKit.block("a fortune-teller's ledger, in card form — Godot vertical-slice port", 14, UIKit.DIM))
	v.add_child(Control.new())  # spacer

	var saved: Dictionary = Save.peek()
	if not saved.is_empty():
		v.add_child(UIKit.button(I18n.t("CONTINUE"), _continue))
		v.add_child(UIKit.block(_saved_line(saved), 11, UIKit.DIM))
	elif Save.last_error != "":
		# A save that exists but cannot be read is worth saying out loud: the
		# alternative is a player whose run silently evaporates.
		v.add_child(UIKit.block("%s %s" % [I18n.t("Could not read your saved run."), Save.last_error], 11, UIKit.RED))

	v.add_child(UIKit.button(_begin_label(), _begin))
	v.add_child(UIKit.button(I18n.t("LIBRARY"), func(): Nav.goto_library()))
	v.add_child(UIKit.button(I18n.t("MODS"), func(): Nav.goto_mods()))
	v.add_child(UIKit.button(I18n.t("SETTINGS"), func(): Nav.goto_settings()))
	v.add_child(UIKit.button(I18n.t("QUIT"), _quit))

	var edits := CardEdits.edit_count()
	if edits > 0:
		v.add_child(UIKit.block("%d card(s) changed in the Library." % edits, 11, UIKit.GOLD))

	if not Content.load_errors.is_empty():
		v.add_child(UIKit.block(
			"%d %s" % [Content.load_errors.size(), I18n.t("content warning(s) — see MODS.")], 12, UIKit.RED))


func _begin_label() -> String:
	if _begin_armed:
		return I18n.t("THIS ENDS THE RUN IN PROGRESS — BEGIN ANYWAY")
	return I18n.t("BEGIN A READING")


func _saved_line(saved: Dictionary) -> String:
	var reader: Dictionary = Content.get_reader(str(saved.get("reader", "")))
	var who: String = I18n.reader_field(reader, "name") if not reader.is_empty() else "?"
	return I18n.t("night %s, knock %s · %s · %s faith") % [
		saved.get("night", 1), saved.get("step", 1), who, saved.get("faith", 0),
	]


func _continue() -> void:
	var res: Dictionary = Save.restore()
	if not res.get("ok", false):
		_begin_armed = false
		_build()
		return
	Nav.goto_for_state()


func _begin() -> void:
	if Save.has_save() and not _begin_armed:
		_begin_armed = true
		_build()
		return
	Save.clear()
	Run.state = Run.fresh()
	Nav.goto_for_state()


func _quit() -> void:
	get_tree().quit()
