class_name Enemy
extends Area2D
## Typed, frequency-colored enemy. Subscribes to echolocation pulses
## via EnemySystem. Takes damage + knockback from matching-frequency
## pulses. Deals touch damage to the player on overlap.
##
## Movement is owned by subclasses via `_update_behavior(delta,
## player)`. The base class integrates a knockback impulse that
## decays toward zero so subclass movement feels stable between hits.


signal died(enemy: Enemy)
signal damaged(enemy: Enemy, amount: int)


## SceneTree group name. Enemies self-register in `_ready()` so
## systems like `EnemySystem.apply_pulse_damage` and
## `EcholocationRenderer` can iterate them without holding direct
## references.
const GROUP := &"enemies"


## Taxonomy of enemy scenes known to EnemySystem. Used by
## `EnemySpawnPoint.kind` to select which scene to instantiate.
enum Kind {
	SPIDER,
	COYOTE,
	OWL,
}


## Perception at which the enemy switches from idle to pursuit.
const _PURSUIT_THRESHOLD := 0.3
## Perception decay back to zero, in units per second.
const _PERCEPTION_DECAY_PER_SEC := 0.25
## Knockback velocity decay rate (units of fraction per second).
const _KNOCKBACK_DECAY_PER_SEC := 3.5
## Grace period after taking damage: further damage is ignored and
## the sprite blinks.
const _INVINCIBILITY_SEC := 0.6
## Blink period while invincible.
const _BLINK_PERIOD_SEC := 0.1

## Offset (in atlas/game pixels) used for the 4-cardinal-neighbor
## outline test in `player_damage_flash.gdshader`. A fragment in
## transparent padding is painted with `outline_color` when any of
## its 4 neighbors at this radius is opaque, producing a 1-pixel-
## thick outline displaced outward by this many atlas pixels.
const _FREQUENCY_OUTLINE_WIDTH_PX := 1.0

## Lightening applied to the pure frequency palette color before
## it's pushed as `outline_color`. Needed because the echolocation
## composite shader's "tile interior" pass detects and replaces
## pixels whose color matches the tile palette within
## `overlay_sprite_diff_threshold` (~0.08 in RGB distance). A pure
## palette-color outline drawn over a matching-frequency tile
## would therefore get overwritten by the tile's interior texture;
## lightening nudges the outline outside that threshold.
const _OUTLINE_COLOR_LIGHTEN_AMOUNT := 0.25

## Matching-frequency pulse damage at the pulse center, as a
## fraction of `max_health`. 1.0 means a point-blank pulse is
## enough to kill any enemy in one hit.
const _CLOSE_RANGE_DAMAGE_FRACTION := 1.0
## Matching-frequency pulse damage at the pulse's max radius, as
## a fraction of `max_health`. 1/5 means five matching pulses at
## the edge of the shell are needed to kill any enemy.
const _FAR_RANGE_DAMAGE_FRACTION := 0.2

## Death pulse — red outline that expands outward from the enemy's
## sprite silhouette. Mirrors the player's death pulse so downed
## enemies and the downed player share the same visual vocabulary.
## Plays via a ShaderMaterial on the subclass's `AnimatedSprite2D`;
## queue_free waits for the tween to finish.
const _DEATH_FLASH_PEAK := 0.9
const _DEATH_FLASH_DURATION_SEC := 0.55
const _DEATH_PULSE_DURATION_SEC := 0.8
const _DEATH_PULSE_MAX_RADIUS_PX := 8.0
const _DEATH_PULSE_WIDTH_PX := 3.5
const _DEATH_PULSE_ALPHA := 0.9

## Damage-hit flash (non-fatal). Short red tint on the sprite body.
const _DAMAGE_FLASH_PEAK := 0.85
const _DAMAGE_FLASH_DURATION_SEC := 0.25

## Peak perception-glow strength. Applied as a modulate mix
## toward `Frequency.color_of(frequency)` so an enemy tinted
## toward its own color when it's actively "hunting" the player
## — reads as "this creature has detected you" without a new
## shader uniform. `_perception` is 0..1 and decays on its own,
## so the mix value naturally fades when the player escapes.
const _PERCEPTION_GLOW_PEAK := 0.35


