class_name Instruction
extends RefCounted
# An input event to trigger (or untrigger) at a specific time.


var input_key: String
var time: float
# Optional
var is_pressed: bool
# Optional
var position := Vector2.INF


func _init(
		p_input_key := "",
		p_time := INF,
		p_is_pressed := false,
		p_position := Vector2.INF) -> void:
	# Correct for round-off error.
	if Geometry.are_floats_equal_with_epsilon(p_time, 0.0, 0.00001):
		p_time = 0.0

	self.input_key = p_input_key
	self.time = p_time
	self.is_pressed = p_is_pressed
	self.position = p_position


func get_string() -> String:
	return "EdgeInstruction{ %s, %.2f, %s%s }" % [
			input_key,
			time,
			is_pressed,
			", %s" % position if position != Vector2.INF else ""
		]
