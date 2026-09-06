## The Library — browse every card in the game and edit it.
##
## This is the prototype's CARD TABLE > CARDS tab. Two rules carried over
## from it, because they're what made it work:
##
##  1. Card text is NEVER hand-typed. You edit mechanical fields and the
##     printed text regenerates from them via Rules.auto_text(), so the text
##     and the behaviour cannot disagree. The live preview shows exactly what
##     a player will read.
##  2. Which numeric fields exist is driven by the card_effects registry
##     (data/base/card_effects.json), not hardcoded here — so a mod that adds
##     an effect field gets an editor row for it for free.
##
## Edits persist through CardEdits as a real mod pack; see its doc comment.
extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")

## Flag fields, and the label each gets. Unlike the numeric fields (which
## come from the card_effects registry) these are booleans the engine reads
## directly in Rules.simulate(), so they're enumerated here.
const FLAGS := {
	"pierce": "Pierces denial",
	"exhaust": "Once per sitter",
	"bank": "Restores faith, not composure",
	"wild": "Counts as every element",
	"any": "Reads as their element",
	"chroma": "Counts as your current element",
	"neutral": "No element (basic decency)",
}

var _pool_filter: String = "all"
var _element_filter: String = "all"
var _search: String = ""
var _selected_name: String = ""
var _selected_pool: String = ""

var _list_box: VBoxContainer
var _editor_box: VBoxContainer
var _summary_label: Label


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_WALL)
	add_child(root)
	var m := UIKit.margin(24)
	root.add_child(m)
	var v := UIKit.vbox(8)
	m.add_child(v)

	var head := UIKit.hbox(12)
	var title := UIKit.block(I18n.t("LIBRARY"), 24, UIKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.button(I18n.t("BACK"), _back))
	v.add_child(head)

	_summary_label = UIKit.block("", 11, UIKit.DIM)
	v.add_child(_summary_label)
	_refresh_summary()

	v.add_child(_filter_row())

	var split := UIKit.hbox(16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(split)

	var left := UIKit.scroll()
	left.custom_minimum_size = Vector2(430, 430)
	split.add_child(left)
	_list_box = UIKit.vbox(4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_list_box)

	var right := UIKit.scroll()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(0, 430)
	split.add_child(right)
	_editor_box = UIKit.vbox(6)
	_editor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_editor_box)

	_rebuild_list()
	_rebuild_editor()
	UIKit.focus_first(self)


# ── filters ─────────────────────────────────────────────────────────────

func _filter_row() -> Control:
	var row := UIKit.hbox(8)

	var pool_opt := OptionButton.new()
	UIKit.style_button(pool_opt)
	pool_opt.add_item(I18n.t("All pools"))
	pool_opt.set_item_metadata(0, "all")
	var i := 1
	for pool in CardEdits.POOLS:
		pool_opt.add_item(_pool_label(pool))
		pool_opt.set_item_metadata(i, pool)
		i += 1
	pool_opt.item_selected.connect(func(idx: int):
		_pool_filter = pool_opt.get_item_metadata(idx)
		_rebuild_list()
	)
	row.add_child(pool_opt)

	var el_opt := OptionButton.new()
	UIKit.style_button(el_opt)
	el_opt.add_item(I18n.t("All elements"))
	el_opt.set_item_metadata(0, "all")
	var j := 1
	for el in Content.ring:
		el_opt.add_item(UIKit.el_tag(el))
		el_opt.set_item_metadata(j, el)
		j += 1
	el_opt.add_item(I18n.t("No element"))
	el_opt.set_item_metadata(j, "none")
	el_opt.item_selected.connect(func(idx: int):
		_element_filter = el_opt.get_item_metadata(idx)
		_rebuild_list()
	)
	row.add_child(el_opt)

	var search := LineEdit.new()
	UIKit.style_field(search)
	search.placeholder_text = I18n.t("Search by name…")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t: String):
		_search = t.strip_edges().to_lower()
		_rebuild_list()
	)
	row.add_child(search)

	return row


