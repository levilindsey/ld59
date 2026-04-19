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
## Shader ping pool. Large enough to hold all segments in a typical
## pulse's radius plus residuals from earlier pulses still fading.
## Uniform cost: MAX_PINGS × 2 vec4 = 256 vec4s; well within WebGL2
## limits when combined with the other uniform arrays.
const _MAX_PINGS := 128
## Maximum world-px distance the ping scheduler scans for surfaces.
## Decoupled from `pulse.max_radius_px` because the visible stipple
## wave fades out well before the pulse's damage radius (usually
## ~400 px on screen at typical zoom), so ping lines beyond this
## cap don't register visually anyway. Capping the scan gives a
## large speedup: bbox area scales as radius², so cutting from
## 1000 → 600 is a ~2.8× reduction in cells inspected.
const _PING_SCAN_MAX_RADIUS_PX := 600.0
## How long (seconds) each visual ping stays on screen after firing.
const _PING_LIFETIME_SEC := 0.5
## Minimum dot(outward_normal, toward_pulse) required to keep a
## segment. Segments whose normal points AWAY from the pulse (i.e.,
## back-of-wall surfaces hidden from the player) get culled. 0.0
## keeps everything ≥ perpendicular; positive values tighten to
## only strongly-facing surfaces.
const _PING_PLAYER_FACING_THRESHOLD := 0.0
## Safety cap on LoS DDA walk length (in grid cells crossed). A miss
## past this length is treated as "not occluded" so the segment
## schedules. At cell_size=8 px, 200 cells = 1600 px — more than any
## pulse radius we actually use.
const _PING_LOS_MAX_STEPS := 200
## Fallback cell-size-px when G.terrain.settings isn't available at
## raycast time. Matches TerrainSettings default.
const _DEFAULT_CELL_SIZE_PX := 8.0
## Number of frames the damage-region outline flash stays visible after
## a pulse stamps a cell. At 60 FPS, 30 frames ≈ 0.5 sec.
const _DAMAGE_FLASH_FRAMES := 40

## Debris-particle tuning. Spawned one per destroyed cell (times
## `_PARTICLES_PER_DESTROYED_CELL`); no scene nodes, integrated in
## the renderer's `_process`. Shader renders them as solid colored
## disks, sampled with either the tile atlas (near-field) or flat
## palette color (outside).
const _MAX_PARTICLES := 256
const _PARTICLES_PER_DESTROYED_CELL := 6
const _PARTICLE_LIFETIME_SEC := 0.9
const _PARTICLE_BURST_SPEED_PX_PER_SEC := 40.0
const _PARTICLE_GRAVITY_PX_PER_SEC2 := 220.0
const _PARTICLE_RADIUS_PX := 2.5
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

## Terrain art atlases sampled in the composite shader's near-field.
## Regenerate defaults with `scripts/dump_placeholder_textures.ps1`.
## `interior_atlas` and `surface_atlas` are horizontal strips of
## `Frequency.ATLAS_SLOT_COUNT` slots; `damage_tier_atlas` is a strip
## of `PlaceholderTerrainTextures.DAMAGE_TIER_COUNT` crack tiers.
@export var interior_atlas: Texture2D
@export var surface_atlas: Texture2D
@export var damage_tier_atlas: Texture2D

@export_range(0.0, 512.0) var near_radius_px := 72.0
@export_range(0.0, 128.0) var near_fade_px := 64.0

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
@export_range(0.0, 1.0) var non_matching_stipple_factor := 0.5

## Cheap in-shader bloom on matching-type stipples:
## - `matching_bloom_size_multiplier`: Bayer tile is scaled up for
##   matching pixels so each dot covers more screen pixels.
## - `matching_bloom_soft_width`: width of the smoothstep Bayer
##   threshold; > 0 gives matching dots soft edges (fake halo).
## - `matching_bloom_brightness_bump`: extra brightness multiplier
##   applied to matching stipple color, on top of the existing
##   saturation boost, pushing color past 1.0 for an overbright feel.
@export_range(1.0, 3.0) var matching_bloom_size_multiplier := 2.5
@export_range(0.0, 0.5) var matching_bloom_soft_width := 0.32
@export_range(1.0, 3.0) var matching_bloom_brightness_bump := 2.4

