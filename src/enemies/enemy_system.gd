class_name EnemySystem
extends Node
## Broadcasts echolocation pulse effects to all enemies. Enemies
## subscribe to this via the "enemies" group; EnemySystem listens to
## G.echo.pulse_emitted once and dispatches.
##
## Also owns the registry of `Enemy.Kind -> PackedScene` so
## `EnemySpawnPoint` can spawn by enum rather than by PackedScene
## reference. Scenes are assigned in the scene inspector on the
## level template.
##
## Lives under Level so it's torn down on reset.


@export var spider_scene: PackedScene
@export var coyote_scene: PackedScene
@export var owl_scene: PackedScene


func _enter_tree() -> void:
	G.enemies = self


func _exit_tree() -> void:
	if G.enemies == self:
		G.enemies = null


func _ready() -> void:
	if is_instance_valid(G.echo):
		G.echo.pulse_emitted.connect(apply_pulse_damage)
	else:
		G.warning(
				"EnemySystem: G.echo not ready; "
				+ "pulses will not damage enemies")


## Returns the PackedScene registered for `kind`, or null if no
## scene is assigned in this level's EnemySystem.
func scene_for(kind: Enemy.Kind) -> PackedScene:
	match kind:
		Enemy.Kind.SPIDER:
			return spider_scene
		Enemy.Kind.COYOTE:
			return coyote_scene
		Enemy.Kind.OWL:
			return owl_scene
	return null


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