func _pool_label(pool: String) -> String:
	match pool:
		"cards_basics": return I18n.t("Basics")
		"cards_chroma": return I18n.t("Chromatic")
		"cards_minor": return I18n.t("Minor")
		"cards_arcana": return I18n.t("Arcana")
	return pool


## The card's rarity word, in the player's language.
##
## It was printed straight from the data, so a French library read "Bases ·
## basic" — and it was in no checklist to catch, because the scraper only sees
## literal I18n.t("…") calls and this is a value, not a literal. The keys come
## from the template generator walking the cards themselves, which is also what
## gives a mod's invented rarity a key.
func _rarity(c: Dictionary) -> String:
	var r := str(c.get("r", ""))
	return I18n.t(r) if r != "" else "?"


func _cards_for_pool(pool: String) -> Array:
	return Content.registries.get(pool, [])


func _visible_rows() -> Array:
	var rows: Array = []
	for pool in CardEdits.POOLS:
		if _pool_filter != "all" and _pool_filter != pool:
			continue
		for c in _cards_for_pool(pool):
			var el = c.get("el")
			var el_key: String = str(el) if el != null and el != "" else "none"
			if _element_filter != "all" and _element_filter != el_key:
				continue
			if _search != "" and not str(c.get("n", "")).to_lower().contains(_search):
				continue
			rows.append({"pool": pool, "card": c})
	return rows


# ── list ────────────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var rows := _visible_rows()
	if rows.is_empty():
		_list_box.add_child(UIKit.block(I18n.t("Nothing matches those filters."), 12, UIKit.DIM))
		# The editor keeps whatever was last selected: the filters narrow the
		# LIST, and blanking the card you were working on because you typed a
		# letter in the search box would be its own small betrayal.
		return
	# BEFORE the rows are built, not after: each row is drawn knowing whether it
	# is the selected one, so settling the selection afterwards would leave the
	# accent a rebuild behind — visible as a library that opens with a card in
	# the editor and nothing marked in the list.
	_keep_a_card_selected(rows)
	for r in rows:
		var c: Dictionary = r["card"]
		var pool: String = r["pool"]
		var edited := CardEdits.has_edit(pool, c["n"])
		var el = c.get("el")
		var el_c: Color = UIKit.el_color(el) if el != null and el != "" else UIKit.DIM
		var name_line := "%s%s" % [UIKit.card_summary(c), "   ●" if edited else ""]
		var lines := [
			[name_line, 14, UIKit.GOLD if edited else el_c],
			# Through card_price(), so the Library says a card's two numbers in
			# the same words the reward screen and the hand's tooltip do.
			["%s · %s · %s" % [_pool_label(pool), _rarity(c), UIKit.card_price(c)], 11, UIKit.DIM],
			[UIKit.card_text(c), 11, UIKit.INK],
		]
		# The selected row is lit at its edge. There is always one now, and
		# without a mark on it the list and the editor look like two unrelated
		# halves of a screen — you can read a card's numbers on the right with no
		# way to see which of the sixty rows on the left they belong to.
		var selected := pool == _selected_pool and str(c["n"]) == _selected_name
		# The element's colour where there is one — it says which card is selected
		# and reminds you what it is in the same stroke. The elementless cards
		# (most of the basics) fall back to ink rather than to the dim grey their
		# names are printed in, which at the border's alpha is not a mark at all.
		var sel_c: Color = el_c if el != null and el != "" else UIKit.INK
		var row := UIKit.panel_button(lines, _select.bind(pool, c["n"]), true,
			I18n.t("● marks a card you've changed") if edited else "", null,
			sel_c if selected else Color(0, 0, 0, 0))
		row.set_meta(ROW_KEY, _key(pool, str(c["n"])))
		_list_box.add_child(row)


