## The player's two hands, at the bottom of the reading. Scenes/Table.gd draws
## them and places what they wear; this only keeps them MOVING — it asks Feel
## for each hand's pose every frame and redraws when the pose has changed.
##
## The pose lives in Feel, not here. The reading rebuilds its hands on every
## change of state, and the moment a card is laid is exactly such a change: the
## "lay" gesture starts in the frame the old hands are freed. New hands ask Feel
## where the gesture has got to and carry on from there.
##
## Built by Table.hands(), never on its own.
extends Control

const Table := preload("res://scenes/Table.gd")

var marks: Array = []
var span: Callable = Callable()
var reach := 1.0

## The pose last drawn, {left, right}. Compared each frame so a hand at rest
## with motion off costs no redraws at all.
var poses: Dictionary = {}


func _ready() -> void:
	poses = _now()


func _process(_delta: float) -> void:
	var now := _now()
	if now != poses:
		poses = now
		queue_redraw()


func _draw() -> void:
	Table._draw_hands(self, marks, span, reach, poses)


func _now() -> Dictionary:
	return {"left": Feel.hand_pose("left"), "right": Feel.hand_pose("right")}
