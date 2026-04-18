class_name PlayerHealth
extends Node
## Tracks the player's HP and emits signals on change/death. Owned
## by the player; accessed via `player.health` (or the unique-name
## child `%PlayerHealth`).
##
## Damage and heal callers are gameplay systems (enemies, bugs,
## fluid, fragments). Death handling is delegated via the `died`
## signal so callers don't need to know about scene reload.


## Emitted after every health change, including ones that don't
## cross the 0 boundary. `current` is clamped to [0, max_health].
signal health_changed(current: int, max: int)

## Emitted exactly once when health first hits 0. The node stays in
## the tree; whoever is connected (typically Level) decides what to
## do next.
signal died


@export_range(1, 500) var max_health: int = 100
## Starting health. Defaults to `max_health` if left negative.
@export_range(-1, 500) var starting_health: int = -1


var current_health: int
var _is_dead: bool = false


func _ready() -> void:
	current_health = max_health if starting_health < 0 else starting_health
	current_health = clampi(current_health, 0, max_health)
	health_changed.emit(current_health, max_health)


func apply_damage(amount: int) -> void:
	if _is_dead:
		return
	if amount <= 0:
		return
	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		_is_dead = true
		died.emit()


func apply_heal(amount: int) -> void:
	if _is_dead:
		return
	if amount <= 0:
		return
	current_health = mini(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


## Resets to full health and clears the dead flag. Used by Level on
## respawn.
func revive() -> void:
	_is_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)


func is_dead() -> bool:
	return _is_dead
