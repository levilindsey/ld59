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


## Number of atlas slots the placeholder textures reserve, sized to
## fit every Frequency.Type enum value (including NONE at index 0).
const ATLAS_SLOT_COUNT := 12


## Mid-shade representative color per type. The composite shader
## uses these for nearest-palette-match type detection on the
## backbuffer, and TerrainWorld uses them as the mesh vertex color.
##
## Declared as a `static var` (not a `const`) so
## `configure_palette(settings)` can overwrite entries from the
## `Settings` resource at startup. The defaults here are only used
## as a fallback if Settings isn't available (e.g., unit tests
## without an autoload).
##
## C++ `TerrainSettings::color_for_type()` is kept in sync at
## runtime by pushing the same Settings values into the level's
## `TerrainSettings` resource.
# gdlint: ignore=class-variable-name
static var PALETTE: Dictionary = {
	Type.NONE: Color(0, 0, 0, 0),
	Type.INDESTRUCTIBLE: Color(0.12, 0.12, 0.14, 1),
	Type.RED: Color(0.95, 0.38, 0.48, 1),
	Type.GREEN: Color(0.28, 0.82, 0.65, 1),
	Type.BLUE: Color(0.45, 0.80, 0.98, 1),
	Type.LIQUID: Color(0.16, 0.36, 0.68, 1),
	Type.SAND: Color(0.80, 0.74, 0.52, 1),
	Type.YELLOW: Color(0.95, 0.82, 0.22, 1),
	# WEB_* are translucent variants (alpha taken from
	# `color_frequency_web_alpha`). These defaults are overwritten
	# by `configure_palette` at startup.
	Type.WEB_RED: Color(0.95, 0.38, 0.48, 0.55),
	Type.WEB_GREEN: Color(0.28, 0.82, 0.65, 0.55),
	Type.WEB_BLUE: Color(0.45, 0.80, 0.98, 0.55),
	Type.WEB_YELLOW: Color(0.95, 0.82, 0.22, 0.55),
}


## Populates `PALETTE` from a `Settings` resource. Called once at
## startup (from `G._enter_tree` in editor mode and `Main._ready`
## in-game). No-op if `settings` is null so headless tests can
## fall through to the authored defaults.
static func configure_palette(settings: Settings) -> void:
	if settings == null:
		return
	PALETTE[Type.NONE] = settings.color_frequency_none
	PALETTE[Type.INDESTRUCTIBLE] = settings.color_frequency_indestructible
	PALETTE[Type.RED] = settings.color_frequency_red
	PALETTE[Type.GREEN] = settings.color_frequency_green
	PALETTE[Type.BLUE] = settings.color_frequency_blue
	PALETTE[Type.LIQUID] = settings.color_frequency_liquid
	PALETTE[Type.SAND] = settings.color_frequency_sand
	PALETTE[Type.YELLOW] = settings.color_frequency_yellow
	var web_alpha := settings.color_frequency_web_alpha
	PALETTE[Type.WEB_RED] = _with_alpha(
			settings.color_frequency_red, web_alpha)
	PALETTE[Type.WEB_GREEN] = _with_alpha(
			settings.color_frequency_green, web_alpha)
	PALETTE[Type.WEB_BLUE] = _with_alpha(
			settings.color_frequency_blue, web_alpha)
	PALETTE[Type.WEB_YELLOW] = _with_alpha(
			settings.color_frequency_yellow, web_alpha)


static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


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
