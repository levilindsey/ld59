class_name PlayerActionSource
extends CharacterActionSource


const ACTIONS_TO_INPUT_KEYS := {
  "jump": "j",
  "move_up": "mu",
  "move_down": "md",
  "move_left": "ml",
  "move_right": "mr",
  "attach": "g",
  "face_left": "fl",
  "face_right": "fr",
}


func _init(p_character, p_is_additive: bool) -> void:
	super ("PLAYER", p_character, p_is_additive)


# Calculates actions for the current frame.
func update(
		actions: CharacterActionState,
		previous_actions: CharacterActionState,
		time_scaled: float) -> void:
	if !character.is_player_control_active:
		return
	for action in ACTIONS_TO_INPUT_KEYS:
		var input_key: String = ACTIONS_TO_INPUT_KEYS[action]
		var is_pressed: bool = Input.is_action_pressed(action)
		if !Input.is_key_pressed(KEY_CTRL):
			CharacterActionSource.update_for_explicit_key_event(
					actions,
					previous_actions,
					input_key,
					is_pressed,
					time_scaled,
					is_additive)


static func get_is_some_player_action_pressed() -> bool:
	for action in ACTIONS_TO_INPUT_KEYS:
		if Input.is_action_pressed(action):
			return true
	return false


static func validate_project_settings_input_actions() -> void:
	for action in ACTIONS_TO_INPUT_KEYS:
		if !InputMap.has_action(action):
			push_error(
				"PlayerActionSource: Missing input action '" +
				action +
				"' in project settings.")
