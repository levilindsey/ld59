class_name Coyote
extends Enemy
## Ground-chasing enemy with a pounce attack. Wanders on the floor
## when not perceiving the player. When it perceives, approaches
## with normal walk + wall-jumps. When close enough, launches a
## ballistic pounce THROUGH and PAST the player: big horizontal
## impulse toward the player plus an upward impulse to carry over
## obstacles. After landing, idles briefly before resuming approach.
##
## Gravity + downward raycast for floor snapping mirror the Spider
## pattern.


enum CoyoteState { WANDER, APPROACH, POUNCE, RECOVER }


const _GROUND_RAY_LENGTH_PX := 18.0
const _WALL_RAY_LENGTH_PX := 14.0
const _GRAVITY_PX_PER_SEC_SQ := 1200.0
const _MAX_FALL_SPEED_PX_PER_SEC := 800.0

const _APPROACH_SPEED_PX_PER_SEC := 140.0
const _WANDER_SPEED_PX_PER_SEC := 28.0
const _WANDER_RADIUS_PX := 96.0
const _WANDER_IDLE_MIN_SEC := 0.6
const _WANDER_IDLE_MAX_SEC := 1.8

## Wall-jump (while approaching) and vertical-jump tuning.
const _JUMP_IMPULSE_PX_PER_SEC := 420.0
const _JUMP_COOLDOWN_SEC := 0.5
const _VERTICAL_JUMP_THRESHOLD_PX := 24.0
const _VERTICAL_JUMP_HORIZONTAL_RANGE_PX := 80.0

## Pounce tuning. `horizontal` + `vertical` impulses are applied
## together the instant the coyote enters POUNCE. During the pounce
## we don't override horizontal momentum — gravity + floor are the
## only forces — so the coyote carries past the player and lands
## past them.
const _POUNCE_TRIGGER_DIST_PX := 72.0
const _POUNCE_HORIZONTAL_SPEED_PX_PER_SEC := 320.0
const _POUNCE_VERTICAL_IMPULSE_PX_PER_SEC := 360.0
const _POUNCE_COOLDOWN_SEC := 0.35

## Post-pounce pause before the coyote starts approaching again.
const _RECOVER_DURATION_SEC := 0.8

const _SURFACE_MASK := 1
## Horizontal speed below which the animator plays idle instead of
## walk.
const _IDLE_SPEED_THRESHOLD_PX_PER_SEC := 2.0


@export var animated_sprite: AnimatedSprite2D


var _time_sec := 0.0
var _is_grounded := false
var _jump_cooldown_sec := 0.0
var _pounce_cooldown_sec := 0.0
var _state: CoyoteState = CoyoteState.WANDER
var _state_timer_sec := 0.0
var _facing_sign := 1


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta
	_jump_cooldown_sec = maxf(0.0, _jump_cooldown_sec - delta)
	_pounce_cooldown_sec = maxf(0.0, _pounce_cooldown_sec - delta)

	_snap_to_floor()

	# State transitions driven by perception first.
	if _state == CoyoteState.WANDER and is_pursuing():
		_state = CoyoteState.APPROACH
		_wander_has_target = false
		_wander_idle_timer_sec = 0.0
	if (not is_pursuing()
			and _state != CoyoteState.POUNCE
			and _state != CoyoteState.WANDER):
		_state = CoyoteState.WANDER

	var horizontal: float = 0.0
	match _state:
		CoyoteState.WANDER:
			var wander_v: Vector2 = _compute_wander_velocity(
					delta,
					_WANDER_SPEED_PX_PER_SEC,
					_WANDER_RADIUS_PX,
					_WANDER_IDLE_MIN_SEC,
					_WANDER_IDLE_MAX_SEC)
			horizontal = wander_v.x
		CoyoteState.APPROACH:
			horizontal = _approach_horizontal(player)
			if _should_wall_jump():
				_trigger_jump()
			elif _should_vertical_jump(player):
				_trigger_jump()
			elif _should_pounce(player):
				_trigger_pounce(player)
		CoyoteState.POUNCE:
			# Keep horizontal velocity from the launch impulse; no
			# override while airborne. Land detection below.
			horizontal = _velocity.x
			if _is_grounded and _velocity.y >= 0.0:
				_state = CoyoteState.RECOVER
				_state_timer_sec = _RECOVER_DURATION_SEC
				horizontal = 0.0
		CoyoteState.RECOVER:
			_state_timer_sec -= delta
			horizontal = 0.0
			if _state_timer_sec <= 0.0:
				_state = (CoyoteState.APPROACH
						if is_pursuing() else CoyoteState.WANDER)

	if horizontal != 0.0:
		_facing_sign = 1 if horizontal > 0.0 else -1

	var vertical: float = _velocity.y
	if _is_grounded and vertical >= 0.0:
		vertical = 0.0
	else:
		vertical = minf(
				vertical + _GRAVITY_PX_PER_SEC_SQ * delta,
				_MAX_FALL_SPEED_PX_PER_SEC)

	_velocity = Vector2(horizontal, vertical)
	_update_animation(horizontal)


