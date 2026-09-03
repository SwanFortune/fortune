## The parlour itself: a table, a cloth, and the reader's own hands holding the
## fan — with every mark they have picked up drawn onto them.
##
## The reading screen was a dark rectangle with widgets on it. The game is a
## fortune-teller at a table in a village front room, and none of that was
## anywhere on screen. This is that room, drawn procedurally.
##
## PLACEHOLDER, on the same terms as UIKit.sitter_portrait() and the app icon:
## it is geometry, not illustration, and it is meant to be replaced by an
## artist's work — see docs/ART_GUIDE.md. It ships because a game that looks
## like a spreadsheet reads as unfinished no matter how good the engine under
## it is, and because the hands close a loop the writing had already opened.
##
## THE HANDS ARE NOT DECORATION. The overlay that lists your relics is called
## YOUR HANDS, and the marks themselves are rings, tattoos, scars and boons —
## the game has always described them as things ON the reader's hands, and they
## have only ever been a list. Now a ring you win goes on a finger and stays
## there for the rest of the run, where you can see it while you play.
##
## Each of the four kinds knows where it belongs:
##   RING    a band around a finger, the metal tinted by what it does
##   TATTOO  ink on the back of the hand
##   SCAR    a pale line across the knuckles
##   BOON    a small warm glow above the hand — the one that is not a mark on
##           the skin, so it is not drawn as one
extends RefCounted

## Loaded by path, not by `class_name` — see autoload/Content.gd's header.
const UIKit := preload("res://scenes/UIKit.gd")

# ── the room ────────────────────────────────────────────────────────────

## The table is warm and clearly wood; the cloth is a deep green that reads as
## cloth against it. An earlier pass had both so close in value that the cloth
## was invisible — which is the whole reason to draw a table at all.
const WOOD_DARK := Color(0.155, 0.105, 0.070)
const WOOD_LIGHT := Color(0.255, 0.175, 0.115)
const CLOTH := Color(0.075, 0.135, 0.110)
const CLOTH_EDGE := Color(0.22, 0.30, 0.24)
const CLOTH_WORN := Color(0.115, 0.185, 0.150)

## Skin, and the line around it. Warm and desaturated — a lamp-lit room, not
## daylight.
const SKIN := Color(0.72, 0.58, 0.47)
const SKIN_SHADE := Color(0.58, 0.45, 0.36)
const SKIN_LINE := Color(0.30, 0.22, 0.17)

## Every part of a hand is drawn three times: a dark silhouette a little wider
## than the part, the shaded skin at its true size, and the lit skin inset and
## offset toward the light. That gives an edge without stroking an outline over
## the fill, and the dark pass of one finger is what separates it from the one
## behind it.
const SKIN_PASSES := [SKIN_LINE, SKIN_SHADE, SKIN]
const PASS_GROW := [1.16, 1.0, 0.80]


## The table with its cloth: a full-rect background to put behind a screen.
## Draws nothing that moves and takes no input, so it can sit under anything.
static func background() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No z_index: this is added straight after UIKit.root_control()'s flat
	# background ColorRect and paints over it, and everything the screen adds
	# afterwards is a later sibling and so draws on top. Pushing it behind with
	# a negative z_index put it UNDER that opaque ColorRect, which is exactly
	# where it cannot be seen.
	c.draw.connect(func(): _draw_room(c))
	# Godot only redraws a Control when something asks it to, and this one has
	# no state of its own to change — but its SIZE changes with the window, and
	# every measurement below is taken from it.
	c.resized.connect(func(): c.queue_redraw())
	return c


