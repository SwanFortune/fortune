extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_WALL)
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	# A HEADING AND A WAY BACK, on the same line. This screen had neither a run
	# header nor an exit: pressing BEGIN on the menu — by accident or to see what
	# was here — left a player on a screen whose only move was forward into a run.
	# Nothing is lost by going back; the run is not made until a reader is picked.
	var top := UIKit.hbox(14)
	var heading := UIKit.block(I18n.t("CHOOSE YOUR SIGN"), 26, UIKit.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var back := UIKit.button(I18n.t("BACK"), func(): Nav.goto_main_menu())
	back.add_to_group(UIKit.WAY_OUT)
	top.add_child(back)
	v.add_child(top)
	v.add_child(UIKit.block(I18n.t("Every reader is a sign, an element, and a starting deck of ten."), 13, UIKit.DIM))
	v.add_child(_before_you_start())

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 420)
	var list := UIKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for i in Content.readers.size():
		var r: Dictionary = Content.readers[i]
		var el_c := UIKit.el_color(r["el"])
		# A reader may be locked behind a condition (readers.json's `unlock`).
		# No base reader is; a pack can be. A locked one is shown rather than
		# hidden, with what it wants — a reader you cannot see is not a goal.
		var locked: bool = Profile.reader_locked(r)
		var lines := [
			["%s — %s" % [I18n.reader_field(r, "name"), I18n.reader_field(r, "sign")], 16,
				UIKit.DIM if locked else UIKit.INK],
			[I18n.reader_field(r, "line"), 12, UIKit.DIM],
			[I18n.reader_field(r, "rule"), 12, UIKit.DIM if locked else el_c],
			["%s %s" % [I18n.t("Starts with:"), ", ".join(r.get("deck", []))], 11, UIKit.DIM],
		]
		if locked:
			lines.append(["%s %s" % [I18n.t("LOCKED —"), Profile.unlock_text(r.get("unlock", null))], 12, UIKit.GOLD])
		list.add_child(UIKit.panel_button(lines, _pick.bind(i), not locked, "", _sigil(r, locked)))
	# The LIST, not the screen. What this screen is for is choosing a reader, and
	# focus_first takes the first focusable thing in tree order — which, since
	# BACK was added at the top, would otherwise be the way out.
	UIKit.focus_first(list)


## The two things that are decided before a run rather than during it: how hard
## it will be, and which evening it will be.
##
## Both here rather than in Settings, because neither is a preference — they are
## part of the run, they are written into the save, and changing them means
## starting again. A difficulty buried in an options menu is one nobody finds.
var _seed_field: LineEdit
var _level := 0

func _before_you_start() -> Control:
	var box := UIKit.vbox(8)

	# THE LADDER. A run is three nights and sixteen knocks, and once you have
	# finished it there is nothing further to reach for — the shortage every
	# roguelike solves the same way. Levels are cumulative and unlock by runs
	# FINISHED, won or lost, because losing a run teaches you as much.
	var rungs: Array = Content.difficulty
	if rungs.size() > 1:
		_level = clampi(int(Profile.get_stat("best_level")), 0, rungs.size() - 1)
		while _level > 0 and not Run.level_open(rungs[_level]):
			_level -= 1
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label(I18n.t("HOW HARD"), 11, UIKit.GOLD))
		var what := UIKit.label("", 12, UIKit.INK)
		what.custom_minimum_size.x = 300 * UIKit.text_scale
		what.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var explain := UIKit.block("", 11, UIKit.DIM)
		var show := func() -> void:
			var rung: Dictionary = rungs[_level]
			var open: bool = Run.level_open(rung)
			what.text = "%d · %s" % [_level, I18n.t(str(rung.get("name", "")))]
			what.add_theme_color_override("font_color", UIKit.INK if open else UIKit.DIM)
			explain.text = I18n.t(str(rung.get("text", ""))) if open else \
				I18n.t("LOCKED — finish %d run(s) to reach this.") % int(rung.get("unlock_at", 0))
			explain.add_theme_color_override("font_color", UIKit.DIM if open else UIKit.GOLD)
		var down := UIKit.button("−", func():
			_level = clampi(_level - 1, 0, rungs.size() - 1)
			show.call()
		)
		var up := UIKit.button("+", func():
			_level = clampi(_level + 1, 0, rungs.size() - 1)
			show.call()
		)
		for b: Button in [down, up]:
			b.custom_minimum_size.x = 44
		row.add_child(down)
		row.add_child(what)
		row.add_child(up)
		box.add_child(row)
		box.add_child(explain)
		show.call()

	# THE SEED. Every roll a run makes comes out of it, so this box is the
	# whole run: hand it to somebody else and they play the same three nights.
	var seed_row := UIKit.hbox(10)
	# "WHICH EVENING", not "THE EVENING". The agenda down the left of the map is
	# headed THE EVENING, and so was this box, and so were two different sections
	# of the How To Play screen — one about the clock, one about the seed. The
	# seed is not the evening; it is which of all possible evenings you get.
	seed_row.add_child(UIKit.label(I18n.t("WHICH EVENING"), 11, UIKit.GOLD))
	_seed_field = LineEdit.new()
	UIKit.style_field(_seed_field)
	# Short enough to actually fit the box. The old placeholder ran off the end
	# of the field — "leave empty for whichever one turns" — which is a worse
	# sentence than the one it was trying to be, and looked like a bug.
	_seed_field.placeholder_text = I18n.t("leave empty for a new one")
	_seed_field.custom_minimum_size.x = 300 * UIKit.text_scale
	seed_row.add_child(_seed_field)
	box.add_child(seed_row)
	return box