## Keeps the right-hand half of the screen showing a card.
##
## It opened on "Pick a card on the left to edit it." — one line of grey in six
## hundred pixels of nothing, which is half the screen spent explaining that the
## screen is empty. Worse, it stayed empty every time a filter moved the
## selected card out of the list, so narrowing to a pool you were not looking at
## blanked the editor with no explanation.
##
## So the list always has one card selected: the one you picked if the filters
## still show it, and otherwise the first row. Nothing is written by selecting —
## the editor is a view until a number is changed — so opening onto a real card
## costs nothing and shows a newcomer what the screen is for.
func _keep_a_card_selected(rows: Array) -> void:
	for r in rows:
		if r["pool"] == _selected_pool and r["card"]["n"] == _selected_name:
			return
	_selected_pool = rows[0]["pool"]
	_selected_name = rows[0]["card"]["n"]
	_rebuild_editor()


## Which card a list row stands for, so the row can be found again after the
## list is rebuilt. See _select.
const ROW_KEY := "library_card"


func _key(pool: String, card_name: String) -> String:
	return pool + "|" + card_name


func _select(pool: String, card_name: String) -> void:
	_selected_pool = pool
	_selected_name = card_name
	# The list is rebuilt, not just repainted. The accent on the selected row is
	# baked in when the row is built — make_interactive captures the border
	# colour it was given and restores that on focus_exited, so a colour written
	# onto a live row afterwards survives exactly until the next time focus
	# leaves it. Rebuilding is honest and cheap; the list already rebuilds on
	# every keystroke in the search box.
	_rebuild_list()
	_rebuild_editor()
	_focus_selected_row()


## Puts the keyboard back where it was.
##
## Selecting a card destroys the row that was pressed, and with it the focus —
## which for a mouse player is invisible and for a keyboard player means the
## list stops responding to the arrow keys the moment they choose anything. The
## replacement row for the same card is the right place to land.
##
## The freed rows are still children until the end of the frame, so the ones on
## their way out have to be skipped or focus goes to a node that is about to
## stop existing.
func _focus_selected_row() -> void:
	var want := _key(_selected_pool, _selected_name)
	for row in _list_box.get_children():
		if row.is_queued_for_deletion() or not row.has_meta(ROW_KEY):
			continue
		if str(row.get_meta(ROW_KEY)) == want and row is Control:
			(row as Control).grab_focus()
			return


func _refresh_summary() -> void:
	var n := CardEdits.edit_count()
	if n == 0:
		_summary_label.text = I18n.t("Edit any card's numbers and its printed text regenerates to match. Changes save as a shareable mod pack — nothing here touches the base game files.")
	else:
		_summary_label.text = I18n.t("%d card(s) changed. Saved as a mod pack at %s — that folder is shareable and Workshop-ready as-is.") % [n, CardEdits.pack_path_for_display()]


# ── editor ──────────────────────────────────────────────────────────────

func _selected_card() -> Dictionary:
	if _selected_name == "":
		return {}
	for c in _cards_for_pool(_selected_pool):
		if c["n"] == _selected_name:
			return c
	return {}


