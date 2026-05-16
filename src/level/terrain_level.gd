@tool
class_name TerrainLevel
extends Level
## Level variant whose playable surface is a marching-squares
## TerrainWorld instead of a TileMap.
##
## At RUNTIME: bakes the child TileMapLayer (if present and
## non-empty) into the TerrainWorld; otherwise falls back to a
## hand-coded test rectangle. Wires the player's echo pulse to
## terrain damage.
##
## In the EDITOR (`@tool`): bakes the child TileMapLayer into the
## TerrainWorld synchronously and renders the marching-squares
## preview live, so the designer sees the smooth MS surfaces while
## authoring instead of the blocky tile-grid view. Re-bakes on
## TileMapLayer.changed (debounced via `Engine.get_process_frames()`).


@export var terrain_world_path: NodePath
@export var terrain_settings: Resource
@export var tile_map_layer_path: NodePath
## Optional second TileMapLayer, aligned to the same grid as the
## main tile layer. Any tile painted in it marks the corresponding
## marching-squares cells to start at 10% of their normal health,
## so those regions read as pre-damaged at level load.
@export var damage_paint_layer_path: NodePath

@export_group("Test fallback (used when TileMapLayer is empty)")
@export var test_rect_world_px: Rect2 = Rect2(-320, 32, 640, 256)
@export var test_rect_type: int = Frequency.Type.GREEN
## Thickness of the INDESTRUCTIBLE border around the fallback rect.
## Acts as an anchor so the CC pass has something to call "the main
## world" when the player carves out chunks. Set to 0 to disable.
@export_range(0, 8) var test_rect_border_cells: int = 2
@export var test_rect_border_type: int = Frequency.Type.INDESTRUCTIBLE

@export_group("Authoring")
## Frequency.Type assigned to every tile in the tilemap. Per-tile
## type-from-custom-data lands in Phase 3.
@export var default_terrain_type: int = Frequency.Type.GREEN
## Scene instantiated by the loader whenever it encounters a TileMap
## tile whose `type` custom-data equals `Frequency.Type.WEB`. The
## instance is parented under this level and positioned at the
## tile's world center. Its `frequency` export is populated from the
## tile's `web_frequency` custom data (default GREEN).
@export var web_tile_scene: PackedScene

@export_group("Damage rendering")
## Applied to every terrain chunk's canvas_item so damaged cells
## can drop their alpha toward zero where cracks are authored,
## letting the parallax show through actual punched-out regions.
## If null, terrain renders opaque (old behavior). Intended
## shader: `src/level/terrain_damage_punchthrough.gdshader`.
@export var damage_punchthrough_shader: Shader
## Same atlas the echolocation composite uses for crack tiers.
## Assigned in the scene so both shaders share one authored asset.
@export var damage_tier_atlas: Texture2D


@export_group("Fragments")
## Scene spawned per-cell when a connected-components pass detaches
## an un-anchored island. Each cell falls straight down under simple
## scalar gravity (no rigid-body physics) and merges back into the
## terrain on landing. Staggered by row (bottom first) so cells
## don't self-collide in flight.
@export var falling_cell_scene: PackedScene
## Randomizer stream played spatially at each detachment origin. The
## throttle below caps how often this fires to avoid a wall-of-sound
## when a carve produces many back-to-back detachments.
@export var fwoof_stream: AudioStream
## Minimum seconds between consecutive Fwoof plays, regardless of
## how many detachments the frame produces.
@export_range(0.0, 2.0) var fwoof_throttle_sec: float = 0.15
## Toggle to force a re-bake from the editor inspector. Auto-flips
## back to false after triggering.
@export var refresh_preview: bool = false:
	set(value):
		refresh_preview = false
		if Engine.is_editor_hint():
			_rebake_editor_preview()


var _tilemap_signal_connected: bool = false
var _fwoof_last_time_sec: float = -INF
var _punchthrough_material: ShaderMaterial
## Queue of falling-cell spawn requests that couldn't fit in the
## frame's spawn budget. Each entry is a 4-tuple
## [world_pos: Vector2, type: int, health: int, delay_sec: float].
## Drained in `_process` at `_MAX_FALLING_CELL_SPAWNS_PER_FRAME`
## entries per frame.
var _pending_falling_cells: Array = []