@export var frequency: Frequency.Type = Frequency.Type.RED
@export_range(1, 500) var max_health: int = 30
@export_range(0, 200) var touch_damage: int = 10

## Knockback impulse magnitude applied on a matching-frequency pulse.
@export_range(0.0, 2000.0) var knockback_impulse_px_per_sec := 320.0

## Radius at which the enemy notices the player from proximity
## alone (no echolocation pulse required). Perception is pegged to
## 1.0 while the player is within this radius and then decays
## naturally once the player moves away, so pursuit feels "sticky"
## for a moment after the enemy loses sight.
@export_range(0.0, 1024.0) var proximity_perception_radius_px := 200.0

## World-px halo radius used for this enemy's stipple tag. Should
## roughly cover the sprite's largest silhouette extent so the
## stipple can paint across the entire sprite. Subclass scenes
## override this per-sprite (spiders are compact, coyotes are
## elongated, owls are close to square).
@export_range(2.0, 64.0) var tag_radius_px: float = 16.0

@export_node_path("CollisionShape2D") var collision_shape_path: NodePath

var _health: int
var _perception: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _is_dead: bool = false
var _invincibility_remaining_sec := 0.0
var _blink_accum_sec := 0.0
var _damage_hit_tween: Tween = null

## Shared wander state used by `_compute_wander_velocity`. Subclasses
## that want to wander while not perceiving the player call that
## helper; when perceiving, they ignore it and pursue directly.
var _wander_has_target: bool = false
var _wander_target: Vector2 = Vector2.ZERO
var _wander_idle_timer_sec: float = 0.0

## Tracks `is_pursuing()` across frames so the base class can fire
## `_on_pursuit_started()` exactly on the rising edge.
var _was_pursuing: bool = false

## True while the player's CharacterBody2D is overlapping this
## enemy's Area2D. Driven by `body_entered` / `body_exited`. Lets
## the per-frame tick in `_process` re-apply touch damage the moment
## the player's invincibility lapses if they're still in contact,
## rather than requiring a fresh enter signal.
var _is_player_in_contact: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	monitoring = true
	monitorable = true
	_health = max_health
	_apply_sprite_shader_parameters()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _apply_sprite_shader_parameters() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var material := sprite.material as ShaderMaterial
	if material == null:
		return
	if G.settings != null:
		material.set_shader_parameter(
				"flash_color", G.settings.color_damage_flash)
		material.set_shader_parameter(
				"pulse_color", G.settings.color_damage_pulse)
	material.set_shader_parameter(
			"outline_color",
			Frequency.color_of(frequency).lightened(
					_OUTLINE_COLOR_LIGHTEN_AMOUNT))
	material.set_shader_parameter(
			"outline_width_px", _FREQUENCY_OUTLINE_WIDTH_PX)


func _process(delta: float) -> void:
	if _is_dead:
		return
	# Once the player has won, freeze every enemy — no more movement,
	# no more perception. Matches the "enemies won't pursue" post-win
	# contract since `Level.win()` doesn't pause the scene tree.
	if is_instance_valid(G.level) and G.level.has_won:
		return

	_perception = maxf(0.0, _perception - _PERCEPTION_DECAY_PER_SEC * delta)

	var knockback_decay := exp(-_KNOCKBACK_DECAY_PER_SEC * delta)
	_knockback_velocity *= knockback_decay

	var player := _get_player()
	if (is_instance_valid(player)
			and proximity_perception_radius_px > 0.0
			and not player.is_non_interactive):
		var distance_sq: float = (global_position
				.distance_squared_to(player.global_position))
		var radius_sq: float = (proximity_perception_radius_px
				* proximity_perception_radius_px)
		if distance_sq <= radius_sq:
			_perception = 1.0
	_update_behavior(delta, player)

	var is_pursuing_now := is_pursuing()
	if is_pursuing_now and not _was_pursuing:
		_on_pursuit_started()
	_was_pursuing = is_pursuing_now

	global_position += (_velocity + _knockback_velocity) * delta
	_extricate_from_solid_terrain()
	_tick_invincibility(delta)
	_tick_contact_damage()
	_tick_perception_glow()


