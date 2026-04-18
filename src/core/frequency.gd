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
	YELLOW = 7,
}


## Mid-shade representative color per type. The composite shader
## uses these for nearest-palette-match type detection on the
## backbuffer, and TerrainWorld uses them as the mesh vertex color.
## Keep these in sync with `TerrainSettings::color_for_type()` on
## the C++ side.
const PALETTE := {
	Type.NONE: Color(0, 0, 0, 0),
	Type.INDESTRUCTIBLE: Color(0.12, 0.12, 0.14, 1),
	Type.RED: Color(0.95, 0.38, 0.48, 1),
	Type.GREEN: Color(0.28, 0.82, 0.65, 1),
	Type.BLUE: Color(0.45, 0.80, 0.98, 1),
	Type.LIQUID: Color(0.16, 0.36, 0.68, 1),
	Type.SAND: Color(0.80, 0.74, 0.52, 1),
	Type.YELLOW: Color(0.98, 0.70, 0.25, 1),
}


## Number of atlas slots the placeholder textures reserve, sized to
## fit every Frequency.Type enum value (including NONE at index 0).
const ATLAS_SLOT_COUNT := 8


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
