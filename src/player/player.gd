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

## Scale factors applied to the coin-pickup PulseRing wash when it's
## piggybacked on an echo emit. 2/3 opacity + 2/3 radius keeps the
## feedback readable without overpowering the echolocation pulse
## that fires in the same frame.
const _ECHO_PULSE_RING_OPACITY_SCALE := 2.0 / 3.0
const _ECHO_PULSE_RING_SIZE_SCALE := 2.0 / 3.0

## Trailing inner ring spawned after the primary pulse ring on each
## echo. Smaller, more transparent, and slightly delayed so it reads
## as a second pulse "behind" the first.
const _ECHO_PULSE_RING_TRAIL_OPACITY_SCALE := 1.0 / 3.0
const _ECHO_PULSE_RING_TRAIL_SIZE_SCALE := 1.0 / 3.0
const _ECHO_PULSE_RING_TRAIL_DELAY_SEC := 0.04

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
## that snaps outward on every non-fatal hit. Flash duration is held
## roughly through the full invincibility grace so the red-tint read
## is louder while the player is still vulnerable-adjacent.
const _DAMAGE_FLASH_DURATION_SEC := 0.75
const _DAMAGE_PULSE_DURATION_SEC := 0.3
const _DAMAGE_PULSE_MAX_RADIUS_PX := 10.0
const _DAMAGE_PULSE_WIDTH_PX := 5.0
const _DAMAGE_PULSE_ALPHA := 0.7

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

## After detaching from the ceiling, the next re-attach is blocked
## for this long. The first bonk after that cooldown clears will
## attach immediately — no double-bonk gate — so the input model is
## "jump, bonk, hang" rather than "jump, bonk, bonk, hang".
const _REATTACH_COOLDOWN_SEC := 0.8

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

## Player's frequency-outline width (in atlas/game px). 1 = hugging
## 1-px halo around the sprite body. Only active when a colored
## frequency is selected; NONE zeroes this out.
const _FREQUENCY_OUTLINE_WIDTH_PX := 1.0
## Lightening applied to the pure palette color before pushing it
## as the outline color — needed so the outline sits outside the
## composite's 0.08 palette-diff threshold (same rationale as on
## enemies; see `Enemy._OUTLINE_COLOR_LIGHTEN_AMOUNT`).
const _FREQUENCY_OUTLINE_LIGHTEN_AMOUNT := 0.25
## Alpha applied to the lightened color before it's pushed. Keeps
## the player's outline intentionally faint (partially transparent)
## so it reads as a frequency tint, not a hard silhouette ring.
const _FREQUENCY_OUTLINE_ALPHA := 0.5


signal juice_changed(frequency: int, new_value: int)
signal frequency_selection_changed(frequency: int)


var _is_in_web := false
var _is_in_water := false
## Last frame's `_is_in_water` value, used to detect the rising
## edge so a splash spawns only on the frame the player crosses
## into water (not every frame they're submerged).
var _was_in_water := false
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

## Seconds remaining on the post-detach cooldown. While > 0, a
## ceiling bonk will NOT re-trigger the attached-idle pose. Ticked
## each physics step. Bumped to `_REATTACH_COOLDOWN_SEC` in
## `_exit_attached_idle` so the input sequence is
## detach → fly → bonk → hang, with a breathing window between
## detach and the next hang.
var _reattach_cooldown_remaining_sec := 0.0

## True from spawn until the FIRST detach of the run. While true the
## player is impervious to damage and the player-layer bit is cleared
## so bugs/enemies can't detect them.
var _is_in_spawn_grace := false
## Set the first time the player fires a GREEN echo. The intro
## overlay (Title + Controls) is held visible until then, so the
## controls hint stays on screen across the spawn detach + first
## few frames of free movement until the player actually uses the
## core mechanic.
var _has_fired_green_echo: bool = false

## True from `enter_win_pose()` onward. Mirrors spawn grace — the
## player-layer bit is cleared and damage is ignored — but without
## the attached-idle animation. `has_won` in `_physics_process` and
## `_unhandled_input` already halts movement/input, so this flag
## only has to gate damage and enemy perception.
var _is_in_win_pose := false

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

