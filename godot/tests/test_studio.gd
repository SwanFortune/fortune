## The studio (scenes/Studio.gd): the screen whoever draws and animates for the
## game works in.
##   godot --headless --path godot -s tests/test_studio.gd
##
## Everything it promises an artist is measured here, because an artist is the
## person least likely to report that a tool quietly stopped doing its job:
##   - a file saved into a watched folder is noticed, and the screen reloads;
##   - the templates come out at exactly the sizes the manifest's spec asks for;
##   - the file name a tile hands over is the one the game will look for;
##   - every moment button plays its moment;
##   - stepping through cards does not free the button that was pressed;
##   - slow motion does not outlive the screen.
extends "res://tests/harness.gd"

var content: Node
var feel: Node
var art: Node
var Studio = null
var _probe_dir := "user://mods/_studio_probe"


func setup() -> void:
	content = root.get_node("Content")
	feel = root.get_node("Feel")
	art = root.get_node("Art")
	content.reload()
	Studio = load("res://scenes/Studio.gd")
	root.size = Vector2i(1280, 720)


func teardown() -> void:
	_remove(_probe_dir)
	Engine.time_scale = 1.0
	content.reload()


func _test_a_saved_file_is_noticed() -> void:
	var before: Dictionary = Studio.snapshot()
	DirAccess.make_dir_recursive_absolute(_probe_dir)
	var f := FileAccess.open(_probe_dir.path_join("shard.png"), FileAccess.WRITE)
	f.store_string("not really a png")
	f.close()
	var after: Dictionary = Studio.snapshot()
	var changed: Array = Studio.changed_files(before, after)
	check(changed.has("shard.png"), "a new file in the mod folder should be noticed, saw %s" % [changed])
	check(Studio.changed_files(after, Studio.snapshot()).is_empty(), "nothing changed, nothing to report")
	_remove(_probe_dir)
	check(Studio.changed_files(after, Studio.snapshot()).has("shard.png"), "a file that went should be noticed too")
	done()


## The screen, not just the helper: a change makes it reload the content and
## say which file it was.
func _test_the_screen_reloads_when_a_file_changes() -> void:
	var s: Control = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	var reloads := [0]
	var count := func(): reloads[0] += 1
	content.reloaded.connect(count)
	DirAccess.make_dir_recursive_absolute(_probe_dir)
	var f := FileAccess.open(_probe_dir.path_join("ember.png"), FileAccess.WRITE)
	f.store_string("x")
	f.close()
	s._look_for_changes()
	check(reloads[0] == 1, "a changed file should reload the content once, reloaded %d times" % reloads[0])
	check(s._toast.text.contains("ember.png"), "the screen should say what changed, says '%s'" % s._toast.text)
	s._look_for_changes()
	check(reloads[0] == 1, "no change, no reload")
	content.reloaded.disconnect(count)
	_remove(_probe_dir)
	s.queue_free()
	await process_frame
	done()


## The sizes come from the manifest's spec, the one place they are written, so
## this reads them from there too and holds each template to them.
func _test_the_templates_are_the_sizes_the_game_wants() -> void:
	var dir := "user://_studio_templates_probe"
	var made: Array = Studio.make_templates(dir)
	check(made.size() >= 6, "two art kinds, a still and a sheet each, and two particle sheets: made %d" % made.size())
	for block_name in art.spec:
		var block = art.spec[block_name]
		if not (block is Dictionary) or not block.has("pixels"):
			continue
		var wh: PackedStringArray = str(block["pixels"]).split("x")
		var want := Vector2i(int(wh[0]), int(wh[1]))
		var kind := str(block_name).trim_suffix("_art")
		var still := made.filter(func(p): return str(p).get_file().begins_with(kind + "_") and not str(p).contains("sheet"))
		var sheet := made.filter(func(p): return str(p).get_file().begins_with(kind + "_sheet"))
		check(still.size() == 1 and sheet.size() == 1, "one still and one sheet for %s" % kind)
		if still.size() == 1:
			check(Image.load_from_file(still[0]).get_size() == want, "%s should be %s" % [still[0].get_file(), want])
		if sheet.size() == 1:
			check(Image.load_from_file(sheet[0]).get_size() == Vector2i(want.x * 4, want.y * 2), "%s should be 4x2 frames of %s" % [sheet[0].get_file(), want])
	_remove(dir)
	done()


## The path a tile copies is the path Art.texture() reads, for every asset.
func _test_the_copied_path_is_where_the_game_looks() -> void:
	for id in art.manifest:
		var said: String = Studio.expected_file(id)
		var entry: Dictionary = art.manifest[id]
		var looked: String = str(entry.get("file", "")) if str(entry.get("file", "")) != "" else art.ART_ROOT + id + ".png"
		check("res://" + said == looked or said == looked.trim_prefix("res://"), "%s: the studio says %s, the game reads %s" % [id, said, looked])
	done()


func _test_every_moment_button_plays() -> void:
	var s: Control = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	await process_frame
	root.get_node("Settings").set_value("haptics", true)
	root.get_node("Settings").set_value("haptic_strength", 1.0)
	for event in feel.EVENTS:
		var b := _button(s, event)
		check(b != null, "there should be a button for '%s'" % event)
		if b == null:
			continue
		b.pressed.emit()
		check(s._last_event == event, "pressing '%s' should play it" % event)
		check(s._preset_text.text.begins_with(event), "and describe it")
	s.queue_free()
	await process_frame
	done()


## ▶ replaces the card and its name, and nothing else: the button pressed is
## still there, still the same node, after the press.
func _test_stepping_through_cards_keeps_the_button() -> void:
	var s: Control = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	var next := _button(s, "▶")
	var name_before: String = s._card_name.text
	next.pressed.emit()
	await process_frame
	check(is_instance_valid(next) and not next.is_queued_for_deletion(), "the ▶ that was pressed should survive its own press")
	check(s._card_name.text != name_before, "and the card should have changed")
	s.queue_free()
	await process_frame
	done()


func _test_slow_motion_does_not_outlive_the_screen() -> void:
	var s: Control = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	s._toggle_slow()
	check(is_equal_approx(Engine.time_scale, Studio.SLOW), "slow motion should slow the clock")
	s.free()
	check(is_equal_approx(Engine.time_scale, 1.0), "leaving the studio should put the clock back, it is %s" % Engine.time_scale)
	done()


## A rule switched off in feel.json is still shown, dressed, so it can be
## judged; the pane has one row per rule.
func _test_every_card_state_is_shown_dressed() -> void:
	var s: Control = load("res://scenes/Studio.tscn").instantiate()
	root.add_child(s)
	await process_frame
	s._show("hand")
	await process_frame
	await process_frame
	var dressed := 0
	for n in _all(s, []):
		if n is PanelContainer and (n.has_meta("_feel_tween") or n.get_children().any(func(c): return c is CPUParticles2D)):
			dressed += 1
	check(dressed == content.card_states.size(), "every rule, off ones included, should be shown on a dressed card: %d of %d" % [dressed, content.card_states.size()])
	s.queue_free()
	await process_frame
	done()


func _button(n: Node, text: String) -> Button:
	for c in _all(n, []):
		if c is Button and c.text == text and not c.is_queued_for_deletion():
			return c
	return null


func _all(n: Node, out: Array) -> Array:
	for c in n.get_children():
		out.append(c)
		_all(c, out)
	return out


func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
