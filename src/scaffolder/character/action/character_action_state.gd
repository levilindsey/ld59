class_name CharacterActionState
extends RefCounted


enum ActionFlags {
	NONE = 0,
	JUMP = 1 << 0,
	PRESSED_UP = 1 << 1,
	PRESSED_DOWN = 1 << 2,
	PRESSED_LEFT = 1 << 3,
	PRESSED_RIGHT = 1 << 4,
	PRESSED_ATTACH = 1 << 5,
}


var current_actions_bitmask: int:
	get: return _get_current_actions_bitmask()
	set(value): _set_current_actions_bitmask(value)

var pressed_jump := false
var just_pressed_jump := false
var just_released_jump := false

var pressed_up := false
var just_pressed_up := false
var just_released_up := false

var pressed_down := false
var just_pressed_down := false
var just_released_down := false

var pressed_left := false
var just_pressed_left := false
var just_released_left := false

var pressed_right := false
var just_pressed_right := false
var just_released_right := false

var pressed_attach := false
var just_pressed_attach := false
var just_released_attach := false

var pressed_face_left := false
var just_pressed_face_left := false
var just_released_face_left := false

var pressed_face_right := false
var just_pressed_face_right := false
var just_released_face_right := false


func _get_current_actions_bitmask() -> int:
	var bitmask: int = ActionFlags.NONE
	if pressed_jump:
		bitmask |= ActionFlags.JUMP
	if pressed_up:
		bitmask |= ActionFlags.PRESSED_UP
	if pressed_down:
		bitmask |= ActionFlags.PRESSED_DOWN
	if pressed_left:
		bitmask |= ActionFlags.PRESSED_LEFT
	if pressed_right:
		bitmask |= ActionFlags.PRESSED_RIGHT
	if pressed_attach:
		bitmask |= ActionFlags.PRESSED_ATTACH
	return bitmask


func _set_current_actions_bitmask(value: int) -> void:
	var was_pressing_jump: bool = pressed_jump
	pressed_jump = (value & ActionFlags.JUMP) != 0
	just_pressed_jump = pressed_jump and not was_pressing_jump
	just_released_jump = not pressed_jump and was_pressing_jump

	var was_pressing_up: bool = pressed_up
	pressed_up = (value & ActionFlags.PRESSED_UP) != 0
	just_pressed_up = pressed_up and not was_pressing_up
	just_released_up = not pressed_up and was_pressing_up

	var was_pressing_down: bool = pressed_down
	pressed_down = (value & ActionFlags.PRESSED_DOWN) != 0
	just_pressed_down = pressed_down and not was_pressing_down
	just_released_down = not pressed_down and was_pressing_down

	var was_pressing_left: bool = pressed_left
	pressed_left = (value & ActionFlags.PRESSED_LEFT) != 0
	just_pressed_left = pressed_left and not was_pressing_left
	just_released_left = not pressed_left and was_pressing_left

	var was_pressing_right: bool = pressed_right
	pressed_right = (value & ActionFlags.PRESSED_RIGHT) != 0
	just_pressed_right = pressed_right and not was_pressing_right
	just_released_right = not pressed_right and was_pressing_right

	var was_pressing_attach: bool = pressed_attach
	pressed_attach = (value & ActionFlags.PRESSED_ATTACH) != 0
	just_pressed_attach = pressed_attach and not was_pressing_attach
	just_released_attach = not pressed_attach and was_pressing_attach


func clear() -> void:
	self.pressed_jump = false
	self.just_pressed_jump = false
	self.just_released_jump = false

	self.pressed_up = false
	self.just_pressed_up = false
	self.just_released_up = false

	self.pressed_down = false
	self.just_pressed_down = false
	self.just_released_down = false

	self.pressed_left = false
	self.just_pressed_left = false
	self.just_released_left = false

	self.pressed_right = false
	self.just_pressed_right = false
	self.just_released_right = false

	self.pressed_attach = false
	self.just_pressed_attach = false
	self.just_released_attach = false

	self.pressed_face_left = false
	self.just_pressed_face_left = false
	self.just_released_face_left = false

	self.pressed_face_right = false
	self.just_pressed_face_right = false
	self.just_released_face_right = false


