## THE ROOM REMEMBERS. What the cards you have laid have become: the cup of tea
## on their side of the table, their coat on the hook, the lamp turned up, the
## ash of a letter. Drawn over the room and under everything you read, for as
## long as this person is sitting there.
##
## The rules are data/base/room.json; the moment a card turns into its thing is
## Feel.become(). This is only what stays: a layer that draws the list it is
## given, which on the reading screen is Run.state.f.room — so it is saved with
## the fight, taken back with TAKE IT BACK (the whole fight is snapshotted
## before a card is laid), and gone when the next person sits down.
##
## THE SCREEN IS REBUILT ON EVERY ACTION, so nothing here can animate by
## keeping a tween alive. Instead each thing carries the moment it `born`s, and
## a new layer built mid-arrival simply does not draw it yet, then fades it in.
## A rattle works the same way: the fight carries when the room was last
## jolted, and whichever layer is on screen then does the shaking.
##
## Everything is a PLACEHOLDER drawn in code until a drawing lands at
## assets/art/prop/<id>.png, on the same terms as the room itself (Table.gd).
extends Control

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const Table := preload("res://scenes/Table.gd")

## How many things the table holds before the oldest is cleared away. A long
## visit of coins would otherwise bury the cloth.
const MAX_TRACES := 10

## Seconds a new thing takes to fade in once it has arrived, and how long a
## rattle lasts.
const FADE_IN := 0.35
const JOLT_FOR := 0.6

## An arrival never takes this long. A `born` further ahead than this came from
## an earlier session's clock (Time.get_ticks_msec() starts again at every
## launch) and is treated as long since arrived, or a reloaded save would hide
## the cup until the new session's clock caught up with the old one's.
const STALE_MS := 3000

## What to draw: [{prop, spot, jitter: [x, y], born}], shared with its owner.
var traces: Array = []
## When the room was last jolted, in Time.get_ticks_msec().
var jolt_at := 0
## The sitter's element, for things tinted by it (their coat).
var element := ""

var _steaming := {}


static func layer(what: Array, jolted: int = 0, el: String = "") -> Control:
	var c: Control = (load("res://scenes/RoomTraces.gd") as GDScript).new()
	c.name = "RoomTraces"
	c.traces = what
	c.jolt_at = jolted
	c.element = el
	return c


func _ready() -> void:
	# Anchors AND offsets. Already in the tree by now, so set_anchors_preset()
	# alone keeps the rect it has — zero — by moving the offsets to match, and
	# the layer covered nothing: every thing on the table was drawn into a 0x0
	# box. Found by rendering the screen, which no test that only asked whether
	# the layer existed would have done.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(true)


## Redraws only while something is arriving, fading in or rattling, then stops.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var busy := now - jolt_at < JOLT_FOR * 1000.0
	for t in traces:
		var age := _age(t, now)
		if age < FADE_IN:
			busy = true
		elif age >= 0.0:
			_steam(t)
	queue_redraw()
	if not busy:
		set_process(false)


## Wakes the layer after its list changed, from outside.
func refresh() -> void:
	set_process(true)
	queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec()
	var h := size.y
	var shake := clampf(1.0 - (now - jolt_at) / (JOLT_FOR * 1000.0), 0.0, 1.0)
	var i := 0
	for t in traces:
		i += 1
		var age := _age(t, now)
		if age < 0.0:
			continue
		var at := where(t, size)
		if shake > 0.0:
			at += Vector2(sin(now * 0.07 + i * 1.7), cos(now * 0.09 + i)) * h * 0.004 * shake
		draw_prop(self, str(t.get("prop", "")), at, h, clampf(age / FADE_IN, 0.0, 1.0), element)


## Seconds since the thing arrived; negative while it is still on its way.
static func _age(t: Dictionary, now: int) -> float:
	var born := int(t.get("born", 0))
	if born - now > STALE_MS:
		return 999.0
	return (now - born) / 1000.0


## Where a thing sits, in this layer's coordinates.
static func where(t: Dictionary, s: Vector2) -> Vector2:
	var spot: Array = Content.spots.get(str(t.get("spot", "")), [0.5, 0.5])
	var j: Array = t.get("jitter", [0, 0])
	return Vector2(float(spot[0]) * s.x, float(spot[1]) * s.y) + Vector2(float(j[0]), float(j[1])) * s.y


## A running emitter on a thing that asks for one — the steam off the tea —
## started once, when it has arrived. A child of this layer, so it goes with it.
func _steam(t: Dictionary) -> void:
	var key := "%s@%s" % [t.get("prop", ""), t.get("born", 0)]
	if _steaming.has(key):
		return
	_steaming[key] = true
	var preset := str(Content.props.get(str(t.get("prop", "")), {}).get("particles", ""))
	if preset == "":
		return
	var p: CPUParticles2D = Feel.emitter_for(preset, Color.WHITE)
	if p == null:
		return
	add_child(p)
	var size_h := float(Content.props.get(str(t.get("prop", "")), {}).get("size", 0.05)) * size.y
	p.position = where(t, size) - Vector2(0, size_h * 0.55)
	p.emitting = true


