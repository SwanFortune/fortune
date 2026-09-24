## Autoload. How a game moment FEELS, as opposed to how it sounds (Audio.gd)
## or what it looks like at rest (Art.gd): the sparks when a card lands, the
## card that jolts as it goes through a wall, the rumble in a gamepad when the
## reading lands on the person opposite.
##
## THREE KINDS OF THING, ONE DOOR. `play("card_pierce", the_card)` looks the
## moment up in data/base/feel.json and does whatever that entry asks for:
##
##   particles  a burst of CPUParticles2D at the target, on Feel's own layer
##   motion     a short tween on the target itself: pulse, shake, tilt, flash, hop
##   haptic     a pattern of gamepad rumble (and a phone's vibrator, if any)
##
## Any of the three may be absent; an entry with none is a moment that has been
## named and not yet given a feel, which is where most of them start.
##
## THE SAME CONTRACT AS Audio.play(): an unknown event, a missing preset, a
## missing texture and an empty registry do nothing at all. The game is fully
## playable with feel.json deleted. What is WRONG in the registry — a preset
## name nothing defines — is said once, at load, as a warning, and
## tests/run_all.sh fails on the warning; see _say_what_does_not_resolve().
##
## CARDS THAT ANIMATE ON THEIR OWN. dress_card() is the other half: while a
## card sits in the hand, the `card_states` rules decide whether it carries a
## looping motion or a standing emitter — a rare card that shimmers, a card that
## would continue the line breathing. Those are data too, so which cards move
## is a design decision made in a JSON file and not in this one.
##
## THE PLAYER DECIDES. Particles and card motion stop entirely when the game
## speed is INSTANT (the reduced-motion setting, see UIKit.motion_off()) or when
## `particles` is off; haptics have their own switch and strength and do NOT
## follow the motion setting, because someone who cannot watch things move may
## very much want to feel them.
##
## EVERYTHING HERE IS A PLACEHOLDER until someone who draws decides otherwise.
## Each particle preset carries a `status` in the same vocabulary as the audio,
## a `texture` slot that is empty until a drawing lands in it, and a procedural
## soft dot in the meantime. docs/FEEL_GUIDE.md is the handover.
extends Node

## The moments the game can announce, and what each one is FOR. The authority,
## as Audio.EVENTS is for sound: data/base/feel.json must cover exactly these
## keys, which tests/test_feel.gd asserts in both directions — a renamed event
## would otherwise silently stop being felt, and an entry for an event nobody
## fires would sit in the file looking like it worked.
const EVENTS := {
	"card_draw": "a card arriving in hand — fires once per card dealt, so keep it light",
	"card_lay": "a card leaving the hand for the table",
	"card_link_same": "read out: a card continuing the element of the one before it",
	"card_link_turn": "read out: a card turning forward round the ring",
	"card_pierce": "read out: a card going straight through their denial",
	"card_bank": "read out: a card paid as faith rather than composure",
	"card_exhaust": "read out: a ONCE card spoken for good",
	"wall_absorb": "read out: their denial holding off the front of the reading",
	"reading_resolve": "read out: what actually reaches them — the moment the reading pays",
	"sitter_win": "they go home whole",
	"sitter_lose": "they leave as they came",
	"knock": "somebody at the front door",
	"coin": "centimes changing hands",
}

## The motions a preset may name as its `kind`. Every one of them is a tween on
## scale, rotation or modulate and NEVER on position: the hand is laid out by
## containers, which put a card back where they want it on the next layout pass
## (see Reading._lift()). Each returns the card to exactly where it started.
const MOTION_KINDS := {
	"pulse": "grows by `amount` and settles back",
	"hop": "grows by `amount` with an overshoot, like being picked up and set down",
	"shake": "rocks by `amount` degrees, `count` times, dying away",
	"tilt": "leans `amount` degrees and comes back",
	"flash": "brightens by `amount` and fades back",
	"breathe": "LOOPS: brightens by `amount` and back, for as long as the card is there",
	"keys": "keyframes, as an animator writes them: `keys` is a list of {at, scale, turn, bright, alpha, ease}",
}

## The curves a keyframe may ask for on its way IN, by the names an animator
## uses. Each is [transition, ease].
const EASES := {
	"linear": [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT],
	"in": [Tween.TRANS_QUAD, Tween.EASE_IN],
	"out": [Tween.TRANS_QUAD, Tween.EASE_OUT],
	"in_out": [Tween.TRANS_QUAD, Tween.EASE_IN_OUT],
	"back": [Tween.TRANS_BACK, Tween.EASE_OUT],
	"elastic": [Tween.TRANS_ELASTIC, Tween.EASE_OUT],
	"bounce": [Tween.TRANS_BOUNCE, Tween.EASE_OUT],
	"snap": [Tween.TRANS_EXPO, Tween.EASE_OUT],
}

## What a particle preset's `status` may say. The same words the audio uses, so
## a person handing over work has one vocabulary for both.
const STATUSES := {
	"placeholder": "a procedural stand-in, meant to be replaced",
	"wip": "drawn, but not the version that ships",
	"final": "delivered",
}

## The status assumed for a preset that does not say. Counted as outstanding
## work rather than credited as finished, as Audio.UNDELIVERED is.
const UNDELIVERED := "placeholder"

## Where `texture` paths resolve when they are bare filenames.
const TEXTURE_ROOT := "res://assets/particles/"

## Above Table (the room) and every screen, below nothing that matters: the
## tooltips and popups Godot draws are their own windows.
const LAYER := 90

## A cap on bursts alive at once. A reading of six cards, each with a link and
## a pierce, is a dozen bursts inside two seconds; a mod that set `amount` to
## 500 on all of them should cost frames, not the machine.
const MAX_LIVE := 24

