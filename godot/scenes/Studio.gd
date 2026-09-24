## THE STUDIO — where whoever draws and animates for the game sees their work IN
## it, as they make it, without a line of code and without restarting.
##
## Reached from the credits (STUDIO, beside BACK) and straight from the command
## line: `godot --path godot -- --studio`. Three panes:
##
##   MOMENTS        every moment in Feel.EVENTS as a button, played on a real
##                  card you can step through all fifty-six of, with the preset
##                  it is using printed beside it;
##   CARDS IN HAND  every card_states rule on a card it matches — rules that are
##                  switched off included, so they can be judged before anyone
##                  decides to switch them on;
##   ART            every asset the game will ever ask for, as it looks now —
##                  drawn, animated or still a gap — with the exact file name
##                  to save it as. Pressing a tile copies that path.
##
## THE FILES ARE WATCHED. data/base/, assets/art/, assets/particles/ and the
## player's mod folder are looked at a few times a second, and anything that
## changes reloads the content and redraws the pane: save a PNG or a tweak to
## feel.json and look. SLOW MOTION runs everything at a quarter speed, and
## REPEAT plays the last moment over and over while you tune it. MAKE TEMPLATES
## writes blank sheets at the sizes the game wants into a folder and opens it.
##
## Not a player's screen, and deliberately not on the main menu: it is found
## where the art is credited.
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## How often the watched folders are looked at, and how often REPEAT fires.
const WATCH_EVERY := 0.75
const REPEAT_EVERY := 1.4
## SLOW MOTION's speed.
const SLOW := 0.25

## Where a change means "reload". The mod folder is here because a drawing
## delivered as a pack, and not into the repository, has to be seen too.
const WATCHED := ["res://data/base/", "res://assets/art/", "res://assets/particles/", "user://mods/"]

## Where MAKE TEMPLATES writes. user:// because an exported build cannot write
## into itself, and this is the one folder every build can open.
const TEMPLATES := "user://studio_templates"

var _pane := "moments"
var _art_kind := "card"
var _card_i := 0
var _last_event := ""
var _slow := false
var _repeat := false
var _mtimes := {}

var _body: VBoxContainer
var _toast: Label
var _stage: Control
var _holder: CenterContainer
var _card_name: Label
var _grid: HFlowContainer
var _preset_text: Label
var _slow_btn: Button
var _repeat_btn: Button
var _repeat_timer: Timer


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_TABLE)
	add_child(root)
	var m := UIKit.margin(28)
	root.add_child(m)
	var outer := UIKit.vbox(10)
	m.add_child(outer)

	outer.add_child(UIKit.block(I18n.t("STUDIO"), 26, UIKit.GOLD))
	outer.add_child(UIKit.block(I18n.t(
		"The game's drawings and animations, live. Save a file and it appears here — no restart. Everything is explained in docs/ATELIER.md."
	), 12, UIKit.DIM))

	var tabs := UIKit.hbox(8)
	tabs.add_child(UIKit.button(I18n.t("MOMENTS"), _show.bind("moments")))
	tabs.add_child(UIKit.button(I18n.t("CARDS IN HAND"), _show.bind("hand")))
	tabs.add_child(UIKit.button(I18n.t("ART"), _show.bind("art")))
	_slow_btn = UIKit.button("", _toggle_slow)
	tabs.add_child(_slow_btn)
	_repeat_btn = UIKit.button("", _toggle_repeat)
	tabs.add_child(_repeat_btn)
	tabs.add_child(UIKit.button(I18n.t("MAKE TEMPLATES"), _templates))
	tabs.add_child(UIKit.button(I18n.t("BACK"), _back))
	outer.add_child(tabs)
	_label_toggles()

	_toast = UIKit.label("", 12, UIKit.GREEN)
	outer.add_child(_toast)

	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_body = UIKit.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	var watch := Timer.new()
	watch.wait_time = WATCH_EVERY
	watch.autostart = true
	watch.timeout.connect(_look_for_changes)
	add_child(watch)
	_repeat_timer = Timer.new()
	_repeat_timer.wait_time = REPEAT_EVERY
	_repeat_timer.timeout.connect(_fire)
	add_child(_repeat_timer)

	_mtimes = snapshot()
	_show(_pane)
	UIKit.focus_first(self)


func _exit_tree() -> void:
	# Slow motion is the engine's clock, not this screen's: leaving it on would
	# play the rest of the game at a quarter speed.
	Engine.time_scale = 1.0


