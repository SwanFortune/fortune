## How the game feels: particles, card motion, haptics (autoload/Feel.gd).
##   godot --headless --path godot -s tests/test_feel.gd
##
## Everything Feel does is either on screen for half a second or in a motor
## nobody can read back, so none of it fails a test by accident. Each guarantee
## the file makes is measured here instead:
##   - the registry and Feel.EVENTS agree, both ways, and every event is fired
##     from somewhere in the game;
##   - nothing the registry names is missing (the same load-time check the game
##     makes, which tests/run_all.sh fails on);
##   - every motion ends where it started — a card left 6% too big after a pulse
##     is the kind of thing nobody sees until it is everywhere;
##   - bursts go on Feel's layer, free themselves, respect the cap, and do not
##     happen at all when the player said no or when motion is off;
##   - haptics respect their own switch and strength and ignore game speed;
##   - card_states match the way their comment says they do;
##   - a moment whose target was freed before it came is dropped, silently.
extends "res://tests/harness.gd"

var feel: Node
var content: Node
var settings: Node
var _before := {}


func setup() -> void:
	feel = root.get_node("Feel")
	content = root.get_node("Content")
	settings = root.get_node("Settings")
	content.reload()
	for key in ["particles", "haptics", "haptic_strength", "animation_scale"]:
		_before[key] = settings.get_value(key)
	# Wide enough that a Control has a size to be the centre of.
	root.size = Vector2i(1280, 720)


func before_each(_name: String) -> void:
	settings.set_value("particles", true)
	settings.set_value("haptics", true)
	settings.set_value("haptic_strength", 1.0)
	settings.set_value("animation_scale", 1.0)
	feel.haptic_log.clear()


func teardown() -> void:
	for key in _before:
		settings.set_value(key, _before[key])
	content.reload()


# ── the registry ─────────────────────────────────────────────────────────

func _test_the_registry_covers_exactly_the_events() -> void:
	for event in feel.EVENTS:
		check(content.feel.has(event), "feel.json has no entry for '%s' — it would never be felt" % event)
	for event in content.feel:
		check(feel.EVENTS.has(event), "feel.json has '%s', which nothing fires" % event)
	done()


