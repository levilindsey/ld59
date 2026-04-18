class_name EnemySpawnPoint
extends Node2D
## Single-shot enemy spawn. Spawns one `enemy_scene` at this node's
## world position on _ready. Use RespawningEnemySpawnPoint for
## continuous/capped respawns.


## Scene instantiated on spawn. Typically one of
## `monster_bird.tscn`, `spider.tscn`, `flying_critter.tscn`.
@export var enemy_scene: PackedScene

## Optional override for the spawned enemy's frequency. If left as
## `Frequency.Type.NONE` the scene's baked-in frequency is kept.
@export var frequency_override: int = Frequency.Type.NONE


func _ready() -> void:
	spawn_one()


## Instantiate `enemy_scene`, position it at this node, and parent
## it here so level reset tears it down with the spawn point.
## Returns the new Enemy or null on failure.
func spawn_one() -> Enemy:
	if not G.ensure_valid(
			enemy_scene,
			"EnemySpawnPoint.enemy_scene is unset"):
		return null

	var enemy: Enemy = enemy_scene.instantiate()
	if frequency_override != Frequency.Type.NONE:
		enemy.frequency = frequency_override
	add_child(enemy)
	enemy.global_position = global_position
	return enemy
