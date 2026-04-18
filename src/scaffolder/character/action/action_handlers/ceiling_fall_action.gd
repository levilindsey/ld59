class_name CeilingFallAction
extends CharacterActionHandler


const NAME := "CeilingFallAction"
const TYPE := SurfaceType.CEILING
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 330


func _init() -> void:
	super(
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	if !character.processed_action(CeilingJumpDownAction.NAME) and \
			character.surface_state.is_triggering_ceiling_release:
		# Cancel any velocity toward the ceiling.
		character.velocity.y = \
				character.movement_settings.ceiling_fall_velocity_boost

		return true
	else:
		return false
