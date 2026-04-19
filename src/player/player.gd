class_name Player
extends Character


## Horizontal speed multiplier applied while any WebTile overlaps the
## player's WebSensor.
const _WEB_SPEED_MULTIPLIER := 0.25

## Damage per second applied while the player overlaps any LIQUID
## terrain, regardless of flow. Flowing water above the speed
## threshold ramps damage above this base rate.
const _WATER_BASE_DAMAGE_PER_SEC := 10.0

## Fluid velocity magnitude (px/sec) above which fluid damage scales
## up past the base water rate. Below this, the player still takes
## base water damage but without a flow bonus.
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

## Minimum interval between echo pulses (3 / second) for colored pulses.
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

## Peak body-tint strength at the start of a damage/death flash. Both
## hit and death animations tween this down to zero.
const _DAMAGE_FLASH_PEAK := 0.85

## Damage-hit pulse — short, farther, thicker, translucent outline
## that snaps outward on every non-fatal hit.
const _DAMAGE_FLASH_DURATION_SEC := 0.25
const _DAMAGE_PULSE_DURATION_SEC := 0.3
const _DAMAGE_PULSE_MAX_RADIUS_PX := 10.0
const _DAMAGE_PULSE_WIDTH_PX := 3.5
const _DAMAGE_PULSE_ALPHA := 0.7

## Death pulse — same shape, bigger and slower, plays once on the
## fatal hit. Final radius is bounded by how much transparent border
## the sprite's frame quad has; the kittenbaticorn frames clip past
## ~20 px, which still leaves a dramatic halo.
const _DEATH_FLASH_DURATION_SEC := 0.55
const _DEATH_PULSE_DURATION_SEC := 0.8
const _DEATH_PULSE_MAX_RADIUS_PX := 18.0
const _DEATH_PULSE_WIDTH_PX := 5.0
const _DEATH_PULSE_ALPHA := 0.9

const _DAMAGE_FLASH_COLOR := Color(1.0, 0.2, 0.2)
const _DAMAGE_PULSE_COLOR := Color(1.0, 0.35, 0.35)

## Delay between the player's "death" sound and the follow-up
## "failure" cadence. Synced with the destination win cadence offset
## so both fail/success feedback have the same rhythm.
const _FAILURE_CADENCE_DELAY_SEC := 0.9

## Post-jump stuck detection: if `move_and_slide` produced less total
## displacement than this after the jump impulse, we consider the
## player wedged.
const _JUMP_STUCK_DISPLACEMENT_THRESHOLD_PX := 1.0

## How far out (in cell-size increments) we search for the nearest
## open space when unsticking a wedged jump.
const _UNSTICK_MAX_RING_RADIUS := 8

## AABB-shrink used by `_aabb_overlaps_collidable` so that normal
## resting contact with a floor/wall (collision-resolution puts us
## flush against the cell) doesn't count as overlap.
const _AABB_OVERLAP_EPSILON_PX := 0.5

## Two airborne ceiling touches within this window trigger the
## idle-ceiling-attached state.
const _CEILING_BONK_DOUBLE_THRESHOLD_SEC := 0.4

## After entering idle-ceiling-attached, detach inputs are ignored for
## this long so held inputs or coincident events don't immediately slip
## the player back off the ceiling.
const _POST_ATTACH_DETACH_LOCKOUT_SEC := 0.6

## Lockout applied at spawn, a touch longer than the normal post-attach
## lockout so the title screen/camera can settle before the player can
## take control.
const _SPAWN_DETACH_LOCKOUT_SEC := 0.8

## Extra downward y offset applied to the animator's AnimatedSprite2D
## while attached-idle, so the sprite reads as kissing the ceiling
## instead of floating in the gap.
const _ATTACHED_IDLE_SPRITE_Y_OFFSET_PX := 1.0

## Downward spawn offset from `%PlayerSpawnPoint.global_position`. The
## player spawns 15 px below the marker so the spawn marker can sit
## right at the ceiling line the player hangs from.
const _CEILING_SPAWN_Y_OFFSET_PX := 15.0


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
## Current damage-hit flash / outline-pulse tween, if any. Killed
## on each subsequent hit so overlapping hits restart the animation.
var _damage_hit_tween: Tween = null
var _pre_step_velocity_y := 0.0
## Set true on the frame a jump is triggered so that we check, on the
## following frame (once `move_and_slide` has had a chance to apply
## the jump impulse), whether the player actually moved.
var _check_jump_displacement_next_step := false

