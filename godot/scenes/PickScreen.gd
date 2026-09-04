## Generic "choose one of several options" screen — covers the gift (start of
## run), reward (after winning a reading), shop (apothecary), and event (back
## room) states, matching how the source unifies all four under one `pick`
## state shape (see Component.buildGift/buildReward/buildShop/buildEvent).
extends Control

## Loaded by path, not by `class_name` — a bare name does not resolve on a fresh
## clone. See autoload/Content.gd's header for why, and never change these back.
const RunHeader := preload("res://scenes/RunHeader.gd")
const UIKit := preload("res://scenes/UIKit.gd")


func _ready() -> void:
	var pick: Dictionary = Run.state["pick"]

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	v.add_child(RunHeader.build(self))
	if pick.get("head", "") != "":
		v.add_child(UIKit.block(I18n.t(str(pick["head"])), 13, UIKit.GOLD))
	v.add_child(UIKit.block(I18n.t(str(pick.get("title", ""))), 22, UIKit.INK))
	v.add_child(UIKit.block(I18n.t(str(pick.get("body", ""))), 13, UIKit.DIM))

	var scroll := UIKit.scroll()
	v.add_child(scroll)
	scroll.custom_minimum_size = Vector2(0, 420)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var opts: Array = pick.get("opts", [])
	for i in opts.size():
		list.add_child(_opt_button(opts[i], i))

	if pick.get("skippable", false):
		v.add_child(UIKit.button(I18n.t(str(pick.get("skipLabel", "SKIP"))), _skip))
	# The offers, not the run header above them. See Map.gd.
	UIKit.focus_first(list)


func _opt_button(o: Dictionary, i: int) -> Control:
	# An option may name its card or mark rather than carry a copy — see
	# Run.resolve_named(). Resolved HERE as well as in take_pick() so the row a
	# player reads and the thing they get are the same object; a named card
	# rendered through the "neither a card nor a mark" branch below would show
	# its own name as flavour text and no rules at all.
	o = Run.resolve_named(o)
	var lines: Array = []
	var cost := int(o.get("cost", 0))
	var afford := cost <= int(Run.state["coin"])
	var tooltip := ""

	if o.has("card"):
		var c: Dictionary = o["card"]
		var el_c: Color = UIKit.el_color(c["el"]) if c.get("el") != null else UIKit.DIM
		lines.append([I18n.t(str(o.get("kind", ""))), 11, UIKit.GOLD])
		lines.append([UIKit.card_summary(c), 16, el_c])
		# WHAT IT COSTS AND WHAT IT RESTORES WERE NOWHERE ON THIS SCREEN. The
		# rows carried the name, the extra rule and the flavour — and the two
		# numbers that define a card were not among them, because auto_text()
		# only describes what a card does BEYOND restoring. So the single most
		# consequential decision in the game, which card goes into your deck for
		# the rest of the run, was made without them. A plain card with no extra
		# rule was worse still: its rules line came out empty, so the row said a
		# name, a blank, and a line of flavour.
		#
		# A line, not the drawn face. The face was tried first and is the nicer
		# object — it is what the card will look like in the hand — but it is 158
		# pixels tall, and three of them pushed the third reward below the fold.
		# A choice screen whose options cannot be seen at once is a worse problem
		# than the one being fixed.
		lines.append([I18n.t("%s energy · restores %s") % [
			c.get("cost", 0), c.get("f", 0)], 12, UIKit.GOLD])
		lines.append([UIKit.card_text(c), 12, UIKit.INK])
		if c.get("fl", "") != "":
			lines.append([c["fl"], 11, UIKit.DIM])
		tooltip = UIKit.card_keyword_tooltip(c)
	elif o.has("mark"):
		var mk: Dictionary = o["mark"]
		lines.append([I18n.t(str(o.get("kind", ""))), 11, UIKit.GOLD])
		lines.append([I18n.content("mark/" + Art.slug(str(mk.get("n",""))), "n", str(mk.get("n",""))), 16, UIKit.INK])
		lines.append([I18n.content("mark/" + Art.slug(str(mk.get("n",""))), "text", str(mk.get("text",""))), 12, UIKit.DIM])
	else:
		lines.append([I18n.t(str(o.get("kind", ""))), 11, UIKit.GOLD])
		lines.append([I18n.t(str(o.get("name", ""))), 16, UIKit.INK])
		lines.append([I18n.t(str(o.get("text", ""))), 12, UIKit.DIM])

	# An option that hands over a card or a mark may still have SOMETHING TO SAY
	# about it — the events written for the port lean on that line ("It smells
	# like her kitchen and it works, which you resent"). Only the third branch
	# above printed `text`, so on a card or a mark the option's own words were
	# silently thrown away and the row read as a shop entry.
	if (o.has("card") or o.has("mark")) and str(o.get("text", "")) != "":
		lines.append([I18n.t(str(o["text"])), 11, UIKit.DIM])

	if cost > 0:
		lines.append(["Cost: %s centimes" % cost, 12, UIKit.GOLD if afford else UIKit.RED])
	var reward: Dictionary = o.get("reward", {})
	if reward.has("faith"):
		lines.append(["+%s faith" % reward["faith"], 12, UIKit.GREEN])
	if reward.has("coin"):
		lines.append(["+%s centimes" % reward["coin"], 12, UIKit.GREEN])

	return UIKit.panel_button(lines, _take.bind(i), afford, tooltip)


func _take(i: int) -> void:
	# Only when it actually costs something — a free reward is not a purchase,
	# and playing the coin sound for one would be a small lie.
	if int(Run.state["pick"].get("opts", [])[i].get("cost", 0)) > 0:
		Audio.play("coin")
	Run.take_pick(i)
	Nav.goto_for_state()


func _skip() -> void:
	Run.skip_pick()
	Nav.goto_for_state()


func _unhandled_input(event: InputEvent) -> void:
	if RunHeader.handle_shortcut(event, self):
		get_viewport().set_input_as_handled()
