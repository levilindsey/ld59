class_name ProcgenLayoutPlanner
extends RefCounted
## First-stage planner. Writes the arena shell + internal platforms
## into the grid, picks the player spawn + destination tile coords,
## and returns the spawn/goal positions so later stages know where
## the golden path endpoints are.
##
## v1 strategy: one rectangular arena with an INDESTRUCTIBLE border,
## a thick floor layer, and a handful of floating platforms at
## varying heights. Enough structure to demonstrate the pipeline
## end-to-end; room-graph macro comes in v2.


## Output of `plan`. Consumed by later stages.
class Plan:
	var grid: ProcgenGrid
	var spawn_tile: Vector2i
	var destination_tile: Vector2i
	## Tile rects where set-pieces are allowed to stamp. Each rect is
	## in tile coords; set-pieces clamp themselves inside their rect.
	var floor_platforms: Array[Rect2i] = []
	## Tile rects that represent open air (empty) where flying enemy
	## spawners can be placed without clipping terrain.
	var air_pockets: Array[Rect2i] = []


static func plan(
		config: ProcgenConfig,
		rng: RandomNumberGenerator) -> Plan:
	var plan := Plan.new()
	plan.grid = ProcgenGrid.new(config.width_tiles, config.height_tiles)

	_carve_border(plan.grid, config.border_tiles)
	_carve_floor(plan.grid, config.border_tiles, config.height_tiles, rng, config)
	var platforms := _carve_platforms(plan.grid, config, rng)
	plan.floor_platforms = platforms

	var spawn := _pick_spawn(plan.grid, config.border_tiles)
	var goal := _pick_destination(plan.grid, config.border_tiles)
	plan.spawn_tile = spawn
	plan.destination_tile = goal

	# Mark a 3-wide golden corridor at standing-height from spawn to
	# goal. Nothing in that corridor can later be overwritten by a
	# set-piece that doesn't know about the corridor — validators
	# confirm the spawn and goal are standable post-gen.
	plan.grid.mark_golden(spawn.x, spawn.y, true)
	plan.grid.mark_golden(goal.x, goal.y, true)

	_register_air_pockets(plan, config)

	return plan


static func _carve_border(grid: ProcgenGrid, thickness: int) -> void:
	var t := maxi(1, thickness)
	# Top band.
	grid.fill_rect(Rect2i(0, 0, grid.width, t),
			Frequency.Type.INDESTRUCTIBLE)
	# Bottom band.
	grid.fill_rect(Rect2i(0, grid.height - t, grid.width, t),
			Frequency.Type.INDESTRUCTIBLE)
	# Left column.
	grid.fill_rect(Rect2i(0, 0, t, grid.height),
			Frequency.Type.INDESTRUCTIBLE)
	# Right column.
	grid.fill_rect(Rect2i(grid.width - t, 0, t, grid.height),
			Frequency.Type.INDESTRUCTIBLE)


static func _carve_floor(
		grid: ProcgenGrid,
		border: int,
		height: int,
		rng: RandomNumberGenerator,
		config: ProcgenConfig) -> void:
	# Thick floor: fill from 2 tiles above the bottom border upward
	# by 4 tiles. Mostly one "frequency-of-the-level" tile type with
	# an occasional variation.
	var floor_top := height - border - 5
	var floor_bottom := height - border - 1
	var primary := _weighted_pick(config.weighted_frequencies(), rng)
	for y in range(floor_top, floor_bottom + 1):
		for x in range(border, grid.width - border):
			var t := primary
			# 1-in-8 cells upstairs get a different color for variety.
			if y == floor_top and rng.randi() % 8 == 0:
				t = _weighted_pick(config.weighted_frequencies(), rng)
			grid.set_cell(x, y, t)


static func _carve_platforms(
		grid: ProcgenGrid,
		config: ProcgenConfig,
		rng: RandomNumberGenerator) -> Array[Rect2i]:
	var platforms: Array[Rect2i] = []
	var tries := 0
	var max_tries := config.platform_count * 4
	while platforms.size() < config.platform_count and tries < max_tries:
		tries += 1
		var width := 6 + rng.randi_range(0, 6)
		var height := 1 + rng.randi_range(0, 2)
		var min_y := config.border_tiles + 3
		var max_y := grid.height - config.border_tiles - 8
		if max_y <= min_y:
			break
		var x := rng.randi_range(
				config.border_tiles + 2,
				grid.width - config.border_tiles - 2 - width)
		var y := rng.randi_range(min_y, max_y)
		var rect := Rect2i(x, y, width, height)
		if _overlaps_any(platforms, rect.grow(2)):
			continue
		var freq := _weighted_pick(config.weighted_frequencies(), rng)
		grid.fill_rect(rect, freq)
		platforms.append(rect)
	return platforms


static func _pick_spawn(grid: ProcgenGrid, border: int) -> Vector2i:
	# Stand the player on the main floor on the left side.
	var x := border + 3
	var y := _find_standable_column(grid, x, border)
	return Vector2i(x, y)


static func _pick_destination(grid: ProcgenGrid, border: int) -> Vector2i:
	var x := grid.width - border - 4
	var y := _find_standable_column(grid, x, border)
	return Vector2i(x, y)


static func _find_standable_column(
		grid: ProcgenGrid, x: int, border: int) -> int:
	# Walk up from one tile above the bottom border; the first empty
	# cell whose below-neighbor is solid is standable.
	for y in range(grid.height - border - 1, border, -1):
		if grid.is_solid(x, y):
			continue
		if grid.is_solid(x, y + 1):
			return y
	return grid.height - border - 2


static func _overlaps_any(rects: Array[Rect2i], rect: Rect2i) -> bool:
	for r in rects:
		if r.intersects(rect):
			return true
	return false


static func _register_air_pockets(
		plan: Plan, config: ProcgenConfig) -> void:
	# Register one big air pocket (everything above the floor inside
	# the border). Finer pockets per room are a v2 concern.
	var inner := Rect2i(
			config.border_tiles + 1,
			config.border_tiles + 1,
			plan.grid.width - 2 * (config.border_tiles + 1),
			plan.grid.height - 2 * (config.border_tiles + 1) - 6)
	if inner.size.x > 0 and inner.size.y > 0:
		plan.air_pockets.append(inner)


static func _weighted_pick(
		entries: Array,
		rng: RandomNumberGenerator) -> int:
	var total := 0
	for e in entries:
		total += int(e[1])
	if total <= 0:
		return Frequency.Type.GREEN
	var r := rng.randi_range(0, total - 1)
	var acc := 0
	for e in entries:
		acc += int(e[1])
		if r < acc:
			return int(e[0])
	return int(entries[-1][0])
