class_name TerrainChunkFragment
extends RigidBody2D
## RigidBody2D spawned when a connected-components pass detects a
## piece of terrain that's disconnected from any anchor. Built from
## pre-baked mesh + collision data emitted by `TerrainWorld`'s
## `fragment_detached` signal.
##
## Despawns after resting for `_REST_DESPAWN_SEC` seconds, or on
## `_MAX_LIFETIME_SEC`, whichever comes first. Damages the player
## on collision if the relative velocity exceeds a threshold.


const _REST_DESPAWN_SEC := 2.0
const _MAX_LIFETIME_SEC := 15.0
const _REST_VELOCITY_PX_PER_SEC := 12.0
const _DAMAGE_VELOCITY_THRESHOLD_PX_PER_SEC := 200.0
const _CONTACT_DAMAGE := 10
const _DAMAGE_COOLDOWN_SEC := 0.5


@export var initial_velocity := Vector2.ZERO


var _mesh_canvas_rid: RID = RID()
var _rest_accum_sec := 0.0
var _lifetime_sec := 0.0
var _damage_cooldown_sec := 0.0


func _ready() -> void:
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 1
	collision_mask = 9
	body_entered.connect(_on_body_entered)


## Build mesh + collision from pre-baked data (called by terrain_level
## right after instantiation). `origin_world` is the world-space
## position of the fragment's local (0, 0); mesh verts are in fragment-
## local space.
func build(
		origin_world: Vector2,
		mesh_verts: PackedVector2Array,
		mesh_indices: PackedInt32Array,
		mesh_colors: PackedColorArray,
		collision_segments: PackedVector2Array) -> void:
	global_position = origin_world
	linear_velocity = initial_velocity

	_build_mesh(mesh_verts, mesh_indices, mesh_colors)
	_build_collision(collision_segments)


func _build_mesh(
		verts: PackedVector2Array,
		indices: PackedInt32Array,
		colors: PackedColorArray) -> void:
	if verts.is_empty() or indices.is_empty():
		return
	_mesh_canvas_rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(
			_mesh_canvas_rid, get_canvas_item())
	RenderingServer.canvas_item_set_visibility_layer(_mesh_canvas_rid, 3)
	RenderingServer.canvas_item_add_triangle_array(
			_mesh_canvas_rid, indices, verts, colors)


func _build_collision(segments: PackedVector2Array) -> void:
	if segments.is_empty():
		return
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segments
	var coll := CollisionShape2D.new()
	coll.shape = shape
	add_child(coll)


func _physics_process(delta: float) -> void:
	_lifetime_sec += delta
	_damage_cooldown_sec = maxf(0.0, _damage_cooldown_sec - delta)

	if linear_velocity.length_squared() < (
			_REST_VELOCITY_PX_PER_SEC * _REST_VELOCITY_PX_PER_SEC):
		_rest_accum_sec += delta
	else:
		_rest_accum_sec = 0.0

	if (
			_rest_accum_sec >= _REST_DESPAWN_SEC
			or _lifetime_sec >= _MAX_LIFETIME_SEC):
		queue_free()


func _exit_tree() -> void:
	if _mesh_canvas_rid.is_valid():
		RenderingServer.free_rid(_mesh_canvas_rid)
		_mesh_canvas_rid = RID()


func _on_body_entered(body: Node) -> void:
	if _damage_cooldown_sec > 0.0:
		return
	if not (body is Player):
		return
	var relative_speed := linear_velocity.length()
	if relative_speed < _DAMAGE_VELOCITY_THRESHOLD_PX_PER_SEC:
		return
	(body as Player).apply_damage(_CONTACT_DAMAGE)
	_damage_cooldown_sec = _DAMAGE_COOLDOWN_SEC
