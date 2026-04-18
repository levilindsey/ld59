class_name BugSpawnRegion
extends Area2D
## Authored region placed in level scenes. Contributes `rate_delta`
## bugs-per-second of `frequency` to the BugSpawner's spawn rate
## whenever the player (via BugRegionProbe) overlaps this region.
##
## Multiple regions stack additively per frequency. Negative
## rate_delta is allowed so designers can author dead-zones; the
## total stacked rate is clamped at the spawner.


## Physics layer bit (9) reserved for bug spawn regions. Set
## programmatically so level designers don't have to manage masks.
const _BUG_REGION_LAYER_BIT := 1 << 8


@export var frequency: int = Frequency.Type.GREEN
## Bugs per second contributed for this frequency while the probe
## overlaps the region. Can be negative to suppress spawns.
@export var rate_delta: float = 1.0


func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = _BUG_REGION_LAYER_BIT
	collision_mask = 0
