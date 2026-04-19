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
## footprint. `width` and `depth` are in tiles.
static func stamp_pool_sand_trap(
		grid: ProcgenGrid,
		anchor: Vector2i,
		width: int,
		depth: int,
		rng: RandomNumberGenerator) -> Stamp:
	var out := Stamp.new()
	width = maxi(3, width)
	depth = maxi(2, depth)

	# Footprint sanity check.
	if anchor.x < 1 or anchor.y < 1:
		return out
	if anchor.x + width >= grid.width or anchor.y + depth + 1 >= grid.height:
		return out

	# INDESTRUCTIBLE rim: one-tile wall on left/right, one-tile floor
	# of SAND under the basin.
	for y in range(anchor.y, anchor.y + depth):
		grid.set_cell(anchor.x, y, Frequency.Type.INDESTRUCTIBLE)
		grid.set_cell(anchor.x + width - 1, y, Frequency.Type.INDESTRUCTIBLE)

	# SAND shell (2 tiles thick — player can carve through, but not
	# trivially with a single pulse).
	var shell_y := anchor.y + depth
	for x in range(anchor.x + 1, anchor.x + width - 1):
		grid.set_cell(x, shell_y, Frequency.Type.SAND)
		grid.set_cell(x, shell_y + 1, Frequency.Type.SAND)

	# LIQUID fill above the shell.
	for y in range(anchor.y, anchor.y + depth):
		for x in range(anchor.x + 1, anchor.x + width - 1):
			grid.set_cell(x, y, Frequency.Type.LIQUID)

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
	# bypassed by carving around them.
	for x in range(anchor.x, anchor.x + length):
		grid.set_cell(x, anchor.y - 1, Frequency.Type.INDESTRUCTIBLE)
		grid.set_cell(x, anchor.y + 2, Frequency.Type.INDESTRUCTIBLE)

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


## Small alcove with a single enemy spawner.
static func stamp_enemy_pocket(
		grid: ProcgenGrid,
		anchor: Vector2i,
		rng: RandomNumberGenerator,
		config: ProcgenConfig) -> Stamp:
	var out := Stamp.new()
	# Dig a 4x3 alcove if the surrounding 5x4 area is mostly solid.
	var w := 4
	var h := 3
	if anchor.x + w >= grid.width or anchor.y + h >= grid.height:
		return out
	for y in range(anchor.y, anchor.y + h):
		for x in range(anchor.x, anchor.x + w):
			grid.set_cell(x, y, Frequency.Type.NONE)

	# Pick an enemy type. Ground enemies want a floor below them;
	# flyers want open air.
	var has_floor_below := grid.is_solid(anchor.x + 1, anchor.y + h)
	var kind: String
	if has_floor_below:
		# Coyote (active chase + jump) vs Spider (passive ambusher).
		kind = "enemy_coyote" if (rng.randi() % 3 == 0) else "enemy_spider"
	else:
		kind = "enemy_bird" if (rng.randi() % 2 == 0) else "enemy_critter"

	var hint := EntityHint.new()
	hint.kind = kind
	# Spawn tile is the floor-of-the-alcove if ground, else mid-air.
	var spawn_y := anchor.y + h - 1 if has_floor_below else anchor.y + 1
	hint.tile = Vector2i(anchor.x + w / 2, spawn_y)
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
