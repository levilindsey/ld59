class_name EcholocationRenderer
extends CanvasLayer
## Screen-space darkness-mask overlay that drives echolocation
## visibility. Registers as G.echo so subscribers can connect to
## `pulse_emitted`. Maintains a pool of active EchoPulse objects and
## pushes their screen-space state + frequency colors into the
## composite shader each frame.
##
## Per-pixel terrain type and surface detection are driven by two
## world-spanning R8 textures (`density_tex`, `type_tex`) built from
## C++ terrain state and rebuilt on every `TerrainWorld.chunk_modified`.
## The old tag SubViewport is retired — see `main.gd` for the scene-
## side cleanup.


signal pulse_emitted(pulse: EchoPulse)
signal pulse_completed(pulse: EchoPulse)
## Emitted each time a scheduled bounce-back ping's scheduled_time_sec
## elapses. The audio player listens for this to play per-hit pings
## with pitch + distance-attenuated volume.
signal ping_fired(ping: EchoPing)


const _MAX_PULSES := 8
const _MAX_TAGGED_SPRITES := 32
## Shader ping pool. 32 slots — enough headroom for 24 rays from the
## most-recently-emitted pulse plus residual pings from earlier ones.
const _MAX_PINGS := 32
## Number of rays cast per pulse arc. Per `docs/deferred.md` §1.1
## design. Adjust if terrain gaps feel "missed" by the pings.
const _BOUNCE_RAY_COUNT := 24
## How long (seconds) each visual ping stays on screen after firing.
const _PING_LIFETIME_SEC := 0.5
## Fallback cell-size-px when G.terrain.settings isn't available at
## raycast time. Matches TerrainSettings default.
const _DEFAULT_CELL_SIZE_PX := 8.0
## Cap on how many cells the surface-segment walk will extend in each
## direction from a ping's hit point. 24 cells × default 8 px = 192 px
## which covers most single walls; prevents runaway walks across long
## straight surfaces in authored levels.
const _PING_SEGMENT_MAX_CELLS := 24
## Halo radius for a bug's frequency tag, in WORLD pixels (the
## renderer scales this by canvas_scale before passing to the
## shader, so it tracks camera zoom). 6 = the radius of the bug's
## Glow sprite (12-px scale, half-extent 6), so the tag halo
## visually matches the bug's brightest visible area instead of
## extending past the collision shape into surrounding empty space.
const _BUG_TAG_RADIUS_PX := 6.0

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
@export_range(0.5, 16.0) var bayer_tile_px := 2.0

## Stipple-density fraction applied to non-matching tagged pixels.
## Matching-frequency pixels stipple at full density (1.0); non-
## matching pixels scale down to this value so the player's current
## frequency dominates visually.
@export_range(0.0, 1.0) var non_matching_stipple_factor := 0.2

## Cheap in-shader bloom on matching-type stipples:
## - `matching_bloom_size_multiplier`: Bayer tile is scaled up for
##   matching pixels so each dot covers more screen pixels.
## - `matching_bloom_soft_width`: width of the smoothstep Bayer
##   threshold; > 0 gives matching dots soft edges (fake halo).
## - `matching_bloom_brightness_bump`: extra brightness multiplier
##   applied to matching stipple color, on top of the existing
##   saturation boost, pushing color past 1.0 for an overbright feel.
@export_range(1.0, 3.0) var matching_bloom_size_multiplier := 1.5
@export_range(0.0, 0.5) var matching_bloom_soft_width := 0.15
@export_range(1.0, 3.0) var matching_bloom_brightness_bump := 1.4

@export_range(100.0, 2000.0) var default_pulse_speed_px_per_sec := 600.0
@export_range(100.0, 4000.0) var default_pulse_max_radius_px := 1000.0

## If true, draws a cyan cross at the computed player_uv and prints
## diagnostics for the first few frames after a player is acquired.
## Use to verify world→screen conversion.
@export var debug_show_anchor := false

var _pool: Array[EchoPulse] = []
## Bounce-back ping pool (pending + active). Pool-managed rather than
## scene-node spawned so there's zero allocation after warmup.
var _ping_pool: Array[EchoPing] = []
## Monotonic process-time clock used to schedule pings. Driven by the
## renderer's `_process` delta, so pausing the scene pauses the ping
## schedule too.
var _elapsed_sec: float = 0.0
var _shader_mat: ShaderMaterial
var _debug_frames_remaining: int = 10

