class_name PlaceholderParallaxTextures
extends RefCounted
## Generates placeholder tileable parallax background textures in a
## dark blue-gray-purple palette. Three layers, darkest/sparsest at
## the back and progressively more visible toward the foreground.
##
## Replace the returned textures with authored art when it lands —
## the parallax background scene consumes them as layer sprites.


const LAYER_SIZE := 256

# Base palette (darkest → brightest in the cool-tone range).
const _VOID := Color(0.02, 0.02, 0.05, 1.0)
const _DARK_BLUE_GRAY := Color(0.05, 0.06, 0.12, 1.0)
const _DARK_INDIGO := Color(0.09, 0.11, 0.20, 1.0)
const _PURPLE_BLUE := Color(0.17, 0.19, 0.32, 1.0)
const _DUSTY_PURPLE := Color(0.26, 0.21, 0.40, 1.0)
const _LIGHT_PURPLE := Color(0.38, 0.30, 0.52, 1.0)
# Pinpoint highlights (stars).
const _STAR_COOL := Color(0.55, 0.65, 0.90, 1.0)
const _STAR_WARM := Color(0.85, 0.78, 0.92, 1.0)


## Far layer: deepest black with sparse single-pixel stars.
static func make_far() -> ImageTexture:
	var img := Image.create(
			LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(_VOID)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5001

	# Faint base noise — per-pixel subtle variation between two
	# near-black shades to avoid flat-color banding under the
	# echolocation shader's gradient sampler.
	for y in range(LAYER_SIZE):
		for x in range(LAYER_SIZE):
			if rng.randf() < 0.08:
				img.set_pixel(x, y, _DARK_BLUE_GRAY)

	# Sparse pinpoint stars.
	for i in range(60):
		var x := rng.randi() % LAYER_SIZE
		var y := rng.randi() % LAYER_SIZE
		var brightness := rng.randf_range(0.25, 0.70)
		var hue := _STAR_COOL if rng.randf() > 0.55 else _STAR_WARM
		img.set_pixel(x, y, _VOID.lerp(hue, brightness))

	return ImageTexture.create_from_image(img)


## Mid layer: dark blue-gray base with small soft purple nebula
## blobs and medium-density stars.
static func make_mid() -> ImageTexture:
	var img := Image.create(
			LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(_DARK_BLUE_GRAY)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5002

	# Base dithering between the two dark shades for visual texture.
	for y in range(LAYER_SIZE):
		for x in range(LAYER_SIZE):
			if rng.randf() < 0.12:
				img.set_pixel(x, y, _DARK_INDIGO)

	# Small nebula blobs (2..6 px radius). Wrap around edges so the
	# texture remains tileable.
	for i in range(28):
		var cx := rng.randi() % LAYER_SIZE
		var cy := rng.randi() % LAYER_SIZE
		var radius := rng.randi_range(2, 6)
		var tint := _PURPLE_BLUE if rng.randf() > 0.5 else _DUSTY_PURPLE
		_splat_soft_blob(img, cx, cy, radius, tint, 0.45, rng)

	# Stars: cool-biased, sparse.
	for i in range(40):
		var x := rng.randi() % LAYER_SIZE
		var y := rng.randi() % LAYER_SIZE
		var color := _STAR_COOL if rng.randf() > 0.25 else _STAR_WARM
		var current := img.get_pixel(x, y)
		img.set_pixel(x, y, current.lerp(color, 0.85))

	return ImageTexture.create_from_image(img)


## Near layer: brighter indigo base with larger purple clouds and
## the most visible detail. Still well below mid-tile luminance so
## the echolocation shader's background threshold leaves it dark.
static func make_near() -> ImageTexture:
	var img := Image.create(
			LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(_DARK_INDIGO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5003

	# Base ditheriness with the purple-blue shade.
	for y in range(LAYER_SIZE):
		for x in range(LAYER_SIZE):
			if rng.randf() < 0.14:
				img.set_pixel(x, y, _PURPLE_BLUE)

	# Larger cloud shapes.
	for i in range(14):
		var cx := rng.randi() % LAYER_SIZE
		var cy := rng.randi() % LAYER_SIZE
		var radius := rng.randi_range(7, 16)
		var tint := _DUSTY_PURPLE if rng.randf() > 0.35 else _LIGHT_PURPLE
		_splat_soft_blob(img, cx, cy, radius, tint, 0.30, rng)

	# Small dot highlights scattered across — not stars, more like
	# dust / motes.
	for i in range(80):
		var x := rng.randi() % LAYER_SIZE
		var y := rng.randi() % LAYER_SIZE
		var shade := _LIGHT_PURPLE if rng.randf() > 0.5 else _DUSTY_PURPLE
		var current := img.get_pixel(x, y)
		img.set_pixel(x, y, current.lerp(shade, 0.50))

	return ImageTexture.create_from_image(img)


## Wrap-around soft circular splat. Used by mid + near layers to
## paint nebula / cloud shapes that stay tileable across image
## edges. `strength` is the maximum blend weight at the centre; it
## falls off radially to 0 at the edge of the blob.
static func _splat_soft_blob(
		img: Image,
		cx: int,
		cy: int,
		radius: int,
		tint: Color,
		strength: float,
		rng: RandomNumberGenerator) -> void:
	var r_sq := float(radius * radius)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d_sq := float(dx * dx + dy * dy)
			if d_sq > r_sq:
				continue
			var t := 1.0 - (d_sq / r_sq)
			# Softer edges via gamma.
			t = t * t
			# Jitter a little so it doesn't look like a perfect disc.
			if rng.randf() > 0.70:
				t *= 0.5
			var x := (cx + dx + LAYER_SIZE) % LAYER_SIZE
			var y := (cy + dy + LAYER_SIZE) % LAYER_SIZE
			var current := img.get_pixel(x, y)
			img.set_pixel(x, y, current.lerp(tint, t * strength))
