@tool
class_name ScaffolderTween
extends Node


signal tween_all_completed
# NOTE: Using this is almost never what you want.
#	   Use tween_all_completed instead.
signal _tween_completed(object, key)

var parent
var id := -1

var _pending_sub_tweens := []
var _active_sub_tweens := []


func _init(
		p_parent,
		adds_self_as_child_of_parent := true) -> void:
	self.parent = p_parent
	name = "ScaffolderTween"
	self.id = G.time.get_next_task_id()
	if adds_self_as_child_of_parent:
		p_parent.add_child(self)


func _destroy() -> void:
	G.time.clear_tween(id)


func _process(_delta: float) -> void:
	step()


func step() -> void:
	if !is_active():
		return

	# End and remove any finished tweens.
	var finished_sub_tweens := []
	for sub_tween in _active_sub_tweens:
		if sub_tween.get_is_finished():
			finished_sub_tweens.push_back(sub_tween)
	for sub_tween in finished_sub_tweens:
		sub_tween.end()
		_stop_sub_tween(sub_tween)
		emit_signal("_tween_completed", sub_tween.object, sub_tween.key)

	# Update all in-progress tweens.
	for sub_tween in _active_sub_tweens:
		sub_tween.step()

	if !is_active():
		emit_signal("tween_all_completed")


func is_active() -> bool:
	return !_active_sub_tweens.is_empty()


func get_progress() -> float:
	return 0.0 if \
			_active_sub_tweens.is_empty() else \
			_active_sub_tweens[0].progress


func start() -> bool:
	if _pending_sub_tweens.is_empty():
		return false

	for sub_tween in _pending_sub_tweens:
		sub_tween.start()
		_active_sub_tweens.push_back(sub_tween)
	_pending_sub_tweens.clear()

	return true


func stop(object: Object, key := "") -> bool:
	var matching_index := -1
	for index in _active_sub_tweens.size():
		var sub_tween: _SubTween = _active_sub_tweens[index]
		if sub_tween.object == object and \
				(key == "" or \
				sub_tween.key == key):
			matching_index = index
			break

	if matching_index >= 0:
		_active_sub_tweens.erase(matching_index)
		return true
	else:
		return false


func _stop_sub_tween(sub_tween: _SubTween) -> void:
	_active_sub_tweens.erase(sub_tween)


func stop_all() -> bool:
	if _active_sub_tweens.is_empty():
		return false
	else:
		_active_sub_tweens.clear()
		return true


func trigger_completed() -> void:
	if _active_sub_tweens.is_empty():
		return
	var _sub_tween: _SubTween = _active_sub_tweens[0]

	var connections := get_signal_connection_list("tween_all_completed")
	if connections.is_empty():
		return
	var connection: Dictionary = connections[0]

#	var args := [sub_tween.object, sub_tween.key]
	var args := []
	args.append_array(connection.binds)

	connection.target.callv(connection.method, args)


func interpolate_method(
		object: Object,
		key: String,
		initial_val,
		final_val,
		duration: float,
		ease_name := "ease_in_out",
		delay := 0.0,
		time_type := TimeType.APP_PHYSICS) -> void:
	_interpolate(
			object,
			key,
			false,
			initial_val,
			final_val,
			duration,
			ease_name,
			delay,
			time_type)


func interpolate_property(
		object: Object,
		key: NodePath,
		initial_val,
		final_val,
		duration: float,
		ease_name := "ease_in_out",
		delay := 0.0,
		time_type := TimeType.APP_PHYSICS) -> void:
	_interpolate(
			object,
			key,
			true,
			initial_val,
			final_val,
			duration,
			ease_name,
			delay,
			time_type)


func _interpolate(
		object: Object,
		key: NodePath,
		is_property: bool,
		initial_val,
		final_val,
		duration: float,
		ease_name: String,
		delay: float,
		time_type: int) -> void:
	_pending_sub_tweens.push_back(_SubTween.new(
			object,
			key,
			is_property,
			initial_val,
			final_val,
			duration,
			ease_name,
			delay,
			time_type))


class _SubTween extends RefCounted:


	var object: Object
	var key: String
	var is_property: bool
	var initial_val
	var final_val
	var duration: float
	var ease_name: String
	var delay: float
	var time_type: int

	var start_time := INF

	var progress := 0.0


	func _init(
			p_object: Object,
			p_key: String,
			p_is_property: bool,
			p_initial_val,
			p_final_val,
			p_duration: float,
			p_ease_name: String,
			p_delay: float,
			p_time_type: int) -> void:
		assert(p_duration > 0)
		self.object = p_object
		self.key = p_key
		self.is_property = p_is_property
		self.initial_val = p_initial_val
		self.final_val = p_final_val
		self.duration = p_duration
		self.ease_name = p_ease_name
		self.delay = p_delay
		self.time_type = p_time_type


	func get_is_finished() -> bool:
		return G.time.get_elapsed_time(time_type) >= \
				start_time + duration + delay or \
				!is_instance_valid(object)


	func start() -> void:
		start_time = G.time.get_elapsed_time(time_type)


	func end() -> void:
		if is_instance_valid(object):
			_update_with_value(final_val)


	func step() -> void:
		var current_time: float = G.time.get_elapsed_time(time_type)
		var elapsed_time := current_time - start_time
		if elapsed_time < delay:
			return
		progress = clamp(
				(elapsed_time - delay) / duration,
				0,
				1)
		progress = Utils.ease_by_name(progress, ease_name)
		_update_with_value(lerp(initial_val, final_val, progress))


	func _update_with_value(value) -> void:
		if is_property:
			object.set_indexed(key, value)
		else:
			object.call(key, value)