func _rebuild_editor() -> void:
	for child in _editor_box.get_children():
		child.queue_free()

	var c := _selected_card()
	if c.is_empty():
		_editor_box.add_child(UIKit.block(I18n.t("Pick a card on the left to edit it."), 13, UIKit.DIM))
		return

	var el = c.get("el")
	var el_c: Color = UIKit.el_color(el) if el != null and el != "" else UIKit.DIM

	# The card as it is actually dealt, beside its numbers. Every other line here
	# describes the card in words; this is the object, at the size and with the
	# art well it has in the hand, so a change to a cost or an element can be
	# seen landing on the thing rather than only read back as a sentence. Shown
	# as an illustration — it takes neither the pointer nor a focus stop, which
	# would otherwise sit between the list and the first spin box.
	var heading := UIKit.hbox(14)
	heading.add_child(UIKit.card_face(c, Callable(), true, false))
	var titles := UIKit.vbox(4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_child(UIKit.block(UIKit.card_summary(c), 20, el_c))
	titles.add_child(UIKit.block("%s · %s%s" % [
		_pool_label(_selected_pool), _rarity(c),
		"  ·  " + I18n.t("CHANGED") if CardEdits.has_edit(_selected_pool, c["n"]) else "",
	], 11, UIKit.GOLD if CardEdits.has_edit(_selected_pool, c["n"]) else UIKit.DIM))
	heading.add_child(titles)
	_editor_box.add_child(heading)

	# Which pack this card came from, when it is not the base game's. The stamp
	# is put on by ModLoader; showing it here answers the question a player with
	# several packs installed actually has — "where did this card come from, and
	# who last changed it?" — which used to need reading JSON by hand.
	var pack := str(c.get("_pack", ""))
	if pack != "" and pack != "parlour.base":
		_editor_box.add_child(UIKit.block(I18n.t("from %s") % pack, 11, UIKit.GOLD))

	# Live preview: exactly the text a player sees, regenerated from the
	# current field values rather than stored separately.
	var preview := UIKit.block(UIKit.card_text(c), 13, UIKit.INK)
	_editor_box.add_child(UIKit.block(I18n.t("READS AS"), 11, UIKit.DIM))
	_editor_box.add_child(preview)
	if c.get("fl", "") != "":
		_editor_box.add_child(UIKit.block(I18n.card_flavor(c), 11, UIKit.DIM))

	_editor_box.add_child(_gap())
	_editor_box.add_child(UIKit.block(I18n.t("CORE"), 11, UIKit.GOLD))
	_editor_box.add_child(_int_row(c, "cost", I18n.t("Energy cost"), 0, 6))
	_editor_box.add_child(_int_row(c, "f", I18n.t("Base restore"), 0, 30))
	_editor_box.add_child(_element_row(c))

	_editor_box.add_child(_gap())
	_editor_box.add_child(UIKit.block(I18n.t("EFFECTS"), 11, UIKit.GOLD))
	_editor_box.add_child(UIKit.block(
		I18n.t("Set a value to 0 to remove that effect from the card entirely."), 11, UIKit.DIM))
	for e in Content.card_effects:
		_editor_box.add_child(_effect_row(c, e))

	_editor_box.add_child(_gap())
	_editor_box.add_child(UIKit.block(I18n.t("FLAGS"), 11, UIKit.GOLD))
	for key in FLAGS:
		_editor_box.add_child(_flag_row(c, key, I18n.t(FLAGS[key])))

	_editor_box.add_child(_gap())
	var actions := UIKit.hbox(8)
	if CardEdits.has_edit(_selected_pool, c["n"]):
		actions.add_child(UIKit.button(I18n.t("REVERT THIS CARD"), func():
			CardEdits.revert_card(_selected_pool, c["n"])
			_reload_content()
		))
	actions.add_child(UIKit.button(I18n.t("REVERT ALL CARDS"), func():
		CardEdits.revert_all()
		_reload_content()
	))
	_editor_box.add_child(actions)


func _gap() -> Control:
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	return sp


## Writes `value` into the selected card and persists. A null value removes
## the key, which is how an effect is dropped from a card entirely.
func _apply(field: String, value) -> void:
	var c := _selected_card().duplicate(true)
	if c.is_empty():
		return
	c.erase("uid")  # runtime-only; must never be baked into a saved card
	if value == null:
		c.erase(field)
	else:
		c[field] = value
	CardEdits.set_card(_selected_pool, c)
	_reload_content()


## Editing a card here used to change the registry and leave a run in progress
## holding the old version of that card, because this reloaded two of the four
## things that need reloading. They now re-sync themselves; see
## Content.reloaded.
func _reload_content() -> void:
	Content.reload()
	_refresh_summary()
	_rebuild_list()
	_rebuild_editor()


func _int_row(c: Dictionary, field: String, caption: String, lo: int, hi: int) -> Control:
	var row := UIKit.hbox(10)
	var cap := UIKit.label(caption, 12, UIKit.INK)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)

	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.value = float(c.get(field, 0))
	spin.custom_minimum_size.x = 90
	spin.value_changed.connect(func(v: float): _apply(field, int(v)))
	row.add_child(spin)
	return row


