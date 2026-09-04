## The persistent run status bar, on every in-run screen: map, reading, pick,
## result. One place where the run's own state is rendered, so it cannot drift
## between screens, and where the deck and the marks are inspectable rather than
## being a number you cannot open.
##
## A static factory rather than a scene, so a screen that builds its UI in
## _ready() adds one line and gets it, with no .tscn wiring.
class_name RunHeader
extends RefCounted

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const UIKit := preload("res://scenes/UIKit.gd")


## `host` is the scene adding the header — the parent for the modal overlays,
## and the scene Settings comes back to.
##
## Returns the bar, OR a column of the bar under a warning line when the run
## cannot be written to disk. Callers add whatever comes back without caring
## which, so every screen with a header inherits the warning.
static func build(host: Node) -> Control:
	var bar := _bar(host)
	if not Save.write_failed:
		return bar
	# Loud, permanent, and NOT a modal: a player mid-reading should not have
	# their turn interrupted, but they must not reach the end of the night
	# still believing the game is keeping their progress.
	var col := UIKit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.block(
		"%s %s" % [I18n.t("THIS RUN IS NOT BEING SAVED — anything from here is lost if you close the game."), Save.last_error],
		12, UIKit.RED))
	col.add_child(bar)
	return col


static func _bar(host: Node) -> Control:
	var st: Dictionary = Run.state
	var bar := UIKit.hbox(14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var reader: Dictionary = st.get("reader", {})
	bar.add_child(UIKit.label("%s  %s" % [
		UIKit.el_glyph(reader.get("el", "")), I18n.reader_field(reader, "name")
	], 12, UIKit.el_color(reader.get("el", ""))))

	bar.add_child(_stat(I18n.t("Faith"), str(st.get("faith", 0)), UIKit.GOLD, I18n.t(UIKit.KEYS["faith"])))
	bar.add_child(_stat(I18n.t("Centimes"), str(st.get("coin", 0)), UIKit.GOLD, I18n.t(UIKit.KEYS["centimes"])))
	bar.add_child(_stat(I18n.t("Mended"), str(st.get("mended", 0)), UIKit.GREEN, ""))
	# WHICH RUN THIS IS — the difficulty and the seed chosen on the sign screen.
	# Without them a player halfway up the ladder cannot tell a hard run from an
	# ordinary one, and a seed handed to somebody else is unverifiable.
	var level := int(st.get("level", 0))
	if level > 0:
		var rung: Dictionary = {}
		for r in Content.difficulty:
			if int(r.get("n", 0)) == level:
				rung = r
		bar.add_child(_stat(I18n.t("Level"), str(level), UIKit.RED,
			I18n.t(str(rung.get("text", "")))))
	var seed_text := str(st.get("seed", ""))
	if seed_text != "":
		bar.add_child(_stat(I18n.t("Evening no."), seed_text, UIKit.DIM,
			I18n.t("Every roll this run makes comes from this. Type it on the sign screen to play it again.")))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var deck: Array = st.get("deck", [])
	bar.add_child(_chip("%s (%d)" % [I18n.t("DECK"), deck.size()], func(): _show_deck(host)))

	var marks: Array = st.get("marks", [])
	# Reads "MARKS (0)" rather than hiding when empty, so it is discoverable as
	# a thing that fills up rather than appearing from nowhere.
	bar.add_child(_chip("%s (%d)" % [I18n.t("MARKS"), marks.size()], func(): _show_marks(host)))
	# An overlay rather than a scene change: looking a rule up mid-reading
	# should not mean leaving the reading.
	bar.add_child(_chip(I18n.t("RULES"), func(): _show_rules(host)))
	bar.add_child(_chip(I18n.t("SETTINGS"), func():
		Nav.goto_settings(host.scene_file_path)
	))
	# THE WAY OUT of a run, and the only route back to the Library, the Minitel,
	# the mods list and QUIT once one has started. See UIKit.WAY_OUT.
	#
	# No confirmation, because there is nothing to confirm: the run is flushed to
	# disk on the way out and CONTINUE picks it up mid-reading, cards in hand.
	# That is what the save keeping the fight is for.
	var way_out := _chip(I18n.t("MENU"), func():
		Save.flush()
		Nav.goto_main_menu()
	)
	way_out.add_to_group(UIKit.WAY_OUT)
	bar.add_child(way_out)
	return bar


## The header's chips as keyboard/gamepad shortcuts. Called by each in-run
## screen from its own _unhandled_input rather than handled here, because
## RunHeader is a static factory returning a plain Control — there is no node
## of its own to receive input on, and inventing one just to hold a script
## would be more machinery than three delegating lines.
##
## Returns true if it consumed the event, so the caller can mark it handled.
##
## WHILE AN OVERLAY IS OPEN THIS SWALLOWS EVERYTHING, and must: the overlay is
## a panel drawn over a screen that is still live underneath. Let a key through
## and D opens a second deck on top of the first, Escape closes nothing, and
## READ IT fires at a board the player cannot see.
static func handle_shortcut(event: InputEvent, host: Node) -> bool:
	var open := open_overlay(host)
	if open != null:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("parlour_deck") \
				or event.is_action_pressed("parlour_marks"):
			_close(open)
		# Swallowed either way: an in-run shortcut must not reach the screen
		# behind a modal. Focus navigation (ui_left, Tab, ...) is routed by the
		# viewport before _unhandled_input and is unaffected.
		return true
	if event.is_action_pressed("parlour_deck"):
		_show_deck(host)
		return true
	if event.is_action_pressed("parlour_marks"):
		_show_marks(host)
		return true
	return false


## Nodes in this group are the modal layers built by _overlay(). A group rather
## than a static variable, because RunHeader is a stateless factory and a static
## would outlive the scene it referred to.
const OVERLAY_GROUP := "run_overlay"


## The overlay currently open over `host`, or null.
static func open_overlay(host: Node) -> Node:
	for child in host.get_children():
		if child.is_in_group(OVERLAY_GROUP) and not child.is_queued_for_deletion():
			return child
	return null


static func _stat(caption: String, value: String, color: Color, tip: String) -> Control:
	var row := UIKit.hbox(5)
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(UIKit.label(caption, 11, UIKit.DIM))
	row.add_child(UIKit.label(value, 13, color))
	return row


static func _chip(text: String, on_pressed: Callable) -> Control:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	b.add_theme_font_size_override("font_size", 11)
	# The same surface as every other button at three fifths of the treatment:
	# these sit above the game and should not shout.
	UIKit.style_button(b, 0.6)
	return b


# ── overlays ────────────────────────────────────────────────────────────

## A modal panel over the current screen. Used instead of a scene change so
## opening the deck mid-reading can't disturb the reading's own state — the
## screen underneath is untouched and simply revealed again on close.
static func _overlay(host: Node, title: String, build_body: Callable) -> void:
	var layer := Control.new()
	layer.add_to_group(OVERLAY_GROUP)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	# Remembered so closing puts the highlight back where the player left it.
	# Without this, coming out of the deck left focus on whatever the overlay
	# had taken it from — in practice nowhere, since the overlay is freed.
	var came_from: Control = host.get_viewport().gui_get_focus_owner()
	if came_from != null:
		layer.set_meta("came_from", came_from)

	# Clicking outside the panel closes it, the way every modal a player has
	# ever met does. The scrim was inert, so the only way out with a mouse was
	# to find the CLOSE button.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.66)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close(layer)
	)
	layer.add_child(scrim)

	var m := UIKit.margin(48)
	layer.add_child(m)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.BG
	style.set_content_margin_all(18)
	style.set_border_width_all(1)
	style.border_color = Color(UIKit.GOLD, 0.4)
	panel.add_theme_stylebox_override("panel", style)
	m.add_child(panel)

	var v := UIKit.vbox(10)
	panel.add_child(v)

	var head := UIKit.hbox(12)
	var t := UIKit.block(title, 20, UIKit.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.button(I18n.t("CLOSE"), func(): _close(layer)))
	v.add_child(head)

	build_body.call(v)
	host.add_child(layer)
	UIKit.animate_in(panel)
	# Focus moves INTO the overlay. It did not, and the consequence was worse
	# than a dead highlight: focus stayed on the card behind the scrim, so a
	# keyboard or gamepad player who opened their deck and pressed Confirm
	# played a card they could not see.
	UIKit.focus_first(layer)