# ── the panes ────────────────────────────────────────────────────────────

func _show(pane: String) -> void:
	_pane = pane
	for c in _body.get_children():
		c.queue_free()
	_stage = null
	_preset_text = null
	match pane:
		"hand":
			_pane_hand()
		"art":
			_pane_art()
		_:
			_pane_moments()


func _pane_moments() -> void:
	var row := UIKit.hbox(24)
	_body.add_child(row)

	var list := UIKit.vbox(4)
	for event in Feel.EVENTS:
		var b := UIKit.button(event, _play.bind(event))
		b.tooltip_text = str(Feel.EVENTS[event])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	row.add_child(list)

	var right := UIKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var chooser := UIKit.hbox(8)
	chooser.add_child(UIKit.button("◀", _step_card.bind(-1)))
	chooser.add_child(UIKit.button("▶", _step_card.bind(1)))
	_card_name = UIKit.label("", 13, UIKit.INK)
	chooser.add_child(_card_name)
	right.add_child(chooser)

	_holder = CenterContainer.new()
	_holder.custom_minimum_size = Vector2(0, 260)
	right.add_child(_holder)
	_put_card()

	_preset_text = UIKit.block(I18n.t("Press a moment to play it on this card."), 11, UIKit.DIM)
	right.add_child(_preset_text)
	if _last_event != "":
		_describe(_last_event)


func _pane_hand() -> void:
	_body.add_child(UIKit.block(I18n.t(
		"Each rule in card_states, on a card it matches. A rule switched off in feel.json is shown anyway, so it can be judged before it is switched on."
	), 12, UIKit.DIM))
	var cards := _all_cards()
	for rule in Content.card_states:
		var row := UIKit.hbox(20)
		# In the tree BEFORE the card is dressed: Feel ignores a node that is
		# not in the tree yet, which is right in the game and was wrong here.
		_body.add_child(row)
		var when: Dictionary = rule.get("when", {})
		var ctx := _ctx_for(when)
		var sample := {}
		for c in cards:
			if Feel.matches(when, c, ctx):
				sample = c
				break
		var text := "%s\n%s" % [str(rule.get("id", "?")), JSON.stringify(when)]
		if bool(rule.get("off", false)):
			text += "\n" + I18n.t("(switched off in feel.json)")
		if sample.is_empty():
			text += "\n" + I18n.t("(no card matches this rule)")
		var words := UIKit.block(text, 12, UIKit.INK)
		words.custom_minimum_size.x = 320
		row.add_child(words)
		if not sample.is_empty():
			var face := UIKit.card_face(sample, func(): pass, true, false)
			row.add_child(face)
			Feel.dress_with(face, rule, sample, ctx)


func _pane_art() -> void:
	var counts := {}
	var animated := 0
	for id in Art.manifest:
		var st := str(Art.manifest[id].get("status", Art.UNDELIVERED))
		counts[st] = int(counts.get(st, 0)) + 1
		if Art.texture(str(id)) is AnimatedTexture:
			animated += 1
	_body.add_child(UIKit.block(I18n.t("%d assets: %d drawn, %d in progress, %d animated. Press a tile to copy the file name it wants.")
		% [Art.manifest.size(), int(counts.get("final", 0)), int(counts.get("wip", 0)), animated], 12, UIKit.DIM))
	var kinds := UIKit.hbox(8)
	kinds.add_child(UIKit.button(I18n.t("CARDS"), _fill_grid.bind("card")))
	kinds.add_child(UIKit.button(I18n.t("SITTERS"), _fill_grid.bind("sitter")))
	kinds.add_child(UIKit.button(I18n.t("READERS"), _fill_grid.bind("reader")))
	_body.add_child(kinds)

	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(_grid)
	_fill_grid(_art_kind)


## Only the tiles are rebuilt, for the reason _step_card() gives.
func _fill_grid(kind: String) -> void:
	_art_kind = kind
	for c in _grid.get_children():
		c.queue_free()
	var ids: Array = Art.manifest.keys().filter(func(i): return str(Art.manifest[i].get("kind", "")) == kind)
	ids.sort()
	for id in ids:
		_grid.add_child(_tile(str(id)))


