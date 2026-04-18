class_name Collision
extends RefCounted


var is_tilemap_collision := false
var side := SurfaceSide.NONE
var key := ""
var collision_index := -1

var angle: float
var collider: Object
var collider_id: int
var collider_rid: RID
var collider_shape: Object
var collider_shape_index: int
var collider_velocity: Vector2
var depth: float
var local_shape: Object
var normal: Vector2
var position: Vector2
var remainder: Vector2
var travel: Vector2


func _init(original: KinematicCollision2D = null, index := -1) -> void:
	if is_instance_valid(original):
		self.angle = original.get_angle()
		self.collider = original.get_collider()
		self.collider_id = original.get_collider_id()
		self.collider_rid = original.get_collider_rid()
		self.collider_shape = original.get_collider_shape()
		self.collider_shape_index = original.get_collider_shape_index()
		self.collider_velocity = original.get_collider_velocity()
		self.depth = original.get_depth()
		self.local_shape = original.get_local_shape()
		self.normal = original.get_normal()
		self.position = original.get_position()
		self.remainder = original.get_remainder()
		self.travel = original.get_travel()
		self.collision_index = index

		#self.is_tilemap_collision = collider is TileMapLayer
		self.is_tilemap_collision = true

		if is_tilemap_collision:
			if angle_to_within_plus_minus_pi(normal, Vector2.UP) <= MovementSettings._MAX_FLOOR_ANGLE:
				side = SurfaceSide.FLOOR
			elif angle_to_within_plus_minus_pi(normal, Vector2.DOWN) <= MovementSettings._MAX_FLOOR_ANGLE:
				side = SurfaceSide.CEILING
			elif angle_to_within_plus_minus_pi(normal, Vector2.LEFT) <= PI / 2 - MovementSettings._MAX_FLOOR_ANGLE:
				side = SurfaceSide.RIGHT_WALL
			else:
				side = SurfaceSide.LEFT_WALL
		else:
			side = SurfaceSide.NONE

		key = "%s:%s" % [G.utils.get_vector_string(position, 3), side]


static func angle_to_within_plus_minus_pi(a: Vector2, b: Vector2) -> float:
	return abs(fmod(a.angle_to(b) + TAU + PI, TAU) - PI)
