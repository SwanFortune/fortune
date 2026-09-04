extends Control

## Loaded by path, not by `class_name`. A class_name global is only declared
## once Godot has written .godot/global_script_class_cache.cfg — a cache the
## EDITOR generates, correctly gitignored — so on a fresh clone the bare name
## does not resolve, this script fails to compile, and the scene instantiates
## with no script at all. See autoload/Content.gd's header for the full story.
const RunHeader := preload("res://scenes/RunHeader.gd")
const UIKit := preload("res://scenes/UIKit.gd")
const Table := preload("res://scenes/Table.gd")


func _ready() -> void:
	var root := UIKit.root_control(Table.VIEW_DOOR)
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	var st: Dictionary = Run.state
	v.add_child(RunHeader.build(self))
	v.add_child(UIKit.block("%s %d · %s %d / 8" % [
		I18n.t("NIGHT"), int(st["night"]) + 1, I18n.t("KNOCK"), int(st["step"]) + 1
	], 14, UIKit.GOLD))
	v.add_child(UIKit.block(I18n.t("Who knocks tonight?"), 22, UIKit.INK))

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 460)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var opts: Array = st["options"]
	for i in opts.size():
		var row := _opt_button(opts[i], i)
		list.add_child(row)
		# Each option arrives on a knock. The staggering is small on purpose:
		# this is a beat, not a cutscene, and it is over before someone who has
		# seen it forty times can be annoyed by it.
		UIKit.animate_in(row, KNOCKS[mini(i, KNOCKS.size() - 1)] + 0.05)
	# The night's options, not the run header above them — the header is chrome,
	# and landing on its DECK chip would make the first key press do nothing useful.
	UIKit.focus_first(list)
	_knock(root)


## SOMEBODY KNOCKS. The screen asks "who knocks tonight?", a run is sixteen
## knocks long, and it ends the night the knocking stops — and in the entire
## port nothing had ever knocked. Three raps on the door behind the screen: the
## sound, the leaf jumping in its frame, and more of whoever is out there coming
## under it each time.
##
## Nothing waits for it. The options are already there and already focused; a
## player can choose during the first knock. An atmosphere beat that takes the
## game away from you is a beat you resent by the tenth night.
##
## The rhythm accelerates slightly, the way a person's knuckles do.
const KNOCKS := [0.00, 0.34, 0.60]

func _knock(root: Control) -> void:
	var room := root.find_child("Room", false, false)
	if room == null:
		return
	if UIKit.motion_off():
		# One knock, no rattle: the sound is not the animation, and turning
		# motion off should not make the door go quiet.
		Audio.play("knock")
		return
	for i in KNOCKS.size():
		var at: float = KNOCKS[i]
		var timer := get_tree().create_timer(UIKit.dur(at))
		timer.timeout.connect(func():
			if not is_instance_valid(room):
				return
			Audio.play("knock")
			var t := UIKit.bound_tween(room)
			# Sharp in, slower out — a hit, then the door settling back.
			t.tween_method(func(v: float): Table.set_knock(room, v), 0.0, 1.0, UIKit.dur(0.03))
			t.tween_method(func(v: float): Table.set_knock(room, v), 1.0, 0.0, UIKit.dur(0.22)) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		)


func _opt_button(o: Dictionary, i: int) -> Control:
	var lines: Array = []
	var leading: Control = null
	match o["kind"]:
		"sitter", "elite", "boss":
			var s: Dictionary = o["sitter"]
			var q: Dictionary = o["quirk"]
			var tag := "ELITE — " if o["kind"] == "elite" else ("THE MAYOR — " if o["kind"] == "boss" else "")
			lines.append(["%s%s" % [tag, I18n.sitter_field(s, "name")], 17, UIKit.RED if o["kind"] != "sitter" else UIKit.INK])
			lines.append(["%s · %s %s (%s)" % [I18n.sitter_field(s, "role"), I18n.t("sign"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn")], 12, UIKit.el_color(s["el"])])
			lines.append([I18n.sign_rule(q, s), 11, UIKit.DIM])
			lines.append(["composure %s · denial %s · %s readings" % [s["max"], s["denial"], s["turns"]], 11, UIKit.DIM])
			var job: Dictionary = Content.get_job(s["role"])
			if job.get("t", "") != "":
				lines.append([I18n.fill(I18n.job_text(s["role"], job), str(s.get("p", "they"))), 11, UIKit.GOLD])
			# An elite's twist changes composure, denial, readings or hand size,
			# and until now was applied silently — the option said "ELITE" and
			# nothing about what that elite actually does. The source shows this
			# line on the same card (~line 593), so the field was ported but
			# never read by anything.
			var tw: Dictionary = s.get("twist", {})
			if tw.get("t", "") != "":
				lines.append([I18n.fill(I18n.twist_text(tw), str(s.get("p", "they"))), 11, UIKit.RED])
			lines.append([I18n.sitter_field(s, "brings"), 12, UIKit.DIM])
			# Sitters wear the same sigil as readers do: their SIGN, drawn in
			# their element's colour. Those two facts — which denial you are up
			# against and which cards are worth more — are the whole of the
			# decision this screen asks for, and they were a line of small text.
			leading = _sigil(str(q.get("k", "")), str(s.get("el", "")))
		"break":
			var rest: Dictionary = o["rest"]
			if rest.get("kind", "") == "SHOP":
				lines.append([I18n.t("THE APOTHECARY"), 17, UIKit.GOLD])
				lines.append([rest.get("title", ""), 12, UIKit.DIM])
			else:
				lines.append([rest.get("head", "EVENT"), 13, UIKit.GOLD])
				lines.append([rest.get("title", ""), 17, UIKit.INK])
				lines.append([rest.get("line", ""), 12, UIKit.DIM])
	return UIKit.panel_button(lines, _choose.bind(i), true, "", leading)


## A sitter's sigil: their sign, in their element's colour — the same drawing
## the sign-select screen puts beside a reader, so the two read as one system.
func _sigil(sign_key: String, el: String) -> Control:
	var tint: Color = UIKit.el_color(el) if el != "" else UIKit.GOLD
	var col := UIKit.vbox(4)
	col.custom_minimum_size.x = 46
	var badge := UIKit.icon_badge("sign", sign_key, 42, tint)
	if badge != null:
		col.add_child(badge)
	var el_b := UIKit.el_badge(el, 20)
	if el_b != null:
		el_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(el_b)
	return col


func _choose(i: int) -> void:
	Run.choose(i)
	Nav.goto_for_state()


func _unhandled_input(event: InputEvent) -> void:
	if RunHeader.handle_shortcut(event, self):
		get_viewport().set_input_as_handled()
