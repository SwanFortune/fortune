## Credits and build information.
##
## Reachable from HOW TO PLAY rather than from the main menu directly: the menu
## is already eight entries long, and someone looking for the version number is
## looking for information about the game, which is where the rules are.
##
## The content is Version.credits() — a fact list assembled from the repository
## and from what actually loaded, so a modded build credits its packs and a
## half-finished locale is credited at its real percentage.
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

const COLUMN_WIDTH := 780
const SCROLL_STEP := 60

var _return_scene: String = "res://scenes/HowToPlay.tscn"
var _scroll: ScrollContainer


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_WALL)
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var outer := UIKit.vbox(12)
	m.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("CREDITS"), 26, UIKit.GOLD))
	outer.add_child(UIKit.block(Version.full(), 12, UIKit.DIM))

	_scroll = UIKit.scroll()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var v := UIKit.vbox(6)
	v.custom_minimum_size.x = COLUMN_WIDTH
	_scroll.add_child(v)
	# The same renderer as the rules screen: both are headed lists of lines, and
	# two of them would drift apart the first time one was restyled.
	var HowToPlay = load("res://scenes/HowToPlay.gd")
	HowToPlay.render_sections(v, Version.credits())

	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	outer.add_child(actions)
	UIKit.focus_first(self)


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