func _enter_tree() -> void:
	_sync_terrain_settings_palette()
	if Engine.is_editor_hint():
		return
	super._enter_tree()
	# Hide the authoring TileMapLayer the instant this level enters
	# the tree. Otherwise the raw tile grid briefly renders for ~1
	# frame (visibly as a "duplicate of the marching-squares terrain"
	# the moment a new level spawns after a death) before
	# `_setup_runtime` gets a chance to toggle it off in `_ready`.
	# The bake still reads its data — visibility doesn't affect it.
	var tml := _get_tile_map_layer()
	if is_instance_valid(tml):
		tml.visible = false
	var damage_tml := _get_damage_paint_layer()
	if is_instance_valid(damage_tml):
		damage_tml.visible = false


## Pushes `Settings` frequency colors into the level's shared
## `TerrainSettings` resource so the C++ terrain shader vertex
## colors match `Frequency.PALETTE`. Runs before the TerrainWorld
## bakes meshes so no post-bake refresh is needed.
func _sync_terrain_settings_palette() -> void:
	if G.settings == null:
		return
	if terrain_settings == null:
		return
	var s: Settings = G.settings
	terrain_settings.set("color_indestructible",
			s.color_frequency_indestructible)
	terrain_settings.set("color_red", s.color_frequency_red)
	terrain_settings.set("color_green", s.color_frequency_green)
	terrain_settings.set("color_blue", s.color_frequency_blue)
	terrain_settings.set("color_liquid", s.color_frequency_liquid)
	terrain_settings.set("color_sand", s.color_frequency_sand)
	terrain_settings.set("color_yellow", s.color_frequency_yellow)
	var web_alpha := s.color_frequency_web_alpha
	terrain_settings.set("color_web_red",
			_with_alpha(s.color_frequency_red, web_alpha))
	terrain_settings.set("color_web_green",
			_with_alpha(s.color_frequency_green, web_alpha))
	terrain_settings.set("color_web_blue",
			_with_alpha(s.color_frequency_blue, web_alpha))
	terrain_settings.set("color_web_yellow",
			_with_alpha(s.color_frequency_yellow, web_alpha))


static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	super._exit_tree()


func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor_preview()
		return
	_setup_runtime()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._physics_process(delta)
	_drain_pending_falling_cells()


## Spawns up to `_MAX_FALLING_CELL_SPAWNS_PER_FRAME` queued
## FallingCell scenes this tick. Called from `_physics_process`
## so the spawn budget runs at a fixed rate regardless of render
## framerate.
func _drain_pending_falling_cells() -> void:
	if falling_cell_scene == null:
		_pending_falling_cells.clear()
		return
	var budget: int = mini(
			_MAX_FALLING_CELL_SPAWNS_PER_FRAME,
			_pending_falling_cells.size())
	for i in range(budget):
		var entry: Array = _pending_falling_cells.pop_front()
		var cell: FallingCell = falling_cell_scene.instantiate()
		add_child(cell)
		cell.configure(entry[0], entry[1], entry[2], entry[3])


# ---- Runtime path -----------------------------------------------------------

func _setup_runtime() -> void:
	var tw := _get_terrain_world()
	if not is_instance_valid(tw):
		G.error("TerrainLevel: no TerrainWorld in scene")
		super._ready()
		return

	# Belt-and-suspenders: also set from GDScript in case the
	# scene-file value gets clobbered by the C++ class init order.
	tw.visibility_layer = 3

	if terrain_settings != null:
		tw.settings = terrain_settings
	G.terrain = tw

	var tml := _get_tile_map_layer()
	if is_instance_valid(tml) and tml.get_used_cells().size() > 0:
		# Log the first few tile positions so we can diagnose any
		# offset between the authored TileMapLayer positions and the
		# cells we end up baking into the TerrainWorld. Only prints
		# once per level load and bounded to ~5 entries so it stays
		# cheap.
		var damage_tml := _get_damage_paint_layer()
		TerrainLevelLoader.bake_from_tile_map_layer(
				tw, tml, default_terrain_type,
				self, web_tile_scene, damage_tml)
		# The tilemap was authoring-only; remove it now that the MS
		# version is what drives gameplay. Hide immediately for the
		# current frame (queue_free doesn't take effect until the
		# frame ends), then queue_free so the node is actually gone
		# on the next frame.
		tml.visible = false
		tml.enabled = false
		tml.queue_free()
		if is_instance_valid(damage_tml):
			damage_tml.visible = false
			damage_tml.enabled = false
			damage_tml.queue_free()
	else:
		_bake_fallback_arena(tw)

	_connect_pulse_damage()
	_connect_fragment_detached(tw)
	super._ready()
	# Wait for the marching-squares worker to finish meshing every
	# chunk the bake queued. The bake itself queues jobs, then
	# `_on_process` integrates results over the next several frames.
	# `get_stats()` surfaces the three counters that together tell us
	# the queue is idle: no more dirty chunks, no jobs in flight, no
	# unintegrated results.
	await _await_terrain_meshed(tw)
	is_terrain_ready = true
	_setup_damage_punchthrough(tw)


