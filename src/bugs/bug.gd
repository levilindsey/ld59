class_name Bug
extends Area2D
## One spawned bug. Drifts gently, fades out over its lifetime, and
## is consumed when the player overlaps it. Consumption sets the
## player's echolocation frequency and queue_free()s the bug.
##
## Hosted under BugSpawner. Collision layer 0 (nothing queries for
## bugs); collision mask = player layer so Area2D overlap fires on
## player contact.


signal eaten(bug: Bug)


const _FADE_IN_SEC := 0.25
## Fraction of lifetime over which opacity fades out at end of life.
const _FADE_OUT_FRACTION := 0.35

## How often the drift direction is re-rolled.
const _DRIFT_REROLL_INTERVAL_SEC := 0.6
## Angular jitter applied to drift direction per reroll.
const _DRIFT_JITTER_RADIANS := PI * 0.6


## Frequency type (see Frequency.Type). Drives tint and the player's
## post-consumption frequency.
@export var frequency: int = Frequency.Type.GREEN:
	set(value):
		frequency = value
		_apply_frequency_tint()

@export_range(1.0, 60.0) var lifetime_sec := 12.0
@export_range(0.0, 64.0) var drift_speed_px_per_sec := 10.0

var _age_sec := 0.0
var _drift_velocity := Vector2.ZERO
var _drift_reroll_countdown := 0.0
var _consumed := false


func _ready() -> void:
	monitoring = true
	monitorable = false
	# Initial drift direction: a random unit vector.
	var angle := randf() * TAU
	_drift_velocity = (
			Vector2.from_angle(angle) * drift_speed_px_per_sec)
	_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC
	_apply_frequency_tint()
	modulate.a = 0.0
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _consumed:
		return

	_age_sec += delta
	if _age_sec >= lifetime_sec:
		queue_free()
		return

	global_position += _drift_velocity * delta

	_drift_reroll_countdown -= delta
	if _drift_reroll_countdown <= 0.0:
		_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC
		var jitter := randf_range(
				-_DRIFT_JITTER_RADIANS, _DRIFT_JITTER_RADIANS)
		_drift_velocity = _drift_velocity.rotated(jitter)

	_update_opacity()


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if body is Player:
		_consume(body as Player)


func _consume(player: Player) -> void:
	_consumed = true
	player.set_frequency(frequency)
	eaten.emit(self)
	queue_free()


func _update_opacity() -> void:
	var fade_out_start := lifetime_sec * (1.0 - _FADE_OUT_FRACTION)
	var alpha := 1.0
	if _age_sec < _FADE_IN_SEC:
		alpha = _age_sec / _FADE_IN_SEC
	elif _age_sec > fade_out_start:
		var remaining := lifetime_sec - _age_sec
		var fade_window := lifetime_sec - fade_out_start
		alpha = clampf(remaining / fade_window, 0.0, 1.0)
	modulate.a = alpha


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	# Keep alpha separate; _update_opacity owns it.
	color.a = modulate.a
	modulate = color
