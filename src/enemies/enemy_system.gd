class_name EnemySystem
extends Node
## Broadcasts echolocation pulse effects to all enemies. Enemies
## subscribe to this via the "enemies" group; EnemySystem listens to
## G.echo.pulse_emitted once and dispatches.
##
## Lives under Level so it's torn down on reset.


func _ready() -> void:
	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(apply_pulse_damage)
	else:
		G.warning(
				"EnemySystem: G.echo not ready; "
				+ "pulses will not damage enemies")


## Applies pulse perception/damage/knockback to every enemy currently
## in the tree. Matching-frequency enemies take damage + knockback;
## all in-range enemies get perception raised.
func apply_pulse_damage(pulse: EchoPulse) -> void:
	for enemy: Enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.receive_pulse(
				pulse.frequency,
				pulse.center,
				pulse.max_radius_px,
				pulse.damage)
