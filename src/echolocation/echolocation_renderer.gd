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
const _MAX_TAGGED_SPRITES := 48
## Shader ping pool. Large enough to hold all segments in a typical
## pulse's radius plus residuals from earlier pulses still fading.
## Uniform cost: MAX_PINGS × 2 vec4 = 256 vec4s; well within WebGL2
## limits when combined with the other uniform arrays.
const _MAX_PINGS := 128
## How long (seconds) each visual ping stays on screen after firing.
const _PING_LIFETIME_SEC := 0.99
## Fixed-duration envelope for `global_echo_intensity` (sprite
## stipple bonus). Decoupled from `lifetime_sec` so sprite
## stipples (web tiles, bugs, enemies) fade quickly with the
## echo event rather than lingering across the long terrain-
## stipple tail.
const _ECHO_INTENSITY_DURATION_SEC := 1.2
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
const _PARTICLES_PER_DESTROYED_CELL := 2
const _PARTICLE_LIFETIME_SEC := 0.55
const _PARTICLE_BURST_SPEED_PX_PER_SEC := 40.0
const _PARTICLE_GRAVITY_PX_PER_SEC2 := 220.0
const _PARTICLE_RADIUS_PX := 0.7
## Halo radius for a bug's frequency tag, in WORLD pixels (the
## renderer scales this by canvas_scale before passing to the
## shader, so it tracks camera zoom). 6 = the radius of the bug's
## Glow sprite (12-px scale, half-extent 6), so the tag halo
## visually matches the bug's brightest visible area instead of
## extending past the collision shape into surrounding empty space.
const _BUG_TAG_RADIUS_PX := 4.0

## Sentinel stored in the packed tag's `.w` component to flag
## collectible coins for the composite shader's coin-stipple override
## (gold + ROYGBV sprinkles). Must be negative so normal Frequency
## type-ids (all non-negative) can never collide with it.
const _COIN_TAG_SENTINEL := -1.0

## Sentinel for enemies that are in their death-pulse window
## (`Enemy.is_dying()` true). The composite shader repaints the
## stipple in the damage-flash red so a dying enemy's stipple
## matches the expanding red death ring on the sprite itself. Must
## stay < _COIN_TAG_SENTINEL so the `< -1.5` shader branch can
## distinguish them from coins.
const _ENEMY_DYING_TAG_SENTINEL := -2.0

## Fixed stipple intensity used for a dying enemy, regardless of
## velocity or echo state. Persistent = peak so the formula
## `tag_alpha + tag_echo_alpha * intensity` lands at the persistent
## value at every echo intensity, giving a steady red stipple for
## the whole death pulse duration.
const _ENEMY_DYING_STIPPLE_PERSISTENT := 0.5


## Bug stipple strengths. Pushed into `tagged_sprite_alphas[i]`
## (persistent, always-on) and `tagged_sprite_echo_alphas[i]` (echo
## peak). The shader blends between them via `raw_pulse_vis` so the
## boost fades in/out smoothly as an echo pulse sweeps across the
## bug, matching the envelope terrain stipples get. Echo bonus (=
## peak − persistent) is kept small so the echo boost feels like a
## gentle brightening rather than a dense flood of new dots.
const _BUG_STIPPLE_PERSISTENT := 0.4
const _BUG_STIPPLE_ECHO_PEAK := 1.0

## Web-tile stipple strengths. Webs already have their own visible
## sprite art so persistent is intentionally faint — it only needs
## to hint at the frequency tag, not repaint the tile.
## Webs already have visible cobweb sprite art — we want stipples
## ONLY during an echo, no persistent halo. Setting persistent to
## zero means the echo bonus (= peak − persistent) becomes the full
## peak, so the stipple fades cleanly in during the pulse and out
## after.
const _WEB_STIPPLE_PERSISTENT := 0.0
const _WEB_STIPPLE_ECHO_PEAK := 0.8

## Reference enemy movement speed used to normalize velocity into
## a 0..1 fraction. Stationary enemies (velocity = 0) render no
## persistent stipple; enemies at or above this speed render the
## full persistent peak. The same fraction also scales the echo
## boost so a fast-moving enemy lights up more brightly than a
## slow one when an echo sweeps over it.
const _ENEMY_REFERENCE_SPEED_PX_PER_SEC := 75.0

## Enemy stipple strengths, scaled by `velocity_fraction` before
## upload. Persistent is kept low so a moving enemy is a faint
## silhouette hint rather than a dense stippled outline. The echo
## bonus (= peak − persistent) adds an additional slight brighten
## when a pulse lands.
const _ENEMY_STIPPLE_PERSISTENT_MAX := 0.22
const _ENEMY_STIPPLE_ECHO_PEAK_MAX := 0.97

## Coin stipple strengths. Persistent is 0 (coins stay invisible
## without an echo) and the echo peak is only meaningful while a
## pulse/ping is live, so we skip packing coins entirely outside
## those frames to leave room in the tag array for other sprites.
## The shader's coin-stipple override (gold) still layers on top.
const _COIN_STIPPLE_PERSISTENT := 0.0
const _COIN_STIPPLE_ECHO_PEAK := 0.25

## Multiplier applied to `near_radius_px` once the player wins, and
## the duration (seconds) of the animation from 1× up to that peak.
## The close-by aperture expands outward from its gameplay radius to
## reveal a wider patch of textured terrain around the player's
## idle-floor pose, since echolocation pulses are frozen post-win.
## Multiplier applied to `near_radius_px` on game-win to expand
## the fully-visible zone. Sized so the win aperture's fully-
## black boundary (`near_radius * scale + near_fade`) still lands
## at the same pixel it did before the near-field parameters were
## rebalanced: 8 × 10 + 128 = 208, matching the pre-change
## 72 × 2 + 64 = 208.
const _WIN_APERTURE_SCALE := 10.0
const _WIN_APERTURE_ANIMATION_SEC := 1.0

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