static func _draw_room(c: Control) -> void:
	var s := c.size
	if s.x < 4.0 or s.y < 4.0:
		return

	# The table: a warm dark ground with a few grain lines running its length.
	c.draw_rect(Rect2(Vector2.ZERO, s), WOOD_DARK)
	var grain := 14
	for i in grain:
		var t := (float(i) + 0.5) / float(grain)
		var y := s.y * t
		var wobble := sin(t * 9.0) * s.y * 0.012
		c.draw_line(Vector2(0, y + wobble), Vector2(s.x, y - wobble),
			Color(WOOD_LIGHT, 0.16 + 0.1 * sin(t * 21.0)), 1.0, true)

	# The cloth: inset from the table on every side, so the wood shows as a
	# border. Rounded, because a cloth thrown over a table has no corners.
	var inset := Vector2(s.x * 0.035, s.y * 0.05)
	var cloth := Rect2(inset, s - inset * 2.0)
	var radius := minf(cloth.size.x, cloth.size.y) * 0.06
	_rounded(c, cloth, radius, CLOTH)

	# A worn lighter patch in the middle, where a lifetime of hands has rubbed
	# the pile flat. Elliptical and very soft — it should be felt, not noticed.
	var mid := cloth.position + cloth.size * 0.5
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_circle(mid, cloth.size.x * 0.34 * f, Color(CLOTH_WORN, 0.055))

	# The cloth's own edge, a shade lighter than its face.
	_rounded_outline(c, cloth, radius, CLOTH_EDGE, 2.0)

	# Vignette: four soft bands darkening the outside, which puts the eye in
	# the middle of the table where the cards are.
	var depth := 22
	for i in depth:
		var f := float(i) / float(depth)
		var a := 0.05 * (1.0 - f)
		var band := s.y * 0.16 * f
		c.draw_rect(Rect2(0, 0, s.x, band), Color(0, 0, 0, a))
		c.draw_rect(Rect2(0, s.y - band, s.x, band), Color(0, 0, 0, a))
		var side := s.x * 0.10 * f
		c.draw_rect(Rect2(0, 0, side, s.y), Color(0, 0, 0, a))
		c.draw_rect(Rect2(s.x - side, 0, side, s.y), Color(0, 0, 0, a))


# ── the hands ───────────────────────────────────────────────────────────

## A pair of hands rising from the bottom edge, fingers curling up over
## whatever is drawn in front of them. `marks` is Run.state's marks array; each
## one is placed on a hand according to its `kind`.
##
## Sized by its parent — pass it a Control that spans the width under the fan.
## The hands sit at the two ends, so the cards appear to be held between them.
## Add it AFTER the cards: the fingertips have to draw over their lower edge,
## which is the whole difference between hands holding a fan and hands drawn
## near one.
##
## `span` is an optional Callable returning the horizontal extent of the thing
## being held, as a Vector2 of local x coordinates. Called at DRAW time, which
## is after layout, so it can measure the fan itself — and it has to, because a
## hand of two cards and a hand of nine are not the same width, and hands nailed
## to fixed fractions of the screen hold the first at arm's length and the
## second by the middle. Return a degenerate span (or pass nothing) to fall back
## to those fractions.
static func hands(marks: Array, span: Callable = Callable()) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = 110
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var held: Array = marks.duplicate()
	c.draw.connect(func(): _draw_hands(c, held, span))
	c.resized.connect(func(): c.queue_redraw())
	return c


static func _draw_hands(c: Control, marks: Array, span: Callable) -> void:
	var s := c.size
	if s.x < 80.0 or s.y < 20.0:
		return
	# Marks alternate between the two hands in the order they were won, so a
	# player can find a particular one again: the third ring you took is always
	# on the same finger.
	var left: Array = []
	var right: Array = []
	for i in marks.size():
		if i % 2 == 0:
			left.append(marks[i])
		else:
			right.append(marks[i])

	# How much room one hand takes, thumb to little finger. Everything below is
	# spaced in these, so a hand is never asked to stand somewhere it does not
	# fit.
	var hand_w := s.y * 0.72

	var centre := s.x * 0.5
	var half := s.x * 0.37
	if span.is_valid():
		var measured: Vector2 = span.call()
		if measured.y > measured.x:
			centre = (measured.x + measured.y) * 0.5
			# Just INSIDE the edges of what is held, so the fingers land on the
			# cards rather than beside them.
			half = (measured.y - measured.x) * 0.5 - hand_w * 0.28
	# A floor on how close the two can come. A single card is barely wider than
	# one hand, and following its edges put the two palms together in the middle
	# of the screen covering the only card in play — praying over it rather than
	# holding it.
	half = maxf(half, hand_w * 0.95)
	# And never off the screen, however wide the fan gets.
	var at := Vector2(clampf(centre - half, hand_w * 0.45, s.x * 0.5),
		clampf(centre + half, s.x * 0.5, s.x - hand_w * 0.45))

	_draw_hand(c, Vector2(at.x, s.y), 1.0, left)
	_draw_hand(c, Vector2(at.y, s.y), -1.0, right)


