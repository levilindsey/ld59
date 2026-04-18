class_name Spider
extends Enemy
## Floor-crawling enemy. Casts a short ray downward each frame to
## stick to the top of tile surfaces. Idle: minor sway in place.
## Pursuit: walks horizontally toward the player.
##
## Full wall/ceiling crawling is a later enhancement; for now the
## spider only adheres to floors.


const _GROUND_RAY_LENGTH_PX := 18.0
const _GRAVITY_PX_PER_SEC_SQ := 900.0
const _MAX_FALL_SPEED_PX_PER_SEC := 500.0

const _IDLE_SWAY_AMPLITUDE_PX_PER_SEC := 6.0
const _IDLE_SWAY_FREQUENCY_HZ := 0.5

const _PURSUIT_SPEED_PX_PER_SEC := 75.0

const _SURFACE_MASK := 1


var _time_sec := 0.0
var _is_grounded := false


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	_snap_to_floor()

	var horizontal := 0.0
	if is_pursuing() and is_instance_valid(player):
		var dx := player.global_position.x - global_position.x
		if absf(dx) > 2.0:
			horizontal = signf(dx) * _PURSUIT_SPEED_PX_PER_SEC
	else:
		horizontal = sin(
				_time_sec * _IDLE_SWAY_FREQUENCY_HZ * TAU
		) * _IDLE_SWAY_AMPLITUDE_PX_PER_SEC

	var vertical: float = _velocity.y
	if _is_grounded:
		vertical = 0.0
	else:
		vertical = minf(
				vertical + _GRAVITY_PX_PER_SEC_SQ * delta,
				_MAX_FALL_SPEED_PX_PER_SEC)

	_velocity = Vector2(horizontal, vertical)


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
	_is_grounded = true
	# Rest just above the hit point so the ray keeps contact next
	# frame without clipping into the surface.
	global_position.y = hit["position"].y - 1.0
