class_name JuiceSelectionBox
extends Control
## Draws an animated border around the currently-selected juice
## slot. Brightness + thickness scale with the player's echo
## cooldown fraction: dim + thin just after firing, bright + fat
## when ready. A subtle sine breathe makes the ready state visibly
## alive.
##
## Container code writes `cooldown_fraction` (0.0 = just fired,
## 1.0 = ready) via `set_meta` each frame and calls `queue_redraw`.


const _MIN_BORDER_ALPHA := 0.35
const _MAX_BORDER_ALPHA := 1.0
const _MIN_BORDER_WIDTH := 1.0
const _MAX_BORDER_WIDTH := 2.5
const _BREATHE_HZ := 2.0
const _BREATHE_AMPLITUDE := 0.12


var _time_sec := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bypass the HBoxContainer parent's layout so the Row script can
	# freely position us over the currently-selected slot in global
	# coordinates. Without this the container would snap us back
	# into the box flow every frame.
	top_level = true
	# Draw on top of siblings without intercepting input.
	z_index = 10


func _process(delta: float) -> void:
	_time_sec += delta


func _draw() -> void:
	var frac := float(get_meta("cooldown_fraction", 1.0))
	frac = clampf(frac, 0.0, 1.0)
	var alpha := lerpf(_MIN_BORDER_ALPHA, _MAX_BORDER_ALPHA, frac)
	var width := lerpf(_MIN_BORDER_WIDTH, _MAX_BORDER_WIDTH, frac)
	# Breathe only while ready so it signals "ready to fire" without
	# adding visual noise mid-cooldown.
	if frac >= 1.0:
		alpha += sin(_time_sec * _BREATHE_HZ * TAU) * _BREATHE_AMPLITUDE
		alpha = clampf(alpha, 0.0, 1.0)
	var color := Color(1.0, 1.0, 1.0, alpha)
	var r := Rect2(Vector2.ZERO, size)
	# Four edges, each as a filled rect so the corners meet cleanly.
	draw_rect(Rect2(r.position,
			Vector2(r.size.x, width)), color)
	draw_rect(Rect2(
			Vector2(r.position.x, r.size.y - width),
			Vector2(r.size.x, width)), color)
	draw_rect(Rect2(r.position,
			Vector2(width, r.size.y)), color)
	draw_rect(Rect2(
			Vector2(r.size.x - width, r.position.y),
			Vector2(width, r.size.y)), color)
