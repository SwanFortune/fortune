## THE ROOM REMEMBERS (scenes/RoomTraces.gd, Feel.become(), room.json).
##   godot --headless --path godot -s tests/test_room.gd
##
## A card laid becomes a thing in the parlour and the thing stays for the visit.
## Every half of that sentence is a place it can quietly stop being true, so:
##   - the rules name things, spots, cards and rumbles that all exist, and the
##     load-time check can see when one does not;
##   - laying the card through the real reading screen leaves the thing on the
##     fight, TAKE IT BACK takes it away, and a card that could not be paid for
##     leaves nothing;
##   - the layer that draws it covers the screen — it once covered 0x0 and drew
##     every thing into nothing, and only a screenshot showed it;
##   - it is saved with the fight and still there after a reload, including when
##     the new session's clock is behind the old one's;
##   - the card's journey is a copy of the card that frees itself, and there is
##     no journey at all when motion is off.
extends "res://tests/harness.gd"

var content: Node
var feel: Node
var run: Node
var RoomTraces = null
var _speed_before = 1.0


func setup() -> void:
	content = root.get_node("Content")
	feel = root.get_node("Feel")
	run = root.get_node("Run")
	content.reload()
	RoomTraces = load("res://scenes/RoomTraces.gd")
	root.size = Vector2i(1280, 720)
	_speed_before = root.get_node("Settings").get_value("animation_scale")


func before_each(_name: String) -> void:
	root.get_node("Settings").set_value("animation_scale", 1.0)


func teardown() -> void:
	# Settings are saved to disk as they change. Left at INSTANT, the next file
	# in the suite found motion off and its cards undressed — which is how
	# this line came to exist.
	root.get_node("Settings").set_value("animation_scale", _speed_before)
	root.get_node("Save").clear()
	content.reload()


# ── the rules ────────────────────────────────────────────────────────────

func _test_the_rules_name_only_things_that_exist() -> void:
	var said: Array = feel.room_problems()
	check(said.is_empty(), "room.json has problems:\n  %s" % "\n  ".join(said))
	# And the check can see each kind of mistake.
	content.traces.append({"id": "probe", "when": {"n": "Pour The Tae"}, "becomes": "teapot", "at": "ceiling", "how": "fly", "haptic": "hum"})
	content.props["odd"] = {"draw": "sculpture", "particles": "smoke"}
	said = feel.room_problems()
	for needle in ["Pour The Tae", "'teapot'", "'ceiling'", "'fly'", "'hum'", "'sculpture'", "'smoke'"]:
		check(said.any(func(l): return l.contains(needle)), "a trace or prop naming %s should be reported" % needle)
	content.reload()
	done()


## Every thing the rules can make is on the illustrator's list, where the studio
## and test_art.gd will find it.
func _test_every_thing_is_on_the_art_list() -> void:
	var art: Node = root.get_node("Art")
	for id in content.props:
		# Through Art's own slug, as prop_texture() looks it up: the ids use
		# hyphens like every other drawing's, and room.json's keys may not.
		check(art.manifest.has("prop/" + art.slug(str(id))), "prop '%s' has no entry in art_manifest.json — re-run tests/gen_art_manifest.gd" % id)
	done()


func _test_once_stacking_and_the_cap() -> void:
	var room: Array = []
	var coat := {"becomes": "their_coat", "at": "hook", "once": true}
	check(not RoomTraces.place(room, coat).is_empty(), "the first coat goes on the hook")
	check(RoomTraces.place(room, coat).is_empty(), "their coat only comes off the once")
	var coins := {"becomes": "coins", "at": "beside"}
	var a: Dictionary = RoomTraces.place(room, coins)
	var b: Dictionary = RoomTraces.place(room, coins)
	check(a["jitter"] != b["jitter"], "a second pile of coins should sit beside the first, not on it")
	for _i in RoomTraces.MAX_TRACES + 5:
		RoomTraces.place(room, coins)
	check(room.size() == RoomTraces.MAX_TRACES, "the table holds %d things, has %d" % [RoomTraces.MAX_TRACES, room.size()])
	check(str(room[0].get("prop")) == "coins", "the OLDEST thing is cleared first — the coat went")
	check(RoomTraces.place(room, {"becomes": "no_such_thing", "at": "hook"}).is_empty(), "a thing nobody defined is not placed")
	done()


# ── in play ──────────────────────────────────────────────────────────────

## Through the real screen: the tea becomes their cup, on the fight; TAKE IT
## BACK takes it away; the chair rattles the room.
func _test_laying_the_tea_leaves_a_cup_and_taking_it_back_takes_it() -> void:
	var r := await _reading_with("Pour The Tea", 0)
	r._lay("probe")
	var room: Array = run.state["f"].get("room", [])
	check(room.size() == 1 and str(room[0].get("prop")) == "their_cup", "Pour The Tea should leave their cup, the room holds %s" % [room])
	run.unlay()
	check(run.state["f"].get("room", []).is_empty(), "TAKE IT BACK should take the cup away too")
	r.free()

	r = await _reading_with("Kick The Chair Over", 0)
	r._lay("probe")
	check(int(run.state["f"].get("room_jolt", 0)) > 0, "kicking the chair over should jolt the room")
	check(run.state["f"].get("room", []).is_empty(), "…and leave nothing behind")
	r.free()
	done()