## How many haptic pulses the log keeps. See `haptic_log`.
const HAPTIC_LOG := 64

## Every pulse this session has ASKED for, newest last: {weak, strong,
## seconds, devices}. There is no way to read a gamepad's motor back, so this
## is what tests/test_feel.gd and the settings probe can observe. It is
## recorded even when no pad is connected — the request is what is under test.
var haptic_log: Array = []

var _layer: CanvasLayer
var _dot: Texture2D
var _textures := {}
var _last_pad := -1
var _uikit = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "FeelLayer"
	_layer.layer = LAYER
	add_child(_layer)
	_dot = _soft_dot(32)
	# Content is earlier in the autoload order and has already loaded, so the
	# first check is made here rather than waiting for a reload that may never
	# come — the same trap Audio fell into (see Audio.gd, reload()).
	Content.reloaded.connect(_on_reloaded)
	_on_reloaded()


func _on_reloaded() -> void:
	_textures.clear()
	_say_what_does_not_resolve()


## The gamepad the player is actually holding, so a second pad left plugged in
## does not buzz on the desk. Read, never consumed.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_last_pad = event.device


# ── the one door ─────────────────────────────────────────────────────────

## Does whatever feel.json says `event` feels like, at `target`.
##
## `target` is the Control the moment happened to — a card face, a line of the
## reading ledger — and may be null for a moment that has no place on screen
## (a knock). `ctx` may carry `el` (the element the colour "element" means) and
## `at` (a global position to use when there is no target).
func play(event: String, target: Control = null, ctx: Dictionary = {}) -> void:
	var rec: Dictionary = Content.feel.get(event, {})
	if rec.is_empty():
		return
	var colour := _colour(str(rec.get("color", "")), ctx, target)
	var motion := str(rec.get("motion", ""))
	if motion != "" and _alive(target):
		move(target, motion)
	var particles := str(rec.get("particles", ""))
	# A burst needs somewhere to be. With no target and no `at` it would go off
	# in the top-left corner of the screen, which is worse than nothing.
	if particles != "" and (_alive(target) or ctx.has("at")):
		var at: Vector2 = ctx.get("at", Vector2.ZERO)
		var extent := Vector2.ZERO
		if _alive(target):
			at = target.get_global_rect().get_center()
			extent = target.size * 0.5
		burst(particles, at, colour, extent)
	var haptic := str(rec.get("haptic", ""))
	if haptic != "":
		rumble(haptic)
	var hands := str(rec.get("hands", ""))
	if hands != "":
		gesture(hands)


## play(), `seconds` from now at the game's speed — the reading's ledger is
## paced, and each line should feel like something as it is written.
##
## Holds the target by its instance id, never by reference. The reading can be
## skipped, which frees every line before its moment comes; a freed Node bound
## into a callable is an ERROR when the timer fires (see UIKit.after()), and a
## moment whose line is gone was skipped, so it is dropped whole — rumble too.
func play_later(seconds: float, event: String, target: Control = null, ctx: Dictionary = {}) -> void:
	if seconds <= 0.0:
		play(event, target, ctx)
		return
	var id := target.get_instance_id() if _alive(target) else 0
	get_tree().create_timer(_dur(seconds)).timeout.connect(_play_if_still_there.bind(event, id, ctx))


func _play_if_still_there(event: String, id: int, ctx: Dictionary) -> void:
	var target = instance_from_id(id) if id != 0 else null
	if id != 0 and not _alive(target):
		return
	play(event, target, ctx)


# ── particles ────────────────────────────────────────────────────────────

## One burst of the named preset at `at` (global canvas coordinates), tinted
## `colour`. `extent` is half the size of the thing it came from, for presets
## that emit from an area rather than a point.
##
## Returns the emitter, or null when nothing was made — particles off, motion
## off, an unknown preset, too many alive. It frees itself when it is done.
func burst(preset_name: String, at: Vector2, colour: Color = Color.WHITE, extent: Vector2 = Vector2.ZERO) -> CPUParticles2D:
	if not particles_on() or _layer.get_child_count() >= MAX_LIVE:
		return null
	var p := _emitter(preset_name, colour, extent)
	if p == null:
		return null
	p.one_shot = true
	p.position = at
	_layer.add_child(p)
	p.emitting = true
	# `finished` is the clean ending; the timer is for the case where it never
	# comes (the node is paused, or the engine skips it at speed 0). Connected
	# to the emitter's OWN method, never through a lambda that captures it: a
	# freed capture is an error when the timer fires (see UIKit.after()), while
	# a connection whose object is freed is simply dropped.
	p.finished.connect(p.queue_free)
	var ttl := p.lifetime / maxf(p.speed_scale, 0.01) + 1.0
	get_tree().create_timer(ttl).timeout.connect(p.queue_free)
	return p


## Whether a burst would be shown at all right now.
func particles_on() -> bool:
	return bool(Settings.get_value("particles")) and not _motion_off()


