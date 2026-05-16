class_name FloorDefaultAction
extends CharacterActionHandler


const NAME := "FloorDefaultAction"
const TYPE := SurfaceType.FLOOR
const USES_RUNTIME_PHYSICS := true
const PRIORITY := 210


func _init() -> void:
	super(
		NAME,
		TYPE,
		USES_RUNTIME_PHYSICS,
		PRIORITY)


func process(character) -> bool:
	character.jump_count = 0
	character.is_rising_from_jump = false

	character.velocity.y = 0.0

	# On the landing frame specifically, if the player isn't
	# actively pressing a direction, zero horizontal velocity too.
	# Godot's floor slide resolver nudges the body tangentially on
	# every landing and against a marching-squares collision mesh
	# that bias is consistently rightward — the character appears
	# to get shoved right on every floor contact. Restricting the
	# zero to `just_touched_floor && no input` keeps normal walking
	# (input sets `horizontal_acceleration_sign != 0`) untouched.
	if (character.surface_state.just_touched_floor
			and character.surface_state.horizontal_acceleration_sign == 0):
		character.velocity.x = 0.0

	return true
