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
const WOOD_DARK := Color(0.128, 0.087, 0.058)
const WOOD_LIGHT := Color(0.205, 0.141, 0.093)
const CLOTH := Color(0.075, 0.135, 0.110)
const CLOTH_EDGE := Color(0.22, 0.30, 0.24)
const CLOTH_WORN := Color(0.115, 0.185, 0.150)

## The room behind the table. Everything here is DARKER than the table, and
## deliberately so: the screen's text sits on top of it, and a back wall that
## competes with the words costs more than it gives. It should be recognised
## rather than looked at.
const WALL := Color(0.068, 0.052, 0.046)
const WALL_STRIPE := Color(0.092, 0.070, 0.059)
const RAIL := Color(0.115, 0.084, 0.061)
const DOOR := Color(0.098, 0.070, 0.050)
const DOOR_PANEL := Color(0.074, 0.052, 0.037)
const DOOR_EDGE := Color(0.140, 0.102, 0.072)
const BRASS := Color(0.40, 0.31, 0.15)
const COAT := Color(0.082, 0.078, 0.096)
const FLOOR := Color(0.052, 0.041, 0.036)
const FLOOR_SEAM := Color(0.028, 0.022, 0.019)

## The Minitel, which the game already has a whole screen for (3615 codes, see
## autoload/Minitel.gd) and which had never once been drawn. Beige plastic, a
## small green phosphor screen, a keyboard folded down in front.
const MINITEL_BODY := Color(0.200, 0.180, 0.148)
const MINITEL_SHADE := Color(0.130, 0.116, 0.095)
const MINITEL_DARK := Color(0.085, 0.075, 0.062)
const MINITEL_SCREEN := Color(0.045, 0.075, 0.052)
const MINITEL_GLOW := Color(0.36, 0.70, 0.41)

## The cup, and the lamplight it sits in. Both come straight out of the card
## list — WARM THE CUP, LIGHT THE LAMP — so they are the room the writing
## already described.
const CHINA := Color(0.52, 0.50, 0.46)
const CHINA_SHADE := Color(0.33, 0.32, 0.29)
const TEA := Color(0.32, 0.19, 0.10)
const LAMPLIGHT := Color(1.0, 0.82, 0.52)

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


## The three views of the room, which is the whole set: one game, one parlour,
## three places to be standing in it.
##
##   TABLE   you are at the table, looking down at the cloth. The reading, the
##           rewards, the shop, the reference screens.
##   DOOR    you are looking across the room at the door somebody is about to
##           knock on. The menu, "who knocks tonight?", and the end of a run,
##           which is the night the knocking stops.
##   WALL    just the papered wall and the floor, no props. For the reference
##           screens — settings, library, mods, the rules, the credits. They are
##           dense with words and there is nothing happening in them; a table
##           laid out behind a list of sliders is something to look past, not at.
const VIEW_TABLE := "table"
const VIEW_DOOR := "door"
const VIEW_WALL := "wall"


## The room, as a full-rect backdrop to put behind a screen. Draws nothing that
## moves and takes no input, so it can sit under anything.
static func background(view: String = VIEW_TABLE) -> Control:
	var c := Control.new()
	c.name = "Room"
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No z_index: this is added straight after UIKit.root_control()'s flat
	# background ColorRect and paints over it, and everything the screen adds
	# afterwards is a later sibling and so draws on top. Pushing it behind with
	# a negative z_index put it UNDER that opaque ColorRect, which is exactly
	# where it cannot be seen.
	match view:
		VIEW_DOOR:
			c.draw.connect(func(): _draw_doorway(c))
		VIEW_WALL:
			c.draw.connect(func(): _draw_bare_wall(c))
		_:
			c.draw.connect(func(): _draw_room(c))
	# Godot only redraws a Control when something asks it to, and this one has
	# no state of its own to change — but its SIZE changes with the window, and
	# every measurement below is taken from it.
	c.resized.connect(func(): c.queue_redraw())
	return c


## Where the far edge of the table meets the room, as a fraction of the height.
## Everything above this line is the room; everything below is the table you are
## sitting at.
const HORIZON := 0.30


