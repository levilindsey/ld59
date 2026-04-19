class_name ProcgenLayoutPlanner
extends RefCounted
## Chamber-sequence layout planner. Carves an N-chamber horizontal
## sequence (spawn on the left, destination on the right), applies a
## themed beat per interior chamber, and emits entity hints as it
## goes. The old single-arena mode is retired — equivalent effect at
## `chamber_count = 2`.
##
## Themes (per-chamber):
##   entry    — spawn point; bare floor + optional deco platform.
##   transit  — gentle platforming + one bug region.
##   combat   — one enemy pocket (Spider / Coyote / Bird / Critter).
##   hazard   — one set-piece (pool_sand_trap or web_tunnel).
##   exit     — destination; bare floor.
##
## Golden path: base floor spans every chamber at a shared Y, with
## doorways carved through each inter-chamber wall two tiles tall
## at standing height. Within a chamber, the floor top is noise-
## jittered and platforms are organic, per ProcgenShapes.


const _FLOOR_DEPTH := 5
const _MIN_CHAMBER_WIDTH := 10


class Plan:
	var grid: ProcgenGrid
	var spawn_tile: Vector2i
	var destination_tile: Vector2i
	## Entity hints emitted by themed chambers. Consumed by
	## `ProcgenLevel` → `TileMapWriter.apply`.
	var entity_hints: Array = []
	## Every tile rect in the grid where flying enemies / bug
	## regions can be placed without clipping terrain. Populated one-
	## per-chamber for the post-pass bug-coverage placement in
	## `ProcgenLevel`.
	var air_pockets: Array[Rect2i] = []


class Chamber:
	var bounds: Rect2i
	var theme: String
	var floor_base_y: int


static func plan(
		config: ProcgenConfig,
		rng: RandomNumberGenerator) -> Plan:
	var result := Plan.new()
	result.grid = ProcgenGrid.new(
			config.width_tiles, config.height_tiles)
	_carve_border(result.grid, config.border_tiles)

	var chambers := _plan_chambers(result.grid, config, rng)
	var shared_floor_base := _compute_shared_floor_base(
			result.grid, config)
	for c in chambers:
		c.floor_base_y = shared_floor_base

	_carve_inter_chamber_walls_and_doors(
			result.grid, chambers, shared_floor_base)

	for c in chambers:
		_carve_chamber_floor(result.grid, c, config, rng)

	for c in chambers:
		_apply_theme(
				result.grid, c, config, rng, result, chambers, shared_floor_base)

	result.spawn_tile = _pick_chamber_stand_tile(
			result.grid, chambers[0], shared_floor_base)
	result.destination_tile = _pick_chamber_stand_tile(
			result.grid, chambers[chambers.size() - 1],
			shared_floor_base, true)

	# Mark golden cells so set-pieces that run in later iterations
	# know not to overwrite them.
	result.grid.mark_golden(
			result.spawn_tile.x, result.spawn_tile.y, true)
	result.grid.mark_golden(
			result.destination_tile.x,
			result.destination_tile.y, true)

	return result


# ---- Chamber layout ---------------------------------------------------------

static func _plan_chambers(
		grid: ProcgenGrid,
		config: ProcgenConfig,
		rng: RandomNumberGenerator) -> Array[Chamber]:
	var n := maxi(2, config.chamber_count)
	var border := config.border_tiles
	var span := grid.width - 2 * border
	var per := maxi(_MIN_CHAMBER_WIDTH, span / n)
	# Recompute n so chambers fit within the span.
	var real_n := maxi(2, span / per)
	per = span / real_n
	var chambers: Array[Chamber] = []
	for i in range(real_n):
		var left := border + i * per
		var right_excl: int
		if i == real_n - 1:
			right_excl = grid.width - border
		else:
			right_excl = border + (i + 1) * per
		var c := Chamber.new()
		c.bounds = Rect2i(
				left, border,
				right_excl - left, grid.height - 2 * border)
		c.theme = _theme_for(i, real_n, config)
		chambers.append(c)
	return chambers