static func _close(layer: Node) -> void:
	var came_from = layer.get_meta("came_from", null)
	layer.queue_free()
	if came_from is Control and is_instance_valid(came_from) and not UIKit.going_away(came_from):
		came_from.grab_focus()


## The deck, grouped by card so a deck with four copies of one card reads as
## "x4" rather than four identical rows you have to count by eye.
static func _show_deck(host: Node) -> void:
	_overlay(host, I18n.t("YOUR DECK"), func(v: VBoxContainer):
		var deck: Array = Run.state.get("deck", [])
		var counts := {}
		var first := {}
		for c in deck:
			var n: String = c.get("n", "?")
			counts[n] = int(counts.get(n, 0)) + 1
			if not first.has(n):
				first[n] = c
		v.add_child(UIKit.block(
			"%d %s" % [deck.size(), I18n.t("cards")], 12, UIKit.DIM))
		var scroll := UIKit.scroll()
		scroll.custom_minimum_size = Vector2(0, 400)
		v.add_child(scroll)
		var fan := HFlowContainer.new()
		fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fan.add_theme_constant_override("h_separation", 8)
		fan.add_theme_constant_override("v_separation", 8)
		scroll.add_child(fan)
		var names: Array = counts.keys()
		names.sort()
		for n in names:
			var box := UIKit.vbox(2)
			# Shown, not pressable. These were focusable and did nothing when
			# pressed, so a keyboard player paging through a ten-card deck met
			# ten dead stops before reaching CLOSE — which is now what focus
			# lands on when the overlay opens.
			box.add_child(UIKit.card_face(first[n], Callable(), true, false))
			var count_l := UIKit.label("x%d" % counts[n], 12, UIKit.GOLD if counts[n] > 1 else UIKit.DIM)
			count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count_l)
			fan.add_child(box)
	)


