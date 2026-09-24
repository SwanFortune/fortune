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
	if bool(pre.get("fade", true)):
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
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
## TWO WAYS IN, the same two Art.gd and Audio.gd learned the hard way. The raw
## file first, read as bytes: that is the only way a mod's PNG in user:// works
## at all, since Godot's importer never sees it. Then the imported resource:
## in an EXPORTED build the .png itself is not in the pack, only its import, and
## reading bytes alone is how every sound in the game went missing from every
## build ever shipped (see Audio.gd).
func texture_of(preset_name: String) -> Texture2D:
	if _textures.has(preset_name):
		return _textures[preset_name]
	var path := texture_path(preset_name)
	var tex: Texture2D = _dot
	if path != "":
		var drawn := _load_texture(path)
		if drawn != null:
			tex = drawn
	_textures[preset_name] = tex
	return tex


func _load_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is Texture2D:
			return loaded
	return null


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
		_:
			tw.kill()
			target.remove_meta("_feel_tween")
			return null
	return tw


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
		if _matches(rule.get("when", {}), card, ctx):
			return rule
	return {}


## Gives a card in the hand whatever its state asks for: a looping motion on
## the face, and a standing emitter parented TO the face, so both go when the
## face goes and nothing has to be cleaned up by hand.
func dress_card(face: Control, card: Dictionary, ctx: Dictionary = {}) -> void:
	if not _alive(face):
		return
	var rule := card_state(card, ctx)
	if rule.is_empty():
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


func _matches(when: Dictionary, card: Dictionary, ctx: Dictionary) -> bool:
	for field in when:
		var want = when[field]
		var have = ctx.get(field) if ctx.has(field) else card.get(field)
		if want is bool:
			if _truthy(have) != want:
				return false
		elif want is Array:
			if not Array(want).map(func(x): return str(x)).has(str(have)):
				return false
		elif str(have) != str(want):
			return false
	return true


func _truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_STRING, TYPE_STRING_NAME:
			return v != ""
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return bool(v)
	return true


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
	for rule in Content.card_states:
		for pair in [["particles", Content.particles], ["motion", Content.motions]]:
			var wanted := str(rule.get(pair[0], ""))
			if wanted != "" and not pair[1].has(wanted):
				out.append("feel.json: card state '%s' asks for %s '%s', which nothing defines" % [rule.get("id", "?"), pair[0], wanted])
	for m in Content.motions:
		var kind := str(Content.motions[m].get("kind", ""))
		if not MOTION_KINDS.has(kind):
			out.append("feel.json: motion '%s' is of kind '%s', which is not one of %s" % [m, kind, MOTION_KINDS.keys()])
	for name in Content.particles:
		var st := str(Content.particles[name].get("status", UNDELIVERED))
		if not STATUSES.has(st):
			out.append("feel.json: particles '%s' has status '%s', which is not one of %s" % [name, st, STATUSES.keys()])
		var path := texture_path(name)
		if path != "" and _load_texture(path) == null:
			out.append("feel.json: particles '%s' names the texture %s, which does not load" % [name, path])
	return out


func _say_what_does_not_resolve() -> void:
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
