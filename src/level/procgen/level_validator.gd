class_name ProcgenValidator
extends RefCounted
## Lint pipeline run after every generator or targeted-adjust call.
## A list of `Issue`s; empty list = level is shippable.
##
## Each check returns issues it finds; the caller decides whether
## issue severity triggers a regen or just a warning print.


enum Severity {
	ERROR,   # regen required
	WARNING, # playable but flagged
	INFO,    # informational
}


class Issue:
	var severity: int
	var code: String
	var message: String
	var tile: Vector2i = Vector2i(-1, -1)

	func _init(s: int, c: String, m: String, t: Vector2i = Vector2i(-1, -1)) -> void:
		severity = s
		code = c
		message = m
		tile = t


class Report:
	var issues: Array[Issue] = []

	func add(severity: int, code: String, message: String,
			tile: Vector2i = Vector2i(-1, -1)) -> void:
		issues.append(Issue.new(severity, code, message, tile))

	func has_errors() -> bool:
		for i in issues:
			if i.severity == Severity.ERROR:
				return true
		return false

	func summary_lines() -> Array[String]:
		var sev_name := {
			Severity.ERROR: "ERROR",
			Severity.WARNING: "WARN",
			Severity.INFO: "INFO",
		}
		var lines: Array[String] = []
		for i in issues:
			var where := ""
			if i.tile.x >= 0:
				where = " @ %s" % i.tile
			lines.append("[%s] %s: %s%s" % [
					sev_name[i.severity], i.code, i.message, where])
		return lines


## Run all checks. `plan` is the LayoutPlanner.Plan (contains spawn +
## destination). `entity_hints` is the list of entity hints placed.
static func validate(
		grid: ProcgenGrid,
		spawn: Vector2i,
		destination: Vector2i,
		entity_hints: Array) -> Report:
	var r := Report.new()

	_check_spawn_and_goal_standable(grid, spawn, destination, r)
	_check_bounds_wrapped(grid, r)
	_check_path_exists(grid, spawn, destination, r)
	_check_anchor_presence(grid, r)
	_check_liquid_containment(grid, r)
	_check_sand_shell_thickness(grid, r)
	_check_entity_hints(grid, entity_hints, r)
	_check_web_tunnels_have_spider(grid, entity_hints, r)
	_check_density(grid, r)

	return r


static func _check_spawn_and_goal_standable(
		grid: ProcgenGrid, spawn: Vector2i,
		goal: Vector2i, r: Report) -> void:
	if not grid.in_bounds(spawn.x, spawn.y):
		r.add(Severity.ERROR, "spawn_oob",
				"Spawn tile %s is out of grid bounds" % spawn, spawn)
	elif grid.is_solid(spawn.x, spawn.y):
		r.add(Severity.ERROR, "spawn_blocked",
				"Spawn tile is inside a solid cell", spawn)
	elif not grid.is_solid(spawn.x, spawn.y + 1):
		r.add(Severity.ERROR, "spawn_no_floor",
				"Spawn tile has no floor beneath it", spawn)

	if not grid.in_bounds(goal.x, goal.y):
		r.add(Severity.ERROR, "goal_oob",
				"Destination tile %s is out of grid bounds" % goal, goal)
	elif grid.is_solid(goal.x, goal.y):
		r.add(Severity.ERROR, "goal_blocked",
				"Destination tile is inside a solid cell", goal)
	elif not grid.is_solid(goal.x, goal.y + 1):
		r.add(Severity.ERROR, "goal_no_floor",
				"Destination tile has no floor beneath it", goal)


static func _check_bounds_wrapped(grid: ProcgenGrid, r: Report) -> void:
	# Every tile on the grid perimeter must be INDESTRUCTIBLE, so
	# the CC detach pass always has an anchor to reference.
	for x in range(grid.width):
		if grid.get_cell(x, 0) != Frequency.Type.INDESTRUCTIBLE:
			r.add(Severity.ERROR, "border_gap",
					"Top border tile is not INDESTRUCTIBLE",
					Vector2i(x, 0))
			return
		if grid.get_cell(x, grid.height - 1) != Frequency.Type.INDESTRUCTIBLE:
			r.add(Severity.ERROR, "border_gap",
					"Bottom border tile is not INDESTRUCTIBLE",
					Vector2i(x, grid.height - 1))
			return
	for y in range(grid.height):
		if grid.get_cell(0, y) != Frequency.Type.INDESTRUCTIBLE:
			r.add(Severity.ERROR, "border_gap",
					"Left border tile is not INDESTRUCTIBLE",
					Vector2i(0, y))
			return
		if grid.get_cell(grid.width - 1, y) != Frequency.Type.INDESTRUCTIBLE:
			r.add(Severity.ERROR, "border_gap",
					"Right border tile is not INDESTRUCTIBLE",
					Vector2i(grid.width - 1, y))
			return