## Read-only view of the initial-spawn grace flag. True from spawn
## until the player's first detach; enemies skip proximity
## perception while this is true so they don't pre-aggro while the
## player is still pinned to the ceiling.
var is_in_spawn_grace: bool:
	get: return _is_in_spawn_grace

## Read-only view of the post-win pose flag. True from `win()` until
## the level resets; enemies skip proximity perception and damage
## routing skips the player while this is true.
var is_in_win_pose: bool:
	get: return _is_in_win_pose

## True whenever the player is in either the spawn-grace pose or
## the post-win pose. External AI (enemies) gates proximity
## perception on this so they don't pursue a non-interactive player.
var is_non_interactive: bool:
	get: return _is_in_spawn_grace or _is_in_win_pose


func _ready() -> void:
	super._ready()
	half_size = Geometry.calculate_half_width_height(
		collision_shape.shape,
		false)
	var starting_juice: int = (
			MAX_JUICE
			if G.settings.start_with_full_juice
			else 0)
	# Green starts with a 1/4-bar floor so the player has at least
	# one usable colored echo from spawn (and can therefore default
	# to GREEN as the selected frequency below). `start_with_full_juice`
	# still wins via the maxi.
	var green_floor: int = int(ceil(MAX_JUICE / 4.0))
	_juice = {
		Frequency.Type.RED: starting_juice,
		Frequency.Type.GREEN: maxi(starting_juice, green_floor),
		Frequency.Type.BLUE: starting_juice,
		Frequency.Type.YELLOW: starting_juice,
	}
	for freq in _juice:
		juice_changed.emit(freq, _juice[freq])
	current_frequency = Frequency.Type.NONE
	%PlayerHealth.died.connect(_on_died)
	frequency_selection_changed.connect(
			_on_frequency_selection_changed_for_outline)
	_apply_frequency_outline()


func _on_frequency_selection_changed_for_outline(_freq: int) -> void:
	_apply_frequency_outline()


## Pushes the current frequency color into the sprite shader's
## `outline_*` uniforms. With NONE selected, the outline is
## disabled (width 0). Otherwise the outline renders in a
## partially transparent lightened-freq tint so the player reads
## as "carrying" the selected frequency without looking like a
## hard silhouette.
func _apply_frequency_outline() -> void:
	if animator == null:
		return
	var sprite: AnimatedSprite2D = animator.animated_sprite
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	# Dead players render no outline. `%PlayerHealth.is_dead()` goes
	# true the moment fatal damage lands and stays true for the
	# game-over delay, so gating here keeps the outline off for the
	# whole corpse window.
	if (has_node("%PlayerHealth")
			and (%PlayerHealth as Node).has_method("is_dead")
			and %PlayerHealth.is_dead()):
		mat.set_shader_parameter("outline_width_px", 0.0)
		return
	if current_frequency == Frequency.Type.NONE:
		mat.set_shader_parameter("outline_width_px", 0.0)
		return
	var tint: Color = (Frequency.color_of(current_frequency)
			.lightened(_FREQUENCY_OUTLINE_LIGHTEN_AMOUNT))
	tint.a = _FREQUENCY_OUTLINE_ALPHA
	mat.set_shader_parameter("outline_color", tint)
	mat.set_shader_parameter(
			"outline_width_px", _FREQUENCY_OUTLINE_WIDTH_PX)


func _clear_frequency_outline() -> void:
	if animator == null:
		return
	var sprite: AnimatedSprite2D = animator.animated_sprite
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("outline_width_px", 0.0)


func destroy() -> void:
	queue_free()


## Debug overlay comparing visual vs physics terrain around the player.
## - Magenta line: top of the first collidable cell below the body.
## - Cyan cell outlines: cells with type != NONE (visually drawn).
## - Green cell outlines: cells that are collidable (physics-solid).
## A cyan cell that is NOT wrapped in green = visible-but-not-collidable
## (e.g. LIQUID type) — the most likely source of a perceived "sink".
func _draw() -> void:
	if not G.settings.draw_annotations:
		return
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
	if G.settings.draw_annotations:
		queue_redraw()
	if _echo_cooldown_sec > 0.0:
		_echo_cooldown_sec = maxf(0.0, _echo_cooldown_sec - delta)
	_tick_invincibility(delta)
	_ensure_tile_destroyed_connected()


