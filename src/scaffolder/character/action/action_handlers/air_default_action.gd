class_name AirDefaultAction
extends CharacterActionHandler


const NAME := "AirDefaultAction"
const TYPE := SurfaceType.AIR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 410

const BOUNCE_OFF_CEILING_VELOCITY := 15.0


func _init() -> void:
	super(
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	# If the character falls off a wall or ledge, then that's considered the
	# first jump.
	character.jump_count = max(character.jump_count, 1)

	var is_first_jump: bool = character.jump_count == 1

	# If we just fell off the bottom of a wall, cancel any velocity toward that
	# wall.
	if character.surface_state.just_entered_air and \
			((character.surface_state.previous_attachment_side == \
					SurfaceSide.LEFT_WALL and \
					character.velocity.x < 0.0) or \
			(character.surface_state.previous_attachment_side == \
					SurfaceSide.RIGHT_WALL and \
					character.velocity.x > 0.0)):
		character.velocity.x = 0.0

	character.velocity = update_velocity_in_air(
			character.velocity,
			character.last_delta_scaled,
			character.actions.pressed_jump,
			is_first_jump,
			character.surface_state.horizontal_acceleration_sign,
			character.movement_settings)

	# Bouncing off ceiling.
	if character.surface_state.is_touching_ceiling and \
			!character.surface_state.is_attaching_to_ceiling:
		character.is_rising_from_jump = false
		character.velocity.y = BOUNCE_OFF_CEILING_VELOCITY

		var is_ceiling_sloped_against_movement: bool = \
				(character.surface_state.ceiling_contact \
						.normal.x < 0.0) != \
				(character.velocity.x < 0.0)
		if is_ceiling_sloped_against_movement:
			character.velocity.x = 0.0

	return true


static func update_velocity_in_air(
		velocity: Vector2,
		delta: float,
		is_pressing_jump: bool,
		is_first_jump: bool,
		horizontal_acceleration_sign: int,
		movement_settings: MovementSettings) -> Vector2:
	var is_rising_from_jump := velocity.y < 0 and is_pressing_jump

	# Make gravity stronger when falling. This creates a more satisfying jump.
	# Similarly, make gravity stronger for double jumps.
	var gravity := \
			movement_settings.gravity_fast_fall_acceleration if \
			!is_rising_from_jump else \
			(movement_settings.gravity_slow_rise_acceleration if \
			is_first_jump else \
			movement_settings.gravity_double_jump_slow_rise_acceleration)

	# Vertical movement.
	velocity.y += \
			delta * \
			gravity

	# Horizontal movement.
	velocity.x += \
			delta * \
			movement_settings.in_air_horizontal_acceleration * \
			horizontal_acceleration_sign

	return velocity
