class_name Character
extends CharacterBody2D


signal physics_processed


const _NORMAL_SURFACES_COLLISION_MASK_BIT := 1 << 0
const _FALL_THROUGH_FLOORS_COLLISION_MASK_BIT := 1 << 1
const _WALK_THROUGH_WALLS_COLLISION_MASK_BIT := 1 << 2
const _HACK_FOR_EDGE_DETECTION_COLLISION_MASK_BIT := 1 << 7

const _MIN_FALL_DAMAGE_SPEED := 600.0
const _MAX_FALL_DAMAGE_SPEED := 2000.0

const _MIN_FALL_DAMAGE := 5.0
const _MAX_FALL_DAMAGE := 40.0

@export var collision_shape: CollisionShape2D
@export var animator: CharacterAnimator
@export var movement_settings: MovementSettings

var start_position := Vector2.INF
var previous_position := Vector2.INF
var stationary_frames_count := 0

var total_distance_traveled := INF

var start_time := INF
var previous_total_time := INF
var total_time := INF

var last_delta_scaled := ScaffolderTime.PHYSICS_TIME_STEP

var is_player_control_active := true

var just_triggered_jump := false
var is_rising_from_jump := false
var jump_count := 0

var previous_velocity := Vector2.INF

var _current_max_horizontal_speed_multiplier := 1.0

var surface_state := CharacterSurfaceState.new(self)

var _actions_from_previous_frame := CharacterActionState.new()
var actions := CharacterActionState.new()

# Array<CharacterActionSource>
var _action_sources := []
# Dictionary<String, bool>
var _previous_actions_handlers_this_frame := {}

var _character_action_source: CharacterActionSource

var is_walking: bool:
	get:
		return (
			(actions.pressed_left or actions.pressed_right) and
			surface_state.is_attaching_to_floor
		)


var current_surface_max_horizontal_speed: float:
	get: return movement_settings.max_ground_horizontal_speed * \
			_current_max_horizontal_speed_multiplier * \
			(surface_state.surface_properties.speed_multiplier if \
			surface_state.is_attaching_to_surface else \
			1.0)


var current_air_max_horizontal_speed: float:
	get: return movement_settings.max_air_horizontal_speed * \
			_current_max_horizontal_speed_multiplier


var current_walk_acceleration: float:
	get: return movement_settings.walk_acceleration * \
			(surface_state.surface_properties.speed_multiplier if \
			surface_state.is_attaching_to_surface else \
			1.0)


var current_climb_up_speed: float:
	get: return movement_settings.climb_up_speed * \
			(surface_state.surface_properties.speed_multiplier if \
			surface_state.is_attaching_to_surface else \
			1.0)


var current_climb_down_speed: float:
	get: return movement_settings.climb_down_speed * \
			(surface_state.surface_properties.speed_multiplier if \
			surface_state.is_attaching_to_surface else \
			1.0)


var current_ceiling_crawl_speed: float:
	get: return movement_settings.ceiling_crawl_speed * \
			(surface_state.surface_properties.speed_multiplier if \
			surface_state.is_attaching_to_surface else \
			1.0)


var is_sprite_visible: bool:
	set(value): animator.visible = value
	get: return animator.visible


func _ready() -> void:
	if not collision_shape:
		assert(false, "Character.collision_shape is not provided: %s" % name)
	if not animator:
		assert(false, "Character.animator is not provided: %s" % name)
	if not movement_settings:
		assert(false, "Character.movement_settings is not provided: %s" % name)

	movement_settings.set_up()

	total_distance_traveled = 0.0
	start_time = G.time.get_scaled_play_time()
	total_time = 0.0

	start_position = position

	# Start facing right.
	surface_state.horizontal_facing_sign = 1
	animator.face_right()

	if !is_instance_valid(_character_action_source):
		_init_player_controller_action_source()

	# For move_and_slide.
	up_direction = Vector2.UP
	floor_stop_on_slope = false
	max_slides = MovementSettings._MAX_SLIDES_DEFAULT
	floor_max_angle = G.geometry.FLOOR_MAX_ANGLE + G.geometry.WALL_ANGLE_EPSILON


func _init_player_controller_action_source() -> void:
	assert(!is_instance_valid(_character_action_source))
	self._character_action_source = PlayerActionSource.new(self, true)
	_action_sources.push_back(_character_action_source)


func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	last_delta_scaled = G.time.scale_delta(delta)

	previous_total_time = total_time
	total_time = G.time.get_scaled_play_time() - start_time

	previous_position = global_position

	previous_velocity = velocity

	_apply_movement()

	_update_actions()
	surface_state.clear_just_changed_state()
	surface_state.update_actions()

	#actions.log_new_presses_and_releases(self)

	# Flip the horizontal direction of the animation according to which way the
	# character is facing.
	if surface_state.horizontal_facing_sign == 1:
		animator.face_right()
	elif surface_state.horizontal_facing_sign == -1:
		animator.face_left()

	_process_actions()
	_process_animation()
	_process_sounds()
	_update_collision_mask()

	if surface_state.did_move_last_frame:
		stationary_frames_count = 0
	else:
		stationary_frames_count += 1

	total_distance_traveled += position.distance_to(previous_position)

	physics_processed.emit()


