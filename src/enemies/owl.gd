class_name Owl
extends Enemy
## Flying enemy. No gravity — floats to where it wants to go.
## Behavior states:
##   - WANDER: not perceiving the player. Uses Enemy's shared wander
##     helper to idle-then-slow-drift around the current position.
##   - APPROACH: perceiving the player but too far for a swoop yet.
##     Closes distance at a cruise speed.
##   - SWOOP: within striking range. Snap the swoop direction to the
##     current toward-player vector, then fly along that direction
##     fast enough to overshoot past the player before stopping.
##   - RECOVER: just finished a swoop. Hover in place for a bit,
##     then switch back to APPROACH if still perceiving, or WANDER
##     otherwise.


## Max speed while closing in (approaching, not yet swooping).
const _APPROACH_SPEED_PX_PER_SEC := 85.0

## Distance at which APPROACH flips to SWOOP.
const _SWOOP_TRIGGER_DIST_PX := 80.0

## Speed during the swoop — fast enough to feel predatory and to
## meaningfully overshoot.
const _SWOOP_SPEED_PX_PER_SEC := 260.0

## How long the swoop runs before the owl slows to a stop. Speed ×
## duration = overshoot distance past the player.
const _SWOOP_DURATION_SEC := 0.55

## Post-swoop idle pause before approaching again.
const _RECOVER_DURATION_SEC := 0.9

## How quickly the owl's velocity chases the target velocity. Lower
## = floatier / more momentum; higher = snappier. Different per state
## so swoops feel committed while approach feels glide-y.
const _APPROACH_STEER_PER_SEC := 3.5
const _SWOOP_STEER_PER_SEC := 8.0
const _RECOVER_STEER_PER_SEC := 6.0

const _WANDER_SPEED_PX_PER_SEC := 28.0
const _WANDER_RADIUS_PX := 80.0
const _WANDER_IDLE_MIN_SEC := 0.4
const _WANDER_IDLE_MAX_SEC := 1.4

## Gentle hover bob amplitude while idling in RECOVER / wander
## (no-motion phases).
const _HOVER_AMPLITUDE_PX_PER_SEC := 18.0
const _HOVER_FREQUENCY_HZ := 0.8


enum OwlState { WANDER, APPROACH, SWOOP, RECOVER }


@export var animated_sprite: AnimatedSprite2D


var _state: OwlState = OwlState.WANDER
var _state_timer_sec: float = 0.0
var _swoop_velocity: Vector2 = Vector2.ZERO
var _time_sec: float = 0.0


func _update_behavior(delta: float, player: Player) -> void:
	_time_sec += delta

	# Transition-in: when perception arrives, leave WANDER.
	if _state == OwlState.WANDER and is_pursuing():
		_state = OwlState.APPROACH
	# Transition-out: lost the player. Drop to WANDER from any state
	# except mid-swoop (let swoops finish — the owl committed).
	if (not is_pursuing()
			and _state != OwlState.SWOOP
			and _state != OwlState.WANDER):
		_state = OwlState.WANDER
		_wander_has_target = false
		_wander_idle_timer_sec = 0.0

	match _state:
		OwlState.WANDER:
			_velocity = _velocity.lerp(
					_wander_target_velocity(delta),
					clampf(_APPROACH_STEER_PER_SEC * delta, 0.0, 1.0))
		OwlState.APPROACH:
			_velocity = _velocity.lerp(
					_approach_velocity(player),
					clampf(_APPROACH_STEER_PER_SEC * delta, 0.0, 1.0))
			if (is_instance_valid(player)
					and global_position.distance_to(player.global_position)
							< _SWOOP_TRIGGER_DIST_PX):
				_begin_swoop(player)
		OwlState.SWOOP:
			_state_timer_sec -= delta
			_velocity = _velocity.lerp(
					_swoop_velocity,
					clampf(_SWOOP_STEER_PER_SEC * delta, 0.0, 1.0))
			if _state_timer_sec <= 0.0:
				_state = OwlState.RECOVER
				_state_timer_sec = _RECOVER_DURATION_SEC
		OwlState.RECOVER:
			_state_timer_sec -= delta
			_velocity = _velocity.lerp(
					_hover_velocity(),
					clampf(_RECOVER_STEER_PER_SEC * delta, 0.0, 1.0))
			if _state_timer_sec <= 0.0:
				_state = (OwlState.APPROACH
						if is_pursuing() else OwlState.WANDER)

	_update_animation()


func _update_animation() -> void:
	if animated_sprite == null:
		return
	# Only one animation (fly), so always play it; but flip according
	# to current horizontal velocity so the owl faces where it's going.
	if animated_sprite.animation != &"fly":
		animated_sprite.play(&"fly")
	if absf(_velocity.x) > 1.0:
		animated_sprite.flip_h = _velocity.x < 0.0


func _wander_target_velocity(delta: float) -> Vector2:
	var wander: Vector2 = _compute_wander_velocity(
			delta,
			_WANDER_SPEED_PX_PER_SEC,
			_WANDER_RADIUS_PX,
			_WANDER_IDLE_MIN_SEC,
			_WANDER_IDLE_MAX_SEC)
	if wander == Vector2.ZERO:
		# Idling — hover in place.
		return _hover_velocity()
	return wander


func _approach_velocity(player: Player) -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() < 1.0:
		return Vector2.ZERO
	return to_player.normalized() * _APPROACH_SPEED_PX_PER_SEC


func _hover_velocity() -> Vector2:
	var bob_y: float = sin(
			_time_sec * _HOVER_FREQUENCY_HZ * TAU
	) * _HOVER_AMPLITUDE_PX_PER_SEC
	return Vector2(0.0, bob_y)


func _begin_swoop(player: Player) -> void:
	_state = OwlState.SWOOP
	_state_timer_sec = _SWOOP_DURATION_SEC
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() < 1.0:
		_swoop_velocity = Vector2(_SWOOP_SPEED_PX_PER_SEC, 0.0)
	else:
		_swoop_velocity = (to_player.normalized()
				* _SWOOP_SPEED_PX_PER_SEC)
