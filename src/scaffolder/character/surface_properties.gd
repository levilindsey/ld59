class_name SurfaceProperties
extends RefCounted


const KEYS := [
	"can_attach",
	"friction_multiplier",
	"speed_multiplier",
	"clockwise_speed_offset"
]

var name: String

var can_attach := true

var friction_multiplier := 1.0

## -   This affects the character's speed while moving along the surface.[br]
## -   This does not affect jump start/end velocities or in-air velocities.[br]
## -   This will modify both acceleration and max-speed.[br]
var speed_multiplier := 1.0