@export_range(100.0, 2000.0) var default_pulse_speed_px_per_sec := 600.0
@export_range(100.0, 4000.0) var default_pulse_max_radius_px := 1000.0

## Scale factor applied to the echo's physical round-trip delay
## (2 × dist / speed). 1.0 = physical; 0.5 = half (snappier feel).
## Low values make echoes feel immediate; high values feel sluggish.
@export_range(0.1, 2.0) var ping_delay_scale := 0.7

## If true, draws a cyan cross at the computed player_uv and prints
## diagnostics for the first few frames after a player is acquired.
## Use to verify world→screen conversion.
@export var debug_show_anchor := false

var _pool: Array[EchoPulse] = []
## Bounce-back ping pool (pending + active). Pool-managed rather than
## scene-node spawned so there's zero allocation after warmup.
var _ping_pool: Array[EchoPing] = []
## Destruction-debris particle pool. Same pool pattern; integrated
## each frame in `_process`.
var _particle_pool: Array[EchoParticle] = []
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
## Per-cell current health, rebuilt from C++ on every `chunk_modified`.
## Feeds the shader's damage-tier crack overlay — cells visibly crack
## as their health drops, before the final destruction pop.
var _health_texture: ImageTexture
## Set by `_on_chunk_modified` to coalesce multiple dirty chunks in
## one frame (the flow CA can dirty many per tick). Drained in
## `_process`.
var _terrain_textures_dirty: bool = false
## Cell size in world px, cached from TerrainSettings the first time
## the textures get built. Default matches TerrainSettings default.
var _density_cell_size_px: float = 8.0

## Cached type-image bytes + dimensions + origin, used by the ping
## scheduler's bulk surface scan. Updated in `_rebuild_terrain_textures`
## alongside the corresponding GPU texture. Scanning the CPU-side
## PackedByteArray is ~O(1) per cell access, making it cheap to walk
## all visible surfaces every pulse without C++ cross-calls.
var _type_image_bytes: PackedByteArray
var _type_image_width: int = 0
var _type_image_height: int = 0
var _type_image_origin_cells: Vector2i = Vector2i.ZERO

