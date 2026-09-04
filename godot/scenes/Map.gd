extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
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
	v.add_child(UIKit.block("%s %d · %s" % [
		I18n.t("NIGHT"), int(st["night"]) + 1, I18n.t("Who knocks tonight?")
	], 20, UIKit.INK))

	# THE AGENDA down the left, the hour's callers on the right. The night is
	# planned before it starts (Run.make_plan) so it can be READ before it
	# starts: what is already written in, what is happening now, and the shape
	# of what is still to come. See _agenda().
	var page := UIKit.hbox(20)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(page)
	page.add_child(_agenda(st))

	var scroll := UIKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
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


## Three raps on the door behind the screen: the sound, the leaf jumping in its
## frame, and more light under it each time. The rhythm accelerates slightly,
## the way a person's knuckles do.
##
## NOTHING WAITS FOR IT. The options are already there and already focused, so a
## player can choose during the first knock. An atmosphere beat that takes the
## game away from you is one you resent by the tenth night.
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
	# THE ROOM BY ITS ID, never by reference, all the way down.
	#
	# A lambda whose OWN OBJECT is freed is dropped silently and never runs. A
	# lambda that CAPTURES a freed Node is not: Godot nulls the capture, logs
	# "Lambda capture at index 0 was freed", and calls the body ANYWAY — so a
	# guard inside the body is too late. These knocks stay pending for six
	# tenths of a second after the map is torn down, which is long enough to
	# hit it on every single encounter.
	var id := room.get_instance_id()
	var rattle := func(v: float) -> void:
		if is_instance_id_valid(id):
			Table.set_knock(instance_from_id(id), v)
	for i in KNOCKS.size():
		UIKit.after(KNOCKS[i], func():
			if not is_instance_id_valid(id):
				return
			Audio.play("knock")
			var t := UIKit.bound_tween(instance_from_id(id))
			# Sharp in, slower out — a hit, then the door settling back.
			t.tween_method(rattle, 0.0, 1.0, UIKit.dur(0.03))
			t.tween_method(rattle, 1.0, 0.0, UIKit.dur(0.22)) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		)


## The night as a page in an appointment book: eight half-hours down the left,
## each either written in, happening now, or still to come.
##
## PAST hours name who came and how it went; FUTURE hours give the shape only —
## a name would give the night away. Built from Run.state's plan, which is
## decided at the start of the night for exactly this reason.
const AGENDA_WIDTH := 214.0

## What a future hour promises, by what the plan says is on offer. Only the
## SHAPE — a name would give the night away, and the shape is what a plan is.
const PROMISE := {
	"boss": "THE MAYOR",
	"elite": "someone difficult",
	"shop": "the apothecary",
	"event": "an evening off",
	"secret": "an evening off",
	"sitter": "a caller",
}

## One line saying how the deck you are carrying answers to this caller's sign.
##
## Counted straight off the deck rather than through Rules: this is a plain "how
## many of these do I own". The chromatics, whose element is not fixed until
## they are played, are reported as UNFIXED rather than guessed — a screen that
## guesses is worse than one that says it does not know.
func _deck_against(q: Dictionary) -> String:
	var el := str(q.get("el", ""))
	if el == "":
		return ""
	var deck: Array = Run.state.get("deck", [])
	var match_count := 0
	var shifting := 0
	for c in deck:
		# A chromatic card has `el: null` AND `chroma: true`; a basic has
		# `el: null` and `neutral: true`. Both read as "no element" if you only
		# look at `el`, and they are opposites — one answers to every sign and
		# the other to none — so the flag is what is asked, not the field.
		if c.get("chroma", false):
			shifting += 1
		elif str(c.get("el", "")) == el:
			match_count += 1
	var word := I18n.element_field(el, "label")
	var line := I18n.t("your deck: %d of %d answer to %s") % [match_count, deck.size(), word]
	if shifting > 0:
		line += I18n.t(" (+%d that shift)") % shifting
	# The signs that turn their own element against you. Worth saying here,
	# because it inverts the number immediately to its left.
	match str(q.get("fx", "")):
		"halfown":
			line += I18n.t(" — and this sign halves them")
		"deadel":
			line += I18n.t(" — and this sign kills %s outright") % I18n.element_field(str(q.get("dead", "")), "label")
	return line