## World-spanning density + type textures rebuilt from C++ on every
## `TerrainWorld.chunk_modified`. Kept alive as members so successive
## rebuilds can reuse the same GPU texture via `ImageTexture.update()`
## (avoids a texture alloc every damage event).
var _density_texture: ImageTexture
var _type_texture: ImageTexture
## Set by `_on_chunk_modified` to coalesce multiple dirty chunks in
## one frame (the flow CA can dirty many per tick). Drained in
## `_process`.
var _terrain_textures_dirty: bool = false
## Cell size in world px, cached from TerrainSettings the first time
## the textures get built. Default matches TerrainSettings default.
var _density_cell_size_px: float = 8.0


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
	_ping_pool.resize(_MAX_PINGS)

	_shader_mat = %Mask.material as ShaderMaterial
	G.ensure_valid(_shader_mat, "EcholocationRenderer: Mask missing ShaderMaterial")

	_shader_mat.set_shader_parameter("bayer_tex", _build_bayer_texture())
	# Per-type interior + surface atlases. The scene renders tiles as
	# flat palette color; the composite shader overlays these atlases
	# in the near-field only, so close-by terrain has real art while
	# pulse stipples outside the near-field stay flat palette color.
	_shader_mat.set_shader_parameter(
			"interior_atlas",
			PlaceholderTerrainTextures.make_interior_atlas())
	_shader_mat.set_shader_parameter(
			"surface_atlas",
			PlaceholderTerrainTextures.make_surface_atlas())
	_shader_mat.set_shader_parameter(
			"atlas_slot_count", Frequency.ATLAS_SLOT_COUNT)
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
			"non_matching_stipple_factor", non_matching_stipple_factor)
	_shader_mat.set_shader_parameter(
			"matching_bloom_size_multiplier",
			matching_bloom_size_multiplier)
	_shader_mat.set_shader_parameter(
			"matching_bloom_soft_width", matching_bloom_soft_width)
	_shader_mat.set_shader_parameter(
			"matching_bloom_brightness_bump",
			matching_bloom_brightness_bump)
	_shader_mat.set_shader_parameter(
			"debug_show_anchor", debug_show_anchor)

	# Populate the frequency palette. The shader uses it purely as a
	# type-id → display-color lookup (tagged sprites and `type_tex`
	# pixels alike).
	var palette_uniforms := (
			PlaceholderTerrainTextures.build_palette_uniforms())
	_shader_mat.set_shader_parameter(
			"palette", palette_uniforms["palette"])
	_shader_mat.set_shader_parameter(
			"palette_freqs", palette_uniforms["palette_freqs"])
	_shader_mat.set_shader_parameter(
			"palette_count", palette_uniforms["palette_count"])
	_shader_mat.set_shader_parameter(
			"current_frequency", Frequency.Type.NONE)

	# Wire up terrain-texture rebuild. The first chunk_modified emit
	# (which fires after the initial bake integrates) drives the
	# first texture push. Marking dirty here ensures that if terrain
	# is already baked before _ready runs, the next frame still builds
	# the textures.
	_terrain_textures_dirty = true


