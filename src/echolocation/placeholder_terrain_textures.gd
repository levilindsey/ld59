class_name PlaceholderTerrainTextures
extends RefCounted
## Generates tileable placeholder textures for terrain rendering
## while real art is still a TODO. Produces:
## - a tileable "dirt" interior texture (world-space wrapping).
## - a tileable-horizontal "grass" surface strip (applied in a band
##   along surface edges, rotated to align with the surface tangent).
##
## Replace the returned textures with authored art when it lands —
## the composite shader consumes them as uniforms.


const _DIRT_SIZE := 32
const _DIRT_DARK := Color(0.32, 0.22, 0.15, 1.0)
const _DIRT_MID := Color(0.45, 0.32, 0.20, 1.0)
const _DIRT_LIGHT := Color(0.55, 0.40, 0.25, 1.0)
const _DIRT_SHADOW := Color(0.25, 0.17, 0.11, 1.0)

const _GRASS_WIDTH := 32
const _GRASS_HEIGHT := 12
const _GRASS_TOP := Color(0.40, 0.82, 0.32, 1.0)
const _GRASS_MID := Color(0.25, 0.58, 0.22, 1.0)
const _GRASS_DARK := Color(0.18, 0.40, 0.18, 1.0)


static func make_dirt_interior() -> ImageTexture:
	var img := Image.create(
			_DIRT_SIZE, _DIRT_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(_DIRT_MID)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Scatter highlights and deep shadows to give the tile some
	# texture without leaving visible seams. Symmetric wrap: any
	# pixel placed near an edge is mirrored on the opposite side so
	# tiling stays seamless.
	for i in range(80):
		var x := rng.randi() % _DIRT_SIZE
		var y := rng.randi() % _DIRT_SIZE
		var c := _DIRT_DARK
		var roll := rng.randf()
		if roll < 0.33:
			c = _DIRT_LIGHT
		elif roll < 0.50:
			c = _DIRT_SHADOW
		img.set_pixel(x, y, c)

	# Subtle small stones: 2x2 clusters.
	for i in range(10):
		var x := rng.randi() % (_DIRT_SIZE - 1)
		var y := rng.randi() % (_DIRT_SIZE - 1)
		img.set_pixel(x, y, _DIRT_LIGHT)
		img.set_pixel(x + 1, y, _DIRT_MID)
		img.set_pixel(x, y + 1, _DIRT_MID)
		img.set_pixel(x + 1, y + 1, _DIRT_SHADOW)

	return ImageTexture.create_from_image(img)


static func make_grass_surface() -> ImageTexture:
	# Horizontal strip: x tiles along the surface tangent, y goes
	# from grass (y=0, just outside the surface) down into the tile
	# (y=HEIGHT-1, deepest in the surface band).
	var img := Image.create(
			_GRASS_WIDTH, _GRASS_HEIGHT, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	# Per-column grass blade height: how far "down" the grass
	# extends into the tile at each horizontal position.
	var blade_heights: PackedInt32Array = PackedInt32Array()
	blade_heights.resize(_GRASS_WIDTH)
	for x in range(_GRASS_WIDTH):
		blade_heights[x] = rng.randi_range(2, 5)

	for y in range(_GRASS_HEIGHT):
		for x in range(_GRASS_WIDTH):
			var c: Color
			var blade_depth: int = blade_heights[x]
			if y <= 0:
				c = _GRASS_TOP
			elif y <= blade_depth:
				# Blade body: interpolate from top to dark.
				var t := float(y) / float(max(1, blade_depth))
				c = _GRASS_TOP.lerp(_GRASS_DARK, t)
			elif y <= blade_depth + 2:
				# Transition band.
				c = _GRASS_MID.lerp(_DIRT_MID, 0.3)
			else:
				# Below the grass: fade into dirt color.
				var t := float(y - (blade_depth + 2)) / float(
						_GRASS_HEIGHT - (blade_depth + 2))
				c = _GRASS_DARK.lerp(_DIRT_MID, clamp(t, 0.0, 1.0))
			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)
