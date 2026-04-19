class_name ProcgenTileMapWriter
extends RefCounted
## Converts a `ProcgenLevel.Result` into concrete edits on a Godot
## scene: populates the `Tiles` TileMapLayer with atlas cells,
## repositions `%PlayerSpawnPoint` to the spawn tile's world
## position, and spawns entity hints (bug regions, enemy spawners,
## destination) as children of the level root.
##
## The scene is modified in-memory; the runner script packs + saves
## it to disk. Every spawned child has `owner = level_root` set so
## `PackedScene.pack()` includes them in the saved .tscn.


const _TILE_SIZE_PX := 16
const _TILE_SET_SOURCE_ID := 2


## Atlas coord per Frequency.Type. Must match the custom_data_0
## mappings authored in `default_tile_set.tres`. Row 0 atlas col = type.
## Exposed (no underscore) because the adjust path in
## `procgen_autoload.gd` also needs to invert it.
## Map from EntityHint.kind strings to Enemy.Kind enum values.
## Kept as a file-level constant so set_piece_library and the
## writer stay in sync on the hint vocabulary.
const _HINT_TO_ENEMY_KIND := {
	"enemy_spider": Enemy.Kind.SPIDER,
	"enemy_coyote": Enemy.Kind.COYOTE,
	"enemy_owl": Enemy.Kind.OWL,
}


const TYPE_TO_ATLAS_COORD := {
	Frequency.Type.INDESTRUCTIBLE: Vector2i(1, 0),
	Frequency.Type.RED: Vector2i(2, 0),
	Frequency.Type.GREEN: Vector2i(3, 0),
	Frequency.Type.BLUE: Vector2i(4, 0),
	Frequency.Type.LIQUID: Vector2i(5, 0),
	Frequency.Type.SAND: Vector2i(6, 0),
	Frequency.Type.YELLOW: Vector2i(7, 0),
	Frequency.Type.WEB_RED: Vector2i(8, 0),
	Frequency.Type.WEB_GREEN: Vector2i(9, 0),
	Frequency.Type.WEB_BLUE: Vector2i(10, 0),
	Frequency.Type.WEB_YELLOW: Vector2i(11, 0),
}


## Apply the procgen result onto an already-instantiated level scene.
## `level_root` is the root node (`TerrainLevel`). `tml` is the child
## TileMapLayer named `Tiles`. Returns the list of child nodes added
## so the caller can verify.
static func apply(
		level_root: Node,
		tml: TileMapLayer,
		result: ProcgenLevel.Result,
		destination_scene: PackedScene,
		bug_spawn_region_script: Script,
		enemy_spawn_point_script: Script,
		respawning_enemy_spawn_point_script: Script) -> Array[Node]:
	clear_and_write_tilemap(tml, result.grid)
	_reposition_spawn(level_root, result.spawn_tile)
	return _spawn_entity_hints(
			level_root,
			result,
			destination_scene,
			bug_spawn_region_script,
			enemy_spawn_point_script,
			respawning_enemy_spawn_point_script)


static func clear_and_write_tilemap(
		tml: TileMapLayer, grid: ProcgenGrid) -> void:
	tml.clear()
	for y in range(grid.height):
		for x in range(grid.width):
			var t := grid.get_cell(x, y)
			if t == Frequency.Type.NONE:
				continue
			if not TYPE_TO_ATLAS_COORD.has(t):
				continue
			tml.set_cell(Vector2i(x, y), _TILE_SET_SOURCE_ID,
					TYPE_TO_ATLAS_COORD[t])


static func _reposition_spawn(level_root: Node, spawn_tile: Vector2i) -> void:
	var spawn_node := level_root.get_node_or_null("PlayerSpawnPoint")
	if spawn_node == null:
		return
	# The spawn tile in the grid is the "standing" cell (empty with
	# solid below). Place the spawn point at the tile's center.
	var spawn_node_2d := spawn_node as Node2D
	if spawn_node_2d == null:
		return
	spawn_node_2d.global_position = _tile_center(spawn_tile)


