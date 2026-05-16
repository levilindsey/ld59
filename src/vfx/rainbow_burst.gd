class_name RainbowBurst
extends Node2D
## A single rainbow streak that arcs from `start` to `end` along a
## quadratic Bézier (no straight lines). Animates a reveal sweep
## along the arc, then fades out. Self-frees when done.
##
## The arc geometry is baked into the mesh at spawn — the shader only
## owns the reveal + color. This guarantees the shape is a real arc,
## not a hack in UV space.


const _SEGMENTS := 32
## Thickness of the strip at the start (t=0) and end (t=1). The
## rainbow tapers linearly between them so bursts read as thin at
## the origin and wider as they fan out.
const _THICKNESS_START_PX := 1.0
const _THICKNESS_END_PX := 72.0

## Extra mesh width past the visible stripe, used to render a soft
## glow halo. The mesh's half-width is `(1 + _GLOW_EXTENT) *
## stripe_half`, so the shader has room to fade the glow to zero by
## `|UV.y| = 1`. `_STRIPE_EDGE_UV` is the reciprocal — the UV.y
## fraction that marks the visible stripe's edge.
const _GLOW_EXTENT := 0.8
const _STRIPE_EDGE_UV := 1.0 / (1.0 + _GLOW_EXTENT)
const _DEFAULT_DURATION_SEC := 0.9


## Configure-then-add. Must be called before the burst is added to
## the tree (or before `_ready` runs).
var start_world: Vector2 = Vector2.ZERO
var end_world: Vector2 = Vector2.ZERO
## Bézier control point offset from the chord midpoint. Encodes the
## full arc bow direction + magnitude as a single vector so callers
## can curve downward (`(0, +sagitta)`) or chord-perpendicular
## (`perp * sagitta`) without the burst needing two code paths.
var control_offset: Vector2 = Vector2(0.0, -48.0)
var hue_offset: float = 0.0
var duration_sec: float = _DEFAULT_DURATION_SEC
var head_width: float = 0.28
## Per-burst override for the shader's `distance_fade_reach`. Values
## < 0 mean "leave the material's authored default" so coin pickups
## keep the shared look; callers like the game-win burst can pass a
## smaller value to stretch the fade past the tip.
var distance_fade_reach: float = -1.0
## Scales the baked-in stripe thickness (both start and end). 1.0 =
## the authored per-coin thickness; 2.0 doubles the stripe width at
## every point along the arc. Length scales via chord geometry in
## the caller (not this var).
var thickness_multiplier: float = 1.0
## Additional multiplier applied only at the START of the arc. 1.0 =
## the authored taper (thin at origin, fat at tip). Raising it makes
## the arc start fatter so the burst reads less like a sharp needle
## launching from a point and more like a wide ribbon sweeping in.
## Linearly blends to 1× at the far end via the Bézier `t`.
var thickness_start_multiplier: float = 1.0


@onready var _mesh_instance: MeshInstance2D = $MeshInstance2D


func _ready() -> void:
	_build_arc_mesh()
	var mat := _mesh_instance.material as ShaderMaterial
	if mat == null:
		queue_free()
		return
	mat.set_shader_parameter("hue_offset", hue_offset)
	mat.set_shader_parameter("head_width", head_width)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("alpha_scale", 1.0)
	mat.set_shader_parameter("stripe_edge_uv", _STRIPE_EDGE_UV)
	if distance_fade_reach >= 0.0:
		mat.set_shader_parameter(
				"distance_fade_reach", distance_fade_reach)
	_push_rainbow_palette(mat)
	_play_animation(mat)


## Pushes the 7-slot rainbow palette from `G.settings` into the
## shader. The shader linearly samples between adjacent slots along
## the burst's arc parameter, so the order of the colors is the
## order they're read on the rainbow. Called per-burst so live
## Settings tweaks pick up on the next burst spawn.
func _push_rainbow_palette(mat: ShaderMaterial) -> void:
	if not is_instance_valid(G.settings):
		return
	mat.set_shader_parameter(
			"rainbow_colors",
			PackedColorArray([
				G.settings.color_rainbow_red,
				G.settings.color_rainbow_orange,
				G.settings.color_rainbow_yellow,
				G.settings.color_rainbow_green,
				G.settings.color_rainbow_cyan,
				G.settings.color_rainbow_blue,
				G.settings.color_rainbow_violet,
			]))


func _build_arc_mesh() -> void:
	var chord := end_world - start_world
	var mid := start_world + chord * 0.5
	var control := mid + control_offset

	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i in range(_SEGMENTS + 1):
		var t := float(i) / float(_SEGMENTS)
		var pos := _bezier(start_world, control, end_world, t)
		var tangent := _bezier_tangent(
				start_world, control, end_world, t)
		if tangent.length_squared() > 0.0:
			tangent = tangent.normalized()
		else:
			tangent = Vector2.RIGHT
		var cross_perp := Vector2(-tangent.y, tangent.x)
		# Thin at the start, fat at the end. Matches the "burst
		# launches from a point and fans outward" silhouette. The
		# mesh extends past the visible stripe by `_GLOW_EXTENT` so
		# the shader can draw a soft halo outside the stripe edges.
		var start_px: float = (
				_THICKNESS_START_PX * thickness_start_multiplier)
		var thickness := lerpf(start_px, _THICKNESS_END_PX, t) \
				* thickness_multiplier
		var mesh_half := thickness * (1.0 + _GLOW_EXTENT)
		var offset_left := cross_perp * mesh_half
		var offset_right := -cross_perp * mesh_half
		vertices.append(pos + offset_left)
		vertices.append(pos + offset_right)
		uvs.append(Vector2(t, 1.0))
		uvs.append(Vector2(t, -1.0))

	for i in range(_SEGMENTS):
		var base := i * 2
		indices.append(base + 0)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh


static func _bezier(
		p0: Vector2,
		c: Vector2,
		p1: Vector2,
		t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * c + t * t * p1


static func _bezier_tangent(
		p0: Vector2,
		c: Vector2,
		p1: Vector2,
		t: float) -> Vector2:
	return 2.0 * (1.0 - t) * (c - p0) + 2.0 * t * (p1 - c)


func _play_animation(mat: ShaderMaterial) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(
			mat,
			"shader_parameter/progress",
			1.0,
			duration_sec
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
			mat,
			"shader_parameter/alpha_scale",
			0.0,
			duration_sec * 1.2
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