@export_range(0.0, 512.0) var near_radius_px := 8.0
@export_range(0.0, 256.0) var near_fade_px := 128.0

## Brightness floor for non-terrain, non-tagged sprite pixels
## (player, enemies, enemy frequency outlines) while they are
## INSIDE the close-by visibility area. 1.0 = sprites stay at full
## brightness across the whole near zone and cut cleanly to black
## outside it. 0.0 = sprites just ride the smooth `near_vis` fade
## (so they darken with distance even inside the near zone). The
## boost is multiplied by a binary near-zone mask in the composite
## shader, so the starfield and other non-sprite content still
## fade to black outside the reveal radius.
@export_range(0.0, 1.0) var sprite_ambient_vis := 1.0

@export_range(1.0, 64.0) var edge_width_px := 12.0
@export_range(0.05, 2.0) var fade_tau_sec := 0.35
@export_range(0.1, 12.0) var lifetime_sec := 7.2
@export_range(1.0, 4.0) var edge_boost := 1.5

@export_range(1.0, 16.0) var ring_width_px := 4.0
@export_range(0.0, 2.0) var ring_glow_strength := 1.2
@export_range(0.5, 16.0) var bayer_tile_px := 2.0

## Stipple-density fraction applied to non-matching tagged pixels.
## Matching-frequency pixels stipple at full density (1.0); non-
## matching pixels scale down to this value so the player's current
## frequency dominates visually.
@export_range(0.0, 1.0) var non_matching_stipple_factor := 0.5

## Peak stipple strength for sprite-tagged pixels (bugs, future
## enemies). Caps the synthetic always-on pulse-vis so bugs read as
## faint pointillist silhouettes rather than solid discs. 0 hides
## sprite stipples entirely; 1 matches terrain stipples at a direct
## pulse.
@export_range(0.0, 1.0) var sprite_tag_stipple_max := 0.25

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
## How long after a pulse fires its per-pulse "matching" emphasis
## (bloom + bigger Bayer + brightness bump) keeps applying to cells
## whose type matches the pulse frequency. Capped well below
## `lifetime_sec` so old in-flight pulses don't keep emphasizing
## across a frequency switch.
@export_range(0.1, 4.0) var matching_emphasis_lifetime_sec := 1.5
## Width of the smooth fade between matching and non-matching
## emphasis as pulse_reveal drops to zero. At pulse_reveal above
## this, matching look is at full strength; below it, the bloom
## dither, color saturation, and brightness bump fade smoothly
## toward the non-matching look. Smaller value = matching stays
## vivid until the very end of the stipple fade.
@export_range(0.01, 0.5) var matching_emphasis_fade_band := 0.15

@export_range(100.0, 2000.0) var default_pulse_speed_px_per_sec := 600.0
@export_range(100.0, 4000.0) var default_pulse_max_radius_px := 120.0

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
## Extra ShaderMaterials that also want the latest `_health_texture`
## pushed into their `health_tex` uniform each frame. Registered via
## `register_secondary_health_material`. Used by the terrain
## punch-through shader so it never diverges from the composite's
## view of damage.
var _secondary_health_materials: Array[ShaderMaterial] = []
## Set by `_on_chunk_modified` to coalesce multiple dirty chunks in
## one frame (the flow CA can dirty many per tick). Drained in
## `_process`.
var _terrain_textures_dirty: bool = false
## Per-aspect dirty hints. `chunk_modified` (full remesh) sets both;
## `health_only_changed` (partial damage with no destruction) sets
## only `_health_dirty`. `_rebuild_terrain_textures` skips the
## density + type build/upload when only health is dirty, saving
## ~2/3 of the per-rebuild allocations + GPU uploads.
var _density_type_dirty: bool = false
var _health_dirty: bool = false

## Diagnostic accumulators for main-thread terrain-texture rebuild
## cost. Reset each time `_maybe_log_main_thread_workload` prints a
## summary. Used to verify whether this work is worth moving off the
## main thread via `WorkerThreadPool`.
var _rebuild_terrain_textures_count_since_log: int = 0
var _rebuild_terrain_textures_usec_since_log: int = 0
var _main_thread_log_last_usec: int = 0
const _MAIN_THREAD_LOG_INTERVAL_USEC: int = 2_000_000
## Cell size in world px, cached from TerrainSettings the first time
## the textures get built. Default matches TerrainSettings default.
var _density_cell_size_px: float = 8.0

## Owns the per-pulse surface-segment enumeration + per-segment
## ping allocation. Holds its own CPU-side type-image cache that we
## re-sync on every terrain rebuild.
var _ping_scheduler: EcholocationPingScheduler

## Cached world-cell origin of the terrain grid, kept in sync with
## the scheduler. Used by `_on_tile_destroyed` to translate a world-
## space hit into damage-age cell coordinates.
var _terrain_origin_cells := Vector2i.ZERO

## Scale factor applied on top of `near_radius_px` before the
## uniform is pushed to the shader. Tween-animated up to
## `_WIN_APERTURE_SCALE` on game-win and snapped back to 1.0 when a
## fresh Level instance spawns (game-over reload).
var _win_aperture_scale: float = 1.0
var _win_aperture_tween: Tween = null
## Instance id of the Level we last observed. Mismatch means the
## level reloaded and any in-flight win-aperture tween should be
## killed and the scale reset.
var _win_aperture_level_id: int = 0

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

