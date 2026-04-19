class_name Destination
extends Area2D
## Win-condition object placed by the level generator (or by hand).
## When the player's body enters this area, the level transitions to
## its "won" state via `G.level.win()`. Frequency-tinted sprite so
## players visually recognize it as a terminal goal rather than a
## pickup or prop.


## Frequency tint; cosmetic only (does not gate the win).
@export var frequency: int = Frequency.Type.YELLOW


func _ready() -> void:
	monitoring = true
	monitorable = false
	# Player is on layer 4 (bit 3); mask matches only the player.
	collision_layer = 0
	collision_mask = 1 << 3
	body_entered.connect(_on_body_entered)
	_apply_frequency_tint()


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	if is_instance_valid(G.level):
		G.level.win()


func _apply_frequency_tint() -> void:
	var color := Frequency.color_of(frequency)
	modulate = Color(color.r, color.g, color.b, modulate.a)
