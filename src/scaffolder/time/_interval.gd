@tool
class_name _Interval
extends RefCounted


var time_tracker
var elapsed_time_key: String
var callback: Callable
var interval: float
var arguments: Array
var next_trigger_time: float
var id: int
var parent


func _init(
		p_parent,
		p_time_type: int,
		p_callback: Callable,
		p_interval: float,
		p_arguments: Array) -> void:
	self.parent = p_parent
	self.time_tracker = G.time._get_time_tracker_for_time_type(p_time_type)
	self.elapsed_time_key = \
			G.time._get_elapsed_time_key_for_time_type(p_time_type)
	self.callback = p_callback
	self.interval = p_interval
	self.arguments = p_arguments
	self.next_trigger_time = \
			time_tracker.get(elapsed_time_key) + p_interval
	self.id = G.time.get_next_task_id()


func get_has_reached_next_trigger_time() -> bool:
	var elapsed_time: float = time_tracker.get(elapsed_time_key)
	return elapsed_time >= next_trigger_time


func trigger() -> void:
	if !callback.is_valid():
		return
	next_trigger_time = \
			time_tracker.get(elapsed_time_key) + interval
	callback.callv(arguments)
