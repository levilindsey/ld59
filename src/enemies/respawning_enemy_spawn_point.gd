@tool
class_name RespawningEnemySpawnPoint
extends EnemySpawnPoint
## Enemy spawn point that keeps up to `max_active` enemies alive,
## respawning on an interval as they die. Seeds the first batch on
## ready and then ticks a simple countdown timer.


@export_range(1, 16) var max_active: int = 3:
	set(value):
		max_active = value
		queue_redraw()
@export_range(0.1, 60.0) var respawn_interval_sec: float = 5.0:
	set(value):
		respawn_interval_sec = value
		queue_redraw()


var _active_count: int = 0
var _respawn_countdown_sec: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Override: do not auto-spawn one via EnemySpawnPoint._ready();
	# this class manages its own cadence.
	_respawn_countdown_sec = 0.0
	# Seed the first batch so the room isn't empty on level load.
	while _active_count < max_active:
		if _spawn_tracked() == null:
			break


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _active_count >= max_active:
		return

	_respawn_countdown_sec -= delta
	if _respawn_countdown_sec > 0.0:
		return

	_respawn_countdown_sec = respawn_interval_sec
	_spawn_tracked()


func _spawn_tracked() -> Enemy:
	var enemy := spawn_one()
	if not is_instance_valid(enemy):
		return null
	_active_count += 1
	enemy.tree_exited.connect(_on_enemy_tree_exited)
	return enemy


func _on_enemy_tree_exited() -> void:
	_active_count = maxi(0, _active_count - 1)


func _editor_label_text() -> String:
	return "%s x%d @%.1fs" % [
		super(), max_active, respawn_interval_sec,
	]