## Lazy-connect `G.terrain.tile_destroyed` so the player can detach
## when the ceiling cell they're hanging from gets carved out. Retries
## each frame until `G.terrain` exists (level load order: the player
## spawns before the terrain world is fully wired in some cases).
func _ensure_tile_destroyed_connected() -> void:
	if not is_instance_valid(G.terrain):
		return
	if not G.terrain.tile_destroyed.is_connected(
			_on_tile_destroyed_while_attached):
		G.terrain.tile_destroyed.connect(
				_on_tile_destroyed_while_attached)


## Detaches the player when a cell near their head — i.e. the ceiling
## cell they were clinging to — is destroyed. Uses a radius slightly
## larger than one cell so straddle cases (player body spanning the
## edge between two ceiling cells) still trigger.
func _on_tile_destroyed_while_attached(
		world_pos: Vector2, _type: int) -> void:
	if not _is_attached_idle:
		return
	var cs: float = 8.0
	if is_instance_valid(G.terrain) and G.terrain.settings != null:
		cs = G.terrain.settings.cell_size_px
	var head_pos := global_position - Vector2(0.0, half_size.y)
	var threshold := cs * 1.5
	if head_pos.distance_squared_to(world_pos) <= threshold * threshold:
		_exit_attached_idle()


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

	if (not is_player_control_active
			and is_instance_valid(G.hud)
			and G.hud.is_blackout_hidden):
		is_player_control_active = true

	_detach_lockout_remaining_sec = maxf(
			0.0, _detach_lockout_remaining_sec - delta)
	_reattach_cooldown_remaining_sec = maxf(
			0.0, _reattach_cooldown_remaining_sec - delta)

	if _is_attached_idle:
		velocity = Vector2.ZERO
		animator.play(_ceiling_idle_animation_name())
		if _wants_to_detach():
			_exit_attached_idle()
		return

	_sample_web_overlap()
	_sample_water_overlap()
	if _is_in_water and not _was_in_water:
		_spawn_water_splash()
	_was_in_water = _is_in_water
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
			# Only snap upward: don't pull the player down onto terrain
			# they weren't previously touching.
			if global_position.y > cell_top:
				global_position.y = cell_top
				if velocity.y > 0.0:
					velocity.y = 0.0
			return


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


## Spawns a one-shot WaterSplash above the player at the surface of
## the water cell they just entered. Parented to the level so the
## splash stays world-fixed (doesn't drift with the player).
func _spawn_water_splash() -> void:
	if not is_instance_valid(G.level):
		return
	var splash := WaterSplash.new()
	# Top edge of the cell currently containing the player (reads as
	# the water surface) so droplets visibly fly above the waterline.
	var cs: float = 8.0
	if is_instance_valid(G.terrain) and G.terrain.settings != null:
		cs = G.terrain.settings.cell_size_px
	var cell_top_y: float = floorf(global_position.y / cs) * cs
	splash.global_position = Vector2(global_position.x, cell_top_y)
	G.level.add_child(splash)
	if is_instance_valid(G.audio):
		G.audio.play_player_sound("splash")


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
	if not is_player_control_active:
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
	# Only the first echo (the spawn-grace "press to start" input)
	# detaches from the ceiling. Subsequent echoes fire without
	# disturbing an attached-idle hang so the player can call out
	# while kissing a ceiling without losing their perch.
	if _is_attached_idle and _is_in_spawn_grace:
		_exit_attached_idle()
	G.echo.emit_pulse(global_position, current_frequency)
	# Hide the intro overlay only after the player has actually
	# blasted a GREEN echo — that's the first deliberate use of the
	# core mechanic, so the controls hint remains until then.
	if (current_frequency == Frequency.Type.GREEN
			and not _has_fired_green_echo):
		_has_fired_green_echo = true
		if is_instance_valid(G.hud):
			G.hud.hide_controls_overlay()
	var coin_vfx := (get_tree()
			.get_first_node_in_group(CoinVfx.GROUP) as CoinVfx)
	if coin_vfx != null:
		var ring_origin: Vector2 = get_horn_tip_world_position()
		coin_vfx.spawn_world_pulse_ring(
				ring_origin,
				_ECHO_PULSE_RING_OPACITY_SCALE,
				_ECHO_PULSE_RING_SIZE_SCALE)
		# Trailing inner ring: same origin, smaller + dimmer, fired
		# `_ECHO_PULSE_RING_TRAIL_DELAY_SEC` later so it reads as a
		# second pulse following the first.
		var trail_timer := get_tree().create_timer(
				_ECHO_PULSE_RING_TRAIL_DELAY_SEC)
		trail_timer.timeout.connect(func() -> void:
			if not is_instance_valid(coin_vfx):
				return
			coin_vfx.spawn_world_pulse_ring(
					ring_origin,
					_ECHO_PULSE_RING_TRAIL_OPACITY_SCALE,
					_ECHO_PULSE_RING_TRAIL_SIZE_SCALE))
	# "Detach" fires immediately with the ability input; the "echo"
	# proper lags 0.2s so the meow reads as the wind-up and the
	# pulse ping reads as the emitted wave.
	play_sound("detach", true)
	G.audio.play_player_sound_delayed("echo", 0.2, true)
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
				play_sound("select", true)
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
	if _is_in_spawn_grace or _is_in_win_pose:
		return
	if _invincibility_remaining_sec > 0.0:
		return
	if %PlayerHealth.is_dead():
		return
	%PlayerHealth.apply_damage(amount)
	# Same pulse shape for both hit and death — the death effect just
	# runs alongside `_on_died`, which hides the sprite body via
	# `body_alpha`. The pulse then reads as an expanding silhouette
	# echo rather than an oversized halo around a still-visible
	# corpse.
	_play_damage_pulse_hit()
	if not %PlayerHealth.is_dead():
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


