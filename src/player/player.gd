class_name Player
extends Character


## Horizontal speed multiplier applied while any WebTile overlaps the
## player's WebSensor.
const _WEB_SPEED_MULTIPLIER := 0.25

## Fluid velocity magnitude (px/sec) at which fluid begins to damage
## the player. Below this the player can wade through liquid safely.
const _FLUID_DAMAGE_SPEED_THRESHOLD := 120.0

## Damage per second applied at the max fluid speed; scales linearly
## with excess-over-threshold.
const _FLUID_DAMAGE_PER_SEC := 20.0

## Applied-damage cooldown so we don't tick integer HP every frame.
const _FLUID_DAMAGE_TICK_SEC := 0.25

## Absolute cap on `|velocity.y|` while overlapping a web. Applied
## after the scaffolder's action handlers run, so gravity and jump
## impulses are still computed normally but the resulting motion is
## slow. Clamping (rather than scaling) avoids compound-drag weirdness
## across frames at varying physics steps.
const _WEB_MAX_VERTICAL_SPEED_PX_PER_SEC := 120.0

<<<<<<< HEAD
## Horizontal speed multiplier while submerged in LIQUID terrain.
const _WATER_SPEED_MULTIPLIER := 0.45
## Post-step cap on |velocity.y| while submerged. Keeps buoyancy and
## sinking gentle so the player can orient mid-water.
const _WATER_MAX_VERTICAL_SPEED_PX_PER_SEC := 160.0
## Fraction of normal gravity applied while submerged. Anything < 1
## feels floaty.
const _WATER_GRAVITY_SCALE := 0.2
## Upward impulse applied on each jump-press while submerged. Lets
## the player "double-jump" upward through water repeatedly.
const _WATER_SWIM_IMPULSE_PX_PER_SEC := 180.0

## Minimum interval between echo pulses (3 / second).
=======
## Minimum interval between echo pulses (3 / second) for colored pulses.
>>>>>>> a2a916c (Update juice)
const _ECHO_COOLDOWN_SEC := 1.0 / 3.0

## Half-rate cooldown for the blank (NONE) reveal-only pulse.
const _NONE_ECHO_COOLDOWN_SEC := _ECHO_COOLDOWN_SEC * 2.0

## Maximum juice per frequency. Fills from eating bugs (+1 small,
## +5 big); consumed at 1/echo.
const MAX_JUICE := 10

## Juice granted by each bug size (used by `Bug._consume`).
const SMALL_JUICE_GRANT := 1
const BIG_JUICE_GRANT := 5

## Order the Q/E selection cursor walks. NONE is always selectable;
## the four colored slots are skipped while their juice is 0.
const _SELECTABLE_ORDER: Array[int] = [
	Frequency.Type.NONE,
	Frequency.Type.RED,
	Frequency.Type.GREEN,
	Frequency.Type.BLUE,
	Frequency.Type.YELLOW,
]

## Grace period after taking damage: further damage is ignored and
## the sprite blinks.
const _INVINCIBILITY_SEC := 0.8

## Blink period while invincible: visibility toggles every half of
## this many seconds.
const _BLINK_PERIOD_SEC := 0.12


signal juice_changed(frequency: int, new_value: int)
signal frequency_selection_changed(frequency: int)


var _is_in_web := false
var _is_in_water := false
var _fluid_damage_accum_sec := 0.0
var _echo_cooldown_sec := 0.0
## Cooldown duration that's currently in effect — either
## `_ECHO_COOLDOWN_SEC` or `_NONE_ECHO_COOLDOWN_SEC`, depending on
## which frequency the last pulse used. Used by the HUD to scale its
## cooldown-ready animation against the right denominator.
var _current_cooldown_duration := _ECHO_COOLDOWN_SEC
var _invincibility_remaining_sec := 0.0
var _blink_accum_sec := 0.0
var _pre_step_velocity_y := 0.0

## Per-frequency juice pool. Populated in `_ready()`; only the four
## gameplay frequencies (RED/GREEN/BLUE/YELLOW) are keys.
var _juice: Dictionary = {}


var half_size := Vector2.INF

## Player's currently-selected echolocation frequency. Driven by
## Q/E (or auto-advance when the active color runs dry). NONE is
## "stipple-only" — no juice cost, half-rate cooldown, reveals the
## level but interacts with no tiles or enemies.
var current_frequency: int = Frequency.Type.NONE


