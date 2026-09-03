## Mods screen — the front door to everything ModLoader/CardEdits/Workshop do.
##
## Until now all of that ran with no interface at all: a player could not see
## which packs were loaded, in what order, or which of them was responsible
## for a load error. Errors were counted on the main menu ("2 content
## warnings") but the messages themselves went to push_warning, so reading them
## meant launching the game from a terminal. That is a fine state for the
## engine work and a bad one for a game that advertises mod support.
##
## Everything here reads from Content.packs, which ModLoader now records during
## discovery, so this screen cannot drift from what actually loaded — it is not
## re-scanning the disk with its own copy of the rules.
extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const UIKit := preload("res://scenes/UIKit.gd")

var _return_scene: String = "res://scenes/MainMenu.tscn"


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var outer := UIKit.vbox(10)
	m.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("MODS"), 26, UIKit.GOLD))
	outer.add_child(UIKit.block(
		I18n.t("Packs load in the order below. A later pack wins where two define the same card, sign or reader."),
		12, UIKit.DIM))

	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_packs_section(v)
	_errors_section(v)
	_where_section(v)
	_workshop_section(v)

	var actions := UIKit.hbox(10)
	actions.add_child(UIKit.button(I18n.t("BACK"), _back))
	actions.add_child(UIKit.button(I18n.t("RELOAD CONTENT"), _reload))
	outer.add_child(actions)
	UIKit.focus_first(self)


# ── the pack list ───────────────────────────────────────────────────────

func _packs_section(v: VBoxContainer) -> void:
	_section(v, I18n.t("LOADED PACKS"))
	if Content.packs.is_empty():
		v.add_child(UIKit.block(I18n.t("No packs found at all — even the base game is missing."), 12, UIKit.RED))
		return
	var order := 0
	for p in Content.packs:
		v.add_child(_pack_row(p, order))
		order += 1


func _pack_row(p: Dictionary, order: int) -> Control:
	var enabled: bool = bool(p.get("enabled", true))
	var is_base: bool = bool(p.get("base", false))
	var accent: Color = UIKit.GOLD if is_base else (UIKit.INK if enabled else UIKit.DIM)

	var title := "%d. %s" % [order + 1, p.get("name", p.get("id", "?"))]
	var version := str(p.get("version", ""))
	if version != "":
		title += "  v" + version

	var lines: Array = [
		[title, 15, accent],
		["%s · %s · %s" % [
			p.get("id", ""),
			I18n.t(_source_label(str(p.get("source", "")))),
			I18n.t("priority %s") % p.get("priority", 0),
		], 11, UIKit.DIM],
	]
	if enabled and int(p.get("records", 0)) > 0:
		lines.append([I18n.t("%s record(s) in %s") % [
			p.get("records", 0), ", ".join(p.get("categories", []))
		], 11, UIKit.DIM])
	elif not enabled:
		lines.append([I18n.t("Switched off — nothing from this pack is loaded."), 11, UIKit.RED])
	var desc := str(p.get("description", ""))
	if desc != "":
		lines.append([desc, 11, UIKit.DIM])
	lines.append([str(p.get("path", "")), 10, UIKit.DIM])

	# The base pack has no toggle on purpose: without it there is no game left
	# to mod, so offering the switch would only offer a way to break things.
	if is_base:
		lines.append([I18n.t("The game's own content. Always loaded, always first."), 11, UIKit.GOLD])
		return UIKit.panel_button(lines, func(): pass, false)

	lines.append([I18n.t("TURN OFF") if enabled else I18n.t("TURN ON"), 12, UIKit.GOLD])
	return UIKit.panel_button(lines, func(): _toggle(str(p.get("id", ""))))


func _source_label(source: String) -> String:
	match source:
		"base": return "shipped with the game"
		"example": return "bundled example"
		"user": return "your mods folder"
		"workshop": return "Steam Workshop"
	return source


func _toggle(id: String) -> void:
	if id == "":
		return
	var disabled: Array = Array(Settings.get_value("disabled_mods")).duplicate()
	if disabled.has(id):
		disabled.erase(id)
	else:
		disabled.append(id)
	Settings.set_value("disabled_mods", disabled)
	_reload()


# ── errors ──────────────────────────────────────────────────────────────

func _errors_section(v: VBoxContainer) -> void:
	_section(v, I18n.t("LOAD MESSAGES"))
	if Content.load_errors.is_empty():
		v.add_child(UIKit.block(I18n.t("Everything loaded cleanly."), 12, UIKit.DIM))
		return
	v.add_child(UIKit.block(
		I18n.t("%s problem(s). A pack that reports one is still loaded — only the offending record is skipped.") % Content.load_errors.size(),
		12, UIKit.RED))
	for e in Content.load_errors:
		v.add_child(UIKit.block("· " + e, 11, UIKit.RED))


# ── where mods go ───────────────────────────────────────────────────────

func _where_section(v: VBoxContainer) -> void:
	_section(v, I18n.t("WHERE TO PUT A MOD"))
	# The absolute path, not the user:// form: this is the one line a player
	# needs to be able to paste into a file manager.
	v.add_child(UIKit.block(ProjectSettings.globalize_path("user://mods/"), 12, UIKit.GOLD))
	v.add_child(UIKit.block(
		I18n.t("One folder per pack, each with a mod.json. Turn a pack off above rather than deleting it if you only want it gone for a while."),
		11, UIKit.DIM))
	var edits := CardEdits.edit_count()
	if edits > 0:
		v.add_child(UIKit.block(
			I18n.t("Your own Library changes are pack \"%s\" above — %s card(s).") % [CardEdits.PACK_ID, edits],
			11, UIKit.GOLD))


# ── workshop ────────────────────────────────────────────────────────────

func _workshop_section(v: VBoxContainer) -> void:
	_section(v, I18n.t("STEAM WORKSHOP"))
	if Workshop.is_available:
		v.add_child(UIKit.block(I18n.t("Connected. Subscribed packs appear in the list above."), 12, UIKit.DIM))
		v.add_child(UIKit.button(I18n.t("REFRESH SUBSCRIPTIONS"), func():
			Workshop.refresh_subscribed_items()
			_reload()
		))
		return
	# Say plainly that this is not wired up rather than showing a button that
	# does nothing — an inert control is worse than an honest sentence.
	v.add_child(UIKit.block(
		I18n.t("Not connected. Workshop needs a Steam App ID and the GodotSteam extension, neither of which this build has — see docs/STEAM_WORKSHOP.md. Until then, share a pack by sharing its folder."),
		11, UIKit.DIM))


# ── plumbing ────────────────────────────────────────────────────────────

func _section(v: VBoxContainer, title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	v.add_child(sp)
	v.add_child(UIKit.block(title, 12, UIKit.GOLD))


## Rebuilding content can change or remove cards a run in progress is holding.
## That is handled — Save re-resolves everything by name on load — but the live
## Run.state in memory is not re-resolved, so a pack switched off mid-run would
## leave stale card dicts in hand. Reload writes the run out and reads it back,
## which puts it through exactly the same re-resolution a restart would.
func _reload() -> void:
	# Art, Audio, I18n and the run in progress all re-sync themselves off
	# Content.reloaded — see its doc comment for why that stopped being the
	# caller's job to remember.
	Content.reload()
	_build()


func _back() -> void:
	get_tree().change_scene_to_file(_return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
