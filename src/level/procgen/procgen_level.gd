class_name ProcgenLevel
extends RefCounted
## Orchestrator. Runs the generator pipeline and returns a `Result`
## that the runner script can then write into a scene file.
##
## Pipeline:
##   1. LayoutPlanner sketches arena + floor + platforms.
##   2. SetPieceLibrary stamps a budget of pool_sand_trap /
##      web_tunnel / enemy_pocket / bug_region set-pieces.
##   3. Validator runs. If errors, regen with a fresh seed.
##   4. Return the grid + entity hints + spawn/destination coords.
##
## TileMapWriter + EntityPlacer consume the Result separately; this
## orchestrator stays scene-agnostic so it can run in isolation.


class Result:
	var grid: ProcgenGrid
	var spawn_tile: Vector2i
	var destination_tile: Vector2i
	var entity_hints: Array = []
	var config: ProcgenConfig
	var seed_used: int
	var attempt: int
	var validator_report: ProcgenValidator.Report


## Main entry. `config` supplies the tunables. Returns a Result
## whose `validator_report` has no ERRORs, or (if regen budget
## exhausted) the best-effort result with the last report.
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
	var rng_hazard := _named_rng(seed, "hazard")
	var rng_entity := _named_rng(seed, "entity")

	var plan := ProcgenLayoutPlanner.plan(config, rng_layout)
	var grid := plan.grid

	var hints: Array = []

	# Stamp set-pieces from the mix.
	var budget := config.set_piece_budget
	var mix_entries := config.set_piece_weights()
	for i in range(budget):
		var kind: String = _weighted_pick_str(mix_entries, rng_hazard)
		var hint_or_null := _stamp(kind, grid, plan, rng_hazard, config)
		if hint_or_null != null:
			hints.append_array(hint_or_null)

	# Always emit at least one bug region per frequency used by
	# platforms — otherwise the player can get stuck on a frequency
	# with no matching bugs nearby. Cheap coverage pass.
	for freq_entry in config.weighted_frequencies():
		var freq: int = freq_entry[0]
		if int(freq_entry[1]) <= 0:
			continue
		var region_hint := _place_bug_region_anywhere(
				grid, plan, freq, 0.6, rng_entity)
		if region_hint != null:
			hints.append(region_hint)

	# Destination hint (the single win object).
	var dest_hint := ProcgenSetPieceLibrary.EntityHint.new()
	dest_hint.kind = "destination"
	dest_hint.tile = plan.destination_tile
	dest_hint.frequency = Frequency.Type.YELLOW
	hints.append(dest_hint)

	# Smoothing post-pass. Runs on every colored + hazard type so
	# platform ends, pool rims, and pocket edges lose single-cell
	# spikes and 1-wide pits. INDESTRUCTIBLE and the perimeter are
	# skipped inside `smooth_once`, so the anchor border stays
	# intact. Two iterations is the sweet spot — more erodes thin
	# platforms below the BFS jump-height.
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

	# Re-carve spawn and goal stand tiles + the 2 tiles above each
	# in case the smoothing pass filled them. Belt-and-suspenders
	# for the validator's spawn_no_floor / goal_no_floor checks.
	_ensure_standable(grid, plan.spawn_tile)
	_ensure_standable(grid, plan.destination_tile)

	# Validate.
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


static func _stamp(
		kind: String,
		grid: ProcgenGrid,
		plan: ProcgenLayoutPlanner.Plan,
		rng: RandomNumberGenerator,
		config: ProcgenConfig) -> Array:
	match kind:
		"pool_sand_trap":
			var anchor := _pick_surface_anchor(
					grid, plan, rng, 4, 3)
			if anchor.x < 0:
				return []
			var stamp := ProcgenSetPieceLibrary.stamp_pool_sand_trap(
					grid, anchor, 6, 2, rng)
			return stamp.hints
		"web_tunnel":
			var anchor2 := _pick_interior_anchor(
					grid, plan, rng, 10, 3)
			if anchor2.x < 0:
				return []
			var stamp2 := ProcgenSetPieceLibrary.stamp_web_tunnel(
					grid, anchor2, 8, rng)
			return stamp2.hints
		"enemy_pocket":
			var anchor3 := _pick_interior_anchor(
					grid, plan, rng, 4, 3)
			if anchor3.x < 0:
				return []
			var stamp3 := ProcgenSetPieceLibrary.stamp_enemy_pocket(
					grid, anchor3, rng, config)
			return stamp3.hints
		"bug_region":
			var freqs := config.weighted_frequencies()
			var freq: int = _weighted_pick_int(freqs, rng)
			var hint := _place_bug_region_anywhere(
					grid, plan, freq, 1.0, rng)
			if hint != null:
				return [hint]
	return []


