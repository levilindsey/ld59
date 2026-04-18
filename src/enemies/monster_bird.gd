class_name MonsterBird
extends Enemy
## Flying enemy. Idle: gentle vertical hover. Pursuit: dashes toward
## the player along an arcing path (direct-vector plus a tangent
## lateral oscillation, so it swoops rather than beelines).


const _HOVER_AMPLITUDE_PX_PER_SEC := 20.0
const _HOVER_FREQUENCY_HZ := 0.8

const _DASH_SPEED_PX_PER_SEC := 140.0
## Fraction of dash speed added as a tangential oscillation.
const _ARC_LATERAL_AMPLITUDE := 0.55
const _ARC_FREQUENCY_HZ := 1.2

const _STEER_PER_SEC := 4.0

## Stop accelerating toward the player when within this distance.
const _CLOSE_ENOUGH_PX := 6.0


var _time_sec := 0.0


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	if is_pursuing() and is_instance_valid(player):
		_velocity = _steer_toward_player(delta, player)
	else:
		var bob_y := sin(
				_time_sec * _HOVER_FREQUENCY_HZ * TAU
		) * _HOVER_AMPLITUDE_PX_PER_SEC
		_velocity = _velocity.lerp(
				Vector2(0.0, bob_y),
				clampf(_STEER_PER_SEC * delta, 0.0, 1.0))


func _steer_toward_player(delta: float, player: Player) -> Vector2:
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() < _CLOSE_ENOUGH_PX:
		return Vector2.ZERO

	var direct := to_player.normalized() * _DASH_SPEED_PX_PER_SEC
	var tangent := Vector2(-direct.y, direct.x).normalized()
	var lateral_gain := sin(
			_time_sec * _ARC_FREQUENCY_HZ * TAU
	) * _ARC_LATERAL_AMPLITUDE * _DASH_SPEED_PX_PER_SEC
	var target := direct + tangent * lateral_gain

	return _velocity.lerp(
			target,
			clampf(_STEER_PER_SEC * delta, 0.0, 1.0))
