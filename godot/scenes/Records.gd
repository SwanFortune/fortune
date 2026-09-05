## WHAT THE PROFILE HAS BEEN KEEPING, shown to the person it is about.
##
## Profile.gd has recorded runs finished, faith, people mended, readers taken to
## the end and codes dialled since it was written, and nothing has ever shown
## any of it. The only place a stat surfaced was as an unlock condition on a
## locked reader — so a player could learn a number existed only by failing to
## meet it.
##
## THE STREAKS ARE THE POINT. A total says what you have done; a streak says
## what you are in the middle of, and it is the one number that makes stopping
## cost something. Three of them run at once — people, runs, days — and each
## shows what it is on and the best it has ever been, because a streak with no
## record behind it is only a counter.
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

const SCROLL_STEP := 60

var _return_scene: String = "res://scenes/MainMenu.tscn"
var _scroll: ScrollContainer


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_WALL)
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var outer := UIKit.vbox(12)
	m.add_child(outer)

	var top := UIKit.hbox(14)
	var heading := UIKit.block(I18n.t("WHAT YOU HAVE DONE"), 26, UIKit.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var back := UIKit.button(I18n.t("BACK"), _back)
	back.add_to_group(UIKit.WAY_OUT)
	top.add_child(back)
	outer.add_child(top)

	_scroll = UIKit.scroll()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)

	v.add_child(_streaks())
	v.add_child(_tallies())
	v.add_child(_the_readers())

	# The way out, not the list: nothing in the list can be pressed.
	UIKit.focus_first(back, self)


## The three things that can be running, side by side. Each one says what it is
## on now, and under it the best it has ever been — so a streak that has just
## broken still has something to show for itself.
func _streaks() -> Control:
	var box := UIKit.vbox(8)
	box.add_child(UIKit.block(I18n.t("ON A RUN"), 13, UIKit.GOLD))
	var row := UIKit.hbox(10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for one in [
		["readings", I18n.t("PEOPLE IN A ROW"), I18n.t("mended, one after another. Somebody going home as they came ends it — finishing a run does not."), UIKit.GREEN],
		["runs", I18n.t("RUNS IN A ROW"), I18n.t("three whole nights, one after another."), UIKit.GOLD],
		["days", I18n.t("DAYS IN A ROW"), I18n.t("days you finished a run on. Miss one and it starts again."), UIKit.VIOLET],
	]:
		row.add_child(_streak_card(str(one[0]), str(one[1]), str(one[2]), one[3]))
	box.add_child(row)
	return box


func _streak_card(key: String, caption: String, under: String, tint: Color) -> Control:
	var now := int(Profile.get_stat("streak_" + key))
	var best := int(Profile.get_stat("best_streak_" + key))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = under
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# Lit while it is running, and the house surface once it is not: a streak of
	# nothing should not look like an achievement.
	panel.add_theme_stylebox_override("panel", UIKit.surface(
		UIKit.warm(UIKit.PANEL, 0.04), Color(tint, 0.45 if now > 0 else 0.12), 1, 12))
	var col := UIKit.vbox(2)
	panel.add_child(col)
	col.add_child(UIKit.block(caption, 11, UIKit.DIM))
	col.add_child(UIKit.block(str(now), 30, tint if now > 0 else UIKit.DIM))
	col.add_child(UIKit.block(I18n.t("best %d") % best, 11, UIKit.DIM))
	return panel


## The totals. Two columns of label-and-number, because a wall of them in one
## column is a receipt.
func _tallies() -> Control:
	var finished := int(Profile.get_stat("runs_finished"))
	var won := int(Profile.get_stat("runs_won"))
	var mended := int(Profile.get_stat("total_mended"))
	var left := int(Profile.get_stat("total_left"))
	var sat := mended + left

	var rungs: Array = Content.difficulty
	var level := clampi(int(Profile.get_stat("best_level")), 0, maxi(0, rungs.size() - 1))
	var level_name := str(rungs[level].get("name", "")) if level < rungs.size() else ""

	var box := UIKit.vbox(8)
	box.add_child(UIKit.block(I18n.t("ALTOGETHER"), 13, UIKit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	# SHRINK, not EXPAND: given the whole window the two columns split it in
	# half and each number ends up six hundred pixels from the words it belongs
	# to, which is a table nobody can read across.
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(grid)
	for line in [
		[I18n.t("Evenings finished"), str(finished)],
		[I18n.t("Three nights, whole"), "%d%s" % [won, ("  ·  %d%%" % int(round(100.0 * won / finished))) if finished > 0 else ""]],
		[I18n.t("Sat down with you"), str(sat)],
		[I18n.t("Went home whole"), str(mended)],
		[I18n.t("Went home as they came"), str(left)],
		[I18n.t("Most faith in one evening"), str(int(Profile.get_stat("best_faith")))],
		[I18n.t("Hardest week finished"), "%d · %s" % [level, I18n.t(level_name)]],
		[I18n.t("Minitel codes dialled"), str((Profile.get_stat("codes_entered") as Array).size())],
	]:
		grid.add_child(_tally(str(line[0]), str(line[1])))
	return box


func _tally(label: String, value: String) -> Control:
	var row := UIKit.hbox(8)
	row.custom_minimum_size.x = 400 * UIKit.text_scale
	var l := UIKit.block(label, 12, UIKit.DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r := UIKit.label(value, 13, UIKit.INK)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(r)
	return row


## Which of them you have taken all the way. Named, not counted: "6 of 13" tells
## you a number, and the list tells you which one to try next.
func _the_readers() -> Control:
	var done: Array = Profile.get_stat("readers_finished")
	var box := UIKit.vbox(6)
	box.add_child(UIKit.block(I18n.t("TAKEN TO THE END"), 13, UIKit.GOLD))
	box.add_child(UIKit.block(
		I18n.t("%d of %d readers") % [done.size(), Content.readers.size()], 12, UIKit.INK))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(flow)
	for r in Content.readers:
		var did: bool = done.has(str(r.get("k", "")))
		var tint: Color = UIKit.el_color(str(r.get("el", ""))) if did else UIKit.DIM
		# label(), not block(): a wrapping label in a flow container breaks
		# SERPENTARIUS across two lines in the middle of the word.
		flow.add_child(UIKit.label(
			"%s %s" % ["·" if did else "—", I18n.reader_field(r, "sign")], 12,
			tint if did else Color(UIKit.DIM, 0.55)))
	return box


func _back() -> void:
	get_tree().change_scene_to_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
		return
	if _scroll == null:
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = SCROLL_STEP
	elif event.is_action_pressed("ui_up", true):
		step = -SCROLL_STEP
	if step != 0:
		_scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()
