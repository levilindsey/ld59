@tool
class_name _Throttler
extends RefCounted


var time_type: int
var time_tracker
var elapsed_time_key: String
var callback: Callable
var interval: float
var invokes_at_end: bool
var parent

var last_timeout_id := -1

var last_call_time := -INF
var is_callback_scheduled := false


func _init(
		p_parent,
		p_time_type: int,
		p_callback: Callable,
		p_interval: float,
		p_invokes_at_end: bool) -> void:
	self.parent = p_parent
	self.time_type = p_time_type
	self.time_tracker = G.time._get_time_tracker_for_time_type(p_time_type)
	self.elapsed_time_key = \
			G.time._get_elapsed_time_key_for_time_type(p_time_type)
	self.callback = p_callback
	self.interval = p_interval
	self.invokes_at_end = p_invokes_at_end


func on_call() -> void:
	if !is_callback_scheduled:
		var current_call_time: float = \
				time_tracker.get(elapsed_time_key)
		var next_call_time := last_call_time + interval
		if current_call_time > next_call_time:
			_trigger_callback()
		elif invokes_at_end:
			last_timeout_id = G.time.set_timeout(
					_trigger_callback,
					next_call_time - current_call_time,
					[],
					time_type)
			is_callback_scheduled = true


func cancel() -> void:
	G.time.clear_timeout(last_timeout_id)
	is_callback_scheduled = false


func _trigger_callback() -> void:
	last_call_time = time_tracker.get(elapsed_time_key)
	is_callback_scheduled = false
	if callback.is_valid():
		callback.call()
