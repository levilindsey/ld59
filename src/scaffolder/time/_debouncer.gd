@tool
class_name _Debouncer
extends RefCounted


var time_type: int
var time_tracker
var elapsed_time_key: String
var callback: Callable
var interval: float
var invokes_at_start: bool
var parent

var last_timeout_id := -1

var last_call_time := -INF
var is_callback_scheduled := false


func _init(
		p_parent,
		p_time_type: int,
		p_callback: Callable,
		p_interval: float,
		p_invokes_at_start: bool) -> void:
	self.parent = p_parent
	self.time_type = p_time_type
	self.time_tracker = G.time._get_time_tracker_for_time_type(p_time_type)
	self.elapsed_time_key = \
			G.time._get_elapsed_time_key_for_time_type(p_time_type)
	self.callback = p_callback
	self.interval = p_interval
	self.invokes_at_start = p_invokes_at_start


func on_call() -> void:
	var current_call_time: float = \
			time_tracker.get(elapsed_time_key)
	if invokes_at_start and \
			!is_callback_scheduled and \
			current_call_time > last_call_time + interval:
		_trigger_callback()

	G.time.clear_timeout(last_timeout_id)
	last_timeout_id = G.time.set_timeout(
			_trigger_callback,
			interval,
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
