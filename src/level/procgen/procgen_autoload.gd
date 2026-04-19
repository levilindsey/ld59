extends Node
## Autoload entry for the procedural level generator. Inspects
## `OS.get_cmdline_user_args()` on `_ready`. If `--procgen-seed <n>`
## is present, runs the generator and quits the engine. Otherwise
## does nothing — the game boots normally.
##
## Lives under its own autoload so it runs after `G` but before the
## main scene instantiates, giving `G` et al. full visibility while
## also letting us short-circuit main-scene loading on gen runs.


func _ready() -> void:
	# Prefer `get_cmdline_user_args()` (everything after `--`). Falls
	# back to full cmdline if the separator wasn't used.
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var parsed := _parse_args(args)

	if parsed.has("procgen-adjust"):
		_run_adjust(parsed)
		return
	if not parsed.has("procgen-seed"):
		return
	_run_generate(parsed)


func _run_generate(parsed: Dictionary) -> void:
	var cfg := ProcgenConfig.new()
	cfg.seed = int(parsed.get("procgen-seed", 0))
	cfg.width_tiles = int(parsed.get("width", 72))
	cfg.height_tiles = int(parsed.get("height", 40))
	cfg.chamber_count = int(parsed.get("chambers", 5))
	cfg.platforms_per_chamber = int(parsed.get("platforms-per", 2))

	var template_path: String = parsed.get(
			"template", "res://src/level/terrain_level.tscn")
	var output_path: String = parsed.get(
			"output", "res://src/level/generated_level.tscn")

	print("=== procgen ===")
	print("seed=%d template=%s output=%s size=%dx%d"
			% [cfg.seed, template_path, output_path,
					cfg.width_tiles, cfg.height_tiles])

	var result := ProcgenLevel.generate(cfg)
	print("attempts=%d seed_used=%d spawn=%s goal=%s"
			% [result.attempt + 1, result.seed_used,
					result.spawn_tile, result.destination_tile])
	for line in result.validator_report.summary_lines():
		print(line)
	if result.validator_report.has_errors():
		printerr("ERROR: validator failed after %d attempts; aborting save"
				% cfg.max_regen_attempts)
		get_tree().quit(1)
		return

	var ok := _apply_and_save(result, template_path, output_path)
	if not ok:
		get_tree().quit(1)
		return
	print("Saved: %s" % output_path)
	get_tree().quit(0)


func _apply_and_save(
		result: ProcgenLevel.Result,
		template_path: String,
		output_path: String) -> bool:
	var packed: PackedScene = load(template_path)
	if packed == null:
		printerr("Could not load template: %s" % template_path)
		return false
	var root: Node = packed.instantiate(
			PackedScene.GEN_EDIT_STATE_DISABLED)
	if root == null:
		printerr("Could not instantiate template")
		return false
	var tml_candidate := root.get_node_or_null("Tiles")
	if not (tml_candidate is TileMapLayer):
		printerr("Template has no child named 'Tiles' of TileMapLayer")
		root.queue_free()
		return false
	var tml: TileMapLayer = tml_candidate

	ProcgenTileMapWriter.clear_previous_spawns(root)

	var destination_scene := load("res://src/level/destination.tscn")
	var bug_spawn_region_script := load(
			"res://src/bugs/bug_spawn_region.gd")
	var enemy_spawn_point_script := load(
			"res://src/enemies/enemy_spawn_point.gd")
	var respawning_enemy_spawn_point_script := load(
			"res://src/enemies/respawning_enemy_spawn_point.gd")

	var added := ProcgenTileMapWriter.apply(
			root,
			tml,
			result,
			destination_scene,
			bug_spawn_region_script,
			enemy_spawn_point_script,
			respawning_enemy_spawn_point_script)
	print("Added %d entity children" % added.size())

	var packed_out := PackedScene.new()
	var pack_err := packed_out.pack(root)
	if pack_err != OK:
		printerr("PackedScene.pack failed: %s" % pack_err)
		return false
	var save_err := ResourceSaver.save(packed_out, output_path)
	if save_err != OK:
		printerr("ResourceSaver.save failed: %s" % save_err)
		return false
	return true


