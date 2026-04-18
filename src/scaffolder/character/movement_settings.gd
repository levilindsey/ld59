class_name MovementSettings
extends Resource


enum ActionHandlerType {
	FLOOR_DEFAULT,
	AIR_DEFAULT,
	WALL_DEFAULT,
	CEILING_DEFAULT,
	ALL_DEFAULT,
	CAP_VELOCITY,

	FLOOR_WALK,
	FLOOR_JUMP,
	FLOOR_FRICTION,
	FALL_THROUGH_FLOOR,

	AIR_JUMP,

	WALL_CLIMB,
	WALL_FALL,
	WALL_JUMP,

	CEILING_CRAWL,
	CEILING_FALL,
	CEILING_JUMP_DOWN,
}

var DEFAULT_ACTION_HANDLER_CLASSES := {
	ActionHandlerType.FLOOR_DEFAULT: FloorDefaultAction,
	ActionHandlerType.AIR_DEFAULT: AirDefaultAction,
	ActionHandlerType.WALL_DEFAULT: WallDefaultAction,
	ActionHandlerType.CEILING_DEFAULT: CeilingDefaultAction,
	ActionHandlerType.ALL_DEFAULT: AllDefaultAction,
	ActionHandlerType.CAP_VELOCITY: CapVelocityAction,

	ActionHandlerType.FLOOR_WALK: FloorWalkAction,
	ActionHandlerType.FLOOR_JUMP: FloorJumpAction,
	ActionHandlerType.FLOOR_FRICTION: FloorFrictionAction,
	ActionHandlerType.FALL_THROUGH_FLOOR: FallThroughFloorAction,

	ActionHandlerType.AIR_JUMP: AirJumpAction,

	ActionHandlerType.WALL_CLIMB: WallClimbAction,
	ActionHandlerType.WALL_FALL: WallFallAction,
	ActionHandlerType.WALL_JUMP: WallJumpAction,

	ActionHandlerType.CEILING_CRAWL: CeilingCrawlAction,
	ActionHandlerType.CEILING_FALL: CeilingFallAction,
	ActionHandlerType.CEILING_JUMP_DOWN: CeilingJumpDownAction,
}

const _MAX_SLIDES_DEFAULT := 4
# 45 degrees
const _MAX_FLOOR_ANGLE = PI / 4.0
const _STRONG_SPEED_TO_MAINTAIN_COLLISION := 900.0

# --- Movement parameters ---

@export var can_attach_to_floors := true
@export var can_attach_to_walls := false
@export var can_attach_to_ceilings := false

@export var always_tries_to_face_direction_of_motion := true
@export var max_jump_chain := 1

@export var jump_boost := -900.0
@export var double_jump_boost_multiplier := 0.6
@export var wall_jump_horizontal_boost := 200.0
@export var wall_fall_horizontal_boost := 20.0

@export var gravity_acceleration_multiplier := 1.0
@export var gravity_slow_rise_multiplier := 0.38
@export var gravity_double_jump_slow_rise_multiplier := 0.68

var gravity_fast_fall_acceleration: float:
	get: return gravity_acceleration_multiplier * G.settings.default_gravity_acceleration
var gravity_slow_rise_acceleration: float:
	get: return gravity_fast_fall_acceleration * gravity_slow_rise_multiplier
var gravity_double_jump_slow_rise_acceleration: float:
	get: return gravity_fast_fall_acceleration * gravity_double_jump_slow_rise_multiplier

@export var walk_acceleration := 8000.0
@export var in_air_horizontal_acceleration := 2500.0
@export var climb_up_speed := -230.0
@export var climb_down_speed := 120.0
@export var ceiling_crawl_speed := 230.0

@export var fall_through_floor_velocity_boost := 100.0
@export var ceiling_fall_velocity_boost := 100.0

@export var friction_coeff_with_sideways_input := 1.25
@export var friction_coeff_without_sideways_input := 1.0

@export var max_ground_horizontal_speed := 320.0
@export var max_air_horizontal_speed := 400.0
@export var max_vertical_speed := 2800.0
@export var min_horizontal_speed := 5.0
@export var min_vertical_speed := 0.0

## Coyote time.
@export var late_jump_forgiveness_threshold_sec := 0.3

@export var action_handler_types: Array[ActionHandlerType] = [
	ActionHandlerType.FLOOR_DEFAULT,
	ActionHandlerType.AIR_DEFAULT,
	ActionHandlerType.WALL_DEFAULT,
	ActionHandlerType.CEILING_DEFAULT,
	ActionHandlerType.ALL_DEFAULT,
	ActionHandlerType.CAP_VELOCITY,

	ActionHandlerType.FLOOR_WALK,
	ActionHandlerType.FLOOR_JUMP,
	ActionHandlerType.FLOOR_FRICTION,
	ActionHandlerType.FALL_THROUGH_FLOOR,

	ActionHandlerType.AIR_JUMP,

	ActionHandlerType.WALL_CLIMB,
	ActionHandlerType.WALL_FALL,
	ActionHandlerType.WALL_JUMP,

	ActionHandlerType.CEILING_CRAWL,
	ActionHandlerType.CEILING_FALL,
	ActionHandlerType.CEILING_JUMP_DOWN,
]

var action_handlers: Array[CharacterActionHandler] = []


func set_up() -> void:
	action_handlers.clear()
	for type in action_handler_types:
		action_handlers.append(DEFAULT_ACTION_HANDLER_CLASSES[type].new())
	action_handlers.sort_custom(_compare_character_action_handler)


static func _compare_character_action_handler(
		a: CharacterActionHandler,
		b: CharacterActionHandler) -> bool:
	return a.priority < b.priority
