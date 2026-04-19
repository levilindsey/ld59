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

## Width of the frequency-color outline rendered by
## `player_damage_flash.gdshader` around the enemy silhouette.
const _FREQUENCY_OUTLINE_WIDTH_PX := 1.0

## Matching-frequency pulse damage at the pulse center, as a
## fraction of `max_health`. 1.0 means a point-blank pulse is
## enough to kill any enemy in one hit.
const _CLOSE_RANGE_DAMAGE_FRACTION := 1.0
## Matching-frequency pulse damage at the pulse's max radius, as
## a fraction of `max_health`. 1/5 means five matching pulses at
## the edge of the shell are needed to kill any enemy.
const _FAR_RANGE_DAMAGE_FRACTION := 0.2

## Death pulse — big, slow, red outline that expands outward from
## the enemy's sprite silhouette. Mirrors the player's death pulse
## so downed enemies and the downed player share the same visual
## vocabulary. Plays via a ShaderMaterial on the subclass's
## `AnimatedSprite2D`; queue_free waits for the tween to finish.
const _DEATH_FLASH_PEAK := 0.9
const _DEATH_FLASH_DURATION_SEC := 0.55
const _DEATH_PULSE_DURATION_SEC := 0.8
const _DEATH_PULSE_MAX_RADIUS_PX := 18.0
const _DEATH_PULSE_WIDTH_PX := 5.0
const _DEATH_PULSE_ALPHA := 0.9


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

@export_node_path("CollisionShape2D") var collision_shape_path: NodePath

var _health: int
var _perception: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _is_dead: bool = false
var _invincibility_remaining_sec := 0.0
var _blink_accum_sec := 0.0

## Shared wander state used by `_compute_wander_velocity`. Subclasses
## that want to wander while not perceiving the player call that
## helper; when perceiving, they ignore it and pursue directly.
var _wander_has_target: bool = false
var _wander_target: Vector2 = Vector2.ZERO
var _wander_idle_timer_sec: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	monitoring = true
	monitorable = true
	_health = max_health
	_apply_sprite_shader_parameters()
	body_entered.connect(_on_body_entered)


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
			"outline_color", Frequency.color_of(frequency))
	material.set_shader_parameter(
			"outline_width_px", _FREQUENCY_OUTLINE_WIDTH_PX)


func _process(delta: float) -> void:
	if _is_dead:
		return

	_perception = maxf(0.0, _perception - _PERCEPTION_DECAY_PER_SEC * delta)

	var knockback_decay := exp(-_KNOCKBACK_DECAY_PER_SEC * delta)
	_knockback_velocity *= knockback_decay

	var player := _get_player()
	if (is_instance_valid(player)
			and proximity_perception_radius_px > 0.0):
		var distance_sq: float = (global_position
				.distance_squared_to(player.global_position))
		var radius_sq: float = (proximity_perception_radius_px
				* proximity_perception_radius_px)
		if distance_sq <= radius_sq:
			_perception = 1.0
	_update_behavior(delta, player)

	global_position += (_velocity + _knockback_velocity) * delta
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
	_invincibility_remaining_sec = _INVINCIBILITY_SEC
	_blink_accum_sec = 0.0


func _die() -> void:
	_is_dead = true
	# Stop further contact damage / pulse reception while the death
	# tween plays out — the enemy is already logically gone.
	monitoring = false
	monitorable = false
	died.emit(self)
	_play_death_pulse()


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
	if _is_dead:
		return
	if body is Player:
		_apply_touch_damage_to(body as Player)


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