func _process(delta: float) -> void:
	_elapsed_sec += delta

	# Lazy-connect to G.terrain.chunk_modified so the density/type
	# textures rebuild after any terrain edit. The connection survives
	# until _exit_tree. G.terrain may not exist yet at _ready time
	# (level load order), so we retry each frame until it does.
	if (is_instance_valid(G.terrain)
			and not G.terrain.chunk_modified.is_connected(
					_on_chunk_modified)):
		G.terrain.chunk_modified.connect(_on_chunk_modified)
		_terrain_textures_dirty = true

	# Rebuild SDF textures if terrain changed since the last frame.
	if _terrain_textures_dirty and is_instance_valid(G.terrain):
		_rebuild_terrain_textures()
		_terrain_textures_dirty = false

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
	# Compute world-space anchor for the near-field atlas sampling in
	# the composite shader. Assumes a Camera2D with
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
		# NONE (blank) pulses are "stipple-only": they still reveal
		# the level but don't damage anything. The PALETTE entry for
		# NONE is fully transparent, which would make the pulse ring
		# invisible; substitute an opaque white so the stipple still
		# renders. Non-NONE pulses get their palette color verbatim.
		packed_colors[active_count] = (
				Color(1.0, 1.0, 1.0, 1.0)
				if pulse.frequency == Frequency.Type.NONE
				else Frequency.color_of(pulse.frequency))
		packed_cones[active_count] = Vector4(
				pulse.arc_radians,
				pulse.arc_direction_radians,
				0.0, 0.0)
		active_count += 1

	_shader_mat.set_shader_parameter("pulses", packed_pulses)
	_shader_mat.set_shader_parameter("pulse_colors", packed_colors)
	_shader_mat.set_shader_parameter("pulse_cones", packed_cones)
	_shader_mat.set_shader_parameter("pulse_count", active_count)

	# Pack tagged sprites (bugs now, enemies later) into the tag-halo
	# uniform. Each entry gives the shader a screen-space circle + a
	# frequency id so pulse stipples can reveal the sprite even when
	# its rendered pixels are too faint or small for palette-match to
	# catch. Radius scales with canvas zoom so the halo stays at a
	# consistent visual size regardless of camera zoom.
	var packed_tags: Array[Vector4] = []
	packed_tags.resize(_MAX_TAGGED_SPRITES)
	var tag_count := 0
	if is_instance_valid(G.bugs):
		var halo_radius_px: float = (_BUG_TAG_RADIUS_PX
				* absf(canvas_scale.x))
		var spawner: BugSpawner = G.bugs as BugSpawner
		for bug: Bug in spawner.get_alive_bugs():
			if tag_count >= _MAX_TAGGED_SPRITES:
				break
			var bug_screen_px: Vector2 = (bug
					.get_global_transform_with_canvas().origin)
			packed_tags[tag_count] = Vector4(
					bug_screen_px.x,
					bug_screen_px.y,
					halo_radius_px,
					float(bug.frequency))
			tag_count += 1
	_shader_mat.set_shader_parameter("tagged_sprites", packed_tags)
	_shader_mat.set_shader_parameter("tagged_sprite_count", tag_count)

	# Advance active pings, fire pending ones whose scheduled time has
	# arrived, and pack into shader uniform arrays. Each entry uses
	# two vec4s:
	#   `pings[i]`          = (hit_uv.xy, age_sec, frequency)
	#   `ping_segments[i]`  = (start_uv.xy, end_uv.xy)
	# `age_sec < 0` encodes "pending" (scheduled but not yet fired).
	var packed_pings: Array[Vector4] = []
	var packed_segments: Array[Vector4] = []
	packed_pings.resize(_MAX_PINGS)
	packed_segments.resize(_MAX_PINGS)
	var ping_active_count := 0
	for i in range(_MAX_PINGS):
		var ping: EchoPing = _ping_pool[i]
		if ping == null:
			continue
		if ping.is_pending():
			# Fire scheduled pings whose time has arrived. `ping_fired`
			# signal drives the audio player.
			if _elapsed_sec >= ping.scheduled_time_sec:
				ping.age_sec = 0.0
				ping_fired.emit(ping)
			else:
				continue
		else:
			ping.advance(delta)
			if ping.age_sec > _PING_LIFETIME_SEC:
				_ping_pool[i] = null
				continue
		var hit_uv := _world_to_uv(
				ping.world_pos,
				follow_target.global_position,
				player_screen_px,
				canvas_rot,
				canvas_scale,
				viewport_size)
		var start_uv := _world_to_uv(
				ping.segment_start,
				follow_target.global_position,
				player_screen_px,
				canvas_rot,
				canvas_scale,
				viewport_size)
		var end_uv := _world_to_uv(
				ping.segment_end,
				follow_target.global_position,
				player_screen_px,
				canvas_rot,
				canvas_scale,
				viewport_size)
		packed_pings[ping_active_count] = Vector4(
				hit_uv.x, hit_uv.y, ping.age_sec, float(ping.frequency))
		packed_segments[ping_active_count] = Vector4(
				start_uv.x, start_uv.y, end_uv.x, end_uv.y)
		ping_active_count += 1
	_shader_mat.set_shader_parameter("pings", packed_pings)
	_shader_mat.set_shader_parameter("ping_segments", packed_segments)
	_shader_mat.set_shader_parameter("ping_count", ping_active_count)


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
	_schedule_pings_for_pulse(pulse)
	pulse_emitted.emit(pulse)
	return pulse