## The same rules the HOW TO PLAY screen shows, from the same function — so
## what a player reads mid-run cannot drift from what the menu told them.
static func _show_rules(host: Node) -> void:
	# load() at call time, not preload(). A local `const preload` still resolves
	# while THIS file is compiled, and RunHeader is reached by `godot -s` tools
	# before the autoloads exist — HowToPlay refers to four of them. See
	# tests/test_dead_content.gd, which now refuses this pattern outright.
	var HowToPlay = load("res://scenes/HowToPlay.gd")
	_overlay(host, I18n.t("HOW TO PLAY"), func(v: VBoxContainer):
		var scroll := UIKit.scroll()
		scroll.custom_minimum_size = Vector2(0, 420)
		v.add_child(scroll)
		var inner := UIKit.vbox(6)
		inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(inner)
		HowToPlay.build_into(inner)
	)


## Marks and relics — the permanent passives. Both pools land in the same
## runtime list (see CardEdits/Run.roll_relic); they're shown together here
## because to the player they are one thing: what's on your hands.
static func _show_marks(host: Node) -> void:
	_overlay(host, I18n.t("YOUR HANDS"), func(v: VBoxContainer):
		var marks: Array = Run.state.get("marks", [])
		if marks.is_empty():
			v.add_child(UIKit.block(I18n.t("Nothing on your hands yet. Rings and marks come from elites, events and the apothecary."), 13, UIKit.DIM))
			return
		var scroll := UIKit.scroll()
		scroll.custom_minimum_size = Vector2(0, 360)
		v.add_child(scroll)
		var list := UIKit.vbox(6)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for mk in marks:
			var el = mk.get("el")
			var col: Color = UIKit.el_color(el) if el != null and el != "" else UIKit.GOLD
			list.add_child(UIKit.panel_button([
				[I18n.content("mark/" + Art.slug(str(mk.get("n", ""))), "n", str(mk.get("n", ""))), 15, col],
				[str(mk.get("kind", "")), 10, UIKit.DIM],
				[I18n.content("mark/" + Art.slug(str(mk.get("n", ""))), "text", str(mk.get("text", ""))), 12, UIKit.INK],
			], func(): pass, true))
	)