## Pre-allocated per-frame uniform buffers. Sized once in `_ready()` to
## their respective `_MAX_*` constants and refilled in place each frame.
## The shader gates iteration on `*_count` uniforms, so trailing stale
## slots are never read. Keeping the buffers persistent avoids ~10 fresh
## `Array`/`Packed*Array` allocations per frame, which matters on web
## (WASM) where allocation is heavier than native.
var _packed_pulses: Array[Vector4] = []
var _packed_pulse_colors: Array[Color] = []
var _packed_pulse_cones: Array[Vector4] = []
var _packed_pulse_freqs: PackedInt32Array = PackedInt32Array()
var _packed_tags: Array[Vector4] = []
var _packed_tag_alphas: PackedFloat32Array = PackedFloat32Array()
var _packed_tag_echo_alphas: PackedFloat32Array = PackedFloat32Array()
var _packed_pings: Array[Vector4] = []
var _packed_ping_segments: Array[Vector4] = []
var _packed_ping_normals: Array[Vector4] = []
var _packed_particles: Array[Vector4] = []

## Cached group memberships used for the per-frame tag-halo pack loop.
## Maintained via `SceneTree.node_added` / `node_removed` so we don't
## walk the full scene tree three times per frame. Defensive
## `is_instance_valid` checks at pack-time guard against any race
## (e.g. queue_free between signal emit and consumption).
var _cached_coins: Array[Coin] = []
var _cached_enemies: Array[Enemy] = []
var _cached_web_tiles: Array[WebTile] = []


func _enter_tree() -> void:
	G.echo = self


func _exit_tree() -> void:
	if G.echo == self:
		G.echo = null