func _find_free_slot() -> int:
	for i in range(_MAX_PULSES):
		if _pool[i] == null:
			return i
	return -1


func _find_free_ping_slot() -> int:
	for i in range(_MAX_PINGS):
		if _ping_pool[i] == null:
			return i
	return -1


## Cast bounce-back rays for a pulse the instant it's emitted, and
## schedule a visual + audio ping for each ray that hits solid
## terrain. Scheduled time is `_elapsed_sec + 2 × dist / speed`
## (outgoing + returning travel). Rays are distributed uniformly
## across the pulse's arc.
func _schedule_pings_for_pulse(pulse: EchoPulse) -> void:
	if not is_instance_valid(G.terrain):
		return
	var cell_size_px: float = _DEFAULT_CELL_SIZE_PX
	if G.terrain.settings != null:
		cell_size_px = G.terrain.settings.cell_size_px
	if cell_size_px <= 0.0:
		return

	var is_full_circle: bool = pulse.arc_radians >= TAU - 0.01
	# Distribute ray angles across the arc. For a full circle, step
	# evenly without duplicating the last ray at the seam.
	var step: float
	var start_angle: float
	if is_full_circle:
		step = TAU / float(_BOUNCE_RAY_COUNT)
		start_angle = 0.0
	else:
		# Center the fan on arc_direction_radians.
		var count_f := float(maxi(_BOUNCE_RAY_COUNT - 1, 1))
		step = pulse.arc_radians / count_f
		start_angle = (pulse.arc_direction_radians
				- pulse.arc_radians * 0.5)

	for i in range(_BOUNCE_RAY_COUNT):
		var angle: float = start_angle + step * float(i)
		var direction := Vector2(cos(angle), sin(angle))
		# DDA march: start one cell off the origin to avoid hitting
		# the cell the player is standing in (or overlapping a few px).
		var dist: float = cell_size_px
		var hit := false
		var hit_pos := Vector2.ZERO
		while dist <= pulse.max_radius_px:
			hit_pos = pulse.center + direction * dist
			if G.terrain.is_cell_non_empty(hit_pos):
				hit = true
				break
			dist += cell_size_px
		if not hit:
			continue
		var slot := _find_free_ping_slot()
		if slot < 0:
			# Out of slots — drop the remaining rays for this pulse.
			break
		var ping := EchoPing.new()
		ping.world_pos = hit_pos
		ping.frequency = pulse.frequency
		ping.hit_angle_rad = angle
		ping.hit_distance_px = dist
		# Compute the colinear surface segment `hit_pos` sits on, so
		# the shader can animate a line outward along the wall rather
		# than a radial ring from the point.
		var segment := _compute_surface_segment(
				hit_pos, direction, cell_size_px)
		ping.segment_start = segment[0]
		ping.segment_end = segment[1]
		# Return delay: pulse travels out at `speed_px_per_sec`, then
		# echoes back at the same speed, so the full round-trip time
		# is `2 × dist / speed`.
		ping.scheduled_time_sec = (_elapsed_sec
				+ 2.0 * dist / pulse.speed_px_per_sec)
		ping.age_sec = -1.0
		_ping_pool[slot] = ping


## Shared world→screen-UV conversion for packing ping positions +
## segment endpoints into shader uniforms. Matches the canvas
## transform used by the main pulse-packing loop.
func _world_to_uv(
		world_pos: Vector2,
		follow_world: Vector2,
		player_screen_px: Vector2,
		canvas_rot: float,
		canvas_scale: Vector2,
		viewport_size: Vector2,
) -> Vector2:
	var offset: Vector2 = world_pos - follow_world
	var screen_offset: Vector2 = offset.rotated(canvas_rot) * canvas_scale
	var screen_px: Vector2 = player_screen_px + screen_offset
	return screen_px / viewport_size