## A configured, unparented emitter, or null. Decided BEFORE it is built — an
## unparented Node is never collected (see CLAUDE.md), so every path that makes
## one must hand it to a parent.
func _emitter(preset_name: String, colour: Color, extent: Vector2) -> CPUParticles2D:
	var pre: Dictionary = Content.particles.get(preset_name, {})
	if pre.is_empty():
		return null
	var p := CPUParticles2D.new()
	p.amount = maxi(1, int(pre.get("amount", 12)))
	p.lifetime = maxf(0.05, float(pre.get("lifetime", 0.6)))
	p.explosiveness = clampf(float(pre.get("explosiveness", 0.9)), 0.0, 1.0)
	p.randomness = clampf(float(pre.get("randomness", 0.3)), 0.0, 1.0)
	var dir: Array = pre.get("direction", [0, -1])
	p.direction = Vector2(float(dir[0]), float(dir[1]))
	p.spread = float(pre.get("spread", 180))
	var speed: Array = pre.get("speed", [40, 120])
	p.initial_velocity_min = float(speed[0])
	p.initial_velocity_max = float(speed[1])
	var gravity: Array = pre.get("gravity", [0, 0])
	p.gravity = Vector2(float(gravity[0]), float(gravity[1]))
	p.damping_min = float(pre.get("damping", 0))
	p.damping_max = float(pre.get("damping", 0))
	var size: Array = pre.get("scale", [0.3, 0.6])
	p.scale_amount_min = float(size[0])
	p.scale_amount_max = float(size[1])
	p.angular_velocity_min = -float(pre.get("spin", 0))
	p.angular_velocity_max = float(pre.get("spin", 0))
	p.texture = texture_of(preset_name)
	p.color = colour
	# COLOUR OVER A PARTICLE'S LIFE. `colors` is a list of stops, evenly spaced
	# from birth to death, multiplied by the tint — ["#ffffff", "#ffaa33",
	# "#ff330000"] is a spark cooling to an ember and going out. Without it,
	# `fade` (on by default) takes it from opaque to nothing.
	var stops: Array = pre.get("colors", [])
	if stops.size() >= 2:
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array()
		ramp.colors = PackedColorArray()
		for i in stops.size():
			ramp.add_point(float(i) / (stops.size() - 1), Color(str(stops[i])))
		p.color_ramp = ramp
	elif bool(pre.get("fade", true)):
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
	# SIZE OVER LIFE: [at birth, …, at death], multiplying `scale`. [1, 0]
	# shrinks to nothing; [0, 1, 0] swells and dies.
	var sizes: Array = pre.get("size_over_life", [])
	if sizes.size() >= 2:
		var curve := Curve.new()
		curve.max_value = maxf(1.0, sizes.map(func(x): return float(x)).max())
		for i in sizes.size():
			curve.add_point(Vector2(float(i) / (sizes.size() - 1), float(sizes[i])))
		p.scale_amount_curve = curve
	# A FLIPBOOK: the texture is a grid of frames, [columns, rows], played
	# `cycles` times over each particle's life (1 by default), or one frame per
	# particle picked at random with `random_frame` — sparks that are not all
	# the same spark. And `blend: "add"` for light: glows that brighten what is
	# under them instead of covering it.
	var grid = pre.get("frames")
	var additive := str(pre.get("blend", "")) == "add"
	if (grid is Array and grid.size() == 2) or additive:
		var mat := CanvasItemMaterial.new()
		if additive:
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		if grid is Array and grid.size() == 2:
			mat.particles_animation = true
			mat.particles_anim_h_frames = maxi(1, int(grid[0]))
			mat.particles_anim_v_frames = maxi(1, int(grid[1]))
			mat.particles_anim_loop = true
			if bool(pre.get("random_frame", false)):
				p.anim_offset_max = 1.0
			else:
				p.anim_speed_min = float(pre.get("cycles", 1.0))
				p.anim_speed_max = float(pre.get("cycles", 1.0))
		p.material = mat
	match str(pre.get("from", "point")):
		"area":
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = extent
		"edge":
			# The card's outline, not its face: a ring of points round the rect.
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
			p.emission_points = _outline(extent, 24)
		_:
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	# The game speed setting speeds the effects up with everything else.
	p.speed_scale = maxf(Settings.animation_scale(), 0.01)
	p.local_coords = false
	p.z_index = int(pre.get("z", 0))
	return p


## The drawing a preset asks for, or the soft dot. A bare filename resolves under
## assets/particles/; a res:// or user:// path is taken as it is, so a mod can
## ship its own.
##
## Loaded by Art.load_texture(), the game's one image loader: raw bytes first
## (a mod's PNG in user:// is never imported), then the imported resource (an
## exported build carries the import and not the .png — the trap that made
## every build mute, see Audio.gd).
func texture_of(preset_name: String) -> Texture2D:
	if _textures.has(preset_name):
		return _textures[preset_name]
	var path := texture_path(preset_name)
	var tex: Texture2D = _dot
	if path != "":
		var drawn := Art.load_texture(path)
		if drawn != null:
			tex = drawn
	_textures[preset_name] = tex
	return tex


func texture_path(preset_name: String) -> String:
	var t := str(Content.particles.get(preset_name, {}).get("texture", ""))
	if t == "":
		return ""
	if t.begins_with("res://") or t.begins_with("user://"):
		return t
	return TEXTURE_ROOT + t


# ── motion ───────────────────────────────────────────────────────────────

