class_name BugSpawner
extends Node2D
## Ticks per-frequency spawn rates by iterating authored
## BugSpawnRegion nodes (grouped at runtime) and instantiates Bug
## scenes in an annulus around the player. Stacks region
## contributions additively, applies a per-frequency minimum-rate
## floor to prevent soft-lock, and rejects candidate positions that
## fall inside a solid tile.
##
## Lives under Level so it's torn down on level reset.


## Frequencies the spawner rotates through. Kept here rather than
## hard-coded so level designers can restrict the set per-level.
const _SPAWN_FREQUENCIES := [
	Frequency.Type.RED,
	Frequency.Type.GREEN,
	Frequency.Type.BLUE,
	Frequency.Type.YELLOW,
]

## Physics layer mask used for the "candidate inside a solid tile?"
## rejection check. 1 << 0 = normal_surfaces.
const _SOLID_MASK := 1

const _MAX_REJECTION_TRIES := 8


## Bug scene to instantiate. Assigned in the scene inspector.
@export var bug_scene: PackedScene

## Inner radius of the spawn annulus around the player. Keeps bugs
## from appearing right on top of the player.
@export_range(16.0, 512.0) var min_spawn_radius_px := 96.0
## Outer radius. Roughly matches a pulse's visible range so new
## bugs are findable without immediately exiting the play area.
@export_range(32.0, 1024.0) var max_spawn_radius_px := 256.0

## Hard cap on concurrent alive bugs per frequency. Prevents runaway
## spawn counts if the player stays in a high-rate region forever.
@export_range(1, 64) var max_concurrent_per_frequency := 12

## Probability denominator for big bugs: on each spawn, a
## `randi() % N == 0` roll becomes BIG, else SMALL. Default 4 gives
## a ~25% big-bug rate — "big bugs spawn 1/4 as often" per the
## design ask.
@export_range(1, 16) var big_bug_ratio_denominator: int = 4

## Floor rate (bugs/sec) applied after region stacking, per
## frequency. Prevents "player is stuck on the wrong frequency with
## no matching bugs anywhere nearby" soft-locks. Dictionary of
## Frequency.Type -> float. Keys not present default to 0.
@export var min_rate_floor: Dictionary = {
	Frequency.Type.RED: 0.08,
	Frequency.Type.GREEN: 0.08,
	Frequency.Type.BLUE: 0.08,
	Frequency.Type.YELLOW: 0.08,
}

## Base rate (bugs/sec) applied before region stacking. Typically 0.
@export var base_rates: Dictionary = {
	Frequency.Type.RED: 0.0,
	Frequency.Type.GREEN: 0.0,
	Frequency.Type.BLUE: 0.0,
	Frequency.Type.YELLOW: 0.0,
}

## Global multiplier applied to the per-frequency rate after base +
## region stacking + min-floor. Scales bug spawn frequency
## uniformly without having to retune every region or floor value.
@export_range(0.0, 10.0) var spawn_rate_multiplier: float = 2.0

## Seeded RNG for the big/small roll. Kept separate from global
## `randi()` so other per-spawn randomness (spawn position,
## lifetime jitter) doesn't shift if we tune this ratio.
var _size_rng := RandomNumberGenerator.new()

## Accumulated Poisson phase per frequency. When phase crosses
## `_thresholds[freq]`, a bug is spawned and the threshold is
## re-rolled from an Exp(1) distribution.
var _phases: Dictionary = {}
var _thresholds: Dictionary = {}
## Live-bug counters per frequency. Decremented when a bug frees.
var _alive_counts: Dictionary = {}


func _enter_tree() -> void:
	G.bugs = self


func _exit_tree() -> void:
	if G.bugs == self:
		G.bugs = null


func _ready() -> void:
	_size_rng.randomize()
	for freq: int in _SPAWN_FREQUENCIES:
		_phases[freq] = 0.0
		_thresholds[freq] = _sample_exp_threshold()
		_alive_counts[freq] = 0


