## The rules, in one place a player can actually reach.
##
## The game explained itself nowhere. What explanation existed lived in hover
## tooltips — which are unreachable on a gamepad, invisible to anyone who does
## not think to hover, and gone the moment you move the mouse. So a player
## opening this cold had no way to learn what composure is, why the ORDER of
## the cards is the entire game, or what a sign's denial does to them.
##
## MOST OF THIS IS NOT NEW PROSE. The glossary is `UIKit.KEYS`, which the
## author wrote and the locale already translates; the elements come from
## elements.json; the controls are read live off the InputMap, so a rebind
## shows here immediately. Only the four sections describing the loop are
## written for this screen, and they are a paraphrase of the prototype's own
## rules reference (`handoffRules()` in Parlour v23.dc.html, "The loop" and
## "Resolving one reading") aimed at a player rather than at a porter.
##
## Building it from live data is the point: a screen that explains the game by
## restating it in its own words would be wrong the first time a number
## changed, and nothing would notice. tests/test_scenes.gd checks that the
## element wheel this screen draws matches the one Rules actually uses.
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## A comfortable measure for prose. The rest of the game is columns and lists
## that want the whole window; this is the only screen that is paragraphs, and
## a paragraph 1900px wide is one your eye loses its place in.
const COLUMN_WIDTH := 780

## How far one press of up/down moves the page. See _unhandled_input.
const SCROLL_STEP := 60

var _return_scene: String = "res://scenes/MainMenu.tscn"
var _scroll: ScrollContainer


func _ready() -> void:
	if Nav.help_return_scene != "":
		_return_scene = Nav.help_return_scene
	var root := UIKit.root_control(Table.VIEW_WALL)
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var outer := UIKit.vbox(12)
	m.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("HOW TO PLAY"), 26, UIKit.GOLD))

	_scroll = UIKit.scroll()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var v := UIKit.vbox(6)
	v.custom_minimum_size.x = COLUMN_WIDTH
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scroll.add_child(v)
	build_into(v)

	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	actions.add_child(UIKit.button(I18n.t("CREDITS"), func():
		get_tree().change_scene_to_file("res://scenes/Credits.tscn")
	))
	outer.add_child(actions)
	UIKit.focus_first(self)


## Fills `v` with the whole explanation. Shared with the in-run overlay
## (RunHeader), so the rules a player reads mid-reading cannot drift from the
## ones on the menu — they are the same function.
static func build_into(v: VBoxContainer) -> void:
	render_sections(v, sections())


## Renders [heading, [lines]] pairs. Shared with the credits screen, which is
## the same shape of document.
static func render_sections(v: VBoxContainer, list: Array) -> void:
	for section in list:
		var sp := Control.new()
		sp.custom_minimum_size.y = 10
		v.add_child(sp)
		v.add_child(UIKit.block(str(section[0]), 13, UIKit.GOLD))
		for line in section[1]:
			v.add_child(UIKit.block(str(line), 13, UIKit.INK if str(line).begins_with("·") else UIKit.DIM))


## [heading, [lines]] pairs. Assembled from live content wherever the game
## already has the words.
static func sections() -> Array:
	return [
		[I18n.t("THE NIGHT"), [
			I18n.t("Someone knocks. They have a job, a sign, and something they will not say. Their composure starts at nothing, and you have to fill it before your readings with them run out — then they go home whole."),
			I18n.t("Eight knocks a night, three nights. The last one on the third night is the mayor, and he is not like the others."),
			I18n.t("Between knocks you take a road: another sitter, the apothecary, or whatever the evening puts in front of you."),
		]],
		[I18n.t("ONE READING"), [
			I18n.t("You draw a hand. You lay cards left to right, spending energy, and then you READ IT — they are spoken as one sentence, in the order you laid them."),
			I18n.t("THE ORDER IS THE WHOLE GAME. Most cards pay attention to what came before them, and a card laid in the wrong place is worth a fraction of the same card laid in the right one."),
			I18n.t("Energy comes back in full every reading. Your hand does not: whatever is left is discarded and you draw fresh."),
		]],
		[I18n.t("THE WHEEL"), _wheel_lines()],
		[I18n.t("WHAT THEY WILL NOT SAY"), [
			I18n.t("Every sitter carries their sign's denial — one named thing it does to every reading you give them. Some of them hold off the first points of anything you say, like a wall; some cut a reading in half; some refuse to hear the same sign twice."),
			I18n.t("It is written under their name before you start. Read it first: it is usually the difference between a good deck and a good night."),
			I18n.t("A card that PIERCES ignores denial entirely."),
		]],
		[I18n.t("THE WORDS ON A CARD"), _glossary_lines()],
		[I18n.t("THE FOUR ELEMENTS"), _element_lines()],
		[I18n.t("CONTROLS"), _control_lines()],
	]