## One asset: how it looks now, what it is, where to save it. A Button so it
## takes focus and a press, with everything inside it ignoring the pointer.
func _tile(id: String) -> Control:
	var entry: Dictionary = Art.manifest[id]
	var portrait := str(entry.get("kind", "")) != "card"
	var picture := Vector2(96, 128) if portrait else Vector2(128, 96)
	var b := Button.new()
	UIKit.style_button(b)
	b.custom_minimum_size = Vector2(picture.x + 24, picture.y + 70)
	b.tooltip_text = expected_file(id)
	b.pressed.connect(_copy_path.bind(id))
	var v := UIKit.vbox(3)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var tex := Art.texture(id)
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.custom_minimum_size = picture
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pic)
	else:
		var gap := ColorRect.new()
		gap.color = Color(UIKit.DIM, 0.15)
		gap.custom_minimum_size = picture
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(gap)
	var name_l := UIKit.label(str(entry.get("display", id)).left(22), 10, UIKit.INK)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var st := str(entry.get("status", Art.UNDELIVERED))
	var note: String = {"final": I18n.t("drawn"), "wip": I18n.t("in progress")}.get(st, I18n.t("not drawn yet"))
	if tex is AnimatedTexture:
		note += " · " + I18n.t("%d frames") % tex.frames
	var st_l := UIKit.label(note, 10, {"final": UIKit.GREEN, "wip": UIKit.GOLD}.get(st, UIKit.DIM))
	st_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(st_l)
	return b


# ── actions ──────────────────────────────────────────────────────────────

func _play(event: String) -> void:
	_last_event = event
	_fire()
	_describe(event)


func _fire() -> void:
	if _last_event == "" or _stage == null or not is_instance_valid(_stage):
		return
	var cards := _all_cards()
	var card: Dictionary = cards[_card_i % cards.size()] if not cards.is_empty() else {}
	Feel.play(_last_event, _stage, {"el": str(card.get("el", "")) if card.get("el") != null else ""})
	Audio.play(_audio_for(_last_event))


## What the moment is made of, from the registry, so the numbers being tuned
## are on screen next to what they do.
func _describe(event: String) -> void:
	if _preset_text == null or not is_instance_valid(_preset_text):
		return
	var rec: Dictionary = Content.feel.get(event, {})
	var lines: Array = ["%s — %s" % [event, Feel.EVENTS.get(event, "")], JSON.stringify(rec)]
	for pair in [["particles", Content.particles], ["motion", Content.motions], ["haptic", Content.haptics]]:
		var name := str(rec.get(pair[0], ""))
		if name != "":
			var pre = pair[1].get(name, {})
			lines.append("%s \"%s\": %s" % [pair[0], name, JSON.stringify(pre)])
	_preset_text.text = "\n".join(lines)


## Steps through the cards WITHOUT rebuilding the pane: the ◀ ▶ that asked
## would be freed inside its own signal, and a keyboard player would lose their
## place (see CLAUDE.md). Only the card and its name are replaced.
## The sound that goes with a moment in the game, so what is tuned here is
## judged with it. Most moments share the audio event's name.
func _audio_for(event: String) -> String:
	return {"card_link_same": "card_lay", "card_link_turn": "card_lay", "card_pierce": "card_lay",
		"card_bank": "coin", "card_exhaust": "card_discard", "wall_absorb": "card_discard"}.get(event, event)


func _step_card(by: int) -> void:
	var n := _all_cards().size()
	_card_i = posmod(_card_i + by, maxi(1, n))
	_put_card()


func _put_card() -> void:
	var cards := _all_cards()
	var card: Dictionary = cards[_card_i % cards.size()] if not cards.is_empty() else {}
	_card_name.text = "%s  (%d / %d)" % [I18n.card_name(card), _card_i % maxi(1, cards.size()) + 1, cards.size()]
	for c in _holder.get_children():
		c.queue_free()
	_stage = UIKit.card_face(card, func(): pass, true, false)
	_holder.add_child(_stage)
	Feel.dress_card(_stage, card, {"affordable": true})


func _toggle_slow() -> void:
	_slow = not _slow
	Engine.time_scale = SLOW if _slow else 1.0
	_label_toggles()


func _toggle_repeat() -> void:
	_repeat = not _repeat
	if _repeat:
		_repeat_timer.start()
	else:
		_repeat_timer.stop()
	_label_toggles()


func _label_toggles() -> void:
	_slow_btn.text = I18n.t("SLOW MOTION: ON") if _slow else I18n.t("SLOW MOTION: OFF")
	_repeat_btn.text = I18n.t("REPEAT: ON") if _repeat else I18n.t("REPEAT: OFF")