## The whole room, back to front. Order is the whole trick: the wall, then the
## things against it, then the table over the bottom of them, then the cloth,
## then what is standing on the cloth, and last the light and the shadows that
## tie the three together.
static func _draw_room(c: Control) -> void:
	var s := c.size
	if s.x < 4.0 or s.y < 4.0:
		return
	var wall_h := s.y * HORIZON
	_draw_wall(c, s, wall_h)
	_draw_floor(c, s, wall_h)
	_draw_door(c, s, Rect2(s.x * 0.615, wall_h * 0.10, s.x * 0.155, wall_h * 0.90))
	_draw_coat(c, s, Vector2(s.x * 0.855, wall_h * 0.24), wall_h * 0.74)
	var cloth := _draw_table(c, s)
	_draw_minitel(c, s)
	_draw_teacup(c, s)
	_draw_light(c, s, cloth)
	_draw_vignette(c, s)


## The quietest view: the wall behind you and the boards under your feet, and
## nothing else in it at all. Same paper, same floor, so a screen using it is
## still in the same house.
static func _draw_bare_wall(c: Control) -> void:
	var s := c.size
	if s.x < 4.0 or s.y < 4.0:
		return
	var wall_h := s.y * 0.86
	_draw_wall(c, s, wall_h)
	_draw_floor(c, s, wall_h)
	_draw_vignette(c, s)


## Somebody is at the door. `amount` is 1 at the instant a fist lands on it and
## 0 at rest; the caller tweens it down. The door jumps in its frame, the light
## under it flickers, and the frame itself takes a little of it.
##
## Kept as state ON the backdrop rather than as an argument, because the room is
## drawn from a `draw` signal with no parameters and the alternative is rebuilding
## the whole node three times a knock. A view with no door ignores it.
static func set_knock(room: Control, amount: float) -> void:
	if room == null or not is_instance_valid(room):
		return
	room.set_meta("knock", amount)
	room.queue_redraw()


## The other end of the same room: you have turned your chair round and you are
## looking at the door. Nobody has knocked yet.
##
## Same wall, same door, same coat, same floor — a long way up the wall this
## time, because the table is behind you. What it adds is a cold line of outside
## under the door, and the warm pool of the lamp on the floorboards behind you,
## which between them say that the light in here is yours and the light out
## there is not.
static func _draw_doorway(c: Control) -> void:
	var s := c.size
	if s.x < 4.0 or s.y < 4.0:
		return
	var wall_h := s.y * 0.80
	_draw_wall(c, s, wall_h)
	_draw_floor(c, s, wall_h)

	# The door, near enough to reach. Well off centre and to the RIGHT: a door
	# dead centre reads as a diagram of a door, and the screens that use this
	# view put their words down the left.
	var dw := minf(s.x * 0.185, s.y * 0.37)
	var leaf := Rect2(s.x * 0.655 - dw * 0.5, wall_h * 0.13, dw, wall_h * 0.87)
	# A knock moves the LEAF and not the frame, because that is what a door in a
	# frame does — it is the gap between them that rattles.
	var hit: float = float(c.get_meta("knock", 0.0))
	if hit > 0.001:
		leaf.position += Vector2(s.y * 0.006 * hit, -s.y * 0.0035 * hit)
	_draw_door(c, s, leaf, true, hit)
	_draw_coat(c, s, Vector2(s.x * 0.885, wall_h * 0.19), wall_h * 0.50)

	# The lamp behind you, thrown forward across the boards. It stops short of
	# the door, which is the whole point of it.
	for i in range(9, 0, -1):
		var f := float(i) / 9.0
		c.draw_circle(Vector2(s.x * 0.5, s.y * 1.02), s.x * 0.44 * f, Color(LAMPLIGHT, 0.013))
	_draw_vignette(c, s)


