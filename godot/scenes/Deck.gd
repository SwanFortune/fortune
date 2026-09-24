## THE DECK ON THE TABLE, and the back of every card in it.
##
## The cards you draw come from somewhere now: a pile of backs on the table,
## at the `deck` spot in data/base/room.json, as thick as what is left to draw.
## A card drawn flies off the top of it face down and turns over in your hand —
## Feel.deal() is the flight; this is the pile and the back.
##
## THE BACK is a drawing like any other: assets/art/ui/card-back.png, through
## the art manifest (the `card_back` spec). Until one is delivered, a stand-in
## is drawn here in the room's colours — deep wine, a gold edge, a moon — on
## the same terms as the rest of the room (scenes/Table.gd).
extends Control

const Table := preload("res://scenes/Table.gd")
const UIKit := preload("res://scenes/UIKit.gd")

## The art slot for the back of every card, after `ui/`.
const BACK_ART := "card-back"

## How big a card on the pile is, against a card in the hand: it is further
## away, across the table.
const PILE_SCALE := 0.5

## Cards the pile shows at most, however many are left: past a dozen a pile is
## just "thick", and drawing forty backs to say so costs more than it says.
const PILE_MAX := 12

## How the pile lies on the table, in degrees. A little crooked, as a pile
## somebody has been drawing from is.
const PILE_TURN := -9.0

## The stand-in's colours.
const WINE := Color(0.22, 0.085, 0.11)
const WINE_EDGE := Color(0.11, 0.04, 0.055)
const GOLD := Color(0.72, 0.58, 0.28)

## How many cards are left to draw.
var count := 0


## The pile, as a layer over the whole screen, drawing `n` cards at the `deck`
## spot. Named, so a test can find it.
static func pile(n: int) -> Control:
	var c: Control = (load("res://scenes/Deck.gd") as GDScript).new()
	c.name = "Deck"
	c.count = n
	return c


## One card back, `size` big, as a Control of its own: what flies from the pile
## to the hand.
static func back(size: Vector2) -> Control:
	var c := Control.new()
	c.name = "CardBack"
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): draw_back(c, Rect2(Vector2.ZERO, c.size)))
	return c


## Where the top card of a pile of `n` lies on a screen of `screen` size, before
## the pile's tilt: the rect a dealt card starts from.
static func top_rect(screen: Vector2, n: int) -> Rect2:
	var spot: Array = Content.spots.get("deck", [0.74, 0.47])
	var size := UIKit.card_face_size() * PILE_SCALE
	var centre := Vector2(float(spot[0]) * screen.x, float(spot[1]) * screen.y) + _step() * float(_layers(n) - 1)
	return Rect2(centre - size * 0.5, size)


## How many backs a pile of `n` draws: one for every two cards, at least one if
## there is any, never more than PILE_MAX.
static func _layers(n: int) -> int:
	if n <= 0:
		return 0
	return clampi((n + 1) / 2, 1, PILE_MAX)


## How far each card on the pile sits from the one under it.
static func _step() -> Vector2:
	return Vector2(-0.6, -1.3) * UIKit.card_scale()


func _ready() -> void:
	# Anchors AND offsets: see RoomTraces._ready().
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var layers := _layers(count)
	if layers == 0:
		return
	var top := top_rect(size, count)
	var bottom := top.position - _step() * float(layers - 1)
	# A shadow under the pile, so it sits on the cloth rather than over it.
	draw_set_transform(top.get_center() - _step() * float(layers - 1) + Vector2(3, 5), deg_to_rad(PILE_TURN), Vector2.ONE)
	draw_rect(Rect2(-top.size * 0.5, top.size), Color(0, 0, 0, 0.30))
	for i in layers:
		var at := bottom + _step() * float(i)
		draw_set_transform(at + top.size * 0.5, deg_to_rad(PILE_TURN), Vector2.ONE)
		draw_back(self, Rect2(-top.size * 0.5, top.size), i < layers - 1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A card's back, into `rect`. The delivered drawing when there is one; the
## stand-in otherwise. `edge_only` draws just the edge of a card under the top
## one — its face is covered, and drawing it forty times is waste.
static func draw_back(c: CanvasItem, rect: Rect2, edge_only: bool = false) -> void:
	var art: Texture2D = Art.ui_texture(BACK_ART)
	if art != null:
		c.draw_texture_rect(art, rect, false)
		return
	var r := minf(rect.size.x, rect.size.y) * 0.07
	var outline := Table._soften(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.end, rect.position + Vector2(0, rect.size.y)]), r)
	c.draw_colored_polygon(outline, WINE_EDGE)
	if edge_only:
		return
	var inset := rect.grow(-maxf(1.0, rect.size.x * 0.03))
	c.draw_colored_polygon(Table._soften(PackedVector2Array([inset.position, inset.position + Vector2(inset.size.x, 0),
		inset.end, inset.position + Vector2(0, inset.size.y)]), r * 0.8), WINE)
	# A gold rule inside the edge.
	var rule := rect.grow(-rect.size.x * 0.09)
	c.draw_rect(rule, Color(GOLD, 0.55), false, maxf(1.0, rect.size.x * 0.018))
	# A moon in a ring of eight points: a crescent, cut from a disc by a disc of
	# the ground colour.
	var mid := rect.get_center()
	var w := rect.size.x
	c.draw_circle(mid, w * 0.17, Color(GOLD, 0.9))
	c.draw_circle(mid + Vector2(w * 0.07, -w * 0.04), w * 0.15, WINE)
	for i in 8:
		var a := float(i) / 8.0 * TAU
		c.draw_circle(mid + Vector2(cos(a), sin(a)) * w * 0.30, maxf(0.8, w * 0.018), Color(GOLD, 0.7))