static func _theme_for(i: int, n: int, config: ProcgenConfig) -> String:
	if i == 0:
		return "entry"
	if i == n - 1:
		return "exit"
	var interior := config.interior_themes
	if interior.is_empty():
		return "transit"
	return interior[(i - 1) % interior.size()]


static func _compute_shared_floor_base(
		grid: ProcgenGrid, config: ProcgenConfig) -> int:
	# All chambers share one base floor_top_y so inter-chamber
	# doorways line up with floor height; per-column noise jitter
	# happens within each chamber's carve.
	return grid.height - config.border_tiles - _FLOOR_DEPTH


static func _carve_border(grid: ProcgenGrid, thickness: int) -> void:
	var t := maxi(1, thickness)
	grid.fill_rect(Rect2i(0, 0, grid.width, t),
			Frequency.Type.INDESTRUCTIBLE)
	grid.fill_rect(Rect2i(0, grid.height - t, grid.width, t),
			Frequency.Type.INDESTRUCTIBLE)
	grid.fill_rect(Rect2i(0, 0, t, grid.height),
			Frequency.Type.INDESTRUCTIBLE)
	grid.fill_rect(Rect2i(grid.width - t, 0, t, grid.height),
			Frequency.Type.INDESTRUCTIBLE)


static func _carve_inter_chamber_walls_and_doors(
		grid: ProcgenGrid,
		chambers: Array[Chamber],
		floor_base_y: int) -> void:
	# Walls: run a single-tile-thick INDESTRUCTIBLE column down the
	# shared boundary between adjacent chambers, from the top
	# border to the floor top, then carve a 2-tile-tall doorway at
	# standing height. The main floor below doorway stays solid.
	for i in range(1, chambers.size()):
		var wall_x: int = chambers[i].bounds.position.x
		var top: int = chambers[i].bounds.position.y
		var bot: int = chambers[i].bounds.position.y \
				+ chambers[i].bounds.size.y
		for y in range(top, bot):
			grid.set_cell(wall_x, y, Frequency.Type.INDESTRUCTIBLE)
		# Doorway. Standing tiles are floor_base_y - 1 and -2.
		grid.set_cell(
				wall_x, floor_base_y - 1, Frequency.Type.NONE)
		grid.set_cell(
				wall_x, floor_base_y - 2, Frequency.Type.NONE)


static func _carve_chamber_floor(
		grid: ProcgenGrid,
		c: Chamber,
		config: ProcgenConfig,
		rng: RandomNumberGenerator) -> void:
	# Shared base + per-column noise. Amplitude small so the top
	# never rises into the doorway region.
	var x0 := c.bounds.position.x
	var w := c.bounds.size.x
	var bottom := grid.height - config.border_tiles - 1
	var heights := ProcgenShapes.noise_heights_1d(
			w, c.floor_base_y, 2, 10.0, rng)
	# Make sure the columns adjacent to each wall match floor_base_y
	# exactly (so doorways stand on solid ground on BOTH sides).
	if w > 0:
		heights[0] = c.floor_base_y
	if w > 1:
		heights[w - 1] = c.floor_base_y
	var primary := _weighted_pick(config.weighted_frequencies(), rng)
	for x_idx in range(w):
		var x := x0 + x_idx
		# Don't overwrite inter-chamber walls.
		if grid.get_cell(x, c.floor_base_y) == Frequency.Type.INDESTRUCTIBLE:
			continue
		var top_y: int = clampi(
				heights[x_idx], c.floor_base_y - 1, bottom - 1)
		for y in range(top_y, bottom + 1):
			var t := primary
			if y == top_y and rng.randi() % 9 == 0:
				t = _weighted_pick(config.weighted_frequencies(), rng)
			grid.set_cell(x, y, t)


# ---- Themes -----------------------------------------------------------------

