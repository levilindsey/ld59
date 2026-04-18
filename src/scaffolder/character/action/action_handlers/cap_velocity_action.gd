class_name CapVelocityAction
extends CharacterActionHandler


const NAME := "CapVelocityAction"
const TYPE := SurfaceType.OTHER
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 10020


func _init() -> void:
	super(
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	var max_horizontal_speed: float = \
			character.current_surface_max_horizontal_speed if \
			character.surface_state.is_attaching_to_surface else \
			character.current_air_max_horizontal_speed

	character.velocity = cap_velocity(
			character.velocity,
			character.movement_settings,
			max_horizontal_speed)

	return true


static func cap_velocity(
		velocity: Vector2,
		movement_settings: MovementSettings,
		current_max_horizontal_speed: float) -> Vector2:
	# Cap horizontal speed at a max value.
	velocity.x = clamp(
			velocity.x,
			- current_max_horizontal_speed,
			current_max_horizontal_speed)

	# Kill horizontal speed below a min value.
	if velocity.x > -movement_settings.min_horizontal_speed and \
			velocity.x < movement_settings.min_horizontal_speed:
		velocity.x = 0

	# Cap vertical speed at a max value.
	velocity.y = clamp(
			velocity.y,
			- movement_settings.max_vertical_speed,
			movement_settings.max_vertical_speed)

	# Kill vertical speed below a min value.
	if velocity.y > -movement_settings.min_vertical_speed and \
			velocity.y < movement_settings.min_vertical_speed:
		velocity.y = 0

	return velocity
