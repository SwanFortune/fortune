extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")

## Set once BEGIN has been pressed while a run was in progress, so the second
## press is the one that actually discards it. A two-step button rather than a
## modal: there is no dialog system here, and losing three nights to a misclick
## is exactly the kind of thing a confirmation exists for.
var _begin_armed := false

## How many cards the last CONTINUE could not resolve — cards from a pack that
## has since been switched off or removed. Save.restore() has always counted
## these, and nothing was reading the count, so a deck could quietly come back
## shorter than it went in. CONTINUE now stops on the first press to say so,
## and resumes on the second.
var _dropped := 0

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
	# The version, where a player can find it without being asked to. The first
	# thing a bug report needs is which build it happened on.
	v.add_child(UIKit.block(Version.full(), 11, UIKit.DIM))
	v.add_child(Control.new())  # spacer

	var saved: Dictionary = Save.peek()
	if not saved.is_empty():
		v.add_child(UIKit.button(
			I18n.t("RESUME ANYWAY") if _dropped > 0 else I18n.t("CONTINUE"), _continue))
		v.add_child(UIKit.block(_saved_line(saved), 11, UIKit.DIM))
		if Save.restored_from_backup:
			# Quietly rolling a player back in time is the kind of thing they
			# would later describe as the game losing their progress. Saying it
			# costs one line.
			v.add_child(UIKit.block(I18n.t(
				"Your last save could not be read, so this is the one before it — you may have lost a step."
			), 11, UIKit.GOLD))
		if _dropped > 0:
			v.add_child(UIKit.block(I18n.t(
				"%s card(s) in this run came from content you no longer have and have been removed from the deck."
			) % _dropped, 11, UIKit.RED))
	elif Save.last_error != "":
		# A save that exists but cannot be read is worth saying out loud: the
		# alternative is a player whose run silently evaporates.
		v.add_child(UIKit.block("%s %s" % [I18n.t("Could not read your saved run."), Save.last_error], 11, UIKit.RED))

	# If user:// cannot be written, NOTHING persists — not the run, not the
	# settings, not the unlocks — and all three used to fail in silence. The run
	# says so in its own header while you are playing; this is the same news at
	# the point where a player would otherwise notice their settings resetting
	# every launch and have no idea why.
	var write_problem := ""
	for pair in [[Settings.last_error, "settings"], [Profile.last_error, "profile"]]:
		if str(pair[0]) != "":
			write_problem = str(pair[0])
	if write_problem != "" or Save.write_failed:
		v.add_child(UIKit.block(I18n.t(
			"NOTHING IS BEING SAVED — your run, settings and unlocks will all be lost when you close the game. %s"
		) % (write_problem if write_problem != "" else Save.last_error), 11, UIKit.RED))

	v.add_child(UIKit.button(_begin_label(), _begin))
	# Above LIBRARY on purpose: a player who has just arrived needs this more
	# than they need the card editor, and a rules screen nobody finds is worth
	# about as much as no rules screen.
	v.add_child(UIKit.button(I18n.t("HOW TO PLAY"), func(): Nav.goto_how_to_play()))
	v.add_child(UIKit.button(I18n.t("LIBRARY"), func(): Nav.goto_library()))
	# Always shown, never teased. A hidden entry that appears once you already
	# know a code is a worse secret than an ordinary-looking machine that
	# happens to answer to four letters.
	v.add_child(UIKit.button(I18n.t("MINITEL"), func(): Nav.goto_minitel()))
	v.add_child(UIKit.button(I18n.t("MODS"), func(): Nav.goto_mods()))
	v.add_child(UIKit.button(I18n.t("SETTINGS"), func(): Nav.goto_settings()))
	v.add_child(UIKit.button(I18n.t("QUIT"), _quit))

	var edits := CardEdits.edit_count()
	if edits > 0:
		v.add_child(UIKit.block("%d card(s) changed in the Library." % edits, 11, UIKit.GOLD))

	if not Content.load_errors.is_empty():
		v.add_child(UIKit.block(
			"%d %s" % [Content.load_errors.size(), I18n.t("content warning(s) — see MODS.")], 12, UIKit.RED))
	UIKit.focus_first(self)


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
		_dropped = 0
		_build()
		return
	# A run that came back short is worth stopping for once. Losing cards out of
	# a deck silently is the sort of thing a player would later report as the
	# game cheating them.
	if int(res.get("dropped", 0)) > 0 and _dropped == 0:
		_dropped = int(res["dropped"])
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
