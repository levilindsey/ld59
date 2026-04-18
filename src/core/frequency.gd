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
	# WEB_* are marker types used by the level loader to spawn a
	# WebTile Area2D in place of a solid marching-squares cell.
	# They are NOT damageable terrain materials — they never end up
	# in `TerrainWorld.type_per_cell`, so the composite shader
	# never renders them. The suffix encodes the web's
	# damage-matching frequency (i.e. WEB_RED is broken by RED
	# pulses), saving us a second custom data layer on authored
	# tiles.
	WEB_RED = 8,
	WEB_GREEN = 9,
	WEB_BLUE = 10,
	WEB_YELLOW = 11,
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
	# WEB_* never render through the terrain shader (loader spawns
	# WebTile Area2Ds). Palette entries exist so `color_of(WEB_*)`
	# returns a sensible fallback — translucent (alpha 0.55) variant
	# of the corresponding base frequency color.
	Type.WEB_RED: Color(0.95, 0.38, 0.48, 0.55),
	Type.WEB_GREEN: Color(0.28, 0.82, 0.65, 0.55),
	Type.WEB_BLUE: Color(0.45, 0.80, 0.98, 0.55),
	Type.WEB_YELLOW: Color(0.98, 0.70, 0.25, 0.55),
}


## Number of atlas slots the placeholder textures reserve, sized to
## fit every Frequency.Type enum value (including NONE at index 0).
const ATLAS_SLOT_COUNT := 12


## Returns true if `type` is one of the WEB_* marker types. The
## level loader routes these to WebTile spawning rather than solid
## marching-squares cells.
static func is_web_type(type: int) -> bool:
	return (type == Type.WEB_RED
			or type == Type.WEB_GREEN
			or type == Type.WEB_BLUE
			or type == Type.WEB_YELLOW)


## Maps a WEB_* marker type to the base frequency that can damage
## the corresponding WebTile. Returns GREEN as a safe fallback if
## `web_type` isn't a WEB_* value.
static func web_type_to_frequency(web_type: int) -> int:
	match web_type:
		Type.WEB_RED: return Type.RED
		Type.WEB_GREEN: return Type.GREEN
		Type.WEB_BLUE: return Type.BLUE
		Type.WEB_YELLOW: return Type.YELLOW
	return Type.GREEN


## True iff an echo pulse of `pulse_type` damages a tile of
## `tile_type`. Matching rules:
##   - NONE + INDESTRUCTIBLE: never damageable.
##   - LIQUID + SAND: never damageable by gameplay (their Frequency
##     values don't match the player's available palette, so no
##     pulse ever carries the right type; documented explicitly
##     here so no GDScript caller gets confused).
##   - WEB_*: damageable iff pulse_type equals the base frequency
##     encoded in the web's suffix (WEB_RED by RED, etc.).
##   - Everything else: damageable iff types match exactly.
static func is_damageable_by(tile_type: Type, pulse_type: Type) -> bool:
	if tile_type == Type.INDESTRUCTIBLE or tile_type == Type.NONE:
		return false
	if tile_type == Type.LIQUID or tile_type == Type.SAND:
		return false
	if is_web_type(tile_type):
		return web_type_to_frequency(tile_type) == pulse_type
	return tile_type == pulse_type


static func color_of(type: Type) -> Color:
	return PALETTE.get(type, Color.MAGENTA)
