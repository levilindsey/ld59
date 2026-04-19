class_name Spider
extends Enemy
## Floor-crawling enemy. Casts a short ray downward each frame to
## stick to the top of tile surfaces. When perceiving the player,
## walks horizontally toward them. When not perceiving, wanders
## idly along the floor (idle-pause, then slow-walk to a nearby
## offset, repeat).
##
## Full wall/ceiling crawling is a later enhancement; for now the
## spider only adheres to floors.


## Distance from the spider's origin down to the bottom of its
## sprite. Used by `_snap_to_floor` so the sprite's feet rest on the
## floor instead of its center. The spider's sprite is 40 px tall
## and offset (0, 1) from origin, putting its bottom edge 21 px
## below origin; 20 leaves a 1 px visual gap above the floor.
const _FOOT_OFFSET_PX := 20.0
## Ray length must exceed `_FOOT_OFFSET_PX` plus one frame's worth
## of fall so the downward probe still finds the floor from a
## resting pose.
const _GROUND_RAY_LENGTH_PX := 40.0
const _GRAVITY_PX_PER_SEC_SQ := 900.0
const _MAX_FALL_SPEED_PX_PER_SEC := 500.0

const _PURSUIT_SPEED_PX_PER_SEC := 75.0
const _WANDER_SPEED_PX_PER_SEC := 22.0
const _WANDER_RADIUS_PX := 64.0
const _WANDER_IDLE_MIN_SEC := 0.6
const _WANDER_IDLE_MAX_SEC := 1.8

const _SURFACE_MASK := 1
## Horizontal speed below which the animator plays idle instead of
## walk.
const _IDLE_SPEED_THRESHOLD_PX_PER_SEC := 2.0


@export var animated_sprite: AnimatedSprite2D


var _time_sec := 0.0
var _is_grounded := false


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	_snap_to_floor()

	var horizontal: float = 0.0
	if is_pursuing() and is_instance_valid(player):
		var dx: float = player.global_position.x - global_position.x
		if absf(dx) > 2.0:
			horizontal = signf(dx) * _PURSUIT_SPEED_PX_PER_SEC
	else:
		# Wander horizontally (spider stays on the floor so vertical
		# wander is irrelevant — just use the x component).
		var wander_v: Vector2 = _compute_wander_velocity(
				delta,
				_WANDER_SPEED_PX_PER_SEC,
				_WANDER_RADIUS_PX,
				_WANDER_IDLE_MIN_SEC,
				_WANDER_IDLE_MAX_SEC)
		horizontal = wander_v.x

	var vertical: float = _velocity.y
	if _is_grounded:
		vertical = 0.0
	else:
		vertical = minf(
				vertical + _GRAVITY_PX_PER_SEC_SQ * delta,
				_MAX_FALL_SPEED_PX_PER_SEC)

	_velocity = Vector2(horizontal, vertical)
	_update_animation(horizontal)


func _update_animation(horizontal: float) -> void:
	if animated_sprite == null:
		return
	if absf(horizontal) < _IDLE_SPEED_THRESHOLD_PX_PER_SEC:
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
	else:
		if animated_sprite.animation != &"walk":
			animated_sprite.play(&"walk")
		animated_sprite.flip_h = horizontal < 0.0


func _on_pursuit_started() -> void:
	var voice := get_node_or_null(^"%VoicePlayer") as AudioStreamPlayer2D
	if voice != null:
		voice.play()


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
	# Align the sprite's feet (offset by `_FOOT_OFFSET_PX` from the
	# node origin) with the floor surface. The ray starts at the
	# origin and is long enough to still hit the floor next frame
	# from this rest pose.
	global_position.y = hit["position"].y - _FOOT_OFFSET_PX
