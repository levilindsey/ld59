class_name BugRegionProbe
extends Area2D
## Small Area2D parented under the player. Detects overlapping
## BugSpawnRegion nodes so the BugSpawner can aggregate per-frequency
## spawn rates. Filters by type (`is BugSpawnRegion`) rather than by
## physics layer so authoring doesn't need to manage mask bits.


func _ready() -> void:
	monitoring = true
	monitorable = false


## Sum `rate_delta` across all currently overlapping BugSpawnRegions
## that match `frequency`. Returns 0.0 if no overlap.
func get_rate_for(frequency: int) -> float:
	var total := 0.0
	for area in get_overlapping_areas():
		if area is BugSpawnRegion:
			var region := area as BugSpawnRegion
			if region.frequency == frequency:
				total += region.rate_delta
	return total
