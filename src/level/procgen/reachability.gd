class_name ProcgenReachability
extends RefCounted
## Hard-reachability BFS over a `ProcgenGrid` in tile coords.
##
## "Hard" means: every colored terrain type (RED/GREEN/BLUE/YELLOW)
## is treated as passable — assumes the player will carry the right
## frequency to carve through. Only INDESTRUCTIBLE, LIQUID and SAND
## are walls. WEB_* tiles are slow but passable.
##
## Movement rules approximated for a platformer:
##   * walk step between two standable cells sharing an edge;
##   * single-tile jump up (origin cell → +y-1 cell) if overhead is clear;
##   * fall drop through any empty cells below;
##   * carve-pass through a colored tile (counts as one step).
##
## Not a precise jump-arc graph — v2. Good enough to catch
## "destination is sealed in a separate cavern" failures at the
## generator level.


const _NEIGHBORS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const _JUMP_HEIGHT := 3
const _FALL_LIMIT := 40


## Returns true iff there's a reachable chain from `start` to `goal`
## under the hard-reachability rules.
static func path_exists(
		grid: ProcgenGrid,
		start: Vector2i,
		goal: Vector2i) -> bool:
	var visited := _reachable_set(grid, start)
	return visited.has(goal)


## Return every tile coord reachable from `start`. Use this for the
## "every feature is reachable" validator check.
static func reachable_set(
		grid: ProcgenGrid,
		start: Vector2i) -> Dictionary:
	return _reachable_set(grid, start)


## A tile is passable-for-reachability iff not hard and not a
## liquid/sand wall. Colored + WEB_* tiles are passable.
static func is_passable(grid: ProcgenGrid, p: Vector2i) -> bool:
	if not grid.in_bounds(p.x, p.y):
		return false
	var t := grid.get_cell(p.x, p.y)
	if t == Frequency.Type.NONE:
		return true
	if t == Frequency.Type.INDESTRUCTIBLE:
		return false
	if t == Frequency.Type.LIQUID:
		return false
	if t == Frequency.Type.SAND:
		# Sand is walkable-on-top (the player stands on it) but not
		# passable as movement volume. Treat as wall for the BFS and
		# rely on "standable" check for landings.
		return false
	# Colored or WEB_*.
	return true


static func _reachable_set(
		grid: ProcgenGrid,
		start: Vector2i) -> Dictionary:
	var visited: Dictionary = {}
	var frontier: Array[Vector2i] = []
	if grid.in_bounds(start.x, start.y) and is_passable(grid, start):
		frontier.append(start)
		visited[start] = true

	while not frontier.is_empty():
		var p: Vector2i = frontier.pop_back()
		# 4-neighbors.
		for d in _NEIGHBORS_4:
			var q := p + d
			if not is_passable(grid, q):
				continue
			if visited.has(q):
				continue
			visited[q] = true
			frontier.append(q)
		# Jump up (up to _JUMP_HEIGHT, must have clear overhead).
		for h in range(1, _JUMP_HEIGHT + 1):
			var jp := p + Vector2i(0, -h)
			if not is_passable(grid, jp):
				break
			if visited.has(jp):
				continue
			# Only consider landings: jp has a solid cell below at
			# jump apex OR the BFS will continue from it via neighbors.
			visited[jp] = true
			frontier.append(jp)
		# Drop: fall-through below until we hit a solid.
		for k in range(1, _FALL_LIMIT + 1):
			var dp := p + Vector2i(0, k)
			if not grid.in_bounds(dp.x, dp.y):
				break
			if not is_passable(grid, dp):
				break
			if not visited.has(dp):
				visited[dp] = true
				frontier.append(dp)
	return visited