## The back wall: striped paper, a picture rail near the top, and a skirting
## board where it meets the floor. The stripes are what make it read as a room
## in a house rather than as a dark rectangle.
static func _draw_wall(c: Control, s: Vector2, wall_h: float) -> void:
	c.draw_rect(Rect2(0, 0, s.x, wall_h), WALL)
	var pitch := s.x * 0.032
	var x := pitch * 0.5
	var i := 0
	while x < s.x:
		# Two weights alternating, the way a printed paper has a wide band and a
		# hairline between them.
		var wide := i % 2 == 0
		c.draw_line(Vector2(x, 0), Vector2(x, wall_h),
			Color(WALL_STRIPE, 0.9 if wide else 0.45), pitch * (0.34 if wide else 0.10), true)
		x += pitch
		i += 1
	# The picture rail, and the skirting under it.
	var rail_y := wall_h * 0.16
	c.draw_line(Vector2(0, rail_y), Vector2(s.x, rail_y), Color(RAIL, 0.75), maxf(1.0, s.y * 0.005), true)
	c.draw_rect(Rect2(0, wall_h - s.y * 0.022, s.x, s.y * 0.022), Color(RAIL, 0.5))


## The floor. It is only ever seen in two narrow wedges either side of the
## table — but without it those wedges are the flat colour of the empty screen
## behind everything, and the table reads as a shape cut out of a void rather
## than a piece of furniture standing on something. Boards crowding together
## toward the wall is the whole of the perspective here.
static func _draw_floor(c: Control, s: Vector2, y: float) -> void:
	c.draw_rect(Rect2(0, y, s.x, s.y - y), FLOOR)
	for i in 6:
		var t := (float(i) + 1.0) / 7.0
		var by := y + (s.y - y) * pow(t, 1.8)
		c.draw_line(Vector2(0, by), Vector2(s.x, by), Color(FLOOR_SEAM, 0.55),
			maxf(1.0, s.y * 0.003), true)


## The door. It is the one prop in this room with a job: someone knocks on it,
## and a run ends when the knocking stops. Closed, panelled, brass knob, hinged
## on the far side so the knob faces the room.
static func _draw_door(c: Control, s: Vector2, leaf: Rect2, under_light: bool = false, hit: float = 0.0) -> void:
	var w := leaf.size.x
	# The architrave is a BORDER, not a filled rectangle behind the leaf. Filled,
	# it was a pale slab the size of a door sitting directly under the header
	# text, which is the loudest thing this room could possibly have done.
	var frame := leaf.grow_individual(w * 0.055, leaf.size.y * 0.035, w * 0.055, 0.0)
	c.draw_rect(frame, Color(DOOR_EDGE, 0.55), false, maxf(1.0, s.y * 0.005))
	c.draw_rect(leaf, DOOR)

	# Two recessed panels, each with a lit top edge so the recess reads.
	for k in 2:
		var ph := leaf.size.y * (0.40 if k == 0 else 0.30)
		var py := leaf.position.y + leaf.size.y * (0.09 if k == 0 else 0.60)
		var panel := Rect2(leaf.position.x + w * 0.16, py, w * 0.68, ph)
		c.draw_rect(panel, DOOR_PANEL)
		c.draw_line(panel.position, panel.position + Vector2(panel.size.x, 0),
			Color(DOOR_EDGE, 0.45), 1.0, true)
		c.draw_line(panel.position + Vector2(0, panel.size.y),
			panel.end, Color(0, 0, 0, 0.35), 1.0, true)

	# The knob, on the room side.
	var knob := Vector2(leaf.position.x + w * 0.10, leaf.position.y + leaf.size.y * 0.52)
	var knob_r := maxf(2.0, minf(s.y * 0.011, w * 0.07))
	c.draw_circle(knob, knob_r, Color(BRASS, 0.85))
	c.draw_circle(knob - Vector2(knob_r * 0.3, knob_r * 0.3), knob_r * 0.36, Color(1, 0.92, 0.75, 0.5))

	# A cold sliver of outside under the door. Only in the view that faces it —
	# on the reading screen the door is a detail at the back of the room, and a
	# glowing line under it would be the brightest thing on the table.
	if under_light:
		var cold := Color(0.56, 0.64, 0.78)
		# The spill first, ON THE FLOOR in front of the threshold and fading as
		# it goes — light under a door lands somewhere. Then the gap itself, a
		# hairline. A first pass drew the gap alone, thick and bright, and it
		# read as a strip light rather than as night on the other side.
		for i in 7:
			var f := float(i) / 7.0
			c.draw_rect(Rect2(leaf.position.x - w * 0.06 * f, leaf.end.y,
				w * (1.0 + 0.12 * f), s.y * 0.055 * f), Color(cold, 0.012))
		c.draw_rect(Rect2(leaf.position.x, leaf.end.y - s.y * 0.0015, w, s.y * 0.003),
			Color(cold, 0.20 + 0.55 * hit))
		# Whoever is out there is standing in the light, so a knock puts more of
		# them across the threshold, not less.
		if hit > 0.001:
			for i in 4:
				var g := float(i) / 4.0
				c.draw_rect(Rect2(leaf.position.x - w * 0.10 * g, leaf.end.y,
					w * (1.0 + 0.20 * g), s.y * 0.085 * g), Color(cold, 0.030 * hit))