## Per-cell R8 texture marking "damage age" for each world cell. 255
## = just damaged; decays to 0 in `_DAMAGE_FLASH_FRAMES` frames. Shader
## samples this to draw a brief outline flash on the boundary of the
## damaged region (see Option B in the echolocation plan). Dimensions
## match the `type_tex`.
var _damage_age_bytes: PackedByteArray
var _damage_age_width: int = 0
var _damage_age_height: int = 0
var _damage_age_texture: ImageTexture
## Active (non-zero) damage cells and their remaining ticks. Bounds
## the per-frame decay cost to O(active), not O(full image).
var _active_damage_cells: Dictionary = {}
## Set whenever `_damage_age_bytes` changes, to schedule a texture
## re-upload on the next `_process`.
var _damage_age_dirty: bool = false


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
	_particle_pool.resize(_MAX_PARTICLES)

	_shader_mat = %Mask.material as ShaderMaterial
	G.ensure_valid(_shader_mat, "EcholocationRenderer: Mask missing ShaderMaterial")

	_shader_mat.set_shader_parameter("bayer_tex", _build_bayer_texture())
	# Per-type interior + surface atlases. The scene renders tiles as
	# flat palette color; the composite shader overlays these atlases
	# in the near-field only, so close-by terrain has real art while
	# pulse stipples outside the near-field stay flat palette color.
	_shader_mat.set_shader_parameter("interior_atlas", interior_atlas)
	_shader_mat.set_shader_parameter("surface_atlas", surface_atlas)
	_shader_mat.set_shader_parameter(
			"damage_tier_atlas", damage_tier_atlas)
	_shader_mat.set_shader_parameter(
			"damage_tier_count",
			PlaceholderTerrainTextures.DAMAGE_TIER_COUNT)
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

	# Lazy-connect to G.terrain signals. The connections survive until
	# _exit_tree. G.terrain may not exist yet at _ready time (level
	# load order), so we retry each frame until it does.
	if is_instance_valid(G.terrain):
		if not G.terrain.chunk_modified.is_connected(
				_on_chunk_modified):
			G.terrain.chunk_modified.connect(_on_chunk_modified)
			_terrain_textures_dirty = true
		if not G.terrain.tile_destroyed.is_connected(
				_on_tile_destroyed):
			G.terrain.tile_destroyed.connect(_on_tile_destroyed)

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
	var packed_freqs: PackedInt32Array = PackedInt32Array()
	packed_pulses.resize(_MAX_PULSES)
	packed_colors.resize(_MAX_PULSES)
	packed_cones.resize(_MAX_PULSES)
	packed_freqs.resize(_MAX_PULSES)

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
		packed_freqs[active_count] = pulse.frequency
		active_count += 1

	_shader_mat.set_shader_parameter("pulses", packed_pulses)
	_shader_mat.set_shader_parameter("pulse_colors", packed_colors)
	_shader_mat.set_shader_parameter("pulse_cones", packed_cones)
	_shader_mat.set_shader_parameter("pulse_freqs", packed_freqs)
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
	# three vec4s:
	#   `pings[i]`          = (hit_uv.xy, age_sec, frequency)
	#   `ping_segments[i]`  = (start_uv.xy, end_uv.xy)
	#   `ping_normals[i]`   = (outward_normal.xy, unused, unused)
	# `age_sec < 0` encodes "pending" (scheduled but not yet fired).
	var packed_pings: Array[Vector4] = []
	var packed_segments: Array[Vector4] = []
	var packed_normals: Array[Vector4] = []
	packed_pings.resize(_MAX_PINGS)
	packed_segments.resize(_MAX_PINGS)
	packed_normals.resize(_MAX_PINGS)
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
		# Rotate normal through the canvas rotation so the shader's
		# translation uses screen-space direction. Scale is uniform so
		# direction is preserved; we don't multiply by canvas_scale
		# (the translation magnitude is already in screen px via the
		# shader's `ping_translate_distance_px`).
		var normal_screen: Vector2 = ping.segment_normal.rotated(
				canvas_rot)
		packed_normals[ping_active_count] = Vector4(
				normal_screen.x, normal_screen.y, 0.0, 0.0)
		ping_active_count += 1
	_shader_mat.set_shader_parameter("pings", packed_pings)
	_shader_mat.set_shader_parameter("ping_segments", packed_segments)
	_shader_mat.set_shader_parameter("ping_normals", packed_normals)
	_shader_mat.set_shader_parameter("ping_count", ping_active_count)

	# Advance + pack debris particles. Gravity pulls +y (screen-down
	# in Godot's convention). Expire on age >= lifetime. Pack as
	# vec4(screen_uv.xy, radius_px_screen, frequency).
	var packed_particles: Array[Vector4] = []
	packed_particles.resize(_MAX_PARTICLES)
	var particle_active_count := 0
	var particle_radius_screen: float = (_PARTICLE_RADIUS_PX
			* absf(canvas_scale.x))
	for i in range(_MAX_PARTICLES):
		var particle: EchoParticle = _particle_pool[i]
		if particle == null:
			continue
		particle.age_sec += delta
		if particle.age_sec >= particle.lifetime_sec:
			_particle_pool[i] = null
			continue
		particle.velocity.y += (_PARTICLE_GRAVITY_PX_PER_SEC2 * delta)
		particle.world_pos += particle.velocity * delta
		var p_uv := _world_to_uv(
				particle.world_pos,
				follow_target.global_position,
				player_screen_px,
				canvas_rot,
				canvas_scale,
				viewport_size)
		packed_particles[particle_active_count] = Vector4(
				p_uv.x,
				p_uv.y,
				particle_radius_screen,
				float(particle.frequency))
		particle_active_count += 1
	_shader_mat.set_shader_parameter("particles", packed_particles)
	_shader_mat.set_shader_parameter(
			"particle_count", particle_active_count)

	# Damage-region outline flash. Decay active cells, re-upload the
	# damage_age_tex if anything changed.
	_decay_damage_flashes()
	_upload_damage_age_texture()


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