## One hand, rooted at `base` (on the bottom edge) and angled inward.
## `flip` is +1 for the left hand and -1 for the right.
##
## EVERY MEASUREMENT IS A FRACTION OF THE BAND HEIGHT, so the hand keeps its
## proportions whatever height the screen gives it and — the part that matters —
## the fingertips always land at the same place: a fixed fraction from the top.
## The caller positions the band; that alone decides how far up the cards the
## fingers reach.
static func _draw_hand(c: Control, base: Vector2, flip: float, marks: Array) -> void:
	var h := c.size.y

	# The back of the hand, sitting just above the bottom of the band so that a
	# good third of it is on screen. An earlier pass buried all but a sliver of
	# it, and fingers growing out of nothing read as a mitten; it also has to be
	# visible for the tattoos and scars that go on it to be anywhere at all.
	# What falls below the band is the wrist, running off the bottom of the
	# screen, which is where a hand reaching up to hold a fan comes from.
	var palm := base + Vector2(0, 0.02 * h)
	_blob(c, palm, 0.345 * h, 0.315 * h, SKIN_LINE)
	_blob(c, palm, 0.330 * h, 0.300 * h, SKIN_SHADE)
	_blob(c, palm + Vector2(0.01 * h * flip, 0.02 * h), 0.295 * h, 0.260 * h, SKIN)

	# Four fingers, longest in the middle. Each is two segments with a bend at
	# the knuckle: straight out of the hand, then curling in over the cards.
	var lengths := [0.72, 0.86, 0.80, 0.60]
	var widths := [0.048, 0.052, 0.050, 0.043]
	var segments: Array = []
	for i in 4:
		var spread := (float(i) - 1.5) * 0.135 * h * flip
		var root := palm + Vector2(spread, -0.19 * h)
		var length: float = float(lengths[i]) * h
		var w: float = float(widths[i]) * h
		var out := Vector2(0.12 * flip, -1.0).normalized()
		var knuckle := root + out * (length * 0.58)
		var curl := Vector2(0.46 * flip, -1.0).normalized()
		var tip := knuckle + curl * (length * 0.42)
		segments.append([root, knuckle, w])

		# Dark first, then the shaded skin, then the lit skin inset toward the
		# light: three passes give an edge without drawing an outline over the
		# fill, and the dark pass of the next finger separates it from this one.
		for pass_i in 3:
			var col: Color = SKIN_PASSES[pass_i]
			var grow: float = PASS_GROW[pass_i]
			var shift := Vector2.ZERO if pass_i < 2 else Vector2(w * 0.14 * flip, w * 0.10)
			_taper(c, root + shift, knuckle + shift, w * grow, w * 0.94 * grow, col)
			_taper(c, knuckle + shift, tip + shift, w * 0.94 * grow, w * 0.80 * grow, col)

		# The nail, following the last segment: a paler oval at the very end.
		var nail_dir := (tip - knuckle).normalized()
		_taper(c, tip - nail_dir * (w * 1.05), tip - nail_dir * (w * 0.25),
			w * 0.50, w * 0.58, Color(0.85, 0.73, 0.66, 0.75))

		# A crease at the bend, so a finger reads as jointed and not as a peg.
		var across := Vector2(-out.y, out.x) * (w * 0.70)
		c.draw_line(knuckle - across, knuckle + across, Color(SKIN_LINE, 0.40), maxf(1.0, w * 0.16), true)

		# The tendon running from the knuckle down the back of the hand. Four
		# faint lines are the difference between the back of a hand and a mitt.
		c.draw_line(root, root.lerp(palm, 0.62), Color(SKIN_LINE, 0.16), maxf(1.0, w * 0.24), true)

	# The thumb, across the outside and lower than the fingers, resting against
	# the near edge of the fan.
	var t_root := palm + Vector2(-0.29 * h * flip, 0.03 * h)
	var t_knuckle := t_root + Vector2(-0.11 * h * flip, -0.21 * h)
	var t_tip := t_knuckle + Vector2(0.07 * h * flip, -0.17 * h)
	var tw := 0.062 * h
	for pass_i in 3:
		var col: Color = SKIN_PASSES[pass_i]
		var grow: float = PASS_GROW[pass_i]
		_taper(c, t_root, t_knuckle, tw * grow, tw * 0.92 * grow, col)
		_taper(c, t_knuckle, t_tip, tw * 0.92 * grow, tw * 0.78 * grow, col)

	_draw_marks(c, marks, palm, segments, h, flip)


