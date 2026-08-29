## Generic "choose one of several options" screen — covers the gift (start of
## run), reward (after winning a reading), shop (apothecary), and event (back
## room) states, matching how the source unifies all four under one `pick`
## state shape (see Component.buildGift/buildReward/buildShop/buildEvent).
extends Control


func _ready() -> void:
	var pick: Dictionary = Run.state["pick"]

	var root := UIKit.root_control()
	add_child(root)
	var m := UIKit.margin(32)
	root.add_child(m)
	var v := UIKit.vbox(14)
	m.add_child(v)

	if pick.get("head", "") != "":
		v.add_child(UIKit.label(pick["head"], 13, UIKit.GOLD))
	v.add_child(UIKit.label(pick.get("title", ""), 22, UIKit.INK))
	v.add_child(UIKit.label(pick.get("body", ""), 13, UIKit.DIM))
	v.add_child(UIKit.label("Coin: %s   Faith: %s   Deck: %s cards" % [Run.state["coin"], Run.state["faith"], Run.state["deck"].size()], 12, UIKit.DIM))

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
		v.add_child(UIKit.button(pick.get("skipLabel", "SKIP"), _skip))


func _opt_button(o: Dictionary, i: int) -> Button:
	var lines: Array = []
	var cost := int(o.get("cost", 0))
	var afford := cost <= int(Run.state["coin"])

	if o.has("card"):
		var c: Dictionary = o["card"]
		var el_c: Color = UIKit.el_color(c["el"]) if c.get("el") != null else UIKit.DIM
		lines.append([o.get("kind", ""), 11, UIKit.GOLD])
		lines.append([UIKit.card_summary(c), 16, el_c])
		lines.append([UIKit.card_text(c), 12, UIKit.INK])
		if c.get("fl", "") != "":
			lines.append([c["fl"], 11, UIKit.DIM])
	elif o.has("mark"):
		var mk: Dictionary = o["mark"]
		lines.append([o.get("kind", ""), 11, UIKit.GOLD])
		lines.append([mk["n"], 16, UIKit.INK])
		lines.append([mk["text"], 12, UIKit.DIM])
	else:
		lines.append([o.get("kind", ""), 11, UIKit.GOLD])
		lines.append([o.get("name", ""), 16, UIKit.INK])
		lines.append([o.get("text", ""), 12, UIKit.DIM])

	if cost > 0:
		lines.append(["Cost: %s centimes" % cost, 12, UIKit.GOLD if afford else UIKit.RED])
	var reward: Dictionary = o.get("reward", {})
	if reward.has("faith"):
		lines.append(["+%s faith" % reward["faith"], 12, UIKit.GREEN])
	if reward.has("coin"):
		lines.append(["+%s centimes" % reward["coin"], 12, UIKit.GREEN])

	return UIKit.panel_button(lines, _take.bind(i), afford)


func _take(i: int) -> void:
	Run.take_pick(i)
	Nav.goto_for_state()


func _skip() -> void:
	Run.skip_pick()
	Nav.goto_for_state()