## One row per entry in the card_effects registry, so mods that add effect
## fields get an editor without touching this file. Value 0 removes the key.
func _effect_row(c: Dictionary, e: Dictionary) -> Control:
	var field: String = e["k"]
	var row := UIKit.hbox(10)
	row.tooltip_text = _effect_hint(e)

	var cap := UIKit.label(field, 12, UIKit.INK if c.has(field) else UIKit.DIM)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 30
	spin.step = 1
	spin.value = float(c.get(field, 0))
	spin.custom_minimum_size.x = 90
	spin.value_changed.connect(func(v: float): _apply(field, null if int(v) == 0 else int(v)))
	row.add_child(spin)

	# The registry's own suggested amount for this effect (card_effects' "d":
	# draw 1, coin 3, next 4, solo 6...). It was ported and then read by
	# nothing, which left every effect starting at 0 — turning "give this card
	# the solo bonus" into six clicks on a spin box. One button instead.
	var typical := int(e.get("d", 0))
	if typical > 0 and int(c.get(field, 0)) != typical:
		var use := UIKit.button(str(typical), func(): _apply(field, typical))
		use.tooltip_text = I18n.t("The usual amount for this effect.")
		use.custom_minimum_size = Vector2(52, 28)
		row.add_child(use)

	var hint := UIKit.label(_effect_hint(e), 11, UIKit.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	return row


## What an effect makes a card say, as the card will actually say it.
##
## This used to be assembled from the registry's `pre`/`post` fragments — "Draw
## N cards." — which read as English in a French build and, worse, was a SECOND
## description of every effect, kept beside the one Rules.auto_text() prints on
## the card. The two could disagree and nobody would notice; the fragments are
## the prototype's, and auto_text has been rewritten around whole translatable
## sentences since.
##
## So the hint is auto_text itself, run on a bare card carrying only this
## effect at its registry-suggested amount. One source for the wording, already
## translated, and it cannot drift from the card because it IS the card's text.
## An effect auto_text does not know — a field a mod invented — yields nothing,
## and only then do the fragments stand in.
func _effect_hint(e: Dictionary) -> String:
	var amount := int(e.get("d", 1))
	var said := Rules.auto_text({e["k"]: maxi(amount, 1)})
	if said.strip_edges() != "":
		return said
	return "%s %s %s" % [e.get("pre", ""), "N", e.get("post", "")]


func _flag_row(c: Dictionary, field: String, caption: String) -> Control:
	var row := UIKit.hbox(10)
	var box := CheckButton.new()
	box.button_pressed = bool(c.get(field, false))
	box.toggled.connect(func(pressed: bool): _apply(field, true if pressed else null))
	row.add_child(box)
	row.add_child(UIKit.label(caption, 12, UIKit.INK))
	return row


func _element_row(c: Dictionary) -> Control:
	var row := UIKit.hbox(10)
	var cap := UIKit.label(I18n.t("Element"), 12, UIKit.INK)
	cap.custom_minimum_size.x = 150
	row.add_child(cap)

	var opt := OptionButton.new()
	UIKit.style_button(opt)
	opt.add_item(I18n.t("None"))
	opt.set_item_metadata(0, null)
	var current = c.get("el")
	var selected := 0
	var i := 1
	for el in Content.ring:
		opt.add_item("%s %s" % [UIKit.el_glyph(el), str(el).to_upper()])
		opt.set_item_metadata(i, el)
		if current == el:
			selected = i
		i += 1
	opt.select(selected)
	opt.item_selected.connect(func(idx: int): _apply("el", opt.get_item_metadata(idx)))
	row.add_child(opt)
	return row


# ── nav ─────────────────────────────────────────────────────────────────

func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