## True while the player is pinned in the idle-ceiling-attached state.
## Gates the normal physics/animation pipeline in `_physics_process`
## and the detach-input poll.
var _is_attached_idle := false

## Seconds remaining before detach inputs are honored. Ticked each
## physics step.
var _detach_lockout_remaining_sec := 0.0

## Scaled play time of the most recent airborne ceiling touch.
## `-INF` when no recent bonk is being tracked. Reset when the player
## lands on a non-air surface so bonks don't chain across long gaps.
var _last_ceiling_bonk_time_sec := -INF

## True from spawn until the FIRST detach of the run. While true the
## player is impervious to damage and the player-layer bit is cleared
## so bugs/enemies can't detect them.
var _is_in_spawn_grace := false

## Tracks whether the 1 px sprite offset is currently applied, so
## repeated attach/detach cycles can't compound the offset.
var _attached_sprite_offset_applied := false

## Previous-frame snapshot of `surface_state.is_touching_ceiling`. The
## scaffolder clears `just_touched_ceiling` mid-frame (in
## `clear_just_changed_state`) before our post-super bonk check can
## read it, so we reconstruct the transition ourselves.
var _was_touching_ceiling := false

## Per-frequency juice pool. Populated in `_ready()`; only the four
## gameplay frequencies (RED/GREEN/BLUE/YELLOW) are keys.
var _juice: Dictionary = {}


var half_size := Vector2.INF

## Player's currently-selected echolocation frequency. Driven by
## Q/E (or auto-advance when the active color runs dry). NONE is
## "stipple-only" — no juice cost, half-rate cooldown, reveals the
## level but interacts with no tiles or enemies.
var current_frequency: int = Frequency.Type.NONE

## Read-only view of the idle-ceiling-attached flag for external
## callers (e.g. future AI that wants to skip targeting the player
## during spawn grace).
var is_attached_idle: bool:
	get: return _is_attached_idle


func _ready() -> void:
	super._ready()
	half_size = Geometry.calculate_half_width_height(
		collision_shape.shape,
		false)
	var starting_juice: int = (
			MAX_JUICE
			if G.settings.start_with_full_juice
			else 0)
	_juice = {
		Frequency.Type.RED: starting_juice,
		Frequency.Type.GREEN: starting_juice,
		Frequency.Type.BLUE: starting_juice,
		Frequency.Type.YELLOW: starting_juice,
	}
	for freq in _juice:
		juice_changed.emit(freq, _juice[freq])
	current_frequency = Frequency.Type.NONE
	%PlayerHealth.died.connect(_on_died)


func destroy() -> void:
	queue_free()


## Debug overlay comparing visual vs physics terrain around the player.
## - Magenta line: top of the first collidable cell below the body.
## - Cyan cell outlines: cells with type != NONE (visually drawn).
## - Green cell outlines: cells that are collidable (physics-solid).
## A cyan cell that is NOT wrapped in green = visible-but-not-collidable
## (e.g. LIQUID type) — the most likely source of a perceived "sink".
func _draw() -> void:
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	var cs: float = G.terrain.settings.cell_size_px
	# Magenta: first collidable cell top below the body origin.
	const _MAX_STEPS := 8
	for step in _MAX_STEPS:
		var probe_y: float = global_position.y + step * cs
		if G.terrain.is_cell_collidable(Vector2(global_position.x, probe_y)):
			var cell_top_world: float = floorf(probe_y / cs) * cs
			var line_y: float = cell_top_world - global_position.y
			draw_line(
					Vector2(-64.0, line_y),
					Vector2(64.0, line_y),
					Color(1, 0, 1, 0.9),
					1.0)
			break
	# Outline all cells within a window around the body.
	const _GRID_RADIUS := 20
	var player_cx: int = int(floorf(global_position.x / cs))
	var player_cy: int = int(floorf(global_position.y / cs))
	for dy in range(-_GRID_RADIUS, _GRID_RADIUS + 1):
		for dx in range(-_GRID_RADIUS, _GRID_RADIUS + 1):
			var cx: int = player_cx + dx
			var cy: int = player_cy + dy
			var cell_world_tl := Vector2(cx * cs, cy * cs)
			var cell_center := cell_world_tl + Vector2(cs * 0.5, cs * 0.5)
			var non_empty: bool = G.terrain.is_cell_non_empty(cell_center)
			var collidable: bool = G.terrain.is_cell_collidable(cell_center)
			if not non_empty and not collidable:
				continue
			var rect_tl_local: Vector2 = cell_world_tl - global_position
			var color: Color
			if non_empty and collidable:
				color = Color(0, 1, 0, 0.5)
			elif non_empty:
				color = Color(0, 1, 1, 0.8)
			else:
				color = Color(1, 0, 0, 0.8)
			draw_rect(
					Rect2(rect_tl_local, Vector2(cs, cs)),
					color,
					false,
					1.0)