func _ready() -> void:
	# One-time threading diagnostic. `threads` feature is present when
	# the current Godot build supports OS-level threads; on web that
	# requires the dlink+threads template AND a cross-origin-isolated
	# page (COOP/COEP headers). If this prints "threads=false" on a
	# web build, no amount of `WorkerThreadPool` work will help.
	print(
		"[echolocation] OS features: threads=%s web=%s cross_origin_isolated(approx)=%s"
		% [
			OS.has_feature("threads"),
			OS.has_feature("web"),
			OS.has_feature("threads") and OS.has_feature("web"),
		]
	)

	layer = 100
	follow_viewport_enabled = false

	# Pre-allocate pool slots.
	_pool.resize(_MAX_PULSES)
	_ping_pool.resize(_MAX_PINGS)
	_particle_pool.resize(_MAX_PARTICLES)

	# Pre-allocate uniform buffers once. See class-level docs.
	_packed_pulses.resize(_MAX_PULSES)
	_packed_pulse_colors.resize(_MAX_PULSES)
	_packed_pulse_cones.resize(_MAX_PULSES)
	_packed_pulse_freqs.resize(_MAX_PULSES)
	_packed_tags.resize(_MAX_TAGGED_SPRITES)
	_packed_tag_alphas.resize(_MAX_TAGGED_SPRITES)
	_packed_tag_echo_alphas.resize(_MAX_TAGGED_SPRITES)
	_packed_pings.resize(_MAX_PINGS)
	_packed_ping_segments.resize(_MAX_PINGS)
	_packed_ping_normals.resize(_MAX_PINGS)
	_packed_particles.resize(_MAX_PARTICLES)

	_ping_scheduler = EcholocationPingScheduler.new()

	_shader_mat = %Mask.material as ShaderMaterial
	G.ensure_valid(_shader_mat, "EcholocationRenderer: Mask missing ShaderMaterial")

	_shader_mat.set_shader_parameter("bayer_tex", _build_bayer_texture())
	# Seed `health_tex` with an all-full-HP placeholder before the
	# real per-cell health texture is uploaded by
	# `_rebuild_terrain_textures`. Without this, sampling the
	# uninitialized uniform returns 0 (→ damage_frac = 1.0) and the
	# shader paints heavy cracks over every cell during the first
	# few frames of level load.
	_shader_mat.set_shader_parameter(
			"health_tex", _build_full_health_placeholder_texture())
	# Tell the shader what value counts as "full starting HP" so it
	# doesn't render every cell at ~50% damage just because
	# `_DEFAULT_TILE_HEALTH` (128) is below the R8 max (255). The
	# placeholder above is built at the same normalized value, so
	# pre-bake and post-bake frames render consistent zero damage.
	var health_max_norm: float = (
			float(TerrainLevelLoader.DEFAULT_TILE_HEALTH) / 255.0)
	_shader_mat.set_shader_parameter(
			"health_max_norm", health_max_norm)
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
	_shader_mat.set_shader_parameter(
			"sprite_ambient_vis", sprite_ambient_vis)
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
			"sprite_tag_stipple_max", sprite_tag_stipple_max)
	_shader_mat.set_shader_parameter(
			"matching_bloom_size_multiplier",
			matching_bloom_size_multiplier)
	_shader_mat.set_shader_parameter(
			"matching_bloom_soft_width", matching_bloom_soft_width)
	_shader_mat.set_shader_parameter(
			"matching_bloom_brightness_bump",
			matching_bloom_brightness_bump)
	_shader_mat.set_shader_parameter(
			"matching_emphasis_lifetime_sec",
			matching_emphasis_lifetime_sec)
	_shader_mat.set_shader_parameter(
			"matching_emphasis_fade_band",
			matching_emphasis_fade_band)
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

	_push_coin_uniforms()

	# Wire up terrain-texture rebuild. The first chunk_modified emit
	# (which fires after the initial bake integrates) drives the
	# first texture push. Marking dirty here ensures that if terrain
	# is already baked before _ready runs, the next frame still builds
	# the textures.
	_terrain_textures_dirty = true

	# Tag-cache wiring. Defer the initial walk so any sibling/cousin
	# nodes whose `_ready()` adds them to the tracked groups have a
	# chance to register before we snapshot.
	get_tree().node_added.connect(_on_scene_node_added)
	get_tree().node_removed.connect(_on_scene_node_removed)
	_rebuild_tag_caches.call_deferred()


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
			_density_type_dirty = true
			_health_dirty = true
		if (G.terrain.has_signal("health_only_changed")
				and not G.terrain.health_only_changed.is_connected(
					_on_health_only_changed)):
			G.terrain.health_only_changed.connect(
					_on_health_only_changed)
		if not G.terrain.tile_destroyed.is_connected(
				_on_tile_destroyed):
			G.terrain.tile_destroyed.connect(_on_tile_destroyed)

	# Rebuild SDF textures if terrain changed since the last frame.
	if _terrain_textures_dirty and is_instance_valid(G.terrain):
		var rebuild_start_usec := Time.get_ticks_usec()
		_rebuild_terrain_textures()
		var rebuild_elapsed_usec := Time.get_ticks_usec() - rebuild_start_usec
		_terrain_textures_dirty = false
		_density_type_dirty = false
		_health_dirty = false
		_rebuild_terrain_textures_count_since_log += 1
		_rebuild_terrain_textures_usec_since_log += rebuild_elapsed_usec

	_maybe_log_main_thread_workload()

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

	_update_win_aperture()
	_shader_mat.set_shader_parameter(
			"near_radius_px", near_radius_px * _win_aperture_scale)

	# Game-win kills the whole echolocation visual layer: no more
	# active pulses, no tagged sprites, no ping ribbons, no echo
	# envelope. The textured near-field view keeps working via the
	# already-pushed `player_uv` + `world_origin`, so the player can
	# still see themselves in their idle-floor pose against the
	# terrain.
	if is_instance_valid(G.level) and G.level.has_won:
		_shader_mat.set_shader_parameter("pulse_count", 0)
		_shader_mat.set_shader_parameter("tagged_sprite_count", 0)
		_shader_mat.set_shader_parameter("ping_count", 0)
		_shader_mat.set_shader_parameter("global_echo_intensity", 0.0)
		_shader_mat.set_shader_parameter("disable_stipple", true)
		return
	_shader_mat.set_shader_parameter("disable_stipple", false)

	# Advance active pulses and repack uniforms. Buffers are
	# pre-allocated at _ready time and refilled in place here.
	var packed_pulses := _packed_pulses
	var packed_colors := _packed_pulse_colors
	var packed_cones := _packed_pulse_cones
	var packed_freqs := _packed_pulse_freqs

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
		# Per-pulse override wins (alpha > 0 = opt-in) so cosmetic
		# emitters like the destination wayfinding cue can paint a
		# custom hue without needing a whole new Frequency.Type.
		# Otherwise: NONE (blank) pulses are "stipple-only" — they
		# reveal the level but don't damage anything. The PALETTE
		# entry for NONE is fully transparent, which would make the
		# ring invisible, so substitute opaque white. Non-NONE pulses
		# get their palette color verbatim.
		var ring_color: Color
		if pulse.color_override.a > 0.0:
			ring_color = pulse.color_override
		elif pulse.frequency == Frequency.Type.NONE:
			ring_color = Color(1.0, 1.0, 1.0, 1.0)
		else:
			ring_color = Frequency.color_of(pulse.frequency)
		packed_colors[active_count] = ring_color
		# cone.z encodes the ring-only flag (> 0.5 = skip stipple
		# contribution in the composite shader). cone.w is reserved.
		packed_cones[active_count] = Vector4(
				pulse.arc_radians,
				pulse.arc_direction_radians,
				1.0 if pulse.ring_only else 0.0,
				0.0)
		packed_freqs[active_count] = pulse.frequency
		active_count += 1

	_shader_mat.set_shader_parameter("pulses", packed_pulses)
	_shader_mat.set_shader_parameter("pulse_colors", packed_colors)
	_shader_mat.set_shader_parameter("pulse_cones", packed_cones)
	_shader_mat.set_shader_parameter("pulse_freqs", packed_freqs)
	_shader_mat.set_shader_parameter("pulse_count", active_count)

	# Pack tagged sprites (bugs + enemies + web tiles + coins) into
	# the tag-halo uniform. Each entry gives the shader a screen-
	# space circle + a frequency id so the echo pulse's stipple can
	# reveal the sprite even when its rendered pixels are too faint
	# or small for palette-match to catch. Radius scales with canvas
	# zoom so the halo stays at a consistent visual size regardless
	# of camera zoom.
	#
	# Per-tag `alpha` is the stipple-intensity knob. The shader
	# caps it via `sprite_tag_stipple_max`, so passing values > 1
	# here is fine and is how we distinguish "weak persistent" from
	# "strong during-echo" states.
	var packed_tags := _packed_tags
	var packed_tag_alphas := _packed_tag_alphas
	var packed_tag_echo_alphas := _packed_tag_echo_alphas
	var tag_count := 0

	# Global echo intensity — max temporal envelope across every
	# live pulse/ping. Pushed as the `global_echo_intensity`
	# uniform so the composite shader can smoothly ramp sprite
	# stipple bonuses in and out with the echo event. Uses a
	# FIXED short duration (`_ECHO_INTENSITY_DURATION_SEC`) rather
	# than the pulse's full `lifetime_sec` — sprite stipples
	# (web tiles, bugs, enemies) should fire on the echo event
	# and finish quickly, not linger across the long terrain-
	# stipple lifetime tail.
	var global_echo_intensity := 0.0
	for pulse_i in range(_MAX_PULSES):
		var live_pulse: EchoPulse = _pool[pulse_i]
		if live_pulse == null or not live_pulse.is_active():
			continue
		var t_norm: float = clampf(
				live_pulse.age_sec
						/ _ECHO_INTENSITY_DURATION_SEC,
				0.0, 1.0)
		var fade_in: float = smoothstep(0.0, 0.15, t_norm)
		var fade_out: float = 1.0 - smoothstep(0.25, 1.0, t_norm)
		global_echo_intensity = maxf(
				global_echo_intensity, fade_in * fade_out)
	for ping_i in range(_MAX_PINGS):
		var live_ping: EchoPing = _ping_pool[ping_i]
		if live_ping == null or live_ping.is_pending():
			continue
		var ping_life: float = _PING_LIFETIME_SEC
		var ping_t_norm: float = clampf(
				live_ping.age_sec / ping_life, 0.0, 1.0)
		var ping_fade_in: float = smoothstep(0.0, 0.15, ping_t_norm)
		var ping_fade_out: float = 1.0 - smoothstep(
				0.25, 1.0, ping_t_norm)
		global_echo_intensity = maxf(
				global_echo_intensity, ping_fade_in * ping_fade_out)
	_shader_mat.set_shader_parameter(
			"global_echo_intensity", global_echo_intensity)

	# Whether to pack coins at all. Persistent coin stipple is 0,
	# so outside of an active echo they'd contribute nothing and
	# we free up their slots for other sprites.
	var any_echo_active := global_echo_intensity > 0.001

	# Shader evaluates `sprite_stipple = tag_alpha
	# + tag_echo_alpha * global_echo_intensity`. So we pack
	# `tag_echo_alpha` as the BONUS (peak − persistent) rather
	# than the peak itself, so the formula naturally lands at
	# the persistent value at echo_intensity=0 and at the peak
	# at echo_intensity=1.
	#
	# Pack order matters: the shader has a 64-slot cap and webs
	# alone can exceed that, so rare-but-important tags (coins,
	# enemies) go first. Webs, which are visually redundant with
	# their own sprite art, go last.

	# Coins — persistent is 0 so they stay invisible outside an
	# echo. Packed first so they always get slots; the game only
	# has a handful and they're quest-critical to locate.
	if any_echo_active:
		var coin_echo_bonus: float = (
				_COIN_STIPPLE_ECHO_PEAK - _COIN_STIPPLE_PERSISTENT)
		for coin in _cached_coins:
			if tag_count >= _MAX_TAGGED_SPRITES:
				break
			if not is_instance_valid(coin):
				continue
			var coin_screen_px: Vector2 = (coin
					.get_global_transform_with_canvas().origin)
			var coin_radius_px: float = (coin.tag_radius_px
					* absf(canvas_scale.x))
			packed_tags[tag_count] = Vector4(
					coin_screen_px.x,
					coin_screen_px.y,
					coin_radius_px,
					_COIN_TAG_SENTINEL)
			packed_tag_alphas[tag_count] = _COIN_STIPPLE_PERSISTENT
			packed_tag_echo_alphas[tag_count] = coin_echo_bonus
			tag_count += 1

	# Enemies — persistent stipple scaled by movement speed
	# (stationary = 0), with the same fraction scaling the echo
	# bonus so a fast-moving enemy lights up more brightly during
	# an echo than a slow one. Halo radius is per-enemy
	# (`enemy.tag_radius_px`) so differently-shaped silhouettes —
	# compact spider vs elongated coyote — each get coverage.
	var enemy_echo_bonus_max: float = (
			_ENEMY_STIPPLE_ECHO_PEAK_MAX - _ENEMY_STIPPLE_PERSISTENT_MAX)
	for enemy in _cached_enemies:
		if tag_count >= _MAX_TAGGED_SPRITES:
			break
		if not is_instance_valid(enemy):
			continue
		var enemy_screen_px: Vector2 = (enemy
				.get_global_transform_with_canvas().origin)
		var enemy_halo_radius_px: float = (enemy.tag_radius_px
				* absf(canvas_scale.x))
		if enemy.is_dying():
			# Dying enemies stipple in damage-red at a fixed
			# intensity regardless of velocity/echo state, so the
			# death pulse's red flash on the sprite is echoed by a
			# matching red stipple halo from the composite.
			packed_tags[tag_count] = Vector4(
					enemy_screen_px.x,
					enemy_screen_px.y,
					enemy_halo_radius_px,
					_ENEMY_DYING_TAG_SENTINEL)
			packed_tag_alphas[tag_count] = _ENEMY_DYING_STIPPLE_PERSISTENT
			packed_tag_echo_alphas[tag_count] = 0.0
			tag_count += 1
			continue
		var speed: float = enemy.get_current_velocity().length()
		var velocity_fraction: float = clampf(
				speed / _ENEMY_REFERENCE_SPEED_PX_PER_SEC, 0.0, 1.0)
		if velocity_fraction <= 0.001:
			# Stationary, living enemies contribute nothing to
			# stippling, persistent or echo. Skip.
			continue
		packed_tags[tag_count] = Vector4(
				enemy_screen_px.x,
				enemy_screen_px.y,
				enemy_halo_radius_px,
				float(enemy.frequency))
		packed_tag_alphas[tag_count] = (
				velocity_fraction * _ENEMY_STIPPLE_PERSISTENT_MAX)
		packed_tag_echo_alphas[tag_count] = (
				velocity_fraction * enemy_echo_bonus_max)
		tag_count += 1

	# Bugs — faint persistent stipple, echo bonus ramps smoothly
	# with `global_echo_intensity`.
	if is_instance_valid(G.bugs):
		var bug_halo_radius_px: float = (_BUG_TAG_RADIUS_PX
				* absf(canvas_scale.x))
		var bug_echo_bonus: float = (
				_BUG_STIPPLE_ECHO_PEAK - _BUG_STIPPLE_PERSISTENT)
		var spawner: BugSpawner = G.bugs as BugSpawner
		for bug: Bug in spawner.get_alive_bugs():
			if tag_count >= _MAX_TAGGED_SPRITES:
				break
			var bug_screen_px: Vector2 = (bug
					.get_global_transform_with_canvas().origin)
			packed_tags[tag_count] = Vector4(
					bug_screen_px.x,
					bug_screen_px.y,
					bug_halo_radius_px,
					float(bug.frequency))
			var bug_mod: float = bug.modulate.a
			packed_tag_alphas[tag_count] = (
					_BUG_STIPPLE_PERSISTENT * bug_mod)
			packed_tag_echo_alphas[tag_count] = bug_echo_bonus * bug_mod
			tag_count += 1

	# Web tiles — packed last because there can be dozens in a
	# level and they're visually redundant with their own
	# cobweb sprite art; missing a web tag is far less impactful
	# than missing a coin, enemy, or bug.
	var web_echo_bonus: float = (
			_WEB_STIPPLE_ECHO_PEAK - _WEB_STIPPLE_PERSISTENT)
	for web in _cached_web_tiles:
		if tag_count >= _MAX_TAGGED_SPRITES:
			break
		if not is_instance_valid(web):
			continue
		var web_screen_px: Vector2 = (web
				.get_global_transform_with_canvas().origin)
		var web_radius_px: float = (web.tag_radius_px
				* absf(canvas_scale.x))
		# `web.frequency` is a WEB_* marker (8-11); the shader
		# palette only knows base frequencies (RED/GREEN/BLUE/
		# YELLOW), so translate before packing the tag uniform.
		packed_tags[tag_count] = Vector4(
				web_screen_px.x,
				web_screen_px.y,
				web_radius_px,
				float(Frequency.web_type_to_frequency(web.frequency)))
		var web_mod: float = web.modulate.a
		packed_tag_alphas[tag_count] = (
				_WEB_STIPPLE_PERSISTENT * web_mod)
		packed_tag_echo_alphas[tag_count] = web_echo_bonus * web_mod
		tag_count += 1
	_shader_mat.set_shader_parameter("tagged_sprites", packed_tags)
	_shader_mat.set_shader_parameter(
			"tagged_sprite_alphas", packed_tag_alphas)
	_shader_mat.set_shader_parameter(
			"tagged_sprite_echo_alphas", packed_tag_echo_alphas)
	_shader_mat.set_shader_parameter("tagged_sprite_count", tag_count)

	# Advance active pings, fire pending ones whose scheduled time has
	# arrived, and pack into shader uniform arrays. Each entry uses
	# three vec4s:
	#   `pings[i]`          = (hit_uv.xy, age_sec, frequency)
	#   `ping_segments[i]`  = (start_uv.xy, end_uv.xy)
	#   `ping_normals[i]`   = (outward_normal.xy, unused, unused)
	# `age_sec < 0` encodes "pending" (scheduled but not yet fired).
	var packed_pings := _packed_pings
	var packed_segments := _packed_ping_segments
	var packed_normals := _packed_ping_normals
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
	# Refill the pre-allocated particle buffer in place. Trailing
	# stale slots are never read by the shader (it loops to
	# `particle_count`).
	var packed_particles := _packed_particles
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
		particle.velocity.y += (
				_PARTICLE_GRAVITY_PX_PER_SEC2
				* particle.gravity_multiplier
				* delta)
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
		color_override: Color = Color(0, 0, 0, 0),
		ring_only: bool = false,
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
	pulse.color_override = color_override
	pulse.ring_only = ring_only

	var slot := _find_free_slot()
	if slot < 0:
		G.warning("EcholocationRenderer: pulse pool full; dropping")
		return null

	_pool[slot] = pulse
	_ping_scheduler.schedule_pings_for_pulse(
			pulse, _ping_pool, _elapsed_sec, ping_delay_scale)
	pulse_emitted.emit(pulse)
	return pulse