## A coat on a hook by the door — TAKE THEIR COAT is the first thing a lot of
## readings open with, and this is where it goes.
static func _draw_coat(c: Control, s: Vector2, at: Vector2, length: float) -> void:
	c.draw_line(at, at + Vector2(0, s.y * 0.012), Color(BRASS, 0.6), maxf(1.0, s.y * 0.004), true)
	# Shoulders, then a body that widens and settles — a hung coat, not a person.
	var body := PackedVector2Array([
		at + Vector2(0, s.y * 0.014),
		at + Vector2(s.x * 0.028, s.y * 0.040),
		at + Vector2(s.x * 0.032, length),
		at + Vector2(-s.x * 0.032, length),
		at + Vector2(-s.x * 0.028, s.y * 0.040),
	])
	c.draw_colored_polygon(_soften(body, s.y * 0.016), COAT)
	c.draw_line(at + Vector2(0, s.y * 0.022), at + Vector2(0, length * 0.95),
		Color(0, 0, 0, 0.30), maxf(1.0, s.y * 0.004), true)


## The table, in perspective: narrow at the far edge, running off both sides at
## the front. Returns the cloth's outline, which the light and the shadows are
## measured against.
static func _draw_table(c: Control, s: Vector2) -> Array:
	var y := s.y * HORIZON + s.y * 0.02
	var top := PackedVector2Array([
		Vector2(s.x * 0.115, y), Vector2(s.x * 0.885, y),
		Vector2(s.x * 1.06, s.y * 1.02), Vector2(-s.x * 0.06, s.y * 1.02),
	])
	c.draw_colored_polygon(top, WOOD_DARK)
	# The lit far lip, which is what makes it a surface with a thickness rather
	# than a shape cut out of the wall.
	c.draw_line(Vector2(s.x * 0.115, y), Vector2(s.x * 0.885, y),
		Color(WOOD_LIGHT, 0.55), maxf(1.5, s.y * 0.006), true)

	# Grain, running away from the viewer along the perspective.
	for i in 13:
		var t := (float(i) + 0.5) / 13.0
		var a := Vector2(s.x * 0.115, y).lerp(Vector2(s.x * 0.885, y), t)
		var b := Vector2(-s.x * 0.06, s.y * 1.02).lerp(Vector2(s.x * 1.06, s.y * 1.02), t)
		c.draw_line(a, b, Color(WOOD_LIGHT, 0.05 + 0.045 * sin(t * 23.0)), 1.0, true)

	# The cloth, following the same perspective and hanging over the front edge.
	var cloth := PackedVector2Array([
		Vector2(s.x * 0.165, y + s.y * 0.045), Vector2(s.x * 0.835, y + s.y * 0.045),
		Vector2(s.x * 1.01, s.y * 0.99), Vector2(-s.x * 0.01, s.y * 0.99),
	])
	var soft := _soften(cloth, s.y * 0.07)
	c.draw_colored_polygon(soft, CLOTH)

	# A worn lighter patch in the middle, where a lifetime of hands has rubbed
	# the pile flat. Very soft — it should be felt, not noticed.
	var mid := Vector2(s.x * 0.5, s.y * 0.66)
	for i in range(6, 0, -1):
		var f := float(i) / 6.0
		c.draw_circle(mid, s.x * 0.30 * f, Color(CLOTH_WORN, 0.05))

	var edge := soft.duplicate()
	edge.append(edge[0])
	c.draw_polyline(edge, CLOTH_EDGE, 2.0, true)
	return [soft, mid]


