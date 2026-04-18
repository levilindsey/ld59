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

@export_group("Test fallback (used when TileMapLayer is empty)")
@export var test_rect_world_px: Rect2 = Rect2(-320, 32, 640, 256)
@export var test_rect_type: int = Frequency.Type.GREEN

@export_group("Authoring")
## Frequency.Type assigned to every tile in the tilemap. Per-tile
## type-from-custom-data lands in Phase 3.
@export var default_terrain_type: int = Frequency.Type.GREEN
## Toggle to force a re-bake from the editor inspector. Auto-flips
## back to false after triggering.
@export var refresh_preview: bool = false:
	set(value):
		refresh_preview = false
		if Engine.is_editor_hint():
			_rebake_editor_preview()


var _tilemap_signal_connected: bool = false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	super._enter_tree()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	super._exit_tree()


func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor_preview()
		return
	_setup_runtime()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	super._input(event)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	super._physics_process(delta)


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
		TerrainLevelLoader.bake_from_tile_map_layer(
				tw, tml, default_terrain_type)
		# The tilemap was authoring-only; hide it now that the MS
		# version is what drives gameplay.
		tml.visible = false
	else:
		TerrainLevelLoader.bake_rect(
				tw, test_rect_world_px, test_rect_type)

	_connect_pulse_damage()
	super._ready()


func _connect_pulse_damage() -> void:
	if is_instance_valid(G.echo):
		if not G.echo.pulse_emitted.is_connected(_on_pulse_emitted):
			G.echo.pulse_emitted.connect(_on_pulse_emitted)


## Distance-attenuated pulse damage. Full-damage band is half the
## player's near-visible radius so the player has to be close to
## reliably break tiles; max range still tracks the composite
## shader's stipple_fade_end_px. All damage values halved from the
## "kill in one shot up close" baseline, so cells take ~2 hits at
## point-blank and ~12 at the edge of the visible range.
const _DAMAGE_FULL_RADIUS_PX := 40.0
const _DAMAGE_MAX_RADIUS_PX := 420.0
const _DAMAGE_FULL_AMOUNT := 128
const _DAMAGE_MIN_AMOUNT := 22


func _on_pulse_emitted(pulse: EchoPulse) -> void:
	if not is_instance_valid(G.terrain):
		return
	var mask: int = 0
	if pulse.frequency > 0 and pulse.frequency <= 30:
		mask = 1 << pulse.frequency
	G.terrain.damage_with_falloff(
			pulse.center,
			_DAMAGE_MAX_RADIUS_PX,
			_DAMAGE_FULL_RADIUS_PX,
			_DAMAGE_FULL_AMOUNT,
			_DAMAGE_MIN_AMOUNT,
			mask)


func spawn_player() -> void:
	super.spawn_player()
	if is_instance_valid(player) and is_instance_valid(G.terrain):
		# Try to find the actual terrain surface above the spawn
		# point; fall back to the test rect's top edge.
		var spawn_x: float = %PlayerSpawnPoint.global_position.x
		var surface_y: float = G.terrain.get_surface_height(
				spawn_x, 4096.0)
		if is_nan(surface_y):
			surface_y = test_rect_world_px.position.y
		player.global_position = Vector2(
				spawn_x, surface_y - player.half_size.y - 1.0)


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
		TerrainLevelLoader.bake_from_tile_map_layer(
				tw, tml, default_terrain_type)
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