func _test_a_card_that_cannot_be_paid_for_leaves_nothing() -> void:
	var r := await _reading_with("Pour The Tea", 99)
	r._lay("probe")
	check(run.state["f"].get("room", []).is_empty(), "a card that was not laid should not become anything")
	r.free()
	done()


## THE LAYER COVERS THE SCREEN. It was once 0x0 — anchors set after it was in the
## tree keep its rect — and drew every thing into nothing. Nothing else failed.
func _test_the_reading_screen_draws_the_room_over_the_whole_screen() -> void:
	var r := await _reading_with("Pour The Tea", 0)
	var layer: Control = r.find_child("RoomTraces", true, false)
	check(layer != null, "the reading screen should have a RoomTraces layer")
	if layer != null:
		await process_frame
		check(layer.size.is_equal_approx(Vector2(root.size)), "the layer should cover the screen, it is %s" % layer.size)
		check(layer.traces == run.state["f"].get("room", layer.traces), "and draw the fight's own list")
	r.free()
	done()


## A thing on its way is not drawn yet; one from an earlier session's clock
## (born ahead of now by more than any journey takes) is drawn at once.
func _test_arrival_times_and_an_older_clock() -> void:
	var now := Time.get_ticks_msec()
	check(RoomTraces._age({"born": now + 500}, now) < 0.0, "a thing half a second away has not arrived")
	check(RoomTraces._age({"born": now - 1000}, now) >= 1.0, "a thing that landed a second ago has")
	check(RoomTraces._age({"born": now + 60000}, now) > RoomTraces.FADE_IN, "a thing from a clock a minute ahead is treated as long arrived")
	done()


func _test_the_room_is_saved_with_the_fight() -> void:
	var r := await _reading_with("Pour The Tea", 0)
	r._lay("probe")
	r.free()
	var save: Node = root.get_node("Save")
	save._write()
	run.state = run.fresh()
	var res: Dictionary = save.restore()
	check(res.get("ok", false), "the fight should restore")
	var room: Array = run.state.get("f", {}).get("room", [])
	check(room.size() == 1 and str(room[0].get("prop")) == "their_cup", "their cup should still be on the table after a reload, room is %s" % [room])
	done()


# ── the journey ──────────────────────────────────────────────────────────

func _test_the_journey_is_a_copy_of_the_card_that_goes_away() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var face: Control = load("res://scenes/UIKit.gd").card_face(content.get_card("Pour The Tea"), func(): pass)
	face.position = Vector2(200, 500)
	host.add_child(face)
	await process_frame
	var layer: Node = feel.get_node("FeelLayer")
	# The tests above laid cards through the reading screen, and their copies
	# may still be on their way: count only the ones this one makes.
	await create_timer(1.2).timeout
	var already := layer.get_children()
	var rule: Dictionary = feel.trace_rule(content.get_card("Pour The Tea"))
	check(str(rule.get("becomes", "")) == "their_cup", "Pour The Tea should have a rule")
	feel.become(face, rule, Vector2(700, 300))
	var ghosts := layer.get_children().filter(func(c): return c is PanelContainer and not already.has(c))
	check(ghosts.size() == 1, "one copy of the card should be on its way, found %d" % ghosts.size())
	if ghosts.size() == 1:
		var g: Control = ghosts[0]
		check(g.material is ShaderMaterial, "the copy should come apart through the dissolve shader")
		check(g.find_children("*", "CanvasItem", true, false).all(func(n): return n.use_parent_material),
			"every part of the copy — its words too — should dissolve with it")
		check(g.focus_mode == Control.FOCUS_NONE and g.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the copy should take neither focus nor clicks")
	await create_timer(feel.arrival_of(rule) + 0.3).timeout
	check(layer.get_children().filter(func(c): return c is PanelContainer).is_empty(), "the copy should be gone once it has arrived")

	root.get_node("Settings").set_value("animation_scale", 0.0)
	check(is_equal_approx(feel.arrival_of(rule), 0.0), "with motion off the thing simply appears")
	feel.become(face, rule, Vector2(700, 300))
	check(layer.get_children().filter(func(c): return c is PanelContainer).is_empty(), "and nothing makes the journey")
	host.free()
	done()


# ── helpers ──────────────────────────────────────────────────────────────

## A reading screen whose first card in hand is `card_name`, costing `cost`.
func _reading_with(card_name: String, cost: int) -> Control:
	run.state = run.fresh("the room remembers")
	run.pick_reader(0)
	run.take_pick(0)
	for i in run.state["options"].size():
		if run.state["options"][i]["kind"] in ["sitter", "elite"]:
			run.choose(i)
			break
	var c: Dictionary = content.get_card(card_name).duplicate(true)
	c["uid"] = "probe"
	c["cost"] = cost
	run.state["f"]["hand"][0] = c
	var r: Control = load("res://scenes/Reading.tscn").instantiate()
	root.add_child(r)
	await process_frame
	await process_frame
	return r