## The Minitel, on the table at the reader's right: body, screen, keyboard. It
## is the same machine the 3615 screen dials, and the room is where it lives.
static func _draw_minitel(c: Control, s: Vector2) -> void:
	var u := s.y * 0.30            # the whole thing is about this tall
	var at := s * MINITEL_AT       # the front-bottom of it
	# What it stands in. Without a shadow it floats, and a Minitel floating a
	# centimetre above a tablecloth is the one thing nobody has seen.
	_blob(c, at + Vector2(0, u * 0.02), u * 0.52, u * 0.10, Color(0, 0, 0, 0.32))

	# The keyboard slab, nearest the viewer.
	var kb := PackedVector2Array([
		at + Vector2(-u * 0.42, -u * 0.10), at + Vector2(u * 0.42, -u * 0.10),
		at + Vector2(u * 0.46, 0.0), at + Vector2(-u * 0.46, 0.0),
	])
	c.draw_colored_polygon(kb, MINITEL_SHADE)
	c.draw_colored_polygon(_shift(kb, Vector2(0, -u * 0.035)), MINITEL_BODY)
	# Keys, as a grid of small dark marks. Four rows is enough to read.
	for row in 4:
		for col in 9:
			var k := at + Vector2((float(col) - 4.0) * u * 0.088,
				-u * 0.055 - float(row) * u * 0.028)
			c.draw_rect(Rect2(k - Vector2(u * 0.026, u * 0.010),
				Vector2(u * 0.052, u * 0.019)), Color(MINITEL_DARK, 0.75))

	# The body, standing up behind the keyboard.
	var body_bottom := at.y - u * 0.17
	var body := PackedVector2Array([
		Vector2(at.x - u * 0.36, body_bottom - u * 0.62),
		Vector2(at.x + u * 0.36, body_bottom - u * 0.62),
		Vector2(at.x + u * 0.40, body_bottom),
		Vector2(at.x - u * 0.40, body_bottom),
	])
	c.draw_colored_polygon(_soften(body, u * 0.05), MINITEL_SHADE)
	c.draw_colored_polygon(_soften(_shift(body, Vector2(-u * 0.012, -u * 0.014)), u * 0.05), MINITEL_BODY)

	# The screen: recessed, dark, with the phosphor still warm in it.
	var screen := Rect2(at.x - u * 0.28, body_bottom - u * 0.55, u * 0.56, u * 0.40)
	c.draw_rect(screen.grow(u * 0.018), MINITEL_DARK)
	c.draw_rect(screen, MINITEL_SCREEN)
	for i in range(4, 0, -1):
		var f := float(i) / 4.0
		c.draw_rect(screen.grow(-u * 0.02 + u * 0.05 * (1.0 - f)), Color(MINITEL_GLOW, 0.030))
	# A few lines of text on it. Not words — at this size words would be noise;
	# what reads is that something is written there.
	const SCREEN_LINES := [0.72, 0.50, 0.84, 0.34]
	for line in SCREEN_LINES.size():
		var ly := screen.position.y + u * 0.062 + float(line) * u * 0.075
		var lw: float = screen.size.x * SCREEN_LINES[line]
		c.draw_line(Vector2(screen.position.x + u * 0.045, ly),
			Vector2(screen.position.x + u * 0.045 + lw, ly), Color(MINITEL_GLOW, 0.40),
			maxf(1.0, u * 0.016), true)


## Where the props stand. They are BEHIND the screen's words, so where they go
## is not a taste question: it is which parts of the table the reading screen
## leaves empty. The left third from the bars down to the hand label is solid
## text, and a cup sitting in the middle of "YOUR HAND — hover a card" is worse
## than no cup. These two spots are clear in every layout the screen produces.
const MINITEL_AT := Vector2(0.875, 0.535)
const TEACUP_AT := Vector2(0.635, 0.435)


