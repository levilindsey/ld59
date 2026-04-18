class_name TerrainLevelLoader
extends RefCounted
## Bakes authored level content into a TerrainWorld's density + type
## grids at level load.
##
## Two entry points for Phase 2:
## - `bake_from_tile_map_layer(terrain, tml, type_map)`: walks a
##   TileMapLayer and treats each occupied cell as solid. `type_map`
##   optionally maps tile atlas coords → Frequency.Type enum ints; if
##   omitted, every solid tile is treated as `default_type`.
## - `bake_rect(terrain, rect_world_px, type)`: fills a world-space
##   rectangle with solid terrain of a single type. Handy for hand-
##   coded test scenes.
##
## Both paths group the per-cell data into chunks and push to
## `TerrainWorld.set_cells()` in one call per chunk.


## Bake every used cell in `tml` as a solid tile. `default_type` is
## the Frequency.Type applied when `type_map` has no entry for a
## given tile atlas coord.
static func bake_from_tile_map_layer(
		terrain: Node,
		tml: TileMapLayer,
		default_type: int,
		type_map: Dictionary = {}) -> void:
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

	# Collect solid tiles + their types into a dictionary keyed by
	# Vector2i tile-coord.
	var solid: Dictionary = {}
	for tile_pos in tml.get_used_cells():
		var atlas_coord: Vector2i = tml.get_cell_atlas_coords(tile_pos)
		var type: int = type_map.get(atlas_coord, default_type)
		solid[tile_pos] = type

	_bake_from_solid_map(terrain, solid, cells, cell_size_px,
			cells_per_tile, settings)


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

	# Express the rect in cell coords; synthesize a "solid_cells"
	# map at the cell granularity. Any cell intersecting the rect is
	# solid.
	var min_cx: int = int(floor(rect_world_px.position.x / cell_size_px))
	var min_cy: int = int(floor(rect_world_px.position.y / cell_size_px))
	var max_cx: int = int(floor(
			(rect_world_px.position.x + rect_world_px.size.x)
			/ cell_size_px))
	var max_cy: int = int(floor(
			(rect_world_px.position.y + rect_world_px.size.y)
			/ cell_size_px))

	var solid_cells: Dictionary = {}
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			solid_cells[Vector2i(cx, cy)] = type

	# Pass cells_per_tile=1 so "tile" == "cell".
	_bake_from_solid_map(terrain, solid_cells, cells, cell_size_px,
			1, settings)


## Shared bake: `solid` is a Dictionary<Vector2i, int> where keys are
## positions in "tile-units" (whatever cells_per_tile is) and values
## are Frequency.Type ints.
static func _bake_from_solid_map(
		terrain: Node,
		solid: Dictionary,
		cells: int,
		cell_size_px: float,
		cells_per_tile: int,
		settings: TerrainSettings) -> void:
	if solid.is_empty():
		return

	# Convert the solid-tiles map into a solid-cells map at MS-cell
	# granularity. Each tile covers cells_per_tile x cells_per_tile
	# cells.
	var solid_cells: Dictionary = {}
	for tile_pos in solid:
		var type: int = solid[tile_pos]
		var base_cx: int = tile_pos.x * cells_per_tile
		var base_cy: int = tile_pos.y * cells_per_tile
		for dy in range(cells_per_tile):
			for dx in range(cells_per_tile):
				solid_cells[Vector2i(base_cx + dx, base_cy + dy)] = type

	# Find chunk bounds.
	var min_chunk := Vector2i.ZERO
	var max_chunk := Vector2i.ZERO
	var first := true
	for cell_pos in solid_cells:
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
					solid_cells, chunk_coord, cells)
			terrain.set_cells(chunk_coord, bytes)


static func _bake_chunk(
		solid_cells: Dictionary,
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
					if solid_cells.has(Vector2i(gsx + dx, gsy + dy)):
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
			if solid_cells.has(cell_pos):
				type = solid_cells[cell_pos]
				health = 255
			bytes[density_size + cy * cells + cx] = type
			bytes[density_size + per_cell_size + cy * cells + cx] = health

	return bytes