## Enumerate every outward-facing surface segment near `pulse.center`
## and schedule a ping per segment. Much cheaper than raycasting —
## we walk the cached `_type_image_bytes` (PackedByteArray access is
## O(1) per cell, no C++ crossings), find contiguous runs of solid
## cells whose same-direction neighbor is empty, and build one segment
## per run. Each ping's scheduled time follows the same `2 × dist /
## speed` rule; `world_pos` is the closest point on the segment to the
## pulse center so the line grows outward from there.
##
## Cost scales with the pulse's damage-radius bounding box (in cells),
## not with a fixed ray count — a 400px pulse at 8px/cell scans a
## ~100×100 = 10k-cell window, four times, for ~40k byte reads +
## minimal arithmetic. Sub-millisecond in practice.
func _schedule_pings_for_pulse(pulse: EchoPulse) -> void:
	if _type_image_bytes.is_empty():
		return
	var cell_size: float = _density_cell_size_px
	if cell_size <= 0.0:
		return
	var origin_cells: Vector2i = _type_image_origin_cells
	var type_w: int = _type_image_width
	var type_h: int = _type_image_height
	if type_w <= 0 or type_h <= 0:
		return

	# Clamp the scan radius so we never inspect more of the world than
	# the visible stipple wave cares about, even if the pulse's damage
	# reaches farther.
	var scan_radius_px: float = minf(
			pulse.max_radius_px, _PING_SCAN_MAX_RADIUS_PX)
	var pulse_cell_x: int = (int(floor(pulse.center.x / cell_size))
			- origin_cells.x)
	var pulse_cell_y: int = (int(floor(pulse.center.y / cell_size))
			- origin_cells.y)
	var radius_cells: int = int(ceil(scan_radius_px / cell_size))
	var min_cx: int = maxi(0, pulse_cell_x - radius_cells)
	var max_cx: int = mini(type_w - 1, pulse_cell_x + radius_cells)
	var min_cy: int = maxi(0, pulse_cell_y - radius_cells)
	var max_cy: int = mini(type_h - 1, pulse_cell_y + radius_cells)
	if min_cx > max_cx or min_cy > max_cy:
		return

	var is_full_circle: bool = pulse.arc_radians >= TAU - 0.01
	var cos_half_arc: float = cos(pulse.arc_radians * 0.5)
	var aim_x: float = cos(pulse.arc_direction_radians)
	var aim_y: float = sin(pulse.arc_direction_radians)
	var radius_sq: float = scan_radius_px * scan_radius_px

	# NORTH faces — cell solid, cell above (cy - 1) empty. Outward
	# normal points -y (up in screen coords). Segments on top edge.
	var normal_north := Vector2(0.0, -1.0)
	for cy in range(min_cy, max_cy + 1):
		var run_start: int = -1
		for cx in range(min_cx, max_cx + 2):
			var has_face: bool = false
			if cx <= max_cx and _type_byte_at(cx, cy) != 0:
				if cy <= 0 or _type_byte_at(cx, cy - 1) == 0:
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cx
			elif run_start >= 0:
				var run_end: int = cx - 1
				var sx: float = (
						(run_start + origin_cells.x) * cell_size)
				var ex: float = (
						(run_end + 1 + origin_cells.x) * cell_size)
				var y: float = (cy + origin_cells.y) * cell_size
				if not _try_schedule_segment_ping(
						pulse, Vector2(sx, y), Vector2(ex, y),
						normal_north, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					return
				run_start = -1

	# SOUTH faces — cell below (cy + 1) empty. Normal +y (down).
	var normal_south := Vector2(0.0, 1.0)
	for cy in range(min_cy, max_cy + 1):
		var run_start: int = -1
		for cx in range(min_cx, max_cx + 2):
			var has_face: bool = false
			if cx <= max_cx and _type_byte_at(cx, cy) != 0:
				if (cy >= type_h - 1
						or _type_byte_at(cx, cy + 1) == 0):
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cx
			elif run_start >= 0:
				var run_end: int = cx - 1
				var sx: float = (
						(run_start + origin_cells.x) * cell_size)
				var ex: float = (
						(run_end + 1 + origin_cells.x) * cell_size)
				var y: float = ((cy + 1 + origin_cells.y)
						* cell_size)
				if not _try_schedule_segment_ping(
						pulse, Vector2(sx, y), Vector2(ex, y),
						normal_south, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					return
				run_start = -1

	# WEST faces — cell to left (cx - 1) empty. Normal -x (left).
	var normal_west := Vector2(-1.0, 0.0)
	for cx in range(min_cx, max_cx + 1):
		var run_start: int = -1
		for cy in range(min_cy, max_cy + 2):
			var has_face: bool = false
			if cy <= max_cy and _type_byte_at(cx, cy) != 0:
				if cx <= 0 or _type_byte_at(cx - 1, cy) == 0:
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cy
			elif run_start >= 0:
				var run_end: int = cy - 1
				var sy: float = (
						(run_start + origin_cells.y) * cell_size)
				var ey: float = (
						(run_end + 1 + origin_cells.y) * cell_size)
				var x: float = (cx + origin_cells.x) * cell_size
				if not _try_schedule_segment_ping(
						pulse, Vector2(x, sy), Vector2(x, ey),
						normal_west, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					return
				run_start = -1

	# EAST faces — cell to right (cx + 1) empty. Normal +x (right).
	var normal_east := Vector2(1.0, 0.0)
	for cx in range(min_cx, max_cx + 1):
		var run_start: int = -1
		for cy in range(min_cy, max_cy + 2):
			var has_face: bool = false
			if cy <= max_cy and _type_byte_at(cx, cy) != 0:
				if (cx >= type_w - 1
						or _type_byte_at(cx + 1, cy) == 0):
					has_face = true
			if has_face:
				if run_start < 0:
					run_start = cy
			elif run_start >= 0:
				var run_end: int = cy - 1
				var sy: float = (
						(run_start + origin_cells.y) * cell_size)
				var ey: float = (
						(run_end + 1 + origin_cells.y) * cell_size)
				var x: float = ((cx + 1 + origin_cells.x)
						* cell_size)
				if not _try_schedule_segment_ping(
						pulse, Vector2(x, sy), Vector2(x, ey),
						normal_east, is_full_circle, cos_half_arc,
						aim_x, aim_y, radius_sq):
					return
				run_start = -1


func _type_byte_at(cx: int, cy: int) -> int:
	if (cx < 0 or cy < 0
			or cx >= _type_image_width
			or cy >= _type_image_height):
		return 0
	return _type_image_bytes[cy * _type_image_width + cx]


## Return true when the straight line from `from_world` to `to_world`
## passes through any non-empty cell between its origin and target.
## Uses Amanatides-Woo grid DDA on `_type_image_bytes`, so no C++
## crossings. The origin cell (whatever cell contains `from_world`)
## and the target cell (whatever contains `to_world`) are NOT
## checked — we only care about intermediate cells that would occlude
## the pulse's line of sight. Out-of-bounds cells pass (treated as
## empty, so segments near the world edge don't false-positive).
func _los_occluded(from_world: Vector2, to_world: Vector2) -> bool:
	if _type_image_bytes.is_empty():
		return false
	var cell_size: float = _density_cell_size_px
	if cell_size <= 0.0:
		return false

	var from_cx_f: float = (from_world.x / cell_size
			- float(_type_image_origin_cells.x))
	var from_cy_f: float = (from_world.y / cell_size
			- float(_type_image_origin_cells.y))
	var to_cx_f: float = (to_world.x / cell_size
			- float(_type_image_origin_cells.x))
	var to_cy_f: float = (to_world.y / cell_size
			- float(_type_image_origin_cells.y))

	var target_cx: int = int(floor(to_cx_f))
	var target_cy: int = int(floor(to_cy_f))
	var cx: int = int(floor(from_cx_f))
	var cy: int = int(floor(from_cy_f))

	# Same cell — nothing between origin and target.
	if cx == target_cx and cy == target_cy:
		return false

	var dx: float = to_cx_f - from_cx_f
	var dy: float = to_cy_f - from_cy_f
	var abs_dx: float = absf(dx)
	var abs_dy: float = absf(dy)
	var step_x: int = 0 if abs_dx < 1e-9 else (1 if dx > 0.0 else -1)
	var step_y: int = 0 if abs_dy < 1e-9 else (1 if dy > 0.0 else -1)
	if step_x == 0 and step_y == 0:
		return false

	var t_delta_x: float = INF if step_x == 0 else 1.0 / abs_dx
	var t_delta_y: float = INF if step_y == 0 else 1.0 / abs_dy

	var t_max_x: float = INF
	if step_x > 0:
		t_max_x = (float(cx + 1) - from_cx_f) / abs_dx
	elif step_x < 0:
		t_max_x = (from_cx_f - float(cx)) / abs_dx

	var t_max_y: float = INF
	if step_y > 0:
		t_max_y = (float(cy + 1) - from_cy_f) / abs_dy
	elif step_y < 0:
		t_max_y = (from_cy_f - float(cy)) / abs_dy

	for _step in range(_PING_LOS_MAX_STEPS):
		if t_max_x < t_max_y:
			cx += step_x
			t_max_x += t_delta_x
		else:
			cy += step_y
			t_max_y += t_delta_y
		# Reached target — line of sight is clear.
		if cx == target_cx and cy == target_cy:
			return false
		# Off the grid — treat as empty (not a blocker).
		if (cx < 0 or cy < 0
				or cx >= _type_image_width
				or cy >= _type_image_height):
			return false
		# Intermediate cell is solid → blocks the ray.
		if _type_byte_at(cx, cy) != 0:
			return true
	return false


## Schedule a ping for the given surface segment if it's in range and
## within the pulse's arc, and its outward normal faces the pulse
## emitter. Returns false only when the ping pool is exhausted
## (caller halts further scan).
func _try_schedule_segment_ping(
		pulse: EchoPulse,
		seg_start: Vector2,
		seg_end: Vector2,
		normal: Vector2,
		is_full_circle: bool,
		cos_half_arc: float,
		aim_x: float,
		aim_y: float,
		radius_sq: float,
) -> bool:
	var seg_vec: Vector2 = seg_end - seg_start
	var seg_len_sq: float = seg_vec.length_squared()
	if seg_len_sq < 1e-6:
		return true

	# Player-facing cull: the segment's outward normal must be
	# pointing roughly toward the pulse emitter. Skips back-of-wall
	# surfaces that are hidden from the player.
	var seg_midpoint: Vector2 = seg_start + seg_vec * 0.5
	var to_pulse: Vector2 = pulse.center - seg_midpoint
	var to_pulse_len: float = to_pulse.length()
	if to_pulse_len > 1e-3:
		var facing: float = normal.dot(to_pulse) / to_pulse_len
		if facing < _PING_PLAYER_FACING_THRESHOLD:
			return true

	var to_start: Vector2 = pulse.center - seg_start
	var proj_t: float = to_start.dot(seg_vec) / seg_len_sq
	proj_t = clampf(proj_t, 0.0, 1.0)
	var closest: Vector2 = seg_start + seg_vec * proj_t
	var dx: float = closest.x - pulse.center.x
	var dy: float = closest.y - pulse.center.y
	var dist_sq: float = dx * dx + dy * dy
	if dist_sq > radius_sq:
		return true
	var dist: float = sqrt(dist_sq)
	if not is_full_circle and dist > 1e-3:
		var cos_ang: float = (dx * aim_x + dy * aim_y) / dist
		if cos_ang < cos_half_arc:
			return true

	# Line-of-sight: skip segments whose closest-point can't be
	# reached in a straight line from the pulse emitter (some
	# intermediate solid cell blocks the path).
	if _los_occluded(pulse.center, closest):
		return true

	var slot: int = _find_free_ping_slot()
	if slot < 0:
		return false

	var ping := EchoPing.new()
	ping.world_pos = closest
	ping.segment_start = seg_start
	ping.segment_end = seg_end
	ping.segment_normal = normal
	ping.frequency = pulse.frequency
	ping.hit_angle_rad = atan2(dy, dx)
	ping.hit_distance_px = dist
	ping.scheduled_time_sec = (_elapsed_sec
			+ 2.0 * dist / pulse.speed_px_per_sec
			* ping_delay_scale)
	ping.age_sec = -1.0
	_ping_pool[slot] = ping
	return true


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


## Handler for `G.terrain.tile_destroyed(world_pos, type)` — stamps
## the destroyed cell in the damage_age texture for the brief flash,
## and spawns debris particles carrying the cell's color.
func _on_tile_destroyed(world_pos: Vector2, type: int) -> void:
	_spawn_debris_particles(world_pos, type)
	if _damage_age_texture == null or _damage_age_bytes.is_empty():
		return
	var cell_size: float = _density_cell_size_px
	if cell_size <= 0.0:
		return
	var cx: int = (int(floor(world_pos.x / cell_size))
			- _type_image_origin_cells.x)
	var cy: int = (int(floor(world_pos.y / cell_size))
			- _type_image_origin_cells.y)
	if (cx < 0 or cy < 0
			or cx >= _damage_age_width
			or cy >= _damage_age_height):
		return
	var idx: int = cy * _damage_age_width + cx
	_damage_age_bytes[idx] = 255
	_active_damage_cells[Vector2i(cx, cy)] = _DAMAGE_FLASH_FRAMES
	_damage_age_dirty = true


## Spawn `_PARTICLES_PER_DESTROYED_CELL` debris particles at the
## destroyed cell, with random radial velocities. Silently drops on
## pool exhaustion — the visual is cosmetic, not critical.
func _spawn_debris_particles(world_pos: Vector2, type: int) -> void:
	for _i in range(_PARTICLES_PER_DESTROYED_CELL):
		var slot: int = _find_free_particle_slot()
		if slot < 0:
			return
		var angle: float = randf() * TAU
		# Small speed jitter so particles don't all fly at the same
		# rate ("explode out very slightly").
		var speed: float = (_PARTICLE_BURST_SPEED_PX_PER_SEC
				* (0.6 + randf() * 0.8))
		var particle := EchoParticle.new()
		particle.world_pos = world_pos
		particle.velocity = Vector2(cos(angle), sin(angle)) * speed
		particle.frequency = type
		particle.age_sec = 0.0
		particle.lifetime_sec = _PARTICLE_LIFETIME_SEC
		_particle_pool[slot] = particle


func _find_free_particle_slot() -> int:
	for i in range(_MAX_PARTICLES):
		if _particle_pool[i] == null:
			return i
	return -1


## Decrement active-damage-cell ticks, updating stored bytes so the
## shader sees a smoothly fading flash. Removes cells once they hit
## zero. Called each frame from `_process`.
func _decay_damage_flashes() -> void:
	if _active_damage_cells.is_empty():
		return
	var to_remove: Array[Vector2i] = []
	var scale: float = 255.0 / float(_DAMAGE_FLASH_FRAMES)
	for key: Vector2i in _active_damage_cells:
		var remaining: int = (_active_damage_cells[key] as int) - 1
		var idx: int = key.y * _damage_age_width + key.x
		if remaining <= 0:
			_damage_age_bytes[idx] = 0
			to_remove.append(key)
		else:
			_active_damage_cells[key] = remaining
			_damage_age_bytes[idx] = int(float(remaining) * scale)
	for key: Vector2i in to_remove:
		_active_damage_cells.erase(key)
	_damage_age_dirty = true


## Re-upload the damage-age texture when `_damage_age_bytes` changed.
## Rebuilds the wrapping `Image` each call because `ImageTexture.update`
## wants a fresh Image — cheap at 500×500 R8 = 250 KB.
func _upload_damage_age_texture() -> void:
	if not _damage_age_dirty:
		return
	if _damage_age_width <= 0 or _damage_age_height <= 0:
		return
	var image := Image.create_from_data(
			_damage_age_width, _damage_age_height, false,
			Image.FORMAT_R8, _damage_age_bytes)
	_damage_age_texture.update(image)
	_damage_age_dirty = false


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
	var health_image: Image = G.terrain.build_health_image()
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
	if health_image != null:
		if _health_texture == null:
			_health_texture = ImageTexture.create_from_image(health_image)
		else:
			var existing_health_size: Vector2i = Vector2i(
					_health_texture.get_size())
			if existing_health_size != health_image.get_size():
				_health_texture = ImageTexture.create_from_image(
						health_image)
			else:
				_health_texture.update(health_image)
		_shader_mat.set_shader_parameter("health_tex", _health_texture)

	if G.terrain.settings != null:
		_density_cell_size_px = G.terrain.settings.cell_size_px

	var origin_cells: Vector2i = G.terrain.get_world_cell_origin()
	var size_cells: Vector2i = G.terrain.get_world_cell_size()
	var origin_px: Vector2 = Vector2(
			origin_cells.x * _density_cell_size_px,
			origin_cells.y * _density_cell_size_px)

	# Cache type bytes + dimensions for the ping scheduler's bulk
	# surface scan (one PackedByteArray copy per chunk_modified event,
	# not per pulse).
	_type_image_bytes = type_image.get_data()
	_type_image_width = size_cells.x
	_type_image_height = size_cells.y
	_type_image_origin_cells = origin_cells
	_shader_mat.set_shader_parameter("density_tex", _density_texture)
	_shader_mat.set_shader_parameter("type_tex", _type_texture)
	_shader_mat.set_shader_parameter(
			"density_world_origin_px", origin_px)
	_shader_mat.set_shader_parameter(
			"density_world_cell_size",
			Vector2(size_cells.x, size_cells.y))
	_shader_mat.set_shader_parameter(
			"density_cell_size_px", _density_cell_size_px)

	# Allocate or resize the damage-age texture to match type_tex's
	# cell dimensions. Reset to all-zero on bounds change.
	if (_damage_age_width != size_cells.x
			or _damage_age_height != size_cells.y
			or _damage_age_texture == null):
		_damage_age_width = size_cells.x
		_damage_age_height = size_cells.y
		_damage_age_bytes = PackedByteArray()
		_damage_age_bytes.resize(size_cells.x * size_cells.y)
		_active_damage_cells.clear()
		var damage_image := Image.create_from_data(
				_damage_age_width, _damage_age_height, false,
				Image.FORMAT_R8, _damage_age_bytes)
		_damage_age_texture = ImageTexture.create_from_image(damage_image)
		_shader_mat.set_shader_parameter(
				"damage_age_tex", _damage_age_texture)


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