## Walk along the surface tangent in both directions from `hit_pos`
## to find the colinear segment's endpoints. The ray traveled in
## `ray_direction` and stopped at `hit_pos`, so the surface normal
## points roughly back toward the shooter (`-ray_direction`). For
## marching-squares blocky terrain, snap to the dominant cardinal
## axis so the walk follows a straight wall without zigzagging at
## cell corners.
##
## Returns [segment_start, segment_end] in world px. Both endpoints
## equal `hit_pos` if the walk finds no continuous surface.
func _compute_surface_segment(
		hit_pos: Vector2,
		ray_direction: Vector2,
		cell_size_px: float,
) -> Array[Vector2]:
	if cell_size_px <= 0.0:
		return [hit_pos, hit_pos]
	# Surface normal points back toward the shooter, opposite the ray
	# direction. Snap to cardinal so `tangent` runs along a cell face.
	var approx_normal: Vector2 = -ray_direction
	var normal: Vector2
	if absf(approx_normal.x) > absf(approx_normal.y):
		normal = Vector2(signf(approx_normal.x), 0.0)
	else:
		normal = Vector2(0.0, signf(approx_normal.y))
	if normal == Vector2.ZERO:
		# Degenerate — ray direction was zero. Fall back to a point
		# segment.
		return [hit_pos, hit_pos]
	var tangent := Vector2(-normal.y, normal.x)
	# Sample points offset half a cell on either side of the surface.
	# A cell continues the segment iff the inside side is still solid
	# and the outside side is still empty.
	var inside_offset: Vector2 = -normal * cell_size_px * 0.5
	var outside_offset: Vector2 = normal * cell_size_px * 0.5

	var forward_end: Vector2 = hit_pos
	for i in range(1, _PING_SEGMENT_MAX_CELLS + 1):
		var p := hit_pos + tangent * float(i) * cell_size_px
		if not G.terrain.is_cell_non_empty(p + inside_offset):
			break
		if G.terrain.is_cell_non_empty(p + outside_offset):
			break
		forward_end = p

	var back_end: Vector2 = hit_pos
	for i in range(1, _PING_SEGMENT_MAX_CELLS + 1):
		var p := hit_pos - tangent * float(i) * cell_size_px
		if not G.terrain.is_cell_non_empty(p + inside_offset):
			break
		if G.terrain.is_cell_non_empty(p + outside_offset):
			break
		back_end = p

	return [back_end, forward_end]


func _on_chunk_modified(_coords: Vector2i) -> void:
	_terrain_textures_dirty = true


## Rebuild the density + type world-spanning textures from the C++
## terrain's current state, and push them as shader uniforms. First
## call creates `ImageTexture` wrappers; subsequent calls reuse them
## via `update()` so the GPU texture allocation stays stable.
func _rebuild_terrain_textures() -> void:
	if not is_instance_valid(G.terrain):
		return
	var density_image: Image = G.terrain.build_density_image()
	var type_image: Image = G.terrain.build_type_image()
	if density_image == null or type_image == null:
		# No chunks baked yet — try again on the next chunk_modified.
		_terrain_textures_dirty = true
		return

	if _density_texture == null:
		_density_texture = ImageTexture.create_from_image(density_image)
	else:
		# Dimensions can change if the authored level grew; update()
		# requires a matching size, so re-create on mismatch.
		var existing_size: Vector2i = Vector2i(_density_texture.get_size())
		if existing_size != density_image.get_size():
			_density_texture = ImageTexture.create_from_image(density_image)
		else:
			_density_texture.update(density_image)
	if _type_texture == null:
		_type_texture = ImageTexture.create_from_image(type_image)
	else:
		var existing_type_size: Vector2i = Vector2i(_type_texture.get_size())
		if existing_type_size != type_image.get_size():
			_type_texture = ImageTexture.create_from_image(type_image)
		else:
			_type_texture.update(type_image)

	if G.terrain.settings != null:
		_density_cell_size_px = G.terrain.settings.cell_size_px

	var origin_cells: Vector2i = G.terrain.get_world_cell_origin()
	var size_cells: Vector2i = G.terrain.get_world_cell_size()
	var origin_px: Vector2 = Vector2(
			origin_cells.x * _density_cell_size_px,
			origin_cells.y * _density_cell_size_px)
	_shader_mat.set_shader_parameter("density_tex", _density_texture)
	_shader_mat.set_shader_parameter("type_tex", _type_texture)
	_shader_mat.set_shader_parameter(
			"density_world_origin_px", origin_px)
	_shader_mat.set_shader_parameter(
			"density_world_cell_size",
			Vector2(size_cells.x, size_cells.y))
	_shader_mat.set_shader_parameter(
			"density_cell_size_px", _density_cell_size_px)


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
