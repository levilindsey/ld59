class_name FlyingCritter
extends Enemy
## Small, swarm-ish flying enemy. Idle: random low-speed drift.
## Pursuit: direct pursuit with a jittery wobble so a swarm feels
## chaotic rather than mechanical.


const _DRIFT_SPEED_PX_PER_SEC := 18.0
const _DRIFT_REROLL_INTERVAL_SEC := 0.7
const _DRIFT_JITTER_RADIANS := PI * 0.75

const _PURSUIT_SPEED_PX_PER_SEC := 90.0
const _WOBBLE_AMPLITUDE_PX_PER_SEC := 40.0
const _WOBBLE_FREQUENCY_HZ := 3.0

const _STEER_PER_SEC := 5.0


var _time_sec := 0.0
var _drift_reroll_countdown := 0.0


func _ready() -> void:
	super._ready()
	var angle := randf() * TAU
	_velocity = (
			Vector2.from_angle(angle) * _DRIFT_SPEED_PX_PER_SEC)
	_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	if is_pursuing() and is_instance_valid(player):
		_velocity = _pursue(delta, player)
	else:
		_drift_reroll_countdown -= delta
		if _drift_reroll_countdown <= 0.0:
			_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC
			var jitter := randf_range(
					-_DRIFT_JITTER_RADIANS, _DRIFT_JITTER_RADIANS)
			_velocity = _velocity.rotated(jitter)


func _pursue(delta: float, player: Player) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	var direct := to_player.normalized() * _PURSUIT_SPEED_PX_PER_SEC
	var tangent := Vector2(-direct.y, direct.x).normalized()
	var wobble := tangent * sin(
			_time_sec * _WOBBLE_FREQUENCY_HZ * TAU
	) * _WOBBLE_AMPLITUDE_PX_PER_SEC

	return _velocity.lerp(
			direct + wobble,
			clampf(_STEER_PER_SEC * delta, 0.0, 1.0))