func _find_free_slot() -> int:
	for i in range(_MAX_PULSES):
		if _pool[i] == null:
			return i
	return -1


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
			- _terrain_origin_cells.x)
	var cy: int = (int(floor(world_pos.y / cell_size))
			- _terrain_origin_cells.y)
	if (cx < 0 or cy < 0
			or cx >= _damage_age_width
			or cy >= _damage_age_height):
		return
	var idx: int = cy * _damage_age_width + cx
	_damage_age_bytes[idx] = 255
	_active_damage_cells[Vector2i(cx, cy)] = _DAMAGE_FLASH_FRAMES
	_damage_age_dirty = true


## Spawn `_PARTICLES_PER_DESTROYED_CELL` debris particles at the
## destroyed cell, colored by the tile's `type` via its palette
## slot in the composite shader's particle loop.
func _spawn_debris_particles(world_pos: Vector2, type: int) -> void:
	spawn_burst_particles(
			world_pos,
			_PARTICLES_PER_DESTROYED_CELL,
			type,
			_PARTICLE_BURST_SPEED_PX_PER_SEC,
			_PARTICLE_LIFETIME_SEC)


## Public helper: spawn `count` debris particles at `world_pos`
## with random radial velocities. `frequency_type` drives the
## color — the composite shader indexes the palette by this value,
## so passing `Frequency.Type.RED` gets red particles, etc. Used
## by enemies (red damage-flash color on death) and bugs (their
## own frequency color on consumption) to hook into the same
## visibility pipeline used by cell destruction.
func spawn_burst_particles(
		world_pos: Vector2,
		count: int,
		frequency_type: int,
		speed_px_per_sec: float = _PARTICLE_BURST_SPEED_PX_PER_SEC,
		lifetime_sec: float = _PARTICLE_LIFETIME_SEC,
		gravity_multiplier: float = 1.0) -> void:
	for _i in range(count):
		var slot: int = _claim_particle_slot()
		var angle: float = randf() * TAU
		var speed: float = speed_px_per_sec * (0.6 + randf() * 0.8)
		var particle := EchoParticle.new()
		particle.world_pos = world_pos
		particle.velocity = Vector2(cos(angle), sin(angle)) * speed
		particle.frequency = frequency_type
		particle.age_sec = 0.0
		particle.lifetime_sec = lifetime_sec
		particle.gravity_multiplier = gravity_multiplier
		_particle_pool[slot] = particle


