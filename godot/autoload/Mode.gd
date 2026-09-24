## Autoload. Which of the game's two faces is showing.
##
##   PLAY  what a player is handed: the game, and nothing about how it is made.
##   WORK  the same game with the workshop open — the studio, the Library, the
##         mods, the build's own facts, the prototype's knobs.
##
## Nothing about the GAME differs between them. A card plays the same in both;
## only what the screens offer and say changes. Screens ask is_work() while
## they build, and F12 rebuilds the one on screen in the other view, so the
## person making the game can flip between "what I work in" and "what a player
## sees" without leaving the moment they are looking at.
##
## HOW THE WORK VIEW IS REACHED, from least to most hidden:
##   - running from the Godot editor (the project, not an exported build): it is
##     where the game is made, so the workshop is open by default;
##   - `godot --path godot -- --studio` (or `--work`), and `-- --play` for the
##     other way;
##   - in a build handed to someone, dialling 3615 ATEL on the in-game Minitel,
##     which fits the house: the one machine in the room that answers codes.
## Once reached on a machine it stays reachable there (user://work_view.cfg),
## and F12 flips between the two. A player who never dials the code never sees
## a sign of any of it — no key does anything, no tag is drawn.
extends Node

signal changed(work: bool)

const CFG := "user://work_view.cfg"
const TOGGLE_KEY := KEY_F12

## Whether this machine may show the work view at all.
var unlocked := false
## Which view is chosen, when it may be shown.
var work := false

var _tag: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var from_source := OS.has_feature("editor")
	var chosen := _load()
	if from_source or args.has("--studio") or args.has("--work"):
		unlocked = true
	if args.has("--studio") or args.has("--work"):
		work = true
	elif args.has("--play"):
		work = false
	elif from_source and not chosen:
		work = true
	_build_tag()


## THE ONE QUESTION every screen asks.
func is_work() -> bool:
	return unlocked and work


## Opens the workshop on this machine and switches to it. What the Minitel code
## does.
func unlock() -> void:
	unlocked = true
	set_work(true)


func set_work(on: bool) -> void:
	if on and not unlocked:
		return
	work = on
	_save()
	_update_tag()
	changed.emit(is_work())


## F12: the other view, and the screen on show rebuilt in it.
func toggle() -> void:
	set_work(not work)
	var tree := get_tree()
	if tree.current_scene != null:
		tree.reload_current_scene.call_deferred()


func _input(event: InputEvent) -> void:
	if not unlocked:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


## Returns whether a choice had been saved, so a fresh machine running from
## source can default to the work view without overriding a choice made since.
func _load() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) != OK:
		return false
	unlocked = bool(cfg.get_value("view", "unlocked", false))
	work = bool(cfg.get_value("view", "work", false))
	return cfg.has_section_key("view", "work")


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("view", "unlocked", unlocked)
	cfg.set_value("view", "work", work)
	cfg.save(CFG)


## A small word in the corner while the work view is up, so nobody mistakes it
## for what a player sees. Nothing at all in the play view.
func _build_tag() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_tag = Label.new()
	_tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tag.offset_right = -10
	_tag.offset_bottom = -6
	_tag.add_theme_font_size_override("font_size", 11)
	_tag.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 0.75))
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_tag)
	_update_tag()


func _update_tag() -> void:
	if _tag == null:
		return
	_tag.visible = is_work()
	_tag.text = I18n.t("WORK VIEW · F12 for what a player sees")
