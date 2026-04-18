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


## `floor_max_angle` and `up_direction` should match what the
## owning CharacterBody2D is configured with so our per-collision
## side classification agrees with Godot's runtime is_on_floor() /
## is_on_ceiling() / is_on_wall(). Without alignment, sharp
## concave-polygon corners can flip Godot's predicate true on a
## contact whose normal we'd classify differently — the resulting
## "is_on_floor true but no FLOOR contact in surface_contacts" state
## crashes downstream contact-deref code.
func _init(
		original: KinematicCollision2D = null,
		index := -1,
		floor_max_angle: float = MovementSettings._MAX_FLOOR_ANGLE,
		up_direction: Vector2 = Vector2.UP) -> void:
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
			# Mirror Godot's CharacterBody2D classification:
			#   FLOOR if angle(normal, up) <= floor_max_angle
			#   CEILING if angle(normal, -up) <= floor_max_angle
			#   else WALL, side determined by normal.x sign
			# (a wall on the player's right has its normal pointing
			# left, i.e. normal.x < 0 → RIGHT_WALL).
			var down := -up_direction
			if angle_to_within_plus_minus_pi(normal, up_direction) \
					<= floor_max_angle:
				side = SurfaceSide.FLOOR
			elif angle_to_within_plus_minus_pi(normal, down) \
					<= floor_max_angle:
				side = SurfaceSide.CEILING
			elif normal.x < 0.0:
				side = SurfaceSide.RIGHT_WALL
			else:
				side = SurfaceSide.LEFT_WALL
		else:
			side = SurfaceSide.NONE

		key = "%s:%s" % [G.utils.get_vector_string(position, 3), side]


static func angle_to_within_plus_minus_pi(a: Vector2, b: Vector2) -> float:
	return abs(fmod(a.angle_to(b) + TAU + PI, TAU) - PI)