## Build and install a ShaderMaterial that multiplies terrain
## alpha toward zero where damage cracks are authored, so the
## parallax background shows through damaged cells instead of the
## solid palette fill the terrain otherwise renders. The same
## health texture the echolocation composite builds is forwarded
## here so both shaders see matching damage state.
func _setup_damage_punchthrough(tw: Object) -> void:
	if damage_punchthrough_shader == null:
		push_warning(
				"TerrainLevel: damage_punchthrough_shader is null;"
				+ " damaged cells will render opaque.")
		return
	if tw == null or not tw.has_method("set_chunk_material"):
		push_warning(
				"TerrainLevel: TerrainWorld is missing "
				+ "set_chunk_material — the kbterrain GDExtension "
				+ "needs to be rebuilt and Godot fully restarted so "
				+ "the new binary is loaded.")
		return
	_punchthrough_material = ShaderMaterial.new()
	_punchthrough_material.shader = damage_punchthrough_shader
	if damage_tier_atlas != null:
		_punchthrough_material.set_shader_parameter(
				"damage_tier_atlas", damage_tier_atlas)
	var cell_size: float = 8.0
	if tw.get("settings") != null:
		cell_size = tw.settings.cell_size_px
	var origin_cells: Vector2i = tw.get_world_cell_origin()
	var size_cells: Vector2i = tw.get_world_cell_size()
	_punchthrough_material.set_shader_parameter(
			"density_world_origin_px",
			Vector2(
					origin_cells.x * cell_size,
					origin_cells.y * cell_size))
	_punchthrough_material.set_shader_parameter(
			"density_cell_size_px", cell_size)
	_punchthrough_material.set_shader_parameter(
			"density_world_cell_size",
			Vector2(size_cells.x, size_cells.y))
	# Push a health texture RIGHT NOW. Without this the shader's
	# `health_tex` uniform resolves to Godot's default sampler
	# (white), damage_frac clamps to 0, and the shader reports
	# every cell as pristine — which leaves the terrain opaque
	# through cracks and reproduces the "palette color shows
	# through" symptom. Echo renderer keeps it in sync thereafter.
	if tw.has_method("build_health_image"):
		var health_image: Image = tw.build_health_image()
		if health_image != null:
			var health_tex := ImageTexture.create_from_image(
					health_image)
			_punchthrough_material.set_shader_parameter(
					"health_tex", health_tex)
	tw.set_chunk_material(_punchthrough_material)
	if is_instance_valid(G.echo):
		G.echo.register_secondary_health_material(
				_punchthrough_material)


## Polls `TerrainWorld.get_stats()` once per frame until the remesh
## queues drain, then returns. Capped at a generous ceiling so a
## hypothetically-stuck worker can't freeze the HUD blackout
## forever — at worst the blackout lifts on a half-meshed terrain,
## which is strictly better than hanging.
func _await_terrain_meshed(tw: Object) -> void:
	const _MAX_WAIT_FRAMES := 180
	for _i in range(_MAX_WAIT_FRAMES):
		if not is_instance_valid(tw):
			return
		var stats: Dictionary = tw.get_stats()
		var dirty := int(stats.get("dirty_chunks", 0))
		var pending_jobs := int(stats.get("pending_jobs", 0))
		var pending_results := int(stats.get("pending_results", 0))
		if dirty == 0 and pending_jobs == 0 and pending_results == 0:
			# Still wait one extra frame so the integrated mesh has a
			# chance to make it to the GPU before we lift the cover.
			await get_tree().process_frame
			return
		await get_tree().process_frame


func _connect_fragment_detached(tw: Node) -> void:
	if tw.has_signal("fragment_detached"):
		if not tw.is_connected("fragment_detached", _on_fragment_detached):
			tw.connect("fragment_detached", _on_fragment_detached)


const _STAGGER_SEC_PER_ROW := 0.04
## Max number of FallingCell nodes spawned in a single frame,
## across all fragment detachments that fire that frame. On web
## (single-threaded WASM) spawning 100+ scenes in one frame
## during a big echo pulse stalls the main thread for a couple
## of seconds and causes the player to get wedged into surfaces
## as the physics tick catches up. Cells beyond this budget are
## deferred to later frames via `_pending_falling_cells`.
const _MAX_FALLING_CELL_SPAWNS_PER_FRAME := 8
## Hard ceiling on the number of pending falling cells kept
## around. A runaway destruction pulse could otherwise queue
## thousands of cells; beyond this, new cells are silently
## dropped (the underlying terrain cell is still destroyed in
## C++, so there's no gameplay impact — just the visual
## fwoomph of cells falling is skipped).
const _MAX_PENDING_FALLING_CELLS := 64


