class_name TerrainLevelLoader
extends RefCounted
## Bakes authored level content into a TerrainWorld's density + type
## grids at level load.
##
## Two entry points for Phase 2/3:
## - `bake_from_tile_map_layer(terrain, tml, default_type)`: walks a
##   TileMapLayer and treats each occupied cell as solid. Per-tile
##   `type` and `initial_health` come from TileSet custom data
##   layers; tiles without either value fall back to `default_type`
##   and full health (255). Configure the custom data layers on
##   `default_tile_set.tres` and set them per-atlas-tile in the
##   TileSet editor.
## - `bake_rect(terrain, rect_world_px, type)`: fills a world-space
##   rectangle with solid terrain of a single type. Handy for hand-
##   coded test scenes.
## - `bake_rect_with_border(terrain, rect_world_px, inner_type,
##   border_cells, border_type)`: fills a rectangle with a wall of
##   `border_type` around an interior of `inner_type`. Used by the
##   terrain-level fallback arena so Phase 4 CC detachment has real
##   INDESTRUCTIBLE anchors to test against.
##
## All paths group the per-cell data into chunks and push to
## `TerrainWorld.set_cells()` in one call per chunk.


const _CUSTOM_DATA_TYPE := "type"
const _CUSTOM_DATA_HEALTH := "initial_health"


## Bake every used cell in `tml` as a solid tile. Per-tile `type` and
## `initial_health` are read from the TileSet's custom data layers;
## tiles without values fall back to `default_type` / 255.
static func bake_from_tile_map_layer(
		terrain: Node,
		tml: TileMapLayer,
		default_type: int) -> void:
	if not is_instance_valid(terrain) or not is_instance_valid(tml):
		return
	var settings: TerrainSettings = terrain.settings
	if settings == null:
		G.error("TerrainLevelLoader: terrain has no settings")
		return

	var cells: int = settings.chunk_cells
	var cell_size_px: float = settings.cell_size_px
	var tile_size_px: int = int(tml.tile_set.tile_size.x)
	if tile_size_px <= 0:
		G.error("TerrainLevelLoader: tile_set.tile_size invalid")
		return
	var cells_per_tile: int = int(tile_size_px / cell_size_px)
	if cells_per_tile <= 0:
		G.error(
				"TerrainLevelLoader: cell_size_px=%s exceeds tile_size=%s"
				% [cell_size_px, tile_size_px])
		return

	# Collect solid tiles + per-tile type/health into two dictionaries
	# keyed by Vector2i tile-coord.
	var tile_type: Dictionary = {}
	var tile_health: Dictionary = {}
	for tile_pos in tml.get_used_cells():
		var type_from_data: int = _read_custom_data_int(
				tml, tile_pos, _CUSTOM_DATA_TYPE, -1)
		var health_from_data: int = _read_custom_data_int(
				tml, tile_pos, _CUSTOM_DATA_HEALTH, -1)
		tile_type[tile_pos] = (
				type_from_data
				if type_from_data > 0
				else default_type)
		tile_health[tile_pos] = (
				health_from_data
				if health_from_data >= 0
				else 255)

	_bake_from_solid_map(terrain, tile_type, tile_health,
			cells, cell_size_px, cells_per_tile, settings)


## Fill a world-space rectangle with a single type. Rectangle is in
## world pixels; cells entirely within or overlapping the rect are
## marked solid.
static func bake_rect(
		terrain: Node,
		rect_world_px: Rect2,
		type: int) -> void:
	if not is_instance_valid(terrain):
		return
	var settings: TerrainSettings = terrain.settings
	if settings == null:
		return

	var cells: int = settings.chunk_cells
	var cell_size_px: float = settings.cell_size_px

	var min_cx: int = int(floor(rect_world_px.position.x / cell_size_px))
	var min_cy: int = int(floor(rect_world_px.position.y / cell_size_px))
	var max_cx: int = int(floor(
			(rect_world_px.position.x + rect_world_px.size.x)
			/ cell_size_px))
	var max_cy: int = int(floor(
			(rect_world_px.position.y + rect_world_px.size.y)
			/ cell_size_px))

	var solid_type: Dictionary = {}
	var solid_health: Dictionary = {}
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var key := Vector2i(cx, cy)
			solid_type[key] = type
			solid_health[key] = 255

	# Pass cells_per_tile=1 so "tile" == "cell".
	_bake_from_solid_map(terrain, solid_type, solid_health,
			cells, cell_size_px, 1, settings)