func _copy_path(id: String) -> void:
	DisplayServer.clipboard_set(expected_file(id))
	_say(I18n.t("Copied: %s") % expected_file(id))


func _templates() -> void:
	var made := make_templates(TEMPLATES)
	var where := ProjectSettings.globalize_path(TEMPLATES)
	_say(I18n.t("%d templates written to %s") % [made.size(), where])
	if DisplayServer.get_name() != "headless":
		OS.shell_open(where)


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/Credits.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _say(text: String) -> void:
	if is_instance_valid(_toast):
		_toast.text = text


# ── watching the files ───────────────────────────────────────────────────

func _look_for_changes() -> void:
	var now := snapshot()
	var changed := changed_files(_mtimes, now)
	_mtimes = now
	if changed.is_empty():
		return
	Content.reload()
	_show(_pane)
	_say(I18n.t("Reloaded: %s") % ", ".join(changed.slice(0, 3)))


## Every watched file and when it last changed. The .import files Godot writes
## beside a drawing are left out: they change when the editor re-imports, which
## is not something anyone did.
static func snapshot() -> Dictionary:
	var out := {}
	for dir in WATCHED:
		_walk(dir, out)
	return out


static func _walk(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full, out)
		elif not name.ends_with(".import") and not name.begins_with("."):
			out[full] = FileAccess.get_modified_time(full)
		name = d.get_next()
	d.list_dir_end()


## The files that appeared, changed or went, by name.
static func changed_files(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for f in after:
		if not before.has(f) or before[f] != after[f]:
			out.append(str(f).get_file())
	for f in before:
		if not after.has(f):
			out.append(str(f).get_file())
	return out


# ── templates ────────────────────────────────────────────────────────────

## Blank sheets at exactly the sizes the game asks for, with the cells of a
## sprite sheet ruled in, so nobody has to do the arithmetic. The art sizes are
## read from the manifest's own spec rather than written here a second time.
## Returns the files written.
static func make_templates(dir: String) -> Array[String]:
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Array[String] = []
	for block_name in Art.spec:
		var block = Art.spec[block_name]
		if not (block is Dictionary) or not block.has("pixels"):
			continue
		var wh: PackedStringArray = str(block["pixels"]).split("x")
		if wh.size() != 2:
			continue
		var w := int(wh[0])
		var h := int(wh[1])
		# Named for the spec block — "card", "portrait" — since a portrait
		# template is for readers as much as sitters.
		var kind := str(block_name).trim_suffix("_art")
		out.append(_sheet(dir, "%s_%dx%d.png" % [kind, w, h], w, h, 1, 1))
		out.append(_sheet(dir, "%s_sheet_4x2_%dx%d.png" % [kind, w * 4, h * 2], w * 4, h * 2, 4, 2))
	out.append(_sheet(dir, "particle_64x64.png", 64, 64, 1, 1))
	out.append(_sheet(dir, "particle_sheet_4x2_256x128.png", 256, 128, 4, 2))
	return out


static func _sheet(dir: String, file: String, w: int, h: int, cols: int, rows: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var line := Color(0.8, 0.2, 0.6, 0.8)
	for c in cols + 1:
		var x := mini(c * w / cols, w - 1)
		for y in h:
			img.set_pixel(x, y, line)
	for r in rows + 1:
		var y := mini(r * h / rows, h - 1)
		for x in w:
			img.set_pixel(x, y, line)
	var path := dir.path_join(file)
	img.save_png(path)
	return path


# ── small things ─────────────────────────────────────────────────────────

## Where the game looks for an asset, as a path an artist can type: the
## manifest's own `file` if it has one, otherwise assets/art/<id>.png.
static func expected_file(id: String) -> String:
	var f := str(Art.manifest.get(id, {}).get("file", ""))
	if f != "":
		return f.trim_prefix("res://")
	return "assets/art/%s.png" % id


func _all_cards() -> Array:
	return Content.cards_basics + Content.cards_chroma + Content.cards_minor + Content.cards_arcana


## The context a rule's `when` asks about, made up so that it holds — so a rule
## about "a card that would continue the line" can be shown on any card.
func _ctx_for(when: Dictionary) -> Dictionary:
	var ctx := {"affordable": true}
	for field in ["affordable", "link"]:
		if when.has(field):
			var v = when[field]
			ctx[field] = v[0] if v is Array and not v.is_empty() else v
	return ctx
