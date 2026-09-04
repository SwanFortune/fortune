extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## The width of the column this screen reads down. Same idea as MainMenu's.
const COLUMN := 460.0


func _ready() -> void:
	var over: Dictionary = Run.state["over"]

	var root := UIKit.root_control(Table.VIEW_DOOR)
	add_child(root)
	# A column down the left, like the menu — this screen is the same closed
	# door, and stretching four stat lines from one side of the window to the
	# other put "Faith" and "44" a thousand pixels apart with the picture of the
	# thing that just happened hidden behind them.
	root.add_child(UIKit.side_scrim(COLUMN * UIKit.text_scale * 1.6))
	var m := UIKit.margin(48)
	root.add_child(m)
	var row_wrap := UIKit.hbox(28)
	m.add_child(row_wrap)
	var v := UIKit.vbox(12)
	v.custom_minimum_size.x = COLUMN * UIKit.text_scale
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row_wrap.add_child(v)

	v.add_child(UIKit.block(UIKit.tr_line(over.get("head")), 15, UIKit.GOLD))
	v.add_child(UIKit.block(UIKit.tr_line(over.get("title")), 22, UIKit.INK))
	v.add_child(UIKit.block(UIKit.tr_line(over.get("body")), 13, UIKit.DIM))

	# WHAT BECAME OF THE VILLAGE, AND OF YOU. The run is nine people and which
	# of them went home whole; the screen that ended it was a tier line and four
	# numbers, which made it the one place in the game that did not know what
	# the game was about. Both paragraphs come from data/base/endings.json and
	# are chosen by how many of them left as they came.
	var village := str(over.get("village", ""))
	if village != "":
		v.add_child(UIKit.block(I18n.t(village), 12, UIKit.DIM))
	var reader := str(over.get("reader", ""))
	if reader != "":
		var mine := UIKit.block(I18n.t(reader), 13, UIKit.INK)
		v.add_child(mine)

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
	row_wrap.add_child(_the_ledger(over.get("ledger", [])))
	UIKit.focus_first(self)


## Everyone who sat down, in order, with what became of them — their own line
## out of sitters.json, which the source wrote and nothing had ever shown after
## the encounter it belonged to.
##
## In its own column beside the summary rather than under it: this is the list
## the ending is about, and putting it below four stat rows would make it the
## footnote to a scoreboard, which is the wrong way round.
const LEDGER_WIDTH := 470.0

func _the_ledger(ledger: Array) -> Control:
	var col := UIKit.vbox(10)
	col.custom_minimum_size.x = LEDGER_WIDTH * UIKit.text_scale
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	if ledger.is_empty():
		return col
	col.add_child(UIKit.block(I18n.t("WHO SAT DOWN"), 11, UIKit.GOLD))
	var scroll := UIKit.scroll()
	scroll.custom_minimum_size.y = 430
	col.add_child(scroll)
	var list := UIKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in ledger:
		var mended: bool = str(entry.get("outcome", "")) == "mended"
		var who := UIKit.hbox(8)
		who.add_child(UIKit.label(str(entry.get("name", "")), 14, UIKit.INK if mended else UIKit.DIM))
		who.add_child(UIKit.label(str(entry.get("role", "")), 10, UIKit.DIM))
		var when := UIKit.label("%s %d · %s" % [
			I18n.t("night"), int(entry.get("night", 0)) + 1, str(entry.get("at", ""))], 10, UIKit.DIM)
		when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		who.add_child(when)
		list.add_child(who)
		list.add_child(UIKit.block(str(entry.get("said", "")), 11, UIKit.GREEN if mended else UIKit.RED))
	return col


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