func copy(other: CharacterActionState) -> void:
	self.pressed_jump = other.pressed_jump
	self.just_pressed_jump = other.just_pressed_jump
	self.just_released_jump = other.just_released_jump

	self.pressed_up = other.pressed_up
	self.just_pressed_up = other.just_pressed_up
	self.just_released_up = other.just_released_up

	self.pressed_down = other.pressed_down
	self.just_pressed_down = other.just_pressed_down
	self.just_released_down = other.just_released_down

	self.pressed_left = other.pressed_left
	self.just_pressed_left = other.just_pressed_left
	self.just_released_left = other.just_released_left

	self.pressed_right = other.pressed_right
	self.just_pressed_right = other.just_pressed_right
	self.just_released_right = other.just_released_right

	self.pressed_attach = other.pressed_attach
	self.just_pressed_attach = other.just_pressed_attach
	self.just_released_attach = other.just_released_attach

	self.pressed_face_left = other.pressed_face_left
	self.just_pressed_face_left = other.just_pressed_face_left
	self.just_released_face_left = other.just_released_face_left

	self.pressed_face_right = other.pressed_face_right
	self.just_pressed_face_right = other.just_pressed_face_right
	self.just_released_face_right = other.just_released_face_right


func log_new_presses_and_releases(character) -> void:
	_log_new_press_or_release(
			character,
			"jump",
			just_pressed_jump,
			just_released_jump)
	_log_new_press_or_release(
			character,
			"up",
			just_pressed_up,
			just_released_up)
	_log_new_press_or_release(
			character,
			"down",
			just_pressed_down,
			just_released_down)
	_log_new_press_or_release(
			character,
			"left",
			just_pressed_left,
			just_released_left)
	_log_new_press_or_release(
			character,
			"right",
			just_pressed_right,
			just_released_right)
	_log_new_press_or_release(
			character,
			"attach",
			just_pressed_attach,
			just_released_attach)
	_log_new_press_or_release(
			character,
			"faceL",
			just_pressed_face_left,
			just_released_face_left)
	_log_new_press_or_release(
			character,
			"faceR",
			just_pressed_face_right,
			just_released_face_right)


func _log_new_press_or_release(
		character,
		action_name: String,
		just_pressed: bool,
		just_released: bool) -> void:
	var current_presses_strs := []
	if pressed_jump:
		current_presses_strs.push_back("J")
	if pressed_up:
		current_presses_strs.push_back("U")
	if pressed_down:
		current_presses_strs.push_back("D")
	if pressed_left:
		current_presses_strs.push_back("L")
	if pressed_right:
		current_presses_strs.push_back("R")
	if pressed_attach:
		current_presses_strs.push_back("G")
	if pressed_face_left:
		current_presses_strs.push_back("FL")
	if pressed_face_right:
		current_presses_strs.push_back("FR")
	var current_presses_str: String = Utils.join(current_presses_strs)

	var velocity_string: String = \
			"%17s" % G.utils.get_vector_string(character.velocity, 1)

	var details := "v=%s; [%s]" % [
		velocity_string,
		current_presses_str,
	]

	if just_pressed:
		G.print("START %5s: %s" % [action_name, details])
	if just_released:
		G.print("STOP  %5s: %s" % [action_name, details])


const _ACTION_FLAG_DEBUG_LABEL_PAIRS := [
	[ActionFlags.JUMP, "J"],
	[ActionFlags.PRESSED_UP, "U"],
	[ActionFlags.PRESSED_DOWN, "D"],
	[ActionFlags.PRESSED_LEFT, "L"],
	[ActionFlags.PRESSED_RIGHT, "R"],
	[ActionFlags.PRESSED_ATTACH, "G"],
]


static func get_debug_label_from_actions_bitmask(actions_bitmask: int) -> String:
	var action_strs := []
	for pair in _ACTION_FLAG_DEBUG_LABEL_PAIRS:
		var flag: int = pair[0]
		var text: String = pair[1]
		if actions_bitmask & flag:
			action_strs.push_back(text)
		else:
			action_strs.push_back("-")
	return Utils.join(action_strs)