## Returns every Bug currently alive under this spawner. Used by the
## echolocation renderer to push tag halos to the composite shader.
func get_alive_bugs() -> Array[Bug]:
	var result: Array[Bug] = []
	for child in get_children():
		if child is Bug:
			result.append(child as Bug)
	return result


func _process(delta: float) -> void:
	if not is_instance_valid(G.level) or not is_instance_valid(G.level.player):
		return

	var player_pos: Vector2 = G.level.player.global_position
	var stacked_deltas := _aggregate_region_deltas(player_pos)

	for freq: int in _SPAWN_FREQUENCIES:
		var rate := _compute_rate(freq, stacked_deltas.get(freq, 0.0))
		if rate <= 0.0:
			continue

		_phases[freq] += rate * delta
		while _phases[freq] >= _thresholds[freq]:
			_phases[freq] -= _thresholds[freq]
			_thresholds[freq] = _sample_exp_threshold()
			_try_spawn(freq)


## Sum `rate_delta` across every region whose rect contains
## `player_pos`, bucketed by frequency. Unused frequencies are
## absent from the result.
func _aggregate_region_deltas(player_pos: Vector2) -> Dictionary:
	var deltas: Dictionary = {}
	for node in get_tree().get_nodes_in_group(BugSpawnRegion.GROUP):
		var region := node as BugSpawnRegion
		if region == null:
			continue
		if not region.contains_point(player_pos):
			continue
		deltas[region.frequency] = (
				deltas.get(region.frequency, 0.0) + region.rate_delta)
	return deltas


func _compute_rate(freq: int, stacked_delta: float) -> float:
	var base: float = base_rates.get(freq, 0.0)
	var floor_rate: float = min_rate_floor.get(freq, 0.0)
	return maxf(base + stacked_delta, floor_rate) * spawn_rate_multiplier


func _try_spawn(freq: int) -> void:
	if _alive_counts[freq] >= max_concurrent_per_frequency:
		return
	if not G.ensure_valid(bug_scene, "BugSpawner.bug_scene is unset"):
		return

	var player_pos: Vector2 = G.level.player.global_position
	var spawn_pos := _find_spawn_position(player_pos)
	if spawn_pos == Vector2.INF:
		return

	var bug: Bug = bug_scene.instantiate()
	bug.frequency = freq
	# Pick size BEFORE `add_child` so the setter's scale/collision/
	# juice_grant re-application lands before `_ready` runs.
	var is_big := _size_rng.randi() % maxi(1, big_bug_ratio_denominator) == 0
	bug.size_variant = (
			Bug.SizeVariant.BIG if is_big else Bug.SizeVariant.SMALL)
	bug.global_position = spawn_pos
	add_child(bug)
	_alive_counts[freq] += 1
	bug.tree_exited.connect(_on_bug_tree_exited.bind(freq))


func _find_spawn_position(player_pos: Vector2) -> Vector2:
	for attempt in range(_MAX_REJECTION_TRIES):
		var candidate := _sample_annulus(player_pos)
		if not _is_solid_at(candidate):
			return candidate
	return Vector2.INF


func _sample_annulus(center: Vector2) -> Vector2:
	var theta := randf() * TAU
	# Uniform sampling in annulus area: r = sqrt(u*(R² - r²) + r²).
	var r_min_sq := min_spawn_radius_px * min_spawn_radius_px
	var r_max_sq := max_spawn_radius_px * max_spawn_radius_px
	var r_sq := randf() * (r_max_sq - r_min_sq) + r_min_sq
	var radius := sqrt(r_sq)
	return center + Vector2.from_angle(theta) * radius


func _is_solid_at(world_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = _SOLID_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result := space.intersect_point(query, 1)
	return not result.is_empty()


func _on_bug_tree_exited(freq: int) -> void:
	_alive_counts[freq] = maxi(0, _alive_counts[freq] - 1)


func _sample_exp_threshold() -> float:
	# Exp(1) inverse CDF: -ln(1 - U). Guard against log(0).
	var u := randf()
	if u >= 1.0:
		u = 0.999999
	return -log(1.0 - u)