## Plays the named motion on `target`. Returns the tween, or null when nothing
## moved (motion off, no such preset, target gone). A looping kind keeps going
## until the target is freed or stop() is called.
func move(target: Control, motion_name: String) -> Tween:
	if _motion_off() or not _alive(target):
		return null
	var pre: Dictionary = Content.motions.get(motion_name, {})
	if pre.is_empty():
		return null
	var kind := str(pre.get("kind", ""))
	var amount := float(pre.get("amount", 0.1))
	var seconds := _dur(float(pre.get("duration", 0.3)))
	stop(target)
	# Scale and rotation turn about the card's centre, not its top-left corner.
	target.pivot_offset = target.size * 0.5
	var tw := target.create_tween()
	tw.bind_node(target)
	target.set_meta("_feel_tween", tw)
	match kind:
		"pulse", "hop":
			var from := target.scale
			var up := tw.tween_property(target, "scale", from * (1.0 + amount), seconds * 0.4)
			up.set_trans(Tween.TRANS_BACK if kind == "hop" else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(target, "scale", from, seconds * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		"shake":
			var from := target.rotation_degrees
			var count := maxi(1, int(pre.get("count", 4)))
			for i in count:
				var side := amount * (1.0 - float(i) / count) * (1 if i % 2 == 0 else -1)
				tw.tween_property(target, "rotation_degrees", from + side, seconds / (count + 1))
			tw.tween_property(target, "rotation_degrees", from, seconds / (count + 1))
		"tilt":
			var from := target.rotation_degrees
			tw.tween_property(target, "rotation_degrees", from + amount, seconds * 0.4).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(target, "rotation_degrees", from, seconds * 0.6).set_trans(Tween.TRANS_QUAD)
		"flash", "breathe":
			var from := target.modulate
			var lit := Color(from.r * (1.0 + amount), from.g * (1.0 + amount), from.b * (1.0 + amount), from.a)
			tw.tween_property(target, "modulate", lit, seconds * 0.5).set_trans(Tween.TRANS_SINE)
			tw.tween_property(target, "modulate", from, seconds * 0.5).set_trans(Tween.TRANS_SINE)
			if kind == "breathe":
				tw.set_loops()
		"keys":
			if not _keyframes(tw, target, pre.get("keys", [])):
				tw.kill()
				target.remove_meta("_feel_tween")
				return null
			if bool(pre.get("loop", false)):
				tw.set_loops()
		_:
			tw.kill()
			target.remove_meta("_feel_tween")
			return null
	return tw


## KEYFRAMES, the way an animator thinks: each key says where the card is `at`
## that many seconds, and the tween goes there from the key before. Every value
## is RELATIVE to the card as it was when the motion started — `scale` 1.2 is
## 20% bigger than it was, `turn` 5 is five degrees further round, `bright` 1.5
## is half as bright again, `alpha` 0 is gone — so the same motion suits a card
## that is already lifted or already dimmed. A value a key leaves out holds
## what the key before had. `ease` is how the card arrives AT that key; see
## EASES. The first key is where it starts, and should usually be at 0.
##
## To end where it began, the last key says so (scale 1, turn 0, bright 1).
## Nothing forces it: a motion that leaves a card changed is sometimes the
## point, and the test for the built-in kinds does not apply to these.
func _keyframes(tw: Tween, target: Control, keys: Array) -> bool:
	if keys.size() < 2:
		return false
	var s0 := target.scale
	var r0 := target.rotation_degrees
	var m0 := target.modulate
	var now := {"at": 0.0, "scale": 1.0, "turn": 0.0, "bright": 1.0, "alpha": 1.0}
	var first := true
	tw.set_parallel(false)
	for k in keys:
		if not (k is Dictionary):
			continue
		var nxt := now.duplicate()
		for field in ["at", "scale", "turn", "bright", "alpha"]:
			if k.has(field):
				nxt[field] = float(k[field])
		if first:
			# The first key is a pose, not a move: the card jumps to it.
			target.scale = s0 * nxt["scale"]
			target.rotation_degrees = r0 + nxt["turn"]
			target.modulate = Color(m0.r * nxt["bright"], m0.g * nxt["bright"], m0.b * nxt["bright"], m0.a * nxt["alpha"])
			first = false
			now = nxt
			continue
		var seconds := _dur(maxf(0.0, nxt["at"] - now["at"]))
		var curve: Array = EASES.get(str(k.get("ease", "in_out")), EASES["in_out"])
		var lit := Color(m0.r * nxt["bright"], m0.g * nxt["bright"], m0.b * nxt["bright"], m0.a * nxt["alpha"])
		tw.tween_property(target, "scale", s0 * nxt["scale"], seconds).set_trans(curve[0]).set_ease(curve[1])
		tw.parallel().tween_property(target, "rotation_degrees", r0 + nxt["turn"], seconds).set_trans(curve[0]).set_ease(curve[1])
		tw.parallel().tween_property(target, "modulate", lit, seconds).set_trans(curve[0]).set_ease(curve[1])
		now = nxt
	return true


## Stops whatever Feel set moving on `target`. It is left where the motion had
## got to; every kind but `breathe` ends where it began anyway.
func stop(target: Control) -> void:
	if not _alive(target) or not target.has_meta("_feel_tween"):
		return
	var tw = target.get_meta("_feel_tween")
	if tw is Tween and tw.is_valid():
		tw.kill()
	target.remove_meta("_feel_tween")


# ── cards that animate on their own ──────────────────────────────────────

## The first `card_states` rule this card matches, or {}. `ctx` carries what the
## card cannot say about itself: `affordable`, and `link` — the link it would
## make if laid next (same / turn / back / break / open / flat, as Rules.link_of
## names them).
##
## A rule's `when` is a list of field: value pairs, ALL of which must hold. A
## field is looked up in `ctx` first and on the card second. `true` means the
## field is truthy, a list means "any of these", anything else must be equal.
## A rule with `"off": true` is skipped: an example to switch on, not a default.
func card_state(card: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	for rule in Content.card_states:
		if bool(rule.get("off", false)):
			continue
		if matches(rule.get("when", {}), card, ctx):
			return rule
	return {}


## Gives a card in the hand whatever its state asks for: a looping motion on
## the face, and a standing emitter parented TO the face, so both go when the
## face goes and nothing has to be cleaned up by hand.
func dress_card(face: Control, card: Dictionary, ctx: Dictionary = {}) -> void:
	if not _alive(face):
		return
	dress_with(face, card_state(card, ctx), card, ctx)


## dress_card() with the rule chosen by the caller. The studio uses it to show a
## rule that is switched off, so it can be judged before it is switched on.
func dress_with(face: Control, rule: Dictionary, card: Dictionary, ctx: Dictionary = {}) -> void:
	if not _alive(face) or rule.is_empty():
		return
	var motion := str(rule.get("motion", ""))
	if motion != "":
		# Deferred: the face has no size until the container has laid it out,
		# and the pivot is taken from the size. By id, for the reason
		# play_later() gives.
		_move_by_id.call_deferred(face.get_instance_id(), motion)
	var particles := str(rule.get("particles", ""))
	if particles != "" and particles_on():
		var colour := _colour(str(rule.get("color", "")), ctx, face, card)
		var p := _emitter(particles, colour, Vector2.ZERO)
		if p == null:
			return
		p.one_shot = false
		p.local_coords = true
		face.add_child(p)
		var fit := func():
			if is_instance_valid(p) and _alive(face):
				p.position = face.size * 0.5
				if p.emission_shape == CPUParticles2D.EMISSION_SHAPE_RECTANGLE:
					p.emission_rect_extents = face.size * 0.5
				elif p.emission_shape == CPUParticles2D.EMISSION_SHAPE_POINTS:
					p.emission_points = _outline(face.size * 0.5, 24)
		face.resized.connect(fit)
		fit.call()
		p.emitting = true


func _move_by_id(id: int, motion_name: String) -> void:
	var target = instance_from_id(id)
	if _alive(target):
		move(target, motion_name)


## Whether a card_states `when` holds for this card — see card_state().
func matches(when: Dictionary, card: Dictionary, ctx: Dictionary) -> bool:
	for field in when:
		var want = when[field]
		var have = ctx.get(field) if ctx.has(field) else card.get(field)
		if want is bool:
			if Rules.truthy(have) != want:
				return false
		elif want is Array:
			if not Array(want).map(func(x): return str(x)).has(str(have)):
				return false
		elif str(have) != str(want):
			return false
	return true


# ── the room remembers ───────────────────────────────────────────────────

## How a card may get to the thing it becomes, and how long each takes at 1x.
## See data/base/room.json.
const HOWS := {"melt": 0.55, "burn": 0.65, "carry": 0.6}

## The first `traces` rule (room.json) this card matches, or {}. Matched exactly
## as card_states are.
func trace_rule(card: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	for rule in Content.traces:
		if bool(rule.get("off", false)):
			continue
		if matches(rule.get("when", {}), card, ctx):
			return rule
	return {}


## How long the card takes to become its thing — 0 when motion is off, when
## the thing simply appears.
func arrival_of(rule: Dictionary) -> float:
	if _motion_off() or str(rule.get("becomes", "")) == "":
		return 0.0
	return _dur(float(HOWS.get(str(rule.get("how", "melt")), 0.5)))


## THE CARD TURNS INTO THE THING. A picture of the card is taken where it sits
## and that picture melts, burns, or is carried to `to` (a global position:
## where the thing will stand), on Feel's own layer — so it outlives the
## screen being rebuilt underneath it, which happens the instant the card is
## laid. The thing itself is drawn by the room (scenes/RoomTraces.gd) from the
## moment arrival_of() says it lands; this is only the journey, and the rumble
## when it gets there.
##
## A picture rather than the card: whatever the card looks like — today's
## placeholder or the illustrator's drawing — is what comes apart, with no code
## knowing which.
func become(face: Control, rule: Dictionary, to: Vector2) -> void:
	var arrive := arrival_of(rule)
	var haptic := str(rule.get("haptic", ""))
	if haptic != "":
		if arrive <= 0.0:
			rumble(haptic)
		else:
			get_tree().create_timer(arrive).timeout.connect(rumble.bind(haptic))
	if arrive <= 0.0 or not _alive(face):
		return
	var how := str(rule.get("how", "melt"))
	var rect := face.get_global_rect()
	var ghost := _ghost(face, rect)
	_layer.add_child(ghost)
	var tw := ghost.create_tween()
	tw.bind_node(ghost)
	match how:
		"carry":
			ghost.pivot_offset = rect.size * 0.5
			var goal := to - rect.size * 0.5
			tw.tween_property(ghost, "position", goal, arrive).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(ghost, "scale", Vector2(0.3, 0.3), arrive).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(ghost, "rotation_degrees", -8.0, arrive)
			tw.parallel().tween_property(ghost, "modulate:a", 0.0, arrive * 0.35).set_delay(arrive * 0.65)
		_:
			# It drifts to where the thing will stand while it comes apart, so it
			# melts over the table and not over the hand — where the next card
			# is already sliding into its place and would show through the holes.
			ghost.pivot_offset = rect.size * 0.5
			tw.tween_property(ghost, "position", to - rect.size * 0.5, arrive).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(ghost, "scale", Vector2(0.55, 0.55), arrive).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			var mat := ghost.material as ShaderMaterial
			if mat != null:
				if how == "burn":
					mat.set_shader_parameter("edge_color", Color(1.0, 0.55, 0.18, 1.0))
					mat.set_shader_parameter("bias", 0.0)
				tw.parallel().tween_method(_track.bind(ghost), 0.0, 1.0, arrive).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			else:
				tw.parallel().tween_property(ghost, "modulate:a", 0.0, arrive)
			burst("embers" if how == "burn" else "dust", rect.get_center(),
				Color(1.0, 0.6, 0.3) if how == "burn" else Color(1, 1, 1, 0.8), rect.size * 0.5)
	tw.tween_callback(ghost.queue_free)
	# A puff where it lands, as it lands.
	get_tree().create_timer(arrive).timeout.connect(_land.bind(to))


func _land(at: Vector2) -> void:
	burst("dust", at, Color(1, 1, 1, 0.6), Vector2(12, 6))


## The card that comes apart: a COPY of the face, with every part of it
## drawing through the dissolve shader.
##
## It was a snapshot of the screen first, and a measured one came out at a
## tenth of the card's brightness — the viewport is read back in linear light
## and shown as if it were not, a conversion that depends on the renderer. A
## copy has no colour to get wrong, costs no read-back, and exists in a headless
## run too, so the tests see the journey the player does.
func _ghost(face: Control, rect: Rect2) -> Control:
	var g: Control = face.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
	for n in [g] + g.find_children("*", "", true, false):
		if n is CPUParticles2D:
			n.free()
			continue
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			n.focus_mode = Control.FOCUS_NONE
		if n != g and n is CanvasItem:
			n.use_parent_material = true
	g.position = rect.position
	g.size = rect.size
	g.scale = Vector2.ONE
	g.rotation = 0.0
	g.modulate = Color.WHITE
	var shader = load("res://assets/shaders/dissolve.gdshader")
	if shader is Shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("card", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		g.material = mat
	return g


## Keeps the shader's idea of where the card is in step with the card, as it
## drifts and shrinks — otherwise the pattern slides across it.
func _track(progress: float, g: Control) -> void:
	var mat := g.material as ShaderMaterial
	if mat == null:
		return
	var tl := g.position + g.pivot_offset * (Vector2.ONE - g.scale)
	var size := g.size * g.scale
	mat.set_shader_parameter("card", Vector4(tl.x, tl.y, size.x, size.y))
	mat.set_shader_parameter("progress", progress)


## A running emitter of a preset, for something that stays — the steam off a
## cup. Unparented: the caller parents it at once. Null when particles are off
## or the preset does not exist.
func emitter_for(preset_name: String, colour: Color) -> CPUParticles2D:
	if not particles_on():
		return null
	var p := _emitter(preset_name, colour, Vector2.ZERO)
	if p == null:
		return null
	p.one_shot = false
	p.local_coords = false
	return p


# ── haptics ──────────────────────────────────────────────────────────────

## Plays the named haptic pattern: a list of pulses, each [weak, strong,
## seconds, pause_after]. `weak` is the high-frequency motor and `strong` the
## low one — a tap is mostly weak, a thud mostly strong. Scaled by the
## player's strength and skipped entirely when haptics are off.
##
## Returns how many pulses were scheduled.
func rumble(pattern_name: String) -> int:
	if not haptics_on():
		return 0
	var pre: Dictionary = Content.haptics.get(pattern_name, {})
	var pulses: Array = pre.get("pulses", [])
	var strength := clampf(float(Settings.get_value("haptic_strength")), 0.0, 1.0)
	var at := 0.0
	var n := 0
	for pulse in pulses:
		if not (pulse is Array) or pulse.size() < 3:
			continue
		var weak := clampf(float(pulse[0]) * strength, 0.0, 1.0)
		var strong := clampf(float(pulse[1]) * strength, 0.0, 1.0)
		var seconds := maxf(0.01, float(pulse[2]))
		if at <= 0.0:
			_pulse(weak, strong, seconds)
		else:
			get_tree().create_timer(at).timeout.connect(_pulse.bind(weak, strong, seconds))
		at += seconds + (float(pulse[3]) if pulse.size() > 3 else 0.0)
		n += 1
	return n


func haptics_on() -> bool:
	return bool(Settings.get_value("haptics")) and float(Settings.get_value("haptic_strength")) > 0.0


func _pulse(weak: float, strong: float, seconds: float) -> void:
	var pads: Array = Input.get_connected_joypads()
	var devices: Array = [_last_pad] if pads.has(_last_pad) else pads
	for d in devices:
		Input.start_joy_vibration(int(d), weak, strong, seconds)
	# A phone or a Steam Deck in handheld mode has one motor and no weak/strong.
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(int(seconds * 1000.0), maxf(weak, strong))
	haptic_log.append({"weak": weak, "strong": strong, "seconds": seconds, "devices": devices})
	if haptic_log.size() > HAPTIC_LOG:
		haptic_log.pop_front()


# ── the hands ────────────────────────────────────────────────────────────

## The gesture the hands are in when nothing else is asked of them. Loops.
const REST := "rest"

## What a gesture key may set, and the value each has when nothing sets it —
## the hand exactly as Table.gd draws it. `lift` is in heights of the hands'
## band, up; `turn` is degrees toward the cards (mirrored for the right hand);
## `reach` and `spread` scale the fingers' length and fan.
const POSE_FIELDS := {"lift": 0.0, "turn": 0.0, "reach": 1.0, "spread": 1.0}

## Which hands a gesture moves. The other one carries on resting.
const HAND_SIDES := ["both", "left", "right"]

## How much later the right hand breathes than the left, in seconds, so the two
## are not one drawing mirrored.
const REST_OFFSET := 0.9

## The gesture playing, {name, at} with `at` on `clock`. HERE and not on the
## hands: see scenes/Hands.gd.
var _gesture: Dictionary = {}

## The hands' own time, in seconds: the frame's time — which the studio's slow
## motion slows, through Engine.time_scale — at the player's game speed. The
## wall clock ignored both, and a gesture being tuned in slow motion played at
## full speed beside the particles slowed down around it.
var clock := 0.0


func _process(delta: float) -> void:
	clock += delta * _speed()


## Starts `name` on the player's hands. What an event's `hands` field does; call
## it directly for a gesture no event names. An unknown name does nothing.
func gesture(name: String) -> void:
	if not Content.gestures.has(name):
		return
	_gesture = {"name": name, "at": clock}


## The gesture playing on `side` ("left" or "right") at `now` on the clock, or
## "" when it is resting. For the studio's readout and the tests.
func gesture_on(side: String, now: float = -1.0) -> String:
	if _gesture.is_empty():
		return ""
	var g: Dictionary = Content.gestures.get(str(_gesture["name"]), {})
	var hand := str(g.get("hand", "both"))
	if hand != "both" and hand != side:
		return ""
	if not bool(g.get("loop", false)) and _since_gesture(now) > gesture_length(g):
		return ""
	return str(_gesture["name"])


## How one hand is posed at `now` on the clock: every field of POSE_FIELDS. The
## hand at rest when motion is off — the hands hold still, like every other
## thing.
func hand_pose(side: String, now: float = -1.0) -> Dictionary:
	if _motion_off():
		return POSE_FIELDS.duplicate()
	if now < 0.0:
		now = clock
	var playing := gesture_on(side, now)
	if playing != "":
		return pose_of(Content.gestures[playing], _since_gesture(now))
	return pose_of(Content.gestures.get(REST, {}), now + (REST_OFFSET if side == "right" else 0.0))


## The pose a gesture is in `t` seconds after it starts. Keys work as a `keys`
## motion's do (see _keyframes()): each says where the hand is `at` that time, a
## field a key leaves out holds what the key before had, and `ease` is how the
## hand arrives. After its last key a gesture holds that key; a `loop` gesture
## starts again.
func pose_of(g: Dictionary, t: float) -> Dictionary:
	var held: Array = []
	var now := POSE_FIELDS.duplicate()
	now["at"] = 0.0
	for k in g.get("keys", []):
		if not (k is Dictionary):
			continue
		var nxt := now.duplicate()
		for field in nxt:
			if k.has(field):
				nxt[field] = float(k[field])
		held.append([nxt, str(k.get("ease", "in_out"))])
		now = nxt
	if held.is_empty():
		return POSE_FIELDS.duplicate()
	var length: float = held[-1][0]["at"]
	if bool(g.get("loop", false)) and length > 0.0:
		t = fposmod(t, length)
	var pose := {}
	for i in held.size():
		var b: Dictionary = held[i][0]
		if t > b["at"] and i < held.size() - 1:
			continue
		var a: Dictionary = held[maxi(0, i - 1)][0]
		var span: float = b["at"] - a["at"]
		var curve: Array = EASES.get(held[i][1], EASES["in_out"])
		for field in POSE_FIELDS:
			if span <= 0.0 or t >= b["at"]:
				pose[field] = b[field]
			else:
				pose[field] = Tween.interpolate_value(a[field], b[field] - a[field], maxf(0.0, t - a["at"]),
					span, curve[0], curve[1])
		break
	return pose


## When a gesture's last key is.
func gesture_length(g: Dictionary) -> float:
	var at := 0.0
	for k in g.get("keys", []):
		if k is Dictionary and k.has("at"):
			at = float(k["at"])
	return at


func _since_gesture(now: float) -> float:
	return (clock if now < 0.0 else now) - float(_gesture.get("at", 0.0))


## The game speed as a multiplier on time, the other way up from _dur().
func _speed() -> float:
	return maxf(Settings.animation_scale(), 0.01)


# ── what the registry asks for and nothing provides ──────────────────────

## Every preset name an event or a card state points at that nothing defines,
## every motion kind nobody implements, every status outside the vocabulary,
## and every texture a preset names that is not there. Said ONCE, at load, as a
## warning: the registry is a mod surface, and a typo in it is otherwise a
## moment that silently feels of nothing.
func problems() -> Array[String]:
	var out: Array[String] = []
	for event in Content.feel:
		var rec: Dictionary = Content.feel[event]
		for pair in [["particles", Content.particles], ["motion", Content.motions], ["haptic", Content.haptics]]:
			var wanted := str(rec.get(pair[0], ""))
			if wanted != "" and not pair[1].has(wanted):
				out.append("feel.json: '%s' asks for %s '%s', which nothing defines" % [event, pair[0], wanted])
		var hands := str(rec.get("hands", ""))
		if hands != "" and not Content.gestures.has(hands):
			out.append("feel.json: '%s' asks the hands for gesture '%s', which nothing defines" % [event, hands])
	for name in Content.gestures:
		var g: Dictionary = Content.gestures[name]
		if not HAND_SIDES.has(str(g.get("hand", "both"))):
			out.append("feel.json: gesture '%s' moves hand '%s', which is not one of %s" % [name, g.get("hand"), HAND_SIDES])
		if not STATUSES.has(str(g.get("status", UNDELIVERED))):
			out.append("feel.json: gesture '%s' has status '%s', which is not one of %s" % [name, g.get("status"), STATUSES.keys()])
		for k in g.get("keys", []):
			if k is Dictionary and k.has("ease") and not EASES.has(str(k["ease"])):
				out.append("feel.json: gesture '%s' has a key easing '%s', which is not one of %s" % [name, k["ease"], EASES.keys()])
			if k is Dictionary:
				for field in k:
					if field != "at" and field != "ease" and not POSE_FIELDS.has(field):
						out.append("feel.json: gesture '%s' has a key setting '%s', which is not one of %s" % [name, field, POSE_FIELDS.keys()])
	for rule in Content.card_states:
		for pair in [["particles", Content.particles], ["motion", Content.motions]]:
			var wanted := str(rule.get(pair[0], ""))
			if wanted != "" and not pair[1].has(wanted):
				out.append("feel.json: card state '%s' asks for %s '%s', which nothing defines" % [rule.get("id", "?"), pair[0], wanted])
	for m in Content.motions:
		var kind := str(Content.motions[m].get("kind", ""))
		if not MOTION_KINDS.has(kind):
			out.append("feel.json: motion '%s' is of kind '%s', which is not one of %s" % [m, kind, MOTION_KINDS.keys()])
		for k in Content.motions[m].get("keys", []):
			if k is Dictionary and k.has("ease") and not EASES.has(str(k["ease"])):
				out.append("feel.json: motion '%s' has a key easing '%s', which is not one of %s" % [m, k["ease"], EASES.keys()])
	for name in Content.particles:
		var st := str(Content.particles[name].get("status", UNDELIVERED))
		if not STATUSES.has(st):
			out.append("feel.json: particles '%s' has status '%s', which is not one of %s" % [name, st, STATUSES.keys()])
		var path := texture_path(name)
		var drawn: Texture2D = Art.load_texture(path) if path != "" else null
		if path != "" and drawn == null:
			out.append("feel.json: particles '%s' names the texture %s, which does not load" % [name, path])
		# A flipbook cut from a drawing that does not divide into its grid plays
		# frames sliced through the middle of each other.
		var grid = Content.particles[name].get("frames")
		if grid is Array and grid.size() == 2:
			if path == "":
				out.append("feel.json: particles '%s' is a flipbook of %s frames with no texture to cut them from" % [name, grid])
			elif drawn != null and (drawn.get_width() % maxi(1, int(grid[0])) != 0 or drawn.get_height() % maxi(1, int(grid[1])) != 0):
				out.append("feel.json: particles '%s' is %dx%d, which does not divide into a %sx%s grid of frames"
					% [name, drawn.get_width(), drawn.get_height(), grid[0], grid[1]])
	return out


## What room.json asks for and nothing provides: a thing, a spot, a way of
## arriving, a rumble, a placeholder kind or a running preset nobody defined,
## and a card named in a `when` that no loaded pack has — the last because the
## rules match cards BY NAME, and a renamed card would otherwise just stop
## turning into anything, silently.
func room_problems() -> Array[String]:
	var out: Array[String] = []
	var draws: Array = (load("res://scenes/RoomTraces.gd") as GDScript).get_script_constant_map().get("DRAWS", [])
	for rule in Content.traces:
		var id := str(rule.get("id", "?"))
		var becomes := str(rule.get("becomes", ""))
		if becomes == "" and not bool(rule.get("shakes", false)):
			out.append("room.json: trace '%s' becomes nothing and shakes nothing" % id)
		if becomes != "" and not Content.props.has(becomes):
			out.append("room.json: trace '%s' becomes '%s', which no prop defines" % [id, becomes])
		if becomes != "" and not Content.spots.has(str(rule.get("at", ""))):
			out.append("room.json: trace '%s' lands at '%s', which no spot defines" % [id, rule.get("at", "")])
		if becomes != "" and not HOWS.has(str(rule.get("how", "melt"))):
			out.append("room.json: trace '%s' arrives by '%s', which is not one of %s" % [id, rule.get("how"), HOWS.keys()])
		var haptic := str(rule.get("haptic", ""))
		if haptic != "" and not Content.haptics.has(haptic):
			out.append("room.json: trace '%s' rumbles '%s', which feel.json does not define" % [id, haptic])
		var names = rule.get("when", {}).get("n")
		for n in (names if names is Array else ([names] if names != null else [])):
			if not Content.has_card(str(n)):
				out.append("room.json: trace '%s' names the card '%s', which no loaded pack has" % [id, n])
	for id in Content.props:
		var pre: Dictionary = Content.props[id]
		if not draws.has(str(pre.get("draw", ""))) and Art.prop_texture(str(id)) == null:
			out.append("room.json: prop '%s' draws '%s', which is not one of %s, and has no drawing" % [id, pre.get("draw", ""), draws])
		var preset := str(pre.get("particles", ""))
		if preset != "" and not Content.particles.has(preset):
			out.append("room.json: prop '%s' runs particles '%s', which feel.json does not define" % [id, preset])
	return out


func _say_what_does_not_resolve() -> void:
	for line in room_problems():
		push_warning("[Feel] " + line)
	for line in problems():
		push_warning("[Feel] " + line)


## By status, like Art.status_summary() and Audio.status_summary(), for the
## credits and for whoever is counting what is left to draw.
func status_summary() -> Dictionary:
	var out := {}
	for name in Content.particles:
		var st := str(Content.particles[name].get("status", UNDELIVERED))
		out[st] = int(out.get(st, 0)) + 1
	return out


# ── small things ─────────────────────────────────────────────────────────

func _colour(spec: String, ctx: Dictionary, target: Control, card: Dictionary = {}) -> Color:
	if spec == "" or spec == "white":
		return Color.WHITE
	if spec == "element":
		var el := str(ctx.get("el", card.get("el", "")))
		if el == "" or el == "<null>":
			return Color("#EAE4D7")
		return Color(str(Content.elements.get(el, {}).get("color", "#EAE4D7")))
	if spec.begins_with("#"):
		return Color(spec)
	return Color.WHITE


func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree() and not n.is_queued_for_deletion()


## UIKit decides what "motion off" and a game-speed duration mean, and this
## asks it rather than keeping a second opinion. Loaded at run time, never
## preloaded: UIKit names autoloads, and an autoload that preloads it resolves
## them before they exist (see CLAUDE.md).
func _ui():
	if _uikit == null:
		_uikit = load("res://scenes/UIKit.gd")
	return _uikit


func _motion_off() -> bool:
	return _ui().motion_off()


func _dur(seconds: float) -> float:
	return _ui().dur(seconds)


func _outline(half: Vector2, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var t := float(i) / n * 4.0
		var side := int(t)
		var f := t - side
		match side:
			0: pts.append(Vector2(-half.x + 2.0 * half.x * f, -half.y))
			1: pts.append(Vector2(half.x, -half.y + 2.0 * half.y * f))
			2: pts.append(Vector2(half.x - 2.0 * half.x * f, half.y))
			_: pts.append(Vector2(-half.x, half.y - 2.0 * half.y * f))
	return pts


## A white disc that fades to nothing at its edge — the particle every preset
## uses until it is given a drawing. Made, not shipped, so there is no file to
## go missing from an export.
func _soft_dot(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
