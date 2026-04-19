class_name PlayerAnimator
extends CharacterAnimator


const _ANIMATION_NAME_MAPPING := {
	"rest": "idle_floor",
	"rest_on_ceiling": "idle_ceiling",
}


func _ready() -> void:
	super._ready()
	_apply_damage_shader_colors()


func play(animation_name: String) -> void:
	var mapped_name: String = _ANIMATION_NAME_MAPPING.get(
		animation_name, animation_name)
	super.play(mapped_name)


## Pushes `Settings.color_player_damage_*` into the shader params
## of the AnimatedSprite2D's ShaderMaterial so the flash / pulse
## tints stay centrally tunable.
func _apply_damage_shader_colors() -> void:
	if G.settings == null:
		return
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var material := sprite.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(
			"flash_color", G.settings.color_damage_flash)
	material.set_shader_parameter(
			"pulse_color", G.settings.color_damage_pulse)
