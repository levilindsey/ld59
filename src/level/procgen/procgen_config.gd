class_name ProcgenConfig
extends Resource
## Tunables for a single procedurally generated level. Passed to
## `ProcgenLevel.generate()`. Keep this small and explicit — anything
## that affects shipped gameplay goes here, anything cosmetic gets
## baked into `SetPieceLibrary` stamps.


## Master seed. Same seed + same code = same level.
@export var seed: int = 0

## Level size in TileMapLayer tile units (16 px each).
@export_range(32, 512) var width_tiles: int = 72
@export_range(24, 256) var height_tiles: int = 40

## Thickness of the INDESTRUCTIBLE border that wraps the play area.
@export_range(1, 6) var border_tiles: int = 2

## Number of chambers in the sequence. Spawn lands in chamber 0,
## destination in chamber N-1; the middle chambers carry themed
## gameplay beats (transit / combat / hazard). 2 = minimal
## spawn-to-goal with nothing in between; 4–6 is the sweet spot.
@export_range(2, 10) var chamber_count: int = 5

## Per-chamber platform budget. Each chamber attempts up to this
## many floating platforms on top of its themed content.
@export_range(0, 8) var platforms_per_chamber: int = 2

## Rotation of themes assigned to the interior chambers
## (chambers 1..N-2). Entry (0) and Exit (N-1) are fixed. If the
## level has more interior chambers than this array has entries,
## the rotation repeats. Values: "transit", "combat", "hazard".
@export var interior_themes: PackedStringArray = PackedStringArray([
	"transit", "combat", "hazard",
])

## Rough set-piece mix. Values are relative weights.
@export var mix_pool_sand_trap: int = 3
@export var mix_web_tunnel: int = 3
@export var mix_enemy_pocket: int = 4
@export var mix_bug_region: int = 5

## How many regen attempts before giving up. Each attempt reseeds
## derived streams from (master_seed + attempt) so we explore
## different layouts.
@export_range(1, 32) var max_regen_attempts: int = 12

## Frequency mix used for internal platforms + set-pieces. Weights
## are relative. Higher-entropy levels feel more varied but the bug
## spawner has to cover every frequency that appears.
@export var freq_weight_red: int = 1
@export var freq_weight_green: int = 3
@export var freq_weight_blue: int = 1
@export var freq_weight_yellow: int = 1


## Convenience: return the four gameplay-frequency values with their
## relative weights for weighted random draws.
func weighted_frequencies() -> Array:
	return [
		[Frequency.Type.RED, max(0, freq_weight_red)],
		[Frequency.Type.GREEN, max(0, freq_weight_green)],
		[Frequency.Type.BLUE, max(0, freq_weight_blue)],
		[Frequency.Type.YELLOW, max(0, freq_weight_yellow)],
	]


func set_piece_weights() -> Array:
	return [
		["pool_sand_trap", max(0, mix_pool_sand_trap)],
		["web_tunnel", max(0, mix_web_tunnel)],
		["enemy_pocket", max(0, mix_enemy_pocket)],
		["bug_region", max(0, mix_bug_region)],
	]
