class_name ProcgenLevel
extends RefCounted
## Orchestrator. Delegates layout + theme stamping to
## `ProcgenLayoutPlanner`, runs the global "coverage" pass (one bug
## region per gameplay frequency so the player can't get stuck on a
## frequency with no matching bugs), applies the organic-smoothing
## post-pass, then runs the validator. On validator failure, bumps
## the seed and retries.


class Result:
	var grid: ProcgenGrid
	var spawn_tile: Vector2i
	var destination_tile: Vector2i
	var entity_hints: Array = []
	var config: ProcgenConfig
	var seed_used: int
	var attempt: int
	var validator_report: ProcgenValidator.Report


static func generate(config: ProcgenConfig) -> Result:
	var last_result: Result = null
	for attempt in range(config.max_regen_attempts):
		var derived_seed := config.seed + attempt * 0x9E3779B1
		var result := _generate_one(config, derived_seed, attempt)
		last_result = result
		if not result.validator_report.has_errors():
			return result
	return last_result


static func _generate_one(
		config: ProcgenConfig, seed: int, attempt: int) -> Result:
	var rng_layout := _named_rng(seed, "layout")
	var rng_entity := _named_rng(seed, "entity")

	var plan := ProcgenLayoutPlanner.plan(config, rng_layout)
	var grid := plan.grid
	var hints: Array = plan.entity_hints.duplicate()

	# Coverage pass: ensure every configured gameplay frequency has
	# AT LEAST one bug region placed somewhere, so the player isn't
	# locked on a frequency with nothing to eat nearby.
	_ensure_bug_coverage(grid, plan, config, rng_entity, hints)

	# Organic-smoothing pass (rounds spike corners, closes hairline
	# pits). Skip-border + skip-INDESTRUCTIBLE guarantees anchor
	# integrity.
	var smoothable: Array[int] = [
		Frequency.Type.RED,
		Frequency.Type.GREEN,
		Frequency.Type.BLUE,
		Frequency.Type.YELLOW,
		Frequency.Type.LIQUID,
		Frequency.Type.SAND,
	]
	for _i in range(2):
		var changed := ProcgenShapes.smooth_once(grid, smoothable)
		if changed == 0:
			break

	_ensure_standable(grid, plan.spawn_tile)
	_ensure_standable(grid, plan.destination_tile)

	var report := ProcgenValidator.validate(
			grid, plan.spawn_tile, plan.destination_tile, hints)

	var result := Result.new()
	result.grid = grid
	result.spawn_tile = plan.spawn_tile
	result.destination_tile = plan.destination_tile
	result.entity_hints = hints
	result.config = config
	result.seed_used = seed
	result.attempt = attempt
	result.validator_report = report
	return result


static func _ensure_bug_coverage(
		grid: ProcgenGrid,
		plan: ProcgenLayoutPlanner.Plan,
		config: ProcgenConfig,
		rng: RandomNumberGenerator,
		hints: Array) -> void:
	# Tally which frequencies already have a bug region in the
	# hints list.
	var covered: Dictionary = {}
	for raw in hints:
		var h: ProcgenSetPieceLibrary.EntityHint = raw
		if h.kind == "bug_region":
			covered[h.frequency] = true
	# Add one region per missing frequency in any open-air chamber.
	for entry in config.weighted_frequencies():
		var freq: int = entry[0]
		if int(entry[1]) <= 0:
			continue
		if covered.has(freq):
			continue
		if plan.air_pockets.is_empty():
			continue
		var pocket: Rect2i = plan.air_pockets[
				rng.randi() % plan.air_pockets.size()]
		var tile := Vector2i(
				rng.randi_range(
						pocket.position.x,
						pocket.position.x + pocket.size.x - 1),
				rng.randi_range(
						pocket.position.y,
						pocket.position.y + pocket.size.y - 1))
		var stamp := ProcgenSetPieceLibrary.stamp_bug_region(
				tile, freq, 0.6)
		for h in stamp.hints:
			hints.append(h)


static func _ensure_standable(grid: ProcgenGrid, tile: Vector2i) -> void:
	grid.set_cell(tile.x, tile.y, Frequency.Type.NONE)
	grid.set_cell(tile.x, tile.y - 1, Frequency.Type.NONE)
	if not grid.is_solid(tile.x, tile.y + 1):
		grid.set_cell(tile.x, tile.y + 1, Frequency.Type.GREEN)


static func _named_rng(
		master_seed: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = master_seed ^ hash(name)
	return rng