## The reader's own sigil: their zodiac sign over their ruling planet, both
## drawn from the prototype's line art (SIGN_ART / PLANET_ART).
##
## The source colours the sign in the reader's element, EXCEPT the thirteenth —
## Serpentarius is `wild`, belongs to no element, and is drawn in gold. That is
## a rule in the data (`wild`), not a special case here: any reader a pack marks
## wild gets the same treatment.
func _sigil(r: Dictionary, locked: bool) -> Control:
	var tint: Color = UIKit.GOLD if bool(r.get("wild", false)) else UIKit.el_color(str(r.get("el", "")))
	if locked:
		tint = Color(tint, 0.4)
	var col := UIKit.vbox(4)
	col.custom_minimum_size.x = 52
	# THE READER'S OWN FACE, when there is one. The art manifest has asked for
	# thirteen of these since it was written and no screen had ever displayed
	# one — an artist could have drawn every reader in the game and never seen
	# a single one of them in it. Half height: this is a row in a list, not the
	# reading screen, and the sigil below still carries the sign and the planet.
	var face := Art.reader_texture(r)
	if face != null:
		var port := UIKit.sitter_portrait_art(str(r.get("el", "")), 0.0, face)
		# The column's own width, in the portrait's 3:4. Anything taller makes a
		# row with art visibly deeper than a row without one, and art lands one
		# reader at a time.
		port.custom_minimum_size = Vector2(52, 52 / UIKit.PORTRAIT_SLOT.x * UIKit.PORTRAIT_SLOT.y)
		if locked:
			port.modulate = Color(1, 1, 1, 0.4)
		col.add_child(port)
	# The sign badge stands in for the face until there is one. Both would be
	# saying the same thing twice — the row's own title already reads "TAURUS".
	var sign_badge := UIKit.icon_badge("sign", str(r.get("k", "")), 46, tint) if face == null else null
	if sign_badge != null:
		col.add_child(sign_badge)
	var planet := str(r.get("planet", ""))
	if planet != "":
		var p := UIKit.icon_badge("planet", planet, 22, Color(UIKit.INK, 0.55 if not locked else 0.3))
		if p != null:
			p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(p)
	return col


func _pick(i: int) -> void:
	# The run is REMADE here, with the seed and the level from the boxes above.
	# The menu already built a fresh state to get this screen on screen; that
	# one was made before the player had said anything about which evening they
	# wanted, so it is not the one they play.
	var rungs: Array = Content.difficulty
	var level: int = _level if (not rungs.is_empty() and Run.level_open(rungs[_level])) else 0
	Run.state = Run.fresh(_seed_field.text if _seed_field != null else "", level)
	Run.pick_reader(i)
	Nav.goto_for_state()
