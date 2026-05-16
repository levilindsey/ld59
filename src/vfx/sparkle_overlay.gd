class_name SparkleOverlay
extends Control
## Transient sparkle burst drawn over a Control's rect. Used on HUD
## coin slots and (in the future) other collectible contexts. Draws
## twinkling sparkles with `_draw()` so we avoid the Control ->
## ColorRect -> ShaderMaterial stack, which was silently producing no
## output inside `PanelContainer` slots.
##
## The overlay runs a short initial burst (~`duration_sec`) at full
## sparkle density, then continues forever at ~1/5 the density until
## the parent slot is freed (e.g., on level reset).


const _DEFAULT_DURATION_SEC := 0.9
const _DEFAULT_DENSITY := 4.0

## Fraction of sparkles that draw in a random rainbow color instead
## of the gold base color.
const _RAINBOW_CHANCE := 0.5

## Count multiplier applied during the initial burst phase.
const _BURST_COUNT_MULTIPLIER := 0.5

## Multiple of `lifetime` used for the average silent gap between
## successive appearances of a single sparkle during the persistent
## phase. A gap of ~8.5x lifetime gives a ~1:9.5 alive:cycle duty
## ratio. Combined with the reduced burst count, the visible
## persistent sparkle count is ~1/4 of the previous tuning.
const _PERSISTENT_GAP_AVG_MULT := 8.5

## Half-length (px) of each sparkle's horizontal and vertical arm.
## Total arm span is `2 * size`, so a size of 6 yields a 12 px plus
## sign.
const _SPARKLE_SIZE_MIN := 4.0
const _SPARKLE_SIZE_MAX := 8.0


var density: float = _DEFAULT_DENSITY
var duration_sec: float = _DEFAULT_DURATION_SEC


var _base_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _rainbow_palette: Array[Color] = []
var _sparkles: Array = []
var _is_burst_active: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_read_palette_from_settings()
	_generate_sparkles()
	set_process(true)
	# After the burst window elapses, flip to persistent mode. New
	# sparkles spawned from then on carry a long silent gap so only
	# ~1/5 of them are visible at any instant.
	await get_tree().create_timer(duration_sec, true).timeout
	_is_burst_active = false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var rect_size: Vector2 = size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	for i in _sparkles.size():
		var s: Dictionary = _sparkles[i]
		var age: float = now_sec - s.spawn_time
		if age < 0.0:
			continue
		if age >= s.lifetime:
			s = _new_sparkle(now_sec)
			_sparkles[i] = s
			continue
		var t: float = age / s.lifetime
		# Scale 0 -> 1 -> 0 across the lifetime. Ease-out on the way
		# up (snaps out quickly, decelerates), ease-in on the way down
		# (slow start, snaps to nothing). Cubic on both sides.
		var scale_factor: float
		if t < 0.5:
			var u: float = t * 2.0
			scale_factor = 1.0 - pow(1.0 - u, 3.0)
		else:
			var u: float = (t - 0.5) * 2.0
			scale_factor = pow(1.0 - u, 3.0)
		if scale_factor <= 0.01:
			continue
		var pos: Vector2 = s.uv * rect_size
		var color: Color = s.color
		var arm: float = s.size * scale_factor
		draw_line(
				pos + Vector2(-arm, 0.0),
				pos + Vector2(arm, 0.0),
				color,
				1.0,
				false)
		draw_line(
				pos + Vector2(0.0, -arm),
				pos + Vector2(0.0, arm),
				color,
				1.0,
				false)


func _read_palette_from_settings() -> void:
	if not is_instance_valid(G.settings):
		return
	_rainbow_palette = [
		G.settings.color_coin_sprinkle_red,
		G.settings.color_coin_sprinkle_orange,
		G.settings.color_coin_sprinkle_yellow,
		G.settings.color_coin_sprinkle_green,
		G.settings.color_coin_sprinkle_blue,
		G.settings.color_coin_sprinkle_violet,
	]


func _new_sparkle(now_sec: float) -> Dictionary:
	var color: Color = _base_color
	if _rainbow_palette.size() > 0 and randf() < _RAINBOW_CHANCE:
		color = _rainbow_palette[
				randi() % _rainbow_palette.size()]
	var lifetime: float = randf_range(0.35, 0.7)
	var gap: float = 0.0
	if not _is_burst_active:
		gap = lifetime * randf_range(
				_PERSISTENT_GAP_AVG_MULT * 0.5,
				_PERSISTENT_GAP_AVG_MULT * 1.5)
	return {
		uv = Vector2(randf(), randf()),
		color = color,
		spawn_time = now_sec + gap,
		lifetime = lifetime,
		size = randf_range(_SPARKLE_SIZE_MIN, _SPARKLE_SIZE_MAX),
	}


func _generate_sparkles() -> void:
	var count: int = int(round(
			density * density * _BURST_COUNT_MULTIPLIER))
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	for i in range(count):
		var s := _new_sparkle(now_sec)
		# Stagger initial ages so the opening burst isn't all in
		# lockstep — some sparkles start mid-cycle.
		s.spawn_time = now_sec - randf() * float(s.lifetime)
		_sparkles.append(s)
