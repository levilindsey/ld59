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
	MONSTER_BIRD,
	FLYING_CRITTER,
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


@export var frequency: Frequency.Type = Frequency.Type.RED
@export_range(1, 500) var max_health: int = 30
@export_range(0, 200) var touch_damage: int = 10

## Knockback impulse magnitude applied on a matching-frequency pulse.
@export_range(0.0, 2000.0) var knockback_impulse_px_per_sec := 320.0

@export_node_path("CollisionShape2D") var collision_shape_path: NodePath

var _health: int
var _perception: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _knockback_velocity: Vector2 = Vector2.ZERO
var _is_dead: bool = false
var _invincibility_remaining_sec := 0.0
var _blink_accum_sec := 0.0


func _ready() -> void:
	add_to_group("enemies")
	monitoring = true
	monitorable = true
	_health = max_health
	_apply_frequency_tint()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _is_dead:
		return

	_perception = maxf(0.0, _perception - _PERCEPTION_DECAY_PER_SEC * delta)

	var knockback_decay := exp(-_KNOCKBACK_DECAY_PER_SEC * delta)
	_knockback_velocity *= knockback_decay

	var player := _get_player()
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
func receive_pulse(
		pulse_frequency: int,
		pulse_center: Vector2,
		pulse_max_radius_px: float,
		pulse_damage: int,
) -> void:
	if _is_dead:
		return

	var offset := global_position - pulse_center
	if offset.length_squared() > pulse_max_radius_px * pulse_max_radius_px:
		return

	_perception = 1.0

	if pulse_frequency != frequency:
		return

	var direction := offset.normalized() if offset != Vector2.ZERO else (
			Vector2.from_angle(randf() * TAU))
	_knockback_velocity += direction * knockback_impulse_px_per_sec
	_apply_damage(pulse_damage)


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
	died.emit(self)
	queue_free()


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


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)


func is_pursuing() -> bool:
	return _perception >= _PURSUIT_THRESHOLD
