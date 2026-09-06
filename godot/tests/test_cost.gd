## WHAT THE INTERFACE COSTS: THE WORK IT REDOES, AND WHAT IT LEAVES BEHIND.
##
##     godot --headless --path godot -s tests/test_cost.gd
##
## Nothing had ever measured this. "The game is simple" was a claim, and the
## first measurement said the Library takes 220 milliseconds to build its list —
## which it was doing on every keystroke in the search box. Typing "lamp" was
## most of a second of frozen interface, and the first three lists were thrown
## away before anybody could read them. Selecting a card cost the same 220ms to
## move a coloured border from one row to another.
##
## Where the time goes was measured rather than guessed, and none of the obvious
## suspects were it: generating all fifty-seven cards' printed text is 1.7ms,
## the filters are 0.9ms, freeing the old rows is 9ms, and turning off text
## wrapping saves 25ms of the 204. The rest is the plain cost of building three
## hundred Control nodes in GDScript. There is no hot spot to fix — so the fix
## is to do it less often, and that is what this file guards.
##
## MOSTLY WITHOUT A STOPWATCH. A millisecond budget fails on a slow CI runner
## and passes on a fast one, which makes it a test that reports the weather —
## and this project has already had one failure it could not reproduce. So the
## two real guarantees are asserted by IDENTITY instead:
##
##   - a keystroke does not rebuild the list at all;
##   - selecting a card rebuilds two rows, and leaves the other fifty-five as
##     the very same node instances they were.
##
## Both are exact on any machine. The one timing check left is deliberately
## enormous — it is there to catch something going quadratic, not to police
## milliseconds.
extends SceneTree

## Loose on purpose. The Library measures ~220ms here; a runner half the speed
## of this one still has an order of magnitude of room. Anything over this is
## not a regression in degree, it is a different algorithm.
const ABSURD_MS := 2000.0

var content: Node
var failures: Array[String] = []


func _initialize() -> void:
	content = root.get_node("Content")
	await process_frame
	content.reload()
	root.get_node("CardEdits").revert_all()
	content.reload()
	root.size = Vector2i(1280, 720)

	await _test_screens_do_not_leave_nodes_behind()
	await _test_a_keystroke_does_not_rebuild_the_list()
	await _test_selecting_a_card_leaves_the_other_rows_alone()
	await _test_no_screen_takes_absurdly_long_to_build()

	for f in failures:
		printerr("FAIL: ", f)
	if failures.is_empty():
		print("ALL PASS — the interface rebuilds only what changed")
	quit(1 if not failures.is_empty() else 0)


## NOTHING IS LEFT BEHIND WHEN A SCREEN GOES.
##
## An unparented Node in GDScript is not reference-counted: nothing collects it,
## and it is not freed with the screen it was almost part of. card_face() built
## a footer row for the archetype badge and the tags, then parented it "if it
## has any children" — so every plain card, which most of the basics are, left
## an empty HBoxContainer behind. Once per card, on every hand, on every rebuild
## of the reading screen, for the whole of a session.
##
## It was found by counting, because there is nothing else to find it by: the
## game plays correctly, the screens look right, and the suite was green. Six
## rounds of building and freeing the reading screen took the orphan count from
## 0 to 6, 11, 19, 27, 34, 38.
##
## The screen is torn down ONE FRAME after it is built, which is the shape that
## catches this: the deal tween, the knock timer and the ledger's pacing are all
## still pending, and anything holding a reference it should not is still
## holding it. Freeing a settled screen would have found nothing.
##
## Godot's OBJECT_ORPHAN_NODE_COUNT is exact and the same on any machine, so
## unlike a timing budget this can be asserted at zero growth. (The suite's
## runner allows a "ObjectDB instances were leaked at exit" line, which is a
## different thing entirely — that is Godot tearing down a `-s` script with no
## main scene, and it says nothing about what happens while the game runs.)
func _test_screens_do_not_leave_nodes_behind() -> void:
	var run: Node = root.get_node("Run")
	var counts: Array[int] = []
	for cycle in 4:
		for n in 3:
			run.state = run.fresh("leak-%d-%d" % [cycle, n])
			run.pick_reader(0)
			run.take_pick(0)
			for i in run.state["options"].size():
				if run.state["options"][i]["kind"] in ["sitter", "elite"]:
					run.choose(i)
					break
			var instance: Node = load("res://scenes/Reading.tscn").instantiate()
			root.add_child(instance)
			await process_frame
			instance.queue_free()
			for i in 3:
				await process_frame
		counts.append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	# Compared from the SECOND cycle: the first pays for anything the engine
	# holds on to once — a shared theme, a font, a cached resource — and that is
	# not a leak, it is a cache. What matters is whether it keeps climbing.
	if counts[counts.size() - 1] > counts[0]:
		failures.append("building and freeing the reading screen leaves nodes behind: %s orphans after each round of three — an unparented Node is never collected, so this grows for as long as the game is open"
			% str(counts))