func _process(delta: float) -> void:
	super._process(delta)
	queue_redraw()
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

	_detach_lockout_remaining_sec = maxf(
			0.0, _detach_lockout_remaining_sec - delta)

	if _is_attached_idle:
		velocity = Vector2.ZERO
		animator.play("idle_ceiling")
		if _wants_to_detach():
			_exit_attached_idle()
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
	var pos_before_super := global_position
	super._physics_process(delta)
	if _check_jump_displacement_next_step:
		_check_jump_displacement_next_step = false
		var displacement := global_position - pos_before_super
		if (displacement.length_squared()
				< _JUMP_STUCK_DISPLACEMENT_THRESHOLD_PX
				* _JUMP_STUCK_DISPLACEMENT_THRESHOLD_PX):
			_unstick_to_nearest_open_space()
	if just_triggered_jump:
		_check_jump_displacement_next_step = true
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
	_snap_to_terrain_surface()
	_unstick_from_terrain()
	_check_ceiling_bonk_attach()


## Workaround for a Godot 2D physics issue where `CharacterBody2D`'s
## depenetration against our per-cell `ConvexPolygonShape2D` terrain
## lets the capsule settle with its center on the surface instead of
## its bottom. Result: the capsule sinks into floors by half its
## height and leaves a matching gap below ceilings. Manually snap the
## body's origin to the first collidable cell top at the player's x
## when the body is inside terrain. No-op when the capsule is already
## above the surface (normal airborne / jumping state).
func _snap_to_terrain_surface() -> void:
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	var cs: float = G.terrain.settings.cell_size_px
	# Walk downward from the body origin in cell steps and return the
	# top of the first collidable cell we hit. If the body is already
	# inside a solid cell, the first iteration matches and we snap
	# straight up to its top.
	var x := global_position.x
	var start_y := global_position.y
	const _MAX_STEPS := 4
	for step in _MAX_STEPS:
		var probe_y := start_y + step * cs
		if G.terrain.is_cell_collidable(Vector2(x, probe_y)):
			var cell_top := floorf(probe_y / cs) * cs
			print("snap-check: y=", global_position.y,
					" step=", step, " probe=", probe_y,
					" cell_top=", cell_top,
					" will_snap=", global_position.y > cell_top)
			# Only snap upward: don't pull the player down onto terrain
			# they weren't previously touching.
			if global_position.y > cell_top:
				global_position.y = cell_top
				if velocity.y > 0.0:
					velocity.y = 0.0
			return
	print("snap-check: y=", start_y,
			" no collidable cell below within ",
			_MAX_STEPS * cs, " px")


## Continuous stuck check. Conservative: only triggers when a
## collidable cell is fully embedded in the player's AABB. This
## ignores the normal few-pixel penetration of CharacterBody2D
## resting on a floor, only firing when sand/solid has truly filled
## a chunk of the player's interior. Backs up FallingCell's one-
## shot eviction for cases where terrain FLOW moves cells in C++
## without going through the FallingCell paint path. Searches in 2D
## cell-aligned rings for the closest non-embedded position.
func _unstick_from_terrain() -> void:
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	var cs: float = G.terrain.settings.cell_size_px
	var hh: float = half_size.y if half_size.y > 0.0 else cs * 0.5
	var hw: float = half_size.x if half_size.x > 0.0 else cs * 0.5

	if not _is_cell_fully_embedded(global_position, hh, hw, cs):
		return

	for r in range(1, _UNSTICK_MAX_RING_RADIUS + 1):
		var has_best := false
		var best_pos := Vector2.ZERO
		var best_dist_sq := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var try_pos: Vector2 = (
						global_position
						+ Vector2(dx * cs, dy * cs))
				if _is_cell_fully_embedded(try_pos, hh, hw, cs):
					continue
				var d := try_pos.distance_squared_to(global_position)
				if d < best_dist_sq:
					best_dist_sq = d
					best_pos = try_pos
					has_best = true
		if has_best:
			global_position = best_pos
			velocity = Vector2.ZERO
			return