## Safety net for cases where the per-frame integration leaves the
## enemy origin inside a solid (collidable) cell. Common causes:
##   1. Echo knockback overshoots and pushes the enemy through a
##      wall or into a floor.
##   2. A gravity-driven enemy (Coyote) walks off a water cell and
##      falls fast enough that the next frame's origin lands inside
##      the solid cell beneath the water — the per-enemy floor snap
##      rejects far hits to avoid apex-of-jump teleports, so it
##      doesn't recover.
##   3. A FallingCell or flow-step paints a new solid cell on top of
##      the enemy.
## Pushes the origin out along the cardinal direction with the
## shortest exit distance (cell edge + small margin) and damps the
## velocity component in that direction so we don't immediately
## re-penetrate. No-op when the origin is already in an empty cell,
## so AI flow is untouched in normal play.
func _extricate_from_solid_terrain() -> void:
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	if not G.terrain.is_cell_collidable(global_position):
		return
	var cs: float = G.terrain.settings.cell_size_px
	const _EDGE_MARGIN := 0.5
	# Maximum cells to walk in each direction before giving up. Sized
	# bigger than typical floor / wall thickness so a deep knockback
	# into a thick slab still gets pulled out — earlier 1-cell limit
	# missed multi-cell-thick floors and the coyote fell through.
	const _MAX_PUSH_CELLS := 12
	# Walks each cardinal direction one cell at a time and snaps the
	# enemy to the first empty cell found, with a small inset past
	# the edge. Direction priority: UP first (gravity-clip into floor
	# is the dominant case), then DOWN / LEFT / RIGHT.
	var dirs: Array = [
		Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
	]
	for dir in dirs:
		for steps in range(1, _MAX_PUSH_CELLS + 1):
			# Move to the FAR edge of the cell `steps` cells away in
			# `dir`, plus the margin so the new origin sits clearly
			# inside the empty cell.
			var probe: Vector2 = global_position + dir * cs * steps
			if G.terrain.is_cell_collidable(probe):
				continue
			# Snap to the cell edge nearest the source so we don't
			# overshoot into the middle of the empty cell.
			var snapped := global_position
			if dir.y < 0.0:
				var cy_now: int = int(
						floor(global_position.y / cs))
				snapped.y = (cy_now - (steps - 1)) * cs - _EDGE_MARGIN
			elif dir.y > 0.0:
				var cy_now2: int = int(
						floor(global_position.y / cs))
				snapped.y = ((cy_now2 + steps) * cs
						+ _EDGE_MARGIN)
			elif dir.x < 0.0:
				var cx_now: int = int(
						floor(global_position.x / cs))
				snapped.x = (cx_now - (steps - 1)) * cs - _EDGE_MARGIN
			else:
				var cx_now2: int = int(
						floor(global_position.x / cs))
				snapped.x = ((cx_now2 + steps) * cs
						+ _EDGE_MARGIN)
			global_position = snapped
			if dir.x != 0.0:
				_knockback_velocity.x = 0.0
				_velocity.x = 0.0
			else:
				_knockback_velocity.y = 0.0
				_velocity.y = 0.0
			return
	# Truly stuck (more than _MAX_PUSH_CELLS solid in every
	# direction). Leave in place; per-enemy snap routines on
	# subsequent frames may eventually find a surface.


## Mixes the sprite's modulate toward the enemy's frequency color
## by `_perception * _PERCEPTION_GLOW_PEAK`. Zero perception
## leaves modulate at pure white. Invincibility blinking still
## wins because `_tick_invincibility` toggles `visible` (not
## modulate).
func _tick_perception_glow() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var mix_amt: float = _perception * _PERCEPTION_GLOW_PEAK
	var freq_color: Color = Frequency.color_of(frequency)
	sprite.modulate = Color.WHITE.lerp(freq_color, mix_amt)