func _library() -> Node:
	var instance: Node = load("res://scenes/Library.tscn").instantiate()
	root.add_child(instance)
	return instance


## Typing narrows the list, but not once per letter. The search box waits for
## the typing to stop; this asserts that it waits at all, by typing and looking
## at the list in the same frame.
func _test_a_keystroke_does_not_rebuild_the_list() -> void:
	var instance := _library()
	for i in 5:
		await process_frame
	var box: Node = instance.get("_list_box")
	var before := box.get_child_count()
	var before_first: int = box.get_child(0).get_instance_id() if before > 0 else 0

	var field := _search_field(instance)
	if field == null:
		failures.append("the Library has no search box to type in")
		instance.queue_free()
		await process_frame
		return
	# Four keystrokes, as a player types them. Each one used to build the whole
	# list and throw it away.
	for text in ["l", "la", "lam", "lamp"]:
		field.text = text
		field.text_changed.emit(text)
		await process_frame

	if box.get_child_count() != before or (before > 0 and box.get_child(0).get_instance_id() != before_first):
		failures.append("typing four letters rebuilt the list — at ~220ms a rebuild that is most of a second of frozen interface, and the first three lists are thrown away unseen")

	# And then it must actually happen: a search box that never rebuilds is not
	# a fast search box, it is a broken one.
	await create_timer(float(instance.get("SEARCH_SETTLE")) + 0.3).timeout
	var after := box.get_child_count()
	if after >= before:
		failures.append("after the typing settled the list still shows %d of %d rows — the search does not narrow anything" % [after, before])
	instance.queue_free()
	await process_frame


## Moving the selection moves a coloured border. It used to rebuild every row in
## the list to do it. The rows that did not change must be the SAME NODES —
## nothing else proves they were not quietly rebuilt into identical copies.
func _test_selecting_a_card_leaves_the_other_rows_alone() -> void:
	var instance := _library()
	for i in 5:
		await process_frame
	var box: Node = instance.get("_list_box")
	var rows: Array = instance.call("_visible_rows")
	if rows.size() < 4:
		failures.append("only %d cards in the Library — this test needs a list to leave alone" % rows.size())
		instance.queue_free()
		await process_frame
		return

	var before := {}
	for child in box.get_children():
		before[child.get_instance_id()] = true

	var pick: Dictionary = rows[rows.size() - 2]
	instance.call("_select", pick["pool"], pick["card"]["n"])
	await process_frame

	var kept := 0
	for child in box.get_children():
		if before.has(child.get_instance_id()):
			kept += 1
	# The row selected and the row deselected are replaced; everything else
	# stays. A little slack for the case where both are the same row.
	var expected := box.get_child_count() - 2
	if kept < expected:
		failures.append("selecting a card replaced %d of %d rows — only the row pressed and the row left should change" % [box.get_child_count() - kept, box.get_child_count()])
	# And the mark did move, or "leave the rows alone" is satisfied by doing
	# nothing at all.
	if str(instance.get("_selected_name")) != str(pick["card"]["n"]):
		failures.append("selecting a card did not change which card is selected")
	instance.queue_free()
	await process_frame


## The catch-all. Not a budget — a tripwire for something having gone quadratic.
func _test_no_screen_takes_absurdly_long_to_build() -> void:
	var screens := {
		"library": "res://scenes/Library.tscn",
		"how to play": "res://scenes/HowToPlay.tscn",
		"sign": "res://scenes/SignSelect.tscn",
		"records": "res://scenes/Records.tscn",
	}
	var run: Node = root.get_node("Run")
	run.state = run.fresh("cost")
	for label: String in screens:
		var scene := load(screens[label])
		# One throwaway build first: the very first instantiate pays for script
		# compilation and resource loading that no later one repeats, and timing
		# that instead would measure the engine warming up.
		var warm: Node = scene.instantiate()
		root.add_child(warm)
		for i in 3:
			await process_frame
		warm.queue_free()
		await process_frame

		var started := Time.get_ticks_usec()
		var instance: Node = scene.instantiate()
		root.add_child(instance)
		await process_frame
		var took := (Time.get_ticks_usec() - started) / 1000.0
		instance.queue_free()
		await process_frame
		if took > ABSURD_MS:
			failures.append("%s took %.0fms to build (the tripwire is %.0fms) — that is not slow, that is a different algorithm" % [label, took, ABSURD_MS])
		else:
			print("  %-14s %6.1f ms" % [label, took])


func _search_field(node: Node) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit and (child as LineEdit).placeholder_text != "":
			return child
		var deeper := _search_field(child)
		if deeper != null:
			return deeper
	return null