static func _pick_surface_anchor(
		grid: ProcgenGrid,
		plan: ProcgenLayoutPlanner.Plan,
		rng: RandomNumberGenerator,
		width: int,
		depth: int) -> Vector2i:
	# Walk random columns, find the top of the main floor, return
	# that position. Used for pool placement.
	for _tries in range(40):
		var x := rng.randi_range(
				grid.width / 4, grid.width * 3 / 4 - width)
		var y := _surface_top_y(grid, x)
		if y < 0:
			continue
		if y - depth < 2:
			continue
		# Ensure a flat span of `width` columns at this height.
		var ok := true
		for dx in range(width):
			var yy := _surface_top_y(grid, x + dx)
			if yy != y:
				ok = false
				break
		if ok:
			# Anchor y is one above the surface so the rim/shell sit
			# inside the ground.
			return Vector2i(x, y - depth)
	return Vector2i(-1, -1)


static func _pick_interior_anchor(
		grid: ProcgenGrid,
		plan: ProcgenLayoutPlanner.Plan,
		rng: RandomNumberGenerator,
		width: int,
		height: int) -> Vector2i:
	if plan.air_pockets.is_empty():
		return Vector2i(-1, -1)
	for _tries in range(30):
		var pocket: Rect2i = plan.air_pockets[
				rng.randi() % plan.air_pockets.size()]
		if pocket.size.x < width + 2 or pocket.size.y < height + 2:
			continue
		var x := rng.randi_range(
				pocket.position.x,
				pocket.position.x + pocket.size.x - width - 1)
		var y := rng.randi_range(
				pocket.position.y,
				pocket.position.y + pocket.size.y - height - 1)
		return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _surface_top_y(grid: ProcgenGrid, x: int) -> int:
	# Downward raycast: first empty → solid transition.
	for y in range(1, grid.height - 1):
		if not grid.is_solid(x, y) and grid.is_solid(x, y + 1):
			return y + 1  # y+1 is the surface tile; pool anchor is above.
	return -1


static func _place_bug_region_anywhere(
		grid: ProcgenGrid,
		plan: ProcgenLayoutPlanner.Plan,
		frequency: int,
		rate_delta: float,
		rng: RandomNumberGenerator) -> ProcgenSetPieceLibrary.EntityHint:
	if plan.air_pockets.is_empty():
		return null
	var pocket: Rect2i = plan.air_pockets[
			rng.randi() % plan.air_pockets.size()]
	var tile := Vector2i(
			rng.randi_range(pocket.position.x,
					pocket.position.x + pocket.size.x - 1),
			rng.randi_range(pocket.position.y,
					pocket.position.y + pocket.size.y - 1))
	return ProcgenSetPieceLibrary.stamp_bug_region(
			tile, frequency, rate_delta).hints[0]


static func _ensure_standable(grid: ProcgenGrid, tile: Vector2i) -> void:
	# Guarantee the stand-cell is empty, that the cell above it is
	# empty (headroom), and that the cell below it is solid.
	grid.set_cell(tile.x, tile.y, Frequency.Type.NONE)
	grid.set_cell(tile.x, tile.y - 1, Frequency.Type.NONE)
	if not grid.is_solid(tile.x, tile.y + 1):
		grid.set_cell(tile.x, tile.y + 1, Frequency.Type.GREEN)


static func _named_rng(master_seed: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Seed per stream so changing one subsystem doesn't shift the
	# output of another.
	rng.seed = master_seed ^ hash(name)
	return rng


static func _weighted_pick_str(
		entries: Array,
		rng: RandomNumberGenerator) -> String:
	var total := 0
	for e in entries:
		total += int(e[1])
	if total <= 0:
		return String(entries[0][0])
	var r := rng.randi_range(0, total - 1)
	var acc := 0
	for e in entries:
		acc += int(e[1])
		if r < acc:
			return String(e[0])
	return String(entries[-1][0])


static func _weighted_pick_int(
		entries: Array,
		rng: RandomNumberGenerator) -> int:
	var total := 0
	for e in entries:
		total += int(e[1])
	if total <= 0:
		return int(entries[0][0])
	var r := rng.randi_range(0, total - 1)
	var acc := 0
	for e in entries:
		acc += int(e[1])
		if r < acc:
			return int(e[0])
	return int(entries[-1][0])
