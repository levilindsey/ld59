class_name CharacterActionHandler
extends RefCounted
## An ActionHandler updates a character's state each frame, in response to
## current events and the character's current state.
## For example, FloorJumpAction listens for jump events while the character is
## on the ground, and triggers character jump state accordingly.


var name: String
# SurfaceType
var type: int
var uses_runtime_physics: bool
var priority: int


func _init(
		p_name: String,
		p_type: int,
		p_uses_runtime_physics: bool,
		p_priority: int) -> void:
	self.name = p_name
	self.type = p_type
	self.uses_runtime_physics = p_uses_runtime_physics
	self.priority = p_priority


func process(_character) -> bool:
	push_error(
			"Abstract CharacterActionHandler.process is not implemented")
	return false
