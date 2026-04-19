class_name PlaceholderTerrainTextures
extends RefCounted
## Generates placeholder terrain texture atlases while authored art
## is still a TODO. Produces two tileable atlases indexed by
## Frequency.Type:
## - `interior_atlas`: horizontal strip of N per-type interior tiles
##   (each `TILE_PX` square). Sampled with world-space wrapping so
##   the shader gets seamless tiling within a type's slot.
## - `surface_atlas`: horizontal strip of N per-type surface bands
##   (each `TILE_PX` × `SURFACE_HEIGHT_PX`). Sampled with rotated-
##   tangent UVs so the accent band runs along the surface edge.
##
## Slot convention: the atlas has `Frequency.ATLAS_SLOT_COUNT` slots
## keyed by the Frequency.Type enum ordinal. Empty slots (NONE) are
## transparent; types without surface art (INDESTRUCTIBLE, SAND)
## leave their surface slot transparent so the shader's alpha-gated
## blend falls back to interior only.


const TILE_PX := 32
const SURFACE_HEIGHT_PX := 12

## Damage-tier atlas: horizontal strip of `DAMAGE_TIER_COUNT` tiles,
## each showing progressively heavier cracks. Tier 0 is pristine
## (pure black = no cracks), tier N-1 is fully shattered. The shader
## samples `.r` as crack alpha and darkens the tile's interior art.
const DAMAGE_TIER_COUNT := 5
const DAMAGE_TIER_TILE_PX := 32


# ---- Per-type interior palettes (dark / mid / light) ---------------

const _INTERIOR_PALETTES := {
	# RED: pink-red rock. Dark to deep pink shading.
	Frequency.Type.RED: [
		Color(0.52, 0.16, 0.23, 1.0),
		Color(0.86, 0.33, 0.44, 1.0),
		Color(0.98, 0.58, 0.68, 1.0),
	],
	# GREEN: teal rock.
	Frequency.Type.GREEN: [
		Color(0.10, 0.40, 0.34, 1.0),
		Color(0.22, 0.72, 0.58, 1.0),
		Color(0.48, 0.95, 0.78, 1.0),
	],
	# BLUE: bright cyan-ish.
	Frequency.Type.BLUE: [
		Color(0.18, 0.45, 0.70, 1.0),
		Color(0.42, 0.76, 0.96, 1.0),
		Color(0.72, 0.92, 1.00, 1.0),
	],
	# YELLOW: warm amber/orange.
	Frequency.Type.YELLOW: [
		Color(0.60, 0.36, 0.08, 1.0),
		Color(0.95, 0.66, 0.22, 1.0),
		Color(1.00, 0.86, 0.42, 1.0),
	],
	# LIQUID: deep water blue.
	Frequency.Type.LIQUID: [
		Color(0.06, 0.15, 0.35, 1.0),
		Color(0.14, 0.32, 0.62, 1.0),
		Color(0.24, 0.48, 0.80, 1.0),
	],
	# SAND: greyish yellow.
	Frequency.Type.SAND: [
		Color(0.52, 0.46, 0.32, 1.0),
		Color(0.74, 0.68, 0.48, 1.0),
		Color(0.90, 0.86, 0.66, 1.0),
	],
	# INDESTRUCTIBLE: near-black charcoal.
	Frequency.Type.INDESTRUCTIBLE: [
		Color(0.05, 0.05, 0.06, 1.0),
		Color(0.12, 0.12, 0.14, 1.0),
		Color(0.22, 0.22, 0.25, 1.0),
	],
}

# ---- Per-type surface accent palettes (dark / mid / light) ---------

# Accent colors for the surface band. Not strictly "grass green" —
# each type gets an accent that pairs with its interior. Types
# missing from this dict get no surface art.
const _SURFACE_ACCENTS := {
	# RED: rusty moss / coral pink-orange.
	Frequency.Type.RED: [
		Color(0.38, 0.22, 0.14, 1.0),
		Color(0.68, 0.40, 0.20, 1.0),
		Color(0.94, 0.62, 0.32, 1.0),
	],
	# GREEN: classic yellow-green moss.
	Frequency.Type.GREEN: [
		Color(0.18, 0.40, 0.12, 1.0),
		Color(0.42, 0.68, 0.22, 1.0),
		Color(0.72, 0.92, 0.38, 1.0),
	],
	# BLUE: pale cyan-mint accent.
	Frequency.Type.BLUE: [
		Color(0.16, 0.52, 0.52, 1.0),
		Color(0.42, 0.80, 0.76, 1.0),
		Color(0.76, 0.98, 0.92, 1.0),
	],
	# YELLOW: deep ochre accent.
	Frequency.Type.YELLOW: [
		Color(0.42, 0.22, 0.06, 1.0),
		Color(0.70, 0.44, 0.14, 1.0),
		Color(0.94, 0.68, 0.28, 1.0),
	],
}