## Re-applies touch damage every frame the player is still in
## contact with this enemy's Area2D. `Player.apply_damage` guards on
## its own invincibility, so this is a no-op on grace frames and
## lands the next hit the moment the grace expires.
func _tick_contact_damage() -> void:
	if not _is_player_in_contact:
		return
	var player := _get_player()
	if is_instance_valid(player):
		_apply_touch_damage_to(player)


## Override in subclasses. Called once each time perception crosses
## above `_PURSUIT_THRESHOLD` from below (i.e. the enemy starts
## tracking the player). Subclasses use this to play a spatial
## "detection" sound (bark/hoot/chirp).
func _on_pursuit_started() -> void:
	pass


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


## Override in subclasses. Read `_perception` to decide idle vs
## pursuit. Write `_velocity` to change movement.
func _update_behavior(_delta: float, _player: Player) -> void:
	pass


## Called by EnemySystem in response to G.echo.pulse_emitted. Raises
## perception unconditionally if the pulse reaches us; applies damage
## and knockback only when `pulse_frequency` matches this enemy.
## Damage is attenuated by distance from the pulse center: a
## point-blank matching pulse kills in one hit, a max-radius matching
## pulse takes five hits to kill (per `_*_DAMAGE_FRACTION`). The
## caller's `pulse_damage` is intentionally ignored — the shell is
## lethal based on proximity, not the pulse's authored damage.
func receive_pulse(
		pulse_frequency: int,
		pulse_center: Vector2,
		pulse_max_radius_px: float,
		_pulse_damage: int,
) -> void:
	if _is_dead:
		return

	var offset := global_position - pulse_center
	var max_radius_sq := pulse_max_radius_px * pulse_max_radius_px
	if offset.length_squared() > max_radius_sq:
		return

	_perception = 1.0

	if pulse_frequency != frequency:
		return

	var direction := offset.normalized() if offset != Vector2.ZERO else (
			Vector2.from_angle(randf() * TAU))
	_knockback_velocity += direction * knockback_impulse_px_per_sec

	var distance := offset.length()
	var t := clampf(
			distance / maxf(pulse_max_radius_px, 1.0), 0.0, 1.0)
	var fraction := lerpf(
			_CLOSE_RANGE_DAMAGE_FRACTION,
			_FAR_RANGE_DAMAGE_FRACTION,
			t)
	var attenuated_damage := int(ceil(float(max_health) * fraction))
	_apply_damage(attenuated_damage)


## Current velocity magnitude, including knockback. Used by the
## echolocation renderer to scale this enemy's persistent
## stippling intensity with movement — stationary enemies fade out,
## pursuing enemies pop brighter even before an echo is fired.
func get_current_velocity() -> Vector2:
	return _velocity + _knockback_velocity


## True from `_die()` onward until `queue_free` lands. The
## echolocation renderer repaints the stipple in damage-flash red
## during this window so the death pulse reads as a cohesive
## "killed it" beat across the sprite-side flash shader and the
## composite-side stipple layer.
func is_dying() -> bool:
	return _is_dead


func apply_damage(amount: int) -> void:
	_apply_damage(amount)


func _apply_damage(amount: int) -> void:
	if _is_dead or _invincibility_remaining_sec > 0.0:
		return
	_health -= amount
	damaged.emit(self, amount)
	if _health <= 0:
		_die()
		return
	_play_damage_hit_flash()
	_invincibility_remaining_sec = _INVINCIBILITY_SEC
	_blink_accum_sec = 0.0


## Number of particles emitted on enemy death. Scaled to the
## screen-pop the player's damage pulse gets — plenty of particles
## to read as a burst without flooding the pool.
const _DEATH_PARTICLE_COUNT := 14


func _die() -> void:
	_is_dead = true
	# Stop further contact damage / pulse reception while the death
	# tween plays out — the enemy is already logically gone.
	# Deferred because `_die` can run inside Area2D body-entered
	# signal dispatch (falling cells, terrain fragments), where
	# Godot blocks direct `monitoring`/`monitorable` mutation.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	died.emit(self)
	_play_death_pulse()
	# Frequency-colored particle burst — the dots match the enemy's
	# own palette color so each kind reads as a distinct pop rather
	# than a generic red flash.
	if is_instance_valid(G.echo):
		G.echo.spawn_burst_particles(
				global_position, _DEATH_PARTICLE_COUNT, frequency)