## True iff any collidable cell fits entirely inside the player's
## AABB at `center` (shrunk by a small x-inset so glancing side
## contact doesn't count). Normal resting contact produces only a
## few pixels of overlap and doesn't trigger.
func _is_cell_fully_embedded(
		center: Vector2, hh: float, hw: float, cs: float) -> bool:
	const _X_INSET := 1.0
	var p_left := center.x - hw + _X_INSET
	var p_right := center.x + hw - _X_INSET
	var p_top := center.y - hh
	var p_bottom := center.y + hh

	var first_cx := int(floor(p_left / cs))
	var last_cx := int(floor(p_right / cs))
	var first_cy := int(floor(p_top / cs))
	var last_cy := int(floor(p_bottom / cs))

	for cy in range(first_cy, last_cy + 1):
		var cell_top := cy * cs
		var cell_bottom := cell_top + cs
		if cell_top < p_top or cell_bottom > p_bottom:
			continue
		for cx in range(first_cx, last_cx + 1):
			var cell_left := cx * cs
			var cell_right := cell_left + cs
			# Require some x overlap beyond a single-pixel edge
			# contact; the inset on p_left / p_right already does
			# most of the work here.
			if cell_right <= p_left or cell_left >= p_right:
				continue
			var ccx := cell_left + cs * 0.5
			var ccy := cell_top + cs * 0.5
			if G.terrain.is_cell_collidable(Vector2(ccx, ccy)):
				return true
	return false


func _sample_water_overlap() -> void:
	_is_in_water = false
	if not is_instance_valid(G.terrain):
		return
	if G.terrain.is_cell_type_at(
			global_position, Frequency.Type.LIQUID):
		_is_in_water = true


func _apply_fluid_damage(delta: float) -> void:
	if not _is_in_water or not is_instance_valid(G.terrain):
		_fluid_damage_accum_sec = 0.0
		return
	_fluid_damage_accum_sec += delta
	if _fluid_damage_accum_sec < _FLUID_DAMAGE_TICK_SEC:
		return
	_fluid_damage_accum_sec -= _FLUID_DAMAGE_TICK_SEC
	var fluid_vel: Vector2 = G.terrain.sample_fluid_velocity(global_position)
	var speed := fluid_vel.length()
	var over_threshold := maxf(0.0, speed - _FLUID_DAMAGE_SPEED_THRESHOLD)
	var dps := maxf(
			_WATER_BASE_DAMAGE_PER_SEC,
			minf(_FLUID_DAMAGE_PER_SEC, over_threshold * 0.2))
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


## If the jump impulse failed to move the player AND their collision
## box currently overlaps collidable cells, teleport to the nearest
## cell-aligned offset where the box fits. Velocity is zeroed so the
## carry-over jump impulse doesn't push them right back into terrain.
func _unstick_to_nearest_open_space() -> void:
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	var cs: float = G.terrain.settings.cell_size_px
	var hh: float = half_size.y if half_size.y > 0.0 else cs * 0.5
	var hw: float = half_size.x if half_size.x > 0.0 else cs * 0.5
	var aabb_offset: Vector2 = collision_shape.position
	if not _aabb_overlaps_collidable(
			global_position + aabb_offset, hh, hw, cs):
		# We didn't move, but we're not overlapping terrain — likely
		# just a ceiling-kiss or a jump into a tight but walkable
		# space. Leave us alone.
		return
	for r in range(1, _UNSTICK_MAX_RING_RADIUS + 1):
		var has_best := false
		var best_pos := Vector2.ZERO
		var best_dist_sq := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var try_pos: Vector2 = (
						global_position
						+ Vector2(dx * cs, dy * cs))
				if _aabb_overlaps_collidable(
						try_pos + aabb_offset, hh, hw, cs):
					continue
				var d := try_pos.distance_squared_to(global_position)
				if d < best_dist_sq:
					best_dist_sq = d
					best_pos = try_pos
					has_best = true
		if has_best:
			global_position = best_pos
			velocity = Vector2.ZERO
			return


