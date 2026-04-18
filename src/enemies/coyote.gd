class_name Coyote
extends Enemy
## Ground-chasing enemy with jump. Runs toward the player's horizontal
## position. Jumps on two triggers: (1) a forward wall raycast hits,
## (2) the player is close horizontally and above by more than
## `_VERTICAL_JUMP_THRESHOLD_PX`. Gravity + downward raycast for
## floor snapping mirror the Spider pattern.


const _GROUND_RAY_LENGTH_PX := 18.0
const _WALL_RAY_LENGTH_PX := 14.0
const _GRAVITY_PX_PER_SEC_SQ := 1200.0
const _MAX_FALL_SPEED_PX_PER_SEC := 800.0

const _IDLE_SPEED_PX_PER_SEC := 20.0
const _IDLE_DIRECTION_FLIP_INTERVAL_SEC := 2.0

const _PURSUIT_SPEED_PX_PER_SEC := 140.0

const _JUMP_IMPULSE_PX_PER_SEC := 420.0
const _JUMP_COOLDOWN_SEC := 0.5

## Jump at the player vertically when the player is above by at least
## this much and horizontally within `_VERTICAL_JUMP_HORIZONTAL_RANGE_PX`.
const _VERTICAL_JUMP_THRESHOLD_PX := 24.0
const _VERTICAL_JUMP_HORIZONTAL_RANGE_PX := 80.0

const _SURFACE_MASK := 1


var _time_sec := 0.0
var _is_grounded := false
var _jump_cooldown_sec := 0.0
var _facing_sign := 1
var _idle_flip_countdown_sec := _IDLE_DIRECTION_FLIP_INTERVAL_SEC


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta
	_jump_cooldown_sec = maxf(0.0, _jump_cooldown_sec - delta)

	_snap_to_floor()

	var horizontal := _decide_horizontal(delta, player)
	if horizontal != 0.0:
		_facing_sign = 1 if horizontal > 0.0 else -1

	if _should_jump(player):
		_trigger_jump()

	var vertical: float = _velocity.y
	if _is_grounded and vertical >= 0.0:
		vertical = 0.0
	else:
		vertical = minf(
				vertical + _GRAVITY_PX_PER_SEC_SQ * delta,
				_MAX_FALL_SPEED_PX_PER_SEC)

	_velocity = Vector2(horizontal, vertical)


func _decide_horizontal(delta: float, player: Player) -> float:
	if is_pursuing() and is_instance_valid(player):
		var dx := player.global_position.x - global_position.x
		if absf(dx) < 2.0:
			return 0.0
		return signf(dx) * _PURSUIT_SPEED_PX_PER_SEC

	_idle_flip_countdown_sec -= delta
	if _idle_flip_countdown_sec <= 0.0:
		_idle_flip_countdown_sec = _IDLE_DIRECTION_FLIP_INTERVAL_SEC
		_facing_sign = -_facing_sign
	return _facing_sign * _IDLE_SPEED_PX_PER_SEC


func _should_jump(player: Player) -> bool:
	if not _is_grounded:
		return false
	if _jump_cooldown_sec > 0.0:
		return false
	if _is_wall_in_front():
		return true
	if is_pursuing() and is_instance_valid(player):
		var offset := player.global_position - global_position
		if (
				offset.y < -_VERTICAL_JUMP_THRESHOLD_PX
				and absf(offset.x) < _VERTICAL_JUMP_HORIZONTAL_RANGE_PX):
			return true
	return false


func _trigger_jump() -> void:
	_velocity.y = -_JUMP_IMPULSE_PX_PER_SEC
	_is_grounded = false
	_jump_cooldown_sec = _JUMP_COOLDOWN_SEC


func _is_wall_in_front() -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = global_position + Vector2(
			_facing_sign * _WALL_RAY_LENGTH_PX, 0.0)
	query.collision_mask = _SURFACE_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space.intersect_ray(query).is_empty()


func _snap_to_floor() -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = global_position + Vector2(0.0, _GROUND_RAY_LENGTH_PX)
	query.collision_mask = _SURFACE_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_is_grounded = false
		return
	# Only snap when descending or resting; otherwise a mid-jump that
	# glances a ledge would yank the coyote back down.
	if _velocity.y < 0.0:
		_is_grounded = false
		return
	_is_grounded = true
	global_position.y = hit["position"].y - 1.0
