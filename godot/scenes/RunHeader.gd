## The persistent run status bar, shown on every in-run screen (map, reading,
## pick, result). Before this existed the run's own state was scattered and
## partly invisible: coin/faith were re-rendered slightly differently on two
## screens, the deck was only ever a number you couldn't inspect, and MARKS
## AND RELICS WERE SHOWN NOWHERE AT ALL — you could earn a permanent passive
## off an elite and have no way to find out what it did.
##
## Built as a plain static factory rather than a scene so the existing
## screens (which all build their UI procedurally in _ready) can each add one
## line and get it, with no .tscn wiring.
class_name RunHeader
extends RefCounted

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const UIKit := preload("res://scenes/UIKit.gd")


## `host` is the scene adding the header — used as the parent for the modal
## overlays and as the scene to come back to from Settings.
## Returns the header. When the run cannot be written to disk it returns a
## column — the warning line above the bar — rather than the bar alone, so
## every screen that adds a header gets the warning without a change of its
## own. Callers add whatever comes back; none of them cares which it is.
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
	# WHICH RUN THIS IS. You choose a difficulty and a seed on the sign screen
	# and then nothing said which you were on for the next three nights, so a
	# player halfway up the ladder could not tell a hard run from an ordinary
	# one, and a seed handed round was unverifiable at the far end.
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
	# Reads "MARKS (0)" rather than being hidden when empty, so it's
	# discoverable as a thing that fills up rather than appearing from
	# nowhere the first time an elite drops one.
	bar.add_child(_chip("%s (%d)" % [I18n.t("MARKS"), marks.size()], func(): _show_marks(host)))
	# The rules, as an overlay rather than a scene change: a player who needs
	# to look something up mid-reading should not have to leave the reading,
	# and the run screens rebuild from Run.state anyway so a trip out and back
	# would be safe but jarring.
	bar.add_child(_chip(I18n.t("RULES"), func(): _show_rules(host)))
	bar.add_child(_chip(I18n.t("SETTINGS"), func():
		Nav.goto_settings(host.scene_file_path)
	))
	# THE WAY OUT. Once BEGIN was pressed there was no route back to the main
	# menu from anywhere in the game: not from the sign screen, not from the map,
	# not from the ending. SETTINGS returned you to the run it came from, and
	# everything else led forward. Which meant that after starting a run a player
	# could not reach the Library, the Minitel, the mods list — or QUIT. The only
	# way to leave this game was the window's close button.
	#
	# No confirmation, because there is nothing to confirm: the run is written to
	# disk on the way out and CONTINUE on the menu picks it up mid-reading, cards
	# in hand and all. That is the whole reason the save keeps the fight.
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
## WHILE AN OVERLAY IS OPEN THIS SWALLOWS EVERYTHING. That is the point, and it
## was missing: the overlay is a modal panel drawn over the screen, but the
## screen underneath kept its own keyboard handling, so pressing D twice opened
## a second deck on top of the first, Escape closed nothing, and the reading's
## own READ IT shortcut still fired at a board the player could not see.
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
	# The header's chips are the same surface as every other button, at three
	# fifths of the treatment — they sit above the game and should not shout.
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