func _ready() -> void:
	super._ready()
	half_size = Geometry.calculate_half_width_height(
		collision_shape.shape,
		false)
	_juice = {
		Frequency.Type.RED: 0,
		Frequency.Type.GREEN: 0,
		Frequency.Type.BLUE: 0,
		Frequency.Type.YELLOW: 0,
	}
	current_frequency = Frequency.Type.NONE
	%PlayerHealth.died.connect(_on_died)


func destroy() -> void:
	queue_free()


func _process(delta: float) -> void:
	super._process(delta)
	if _echo_cooldown_sec > 0.0:
		_echo_cooldown_sec = maxf(0.0, _echo_cooldown_sec - delta)
	_tick_invincibility(delta)


func _tick_invincibility(delta: float) -> void:
	if _invincibility_remaining_sec <= 0.0:
		if not visible:
			visible = true
		return
	_invincibility_remaining_sec -= delta
	_blink_accum_sec += delta
	if _blink_accum_sec >= _BLINK_PERIOD_SEC:
		_blink_accum_sec = 0.0
		visible = not visible
	if _invincibility_remaining_sec <= 0.0:
		visible = true
		_blink_accum_sec = 0.0


func _physics_process(delta: float) -> void:
	if G.level.has_won:
		return

	_sample_web_overlap()
	_sample_water_overlap()
	if _is_in_water:
		_current_max_horizontal_speed_multiplier = _WATER_SPEED_MULTIPLIER
	elif _is_in_web:
		_current_max_horizontal_speed_multiplier = _WEB_SPEED_MULTIPLIER
	else:
		_current_max_horizontal_speed_multiplier = 1.0
	_pre_step_velocity_y = velocity.y
	super._physics_process(delta)
	if _is_in_water:
		# Scale the gravity delta applied by the scaffolder this
		# frame so water feels floaty. Also handle swim jumps.
		var gravity_delta := velocity.y - _pre_step_velocity_y
		velocity.y = (
				_pre_step_velocity_y
				+ gravity_delta * _WATER_GRAVITY_SCALE)
		if Input.is_action_just_pressed("jump"):
			velocity.y = minf(
					velocity.y,
					-_WATER_SWIM_IMPULSE_PX_PER_SEC)
		velocity.y = clampf(
				velocity.y,
				-_WATER_MAX_VERTICAL_SPEED_PX_PER_SEC,
				_WATER_MAX_VERTICAL_SPEED_PX_PER_SEC)
	elif _is_in_web:
		velocity.y = clampf(
				velocity.y,
				-_WEB_MAX_VERTICAL_SPEED_PX_PER_SEC,
				_WEB_MAX_VERTICAL_SPEED_PX_PER_SEC)
	_apply_fluid_damage(delta)


func _sample_water_overlap() -> void:
	_is_in_water = false
	if not is_instance_valid(G.terrain):
		return
	if G.terrain.is_cell_type_at(
			global_position, Frequency.Type.LIQUID):
		_is_in_water = true


func _apply_fluid_damage(delta: float) -> void:
	if not is_instance_valid(G.terrain):
		return
	var fluid_vel: Vector2 = G.terrain.sample_fluid_velocity(global_position)
	var speed := fluid_vel.length()
	if speed < _FLUID_DAMAGE_SPEED_THRESHOLD:
		_fluid_damage_accum_sec = 0.0
		return
	_fluid_damage_accum_sec += delta
	if _fluid_damage_accum_sec < _FLUID_DAMAGE_TICK_SEC:
		return
	_fluid_damage_accum_sec -= _FLUID_DAMAGE_TICK_SEC
	var over_threshold := speed - _FLUID_DAMAGE_SPEED_THRESHOLD
	var dps := minf(_FLUID_DAMAGE_PER_SEC, over_threshold * 0.2)
	var tick_dmg := int(roundf(dps * _FLUID_DAMAGE_TICK_SEC))
	if tick_dmg > 0:
		apply_damage(tick_dmg)


func _sample_web_overlap() -> void:
	var sensor: Area2D = get_node_or_null(^"%WebSensor") as Area2D
	if not is_instance_valid(sensor):
		_is_in_web = false
		return
	for area in sensor.get_overlapping_areas():
		if area is WebTile:
			_is_in_web = true
			return
	_is_in_web = false


