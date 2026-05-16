class_name WaterSplash
extends Node2D
## One-shot splash effect: spawns a fan of upward droplets that arc
## under gravity and fade out. Self-frees once every droplet has
## expired. CPU-simulated and drawn via `_draw()` to match the
## existing `CoinSparkles` / `RainbowBurst` style — no
## CPUParticles2D / GPUParticles2D node, no shader.


const _DROPLET_COUNT := 18
## Total time before the splash node self-frees. Droplet lifetimes
## are randomized below this so the last one finishes before free.
const _MAX_LIFETIME_SEC := 0.55
const _DROPLET_LIFETIME_MIN_SEC := 0.30
const _DROPLET_LIFETIME_MAX_SEC := 0.50

## Initial speed range (px/sec). Y is upward (negative) at spawn,
## with a horizontal spread biased outward from the splash center.
const _INITIAL_SPEED_MIN := 65.0
const _INITIAL_SPEED_MAX := 143.0
## Horizontal half-fan in radians. 0 = straight up only;
## PI/2 = full half-circle. PI/4 = 45° each side, so the most
## horizontal droplets still launch at 45° above the waterline
## (more upward bias than the wider PI/3 fan).
const _FAN_HALF_RADIANS := PI / 4.0
## Extra horizontal jitter (px/sec) added on top of the fan vector
## so droplets don't all sit on rays from the origin.
const _HORIZ_JITTER_PX_PER_SEC := 18.0

## Gravity pulling droplets back down.
const _GRAVITY_PX_PER_SEC2 := 380.0

## Droplet body length (px) — drawn as a short vertical tick.
const _DROPLET_LENGTH_PX := 2.0
const _DROPLET_WIDTH_PX := 1.0

## Color used when `G.settings` is unavailable. Light cyan-white,
## reads as splash water against the dark echo background.
const _FALLBACK_COLOR := Color(0.78, 0.92, 1.0, 1.0)


var _droplets: Array = []
var _start_time_sec: float = 0.0


func _ready() -> void:
	_start_time_sec = float(Time.get_ticks_msec()) / 1000.0
	var color: Color = _FALLBACK_COLOR
	if (is_instance_valid(G.settings)
			and "color_frequency_liquid" in G.settings):
		var liquid: Color = G.settings.color_frequency_liquid
		# Push hard toward white so the splash reads as bright spray
		# against the dark echo background. The LIQUID palette is
		# mid-blue; lerping 85% toward white keeps the cool tint but
		# brightens it close to a highlight.
		color = Color(
				lerpf(liquid.r, 1.0, 0.85),
				lerpf(liquid.g, 1.0, 0.85),
				lerpf(liquid.b, 1.0, 0.85),
				1.0)
	for i in _DROPLET_COUNT:
		var t: float = float(i) / float(maxi(_DROPLET_COUNT - 1, 1))
		var fan_angle: float = lerpf(
				-_FAN_HALF_RADIANS, _FAN_HALF_RADIANS, t)
		# Up vector rotated by fan_angle, then jittered horizontally.
		var dir: Vector2 = Vector2.UP.rotated(fan_angle)
		var speed: float = randf_range(
				_INITIAL_SPEED_MIN, _INITIAL_SPEED_MAX)
		var jitter: float = randf_range(
				-_HORIZ_JITTER_PX_PER_SEC, _HORIZ_JITTER_PX_PER_SEC)
		var velocity := dir * speed + Vector2(jitter, 0.0)
		_droplets.append({
			pos = Vector2.ZERO,
			velocity = velocity,
			lifetime = randf_range(
					_DROPLET_LIFETIME_MIN_SEC,
					_DROPLET_LIFETIME_MAX_SEC),
			color = color,
		})
	set_process(true)


func _process(delta: float) -> void:
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	if now_sec - _start_time_sec > _MAX_LIFETIME_SEC:
		queue_free()
		return
	for d in _droplets:
		d.velocity.y += _GRAVITY_PX_PER_SEC2 * delta
		d.pos += d.velocity * delta
	queue_redraw()


func _draw() -> void:
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var elapsed: float = now_sec - _start_time_sec
	for d in _droplets:
		if elapsed >= d.lifetime:
			continue
		var t: float = elapsed / d.lifetime
		# Linear alpha fade — simple is fine for a 0.5 sec effect.
		var alpha: float = 1.0 - t
		var col: Color = d.color
		col.a = alpha
		# Short vertical tick — direction-agnostic and reads as a
		# water droplet at small sizes.
		var top: Vector2 = d.pos + Vector2(0.0, -_DROPLET_LENGTH_PX * 0.5)
		var bottom: Vector2 = d.pos + Vector2(0.0, _DROPLET_LENGTH_PX * 0.5)
		draw_line(top, bottom, col, _DROPLET_WIDTH_PX, false)