## The element wheel, drawn from the ring the engine actually uses rather than
## from a sentence somebody typed once. Content.ring is the same array
## Rules.link_of() walks.
static func _wheel_lines() -> Array:
	var ring: Array = Content.ring
	if ring.is_empty():
		return [I18n.t("The elements run in a ring.")]
	var names: Array = []
	for el in ring:
		names.append(UIKit.el_tag(str(el)))
	var loop: String = " → ".join(names) + " → " + str(names[0])
	return [
		I18n.t("The elements run in a ring, and each card's place on it is measured against the card before:"),
		"· " + loop,
		I18n.t("Following the ring forward is a TURN. Saying the same element again is SAME. Going backwards is BACK, and jumping across is a BREAK."),
		I18n.t("A card that reads \"+4 more if it follows △\" wants the card before it to have carried that element. That is what you are arranging when you decide the order."),
		I18n.t("A card matching the sitter's own element is always worth a little more."),
	]


## The glossary the game already had, shown in full instead of only on hover.
## KEYS is authored text and is already in the locale file.
static func _glossary_lines() -> Array:
	var out: Array = []
	for key in UIKit.KEYS:
		out.append("· " + I18n.t(str(UIKit.KEYS[key])))
	return out


static func _element_lines() -> Array:
	var out: Array = []
	for el in Content.ring:
		var rec: Dictionary = Content.elements.get(el, {})
		out.append("· %s — %s" % [UIKit.el_tag(str(el)), I18n.element_field(str(el), "gives")])
		var body := I18n.element_field(str(el), "body")
		if body != "":
			out.append("    " + body)
	return out


## Read off the live InputMap, so a rebind is reflected here at once and this
## cannot become a list of keys the game no longer uses.
static func _control_lines() -> Array:
	var out: Array = [
		I18n.t("Playable entirely from the keyboard or a gamepad: the arrow keys, Tab or the stick move the highlight, and Confirm activates whatever is lit."),
	]
	for entry in Settings.ACTIONS:
		var pad := Settings.pad_label(str(entry[0]))
		var keys := Settings.key_label(str(entry[0]))
		out.append("· %s — %s%s" % [I18n.t(str(entry[1])), keys, ("  /  " + pad) if pad != "" else ""])
	out.append(I18n.t("Any of these can be changed in SETTINGS → CONTROLS."))
	return out


func _back() -> void:
	Nav.help_return_scene = ""
	get_tree().change_scene_to_file(_return_scene)


## The page has to scroll from a gamepad, and a ScrollContainer does not do
## that for you: it scrolls on the mouse wheel and on a drag, and moves itself
## only to keep a FOCUSED child visible. This screen has no focusable children
## at all — it is paragraphs — so on a controller it showed the first screenful
## and nothing else, which for a rules screen is most of the rules missing.
##
## Handled here rather than by making the container focusable, because that
## would put a focus ring on a block of text and still not scroll it.
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
	elif event.is_action_pressed("ui_page_down", true):
		step = int(_scroll.size.y * 0.9)
	elif event.is_action_pressed("ui_page_up", true):
		step = -int(_scroll.size.y * 0.9)
	if step != 0:
		_scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()