static func _apply_theme(
		grid: ProcgenGrid,
		c: Chamber,
		config: ProcgenConfig,
		rng: RandomNumberGenerator,
		plan: Plan,
		all_chambers: Array[Chamber],
		floor_base_y: int) -> void:
	# Every themed chamber contributes exactly one "air pocket" rect
	# covering its breathable interior, used by post-gen bug-region
	# placement.
	var air := Rect2i(
			c.bounds.position.x + 1,
			c.bounds.position.y + 1,
			c.bounds.size.x - 2,
			floor_base_y - c.bounds.position.y - 2)
	if air.size.x > 0 and air.size.y > 0:
		plan.air_pockets.append(air)

	match c.theme:
		"entry":
			_theme_entry(grid, c, config, rng, plan)
		"transit":
			_theme_transit(grid, c, config, rng, plan, floor_base_y)
		"combat":
			_theme_combat(grid, c, config, rng, plan, floor_base_y)
		"hazard":
			_theme_hazard(grid, c, config, rng, plan, floor_base_y)
		"exit":
			_theme_exit(grid, c, config, rng, plan)
		_:
			# Unknown theme -> act like transit.
			_theme_transit(grid, c, config, rng, plan, floor_base_y)


static func _theme_entry(
		grid: ProcgenGrid, c: Chamber,
		config: ProcgenConfig, rng: RandomNumberGenerator,
		plan: Plan) -> void:
	_maybe_place_platforms(grid, c, config, rng, 1)


static func _theme_exit(
		grid: ProcgenGrid, c: Chamber,
		config: ProcgenConfig, rng: RandomNumberGenerator,
		plan: Plan) -> void:
	_maybe_place_platforms(grid, c, config, rng, 1)
	var dest_hint := ProcgenSetPieceLibrary.EntityHint.new()
	dest_hint.kind = "destination"
	dest_hint.tile = _pick_chamber_stand_tile(
			grid, c, c.floor_base_y, true)
	dest_hint.frequency = Frequency.Type.YELLOW
	plan.entity_hints.append(dest_hint)


static func _theme_transit(
		grid: ProcgenGrid, c: Chamber,
		config: ProcgenConfig, rng: RandomNumberGenerator,
		plan: Plan, floor_base_y: int) -> void:
	_maybe_place_platforms(
			grid, c, config, rng, config.platforms_per_chamber)
	# One bug region centered on the chamber.
	var bug_hint := ProcgenSetPieceLibrary.EntityHint.new()
	bug_hint.kind = "bug_region"
	bug_hint.tile = Vector2i(
			c.bounds.position.x + c.bounds.size.x / 2,
			floor_base_y - 4)
	bug_hint.frequency = _weighted_pick(
			config.weighted_frequencies(), rng)
	bug_hint.params = {
		"rate_delta": 1.0,
		"size_tiles": Vector2i(
				mini(10, c.bounds.size.x - 4), 6),
	}
	plan.entity_hints.append(bug_hint)


static func _theme_combat(
		grid: ProcgenGrid, c: Chamber,
		config: ProcgenConfig, rng: RandomNumberGenerator,
		plan: Plan, floor_base_y: int) -> void:
	_maybe_place_platforms(grid, c, config, rng, 1)
	var pocket_x: int = c.bounds.position.x + c.bounds.size.x / 2
	var pocket_y: int = floor_base_y - 4
	var stamp := ProcgenSetPieceLibrary.stamp_enemy_pocket(
			grid, Vector2i(pocket_x - 2, pocket_y - 2), rng, config)
	for h in stamp.hints:
		plan.entity_hints.append(h)


