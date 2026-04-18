class_name Frequency
extends RefCounted
## Shared enum + palette for echolocation frequencies (tile types,
## player color, enemy color, bug color).
##
## Values are ordered so that packing into a u8 is trivial. NONE is 0
## so zero-initialized memory reads as empty.


enum Type {
	NONE = 0,
	INDESTRUCTIBLE = 1,
	RED = 2,
	GREEN = 3,
	BLUE = 4,
	LIQUID = 5,
	SAND = 6,
}


const PALETTE := {
	Type.NONE: Color(0, 0, 0, 0),
	Type.INDESTRUCTIBLE: Color(0.55, 0.55, 0.6, 1),
	Type.RED: Color(0.95, 0.35, 0.35, 1),
	Type.GREEN: Color(0.35, 0.95, 0.45, 1),
	Type.BLUE: Color(0.35, 0.55, 0.95, 1),
	Type.LIQUID: Color(0.3, 0.7, 0.9, 0.7),
	Type.SAND: Color(0.9, 0.82, 0.5, 1),
}


## Damageable by an echo pulse of `pulse_type` iff this tile is of
## `tile_type` and types match (or tile is Liquid/Sand, which always
## damage). Indestructible never takes damage.
static func is_damageable_by(tile_type: Type, pulse_type: Type) -> bool:
	if tile_type == Type.INDESTRUCTIBLE or tile_type == Type.NONE:
		return false
	if tile_type == Type.LIQUID or tile_type == Type.SAND:
		return true
	return tile_type == pulse_type


static func color_of(type: Type) -> Color:
	return PALETTE.get(type, Color.MAGENTA)