func _approach_horizontal(player: Player) -> float:
	if not is_instance_valid(player):
		return 0.0
	var dx: float = player.global_position.x - global_position.x
	if absf(dx) < 2.0:
		return 0.0
	return signf(dx) * _APPROACH_SPEED_PX_PER_SEC


func _should_wall_jump() -> bool:
	if not _is_grounded or _jump_cooldown_sec > 0.0:
		return false
	return _is_wall_in_front()


func _should_vertical_jump(player: Player) -> bool:
	if not _is_grounded or _jump_cooldown_sec > 0.0:
		return false
	if not is_instance_valid(player):
		return false
	var offset: Vector2 = player.global_position - global_position
	return (offset.y < -_VERTICAL_JUMP_THRESHOLD_PX
			and absf(offset.x) < _VERTICAL_JUMP_HORIZONTAL_RANGE_PX)


func _should_pounce(player: Player) -> bool:
	if not _is_grounded or _pounce_cooldown_sec > 0.0:
		return false
	if not is_instance_valid(player):
		return false
	return (global_position.distance_to(player.global_position)
			< _POUNCE_TRIGGER_DIST_PX)


func _trigger_jump() -> void:
	_velocity.y = -_JUMP_IMPULSE_PX_PER_SEC
	_is_grounded = false
	_jump_cooldown_sec = _JUMP_COOLDOWN_SEC


func _trigger_pounce(player: Player) -> void:
	var to_player: Vector2 = player.global_position - global_position
	var dir_x: float = signf(to_player.x) if absf(to_player.x) > 1.0 else 1.0
	_velocity = Vector2(
			dir_x * _POUNCE_HORIZONTAL_SPEED_PX_PER_SEC,
			-_POUNCE_VERTICAL_IMPULSE_PX_PER_SEC)
	_is_grounded = false
	_state = CoyoteState.POUNCE
	_pounce_cooldown_sec = _POUNCE_COOLDOWN_SEC
	_jump_cooldown_sec = _JUMP_COOLDOWN_SEC


func _update_animation(horizontal: float) -> void:
	if animated_sprite == null:
		return
	animated_sprite.flip_h = _facing_sign < 0
	if not _is_grounded:
		# Mid-air: rise while moving up, fall otherwise.
		var target: StringName = (&"jump_rise"
				if _velocity.y < 0.0 else &"jump_fall")
		if animated_sprite.animation != target:
			animated_sprite.play(target)
		return
	if absf(horizontal) < _IDLE_SPEED_THRESHOLD_PX_PER_SEC:
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	else:
		if animated_sprite.animation != &"walk":
			animated_sprite.play(&"walk")


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
	# Only snap when descending or resting; a mid-jump that glances a
	# ledge would otherwise yank the coyote back down.
	if _velocity.y < 0.0:
		_is_grounded = false
		return
	_is_grounded = true
	global_position.y = hit["position"].y - 1.0