## World-space position of the unicorn horn tip, mirrored across x
## when the player is facing left so VFX can attach to the visible
## horn regardless of which way the sprite is flipped. Falls back to
## the player's origin if the authored `%HornTip` marker is missing.
func get_horn_tip_world_position() -> Vector2:
	var horn_tip := get_node_or_null(^"%HornTip") as Node2D
	if not is_instance_valid(horn_tip):
		return global_position
	var local: Vector2 = horn_tip.position
	local.x *= surface_state.horizontal_facing_sign
	return to_global(local)


func _on_died() -> void:
	# Halt input/physics + clear the player-layer bit so nothing can
	# interact with the corpse during the game-over delay. Do NOT
	# queue_free here — `Level.game_over()` handles cleanup after
	# the delay (via `GamePanel.restart_level()`). Keeping the node
	# alive anchors the camera and the echolocation near-field
	# reveal at the death position instead of snapping back to the
	# spawn marker, and keeps the composite shader's `world_origin`
	# / `player_uv` uniforms meaningful for those remaining frames.
	# Otherwise we'd see the camera jump + a band of untextured
	# palette-colored cells for the whole game-over delay.
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	set_collision_layer_value(4, false)
	_hide_sprite_body()
	# Clear the frequency-selection outline so the corpse doesn't
	# sit under a colored silhouette while the game-over delay
	# plays out. The body itself is already faded by
	# `_hide_sprite_body` but the outline shader uniform persists
	# independently.
	_clear_frequency_outline()
	# Route death + trailing failure cadence through AudioMain so the
	# cadence outlives the eventual queue_free on this node.
	if is_instance_valid(G.audio):
		G.audio.play_player_sound("death", true)
		G.audio.play_player_sound_delayed("failure", _FAILURE_CADENCE_DELAY_SEC)
	if is_instance_valid(G.level):
		G.level.game_over()


## Fades the sprite body to transparent via the damage-flash
## shader's `body_alpha` uniform. The pulse overlay still animates
## because the pulse uses the atlas texture's alpha (not the
## rendered body alpha) to locate the silhouette boundary.
func _hide_sprite_body() -> void:
	if animator == null:
		return
	var sprite: AnimatedSprite2D = animator.animated_sprite
	if sprite == null or sprite.material == null:
		return
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("body_alpha", 0.0)


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
	velocity = Vector2.ZERO
	jump_count = 0
	is_rising_from_jump = false
	just_triggered_jump = false
	if not _attached_sprite_offset_applied:
		animator.animated_sprite.position.y += (
				_ATTACHED_IDLE_SPRITE_Y_OFFSET_PX)
		_attached_sprite_offset_applied = true
	animator.play(_ceiling_idle_animation_name())