static func _check_path_exists(
		grid: ProcgenGrid, spawn: Vector2i,
		goal: Vector2i, r: Report) -> void:
	if not ProcgenReachability.path_exists(grid, spawn, goal):
		r.add(Severity.ERROR, "unreachable_goal",
				"Destination not reachable from spawn under hard BFS",
				goal)


static func _check_anchor_presence(grid: ProcgenGrid, r: Report) -> void:
	var anchors := grid.find_cells_of_type(Frequency.Type.INDESTRUCTIBLE)
	var expected_min := 2 * (grid.width + grid.height) - 4
	if anchors.size() < expected_min:
		r.add(Severity.WARNING, "anchor_deficit",
				"Only %d INDESTRUCTIBLE cells (expected >= %d for a full border)"
				% [anchors.size(), expected_min])


static func _check_liquid_containment(grid: ProcgenGrid, r: Report) -> void:
	# Every LIQUID cell should have a non-passable (hard or sand)
	# cell directly beneath it — otherwise the liquid falls out of
	# its container immediately and the pool is broken.
	for y in range(grid.height):
		for x in range(grid.width):
			if grid.get_cell(x, y) != Frequency.Type.LIQUID:
				continue
			var below := grid.get_cell(x, y + 1)
			var supported := (
					below == Frequency.Type.INDESTRUCTIBLE
					or below == Frequency.Type.SAND
					or below == Frequency.Type.LIQUID)
			if not supported:
				r.add(Severity.WARNING, "liquid_unsupported",
						"LIQUID cell has no support beneath",
						Vector2i(x, y))
				return


static func _check_sand_shell_thickness(
		grid: ProcgenGrid, r: Report) -> void:
	# For every SAND cell that sits directly under LIQUID, measure
	# the SAND column thickness and flag if < 1 or > 3 tiles.
	for y in range(grid.height):
		for x in range(grid.width):
			if grid.get_cell(x, y) != Frequency.Type.SAND:
				continue
			if grid.get_cell(x, y - 1) != Frequency.Type.LIQUID:
				continue
			var depth := 0
			var yy := y
			while yy < grid.height \
					and grid.get_cell(x, yy) == Frequency.Type.SAND:
				depth += 1
				yy += 1
			if depth < 1:
				r.add(Severity.ERROR, "sand_shell_too_thin",
						"SAND shell under LIQUID is 0 deep",
						Vector2i(x, y))
			elif depth > 3:
				r.add(Severity.WARNING, "sand_shell_too_thick",
						"SAND shell under LIQUID is %d deep (>3)" % depth,
						Vector2i(x, y))


static func _check_entity_hints(
		grid: ProcgenGrid,
		hints: Array,
		r: Report) -> void:
	for raw in hints:
		var h: ProcgenSetPieceLibrary.EntityHint = raw
		if not grid.in_bounds(h.tile.x, h.tile.y):
			r.add(Severity.ERROR, "hint_oob",
					"Entity hint '%s' out of bounds" % h.kind, h.tile)
			continue
		if grid.is_solid(h.tile.x, h.tile.y):
			r.add(Severity.ERROR, "hint_in_solid",
					"Entity hint '%s' is inside a solid tile" % h.kind,
					h.tile)


static func _check_web_tunnels_have_spider(
		grid: ProcgenGrid,
		hints: Array,
		r: Report) -> void:
	# Collect WEB tile positions + Spider spawner positions. Every
	# web cluster needs at least one spider within 8 tiles Manhattan.
	var web_cells: Array[Vector2i] = []
	for y in range(grid.height):
		for x in range(grid.width):
			var t := grid.get_cell(x, y)
			if t >= Frequency.Type.WEB_RED and t <= Frequency.Type.WEB_YELLOW:
				web_cells.append(Vector2i(x, y))
	if web_cells.is_empty():
		return
	var spiders: Array[Vector2i] = []
	for raw in hints:
		var h: ProcgenSetPieceLibrary.EntityHint = raw
		if h.kind == "enemy_spider":
			spiders.append(h.tile)
	if spiders.is_empty():
		r.add(Severity.WARNING, "web_without_spider",
				"%d WEB tiles exist but no Spider spawner hint was emitted"
				% web_cells.size())
		return
	for w in web_cells:
		var nearest := INF
		for s in spiders:
			var d: float = float(absi(w.x - s.x) + absi(w.y - s.y))
			if d < nearest:
				nearest = d
		if nearest > 8.0:
			r.add(Severity.WARNING, "web_far_from_spider",
					"WEB tile is %d tiles from nearest spider"
					% int(nearest), w)
			return


static func _check_density(grid: ProcgenGrid, r: Report) -> void:
	var total := grid.width * grid.height
	var solid := grid.count_non_empty()
	var ratio := float(solid) / float(max(1, total))
	if ratio < 0.2:
		r.add(Severity.WARNING, "density_low",
				"Solid-cell ratio %.2f (expected >= 0.2)" % ratio)
	elif ratio > 0.7:
		r.add(Severity.WARNING, "density_high",
				"Solid-cell ratio %.2f (expected <= 0.7)" % ratio)
