class_name EcholocationRenderer
extends CanvasLayer
## Screen-space darkness-mask overlay that drives echolocation
## visibility. Registers as G.echo so subscribers can connect to
## `pulse_emitted`. Maintains a pool of active EchoPulse objects and
## pushes their screen-space state + frequency colors into the
## composite shader each frame.
##
## Phase 1: no SubViewports, no frequency-tag buffer yet. The scene
## renders normally underneath; this CanvasLayer paints a black
## overlay with alpha = 1 - visibility.


signal pulse_emitted(pulse: EchoPulse)
signal pulse_completed(pulse: EchoPulse)


const _MAX_PULSES := 8

## Player's visibility anchor. If null at _ready, falls back to
## G.level.player once available.
@export var follow_target: Node2D

@export_range(0.0, 512.0) var near_radius_px := 80.0
@export_range(0.0, 128.0) var near_fade_px := 32.0

@export_range(1.0, 64.0) var edge_width_px := 12.0
@export_range(0.05, 2.0) var fade_tau_sec := 0.35
@export_range(0.1, 4.0) var lifetime_sec := 1.2
@export_range(1.0, 4.0) var edge_boost := 1.5

@export_range(1.0, 16.0) var ring_width_px := 4.0
@export_range(0.0, 2.0) var ring_glow_strength := 1.2
@export_range(1.0, 16.0) var bayer_tile_px := 4.0

@export_range(100.0, 2000.0) var default_pulse_speed_px_per_sec := 600.0
@export_range(100.0, 4000.0) var default_pulse_max_radius_px := 1000.0

## If true, draws a cyan cross at the computed player_uv and prints
## diagnostics for the first few frames after a player is acquired.
## Use to verify world→screen conversion.
@export var debug_show_anchor := false

var _pool: Array[EchoPulse] = []
var _shader_mat: ShaderMaterial
var _debug_frames_remaining: int = 10


func _enter_tree() -> void:
	G.echo = self


func _exit_tree() -> void:
	if G.echo == self:
		G.echo = null


func _ready() -> void:
	layer = 100
	follow_viewport_enabled = false

	# Pre-allocate pool slots.
	_pool.resize(_MAX_PULSES)

	_shader_mat = %Mask.material as ShaderMaterial
	G.ensure_valid(_shader_mat, "EcholocationRenderer: Mask missing ShaderMaterial")

	_shader_mat.set_shader_parameter("bayer_tex", _build_bayer_texture())
	# Placeholder terrain textures — replace with authored art later.
	_shader_mat.set_shader_parameter(
			"interior_tex",
			PlaceholderTerrainTextures.make_dirt_interior())
	_shader_mat.set_shader_parameter(
			"surface_tex",
			PlaceholderTerrainTextures.make_grass_surface())
	_shader_mat.set_shader_parameter("near_radius_px", near_radius_px)
	_shader_mat.set_shader_parameter("near_fade_px", near_fade_px)
	_shader_mat.set_shader_parameter("edge_width_px", edge_width_px)
	_shader_mat.set_shader_parameter("fade_tau_sec", fade_tau_sec)
	_shader_mat.set_shader_parameter("lifetime_sec", lifetime_sec)
	_shader_mat.set_shader_parameter("edge_boost", edge_boost)
	_shader_mat.set_shader_parameter("ring_width_px", ring_width_px)
	_shader_mat.set_shader_parameter(
			"ring_glow_strength", ring_glow_strength)
	_shader_mat.set_shader_parameter("bayer_tile_px", bayer_tile_px)
	_shader_mat.set_shader_parameter(
			"debug_show_anchor", debug_show_anchor)

	# Frequency palette starts empty in Phase 1; populated in
	# Phase 3 when per-frequency tile art lands. When empty, the
	# shader skips frequency gating and every visible pixel matches.
	_shader_mat.set_shader_parameter(
			"palette_count", 0)
	_shader_mat.set_shader_parameter(
			"current_frequency", Frequency.Type.NONE)