## True iff the player's AABB (centered at `center`, shrunk by
## `_AABB_OVERLAP_EPSILON_PX` on every side) overlaps any collidable
## cell. The shrink ignores grazing contact.
func _aabb_overlaps_collidable(
		center: Vector2, hh: float, hw: float, cs: float) -> bool:
	var p_left := center.x - hw + _AABB_OVERLAP_EPSILON_PX
	var p_right := center.x + hw - _AABB_OVERLAP_EPSILON_PX
	var p_top := center.y - hh + _AABB_OVERLAP_EPSILON_PX
	var p_bottom := center.y + hh - _AABB_OVERLAP_EPSILON_PX
	if p_left >= p_right or p_top >= p_bottom:
		return false
	var first_cx := int(floor(p_left / cs))
	var last_cx := int(floor(p_right / cs))
	var first_cy := int(floor(p_top / cs))
	var last_cy := int(floor(p_bottom / cs))
	for cy in range(first_cy, last_cy + 1):
		for cx in range(first_cx, last_cx + 1):
			var ccx := cx * cs + cs * 0.5
			var ccy := cy * cs + cs * 0.5
			if G.terrain.is_cell_collidable(Vector2(ccx, ccy)):
				return true
	return false


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
	play_sound("echo", true)
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
	if _is_in_spawn_grace:
		return
	if _invincibility_remaining_sec > 0.0:
		return
	if %PlayerHealth.is_dead():
		return
	%PlayerHealth.apply_damage(amount)
	if %PlayerHealth.is_dead():
		_play_damage_pulse_death()
	else:
		_play_damage_pulse_hit()
		play_sound("damage", true)
		_invincibility_remaining_sec = _INVINCIBILITY_SEC
		_blink_accum_sec = 0.0


func _play_damage_pulse_hit() -> void:
	_play_damage_pulse(
			_DAMAGE_FLASH_COLOR,
			_DAMAGE_PULSE_COLOR,
			_DAMAGE_FLASH_DURATION_SEC,
			_DAMAGE_PULSE_DURATION_SEC,
			_DAMAGE_PULSE_MAX_RADIUS_PX,
			_DAMAGE_PULSE_WIDTH_PX,
			_DAMAGE_PULSE_ALPHA)


func _play_damage_pulse_death() -> void:
	_play_damage_pulse(
			_DAMAGE_FLASH_COLOR,
			_DAMAGE_PULSE_COLOR,
			_DEATH_FLASH_DURATION_SEC,
			_DEATH_PULSE_DURATION_SEC,
			_DEATH_PULSE_MAX_RADIUS_PX,
			_DEATH_PULSE_WIDTH_PX,
			_DEATH_PULSE_ALPHA)