## Short red tint on the sprite body on non-fatal damage. Separate
## from `_play_death_pulse` — no silhouette ring, just the flash.
func _play_damage_hit_flash() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.material == null:
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		return
	if _damage_hit_tween != null and _damage_hit_tween.is_valid():
		_damage_hit_tween.kill()
	if G.settings != null:
		mat.set_shader_parameter(
				"flash_color", G.settings.color_damage_flash)
	mat.set_shader_parameter("flash_strength", _DAMAGE_FLASH_PEAK)
	_damage_hit_tween = create_tween()
	_damage_hit_tween.tween_property(
			mat, "shader_parameter/flash_strength",
			0.0, _DAMAGE_FLASH_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Runs the same shader animation used by the player's death pulse,
## bound to the subclass's `AnimatedSprite2D`. Frees the enemy once
## the tween completes.
func _play_death_pulse() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.material == null:
		queue_free()
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		queue_free()
		return
	if G.settings != null:
		mat.set_shader_parameter(
				"flash_color", G.settings.color_damage_flash)
		mat.set_shader_parameter(
				"pulse_color", G.settings.color_damage_pulse)
	mat.set_shader_parameter("body_alpha", 0.0)
	mat.set_shader_parameter("flash_strength", _DEATH_FLASH_PEAK)
	mat.set_shader_parameter("pulse_width_px", _DEATH_PULSE_WIDTH_PX)
	mat.set_shader_parameter("pulse_radius_px", 1.0)
	mat.set_shader_parameter("pulse_alpha", _DEATH_PULSE_ALPHA)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(
			mat, "shader_parameter/flash_strength",
			0.0, _DEATH_FLASH_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
			mat, "shader_parameter/pulse_radius_px",
			_DEATH_PULSE_MAX_RADIUS_PX, _DEATH_PULSE_DURATION_SEC
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(
			mat, "shader_parameter/pulse_alpha",
			0.0, _DEATH_PULSE_DURATION_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	_is_player_in_contact = true
	if _is_dead:
		return
	_apply_touch_damage_to(body as Player)


func _on_body_exited(body: Node2D) -> void:
	if not (body is Player):
		return
	_is_player_in_contact = false


func _apply_touch_damage_to(player: Player) -> void:
	player.apply_damage(touch_damage)


func _get_player() -> Player:
	if is_instance_valid(G.level) and is_instance_valid(G.level.player):
		return G.level.player
	return null


func is_pursuing() -> bool:
	return _perception >= _PURSUIT_THRESHOLD


## Returns a velocity that wanders around the enemy's current
## position: alternately idling in place for a random duration, then
## slow-moving to a random nearby point. Subclasses call this from
## `_update_behavior` when `is_pursuing()` is false. Returns
## `Vector2.ZERO` while the enemy is idling at rest.
##
## `radius_px` is the max random offset from the enemy's position
## when picking a new wander target.
func _compute_wander_velocity(
		delta: float,
		speed_px_per_sec: float,
		radius_px: float,
		idle_min_sec: float,
		idle_max_sec: float,
) -> Vector2:
	if _wander_idle_timer_sec > 0.0:
		_wander_idle_timer_sec -= delta
		return Vector2.ZERO
	if not _wander_has_target:
		var angle: float = randf() * TAU
		var dist: float = randf_range(radius_px * 0.3, radius_px)
		_wander_target = (global_position
				+ Vector2(cos(angle), sin(angle)) * dist)
		_wander_has_target = true
	var to_target: Vector2 = _wander_target - global_position
	# Close enough — pause here, then pick a new target.
	if to_target.length() < 4.0:
		_wander_has_target = false
		_wander_idle_timer_sec = randf_range(
				idle_min_sec, idle_max_sec)
		return Vector2.ZERO
	return to_target.normalized() * speed_px_per_sec