# ── putting things down ──────────────────────────────────────────────────

## Adds what `rule` makes to `room`, and returns the new thing (or {} when the
## rule makes nothing, or makes a thing that may only be there once and is).
## `arrive_in` is how long the card takes to get there, so the layer does not
## draw it before the card has finished turning into it. Stacks a second of
## the same thing beside the first rather than on top of it.
static func place(room: Array, rule: Dictionary, arrive_in: float = 0.0) -> Dictionary:
	var prop := str(rule.get("becomes", ""))
	if prop == "" or not Content.props.has(prop):
		return {}
	var same := room.filter(func(t): return str(t.get("prop", "")) == prop)
	if bool(rule.get("once", false)) and not same.is_empty():
		return {}
	var n := same.size()
	var t := {
		"prop": prop,
		"spot": str(rule.get("at", "middle")),
		# A second pile of coins beside the first, a little to the right and
		# nearer — not the same pixels twice.
		"jitter": [0.035 * n, 0.012 * n],
		"born": Time.get_ticks_msec() + int(arrive_in * 1000.0),
	}
	room.append(t)
	while room.size() > MAX_TRACES:
		room.pop_front()
	return t


# ── drawing a thing ──────────────────────────────────────────────────────

## One thing, at `at`, faded by `a`. A delivered drawing if there is one
## (assets/art/prop/<id>.png, through the art manifest like every other
## drawing), and the placeholder drawn here if not.
static func draw_prop(c: CanvasItem, id: String, at: Vector2, h: float, a: float, el: String = "") -> void:
	var pre: Dictionary = Content.props.get(id, {})
	if pre.is_empty() or a <= 0.0:
		return
	var u := float(pre.get("size", 0.06)) * h
	var tint := Color(1, 1, 1)
	if str(pre.get("tint", "")) == "element" and el != "":
		tint = Color(str(Content.elements.get(el, {}).get("color", "#EAE4D7")))
	var tex := Art.prop_texture(id)
	if tex != null:
		var w := u * float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
		# Centred on its spot, or hung from it by its top edge (their coat).
		var top_left := at - Vector2(w * 0.5, 0.0 if str(pre.get("anchor", "center")) == "top" else u * 0.5)
		c.draw_texture_rect(tex, Rect2(top_left, Vector2(w, u)), false, Color(1, 1, 1, a))
		return
	match str(pre.get("draw", "")):
		"teacup":
			_teacup(c, at, u, a)
		"coat":
			_coat(c, at, u, a, tint)
		"cloth":
			_cloth(c, at, u, a)
		"glow":
			_glow(c, at, u, a)
		"ash":
			_ash(c, at, u, a)
		"coins":
			_coins(c, at, u, a)
		"stones":
			_stones(c, at, u, a)
		"paper":
			_paper(c, at, u, a)


## The kinds of placeholder this file can draw. room.json's `draw` must be one
## of them; Feel.problems() says so at load when it is not.
const DRAWS := ["teacup", "coat", "cloth", "glow", "ash", "coins", "stones", "paper"]


static func _f(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * a)