## Fill a world-space rectangle with `inner_type` surrounded by a
## `border_cells`-thick wall of `border_type`. Used to author a
## playable test arena with INDESTRUCTIBLE anchors so Phase 4 CC
## detachment has something to anchor against.
static func bake_rect_with_border(
		terrain: Node,
		rect_world_px: Rect2,
		inner_type: int,
		border_cells: int,
		border_type: int) -> void:
	if not is_instance_valid(terrain):
		return
	var settings: TerrainSettings = terrain.settings
	if settings == null:
		return

	var cells: int = settings.chunk_cells
	var cell_size_px: float = settings.cell_size_px

	var min_cx: int = int(floor(rect_world_px.position.x / cell_size_px))
	var min_cy: int = int(floor(rect_world_px.position.y / cell_size_px))
	var max_cx: int = int(floor(
			(rect_world_px.position.x + rect_world_px.size.x)
			/ cell_size_px))
	var max_cy: int = int(floor(
			(rect_world_px.position.y + rect_world_px.size.y)
			/ cell_size_px))

	var solid_type: Dictionary = {}
	var solid_health: Dictionary = {}
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var in_border := (
					cx - min_cx < border_cells
					or max_cx - cx < border_cells
					or cy - min_cy < border_cells
					or max_cy - cy < border_cells)
			var key := Vector2i(cx, cy)
			solid_type[key] = border_type if in_border else inner_type
			solid_health[key] = 255

	_bake_from_solid_map(terrain, solid_type, solid_health,
			cells, cell_size_px, 1, settings)


## Shared bake: `tile_type` and `tile_health` are parallel
## Dictionary<Vector2i, int> maps keyed by tile-unit position.
static func _bake_from_solid_map(
		terrain: Node,
		tile_type: Dictionary,
		tile_health: Dictionary,
		cells: int,
		cell_size_px: float,
		cells_per_tile: int,
		settings: TerrainSettings) -> void:
	if tile_type.is_empty():
		return

	# Expand tile-granularity maps to cell-granularity.
	var solid_type: Dictionary = {}
	var solid_health: Dictionary = {}
	for tile_pos in tile_type:
		var type: int = tile_type[tile_pos]
		var health: int = tile_health.get(tile_pos, 255)
		var base_cx: int = tile_pos.x * cells_per_tile
		var base_cy: int = tile_pos.y * cells_per_tile
		for dy in range(cells_per_tile):
			for dx in range(cells_per_tile):
				var key := Vector2i(base_cx + dx, base_cy + dy)
				solid_type[key] = type
				solid_health[key] = health

	# Find chunk bounds.
	var min_chunk := Vector2i.ZERO
	var max_chunk := Vector2i.ZERO
	var first := true
	for cell_pos in solid_type:
		var chunk_x: int = int(floor(float(cell_pos.x) / cells))
		var chunk_y: int = int(floor(float(cell_pos.y) / cells))
		if first:
			min_chunk = Vector2i(chunk_x, chunk_y)
			max_chunk = Vector2i(chunk_x, chunk_y)
			first = false
		else:
			min_chunk.x = min(min_chunk.x, chunk_x)
			min_chunk.y = min(min_chunk.y, chunk_y)
			max_chunk.x = max(max_chunk.x, chunk_x)
			max_chunk.y = max(max_chunk.y, chunk_y)

	# Build and upload each chunk.
	for chunk_y in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			var bytes := _bake_chunk(
					solid_type, solid_health, chunk_coord, cells)
			terrain.set_cells(chunk_coord, bytes)


static func _bake_chunk(
		solid_type: Dictionary,
		solid_health: Dictionary,
		chunk_coord: Vector2i,
		cells: int) -> PackedByteArray:
	var density_size := (cells + 1) * (cells + 1)
	var per_cell_size := cells * cells
	var bytes := PackedByteArray()
	bytes.resize(density_size + 2 * per_cell_size)

	# Density samples. A sample at global cell-corner (gsx, gsy) is
	# solid (255) iff any of the 4 adjacent cells is solid.
	for sy in range(cells + 1):
		for sx in range(cells + 1):
			var gsx: int = chunk_coord.x * cells + sx
			var gsy: int = chunk_coord.y * cells + sy
			var any_solid := false
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					if solid_type.has(Vector2i(gsx + dx, gsy + dy)):
						any_solid = true
						break
				if any_solid:
					break
			bytes[sy * (cells + 1) + sx] = 255 if any_solid else 0

	# Per-cell type + health.
	for cy in range(cells):
		for cx in range(cells):
			var gcx: int = chunk_coord.x * cells + cx
			var gcy: int = chunk_coord.y * cells + cy
			var type: int = Frequency.Type.NONE
			var health: int = 0
			var cell_pos := Vector2i(gcx, gcy)
			if solid_type.has(cell_pos):
				type = solid_type[cell_pos]
				health = solid_health.get(cell_pos, 255)
			bytes[density_size + cy * cells + cx] = type
			bytes[density_size + per_cell_size + cy * cells + cx] = health

	return bytes


## Fetch an int-valued custom data layer at the given cell. Returns
## `fallback` if the layer is missing or the cell has no tile data.
static func _read_custom_data_int(
		tml: TileMapLayer,
		tile_pos: Vector2i,
		layer_name: String,
		fallback: int) -> int:
	var tile_data := tml.get_cell_tile_data(tile_pos)
	if tile_data == null:
		return fallback
	var raw: Variant = tile_data.get_custom_data(layer_name)
	if typeof(raw) != TYPE_INT:
		return fallback
	return int(raw)
