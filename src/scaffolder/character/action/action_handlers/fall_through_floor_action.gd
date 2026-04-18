class_name FallThroughFloorAction
extends CharacterActionHandler


const NAME := "FallThroughFloorAction"
const TYPE := SurfaceType.FLOOR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 220


func _init() -> void:
	super(
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	if character.surface_state.is_triggering_fall_through:
		# If we were standing on a floor and just triggered a fall-through,
		# then give a little downward velocity boost.
		character.velocity.y = \
				character.movement_settings.fall_through_floor_velocity_boost
		return true
	else:
		return false