func _agenda(st: Dictionary) -> Control:
	var plan: Array = st.get("plan", [])
	var log: Array = st.get("log", [])
	var now: int = int(st.get("step", 0))

	var col := UIKit.vbox(0)
	col.custom_minimum_size.x = AGENDA_WIDTH * UIKit.text_scale
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(UIKit.block(I18n.t("THE EVENING"), 11, UIKit.GOLD))

	for step in plan.size():
		var slot: Dictionary = plan[step]
		var row := UIKit.hbox(8)
		row.custom_minimum_size.y = 30 * UIKit.text_scale
		var past: bool = step < now
		var here: bool = step == now
		var hour := UIKit.label(str(slot.get("at", "")), 12,
			UIKit.GOLD if here else (UIKit.DIM if past else Color(UIKit.INK, 0.30)))
		hour.custom_minimum_size.x = 44 * UIKit.text_scale
		row.add_child(hour)

		var text := ""
		var tint := Color(UIKit.INK, 0.30)
		if past:
			var done: Dictionary = log[step] if step < log.size() and typeof(log[step]) == TYPE_DICTIONARY else {}
			text = str(done.get("name", I18n.t("nobody")))
			# An hour that has happened is not a plan any more, it is a
			# result — and the whole run is about which of them went home
			# whole, so that is what the page records.
			match str(done.get("outcome", "")):
				"mended":
					tint = UIKit.GREEN
				"left":
					tint = UIKit.RED
				_:
					tint = UIKit.DIM
		elif here:
			text = I18n.t("now")
			tint = UIKit.GOLD
		else:
			var offers: Array = slot.get("offers", [])
			# The heaviest thing on offer is what the hour is remembered as: an
			# hour with the Mayor in it is the Mayor's hour.
			for key: String in ["boss", "elite", "shop", "secret", "event", "sitter"]:
				if offers.has(key):
					text = I18n.t(str(PROMISE[key]))
					break
			if offers.has("boss"):
				tint = UIKit.RED
		var line := UIKit.label(text, 12, tint)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		col.add_child(row)
	return col


func _opt_button(o: Dictionary, i: int) -> Control:
	var lines: Array = []
	var leading: Control = null
	# The flavour halves of the job and the sign, which the rows show only as
	# their mechanics. Joined into the row's hover so the writing is still
	# reachable rather than dropped. See I18n.split_rule().
	var flavours: Array[String] = []
	match o["kind"]:
		"sitter", "elite", "boss":
			var s: Dictionary = o["sitter"]
			var q: Dictionary = o["quirk"]
			var tag := "ELITE — " if o["kind"] == "elite" else ("THE MAYOR — " if o["kind"] == "boss" else "")
			lines.append(["%s%s" % [tag, I18n.sitter_field(s, "name")], 17, UIKit.RED if o["kind"] != "sitter" else UIKit.INK])
			lines.append(["%s · %s %s (%s)" % [I18n.sitter_field(s, "role"), I18n.t("sign"), I18n.sign_field(q, "n"), I18n.sign_field(q, "dn")], 12, UIKit.el_color(s["el"])])
			# The MECHANIC on the row, the flavour on the hover — the same split
			# the reading screen makes. See I18n.split_rule().
			var sign_split: Array = I18n.split_rule(I18n.sign_rule(q, s))
			lines.append([str(sign_split[0]), 11, UIKit.VIOLET])
			flavours.append(str(sign_split[1]))
			lines.append(["composure %s · denial %s · %s readings" % [s["max"], s["denial"], s["turns"]], 11, UIKit.DIM])
			# HOW YOUR DECK LINES UP, which is the actual question being asked
			# and which the screen made you answer from memory. A card whose
			# element matches the sign's is worth +2 on every single play of it
			# (Rules.simulate), so "how many of mine are Water" is the one number
			# that decides whether this caller is easy or a wall — and the deck
			# is thirty cards down a menu two screens away.
			lines.append([_deck_against(q), 11, UIKit.el_color(str(q.get("el", "")))])
			var job: Dictionary = Content.get_job(s["role"])
			if job.get("t", "") != "":
				var job_split: Array = I18n.split_rule(
					I18n.fill(I18n.job_text(s["role"], job), str(s.get("p", "they"))))
				lines.append([str(job_split[0]), 11, UIKit.GOLD])
				flavours.append(str(job_split[1]))
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
	var said: Array[String] = []
	for fl in flavours:
		if fl != "":
			said.append(fl)
	return UIKit.panel_button(lines, _choose.bind(i), true, "\n\n".join(said), leading)


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
