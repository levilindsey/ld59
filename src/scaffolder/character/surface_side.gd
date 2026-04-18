class_name SurfaceSide


enum {
	NONE,
	FLOOR,
	CEILING,
	LEFT_WALL, # Normal is rightward.
	RIGHT_WALL, # Normal is leftward.
}


static func get_string(side: int) -> String:
	match side:
		NONE:
			return "NONE"
		FLOOR:
			return "FLOOR"
		CEILING:
			return "CEILING"
		LEFT_WALL:
			return "LEFT_WALL"
		RIGHT_WALL:
			return "RIGHT_WALL"
		_:
			push_error("Invalid SurfaceSide: %s" % side)
			return "???"


static func get_type(string: String) -> int:
	match string:
		"NONE":
			return NONE
		"FLOOR":
			return FLOOR
		"CEILING":
			return CEILING
		"LEFT_WALL":
			return LEFT_WALL
		"RIGHT_WALL":
			return RIGHT_WALL
		_:
			push_error("Invalid SurfaceSide: %s" % string)
			return NONE


static func get_prefix(side: int) -> String:
	match side:
		NONE:
			return "N"
		FLOOR:
			return "F"
		CEILING:
			return "C"
		LEFT_WALL:
			return "LW"
		RIGHT_WALL:
			return "RW"
		_:
			push_error("Invalid SurfaceSide: %s" % side)
			return "???"


static func get_normal(side: int) -> Vector2:
	match side:
		NONE:
			return Vector2.INF
		FLOOR:
			return G.geometry.UP
		CEILING:
			return G.geometry.DOWN
		LEFT_WALL:
			return G.geometry.RIGHT
		RIGHT_WALL:
			return G.geometry.LEFT
		_:
			push_error("Invalid SurfaceSide: %s" % side)
			return Vector2.INF


const KEYS = [
	"NONE",
	"FLOOR",
	"CEILING",
	"LEFT_WALL",
	"RIGHT_WALL",
]
static func keys() -> Array:
	return KEYS