## Every event is fired from the game's own source — by FEEL. The first version
## of this looked for the event's name anywhere in the source and passed with
## the map's Feel.play("knock") deleted, because Audio.play("knock") is on the
## line below: a needle that matched the wrong call. So a name only counts on a
## line that calls Feel, or inside a `_feel_*` helper — the convention for code
## that works out which moment it is before playing it (Reading._feel_row()).
## The two link events are built as "card_link_" + the link, so that prefix
## counts for both.
func _test_every_event_is_fired_from_somewhere() -> void:
	var feel_lines: PackedStringArray = []
	for dir in ["res://scenes/", "res://autoload/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "Feel.gd":
				continue
			var in_helper := false
			for line in FileAccess.get_file_as_string(dir + f).split("\n"):
				if line.begins_with("func "):
					in_helper = line.begins_with("func _feel_")
				if (in_helper or line.contains("Feel.")) and not line.strip_edges().begins_with("#"):
					feel_lines.append(line)
	var said := "\n".join(feel_lines)
	for event in feel.EVENTS:
		var fired: bool = said.contains('"%s"' % event)
		if event.begins_with("card_link_"):
			fired = fired or said.contains('"card_link_" +')
		check(fired, "nothing in scenes/ or autoload/ hands '%s' to Feel" % event)
	done()


func _test_nothing_the_registry_names_is_missing() -> void:
	var said: Array = feel.problems()
	check(said.is_empty(), "the shipped feel.json has problems:\n  %s" % "\n  ".join(said))
	# And it can see one: a preset nobody defines, a motion kind nobody wrote.
	content.feel["card_lay"] = {"particles": "no_such_burst"}
	content.motions["broken"] = {"kind": "wobble"}
	said = feel.problems()
	check(said.any(func(l): return l.contains("no_such_burst")), "a missing particle preset should be reported")
	check(said.any(func(l): return l.contains("wobble")), "an unknown motion kind should be reported")
	content.reload()
	done()


## A MOD'S DRAWING, from user:// — which Godot's importer never sees, so it has
## to be read as bytes. And a texture that is named and not there is reported.
func _test_a_particle_drawing_loads_from_a_mod_folder() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var path := "user://feel_probe.png"
	img.save_png(path)
	content.particles["probe"] = {"texture": path}
	feel._textures.clear()
	var tex: Texture2D = feel.texture_of("probe")
	check(tex != null and tex.get_width() == 8, "a PNG in user:// should load as the preset's drawing")
	content.particles["probe"] = {"texture": "user://no_such_drawing.png"}
	feel._textures.clear()
	check(feel.texture_of("probe").get_width() == 32, "a missing drawing should fall back to the soft dot")
	check(feel.problems().any(func(l): return l.contains("no_such_drawing")), "…and be reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	content.reload()
	done()


func _test_the_placeholders_are_counted() -> void:
	var summary: Dictionary = feel.status_summary()
	var total := 0
	for st in summary:
		total += int(summary[st])
		check(feel.STATUSES.has(st), "status '%s' is not in the vocabulary" % st)
	check(total == content.particles.size(), "status_summary counted %d of %d presets" % [total, content.particles.size()])
	done()


# ── motion ───────────────────────────────────────────────────────────────

## EVERY KIND ENDS WHERE IT BEGAN — scale, rotation and brightness. Run to the
## end at once with custom_step, so this is a measurement and not a wait.
func _test_every_motion_ends_where_it_started() -> void:
	var host := _host()
	for kind in feel.MOTION_KINDS:
		# breathe never ends, and keys end wherever the animator put them —
		# each has its own test below.
		if kind in ["breathe", "keys"]:
			continue
		content.motions["probe"] = {"kind": kind, "amount": 0.2, "duration": 0.3, "count": 3}
		var card := _card(host)
		card.scale = Vector2(1.1, 1.1)
		card.rotation_degrees = 2.0
		card.modulate = Color(0.9, 0.9, 0.9, 1.0)
		var tw: Tween = feel.move(card, "probe")
		check(tw != null, "'%s' should have made a tween" % kind)
		if tw != null:
			tw.custom_step(10.0)
		check(card.scale.is_equal_approx(Vector2(1.1, 1.1)), "'%s' left the card at scale %s" % [kind, card.scale])
		check(is_equal_approx(card.rotation_degrees, 2.0), "'%s' left the card turned %s°" % [kind, card.rotation_degrees])
		check(card.modulate.is_equal_approx(Color(0.9, 0.9, 0.9, 1.0)), "'%s' left the card tinted %s" % [kind, card.modulate])
		card.free()
	host.free()
	content.reload()
	done()


## KEYFRAMES go where each key says, relative to where the card started, in
## order — measured at the middle key and at the end.
func _test_keyframes_hit_their_keys() -> void:
	var host := _host()
	var card := _card(host)
	card.scale = Vector2(2, 2)
	card.rotation_degrees = 10.0
	content.motions["probe"] = {"kind": "keys", "keys": [
		{"at": 0.0},
		{"at": 0.2, "scale": 1.5, "turn": 30, "bright": 2.0, "ease": "out"},
		{"at": 0.5, "scale": 1.0, "turn": 0, "bright": 1.0, "alpha": 0.5, "ease": "back"},
	]}
	var tw: Tween = feel.move(card, "probe")
	check(tw != null, "a keyed motion should make a tween")
	if tw != null:
		tw.custom_step(0.2)
		check(card.scale.is_equal_approx(Vector2(3, 3)), "at 0.2s the card should be 1.5x its starting 2x, is %s" % card.scale)
		check(is_equal_approx(card.rotation_degrees, 40.0), "at 0.2s it should be 30° past its starting 10°, is %s" % card.rotation_degrees)
		tw.custom_step(1.0)
		check(card.scale.is_equal_approx(Vector2(2, 2)), "at the end it should be back to 2x, is %s" % card.scale)
		check(is_equal_approx(card.modulate.a, 0.5), "the last key asked for half opacity, got %s" % card.modulate.a)
	content.motions["probe"] = {"kind": "keys", "keys": [{"at": 0.0}]}
	check(feel.move(card, "probe") == null, "one key is a pose, not a motion: nothing should play")
	content.motions["probe"] = {"kind": "keys", "keys": [{"at": 0}, {"at": 0.2, "ease": "wobbly"}]}
	check(feel.problems().any(func(l): return l.contains("wobbly")), "an easing nobody defined should be reported")
	host.free()
	content.reload()
	done()


## A FLIPBOOK, an additive glow, colour and size over life: what an animator
## hands over becomes the emitter's material and curves, and a drawing that
## does not divide into its grid is reported rather than played sliced.
func _test_a_flipbook_particle_is_built_from_its_drawing() -> void:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var path := "user://feel_sheet.png"
	img.save_png(path)
	content.particles["probe"] = {"texture": path, "frames": [4, 2], "cycles": 2, "blend": "add",
		"colors": ["#ffffff", "#ff8800", "#ff000000"], "size_over_life": [0, 1, 0]}
	feel._textures.clear()
	var p: CPUParticles2D = feel.burst("probe", Vector2(100, 100))
	check(p != null, "the flipbook preset should burst")
	if p != null:
		var mat := p.material as CanvasItemMaterial
		check(mat != null and mat.particles_animation, "a flipbook needs particles_animation on")
		if mat != null:
			check(mat.particles_anim_h_frames == 4 and mat.particles_anim_v_frames == 2, "a 4x2 grid of frames")
			check(mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "blend: add should light what is under it")
		check(is_equal_approx(p.anim_speed_min, 2.0), "cycles: 2 should play the flipbook twice a life")
		check(p.color_ramp != null and p.color_ramp.get_point_count() == 3, "three colours, three stops")
		check(p.scale_amount_curve != null and p.scale_amount_curve.point_count == 3, "three sizes, three points")
		p.free()
	check(feel.problems().filter(func(l): return l.contains("'probe'")).is_empty(), "64x32 divides into 4x2: nothing to report")
	content.particles["probe"]["frames"] = [3, 2]
	check(feel.problems().any(func(l): return l.contains("does not divide")), "64 wide does not divide into 3 columns — say so")
	content.particles["probe"].erase("texture")
	check(feel.problems().any(func(l): return l.contains("no texture to cut")), "a flipbook with no drawing should be reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	content.reload()
	done()


func _test_breathe_keeps_going_until_stopped() -> void:
	var host := _host()
	var card := _card(host)
	var tw: Tween = feel.move(card, "breathe")
	check(tw != null, "the shipped 'breathe' should make a tween")
	if tw != null:
		tw.custom_step(20.0)
		check(tw.is_valid() and tw.is_running(), "breathe should still be going after twenty seconds")
		feel.stop(card)
		check(not tw.is_valid(), "stop() should have killed it")
	host.free()
	done()


func _test_no_motion_when_motion_is_off() -> void:
	var host := _host()
	var card := _card(host)
	settings.set_value("animation_scale", 0.0)
	check(feel.move(card, "press") == null, "INSTANT is the reduced-motion setting: nothing should move")
	host.free()
	done()


# ── particles ────────────────────────────────────────────────────────────

func _test_a_burst_lands_on_its_layer_and_frees_itself() -> void:
	var p: CPUParticles2D = feel.burst("sparks", Vector2(300, 200), Color.RED)
	check(p != null, "a burst of a shipped preset should be made")
	if p == null:
		done()
		return
	check(p.get_parent() != null and p.get_parent().name == "FeelLayer", "a burst belongs on Feel's layer, so it outlives a screen rebuild")
	check(p.one_shot and p.emitting, "a burst should be one shot, and going")
	check(p.texture != null, "with no drawing, a burst should still have the soft dot")
	await create_timer(p.lifetime + 1.5).timeout
	check(not is_instance_valid(p), "a burst should be gone once it has finished")
	done()


func _test_no_particles_when_the_player_said_no() -> void:
	settings.set_value("particles", false)
	check(feel.burst("sparks", Vector2(10, 10)) == null, "particles off should mean no burst")
	settings.set_value("particles", true)
	settings.set_value("animation_scale", 0.0)
	check(feel.burst("sparks", Vector2(10, 10)) == null, "INSTANT should mean no burst, particles being motion")
	check(feel.burst("no_such_burst", Vector2(10, 10)) == null, "an unknown preset should be nothing, not an error")
	done()


func _test_the_cap_holds() -> void:
	var made := 0
	for _i in feel.MAX_LIVE + 10:
		if feel.burst("bloom", Vector2(100, 100)) != null:
			made += 1
	var layer: Node = feel.get_node("FeelLayer")
	check(layer.get_child_count() <= feel.MAX_LIVE, "%d bursts alive, over the cap of %d" % [layer.get_child_count(), feel.MAX_LIVE])
	for c in layer.get_children():
		c.free()
	done()


func _test_a_burst_without_a_place_is_not_made() -> void:
	var layer: Node = feel.get_node("FeelLayer")
	var before := layer.get_child_count()
	feel.play("coin")    # no target, no `at`: would go off in the corner
	check(layer.get_child_count() == before, "a burst with nowhere to be should not be made")
	check(not feel.haptic_log.is_empty(), "…but the moment should still be felt")
	done()


# ── haptics ──────────────────────────────────────────────────────────────

func _test_haptics_follow_their_own_switch_and_strength() -> void:
	check(feel.rumble("thud") == 1, "thud is one pulse")
	check(feel.haptic_log.size() == 1, "and it should be in the log")
	var full: Dictionary = feel.haptic_log.back()
	settings.set_value("haptic_strength", 0.5)
	feel.rumble("thud")
	var half: Dictionary = feel.haptic_log.back()
	check(is_equal_approx(half["strong"], full["strong"] * 0.5), "strength 0.5 should halve the motor: %s then %s" % [full["strong"], half["strong"]])
	settings.set_value("haptics", false)
	check(feel.rumble("thud") == 0, "haptics off should play nothing")
	settings.set_value("haptics", true)
	settings.set_value("haptic_strength", 0.0)
	check(feel.rumble("thud") == 0, "strength 0 is off")
	done()


## Game speed is the reduced-MOTION setting; it must not silence the motors.
func _test_haptics_do_not_follow_the_motion_setting() -> void:
	settings.set_value("animation_scale", 0.0)
	check(feel.rumble("knock") == 2, "a knock is two pulses, motion or no motion")
	done()


func _test_a_pattern_keeps_its_rhythm() -> void:
	# The test before this one started a knock whose second half is still on
	# its way; let it land, then start clean.
	await create_timer(0.4).timeout
	feel.haptic_log.clear()
	feel.rumble("knock")
	check(feel.haptic_log.size() == 1, "the first knock is at once")
	await create_timer(0.35).timeout
	check(feel.haptic_log.size() == 2, "the second knock comes after the pause, %d so far" % feel.haptic_log.size())
	done()


# ── cards that animate on their own ──────────────────────────────────────

func _test_card_states_match_as_documented() -> void:
	var saved: Array = content.card_states
	content.card_states = [
		{"id": "skipped", "off": true, "when": {}},
		{"id": "truthy", "when": {"pierce": true}},
		{"id": "any_of", "when": {"link": ["same", "turn"]}},
		{"id": "equal", "when": {"r": "rare"}},
	]
	check(feel.card_state({}, {}).is_empty(), "an `off` rule must never match, even with nothing to test")
	check(feel.card_state({"pierce": true}).get("id") == "truthy", "true should match a truthy field")
	check(feel.card_state({"pierce": false}).is_empty(), "true should not match a false one")
	check(feel.card_state({}, {"link": "turn"}).get("id") == "any_of", "a list should match any of its values")
	check(feel.card_state({"link": "turn"}, {"link": "break"}).is_empty(), "ctx should win over the card's own field")
	check(feel.card_state({"r": "rare", "pierce": true}).get("id") == "truthy", "the FIRST rule that matches wins")
	content.card_states = saved
	done()


func _test_a_rare_card_in_hand_shimmers_and_a_common_one_does_not() -> void:
	var host := _host()
	var rare := _card(host)
	var common := _card(host)
	feel.dress_card(rare, {"r": "rare", "el": "fire"})
	feel.dress_card(common, {"r": "common", "el": "fire"})
	check(_emitters(rare) == 1, "a rare card should carry one standing emitter, has %d" % _emitters(rare))
	check(_emitters(common) == 0, "a common card should carry none")
	settings.set_value("particles", false)
	var quiet := _card(host)
	feel.dress_card(quiet, {"r": "rare"})
	check(_emitters(quiet) == 0, "with particles off, not even a rare card")
	host.free()
	done()


# ── the moment that never came ───────────────────────────────────────────

## The ledger schedules each line's feel ahead of time, and the player can skip
## it. A skipped line is freed before its moment; the moment must then be
## dropped — no error (a freed Node in a callable is one), and no rumble.
func _test_a_moment_whose_target_is_gone_is_dropped() -> void:
	var host := _host()
	var line := _card(host)
	feel.play_later(0.1, "card_pierce", line)
	host.free()
	await create_timer(0.3).timeout
	check(feel.haptic_log.is_empty(), "the pierce belonged to a line that was freed; nothing should have rumbled")
	done()


# ── helpers ──────────────────────────────────────────────────────────────

func _host() -> Control:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	return host


func _card(host: Control) -> Control:
	var c := PanelContainer.new()
	c.position = Vector2(200, 200)
	c.size = Vector2(120, 170)
	host.add_child(c)
	return c


func _emitters(n: Node) -> int:
	return n.get_children().filter(func(c): return c is CPUParticles2D).size()
