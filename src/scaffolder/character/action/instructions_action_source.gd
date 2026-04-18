class_name InstructionsActionSource
extends CharacterActionSource


# Array<InstructionsPlayback>
var _all_playback := []


func _init(
		p_character,
		p_is_additive: bool):
	super("NPC", p_character, p_is_additive)


# Calculates actions for the current frame.
func update(
		actions: CharacterActionState,
		previous_actions: CharacterActionState,
		time_scaled: float) -> void:
	var non_pressed_keys := []

	for playback in _all_playback:
		# Handle any new key presses up till the current time.
		playback.update(time_scaled, character)

		non_pressed_keys.clear()

		# Handle all previously started keys that are still pressed.
		for input_key in playback.active_key_presses:
			var is_pressed: bool = playback.active_key_presses[input_key]
			CharacterActionSource.update_for_explicit_key_event(
					actions,
					previous_actions,
					input_key,
					is_pressed,
					time_scaled,
					is_additive)
			if !is_pressed:
				non_pressed_keys.push_back(input_key)

		# Remove from the active set all keys that are no longer pressed.
		for input_key in non_pressed_keys:
			playback.active_key_presses.erase(input_key)

	# Handle instructions that finish.
	var i := 0
	while i < _all_playback.size():
		if _all_playback[i].is_finished:
			_all_playback.remove_at(i)
			i -= 1
		i += 1


func start_instructions(
		instructions: Array[Instruction],
		time_scaled: float) -> InstructionsPlayback:
	var playback := InstructionsPlayback.new(
			instructions,
			is_additive)
	playback.start(time_scaled)
	_all_playback.push_back(playback)
	return playback


func cancel_playback(
		playback: InstructionsPlayback,
		_time_scaled: float) -> bool:
	# Remove the playback.
	var index := _all_playback.find(playback)
	if index < 0:
		return false
	else:
		_all_playback.remove_at(index)
		return true


func cancel_all_playback() -> void:
	_all_playback.clear()
