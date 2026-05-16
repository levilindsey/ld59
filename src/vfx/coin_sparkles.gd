class_name CoinSparkles
extends Node2D
## World-space sparkle field rendered around in-game coins. Two modes:
##
## - `Mode.PERSISTENT`: attached to a coin; low-rate shimmer that
##   renders only while the coin is inside the player's near-field
##   visibility radius.
## - `Mode.BURST`: spawned at pickup; a brief dense burst that
##   queue_frees when done.
##
## Drawing mirrors `SparkleOverlay` (plus-sign glyphs, same gold +
## rainbow palette from `G.settings`), but in local world-px
## coordinates rather than a Control's UV space.


enum Mode {
	PERSISTENT,
	BURST,
}


const _RAINBOW_CHANCE := 0.5

## Multiple of `lifetime` used for the average silent gap between
## successive appearances of a single sparkle during `PERSISTENT`
## mode. ~4x lifetime gives a 1:5 duty ratio.
const _PERSISTENT_GAP_AVG_MULT := 4.0

const _LIFETIME_MIN_SEC := 0.35
const _LIFETIME_MAX_SEC := 0.7

## Half-length (px) of each sparkle's horizontal/vertical arm.
const _SPARKLE_SIZE_MIN := 1.5
const _SPARKLE_SIZE_MAX := 3.0

const _PERSISTENT_COUNT := 2
const _BURST_COUNT := 3
const _BURST_DURATION_SEC := 0.9

## Fallback if `G.echo.near_radius_px` can't be read.
const _DEFAULT_NEAR_RADIUS_PX := 72.0


var mode: int = Mode.PERSISTENT
## Radius of the sparkle spawn disk around this node's local origin.
var radius_px: float = 15.0


var _base_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _rainbow_palette: Array[Color] = []
var _sparkles: Array = []


func _ready() -> void:
	_read_palette_from_settings()
	match mode:
		Mode.PERSISTENT:
			_generate_sparkles(_PERSISTENT_COUNT)
			set_process(true)
		Mode.BURST:
			_generate_sparkles(_BURST_COUNT)
			set_process(true)
			await get_tree().create_timer(
					_BURST_DURATION_SEC, true).timeout
			queue_free()


func _process(_delta: float) -> void:
	if mode == Mode.PERSISTENT:
		visible = _is_within_near_field()
	if visible:
		queue_redraw()


func _is_within_near_field() -> bool:
	if not is_instance_valid(G.level):
		return false
	if not is_instance_valid(G.level.player):
		return false
	var radius: float = _DEFAULT_NEAR_RADIUS_PX
	if is_instance_valid(G.echo) and "near_radius_px" in G.echo:
		radius = G.echo.near_radius_px
	var player_pos: Vector2 = G.level.player.global_position
	return global_position.distance_squared_to(player_pos) \
			<= radius * radius


func _draw() -> void:
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
		var pos: Vector2 = s.pos
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
	var lifetime: float = randf_range(
			_LIFETIME_MIN_SEC, _LIFETIME_MAX_SEC)
	var gap: float = 0.0
	if mode == Mode.PERSISTENT:
		gap = lifetime * randf_range(
				_PERSISTENT_GAP_AVG_MULT * 0.5,
				_PERSISTENT_GAP_AVG_MULT * 1.5)
	# Uniform disk sampling via sqrt(randf()) for radial density.
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * radius_px
	return {
		pos = Vector2(cos(angle), sin(angle)) * dist,
		color = color,
		spawn_time = now_sec + gap,
		lifetime = lifetime,
		size = randf_range(_SPARKLE_SIZE_MIN, _SPARKLE_SIZE_MAX),
	}


func _generate_sparkles(count: int) -> void:
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	for i in range(count):
		var s := _new_sparkle(now_sec)
		# Stagger initial ages so sparkles aren't in lockstep.
		s.spawn_time = now_sec - randf() * float(s.lifetime)
		_sparkles.append(s)