static func _spawn_entity_hints(
		level_root: Node,
		result: ProcgenLevel.Result,
		destination_scene: PackedScene,
		bug_spawn_region_script: Script,
		enemy_spawn_point_script: Script,
		respawning_enemy_spawn_point_script: Script) -> Array[Node]:
	var added: Array[Node] = []
	for raw in result.entity_hints:
		var h: ProcgenSetPieceLibrary.EntityHint = raw
		var node := _spawn_for_hint(
				h,
				destination_scene,
				bug_spawn_region_script,
				enemy_spawn_point_script,
				respawning_enemy_spawn_point_script)
		if node == null:
			continue
		level_root.add_child(node)
		node.owner = level_root
		node.global_position = _tile_center(h.tile)
		added.append(node)
	return added


static func _spawn_for_hint(
		h: ProcgenSetPieceLibrary.EntityHint,
		destination_scene: PackedScene,
		bug_spawn_region_script: Script,
		enemy_spawn_point_script: Script,
		respawning_enemy_spawn_point_script: Script) -> Node:
	if h.kind == "destination":
		if destination_scene == null:
			return null
		var d := destination_scene.instantiate()
		if d is Destination and h.frequency != Frequency.Type.NONE:
			(d as Destination).frequency = h.frequency
		return d
	if h.kind == "bug_region":
		return _make_bug_region(h, bug_spawn_region_script)
	if _HINT_TO_ENEMY_KIND.has(h.kind):
		return _make_enemy_spawn(
				h,
				_HINT_TO_ENEMY_KIND[h.kind],
				enemy_spawn_point_script,
				respawning_enemy_spawn_point_script)
	return null


static func _make_bug_region(
		h: ProcgenSetPieceLibrary.EntityHint,
		bug_spawn_region_script: Script) -> Node:
	if bug_spawn_region_script == null:
		return null
	var region := Node2D.new()
	region.name = "BugSpawnRegion_%s" % [h.tile]
	region.set_script(bug_spawn_region_script)
	region.set("frequency", h.frequency)
	region.set("rate_delta", float(h.params.get("rate_delta", 1.0)))
	var sz: Vector2i = h.params.get("size_tiles", Vector2i(10, 8))
	region.set(
			"size",
			Vector2(sz.x * _TILE_SIZE_PX, sz.y * _TILE_SIZE_PX))
	return region


static func _make_enemy_spawn(
		h: ProcgenSetPieceLibrary.EntityHint,
		kind: Enemy.Kind,
		enemy_spawn_point_script: Script,
		respawning_enemy_spawn_point_script: Script) -> Node:
	var respawn := bool(h.params.get("respawn", false))
	var spawn := Node2D.new()
	spawn.name = "%sSpawn_%s" % [h.kind.capitalize(), h.tile]
	var script: Script = (
			respawning_enemy_spawn_point_script
			if respawn
			else enemy_spawn_point_script)
	if script == null:
		return null
	spawn.set_script(script)
	spawn.set("kind", kind)
	if h.frequency != Frequency.Type.NONE:
		spawn.set("frequency_override", h.frequency)
	if respawn:
		spawn.set("max_active", int(h.params.get("max_active", 2)))
	return spawn


static func _tile_center(tile: Vector2i) -> Vector2:
	# TileMapLayer with a 16 px tile; the standing cell's center is
	# at tile * 16 + 8 in world space.
	return Vector2(
			float(tile.x * _TILE_SIZE_PX + _TILE_SIZE_PX / 2),
			float(tile.y * _TILE_SIZE_PX + _TILE_SIZE_PX / 2))


## Undo every owner=level_root child added by a previous apply().
## Used when re-applying so the saved scene doesn't accumulate stale
## nodes across runs. Children we skip: the base scaffolding
## (TerrainWorld, Tiles, PlayerSpawnPoint, Players, BugSpawner,
## EnemySystem, ParallaxBackground).
static func clear_previous_spawns(level_root: Node) -> int:
	var keep := {
		"ParallaxBackground": true,
		"TerrainWorld": true,
		"Tiles": true,
		"PlayerSpawnPoint": true,
		"Players": true,
		"BugSpawner": true,
		"EnemySystem": true,
	}
	var to_free: Array[Node] = []
	for child in level_root.get_children():
		if keep.has(child.name):
			continue
		to_free.append(child)
	for n in to_free:
		level_root.remove_child(n)
		n.queue_free()
	return to_free.size()
