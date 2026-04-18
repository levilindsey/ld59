class_name InstructionsPlayback
extends RefCounted


const EXTRA_DELAY_TO_ALLOW_COLLISION_WITH_SURFACE := 0.25

var instructions: Array[Instruction] = []

var is_additive: bool
var next_index: int
var _next_instruction: Instruction
var start_time_scaled: float
var previous_time_scaled: float
var current_time_scaled: float
var is_finished: bool
var is_on_last_instruction: bool
# Dictionary<String, boolean>
var active_key_presses: Dictionary
# Dictionary<String, boolean>
var _next_active_key_presses: Dictionary


func _init(
		p_instructions: Array[Instruction],
		p_is_additive: bool) -> void:
	self.instructions = p_instructions
	self.is_additive = p_is_additive


func start(scaled_time: float) -> void:
	start_time_scaled = scaled_time
	previous_time_scaled = scaled_time
	current_time_scaled = scaled_time
	next_index = 0
	_next_instruction = \
			instructions[next_index] if \
			instructions.size() > next_index else \
			null
	is_on_last_instruction = _next_instruction == null
	is_finished = is_on_last_instruction
	active_key_presses = {}
	_next_active_key_presses = {}


func update(
		scaled_time: float,
		character) -> void:
	previous_time_scaled = current_time_scaled
	current_time_scaled = scaled_time

	active_key_presses = _next_active_key_presses.duplicate()

	var was_pressing_move_sideways: bool = \
			_next_active_key_presses.has("ml") and \
			_next_active_key_presses["ml"] or \
			_next_active_key_presses.has("mr") and \
			_next_active_key_presses["mr"]

	while !is_finished and \
			_get_start_time_scaled_for_next_instruction() <= scaled_time:
		if !is_on_last_instruction:
			_ensure_facing_correct_direction_before_update(character)

		_increment()

	var is_pressing_move_sideways: bool = \
			_next_active_key_presses.has("ml") and \
			_next_active_key_presses["ml"] or \
			_next_active_key_presses.has("mr") and \
			_next_active_key_presses["mr"]
	var just_released_move_sideways := \
			was_pressing_move_sideways and \
			!is_pressing_move_sideways

	_ensure_facing_correct_direction_after_update(
			just_released_move_sideways,
			character)


func _increment() -> void:
	is_finished = is_on_last_instruction
	if is_finished:
		return

	# Update the set of active key presses.
	if _next_instruction.is_pressed:
		_next_active_key_presses[_next_instruction.input_key] = true
		active_key_presses[_next_instruction.input_key] = true
		_ensure_previous_face_input_is_released(_next_instruction.input_key)
	else:
		_next_active_key_presses[_next_instruction.input_key] = false
		active_key_presses[_next_instruction.input_key] = \
				true if \
				is_additive and \
				active_key_presses.has(_next_instruction.input_key) and \
				active_key_presses[_next_instruction.input_key] else \
				false

	next_index += 1
	_next_instruction = \
			instructions[next_index] if \
			instructions.size() > next_index else \
			null
	is_on_last_instruction = _next_instruction == null


func get_previous_elapsed_time_scaled() -> float:
	return previous_time_scaled - start_time_scaled


func get_elapsed_time_scaled() -> float:
	return G.time.get_scaled_play_time() - start_time_scaled


func _get_start_time_scaled_for_next_instruction() -> float:
	assert(!is_finished)

	var duration_until_next_instruction: float
	if is_on_last_instruction:
		duration_until_next_instruction = INF
	else:
		duration_until_next_instruction = _next_instruction.time

	return start_time_scaled + duration_until_next_instruction


func _ensure_facing_correct_direction_before_update(character) -> void:
	if character.movement_settings.always_tries_to_face_direction_of_motion and \
			next_index == 0 and \
			character.velocity.x != 0 and \
			(character.velocity.x < 0) != \
					(character.surface_state.horizontal_facing_sign < 0):
		# At the start of edge playback, turn the character to face the
		# initial direction they're moving in.
		_add_instruction_to_face_direction_of_movement(character)


func _ensure_facing_correct_direction_after_update(
		just_released_move_sideways: bool,
		character) -> void:
	var is_pressing_face_left: bool = \
			_next_active_key_presses.has("fl") and \
			_next_active_key_presses["fl"]
	var is_pressing_face_right: bool = \
			_next_active_key_presses.has("fr") and \
			_next_active_key_presses["fr"]

	if character.movement_settings.always_tries_to_face_direction_of_motion and \
			just_released_move_sideways and \
			character.velocity.x != 0 and \
			(character.velocity.x < 0 and !is_pressing_face_left or \
			character.velocity.x > 0 and !is_pressing_face_right):
		# Turn the character around, so they are facing the direction they're
		# moving in.
		_add_instruction_to_face_direction_of_movement(character)


func _add_instruction_to_face_direction_of_movement(character) -> void:
	var press_input_key := \
			"fl" if \
			character.velocity.x < 0 else \
			"fr"
	_next_active_key_presses[press_input_key] = true
	active_key_presses[press_input_key] = true

	_ensure_previous_face_input_is_released(press_input_key)


func _ensure_previous_face_input_is_released(new_input_key: String) -> void:
	if new_input_key != "fl" and \
			new_input_key != "fr":
		return

	var release_input_key := \
			"fl" if \
			new_input_key == "fr" else \
			"fr"
	if active_key_presses.has(release_input_key) and \
			active_key_presses[release_input_key]:
		_next_active_key_presses[release_input_key] = false
		active_key_presses[release_input_key] = false