## Register an extra ShaderMaterial that wants the live health
## texture pushed into its `health_tex` uniform. Idempotent. The
## current texture (if any) is pushed immediately; subsequent
## updates happen alongside the composite shader's own update, so
## both shaders always see the same per-cell damage state.
func register_secondary_health_material(
		mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if mat in _secondary_health_materials:
		return
	_secondary_health_materials.append(mat)
	if _health_texture != null:
		mat.set_shader_parameter("health_tex", _health_texture)


## Returns a pool slot index. Prefers a null (free) slot;
## otherwise evicts the OLDEST particle so new bursts always
## render rather than silently dropping when the pool is saturated
## (which used to happen after ~42 cells destroyed in a pulse).
func _claim_particle_slot() -> int:
	var oldest_slot := 0
	var oldest_age := -1.0
	for i in range(_MAX_PARTICLES):
		var p: EchoParticle = _particle_pool[i]
		if p == null:
			return i
		if p.age_sec > oldest_age:
			oldest_age = p.age_sec
			oldest_slot = i
	return oldest_slot


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
	_density_type_dirty = true
	_health_dirty = true


## Partial-damage path: per-cell health changed but no cell was
## destroyed, so the density and type images are unchanged. Skip
## rebuilding them.
func _on_health_only_changed(_coords: Vector2i) -> void:
	_terrain_textures_dirty = true
	_health_dirty = true


## Emits a one-line summary every `_MAIN_THREAD_LOG_INTERVAL_USEC`
## showing main-thread cost of `_rebuild_terrain_textures`. Reveals
## how often the shader-texture rebuild runs and how expensive each
## call is, so we can decide whether to move it onto
## `WorkerThreadPool`.
func _maybe_log_main_thread_workload() -> void:
	var now_usec := Time.get_ticks_usec()
	if _main_thread_log_last_usec == 0:
		_main_thread_log_last_usec = now_usec
		return
	var elapsed_usec := now_usec - _main_thread_log_last_usec
	if elapsed_usec < _MAIN_THREAD_LOG_INTERVAL_USEC:
		return
	print(
		"[echolocation] main-thread %.2fs: rebuild_terrain_textures %d calls %.2fms"
		% [
			float(elapsed_usec) / 1_000_000.0,
			_rebuild_terrain_textures_count_since_log,
			float(_rebuild_terrain_textures_usec_since_log) / 1_000.0,
		]
	)
	_rebuild_terrain_textures_count_since_log = 0
	_rebuild_terrain_textures_usec_since_log = 0
	_main_thread_log_last_usec = now_usec


## Rebuild the density + type world-spanning textures from the C++
## terrain's current state, and push them as shader uniforms. First
## call creates `ImageTexture` wrappers; subsequent calls reuse them
## via `update()` so the GPU texture allocation stays stable.
func _rebuild_terrain_textures() -> void:
	if not is_instance_valid(G.terrain):
		return

	# Default: rebuild everything when neither aspect flag is set
	# (covers explicit `_terrain_textures_dirty = true` writes in
	# `_ready` and the signal-connect path).
	var rebuild_all: bool = not _density_type_dirty and not _health_dirty
	var rebuild_density_type: bool = _density_type_dirty or rebuild_all
	var rebuild_health: bool = _health_dirty or rebuild_all

	if rebuild_density_type:
		var density_image: Image = G.terrain.build_density_image()
		var type_image: Image = G.terrain.build_type_image()
		if density_image == null or type_image == null:
			# No chunks baked yet — try again on the next signal.
			_terrain_textures_dirty = true
			_density_type_dirty = true
			return
		if _density_texture == null:
			_density_texture = ImageTexture.create_from_image(
					density_image)
		else:
			# Dimensions can change if the authored level grew;
			# update() requires a matching size, so re-create on
			# mismatch.
			var existing_size: Vector2i = Vector2i(
					_density_texture.get_size())
			if existing_size != density_image.get_size():
				_density_texture = ImageTexture.create_from_image(
						density_image)
			else:
				_density_texture.update(density_image)
		if _type_texture == null:
			_type_texture = ImageTexture.create_from_image(type_image)
		else:
			var existing_type_size: Vector2i = Vector2i(
					_type_texture.get_size())
			if existing_type_size != type_image.get_size():
				_type_texture = ImageTexture.create_from_image(
						type_image)
			else:
				_type_texture.update(type_image)
		# Hand the type Image (not its bytes) to the scheduler. The
		# scheduler defers `get_data()` until the next pulse fires,
		# so a burst of carving rebuilds collapses into one byte
		# copy on the next pulse — meaningful on web (WASM marshal
		# is the heavy step). Only sync when type actually changed.
		_ping_scheduler.sync_terrain_state(
				type_image,
				G.terrain.get_world_cell_origin(),
				(G.terrain.settings.cell_size_px
						if G.terrain.settings != null
						else _density_cell_size_px))

	if rebuild_health:
		var health_image: Image = G.terrain.build_health_image()
		if health_image != null:
			if _health_texture == null:
				_health_texture = ImageTexture.create_from_image(
						health_image)
			else:
				var existing_health_size: Vector2i = Vector2i(
						_health_texture.get_size())
				if existing_health_size != health_image.get_size():
					_health_texture = ImageTexture.create_from_image(
							health_image)
				else:
					_health_texture.update(health_image)
			_shader_mat.set_shader_parameter(
					"health_tex", _health_texture)
			# Mirror the health texture onto any registered secondary
			# materials (e.g., the terrain's damage-punchthrough
			# shader) so they see the same per-cell damage state
			# without having to rebuild the image themselves.
			for mat in _secondary_health_materials:
				if is_instance_valid(mat):
					mat.set_shader_parameter(
							"health_tex", _health_texture)

	if G.terrain.settings != null:
		_density_cell_size_px = G.terrain.settings.cell_size_px

	var origin_cells: Vector2i = G.terrain.get_world_cell_origin()
	var size_cells: Vector2i = G.terrain.get_world_cell_size()
	var origin_px: Vector2 = Vector2(
			origin_cells.x * _density_cell_size_px,
			origin_cells.y * _density_cell_size_px)

	_terrain_origin_cells = origin_cells
	# Density / type uniforms always re-pushed (cheap RID-passing,
	# not a texture upload). The actual textures only update if the
	# density/type rebuild ran above.
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


## Pushes coin-stipple override settings (gold base color + strength
## multiplier) and the dying-enemy stipple color (damage-flash red)
## into the composite shader. Called once on `_ready`; Settings is
## authored (not live-reloaded) so no per-frame push is needed.
func _push_coin_uniforms() -> void:
	if G.settings == null:
		return
	_shader_mat.set_shader_parameter(
			"coin_stipple_color", G.settings.color_coin_stipple)
	_shader_mat.set_shader_parameter(
			"coin_stipple_strength", G.settings.coin_stipple_strength)
	_shader_mat.set_shader_parameter(
			"dying_enemy_stipple_color",
			G.settings.color_damage_flash)
	_shader_mat.set_shader_parameter(
			"damage_particle_color",
			G.settings.color_damage_flash)


func _build_bayer_texture() -> Texture2D:
	# 8x8 ordered-dither Bayer matrix, values 0..63.
	var bayer := PackedByteArray([
		0, 32, 8, 40, 2, 34, 10, 42,
		48, 16, 56, 24, 50, 18, 58, 26,
		12, 44, 4, 36, 14, 46, 6, 38,
		60, 28, 52, 20, 62, 30, 54, 22,
		3, 35, 11, 43, 1, 33, 9, 41,
		51, 19, 59, 27, 49, 17, 57, 25,
		15, 47, 7, 39, 13, 45, 5, 37,
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


## 1x1 R8 texture used as a placeholder for `health_tex` before the
## real per-cell health data lands. Filled with the default
## starting HP (same value cells bake to) so the shader's
## `damage_frac = (health_max - health) / health_max` formula
## produces 0 damage — no cracks during the load-window.
func _build_full_health_placeholder_texture() -> Texture2D:
	var bytes := PackedByteArray(
			[TerrainLevelLoader.DEFAULT_TILE_HEALTH])
	var image := Image.create_from_data(
			1, 1, false, Image.FORMAT_L8, bytes)
	return ImageTexture.create_from_image(image)


## Drives the close-by visibility aperture scale used by `_process`.
## On the rising edge of `Level.has_won`, kicks off a tween that
## ramps the scale from 1.0 up to `_WIN_APERTURE_SCALE`. On a level
## instance change (game-over reload spawns a fresh Level), kills the
## tween and snaps the scale back to 1.0 so the new gameplay session
## starts with the authored aperture.
func _update_win_aperture() -> void:
	var current_level_id: int = (G.level.get_instance_id()
			if is_instance_valid(G.level) else 0)
	if current_level_id != _win_aperture_level_id:
		_win_aperture_level_id = current_level_id
		if _win_aperture_tween != null and _win_aperture_tween.is_valid():
			_win_aperture_tween.kill()
		_win_aperture_tween = null
		_win_aperture_scale = 1.0
	if (is_instance_valid(G.level)
			and G.level.has_won
			and _win_aperture_tween == null):
		_win_aperture_tween = create_tween()
		_win_aperture_tween.tween_property(
				self,
				"_win_aperture_scale",
				_WIN_APERTURE_SCALE,
				_WIN_APERTURE_ANIMATION_SEC,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Snapshots current group memberships into the per-frame tag caches.
## Called once (deferred) at `_ready()`. Steady-state cache maintenance
## is signal-driven via `_on_scene_node_added` / `_on_scene_node_removed`.
func _rebuild_tag_caches() -> void:
	_cached_coins.clear()
	for n in get_tree().get_nodes_in_group(Coin.GROUP):
		var c := n as Coin
		if c != null:
			_cached_coins.append(c)
	_cached_enemies.clear()
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e != null:
			_cached_enemies.append(e)
	_cached_web_tiles.clear()
	for n in get_tree().get_nodes_in_group(WebTile.GROUP):
		var w := n as WebTile
		if w != null:
			_cached_web_tiles.append(w)


## SceneTree.node_added handler. Defers the membership check by one
## tick because `add_to_group()` typically runs in the new node's
## `_ready()`, which has not yet fired when `node_added` emits.
func _on_scene_node_added(node: Node) -> void:
	_check_added_node.call_deferred(node)


func _check_added_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is Coin:
		if not _cached_coins.has(node):
			_cached_coins.append(node)
	elif node is Enemy:
		if not _cached_enemies.has(node):
			_cached_enemies.append(node)
	elif node is WebTile:
		if not _cached_web_tiles.has(node):
			_cached_web_tiles.append(node)


func _on_scene_node_removed(node: Node) -> void:
	if node is Coin:
		_cached_coins.erase(node)
	elif node is Enemy:
		_cached_enemies.erase(node)
	elif node is WebTile:
		_cached_web_tiles.erase(node)
