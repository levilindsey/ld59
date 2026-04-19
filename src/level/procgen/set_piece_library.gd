class_name ProcgenSetPieceLibrary
extends RefCounted
## A stamp is a small rectangle of typed tiles + optional
## entity-placement hints (where spawn points / bug regions should
## go alongside the terrain). The library picks an appropriate
## anchor point in the grid and writes the stamp there.
##
## v1 set-pieces:
##   pool_sand_trap   — LIQUID basin over a thin SAND shell with an
##                      INDESTRUCTIBLE rim so the liquid stays put
##                      until the player breaks the shell.
##   web_tunnel       — horizontal corridor gated by WEB tiles; pairs
##                      with a Spider spawner placed inside.
##   enemy_pocket     — small alcove with one enemy spawner appropriate
##                      to the enemy type.
##   bug_region       — open area that hosts a BugSpawnRegion (no
##                      terrain change; just a zone tag).


## Entity-placement hint emitted by a stamp. Consumed by
## `EntityPlacer` after all terrain writes are done.
class EntityHint:
	## "enemy_spider", "enemy_coyote", "enemy_bird", "enemy_critter",
	## "bug_region", "destination" (latter normally placed by the
	## layout planner, not a stamp).
	var kind: String
	## Tile coord of the hint anchor. World coord = tile * 16 + 8.
	var tile: Vector2i
	## Optional frequency override for bug_region / enemy tint.
	var frequency: int = Frequency.Type.NONE
	## Optional tuning (rate_delta, max_active, etc) packed as Dict.
	var params: Dictionary = {}


class Stamp:
	var hints: Array[EntityHint] = []


## Stamp a LIQUID pool over a SAND shell with an INDESTRUCTIBLE rim.
## `anchor` is the tile coord of the bottom-left cell of the pool
## footprint. `width` and `depth` are in tiles. Shape is elliptical
## rather than rectangular — rim wraps the basin as a thick ring,
## liquid fills the inside, and a curved SAND shell traces the
## bottom arc.
static func stamp_pool_sand_trap(
		grid: ProcgenGrid,
		anchor: Vector2i,
		width: int,
		depth: int,
		rng: RandomNumberGenerator) -> Stamp:
	var out := Stamp.new()
	width = maxi(4, width)
	depth = maxi(3, depth)

	var cx := anchor.x + width / 2
	var cy := anchor.y + depth
	var rx := float(width) / 2.0
	var ry := float(depth)

	# Footprint sanity check.
	if cx - rx < 1.0 or cy - ry < 1.0:
		return out
	if cx + rx >= grid.width - 1 or cy + ry + 2 >= grid.height:
		return out

	# INDESTRUCTIBLE rim: an ellipse slightly larger than the basin.
	# Hollow it out with the interior ellipse in the next step so it
	# reads as a ring wall.
	ProcgenShapes.fill_ellipse(
			grid, cx, cy, rx + 1.0, ry + 1.0,
			Frequency.Type.INDESTRUCTIBLE)

	# LIQUID fill carves the interior out of the rim.
	ProcgenShapes.fill_ellipse(
			grid, cx, cy, rx, ry, Frequency.Type.LIQUID)

	# SAND shell: a thin arc tracing the ellipse bottom. The shell
	# is the ring between radius `ry` and `ry + 1.5` on the lower
	# hemisphere only, so the player breaks through from above by
	# carving downward.
	for dy in range(0, int(ceil(ry + 2.0))):
		for dx in range(-int(ceil(rx + 1.0)), int(ceil(rx + 1.0)) + 1):
			var nx := float(dx) / rx
			var ny := float(dy) / ry
			var d := nx * nx + ny * ny
			if d > 1.6 or d < 0.9:
				continue
			# Only lower hemisphere (dy > 0).
			if dy <= 0:
				continue
			grid.set_cell(cx + dx, cy + dy, Frequency.Type.SAND)

	return out