func _apply_movement() -> void:
	var base_velocity := velocity
	# Since move_and_slide automatically accounts for delta, we need to
	# compensate for that in order to support our modified framerate.
	var modified_velocity: Vector2 = base_velocity * G.time.get_combined_scale()

	velocity = modified_velocity
	max_slides = MovementSettings._MAX_SLIDES_DEFAULT
	move_and_slide()

	surface_state.update_collisions()


func _update_actions() -> void:
	# Record actions for the previous frame.
	_actions_from_previous_frame.copy(actions)
	# Clear actions for the current frame.
	actions.clear()

	# Update actions for the current frame.
	for action_source in _action_sources:
		action_source.update(
				actions,
				_actions_from_previous_frame,
				G.time.get_scaled_play_time())

	CharacterActionSource.update_for_implicit_key_events(
			actions,
			_actions_from_previous_frame)


# Updates physics and character states in response to the current actions.
func _process_actions() -> void:
	_previous_actions_handlers_this_frame.clear()

	for action_handler in movement_settings.action_handlers:
		# Our surface-state logic considers the current actions, and
		# surface-state is updated before we process actions here.
		# Furthermore, we use action-handlers to actually apply the
		# changes for things like jump impulses that are needed to
		# actually transition the character from a surface. So we need
		# to also consider the surface that we are currently leaving,
		# and allow an action-handler of that departure-surface-type to
		# handle this frame. However, "Default" actions maintain steady-
		# state behavior and should not run during surface transitions.
		var is_just_left_and_not_default: bool = \
				action_handler.type == surface_state.just_left_surface_type and \
				surface_state.just_left_surface_type != SurfaceType.OTHER and \
				!action_handler.name.contains("Default")
		var is_action_relevant_for_surface: bool = \
				action_handler.type == surface_state.surface_type or \
				action_handler.type == SurfaceType.OTHER or \
				is_just_left_and_not_default
		var is_action_relevant_for_physics_mode: bool = \
				action_handler.uses_runtime_physics
		if is_action_relevant_for_surface and \
				is_action_relevant_for_physics_mode:
			var executed: bool = action_handler.process(self)
			_previous_actions_handlers_this_frame[action_handler.name] = \
					executed

	assert(!Geometry.is_point_partial_inf(velocity))


func _process_animation() -> void:
	match surface_state.surface_type:
		SurfaceType.FLOOR:
			if actions.pressed_left or actions.pressed_right:
				animator.play("walk")
			else:
				animator.play("rest")
		SurfaceType.WALL:
			if processed_action("WallClimbAction"):
				if actions.pressed_up:
					animator.play("climb_up")
				elif actions.pressed_down:
					animator.play("climb_down")
				else:
					G.fatal("SurfacerCharacter._process_animation")
			else:
				animator.play("rest_on_wall")
		SurfaceType.CEILING:
			if actions.pressed_left or actions.pressed_right:
				animator.play("crawl_on_ceiling")
			else:
				animator.play("rest_on_ceiling")
		SurfaceType.AIR:
			if velocity.y > 0:
				animator.play("jump_fall")
			else:
				animator.play("jump_rise")
		_:
			G.fatal("SurfacerCharacter._process_animation")


func _process_sounds() -> void:
	if just_triggered_jump:
		play_sound("jump")

	if surface_state.just_left_air:
		play_sound("land", true)
	elif surface_state.just_touched_surface:
		play_sound("land", true)

	if is_walking:
		play_sound("walk")
	else:
		G.audio.stop_player_sound("walk")


func play_sound(_sound_name: String, _force_restart := false) -> void:
	push_error("Abstract CharacterActionSource.update is not implemented")


func processed_action(p_name: String) -> bool:
	return _previous_actions_handlers_this_frame.get(p_name) == true


# Update whether or not we should currently consider collisions with
# fall-through floors and walk-through walls.
func _update_collision_mask() -> void:
	set_collision_mask_value(
			_FALL_THROUGH_FLOORS_COLLISION_MASK_BIT,
			not surface_state.is_descending_through_floors)
	#set_collision_mask_value(
			#_WALK_THROUGH_WALLS_COLLISION_MASK_BIT,
			#surface_state.is_attaching_to_walk_through_walls)


func force_boost(boost: Vector2) -> void:
	velocity = boost

	position += Vector2(0.0, -1.0)
	surface_state.force_boost()


func get_next_position_prediction() -> Vector2:
	# Since move_and_slide automatically accounts for delta, we need to
	# compensate for that in order to support our modified framerate.
	var modified_velocity: Vector2 = velocity * G.time.get_combined_scale()
	return position + modified_velocity * G.time.PHYSICS_TIME_STEP


func get_position_in_screen_space() -> Vector2:
	return G.utils.get_screen_position_of_node_in_level(self)
