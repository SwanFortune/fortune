extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const UIKit := preload("res://scenes/UIKit.gd")

## How wide the reading's tally is allowed to be. Wide enough for the longest
## label and its number, narrow enough that they read as one line.
const STAT_WIDTH := 460


func _ready() -> void:
	var res: Dictionary = Run.state["res"]
	var kind: String = res.get("kind", "")
	var win: bool = kind == "win"
	Audio.play("sitter_win" if win else "sitter_lose")

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

	# A COLUMN, not the window. These rows were EXPAND_FILL, so on a 1280 screen
	# "Composure" sat at the far left and "36 / 36" at the far right, eleven
	# hundred pixels away with the teacup and the Minitel drawn between them —
	# a pair of numbers nobody can read as a pair, half of it over the artwork.
	var stats := UIKit.vbox(4)
	# BEGIN, not CENTER: everything else on this screen starts at the left
	# margin, and a tally floating in the middle of the table reads as a
	# different screen from the sentence above it.
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.custom_minimum_size.x = STAT_WIDTH * UIKit.text_scale
	v.add_child(stats)
	for line in res.get("lines", []):
		var row := UIKit.hbox(12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var left := UIKit.label(UIKit.tr_line(line["left"]), 13, UIKit.DIM)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		var right := UIKit.label(_right_text(line), 13, UIKit.GOLD)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(right)
		stats.add_child(row)

	v.add_child(UIKit.button(UIKit.tr_line(res.get("cta")), _continue))
	# This screen carries no run header, so it needs its own way out — and it is
	# a screen a player can be sitting on when they close the game, since the
	# result is part of the saved state. Every screen a run can be on offers the
	# same exit; see UIKit.WAY_OUT.
	var way_out := UIKit.button(I18n.t("THE MENU"), func():
		Save.flush()
		Nav.goto_main_menu()
	)
	way_out.add_to_group(UIKit.WAY_OUT)
	v.add_child(way_out)
	UIKit.focus_first(self)


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
