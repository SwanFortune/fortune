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


## `host` is the scene adding the header — used as the parent for the modal
## overlays and as the scene to come back to from Settings.
static func build(host: Node) -> Control:
	var st: Dictionary = Run.state
	var bar := UIKit.hbox(14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var reader: Dictionary = st.get("reader", {})
	bar.add_child(UIKit.label("%s  %s" % [
		UIKit.el_glyph(reader.get("el", "")), I18n.reader_field(reader, "name")
	], 12, UIKit.el_color(reader.get("el", ""))))

	bar.add_child(_stat(I18n.t("Faith"), str(st.get("faith", 0)), UIKit.GOLD, UIKit.KEYS["faith"]))
	bar.add_child(_stat(I18n.t("Centimes"), str(st.get("coin", 0)), UIKit.GOLD, UIKit.KEYS["centimes"]))
	bar.add_child(_stat(I18n.t("Mended"), str(st.get("mended", 0)), UIKit.GREEN, ""))

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
	bar.add_child(_chip(I18n.t("SETTINGS"), func():
		Nav.goto_settings(host.scene_file_path)
	))
	return bar


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
	return b


# ── overlays ────────────────────────────────────────────────────────────

## A modal panel over the current screen. Used instead of a scene change so
## opening the deck mid-reading can't disturb the reading's own state — the
## screen underneath is untouched and simply revealed again on close.
static func _overlay(host: Node, title: String, build_body: Callable) -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.66)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	head.add_child(UIKit.button(I18n.t("CLOSE"), func(): layer.queue_free()))
	v.add_child(head)

	build_body.call(v)
	host.add_child(layer)
	UIKit.animate_in(panel)


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
			box.add_child(UIKit.card_face(first[n], func(): pass, true))
			var count_l := UIKit.label("x%d" % counts[n], 12, UIKit.GOLD if counts[n] > 1 else UIKit.DIM)
			count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count_l)
			fan.add_child(box)
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