## A cup of tea, going cold on the far side of the table where the sitter left
## it. POUR THE TEA and WARM THE CUP are both cards; this is the cup they mean.
static func _draw_teacup(c: Control, s: Vector2) -> void:
	var u := s.y * 0.085
	var at := s * TEACUP_AT

	# Saucer, then the shadow it sits in.
	c.draw_circle(at + Vector2(u * 0.06, u * 0.05), u * 0.62, Color(0, 0, 0, 0.28))
	_blob(c, at, u * 0.60, u * 0.24, CHINA_SHADE)
	_blob(c, at - Vector2(0, u * 0.03), u * 0.54, u * 0.20, CHINA)

	# The cup: a body tapering down onto the saucer, an ellipse of tea on top.
	var rim := at - Vector2(0, u * 0.44)
	var body := PackedVector2Array([
		rim + Vector2(-u * 0.34, 0), rim + Vector2(u * 0.34, 0),
		at + Vector2(u * 0.24, -u * 0.06), at + Vector2(-u * 0.24, -u * 0.06),
	])
	c.draw_colored_polygon(_soften(body, u * 0.07), CHINA_SHADE)
	c.draw_colored_polygon(_soften(_shift(body, Vector2(-u * 0.03, 0)), u * 0.07), CHINA)
	# The handle, on the outside.
	c.draw_arc(rim + Vector2(u * 0.40, u * 0.18), u * 0.17, -PI * 0.55, PI * 0.55,
		12, CHINA_SHADE, maxf(1.5, u * 0.07), true)
	_blob(c, rim, u * 0.34, u * 0.12, CHINA_SHADE)
	_blob(c, rim, u * 0.28, u * 0.09, TEA)


## The lamp overhead, as the light it throws rather than as a lamp: a warm pool
## on the cloth falling off toward the edges of the room. Nothing in the game's
## framing lets you see the ceiling, and a light you can feel is worth more than
## a lamp you can point at.
static func _draw_light(c: Control, s: Vector2, cloth: Array) -> void:
	var mid: Vector2 = cloth[1]
	for i in range(9, 0, -1):
		var f := float(i) / 9.0
		c.draw_circle(mid - Vector2(0, s.y * 0.06), s.x * 0.42 * f, Color(LAMPLIGHT, 0.012))


## Vignette: soft bands darkening the outside, which puts the eye in the middle
## of the table where the cards are — and, just as usefully, keeps the room from
## competing with the words printed over it.
static func _draw_vignette(c: Control, s: Vector2) -> void:
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
##
## `reach` is how far the fingers extend. 1.0 is a hand holding something: the
## fingers stretch to the top of the band and close over whatever is drawn
## there. Below 1.0 they shorten and curl, and the hand OPENS — which is what a
## pair of hands that has just let go of something looks like, and what the
## reading screen asks for when a single card is left floating above them.
static func hands(marks: Array, span: Callable = Callable(), reach: float = 1.0) -> Control:
	var c := Control.new()
	# Named so a test can find it. The hands are a layer with no text on them
	# and no widget in them, so there is nothing else to identify them by.
	c.name = "Hands"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size.y = 110
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var held: Array = marks.duplicate()
	var r := clampf(reach, 0.35, 1.0)
	c.draw.connect(func(): _draw_hands(c, held, span, r))
	c.resized.connect(func(): c.queue_redraw())
	return c


static func _draw_hands(c: Control, marks: Array, span: Callable, reach: float) -> void:
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
	# holding it. An OPEN hand needs more room than a closed one, because its
	# fingers curl inward across the palm, so the floor rises as the reach drops.
	half = maxf(half, hand_w * (0.95 + (1.0 - reach) * 0.35))
	# And never off the screen, however wide the fan gets.
	var at := Vector2(clampf(centre - half, hand_w * 0.45, s.x * 0.5),
		clampf(centre + half, s.x * 0.5, s.x - hand_w * 0.45))

	_draw_hand(c, Vector2(at.x, s.y), 1.0, left, reach)
	_draw_hand(c, Vector2(at.y, s.y), -1.0, right, reach)


## The hand's proportions, as fractions of the band height. Four fingers,
## longest in the middle, each two segments with a bend at the knuckle.
const PALM_DROP := 0.02          # how far the palm sits below the band's bottom
const KNUCKLE_Y := -0.19         # where the fingers leave the hand
const FINGER_LENGTHS := [0.72, 0.86, 0.80, 0.60]
const FINGER_WIDTHS := [0.048, 0.052, 0.050, 0.043]
const FINGER_SPREAD := 0.135