## Horizontal tunnel that the player has to slow-push through (via
## WEB slowdown) or carve (via matching-frequency pulse). Emits a
## spider spawner hint near the tunnel so the player sees what lives
## there before they enter.
static func stamp_web_tunnel(
		grid: ProcgenGrid,
		anchor: Vector2i,
		length: int,
		rng: RandomNumberGenerator) -> Stamp:
	var out := Stamp.new()
	length = maxi(4, length)
	if anchor.x + length >= grid.width - 1:
		return out
	if anchor.y < 1 or anchor.y + 2 >= grid.height - 1:
		return out

	# INDESTRUCTIBLE ceiling + floor for the tunnel so webs can't be
	# bypassed by carving around them. Jitter the outer edges ±1
	# tile so the tunnel doesn't read as a pristine corridor; the
	# INSIDE lane (anchor.y .. anchor.y+1) stays straight so the
	# reachability BFS still finds a 2-tile-tall walkway.
	var ceil_jitter := ProcgenShapes.noise_heights_1d(
			length, anchor.y - 1, 1, 5.0, rng)
	var floor_jitter := ProcgenShapes.noise_heights_1d(
			length, anchor.y + 2, 1, 5.0, rng)
	for x_idx in range(length):
		var x := anchor.x + x_idx
		var c: int = mini(ceil_jitter[x_idx], anchor.y - 1)
		var f: int = maxi(floor_jitter[x_idx], anchor.y + 2)
		for y in range(c, anchor.y):
			grid.set_cell(x, y, Frequency.Type.INDESTRUCTIBLE)
		for y in range(anchor.y + 2, f + 1):
			grid.set_cell(x, y, Frequency.Type.INDESTRUCTIBLE)

	# Hollow the tunnel itself.
	for x in range(anchor.x, anchor.x + length):
		for y in range(anchor.y, anchor.y + 2):
			grid.set_cell(x, y, Frequency.Type.NONE)

	# WEB tiles sprinkled across the tunnel. Every 2 tiles in x, pick
	# a weighted frequency WEB_* variant.
	var freq_entries := [
		[Frequency.Type.WEB_RED, 1],
		[Frequency.Type.WEB_GREEN, 3],
		[Frequency.Type.WEB_BLUE, 1],
		[Frequency.Type.WEB_YELLOW, 1],
	]
	for x in range(anchor.x + 1, anchor.x + length - 1, 2):
		var web_type: int = _weighted_pick(freq_entries, rng)
		# Webs always on the top row of the tunnel so the player has
		# to walk through them rather than jump over.
		grid.set_cell(x, anchor.y, web_type)
		grid.set_cell(x, anchor.y + 1, web_type)

	# Spider spawner placed at the left mouth of the tunnel, one tile
	# outside, on the tunnel floor.
	var spider_hint := EntityHint.new()
	spider_hint.kind = "enemy_spider"
	spider_hint.tile = Vector2i(anchor.x - 2, anchor.y + 1)
	spider_hint.params = {"respawn": true, "max_active": 2}
	out.hints.append(spider_hint)
	return out


## Small alcove with a single enemy spawner. Shape is a blob (main
## disc + jittered lumps) for a more natural cavern-mouth feel than
## the previous rectangular hollow.
static func stamp_enemy_pocket(
		grid: ProcgenGrid,
		anchor: Vector2i,
		rng: RandomNumberGenerator,
		config: ProcgenConfig) -> Stamp:
	var out := Stamp.new()
	var cx := anchor.x + 2
	var cy := anchor.y + 2
	if cx < 3 or cx >= grid.width - 3 or cy < 3 or cy >= grid.height - 3:
		return out
	ProcgenShapes.stamp_blob(
			grid, cx, cy, 2.4, Frequency.Type.NONE, rng, 4)

	# Same enemy-type logic: check whether there's a solid cell
	# beneath the pocket center, pick ground vs air enemy.
	var has_floor_below := grid.is_solid(cx, cy + 3)
	var kind: String
	if has_floor_below:
		kind = "enemy_coyote" if (rng.randi() % 3 == 0) else "enemy_spider"
	else:
		kind = "enemy_bird" if (rng.randi() % 2 == 0) else "enemy_critter"

	var hint := EntityHint.new()
	hint.kind = kind
	var spawn_y := cy + 2 if has_floor_below else cy
	hint.tile = Vector2i(cx, spawn_y)
	hint.params = {"respawn": true, "max_active": 2}
	hint.frequency = _weighted_pick(config.weighted_frequencies(), rng)
	out.hints.append(hint)
	return out


## Bug region. Doesn't modify terrain — just emits a hint for the
## entity placer to drop a `BugSpawnRegion` Area2D with the given
## frequency + rate.
static func stamp_bug_region(
		anchor: Vector2i,
		frequency: int,
		rate_delta: float) -> Stamp:
	var out := Stamp.new()
	var hint := EntityHint.new()
	hint.kind = "bug_region"
	hint.tile = anchor
	hint.frequency = frequency
	hint.params = {"rate_delta": rate_delta, "size_tiles": Vector2i(10, 8)}
	out.hints.append(hint)
	return out


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
