class_name PlayerAnimator
extends CharacterAnimator


const _ANIMATION_NAME_MAPPING := {
	"rest": "idle_floor",
	"rest_on_ceiling": "idle_ceiling",
}


func play(animation_name: String) -> void:
	var mapped_name: String = _ANIMATION_NAME_MAPPING.get(
		animation_name, animation_name)
	super.play(mapped_name)