## Kick off the body flash + outward outline pulse on the sprite's
## ShaderMaterial. The material lives on the PlayerAnimator's
## AnimatedSprite2D and exposes `flash_strength`, `pulse_radius_px`,
## `pulse_alpha`, and `pulse_width_px` uniforms. Re-hitting cancels
## any in-flight tween so the animation restarts cleanly.
func _play_damage_pulse(
		flash_color: Color,
		pulse_color: Color,
		flash_duration: float,
		pulse_duration: float,
		max_radius_px: float,
		width_px: float,
		alpha: float) -> void:
	if animator == null:
		return
	var sprite: AnimatedSprite2D = animator.animated_sprite
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	if _damage_hit_tween != null and _damage_hit_tween.is_valid():
		_damage_hit_tween.kill()
	mat.set_shader_parameter("flash_color", flash_color)
	mat.set_shader_parameter("pulse_color", pulse_color)
	mat.set_shader_parameter("flash_strength", _DAMAGE_FLASH_PEAK)
	mat.set_shader_parameter("pulse_width_px", width_px)
	mat.set_shader_parameter("pulse_radius_px", 1.0)
	mat.set_shader_parameter("pulse_alpha", alpha)
	_damage_hit_tween = create_tween()
	_damage_hit_tween.set_parallel(true)
	_damage_hit_tween.tween_property(
			mat, "shader_parameter/flash_strength",
			0.0, flash_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_damage_hit_tween.tween_property(
			mat, "shader_parameter/pulse_radius_px",
			max_radius_px, pulse_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_damage_hit_tween.tween_property(
			mat, "shader_parameter/pulse_alpha",
			0.0, pulse_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func apply_heal(amount: int) -> void:
	%PlayerHealth.apply_heal(amount)


func _on_died() -> void:
	# Halt input/physics on this frame so no stray tick fires in the
	# window between now and queue_free taking effect at end-of-frame.
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	# Route death + trailing failure cadence through AudioMain so the
	# cadence outlives queue_free on this node.
	if is_instance_valid(G.audio):
		G.audio.play_player_sound("death", true)
		G.audio.play_player_sound_delayed("failure", _FAILURE_CADENCE_DELAY_SEC)
	if is_instance_valid(G.level):
		G.level.game_over()
	destroy()


func _update_actions() -> void:
	super._update_actions()


func _process_animation() -> void:
	super._process_animation()


func play_sound(sound_name: String, force_restart := false) -> void:
	if G.level.has_won:
		return
	G.audio.play_player_sound(sound_name, force_restart)


## Enters the idle-ceiling-attached state: zeroes velocity, resets jump
## state, applies the 1 px sprite offset, and starts the idle_ceiling
## animation. `lockout_sec` is how long detach inputs are ignored.
func _enter_attached_idle(lockout_sec: float) -> void:
	_is_attached_idle = true
	_detach_lockout_remaining_sec = lockout_sec
	_last_ceiling_bonk_time_sec = -INF
	velocity = Vector2.ZERO
	jump_count = 0
	is_rising_from_jump = false
	just_triggered_jump = false
	if not _attached_sprite_offset_applied:
		animator.animated_sprite.position.y += (
				_ATTACHED_IDLE_SPRITE_Y_OFFSET_PX)
		_attached_sprite_offset_applied = true
	animator.play("idle_ceiling")


## Exits the idle-ceiling-attached state. Reverts the sprite offset and,
## if this was the spawn-grace attachment, clears grace and restores
## the player-layer bit so bugs/enemies can detect the player again.
func _exit_attached_idle() -> void:
	_is_attached_idle = false
	play_sound("detach", true)
	if _attached_sprite_offset_applied:
		animator.animated_sprite.position.y -= (
				_ATTACHED_IDLE_SPRITE_Y_OFFSET_PX)
		_attached_sprite_offset_applied = false
	if _is_in_spawn_grace:
		_is_in_spawn_grace = false
		# Godot's helper is 1-indexed: value 4 flips bit index 3 (= 8).
		set_collision_layer_value(4, true)


## Called after `super._physics_process`. The scaffolder clears
## `just_touched_ceiling` mid-super before we get here, so we
## reconstruct the rising-edge transition ourselves from
## `_was_touching_ceiling`. Two airborne ceiling touches within the
## double-bonk window trigger attachment. Outside of AIR, clears the
## stamp so stale bonks don't chain.
func _check_ceiling_bonk_attach() -> void:
	if _is_attached_idle:
		return
	var is_touching_ceiling := surface_state.is_touching_ceiling
	var just_touched := is_touching_ceiling and not _was_touching_ceiling
	_was_touching_ceiling = is_touching_ceiling
	if surface_state.surface_type != SurfaceType.AIR:
		_last_ceiling_bonk_time_sec = -INF
		return
	if not just_touched:
		return
	var now := G.time.get_scaled_play_time()
	if now - _last_ceiling_bonk_time_sec \
			<= _CEILING_BONK_DOUBLE_THRESHOLD_SEC:
		_enter_attached_idle(_POST_ATTACH_DETACH_LOCKOUT_SEC)
	else:
		_last_ceiling_bonk_time_sec = now


## Polls raw input for any direction-press or a jump just-press. Used
## only while attached-idle. `ability` (echo) is deliberately excluded.
func _wants_to_detach() -> bool:
	if _detach_lockout_remaining_sec > 0.0:
		return false
	return (
			Input.is_action_pressed("move_up")
			or Input.is_action_pressed("move_down")
			or Input.is_action_pressed("move_left")
			or Input.is_action_pressed("move_right")
			or Input.is_action_just_pressed("jump"))


## Entry point used by the level right after spawn. Nudges the player
## down from the spawn marker, marks them as in spawn grace (impervious
## + imperceptible) and drops the player-layer bit, then enters
## attached-idle with the spawn lockout.
func _enter_attached_idle_at_spawn() -> void:
	global_position.y += _CEILING_SPAWN_Y_OFFSET_PX
	_is_in_spawn_grace = true
	set_collision_layer_value(4, false)
	_enter_attached_idle(_SPAWN_DETACH_LOCKOUT_SEC)
