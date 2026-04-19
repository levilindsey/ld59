class_name Destination
extends Area2D
## Win-condition object placed by the level generator (or by hand).
## Visually it's Mama Catbaticorn — a 2×-scaled AnimatedSprite2D
## sharing the player's SpriteFrames (`src/player/player_frames.tres`).
## When the player's body enters this area, the level transitions to
## its "won" state via `G.level.win()`. The `frequency` export is
## retained for backward compat but no longer tints the sprite —
## Mama is always full-color.


## Retained for compatibility with existing scene-file `frequency`
## assignments. Cosmetically a no-op now; kept so procgen / level
## designers can set it without breaking.
@export var frequency: int = Frequency.Type.YELLOW


func _ready() -> void:
	monitoring = true
	monitorable = false
	# Player is on layer 4 (bit 3); mask matches only the player.
	collision_layer = 0
	collision_mask = 1 << 3
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	if is_instance_valid(G.level):
		G.level.win()