func _on_fragment_detached(
		origin_world: Vector2,
		_mesh_verts: PackedVector2Array,
		_mesh_indices: PackedInt32Array,
		_mesh_colors: PackedColorArray,
		_collision_segments: PackedVector2Array,
		island_size_cells: Vector2i,
		cell_types: PackedByteArray,
		cell_healths: PackedByteArray) -> void:
	if falling_cell_scene == null:
		return
	if not is_instance_valid(G.terrain) or G.terrain.settings == null:
		return
	var cell_size: float = G.terrain.settings.cell_size_px
	var w := island_size_cells.x
	var h := island_size_cells.y
	_play_fwoof_at(origin_world + Vector2(
			w * 0.5 * cell_size, h * 0.5 * cell_size))
	for ly in h:
		for lx in w:
			var idx := ly * w + lx
			var type := int(cell_types[idx])
			if type == Frequency.Type.NONE:
				continue
			if (_pending_falling_cells.size()
					>= _MAX_PENDING_FALLING_CELLS):
				# Queue full — skip the remaining cells' visual
				# spawn. The C++ terrain has already marked them
				# destroyed, so gameplay state is fine; only the
				# fwoomph animation is dropped.
				return
			var world_pos := origin_world + Vector2(
					(lx + 0.5) * cell_size,
					(ly + 0.5) * cell_size)
			# Bottom row falls immediately; each row above waits
			# one stagger tick so the stack slides cohesively.
			var delay := float(h - 1 - ly) * _STAGGER_SEC_PER_ROW
			# Queue rather than spawn synchronously. Spawning 100+
			# scenes in one frame stalls the main thread (especially
			# on single-threaded WASM).
			_pending_falling_cells.append([
					world_pos,
					type,
					int(cell_healths[idx]),
					delay])


## Spawns a one-shot spatial AudioStreamPlayer2D at `world_pos`
## playing the Fwoof randomizer. Throttled so a carve producing
## many consecutive detachments only fires one audible whoosh.
func _play_fwoof_at(world_pos: Vector2) -> void:
	if fwoof_stream == null:
		return
	var now := G.time.get_scaled_play_time()
	if now - _fwoof_last_time_sec < fwoof_throttle_sec:
		return
	_fwoof_last_time_sec = now
	var player := AudioStreamPlayer2D.new()
	player.stream = fwoof_stream
	player.bus = &"SFX"
	player.global_position = world_pos
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _connect_pulse_damage() -> void:
	if is_instance_valid(G.echo):
		if not G.echo.pulse_emitted.is_connected(_on_pulse_emitted):
			G.echo.pulse_emitted.connect(_on_pulse_emitted)