## The four kinds this knows how to draw. Public because a test asserts that
## every kind the content actually uses is one of them: a mark of an unknown
## kind is skipped, which is right for a pack inventing one and very wrong if
## the base game quietly gains a fifth.
const KINDS := ["RING", "TATTOO", "SCAR", "BOON"]


## WHERE every mark goes, as data. Separate from the drawing so that it can be
## checked: the promise this whole file makes is that a mark you won is a mark
## you can see, and without a screen the only way to assert that is to ask where
## each one landed.
##
## Returns one entry per mark of a known kind, in order, each carrying the point
## it is drawn at and its tint. A mark of an UNKNOWN kind gets no entry — a pack
## inventing a kind should show nothing rather than a ring it did not ask for.
##
## `fingers` is the LOWER segment of each finger — root to knuckle — because
## that is where a ring is worn. `h` is the band height every measurement here
## is a fraction of, the same unit _draw_hand() uses.
static func mark_places(marks: Array, palm: Vector2, fingers: Array, h: float, flip: float) -> Array:
	var used := {"RING": 0, "TATTOO": 0, "SCAR": 0, "BOON": 0}
	var places: Array = []
	for m in marks:
		var kind := str(m.get("kind", ""))
		if not used.has(kind):
			continue
		var slot: int = used[kind]
		used[kind] = slot + 1
		var place := {"kind": kind, "tint": _mark_color(m)}
		match kind:
			"RING":
				# Rings WRAP around the four fingers rather than stopping at the
				# fourth: a run can hand out more rings than a hand has fingers,
				# and a fifth ring that is simply not drawn is a reward the
				# player was told they had and cannot find. The second one on a
				# finger sits below the first, the way a second ring does.
				var finger: Array = fingers[slot % fingers.size()] if not fingers.is_empty() else []
				var tier: int = slot / maxi(1, fingers.size())
				place["finger"] = finger
				place["tier"] = tier
				place["at"] = _ring_point(finger, tier)
			"TATTOO":
				# On the back of the hand, in a row across it — the part of the
				# palm that is above the bottom edge and clear of the knuckles.
				place["at"] = palm + Vector2(float(slot % 3 - 1) * 0.105 * h,
					-0.05 * h + float(slot / 3) * 0.085 * h)
			"SCAR":
				# Across the knuckles, where the fingers leave the hand.
				place["at"] = palm + Vector2(0, -0.215 * h - float(slot) * 0.055 * h)
			"BOON":
				# Not a mark on the skin, so it is not drawn as one: a small warm
				# light held above the hand. OUTSIDE the fingers, on the side away
				# from the fan — over them it read as a bead stuck to a knuckle,
				# and over the cards it would cover the text.
				place["at"] = palm + Vector2(-0.38 * h * flip, -0.58 * h - float(slot) * 0.15 * h)
		places.append(place)
	return places


static func _draw_marks(c: Control, marks: Array, palm: Vector2, fingers: Array, h: float, flip: float) -> void:
	for place in mark_places(marks, palm, fingers, h, flip):
		var at: Vector2 = place["at"]
		var tint: Color = place["tint"]
		match str(place["kind"]):
			"RING":
				_draw_ring(c, place["finger"], at, tint, h)
			"TATTOO":
				_draw_tattoo(c, at, tint, h)
			"SCAR":
				_draw_scar(c, at, h, flip)
			"BOON":
				_glow(c, at, 0.055 * h, tint)


## Where a ring sits on `finger` ([root, knuckle, width]) — `tier` 0 just below
## the knuckle, each one after that a little further down the finger.
static func _ring_point(finger: Array, tier: int) -> Vector2:
	if finger.size() < 2:
		return Vector2.ZERO
	var root: Vector2 = finger[0]
	var knuckle: Vector2 = finger[1]
	return root.lerp(knuckle, maxf(0.18, 0.62 - 0.22 * float(tier)))