func _run_adjust(parsed: Dictionary) -> void:
	var op: String = parsed.get("procgen-adjust", "")
	var input_path: String = parsed.get(
			"input", "res://src/level/generated_level.tscn")
	var output_path: String = parsed.get("output", input_path)

	print("=== procgen adjust ===")
	print("op=%s input=%s output=%s" % [op, input_path, output_path])

	var packed: PackedScene = load(input_path)
	if packed == null:
		printerr("Could not load input: %s" % input_path)
		get_tree().quit(1)
		return
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	var tml_candidate := root.get_node_or_null("Tiles")
	if not (tml_candidate is TileMapLayer):
		printerr("Input has no Tiles TileMapLayer child")
		get_tree().quit(1)
		return
	var tml: TileMapLayer = tml_candidate
	var grid := _grid_from_tilemap(tml)
	var spawn_tile := _spawn_tile_from_root(root)
	var dest_tile := _destination_tile_from_root(root)

	var applied := true
	match op:
		"validate":
			pass # Just runs the validator below; no mutation.
		"carve_rect":
			applied = _apply_carve_rect(grid, parsed)
		"paint_rect":
			applied = _apply_paint_rect(grid, parsed)
		"remove_entity":
			applied = _apply_remove_entity(root, parsed)
		_:
			printerr("Unknown op: '%s' (expected: validate, carve_rect, paint_rect, remove_entity)" % op)
			get_tree().quit(1)
			return
	if not applied:
		printerr("Op failed to apply; see preceding errors")
		get_tree().quit(1)
		return

	# Rebuild the tilemap from the (possibly modified) grid. Grid-
	# based ops work on the grid then flush back to tiles.
	if op != "remove_entity":
		ProcgenTileMapWriter.clear_and_write_tilemap(tml, grid)

	# Re-run the validator. Derive synthetic hints from the scene's
	# actual child nodes so validator checks (web-near-spider, bug-
	# region coverage) can still fire correctly after a save/load.
	var scene_hints := _scan_scene_for_hints(root)
	var report := ProcgenValidator.validate(
			grid, spawn_tile, dest_tile, scene_hints)
	for line in report.summary_lines():
		print(line)
	if report.has_errors() and op != "validate":
		printerr("Adjust produced a broken level; refusing to save")
		get_tree().quit(1)
		return

	if op == "validate":
		get_tree().quit(0)
		return

	var packed_out := PackedScene.new()
	var pack_err := packed_out.pack(root)
	if pack_err != OK:
		printerr("pack failed: %s" % pack_err)
		get_tree().quit(1)
		return
	var save_err := ResourceSaver.save(packed_out, output_path)
	if save_err != OK:
		printerr("save failed: %s" % save_err)
		get_tree().quit(1)
		return
	print("Saved: %s" % output_path)
	get_tree().quit(0)


## Extract a `ProcgenGrid` from an existing TileMapLayer by reading
## every used cell and inverting the atlas_coord -> Frequency.Type
## map from `ProcgenTileMapWriter`.
func _grid_from_tilemap(tml: TileMapLayer) -> ProcgenGrid:
	var used_rect := tml.get_used_rect()
	var width := maxi(1, used_rect.end.x)
	var height := maxi(1, used_rect.end.y)
	var grid := ProcgenGrid.new(width, height)
	var invert := {}
	for k in ProcgenTileMapWriter.TYPE_TO_ATLAS_COORD.keys():
		invert[ProcgenTileMapWriter.TYPE_TO_ATLAS_COORD[k]] = k
	for cell in tml.get_used_cells():
		var atlas := tml.get_cell_atlas_coords(cell)
		var t: int = invert.get(atlas, Frequency.Type.NONE)
		if t != Frequency.Type.NONE:
			grid.set_cell(cell.x, cell.y, t)
	return grid


func _spawn_tile_from_root(root: Node) -> Vector2i:
	var n := root.get_node_or_null("PlayerSpawnPoint")
	if not (n is Node2D):
		return Vector2i(0, 0)
	var pos := (n as Node2D).position
	return Vector2i(int(pos.x / 16.0), int(pos.y / 16.0))


func _destination_tile_from_root(root: Node) -> Vector2i:
	var n := root.get_node_or_null("Destination")
	if not (n is Node2D):
		return Vector2i(0, 0)
	var pos := (n as Node2D).position
	return Vector2i(int(pos.x / 16.0), int(pos.y / 16.0))


func _apply_carve_rect(grid: ProcgenGrid, parsed: Dictionary) -> bool:
	var rect := _parse_rect(parsed.get("rect", ""))
	if rect == Rect2i():
		printerr("carve_rect needs --rect x,y,w,h")
		return false
	grid.fill_rect(rect, Frequency.Type.NONE)
	return true