## Two-component pulse damage:
## - "Surface" component: long-range, linear falloff, gated by
##   surface-only + player-facing inside C++ `_apply_damage_to_cell`.
##   This is the pickier precision damage — erodes exposed surfaces
##   of matching cells.
## - "Proximity" component: short-range, cubic-ease-out falloff,
##   applied UNCONDITIONALLY to every matching cell in range
##   (including interior). Sharp drop just past the close radius, so
##   far cells get nearly none. Lets pulses dig a bit into chunky
##   terrain near the player without long-range spray.
const _DAMAGE_FULL_RADIUS_PX := 40.0
## Surface-damage cutoff. Previously 1500 — which meant any
## matching-frequency cell within 1500 px took the full
## `_DAMAGE_MIN_AMOUNT` per pulse. For a 26-HP web tile (well
## below `_DAMAGE_MIN_AMOUNT`), that destroyed every matching web
## on the level in one blast. Tightened to match the visible
## pulse radius so damage can't reach well past what the player
## can see, but left a bit bigger than `default_pulse_max_radius_px
## = 120` so players still feel the erosion "hit the far wall."
const _DAMAGE_MAX_RADIUS_PX := 200.0
const _DAMAGE_FULL_AMOUNT := 256
## Lowered so far-range surface damage can't one-shot low-HP
## web tiles. At the new 200-px cap, cells at the edge now take
## ~40 damage — 1/3 of a 128-HP terrain cell and still
## destructive to a 26-HP web up close, but not instant-kill at
## max range.
const _DAMAGE_MIN_AMOUNT := 40
const _PROXIMITY_DAMAGE_FULL_RADIUS_PX := 40.0
const _PROXIMITY_DAMAGE_MAX_RADIUS_PX := 280.0
const _PROXIMITY_DAMAGE_FULL_AMOUNT := 96
const _PROXIMITY_DAMAGE_MIN_AMOUNT := 8


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	if not is_instance_valid(G.terrain):
		return
	# Only the four colored frequencies carve terrain. NONE (blank
	# "stipple-only" pulse) and any other non-gameplay value skips
	# the damage dispatch entirely. Without this guard, a NONE pulse
	# would pass mask=0 to the C++ `_apply_damage_to_cell`, whose
	# "if mask != 0" early-gate treats 0 as "no filter" and damages
	# every cell in range — a latent pre-existing issue.
	if pulse.frequency < Frequency.Type.RED \
			or pulse.frequency > Frequency.Type.YELLOW:
		return
	var mask := 1 << pulse.frequency
	G.terrain.damage_with_falloff(
			pulse.center,
			_DAMAGE_MAX_RADIUS_PX,
			_DAMAGE_FULL_RADIUS_PX,
			_DAMAGE_FULL_AMOUNT,
			_DAMAGE_MIN_AMOUNT,
			_PROXIMITY_DAMAGE_MAX_RADIUS_PX,
			_PROXIMITY_DAMAGE_FULL_RADIUS_PX,
			_PROXIMITY_DAMAGE_FULL_AMOUNT,
			_PROXIMITY_DAMAGE_MIN_AMOUNT,
			mask)


func spawn_player() -> void:
	super.spawn_player()


# ---- Editor preview ---------------------------------------------------------

func _setup_editor_preview() -> void:
	var tw := _get_terrain_world()
	if not is_instance_valid(tw):
		return
	if terrain_settings != null:
		tw.settings = terrain_settings

	# Hook the tilemap's changed signal for live re-bake.
	var tml := _get_tile_map_layer()
	if is_instance_valid(tml) and not _tilemap_signal_connected:
		if not tml.changed.is_connected(_on_tilemap_changed):
			tml.changed.connect(_on_tilemap_changed)
		_tilemap_signal_connected = true
	var damage_tml := _get_damage_paint_layer()
	if is_instance_valid(damage_tml):
		if not damage_tml.changed.is_connected(_on_tilemap_changed):
			damage_tml.changed.connect(_on_tilemap_changed)

	_rebake_editor_preview()


func _on_tilemap_changed() -> void:
	if Engine.is_editor_hint():
		_rebake_editor_preview()


func _rebake_editor_preview() -> void:
	var tw := _get_terrain_world()
	if not is_instance_valid(tw):
		return
	tw.clear_all()
	var tml := _get_tile_map_layer()
	if is_instance_valid(tml) and tml.get_used_cells().size() > 0:
		# Skip web-spawn in the @tool preview path — the editor
		# doesn't need runtime Area2D instances and spawning under
		# the edited scene pollutes the tree.
		TerrainLevelLoader.bake_from_tile_map_layer(
				tw, tml, default_terrain_type,
				null, null, _get_damage_paint_layer())
	else:
		_bake_fallback_arena(tw)


func _bake_fallback_arena(tw: Node) -> void:
	if test_rect_border_cells > 0:
		TerrainLevelLoader.bake_rect_with_border(
				tw,
				test_rect_world_px,
				test_rect_type,
				test_rect_border_cells,
				test_rect_border_type)
	else:
		TerrainLevelLoader.bake_rect(
				tw, test_rect_world_px, test_rect_type)


# ---- Helpers ----------------------------------------------------------------

func _get_terrain_world() -> Node:
	if terrain_world_path != NodePath():
		var node := get_node_or_null(terrain_world_path)
		if is_instance_valid(node):
			return node
	for child in get_children():
		if child.get_class() == "TerrainWorld":
			return child
	return null


func _get_tile_map_layer() -> TileMapLayer:
	if tile_map_layer_path != NodePath():
		var node := get_node_or_null(tile_map_layer_path)
		if node is TileMapLayer:
			return node as TileMapLayer
	for child in get_children():
		if child is TileMapLayer:
			return child as TileMapLayer
	return null


func _get_damage_paint_layer() -> TileMapLayer:
	if damage_paint_layer_path != NodePath():
		var node := get_node_or_null(damage_paint_layer_path)
		if node is TileMapLayer:
			return node as TileMapLayer
	return null