# Water "shine" colors (highlights on the surface of liquid).
const _LIQUID_SHINE := [
	Color(0.35, 0.62, 0.96, 1.0),
	Color(0.78, 0.92, 1.00, 1.0),
	Color(1.00, 1.00, 1.00, 1.0),
]


static func make_interior_atlas() -> ImageTexture:
	var width: int = TILE_PX * Frequency.ATLAS_SLOT_COUNT
	var img := Image.create(width, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for type_id in _INTERIOR_PALETTES:
		var palette: Array = _INTERIOR_PALETTES[type_id]
		var tile_x_offset: int = int(type_id) * TILE_PX
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x1000 + int(type_id)

		# Base fill uses the mid shade.
		for y in range(TILE_PX):
			for x in range(TILE_PX):
				img.set_pixel(
						tile_x_offset + x, y,
						palette[1] as Color)

		# Scatter ~60 accent pixels (dark + light shades) to give
		# pattern without visible seams.
		for i in range(60):
			var x: int = rng.randi() % TILE_PX
			var y: int = rng.randi() % TILE_PX
			var shade: Color
			var roll := rng.randf()
			if roll < 0.5:
				shade = palette[0]
			else:
				shade = palette[2]
			img.set_pixel(tile_x_offset + x, y, shade)

		# A handful of 2x2 "stone" clusters for visual interest.
		# Use wraparound modulo so the cluster doesn't cross the
		# slot boundary.
		for i in range(6):
			var x: int = rng.randi() % TILE_PX
			var y: int = rng.randi() % TILE_PX
			var x1: int = (x + 1) % TILE_PX
			var y1: int = (y + 1) % TILE_PX
			img.set_pixel(tile_x_offset + x, y, palette[2] as Color)
			img.set_pixel(tile_x_offset + x1, y, palette[1] as Color)
			img.set_pixel(tile_x_offset + x, y1, palette[1] as Color)
			img.set_pixel(tile_x_offset + x1, y1, palette[0] as Color)

	return ImageTexture.create_from_image(img)


static func make_surface_atlas() -> ImageTexture:
	var width: int = TILE_PX * Frequency.ATLAS_SLOT_COUNT
	var img := Image.create(
			width, SURFACE_HEIGHT_PX, false, Image.FORMAT_RGBA8)
	# Transparent background — slots without surface art stay empty,
	# and the shader's alpha-gated blend will fall back to interior.
	img.fill(Color(0, 0, 0, 0))

	# Plant-like accent surfaces for the four destroyable types.
	for type_id in _SURFACE_ACCENTS:
		_draw_plant_accent_surface(
				img, int(type_id), _SURFACE_ACCENTS[type_id])

	# Water gets a "shine" treatment instead of moss.
	_draw_liquid_shine_surface(img, int(Frequency.Type.LIQUID))

	return ImageTexture.create_from_image(img)


## Generate a horizontal-strip atlas of progressive damage tiers.
## Tier 0: pristine (black = no cracks).
## Tier 1: scratched — a few short cracks.
## Tier 2: cracked — more.
## Tier 3: chipped — many cracks and scatter pixels.
## Tier 4: shattering — heavy coverage.
##
## Shader samples `.r` as crack intensity (0 = clean, 1 = full crack)
## and darkens the tile's interior_rgb by that amount.
static func make_damage_tier_atlas() -> ImageTexture:
	var tile: int = DAMAGE_TIER_TILE_PX
	var width: int = tile * DAMAGE_TIER_COUNT
	var img := Image.create(width, tile, false, Image.FORMAT_L8)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))

	# Tier 0 stays pristine. Draw cracks for tiers 1..N-1.
	for tier in range(1, DAMAGE_TIER_COUNT):
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xD4A + tier
		var tile_x_offset: int = tier * tile
		# Crack count scales roughly quadratically with tier (3, 12,
		# 27, 48) so late tiers look convincingly shattered.
		var crack_count: int = tier * tier * 3
		for _c in range(crack_count):
			var x: int = rng.randi() % tile
			var y: int = rng.randi() % tile
			var length: int = 3 + rng.randi() % 5
			var dx: int = (rng.randi() % 3) - 1
			var dy: int = (rng.randi() % 3) - 1
			if dx == 0 and dy == 0:
				dy = 1
			for _step in range(length):
				if (x < 0 or y < 0
						or x >= tile or y >= tile):
					break
				img.set_pixel(
						tile_x_offset + x, y,
						Color(1.0, 1.0, 1.0, 1.0))
				# Occasional direction jitter keeps cracks jagged.
				if rng.randf() < 0.3:
					dx = (rng.randi() % 3) - 1
					dy = (rng.randi() % 3) - 1
					if dx == 0 and dy == 0:
						dy = 1
				x += dx
				y += dy
		# Scatter chip pixels scaling with tier.
		for _p in range(tier * 8):
			var x: int = rng.randi() % tile
			var y: int = rng.randi() % tile
			img.set_pixel(
					tile_x_offset + x, y,
					Color(1.0, 1.0, 1.0, 1.0))

	return ImageTexture.create_from_image(img)