func _apply_paint_rect(grid: ProcgenGrid, parsed: Dictionary) -> bool:
	var rect := _parse_rect(parsed.get("rect", ""))
	if rect == Rect2i():
		printerr("paint_rect needs --rect x,y,w,h")
		return false
	var type_str: String = parsed.get("type", "")
	var type := _parse_freq_type(type_str)
	if type < 0:
		printerr("paint_rect needs --type <Frequency name>")
		return false
	grid.fill_rect(rect, type)
	return true


func _apply_remove_entity(root: Node, parsed: Dictionary) -> bool:
	var name: String = parsed.get("name", "")
	if name.is_empty():
		printerr("remove_entity needs --name <node_name>")
		return false
	var n := root.get_node_or_null(name)
	if n == null:
		printerr("no child named '%s'" % name)
		return false
	root.remove_child(n)
	n.queue_free()
	return true


func _parse_rect(s: String) -> Rect2i:
	if s.is_empty():
		return Rect2i()
	var parts := s.split(",")
	if parts.size() != 4:
		return Rect2i()
	return Rect2i(
			int(parts[0]), int(parts[1]),
			int(parts[2]), int(parts[3]))


## Walk the scene tree and synthesize EntityHint objects for every
## enemy spawn point and bug spawn region we find. Lets the
## validator's hint-dependent checks (web-near-spider, bug-coverage)
## work on a saved scene without the original generator in memory.
func _scan_scene_for_hints(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		var h: Variant = _hint_for_node(child)
		if h != null:
			out.append(h)
	return out


func _hint_for_node(node: Node) -> Variant:
	# Bug region: Node2D carrying the BugSpawnRegion script.
	if node is BugSpawnRegion:
		var region := node as BugSpawnRegion
		var region_hint := ProcgenSetPieceLibrary.EntityHint.new()
		region_hint.kind = "bug_region"
		region_hint.tile = _world_pos_to_tile(region.global_position)
		region_hint.frequency = region.frequency
		return region_hint
	# Enemy spawn point: Node2D carrying the EnemySpawnPoint script.
	if node is EnemySpawnPoint:
		var spawn := node as EnemySpawnPoint
		var kind_string := _hint_string_from_enemy_kind(spawn.kind)
		if kind_string != "":
			var spawn_hint := ProcgenSetPieceLibrary.EntityHint.new()
			spawn_hint.kind = kind_string
			spawn_hint.tile = _world_pos_to_tile(spawn.global_position)
			return spawn_hint
	return null


func _hint_string_from_enemy_kind(kind: Enemy.Kind) -> String:
	match kind:
		Enemy.Kind.SPIDER:
			return "enemy_spider"
		Enemy.Kind.COYOTE:
			return "enemy_coyote"
		Enemy.Kind.MONSTER_BIRD:
			return "enemy_bird"
		Enemy.Kind.FLYING_CRITTER:
			return "enemy_critter"
	return ""


func _world_pos_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / 16.0), int(pos.y / 16.0))


func _parse_freq_type(s: String) -> int:
	if s.is_empty():
		return -1
	const BY_NAME := {
		"NONE": Frequency.Type.NONE,
		"INDESTRUCTIBLE": Frequency.Type.INDESTRUCTIBLE,
		"RED": Frequency.Type.RED,
		"GREEN": Frequency.Type.GREEN,
		"BLUE": Frequency.Type.BLUE,
		"LIQUID": Frequency.Type.LIQUID,
		"SAND": Frequency.Type.SAND,
		"YELLOW": Frequency.Type.YELLOW,
		"WEB_RED": Frequency.Type.WEB_RED,
		"WEB_GREEN": Frequency.Type.WEB_GREEN,
		"WEB_BLUE": Frequency.Type.WEB_BLUE,
		"WEB_YELLOW": Frequency.Type.WEB_YELLOW,
	}
	var upper := s.to_upper()
	if BY_NAME.has(upper):
		return BY_NAME[upper]
	return -1


func _parse_args(all: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < all.size():
		var arg: String = all[i]
		if arg == "--":
			i += 1
			continue
		if arg.begins_with("--"):
			var body := arg.substr(2)
			if "=" in body:
				var parts := body.split("=", false, 1)
				out[parts[0]] = parts[1]
				i += 1
			else:
				if i + 1 < all.size() and not all[i + 1].begins_with("--"):
					out[body] = all[i + 1]
					i += 2
				else:
					out[body] = "true"
					i += 1
		else:
			i += 1
	return out