func _process(delta: float) -> void:
	# Resolve follow target lazily (player spawns after renderer).
	if not is_instance_valid(follow_target):
		if is_instance_valid(G.level) and is_instance_valid(G.level.player):
			follow_target = G.level.player
		else:
			_shader_mat.set_shader_parameter(
					"player_screen_pos", Vector2(-10000, -10000))
			return

	# Work in UV space so the shader is independent of the
	# canvas_items stretch. Compute player's canvas-pixel position
	# via get_global_transform_with_canvas, then normalize by the
	# base viewport size.
	var viewport_size: Vector2 = (
			get_viewport().get_visible_rect().size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var world_to_screen: Transform2D = (
			follow_target.get_global_transform_with_canvas())
	var player_screen_px: Vector2 = world_to_screen.origin
	var player_uv: Vector2 = player_screen_px / viewport_size

	_shader_mat.set_shader_parameter("player_uv", player_uv)
	_shader_mat.set_shader_parameter("screen_size_px", viewport_size)
	# Compute world-space anchor for the procedural tile-rendering
	# branch of the composite shader. Assumes a Camera2D with
	# ANCHOR_MODE_DRAG_CENTER so the camera's global_position is the
	# world-space center of the viewport.
	var cam: Camera2D = get_viewport().get_camera_2d()
	if is_instance_valid(cam):
		var zoom: Vector2 = cam.zoom
		var world_per_screen_px: float = (1.0 / zoom.x
				if zoom.x > 0.0 else 1.0)
		var cam_world: Vector2 = cam.global_position
		var world_origin: Vector2 = (cam_world
				- viewport_size * world_per_screen_px * 0.5)
		_shader_mat.set_shader_parameter(
				"world_origin", world_origin)
		_shader_mat.set_shader_parameter(
				"world_per_screen_px", world_per_screen_px)
	# Keep current_frequency in sync with the player so palette
	# gating works immediately once the palette is populated.
	if follow_target is Player:
		_shader_mat.set_shader_parameter(
				"current_frequency",
				(follow_target as Player).current_frequency)

	if debug_show_anchor and _debug_frames_remaining > 0:
		_debug_frames_remaining -= 1
		G.print("[echo] player.world=%s player_px=%s player_uv=%s viewport=%s"
				% [
					follow_target.global_position,
					player_screen_px,
					player_uv,
					viewport_size,
				])

	var canvas_scale: Vector2 = world_to_screen.get_scale()
	var canvas_rot: float = world_to_screen.get_rotation()

	# Advance active pulses and repack uniforms.
	var packed_pulses: Array[Vector4] = []
	var packed_colors: Array[Color] = []
	var packed_cones: Array[Vector4] = []
	packed_pulses.resize(_MAX_PULSES)
	packed_colors.resize(_MAX_PULSES)
	packed_cones.resize(_MAX_PULSES)

	var active_count := 0
	for i in range(_MAX_PULSES):
		var pulse: EchoPulse = _pool[i]
		if pulse == null:
			continue

		pulse.advance(delta)

		if not pulse.is_active():
			var completed := pulse
			_pool[i] = null
			pulse_completed.emit(completed)
			continue

		# Translate the pulse's world-space center into UV space
		# using the same transform the player uses.
		var world_offset: Vector2 = (
				pulse.center - follow_target.global_position)
		var screen_offset_px: Vector2 = (
				world_offset.rotated(canvas_rot) * canvas_scale)
		var pulse_screen_px: Vector2 = (
				player_screen_px + screen_offset_px)
		var pulse_uv: Vector2 = pulse_screen_px / viewport_size
		# Scale speed by the canvas scale so pulses animate at the
		# right on-screen rate regardless of camera zoom.
		var screen_speed: float = (pulse.speed_px_per_sec
				* absf(canvas_scale.x))
		packed_pulses[active_count] = Vector4(
				pulse_uv.x,
				pulse_uv.y,
				pulse.age_sec,
				screen_speed)
		packed_colors[active_count] = Frequency.color_of(
				pulse.frequency)
		packed_cones[active_count] = Vector4(
				pulse.arc_radians,
				pulse.arc_direction_radians,
				0.0, 0.0)
		active_count += 1

	_shader_mat.set_shader_parameter("pulses", packed_pulses)
	_shader_mat.set_shader_parameter("pulse_colors", packed_colors)
	_shader_mat.set_shader_parameter("pulse_cones", packed_cones)
	_shader_mat.set_shader_parameter("pulse_count", active_count)


## Fire a new pulse. Returns the EchoPulse on success or null if the
## pool is full (oldest would be evicted in a polish phase; for now
## the call is dropped).
func emit_pulse(
		center: Vector2,
		frequency: int,
		max_radius_px: float = -1.0,
		damage: int = 10,
		speed_px_per_sec: float = -1.0,
		arc_radians: float = TAU,
		arc_direction_radians: float = 0.0,
) -> EchoPulse:
	var pulse := EchoPulse.new()
	pulse.center = center
	pulse.frequency = frequency
	pulse.max_radius_px = (
			max_radius_px if max_radius_px > 0.0
			else default_pulse_max_radius_px)
	pulse.speed_px_per_sec = (
			speed_px_per_sec if speed_px_per_sec > 0.0
			else default_pulse_speed_px_per_sec)
	pulse.lifetime_sec = lifetime_sec
	pulse.damage = damage
	pulse.arc_radians = arc_radians
	pulse.arc_direction_radians = arc_direction_radians

	var slot := _find_free_slot()
	if slot < 0:
		G.warning("EcholocationRenderer: pulse pool full; dropping")
		return null

	_pool[slot] = pulse
	pulse_emitted.emit(pulse)
	return pulse


func _find_free_slot() -> int:
	for i in range(_MAX_PULSES):
		if _pool[i] == null:
			return i
	return -1


func _build_bayer_texture() -> Texture2D:
	# 8x8 ordered-dither Bayer matrix, values 0..63.
	var bayer := PackedByteArray([
		0, 32,  8, 40,  2, 34, 10, 42,
		48, 16, 56, 24, 50, 18, 58, 26,
		12, 44,  4, 36, 14, 46,  6, 38,
		60, 28, 52, 20, 62, 30, 54, 22,
		 3, 35, 11, 43,  1, 33,  9, 41,
		51, 19, 59, 27, 49, 17, 57, 25,
		15, 47,  7, 39, 13, 45,  5, 37,
		63, 31, 55, 23, 61, 29, 53, 21,
	])
	# Scale 0..63 into 0..255 so it fills the u8 range, then shift
	# by half a step so threshold comparisons are unbiased.
	var scaled := PackedByteArray()
	scaled.resize(bayer.size())
	for i in range(bayer.size()):
		scaled[i] = int(floor((float(bayer[i]) + 0.5) * 255.0 / 64.0))
	var image := Image.create_from_data(
			8, 8, false, Image.FORMAT_L8, scaled)
	return ImageTexture.create_from_image(image)