static func _draw_plant_accent_surface(
		img: Image, type_id: int, palette: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x2000 + type_id
	var tile_x_offset: int = type_id * TILE_PX

	# Per-column blade depths: how far the accent extends into the
	# tile (y=0 outside, y=HEIGHT-1 deepest inside).
	var blade_depths := PackedInt32Array()
	blade_depths.resize(TILE_PX)
	for x in range(TILE_PX):
		blade_depths[x] = rng.randi_range(3, 7)

	for x in range(TILE_PX):
		var depth: int = blade_depths[x]
		for y in range(SURFACE_HEIGHT_PX):
			var c: Color
			if y == 0:
				c = palette[2] as Color
			elif y < depth:
				var t := float(y) / float(max(1, depth))
				c = (palette[2] as Color).lerp(
						palette[1] as Color, t)
			elif y < depth + 2:
				c = (palette[1] as Color).lerp(
						palette[0] as Color, 0.5)
			else:
				# Past the blade band: transparent so the shader
				# blends back to interior.
				c = Color(0, 0, 0, 0)
			img.set_pixel(tile_x_offset + x, y, c)


static func _draw_liquid_shine_surface(
		img: Image, type_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x3000
	var tile_x_offset: int = type_id * TILE_PX

	# A thin shine band at the top (y=0..1), then a soft fade.
	for x in range(TILE_PX):
		# Random per-column highlight offset for subtle motion.
		var highlight_x := rng.randf()
		for y in range(SURFACE_HEIGHT_PX):
			var c: Color
			if y == 0:
				# Bright shine at the top.
				c = _LIQUID_SHINE[2]
			elif y == 1:
				# Second row: slightly muted shine, breaks into dots.
				if highlight_x > 0.6:
					c = _LIQUID_SHINE[1]
				else:
					c = Color(
							_LIQUID_SHINE[0].r,
							_LIQUID_SHINE[0].g,
							_LIQUID_SHINE[0].b,
							0.6)
			elif y == 2:
				# Third row: sparse speckles.
				if highlight_x > 0.8:
					c = Color(
							_LIQUID_SHINE[1].r,
							_LIQUID_SHINE[1].g,
							_LIQUID_SHINE[1].b,
							0.4)
				else:
					c = Color(0, 0, 0, 0)
			else:
				c = Color(0, 0, 0, 0)
			img.set_pixel(tile_x_offset + x, y, c)


# ---- Shader uniform packing ----------------------------------------

## Pack the type → mid-color dictionary into a flat `palette` uniform
## + `palette_freqs` uniform for the composite shader's frequency
## detector. Returns a Dictionary with `palette`, `palette_freqs`,
## `palette_count` keys, ready for `set_shader_parameter`.
static func build_palette_uniforms() -> Dictionary:
	var palette := PackedVector4Array()
	var palette_freqs := PackedInt32Array()
	var order: Array = [
		Frequency.Type.INDESTRUCTIBLE,
		Frequency.Type.RED,
		Frequency.Type.GREEN,
		Frequency.Type.BLUE,
		Frequency.Type.YELLOW,
		Frequency.Type.LIQUID,
		Frequency.Type.SAND,
	]
	for type_id in order:
		var c: Color = Frequency.PALETTE[type_id]
		palette.append(Vector4(c.r, c.g, c.b, c.a))
		palette_freqs.append(int(type_id))
	return {
		"palette": palette,
		"palette_freqs": palette_freqs,
		"palette_count": palette.size(),
	}