## A band around a finger, below the knuckle so it reads as worn rather than
## balanced on the end. `finger` is [root, knuckle, width].
static func _draw_ring(c: Control, finger: Array, at: Vector2, tint: Color, h: float) -> void:
	if finger.size() < 3:
		return
	var root: Vector2 = finger[0]
	var knuckle: Vector2 = finger[1]
	var along := (knuckle - root).normalized()
	var across: Vector2 = Vector2(-along.y, along.x) * (float(finger[2]) * 1.16)
	var thickness := 0.030 * h
	c.draw_line(at - across, at + across, Color(0.04, 0.03, 0.03, 0.55), thickness + 0.014 * h, true)
	c.draw_line(at - across, at + across, tint, thickness, true)
	# One highlight dot, which is what makes metal look like metal.
	c.draw_circle(at - across * 0.35 - along * (0.005 * h), 0.012 * h, Color(1, 1, 1, 0.6))


static func _draw_tattoo(c: Control, at: Vector2, tint: Color, h: float) -> void:
	# Three short strokes: enough to read as ink at this size, and nothing that
	# pretends to be a design an artist has not drawn yet.
	for i in 3:
		var a := float(i) * TAU / 3.0 + 0.4
		var v := Vector2(cos(a), sin(a)) * (0.046 * h)
		c.draw_line(at - v, at + v, Color(tint, 0.78), 0.017 * h, true)


static func _draw_scar(c: Control, at: Vector2, h: float, flip: float) -> void:
	var half := 0.115 * h
	var pale := Color(0.86, 0.76, 0.70, 0.66)
	c.draw_line(at + Vector2(-half * flip, 0.016 * h), at + Vector2(half * flip, -0.016 * h),
		pale, 0.015 * h, true)


static func _glow(c: Control, at: Vector2, r: float, tint: Color) -> void:
	for i in range(5, 0, -1):
		var f := float(i) / 5.0
		c.draw_circle(at, r * f * 1.9, Color(tint, 0.07))
	c.draw_circle(at, r * 0.42, Color(tint, 0.72))


## A mark's colour: its element if it has one, gold otherwise. Rings that do
## something to money, energy or cards are all gold — the element is the only
## thing the data gives that is genuinely a colour.
static func _mark_color(m: Dictionary) -> Color:
	var el := str(m.get("el", ""))
	if el != "" and Content.elements.has(el):
		return UIKit.el_color(el)
	return UIKit.GOLD


# ── drawing helpers ─────────────────────────────────────────────────────

## A filled ellipse. draw_circle only does circles, and a palm is not one.
static func _blob(c: Control, at: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 28
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, col)


## A rounded bar from `from` to `to`, `r0` thick at one end and `r1` at the
## other — one segment of one finger. Drawn as a polygon rather than a line so
## the ends are properly round at any thickness, and tapered because a finger
## that is the same width along its whole length is a peg.
static func _taper(c: Control, from: Vector2, to: Vector2, r0: float, r1: float, col: Color) -> void:
	var along := (to - from)
	if along.length() < 0.01:
		return
	along = along.normalized()
	var perp := Vector2(-along.y, along.x)
	var pts := PackedVector2Array()
	var steps := 9
	for i in steps + 1:
		var a := float(i) / float(steps) * PI
		pts.append(to + (perp * r1).rotated(-a))
	for i in steps + 1:
		var a := float(i) / float(steps) * PI
		pts.append(from - (perp * r0).rotated(-a))
	c.draw_colored_polygon(pts, col)


static func _rounded(c: Control, rect: Rect2, r: float, col: Color) -> void:
	c.draw_colored_polygon(_rounded_points(rect, r), col)


static func _rounded_outline(c: Control, rect: Rect2, r: float, col: Color, width: float) -> void:
	var pts := _rounded_points(rect, r)
	pts.append(pts[0])
	c.draw_polyline(pts, col, width, true)


static func _rounded_points(rect: Rect2, r: float) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(r, r), PI, 1.5 * PI],
		[rect.position + Vector2(rect.size.x - r, r), 1.5 * PI, TAU],
		[rect.position + rect.size - Vector2(r, r), 0.0, 0.5 * PI],
		[rect.position + Vector2(r, rect.size.y - r), 0.5 * PI, PI],
	]
	for corner in corners:
		var centre: Vector2 = corner[0]
		var steps := 6
		for i in steps + 1:
			var a: float = lerpf(corner[1], corner[2], float(i) / float(steps))
			pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts
