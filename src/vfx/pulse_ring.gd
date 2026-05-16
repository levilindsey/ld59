class_name PulseRing
extends Node2D
## Expanding circular ring used to punctuate coin pickups. Grows from
## `start_radius_px` to `end_radius_px` while fading out over
## `duration_sec`, then self-frees.
##
## Configure-then-add: callers set the growth bounds, duration, color,
## and line width before the ring enters the tree. The pulse is drawn
## at the node's local origin, so set `position` to where the ring
## should emanate from.


const _DEFAULT_START_RADIUS_PX := 4.0
const _DEFAULT_END_RADIUS_PX := 93.0
const _DEFAULT_DURATION_SEC := 0.55
const _DEFAULT_INITIAL_ALPHA := 0.25


var start_radius_px: float = _DEFAULT_START_RADIUS_PX
var end_radius_px: float = _DEFAULT_END_RADIUS_PX
var duration_sec: float = _DEFAULT_DURATION_SEC
var color: Color = Color(1.0, 1.0, 1.0, _DEFAULT_INITIAL_ALPHA)


var _radius: float = 0.0
var _alpha_scale: float = 1.0


func _ready() -> void:
	_radius = start_radius_px
	_alpha_scale = 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(
			self,
			"_radius",
			end_radius_px,
			duration_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
			self,
			"_alpha_scale",
			0.0,
			duration_sec,
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := color
	c.a *= _alpha_scale
	draw_circle(Vector2.ZERO, _radius, c)