static func _teacup(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	c.draw_circle(at + Vector2(u * 0.06, u * 0.05), u * 0.62, Color(0, 0, 0, 0.28 * a))
	_blob(c, at, u * 0.60, u * 0.24, _f(Table.CHINA_SHADE, a))
	_blob(c, at - Vector2(0, u * 0.03), u * 0.54, u * 0.20, _f(Table.CHINA, a))
	var rim := at - Vector2(0, u * 0.44)
	var body := PackedVector2Array([
		rim + Vector2(-u * 0.34, 0), rim + Vector2(u * 0.34, 0),
		at + Vector2(u * 0.24, -u * 0.06), at + Vector2(-u * 0.24, -u * 0.06),
	])
	c.draw_colored_polygon(Table._soften(body, u * 0.07), _f(Table.CHINA_SHADE, a))
	c.draw_colored_polygon(Table._soften(Table._shift(body, Vector2(-u * 0.03, 0)), u * 0.07), _f(Table.CHINA, a))
	c.draw_arc(rim + Vector2(-u * 0.40, u * 0.18), u * 0.17, PI * 0.45, PI * 1.55,
		12, _f(Table.CHINA_SHADE, a), maxf(1.5, u * 0.07), true)
	_blob(c, rim, u * 0.34, u * 0.12, _f(Table.CHINA_SHADE, a))
	_blob(c, rim, u * 0.28, u * 0.09, _f(Table.TEA, a))


## Their coat on the hook, beside the one that was already there. Hung from
## `at`, `u` long, in a cloth that leans toward their element.
static func _coat(c: CanvasItem, at: Vector2, u: float, a: float, tint: Color) -> void:
	var cloth := Table.COAT.lerp(tint * 0.35, 0.45)
	var w := u * 0.16
	c.draw_line(at, at + Vector2(0, u * 0.06), _f(Table.BRASS, 0.6 * a), maxf(1.0, u * 0.02), true)
	var body := PackedVector2Array([
		at + Vector2(0, u * 0.07),
		at + Vector2(w * 0.9, u * 0.19),
		at + Vector2(w, u),
		at + Vector2(-w, u),
		at + Vector2(-w * 0.9, u * 0.19),
	])
	c.draw_colored_polygon(Table._soften(body, u * 0.07), _f(cloth, a))
	c.draw_line(at + Vector2(0, u * 0.1), at + Vector2(0, u * 0.95), Color(0, 0, 0, 0.3 * a), maxf(1.0, u * 0.02), true)


## A square of pale linen laid flat, seen from the chair: a trapezoid.
static func _cloth(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	var quad := PackedVector2Array([
		at + Vector2(-u * 0.75, -u * 0.30), at + Vector2(u * 0.75, -u * 0.30),
		at + Vector2(u * 1.0, u * 0.30), at + Vector2(-u * 1.0, u * 0.30),
	])
	c.draw_colored_polygon(Table._shift(quad, Vector2(u * 0.05, u * 0.05)), Color(0, 0, 0, 0.22 * a))
	c.draw_colored_polygon(quad, Color(0.74, 0.70, 0.62, 0.92 * a))
	c.draw_line(at + Vector2(-u * 0.05, -u * 0.30), at + Vector2(u * 0.05, u * 0.30), Color(0.55, 0.51, 0.45, 0.6 * a), maxf(1.0, u * 0.03), true)


## The lamp turned up: a warmer, wider pool of light on the cloth.
static func _glow(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	for i in range(8, 0, -1):
		c.draw_circle(at, u * float(i) / 8.0, Color(Table.LAMPLIGHT, 0.016 * a))


static func _ash(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	_blob(c, at, u * 0.70, u * 0.26, Color(0.10, 0.09, 0.08, 0.55 * a))
	_blob(c, at + Vector2(-u * 0.1, -u * 0.04), u * 0.40, u * 0.14, Color(0.20, 0.18, 0.16, 0.8 * a))
	for k in 5:
		var off := Vector2(cos(k * 2.3) * u * 0.55, sin(k * 1.7) * u * 0.18)
		c.draw_circle(at + off, u * 0.05, Color(0.05, 0.04, 0.04, 0.9 * a))


static func _coins(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	var gold := Color(0.72, 0.58, 0.24)
	c.draw_circle(at + Vector2(u * 0.05, u * 0.08), u * 0.55, Color(0, 0, 0, 0.25 * a))
	for k in 4:
		var p := at - Vector2(0, u * 0.14 * k)
		_blob(c, p, u * 0.46, u * 0.17, _f(gold * 0.65, a))
		_blob(c, p - Vector2(0, u * 0.05), u * 0.44, u * 0.15, _f(gold, a))


static func _stones(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	for k in 4:
		var p := at + Vector2((k - 1.5) * u * 0.62, 0)
		_blob(c, p + Vector2(u * 0.04, u * 0.06), u * 0.26, u * 0.12, Color(0, 0, 0, 0.3 * a))
		_blob(c, p, u * 0.24, u * 0.13, Color(0.38, 0.37, 0.35, a))
		_blob(c, p - Vector2(u * 0.05, u * 0.04), u * 0.12, u * 0.05, Color(0.52, 0.51, 0.48, a))


## A sheet with a house drawn on it: the walls, the roof, a door.
static func _paper(c: CanvasItem, at: Vector2, u: float, a: float) -> void:
	var sheet := PackedVector2Array([
		at + Vector2(-u * 0.6, -u * 0.34), at + Vector2(u * 0.55, -u * 0.40),
		at + Vector2(u * 0.68, u * 0.34), at + Vector2(-u * 0.5, u * 0.40),
	])
	c.draw_colored_polygon(Table._shift(sheet, Vector2(u * 0.04, u * 0.05)), Color(0, 0, 0, 0.22 * a))
	c.draw_colored_polygon(sheet, Color(0.80, 0.76, 0.66, a))
	var ink := Color(0.25, 0.22, 0.20, 0.85 * a)
	var lw := maxf(1.0, u * 0.03)
	var base := at + Vector2(0, u * 0.18)
	c.draw_polyline(PackedVector2Array([base + Vector2(-u * 0.25, 0), base + Vector2(-u * 0.25, -u * 0.25),
		base + Vector2(0, -u * 0.42), base + Vector2(u * 0.25, -u * 0.25), base + Vector2(u * 0.25, 0),
		base + Vector2(-u * 0.25, 0)]), ink, lw, true)
	c.draw_rect(Rect2(base + Vector2(-u * 0.05, -u * 0.12), Vector2(u * 0.1, u * 0.12)), ink, false, lw)


static func _blob(c: CanvasItem, at: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		pts.append(at + Vector2(cos(t) * rx, sin(t) * ry))
	c.draw_colored_polygon(pts, col)