## Returns which of the two ceiling-idle animations to play right
## now. The original `idle_ceiling` shows the kitten asleep — used
## ONLY on the very first attach of the run while `_is_in_spawn_grace`
## is still true. Every other re-attach uses `idle_ceiling_awake`
## (same animation, awake sprite) so a player who intentionally hangs
## after the game has started doesn't get the sleepy pose.
func _ceiling_idle_animation_name() -> String:
	return ("idle_ceiling" if _is_in_spawn_grace
			else "idle_ceiling_awake")


## Exits the idle-ceiling-attached state. Reverts the sprite offset and,
## if this was the spawn-grace attachment, clears grace and restores
## the player-layer bit so bugs/enemies can detect the player again.
func _exit_attached_idle() -> void:
	_is_attached_idle = false
	_reattach_cooldown_remaining_sec = _REATTACH_COOLDOWN_SEC
	play_sound("detach", true)
	if _attached_sprite_offset_applied:
		animator.animated_sprite.position.y -= (
				_ATTACHED_IDLE_SPRITE_Y_OFFSET_PX)
		_attached_sprite_offset_applied = false
	if _is_in_spawn_grace:
		_is_in_spawn_grace = false
		# Godot's helper is 1-indexed: value 4 flips bit index 3 (= 8).
		set_collision_layer_value(4, true)
		# Intro dismissal is two-stage. Stage 1 here: drop Title +
		# Dedication and fade the gameplay HUD in so the bars are
		# fully visible the moment the player has agency. Stage 2
		# (Controls hide) fires from the first GREEN echo.
		if is_instance_valid(G.hud):
			G.hud.hide_title_and_dedication()


## Called after `super._physics_process`. The scaffolder clears
## `just_touched_ceiling` mid-super before we get here, so we
## reconstruct the rising-edge transition ourselves from
## `_was_touching_ceiling`. An airborne ceiling touch triggers
## attachment directly, gated only by the post-detach reattach
## cooldown (so the player can't instantly re-hang the moment they
## detach). Outside of AIR, we just track the rising-edge state.
func _check_ceiling_bonk_attach() -> void:
	if _is_attached_idle:
		return
	var is_touching_ceiling := surface_state.is_touching_ceiling
	var just_touched := is_touching_ceiling and not _was_touching_ceiling
	_was_touching_ceiling = is_touching_ceiling
	if surface_state.surface_type != SurfaceType.AIR:
		return
	if not just_touched:
		return
	if _reattach_cooldown_remaining_sec > 0.0:
		return
	_enter_attached_idle(_POST_ATTACH_DETACH_LOCKOUT_SEC)


## Polls raw input for any direction-press or a jump just-press. Used
## only while attached-idle. `ability` (echo) is deliberately excluded.
func _wants_to_detach() -> bool:
	if _detach_lockout_remaining_sec > 0.0:
		return false
	if not is_player_control_active:
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
## attached-idle with the spawn lockout. Also fades in the Title +
## Controls intro overlay so the player sees them while pinned.
func _enter_attached_idle_at_spawn() -> void:
	global_position.y += _CEILING_SPAWN_Y_OFFSET_PX
	_is_in_spawn_grace = true
	set_collision_layer_value(4, false)
	# Disable all control until the HUD's loading blackout has fully
	# faded. `_physics_process` re-enables it once
	# `G.hud.is_blackout_hidden` flips true, so the first detach
	# can't fire under the black cover.
	is_player_control_active = false
	_enter_attached_idle(_SPAWN_DETACH_LOCKOUT_SEC)
	if is_instance_valid(G.hud):
		G.hud.show_intro_overlay()


## Enters the post-win "frozen" pose. Halts velocity, clears the
## player-layer bit so nothing can touch-interact with the player,
## and flags the pose so enemy perception + damage routing skip the
## player. Input + physics already halt via `G.level.has_won` guards
## in `_unhandled_input` / `_physics_process`. Caller (Level.win())
## is responsible for showing the intro overlay.
func enter_win_pose() -> void:
	_is_in_win_pose = true
	velocity = Vector2.ZERO
	set_collision_layer_value(4, false)
	if animator != null:
		animator.play("idle_floor")
