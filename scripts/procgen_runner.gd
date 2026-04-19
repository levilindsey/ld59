extends SceneTree
## Headless entry for the procedural level generator. Loads a
## template scene, runs the generator, writes the result into the
## scene, packs + saves as a new .tscn.
##
## Invoke from PowerShell:
##   godot --headless -s scripts/procgen_runner.gd -- --seed 7 \
##         --template res://src/level/terrain_level.tscn \
##         --output res://src/level/generated_level.tscn
##
## Or use the wrapper: scripts/generate_level.ps1


func _init() -> void:
	var args := _parse_args()
	var seed_val: int = int(args.get("seed", randi()))
	var template_path: String = args.get(
			"template", "res://src/level/terrain_level.tscn")
	var output_path: String = args.get(
			"output", "res://src/level/generated_level.tscn")
	var width: int = int(args.get("width", 72))
	var height: int = int(args.get("height", 40))
	var budget: int = int(args.get("budget", 6))
	var platforms: int = int(args.get("platforms", 8))

	print("=== procgen_runner ===")
	print("seed=%d template=%s output=%s size=%dx%d"
			% [seed_val, template_path, output_path, width, height])

	var cfg := ProcgenConfig.new()
	cfg.seed = seed_val
	cfg.width_tiles = width
	cfg.height_tiles = height
	cfg.set_piece_budget = budget
	cfg.platform_count = platforms

	var result := ProcgenLevel.generate(cfg)
	print("attempts=%d seed_used=%d spawn=%s goal=%s"
			% [result.attempt + 1, result.seed_used,
					result.spawn_tile, result.destination_tile])
	for line in result.validator_report.summary_lines():
		print(line)
	if result.validator_report.has_errors():
		printerr("ERROR: validator failed after %d attempts; aborting save"
				% cfg.max_regen_attempts)
		quit(1)
		return

	var ok := _apply_and_save(result, template_path, output_path)
	if not ok:
		quit(1)
		return
	print("Saved: %s" % output_path)
	quit(0)


func _apply_and_save(
		result: ProcgenLevel.Result,
		template_path: String,
		output_path: String) -> bool:
	var packed: PackedScene = load(template_path)
	if packed == null:
		printerr("Could not load template: %s" % template_path)
		return false
	var root: Node = packed.instantiate()
	if root == null:
		printerr("Could not instantiate template")
		return false

	# Locate TileMapLayer.
	var tml_candidate := root.get_node_or_null("Tiles")
	if not (tml_candidate is TileMapLayer):
		printerr("Template has no child named 'Tiles' of TileMapLayer")
		return false
	var tml: TileMapLayer = tml_candidate

	# Clear any previous spawned children from a prior generator run.
	ProcgenTileMapWriter.clear_previous_spawns(root)

	# Load the entity scripts / scenes the writer needs.
	var destination_scene := load("res://src/level/destination.tscn")
	var bug_spawn_region_script := load("res://src/bugs/bug_spawn_region.gd")
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

	# Pack and save.
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


## Parse `--key value` or `--key=value` pairs from the portion of
## OS.get_cmdline_args() after `--`.
func _parse_args() -> Dictionary:
	var result: Dictionary = {}
	var all := OS.get_cmdline_args()
	var after_sep := false
	var i := 0
	while i < all.size():
		var arg: String = all[i]
		if arg == "--":
			after_sep = true
			i += 1
			continue
		if not after_sep:
			i += 1
			continue
		if arg.begins_with("--"):
			var body := arg.substr(2)
			if "=" in body:
				var parts := body.split("=", false, 1)
				result[parts[0]] = parts[1]
				i += 1
			else:
				# Next arg is value, unless it starts with `--`.
				if i + 1 < all.size() and not all[i + 1].begins_with("--"):
					result[body] = all[i + 1]
					i += 2
				else:
					result[body] = "true"
					i += 1
		else:
			i += 1
	return result