## Where one hand's four fingers are: [root, knuckle, tip, width] each, in the
## band's own coordinates, with `base` on its bottom edge and `flip` +1 for the
## left hand and -1 for the right.
##
## Public, and separate from the drawing, for the same reason mark_places() is:
## a test that asks whether the fingertips clear a floating card has to read the
## SAME geometry the drawing uses. Re-deriving it in the test would only assert
## that two copies of a formula agree.
static func finger_geometry(base: Vector2, h: float, flip: float, reach: float) -> Array:
	var r := clampf(reach, 0.35, 1.0)
	var palm := base + Vector2(0, PALM_DROP * h)
	var out := Vector2(0.12 * flip, -1.0).normalized()
	# The less a hand reaches, the more it curls. Simply shortening the fingers
	# gives a hand with stubs on it; shortening AND bending them gives an open
	# hand, which is what a hand that has just let go of something looks like.
	var curl := Vector2((0.46 + (1.0 - r) * 1.30) * flip, -1.0).normalized()
	var fingers: Array = []
	for i in FINGER_LENGTHS.size():
		var root := palm + Vector2((float(i) - 1.5) * FINGER_SPREAD * h * flip, KNUCKLE_Y * h)
		var length: float = float(FINGER_LENGTHS[i]) * h * r
		var knuckle := root + out * (length * 0.58)
		fingers.append([root, knuckle, knuckle + curl * (length * 0.42),
			float(FINGER_WIDTHS[i]) * h])
	return fingers


## One hand, rooted at `base` (on the bottom edge) and angled inward.
## `flip` is +1 for the left hand and -1 for the right.
##
## EVERY MEASUREMENT IS A FRACTION OF THE BAND HEIGHT, so the hand keeps its
## proportions whatever height the screen gives it and — the part that matters —
## the fingertips always land at the same place: a fixed fraction from the top.
## The caller positions the band; that alone decides how far up the cards the
## fingers reach.
static func _draw_hand(c: Control, base: Vector2, flip: float, marks: Array, reach: float = 1.0) -> void:
	var h := c.size.y

	# The back of the hand, sitting just above the bottom of the band so that a
	# good third of it is on screen. An earlier pass buried all but a sliver of
	# it, and fingers growing out of nothing read as a mitten; it also has to be
	# visible for the tattoos and scars that go on it to be anywhere at all.
	# What falls below the band is the wrist, running off the bottom of the
	# screen, which is where a hand reaching up to hold a fan comes from.
	var palm := base + Vector2(0, PALM_DROP * h)
	_blob(c, palm, 0.345 * h, 0.315 * h, SKIN_LINE)
	_blob(c, palm, 0.330 * h, 0.300 * h, SKIN_SHADE)
	_blob(c, palm + Vector2(0.01 * h * flip, 0.02 * h), 0.295 * h, 0.260 * h, SKIN)

	var fingers := finger_geometry(base, h, flip, reach)
	var segments: Array = []
	for finger in fingers:
		var root: Vector2 = finger[0]
		var knuckle: Vector2 = finger[1]
		var tip: Vector2 = finger[2]
		var w: float = finger[3]
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
		var along := (knuckle - root).normalized()
		var across := Vector2(-along.y, along.x) * (w * 0.70)
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


## The same polygon with every corner rounded off, using the corner itself as
## the control point of a quadratic curve between the two edges that meet there.
##
## Nothing in this room is a rectangle: the table and the cloth are trapezoids
## because they are drawn in perspective, and the Minitel's body and the cup are
## tapered. An earlier rounded-RECTANGLE helper could draw none of them, so this
## rounds whatever shape it is handed instead.
static func _soften(points: PackedVector2Array, r: float, steps: int = 5) -> PackedVector2Array:
	var n := points.size()
	if n < 3 or r <= 0.0:
		return points
	var out := PackedVector2Array()
	for i in n:
		var prev := points[(i - 1 + n) % n]
		var cur := points[i]
		var next := points[(i + 1) % n]
		# Never eat more than the edge can spare, or two roundings on a short
		# edge cross each other and the polygon turns inside out.
		var a := cur + (prev - cur).normalized() * minf(r, (prev - cur).length() * 0.45)
		var b := cur + (next - cur).normalized() * minf(r, (next - cur).length() * 0.45)
		for j in steps + 1:
			var t := float(j) / float(steps)
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	return out


## The same polygon, moved. Used to lay a lit copy of a shape over its shaded
## one, which is how everything in this room gets an edge without an outline.
static func _shift(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p + by)
	return out