static func _theme_hazard(
		grid: ProcgenGrid, c: Chamber,
		config: ProcgenConfig, rng: RandomNumberGenerator,
		plan: Plan, floor_base_y: int) -> void:
	# Choose pool_sand_trap or web_tunnel.
	if rng.randi() % 2 == 0 and c.bounds.size.x >= 8:
		var px: int = c.bounds.position.x + (c.bounds.size.x - 6) / 2
		var py: int = floor_base_y - 1
		var stamp := ProcgenSetPieceLibrary.stamp_pool_sand_trap(
				grid, Vector2i(px, py - 2), 6, 2, rng)
		for h in stamp.hints:
			plan.entity_hints.append(h)
	elif c.bounds.size.x >= 10:
		var tx: int = c.bounds.position.x + (c.bounds.size.x - 8) / 2
		var ty: int = floor_base_y - 3
		var stamp2 := ProcgenSetPieceLibrary.stamp_web_tunnel(
				grid, Vector2i(tx, ty), 8, rng)
		for h in stamp2.hints:
			plan.entity_hints.append(h)
	else:
		# Chamber too narrow for either hazard — fall back to
		# combat so the level doesn't feel empty.
		_theme_combat(grid, c, config, rng, plan, floor_base_y)


static func _maybe_place_platforms(
		grid: ProcgenGrid,
		c: Chamber,
		config: ProcgenConfig,
		rng: RandomNumberGenerator,
		count: int) -> void:
	if c.bounds.size.x < 8:
		return
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var w := 5 + rng.randi_range(0, 4)
		if w >= c.bounds.size.x - 2:
			continue
		var thickness := 1 + rng.randi_range(0, 1)
		var x := rng.randi_range(
				c.bounds.position.x + 2,
				c.bounds.position.x + c.bounds.size.x - 2 - w)
		var min_y: int = c.bounds.position.y + 2
		var max_y := c.floor_base_y - 6
		if max_y <= min_y:
			return
		var y := rng.randi_range(min_y, max_y)
		var rect := Rect2i(x, y, w, thickness + 1)
		var freq := _weighted_pick(config.weighted_frequencies(), rng)
		_stamp_organic_platform(grid, rect, freq, rng)
		placed += 1


# ---- Platform + helpers (carry-over from the previous planner) -------------

static func _stamp_organic_platform(
		grid: ProcgenGrid,
		rect: Rect2i,
		freq: int,
		rng: RandomNumberGenerator) -> void:
	var w := rect.size.x
	var top_y := rect.position.y
	var max_drop := maxi(0, rect.size.y - 1)
	var heights := ProcgenShapes.noise_heights_1d(
			w, top_y, 1, 6.0, rng)
	var mid_from := w / 3
	var mid_to := (w * 2) / 3
	var mid_y: int = heights[mid_from] if mid_from < w else top_y
	for x_idx in range(mid_from, mid_to):
		heights[x_idx] = mid_y
	for x_idx in range(w):
		var col_x: int = rect.position.x + x_idx
		var col_top: int = clampi(
				heights[x_idx], top_y, top_y + max_drop)
		for y in range(col_top, rect.position.y + rect.size.y):
			grid.set_cell(col_x, y, freq)
	var cap_r := 1.5
	var left_cx: int = rect.position.x
	var right_cx: int = rect.position.x + rect.size.x - 1
	var cap_cy: int = rect.position.y + rect.size.y - 1
	ProcgenShapes.fill_circle(grid, left_cx, cap_cy, cap_r, freq)
	ProcgenShapes.fill_circle(grid, right_cx, cap_cy, cap_r, freq)


static func _pick_chamber_stand_tile(
		grid: ProcgenGrid,
		c: Chamber,
		floor_base_y: int,
		right_aligned: bool = false) -> Vector2i:
	# Prefer a column near the chamber's far side (entry → left
	# edge, exit → right edge) where the floor is guaranteed at
	# `floor_base_y` (enforced by _carve_chamber_floor's doorway
	# anchoring).
	var inset := 2
	var x: int
	if right_aligned:
		x = c.bounds.position.x + c.bounds.size.x - 1 - inset
	else:
		x = c.bounds.position.x + inset
	return Vector2i(x, floor_base_y - 1)


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