func _unhandled_input(event: InputEvent) -> void:
	if G.level.has_won or G.level.has_finished:
		return
	if event.is_action_pressed("select_prev_frequency"):
		select_prev_frequency()
	elif event.is_action_pressed("select_next_frequency"):
		select_next_frequency()
	elif event.is_action_pressed("ability"):
		_emit_echo_pulse()


func _emit_echo_pulse() -> void:
	if not is_instance_valid(G.echo):
		return
	if _echo_cooldown_sec > 0.0:
		return
	if not can_select(current_frequency):
		# Selection landed on an empty color (shouldn't normally
		# happen — the scroll skips empties — but defend against
		# stale cursor state).
		return
	var is_none := current_frequency == Frequency.Type.NONE
	if not is_none:
		consume_juice(current_frequency, 1)
	_current_cooldown_duration = (
			_NONE_ECHO_COOLDOWN_SEC if is_none else _ECHO_COOLDOWN_SEC)
	_echo_cooldown_sec = _current_cooldown_duration
	G.echo.emit_pulse(global_position, current_frequency)
	if not is_none:
		_auto_advance_if_empty()


## Kept for compatibility with any external callers; the feature
## intentionally drives `current_frequency` via Q/E + auto-advance
## only. Bug `_consume` no longer calls this.
func set_frequency(freq: int) -> void:
	current_frequency = freq
	frequency_selection_changed.emit(current_frequency)


# ---- Juice pool API -------------------------------------------------------

func get_juice(freq: int) -> int:
	return int(_juice.get(freq, 0))


func add_juice(freq: int, amount: int) -> int:
	if not _juice.has(freq):
		return 0
	var before: int = _juice[freq]
	var after: int = mini(MAX_JUICE, before + amount)
	if after == before:
		return 0
	_juice[freq] = after
	juice_changed.emit(freq, after)
	return after - before


func consume_juice(freq: int, amount: int) -> bool:
	if freq == Frequency.Type.NONE:
		return true
	if not _juice.has(freq):
		return false
	if int(_juice[freq]) < amount:
		return false
	_juice[freq] = int(_juice[freq]) - amount
	juice_changed.emit(freq, _juice[freq])
	return true


func has_juice(freq: int) -> bool:
	if freq == Frequency.Type.NONE:
		return true
	return int(_juice.get(freq, 0)) > 0


func can_select(freq: int) -> bool:
	return has_juice(freq)


# ---- Selection cursor -----------------------------------------------------

func select_next_frequency() -> void:
	_step_selection(1)


func select_prev_frequency() -> void:
	_step_selection(-1)


func _step_selection(direction: int) -> void:
	var order := _SELECTABLE_ORDER
	var start_index := order.find(current_frequency)
	if start_index < 0:
		start_index = 0
	var count := order.size()
	for i in range(1, count + 1):
		var idx := (start_index + direction * i) % count
		if idx < 0:
			idx += count
		var candidate: int = order[idx]
		if can_select(candidate):
			if candidate != current_frequency:
				current_frequency = candidate
				frequency_selection_changed.emit(current_frequency)
			return


func _auto_advance_if_empty() -> void:
	if can_select(current_frequency):
		return
	# Fall forward; NONE is always selectable so this terminates.
	select_next_frequency()


# ---- Cooldown read-outs for HUD -------------------------------------------

## 0.0 = just fired, 1.0 = ready to fire.
func get_cooldown_fraction() -> float:
	if _current_cooldown_duration <= 0.0:
		return 1.0
	var remaining := clampf(_echo_cooldown_sec, 0.0, _current_cooldown_duration)
	return 1.0 - remaining / _current_cooldown_duration


func get_current_cooldown_duration() -> float:
	return _current_cooldown_duration


func apply_damage(amount: int) -> void:
	if _invincibility_remaining_sec > 0.0:
		return
	%PlayerHealth.apply_damage(amount)
	if not %PlayerHealth.is_dead():
		_invincibility_remaining_sec = _INVINCIBILITY_SEC
		_blink_accum_sec = 0.0


func apply_heal(amount: int) -> void:
	%PlayerHealth.apply_heal(amount)


func _on_died() -> void:
	if is_instance_valid(G.level):
		G.level.game_over()


func _update_actions() -> void:
	super._update_actions()


func _process_animation() -> void:
	super._process_animation()


func play_sound(sound_name: String, force_restart := false) -> void:
	if G.level.has_won:
		return
	G.audio.play_player_sound(sound_name, force_restart)
