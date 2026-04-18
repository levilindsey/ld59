class_name HealthBar
extends ProgressBar
## Binds this ProgressBar to the player's PlayerHealth node. Polls
## the player each frame so respawn / level reset naturally
## re-targets without needing to (dis)connect signals.


func _ready() -> void:
	min_value = 0
	max_value = 100
	value = 100
	show_percentage = false


func _process(_delta: float) -> void:
	var health := _find_player_health()
	if not is_instance_valid(health):
		return
	if max_value != health.max_health:
		max_value = health.max_health
	if value != health.current_health:
		value = health.current_health


func _find_player_health() -> PlayerHealth:
	if not is_instance_valid(G.level) or not is_instance_valid(G.level.player):
		return null
	return G.level.player.get_node_or_null("PlayerHealth")
