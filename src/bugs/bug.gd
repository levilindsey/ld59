class_name Bug
extends Area2D
## One spawned bug. Drifts gently, fades out over its lifetime, and
## is consumed when the player overlaps it. Consumption fills the
## player's juice pool for this bug's frequency (1 for SMALL, 5 for
## BIG) and heals HP (scaling with size). The player's selected
## frequency is NOT changed by eating — Q/E drives selection.
##
## Hosted under BugSpawner. Collision layer 0 (nothing queries for
## bugs); collision mask = player layer so Area2D overlap fires on
## player contact.


signal eaten(bug: Bug)


enum SizeVariant { SMALL, BIG }


const _FADE_IN_SEC := 0.25
## Fraction of lifetime over which opacity fades out at end of life.
const _FADE_OUT_FRACTION := 0.35

## How often the drift direction is re-rolled.
const _DRIFT_REROLL_INTERVAL_SEC := 0.6
## Angular jitter applied to drift direction per reroll.
const _DRIFT_JITTER_RADIANS := PI * 0.6

## Per-size tuning. Body + Glow sprite scales, collision radius,
## juice granted on eat, and heal amount applied to the player.
const _SMALL_BODY_SCALE := 6.0
const _SMALL_GLOW_SCALE := 12.0
const _SMALL_COLLISION_RADIUS := 15.0
const _SMALL_HEAL := 15
const _BIG_BODY_SCALE := 12.0
const _BIG_GLOW_SCALE := 22.0
const _BIG_COLLISION_RADIUS := 28.0
const _BIG_HEAL := 75


## Frequency type (see Frequency.Type). Drives tint and the juice
## pool filled on consumption.
@export var frequency: int = Frequency.Type.GREEN:
	set(value):
		frequency = value
		_apply_frequency_tint()

## SMALL vs BIG. Setter re-applies sprite scale, collision radius,
## juice grant, and heal amount so the single `bug.tscn` can be
## re-used for both variants — spawner flips this before `add_child`.
@export var size_variant: SizeVariant = SizeVariant.SMALL:
	set(value):
		size_variant = value
		_apply_size_variant()

@export_range(1.0, 60.0) var lifetime_sec := 12.0
@export_range(0.0, 64.0) var drift_speed_px_per_sec := 10.0

## Juice granted to the matching-frequency pool on eat. Set by
## `_apply_size_variant`.
var juice_grant: int = 1

## HP restored to the player on consumption. Set by
## `_apply_size_variant`. Exposed as an `@export` only as a
## maintenance affordance — runtime writes always go via
## `size_variant`'s setter.
@export_range(0, 200) var heal_amount: int = 15

var _age_sec := 0.0
var _drift_velocity := Vector2.ZERO
var _drift_reroll_countdown := 0.0
var _consumed := false


func _ready() -> void:
	monitoring = true
	monitorable = false
	# Initial drift direction: a random unit vector.
	var angle := randf() * TAU
	_drift_velocity = (
			Vector2.from_angle(angle) * drift_speed_px_per_sec)
	_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC
	_apply_frequency_tint()
	# Belt-and-suspenders: the setter fires during property
	# assignment, which happens before `_ready` in the scene tree
	# lifecycle. Re-apply here so the children (Body/Glow/Collision)
	# are guaranteed up-to-date even if the setter's early call ran
	# before they existed.
	_apply_size_variant()
	modulate.a = 0.0
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _consumed:
		return

	_age_sec += delta
	if _age_sec >= lifetime_sec:
		queue_free()
		return

	global_position += _drift_velocity * delta

	_drift_reroll_countdown -= delta
	if _drift_reroll_countdown <= 0.0:
		_drift_reroll_countdown = _DRIFT_REROLL_INTERVAL_SEC
		var jitter := randf_range(
				-_DRIFT_JITTER_RADIANS, _DRIFT_JITTER_RADIANS)
		_drift_velocity = _drift_velocity.rotated(jitter)

	_update_opacity()


func _on_body_entered(body: Node2D) -> void:
	if _consumed:
		return
	if body is Player:
		_consume(body as Player)


func _consume(player: Player) -> void:
	_consumed = true
	player.add_juice(frequency, juice_grant)
	player.apply_heal(heal_amount)
	eaten.emit(self)
	queue_free()


func _update_opacity() -> void:
	var fade_out_start := lifetime_sec * (1.0 - _FADE_OUT_FRACTION)
	var alpha := 1.0
	if _age_sec < _FADE_IN_SEC:
		alpha = _age_sec / _FADE_IN_SEC
	elif _age_sec > fade_out_start:
		var remaining := lifetime_sec - _age_sec
		var fade_window := lifetime_sec - fade_out_start
		alpha = clampf(remaining / fade_window, 0.0, 1.0)
	modulate.a = alpha


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	# Keep alpha separate; _update_opacity owns it.
	color.a = modulate.a
	modulate = color


func _apply_size_variant() -> void:
	var body_scale: float
	var glow_scale: float
	var coll_radius: float
	match size_variant:
		SizeVariant.BIG:
			body_scale = _BIG_BODY_SCALE
			glow_scale = _BIG_GLOW_SCALE
			coll_radius = _BIG_COLLISION_RADIUS
			juice_grant = Player.BIG_JUICE_GRANT
			heal_amount = _BIG_HEAL
		_:
			body_scale = _SMALL_BODY_SCALE
			glow_scale = _SMALL_GLOW_SCALE
			coll_radius = _SMALL_COLLISION_RADIUS
			juice_grant = Player.SMALL_JUICE_GRANT
			heal_amount = _SMALL_HEAL
	var body := get_node_or_null("Body") as Sprite2D
	if is_instance_valid(body):
		body.scale = Vector2(body_scale, body_scale)
	var glow := get_node_or_null("Glow") as Sprite2D
	if is_instance_valid(glow):
		glow.scale = Vector2(glow_scale, glow_scale)
	var coll := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if is_instance_valid(coll) and coll.shape is CircleShape2D:
		# Duplicate before mutating so the shared .tscn resource
		# doesn't get mutated for every bug instance.
		if not coll.shape.resource_local_to_scene:
			coll.shape = coll.shape.duplicate()
		(coll.shape as CircleShape2D).radius = coll_radius
